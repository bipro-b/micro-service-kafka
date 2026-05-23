# Data Collection — Kubernetes Reliability and Cost-Aware Auto-Scaling

Research phase: **Data Collection** (5 experiment runs × 3 workload patterns)

## Directory Layout

```
data-collection/
├── scripts/
│   ├── 00-preflight.sh          # verify cluster is ready
│   ├── 01-baseline.sh           # 10-min quiet baseline
│   ├── 02-spike-experiment.sh   # spike pattern runner (run 5×)
│   ├── 03-ramp-experiment.sh    # ramp pattern runner (run 5×)
│   ├── 04-burst-experiment.sh   # burst pattern runner (run 5×)
│   ├── 05-export-metrics.sh     # pull Prometheus → CSV
│   └── 06-cost-estimate.sh      # compute AWS cost per run
├── logs/
│   ├── experiment-log-template.md
│   └── run-NNN.md               # one file per experiment run
├── raw-data/
│   ├── baseline/
│   ├── spike/   run-1/ … run-5/
│   ├── ramp/    run-1/ … run-5/
│   └── burst/   run-1/ … run-5/
└── README.md (this file)
```

## Metrics Captured Per Run

| Metric              | Source                  | PromQL key                        |
|---------------------|-------------------------|-----------------------------------|
| p95 Latency (ms)    | prom-client histogram   | `http_request_duration_ms_bucket` |
| p50 Latency (ms)    | prom-client histogram   | `http_request_duration_ms_bucket` |
| Request rate (rps)  | prom-client counter     | `http_requests_total`             |
| Error rate (%)      | prom-client counter     | `http_requests_total{status=5xx}` |
| Pod replicas        | kube-state-metrics      | `kube_deployment_status_replicas` |
| HPA desired         | kube-state-metrics      | `kube_horizontalpodautoscaler_*`  |
| CPU utilisation (%) | cAdvisor                | `container_cpu_usage_seconds`     |
| Scale-up time (s)   | k8s events              | `kubectl get events`              |
| Cost estimate ($)   | node CPU × EC2 price    | calculated in 06-cost-estimate.sh |

## Experiment Profiles

| Pattern | CONCURRENCY | INTERVAL_MS | Duration | What it tests           |
|---------|-------------|-------------|----------|-------------------------|
| Spike   | 3 → 20      | 2000 → 200  | 20 min   | Sudden overload         |
| Ramp    | 3 → 20 step | 2000 → 200  | 20 min   | Gradual growth          |
| Burst   | 3 ↔ 20      | 2000 ↔ 200  | 20 min   | Periodic traffic spikes |

## Execution Order

```
# Each session:
bash scripts/00-preflight.sh          # must PASS before any experiment
bash scripts/01-baseline.sh           # once only (first session)

# Spike — run 5 separate times, each ≥ 20 minutes apart to let HPA cool down
RUN=1 bash scripts/02-spike-experiment.sh
RUN=2 bash scripts/02-spike-experiment.sh
... (× 5)

# Ramp — same cadence
RUN=1 bash scripts/03-ramp-experiment.sh
...

# Burst — same cadence
RUN=1 bash scripts/04-burst-experiment.sh
...

# After ALL runs complete
bash scripts/05-export-metrics.sh     # exports CSV per run
bash scripts/06-cost-estimate.sh      # computes $/run table
```

## Naming Convention

Every raw data file: `raw-data/<pattern>/run-<N>/<timestamp>_<metric>.csv`
Every log file:      `logs/run-<NNN>-<pattern>.md`
