# Savepoint: Monorepo Restructure, Terraform Hardening, and Next Steps

This savepoint captures the full context, decisions, and the exact next steps so a new session with no memory can resume and complete the work with zero ambiguity.

--------------------------------------------------------------------------------

Summary of What’s Done

- Terraform init and AWS connectivity
  - Initialized Terraform from the dev environment (previously `terraform/environments/dev`), resolved provider lock mismatch with `terraform init -upgrade`.
  - Confirmed remote S3 backend is configured and reachable.
  - Verified AWS credentials via `aws sts get-caller-identity` (account `984479408136`).

- Git hygiene
  - Ignored local Terraform cache: added `.external_modules/` to `.gitignore`.
  - Generated plan artifacts under the environment and exported human-readable plan (`plan.txt`).

- Pre-commit Terraform checks
  - `terraform_fmt`, `terraform_validate`, and `terraform_docs` pass after formatting updates.
  - `terraform_tfsec` fails (tool is deprecated upstream; recommended replacement is `terraform_trivy`). The failing checks and our decisions are captured below.

- tfsec investigation and policy stance
  - Findings observed (representative):
    - Public EKS API endpoint enabled (CRITICAL) and CIDR open to `0.0.0.0/0` (CRITICAL).
    - EKS control-plane logs for controllerManager/scheduler not fully enabled (MEDIUM).
    - EKS secrets encryption not explicitly configured with CMK (HIGH) — note: EKS already uses AWS-owned KMS under KMS provider v2; tfsec expects a customer-managed key.
    - VPC Flow Logs disabled (MEDIUM).
    - Node IMDS not explicitly set to IMDSv2 (HIGH) and node egress overly broad (CRITICAL) via recommended rules.
  - Decision: Do NOT use a CMK. Suppress the tfsec rule for EKS secret encryption with:
    - Inline ignore at `infra/aws-core/terraform/modules/eks-cluster/main.tf:5-10` using `#tfsec:ignore:aws-eks-encrypt-secrets`.
    - Root-level `.tfsecignore` entry: `aws-eks-encrypt-secrets:module.eks_cluster`.
  - Plan: migrate CI from `terraform_tfsec` to `terraform_trivy` (pre-commit and GitHub Actions), and keep `.tfsecignore` in place until that migration.

- Remediation implemented (code changes)
  - Control-plane logging: enabled full log set for EKS module.
    - File: infra/aws-core/terraform/modules/eks-cluster/main.tf:10
      - `enabled_log_types = ["api","audit","authenticator","controllerManager","scheduler"]`
  - IMDSv2 enforcement for nodes: set `metadata_options` on managed node group.
    - File: services/api/node-groups.tf moved → now at infra/aws-core/terraform/modules/eks-cluster/node-groups.tf:22-26
    - `http_tokens = "required"`, `http_endpoint = "enabled"`.
  - Node egress scoping: disabled module’s blanket recommended rules and limited egress to VPC CIDR; added `vpc_cidr` var.
    - Files:
      - infra/aws-core/terraform/modules/eks-cluster/main.tf:43-44 (`node_security_group_enable_recommended_rules = false`).
      - infra/aws-core/terraform/modules/eks-cluster/security-groups.tf:37-52 (new egress within VPC CIDR).
      - infra/aws-core/terraform/modules/eks-cluster/variables.tf:40-44 (new `vpc_cidr` variable).
      - infra/aws-core/terraform/environments/dev/main.tf:51-53 (wire `vpc_cidr = var.vpc_cidr`).
  - VPC Flow Logs enabled in networking wrapper with CloudWatch log group + IAM role + 60s aggregation + retention.
    - Files:
      - infra/aws-core/terraform/modules/networking/main.tf:34-40 (flow-log settings enabled).
      - infra/aws-core/terraform/modules/networking/variables.tf:112-115 (retention variable).

- Public EKS API decision is pending
  - Current dev env leaves `cluster_endpoint_public_access = true` and default open CIDR.
  - Options captured below (prefer private endpoint or a restricted CIDR list). tfsec continues to flag this until resolved.

