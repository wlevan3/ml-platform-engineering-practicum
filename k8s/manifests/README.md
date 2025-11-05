# Kubernetes Resource Quotas and Limit Ranges

This directory contains Kubernetes manifests for **cost control** and **resource governance** in the ml-platform
cluster. These manifests enforce hard limits on resource consumption to prevent runaway costs and ensure predictable
behavior.

## 📁 Files

- **`resource-quota-compute.yaml`** - Limits total compute resources (pods, CPU, memory, storage)
- **`resource-quota-objects.yaml`** - Limits Kubernetes object counts (deployments, services, load balancers)
- **`limit-range.yaml`** - Sets default resource requests/limits for pods that don't specify them

## 🎯 Purpose: Three-Layer Cost Control Strategy

These manifests implement **Layer 1** of our cost control strategy:

1. **Layer 1: Resource Quotas and Limit Ranges** (this directory)
   - Hard limits on cluster-wide resource consumption
   - Prevents accidental over-provisioning
   - Forces developers to think about resource requirements

2. **Layer 2: Horizontal Pod Autoscaler** (`k8s/hpa.yaml`)
   - Dynamic scaling based on CPU/memory utilization
   - Bounded by ResourceQuota limits (maxReplicas: 10 → quota: 12 pods)

3. **Layer 3: AWS Budget Alerts** (via Terraform security module)
   - Financial monitoring and alerting
   - Last line of defense against cost overruns

## 📊 Resource Limits Summary

### Compute Resources (`resource-quota-compute.yaml`)

| Resource | Limit | Rationale |
|----------|-------|-----------|
| **Pods** | 12 | HPA maxReplicas (10) + 2 buffer for rolling updates |
| **CPU Requests** | 4 vCPUs | Allows 16 pods @ 250m each (HPA headroom) |
| **CPU Limits** | 8 vCPUs | Allows 16 pods @ 500m each |
| **Memory Requests** | 10 GB | ~40 pods @ 256Mi each (generous buffer) |
| **Memory Limits** | 20 GB | ~40 pods @ 512Mi each |
| **PVCs** | 5 | Max 5 persistent volume claims |
| **Total Storage** | 100 GB | Max storage across all PVCs |
| **Ephemeral Storage** | 50 GB | Limits temp file usage |

**Alignment**: Values are aligned with:

- `k8s/deployment.yaml` (container requests: 250m CPU, 256Mi memory)
- `k8s/hpa.yaml` (maxReplicas: 10)

### Object Counts (`resource-quota-objects.yaml`)

| Resource | Limit | Rationale |
|----------|-------|-----------|
| **Deployments** | 5 | Should only need 1-2 for ml-platform-api |
| **Services** | 10 | Plenty for typical microservices |
| **ConfigMaps** | 20 | Application configuration storage |
| **Secrets** | 20 | Credentials and sensitive data |
| **Jobs** | 10 | One-off batch tasks |
| **CronJobs** | 5 | Scheduled tasks |
| **Load Balancers** | 1 | **Critical cost control** - ALBs cost ~$22/month each |

**⚠️ Load Balancer Restriction**: Only 1 ALB allowed per namespace. Use Ingress resources to route to multiple
services through a single ALB instead of creating multiple LoadBalancer services.

### Default Limits (`limit-range.yaml`)

**Container Defaults** (applied if not specified in pod spec):

| Resource | Default Request | Default Limit | Min | Max |
|----------|----------------|---------------|-----|-----|
| **CPU** | 250m | 500m | 100m | 2 vCPUs |
| **Memory** | 512Mi | 1Gi | 128Mi | 4Gi |
| **Ephemeral Storage** | 1Gi | 2Gi | 100Mi | 10Gi |

**Pod-Level Limits** (aggregated across all containers):

| Resource | Min | Max |
|----------|-----|-----|
| **CPU** | 100m | 4 vCPUs |
| **Memory** | 128Mi | 8Gi |
| **Ephemeral Storage** | 100Mi | 20Gi |

**PVC Limits**:

| Resource | Min | Max |
|----------|-----|-----|
| **Storage** | 1Gi | 50Gi |

## 🚀 Deployment

### Prerequisites

- Access to EKS cluster (configured `kubectl` context)
- Appropriate RBAC permissions to create ResourceQuota and LimitRange resources

### Apply Manifests

Apply all manifests at once:

```bash
kubectl apply -f k8s/manifests/
```

Or apply individually:

```bash
kubectl apply -f k8s/manifests/resource-quota-compute.yaml
kubectl apply -f k8s/manifests/resource-quota-objects.yaml
kubectl apply -f k8s/manifests/limit-range.yaml
```

### Verify Deployment

Check that quotas are created and active:

```bash
# View all resource quotas
kubectl get resourcequota -n default

# View compute quota details
kubectl describe quota ml-platform-compute-quota -n default

# View object count quota details
kubectl describe quota ml-platform-object-count-quota -n default

# View limit range details
kubectl describe limitrange ml-platform-default-limits -n default
```

**Expected output** (example):

```text
NAME                               AGE
ml-platform-compute-quota          10s
ml-platform-object-count-quota     10s

Name:                   ml-platform-compute-quota
Namespace:              default
Resource                Used  Hard
--------                ----  ----
limits.cpu              0     8000m
limits.memory           0     20Gi
pods                    0     12
requests.cpu            0     4000m
requests.memory         0     10Gi
```

### Monitor Quota Usage

Check current quota usage vs limits:

```bash
# Summary view
kubectl get resourcequota -n default

# Detailed usage breakdown
kubectl describe quota -n default

# Check if pods are being rejected due to quota
kubectl get events -n default --sort-by='.lastTimestamp' | grep -i quota
```

