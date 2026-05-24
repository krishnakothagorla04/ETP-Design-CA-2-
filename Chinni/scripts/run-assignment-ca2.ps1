# ETP Design CA-2 End-to-End Orchestrator & Debugger
# This script automates every step of ETP-DESIGN-CA2, reporting failures and running diagnostics on errors.

$ErrorActionPreference = "Stop"
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " ETP Design CA-2 End-to-End Orchestrator & Debugger" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$Global:HasErrors = $false

function Run-Step {
    param(
        [string]$Name,
        [scriptblock]$Action,
        [string]$FailureMessage
    )
    Write-Host ">>> Running: $Name..." -ForegroundColor Green
    try {
        $result = &$Action
        Write-Host "[OK] Success: $Name Completed Successfully!" -ForegroundColor Green
        Write-Host ""
    } catch {
        Write-Host ""
        Write-Host "[ERROR] ERROR: Failed during '$Name'" -ForegroundColor Red
        Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
        if ($FailureMessage) {
            Write-Host "Hint: $FailureMessage" -ForegroundColor Yellow
        }
        $Global:HasErrors = $true
        Write-Host "Orchestration aborted due to critical error." -ForegroundColor Red
        Exit 1
    }
}

# Check Prerequisites
Run-Step "Checking prerequisites (Docker, Kubectl, Kind)" {
    if (-not (Get-Command "docker" -ErrorAction SilentlyContinue)) {
        throw "Docker is not installed or not in PATH."
    }
    if (-not (Get-Command "kubectl" -ErrorAction SilentlyContinue)) {
        throw "Kubectl is not installed or not in PATH."
    }
    if (-not (Get-Command "kind" -ErrorAction SilentlyContinue)) {
        throw "Kind is not installed or not in PATH."
    }
    # Check if Docker engine is running
    docker ps > $null
    # Check if Kind cluster is running
    $nodes = kubectl get nodes
    Write-Host "Cluster Status:" -ForegroundColor Gray
    Write-Host $nodes
    $true
} "Make sure Docker Desktop is open and the green status is visible, and the kind cluster is created."

# Step 1: Rebuild Microservice Docker Images
Run-Step "Rebuilding Docker images" {
    Write-Host "Building Gateway..." -ForegroundColor Gray
    docker build -t chinni-gateway:latest ./services/gateway
    Write-Host "Building Checkout..." -ForegroundColor Gray
    docker build -t chinni-checkout:latest ./services/checkout
    Write-Host "Building Pricing..." -ForegroundColor Gray
    docker build -t chinni-pricing:latest ./services/pricing
    Write-Host "Building Inventory..." -ForegroundColor Gray
    docker build -t chinni-inventory:latest ./services/inventory
    $true
} "Docker build failed. Verify Dockerfile syntax or ensure requirements.txt files are valid."

# Step 2: Load Images into Kind
Run-Step "Loading Docker images into Kind" {
    Write-Host "Loading chinni-gateway..." -ForegroundColor Gray
    kind load docker-image chinni-gateway:latest --name demo-cluster
    Write-Host "Loading chinni-checkout..." -ForegroundColor Gray
    kind load docker-image chinni-checkout:latest --name demo-cluster
    Write-Host "Loading chinni-pricing..." -ForegroundColor Gray
    kind load docker-image chinni-pricing:latest --name demo-cluster
    Write-Host "Loading chinni-inventory..." -ForegroundColor Gray
    kind load docker-image chinni-inventory:latest --name demo-cluster
    $true
} "Kind image load failed. Make sure the kind cluster name is 'demo-cluster' (verify using 'kind get clusters')."

# Step 3: Create Namespace & Deploy Database
Run-Step "Deploying PostgreSQL database" {
    kubectl apply -f k8s/base/namespace.yaml
    kubectl apply -f k8s/db/secret.yaml
    kubectl apply -f k8s/db/pvc.yaml
    kubectl apply -f k8s/db/postgres-deployment.yaml
    
    Write-Host "Waiting for PostgreSQL pod to be Ready..." -ForegroundColor Gray
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        $pod = kubectl get pods -n checkout-demo -l app=postgres -o json | ConvertFrom-Json
        if ($pod.items.Count -gt 0 -and $pod.items[0].status.phase -eq "Running" -and $pod.items[0].status.containerStatuses[0].ready) {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $ready) {
        # Debug helper
        Write-Host "PostgreSQL is not ready. Running diagnostics..." -ForegroundColor Red
        kubectl describe pod -n checkout-demo -l app=postgres
        kubectl logs -n checkout-demo -l app=postgres --tail=20
        throw "PostgreSQL startup timed out."
    }
    $true
} "Postgres deployment failed. Check K8s storage provisioner or secrets yaml."

