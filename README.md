# Dawn Health — Site Reliability Engineer Technical Assessment

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
| 1 | **Reliability thinking** — are your SLOs, alerts, and runbooks genuinely actionable in a regulated environment |
| 2 | **Depth of understanding** — do your answers show you understand *why*, not just *what* |
| 3 | **Systems thinking** — can you trace failure modes across application, infrastructure, and platform layers |
| 4 | **Git history** — quality and continuity of your commits |
| 5 | **Pragmatism** — sensible defaults, not over-engineered solutions |
| 6 | **Communication** — are your runbook and postmortem clear enough for a teammate paged at 3am |

---

## Solution Context

Dawn Health operates a **shared multi-tenant AKS cluster** that hosts multiple product teams and Life Sciences partners. We handle highly sensitive patient data under SaMD (Software as a Medical Device) regulations. Reliability is not just an engineering concern — it has direct patient safety implications.

The platform must deliver:

- **Measurable reliability** — SLOs backed by real SLIs, with error budget policies that govern release decisions
- **Fast, safe incident response** — runbooks that reduce MTTR, postmortems that prevent recurrence
- **Proactive capacity management** — failures from resource exhaustion must be caught before they become incidents
- **Minimal operational toil** — manual, repetitive work must be systematically identified and eliminated

The observability stack is **LGTM**: Loki (logs), Grafana (dashboards), Tempo (distributed traces), Mimir (metrics and alerting, Prometheus-compatible).

### Tech Stack

| Layer | Technology |
|-------|------------|
| Cloud Provider | Microsoft Azure |
| Orchestration | AKS (Azure Kubernetes Service) |
| Metrics & Alerting | Mimir (Prometheus-compatible) |
| Logs | Loki |
| Traces | Tempo |
| Dashboards | Grafana |
| GitOps | ArgoCD |

---

## Part 1 — SLOs & Burn-Rate Alerting

Reliable services start with precise definitions of reliability. The `team-alpha-backend` is a patient-facing REST API. Before you can alert meaningfully, you need recording rules to pre-aggregate SLI metrics, and burn-rate alerts to tell you when the SLO is in danger.

Starter files are provided in `part1/`.

### Task 1.1 — Recording Rules

Complete the PromQL expressions in [`part1/recording-rules.yaml`](./part1/recording-rules.yaml) to produce:

1. A **request rate** recording rule — total requests per second, labelled by status code
2. An **error ratio** recording rule — proportion of 5xx responses to total requests
3. A **p95 latency** recording rule — 95th percentile request duration

The backend exposes standard Prometheus histogram metrics: `http_requests_total` (labelled with `job`, `namespace`, `status_code`) and `http_request_duration_seconds`.

> Complete the `expr` fields in [`part1/recording-rules.yaml`](./part1/recording-rules.yaml).

### Task 1.2 — Multi-Window Burn-Rate Alerts

The SLO target for `team-alpha-backend` is **99.9% request success rate** over a rolling 28-day window.

Complete the alert expressions in [`part1/slo-alerts.yaml`](./part1/slo-alerts.yaml) using the multi-window, multi-burn-rate approach from the Google SRE Workbook. The starter file already defines the alert structure — fill in the `expr` fields and the `action` annotations.

> Complete the `TODO` sections in [`part1/slo-alerts.yaml`](./part1/slo-alerts.yaml).

### Task 1.3 — SLO Policy (Written)

