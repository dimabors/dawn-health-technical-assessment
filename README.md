# Dawn Health — DevOps Engineer Technical Assessment

> **Suggested time:** ~4 hours | **We deeply respect your time** — it is fine to skip tasks; just document your intended approach in [`SUBMISSION.md`](./SUBMISSION.md).

---

## Getting Started

**Fork this repository** to your own GitHub account and work in your fork throughout the assessment. You are also welcome to host your work on GitLab, Azure DevOps, or any other Git platform — just make sure we can access it (public, or with the reviewers invited).

When you are done:

1. Ensure your repository is **publicly accessible** (or grant access to the reviewers listed below).
2. If hosting on **GitHub**, invite: `fja-dawn`, `rdy-dawn`, `aliadm-dawn` as collaborators.
3. If hosting elsewhere, share access details alongside the repository link.
4. Notify **Faisal Jarkass** at [fja@dawnhealth.com](mailto:fja@dawnhealth.com) with a link to your repository.
5. **Commit continuously** as you work — we value your commit history as part of the assessment.

Written answers go in [`SUBMISSION.md`](./SUBMISSION.md). Code and manifests go in the relevant `part*/` directory.

### A note on AI tools

You are welcome to use AI tools (GitHub Copilot, ChatGPT, etc.) during this assessment — we use them ourselves and encourage it. What matters is that you can explain every line you submit. During the follow-up conversation we will ask you to walk through your choices, so please do not submit anything you do not understand or cannot defend.

### A note on quality vs. completeness

We favour a well-reasoned, incomplete answer over a working but thoughtless one. We are not expecting production-ready code — we are looking for evidence that you understand the problem, have made deliberate choices, and can articulate your thinking. If you run out of time, document your intended approach in [`SUBMISSION.md`](./SUBMISSION.md) rather than rushing something in. A clear explanation of what you would do and why is worth more to us than code that happens to run.

---

## Assessment Criteria

| # | Criterion |
|---|-----------|
| 1 | **Working code** — do your manifests and pipelines actually do what is described |
| 2 | **Correctness** — are RBAC rules, pipeline stages, and selectors wired up properly |
| 3 | **Git history** — quality and continuity of your commits |
| 4 | **Clarity** — would a colleague understand and extend your work without asking |
| 5 | **Pragmatism** — sensible decisions, not over-engineered solutions |
| 6 | **DevOps practices** — evidence of good habits (small commits, meaningful names, comments where needed) |

---

## Solution Context

Dawn Health operates a **shared multi-tenant AKS cluster** that hosts multiple product teams and Life Sciences partners. We handle highly sensitive patient data under SaMD (Software as a Medical Device) regulations, so the platform must enforce:

- **Strict isolation** — a team should only ever be able to affect their own namespace and workloads
- **Safe, reversible deployments** — releases to production must be controllable and fast to roll back
- **Minimal blast radius** — a bad deployment by one team must not impact other tenants

Product teams need to move quickly. The platform team cannot be a bottleneck for every deployment. We use **Azure DevOps** for CI and **ArgoCD** for GitOps-based delivery to AKS.

### Tech Stack

| Layer | Technology |
|-------|------------|
| Cloud Provider | Microsoft Azure |
| Infrastructure as Code | Bicep |
| Orchestration | AKS (Azure Kubernetes Service) |
| CI | Azure DevOps Pipelines |
| GitOps / CD | ArgoCD |
| Observability | LGTM Stack — Loki, Grafana, Tempo, Mimir |

---

## Part 1 — Tenant Onboarding: Access & Identity

A new product team (`team-alpha`) is joining the platform. They will run their services in the `team-alpha` namespace on the shared AKS cluster. Your job is to wire up the access model so they can operate independently — without touching other tenants.

A starter file is provided at [`part1/namespace.yaml`](./part1/namespace.yaml). Complete and extend it.

### Task 1.1 — Kubernetes Namespace Manifests

The starter file already defines the `Namespace`. You need to add:

1. **A `Role`** that allows `team-alpha` developers to manage Deployments, Services, ConfigMaps, and Pods within their namespace — but nothing outside it.

2. **A `RoleBinding`** that grants that Role to an Azure AD group with object ID `00000000-0000-0000-0000-000000000001` (placeholder — we just want to see the wiring).

3. **A `ServiceAccount`** named `team-alpha-workload-sa` for the team's pods to use.

> Edit [`part1/namespace.yaml`](./part1/namespace.yaml) directly.

### Task 1.2 — Workload Identity (Bicep)

The team's backend pod needs to read secrets from a **dedicated Azure Key Vault** (`kv-team-alpha-dev`). It must authenticate without any stored credentials.

Write a **Bicep snippet** at `part1/workload-identity.bicep` that provisions:

