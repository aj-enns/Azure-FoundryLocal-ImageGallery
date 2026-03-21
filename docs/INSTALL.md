# Installation Guide

This guide walks you through deploying the **Azure-FoundryLocal-ImageGallery** solution into your own Azure subscription. By the end, you will have a GitHub Actions pipeline that automatically builds a **Windows 11 Enterprise 24H2** VM image with **Azure Foundry Local** pre-installed and publishes it to an **Azure Compute Gallery** with community sharing enabled.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Create the App Registration, OIDC Credential & Role Assignment](#2-create-the-app-registration-oidc-credential--role-assignment)
3. [Fork or Clone the Repository](#3-fork-or-clone-the-repository)
4. [Configure GitHub Secrets](#4-configure-github-secrets)
5. [Configure GitHub Variables (Optional)](#5-configure-github-variables-optional)
6. [Customise Gallery Metadata](#6-customise-gallery-metadata)
7. [Run the Workflow](#7-run-the-workflow)
8. [What the Workflow Does](#8-what-the-workflow-does)
9. [Create a VM from the Published Image](#9-create-a-vm-from-the-published-image)
10. [Verify Foundry Local on the VM](#10-verify-foundry-local-on-the-vm)
11. [Ongoing Maintenance](#11-ongoing-maintenance)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Prerequisites

Before you begin, make sure you have:

| Requirement | Details |
|-------------|---------|
| **Azure subscription** | With **Owner** or **Contributor + User Access Administrator** rights. Owner is preferred because the Bicep templates create role assignments. |
| **Azure AD (Entra ID) access** | Permission to create App Registrations and Federated Credentials. |
| **GitHub account** | To host the repository and run GitHub Actions. |
| **Azure CLI** *(optional)* | If you want to verify provider registration or create VMs locally. [Install Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli). |

### Required Azure Resource Providers

The workflow registers these automatically, but if you want to register them ahead of time:

```bash
az provider register --namespace Microsoft.VirtualMachineImages --wait
az provider register --namespace Microsoft.Compute --wait
az provider register --namespace Microsoft.KeyVault --wait
az provider register --namespace Microsoft.Storage --wait
az provider register --namespace Microsoft.Network --wait
az provider register --namespace Microsoft.ManagedIdentity --wait
```

> **Note:** Provider registration can take a few minutes. The `--wait` flag blocks until complete.

---

## 2. Create the App Registration, OIDC Credential & Role Assignment

The GitHub Actions workflow authenticates to Azure using **OpenID Connect (OIDC)** — no passwords or client secrets are stored in GitHub. A Bicep bootstrap template automates the entire setup.

### Option A: Automated (recommended) — Bicep bootstrap template

The `infra/setup.bicep` template creates everything in one command:

- Entra ID **App Registration**
- **Federated Identity Credential** for GitHub Actions OIDC
- **Service Principal**
- **Contributor** role assignment at the subscription scope

#### 1. Copy and update the parameters

The repo ships a template file — copy it and fill in your values:

```bash
cp infra/setup.bicepparam.example infra/setup.bicepparam
```

Then edit `infra/setup.bicepparam` with your GitHub details:

```bicep
param gitHubOrganisation = 'your-github-username'   // your GitHub org or username
param gitHubRepository   = 'Azure-FoundryLocal-ImageGallery'
param gitHubBranch       = 'main'
param location           = 'eastus'                  // any valid Azure region
```

> `setup.bicepparam` is git-ignored so your values stay local and are never committed.

#### 2. Login and deploy

```bash
# Login as a user with Owner rights on the subscription
az login

# Deploy the bootstrap template (subscription-scoped)
az deployment sub create \
  --location eastus \
  --template-file infra/setup.bicep \
  --parameters infra/setup.bicepparam \
  --query '{AZURE_CLIENT_ID: properties.outputs.azurE_CLIENT_ID.value, AZURE_TENANT_ID: properties.outputs.azurE_TENANT_ID.value, AZURE_SUBSCRIPTION_ID: properties.outputs.azurE_SUBSCRIPTION_ID.value}' \
  --output table
```

The command prints a clean table with the three values you need:

```
AZURE_CLIENT_ID                       AZURE_TENANT_ID                       AZURE_SUBSCRIPTION_ID
------------------------------------  ------------------------------------  ------------------------------------
e4e6b0d2-b207-4055-b8dc-b59a90762aa9  d967678a-e358-4218-9a75-5cc7ca5fdefb  1b2c6be0-ed07-4512-b69c-8c080c09c608
```

#### 3. Copy the outputs into GitHub Secrets

Add each value as a GitHub Secret in **Settings → Secrets and variables → Actions**:

| Output | GitHub Secret |
|--------|--------------|
| `AZURE_CLIENT_ID` | App Registration client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID |

> **Note:** The deploying user requires **Owner** on the subscription (to create role assignments) and **Application.ReadWrite.OwnedBy** (or **Application.ReadWrite.All**) Microsoft Graph API permissions.

---

### Option B: Manual — Azure Portal

If you prefer to set things up through the portal:

#### Create the App Registration

1. Sign in to the [Azure Portal](https://portal.azure.com).
2. Navigate to **Microsoft Entra ID → App registrations → New registration**.
3. Set:
   - **Name:** `github-foundry-image-builder` (or any name you prefer)
   - **Supported account types:** *Accounts in this organizational directory only*
4. Click **Register**.
5. On the app's **Overview** page, note these values — you will need them later:
   - **Application (client) ID** → this is your `AZURE_CLIENT_ID`
   - **Directory (tenant) ID** → this is your `AZURE_TENANT_ID`

#### Add Federated Credentials for GitHub Actions (OIDC)

1. In the App Registration, go to **Certificates & secrets → Federated credentials → Add credential**.
2. Select **GitHub Actions deploying Azure resources**.
3. Fill in:
   - **Organization:** Your GitHub username or org (e.g. `aj-enns`)
   - **Repository:** `Azure-FoundryLocal-ImageGallery`
   - **Entity type:** `Branch`
   - **GitHub branch name:** `main`
   - **Name:** `github-actions-main` (or any descriptive name)
4. Click **Add**.

> **Tip:** If you also run the workflow from other branches, add an additional federated credential for each branch.

#### Grant the App Registration Contributor Access

1. Navigate to **Subscriptions → (your subscription) → Access control (IAM)**.
2. Click **Add → Add role assignment**.
3. Under the **Role** tab, select **Contributor**.
4. Under the **Members** tab:
   - **Assign access to:** User, group, or service principal
   - Click **Select members** and search for the App Registration name (e.g. `github-foundry-image-builder`).
5. Click **Review + assign**.

Alternatively via the Azure CLI:

```bash
az role assignment create \
  --assignee "<AZURE_CLIENT_ID>" \
  --role "Contributor" \
  --scope "/subscriptions/<AZURE_SUBSCRIPTION_ID>"
```

> **Note:** The Bicep templates also create a **User-Assigned Managed Identity** with Contributor rights scoped to the resource group for Azure Image Builder. This is separate from the App Registration.

---

## 3. Fork or Clone the Repository

If you are setting this up in your own GitHub account:

```bash
# Option A: Fork via GitHub UI, then clone your fork
git clone https://github.com/<your-username>/Azure-FoundryLocal-ImageGallery.git

# Option B: Clone and push to your own repo
git clone https://github.com/aj-enns/Azure-FoundryLocal-ImageGallery.git
cd Azure-FoundryLocal-ImageGallery
git remote set-url origin https://github.com/<your-username>/Azure-FoundryLocal-ImageGallery.git
git push -u origin main
```

---

## 4. Configure GitHub Secrets

In your GitHub repository, navigate to **Settings → Secrets and variables → Actions → Secrets** and add:

| Secret Name | Value | Where to Find It |
|-------------|-------|-------------------|
| `AZURE_CLIENT_ID` | Application (client) ID | Azure Portal → App Registration → Overview |
| `AZURE_TENANT_ID` | Directory (tenant) ID | Azure Portal → App Registration → Overview |
| `AZURE_SUBSCRIPTION_ID` | Subscription ID | Azure Portal → Subscriptions → Overview |

---

## 5. Configure GitHub Variables (Optional)

Under **Settings → Secrets and variables → Actions → Variables**, you can optionally override defaults:

| Variable Name | Default Value | Description |
|---------------|---------------|-------------|
| `AZURE_RESOURCE_GROUP` | `rg-foundry-image-gallery` | Resource group where all resources are deployed |
| `AZURE_LOCATION` | `eastus` | Azure region for the deployment |

> **Tip:** Choose a region that supports Azure Image Builder and Windows 11 images. Most major regions (eastus, westus2, westeurope, etc.) are supported.

---

## 6. Customise Gallery Metadata

Copy the example file and fill in your values:

```bash
cp infra/main.bicepparam.example infra/main.bicepparam
```

Then edit `infra/main.bicepparam` to set your community gallery details:

```bicep
// Must be globally unique across all of Azure
param galleryPublicNamePrefix = 'YourUniqueGalleryName'

// Your public website or GitHub profile
param publisherUri = 'https://github.com/your-username'

// Contact email shown to gallery consumers
param publisherContact = 'you@example.com'

// End-User Licence Agreement text
param eula = 'By using images from this gallery you accept that they are provided as-is without warranty.'
```

### Optional: Multi-Region Replication

To replicate the built image to additional regions, update the `additionalReplicationRegions` parameter:

```bicep
param additionalReplicationRegions = ['westus2', 'westeurope']
```

> The primary region (set by `AZURE_LOCATION`) is always included automatically.

---

## 7. Run the Workflow

1. In your GitHub repository, go to **Actions**.
2. Select the **Build Windows 11 + Foundry Local Image** workflow from the left sidebar.
3. Click **Run workflow**.
4. Optionally override the resource group name and Azure region.
5. Click the green **Run workflow** button.

The build takes approximately **2–3 hours** (mostly due to Windows Update applying patches).

---

## 8. What the Workflow Does

The workflow executes these steps automatically:

| Step | Description |
|------|-------------|
| **1. Checkout** | Pulls the repository code. |
| **2. Azure Login** | Authenticates to Azure using OIDC (no stored passwords). |
| **3. Register Providers** | Registers `Microsoft.VirtualMachineImages`, `Microsoft.Compute`, `Microsoft.KeyVault`, `Microsoft.Storage`, `Microsoft.Network`, and `Microsoft.ManagedIdentity`. |
| **4. Create Resource Group** | Creates the resource group if it doesn't exist. |
| **5. Deploy Bicep** | Deploys the infrastructure: User-Assigned Managed Identity, Azure Compute Gallery (with community sharing), image definition, and Image Builder template. |
| **6. RBAC Propagation** | Waits 90 seconds for role assignments to propagate. |
| **7. Trigger Build** | Starts the Azure Image Builder build. |
| **8. Poll for Completion** | Checks build status every 5 minutes (up to 3 hours). |
| **9. Summary** | Prints the published image version details to the GitHub Actions summary. |

### Resources Created

| Resource | Name (default) | Purpose |
|----------|----------------|---------|
| User-Assigned Managed Identity | `flocal-aib-identity` | Gives Azure Image Builder permissions to create staging resources and write to the gallery. |
| Azure Compute Gallery | `flocalgallery` | Hosts the image definitions and versions with community sharing. |
| Image Definition | `Win11-FoundryLocal` | Describes the Windows 11 Enterprise 24H2 + Foundry Local image (Gen 2, Trusted Launch). |
| Image Template | `flocal-win11-foundry-template` | Azure Image Builder template that sources Windows 11, installs Foundry Local, applies Windows Updates, and outputs to the gallery. |
| Contributor Role Assignment | *(auto-generated GUID)* | Grants the managed identity Contributor rights on the resource group. |

---

## 9. Create a VM from the Published Image

Once the workflow completes successfully, you can create VMs using the published image.

### Azure Portal

1. Go to the [Azure Portal](https://portal.azure.com).
2. Search for **Community images** in the top search bar.
3. Search for the `galleryPublicNamePrefix` you configured (e.g. `FoundryLocalGallery`).
4. Select the **Win11-FoundryLocal** image definition.
5. Click **Create VM** and configure your VM settings.

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
  --resource-group  my-vm-rg \
  --name            my-foundry-vm \
  --image           "/communityGalleries/<yourGalleryPublicNamePrefix>/images/Win11-FoundryLocal/versions/latest" \
  --size            Standard_D8ads_v5 \
  --admin-username  azureuser \
  --generate-ssh-keys
```

> **Recommended VM size:** `Standard_D8ads_v5` (8 vCPU / 32 GiB RAM) or larger. Foundry Local benefits from sufficient memory and compute.

---

## 10. Verify Foundry Local on the VM

After the VM is running, connect via RDP or Bastion and confirm Foundry Local is installed:

```powershell
# Check the CLI is available
foundry --version

# List available models
foundry model list
```

---

## 11. Ongoing Maintenance

### Automatic Monthly Rebuilds

The workflow is scheduled to run automatically on the **1st of every month at 03:00 UTC**. This picks up:

- The latest Windows 11 Enterprise 24H2 patches
- Any updates to the Azure Foundry Local package

### Manual Rebuilds

Trigger a rebuild at any time from **Actions → Build Windows 11 + Foundry Local Image → Run workflow**.

### Updating Parameters

To change gallery metadata, region, or replication settings, update `infra/main.bicepparam` and run the workflow again. The Bicep deployment is idempotent — it will update existing resources rather than recreating them.

> `main.bicepparam` is git-ignored so your values are never committed.

---

## 12. Troubleshooting

### Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| **Workflow fails at "Login to Azure"** | Missing or incorrect GitHub Secrets | Verify `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` are set correctly in GitHub Secrets. |
| **"Authorization failed" during Bicep deployment** | App Registration lacks permissions | Ensure the App Registration has **Contributor** on the subscription. If the Bicep deployment creates role assignments, **Owner** may be needed. |
| **"Federated credential not found"** | Branch name mismatch | Ensure the federated credential in Azure AD matches the branch name the workflow runs from (e.g. `main`). |
| **Provider registration fails** | Subscription doesn't support the provider | Some providers require specific subscription types. Check `az provider show --namespace Microsoft.VirtualMachineImages` for registration state. |
| **Image build times out (>3 hours)** | Windows Update or network issues in the build VM | Check the Image Builder run status with `az image builder show --resource-group <rg> --name <template> --query lastRunStatus`. Retry the workflow. |
| **"galleryPublicNamePrefix already in use"** | Prefix must be globally unique | Choose a different, unique prefix in `infra/main.bicepparam`. Must be 5–16 chars, alphanumeric only. |
| **Image Builder fails with Contributor error** | RBAC hasn't propagated yet | The workflow includes a 90-second wait. If issues persist, manually re-run the failed workflow — RBAC should have propagated by then. |

### Inspecting Build Logs

```bash
# View the Image Builder template status
az image builder show \
  --resource-group rg-foundry-image-gallery \
  --name flocal-win11-foundry-template \
  --query lastRunStatus \
  --output json

# View detailed customization logs (available in the staging resource group)
az image builder show \
  --resource-group rg-foundry-image-gallery \
  --name flocal-win11-foundry-template \
  --query "lastRunStatus.message" \
  --output tsv
```

### Cleaning Up

To remove all deployed resources:

```bash
# Delete the resource group and everything in it
az group delete --name rg-foundry-image-gallery --yes --no-wait
```

> **Warning:** This permanently deletes the gallery, all image versions, the managed identity, and the image template.
