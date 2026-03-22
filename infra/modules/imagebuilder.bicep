// ─────────────────────────────────────────────────────────────────────────────
// imagebuilder.bicep
// Azure Image Builder template that:
//   1. Sources the latest Windows 11 Enterprise 24H2 platform image.
//   2. Installs Azure Foundry Local via winget.
//   3. Applies all pending (non-preview) Windows Updates.
//   4. Distributes the finished image to the Azure Compute Gallery.
// ─────────────────────────────────────────────────────────────────────────────

@description('Azure region for the image template.')
param location string

@description('Name of the Azure Image Builder image template resource.')
param imageTemplateName string

@description('Resource ID of the user-assigned managed identity used by Image Builder.')
param managedIdentityId string

@description('Resource ID of the target Azure Compute Gallery image definition.')
param galleryImageDefinitionId string

@description('Azure region(s) to replicate the finished image version into.')
param replicationRegions array = [location]

@description('Resource tags applied to the image template.')
param tags object = {}

@description('Resource ID of a pre-created resource group for Image Builder staging resources. If empty, Image Builder creates a temporary one. Specify this when Azure Policy blocks shared key access on storage accounts — you can exempt this RG from that policy.')
param stagingResourceGroupId string = ''

@description('Whether to apply Windows Updates during the build. Set to false to speed up test builds.')
param applyWindowsUpdate bool = true

// ─────────────────────────────────────────────────────────────────────────────
// Image Builder template
// API 2024-02-01 supports Trusted Launch VMs as the build VM which is required
// for Windows 11.
//
// Windows Update strategy
// ───────────────────────
// • A single pass of WindowsUpdate is run followed by a restart.
//   Monthly rebuilds will catch any remaining updates from the previous cycle.
// • The filter uses AutoSelectOnWebSites (= true for security, critical, and
//   important updates) rather than include:$true.  Omitting this filter
//   caused large optional driver/feature packages (often 1–3 GB each) to be
//   queued, dramatically inflating build time and causing timeouts.
// • updateLimit is intentionally omitted so the default (1,000) applies.
//   Setting it to a small value (e.g. 40) means only 40 updates are attempted
//   per pass; on a fresh image after Patch Tuesday there can be 100+ pending
//   updates, so a low cap leaves the image partially patched.
// ─────────────────────────────────────────────────────────────────────────────

// ── Customization step arrays (combined conditionally below) ─────────────────
// Each major step is bookended with timestamped Write-Host messages so the
// customization.log shows exactly which step was running when a timeout or
// failure occurred.

var foundryInstallSteps = [
  {
    type: 'PowerShell'
    name: 'InstallFoundryLocal'
    runElevated: true
    inline: [
      '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12'
      '$ErrorActionPreference = "Stop"'
      'Write-Host "[$(Get-Date -f o)] === STEP: Install Foundry Local — START ==="'
      'Write-Host "Refreshing winget sources..."'
      'winget source update --disable-interactivity'
      'Write-Host "Installing Azure Foundry Local..."'
      'winget install Microsoft.FoundryLocal --accept-package-agreements --accept-source-agreements --silent --disable-interactivity'
      'if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { throw "Foundry Local install failed – winget exit code: $LASTEXITCODE" }'
      'Write-Host "[$(Get-Date -f o)] === STEP: Install Foundry Local — COMPLETE ==="'
    ]
  }
  {
    type: 'WindowsRestart'
    restartCheckCommand: 'Write-Host "[$(Get-Date -f o)] === STEP: Reboot after Foundry Local — COMPLETE ==="'
    restartTimeout: '10m'
  }
]