- Argo CD + GitOps approach clarified
  - Use GitOps app-of-apps pattern.
  - Bootstrap Argo CD via Terraform (separate root from AWS core), then manage cluster applications via `clusters/<env>`.
  - CI should lint/validate manifests and Helm values; Argo CD performs the apply/reconcile.

- Monorepo restructure (branch: feature/restructure-monorepo)
  - New top-level layout:
    - infra/
      - aws-core/terraform/ … (moved from terraform/)
      - policies/ (moved policy/sentinel → infra/policies/sentinel, policy/terraform → infra/policies/opa, checkov custom policies → infra/policies/checkov)
    - clusters/
      - dev/bootstrap/k8s-manifests/ (moved from k8s/)
    - services/
      - api/ (moved from app/), with bundled model assets under `services/api/models/`
    - platform/
      - scripts/ (moved from scripts/)
  - All code, tests, Dockerfile, docs, CI paths updated:
    - Imports: `app.*` → `services.api.*`.
    - Dockerfile now copies `services/api/` and runs `uvicorn services.api.main:app`.
    - `train_model.py` writes models to `services/api/models/` (creating parents if needed).
    - Tests updated to import from `services.api.*` and reference model artifacts using a repository-root anchored path.
    - `pytest.ini` coverage target updated to `services.api` and excludes `services/api/models/*`.
    - README, quick refs, troubleshooting, and security docs updated for new paths and commands.
    - GitHub Actions (`.github/workflows/ci.yml`) updated to look at `infra/aws-core/terraform/**` and `clusters/dev/bootstrap/k8s-manifests/**`.
    - `.gitignore` adjusted (ignore `services/api/models/`, and environment plan path under `infra/aws-core`).
  - Added READMEs:
    - infra/README.md, infra/aws-core/README.md, infra/policies/README.md
    - clusters/README.md, clusters/dev/README.md
    - services/README.md, platform/README.md

- Sanity checks
  - Ran `terraform fmt -recursive`.
  - Adjusted bootstrap script to source shared logging lib at its new relative path.
  - Attempted running pytest locally; hit environment constraint (no venv; `fastapi` missing). Left clear instructions in Next Steps.

--------------------------------------------------------------------------------

Decisions and Rationale

- EKS secret encryption: rely on AWS-owned KMS (KMS provider v2) instead of CMK
  - Reason: Sentinel and org policy prohibit provisioning customer-managed KMS keys for this control plane.
  - Action: Suppress tfsec `aws-eks-encrypt-secrets`; document the rationale inline and in `.tfsecignore`.

- Public EKS API: postponed change for dev; prefer private in long run
  - For dev, public can be acceptable while bringing up the platform. Long-term, prefer `endpoint_public_access=false` with VPN/SSM/bastion or self-hosted runner inside VPC; otherwise restrict `public_access_cidrs` to minimal trusted IPs.

- GitOps over CI Helm apply
  - Use Argo CD (app-of-apps) to reconcile cluster state from `clusters/<env>`. CI validates but does not apply.

- Monorepo separation of concerns
  - Clear boundaries: infra (cloud+policies), clusters (GitOps desired state), services (apps), platform (scripts/tooling).
  - Terraform roots remain small and focused (aws-core vs future platform-bootstrap).

--------------------------------------------------------------------------------

Outstanding Work (Next Steps)

1) Finalize tfsec/trivy scanning strategy
   - In GitHub Actions (`.github/workflows/ci.yml`), we updated tfsec working directory to `infra/aws-core/terraform`. The root-level `.tfsecignore` should be honored by default. If `aws-eks-encrypt-secrets` still shows, either:
     - Add `additional_args: --exclude aws-eks-encrypt-secrets` to the action, or
     - Migrate to the `terraform_trivy` hook/action as recommended by pre-commit-terraform maintainers.
   - In pre-commit: consider replacing `terraform_tfsec` with `terraform_trivy` to avoid deprecation noise.

2) Decide and implement EKS API access posture
   - Option A (recommended for prod): set `cluster_endpoint_public_access=false` and rely on private access paths (VPN/SSM/bastion/self-hosted runners).
   - Option B (interim for dev): keep public=true but set `cluster_endpoint_public_access_cidrs=["<trusted CIDR>"]`. Update variables and re-run plan.
   - Remove or justify any tfsec suppressions related to public access depending on the chosen posture.

