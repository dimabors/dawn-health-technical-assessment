# Pipeline & Infrastructure

> How code goes from your laptop to production. How to contribute, how to deploy, how to roll back.

---

## What we run

```
Azure (Bicep)          → rg-team-alpha / AKS (aks-shared) + ACR (ecapacr) + Key Vaults
GitHub Actions         → infra CI (Bicep deploys)
Azure DevOps Pipelines → app CI (build / test / scan / push)
ArgoCD                 → CD (GitOps sync to cluster)
Kustomize              → manifest rendering (base + overlays)
LGTM Stack             → observability (Loki, Grafana, Tempo, Mimir)
Prometheus Operator    → alerting (PrometheusRule / ServiceMonitor CRDs)
```

---

## Repo map

```
deploy/
  bicep/
    platform.bicep           # AKS + ACR — shared across all teams
    workload-identity.bicep  # Key Vaults + UAMIs (dev / staging / prod) — per tenant
    gha-deployer.bicep       # GitHub Actions OIDC identity — bootstrapped once locally
    modules/wi-env.bicep     # Reusable: KV + UAMI + fedcred + KV role (1 per env)
  k8s/namespace-sa.yaml      # Namespace + ServiceAccount template (CI substitutes vars)

part1/
  namespace.yaml             # Namespace, Role, RoleBinding, ServiceAccount for team-alpha
  workload-identity.bicep    # Single-env identity wiring explained in full (dev only)

part2/
  pipeline.yml               # Azure DevOps CI pipeline
  base/                      # Kustomize base — blue + green Deployments + Service
  overlays/
    dev/kustomization.yaml   # ← CI bumps green newTag here on every main build
    staging/kustomization.yaml
    prod/kustomization.yaml

part3/
  argocd-application.yaml          # ArgoCD app — dev   (watches context/devops-dev)
  argocd-application-staging.yaml  # ArgoCD app — staging (watches context/devops)
  argocd-application-prod.yaml     # ArgoCD app — prod  (watches main)

part4/
  Dockerfile.hardened        # Multi-stage, node:24-alpine, non-root — use this one
  src/server.js              # Node stdlib only: /health, /api/v1/patients, /api/v1/appointments
  tests/smoke.test.js        # node:test smoke tests (run inside the container in CI)

part5/
  servicemonitor.yaml        # Scrape /metrics every 30s
  alert-rule.yaml            # HighErrorRate (5xx >5% / 5m), HighP95Latency (p95 >1s / 10m)
```

---

## Contributing — the everyday loop

### 1. Branch off main

```bash
git checkout -b feature/your-thing
```

Feature branch naming `feature/*` is picked up by the ADO trigger automatically.

### 2. Work on the code

```bash
npm install && npm start   # server on :8080
curl localhost:8080/health
```

No build step. The server runs directly with `node src/server.js`.

### 3. Push → CI runs automatically

Azure DevOps triggers on `feature/*`. It:

1. Builds `Dockerfile.hardened` (multi-stage, Alpine, no secrets, non-root)
2. Runs `npm test` **inside the built container** (so tests run against the exact runtime env)
3. Runs Trivy — fails the build if any CRITICAL CVE is found
4. Does **not** push the image and does **not** touch GitOps overlays

Your PR gets a ✅ or ❌ from CI. The Trivy result is visible in the build log.

### 4. PR review → merge to main

After merge to main, CI runs again **in full mode**:

1. Build + test + scan (same as above)
2. Push image to `ecapacr.azurecr.io/team-alpha/backend:{buildNumber}-{fullSHA}`
3. Update `part2/overlays/dev/kustomization.yaml` — bumps `team-alpha-backend-green.newTag`
4. Commits that change back with `[skip ci]` and pushes

ArgoCD picks up the new commit within 2-3 minutes and rolls out the update to `team-alpha-dev`.

---

## Full CI pipeline (`part2/pipeline.yml`)

```
Trigger: main, feature/*
Pool:    ubuntu-latest

Stage 1: CI ─────────────────────────────────────────────────────────────────
  Build         docker build -f Dockerfile.hardened -t ecapacr.../team-alpha/backend:{tag}
  Test          docker run <image> npm test
  Scan          trivy image --exit-code 3 --severity CRITICAL <image>
                  → exit 3 if CRITICAL found → build fails, image never pushed
  Push          docker push <image>   ← ONLY on main (condition gate)

Stage 2: UpdateGitOps ───────────────────────────────────────── ONLY on main
  checkout (persistCredentials: true)
  kustomize edit set image team-alpha-backend-green=ecapacr.../team-alpha/backend:{tag}
  git commit "ci: bump dev ... [skip ci]"
  git push origin HEAD:main
```

Image tag format: `{Build.BuildNumber}-{Build.SourceVersion}` — e.g. `30-ce24f324...`  
Every image is traceable to an exact commit. No rebuilds on promotion.

---

## GitOps delivery (ArgoCD)

Three ArgoCD Applications watch three different branches:

| Environment | Branch | Overlay path | Namespace |
|---|---|---|---|
| dev | `context/devops-dev` | `part2/overlays/dev` | `team-alpha-dev` |
| staging | `context/devops` | `part2/overlays/staging` | `team-alpha-staging` |
| prod | `main` | `part2/overlays/prod` | `team-alpha-prod` |

ArgoCD is set to `automated.prune: true` + `selfHeal: true` on all environments.  
`selfHeal` means: if someone does `kubectl set image` directly, ArgoCD will revert it.  
Nothing in the cluster is authoritative — Git is authoritative.

### What Kustomize renders

The base has two Deployments and one Service:

```
team-alpha-backend-blue   replicas: 1   # preview / canary slot — no live traffic
team-alpha-backend-green  replicas: 2   # live traffic slot
Service                                 # selector: slot: green  ← only green gets traffic
```

