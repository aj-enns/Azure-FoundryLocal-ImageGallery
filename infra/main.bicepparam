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

// ── Tags ──────────────────────────────────────────────────────────────────────
param tags = {
  project: 'Azure-FoundryLocal-ImageGallery'
  managedBy: 'AzureImageBuilder'
}
