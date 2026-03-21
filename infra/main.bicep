// ─────────────────────────────────────────────────────────────────────────────
// main.bicep
// Root Bicep template for the Azure-FoundryLocal-ImageGallery solution.
// Orchestrates:
//   • User-assigned managed identity (for Azure Image Builder)
//   • Azure Compute Gallery with community sharing + image definition
//   • Azure Image Builder template (Windows 11 Enterprise 24H2 + Foundry Local)
// ─────────────────────────────────────────────────────────────────────────────

@description('Azure region for all resources. Defaults to the resource group\'s location.')
param location string = resourceGroup().location

// ── Naming ────────────────────────────────────────────────────────────────────

@description('Short prefix used to name all resources (lowercase, no spaces).')
@minLength(2)
@maxLength(8)
param namePrefix string = 'flocal'

@description('Name of the Azure Compute Gallery.')
param galleryName string = '${namePrefix}gallery'

@description('Name of the image definition inside the gallery.')
param imageDefinitionName string = 'Win11-FoundryLocal'

@description('Name of the user-assigned managed identity used by Image Builder.')
param identityName string = '${namePrefix}-aib-identity'

@description('Name of the Azure Image Builder image template.')
param imageTemplateName string = '${namePrefix}-win11-foundry-template'

// ── Community gallery metadata ────────────────────────────────────────────────

@description('Short public name prefix for the community gallery (max 30 chars, letters/numbers only).')
@minLength(1)
@maxLength(30)
param galleryPublicNamePrefix string

@description('Public HTTPS URI for the gallery publisher.')
param publisherUri string

@description('Contact e-mail address shown to community gallery consumers.')
param publisherContact string

@description('End-User Licence Agreement text for the community gallery images.')
param eula string

// ── Replication ───────────────────────────────────────────────────────────────

@description('Additional Azure regions to replicate the image version into (primary region is always included).')
param additionalReplicationRegions array = []

// ── Tags ──────────────────────────────────────────────────────────────────────

@description('Tags applied to every resource deployed by this template.')
param tags object = {
  project: 'Azure-FoundryLocal-ImageGallery'
  managedBy: 'AzureImageBuilder'
}

// ─────────────────────────────────────────────────────────────────────────────
// Modules
// ─────────────────────────────────────────────────────────────────────────────

module identity 'modules/identity.bicep' = {
  name: 'deploy-identity'
  params: {
    location: location
    identityName: identityName
    tags: tags
  }
}

module gallery 'modules/gallery.bicep' = {
  name: 'deploy-gallery'
  params: {
    location: location
    galleryName: galleryName
    galleryPublicNamePrefix: galleryPublicNamePrefix
    publisherUri: publisherUri
    publisherContact: publisherContact
    eula: eula
    imageDefinitionName: imageDefinitionName
    tags: tags
  }
}

module imageBuilder 'modules/imagebuilder.bicep' = {
  name: 'deploy-image-builder'
  params: {
    location: location
    imageTemplateName: imageTemplateName
    managedIdentityId: identity.outputs.identityId
    galleryImageDefinitionId: gallery.outputs.imageDefinitionId
    replicationRegions: union([location], additionalReplicationRegions)
    tags: tags
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Outputs
// ─────────────────────────────────────────────────────────────────────────────

@description('Name of the Azure Compute Gallery.')
output galleryName string = gallery.outputs.galleryName

@description('Resource ID of the Azure Compute Gallery.')
output galleryId string = gallery.outputs.galleryId

@description('Resource ID of the Windows 11 + Foundry Local image definition.')
output imageDefinitionId string = gallery.outputs.imageDefinitionId

@description('Name of the image definition.')
output imageDefinitionName string = gallery.outputs.imageDefinitionName

@description('Name of the Azure Image Builder template (used to trigger a build).')
output imageTemplateName string = imageBuilder.outputs.imageTemplateName
