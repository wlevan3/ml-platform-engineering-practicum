<!-- markdownlint-disable MD013 -->
# ML Platform Engineering Practicum

> End-to-end ML platform implementation: EKS-based pipelines, model registry, CI/CD, feature store, and
> observability — with reflections on platform design.
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![CI Pipeline](https://github.com/wlevan3/ml-platform-engineering-practicum/actions/workflows/ci.yml/badge.svg)](https://github.com/wlevan3/ml-platform-engineering-practicum/actions/workflows/ci.yml)
[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=wlevan3_ml-platform-engineering-practicum&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=wlevan3_ml-platform-engineering-practicum)
[![Reliability Rating](https://sonarcloud.io/api/project_badges/measure?project=wlevan3_ml-platform-engineering-practicum&metric=reliability_rating)](https://sonarcloud.io/summary/new_code?id=wlevan3_ml-platform-engineering-practicum)
[![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=wlevan3_ml-platform-engineering-practicum&metric=security_rating)](https://sonarcloud.io/summary/new_code?id=wlevan3_ml-platform-engineering-practicum)
[![Maintainability Rating](https://sonarcloud.io/api/project_badges/measure?project=wlevan3_ml-platform-engineering-practicum&metric=sqale_rating)](https://sonarcloud.io/summary/new_code?id=wlevan3_ml-platform-engineering-practicum)

## 🏆 Code Quality

This project maintains high code quality standards using **SonarCloud** for continuous analysis:

- **Quality Gate**: ✅ Passing (A-rated on all metrics)
- **Coverage Target**: 90% (gate requirement: 80%)
- **Integration**: Automatic Analysis via GitHub App
- **Philosophy**: "Clean as You Code" - focus on new code quality

All pull requests are automatically scanned for bugs, vulnerabilities, code smells, and security hotspots.
See [SonarCloud Quality Standards](docs/SONARCLOUD_QUALITY_STANDARDS.md) for detailed metrics and thresholds.

## 📋 About

This repository documents my journey building a production-grade ML platform from scratch. The goal is to gain
hands-on experience with:

- **Infrastructure as Code** - Terraform for AWS resources
- **Container Orchestration** - Kubernetes on AWS EKS
- **ML Infrastructure** - Model registry, feature store, experiment tracking
- **CI/CD & GitOps** - Automated testing, deployment pipelines
- **Observability** - Monitoring, logging, alerting
- **Platform Engineering** - Design patterns, best practices, trade-offs

## 🗂️ Project Management

This project uses **GitHub Projects** to track all work, learnings, and progress.

📊 **[View Project Board](https://github.com/users/wlevan3/projects)**

### Project Structure

- **Status Board** - Track work by status (Backlog → In Progress → Done)
- **Component Board** - Organize by platform component (EKS, Model Registry, etc.)
- **Roadmap View** - Timeline visualization of practicum phases
- **Learning Reflections** - Document insights and takeaways

See [Project Management Guide](docs/PROJECT_MANAGEMENT.md) for detailed setup and workflows.

## 🏗️ Architecture

The ML platform consists of these core components:

- **EKS Cluster** - Kubernetes cluster for running ML workloads
- **Model Registry** - MLflow for model versioning and tracking
- **Feature Store** - Centralized feature management
- **CI/CD Pipeline** - Automated testing and deployment
- **Observability Stack** - Prometheus, Grafana, ELK stack

(Architecture diagram coming soon)

## 🚀 Getting Started

### Prerequisites

- Python 3.13+
- Docker Desktop
- Minikube (for local K8s deployment)
- kubectl >= 1.28
- `gh` CLI (for GitHub integration)
- (Future) AWS Account, `terraform` >= 1.7.0, `aws-cli` >= 2.0, `helm` >= 3.0

### Local Development Setup

```bash
# Clone and setup
git clone https://github.com/wlevan3/ml-platform-engineering-practicum.git
cd ml-platform-engineering-practicum
pre-commit install

# Python environment (3.13 required)
python3.13 -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Train model and run API
python train_model.py
uvicorn services.api.main:app --reload --host 0.0.0.0 --port 8000
```

**Alternative:** Use `uv` package manager - see [CLAUDE.md](CLAUDE.md) for details.

### Docker Quick Start

```bash
docker build -t ml-platform-api:v1.0.0 .
docker run -p 8000:8000 ml-platform-api:v1.0.0

# Test endpoints
curl http://localhost:8000/health/ready
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"features": [5.1, 3.5, 1.4, 0.2]}'
```

**All Docker commands:** [docs/QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md) (build, run, scan, SBOM)

### Kubernetes Quick Start

```bash
# Start Minikube
minikube start --cpus=4 --memory=6144 --driver=docker

# Build, load, and deploy
docker build -t ml-platform-api:v1.0.0 .
minikube image load ml-platform-api:v1.0.0
kubectl apply -f clusters/dev/bootstrap/k8s-manifests/

# Test
minikube service ml-platform-api --url  # Get service URL
curl <SERVICE_URL>/health/ready
```

**All Kubernetes commands:** `docs/QUICK_REFERENCE.md` (deployment, validation, logs, troubleshooting)

## 🧭 Monorepo Layout

```text
infra/
├── aws-core/terraform/     # Foundational AWS infrastructure (VPC, EKS, ECR)
└── policies/               # Policy-as-code (Sentinel, OPA/Rego, Checkov)
clusters/
└── dev/bootstrap/          # GitOps entrypoint, bootstrap manifests (app-of-apps ready)
services/
└── api/                    # FastAPI inference service and packaged model assets
platform/
└── scripts/                # Shared automation (bootstrap, local deploy, diagnostics)
docs/                       # Design docs, runbooks, and how-tos
tests/                      # Automated tests (unit/integration)
```

Each top-level area owns a distinct concern:

- **infra/** – cloud resource definitions and guardrail policies
- **clusters/** – desired Kubernetes state tracked via GitOps (Argo CD app-of-apps)
- **services/** – product/application code, Dockerfiles, ML assets
- **platform/** – reusable tooling shared across teams (CLI helpers, bootstrap scripts)

## 📚 Documentation

### Core Guides

- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Workflow, branch strategy, commit conventions, PR checklist
- **[docs/QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md)** - Commands and shortcuts for all tools
- **[SECURITY.md](SECURITY.md)** - Security practices, scanning tools, vulnerability management
- **[ROADMAP.md](ROADMAP.md)** - Detailed phase-by-phase implementation plan

### Specialized Docs

- **[docs/PROJECT_MANAGEMENT.md](docs/PROJECT_MANAGEMENT.md)** - GitHub Projects setup
- **[docs/SONARCLOUD_QUALITY_STANDARDS.md](docs/SONARCLOUD_QUALITY_STANDARDS.md)** - Quality metrics
- **[docs/SBOM_GENERATION.md](docs/SBOM_GENERATION.md)** - Software Bill of Materials
- **[docs/IMAGE_SIGNING.md](docs/IMAGE_SIGNING.md)** - Container image signing with Cosign
- **[docs/PICKLE_SECURITY.md](docs/PICKLE_SECURITY.md)** - Model deserialization security
- **[docs/KUBERNETES_SECURITY.md](docs/KUBERNETES_SECURITY.md)** - K8s security best practices

## 🛠️ Technology Stack

### Infrastructure & Cloud

- **AWS** - EKS, RDS, S3, IAM, VPC
- **Terraform** - Infrastructure as Code
- **Kubernetes** - Container orchestration

### ML Platform

- **MLflow** - Model registry and experiment tracking
- **Feast** _(planned)_ - Feature store
- **Ray** _(planned)_ - Distributed computing

### CI/CD & Observability

- **GitHub Actions** - CI/CD pipelines
- **Prometheus** - Metrics collection
- **Grafana** - Visualization
- **ELK Stack** - Log aggregation

### Development Tools

- **pre-commit** - Git hooks for code quality
- **TFLint** - Terraform linting
- **kubeval** - Kubernetes manifest validation
- **Black & Ruff** - Python formatting and linting

### Infrastructure Validation

- **Pre-flight Resource Conflict Detection** - Validates potential conflicts before Terraform apply
- **Terraform State Validation** - Ensures state consistency
- **Resource Tagging Validation** - Verifies proper resource tagging

## 📖 Development Workflow

**Quick:** Create issue → Branch → Develop → Test → PR → CI/CD → Merge

**Details:** See [CONTRIBUTING.md](CONTRIBUTING.md) for complete workflow, coding standards, and PR checklist.

## 📝 Learning Philosophy

This practicum emphasizes documenting learnings and design decisions. Use the **Learning Reflection**
issue template to capture insights, challenges, trade-offs, and resources.

**View learnings:** [Project Board Learning view](https://github.com/users/wlevan3/projects)

## 🎯 Roadmap

**Current Phase:** Transitioning from Phase 1 (Foundation ✅) to Phase 2 (EKS & Kubernetes)

**Next Milestone:** EKS cluster deployment with Terraform

**View detailed roadmap:** [ROADMAP.md](ROADMAP.md) - Full phase-by-phase plan with timelines and success metrics

## 🤝 Contributing

This is a personal learning project, but feedback and suggestions are welcome! Feel free to:

- Open an issue to discuss ideas
- Submit a PR with improvements
- Share resources or best practices

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Resources

### Learning Resources

- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [MLOps Community](https://mlops.community/)

### Related Projects

- [MLflow](https://mlflow.org/)
- [Feast Feature Store](https://feast.dev/)
- [Kubeflow](https://www.kubeflow.org/)

---

**Built with** 🧠 **learning** and ☕ **coffee**