3) Create Argo CD bootstrap Terraform root
   - Add `infra/platform-bootstrap/terraform/` with:
     - A Helm release (or manifest apply) for Argo CD installation into `argocd` namespace.
     - A root Argo CD `Application` pointing to this repo’s `clusters/dev` (app-of-apps directory) to seed GitOps.
     - Outputs and README documenting bootstrap and how to toggle automated sync/prune.
   - Wire this root to consume outputs from `infra/aws-core/terraform` (cluster name, OIDC, etc.). Keep layering clean (no cyclic dependency).

4) Complete CI path migrations and validations
   - Confirm `.github/workflows/ci.yml` updates:
     - Terraform jobs use `infra/aws-core/terraform` (fmt, init/validate, plan, OPA/Sentinel paths fixed to `infra/policies/*`).
     - Kubernetes validation/security scan jobs read from `clusters/dev/bootstrap/k8s-manifests/`.
   - Run the pipeline in a PR to validate everything works with the new structure.

5) Local dev/test guardrails
   - Use a virtual environment for Python testing:
     ```bash
     python3 -m venv .venv
     source .venv/bin/activate
     pip install -r requirements.txt
     pytest
     ```
   - For Docker testing: rebuild after the path changes (`Dockerfile` updated to copy `services/api/`).

6) Node egress allow-list refinement
   - We currently allow node egress to the VPC CIDR. If workloads need wider egress (S3/ECR, etc.), add:
     - VPC endpoints (preferred), or
     - Managed prefix lists / explicit CIDR egress rules. Update `infra/aws-core/terraform/modules/eks-cluster/security-groups.tf` accordingly.

7) Update docs where relevant
   - We updated many references, but a content pass through `docs/**` to ensure no stale `k8s/` or `terraform/` references remain is advised.

--------------------------------------------------------------------------------

How to Continue From Here

Branch and PR
  - Current branch: `feature/restructure-monorepo` (created locally).
  - Push and open PR:
    ```bash
    git push -u origin feature/restructure-monorepo
    gh pr create --title "refactor: monorepo restructure + terraform hardening" --body "See SAVEPOINT.md for details"
    ```

Validate Terraform in new location
  - Initialize and plan from new path:
    ```bash
    cd infra/aws-core/terraform/environments/dev
    terraform init
    terraform plan -out plan.tfplan -no-color
    terraform show -no-color plan.tfplan | tee plan.txt
    ```

Pre-commit checks
  - Run pre-commit from repo root. Expect tfsec notices until you either migrate to `terraform_trivy` or accept the configured suppressions.
  - Re-run terraform fmt/validate/docs to ensure consistency after any edits.

Choose EKS API posture (Step 2 above)
  - If switching to private-only, plan for access via SSM/VPN/bastion. If keeping public for dev, add restricted CIDRs and update variables.

Implement Argo CD bootstrap (Step 3 above)
  - Create `infra/platform-bootstrap/terraform/` and add Helm chart or Kubernetes manifests for Argo CD and the root Application pointing at `clusters/dev`.

--------------------------------------------------------------------------------

Reference: Key Updated Files

- Monorepo layout overview: README.md (Monorepo Layout section)
- Infra root: infra/aws-core/terraform/README.md
- Policies: infra/policies/{sentinel,opa,checkov}/
- GitOps manifests: clusters/dev/bootstrap/k8s-manifests/
- API service: services/api/** (entry: services/api/main.py)
- Dockerfile: Dockerfile (entrypoint: `services.api.main:app`)
- Tests: tests/test_api.py; pytest.ini now targets `services.api` for coverage
- CI: .github/workflows/ci.yml (updated paths: Terraform + K8s)
- tfsec suppression: .tfsecignore (root) and inline in infra/aws-core/terraform/modules/eks-cluster/main.tf

--------------------------------------------------------------------------------

Notes / Known Caveats

- Local pytest run previously failed due to missing FastAPI in the system Python; use a venv to install dependencies.
- tfsec is deprecated in favor of Trivy; expect deprecation warnings until the migration.
- The Argo CD bootstrap Terraform root is not yet created; clusters manifests exist but are applied manually for now.

End of savepoint.
