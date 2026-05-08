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

_Your answer here._

---

## Part 2 — CI Pipeline: Azure DevOps

### 2.1 Completed Pipeline

> No written answer needed — your completed `part2/pipeline.yml` is the answer.

---

### 2.2 Pipeline Design Decisions

> How would you structure the pipeline differently for feature branches vs main?

_Your answer here._

> Where would you add a manual approval gate, and why only there?

_Your answer here._

> How do you ensure the same image digest is deployed through dev → staging → prod rather than rebuilt?

_Your answer here._

---

## Part 3 — GitOps Delivery: ArgoCD

### 3.1 ArgoCD Application

> No written answer needed — your completed `part3/argocd-application.yaml` is the answer.

---

### 3.2 Promotion Model

> What does the Azure DevOps pipeline do to trigger a deployment to dev?

_Your answer here._

> What triggers promotion to staging, and then to production?

_Your answer here._

> What is the benefit of this model over having the pipeline kubectl apply directly?

_Your answer here._

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

_Your answer here._

---

### 4.3 Supply Chain for a Regulated Environment

> How does image scanning fit into a compliance-grade pipeline?

_Your answer here._

> What would you add beyond scanning (SBOMs, image signing, provenance attestation) and what problem does each solve?

_Your answer here._

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
