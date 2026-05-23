# Traffic Management & Scaling — Order Service

## Current Architecture (your project baseline)

```
Internet
   │
   ▼
ALB Ingress (internet-facing, port 80)
   │  all traffic → /
   ▼
api-gateway:4000  (NodePort 31411)  ← HPA: 2–6 pods, CPU 60%, Mem 70%
   │
   ├──► order-service:4003   (NodePort 31403)  ← HPA: 1–4 pods, CPU 60%
   ├──► product-service:4001
   └──► user-service:4002
         │
         ▼
      MongoDB  +  Kafka (async events)
```

Load generator is already deployed inside the cluster hitting `api-gateway:4000`.

---

## Part 1 — Scaling

### 1A. HPA (Horizontal Pod Autoscaler) — what's already configured

| Service       | Min | Max | CPU trigger | Memory trigger | ScaleUp window | ScaleDown window |
|---------------|-----|-----|-------------|----------------|----------------|------------------|
| order-service | 1   | 4   | 60%         | —              | 60s            | 180s             |
| api-gateway   | 2   | 6   | 60%         | 70%            | 60s            | 120s             |
| product-service | 1 | 3   | 65%         | —              | default        | default          |

**File:** `kubernetes/hpa.yaml`

### 1B. Key HPA fields to understand

```yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 60   # waits 60s of sustained load before adding pods
    policies:
      - type: Pods
        value: 2          # add at most 2 pods per 60s window (api-gateway only)
        periodSeconds: 60
  scaleDown:
    stabilizationWindowSeconds: 180  # waits 3 min of low load before removing pods
```

`stabilizationWindowSeconds` prevents flapping — scale-up is aggressive, scale-down is conservative.

### 1C. Resource requests/limits matter for HPA

HPA calculates: `actual CPU usage / requested CPU`

For order-service:
- Request = 50m CPU → if pod uses 30m → utilization = 60% → HPA triggers
- Limit = 300m → pod can burst but won't kill the node

**Rule:** If requests are too low, HPA triggers too early. If too high, you waste capacity.

### 1D. Manual scaling (for practice / emergencies)

```bash
# Scale order-service to 3 replicas manually
kubectl scale deployment order-service-deployment --replicas=3 -n mega

# Watch pods come up
kubectl get pods -n mega -l app=order-service -w

# Check HPA status (will fight manual scaling if metrics recover)
kubectl get hpa order-service-hpa -n mega
```

> Note: If HPA is active and CPU drops below threshold, HPA will scale back down after `stabilizationWindowSeconds`.

---

## Part 2 — Traffic Management

### 2A. Entry point — ALB Ingress

**File:** `kubernetes/ingress.yaml`

All public traffic enters through one ALB → api-gateway. The api-gateway then routes internally.

Key ALB annotations already set:
```yaml
alb.ingress.kubernetes.io/scheme: internet-facing     # public-facing
alb.ingress.kubernetes.io/target-type: ip             # routes to pod IPs (not node IPs)
alb.ingress.kubernetes.io/healthcheck-path: /health   # ALB only sends traffic to healthy pods
alb.ingress.kubernetes.io/unhealthy-threshold-count: "3"  # 3 failed checks = deregister pod
```

### 2B. Kubernetes Service — internal load balancing

The `order-service` Service (ClusterIP-equivalent within `NodePort`) round-robins requests across all healthy order-service pods. `kube-proxy` handles this with `iptables` rules.

```bash
# See endpoints (all pod IPs behind the service)
kubectl get endpoints order-service -n mega

# Describe service
kubectl describe svc order-service -n mega
```

### 2C. Readiness vs Liveness probes — traffic gate

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 4003
  initialDelaySeconds: 5    # wait 5s before first check
  periodSeconds: 10         # check every 10s
```

- **Readiness probe fails** → pod removed from Service endpoints → no traffic sent to it
- **Liveness probe fails** → pod restarted by kubelet

This means a pod that's starting up or overloaded gets drained before being killed — zero downtime.

### 2D. Traffic during rolling updates (zero-downtime deploys)

The deployment strategy defaults to `RollingUpdate`. When you push a new image:
1. New pod starts, readiness probe runs
2. Only when new pod is ready does old pod get terminated
3. Service endpoint list is updated atomically

```bash
# Watch a rolling update
kubectl rollout status deployment/order-service-deployment -n mega

