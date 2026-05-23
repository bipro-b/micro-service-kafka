#!/usr/bin/env bash
# Cost estimation per experiment run.
# Uses node-level CPU/memory peak from the HPA poll CSVs + AWS EC2 pricing.
#
# Assumes EKS on us-west-2 with t3.medium nodes (2 vCPU, 4 GB, $0.0416/hr)
# Change NODE_PRICE_PER_HR if using a different instance type.
#
# Usage:
#   bash scripts/06-cost-estimate.sh
#   → writes raw-data/cost_summary.csv
set -euo pipefail

NODE_PRICE_PER_HR=0.0416    # t3.medium us-west-2 on-demand
OUTPUT="raw-data/cost_summary.csv"

echo "timestamp,pattern,run,peak_replicas,experiment_duration_min,estimated_pod_cost_usd,note" > "$OUTPUT"

echo "============================================"
echo " COST ESTIMATE — all runs"
echo " Node type   : t3.medium"
echo " Price/hr    : \$$NODE_PRICE_PER_HR"
echo "============================================"

for PATTERN in spike ramp burst; do
  for RUN in 1 2 3 4 5; do
    DIR="raw-data/${PATTERN}/run-${RUN}"
    HPA_FILE=$(ls "$DIR/"*_hpa_poll.csv 2>/dev/null | head -1)
    if [[ -z "$HPA_FILE" ]]; then
      echo "  [skip] $PATTERN/run-$RUN — no HPA CSV found"
      continue
    fi

    # Peak replicas (max current_replicas column = col 3)
    PEAK=$(tail -n +2 "$HPA_FILE" \
      | awk -F',' '$2=="order-service-hpa" {print $3}' \
      | sort -n | tail -1)
    PEAK=${PEAK:-1}

    # Experiment duration from first and last timestamp
    FIRST_TS=$(tail -n +2 "$HPA_FILE" | head -1 | cut -d',' -f1)
    LAST_TS=$(tail -n +2 "$HPA_FILE"  | tail -1 | cut -d',' -f1)
    if [[ -n "$FIRST_TS" && -n "$LAST_TS" ]]; then
      DURATION_SEC=$((LAST_TS - FIRST_TS))
      DURATION_MIN=$(echo "scale=1; $DURATION_SEC / 60" | bc)
      DURATION_HR=$(echo  "scale=4; $DURATION_SEC / 3600" | bc)
    else
      DURATION_MIN=20
      DURATION_HR=$(echo "scale=4; 20/60" | bc)
    fi

    # Cost = peak pods × (node price / pods per node)
    # Assumes ~4 app pods per t3.medium node (conservative)
    PODS_PER_NODE=4
    COST=$(echo "scale=4; $PEAK * ($NODE_PRICE_PER_HR / $PODS_PER_NODE) * $DURATION_HR" | bc)

    echo "$(date +%s),$PATTERN,$RUN,$PEAK,$DURATION_MIN,$COST,t3.medium-us-west-2" >> "$OUTPUT"
    echo "  $PATTERN / run-$RUN : peak_replicas=$PEAK  duration=${DURATION_MIN}min  cost=\$$COST"
  done
done

echo ""
echo "Cost summary written → $OUTPUT"
echo ""
echo "=== SUMMARY TABLE ==="
echo "Pattern | Run | Peak Pods | Duration | Cost USD"
echo "--------|-----|-----------|----------|----------"
tail -n +2 "$OUTPUT" | awk -F',' '{
  printf "%-7s | %3s | %9s | %7s min | $%s\n", $2, $3, $4, $5, $6
}'
