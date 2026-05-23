# Step-by-Step Data Collection Guide
# Kubernetes Reliability and Cost-Aware Auto-Scaling

**Total runs required:** 15 (5× spike + 5× ramp + 5× burst)  
**Time per run:** ~25 minutes experiment + 5 min cooldown  
**Estimated total:** ~12 hours across multiple sessions

---

## BEFORE YOU START (one-time setup)

### 1. Verify AWS/kubectl access
```bash
aws sts get-caller-identity
kubectl get nodes
kubectl get pods -n mega
```

### 2. Pre-flight check
```bash
cd data-collection
bash scripts/00-preflight.sh
```
All items must show `[OK]`. Fix any `[FAIL]` before continuing.

### 3. Run baseline (once only)
```bash
bash scripts/01-baseline.sh
```
This sets the 10-minute quiet-traffic baseline. Outputs go to `raw-data/baseline/`.

### 4. Open Prometheus port-forward (keep running in a separate terminal)
```bash
kubectl port-forward svc/stable-kube-prometheus-st-prometheus \
  -n prometheus 9090:9090
```
Visit http://localhost:9090 to confirm it works.

### 5. Open Grafana (optional but useful for screenshots)
```bash
kubectl port-forward svc/stable-grafana -n prometheus 3000:80
```
Visit http://localhost:3000 (default: admin / prom-operator)

---

## PART A — SPIKE EXPERIMENTS (5 runs)

**What it tests:** Sudden 10× traffic surge → HPA scale-up → load drops → scale-down  
**Key measurement:** Scale-up time (seconds from spike to new pod Ready)

### Run each spike experiment (repeat 5×, wait 5 min between runs):

```bash
# Run 1
RUN=1 bash scripts/02-spike-experiment.sh

# ← wait 5 minutes for HPA stabilisation ←

# Run 2
RUN=2 bash scripts/02-spike-experiment.sh

# … repeat for RUN=3, RUN=4, RUN=5
```

### After each spike run:
1. Copy `logs/experiment-log-template.md` → `logs/run-spike-N.md`
2. Fill in the observation table (scale-up time, peak replicas, p95 latency, errors)
3. Take a Grafana screenshot of the HPA replica graph and latency panel

---

## PART B — RAMP EXPERIMENTS (5 runs)

**What it tests:** Gradual 5-step load increase → at what load does HPA first trigger?  
**Key measurement:** Threshold replica count, latency degradation curve

```bash
RUN=1 bash scripts/03-ramp-experiment.sh
# wait 5 min, repeat for RUN=2 … RUN=5
```

### After each ramp run:
1. Copy template → `logs/run-ramp-N.md`
2. Record: at which CONCURRENCY step did HPA first add a pod?
3. Note the latency at each step (read from Prometheus or Grafana)

---

## PART C — BURST EXPERIMENTS (5 runs)

**What it tests:** 4 cycles of HIGH/LOW load → does HPA react to each burst?  
**Key measurement:** Does HPA over/under-react? Does scaleDown stabilisation window (180s) match burst period?

```bash
RUN=1 bash scripts/04-burst-experiment.sh
# wait 5 min, repeat for RUN=2 … RUN=5
```

### After each burst run:
1. Copy template → `logs/run-burst-N.md`
2. Record per-cycle: did pod count change on HIGH? did it reduce on LOW?
3. Note any oscillation or flapping behaviour

---

## PART D — EXPORT RAW DATA TO CSV

After all 15 runs are done, export Prometheus time-series data:

```bash
# For each run, set the correct timestamps and export
# Example — spike run 1 (timestamps from your experiment log):
PATTERN=spike RUN=1 \
  START_TS=$(date -d "2026-MM-DD HH:MM" +%s) \
  END_TS=$(date   -d "2026-MM-DD HH:MM" +%s) \
  bash scripts/05-export-metrics.sh
```

Repeat for each of the 15 runs. CSVs land in `raw-data/<pattern>/run-<N>/`.

---

## PART E — COST ESTIMATE

```bash
bash scripts/06-cost-estimate.sh
```

Outputs `raw-data/cost_summary.csv` — a table of peak replicas, duration, and estimated AWS cost per run. Use this for the paper's cost-awareness analysis.

---

## WHAT TO RECORD IN YOUR PAPER

For each experiment pattern, you will have:

| Item | Where it comes from |
|------|---------------------|
| Scale-up time (mean ± std) | `*_scale_events.csv` across 5 runs |
| p95 latency at peak (mean ± std) | `*_latency_p95.csv` across 5 runs |
| Error rate at peak (%) | `*_error_rate_pct.csv` |
| Cost per experiment ($) | `cost_summary.csv` |
| HPA replica trajectory graph | `*_hpa_poll.csv` → plot |

**Research questions your data answers:**
1. How quickly does HPA respond to sudden vs gradual load? (spike vs ramp scale-up time)
2. Does HPA over-provision during burst traffic? (burst replica count vs actual load)
3. What is the latency cost of HPA reaction delay? (latency spike before pods become Ready)
4. How does scaling behaviour affect estimated AWS cost? (cost_summary.csv)

---

## TROUBLESHOOTING

| Problem | Fix |
|---------|-----|
| `kubectl` can't reach cluster | `aws eks update-kubeconfig --name mega --region us-west-2` |
| HPA not scaling up | Check `kubectl describe hpa order-service-hpa -n mega` — CPU % too low? Increase CONCURRENCY |
| Prometheus port-forward drops | Re-run the port-forward command; re-run the export script for that run |
| p95 latency query returns empty | Services may not expose `http_request_duration_ms_bucket` — check with `kubectl logs` on order-service |
| Script permission denied | `chmod +x scripts/*.sh` |
