# Kubernetes Resource Quotas and Limit Ranges

This directory contains Kubernetes manifests for cost control and resource governance in the ml-platform cluster.

**Files**:

- `resource-quota-compute.yaml` - Limits total compute resources
- `resource-quota-objects.yaml` - Limits Kubernetes object counts
- `limit-range.yaml` - Sets default resource requests/limits

---

## Resource Limits Summary

### Compute Resources

| Resource | Limit | Rationale |
|----------|-------|-----------|
| **Pods** | 12 | HPA max (10) + rolling update buffer |
| **CPU Requests** | 4 vCPUs | 16 pods @ 250m each |
| **CPU Limits** | 8 vCPUs | 16 pods @ 500m each |
| **Memory Requests** | 10 GB | 12 pods × 512Mi + buffer |
| **Memory Limits** | 20 GB | 12 pods × 1Gi + buffer |
| **PVCs** | 5 | Max persistent volume claims |
| **Storage** | 100 GB | Max across all PVCs |

### Object Counts

| Resource | Limit |
|----------|-------|
| **Deployments** | 5 |
| **Services** | 10 |
| **ConfigMaps** | 20 |
| **Secrets** | 20 |
| **Jobs** | 10 |
| **Load Balancers** | 1 |

⚠️ Only 1 ALB allowed. Use Ingress to route multiple services.

### Default Limits (Container)

| Resource | Request | Limit |
|----------|---------|-------|
| **CPU** | 250m | 500m |
| **Memory** | 512Mi | 1Gi |

---

## Deployment

### Apply Manifests

```bash
kubectl apply -f k8s/manifests/
```

### Verify

```bash
kubectl get resourcequota -n ml-platform
kubectl describe quota ml-platform-compute-quota -n ml-platform
kubectl describe limitrange ml-platform-default-limits -n ml-platform
```

### Monitor Usage

```bash
kubectl describe quota -n ml-platform
kubectl get events -n ml-platform --sort-by='.lastTimestamp' | grep quota
```

---

## Common Issues

### Pod Creation Fails (Quota Exceeded)

```bash
# Check current usage
kubectl describe quota -n ml-platform

# Delete unused pods or reduce replicas
kubectl scale deployment ml-platform-api --replicas=<N>
```

### Service Creation Fails (Load Balancer Quota)

Use Ingress instead of LoadBalancer service type:

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

LimitRange only applies at pod creation. Restart deployments:

```bash
kubectl rollout restart deployment/ml-platform-api -n ml-platform
```

---

## Related Documentation

- `k8s/deployment.yaml` - Deployment with resource requests/limits
- `k8s/hpa.yaml` - Horizontal Pod Autoscaler (maxReplicas: 10)
- `terraform/modules/eks-cluster/` - EKS cluster setup

---

## Important Notes

1. **Namespace**: All resources deploy to `ml-platform` namespace
2. **Quota Coordination**: Update pod quota if changing HPA maxReplicas
3. **Cost Control**: Quotas prevent:
   - Runaway HPA scaling (capped at 12 pods)
   - Multiple ALB creation (~$22/month each)
   - Unlimited storage provisioning (capped at 100GB)

---

**Last Updated**: 2025-11-05 | **Review**: Update quotas when HPA/deployment specs change
