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

// ─────────────────────────────────────────────────────────────────────────────
// Image Builder template
// API 2024-02-01 supports Trusted Launch VMs as the build VM which is required
// for Windows 11.
//
// Windows Update strategy
// ───────────────────────
// • Two passes of WindowsUpdate are run with a restart between each.
//   Two passes are enough: the first installs all currently-available patches;
//   the second catches any updates that only become visible after the first
//   batch is rebooted into.
// • The filter uses AutoSelectOnWebSites (= true for security, critical, and
//   important updates) rather than include:$true.  Omitting this filter
//   caused large optional driver/feature packages (often 1–3 GB each) to be
//   queued, dramatically inflating build time and causing timeouts.
// • updateLimit is intentionally omitted so the default (1,000) applies.
//   Setting it to a small value (e.g. 40) means only 40 updates are attempted
//   per pass; on a fresh image after Patch Tuesday there can be 100+ pending
//   updates, so a low cap leaves the image partially patched.
// ─────────────────────────────────────────────────────────────────────────────

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
    buildTimeoutInMinutes: 300

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

    // ── Customization steps ───────────────────────────────────────────────────
    customize: [

      // 1. Install Azure Foundry Local via winget.
      //    Each array element is a separate PowerShell statement.
      {
        type: 'PowerShell'
        name: 'InstallFoundryLocal'
        runElevated: true
        inline: [
          '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12'
          '$ErrorActionPreference = "Stop"'
          'Write-Host "Refreshing winget sources..."'
          'winget source update --disable-interactivity'
          'Write-Host "Installing Azure Foundry Local..."'
          'winget install Microsoft.FoundryLocal --accept-package-agreements --accept-source-agreements --silent --disable-interactivity'
          'if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { throw "Foundry Local install failed – winget exit code: $LASTEXITCODE" }'
          'Write-Host "Azure Foundry Local installation complete."'
        ]
      }

      // 2. Restart to finalise the Foundry Local installation.
      {
        type: 'WindowsRestart'
        restartCheckCommand: 'echo Restart after Foundry Local install complete.'
        restartTimeout: '10m'
      }

      // 3. Apply all available security / critical / important Windows Updates.
      //    AutoSelectOnWebSites = true means "recommended for automatic install",
      //    which covers security, critical, and important updates but skips large
      //    optional driver and feature packages that inflate build time.
      //    updateLimit is omitted to use the default (1,000) — a low cap causes
      //    the image to be left partially patched when there are many updates.
      {
        type: 'WindowsUpdate'
        searchCriteria: 'IsInstalled=0'
        filters: [
          'exclude:$_.Title -like \'\'*Preview*\'\''
          'include:$_.AutoSelectOnWebSites -eq $true'
        ]
      }

      // 4. Restart after Windows Update (first pass).
      {
        type: 'WindowsRestart'
        restartCheckCommand: 'echo Restart after Windows Update pass 1 complete.'
        restartTimeout: '15m'
      }

      // 5. Apply a second round of Windows Updates (same recommended-only filter).
      //    Some updates only become available after a reboot installs earlier ones.
      {
        type: 'WindowsUpdate'
        searchCriteria: 'IsInstalled=0'
        filters: [
          'exclude:$_.Title -like \'\'*Preview*\'\''
          'include:$_.AutoSelectOnWebSites -eq $true'
        ]
      }

      // 6. Restart after Windows Update (second pass).
      {
        type: 'WindowsRestart'
        restartCheckCommand: 'echo Restart after Windows Update pass 2 complete.'
        restartTimeout: '15m'
      }

      // 7. Run a final sysprep-prepare cleanup so the image is generalised
      //    cleanly (Image Builder calls sysprep automatically, but this
      //    ensures temporary files are removed first).
      {
        type: 'PowerShell'
        name: 'CleanupTempFiles'
        runElevated: true
        inline: [
          'Write-Host "Cleaning up temporary files..."'
          'Remove-Item -Path "$env:TEMP\\*" -Recurse -Force -ErrorAction SilentlyContinue'
          'Remove-Item -Path "C:\\Windows\\Temp\\*" -Recurse -Force -ErrorAction SilentlyContinue'
          'Write-Host "Cleanup complete."'
        ]
      }
    ]

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
