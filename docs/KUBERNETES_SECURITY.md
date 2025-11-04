# Kubernetes Security Implementation

## Overview

This document details the Kubernetes security scanning and hardening implementation for the ml-platform-engineering-practicum project. It covers manifest scanning with kubesec, cluster assessment with kube-bench, Pod Security Standards enforcement, and RBAC validation.

## Security Scanning Tools

### 1. Kubesec - Manifest Security Scanning

**Purpose**: Automated security scanning of Kubernetes manifests to identify misconfigurations and security risks.

**Integration**: GitHub Actions CI/CD pipeline (`kubernetes-security-scan` job in `.github/workflows/ci.yml`)

**Scanning Scope**:
- All YAML manifest files in `k8s/` directory
- Deployment, StatefulSet, DaemonSet, Pod configurations
- Container security contexts, resource limits, probes

**Severity Levels**:
- **CRITICAL**: High-risk configuration errors (privilege escalation, dangerous capabilities)
- **HIGH**: Significant security issues (missing security controls)
- **MEDIUM**: Defense-in-depth recommendations (defense layer reduction)
- **LOW**: Best practice improvements

**Output Format**: SARIF (Static Analysis Results Format)
- Integrated with GitHub Security tab for visibility
- Results accessible at: `Settings > Security > Code scanning > Security alerts`

**Key Checks**:
- Container runs as root (`runAsNonRoot: false`)
- Privileged container (`privileged: true`)
- Privilege escalation allowed (`allowPrivilegeEscalation: true`)
- Dangerous capabilities enabled (CAP_SYS_ADMIN, CAP_NET_ADMIN, etc.)
- Writable root filesystem (`readOnlyRootFilesystem: false`)
- Host namespace access (`hostNetwork`, `hostPID`, `hostIPC`)
- No security context defined
- Missing resource limits
- No liveness/readiness probes

### 2. Kube-bench - Cluster Security Assessment

**Purpose**: Automated cluster security assessment against CIS Kubernetes Benchmarks.

**CIS Benchmark Coverage**:
- Control plane security (API server, scheduler, controller manager)
- Worker node security (kubelet, container runtime)
- Policies (RBAC, network policies, pod security)
- Configuration (etcd encryption, audit logging)

**Running Kube-bench Locally**:

Against Minikube cluster:
```bash
# Start Minikube with necessary features
minikube start --kubernetes-version=v1.30

# Run kube-bench as a Kubernetes Job
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml

# Fetch results
kubectl logs -l app=kube-bench
```

Against local cluster (Docker):
```bash
# Run in Docker for local development
docker run --rm -v $(pwd):/host aquasec/kube-bench:latest
```

**Benchmark Profile**:
- **PASS**: Control fully complies with benchmark
- **FAIL**: Control does not comply (security gap)
- **WARN**: Manual review recommended (ambiguous configuration)
- **INFO**: Informational result (no action needed)

## Manifest Hardening - Current Status

### Deployment Security Context ✅

The `ml-platform-api` deployment in `k8s/deployment.yaml` implements defense-in-depth security controls:

**Security Strengths**:

1. **Non-root User** ✅
   ```yaml
   runAsNonRoot: true
   runAsUser: 1000
   ```
   - Containers execute as unprivileged user (UID 1000)
   - Prevents privilege escalation attacks
   - Limits impact of container compromises

2. **Privilege Escalation Protection** ✅
   ```yaml
   allowPrivilegeEscalation: false
   ```
   - Child processes cannot gain additional privileges
   - Prevents privilege escalation via setuid binaries

3. **Capability Hardening** ✅
   ```yaml
   capabilities:
     drop:
       - ALL
   ```
   - All Linux kernel capabilities removed
   - Containers have minimal privileges
   - Only essential capabilities needed (none for FastAPI inference)

4. **Resource Limits** ✅
   ```yaml
   resources:
     requests:
       memory: "256Mi"
       cpu: "250m"
       ephemeral-storage: "1Gi"
     limits:
       memory: "512Mi"
       cpu: "500m"
       ephemeral-storage: "2Gi"
   ```
   - Memory: 256Mi request / 512Mi limit
   - CPU: 250m request / 500m limit
   - Ephemeral storage: 1Gi request / 2Gi limit
   - Prevents resource exhaustion and DoS attacks
   - Supports fair multi-tenant scheduling

