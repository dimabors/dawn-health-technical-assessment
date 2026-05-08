# Part 4.1 — Observability Investigation

## Scenario

The on-call engineer is paged at 02:30: the error rate on `team-alpha-backend` has
risen to 8% over the past 10 minutes. The pods are running. No deployment has
occurred in the last 4 hours.

You have access to:

- **Grafana / Mimir** — Prometheus-compatible query interface (metrics)
- **Loki** — LogQL query interface (logs)
- **Tempo** — trace search and waterfall view
- **kubectl** on the cluster

---

## Task A — Metrics Triage (PromQL)

Write PromQL queries to answer each question. Add your query below each prompt.

### A1. What is the current error rate for `team-alpha-backend`?

```promql
# TODO: Write a PromQL expression showing the 5xx error rate as a percentage
# of total requests, over the last 5 minutes.
# Scope to the team-alpha namespace.
```

### A2. Is the error rate affecting all pods or just one?

```promql
# TODO: Write a PromQL expression showing error rates broken down by pod.
# This helps determine whether the issue is isolated or cluster-wide.
```

### A3. Has memory or CPU usage changed in the last hour?

```promql
# TODO: Write two PromQL expressions:
#   1. Container memory working set bytes for team-alpha-backend pods
#   2. CPU usage rate for team-alpha-backend pods
# Use a time range that shows the trend over the past hour.
```

### A4. Are request latencies elevated?

```promql
# TODO: Write a PromQL expression for the p95 request latency of team-alpha-backend
# over the last 5 minutes. Compare this to what you would expect normally.
```

---

## Task B — Log Investigation (LogQL)

Write LogQL queries to answer each question.

### B1. Show all error-level logs from `team-alpha-backend` in the last 15 minutes

```logql
# TODO: Write a LogQL query streaming error-level log lines from
# team-alpha-backend pods in the team-alpha namespace.
# Consider both structured (JSON) and unstructured log formats.
```

### B2. Count errors by message pattern to identify the most common failure

```logql
# TODO: Write a LogQL metric query that counts log lines containing "error" or "ERROR"
# and groups them by a relevant parsed field (e.g. error message, endpoint, status code).
# Use count_over_time or a log metric aggregation.
```

### B3. Is there a timing pattern — are errors arriving in bursts or steadily?

```logql
# TODO: Write a LogQL rate query to plot error log frequency over time.
# A burst pattern suggests a different root cause than a steady increase.
```

---

## Task C — Connecting the Dots

<!-- TODO: Based on what you found (or hypothetically found) in Tasks A and B,
     describe how you would use Tempo distributed traces to narrow down the root cause.

     Specifically:
     - What would you search for in Tempo to find the failing requests?
     - What would you look for in the trace waterfall to identify where time is being lost?
     - If the error is originating in a downstream dependency, what would that look like
       in the trace vs. originating in team-alpha-backend itself?
-->

_Your answer here._
