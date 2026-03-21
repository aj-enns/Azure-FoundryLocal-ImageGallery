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
    // Allow up to 4.5 hours for the build. Windows Update on a fresh
    // Windows 11 image can easily take 2+ hours on its own, plus time for
    // Foundry Local install, restarts, cleanup, and VHD distribution.
    buildTimeoutInMinutes: 270

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

      // 3. Apply all available non-preview Windows Updates.
      {
        type: 'WindowsUpdate'
        searchCriteria: 'IsInstalled=0'
        filters: [
          'exclude:$_.Title -like \'\'*Preview*\'\''
          'include:$true'
        ]
        updateLimit: 40
      }

      // 4. Restart after Windows Update (first pass).
      {
        type: 'WindowsRestart'
        restartCheckCommand: 'echo Restart after Windows Update pass 1 complete.'
        restartTimeout: '15m'
      }

      // 5. Apply a second round of Windows Updates.
      //    Some updates only appear after a reboot installs earlier ones.
      {
        type: 'WindowsUpdate'
        searchCriteria: 'IsInstalled=0'
        filters: [
          'exclude:$_.Title -like \'\'*Preview*\'\''
          'include:$true'
        ]
        updateLimit: 40
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
