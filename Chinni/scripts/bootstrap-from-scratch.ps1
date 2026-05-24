# ETP Design CA-2 - Complete Clean Bootstrap & Execution Script
# This script configures the entire environment from scratch.

$ErrorActionPreference = "Stop"
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " ETP Design CA-2 Complete From-Scratch Bootstrapper" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$Global:HasErrors = $false

function Run-Bootstrap-Step {
    param(
        [string]$Name,
        [scriptblock]$Action,
        [string]$FailureMessage
    )
    Write-Host ">>> [BOOTSTRAP] Running: $Name..." -ForegroundColor Green
    try {
        $result = &$Action
        Write-Host "[OK] Success: $Name Completed!" -ForegroundColor Green
        Write-Host ""
    } catch {
        Write-Host ""
        Write-Host "[ERROR]: Failed during bootstrap step '$Name'" -ForegroundColor Red
        Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
        if ($FailureMessage) {
            Write-Host "Hint: $FailureMessage" -ForegroundColor Yellow
        }
        $Global:HasErrors = $true
        Write-Host "Bootstrap aborted due to critical error." -ForegroundColor Red
        Exit 1
    }
}

# Step 1: Check Docker
Run-Bootstrap-Step "Verifying Docker Engine is running" {
    if (-not (Get-Command "docker" -ErrorAction SilentlyContinue)) {
        throw "Docker is not installed or not in PATH."
    }
    docker ps > $null
    $true
} "Please open Docker Desktop and wait until the status bar is green."

# Step 2: Check or Create Kind Cluster
Run-Bootstrap-Step "Checking Kind Cluster status" {
    if (-not (Get-Command "kind" -ErrorAction SilentlyContinue)) {
        throw "Kind is not installed or not in PATH."
    }
    
    $clusters = kind get clusters
    if ($clusters -contains "demo-cluster") {
        Write-Host "  Kind cluster 'demo-cluster' already exists. Re-using cluster." -ForegroundColor Gray
    } else {
        Write-Host "  Kind cluster 'demo-cluster' not found. Creating new cluster with image kindest/node:v1.28.0..." -ForegroundColor Gray
        kind create cluster --name demo-cluster --image kindest/node:v1.28.0
    }
    
    # Configure kubectl context
    kubectl config use-context kind-demo-cluster > $null
    $nodes = kubectl get nodes
    Write-Host "Cluster Status:" -ForegroundColor Gray
    Write-Host $nodes
    $true
} "Make sure Docker is fully active and has sufficient resources configured."

# Step 3: Install KEDA Core
Run-Bootstrap-Step "Installing KEDA Operator (v2.19.0)" {
    Write-Host "  Applying KEDA Core manifests..." -ForegroundColor Gray
    kubectl apply --server-side --force-conflicts -f https://github.com/kedacore/keda/releases/download/v2.19.0/keda-2.19.0.yaml
    
    Write-Host "  Waiting for KEDA controller to be ready..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        $pods = kubectl get pods -n keda -o json | ConvertFrom-Json
        $allRunning = $true
        if ($pods.items.Count -eq 0) { $allRunning = $false }
        foreach ($pod in $pods.items) {
            if ($pod.status.phase -ne "Running") {
                $allRunning = $false
            }
        }
        if ($allRunning) {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 3
    }
    if (-not $ready) {
        throw "KEDA deployment pods are taking too long to start."
    }
    $true
} "Verify cluster network connectivity to GitHub."

# Step 4: Install KEDA HTTP Add-on
Run-Bootstrap-Step "Installing KEDA HTTP Add-on via Helm" {
    if (-not (Get-Command "helm" -ErrorAction SilentlyContinue)) {
        throw "Helm is not installed. Helm is required to deploy the KEDA HTTP Add-on."
    }
    
    Write-Host "  Configuring Helm Repo..." -ForegroundColor Gray
    helm repo add kedacore https://kedacore.github.io/charts 2>$null | Out-Null
    helm repo update
    
    $releases = helm list -n keda -o json | ConvertFrom-Json
    $installed = $false
    foreach ($rel in $releases) {
        if ($rel.name -eq "http-add-on") {
            $installed = $true
        }
    }
    
    if ($installed) {
        Write-Host "  KEDA HTTP Add-on already installed. Upgrading..." -ForegroundColor Gray
        helm upgrade http-add-on kedacore/keda-add-ons-http -n keda | Out-Null
    } else {
        Write-Host "  Installing KEDA HTTP Add-on..." -ForegroundColor Gray
        helm install http-add-on kedacore/keda-add-ons-http -n keda | Out-Null
    }
    
    Write-Host "  Waiting for HTTP Add-on pods to start..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
    $true
} "Ensure Helm is configured in your system environment PATH."

# Step 5: Run Application deployment and scans
Run-Bootstrap-Step "Deploying Chinni App, Security Policies, Monitoring & Running Scans" {
    Write-Host "  Invoking Orchestrator pipeline script..." -ForegroundColor Gray
    # Run the orchestrator script
    & ".\scripts\run-assignment-ca2.ps1"
    $true
} "Orchestration pipeline execution failed."

# Step 6: Start Port forwards in the background
Run-Bootstrap-Step "Establishing background port-forwards" {
    Write-Host "  Killing any existing port-forward processes..." -ForegroundColor Gray
    Stop-Process -Name "kubectl" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    
    Write-Host "  Temporarily scaling gateway to 1 to enable port-forwarding..." -ForegroundColor Gray
    kubectl scale deploy gateway -n checkout-demo --replicas=1 | Out-Null
    Start-Sleep -Seconds 3
    
    Write-Host "  Starting port forwards..." -ForegroundColor Gray
    # Start gateway port-forward
    Start-Process kubectl -ArgumentList "port-forward svc/gateway 8080:80 -n checkout-demo" -NoNewWindow
    # Start prometheus port-forward
    Start-Process kubectl -ArgumentList "port-forward svc/prometheus 9090:9090 -n checkout-demo" -NoNewWindow
    # Start grafana port-forward
    Start-Process kubectl -ArgumentList "port-forward svc/grafana 3000:3000 -n checkout-demo" -NoNewWindow
    
    Start-Sleep -Seconds 5
    $true
} "Port-forward setup failed. Verify ports 8080, 9090, and 3000 are not in use by other processes."

# Step 7: Generate Metrics Traffic
Run-Bootstrap-Step "Generating load traffic to populate RED metrics" {
    Write-Host "  Executing Python traffic generator..." -ForegroundColor Gray
    & python "$PSScriptRoot\send_requests.py"
    $true
} "Traffic generator execution failed."

# Step 8: Run Final Verification checker
Run-Bootstrap-Step "Executing automated verification checker" {
    & ".\scripts\verify-all.ps1"
    $true
} "Verification script reported one or more check failures."

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Bootstrap, Deployment, Scanning, & Verification Complete!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "To test API manually or query dashboards, open your browser:"
Write-Host "  - Grafana Visualization: http://localhost:3000 (admin / admin)"
Write-Host "  - Prometheus Target Metrics: http://localhost:9090"
Write-Host "  - API Gateway Endpoint: http://localhost:8080/api/checkout"
Write-Host ""
