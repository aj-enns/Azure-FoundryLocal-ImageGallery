# Build Flow

This diagram shows the end-to-end logic flow when the **Build Windows 11 + Foundry Local Image** workflow is triggered.

```mermaid
flowchart TD
    subgraph Trigger["Trigger"]
        A1[Manual: Run Workflow] --> START
        A2[Schedule: 1st of month 03:00 UTC] --> START
    end

    START((Start)) --> B1

    subgraph GHA["GitHub Actions Workflow — build-image.yml"]
        B1["1. Checkout repo"]
        B1 --> B2["2. Azure Login via OIDC"]
        B2 --> B3["3. Register resource providers + SIGSoftDelete feature"]
        B3 --> B4["4. Create resource group"]
        B4 --> B5{"5. Image template exists?"}
        B5 -- Yes --> B5a["Cancel running build then delete template"]
        B5 -- No --> B6
        B5a --> B6

        B6["6. Deploy Bicep — main.bicep"]
        B6 --> B6a["identity.bicep — Managed Identity + Contributor RBAC"]
        B6 --> B6b["gallery.bicep — Compute Gallery + Image Definition"]
        B6a --> B6c["imagebuilder.bicep — Image Builder template"]
        B6b --> B6c

        B6c --> B7["7. Wait 90s for RBAC propagation"]
        B7 --> B8["8. Trigger Image Builder run"]
        B8 --> B9["9. Poll every 5 min until Succeeded / Failed / Timeout"]
    end

    B9 -- Succeeded --> B10["10. Print image version summary"]
    B9 -- Failed/Timeout --> FAIL["Build Failed"]
    B10 --> B11["11. Azure Logout"]
    FAIL --> B11

    subgraph AIB["Azure Image Builder — Packer VM in staging RG"]
        direction TB
        C1["Boot Windows 11 24H2 VM — Standard_D8ads_v5"]
        C1 --> C2["Install Foundry Local via winget"]
        C2 --> C3["Reboot"]
        C3 --> C4{"applyWindowsUpdate?"}
        C4 -- true --> C5["Windows Update — Security + Critical + Important"]
        C5 --> C6["Reboot"]
        C6 --> C7["Log Windows Update events"]
        C7 --> C8["Cleanup temp files"]
        C4 -- false --> C8
        C8 --> C9["Sysprep — Generalize image"]
        C9 --> C10["Capture VHD"]
        C10 --> C11["Distribute to Compute Gallery"]
    end

    B8 -.->|triggers| C1
    C11 -.->|image version published| B9
```

## Files involved

| Step | File | Purpose |
|------|------|---------|
| Workflow orchestration | `.github/workflows/build-image.yml` | GitHub Actions workflow — triggers, inputs, Azure CLI steps |
| Root Bicep template | `infra/main.bicep` | Orchestrates all Bicep modules |
| Parameters | `infra/main.bicepparam` | Default values for the deployment |
| Managed Identity | `infra/modules/identity.bicep` | Creates the user-assigned identity + Contributor RBAC |
| Compute Gallery | `infra/modules/gallery.bicep` | Creates the gallery with community sharing + image definition |
| Image Builder | `infra/modules/imagebuilder.bicep` | Defines the Packer-based build template with customization steps |
| Bicep config | `infra/bicepconfig.json` | Registers the Microsoft Graph extension |
