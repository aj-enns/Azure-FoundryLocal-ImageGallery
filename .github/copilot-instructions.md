# Copilot Instructions for Azure-FoundryLocal-ImageGallery

## Project Overview

This is a **public repository**. Every piece of documentation, code comments, and Bicep descriptions must be written so that an external user with basic Azure knowledge can follow along without ambiguity.

## Audience

Contributors and consumers range from first-time Azure users to experienced cloud engineers. Always err on the side of **clarity over brevity** — spell out prerequisites, link to official docs, and explain *why* a step is needed, not just *what* to do.

## Repository Layout

| Path | Purpose |
|------|---------|
| `infra/setup.bicep` + `setup.bicepparam.example` | One-time bootstrap (subscription-scoped): App Registration, OIDC federation, Contributor + User Access Administrator roles. Users copy `.example` to `setup.bicepparam` (git-ignored). |
| `infra/main.bicep` + `main.bicepparam` | Core infrastructure (resource-group-scoped): managed identity, Compute Gallery, Image Builder template. Checked in with safe defaults; subscription-specific values (e.g. staging RG) are overridden via GitHub Variables. |
| `infra/bicepconfig.json` | Bicep CLI configuration — registers the Microsoft Graph dynamic extension for `appregistration.bicep`. |
| `infra/modules/*.bicep` | Reusable Bicep modules (identity, gallery, imagebuilder, appregistration). |
| `.github/workflows/build-image.yml` | GitHub Actions workflow — builds and publishes the VM image. |
| `scripts/windows/` | PowerShell scripts executed inside the image (e.g. Foundry Local install). |
| `docs/INSTALL.md` | Step-by-step installation guide for end users. |

## Writing Style

- Use **plain, direct language**. Avoid jargon unless it is an Azure-specific term (and link to the relevant Microsoft Learn page on first use).
- Prefer **active voice** and imperative mood in instructions ("Run this command", not "The command should be run").
- Keep paragraphs short — three to four sentences maximum.
- Use tables and bullet lists to organise information; avoid walls of text.

## Documentation Rules

1. **README.md** — High-level overview, quick-start summary, and links to `docs/INSTALL.md` for detailed setup.
2. **docs/INSTALL.md** — The canonical, step-by-step install guide. Must remain accurate whenever infrastructure files change. Always update this file alongside any Bicep or workflow changes.
3. **Code comments** — Every Bicep file must start with a comment block describing its purpose. Every parameter must have a `@description()` decorator. Non-obvious logic should have inline comments explaining *why*.
4. **Outputs** — Bicep outputs must include `@description()` decorators that tell the user what the value is and where to use it (e.g. "Add this to GitHub Secrets as `AZURE_CLIENT_ID`").

## Bicep Conventions

- **API versions**: Use the latest stable API version available. Do not use preview APIs unless absolutely necessary.
- **Naming**: Use the `namePrefix` parameter pattern established in `main.bicep`. Resource names should be deterministic and predictable.
- **Modules**: Each logical Azure resource group (identity, gallery, image builder, app registration) lives in its own file under `infra/modules/`.
- **Parameters**: Always provide sensible defaults where possible. Required parameters (no default) must be clearly documented.
- **Tags**: Propagate the `tags` object to every resource for consistent governance.
- **Scope**: `main.bicep` is resource-group-scoped. `setup.bicep` is subscription-scoped. Do not mix scopes within a single template.
- **Security**: Never hard-code secrets, keys, or credentials. Use managed identities and OIDC federation. Role assignments should use the narrowest scope that works.

## PowerShell Script Conventions

- Scripts must start with `#Requires -RunAsAdministrator` when elevation is needed.
- Use `$ErrorActionPreference = 'Stop'` and `Set-StrictMode -Version Latest`.
- Log every significant action with a timestamped `Write-Host` or `Write-Log` helper.
- Validate tool availability (e.g. `winget`) before using it, and provide a clear error message if missing.

## GitHub Actions Workflow

- Authenticate to Azure exclusively via **OIDC** (`azure/login@v2` with federated credentials). No stored client secrets.
- Pin action versions to major tags (e.g. `actions/checkout@v4`).
- Use environment variables for values referenced in multiple steps.
- Keep the workflow timeout generous (240 minutes) — Image Builder builds include Windows Update.

## Pull Request & Change Guidelines

- When modifying any `infra/*.bicep` file, verify that `docs/INSTALL.md` still reflects the current deployment steps. Update it if anything has changed.
- When adding a new Bicep module, add a corresponding row to the repository layout table in this file and in `README.md`.
- Test Bicep changes locally with `az bicep build --file <path>` before committing.
- Commit messages should be concise and descriptive (e.g. "Add appregistration.bicep for OIDC bootstrap").