5. **Health Probes** ✅
   - Startup probe: Handles slow model loading (max 70s)
   - Liveness probe: Detects stuck processes (10s interval)
   - Readiness probe: Routes traffic only to ready instances (5s interval)
   - Fail-fast philosophy: Quick detection and container restart

6. **Image Pull Policy** ✅
   ```yaml
   imagePullPolicy: Always
   ```
   - Always pull latest image from registry
   - Ensures latest security patches
   - Prevents stale vulnerable images

7. **Service Account Token** ✅
   ```yaml
   automountServiceAccountToken: false
   ```
   - Disables automatic service account mounting
   - Prevents container from accessing Kubernetes API unless explicitly needed
   - Reduces attack surface

**Areas for Future Hardening**:

- Writable /tmp: Allowed for Python temporary files (model loading, bytecode cache)
  - Could be addressed with `initContainer` for model preloading
  - Trade-off: Increased complexity vs. reduced write access
  - Current approach is acceptable for development phase

### Pod Security Standards (PSS) Enforcement ✅

The `k8s/namespace.yaml` defines the `ml-platform` namespace with restricted PSS enforcement:

```yaml
pod-security.kubernetes.io/enforce: restricted
pod-security.kubernetes.io/audit: restricted
pod-security.kubernetes.io/warn: restricted
```

**Enforcement Levels**:

1. **enforce**: Strict mode
   - Violations are rejected at admission time
   - Pods cannot start if they violate restrictions
   - Suitable for production namespaces

2. **audit**: Logging mode
   - Violations are allowed but logged
   - Useful for gradual migration or testing
   - Enables visibility into non-compliant workloads

3. **warn**: User feedback mode
   - Violations generate warnings in kubectl output
   - Educates users about security best practices
   - No blocking, purely informational

**Restricted Standard Requirements**:
- All capabilities dropped except NET_BIND_SERVICE
- Non-root user enforcement
- Read-only root filesystem (with exceptions)
- No privileged containers
- No host namespace access
- No dangerous capabilities

### RBAC Configuration

Current RBAC posture (minimal):

**Service Account**:
- Default service account used (no custom ClusterRoles)
- Can be enhanced with least-privilege roles when cluster features are needed

**Future RBAC Implementation**:
```yaml
# Example: Role for accessing only required endpoints
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: ml-platform
  name: ml-platform-api
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get"]  # Only read access to ConfigMaps for config
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get"]  # Only read access to Secrets for credentials
```

## Security Audit Results

### kubesec Scan Findings

When running kubesec locally:

```bash
# Scan all manifests
kubesec scan k8s/*.yaml

# Example output format:
# Score (10 = most secure, 0 = least secure)
# k8s/deployment.yaml: 9 (PASS)
# k8s/service.yaml: 10 (PASS)
# k8s/namespace.yaml: 10 (PASS)
```

**Expected Score**: 8-9 (High security, minimal vulnerabilities)
- Non-root execution
- Security context hardening
- Resource limits defined
- Health probes configured

### Common Issues Checked

✅ **Privilege Escalation**:
- `allowPrivilegeEscalation: false` - Enforced
- No SYS_ADMIN or dangerous capabilities

✅ **Root User**:
- `runAsNonRoot: true` - Enforced
- User ID 1000 (unprivileged)

✅ **Host Access**:
- `hostNetwork: false` - Not set (default)
- `hostPID: false` - Not set (default)
- `hostIPC: false` - Not set (default)

⚠️ **Writable Root Filesystem**:
- `readOnlyRootFilesystem: false` - Required for Python interpreter
- Mitigated by other security controls (non-root, no privileges)

✅ **Resource Limits**:
- Memory limits: 512Mi (sufficient for FastAPI + small model)
- CPU limits: 500m (sufficient for inference workload)
- Ephemeral storage limits: 2Gi (covers temporary files)

✅ **Health Probes**:
- Startup, liveness, and readiness probes configured
- Proper timeout and failure thresholds