In [`SUBMISSION.md`](./SUBMISSION.md#13-slo-policy):

- What SLO target would you propose for a patient-facing API, and how would you justify it to product stakeholders who want to move fast?
- How would you use the error budget to decide whether a release should proceed?
- What should happen when the error budget is exhausted?

---

## Part 2 — Incident Response

Good runbooks and postmortems are force multipliers: they reduce MTTR, enable less experienced engineers to respond confidently, and prevent recurrence.

A starter runbook is provided at [`part2/runbook.md`](./part2/runbook.md).

### Task 2.1 — Complete the Runbook

The starter file provides the structure for a runbook responding to a memory exhaustion event on `team-alpha-backend`. Fill in the `TODO` sections:

- **Triage** — the first commands you run to confirm scope and impact
- **Diagnosis** — how you distinguish a memory leak from a traffic spike; how to check for OOMKills
- **Resolution** — immediate mitigation and longer-term fix
- **Escalation** — when and to whom
- **Prevention** — what you would add to prevent recurrence

> Complete [`part2/runbook.md`](./part2/runbook.md).

### Task 2.2 — Postmortem (Written)

In [`SUBMISSION.md`](./SUBMISSION.md#22-postmortem), write a postmortem for the following incident:

> **Incident summary**: At 02:14, `team-alpha-backend` began returning HTTP 503s. By 02:19, 40% of requests were failing. Root cause: a memory leak introduced in a release at 01:55 caused all three pods to OOMKill within 4 minutes of each other. The Deployment's `livenessProbe` restarted each pod, but the leak caused them to fail again within 90 seconds. The service was fully restored at 02:47 by rolling back via ArgoCD. Total impact: 33 minutes of degraded service.

Your postmortem should cover: timeline, root cause, contributing factors, impact, and at least three action items.

---

## Part 3 — Reliability Engineering

Runbooks resolve incidents. Good Kubernetes configuration reduces their frequency.

A starter deployment manifest is provided at [`part3/reliability.yaml`](./part3/reliability.yaml).

### Task 3.1 — HPA and PodDisruptionBudget

The `team-alpha-backend` Deployment is currently static at 2 replicas with no disruption protection. Add to [`part3/reliability.yaml`](./part3/reliability.yaml):

1. A **HorizontalPodAutoscaler** that scales the Deployment between 2 and 10 replicas based on CPU (target: 70%) and memory utilisation (target: 80%)
2. A **PodDisruptionBudget** that ensures at least 1 pod is always available during voluntary disruptions (e.g. node drain, cluster upgrades)

### Task 3.2 — Resource Strategy (Written)

In [`SUBMISSION.md`](./SUBMISSION.md#32-resource-strategy):

- How would you approach setting CPU and memory `requests` and `limits` for a service you have never seen before?
- What is the risk of setting limits too low? Too high? On a shared multi-tenant cluster?
- How would you enforce resource quotas consistently across all teams?

### Task 3.3 — Capacity Planning (Written)

In [`SUBMISSION.md`](./SUBMISSION.md#33-capacity-planning):

> The business expects a 3x traffic increase over the next 6 weeks as a new partner integration goes live.

- How would you assess whether the platform can absorb this?
- What signals would you monitor in the run-up?
- What would you change proactively vs. reactively?

---

## Part 4 — Observability Investigation

Understanding a system under failure requires fluency with all three observability pillars: metrics, logs, and traces.

A starter investigation document is provided at [`part4/queries.md`](./part4/queries.md).

### Task 4.1 — Write the Queries

The file describes a live incident scenario and asks you to write PromQL and LogQL queries to investigate it. Fill in the `TODO` blocks for each question.

> Complete the query blocks in [`part4/queries.md`](./part4/queries.md).

### Task 4.2 — Dashboard Strategy (Written)

In [`SUBMISSION.md`](./SUBMISSION.md#42-dashboard-strategy):

- What dashboards would you maintain as a platform SRE for a multi-tenant cluster? Describe 3–4 and what they show.
- How would you structure dashboards so that a product team can investigate their own service without needing to ask the platform team?
- What is the difference between a triage dashboard and a deep-dive dashboard, and when do you use each?

---

## Part 5 — Toil & Automation

SREs are responsible for reducing the operational burden on the team — including their own.

### Task 5.1 — Identify and Prioritise Toil (Written)

In [`SUBMISSION.md`](./SUBMISSION.md#51-identify-and-prioritise-toil):

Describe **three examples of toil** you would expect to find on a Kubernetes platform team running a shared multi-tenant cluster. For each one:

- What makes it toil (rather than valuable engineering work)?
- How would you measure how much time it consumes?
- How would you prioritise which to automate first?

### Task 5.2 — Implement the Automation

A starter CronJob manifest is provided at [`part5/cronjob.yaml`](./part5/cronjob.yaml). Complete it to automate the cleanup of stale pods and completed Jobs across the cluster.

You will also need to add the required `ServiceAccount`, `ClusterRole`, and `ClusterRoleBinding` — applying the principle of least privilege.

> Complete [`part5/cronjob.yaml`](./part5/cronjob.yaml).

---

## Part 6 — Operational Scenarios

Bullet points are fine. Answer in [`SUBMISSION.md`](./SUBMISSION.md#part-6--operational-scenarios).

### 6.1 — Cascading Failure

Service A depends on Service B. Service B becomes slow (p99 latency 8s, normally 200ms) but does not return errors. Service A's thread pool fills up waiting for Service B responses. Service A starts returning 503s to its callers.

Walk through your investigation from the first alert. How do you identify the root cause is Service B — not Service A — and what do you do about it?

### 6.2 — On-Call Handoff During an Active Incident

You are 30 minutes into a P1 incident when your shift ends. The issue is partially diagnosed but not resolved.

How do you hand off? What do you communicate, in what format, to ensure the incoming engineer can pick up without losing ground?

### 6.3 — Noisy Alerting *(Optional)*

The team is receiving 40–60 alert notifications per week, most of which result in no action. Engineers are beginning to ignore pages.

How would you audit and reduce alert noise without reducing coverage for real incidents? Walk through your approach.

---

## Starter Files

| File | Purpose |
|------|---------|
| [`part1/recording-rules.yaml`](./part1/recording-rules.yaml) | Partial PrometheusRule — complete the recording rule expressions |
| [`part1/slo-alerts.yaml`](./part1/slo-alerts.yaml) | Partial PrometheusRule — complete the multi-window burn-rate alerts |
| [`part2/runbook.md`](./part2/runbook.md) | Partial runbook — complete the triage, diagnosis, and resolution steps |
| [`part3/reliability.yaml`](./part3/reliability.yaml) | Partial K8s manifests — add HPA and PodDisruptionBudget |
| [`part4/queries.md`](./part4/queries.md) | Investigation scenario — write the PromQL and LogQL queries |
| [`part5/cronjob.yaml`](./part5/cronjob.yaml) | Partial CronJob — complete the cleanup automation and RBAC |

---

## Suggested Final Structure

```
your-fork/
├── README.md
├── SUBMISSION.md
├── part1/
│   ├── recording-rules.yaml    # Completed recording rules
│   └── slo-alerts.yaml         # Completed multi-window burn-rate alerts
├── part2/
│   └── runbook.md              # Completed runbook
├── part3/
│   └── reliability.yaml        # Deployment + HPA + PodDisruptionBudget
├── part4/
│   └── queries.md              # PromQL and LogQL queries for the scenario
├── part5/
│   └── cronjob.yaml            # Cleanup CronJob + ServiceAccount + RBAC
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