The overlay sets concrete image tags for both slots. CI bumps the **green** tag on every build. The blue slot is used for internal preview validation before a traffic flip.

---

## Promote to staging

1. Open a PR: `context/devops-dev` → `context/devops`
2. Change: copy the green `newTag` from `overlays/dev/kustomization.yaml` into `overlays/staging/kustomization.yaml`
3. Peer review + merge
4. ArgoCD syncs `team-alpha-staging` automatically

The image was already pushed by the dev CI run. Nothing is rebuilt.

---

## Promote to prod

1. Open a PR: `context/devops` → `main`
2. Change: copy the green `newTag` into `overlays/prod/kustomization.yaml`
3. PR must be approved by a designated reviewer (**Azure DevOps Environment approval** on `prod`)
4. Merge → ArgoCD syncs `team-alpha-prod`

The approval creates an auditable record: who approved, when, exactly which image. Required under SaMD change control.

---

## Rollback

Something broke in prod. Do this:

```bash
# Find the commit that bumped the tag
git log --oneline part2/overlays/prod/kustomization.yaml
# → abc1234 ci: bump prod team-alpha-backend-green to 30-ce24f... [skip ci]

# Revert it
git revert abc1234 --no-edit
git push origin main
```

ArgoCD detects the revert commit and rolls the Deployment back to the previous image tag within 2-3 minutes. No pipeline run, no kubectl, no approval gate (rollbacks bypass the gate intentionally).

Tell the incident channel **before** you revert, not after. One line is enough:
> `Initiating rollback on prod — error rate at 12% — ETA 3 min`

---

## Infra changes (Bicep)

All Bicep changes go through GitHub Actions (not Azure DevOps). Push to the relevant branch:

| Branch | What re-deploys |
|---|---|
| `context/devops-dev` | Bicep infra + dev K8s namespace + dev SA |
| `context/devops` | Bicep infra + staging K8s namespace + staging SA |
| `main` | Bicep infra + prod K8s namespace + prod SA |

The GH Actions workflow authenticates via OIDC (no passwords, no secrets in repo). The UAMI `id-team-alpha-gha-deployer` has `Contributor` + `User Access Administrator` on `rg-team-alpha`.

To add a new team/environment: add a new entry in `workload-identity.bicep` environments array + add a namespace/SA in `deploy/k8s/` + create ArgoCD Application pointing at the new overlay.

---

## Identity — how authentication works (no passwords)

```
Developer laptop
  → Azure AD group (OID: 00000000-...) → RoleBinding in team-alpha namespace

GitHub Actions
  → OIDC token from github.com → exchanged for Azure access token
  → UAMI id-team-alpha-gha-deployer → Contributor on rg-team-alpha

Pod (running in AKS)
  → ServiceAccount annotation: azure.workload.identity/client-id: <uami-client-id>
  → Webhook injects OIDC token + AZURE_CLIENT_ID env var
  → UAMI id-team-alpha-workload-{env} → Key Vault Secrets User on kv-team-alpha-{env}

AKS pulling images from ACR
  → AcrPull role on ecapacr for AKS kubelet identity (set in platform.bicep)
```

No service principal keys. No passwords in env vars. No secrets in Dockerfiles.

---

## Observability

> **LGTM stack (Grafana, Loki, Tempo, Mimir) is not yet deployed.** The `part5/` manifests are written and ready — they need `kube-prometheus-stack` installed first. Until then, use the commands below.

### What works right now

**Logs** (any running pod):
```sh
kubectl logs -n team-alpha-prod -l slot=green --tail=100 --follow
```

**Resource usage** (`metrics-server` is installed):
```sh
kubectl top nodes
kubectl top pods -n team-alpha-prod
```

**Live app endpoints** (LoadBalancer IPs):

| Env | External IP | Health |
|---|---|---|
| dev | `20.93.122.142` | `http://20.93.122.142/health` |
| staging | `20.54.105.188` | `http://20.54.105.188/health` |
| prod | pending | — |

**ArgoCD UI** — sync status, diffs, rollout events for all three environments:
```sh
kubectl port-forward svc/argocd-server -n argocd 8080:443
# open https://localhost:8080 (accept self-signed cert)
# admin password:
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```

### Enabling full metrics + alerting (once kube-prometheus-stack is installed)

```sh
kubectl apply -f part5/servicemonitor.yaml
kubectl apply -f part5/alert-rule.yaml
```

Two alert rules will activate:

| Alert | Condition | Window | Severity |
|---|---|---|---|
| HighErrorRate | 5xx rate > 5% | 5 min sustained | warning |
| HighP95Latency | p95 latency > 1s | 10 min sustained | warning |

Both carry a copy-paste `kubectl` command in the `action:` annotation — the alert tells you what to run first.

Then port-forward Grafana:
```sh
kubectl port-forward svc/grafana -n monitoring 3000:80
# open http://localhost:3000
```

---

## Key names at a glance

| Thing | Value |
|---|---|
| Resource group | `rg-team-alpha` |
| AKS cluster | `aks-shared` |
| Container registry | `ecapacr.azurecr.io` |
| Image path | `ecapacr.azurecr.io/team-alpha/backend` |
| Image tag format | `{buildNumber}-{commitSHA}` |
| Dev namespace | `team-alpha-dev` |
| Staging namespace | `team-alpha-staging` |
| Prod namespace | `team-alpha-prod` |
| ServiceAccount | `team-alpha-workload-sa` |
| Dev Key Vault | `kv-team-alpha-dev` |
| Prod Key Vault | `kv-team-alpha-prod` |
| ArgoCD dev app | `team-alpha-backend-dev` |
| ArgoCD prod app | `team-alpha-backend-prod` |