## Kube-bench Assessment Results

Expected results when running against cluster:

### Control Plane (Master Node)

| Control | Expected | Note |
|---------|----------|------|
| API Server flags | PASS | Default settings secure |
| Controller Manager flags | PASS | RBAC enabled |
| Scheduler flags | PASS | Default settings secure |
| Etcd encryption | WARN | Requires manual configuration |
| Audit logging | WARN | Optional for development |

### Worker Nodes

| Control | Expected | Note |
|---------|----------|------|
| Kubelet configuration | PASS | Default settings secure |
| Container runtime | PASS | Docker/containerd default |
| Network policies | WARN | Requires manual definition |
| Pod security policies | INFO | Deprecated in K8s 1.25+ |

## Remediation Workflow

When kubesec or kube-bench find issues:

### For kubesec Findings:

1. **CRITICAL/HIGH severity**:
   - Fix immediately in manifest
   - Update `k8s/*.yaml` with security improvements
   - Test locally with kubeval/kube-linter
   - Commit with detailed explanation

2. **MEDIUM severity**:
   - Evaluate trade-offs between security and functionality
   - Document decision in commit message
   - Add comment in manifest explaining reasoning

3. **LOW severity**:
   - Consider for next iteration
   - Document as technical debt if deferred
   - No blocking required

### For kube-bench Findings:

1. **FAIL results**:
   - Analyze root cause
   - Determine if applicable to current environment
   - Create issue or backlog item for remediation
   - Document in cluster setup documentation

2. **WARN results**:
   - Review manually for applicability
   - Document recommendations in operations guide
   - Plan for future hardening phases

## GitHub Security Integration

All security scan results are integrated with GitHub Security tab:

**Accessing Results**:
1. Go to repository `Settings` > `Security`
2. View `Code scanning` for kubesec findings
3. Each alert shows:
   - Manifest file and line number
   - Severity level
   - Description of security issue
   - Recommended remediation steps

**Alert Management**:
- Auto-dismiss resolved alerts when code is fixed
- Manually dismiss false positives with explanation
- Track alert history and trends

## Best Practices Applied

### 1. Defense in Depth
Multiple security layers ensure single-layer compromise doesn't expose system:
- Non-root user
- Disabled privilege escalation
- Dropped capabilities
- Read-only restrictions where feasible
- Resource limits
- Network isolation (future)

### 2. Least Privilege
Containers run with minimum required permissions:
- No sudo/su capabilities
- Only necessary system calls allowed
- Service account without excessive permissions
- No access to Kubernetes API unless needed

### 3. Security by Default
Security controls applied at namespace/cluster level:
- Pod Security Standards enforcement
- Resource quotas (future)
- Network policies (future)
- Audit logging (future)

### 4. Observability
Security controls are visible and manageable:
- Health probes show container readiness
- Resource limits prevent silent failures
- Security context documented in manifests
- kubesec scanning integrated into CI/CD

## References

- [Kubesec.io](https://kubesec.io/) - Manifest security scoring
- [Kube-bench](https://github.com/aquasecurity/kube-bench) - CIS benchmark assessment
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) - PSS documentation
- [NIST Application Container Security](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf)
- [CIS Kubernetes Benchmarks](https://www.cisecurity.org/benchmark/kubernetes)

## Phase 2 Roadmap

Future enhancements planned for Phase 2 (EKS deployment):

- [ ] Implement Network Policies (deny-all ingress, allow specific rules)
- [ ] Configure RBAC for least-privilege access
- [ ] Enable audit logging for security events
- [ ] Implement Pod Disruption Budgets for availability
- [ ] Configure resource quotas per namespace
- [ ] Integrate with container image scanning (Trivy)
- [ ] Implement security group rules for EKS
- [ ] Configure KMS encryption for etcd

## Maintenance

**When to Re-scan**:
- After any manifest changes
- When updating Kubernetes version
- Quarterly security review
- As part of CI/CD pipeline (automatically)

**Monitoring**:
- GitHub Security tab alerts
- CI/CD pipeline results
- Regular kube-bench assessments against running clusters
