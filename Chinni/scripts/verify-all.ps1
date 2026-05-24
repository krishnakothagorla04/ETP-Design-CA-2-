# ETP Design CA-2 Automated Verification Script
# This script executes all verification checks step-by-step to validate compliance.

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " ETP Design CA-2 Automated Project Verification" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$Passed = 0
$Failed = 0

function Assert-Step {
    param(
        [string]$Name,
        [scriptblock]$Test
    )
    Write-Host "Running check: $Name..." -NoNewline -ForegroundColor Yellow
    try {
        $result = &$Test
        if ($result -eq $true) {
            Write-Host " [PASS]" -ForegroundColor Green
            $script:Passed++
        } else {
            Write-Host " [FAIL]" -ForegroundColor Red
            $script:Failed++
        }
    } catch {
        Write-Host " [FAIL] (Error: $($_.Exception.Message))" -ForegroundColor Red
        $script:Failed++
    }
}

# 1. Verify Pod Status
Assert-Step "All Pods running in namespace 'checkout-demo'" {
    $pods = kubectl get pods -n checkout-demo -o json | ConvertFrom-Json
    $allRunning = $true
    foreach ($pod in $pods.items) {
        $status = $pod.status.phase
        if ($status -ne "Running") {
            $allRunning = $false
            Write-Host "      Pod $($pod.metadata.name) is in state: $status" -ForegroundColor Red
        }
    }
    $allRunning
}

# 2. Verify Non-Root User Runtime
Assert-Step "Containers running as non-root user (appuser)" {
    $services = @("gateway", "checkout", "pricing", "inventory")
    $allNonRoot = $true
    foreach ($svc in $services) {
        $user = kubectl exec deploy/$svc -n checkout-demo -- whoami
        if ($user.Trim() -ne "appuser") {
            $allNonRoot = $false
            Write-Host "      Service $svc runs as: $user" -ForegroundColor Red
        }
    }
    $allNonRoot
}

# 3. Verify NetworkPolicies Deployed
Assert-Step "All 5 NetworkPolicies deployed" {
    $netpols = kubectl get networkpolicy -n checkout-demo -o json | ConvertFrom-Json
    $count = $netpols.items.Count
    if ($count -eq 5) {
        $true
    } else {
        Write-Host "      Found $count network policies instead of 5." -ForegroundColor Red
        $false
    }
}

# 4. Verify Checkout Request Processing
Assert-Step "Legitimate checkout traffic processes successfully" {
    try {
        $resp = Invoke-RestMethod -Uri http://localhost:8080/api/checkout -Method POST `
            -ContentType "application/json" `
            -Headers @{"X-Request-Id"="automation-test-001"} `
            -Body '{"items":[{"item_id":"item-1","quantity":2}]}'
        if ($resp.total_cost -eq 20.0 -and $resp.order_id -gt 0) {
            $true
        } else {
            Write-Host "      Unexpected response total_cost: $($resp.total_cost)" -ForegroundColor Red
            $false
        }
    } catch {
        Write-Host "      Checkout request failed: $($_.Exception.Message)" -ForegroundColor Red
        $false
    }
}

# 5. Verify Prometheus Targets Scrape Status
Assert-Step "Prometheus targets scraping status is healthy" {
    try {
        $targets = Invoke-RestMethod -Uri http://localhost:9090/api/v1/targets
        $allUp = $true
        foreach ($target in $targets.data.activeTargets) {
            $job = $target.discoveredLabels.job
            $health = $target.health
            if ($health -ne "up") {
                # If gateway is scaled to zero by KEDA, it might be down which is expected under autoscaling,
                # but if we manually scaled gateway to 1 for port forwarding, all should be up.
                if ($job -ne "gateway" -or $health -ne "down") {
                    $allUp = $false
                    Write-Host "      Target $job status: $health" -ForegroundColor Red
                }
            }
        }
        $allUp
    } catch {
        Write-Host "      Prometheus targets check failed: $($_.Exception.Message)" -ForegroundColor Red
        $false
    }
}

# 6. Verify Trivy reports generated
Assert-Step "Trivy scan reports exist in workspace" {
    $exists = $true
    $reports = @("trivy-gateway-report.txt", "trivy-checkout-report.txt", "trivy-pricing-report.txt", "trivy-inventory-report.txt")
    foreach ($rep in $reports) {
        if (-not (Test-Path ".\$rep")) {
            $exists = $false
            Write-Host "      Missing Trivy report: $rep" -ForegroundColor Red
        }
    }
    $exists
}

# 7. Verify Kubescape scan completed
Assert-Step "Kubescape scan reports exist in workspace" {
    $exists = (Test-Path ".\kubescape-report.txt") -and (Test-Path ".\kubescape-report.pdf")
    if (-not $exists) {
        Write-Host "      Missing Kubescape reports" -ForegroundColor Red
    }
    $exists
}

$color = "Green"
if ($Failed -gt 0) { $color = "Red" }

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Verification Summary: $Passed Passed, $Failed Failed" -ForegroundColor $color
Write-Host "==========================================================" -ForegroundColor Cyan
