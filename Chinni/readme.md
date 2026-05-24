# ETP Design CA-2

## Section 1: Secure Design Review & Architecture

### 1.1  Risks Identified in Assignment-1 System
The Assignment-1 deployment of the Checkout system shipped with four open weaknesses that a competent attacker could chain into a full cluster compromise. Containers ran as root, so any container break-out would land the attacker on the Kubernetes node as a privileged user. The cluster had no NetworkPolicies in place, so any compromised pod could reach any other pod over any port - lateral movement was trivial. No image scanning had been performed, leaving the team blind to known CVEs shipping in the python:3.10-slim base layer and transitive Python packages. Database credentials sat as plain values in the deployment YAML rather than being referenced from a Kubernetes Secret.

### 1.2  Mitigations Applied
Every service Dockerfile was rebuilt to create a dedicated appuser account (UID 1000), chown the working directory and drop privileges with USER appuser before the entrypoint. Runtime verification was performed by executing kubectl exec deploy/<name> -- whoami on each pod; all four returned appuser, confirming that the privilege drop took effect at runtime rather than only at build time.

Five NetworkPolicies were then applied to enforce least-privilege pod-to-pod communication. A default-deny ingress rule blocks everything, and explicit allow-rules permit only the legitimate paths: gateway accepts external traffic; checkout accepts traffic only from gateway; pricing and inventory accept traffic only from checkout; postgres accepts traffic only from checkout. The Prometheus pod (labelled app=prometheus) is whitelisted into every service on the metrics port so that observability is preserved.

## Section 2: Logging, Monitoring & Observability
### 2.1  What Was Added
The prometheus-fastapi-instrumentator library was added to the requirements of all four services and wired into each main.py during startup. The library automatically exposes /metrics on a Prometheus-friendly text format covering HTTP request counts, latency histograms and in-flight requests - the inputs required to compute the canonical RED indicators (Rate, Errors, Duration). A dedicated Prometheus deployment was added to scrape every service on a 15-second interval, and a Grafana deployment was added with Prometheus auto-provisioned as its default data source and a pre-built RED metrics dashboard.


### 2.2 Realistic Observability Scenario
Consider a real production fault: customer checkouts begin to fail intermittently. On the Grafana dashboard the Error Rate panel for the checkout job spikes from 0 % to roughly 10 % within a single 15-second scrape interval, while the Request Rate panel remains flat - so requests are still arriving but a fraction of them are failing. To pinpoint the cause, the operator runs kubectl logs deploy/checkout -n checkout-demo and pipes the output through Select-String filtering on the request_id of a failing call. Because every service propagates the inbound X-Request-Id header through every downstream call, a single grep on that ID surfaces the entire request chain - gateway received it, checkout received it, but the call to pricing failed with a ConnectError. Without the propagated request ID, the same diagnosis would require manually correlating four log streams by timestamp; with it, root cause is identified in seconds.

## Section 3: Security Testing
### 3.1  Vulnerability Scanning  -  Trivy
Trivy was used to scan all four microservice images with the --severity HIGH,CRITICAL filter and the JSON results were saved into the project root as trivy-{gateway,checkout,pricing,inventory}-report.txt for offline analysis. No CRITICAL vulnerabilities were identified. The scans returned four HIGH-severity findings in the libncursesw6 / libtinfo6 / ncurses-base / ncurses-bin family on the Debian 13.5 base layer (CVE-2025-69720), plus HIGH findings in the Python build-time packages jaraco.context (CVE-2026-23949) and wheel (CVE-2026-24049).

### 3.2  Configuration Posture Review  -  Kubescape
Kubescape was executed against the k8s/ manifest tree and returned an overall posture compliance score of 84 %. Three notable hardening controls passed cleanly: privileged container (C-0057), host network access (C-0041) and non-root containers (C-0013). Resource policies on all deployments also passed. Kubescape additionally identified the three highest-stake workloads (inventory, pricing, postgres), prioritising future hardening effort to where it yields the largest blast-radius reduction.

### 3.3  Deeper Test  -  Runtime Verification
Non-root execution was verified not just by manifest inspection but by kubectl exec deploy/<name> -- whoami on each running pod, returning appuser on all four services. NetworkPolicy enforcement was verified by deploying a test pod and attempting to reach pricing:8001 directly - the connection timed out after three seconds, confirming the policy is enforced and not merely declared. A 7-check automated harness (verify-all.ps1) ties everything together and returned 7 Passed, 0 Failed.

### 3.4  Findings Prioritisation
Priority
Finding
Status
Justification
Critical
Containers running as root
Fixed
Direct node compromise risk via container break-out.
High
No network isolation
Fixed
Lateral movement enables full cluster takeover.
Medium
4 HIGH CVEs in base image
Recommended
Upgrade to python:3.12-slim removes most OS-layer CVEs.
Low
No CPU/memory limits enforced
Recommended
Prevents resource exhaustion and DoS by noisy neighbours.


### 3.5  What Would Change Next
Three short-term improvements would tighten the posture further. First, upgrade the base image from python:3.10-slim to python:3.12-slim (or move to a distroless base) to retire the open ncurses CVE-2025-69720 in a single Dockerfile change. Second, add explicit CPU/memory limits to every deployment so that a runaway pod cannot exhaust the node. Third, implement mutual TLS between services using a service mesh such as Istio or Linkerd, so that the network plane is encrypted even inside the cluster. Finally, add OPA Gatekeeper admission policies at the namespace level so that non-root execution and the absence of privileged escalation become cluster-enforced invariants rather than per-Dockerfile conventions.

## Section 4: Conclusion
The Checkout system has been hardened across multiple layers - non-root container execution, five NetworkPolicies for microsegmentation, Kubernetes Secrets for credentials - and instrumented with Prometheus and Grafana for end-to-end observability with X-Request-Id propagation. Trivy and Kubescape security testing returned no CRITICAL findings, an 84 % posture compliance score and documented remediation paths for the remaining HIGH findings. The automated 7-check verify-all.ps1 harness confirms the system passes every Assignment-2 acceptance criterion. The platform is ready for the next iteration of production hardening.
