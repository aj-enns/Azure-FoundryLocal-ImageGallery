// ─────────────────────────────────────────────────────────────────────────────
// appregistration.bicep
// Creates a Microsoft Entra ID App Registration with a Service Principal and
// a GitHub Actions OIDC federated identity credential.
//
// Requires the Microsoft Graph Bicep extension (dynamic types) and the
// deploying identity must have Application.ReadWrite.OwnedBy (or
// Application.ReadWrite.All) permissions in Microsoft Graph.
//
// See bicepconfig.json in the infra/ folder for the extension source.
// ─────────────────────────────────────────────────────────────────────────────

extension microsoftGraphV1_0

@description('Display name for the App Registration.')
param appDisplayName string

@description('GitHub organisation or username that owns the repository.')
param gitHubOrganisation string

@description('GitHub repository name (without the org prefix).')
param gitHubRepository string

@description('GitHub branch name to federate (e.g. "main").')
param gitHubBranch string = 'main'

// ── App Registration ─────────────────────────────────────────────────────────

resource app 'Microsoft.Graph/applications@v1.0' = {
  displayName: appDisplayName
  uniqueName: appDisplayName
}

// ── Service Principal ────────────────────────────────────────────────────────
// Required so the app can be assigned Azure RBAC roles.

resource sp 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: app.appId
}

// ── Federated Identity Credential (GitHub Actions OIDC) ──────────────────────

resource federatedCredential 'Microsoft.Graph/applications/federatedIdentityCredentials@v1.0' = {
  name: '${app.uniqueName}/github-actions-${gitHubBranch}'
  audiences: [
    'api://AzureADTokenExchange'
  ]
  issuer: 'https://token.actions.githubusercontent.com'
  subject: 'repo:${gitHubOrganisation}/${gitHubRepository}:ref:refs/heads/${gitHubBranch}'
  description: 'GitHub Actions OIDC for ${gitHubOrganisation}/${gitHubRepository} (${gitHubBranch})'
}

// ── Outputs ───────────────────────────────────────────────────────────────────

@description('Application (client) ID – use as AZURE_CLIENT_ID in GitHub Secrets.')
output appClientId string = app.appId

@description('Object ID of the App Registration.')
output appObjectId string = app.id

@description('Object ID of the Service Principal (needed for role assignments).')
output servicePrincipalObjectId string = sp.id
