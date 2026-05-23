#!/usr/bin/env bash
# RAMP experiment — gradual load increase over 20 minutes.
# Run with: RUN=1 bash scripts/03-ramp-experiment.sh   (RUN 1-5)
#
# Timeline (each step = 3 min):
#   Step 1: CONCURRENCY=3,  INTERVAL=2000  (baseline)
#   Step 2: CONCURRENCY=6,  INTERVAL=1000
#   Step 3: CONCURRENCY=10, INTERVAL=600
#   Step 4: CONCURRENCY=15, INTERVAL=400
#   Step 5: CONCURRENCY=20, INTERVAL=200   (peak)
#   Step 6: CONCURRENCY=1,  INTERVAL=2000  (cool-down, 5 min)
set -euo pipefail

NAMESPACE=mega
RUN=${RUN:-1}
PATTERN="ramp"
OUTPUT_DIR="raw-data/${PATTERN}/run-${RUN}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$OUTPUT_DIR"

echo "============================================"
echo " EXPERIMENT: RAMP  |  Run #${RUN}"
echo " Start: $(date)"
echo " Output: $OUTPUT_DIR"
echo "============================================"

HPA_CSV="$OUTPUT_DIR/${TIMESTAMP}_hpa_poll.csv"
EVENT_LOG="$OUTPUT_DIR/${TIMESTAMP}_events.txt"
RAMP_LOG="$OUTPUT_DIR/${TIMESTAMP}_ramp_steps.csv"

echo "timestamp_unix,hpa_name,current_replicas,desired_replicas" > "$HPA_CSV"
echo "timestamp_unix,step,concurrency,interval_ms,hpa_current,hpa_desired" > "$RAMP_LOG"

# Background poller
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

ramp_step() {
  local STEP=$1
  local CONC=$2
  local INTV=$3
  local DUR=$4

  echo ""
  echo "[ramp] Step $STEP — CONCURRENCY=$CONC, INTERVAL=${INTV}ms, duration=${DUR}s"
  kubectl set env deployment/load-generator-deployment \
    INTERVAL_MS=$INTV CONCURRENCY=$CONC -n $NAMESPACE
  kubectl rollout status deployment/load-generator-deployment \
    -n $NAMESPACE --timeout=60s

  TS=$(date +%s)
  # record HPA state at step start
  kubectl get hpa -n $NAMESPACE --no-headers 2>/dev/null | while read -r line; do
    NAME=$(echo "$line"  | awk '{print $1}')
    CURR=$(echo "$line"  | awk '{print $6}')
    DESIR=$(echo "$line" | awk '{print $7}')
    echo "$TS,$STEP,$CONC,$INTV,$CURR,$DESIR"
  done >> "$RAMP_LOG"

  sleep "$DUR"
}

# Record pre-experiment state
echo "=== PRE-EXPERIMENT ===" >> "$EVENT_LOG"
kubectl get pods -n $NAMESPACE >> "$EVENT_LOG"
kubectl get hpa  -n $NAMESPACE >> "$EVENT_LOG"

# Ramp steps (each 3 min = 180s)
ramp_step 1   3 2000 180
ramp_step 2   6 1000 180
ramp_step 3  10  600 180
ramp_step 4  15  400 180
ramp_step 5  20  200 180

# Capture peak state
echo "" >> "$EVENT_LOG"
echo "=== PEAK STATE ===" >> "$EVENT_LOG"
kubectl get pods -n $NAMESPACE >> "$EVENT_LOG"
kubectl get hpa  -n $NAMESPACE >> "$EVENT_LOG"
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -20 >> "$EVENT_LOG"

# Cool-down
ramp_step 6   1 2000 300

echo "" >> "$EVENT_LOG"
echo "=== POST-COOLDOWN ===" >> "$EVENT_LOG"
kubectl get hpa -n $NAMESPACE >> "$EVENT_LOG"

echo ""
echo "============================================"
echo " RAMP Run #${RUN} COMPLETE — $(date)"
echo " HPA CSV  : $HPA_CSV"
echo " Ramp log : $RAMP_LOG"
echo " Events   : $EVENT_LOG"
echo "============================================"
