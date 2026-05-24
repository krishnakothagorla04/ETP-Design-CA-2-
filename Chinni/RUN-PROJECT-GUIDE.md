# Chinni Checkout System — Complete Project Guide

## Nanoservices Checkout on Kubernetes (kind cluster) with Monitoring & Security

**Module:** Enterprise Architecture Design (ENTPH6001)
**Architecture:** `nanoservices-k8s-keda`
**Covers:** CA-1 (Microservices, Reliability, Scaling, Tracing, Persistence) + CA-2 (Monitoring, Security)

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [STEP 0 — Build & Deploy](#step-0--build--deploy-everything)
3. [REQ 1 — Microservices Composition](#requirement-1-microservices-composition)
4. [REQ 2 — Reliability & Partial Failures](#requirement-2-reliability--partial-failures)
5. [REQ 3 — Scaling with KEDA](#requirement-3-scaling-with-keda)
6. [REQ 4 — Request Correlation / Tracing-Lite](#requirement-4-request-correlation--tracing-lite)
7. [REQ 5 — Troubleshooting Evidence](#requirement-5-troubleshooting-evidence)
8. [REQ 6 — Persistence (Postgres)](#requirement-6-persistence-postgres)
9. [REQ 7 — Monitoring with Prometheus & Grafana (CA-2)](#requirement-7-monitoring--observability-ca-2)
10. [REQ 8 — Security Hardening & Network Policies (CA-2)](#requirement-8-security-hardening--network-policies-ca-2)
11. [REQ 9 — Security Testing with Trivy & Kubescape (CA-2)](#requirement-9-security-testing-ca-2)
12. [Full Summary Checklist](#full-summary-checklist)
13. [Quick Reference Commands](#quick-reference-commands)

---

## Prerequisites

Verify your development environment is ready:

```powershell
# Verify Kubernetes is running
kubectl get nodes
# Expected: 1 node (demo-cluster-control-plane) in Ready state

# Verify Docker is available
docker version

# Verify kind is installed
kind get clusters
# Expected: demo-cluster
```

> **⚠️ IMPORTANT — kind Cluster:**
> This project runs on a **kind** (Kubernetes in Docker) cluster named `demo-cluster`.
> kind uses **containerd** (not Docker) as its container runtime, so it **cannot** see
> Docker's local images. Every time you rebuild images with `docker build`, you **must**
> also run `kind load docker-image <image> --name demo-cluster` to push them into the cluster.
> Without this step, pods will fail with `ImagePullBackOff` / `ErrImagePull`.
>
> ### 🔍 FAQ: Is this expected?
> **Yes, absolutely.** If you deploy the Kubernetes manifests before building and loading your local images into the **kind** cluster, containerd cannot pull the images from any public registry and the pods will display `ImagePullBackOff` or `ErrImagePull`.
>
> For example:
> ```text
> pricing-7fc895d6d8-tvtrq     0/1     ErrImagePull       0          23h
> gateway-5c8b9bbbc-nrzz2      0/1     ImagePullBackOff   0          15s
> inventory-697c9db568-zsxwq   0/1     ImagePullBackOff   0          16s
> ```
> *Note on terminal wrapping:* If you see a pod named `ng-7fc895d6d8-tvtrq`, this is actually the `pricing-7fc895d6d8-tvtrq` pod name that has been split across lines because of your terminal's character-width wrapping (splitting `pricing-` into `prici` and `ng-`).
>
> **How to resolve:**
> 1. Build the local docker images:
>    ```powershell
>    docker build -t chinni-gateway:latest  ./services/gateway
>    docker build -t chinni-checkout:latest ./services/checkout
>    docker build -t chinni-pricing:latest  ./services/pricing
>    docker build -t chinni-inventory:latest ./services/inventory
>    ```
> 2. Load the built Docker images into your **kind** cluster:
>    ```powershell
>    kind load docker-image chinni-gateway:latest  --name demo-cluster
>    kind load docker-image chinni-checkout:latest --name demo-cluster
>    kind load docker-image chinni-pricing:latest  --name demo-cluster
>    kind load docker-image chinni-inventory:latest --name demo-cluster
>    ```
> 3. Restart the deployments to trigger the pods to pull the loaded local images:
>    ```powershell
>    kubectl rollout restart deploy gateway checkout pricing inventory -n checkout-demo
>    ```

---

## STEP 0 — Build & Deploy Everything

### 0a. Build all service images

```powershell
cd c:\Users\bhara\Desktop\Final\Chinni

docker build -t chinni-gateway:latest  ./services/gateway
docker build -t chinni-checkout:latest ./services/checkout
docker build -t chinni-pricing:latest  ./services/pricing
docker build -t chinni-inventory:latest ./services/inventory
```

### 0b. Load images into kind cluster

> **This step is required** — kind uses containerd, not Docker.
> Without it, pods will fail with `ImagePullBackOff`.

```powershell
kind load docker-image chinni-gateway:latest  --name demo-cluster
kind load docker-image chinni-checkout:latest --name demo-cluster
kind load docker-image chinni-pricing:latest  --name demo-cluster
kind load docker-image chinni-inventory:latest --name demo-cluster
```

### 0c. Deploy core infrastructure

```powershell
# Create namespace
kubectl apply -f k8s/base/namespace.yaml

# Deploy Postgres (secrets + PVC + deployment)
kubectl apply -f k8s/db/secret.yaml
kubectl apply -f k8s/db/pvc.yaml
kubectl apply -f k8s/db/postgres-deployment.yaml

# Deploy all services + ingress
kubectl apply -f k8s/base/

# Wait for all pods to be ready
kubectl get pods -n checkout-demo -w
```

### 0d. Deploy monitoring stack (CA-2)

```powershell
kubectl apply -f k8s/monitoring/prometheus-configmap.yaml
kubectl apply -f k8s/monitoring/prometheus-deployment.yaml
kubectl apply -f k8s/monitoring/grafana-datasource.yaml
kubectl apply -f k8s/monitoring/grafana-deployment.yaml
```

### 0e. Deploy network policies (CA-2)

```powershell
kubectl apply -f k8s/security/network-policies.yaml
```

### 0f. Verify everything is running

```powershell
kubectl get deploy,pods,svc,ingress -n checkout-demo
# Expected: gateway, checkout, pricing, inventory, postgres, prometheus, grafana — all Running
```

📸 **Screenshot this** — proves the complete system is deployed.

### 0g. Get the ingress address

```powershell
kubectl get ingress -n checkout-demo
```

### 🌐 Accessing the Application Gateway (Port-Forwarding & KEDA)

Since this project runs on a **kind** (Kubernetes in Docker) cluster on Windows:
1. **Port 80 Conflict:** Port 80 on your host is likely occupied by Docker Desktop's VM helpers (`host-switch`/`wslrelay`). We will port-forward to port `8080` instead.
2. **KEDA Scale-to-Zero:** If KEDA is already installed and its `HTTPScaledObject` is active from CA-1, KEDA will scale the `gateway` deployment to `0` replicas when there is no traffic. Manually scaling the deployment up with `kubectl scale` is reverted by KEDA within seconds.

To test the APIs manually, follow these preparatory steps:

**Open a separate PowerShell terminal and run:**
```powershell
# 1. Temporarily remove KEDA HTTP scaling so it doesn't scale gateway to 0
kubectl delete httpscaledobject gateway-http-scaler -n checkout-demo 2>$null

# 2. Scale the gateway to 1 replica manually
kubectl scale deploy gateway -n checkout-demo --replicas=1
kubectl rollout status deploy/gateway -n checkout-demo --timeout=60s

# 3. Port-forward the gateway service to host port 8080 (Leave this terminal running!)
kubectl port-forward svc/gateway 8080:80 -n checkout-demo
```

Now, all test requests in the steps below will use `http://localhost:8080/` instead of `http://localhost:8080/`.

*(Note: When you want to re-enable KEDA autoscaling later, simply run `kubectl apply -f k8s/keda/httpscaledobject-gateway-scale-to-zero.yaml`)*

---

## REQUIREMENT 1: Microservices Composition

> **What to show:** 4 services running, gateway routing to checkout, checkout composing pricing + inventory.

### 1a. Show all running components

```powershell
kubectl get deploy,pods,svc,ingress -n checkout-demo
```

📸 **Screenshot this** — shows all deployments, pods, services, and ingress.

### 1b. Test GET / (Gateway UI)

```powershell
Invoke-RestMethod -Uri http://localhost:8080/ -UseBasicParsing
# Expected: HTML with Gateway UI
```

### 1c. Test GET /api/arch

```powershell
Invoke-RestMethod -Uri http://localhost:8080/api/arch
# Expected: nanoservices-k8s-keda
```

### 1d. Test GET /api/ping

```powershell
Invoke-RestMethod -Uri http://localhost:8080/api/ping
# Expected: status = ok
```

### 1e. Test /health endpoints from inside the cluster

```powershell
kubectl run toolbox --image=curlimages/curl -n checkout-demo --rm -it --restart=Never -- sh

# Inside the toolbox pod, run:
curl http://gateway:80/health
curl http://checkout:8003/health
curl http://pricing:8001/health
curl http://inventory:8002/health
# All should return: {"status":"ok"}
exit
```

### 1f. Test POST /api/checkout (happy path)

```powershell
Invoke-RestMethod -Uri http://localhost:8080/api/checkout -Method POST `
  -ContentType "application/json" `
  -Headers @{"X-Request-Id"="test-req-001"} `
  -Body '{"items":[{"item_id":"item-1","quantity":2}]}'

# Expected: request_id=test-req-001, total_cost=20, order_id=<number>
```

### 1g. Test edge cases

```powershell
# Out of stock (item-2 has 0 stock)
Invoke-RestMethod -Uri http://localhost:8080/api/checkout -Method POST `
  -ContentType "application/json" `
  -Body '{"items":[{"item_id":"item-2","quantity":1}]}'
# Expected: 409 "Not enough stock for item-2"

# Item not found
Invoke-RestMethod -Uri http://localhost:8080/api/checkout -Method POST `
  -ContentType "application/json" `
  -Body '{"items":[{"item_id":"item-999","quantity":1}]}'
# Expected: 404 error from inventory

# No items
Invoke-RestMethod -Uri http://localhost:8080/api/checkout -Method POST `
  -ContentType "application/json" `
  -Body '{"items":[]}'
# Expected: 400 "No items provided"
```

📸 **Screenshot all edge case responses.**

---

## REQUIREMENT 2: Reliability & Partial Failures

> **What to show:** Gateway stays up when pricing is down. Timeouts work. No indefinite hangs.

### 2a. Verify timeouts are configured

```powershell
kubectl describe deploy checkout -n checkout-demo | Select-String -Pattern "HTTP_TIMEOUT"
# Expected: HTTP_TIMEOUT_SECONDS: 2.0
```

📸 **Screenshot this** — proves timeouts are configured.

### 2b. Confirm checkout works BEFORE failure

```powershell
Invoke-RestMethod -Uri http://localhost:8080/api/checkout -Method POST `
  -ContentType "application/json" `
  -Body '{"items":[{"item_id":"item-1","quantity":2}]}' `
  -Headers @{"X-Request-Id"="before-failure-test"}

# Expected: request_id=before-failure-test, total_cost=20
```

📸 **Screenshot this** — proves system works before we break it.

### 2c. BREAK pricing — scale to 0

```powershell
kubectl scale deploy pricing -n checkout-demo --replicas=0

# Wait 5 seconds, then verify
kubectl get pods -n checkout-demo -l app=pricing
# Expected: No resources found — pricing is DOWN
```

📸 **Screenshot this** — shows pricing has 0 pods.

### 2d. Prove gateway is STILL UP (partial failure isolation)

```powershell
Invoke-RestMethod -Uri http://localhost:8080/api/ping
# Expected: status = ok — gateway STILL HEALTHY
```

📸 **Screenshot this** — gateway returns OK while pricing is down.

### 2e. Show checkout FAILS FAST (no hang)

```powershell
$time = Measure-Command {
    try {
        Invoke-RestMethod -Uri http://localhost:8080/api/checkout -Method POST `
          -ContentType "application/json" `
          -Body '{"items":[{"item_id":"item-1","quantity":1}]}'
    } catch {
        Write-Host "ERROR: $_"
    }
}
Write-Host "Failed in $($time.TotalSeconds) seconds"

# Expected: ERROR 503 "Pricing service unavailable"
# Expected: Failed in ~0.1 seconds (fast failure!)
```

📸 **Screenshot this** — shows fast failure with timing.

### 2f. Show failure in checkout logs

```powershell
kubectl logs -l app=checkout -n checkout-demo --tail=5
```

📸 **Screenshot this** — shows the 503 failure logged.

### 2g. Restore pricing (recover the system)

```powershell
kubectl scale deploy pricing -n checkout-demo --replicas=1

# Wait for pod to be ready
kubectl get pods -n checkout-demo -l app=pricing
# Wait until: 1/1 Running

# Verify checkout works again
Invoke-RestMethod -Uri http://localhost:8080/api/checkout -Method POST `
  -ContentType "application/json" `
  -Body '{"items":[{"item_id":"item-1","quantity":1}]}'

# Expected: 200 success — system recovered!
```

📸 **Screenshot this** — proves system recovers after dependency is restored.

### Why This Happens (explanation for report)

> When pricing has 0 replicas, the Kubernetes service `pricing:8001` has **no backing pods**. Checkout's HTTP request gets no response. The **2-second timeout** (`HTTP_TIMEOUT_SECONDS=2.0`) kicks in, and checkout returns a **503 error** immediately. The **gateway remains healthy** because failure is isolated to the checkout→pricing path. This demonstrates **partial failure isolation** — a key benefit of microservices.

---

## REQUIREMENT 3: Scaling with KEDA

> **What to show:** Scale-to-zero, scale-from-zero, live scaling demo, cold vs warm latency.

### 3a. Install KEDA (one-time)

```powershell
kubectl apply --server-side --force-conflicts -f https://github.com/kedacore/keda/releases/download/v2.19.0/keda-2.19.0.yaml

# Wait for KEDA operator
kubectl get pods -n keda -w
```

### 3b. Install KEDA HTTP Add-on (one-time)

```powershell
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install http-add-on kedacore/keda-add-ons-http -n keda
```

### 3c. Apply KEDA ScaledObjects

```powershell
kubectl apply -f k8s/keda/httpscaledobject-gateway-scale-to-zero.yaml
kubectl apply -f k8s/keda/scaledobject-checkout.yaml
```

### 3d. Show the KEDA config

```powershell
Get-Content k8s/keda/httpscaledobject-gateway-scale-to-zero.yaml
# Shows: min: 0, max: 5 — KEDA configured for scale-to-zero
```

📸 **Screenshot this** — shows KEDA configuration with min=0.

### 3e. Show gateway at zero replicas (scale-to-zero proof)

```powershell
kubectl get deploy gateway -n checkout-demo
# Expected: READY 0/0 — KEDA scaled it to zero
```

📸 **Screenshot this** — proves scale-to-zero works.

### 3f. Run live scaling demo (0 → 1 → 3 → 5 → 0)

Open **2 terminals side by side:**

**Terminal 1 — Watch scaling live:**
```powershell
kubectl get deploy gateway -n checkout-demo -w
```

**Terminal 2 — Run load generator:**
```powershell
.\scripts\scaling-demo.ps1
```

**Terminal 1 will show:**
```
NAME      READY
gateway   0/0     ← zero pods (no traffic)
gateway   1/1     ← 1 pod (light load)
gateway   3/3     ← 3 pods (medium load)
gateway   5/5     ← 5 pods (heavy load)
gateway   3/3     ← cooling down
gateway   0/0     ← back to zero
```

📸 **Screenshot both terminals** — proves scaling up and back to zero.

### 3g. Measure cold vs warm latency

First, ensure gateway is at 0 replicas, then remove KEDA:

```powershell
kubectl delete httpscaledobject gateway-http-scaler -n checkout-demo
```

**COLD start (pod creation + first request):**
```powershell
$cold = Measure-Command {
    kubectl scale deploy gateway -n checkout-demo --replicas=1
    kubectl rollout status deploy/gateway -n checkout-demo --timeout=60s
}
Write-Host "COLD start (pod creation): $($cold.TotalSeconds) seconds"
```

**First request to fresh pod:**
```powershell
$coldReq = Measure-Command {
    Invoke-RestMethod -Uri http://localhost:8080/api/checkout -Method POST `
      -ContentType "application/json" `
      -Headers @{"X-Request-Id"="cold-001"} `
      -Body '{"items":[{"item_id":"item-1","quantity":1}]}'
}
Write-Host "COLD request latency: $($coldReq.TotalMilliseconds) ms"
```

**5 WARM requests (pod already running):**
```powershell
1..5 | ForEach-Object {
    $n = $_
    $w = Measure-Command {
        Invoke-RestMethod -Uri http://localhost:8080/api/checkout -Method POST `
          -ContentType "application/json" `
          -Body '{"items":[{"item_id":"item-1","quantity":1}]}'
    }
    Write-Host "WARM request ${n}: $($w.TotalMilliseconds) ms"
}
```

📸 **Screenshot cold and warm results.**

**Re-apply KEDA:**
```powershell
kubectl apply -f k8s/keda/httpscaledobject-gateway-scale-to-zero.yaml
```

### 3h. Latency table for report

| Scenario | Latency |
|----------|---------|
| Cold start (pod creation to ready) | ~6–13 seconds |
| COLD request (first request to new pod) | ~200–500 ms |
| WARM requests (average) | ~50–150 ms |

---

## REQUIREMENT 4: Request Correlation / Tracing-Lite

> **What to show:** X-Request-Id propagated across gateway → checkout → pricing → inventory.

### 4a. Ensure gateway is running

```powershell
# If KEDA scaled it to zero, bring it back:
kubectl delete httpscaledobject gateway-http-scaler -n checkout-demo
kubectl scale deploy gateway -n checkout-demo --replicas=1
kubectl rollout status deploy/gateway -n checkout-demo --timeout=60s
```

### 4b. Send request with known X-Request-Id

```powershell
Invoke-RestMethod -Uri http://localhost:8080/api/checkout -Method POST `
  -ContentType "application/json" `
  -Headers @{"X-Request-Id"="TRACE-ABC-123"} `
  -Body '{"items":[{"item_id":"item-1","quantity":2}]}'
```

### 4c. Check logs across ALL services

```powershell
# Gateway logs
kubectl logs -l app=gateway -n checkout-demo --tail=10 | Select-String "TRACE-ABC-123"

# Checkout logs
kubectl logs -l app=checkout -n checkout-demo --tail=10 | Select-String "TRACE-ABC-123"

# Pricing logs
kubectl logs -l app=pricing -n checkout-demo --tail=10 | Select-String "TRACE-ABC-123"

# Inventory logs
kubectl logs -l app=inventory -n checkout-demo --tail=10 | Select-String "TRACE-ABC-123"
```

📸 **Screenshot all 4 log outputs** — same `TRACE-ABC-123` appears in all services.

### 4d. Show auto-generated request ID (no header sent)

```powershell
Invoke-RestMethod -Uri http://localhost:8080/api/checkout -Method POST `
  -ContentType "application/json" `
  -Body '{"items":[{"item_id":"item-1","quantity":1}]}'
# Check: response includes auto-generated X-Request-Id

kubectl logs -l app=gateway -n checkout-demo --tail=5
kubectl logs -l app=checkout -n checkout-demo --tail=5
```

---

## REQUIREMENT 5: Troubleshooting Evidence

> **What to show:** Repeatable diagnosis workflow with 5 categories of evidence.

### 5a. "What exists" — show all resources

```powershell
kubectl get deploy,pods,svc,ingress -n checkout-demo
kubectl get scaledobjects,httpscaledobjects -n checkout-demo
kubectl get pvc,secrets -n checkout-demo
kubectl get networkpolicies -n checkout-demo
```

📸 **Screenshot this.**

### 5b. Failure mode — simulate bad image

```powershell
# Deploy bad image to trigger failure
kubectl set image deploy/checkout checkout=chinni-checkout:BROKEN -n checkout-demo

# Wait ~30 seconds, then show failure
kubectl get pods -n checkout-demo
kubectl describe pod -l app=checkout -n checkout-demo | Select-String -Pattern "Events:" -Context 0,20
kubectl get events -n checkout-demo --sort-by='.lastTimestamp' | Select-Object -Last 15
```

📸 **Screenshot this** — shows ImagePullBackOff or ErrImageNeverPull.

```powershell
# Restore correct image
kubectl set image deploy/checkout checkout=chinni-checkout:latest -n checkout-demo
kubectl get pods -n checkout-demo -w
```

### 5c. Logs evidence

```powershell
kubectl logs -l app=gateway -n checkout-demo --tail=20
kubectl logs -l app=checkout -n checkout-demo --tail=20
kubectl logs -l app=pricing -n checkout-demo --tail=20
kubectl logs -l app=inventory -n checkout-demo --tail=20
kubectl logs -l app=postgres -n checkout-demo --tail=10
```

### 5d. Service routing evidence

```powershell
kubectl get endpoints -n checkout-demo
kubectl get endpointslices -n checkout-demo
```

📸 **Screenshot this** — shows pod IPs backing each service.

### 5e. Inside-cluster connectivity check

```powershell
kubectl run toolbox --image=curlimages/curl -n checkout-demo --rm -it --restart=Never -- sh

# Inside the toolbox:
curl -s http://gateway:80/api/ping
curl -s http://checkout:8003/health
curl -s http://pricing:8001/health
curl -s http://inventory:8002/health
exit
```

📸 **Screenshot the inside-cluster results.**

---

## REQUIREMENT 6: Persistence (Postgres)

> **What to show:** Secret-managed credentials, PVC storage, data survives pod restart.

### 6a. Show secret-managed credentials

```powershell
kubectl get secret postgres-credentials -n checkout-demo -o yaml
# Shows base64-encoded POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB
```

### 6b. Show PVC-backed storage

```powershell
kubectl get pvc -n checkout-demo
# Expected: postgres-pvc  Bound  1Gi
```

### 6c. Insert a row via checkout API

```powershell
Invoke-RestMethod -Uri http://localhost:8080/api/checkout -Method POST `
  -ContentType "application/json" `
  -Headers @{"X-Request-Id"="persist-test-001"} `
  -Body '{"items":[{"item_id":"item-1","quantity":3}]}'
# Note the order_id in the response
```

### 6d. Verify the row in Postgres

```powershell
kubectl exec deploy/postgres -n checkout-demo -- psql -U checkout -d checkout -t -c "SELECT id, request_id, total_cost FROM orders ORDER BY id DESC LIMIT 5;"
# Expected: row with request_id='persist-test-001'
```

📸 **Screenshot the SELECT output.**

### 6e. Restart the Postgres pod

```powershell
kubectl delete pod -l app=postgres -n checkout-demo
kubectl get pods -n checkout-demo -l app=postgres -w
# Wait for new pod to be ready
```

### 6f. Verify data persisted after restart

```powershell
kubectl exec deploy/postgres -n checkout-demo -- psql -U checkout -d checkout -t -c "SELECT id, request_id, total_cost FROM orders ORDER BY id DESC LIMIT 5;"
# Expected: SAME rows — data survived the restart!
```

📸 **Screenshot this** — proves PVC persistence works.

---

## REQUIREMENT 7: Monitoring & Observability (CA-2)

> **What to show:** Prometheus scraping metrics from all services, Grafana dashboards with RED metrics.

### 7a. Verify /metrics endpoint on every service

```powershell
kubectl run metrics-test --image=curlimages/curl -n checkout-demo --labels="app=prometheus" --rm -it --restart=Never -- sh

# Inside the pod:
curl -s http://gateway:80/metrics | head -20
curl -s http://checkout:8003/metrics | head -20
curl -s http://pricing:8001/metrics | head -20
curl -s http://inventory:8002/metrics | head -20
exit
```

📸 **Screenshot the /metrics output** — proves all 4 services expose Prometheus metrics.

### 7b. Show instrumentation in source code

```powershell
Select-String -Path ".\services\gateway\main.py" -Pattern "Instrumentator|prometheus"
Select-String -Path ".\services\checkout\main.py" -Pattern "Instrumentator|prometheus"
Select-String -Path ".\services\pricing\main.py" -Pattern "Instrumentator|prometheus"
Select-String -Path ".\services\inventory\main.py" -Pattern "Instrumentator|prometheus"
```

📸 **Screenshot this** — shows `prometheus-fastapi-instrumentator` integrated in all services.

### 7c. Verify Prometheus is running

```powershell
kubectl get pods -n checkout-demo -l app=prometheus
# Expected: 1/1 Running
```

### 7d. Verify Grafana is running

```powershell
kubectl get pods -n checkout-demo -l app=grafana
# Expected: 1/1 Running
```

📸 **Screenshot both** — shows monitoring stack is deployed.

### 7e. Port-forward Prometheus & Grafana

Open **2 separate terminals:**

**Terminal 1 — Prometheus:**
```powershell
kubectl port-forward svc/prometheus 9090:9090 -n checkout-demo
# Available at: http://localhost:9090
```

**Terminal 2 — Grafana:**
```powershell
kubectl port-forward svc/grafana 3000:3000 -n checkout-demo
# Available at: http://localhost:3000  (login: admin / admin)
```

### 7f. Generate traffic for metrics

```powershell
1..10 | ForEach-Object {
    $n = $_
    try {
        Invoke-RestMethod -Uri http://localhost:8080/api/checkout -Method POST `
          -ContentType "application/json" `
          -Headers @{"X-Request-Id"="metrics-test-$n"} `
          -Body '{"items":[{"item_id":"item-1","quantity":1}]}'
        Write-Host "Request $n : OK"
    } catch {
        Write-Host "Request $n : ERROR"
    }
    Start-Sleep -Milliseconds 500
}
```

### 7g. Verify Prometheus targets

Open **http://localhost:9090/targets** in your browser.

📸 **Screenshot this** — all 4 targets (gateway, checkout, pricing, inventory) show as **UP**.

### 7h. Query metrics in Prometheus UI

Open **http://localhost:9090/graph** and run these queries:

```promql
# Total HTTP requests across all services
http_requests_total

# Request rate per service (requests/second)
rate(http_requests_total[1m])

# Average request duration per service
rate(http_request_duration_seconds_sum[1m]) / rate(http_request_duration_seconds_count[1m])

# Error rate (5xx status codes)
rate(http_requests_total{status=~"5.."}[1m])
```

📸 **Screenshot each query result.**

### 7i. Access Grafana & verify data source

1. Open **http://localhost:3000** → login: `admin` / `admin`
2. Go to **Connections → Data Sources**
3. Verify **Prometheus** is listed and connected

📸 **Screenshot the data sources page.**

### 7j. Create a Grafana dashboard

1. Click **+** → **New Dashboard** → **Add Visualization**
2. Select **Prometheus** as data source
3. Add 4 panels:

| Panel | PromQL Query |
|-------|-------------|
| Request Rate | `sum(rate(http_requests_total[1m])) by (job)` |
| Error Rate | `sum(rate(http_requests_total{status=~"5.."}[1m])) by (job)` |
| Latency (p95) | `histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[1m])) by (le, job))` |
| In-Progress | `http_requests_in_progress` |

📸 **Screenshot the completed dashboard** — shows RED metrics visualized.

### Why Prometheus + Grafana Matters (for report)

> Prometheus collects metrics from all four microservices via their `/metrics` endpoints, auto-instrumented using `prometheus-fastapi-instrumentator`. This library automatically tracks HTTP request counts, durations, sizes, and in-flight requests. Grafana connects to Prometheus and provides real-time dashboards showing **RED metrics** — Rate (requests/sec), Error rate (5xx/sec), and Duration (latency percentiles). This monitoring stack enables detection of performance degradation, error spikes, and correlation of issues across services in real-time.

---

## REQUIREMENT 8: Security Hardening & Network Policies (CA-2)

> **What to show:** Non-root containers, NetworkPolicies restricting traffic, verified isolation.

### 8a. Show Dockerfile security (non-root user)

```powershell
Get-Content .\services\gateway\Dockerfile
# Look for: RUN useradd -u 1000 -m appuser / USER appuser
```

📸 **Screenshot this** — proves Dockerfile creates non-root user.

### 8b. Verify non-root inside running containers

```powershell
kubectl exec deploy/gateway -n checkout-demo -- whoami
# Expected: appuser

kubectl exec deploy/checkout -n checkout-demo -- whoami
# Expected: appuser

kubectl exec deploy/pricing -n checkout-demo -- whoami
# Expected: appuser

kubectl exec deploy/inventory -n checkout-demo -- whoami
# Expected: appuser
```

📸 **Screenshot all 4 outputs** — all containers run as `appuser`, not root.

### 8c. Show Network Policies

```powershell
kubectl get networkpolicies -n checkout-demo
# Expected: 5 policies listed
```

📸 **Screenshot this.**

### 8d. Describe Network Policy rules

```powershell
kubectl describe networkpolicy gateway-netpol -n checkout-demo
kubectl describe networkpolicy checkout-netpol -n checkout-demo
kubectl describe networkpolicy postgres-netpol -n checkout-demo
```

📸 **Screenshot these** — shows ingress/egress rules per service.

### 8e. Test network isolation

```powershell
# A random pod should NOT reach postgres directly
kubectl run test-isolation --image=curlimages/curl -n checkout-demo --rm -it --restart=Never -- sh -c "curl -s --connect-timeout 3 http://postgres:5432 || echo 'CONNECTION BLOCKED'"

# Expected: timeout/blocked (NetworkPolicy prevents direct access)
```

📸 **Screenshot this** — proves network isolation works.

### 8f. Verify legitimate traffic still flows

```powershell
Invoke-RestMethod -Uri http://localhost:8080/api/checkout -Method POST `
  -ContentType "application/json" `
  -Headers @{"X-Request-Id"="security-test-001"} `
  -Body '{"items":[{"item_id":"item-1","quantity":2}]}'

# Expected: 200 OK, total_cost=20 — legitimate path still works!
```

📸 **Screenshot this** — proves legitimate traffic flows through policies.

---

## REQUIREMENT 9: Security Testing (CA-2)

> **What to show:** Trivy image vulnerability scanning, Kubescape K8s config scanning.

### 9a. Install Trivy

```powershell
# Option A: Chocolatey
choco install trivy

# Option B: Download from https://github.com/aquasecurity/trivy/releases
```

### 9b. Scan Docker images for vulnerabilities

```powershell
trivy image chinni-gateway:latest
trivy image chinni-checkout:latest
trivy image chinni-pricing:latest
trivy image chinni-inventory:latest
```

📸 **Screenshot each scan** — shows CVE findings per image.

### 9c. Filter HIGH and CRITICAL only

```powershell
trivy image --severity HIGH,CRITICAL chinni-gateway:latest
trivy image --severity HIGH,CRITICAL chinni-checkout:latest
```

📸 **Screenshot filtered output.**

### 9d. Save Trivy reports

```powershell
trivy image --format table chinni-gateway:latest > trivy-gateway-report.txt
trivy image --format table chinni-checkout:latest > trivy-checkout-report.txt
trivy image --format table chinni-pricing:latest > trivy-pricing-report.txt
trivy image --format table chinni-inventory:latest > trivy-inventory-report.txt
```

### 9e. Install Kubescape

```powershell
# Option A: Chocolatey
choco install kubescape

# Option B: Download from https://github.com/kubescape/kubescape/releases
```

### 9f. Scan K8s manifests

```powershell
kubescape scan k8s/

# Or with NSA framework:
kubescape scan framework nsa k8s/
```

📸 **Screenshot the output** — shows posture score and findings.

### 9g. Document findings table (for report)

| Finding | Severity | Tool | Status |
|---------|----------|------|--------|
| Non-root containers | — | Kubescape | ✅ PASS (`USER appuser` in Dockerfiles) |
| Network policies applied | — | Kubescape | ✅ PASS (`k8s/security/network-policies.yaml`) |
| Resource limits set | — | Kubescape | ✅ PASS (requests + limits on all deployments) |
| Readiness/liveness probes | — | Kubescape | ✅ PASS (HTTP probes on all services) |
| Secrets not hardcoded | — | Kubescape | ✅ PASS (Kubernetes Secret object) |
| Base image CVEs | HIGH | Trivy | ⚠️ Mitigate by upgrading to `python:3.12-slim` |

---

## Full Summary Checklist

| # | Requirement | Source | How to Demonstrate |
|---|------------|--------|-------------------|
| 1 | Microservices composition | CA-1 | Show 4 services + successful checkout flow |
| 2 | Reliability & partial failures | CA-1 | Scale pricing to 0, gateway stays up, checkout fails fast |
| 3 | KEDA scaling | CA-1 | Scale-to-zero, scale-from-zero, cold vs warm latency |
| 4 | Request correlation | CA-1 | Send X-Request-Id, grep logs across 4 services |
| 5 | Troubleshooting | CA-1 | Run 5 diagnosis categories with screenshots |
| 6 | Persistence | CA-1 | Insert row → restart pod → verify row exists |
| 7 | Monitoring (Prometheus + Grafana) | CA-2 | /metrics endpoints, Prometheus targets UP, Grafana dashboard |
| 8 | Security hardening | CA-2 | Non-root user, NetworkPolicies, isolation test |
| 9 | Security testing | CA-2 | Trivy image scan, Kubescape manifest scan |

---

## Quick Reference Commands

```powershell
# ──────────────────────────────────────
# BUILD & DEPLOY
# ──────────────────────────────────────
cd c:\Users\bhara\Desktop\Final\Chinni

# Build all images
docker build -t chinni-gateway:latest  ./services/gateway
docker build -t chinni-checkout:latest ./services/checkout
docker build -t chinni-pricing:latest  ./services/pricing
docker build -t chinni-inventory:latest ./services/inventory

# Load images into kind cluster (REQUIRED — kind can't see Docker images!)
kind load docker-image chinni-gateway:latest  --name demo-cluster
kind load docker-image chinni-checkout:latest --name demo-cluster
kind load docker-image chinni-pricing:latest  --name demo-cluster
kind load docker-image chinni-inventory:latest --name demo-cluster

# Deploy everything
kubectl apply -f k8s/base/namespace.yaml
kubectl apply -f k8s/db/secret.yaml
kubectl apply -f k8s/db/pvc.yaml
kubectl apply -f k8s/db/postgres-deployment.yaml
kubectl apply -f k8s/base/
kubectl apply -f k8s/monitoring/prometheus-configmap.yaml
kubectl apply -f k8s/monitoring/prometheus-deployment.yaml
kubectl apply -f k8s/monitoring/grafana-datasource.yaml
kubectl apply -f k8s/monitoring/grafana-deployment.yaml
kubectl apply -f k8s/security/network-policies.yaml

# Check everything
kubectl get all -n checkout-demo

# ──────────────────────────────────────
# PORT FORWARDING (for browser access)
# ──────────────────────────────────────
kubectl port-forward svc/prometheus 9090:9090 -n checkout-demo
kubectl port-forward svc/grafana 3000:3000 -n checkout-demo

# ──────────────────────────────────────
# URLS
# ──────────────────────────────────────
# Gateway UI:     http://localhost:8080/
# Prometheus:     http://localhost:9090
# Grafana:        http://localhost:3000  (admin / admin)

# ──────────────────────────────────────
# KEDA (install once)
# ──────────────────────────────────────
kubectl apply --server-side --force-conflicts -f https://github.com/kedacore/keda/releases/download/v2.19.0/keda-2.19.0.yaml
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install http-add-on kedacore/keda-add-ons-http -n keda
kubectl apply -f k8s/keda/httpscaledobject-gateway-scale-to-zero.yaml
kubectl apply -f k8s/keda/scaledobject-checkout.yaml

# ──────────────────────────────────────
# DISABLE KEDA (to manually control replicas)
# ──────────────────────────────────────
kubectl delete httpscaledobject gateway-http-scaler -n checkout-demo
kubectl scale deploy gateway -n checkout-demo --replicas=1
kubectl rollout status deploy/gateway -n checkout-demo --timeout=60s

# ──────────────────────────────────────
# RE-ENABLE KEDA
# ──────────────────────────────────────
kubectl apply -f k8s/keda/httpscaledobject-gateway-scale-to-zero.yaml
```
