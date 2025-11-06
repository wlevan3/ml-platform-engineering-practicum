Scope

  You asked for clear, methodical steps to finish the monorepo restructuring. Below is a precise, sequential checklist that assumes the branch feature/
  restructure-monorepo and the pending changes currently in your working tree. It covers path updates, CI, policy wiring, docs, and verification so the PR
  lands cleanly.

  Finish Line Checklist

  - Paths and references
      - Update .pre-commit path exclude for terraform-docs:
          - .pre-commit-config.yaml: change exclude to ^infra/aws-core/terraform/environments/.*/README.md$
      - Update remaining CI paths in .github/workflows:
          - .github/workflows/eks-deploy.yml: replace terraform/environments/${{ inputs.environment }} with infra/aws-core/terraform/environments/
            ${{ inputs.environment }} and policy/terraform → infra/policies/opa; policy/sentinel → infra/policies/sentinel; k8s/ → clusters/dev/bootstrap/
            k8s-manifests/
      - Fix residual k8s/ and terraform/ mentions in docs:
          - Search and replace in docs/** for k8s/ → clusters/dev/bootstrap/k8s-manifests/
          - Search and replace for terraform/ → infra/aws-core/terraform/
      - Update infra/aws-core/terraform/README.md to reference clusters/dev/bootstrap/k8s-manifests/ instead of k8s/ where it still appears.
  - Verify scripts and relative imports
      - Already updated: platform/scripts/deploy-to-minikube.sh and platform/scripts/deploy-local-k3d.sh (use MANIFEST_DIR).
      - Confirm bootstrap-backend script sources logging library with the new relative path:
          - infra/aws-core/terraform/scripts/bootstrap-backend.sh: source "$(dirname "$0")/../../../../platform/scripts/lib/logging.sh"
      - Confirm all scripts under platform/scripts/ no longer reference old terraform/ or k8s/ paths.
  - Terraform and policy wiring
      - Confirm tfsec ignores:
          - .tfsecignore: aws-eks-encrypt-secrets:module.eks_cluster
          - Inline ignore comment at infra/aws-core/terraform/modules/eks-cluster/main.tf:5
      - Decide tfsec vs terraform_trivy (recommended):
          - Pre-commit: replace terraform_tfsec hook with terraform_trivy to avoid deprecated tool warnings.
          - CI: keep tfsec action temporarily, or switch to Trivy config scanning on infra/aws-core/terraform.
      - Confirm OPA/Sentinel path changes in CI:
          - .github/workflows/ci.yml: data directory points to infra/policies/opa, sentinel config and policies under infra/policies/sentinel.
  - Service, tests, and Docker
      - Verify Python imports all use services.api.*:
          - services/api/main.py, services/api/model.py, tests/test_api.py updated
      - Verify Docker build context:
          - Dockerfile copies services/api/ and runs uvicorn services.api.main:app
      - Ensure local testing uses a venv (to avoid system Python restrictions):
          - python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt && pytest
  - Ignores and tools
      - .gitignore updates:
          - services/api/models/ is ignored
          - infra/aws-core/environments/*/plan.json replaces old terraform path
      - Sonar config:
          - sonar-project.properties excludes services/api/models/** (updated)

  High‑Risk Path Updates To Complete

  - .pre-commit-config.yaml:66 (terraform_docs exclude needs new path)
  - .github/workflows/eks-deploy.yml: multiple references to terraform/environments/... and k8s/
  - infra/aws-core/terraform/README.md: references to k8s/ (update to clusters/dev/bootstrap/k8s-manifests/)
  - Any missed docs:
      - rg -n "k8s/" docs infra .github | review results
      - rg -n "terraform/" docs .github | review results

  Validation

  - Local
      - Python: activate venv, install requirements, run pytest, build Docker:
          - python3 -m venv .venv && source .venv/bin/activate
          - pip install -r requirements.txt
          - python train_model.py (writes to services/api/models/)
          - pytest
          - docker build -t ml-platform-api:v1.0.0 .
      - Terraform (new path):
          - cd infra/aws-core/terraform/environments/dev
          - terraform init
          - terraform plan -out plan.tfplan -no-color
          - terraform show -no-color plan.tfplan | tee plan.txt
  - CI
      - Open PR and verify:
          - Terraform validation, plan, OPA/Sentinel
          - Kubernetes validation/scanning against clusters/dev/bootstrap/k8s-manifests/
          - Python tests and coverage
          - Security scans (tfsec/Trivy/Checkov) refer to new directories

  PR Flow

  - Commit, push, and create PR
      - git add -A
      - git commit -m "refactor(monorepo): restructure repo and update paths; terraform hardening"
      - git push -u origin feature/restructure-monorepo
      - gh pr create --title "refactor: monorepo restructure + terraform hardening" --body "See SAVEPOINT.md for context and next steps."
  - Attach SAVEPOINT.md in the PR description or mention it prominently.

  Optional Improvements

  - Repo hygiene
      - Add CODEOWNERS with path-based ownership (infra/, clusters/, services/, platform/).
      - Add Makefile or Taskfile with common targets (fmt, lint, test, plan, build, dev).
      - Add ADR documenting monorepo structure decision and rationale.
  - CI efficiency
      - Add path-based conditions so Terraform jobs only run when infra/** changes; Kubernetes jobs when clusters/** changes; Python when services/
        ** changes.

  Commands To Find Remaining References

  - Find stale path references
      - rg -n "k8s/" docs infra .github
      - rg -n "terraform/environments" docs .github
      - rg -n "policy/sentinel|policy/terraform" .github docs
  - Confirm all changes
      - git status -sb
      - pre-commit run --all-files (after pre-commit path fix)

  If you want, I can apply the specific remaining patches (pre-commit exclude path, update eks-deploy.yml pathing, any straggler docs) and finalize the
  commit + PR.
