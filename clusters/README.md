# GitOps Clusters

The `clusters/` directory tracks desired Kubernetes state using the GitOps pattern.
Each subdirectory represents an environment and contains the manifests or Argo CD
`Application` definitions that reconcile the cluster.

Current layout:

- `dev/` – Development environment.
  - `bootstrap/` – Base manifests deployed during cluster bootstrap (e.g., Argo CD
    root application, namespaces, quotas). These can seed the app-of-apps pattern.

When onboarding Argo CD, point the bootstrap Terraform to the corresponding environment
directory so the cluster continuously reconciles against the manifests stored here.
Additional environments (e.g., `staging`, `prod`) should mirror this structure.