# Step 4: Deploy Base Applications
Run-Step "Deploying microservices and ingress" {
    kubectl apply -f k8s/base/
    Write-Host "Restarting deployments to apply loaded images..." -ForegroundColor Gray
    kubectl rollout restart deploy gateway checkout pricing inventory -n checkout-demo
    
    Write-Host "Waiting for all microservice pods to be Ready..." -ForegroundColor Gray
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        $pods = kubectl get pods -n checkout-demo -o json | ConvertFrom-Json
        $allRunning = $true
        foreach ($pod in $pods.items) {
            # Skip database and monitoring pods since we are validating base app rollout here
            if ($pod.metadata.name -like "*grafana*" -or $pod.metadata.name -like "*prometheus*" -or $pod.metadata.name -like "*postgres*") {
                continue
            }
            if ($pod.status.phase -ne "Running" -or -not $pod.status.containerStatuses[0].ready) {
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
        Write-Host "Not all microservice pods are running. Diagnostics:" -ForegroundColor Red
        $pods = kubectl get pods -n checkout-demo -o json | ConvertFrom-Json
        foreach ($pod in $pods.items) {
            if ($pod.status.phase -ne "Running") {
                Write-Host "=== Pod details for $($pod.metadata.name) ===" -ForegroundColor Yellow
                kubectl describe pod -n checkout-demo $($pod.metadata.name)
                kubectl logs -n checkout-demo $($pod.metadata.name) --tail=20
            }
        }
        throw "Microservices rollout timed out or failed."
    }
    $true
} "Microservices deployment failed. Check image pull policies or container registry status."

# Step 5: Apply Security Network Policies
Run-Step "Applying Network Policies" {
    kubectl apply -f k8s/security/network-policies.yaml
    $netpols = kubectl get networkpolicies -n checkout-demo
    Write-Host "Network Policies applied:" -ForegroundColor Gray
    Write-Host $netpols
    $true
} "Network policies apply failed. Verify file path 'k8s/security/network-policies.yaml'."

# Step 6: Deploy Monitoring Stack
Run-Step "Deploying Prometheus and Grafana stack" {
    kubectl apply -f k8s/monitoring/
    
    Write-Host "Waiting for Prometheus and Grafana pods..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
    $pods = kubectl get pods -n checkout-demo -l "app in (prometheus, grafana)"
    Write-Host $pods
    $true
} "Monitoring stack apply failed. Verify manifests under 'k8s/monitoring/'."

# Step 7: Security Scans
Run-Step "Running Security Vulnerability & Posture Scans" {
    # 1. Trivy Download & Image Scan
    if (-not (Test-Path ".\trivy.exe")) {
        Write-Host "Downloading Trivy..." -ForegroundColor Gray
        curl.exe -L -o .\trivy.zip https://github.com/aquasecurity/trivy/releases/download/v0.70.0/trivy_0.70.0_windows-64bit.zip
        Expand-Archive -Path ".\trivy.zip" -DestinationPath "$env:TEMP\trivy" -Force
        Copy-Item "$env:TEMP\trivy\trivy.exe" -Destination ".\trivy.exe" -Force
        Remove-Item ".\trivy.zip" -Force
    }
    Write-Host "Scanning gateway image..." -ForegroundColor Gray
    .\trivy.exe image --format table --severity HIGH,CRITICAL --output trivy-gateway-report.txt chinni-gateway:latest
    Write-Host "Scanning checkout image..." -ForegroundColor Gray
    .\trivy.exe image --format table --severity HIGH,CRITICAL --output trivy-checkout-report.txt chinni-checkout:latest
    Write-Host "Scanning pricing image..." -ForegroundColor Gray
    .\trivy.exe image --format table --severity HIGH,CRITICAL --output trivy-pricing-report.txt chinni-pricing:latest
    Write-Host "Scanning inventory image..." -ForegroundColor Gray
    .\trivy.exe image --format table --severity HIGH,CRITICAL --output trivy-inventory-report.txt chinni-inventory:latest

    # 2. Kubescape Download & Manifest Scan
    if (-not (Test-Path ".\kubescape.exe")) {
        Write-Host "Downloading Kubescape..." -ForegroundColor Gray
        curl.exe -L -o .\kubescape.exe https://github.com/kubescape/kubescape/releases/download/v4.0.8/kubescape_4.0.8_windows_amd64.exe
    }
    Write-Host "Scanning Kubernetes manifests (Text report)..." -ForegroundColor Gray
    .\kubescape.exe scan k8s/ --format pretty-printer --output kubescape-report.txt
    Write-Host "Scanning Kubernetes manifests (PDF report)..." -ForegroundColor Gray
    .\kubescape.exe scan k8s/ --format pdf --output kubescape-report.pdf
    
    Write-Host "Reports saved:" -ForegroundColor Gray
    dir trivy-*-report.txt, kubescape-report.*
    $true
} "Vulnerability scanning failed. Verify network access to GitHub releases for downloads."

# Final Verification
Write-Host ""
if ($Global:HasErrors) {
    Write-Host "==========================================================" -ForegroundColor Yellow
    Write-Host " Assignment orchestration finished with some skipped warnings!" -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Yellow
} else {
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host " All assignment setup and security validation steps complete!" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "To test API manually, open a new terminal and run:"
    Write-Host "  kubectl port-forward svc/gateway 8080:80 -n checkout-demo"
    Write-Host "  kubectl port-forward svc/prometheus 9090:9090 -n checkout-demo"
    Write-Host "  kubectl port-forward svc/grafana 3000:3000 -n checkout-demo"
    Write-Host ""
}