1. A **User-Assigned Managed Identity** for the team's workload
2. A **federated credential** binding that identity to the `team-alpha-workload-sa` ServiceAccount in the `team-alpha` namespace on the AKS cluster
3. A **Key Vault Secrets User** role assignment scoped to `kv-team-alpha-dev`

Add a comment explaining what annotation must be on the ServiceAccount for the binding to work.

> Place your file at `part1/workload-identity.bicep`.

---

## Part 2 — CI Pipeline: Azure DevOps

A starter pipeline is provided at [`part2/pipeline.yml`](./part2/pipeline.yml). It has a skeleton structure but is missing several key steps. Complete it.

### Task 2.1 — Complete the Pipeline

The pipeline must cover the full CI flow for a microservice:

1. **Build & test** — build the Docker image and run unit tests inside the container (or as a separate step)
2. **Image scan** — scan the built image for vulnerabilities using a tool of your choice (e.g. Trivy, Grype, or an Azure Defender task). The pipeline should **fail** if critical vulnerabilities are found.
3. **Push to registry** — push the image to `dawnhealthacr.azurecr.io` tagged with the build number and the full Git commit SHA
4. **Update the GitOps repository** — after a successful push to the `main` branch, update the image tag in the GitOps config to trigger an ArgoCD sync for the `dev` environment (see Part 3 for what that config looks like)

Fill in the marked `# TODO` sections in [`part2/pipeline.yml`](./part2/pipeline.yml).

### Task 2.2 — Pipeline Design Decisions (Written)