var windowsUpdateSteps = [
  {
    type: 'PowerShell'
    name: 'PreWindowsUpdateLog'
    runElevated: true
    inline: [
      'Write-Host "[$(Get-Date -f o)] === STEP: Windows Update — START ==="'
      'Write-Host "Searching for available updates (AutoSelectOnWebSites only, excluding Preview)..."'
    ]
  }
  {
    type: 'WindowsUpdate'
    searchCriteria: 'IsInstalled=0'
    filters: [
      'exclude:$_.Title -like \'\'*Preview*\'\''
      'include:$_.AutoSelectOnWebSites -eq $true'
    ]
  }
  {
    type: 'PowerShell'
    name: 'PostWindowsUpdateLog'
    runElevated: true
    inline: [
      'Write-Host "[$(Get-Date -f o)] === STEP: Windows Update — COMPLETE, rebooting ==="'
    ]
  }
  {
    type: 'WindowsRestart'
    restartCheckCommand: 'Write-Host "[$(Get-Date -f o)] === STEP: Reboot after Windows Update — COMPLETE ==="'
    restartTimeout: '15m'
  }
  {
    type: 'PowerShell'
    name: 'LogWindowsUpdateStatus'
    runElevated: true
    inline: [
      'Write-Host "[$(Get-Date -f o)] === STEP: Log Windows Update events — START ==="'
      'wevtutil qe System /q:"*[System[Provider[@Name=\'Microsoft-Windows-WindowsUpdateClient\']]]" /f:text /c:20'
      'Write-Host "[$(Get-Date -f o)] === STEP: Log Windows Update events — COMPLETE ==="'
    ]
  }
]

var cleanupSteps = [
  {
    type: 'PowerShell'
    name: 'CleanupTempFiles'
    runElevated: true
    inline: [
      'Write-Host "[$(Get-Date -f o)] === STEP: Cleanup temp files — START ==="'
      'Remove-Item -Path "$env:TEMP\\*" -Recurse -Force -ErrorAction SilentlyContinue'
      'Remove-Item -Path "C:\\Windows\\Temp\\*" -Recurse -Force -ErrorAction SilentlyContinue'
      'Write-Host "[$(Get-Date -f o)] === STEP: Cleanup temp files — COMPLETE ==="'
    ]
  }
]

var customizeSteps = applyWindowsUpdate
  ? concat(foundryInstallSteps, windowsUpdateSteps, cleanupSteps)
  : concat(foundryInstallSteps, cleanupSteps)

resource imageTemplate 'Microsoft.VirtualMachineImages/imageTemplates@2024-02-01' = {
  name: imageTemplateName
  location: location
  tags: tags

  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }

  properties: {
    // Allow up to 5 hours for the build.  A fresh Windows 11 24H2 marketplace
    // image can have 100+ security and important patches pending (especially
    // in the week after Patch Tuesday).  Add time for Foundry Local install,
    // two reboots, cleanup, and gallery distribution.
    buildTimeoutInMinutes: 120

    // Use a dedicated staging resource group so it can be exempted from
    // Azure Policies that block storage-account shared key access.
    stagingResourceGroup: !empty(stagingResourceGroupId) ? stagingResourceGroupId : null

    vmProfile: {
      // D8ads_v5: 8 vCPU / 32 GiB – provides enough headroom for Foundry Local
      // installation and Windows Update downloads.
      vmSize: 'Standard_D8ads_v5'
      osDiskSizeGB: 128
    }

    // ── Source image ──────────────────────────────────────────────────────────
    source: {
      type: 'PlatformImage'
      publisher: 'MicrosoftWindowsDesktop'
      offer: 'windows-11'
      sku: 'win11-24h2-ent'   // Windows 11 Enterprise 24H2 – latest channel
      version: 'latest'
    }

    // ── Customization steps (built from variables above) ─────────────────────
    customize: customizeSteps

    // ── Distribution target ───────────────────────────────────────────────────
    distribute: [
      {
        type: 'SharedImage'
        // galleryImageId points to the image *definition* (no version suffix).
        // Image Builder automatically assigns the next version number.
        galleryImageId: galleryImageDefinitionId
        runOutputName: 'Win11FoundryLocal'
        replicationRegions: replicationRegions
        storageAccountType: 'Standard_LRS'
        artifactTags: {
          sourceImage: 'win11-24h2-ent'
          installedSoftware: 'FoundryLocal'
          builtBy: 'AzureImageBuilder'
        }
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the image template.')
output imageTemplateId string = imageTemplate.id

@description('Name of the image template (used to trigger a build run).')
output imageTemplateName string = imageTemplate.name
