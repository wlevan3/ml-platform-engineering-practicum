# Security Policy

## Supported Versions

Currently supported versions for security updates:

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via:

- **GitHub Security Advisories**: [Report a vulnerability](https://github.com/wlevan3/ml-platform-engineering-practicum/security/advisories/new)
- **Email**: <wlevan3@github.com>

Please include:

- Type of vulnerability
- Full paths to source files related to the issue
- Location of the affected code (tag/branch/commit or direct URL)
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact assessment and potential attack scenarios

## Response Timeline

- **Initial response**: Within 48 hours
- **Status update**: Within 7 days
- **Fix timeline**: 30-90 days depending on severity
- **Public disclosure**: After fix is released and users have been notified

## Security Update Process

1. Vulnerability is reported and acknowledged
2. Issue is investigated and severity assessed (using CVSS scoring)
3. Fix is developed and tested in a private security branch
4. Security advisory is created
5. Fix is released and security advisory published
6. Public disclosure after 90 days or when fix is deployed (whichever comes first)

## Severity Classification

We use the Common Vulnerability Scoring System (CVSS) to assess severity:

- **CRITICAL** (9.0-10.0): Immediate action required
- **HIGH** (7.0-8.9): Fix within 30 days
- **MEDIUM** (4.0-6.9): Fix within 60 days
- **LOW** (0.1-3.9): Fix within 90 days

## Security Best Practices

This repository implements several security measures:

- Secret scanning and push protection enabled
- Automated dependency updates via Dependabot
- CodeQL code scanning for vulnerability detection
- Container image scanning with Trivy
- Infrastructure as Code (IaC) security scanning
- Branch protection rules requiring security checks to pass

## Secret Remediation Process

If you accidentally commit a secret or receive a secret scanning alert, follow these steps immediately:

### 1. Rotate the Compromised Credential

**CRITICAL**: Assume any secret pushed to GitHub has been compromised and must be rotated immediately.

- **AWS Keys**: Deactivate the key in AWS IAM Console and generate a new one
- **API Tokens**: Revoke the token in the service provider's dashboard
- **Passwords**: Change the password immediately
- **SSH Keys**: Remove the key from authorized systems and generate a new keypair

### 2. Remove the Secret from Git History

Secrets must be removed from the entire git history, not just the latest commit:

#### Option A: Using BFG Repo-Cleaner (Recommended)

```bash
# Install BFG
brew install bfg  # macOS
# or download from: https://rtyley.github.io/bfg-repo-cleaner/

# Clone a fresh copy
git clone --mirror https://github.com/wlevan3/ml-platform-engineering-practicum.git

# Remove secrets (replace YOUR-SECRET with the actual secret)
bfg --replace-text passwords.txt repo.git  # using a file with secrets
# or
bfg --delete-files secret_file.txt repo.git  # delete specific files

# Clean up and force push
cd repo.git
git reflog expire --expire=now --all && git gc --prune=now --aggressive
git push --force
```

#### Option B: Using git-filter-repo

```bash
# Install git-filter-repo
pip install git-filter-repo

# Remove file from history
git filter-repo --path path/to/secret/file.txt --invert-paths

# Force push
git push origin --force --all
```

### 3. Verify Secret Removal

- Check the Security tab in GitHub to confirm the alert is resolved
- Run `detect-secrets scan --baseline .secrets.baseline` locally to verify the secret is gone
- Review recent commits to ensure the secret is not in any branch

### 4. Document the Incident

- Create a private incident report documenting:
  - What secret was exposed
  - When it was committed and discovered
  - What systems/services were affected
  - Actions taken (rotation, removal, verification)
  - Lessons learned and preventive measures

### 5. Monitor for Unauthorized Access

- Review access logs for affected services (AWS CloudTrail, application logs, etc.)
- Look for any suspicious activity during the exposure window
- Set up monitoring alerts for the affected services

## Security Contacts

For security-related questions or concerns, please contact:

- **Primary**: <wlevan3@github.com>
- **GitHub**: @wlevan3

## Acknowledgments

We appreciate the security research community's efforts to responsibly disclose vulnerabilities.
Security researchers who follow our disclosure process will be acknowledged in security advisories
(unless they prefer to remain anonymous).
