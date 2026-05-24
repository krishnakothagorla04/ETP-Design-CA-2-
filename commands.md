 kubectl get pods -n checkout-demo

2. 
 ```powershell
    kubectl exec deploy/gateway -n checkout-demo -- whoami
    kubectl exec deploy/checkout -n checkout-demo -- whoami
    kubectl exec deploy/pricing -n checkout-demo -- whoami
    kubectl exec deploy/inventory -n checkout-demo -- whoami
3. 
4.1 kubectl get networkpolicies -n checkout-demo
4.2  kubectl describe networkpolicy checkout-netpol -n checkout-demo
6.1 
 Invoke-RestMethod -Uri http://localhost:8080/api/checkout -Method POST -ContentType "application/json" -Headers @{"X-Request-Id"="screencast-live-999"} -Body '{"items":[{"item_id":"item-1","quantity":2}]}'

8.1  Get-Content .\trivy-gateway-report.txt | Select-Object -First 30
8.2  Start-Process .\kubescape-report.pdf
9 
powershell -ExecutionPolicy Bypass -File "scripts\verify-all.ps1"
