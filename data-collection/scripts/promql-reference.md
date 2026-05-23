# PromQL Reference — Kubernetes Reliability & Cost-Aware Auto-Scaling

Use these queries in Grafana or via `curl http://localhost:9090/api/v1/query?query=...`

## Latency

```promql
# p95 latency across all services (ms)
histogram_quantile(0.95,
  sum(rate(http_request_duration_ms_bucket{namespace="mega"}[1m]))
  by (le, service)
)

# p50 latency
histogram_quantile(0.50,
  sum(rate(http_request_duration_ms_bucket{namespace="mega"}[1m]))
  by (le, service)
)

# p99 latency (for paper's threat-to-validity — tail latency)
histogram_quantile(0.99,
  sum(rate(http_request_duration_ms_bucket{namespace="mega"}[1m]))
  by (le, service)
)
```

## Throughput & Errors

```promql
# Request rate (rps) per service
sum(rate(http_requests_total{namespace="mega"}[1m])) by (service)

# Error rate (%)
sum(rate(http_requests_total{namespace="mega", status=~"5.."}[1m])) by (service)
/
sum(rate(http_requests_total{namespace="mega"}[1m])) by (service)
* 100

# Total 5xx count over experiment window
increase(http_requests_total{namespace="mega", status=~"5.."}[20m])
```

## HPA & Scaling

```promql
# Current replica count (HPA view)
kube_horizontalpodautoscaler_status_current_replicas{namespace="mega"}

# Desired replica count (HPA view — what HPA wants)
kube_horizontalpodautoscaler_status_desired_replicas{namespace="mega"}

# Pod readiness (deployment view)
kube_deployment_status_replicas_available{namespace="mega"}

# HPA scale-up trigger metric (CPU %)
kube_horizontalpodautoscaler_status_target_metric_value{namespace="mega"}
```

## CPU & Memory

```promql
# Per-pod CPU usage (cores)
sum(rate(container_cpu_usage_seconds_total{
  namespace="mega", container!="", container!="POD"
}[1m])) by (pod)

# Per-pod memory (MB)
sum(container_memory_working_set_bytes{
  namespace="mega", container!="", container!="POD"
}) by (pod) / 1024 / 1024

# CPU throttling (sign of under-provisioning)
sum(rate(container_cpu_cfs_throttled_seconds_total{namespace="mega"}[1m])) by (pod)
```

## Node / Cost Metrics

```promql
# Node CPU utilisation (%)
(1 - avg(rate(node_cpu_seconds_total{mode="idle"}[1m]))) * 100

# Number of cluster nodes
count(kube_node_info)

# Node memory available (bytes)
node_memory_MemAvailable_bytes
```

## Scale-up Time Calculation

Scale-up time is measured manually from the experiment logs:

```
scale_up_time = (first timestamp where hpa_current_replicas increases)
              - (timestamp where high load was applied)
```

This is captured in:
- `raw-data/<pattern>/run-<N>/*_scale_events.csv`
- `raw-data/<pattern>/run-<N>/*_hpa_poll.csv`

Look for the first row where `current_replicas` increases after the phase-start event.

## Grafana Dashboard Panels to Screenshot

For each experiment run, screenshot these panels at PEAK LOAD:
1. HTTP Request Rate (rps)
2. p95 Latency (ms)
3. HPA Replica Count
4. Pod CPU Utilisation
5. Error Rate (%)
