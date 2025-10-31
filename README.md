# ML Platform Engineering Practicum

> End-to-end ML platform implementation: EKS-based pipelines, model registry, CI/CD, feature store, and observability — with reflections on platform design.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![CI Pipeline](https://github.com/wlevan3/ml-platform-engineering-practicum/actions/workflows/ci.yml/badge.svg)](https://github.com/wlevan3/ml-platform-engineering-practicum/actions/workflows/ci.yml)

## 📋 About

This repository documents my journey building a production-grade ML platform from scratch. The goal is to gain hands-on experience with:

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

_(Architecture diagram coming soon)_

## 🚀 Getting Started

### Prerequisites

- AWS Account with appropriate permissions
- `terraform` >= 1.7.0
- `kubectl` >= 1.28
- `aws-cli` >= 2.0
- `helm` >= 3.0
- `gh` CLI (for GitHub integration)

### Setup

```bash
# Clone repository
git clone https://github.com/wlevan3/ml-platform-engineering-practicum.git
cd ml-platform-engineering-practicum

# Install pre-commit hooks
pre-commit install

# Configure AWS credentials
aws configure

# Initialize Terraform (when available)
cd terraform
terraform init
```

## 📚 Documentation

- **[Contributing Guide](CONTRIBUTING.md)** - Development workflow, branch strategy, commit conventions
- **[Project Management](docs/PROJECT_MANAGEMENT.md)** - GitHub Projects setup and usage
- **[Quick Reference](docs/QUICK_REFERENCE.md)** - Commands and shortcuts

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

## 📖 Development Workflow

This project follows production-grade practices:

1. **Create Issue** - Use GitHub Projects and issue templates
2. **Create Branch** - Feature branches from `main`
3. **Develop** - Follow coding standards
4. **Test** - Run pre-commit hooks and tests
5. **Create PR** - Use PR template, self-review
6. **CI/CD** - Automated checks must pass
7. **Merge** - Squash merge to keep history clean

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## 📝 Learning Reflections

A key part of this practicum is documenting learnings and design decisions. Use the **Learning Reflection** issue template to capture:

- Key insights and takeaways
- Challenges encountered and solutions
- Trade-offs and alternative approaches
- Resources that helped

View all learnings in the [Project Board's Learning view](https://github.com/users/wlevan3/projects).

## 📈 Progress Tracking

Track progress through:

- **GitHub Projects** - Visual boards and roadmap
- **Issues** - Detailed task tracking
- **Pull Requests** - Code changes and reviews
- **Milestones** - Phase completion markers

## 🎯 Roadmap

### Phase 1: Foundation & Setup ✅

- [x] GitHub repository setup
- [x] Branch protection and rulesets
- [x] Issue templates and PR templates
- [x] CI/CD pipeline foundation
- [x] GitHub Projects configuration

### Phase 2: EKS & Kubernetes

- [ ] Terraform configuration for EKS
- [ ] VPC and networking setup
- [ ] Node groups and autoscaling
- [ ] kubectl access configuration
- [ ] Deploy sample workload

### Phase 3: Model Registry

- [ ] MLflow deployment on EKS
- [ ] S3 backend for artifacts
- [ ] Authentication and access control
- [ ] Integration testing

### Phase 4: Feature Store

- [ ] Feature store architecture design
- [ ] RDS deployment for metadata
- [ ] Feature ingestion pipeline
- [ ] Feature serving API

### Phase 5: CI/CD Integration

- [ ] GitHub Actions workflows
- [ ] Automated testing
- [ ] Deployment automation
- [ ] Rollback procedures

### Phase 6: Observability

- [ ] Prometheus deployment
- [ ] Grafana dashboards
- [ ] Log aggregation (ELK)
- [ ] Alerting setup

### Phase 7: Optimization & Polish

- [ ] Cost optimization
- [ ] Performance tuning
- [ ] Security hardening
- [ ] Documentation completion

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