In [`SUBMISSION.md`](./SUBMISSION.md#22-pipeline-design-decisions), briefly answer:

- How would you structure the pipeline differently for `feature branches` vs `main`? (e.g. skip the push and GitOps update on feature branches)
- Where would you add a manual approval gate, and why only there?
- How do you ensure the **same image digest** is deployed through dev → staging → prod rather than rebuilt?

---

## Part 3 — GitOps Delivery: ArgoCD

Dawn Health uses ArgoCD to deploy to AKS. Changes to a GitOps repository are the **only** way services get deployed — no `kubectl apply` directly.

A starter ArgoCD Application manifest is provided at [`part3/argocd-application.yaml`](./part3/argocd-application.yaml).

### Task 3.1 — Complete the ArgoCD Application

Fill in the marked `# TODO` sections in the manifest to define a working ArgoCD Application for the `team-alpha-backend` service in the `dev` environment. The application should:

- Point at a path in this repository (or your fork) where the Kubernetes manifests live
- Target the `team-alpha` namespace
- Be configured to sync automatically when Git changes, but only after a brief delay (to allow for review of unexpected changes)
- Prune resources that are removed from Git

### Task 3.2 — Promotion Model (Written)

In [`SUBMISSION.md`](./SUBMISSION.md#32-promotion-model), describe how a release flows from **dev → staging → production** in this GitOps model:

- What does the Azure DevOps pipeline from Part 2 do to trigger a deployment to `dev`?
- What triggers promotion to `staging`, and then to `production`?
- What is the benefit of this model over having the pipeline `kubectl apply` directly?

---

## Part 4 — Container Security & Image Hardening

A starter `Dockerfile` is provided at [`part4/Dockerfile`](./part4/Dockerfile). It builds a Node.js backend service but was written quickly and has several security problems.

### Task 4.1 — Harden the Dockerfile

Review the starter file and produce a hardened version. You can replace it in place or produce `part4/Dockerfile.hardened` — your choice.

Think about:

- Base image selection, size, and digest pinning
- Separation of build-time and runtime dependencies using a multi-stage build
- What gets copied into the final image — and what must not
- Secrets and environment variables
- The user the process runs as

> You do not need a working Node.js application. We are assessing your knowledge of Dockerfile best practices, not the app itself. Add comments explaining your reasoning where it is not obvious.

### Task 4.2 — Kubernetes Runtime Security (Written)

A hardened image is one layer of defence. In [`SUBMISSION.md`](./SUBMISSION.md#42-kubernetes-runtime-security), describe the Kubernetes-side controls you would add to ensure the container runs securely even if the image is not perfectly hardened. Cover at minimum:

- `securityContext` settings at the pod and container level (specific fields and values you would set)
- What Linux capabilities you would drop and why
- How you would enforce these controls consistently across all teams on the shared cluster

### Task 4.3 — Supply Chain for a Regulated Environment (Written)

Dawn Health is classified as a SaMD company. In [`SUBMISSION.md`](./SUBMISSION.md#43-supply-chain-for-a-regulated-environment), briefly answer:

- How does image scanning fit into a compliance-grade CI/CD pipeline — where in the pipeline does it go, and what should happen on a failure?
- What would you add beyond scanning (e.g. SBOMs, image signing, provenance attestation) and what problem does each solve in a regulated context?

---

## Part 5 — Observability: Alerting & Instrumentation

The `team-alpha` backend is now running in AKS. The platform uses the **LGTM stack** (Loki, Grafana, Tempo, Mimir) with the Prometheus operator for alert rule management.

Starter files are provided in `part5/`.

### Task 5.1 — ServiceMonitor

Complete the starter [`part5/servicemonitor.yaml`](./part5/servicemonitor.yaml) to configure scraping of metrics from the `team-alpha-backend` pods.

The backend service:
- Is labelled `app: team-alpha-backend`
- Exposes metrics at port `8080`, path `/metrics`

Make sure the selector correctly targets the right pods and the scrape interval is sensible for a production service.

### Task 5.2 — Alert Rules

Write at least **two meaningful alert rules** as a `PrometheusRule` in [`part5/alert-rule.yaml`](./part5/alert-rule.yaml) for the `team-alpha-backend` service.

Choose rules that would be genuinely actionable in production. Avoid alerts that fire on transient noise. Each rule must include an `action` annotation with the first steps an on-call engineer should take.

### Task 5.3 — SLIs, SLOs, and Error Budget (Written)

In [`SUBMISSION.md`](./SUBMISSION.md#53-slis-slos-and-error-budget):

- What SLIs (Service Level Indicators) would you define for a patient-facing API at Dawn Health?
- What initial SLO targets would you set, and how would you use error budget to guide release decisions?
- How would you ensure SLO burn-rate alerts are actionable rather than just noise?

---

## Part 6 — Operational Scenarios

Bullet points are fine. Answer in [`SUBMISSION.md`](./SUBMISSION.md#part-6--operational-scenarios).

### 6.1 — Investigating a Timeout

The `team-alpha` backend API is intermittently returning HTTP 504s. The pods are running and not crashing. You have access to the full LGTM stack.

Walk through your investigation — **be specific about which tool you open first, what query or panel you look at, and what you are trying to confirm or rule out at each step.** Assume you have never seen this service before.

### 6.2 — Bad Deployment in Production

A deployment went out at 14:00. At 14:02, error rates jump from 0.1% to 12%. You need to act.

In a GitOps model, describe your rollback procedure — what you do, in what order, and how you communicate it to the team. Aim for time-to-recovery under 5 minutes.

### 6.3 — Certificate Expiry at 3am *(Optional)*

You receive a PagerDuty alert at 03:00: a TLS certificate for `team-alpha-backend` expires in 2 hours and cert-manager has not renewed it automatically.

Walk through your diagnosis and resolution. Include any `kubectl` commands or queries you would run.

---

## Starter Files

| File | Purpose |
|------|---------|
| [`part1/namespace.yaml`](./part1/namespace.yaml) | Partial K8s manifests — complete and extend |
| [`part2/pipeline.yml`](./part2/pipeline.yml) | Partial Azure DevOps pipeline — fill in the TODOs |
| [`part3/argocd-application.yaml`](./part3/argocd-application.yaml) | Partial ArgoCD Application — fill in the TODOs |
| [`part4/Dockerfile`](./part4/Dockerfile) | Insecure Dockerfile — review and harden |
| [`part5/servicemonitor.yaml`](./part5/servicemonitor.yaml) | Partial ServiceMonitor — fill in the TODOs |
| [`part5/alert-rule.yaml`](./part5/alert-rule.yaml) | Partial PrometheusRule — add your alert rules |

---

## Suggested Final Structure

```
your-fork/
├── README.md
├── SUBMISSION.md
├── part1/
│   ├── namespace.yaml          # Namespace, Role, RoleBinding, ServiceAccount
│   └── workload-identity.bicep # Managed Identity, federated credential, KV RBAC
├── part2/
│   └── pipeline.yml            # Completed Azure DevOps CI pipeline
├── part3/
│   └── argocd-application.yaml # Completed ArgoCD Application manifest
├── part4/
│   └── Dockerfile              # Hardened Dockerfile (replace or alongside original)
├── part5/
│   ├── servicemonitor.yaml     # Completed ServiceMonitor
│   └── alert-rule.yaml         # PrometheusRule with your alert rules
└── diagrams/                   # Optional
```

---

## Questions?

Reach out to any of the team with questions:

- **Faisal Jarkass** — [fja@dawnhealth.com](mailto:fja@dawnhealth.com)
- **Robbie Dyer** — [rdy@dawnhealth.com](mailto:rdy@dawnhealth.com)
- **Aliaksandr Haroshka** — [ali@dawnhealth.com](mailto:ali@dawnhealth.com)

---

*Good luck — we look forward to reviewing your work and discussing it with you.*
