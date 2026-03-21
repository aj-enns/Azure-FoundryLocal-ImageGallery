// ─────────────────────────────────────────────────────────────────────────────
// main.bicepparam
// Default parameter values for the Azure-FoundryLocal-ImageGallery deployment.
// Override any value here or pass --parameters on the az CLI / in the workflow.
// ─────────────────────────────────────────────────────────────────────────────

using './main.bicep'

// ── Resource naming ───────────────────────────────────────────────────────────
param namePrefix = 'flocal'

// ── Community gallery metadata ────────────────────────────────────────────────
// Update these values before your first deployment.

param galleryPublicNamePrefix = 'FoundryLocal'

param publisherUri = 'https://github.com/aj-enns/Azure-FoundryLocal-ImageGallery'

param publisherContact = 'gallery-owner@example.com'

param eula = 'By using images from this gallery you accept that they are provided as-is without warranty. Azure Foundry Local is subject to the Microsoft Software License Terms.'

// ── Optional: replicate to additional regions ─────────────────────────────────
// Example: ['westus2', 'westeurope']
param additionalReplicationRegions = []

// ── Image Builder staging ─────────────────────────────────────────────────────
// Pre-created resource group for Image Builder staging resources. Required when
// Azure Policy blocks shared key access on storage accounts — exempt this RG.
param stagingResourceGroupId = '/subscriptions/72b2c395-4f94-4e3f-997b-43b4871afee0/resourceGroups/rg-foundry-image-staging'

// ── Tags ──────────────────────────────────────────────────────────────────────
param tags = {
  project: 'Azure-FoundryLocal-ImageGallery'
  managedBy: 'AzureImageBuilder'
}
