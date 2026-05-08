# Submission — Dawn Health SRE Technical Assessment

> Fill in this file with your written answers. For code and manifest tasks, your files in the `part*/` directories are the answer — you do not need to repeat code here.

---

## Part 1 — SLOs & Burn-Rate Alerting

### 1.1 — Recording Rules

> No written answer needed — your completed [`part1/recording-rules.yaml`](./part1/recording-rules.yaml) is the answer.

### 1.2 — Multi-Window Burn-Rate Alerts

> No written answer needed — your completed [`part1/slo-alerts.yaml`](./part1/slo-alerts.yaml) is the answer.

### 1.3 — SLO Policy

> What SLO target would you propose for a patient-facing API, and how would you justify it to product stakeholders who want to move fast? How would you use the error budget to govern releases? What happens when it is exhausted?

_Your answer here._

---

## Part 2 — Incident Response

### 2.1 — Runbook

> No written answer needed — your completed [`part2/runbook.md`](./part2/runbook.md) is the answer.

### 2.2 — Postmortem

> Write a postmortem for the incident described in the README. Cover: timeline, root cause, contributing factors, impact, and at least three action items.

**Timeline**

| Time | Event |
|------|-------|
| | |
| | |
| | |

**Root Cause**

_Your root cause here._

**Contributing Factors**

_Your contributing factors here._

**Impact**

_Your impact assessment here._

**Action Items**

| # | Action | Owner | Due |
|---|--------|-------|-----|
| 1 | | | |
| 2 | | | |
| 3 | | | |

---

## Part 3 — Reliability Engineering

### 3.1 — HPA and PodDisruptionBudget

> No written answer needed — your completed [`part3/reliability.yaml`](./part3/reliability.yaml) is the answer.

### 3.2 — Resource Strategy

> How would you approach setting requests/limits for an unknown service? What are the risks at each extreme? How would you enforce resource quotas across teams?

_Your answer here._

### 3.3 — Capacity Planning

> The business expects a 3x traffic increase over 6 weeks. How do you assess readiness, what do you monitor, and what do you change proactively vs. reactively?

_Your answer here._

---

## Part 4 — Observability Investigation

### 4.1 — Queries

> No written answer needed — your completed [`part4/queries.md`](./part4/queries.md) is the answer.

### 4.2 — Dashboard Strategy

> Describe 3–4 dashboards you would maintain as a platform SRE. How would you structure them for self-service? What is the difference between a triage and a deep-dive dashboard?

_Your answer here._

---

## Part 5 — Toil & Automation

### 5.1 — Identify and Prioritise Toil

> Describe three examples of toil on a Kubernetes platform team. For each: what makes it toil, how you measure it, and how you would prioritise it.

**Example 1**

_Your answer here._

**Example 2**

_Your answer here._

**Example 3**

_Your answer here._

### 5.2 — Implement the Automation

> No written answer needed — your completed [`part5/cronjob.yaml`](./part5/cronjob.yaml) is the answer.

---

## Part 6 — Operational Scenarios

### 6.1 — Cascading Failure

> Walk through your investigation of the cascading failure described in the README. How do you identify the root cause is Service B — not Service A — and what do you do about it?

_Your answer here._

### 6.2 — On-Call Handoff During an Active Incident

> How do you hand off a P1 incident mid-investigation? What do you communicate, in what format?

_Your answer here._

### 6.3 — Noisy Alerting *(Optional)*

> How would you audit and reduce 40–60 weekly alert notifications without reducing coverage for real incidents?

_Your answer here._

---

## Anything Else?

> Note any tasks you skipped and how you would have approached them, assumptions you made, or anything else you would like the reviewers to know.

_Your answer here._