# Rollback if bad
kubectl rollout undo deployment/order-service-deployment -n mega
```

### 2E. Rate limiting / throttling (not yet implemented — next step)

Currently there is no rate limiting. Options to add:

| Option | Where | How |
|--------|-------|-----|
| nginx-ingress annotations | Ingress | `nginx.ingress.kubernetes.io/limit-rps: "100"` |
| API Gateway middleware | api-gateway code | express-rate-limit package |
| KEDA + Kafka lag | HPA alternative | scale based on queue depth |

---

## Part 3 — Hands-on Practice Sequence

### Step 1 — Baseline observation

```bash
# Check current state
kubectl get pods -n mega
kubectl get hpa -n mega
kubectl top pods -n mega    # requires metrics-server installed
```

### Step 2 — Watch HPA in real-time

```bash
# Terminal 1: watch HPA decisions
kubectl get hpa order-service-hpa -n mega -w

# Terminal 2: watch pods scale
kubectl get pods -n mega -l app=order-service -w
```

### Step 3 — Trigger load (load-generator is already in the cluster)

The load generator hits `api-gateway:4000` every 2000ms with concurrency 3.

To increase pressure, edit the load-generator and redeploy:
```bash
kubectl set env deployment/load-generator-deployment INTERVAL_MS=200 CONCURRENCY=20 -n mega
```

Then watch HPA kick in within ~60s.

### Step 4 — Observe scale-up

```bash
kubectl describe hpa order-service-hpa -n mega
# Look for: "Conditions", "Events", current/desired replicas
```

### Step 5 — Reduce load and observe scale-down

```bash
# Lower load generator back
kubectl set env deployment/load-generator-deployment INTERVAL_MS=5000 CONCURRENCY=1 -n mega

# Scale-down will happen after stabilizationWindowSeconds=180 (3 minutes)
kubectl get hpa order-service-hpa -n mega -w
```

### Step 6 — Simulate pod failure (traffic management test)

```bash
# Kill a pod — Kubernetes should reschedule + service keeps routing to healthy pods
kubectl delete pod <order-service-pod-name> -n mega

# Watch: new pod created, readiness checked, traffic resumes
kubectl get pods -n mega -l app=order-service -w
```

### Step 7 — Test rolling update with zero downtime

```bash
# Trigger a rolling update (change image tag or env var)
kubectl set image deployment/order-service-deployment \
  order-service=biprob/microservices-project-order-service:latest-v100 -n mega

# In another terminal, hammer the endpoint while update happens
# curl http://<ALB-URL>/orders in a loop — should see 0 errors
```

---

## Part 4 — Things to improve (for your portfolio)

| Gap | Fix | Impact |
|-----|-----|--------|
| No `minAvailable` PodDisruptionBudget | Add PDB so at least 1 order-service pod is always up during node drain | High |
| HPA memory metric missing on order-service | Add memory metric like api-gateway has | Medium |
| No rate limiting | Add at Ingress or api-gateway layer | Medium |
| `maxReplicas: 4` may hit resource limits | Verify node capacity on EKS (t3.medium = 2 vCPU, 4GiB) | Medium |
| No KEDA for Kafka-based scaling | Scale order-service based on Kafka consumer lag | Advanced |

---

## Quick Reference — Commands

```bash
# HPA status
kubectl get hpa -n mega
kubectl describe hpa order-service-hpa -n mega

# Pod resource usage
kubectl top pods -n mega

# Service endpoints
kubectl get endpoints -n mega

# Scale manually
kubectl scale deployment order-service-deployment --replicas=3 -n mega

# Crank up load
kubectl set env deployment/load-generator-deployment INTERVAL_MS=200 CONCURRENCY=20 -n mega

# Reset load
kubectl set env deployment/load-generator-deployment INTERVAL_MS=2000 CONCURRENCY=3 -n mega

# Watch rolling update
kubectl rollout status deployment/order-service-deployment -n mega

# Rollback
kubectl rollout undo deployment/order-service-deployment -n mega
```
