# Initial Deploy — one-time local bootstrap

Everything afterwards runs in CI ([.github/workflows/infra.yml](../.github/workflows/infra.yml)).
This file documents the **single chicken-and-egg step**: the GitHub Actions
deployer UAMI has to exist in Azure before any GitHub workflow can authenticate.

## Prerequisites

- Azure CLI ≥ 2.60 installed (`winget install -e --id Microsoft.AzureCLI`).
- You are an Owner (or have `User Access Administrator` + `Contributor`) on the
  target subscription.

## Steps

```powershell
# 1. Log in.
az login
az account set --subscription 0ab058e3-88c1-4c7d-9f7a-d13afddf3e41

# 2. Resource group (one-time; CI runs RG-scoped deployments and won't create it).
az group create -n rg-team-alpha -l northeurope

# 3. Bootstrap the GitHub Actions deployer UAMI + federated credentials + RG roles.
az deployment group create `
  --resource-group rg-team-alpha `
  --template-file deploy/bicep/gha-deployer.bicep `
  --parameters repo='dimabors/dawn-health-technical-assessment' `
               branch='context/devops-dev'

# 4. Read the values you need to paste into GitHub.
az deployment group show `
  -g rg-team-alpha -n gha-deployer `
  --query "properties.outputs" -o json
```

The outputs object looks like:

```json
{
  "deployerClientId":   { "value": "8bc9f09c-..." },
  "deployerPrincipalId":{ "value": "..." },
  "tenantId":           { "value": "412247cf-..." },
  "subscriptionId":     { "value": "0ab058e3-..." }
}
```

## Add GitHub Repository Variables

GitHub → repo → **Settings → Secrets and variables → Actions → "Variables" tab**.

| Name | Value |
| --- | --- |
| `AZURE_CLIENT_ID` | `deployerClientId` from above |
| `AZURE_TENANT_ID` | `tenantId` from above |
| `AZURE_SUBSCRIPTION_ID` | `subscriptionId` from above |
| `AZURE_RG` | `rg-team-alpha` |
| `AZURE_LOCATION` | `northeurope` |
| `AKS_CLUSTER` | `aks-shared` |
| `ACR_NAME` | `ecapacr` |
| `GH_REPO` | `dimabors/dawn-health-technical-assessment` |

> No GitHub *secrets* are required for infra. OIDC handles auth.

## Create GitHub Environments

**Settings → Environments → New environment** → create `dev`, `staging`, `prod`.

For `prod` only: Required reviewers = yourself; Deployment branches = `context/devops-dev`.

## After that

Push to `context/devops-dev` (or run the `infra` workflow manually). Everything
else — ACR, AKS, all three KVs, all three UAMIs, all the role assignments,
the K8s namespaces and ServiceAccounts — comes from CI re-applying Bicep.
The deployer UAMI is even self-managing: the workflow re-applies
`gha-deployer.bicep` so adding a new branch or environment to trust is a
one-line Bicep change.
