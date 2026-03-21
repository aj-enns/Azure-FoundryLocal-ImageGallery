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
    // Allow up to 3 hours for the build (Windows Update can be slow).
    buildTimeoutInMinutes: 180

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

      // 4. Restart after Windows Update.
      {
        type: 'WindowsRestart'
        restartCheckCommand: 'echo Restart after Windows Update complete.'
        restartTimeout: '15m'
      }

      // 5. Run a final sysprep-prepare cleanup so the image is generalised
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
