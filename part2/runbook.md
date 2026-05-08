# Runbook — team-alpha-backend: Memory Exhaustion / OOMKill

## Overview

**Alert**: `ContainerMemoryUsageCritical`
**Severity**: Critical
**Service**: `team-alpha-backend` in namespace `team-alpha`
**Typical cause**: Memory leak in the application, or a sudden traffic spike exceeding configured resource limits

---

## Triage (first 2 minutes)

<!-- TODO: List the first 3–4 kubectl or Grafana commands you run immediately
     after the alert fires. What are you trying to confirm, and why does the
     order matter? Be specific — include actual command syntax. -->

_Your triage steps here._

---

## Diagnosis

### Is this a memory leak or a traffic spike?

<!-- TODO: Describe how you would distinguish between a gradual memory leak
     (container memory growing steadily over hours) and a sudden spike caused
     by an unexpected traffic increase. What metric query or Grafana panel would
     you open first, and what pattern in the data would confirm each hypothesis? -->

_Your approach here._

### Is the container OOMKilling?

<!-- TODO: Write the exact kubectl command to check whether a container has been
     OOMKilled recently. What field in the output tells you this, and what does
     it look like when OOMKill has occurred vs. a normal restart? -->

_Your command and explanation here._

### Is this isolated to one pod or affecting the node?

<!-- TODO: How would you check whether the memory pressure is isolated to a
     single pod, or whether it is affecting the node and potentially impacting
     other teams on the shared cluster? What would escalation look like if it
     is node-level? -->

_Your approach here._

---

## Resolution

### Immediate mitigation

<!-- TODO: What is the fastest safe action to restore service availability?
     Consider: rollback, pod restart, horizontal scaling, traffic shedding.
     In a GitOps model, what is the correct way to do each of these? -->

_Your steps here._

### Root cause fix

<!-- TODO: Once service is restored, what longer-term fix would you raise?
     How would you confirm the fix actually resolved the leak / spike and did
     not just defer it? -->

_Your steps here._

---

## Escalation

| Condition | Escalate to |
|-----------|-------------|
| <!-- TODO: describe the condition --> | <!-- TODO: who and how --> |
| <!-- TODO: describe the condition --> | <!-- TODO: who and how --> |

---

## Prevention

<!-- TODO: Recommend at least two changes — to resource limits, alert thresholds,
     application instrumentation, or deployment process — that would either prevent
     this incident or detect it earlier. Be specific about what you would change
     and why. -->

_Your recommendations here._

---

## Related Grafana panels and queries

<!-- TODO: List 2–3 Grafana panels or Loki/Mimir queries that would provide
     useful context during this incident. Include the panel name or query
     syntax so an engineer can find them quickly under pressure. -->

_Your links and queries here._
