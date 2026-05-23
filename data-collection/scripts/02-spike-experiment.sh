#!/usr/bin/env bash
# SPIKE experiment — sudden jump from low (CONCURRENCY=3) to high (CONCURRENCY=20) load.
# Run with: RUN=1 bash scripts/02-spike-experiment.sh   (RUN 1-5)
#
# Timeline:
#   0:00 – 5:00   warmup   (CONCURRENCY=3)
#   5:00 – 10:00  SPIKE    (CONCURRENCY=20, INTERVAL=200ms)  ← HPA triggers here
#   10:00 – 20:00 cool-down (CONCURRENCY=1)                  ← HPA scales back down
set -euo pipefail

NAMESPACE=mega
RUN=${RUN:-1}
PATTERN="spike"
OUTPUT_DIR="raw-data/${PATTERN}/run-${RUN}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$OUTPUT_DIR"

echo "============================================"
echo " EXPERIMENT: SPIKE  |  Run #${RUN}"
echo " Start: $(date)"
echo " Output: $OUTPUT_DIR"
echo "============================================"

HPA_CSV="$OUTPUT_DIR/${TIMESTAMP}_hpa_poll.csv"
EVENT_LOG="$OUTPUT_DIR/${TIMESTAMP}_events.txt"
SCALE_LOG="$OUTPUT_DIR/${TIMESTAMP}_scale_events.csv"

echo "timestamp_unix,hpa_name,current_replicas,desired_replicas,last_scale_time" > "$HPA_CSV"
echo "timestamp_unix,type,reason,object,message" > "$SCALE_LOG"

# Background poller — records HPA state every 10s throughout experiment
poll_hpa() {
  while true; do
    kubectl get hpa -n $NAMESPACE --no-headers 2>/dev/null | while read -r line; do
      NAME=$(echo "$line"  | awk '{print $1}')
      CURR=$(echo "$line"  | awk '{print $6}')
      DESIR=$(echo "$line" | awk '{print $7}')
      echo "$(date +%s),$NAME,$CURR,$DESIR,$(date -u +%H:%M:%S)"
    done >> "$HPA_CSV"
    sleep 10
  done
}

poll_hpa &
POLLER_PID=$!
trap "kill $POLLER_PID 2>/dev/null; echo '[spike] Poller stopped.'" EXIT

# Record pre-experiment snapshot
echo "=== PRE-EXPERIMENT SNAPSHOT ===" >> "$EVENT_LOG"
kubectl get pods -n $NAMESPACE >> "$EVENT_LOG"
kubectl get hpa -n $NAMESPACE  >> "$EVENT_LOG"

# ── Phase 1: WARMUP (5 min at low load) ─────────────────────────────────────
echo ""
echo "[spike] Phase 1/3 — Warmup (5 min, CONCURRENCY=3, INTERVAL=2000)"
kubectl set env deployment/load-generator-deployment \
  INTERVAL_MS=2000 CONCURRENCY=3 -n $NAMESPACE
kubectl rollout status deployment/load-generator-deployment -n $NAMESPACE --timeout=60s
WARMUP_START=$(date +%s)
echo "$WARMUP_START,INFO,PHASE_START,load-generator,warmup begin" >> "$SCALE_LOG"
sleep 300

# ── Phase 2: SPIKE (5 min at 10× load) ──────────────────────────────────────
echo ""
echo "[spike] Phase 2/3 — SPIKE (5 min, CONCURRENCY=20, INTERVAL=200)"
kubectl set env deployment/load-generator-deployment \
  INTERVAL_MS=200 CONCURRENCY=20 -n $NAMESPACE
kubectl rollout status deployment/load-generator-deployment -n $NAMESPACE --timeout=60s
SPIKE_START=$(date +%s)
echo "$SPIKE_START,INFO,PHASE_START,load-generator,spike begin" >> "$SCALE_LOG"

# Monitor scale-up events during spike
END_SPIKE=$((SECONDS + 300))
LAST_REPLICAS=""
while [[ $SECONDS -lt $END_SPIKE ]]; do
  CURR=$(kubectl get hpa order-service-hpa -n $NAMESPACE \
    --no-headers 2>/dev/null | awk '{print $6}')
  if [[ "$CURR" != "$LAST_REPLICAS" && -n "$CURR" ]]; then
    TS=$(date +%s)
    echo "$TS,SCALE_EVENT,ReplicaChange,order-service-hpa,replicas=$CURR" >> "$SCALE_LOG"
    echo "[spike] $(date +%H:%M:%S)  order-service replicas → $CURR"
    LAST_REPLICAS="$CURR"
  fi
  sleep 5
done

# Capture k8s events at peak
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' 2>/dev/null \
  | tail -30 >> "$EVENT_LOG"
echo "" >> "$EVENT_LOG"
echo "=== POST-SPIKE HPA STATE ===" >> "$EVENT_LOG"
kubectl get hpa -n $NAMESPACE >> "$EVENT_LOG"

# ── Phase 3: COOL-DOWN (10 min — HPA scales back down) ──────────────────────
echo ""
echo "[spike] Phase 3/3 — Cool-down (10 min, CONCURRENCY=1)"
kubectl set env deployment/load-generator-deployment \
  INTERVAL_MS=2000 CONCURRENCY=1 -n $NAMESPACE
kubectl rollout status deployment/load-generator-deployment -n $NAMESPACE --timeout=60s
COOLDOWN_START=$(date +%s)
echo "$COOLDOWN_START,INFO,PHASE_START,load-generator,cooldown begin" >> "$SCALE_LOG"
sleep 600

# Final snapshot
echo "" >> "$EVENT_LOG"
echo "=== POST-COOLDOWN SNAPSHOT ===" >> "$EVENT_LOG"
kubectl get pods -n $NAMESPACE >> "$EVENT_LOG"
kubectl get hpa -n $NAMESPACE  >> "$EVENT_LOG"

echo ""
echo "============================================"
echo " SPIKE Run #${RUN} COMPLETE"
echo " $(date)"
echo " Files:"
echo "   HPA poll CSV   : $HPA_CSV"
echo "   Scale events   : $SCALE_LOG"
echo "   Event log      : $EVENT_LOG"
echo "============================================"
echo ""
echo "Next step: fill in logs/run-spike-${RUN}.md observation notes"
echo "Then reset the cluster: wait 5 min before next run."
