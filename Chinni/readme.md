# ETP Design CA-2

This script is refined to match the **exact timeline, commands, and sequence** specified in the **CA-2 Submission Plan PDF**.

---

## ⚙️ PRE-RECORDING SETUP (Do this before recording)

### 1. Open Docker Desktop
Ensure Docker Desktop is running and the cluster is active.

### 2. Open 4 Separate PowerShell Windows
*   **Terminal 1 (MAIN):** This is the window you will share/record. Keep it focused and clear.
    ```powershell
    cd "c:\Users\bhara\Desktop\Final\Chinni"
    ```
*   **Terminal 2 (Port-Forward Gateway):** Run this and minimize it.
    ```powershell
    kubectl port-forward svc/gateway 8080:80 -n checkout-demo
    ```
*   **Terminal 3 (Port-Forward Prometheus):** Run this and minimize it.
    ```powershell
    kubectl port-forward svc/prometheus 9090:9090 -n checkout-demo
    ```
*   **Terminal 4 (Port-Forward Grafana):** Run this and minimize it.
    ```powershell
    kubectl port-forward svc/grafana 3000:3000 -n checkout-demo
    ```

### 3. Open Browser Tabs
*   **Tab 1:** Prometheus Targets — [http://localhost:9090/targets](http://localhost:9090/targets)
*   **Tab 2:** Prometheus Graph (Graph tab) — [http://localhost:9090/graph](http://localhost:9090/graph)
*   **Tab 3:** Grafana Login — [http://localhost:3000](http://localhost:3000)
    *   *Credential:* Username `admin`, Password `admin`. Click **Skip** on the change password screen.
    *   *Navigate to:* Dashboards → **Chinni** Folder → **Chinni Checkout System RED Metrics**.
*   **Tab 4:** Grafana Datasources page — [http://localhost:3000/datasources](http://localhost:3000/datasources) (click on the **Prometheus** datasource configuration so it's ready to show).

### 4. Send Warm-up Requests (So charts are populated)
In **Terminal 1**, execute this command to generate immediate traffic before starting:
```powershell
1..20 | ForEach-Object { try { Invoke-RestMethod -Uri http://localhost:8080/api/checkout -Method POST -ContentType "application/json" -Body '{"items":[{"item_id":"item-1","quantity":1}]}' } catch {} }
```

### 5. Open VS Code
Open the project in VS Code and keep it ready in the background:
```powershell
code .
```

---

## 🎬 SCREENCAST SCENE-BY-SCENE PLAN (Record using OBS or Win+G)

### SCENE 1 — Project Introduction (0:00 – 0:30)

*   **SHOW:** VS Code with the project folder open.
*   **DO:** Click on `services` folder in VS Code to expand it — show the 4 service folders.
*   **SAY:**
    > "Hi, I'm [Your Name], Student ID: [Your ID]. This is my screencast for the ETP Design CA-2 assignment. 
    > The project we are looking at is a Nanoservices Checkout System deployed on Kubernetes. It is built around a secure, distributed architecture consisting of four Python FastAPI microservices:
    > 1. The Gateway service on port 8000, which serves as the public edge routing user checkout requests.
    > 2. The Checkout service on port 8003, which handles the core business logic.
    > 3. The Pricing service on port 8001, calculating bulk discounts and pricing rules.
    > 4. The Inventory service on port 8002, verifying stock levels in real-time.
    > Persistence is managed by a PostgreSQL database on port 5432, which stores completed order records via a persistent volume claim."

*   **DO:** Click on `k8s` folder in VS Code to expand it — show `base`, `db`, `monitoring`, `security` folders.
*   **SAY:**
    > "Under the `k8s` directory, we have orchestrated all resources declaratively. In this CA-2 phase, the primary goals were securing this multi-tier application by implementing non-root user sandboxing, enforcing zero-trust Network Policies, adding full telemetry monitoring using Prometheus and Grafana, and validating our security posture with Trivy and Kubescape scans. Let's walk through these features in detail."

---

### Scene 2: Kubernetes Pods Status (0:30 – 1:30)
*   **SHOW:** Switch to **Terminal 1** (PowerShell).
*   **RUN:**
    ```powershell
    kubectl get pods -n checkout-demo
    ```
*   **SAY:**
    > "First, let's verify our running workloads in the cluster. As you can see, all 7 pods are running successfully in the `checkout-demo` namespace: our four microservices—gateway, checkout, pricing, and inventory—plus postgres, prometheus, and grafana. All show status running and 1/1 ready."

---

### Scene 3: Hardened Non-Root Workloads (1:30 – 2:30)
*   **SHOW:** Terminal 1.
*   **RUN:**
    ```powershell
    kubectl exec deploy/gateway -n checkout-demo -- whoami
    kubectl exec deploy/checkout -n checkout-demo -- whoami
    kubectl exec deploy/pricing -n checkout-demo -- whoami
    kubectl exec deploy/inventory -n checkout-demo -- whoami
    ```
*   **SAY:**
    > "For workload security, all containers run under a non-privileged user instead of root. Running the `whoami` command inside all four running containers proves that they execute as the non-root `appuser`. This significantly reduces the risk of container escape and node compromise."

---

### Scene 4: Network Policies Deployment (2:30 – 3:30)
*   **SHOW:** Terminal 1.
*   **RUN:**
    ```powershell
    kubectl get networkpolicies -n checkout-demo
    ```
    *(Let the output print, then run the next command)*
    ```powershell
    kubectl describe networkpolicy checkout-netpol -n checkout-demo
    ```
*   **SAY:**
    > "Next, we have enforced network isolation. Running `kubectl get networkpolicies` shows five active network policies implementing a least-privilege boundary. Looking at the description for the checkout service network policy, we can see ingress is strictly limited to the gateway on port 8003, and egress is only allowed to pricing on port 8001, inventory on port 8002, and postgres on port 5432."

---

### Scene 5: Grafana Monitoring & Dashboards (3:30 – 4:30)
*   **SHOW:** Switch to the browser tab for Grafana Dashboard (`http://localhost:3000`). Show the RED Metrics dashboard panels.
*   **DO:** (Optional) Switch to the Grafana Datasource configuration tab showing the Prometheus connection status.
*   **SAY:**
    > "Moving on to observability. This is our Grafana dashboard visualizing the RED metrics: Request Rate, Error Rate, and P95 Latency. The dashboard is backed by our auto-provisioned Prometheus data source pointing to the in-cluster Prometheus instance."

---

### Scene 6: Live Checkout Request & Metrics Update (4:30 – 5:30)
*   **SHOW:** Switch back to **Terminal 1** (PowerShell).
*   **RUN:**
    ```powershell
    Invoke-RestMethod -Uri http://localhost:8080/api/checkout -Method POST -ContentType "application/json" -Headers @{"X-Request-Id"="screencast-live-999"} -Body '{"items":[{"item_id":"item-1","quantity":2}]}'
    ```
    *(See the JSON response showing total_cost, order_id, and request_id)*
*   **DO:** Switch back to the Grafana dashboard browser tab and show the request count/rate updating in real-time.
*   **SAY:**
    > "Let's perform a live checkout request using an explicit request ID: `screencast-live-999`. The gateway routes the request and returns a successful response from the checkout service. The Grafana dashboard reflects the incoming load immediately. We also correlate logs across microservices using this request ID header."

---

### Scene 7: Prometheus Scraping & Target Status (5:30 – 6:30)
*   **SHOW:** Switch to the browser tab for Prometheus Targets (`http://localhost:9090/targets`).
*   **DO:** (Optional) Switch to the Prometheus Graph tab and run the query: `rate(http_requests_total[1m])`.
*   **SAY:**
    > "In the Prometheus Targets view, we can confirm that Prometheus is actively scraping the `/metrics` endpoint of all 4 microservices. All endpoints show up as green and healthy. We can also query metrics directly in Prometheus using PromQL to visualize query rates."

---

### Scene 8: Security Posture Review & Scanning (6:30 – 7:30)
*   **SHOW:** Switch back to **Terminal 1** or open files directly.
*   **RUN:**
    ```powershell
    Get-Content .\trivy-gateway-report.txt | Select-Object -First 30
    ```
    *(Let it output, then open the Kubescape PDF)*
    ```powershell
    Start-Process .\kubescape-report.pdf
    ```
*   **SAY:**
    > "For security validation, we integrated Trivy vulnerability scanning and Kubescape posture reviews. Opening the Trivy report shows container image vulnerability assessments. Looking at the Kubescape PDF report, we achieve an overall compliance score of 84%, confirming compliance across controls such as host network isolation and non-root workloads."

---

### Scene 9: Automated Verification Suite (7:30 – 8:30)
*   **SHOW:** Close the PDF, return to **Terminal 1**.
*   **RUN:**
    ```powershell
    powershell -ExecutionPolicy Bypass -File "scripts\verify-all.ps1"
    ```
*   **SAY:**
    > "We run an automated verification suite that executes seven comprehensive health and compliance checks. This includes verifying all pods are running, non-root execution, network policy enforcement, API connectivity, Prometheus scrape status, and scan report presence. As you can see, all 7 checks pass successfully."

---

### Scene 10: Dockerfile workload hardening (8:30 – 9:00)
*   **SHOW:** Switch to VS Code and show the `services/gateway/Dockerfile` (or any other microservice Dockerfile).
*   **SAY:**
    > "To show how this workload hardening was achieved at the source, let's look at the Dockerfile. We added user creation, modified file ownership with `chown`, and set the container runtime environment to run under `USER appuser` instead of root."

---

### Scene 11: Summary & Conclusion (9:00 – 10:00)
*   **SHOW:** Focus back on Terminal 1 with the verification success output visible.
*   **SAY:**
    > "In summary, we have hardened the system by implementing non-root container runs and strict network policies. We configured full observability using Prometheus and Grafana, and validated the system through automated verification and static scans. Everything is fully functional and secured. Thank you."

---

## 🗃️ AFTER RECORDING (Cleanup & Submission preparation)

Once your recording is complete and saved, run these steps in **Terminal 1** to prepare the zip file for submission without including massive executables:

```powershell
# Remove the large binary files to keep zip size small
Remove-Item .\trivy.exe -Force
Remove-Item .\kubescape.exe -Force
Remove-Item .\kubescape_v2.exe -Force
Remove-Item .\kubescape_v3.exe -Force
Remove-Item -Recurse .\.venv -Force
Remove-Item -Recurse .\.pytest_cache -Force
```

Then zip your `Chinni` project folder and upload it to Brightspace along with your **OneDrive video link**!
