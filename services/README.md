# Services

Application source code, ML assets, and service-specific deployment artifacts live under
`services/`. Each subdirectory owns a deployable workload, including its API source,
Dockerfile snippets, Helm charts (future), and supporting assets.

Current services:

- `api/` – FastAPI inference service that serves the Iris classifier. Contains the
  application package, Pydantic schemas, security helpers, and bundled model artifacts
  under `models/`.

New services should follow the same pattern:

1. Create `services/<service-name>/` with application code and tests.
2. Co-locate deployment manifests (Helm chart, Kustomize overlay) or add references in
   the `clusters/` GitOps configurations.
3. Update CI workflows if the service requires specialized build/test steps.
