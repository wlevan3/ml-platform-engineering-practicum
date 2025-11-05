# ML Platform Engineering Practicum - Roadmap

This document outlines the planned phases for building the production-grade ML platform.

## Phase 1: Foundation & Setup ✅

**Status:** Complete

- [x] GitHub repository setup
- [x] Branch protection and rulesets
- [x] Issue templates and PR templates
- [x] CI/CD pipeline foundation
- [x] GitHub Projects configuration
- [x] FastAPI ML inference service (Iris classifier)
- [x] Docker containerization
- [x] Kubernetes deployment manifests
- [x] Pre-commit hooks and code quality tools
- [x] Security scanning (Trivy, Gitleaks, Semgrep)
- [x] SBOM generation
- [x] SonarCloud integration

## Phase 2: EKS & Kubernetes

**Focus:** AWS infrastructure and Kubernetes cluster setup

- [ ] Terraform configuration for EKS cluster
- [ ] VPC and networking setup (subnets, NAT gateway, route tables)
- [ ] Node groups and autoscaling configuration
- [ ] kubectl access configuration via IAM
- [ ] Deploy sample workload to EKS
- [ ] Network policies and security groups
- [ ] Load balancer configuration
- [ ] DNS and ingress setup

## Phase 3: Model Registry

**Focus:** MLflow deployment for model versioning and tracking

- [ ] MLflow deployment on EKS
- [ ] S3 backend for model artifacts
- [ ] RDS PostgreSQL for MLflow metadata
- [ ] Authentication and access control
- [ ] Model registration workflow
- [ ] Model staging and promotion
- [ ] Integration testing with inference service
- [ ] CI/CD integration for automated model deployment

## Phase 4: Feature Store

**Focus:** Centralized feature management system

- [ ] Feature store architecture design (evaluate Feast vs custom)
- [ ] RDS deployment for feature metadata
- [ ] Feature ingestion pipeline
- [ ] Feature serving API
- [ ] Feature versioning and lineage
- [ ] Online vs offline feature store
- [ ] Feature monitoring and drift detection
- [ ] Integration with model training pipeline

## Phase 5: CI/CD Integration

**Focus:** Automated testing and deployment pipelines

- [ ] GitHub Actions workflows for EKS deployment
- [ ] Automated testing (unit, integration, e2e)
- [ ] Deployment automation with GitOps (ArgoCD or Flux)
- [ ] Rollback procedures and blue-green deployments
- [ ] Automated model validation gates
- [ ] Performance testing in staging
- [ ] Security scanning in pipeline
- [ ] Deployment notifications and approvals

## Phase 6: Observability

**Focus:** Monitoring, logging, and alerting infrastructure

- [ ] Prometheus deployment on EKS
- [ ] Grafana dashboards for metrics visualization
- [ ] Log aggregation with ELK stack (Elasticsearch, Logstash, Kibana)
- [ ] Distributed tracing (Jaeger or OpenTelemetry)
- [ ] Alerting setup (PagerDuty or Opsgenie)
- [ ] Model performance monitoring
- [ ] Data quality monitoring
- [ ] Cost monitoring dashboards
- [ ] SLO/SLA tracking

## Phase 7: Optimization & Polish

**Focus:** Production readiness and documentation

- [ ] Cost optimization analysis and implementation
- [ ] Performance tuning (autoscaling, resource limits)
- [ ] Security hardening (network policies, RBAC, secrets management)
- [ ] Disaster recovery planning and testing
- [ ] Documentation completion (runbooks, architecture diagrams)
- [ ] Load testing and capacity planning
- [ ] Multi-region setup (if applicable)
- [ ] Final learning reflections and retrospective

## Success Metrics

Each phase should be measured against:

- **Functional Requirements:** Does it work as intended?
- **Quality:** Code quality, test coverage, security scanning
- **Documentation:** Clear runbooks, architecture diagrams, learning reflections
- **Understanding:** Can I explain design decisions and trade-offs?
- **Production Readiness:** Is it resilient, observable, and maintainable?

## Timeline Guidance

- **Phase 1:** ✅ Complete (4-6 weeks)
- **Phase 2:** 2-3 weeks (Terraform + EKS setup)
- **Phase 3:** 2-3 weeks (MLflow deployment)
- **Phase 4:** 3-4 weeks (Feature store design + implementation)
- **Phase 5:** 2-3 weeks (CI/CD automation)
- **Phase 6:** 3-4 weeks (Observability stack)
- **Phase 7:** 2-3 weeks (Optimization + documentation)

**Total Estimated Duration:** 4-6 months (already completed ~6 weeks)

## Current Status

**Active Phase:** Transitioning from Phase 1 to Phase 2

**Next Milestone:** EKS cluster deployment with Terraform

**Blockers:** None

**Recent Completions:**
- Container image signing with Cosign
- OpenSSF Scorecard integration
- SBOM generation with Syft
- Comprehensive security scanning

---

*Last Updated: 2025-01-04*