## 🔄 Integration with Existing Resources

### Deployment Alignment

The resource quotas are aligned with `k8s/deployment.yaml`:

```yaml
# k8s/deployment.yaml:78-85
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

**Calculation**: With a 12-pod quota:

- CPU requests: 12 pods × 250m = 3 vCPUs (under 4 vCPU quota ✓)
- Memory requests: 12 pods × 256Mi = 3Gi (under 10Gi quota ✓)

### HPA Alignment

The pod quota (12) accounts for HPA scaling with rolling updates:

```yaml
# k8s/hpa.yaml:14
maxReplicas: 10  # Maximum HPA scaling
```

**Buffer calculation**: 10 (HPA max) + 2 (rolling update buffer) = 12 pods

During a rolling update with `maxSurge: 1`, you could temporarily have:

- 10 running pods (HPA at max)
- 1 new pod being created (surge)
- 1 old pod being terminated (gradual rollout)

The 12-pod quota provides headroom for this scenario.

## 🛠️ Troubleshooting

### Pod Creation Fails Due to Quota

**Symptom**: Pods stuck in Pending state with event:

```text
Error creating: pods "ml-platform-api-xxx" is forbidden:
exceeded quota: ml-platform-compute-quota,
requested: requests.cpu=250m, used: requests.cpu=3750m, limited: requests.cpu=4000m
```

**Solution**:

1. Check current quota usage: `kubectl describe quota -n default`
2. Delete unused pods or reduce replicas
3. If legitimately needed, increase quota limits in manifest and reapply

### Service Creation Fails Due to Load Balancer Quota

**Symptom**: Service creation fails with:

```text
Error creating load balancer: exceeded quota:
services.loadbalancers, requested: 1, used: 1, limited: 1
```

**Solution**:

- Use **Ingress resources** instead of LoadBalancer services
- Route multiple services through a single ALB via Ingress rules
- Only use LoadBalancer type for the Ingress Controller itself

Example Ingress routing:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ml-platform-ingress
spec:
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ml-platform-api
                port:
                  number: 8000
```

### LimitRange Not Applied to Existing Pods

**Important**: LimitRange is only applied at **pod creation time**. Existing pods are not affected.

**Solution**: Restart deployments to apply new defaults:

```bash
kubectl rollout restart deployment/ml-platform-api -n default
```

## 📚 Background: Migration from Terraform

These manifests were converted from Terraform resources as part of Issue #98 Phase 4 (Terraform provider dependency
cycle resolution).

**Original source**: `terraform/environments/dev/kubernetes-config.tf.reference`

**Why YAML instead of Terraform?**

1. **Resolves provider cycle**: EKS cluster outputs required for Kubernetes provider → circular dependency
2. **GitOps alignment**: Kubernetes resources managed by kubectl/ArgoCD instead of Terraform
3. **Separation of concerns**: AWS infrastructure (Terraform) vs K8s resources (YAML manifests)
4. **Faster iteration**: Changes don't require Terraform apply cycle

**Related issues**:

- Issue #98: Terraform modularization and provider cycle resolution
- Issue #99: Convert Kubernetes resources to YAML manifests (this work)
- Issue #100: Set up ArgoCD for GitOps-based deployments

## 🔗 Related Documentation

- `k8s/deployment.yaml` - ML Platform API deployment with resource requests/limits
- `k8s/hpa.yaml` - Horizontal Pod Autoscaler configuration
- `terraform/modules/eks-cluster/README.md` - EKS cluster setup and cost analysis
- `docs/COST_SAVING_WORKFLOW.md` - Comprehensive cost management guide

## ⚠️ Important Notes

1. **Namespace**: Currently applied to `default` namespace. Update `metadata.namespace` when implementing proper
   namespace separation.

2. **Quota Modification**: When changing quotas, ensure values are coordinated:
   - Pod quota ≥ HPA maxReplicas + rolling update buffer
   - CPU/memory quotas ≥ (max pods × container requests)

3. **Production Considerations**:
   - Separate namespaces with dedicated quotas per team/app
   - Higher quotas for production environments
   - Monitoring and alerting for quota exhaustion (Prometheus + Grafana)

4. **Cost Impact**: These quotas prevent the following cost scenarios:
   - Runaway HPA scaling (capped at 12 pods)
   - Accidental multiple ALB creation (~$22/month each)
   - Unlimited storage provisioning (capped at 100GB)
   - Memory-intensive pods consuming all cluster memory

## 🧪 Testing

Test quota enforcement by attempting to exceed limits:

```bash
# Test pod quota (should fail after 12 pods)
kubectl scale deployment ml-platform-api --replicas=15

# Check quota violation event
kubectl get events -n default | grep -i quota

# Verify quota blocks scale-up
kubectl get pods -n default | wc -l  # Should show 12 or fewer
```

Test LimitRange defaults:

```bash
# Create pod without resource requests/limits
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-defaults
spec:
  containers:
  - name: nginx
    image: nginx:latest
EOF

# Verify defaults were applied
kubectl get pod test-defaults -o jsonpath='{.spec.containers[0].resources}' | jq

# Cleanup
kubectl delete pod test-defaults
```

## 📝 Maintenance

**When to update these quotas**:

- Changing HPA maxReplicas (update pod quota accordingly)
- Changing deployment resource requests/limits (recalculate quotas)
- Adding new deployments to namespace (increase object quotas)
- Scaling up for production workloads (adjust compute quotas)

**Review schedule**: Quarterly review of quota usage and adjust as needed.
