# Security Guide

This document outlines the security practices, scanning tools, and policies for the ML Platform project.

## Table of Contents

- [Model Security](#model-security)
- [Secret Management](#secret-management)
- [Security Scanning](#security-scanning)
- [Vulnerability Management](#vulnerability-management)

## Model Security

### Secure Deserialization (skops.io)

Models are serialized using **skops.io** (v0.13.0+), which provides pickle-free deserialization
to address [CWE-502](https://cwe.mitre.org/data/definitions/502.html) (Deserialization of
Untrusted Data).

**Why skops.io?**

Traditional Python model serialization (pickle/joblib) can execute arbitrary code during
deserialization, creating a serious security vulnerability. skops.io provides a safe
alternative that:

- **Prevents arbitrary code execution** during deserialization
- **Validates object types** before loading
- **Provides transparent security** with untrusted type detection

### Security Layers

Our model loading implements multiple security layers:

#### 1. Execution Safety (skops.io)

- **Format**: `.skops` files (not `.joblib` or `.pkl`)
- **Validation**: Checks for untrusted types before loading
- **Trusted types**: Only allows standard ML library types (sklearn, numpy, scipy)
- **Rejection**: Raises `ModelIntegrityError` if untrusted types detected

```python
# From services/api/model.py
untrusted_types = sio.get_untrusted_types(file=self.model_path)
if untrusted_types:
    raise ModelIntegrityError(f"Model contains untrusted types: {untrusted_types}")

# Load with only default trusted types
# Note: untrusted_types is [] here (validated empty above - only trust defaults)
self.model = sio.load(self.model_path, trusted=untrusted_types)
```

#### 2. Integrity Verification (SHA-256 Hashing)

- **Hash generation**: During training in `train_model.py`
- **Hash storage**: In `model_metadata.json`
- **Hash verification**: Before loading in `services/api/model.py`
- **Detection**: Identifies file corruption or tampering

```python
# From services/api/model.py
expected_hash = self.metadata.get("model_hash")
actual_hash = calculate_file_hash(self.model_path, algorithm="sha256")

# Constant-time comparison prevents timing attacks
if not hmac.compare_digest(expected_hash, actual_hash):
    raise ModelIntegrityError("Model file integrity verification failed!")
```

#### 3. Source Control

- **Training environment**: Models trained locally via `train_model.py`
- **Controlled execution**: Only in development/CI environments
- **No user input**: Model path is hardcoded (`services/api/models/iris_classifier.skops`)
- **No external models**: Never load models from untrusted sources

### Security Model Summary

| Protection | Purpose | Implementation |
|------------|---------|----------------|
| **skops.io** | Prevents code execution (CWE-502) | Type validation, safe deserialization |
| **SHA-256 hash** | Detects tampering/corruption | Hash verification before loading |
| **Source control** | Ensures trusted origin | Local training only, no external models |

**These protections are complementary, not redundant.**

### Future: MLflow Integration (Phase 3)

Phase 3 will integrate with MLflow Model Registry while maintaining security:

- Custom PyFunc wrapper for skops models
- Hash verification in MLflow artifacts
- Signed model metadata
- See `docs/PICKLE_SECURITY.md` for comprehensive security analysis

## Secret Management

### Policies

- **Never commit secrets** - Use environment variables or AWS Secrets Manager
- **No hardcoded credentials** - API keys, tokens, passwords must be external
- **Rotation**: Rotate secrets regularly (at least every 90 days)
- **Least privilege**: Use minimal required permissions

### Detection Tools

#### Pre-commit Hook: detect-secrets

Scans for accidental credential commits before they reach the repository.

```bash
# Runs automatically on git commit
# Or manually:
pre-commit run detect-secrets --all-files
```

**Handling false positives**:

```bash
# Add to .secrets.baseline
detect-secrets scan --baseline .secrets.baseline

# Update baseline
detect-secrets scan --update .secrets.baseline
```

#### CI: Gitleaks

Comprehensive secret detection in CI pipeline.

- **Runs**: On every PR and push to main
- **Scans**: Entire git history
- **Blocks**: PRs if secrets detected
- **Patterns**: 700+ secret patterns

**Remediation**: If secrets are detected, see `docs/VULNERABILITY_REMEDIATION.md`.

### Environment Variables

For local development:

```bash
# Create .env file (gitignored)
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret

# Load in application
from dotenv import load_dotenv
load_dotenv()
```

For production (AWS):

- **AWS Secrets Manager**: For application secrets
- **IAM roles**: For AWS service access (no keys needed)
- **Parameter Store**: For configuration values

## Security Scanning

The project uses a **multi-layer security scanning approach** for defense in depth.

### Layer 1: Pre-commit Hooks (Local Development)

Run automatically before each commit:

#### detect-secrets

- **Purpose**: Prevent accidental credential commits
- **Scope**: All files in changeset
- **Action**: Blocks commit if secrets detected

#### Semgrep

- **Purpose**: Static Application Security Testing (SAST)
- **Ruleset**: Custom rules in `.semgrep.yml`
- **Patterns**: SQL injection, XSS, insecure deserialization, etc.

```bash
# Run manually
pre-commit run semgrep --all-files
```

### Layer 2: CI Pipeline (Automated)

Run on every PR and push to `main`:

#### Trivy (Container and Filesystem Scanning)

Scans for vulnerabilities in:

- **OS packages** (Debian base image)
- **Python dependencies** (requirements.txt)
- **Dockerfile best practices**

**Configuration**:

- Separate scans for builder and runtime stages
- Fail-fast on HIGH/CRITICAL vulnerabilities
- Results uploaded to GitHub Security tab

```bash
# Run locally
trivy image ml-platform-api:latest --severity HIGH,CRITICAL
trivy fs . --severity HIGH,CRITICAL
```

#### Gitleaks (Secret Detection)

- **Scope**: Entire git history
- **Patterns**: 700+ secret patterns
- **Action**: Fails build if secrets found

#### Semgrep (SAST)

- **Rulesets**:
  - `p/security-audit` - Security vulnerabilities
  - `p/owasp-top-ten` - OWASP Top 10
  - `p/python` - Python-specific issues
- **Action**: Fails on HIGH/CRITICAL findings

#### SonarCloud (Code Quality + Security)

- **Analysis**: Code smells, bugs, security hotspots
- **Coverage**: Requires 80%+ test coverage
- **Quality gate**: Must pass for PR merge

### Layer 3: GitHub Actions Security

#### Pinned SHA Hashes

Security scanning actions use **pinned SHA hashes** instead of version tags to prevent supply chain attacks.

**Example**:

```yaml
# Bad: Uses mutable tag
- uses: aquasecurity/trivy-action@master

# Good: Uses immutable SHA
- uses: aquasecurity/trivy-action@6e7b7d1fd3e4fef0c5fa8cce1229c54b2c9bd0d8
```

**Benefits**:

- Prevents malicious updates to action code
- Ensures reproducible builds
- GitHub Dependabot updates SHAs automatically

## Vulnerability Management

### Workflow

1. **Detection**: Security scanner finds vulnerability
2. **Triage**: Assess severity and exploitability
3. **Remediation**: Fix or mitigate
4. **Documentation**: Update changelog

See `docs/VULNERABILITY_REMEDIATION.md` for detailed workflow.

### Trivy Findings

**High/Critical vulnerabilities**: Must be fixed before merge

**Options**:

1. **Update dependency**: Preferred solution
2. **Mitigation**: If no fix available, document risk
3. **Suppress**: Use `.trivyignore` with justification

**Example .trivyignore**:

```text
# CVE-2024-1234 - No fix available, low exploitability
# Risk: Requires local access to exploit
# Mitigation: AWS WAF blocks malicious requests
CVE-2024-1234
```

### SBOM Tracking

Software Bill of Materials (SBOM) provides:

- **Dependency inventory**: Complete list of all components
- **Vulnerability tracking**: Map CVEs to components
- **Compliance**: Required for government contracts (EO 14028)

See `docs/SBOM_GENERATION.md` for details.

### Security Advisories

For **discovered vulnerabilities**:

1. **Do not** create public issues
2. Use GitHub Security Advisories
3. Coordinate disclosure with maintainers
4. Follow 90-day disclosure timeline

## Reporting Security Issues

**Do not report security vulnerabilities through public GitHub issues.**

Instead:

1. Use GitHub Security Advisories
2. Or create a private security advisory via GitHub's Security tab
3. Include:
   - Description of vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

## Security Checklist

Before merging PRs, ensure:

- [ ] No secrets in code or commits
- [ ] Pre-commit hooks pass
- [ ] Trivy scans pass (no HIGH/CRITICAL)
- [ ] Gitleaks scan passes
- [ ] Semgrep scan passes
- [ ] SonarCloud quality gate passes
- [ ] Dependencies up to date
- [ ] SBOM generated

## References

- **Vulnerability Remediation**: `docs/VULNERABILITY_REMEDIATION.md`
- **SBOM Generation**: `docs/SBOM_GENERATION.md`
- **Model Security**: `docs/PICKLE_SECURITY.md`
- **AWS OIDC Setup**: `docs/AWS_OIDC_SETUP.md`
- **CWE-502**: <https://cwe.mitre.org/data/definitions/502.html>
- **OWASP Top 10**: <https://owasp.org/www-project-top-ten/>
