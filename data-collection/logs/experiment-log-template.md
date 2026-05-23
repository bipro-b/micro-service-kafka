# Experiment Log — [PATTERN] Run #[N]

**Date:** YYYY-MM-DD  
**Time start:** HH:MM  
**Time end:** HH:MM  
**Pattern:** spike / ramp / burst  
**Run number:** 1 / 2 / 3 / 4 / 5  
**Experimenter:** Trisha  
**Cluster:** EKS mega (us-west-2)

---

## Pre-Experiment State

| Item                    | Value |
|-------------------------|-------|
| order-service pods       |       |
| api-gateway pods         |       |
| product-service pods     |       |
| Load generator baseline  | CONCURRENCY=3, INTERVAL_MS=2000 |
| Prometheus reachable?    | yes / no |

---

## Load Generator Settings Used

| Phase        | CONCURRENCY | INTERVAL_MS | Duration |
|--------------|-------------|-------------|----------|
| Warmup       |             |             |          |
| Peak load    |             |             |          |
| Cool-down    |             |             |          |

---

## HPA Observations (fill from raw CSV or kubectl watch)

| Time (HH:MM) | order-service replicas | api-gateway replicas | Notes |
|--------------|------------------------|----------------------|-------|
|              |                        |                      |       |
|              |                        |                      |       |
|              |                        |                      |       |

**Scale-up time** (load applied → first new pod Ready):  ______ seconds  
**Scale-down time** (load removed → pods reduced):       ______ seconds

---

## Metric Readings (Prometheus / Grafana)

| Metric                       | Baseline | Peak load | Post cool-down |
|------------------------------|----------|-----------|----------------|
| p95 Latency (ms)             |          |           |                |
| p50 Latency (ms)             |          |           |                |
| Request rate (rps)           |          |           |                |
| Error rate (%)               |          |           |                |
| order-service CPU (%)        |          |           |                |
| order-service replicas       |          |           |                |

---

## Failure Events

List any 5xx errors, pod restarts, OOMKills, or timeout events observed:

- [ ] None
- [ ] _________________________________________________________________
- [ ] _________________________________________________________________

---

## Cost Estimate

| Item                       | Value |
|----------------------------|-------|
| Peak replicas (order-svc)  |       |
| Experiment duration (min)  |       |
| Estimated cost (USD)       |       |

---

## Observations (paper notes — "We observe that…")

> Write as if drafting sentences for the paper's results section.

1. We observe that …
2. Contrary to expectation …
3. A surprising behavior was …
4. Trade-off noted: …

---

## What to Recheck / Fix Before Next Run

- [ ] 
- [ ] 

---

## Raw Data Files

| File | Path |
|------|------|
| HPA poll CSV   | `raw-data/[pattern]/run-[N]/*_hpa_poll.csv` |
| Scale events   | `raw-data/[pattern]/run-[N]/*_scale_events.csv` |
| Metric CSVs    | `raw-data/[pattern]/run-[N]/*.csv` |
| Event log      | `raw-data/[pattern]/run-[N]/*_events.txt` |
