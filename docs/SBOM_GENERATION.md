# SBOM Generation

## Overview

This document describes the Software Bill of Materials (SBOM) generation implementation for the
ML Platform Engineering Practicum project. SBOMs provide a complete, machine-readable inventory
of all software components, dependencies, and their relationships within our application and
container images.

## What is an SBOM?

A Software Bill of Materials (SBOM) is a formal, structured list of all components, libraries,
and dependencies that make up a software application. Think of it as an "ingredients label" for
software, similar to nutritional labels on food products.

### Key Benefits

1. **Vulnerability Management**: Quickly identify if your software contains vulnerable components
   when new CVEs are announced
2. **License Compliance**: Track open source licenses for legal compliance and audit trails
3. **Supply Chain Security**: Understand your software's composition and provenance
4. **Regulatory Compliance**: Meet requirements from Executive Order 14028, EU Cyber Resilience
   Act, and NTIA guidelines
5. **Incident Response**: Accelerate response time when vulnerabilities are disclosed

## Compliance Context

### Executive Order 14028 (USA)

In May 2021, US President Biden issued [Executive Order 14028](https://www.whitehouse.gov/briefing-room/presidential-actions/2021/05/12/executive-order-on-improving-the-nations-cybersecurity/)
"Improving the Nation's Cybersecurity", which mandates that software vendors provide SBOMs to
federal customers. Key requirements:

- SBOMs must follow NTIA minimum elements
- Required for software sold to US government agencies
- Emphasizes transparency in software supply chains

### EU Cyber Resilience Act (CRA)

The [EU Cyber Resilience Act](https://digital-strategy.ec.europa.eu/en/policies/cyber-resilience-act)
introduces mandatory cybersecurity requirements for products with digital elements sold in the EU,
including:

- Vulnerability disclosure requirements
- Security updates throughout product lifecycle
- SBOM generation for transparency and compliance

## Implementation Architecture

### SBOM Generation Workflow

Our CI/CD pipeline generates SBOMs using [Syft](https://github.com/anchore/syft) (by Anchore),
an industry-standard SBOM generation tool. The workflow runs automatically on every push and pull
request:

```text
┌─────────────────┐      ┌──────────────────┐      ┌─────────────────┐
│  Build Docker   │─────▶│  Generate SBOMs  │─────▶│ Upload as       │
│  Image          │      │  (Syft)          │      │ Artifacts       │
└─────────────────┘      └──────────────────┘      └─────────────────┘
                                  │
                                  ├─ Docker Image SBOM (SPDX)
                                  ├─ Docker Image SBOM (CycloneDX)
                                  ├─ Python App SBOM (SPDX)
                                  └─ Python App SBOM (CycloneDX)
```

### Scope: What We Generate

#### 1. Docker Image SBOM

Scans the complete container image (`ml-platform-api:$SHA`) including:

- Base image packages (python:3.13-slim OS packages)
- Python runtime and standard library
- Installed Python packages from requirements.txt
- Transitive dependencies

**Use Case**: Complete runtime view for operations, deployment, and vulnerability scanning

#### 2. Python Application SBOM

Scans the source directory (root `.`) including:

- Application code metadata
- Direct dependencies from requirements.txt
- Transitive dependencies

**Use Case**: Development-focused view, easier correlation with requirements.txt for developers

### SBOM Formats

We generate SBOMs in **two formats** to serve different use cases:

#### SPDX (Software Package Data Exchange)

- **Standard**: ISO/IEC 5962:2021
- **Focus**: License compliance, legal teams, enterprise adoption
- **Format**: JSON (`sbom-*-spdx.json`)
- **Best For**: Compliance audits, license tracking, legal review

#### CycloneDX

- **Standard**: OWASP CycloneDX
- **Focus**: Security, vulnerability management
- **Format**: JSON (`sbom-*-cyclonedx.json`)
- **Best For**: Vulnerability scanning, security analysis, DevSecOps pipelines

**Why Both?** Different teams have different priorities. Legal teams prefer SPDX for license
compliance, while security teams prefer CycloneDX for vulnerability correlation with tools like
Grype, Trivy, and Dependabot.

## Accessing SBOMs

### From GitHub Actions

SBOMs are automatically generated on every CI run and stored as workflow artifacts:

1. Navigate to the **Actions** tab in the GitHub repository
2. Select the workflow run (e.g., "CI Pipeline")
3. Scroll to the **Artifacts** section at the bottom
4. Download:
   - `sbom-docker` (Docker image SBOMs in both formats)
   - `sbom-python` (Python application SBOMs in both formats)

**Retention**: SBOMs are kept for **90 days** (extended from default 5 days for compliance)

### File Naming Convention

```text
sbom-docker-spdx.json         # Docker image SBOM in SPDX format
sbom-docker-cyclonedx.json    # Docker image SBOM in CycloneDX format
sbom-python-spdx.json         # Python app SBOM in SPDX format
sbom-python-cyclonedx.json    # Python app SBOM in CycloneDX format
```

## Local SBOM Generation

### Prerequisites

Install Syft locally:

```bash
# macOS
brew install syft

# Linux
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin

# Or download from GitHub releases
# https://github.com/anchore/syft/releases
```

### Generate SBOMs Locally

#### Docker Image SBOM

```bash
# Build the Docker image first
docker build -t ml-platform-api:latest .

# Generate SPDX format
syft ml-platform-api:latest -o spdx-json --file sbom-docker-spdx.json

# Generate CycloneDX format
syft ml-platform-api:latest -o cyclonedx-json --file sbom-docker-cyclonedx.json
```

#### Python Application SBOM

```bash
# Generate SPDX format
syft dir:. -o spdx-json --file sbom-python-spdx.json

# Generate CycloneDX format
syft dir:. -o cyclonedx-json --file sbom-python-cyclonedx.json
```

#### View SBOM in Terminal

```bash
# Human-readable table format
syft ml-platform-api:latest

# Or for Python app
syft dir:.
```

## Use Cases and Workflows

### 1. Vulnerability Response

When a new CVE is announced (e.g., CVE-2024-XXXX affecting a Python library):

1. Download the latest SBOM from CI artifacts
2. Search for the vulnerable package:

   ```bash
   jq '.packages[] | select(.name == "package-name")' sbom-docker-spdx.json
   ```

3. Check version and determine impact
4. Update requirements.txt and test

### 2. License Compliance Audit

Legal team needs to verify all open-source licenses:

1. Download SPDX format SBOM (preferred for license info)
2. Extract license data:

   ```bash
   jq '.packages[] | {name: .name, version: .version, license: .licenseConcluded}' \
     sbom-docker-spdx.json
   ```

3. Review licenses against company policy

### 3. Dependency Analysis

Understand transitive dependencies:

```bash
# Count total packages
jq '.packages | length' sbom-docker-spdx.json

# List all Python packages
jq '.packages[] | select(.name | startswith("python"))' sbom-docker-cyclonedx.json

# Find packages by supplier
jq '.packages[] | select(.supplier == "Organization: Python Software Foundation")' \
  sbom-python-spdx.json
```

### 4. Integration with Vulnerability Scanners

#### Using Grype (Anchore)

Grype can scan SBOMs directly for vulnerabilities:

```bash
# Install Grype
brew install grype

# Scan Docker image SBOM
grype sbom:sbom-docker-cyclonedx.json

# Scan with severity filtering
grype sbom:sbom-docker-cyclonedx.json --severity HIGH,CRITICAL
```

#### Using Trivy (Aqua Security)

Trivy can also scan SBOMs:

```bash
# Install Trivy
brew install trivy

# Scan SBOM
trivy sbom sbom-docker-cyclonedx.json

# Scan with severity filtering
trivy sbom sbom-docker-cyclonedx.json --severity HIGH,CRITICAL
```

### 5. Supply Chain Transparency

Share SBOMs with stakeholders:

- **Customers**: Provide SBOMs for security assessments
- **Security Team**: Enable continuous vulnerability monitoring
- **Compliance Team**: Support audit and certification processes

## CI/CD Integration Details

### Workflow Configuration

The SBOM generation job in `.github/workflows/ci.yml`:

```yaml
sbom-generation:
  name: SBOM Generation (Syft)
  runs-on: ubuntu-latest
  needs: [docker-build-scan]  # Run after Docker image is built
  permissions:
    contents: read
    actions: write  # Required for artifact upload
```

### Key Features

1. **Runs After Docker Build**: Ensures we scan the final, tested image
2. **Pinned Syft Version**: Uses Syft v1.37.0 for reproducibility
3. **Dual Format Output**: Generates both SPDX and CycloneDX
4. **Package Count Summary**: Shows statistics in GitHub Actions UI
5. **Extended Retention**: 90-day retention for compliance (vs. default 5 days)

### Viewing Results in CI

The workflow creates a summary in the GitHub Actions UI showing:

- Commit SHA for traceability
- File names for each SBOM
- Package counts for Docker image and Python app
- Download links to artifacts

## Future Enhancements

### Phase 2: GitHub Releases Integration

**Planned**: Automatically attach SBOMs to GitHub releases

```yaml
- name: Upload SBOMs to Release
  uses: softprops/action-gh-release@v1
  with:
    files: |
      sbom-docker-*.json
      sbom-python-*.json
```

**Benefit**: Customers can download SBOMs alongside release artifacts

### Phase 3: Container Registry Integration

**Planned**: Attach SBOMs as OCI image annotations

```bash
# Using cosign to attach SBOM
cosign attach sbom --sbom sbom-docker-spdx.json docker.io/org/ml-platform-api:v1.0.0
```

**Benefit**: SBOMs travel with container images in registries (Docker Hub, ECR, etc.)

### Phase 4: SBOM Diffing on PRs

**Planned**: Show dependency changes in pull requests

```yaml
- name: SBOM Diff
  run: |
    syft ml-platform-api:main -o json > base.json
    syft ml-platform-api:pr -o json > pr.json
    diff <(jq -S '.packages' base.json) <(jq -S '.packages' pr.json)
```

**Benefit**: Reviewers can see new dependencies introduced by PRs

### Phase 5: SBOM Signing

**Planned**: Sign SBOMs with cosign for integrity verification

```bash
cosign sign-blob --key cosign.key sbom-docker-spdx.json > sbom-docker-spdx.json.sig
```

**Benefit**: Customers can verify SBOM authenticity and integrity

### Phase 6: Continuous Monitoring

**Planned**: Integrate with Dependency-Track or similar SBOM management platforms

**Benefit**: Real-time vulnerability alerts when new CVEs match SBOM components

## Troubleshooting

### SBOM Generation Fails in CI

**Symptom**: `sbom-generation` job fails with Syft error

**Solutions**:

1. Check if Docker image built successfully (dependency on `docker-build-scan`)
2. Verify Syft version is available: [GitHub Releases](https://github.com/anchore/syft/releases)
3. Check for Syft breaking changes in release notes

### SBOM is Empty or Incomplete

**Symptom**: Package count is 0 or unexpectedly low

**Solutions**:

1. Verify source code is checked out (`actions/checkout@v4`)
2. Check if model was trained before Docker build (`python train_model.py`)
3. Ensure Docker image was built with correct tag

### Cannot Download Artifacts

**Symptom**: Artifacts not available in Actions UI

**Solutions**:

1. Check artifact retention period (90 days by default)
2. Verify workflow had `actions: write` permission
3. Confirm job completed successfully (check status)

### Local Syft Installation Issues

**Symptom**: Syft command not found or version mismatch

**Solutions**:

```bash
# Verify installation
which syft
syft version

# Reinstall if needed
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin

# Or use specific version
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin v1.37.0
```

## References

### Standards and Specifications

- [SPDX Specification 2.3](https://spdx.github.io/spdx-spec/v2.3/)
- [CycloneDX Specification 1.6](https://cyclonedx.org/specification/overview/)
- [NTIA Minimum Elements for an SBOM](https://www.ntia.gov/sites/default/files/publications/sbom_minimum_elements_report_0.pdf)

### Tools and Projects

- [Syft by Anchore](https://github.com/anchore/syft) - SBOM generation
- [Grype by Anchore](https://github.com/anchore/grype) - Vulnerability scanning for SBOMs
- [Trivy by Aqua Security](https://github.com/aquasecurity/trivy) - Container and SBOM scanning
- [Dependency-Track](https://dependencytrack.org/) - SBOM analysis platform

### Regulatory and Policy

- [Executive Order 14028](https://www.whitehouse.gov/briefing-room/presidential-actions/2021/05/12/executive-order-on-improving-the-nations-cybersecurity/)
- [EU Cyber Resilience Act](https://digital-strategy.ec.europa.eu/en/policies/cyber-resilience-act)
- [CISA SBOM Resources](https://www.cisa.gov/sbom)

### Learning Resources

- [SBOM Tutorial by Anchore](https://anchore.com/sbom/)
- [OWASP Software Component Verification Standard (SCVS)](https://owasp.org/www-project-software-component-verification-standard/)
- [Linux Foundation SBOM Guide](https://www.linuxfoundation.org/tools/the-state-of-software-bill-of-materials-sbom-and-cybersecurity-readiness/)

## Related Documentation

- [VULNERABILITY_REMEDIATION.md](./VULNERABILITY_REMEDIATION.md) - Vulnerability management workflow
- [PICKLE_SECURITY.md](./PICKLE_SECURITY.md) - Model deserialization security
- [KUBERNETES_SECURITY.md](./KUBERNETES_SECURITY.md) - Kubernetes security best practices
- [CI/CD Pipeline Documentation](../.github/workflows/ci.yml) - Complete CI/CD configuration
