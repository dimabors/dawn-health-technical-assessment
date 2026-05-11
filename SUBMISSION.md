# Submission — DevOps Engineer Technical Assessment

**Candidate name:**
**Date:**
**Repository:**

---

## Part 1 — Tenant Onboarding: Access & Identity

### 1.1 Kubernetes Manifests

> No written answer needed — your completed `part1/namespace.yaml` is the answer.
>
> If you made design decisions worth calling out, note them briefly here.

_Optional notes here._

---

### 1.2 Workload Identity

> No written answer needed — your `part1/workload-identity.bicep` is the answer.
>
> What annotation must be present on the ServiceAccount for the Workload Identity binding to work, and why?

The ServiceAccount must carry:

```yaml
annotations:
  azure.workload.identity/client-id: "<uami-client-id>"
```

The AKS Workload Identity mutating webhook reads this annotation to know which Azure Managed Identity the pod should assume. Without it the webhook skips the pod entirely — it does not inject the AZURE_CLIENT_ID environment variable nor the projected OIDC token volume mount. The pod starts but every Azure SDK call fails at authentication because there is nothing to exchange.

Optionally, `azure.workload.identity/tenant-id` can be added if the identity lives in a different tenant than the cluster; it defaults to the cluster's tenant if omitted.

The pod spec also needs the label azure.workload.identity/use: `"true"` to opt into the mutation — the webhook ignores pods without it, which is the safe default so other workloads are unaffected.

---

## Part 2 — CI Pipeline: Azure DevOps

### 2.1 Completed Pipeline

> No written answer needed — your completed `part2/pipeline.yml` is the answer.
Done

---

### 2.2 Pipeline Design Decisions

> How would you structure the pipeline differently for feature branches vs main?

Feature branches run the full CI stage — build, test, and scan — so every PR gets a quality gate. The push and GitOps update stages are skipped entirely (enforced by the `condition: eq(variables['Build.SourceBranchName'], 'main')` on both the push step and the `UpdateGitOps` stage). This means a feature branch never writes to the registry or triggers a deployment; it only proves the code is safe to merge. On `main`, after the push succeeds, the GitOps update runs automatically and ArgoCD picks up the change within its sync interval.

> Where would you add a manual approval gate, and why only there?

Between staging and production, using an Azure DevOps **Environment approval** on the `prod` environment resource. 
Not before dev — dev should be fully automated to keep the feedback loop fast. 
Not before staging — staging validation is also automated (smoke tests, integration tests), but it can be also manual if needed as it can ruin the manual test if someone is doing it on a specific release candidate. 
The gate sits only before prod because that is the only environment where a bad deploy has direct patient impact and cannot be quietly rolled back without communication. 
The approval also creates an audit record required under SaMD change control: a named person explicitly approved the release at a specific time.

> How do you ensure the same image digest is deployed through dev → staging → prod rather than rebuilt?

The image is built and pushed **once** in the CI stage, tagged with `$(Build.BuildNumber)-$(Build.SourceVersion)`. That tag encodes the exact commit SHA, so it uniquely identifies one build. 
Promotion to staging and production is done by copying that same tag string into the staging/prod Kustomize overlay and committing it — no rebuild, no new `docker build`. ArgoCD then pulls the exact same layer digest from ACR that dev already ran. 
To make this even stricter in production would pin by digest (`image@sha256:...`) rather than tag, since a tag can theoretically be overwritten; a digest cannot that will bring extra transparency to the audit log.

---

## Part 3 — GitOps Delivery: ArgoCD

### 3.1 ArgoCD Application

> No written answer needed — your completed `part3/argocd-application.yaml` is the answer.

---

### 3.2 Promotion Model

> What does the Azure DevOps pipeline do to trigger a deployment to dev?

