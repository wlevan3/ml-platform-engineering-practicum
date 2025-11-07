# Development Cluster (dev)

Bootstrap manifests and Argo CD entrypoints for the development EKS cluster.

- `bootstrap/k8s-manifests/` – Namespace, quota, deployment, and HPA resources used to
  bring the cluster online before GitOps takes over. Replace or extend these with Argo CD
  `Application` objects as the GitOps workflow matures.

When creating Argo CD app-of-apps definitions, commit them under this directory so the
development cluster automatically syncs to the desired configuration.
