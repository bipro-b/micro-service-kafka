#!/usr/bin/env bash
# Pre-flight check — run this before every experiment session.
# Exits non-zero if anything is not ready.
set -euo pipefail

NAMESPACE=mega
PROM_NAMESPACE=prometheus
PASS=0
FAIL=0

ok()   { echo "[OK]   $*"; ((PASS++)) || true; }
fail() { echo "[FAIL] $*"; ((FAIL++)) || true; }

echo "============================================"
echo " PRE-FLIGHT: Kubernetes Data Collection"
echo " $(date)"
echo "============================================"

# 1. kubectl connectivity
if kubectl cluster-info &>/dev/null; then
  ok "kubectl connected to cluster"
else
  fail "kubectl cannot reach cluster — check kubeconfig / AWS credentials"
fi

# 2. All mega pods Running
NOT_READY=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null \
  | grep -v "Running\|Completed" | wc -l | tr -d ' ')
if [[ "$NOT_READY" -eq 0 ]]; then
  ok "All pods in '$NAMESPACE' are Running"
else
  fail "$NOT_READY pod(s) not in Running state:"
  kubectl get pods -n $NAMESPACE --no-headers | grep -v "Running\|Completed"
fi

# 3. Load generator is deployed
if kubectl get deployment load-generator-deployment -n $NAMESPACE &>/dev/null; then
  ok "load-generator-deployment exists"
else
  fail "load-generator-deployment not found in $NAMESPACE"
fi

# 4. HPA objects
HPA_COUNT=$(kubectl get hpa -n $NAMESPACE --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$HPA_COUNT" -ge 2 ]]; then
  ok "Found $HPA_COUNT HPA object(s) in '$NAMESPACE'"
  kubectl get hpa -n $NAMESPACE
else
  fail "Expected ≥ 2 HPAs in '$NAMESPACE', found $HPA_COUNT"
fi

# 5. Prometheus running
PROM_PODS=$(kubectl get pods -n $PROM_NAMESPACE --no-headers 2>/dev/null \
  | grep "prometheus-stable-kube-prometheus" | grep Running | wc -l | tr -d ' ')
if [[ "$PROM_PODS" -ge 1 ]]; then
  ok "Prometheus pod(s) running in '$PROM_NAMESPACE'"
else
  fail "No running Prometheus pods found in '$PROM_NAMESPACE'"
fi

# 6. ServiceMonitors
SM_COUNT=$(kubectl get servicemonitor -n $NAMESPACE --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$SM_COUNT" -ge 4 ]]; then
  ok "Found $SM_COUNT ServiceMonitor(s)"
else
  fail "Expected 4 ServiceMonitors, found $SM_COUNT"
fi

echo "============================================"
echo " RESULT: $PASS passed  /  $FAIL failed"
echo "============================================"

if [[ "$FAIL" -gt 0 ]]; then
  echo "Fix the failures above before running experiments."
  exit 1
fi
echo "All checks passed — ready to collect data."
