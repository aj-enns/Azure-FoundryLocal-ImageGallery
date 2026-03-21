# Azure-FoundryLocal-ImageGallery

Automated pipeline that builds a **Windows 11 Enterprise 24H2** VM image with **[Azure Foundry Local](https://learn.microsoft.com/en-us/azure/foundry-local/get-started)** pre-installed, then publishes it to an **Azure Compute Gallery** with community sharing so anyone in Azure can consume it.

---

## Quick Start

> For detailed, step-by-step instructions see **[docs/INSTALL.md](docs/INSTALL.md)**.

```bash
# 1. Fork/clone the repo, then copy the example param file and fill in your values
cp infra/setup.bicepparam.example infra/setup.bicepparam
# Edit infra/setup.bicepparam — set your GitHub org/username and preferred region

# 2. Bootstrap the App Registration + OIDC + Contributor role (one-time)
az login
az deployment sub create \
  --location eastus \
  --template-file infra/setup.bicep \
  --parameters infra/setup.bicepparam \
  --query '{AZURE_CLIENT_ID: properties.outputs.azurE_CLIENT_ID.value, AZURE_TENANT_ID: properties.outputs.azurE_TENANT_ID.value, AZURE_SUBSCRIPTION_ID: properties.outputs.azurE_SUBSCRIPTION_ID.value}' \
  --output table

# 3. Copy the three output values from the table into GitHub Secrets

# 4. Update infra/main.bicepparam with your gallery metadata, then:
#    Actions → Build Windows 11 + Foundry Local Image → Run workflow
```

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
│   ├── copilot-instructions.md          # Copilot coding conventions
│   └── workflows/
│       └── build-image.yml              # GitHub Actions workflow
├── docs/
│   └── INSTALL.md                       # Step-by-step installation guide
├── infra/
│   ├── setup.bicep                      # One-time bootstrap (subscription-scoped)
│   ├── setup.bicepparam.example         # Bootstrap parameter template (copy to setup.bicepparam)
│   ├── main.bicep                       # Core infrastructure (resource-group-scoped)
│   ├── main.bicepparam                  # Infrastructure parameter defaults
│   └── modules/
│       ├── appregistration.bicep        # App Registration + OIDC federation
│       ├── identity.bicep               # User-assigned managed identity + RBAC
│       ├── gallery.bicep                # Azure Compute Gallery + image definition
│       └── imagebuilder.bicep           # Azure Image Builder template
└── scripts/
    └── windows/
        └── install-foundry-local.ps1    # Standalone Foundry Local install script
```

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **Azure subscription** | With **Owner** rights (needed to create role assignments). |
| **Azure AD (Entra ID)** | Permission to create App Registrations. |
| **GitHub account** | To host the repository and run GitHub Actions. |
| **Azure CLI** | [Install Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) — used for the one-time bootstrap deployment. |

The workflow automatically registers all required resource providers (`Microsoft.VirtualMachineImages`, `Microsoft.Compute`, `Microsoft.KeyVault`, `Microsoft.Storage`, `Microsoft.Network`, `Microsoft.ManagedIdentity`).

---

## Setup Overview

Setup is split into two phases:

### Phase 1 — Bootstrap (run once from your machine)

Deploy `infra/setup.bicep` to create:

- An **App Registration** in Entra ID
- A **Federated Identity Credential** for GitHub Actions OIDC (no stored secrets)
- A **Service Principal** with **Contributor** on the subscription

Then copy the three deployment outputs into **GitHub Secrets** (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`).

### Phase 2 — Build the image (GitHub Actions)

Trigger the **Build Windows 11 + Foundry Local Image** workflow. It deploys the Bicep infrastructure, runs Azure Image Builder, and publishes the finished image to the Compute Gallery.

> See **[docs/INSTALL.md](docs/INSTALL.md)** for the full walkthrough, including a manual portal-based alternative.

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
  --gallery-name    flocalgallery \
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

### Verifying Foundry Local

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
