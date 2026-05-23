#!/usr/bin/env bash
# BURST experiment — periodic high/low cycles to simulate intermittent traffic.
# Run with: RUN=1 bash scripts/04-burst-experiment.sh   (RUN 1-5)
#
# Timeline (4 burst cycles × 4 min each = 16 min, then 5 min cool-down):
#   HIGH: CONCURRENCY=20, INTERVAL=200  (2 min)
#   LOW:  CONCURRENCY=2,  INTERVAL=2000 (2 min)
#   × 4 cycles
set -euo pipefail

NAMESPACE=mega
RUN=${RUN:-1}
PATTERN="burst"
OUTPUT_DIR="raw-data/${PATTERN}/run-${RUN}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$OUTPUT_DIR"

echo "============================================"
echo " EXPERIMENT: BURST  |  Run #${RUN}"
echo " Start: $(date)"
echo " Output: $OUTPUT_DIR"
echo "============================================"

HPA_CSV="$OUTPUT_DIR/${TIMESTAMP}_hpa_poll.csv"
EVENT_LOG="$OUTPUT_DIR/${TIMESTAMP}_events.txt"
BURST_LOG="$OUTPUT_DIR/${TIMESTAMP}_burst_cycles.csv"

echo "timestamp_unix,hpa_name,current_replicas,desired_replicas" > "$HPA_CSV"
echo "timestamp_unix,cycle,phase,concurrency,interval_ms,hpa_replicas" > "$BURST_LOG"

# Background poller every 10s
poll_hpa() {
  while true; do
    kubectl get hpa -n $NAMESPACE --no-headers 2>/dev/null | while read -r line; do
      NAME=$(echo "$line"  | awk '{print $1}')
      CURR=$(echo "$line"  | awk '{print $6}')
      DESIR=$(echo "$line" | awk '{print $7}')
      echo "$(date +%s),$NAME,$CURR,$DESIR"
    done >> "$HPA_CSV"
    sleep 10
  done
}
poll_hpa &
POLLER_PID=$!
trap "kill $POLLER_PID 2>/dev/null" EXIT

set_load() {
  local INTV=$1
  local CONC=$2
  kubectl set env deployment/load-generator-deployment \
    INTERVAL_MS=$INTV CONCURRENCY=$CONC -n $NAMESPACE
  kubectl rollout status deployment/load-generator-deployment \
    -n $NAMESPACE --timeout=60s
}

log_burst() {
  local CYCLE=$1 PHASE=$2 CONC=$3 INTV=$4
  kubectl get hpa -n $NAMESPACE --no-headers 2>/dev/null | while read -r line; do
    CURR=$(echo "$line" | awk '{print $6}')
    echo "$(date +%s),$CYCLE,$PHASE,$CONC,$INTV,$CURR"
  done >> "$BURST_LOG"
}

# Pre-experiment
echo "=== PRE-EXPERIMENT ===" >> "$EVENT_LOG"
kubectl get pods -n $NAMESPACE >> "$EVENT_LOG"
kubectl get hpa  -n $NAMESPACE >> "$EVENT_LOG"

# Warm up at low load (2 min)
echo "[burst] Warm-up (CONCURRENCY=2)"
set_load 2000 2
sleep 120

# 4 burst cycles
for CYCLE in 1 2 3 4; do
  echo ""
  echo "[burst] Cycle $CYCLE/4 — HIGH load (CONCURRENCY=20, 2 min)"
  set_load 200 20
  log_burst $CYCLE HIGH 20 200
  sleep 120

  echo "[burst] Cycle $CYCLE/4 — LOW load  (CONCURRENCY=2, 2 min)"
  set_load 2000 2
  log_burst $CYCLE LOW 2 2000
  sleep 120

  # Capture events mid-burst
  echo "" >> "$EVENT_LOG"
  echo "=== Cycle $CYCLE events ===" >> "$EVENT_LOG"
  kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' \
    2>/dev/null | tail -10 >> "$EVENT_LOG"
  kubectl get hpa -n $NAMESPACE >> "$EVENT_LOG"
done

# Cool-down
echo "[burst] Cool-down (5 min)"
set_load 2000 1
sleep 300

echo "" >> "$EVENT_LOG"
echo "=== POST-COOLDOWN ===" >> "$EVENT_LOG"
kubectl get hpa -n $NAMESPACE >> "$EVENT_LOG"

echo ""
echo "============================================"
echo " BURST Run #${RUN} COMPLETE — $(date)"
echo " HPA CSV   : $HPA_CSV"
echo " Burst log : $BURST_LOG"
echo " Events    : $EVENT_LOG"
echo "============================================"
