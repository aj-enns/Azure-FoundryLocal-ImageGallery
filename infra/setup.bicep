// ─────────────────────────────────────────────────────────────────────────────
// setup.bicep
// One-time bootstrap template (subscription-scoped) that creates the Entra ID
// App Registration with GitHub Actions OIDC federation and assigns it the
// Contributor role on the subscription.
//
// Run this ONCE from your local machine before using the GitHub Actions workflow:
//
//   az deployment sub create \
//     --location <region> \
//     --template-file infra/setup.bicep \
//     --parameters infra/setup.bicepparam \
//     --query '{AZURE_CLIENT_ID: properties.outputs.azurE_CLIENT_ID.value, AZURE_TENANT_ID: properties.outputs.azurE_TENANT_ID.value, AZURE_SUBSCRIPTION_ID: properties.outputs.azurE_SUBSCRIPTION_ID.value}' \
//     --output table
//
// The --location flag tells Azure where to store the *deployment metadata* —
// it does not affect where resources are created. Use any region you like
// (e.g. canadacentral, eastus). Resources use the 'location' parameter below.
//
// Prerequisites:
//   • Azure CLI logged in as a user with Owner on the subscription
//   • Microsoft Graph permissions: Application.ReadWrite.OwnedBy (or .All)
// ─────────────────────────────────────────────────────────────────────────────

// Tells Bicep this template runs at the subscription level.
// The deploying user's current subscription is used automatically
// (set via 'az account set --subscription <name-or-id>' before deploying).
targetScope = 'subscription'

// ── App Registration parameters ───────────────────────────────────────────────

@description('Display name for the App Registration in Entra ID.')
param appDisplayName string = 'github-foundry-image-builder'

@description('GitHub organisation or username that owns the repository.')
param gitHubOrganisation string

@description('GitHub repository name (without the org prefix).')
param gitHubRepository string = 'Azure-FoundryLocal-ImageGallery'

@description('GitHub branch name to federate (e.g. "main").')
param gitHubBranch string = 'main'

// ── Resource group parameters ─────────────────────────────────────────────────

@description('Name of the resource group for the setup deployment helper. The main image-builder resources are deployed separately.')
param setupResourceGroupName string = 'rg-foundry-image-setup'

@description('Azure region for the setup resource group.')
param location string

// ── Tags ──────────────────────────────────────────────────────────────────────

@description('Tags applied to resources created by this template.')
param tags object = {
  project: 'Azure-FoundryLocal-ImageGallery'
  managedBy: 'BootstrapSetup'
}

// ─────────────────────────────────────────────────────────────────────────────
// Resource Group (needed to host the Microsoft Graph module deployment)
// ─────────────────────────────────────────────────────────────────────────────

resource setupRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: setupResourceGroupName
  location: location
  tags: tags
}

// ─────────────────────────────────────────────────────────────────────────────
// App Registration + Federated Credential (resource-group-scoped module)
// ─────────────────────────────────────────────────────────────────────────────

module appRegistration 'modules/appregistration.bicep' = {
  name: 'deploy-app-registration'
  scope: setupRg
  params: {
    appDisplayName: appDisplayName
    gitHubOrganisation: gitHubOrganisation
    gitHubRepository: gitHubRepository
    gitHubBranch: gitHubBranch
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contributor role assignment at subscription scope
// ─────────────────────────────────────────────────────────────────────────────

// Built-in Contributor role definition ID
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // guid() inputs must be known at deployment start — use the app display name
  // (a parameter) instead of the runtime service principal object ID.
  name: guid(subscription().id, appDisplayName, contributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      contributorRoleId
    )
    principalId: appRegistration.outputs.servicePrincipalObjectId
    principalType: 'ServicePrincipal'
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Outputs – copy these values into GitHub Secrets
// ─────────────────────────────────────────────────────────────────────────────

@description('AZURE_CLIENT_ID – add this to GitHub Secrets.')
output AZURE_CLIENT_ID string = appRegistration.outputs.appClientId

@description('AZURE_TENANT_ID – add this to GitHub Secrets.')
output AZURE_TENANT_ID string = tenant().tenantId

@description('AZURE_SUBSCRIPTION_ID – add this to GitHub Secrets.')
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId
