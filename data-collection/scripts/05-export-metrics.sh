#!/usr/bin/env bash
# Export Prometheus metrics to CSV for all completed runs.
# Requires: kubectl port-forward to Prometheus on localhost:9090
#
# Usage:
#   # In one terminal — port-forward Prometheus:
#   kubectl port-forward svc/stable-kube-prometheus-st-prometheus -n prometheus 9090:9090
#
#   # In another terminal — run this script:
#   PATTERN=spike RUN=1 START_TS=1740000000 END_TS=1740003600 bash scripts/05-export-metrics.sh
#
# START_TS and END_TS are Unix timestamps (use `date -d "2026-03-06 10:00" +%s`)
set -euo pipefail

PROM_URL=${PROM_URL:-"http://localhost:9090"}
PATTERN=${PATTERN:-"spike"}
RUN=${RUN:-1}
# Default: last 1 hour
END_TS=${END_TS:-$(date +%s)}
START_TS=${START_TS:-$((END_TS - 3600))}
STEP=${STEP:-"15s"}

OUTPUT_DIR="raw-data/${PATTERN}/run-${RUN}"
mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "============================================"
echo " EXPORT METRICS: $PATTERN / run-$RUN"
echo " Prometheus : $PROM_URL"
echo " Range      : $START_TS → $END_TS"
echo " Step       : $STEP"
echo "============================================"

query_range() {
  local LABEL=$1
  local QUERY=$2
  local OUT="$OUTPUT_DIR/${TIMESTAMP}_${LABEL}.csv"

  echo "  Fetching: $LABEL"
  RESULT=$(curl -sf --data-urlencode "query=$QUERY" \
    --data-urlencode "start=$START_TS" \
    --data-urlencode "end=$END_TS" \
    --data-urlencode "step=$STEP" \
    "$PROM_URL/api/v1/query_range") || {
    echo "  [WARN] Query failed for $LABEL — skipping"
    return
  }

  echo "timestamp_unix,value,metric_json" > "$OUT"
  echo "$RESULT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for series in data.get('data', {}).get('result', []):
    metric = json.dumps(series.get('metric', {}))
    for ts, val in series.get('values', []):
        print(f'{ts},{val},{metric}')
" >> "$OUT" 2>/dev/null || {
    echo "  [WARN] Python parse failed for $LABEL — raw JSON saved"
    echo "$RESULT" > "${OUT%.csv}.json"
  }
  echo "  Saved: $OUT"
}

# ── Latency metrics ──────────────────────────────────────────────────────────
# p95 response latency (order-service)
query_range "latency_p95" \
  'histogram_quantile(0.95, sum(rate(http_request_duration_ms_bucket{namespace="mega"}[1m])) by (le, service))'

# p50 response latency
query_range "latency_p50" \
  'histogram_quantile(0.50, sum(rate(http_request_duration_ms_bucket{namespace="mega"}[1m])) by (le, service))'

# ── Request and error rates ──────────────────────────────────────────────────
query_range "request_rate_rps" \
  'sum(rate(http_requests_total{namespace="mega"}[1m])) by (service)'

query_range "error_rate_pct" \
  'sum(rate(http_requests_total{namespace="mega",status=~"5.."}[1m])) by (service) / sum(rate(http_requests_total{namespace="mega"}[1m])) by (service)'

# ── HPA / Scaling metrics ────────────────────────────────────────────────────
query_range "hpa_current_replicas" \
  'kube_horizontalpodautoscaler_status_current_replicas{namespace="mega"}'

query_range "hpa_desired_replicas" \
  'kube_horizontalpodautoscaler_status_desired_replicas{namespace="mega"}'

query_range "deployment_replicas_available" \
  'kube_deployment_status_replicas_available{namespace="mega"}'

# ── CPU / Resource utilisation ───────────────────────────────────────────────
query_range "cpu_usage_cores" \
  'sum(rate(container_cpu_usage_seconds_total{namespace="mega",container!=""}[1m])) by (pod)'

query_range "memory_usage_bytes" \
  'sum(container_memory_working_set_bytes{namespace="mega",container!=""}) by (pod)'

# ── Node-level (for cost estimation) ────────────────────────────────────────
query_range "node_cpu_utilisation" \
  '1 - avg(rate(node_cpu_seconds_total{mode="idle"}[1m]))'

query_range "node_count" \
  'count(kube_node_info)'

echo ""
echo "All exports complete → $OUTPUT_DIR"
echo "Files:"
ls "$OUTPUT_DIR/"*.csv 2>/dev/null || true