On a successful merge to `main`, the `UpdateGitOps` stage runs `kustomize edit set image` to update the `newTag` for [team-alpha-backend-green](part2/overlays/dev/kustomization.yaml#L13) in [part2/overlays/dev/kustomization.yaml](part2/overlays/dev/kustomization.yaml), then commits and pushes that change back to the repo. 
ArgoCD polls the repo on its sync interval and detects the new commit. Because `automated.prune` and `selfHeal` are enabled, it reconciles the cluster state to match Git — pulling the new image and rolling out the updated Deployment — without any manual intervention.
[part1/workload-identity.bicep](part1/workload-identity.bicep)
> What triggers promotion to staging, and then to production?

Promotion is a deliberate, human-reviewed Git operation — not an automatic pipeline step. A team member (or a promotion script) opens a PR that copies the verified image tag from `overlays/dev/kustomization.yaml` into [overlays/staging/kustomization.yaml](overlays/staging/kustomization.yaml). 
Merging that PR is the promotion event: ArgoCD's staging Application detects the commit and syncs. 
Production follows the same pattern — a PR from staging into `overlays/prod/kustomization.yaml`, but gated by the Azure DevOps Environment approval that requires a named reviewer to sign off before the PR can be merged.

> What is the benefit of this model over having the pipeline kubectl apply directly?

Four benefits by using this model: 

(1) **Auditability** — every deployment is a Git commit in a version control environment with an author, timestamp, and diff, which satisfies SaMD change-control requirements without extra tooling. 

(2) **Drift detection** — ArgoCD continuously compares cluster state to Git and alerts (or self-heals) if they diverge, meaning an ad-hoc `kubectl` change is immediately visible and reversible. 

(3) **Rollback is a revert** — to undo a bad release someone can revert the commit; ArgoCD syncs the old state back, so that no pipeline re-run is needed. That rollback is also auditable with a clear record of who did it and why (in the commit message). Moreover, the revert back can be done automatically by ArgoCD if it's set up a sync failure hook to trigger a rollback on failed health checks after a deploy — giving a near-instant remediation without waiting for a human to notice and react, and maybe it would be a acceptable to realease on Friday :) (NO). Though the automatic rollback pattern should be used very carefully in production as it can cause instability.  

(4) **Separation of concerns** — CI proves the code is safe; CD is a separate, auditable promotion step. With `kubectl apply` in the pipeline will lose all of these: no drift detection, no approval record, rollback requires another pipeline run.

---

## Part 4 — Container Security & Image Hardening

### 4.1 Hardened Dockerfile

> No written answer needed — your hardened `part4/Dockerfile` (or `part4/Dockerfile.hardened`) is the answer.
>
> If you made decisions that are not obvious from the file itself, note them here.

_Optional notes here._

---

### 4.2 Kubernetes Runtime Security

> Describe the Kubernetes-side controls you would add. Cover securityContext fields, capability dropping, and cluster-wide enforcement.



---

### 4.3 Supply Chain for a Regulated Environment

> How does image scanning fit into a compliance-grade pipeline?

Scanning goes after the image is built but before it is pushed to the registry — this is the only position where it gates the rest of the pipeline. 
In the current `part2/pipeline.yml` this is the `ScanImage` step that runs Trivy with `--exit-code 3 --severity CRITICAL`: if any critical CVE is found the step exits non-zero, the push step is skipped, and the build fails with a clear message. 
This means a vulnerable image can never reach the registry, let alone a cluster.

For a SaMD pipeline the scan result must also be stored as a build artefact (the full JSON report) so it forms part of the Design History File (DHF). 
The threshold for failure should be agreed with QA — typically `CRITICAL` must fail the build immediately; `HIGH` fails unless it was agreed upon in the issue tracker.

> What would you add beyond scanning (SBOMs, image signing, provenance attestation) and what problem does each solve?


---

## Part 5 — Observability: Alerting & Instrumentation

### 5.1 ServiceMonitor

> No written answer needed — your completed `part5/servicemonitor.yaml` is the answer.

---

### 5.2 Alert Rules

> No written answer needed — your `part5/alert-rule.yaml` is the answer.
>
> If you want to explain the reasoning behind your chosen rules, add a note here.

_Optional notes here._

---

### 5.3 SLIs, SLOs, and Error Budget

> What SLIs would you define for a patient-facing API at Dawn Health?

_Your answer here._

> What initial SLO targets would you set, and how would you use error budget to guide release decisions?

_Your answer here._

> How would you ensure SLO burn-rate alerts are actionable rather than just noise?

_Your answer here._

---

## Part 6 — Operational Scenarios

### 6.1 Investigating a Timeout

> Walk through your investigation of intermittent HTTP 504s — specific tools, queries, and what you are confirming or ruling out at each step.

_Your answer here._

---

### 6.2 Bad Deployment in Production

> Describe your rollback procedure in a GitOps model — actions, order, and communication. Aim for under 5 minutes.

_Your answer here._

---

### 6.3 Certificate Expiry at 3am *(Optional)*

> Walk through your diagnosis and resolution of an unexpected cert-manager renewal failure.

_Your answer here._

---

## Anything Else?

> Note any tasks you skipped and how you would have approached them, assumptions you made, or anything else you would like the reviewers to know.

_Your answer here._
