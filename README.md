# Azure-FoundryLocal-ImageGallery

Automated pipeline that builds a **Windows 11 Enterprise 24H2** VM image with **[Azure Foundry Local](https://learn.microsoft.com/en-us/azure/foundry-local/get-started)** pre-installed, then publishes it to an **Azure Compute Gallery** with community sharing so anyone in Azure can consume it.

---

## What is built

| Component | Details |
|-----------|---------|
| Base image | Windows 11 Enterprise 24H2 (`win11-24h2-ent`) – latest version |
| Pre-installed software | Azure Foundry Local (`Microsoft.FoundryLocal` via winget) |
| Windows Updates | All non-preview updates applied at build time |
| Distribution | Azure Compute Gallery – Community sharing (publicly discoverable) |
| Automation | GitHub Actions – manual trigger + monthly scheduled rebuild |

---

## Repository structure

```
.
├── .github/
│   └── workflows/
│       └── build-image.yml          # GitHub Actions workflow
├── infra/
│   ├── main.bicep                   # Root Bicep template
│   ├── main.bicepparam              # Default parameter values
│   └── modules/
│       ├── identity.bicep           # User-assigned managed identity + RBAC
│       ├── gallery.bicep            # Azure Compute Gallery + image definition
│       └── imagebuilder.bicep       # Azure Image Builder template
└── scripts/
    └── windows/
        └── install-foundry-local.ps1  # Standalone install script
```

---

## Prerequisites

### Azure

1. An Azure subscription with **Owner** or **Contributor** rights.
2. The following resource providers registered (the workflow registers them automatically):
   - `Microsoft.VirtualMachineImages`
   - `Microsoft.Compute`
   - `Microsoft.KeyVault`
   - `Microsoft.Storage`
   - `Microsoft.Network`
   - `Microsoft.ManagedIdentity`

### GitHub – OIDC federated credentials

The workflow authenticates to Azure using **OpenID Connect** (no long-lived secrets stored in GitHub).

1. [Create an App Registration](https://learn.microsoft.com/en-us/azure/active-directory/develop/quickstart-register-app) in Azure AD.
2. Add a **Federated credential** for GitHub Actions:
   - Organisation: `aj-enns`
   - Repository: `Azure-FoundryLocal-ImageGallery`
   - Entity: `Branch` → `copilot/create-windows-11-image-with-azure-foundry` (or `main` after merge)
3. Grant the App Registration **Contributor** on the target subscription (the Bicep template further scopes permissions).
4. Add the following **GitHub Secrets** (`Settings → Secrets and variables → Actions`):

   | Secret | Value |
   |--------|-------|
   | `AZURE_CLIENT_ID` | App Registration client ID |
   | `AZURE_TENANT_ID` | Azure AD tenant ID |
   | `AZURE_SUBSCRIPTION_ID` | Target subscription ID |

5. Optionally, add **GitHub Variables** to override defaults:

   | Variable | Default |
   |----------|---------|
   | `AZURE_RESOURCE_GROUP` | `rg-foundry-image-gallery` |
   | `AZURE_LOCATION` | `eastus` |

---

## First-time setup

### 1. Update community gallery metadata

Edit `infra/main.bicepparam` and set your publisher details:

```bicep
param galleryPublicNamePrefix = 'FoundryLocalGallery'   // globally unique prefix
param publisherUri     = 'https://your-website.example.com'
param publisherContact = 'your-email@example.com'
param eula             = 'Your EULA text here...'
```

### 2. Run the workflow

Navigate to **Actions → Build Windows 11 + Foundry Local Image → Run workflow**.

The workflow will:
1. Register required resource providers.
2. Create the resource group (if it does not exist).
3. Deploy the Bicep infrastructure (identity, gallery, image definition, image template).
4. Trigger Azure Image Builder (build takes ~2–3 hours including Windows Update).
5. Publish the finished image version to the gallery.
6. Print a summary with the new image version details.

---

## Using the published image

Once the build succeeds, consumers can create VMs directly from the community gallery.

### Azure Portal

1. Search for **Community images** in the portal.
2. Search for the `galleryPublicNamePrefix` you configured (e.g. `FoundryLocalGallery`).
3. Select the **Win11-FoundryLocal** image and create a VM.

### Azure CLI

```bash
# List available image versions
az sig image-version list \
  --resource-group  rg-foundry-image-gallery \
  --gallery-name    flocalGallery \
  --gallery-image-definition Win11-FoundryLocal \
  --output table

# Create a VM from the latest version
az vm create \
  --resource-group  my-rg \
  --name            my-foundry-vm \
  --image           "/communityGalleries/<publicNamePrefix>/images/Win11-FoundryLocal/versions/latest" \
  --size            Standard_D8ads_v5 \
  --admin-username  azureuser \
  --generate-ssh-keys
```

### Verifying Foundry Local after VM creation

```powershell
foundry --version
foundry model list
```

---

## Rebuilding the image

The workflow runs automatically on the **1st of every month** at 03:00 UTC to pick up the latest Windows Updates. To trigger a manual rebuild, use the **Run workflow** button in GitHub Actions.

---

## Contributing

Pull requests are welcome. Please open an issue first to discuss significant changes.
