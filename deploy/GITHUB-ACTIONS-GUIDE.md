# GitHub Actions Deployment Guide — `context/devops-dev`

End-to-end guide to deploy this repo's infrastructure (and later the app) to
Azure from GitHub Actions, with **no PAT, no client secret, and no password**
stored anywhere. Authentication uses **GitHub OIDC federation**: GitHub mints
a short-lived token for each workflow run, and Azure trusts that token via a
federated credential attached to a deployer User-Assigned Managed Identity.

> Why OIDC instead of a PAT or `AZURE_CREDENTIALS` JSON?
>
> - Nothing to rotate, nothing to leak.
> - Trust is scoped to **this repo + this branch (or this GitHub Environment)**.
>   A fork or a different branch cannot use the credential.
> - It's the same primitive we use for the in-cluster pod workload identity,
>   so the pattern stays consistent.

---

## 0. What's already done locally

You already ran:

- `deploy\Deploy-Infrastructure.ps1` — RG `rg-team-alpha`, ACR `ecapacr`, AKS `aks-shared`.
- `deploy\Deploy-WorkloadIdentity.ps1` — 3 KVs, 3 namespaces, 3 UAMIs, 3 federated creds, 3 SAs.
- `deploy\Setup-GitHubOidc.ps1` — deployer UAMI `id-team-alpha-gha-deployer` with federated creds for branch `context/devops-dev`, GitHub Environments `dev/staging/prod`, and pull requests; plus `Contributor` and `User Access Administrator` on `rg-team-alpha`.

Everything below is GitHub-side configuration plus running the workflow.

---

## 1. Merge the current code into `context/devops-dev`

Run locally (still on `context/devops`):

```powershell
git checkout -b context/devops-dev
git add .github deploy part1
git commit -m "ci: GitHub Actions infra workflow + OIDC bootstrap"
git push -u origin context/devops-dev
```

If the branch already exists upstream, instead do:

```powershell
git fetch origin
git checkout context/devops-dev
git merge --no-ff context/devops
git push origin context/devops-dev
```

---

## 2. Create the GitHub repository Variables

Open: **GitHub → repo → Settings → Secrets and variables → Actions → "Variables" tab → "New repository variable"**.

Add **all seven** of these (they are public identifiers, hence variables, not secrets):

| Name | Value |
|---|---|
| `AZURE_CLIENT_ID` | `8bc9f09c-6dd6-4732-8aa8-93fd4ea456a8` |
| `AZURE_TENANT_ID` | `412247cf-f335-4dec-8aa9-9209e17737d6` |
| `AZURE_SUBSCRIPTION_ID` | `0ab058e3-88c1-4c7d-9f7a-d13afddf3e41` |
| `AZURE_RG` | `rg-team-alpha` |
| `AZURE_LOCATION` | `northeurope` |
| `AKS_CLUSTER` | `aks-shared` |
| `ACR_NAME` | `ecapacr` |

> The first three were also printed by `Setup-GitHubOidc.ps1`. If you ever
> rotate the deployer UAMI, only `AZURE_CLIENT_ID` changes.

You **do not** need to add anything in the "Secrets" tab for infra.

---

## 3. Create three GitHub Environments

Open: **Settings → Environments → "New environment"** and create:

- `dev`
- `staging`
- `prod`

Why: the `infra` workflow uses a matrix that targets `environment: <name>`,
which (a) maps cleanly to the per-env federated credentials we already
created, and (b) lets you add **manual approval** on `prod` if you want.

For `prod` recommended settings:

- **Required reviewers**: yourself.
- **Deployment branches**: only `context/devops-dev` (later: `main`).

For `dev` and `staging`: leave defaults (no approvals).

> The federated credential for each environment trusts the subject
> `repo:dimabors/dawn-health-technical-assessment:environment:<name>`,
> so a job that does **not** declare `environment:` cannot get a token.

---

## 4. (Optional) Protect the `context/devops-dev` branch

**Settings → Branches → Add rule** for `context/devops-dev`:

- Require a pull request before merging.
- Require status checks: `validate` (the PR-only Bicep build job).

---

## 5. Trigger the workflow

The `infra` workflow runs automatically on push to `context/devops-dev` when
files under `part1/`, `deploy/`, or `.github/workflows/infra.yml` change.

To trigger it explicitly:

1. **Actions** tab → **infra** workflow → **Run workflow** dropdown.
2. Branch: `context/devops-dev`.
3. Inputs:
   - `skip_bootstrap` = `true` (we already bootstrapped — saves ~5 min).
   - `environments` = `dev,staging,prod` (or a subset).
4. **Run workflow**.

You should see two job groups:

- `bootstrap` — skipped (because of `skip_bootstrap`).
- `workload-identity (dev | staging | prod)` — three matrix jobs.
  - `prod` will pause for approval if you set required reviewers.

---

## 6. What each job actually does

### `validate` (PRs only)
Compiles `part1/workload-identity.bicep` with `az bicep build`. No Azure call,
no credentials needed.

### `bootstrap` (push / dispatch)
Runs `deploy/Deploy-Infrastructure.ps1`:
- Ensures the RG exists.
- Registers the required resource providers.
- Creates ACR + AKS if missing, or attaches ACR + ensures OIDC/WI on existing.
- Idempotent: a second run on an unchanged cluster is a few seconds.

### `workload-identity` (matrix: dev/staging/prod)
Runs `deploy/Deploy-WorkloadIdentity.ps1` for one environment. Per env:
- Creates the env-scoped Key Vault (RBAC mode).
- Creates the K8s namespace.
- Deploys `part1/workload-identity.bicep` → UAMI + federated cred + role assignment.
- Annotates the K8s ServiceAccount with the UAMI clientId.
- Uploads `deploy/outputs/<env>.json` as a workflow artifact (so later app-deploy
  jobs can pull the clientId without calling Azure again).

---

## 7. Troubleshooting

**`AADSTS70021: No matching federated identity record found`**
The token's subject doesn't match any federated credential. Causes:
- Job ran from a branch other than `context/devops-dev` and didn't declare
  `environment:` → no matching trust.
- Repo name in the federated cred doesn't match the actual repo (case sensitive).
- Fix by re-running `deploy\Setup-GitHubOidc.ps1 -Repo <owner/repo> -Branch <branch>`.

**`AuthorizationFailed` when creating role assignments**
Deployer UAMI doesn't have `User Access Administrator`. The setup script grants
this on `rg-team-alpha`; if you changed the RG, re-run the script.

**`The VM size of Standard_B2s is not allowed in your subscription`**
Already handled — script defaults to `Standard_B2s_v2`.

**Bicep deploy says `(ResourceNotFound) … managedClusters/aks-shared`**
You ran `workload-identity` with `skip_bootstrap=true` but the cluster doesn't
exist yet. Re-run with `skip_bootstrap=false`.

---

## 8. What's next (not part of this guide yet)

- **App build & push**: existing `.github/workflows/ci.yml` already pushes to
  ACR via the same OIDC pattern; we just need to add `AcrPush` on the deployer
  UAMI scoped to the ACR (or use a separate UAMI for app push).
- **App deploy / GitOps**: install ArgoCD, point it at `part2/overlays/<env>/`,
  and wire `part3/argocd-application.yaml`.
- **Promote to `main`**: once the dev branch deploys cleanly, merge to `main`
  and add a federated credential for `refs/heads/main` (one-line addition to
  `Setup-GitHubOidc.ps1`).
