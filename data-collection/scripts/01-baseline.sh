#!/usr/bin/env bash
# Baseline measurement — minimal load for 10 minutes.
# Run ONCE at the start of the data collection session.
set -euo pipefail

NAMESPACE=mega
DURATION_SEC=600        # 10 minutes
OUTPUT_DIR="raw-data/baseline"

echo "============================================"
echo " BASELINE: 10-minute minimal-load capture"
echo " Start: $(date)"
echo "============================================"
mkdir -p "$OUTPUT_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$OUTPUT_DIR/${TIMESTAMP}_baseline_events.txt"

# Set load generator to minimal traffic (1 req/2s, concurrency=1)
echo "[baseline] Setting load generator → INTERVAL_MS=2000 CONCURRENCY=1"
kubectl set env deployment/load-generator-deployment \
  INTERVAL_MS=2000 CONCURRENCY=1 -n $NAMESPACE

# Wait for rollout
kubectl rollout status deployment/load-generator-deployment -n $NAMESPACE --timeout=60s

echo "[baseline] Capturing cluster state snapshot..."
{
  echo "=== DATE ==="
  date
  echo "=== PODS ==="
  kubectl get pods -n $NAMESPACE -o wide
  echo "=== HPA ==="
  kubectl get hpa -n $NAMESPACE
  echo "=== NODE RESOURCES ==="
  kubectl top nodes 2>/dev/null || echo "metrics-server not available"
  echo "=== POD RESOURCES ==="
  kubectl top pods -n $NAMESPACE 2>/dev/null || echo "metrics-server not available"
} > "$LOG_FILE"

echo "[baseline] Watching HPA for ${DURATION_SEC}s (one line per 30s)..."

END=$((SECONDS + DURATION_SEC))
POLL_FILE="$OUTPUT_DIR/${TIMESTAMP}_baseline_hpa_poll.csv"
echo "timestamp,hpa_name,min_replicas,max_replicas,current_replicas,desired_replicas,cpu_target" > "$POLL_FILE"

while [[ $SECONDS -lt $END ]]; do
  kubectl get hpa -n $NAMESPACE --no-headers 2>/dev/null | while read -r line; do
    NAME=$(echo "$line" | awk '{print $1}')
    MIN=$(echo "$line"  | awk '{print $4}')
    MAX=$(echo "$line"  | awk '{print $5}')
    CURR=$(echo "$line" | awk '{print $6}')
    DESIR=$(echo "$line"| awk '{print $7}')
    TARGET=$(echo "$line"| awk '{print $3}')
    echo "$(date +%s),$NAME,$MIN,$MAX,$CURR,$DESIR,$TARGET"
  done >> "$POLL_FILE"
  echo "[baseline] $(date +%H:%M:%S) — HPA snapshot written"
  sleep 30
done

echo "[baseline] Baseline complete. Outputs in: $OUTPUT_DIR"
echo "  Events log  : $LOG_FILE"
echo "  HPA CSV     : $POLL_FILE"
echo "[baseline] End: $(date)"
