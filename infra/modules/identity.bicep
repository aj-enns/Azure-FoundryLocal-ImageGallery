// ─────────────────────────────────────────────────────────────────────────────
// identity.bicep
// Creates a User-Assigned Managed Identity and grants it the Contributor role
// at the resource group scope – required by Azure Image Builder to create and
// manage staging resources and to write image versions to the gallery.
// ─────────────────────────────────────────────────────────────────────────────

@description('Azure region for the managed identity.')
param location string

@description('Name of the user-assigned managed identity.')
param identityName string

@description('Resource tags applied to all resources in this module.')
param tags object = {}

// ── Managed Identity ─────────────────────────────────────────────────────────

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

// ── Contributor role at resource-group scope ──────────────────────────────────
// Azure Image Builder requires at minimum: Contributor on the resource group so
// that it can create the staging resource group, VMs, NICs, and disk snapshots,
// and write image versions to the Compute Gallery.

resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, identity.id, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor
    )
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Resource ID of the user-assigned managed identity.')
output identityId string = identity.id

@description('Principal (object) ID of the managed identity.')
output identityPrincipalId string = identity.properties.principalId

@description('Client ID of the managed identity.')
output identityClientId string = identity.properties.clientId
