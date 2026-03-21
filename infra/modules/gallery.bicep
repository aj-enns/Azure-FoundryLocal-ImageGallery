// ─────────────────────────────────────────────────────────────────────────────
// gallery.bicep
// Creates an Azure Compute Gallery with community sharing enabled so that the
// Windows 11 + Foundry Local image can be consumed by anyone in Azure, along
// with the gallery image definition that describes the image.
// ─────────────────────────────────────────────────────────────────────────────

@description('Azure region for the gallery.')
param location string

@description('Name of the Azure Compute Gallery. Must be globally unique.')
param galleryName string

@description('Short prefix used to generate the gallery\'s public community name (5–16 chars, alphanumeric only).')
@minLength(5)
@maxLength(16)
param galleryPublicNamePrefix string

@description('HTTPS URI for the publisher\'s public website.')
param publisherUri string

@description('Contact e-mail address for the gallery publisher.')
param publisherContact string

@description('End-User Licence Agreement text for the community gallery.')
param eula string

@description('Name of the Windows 11 + Foundry Local image definition.')
param imageDefinitionName string = 'Win11-FoundryLocal'

@description('Resource tags applied to all resources in this module.')
param tags object = {}

// ── Azure Compute Gallery (Community sharing) ─────────────────────────────────

resource gallery 'Microsoft.Compute/galleries@2023-07-03' = {
  name: galleryName
  location: location
  tags: tags
  properties: {
    description: 'Public Azure Compute Gallery – Windows 11 with Azure Foundry Local pre-installed.'
    sharingProfile: {
      permissions: 'Community'
      communityGalleryInfo: {
        eula: eula
        publicNamePrefix: galleryPublicNamePrefix
        publisherContact: publisherContact
        publisherUri: publisherUri
      }
    }
    softDeletePolicy: {
      isSoftDeleteEnabled: true
    }
  }
}

// ── Image Definition ──────────────────────────────────────────────────────────
// Describes Windows 11 Enterprise 24H2 (Gen 2, Trusted Launch compatible).

resource imageDefinition 'Microsoft.Compute/galleries/images@2023-07-03' = {
  parent: gallery
  name: imageDefinitionName
  location: location
  tags: tags
  properties: {
    description: 'Windows 11 Enterprise 24H2 with Azure Foundry Local pre-installed.'
    osType: 'Windows'
    osState: 'Generalized'
    hyperVGeneration: 'V2'
    architecture: 'x64'
    identifier: {
      publisher: 'FoundryLocalPublisher'
      offer: 'Windows11'
      sku: 'Win11-24H2-FoundryLocal'
    }
    recommended: {
      vCPUs: {
        min: 4
        max: 32
      }
      memory: {
        min: 16
        max: 128
      }
    }
    features: [
      {
        // Enables Trusted Launch (vTPM + Secure Boot) – required for Windows 11
        name: 'SecurityType'
        value: 'TrustedLaunchSupported'
      }
    ]
    disallowed: {
      diskTypes: []
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the Azure Compute Gallery.')
output galleryId string = gallery.id

@description('Name of the Azure Compute Gallery.')
output galleryName string = gallery.name

@description('Resource ID of the image definition.')
output imageDefinitionId string = imageDefinition.id

@description('Name of the image definition.')
output imageDefinitionName string = imageDefinition.name
