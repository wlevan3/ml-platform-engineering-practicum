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
- **Email**: wlevan3@github.com

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

## Security Contacts

For security-related questions or concerns, please contact:
- **Primary**: wlevan3@github.com
- **GitHub**: @wlevan3

## Acknowledgments

We appreciate the security research community's efforts to responsibly disclose vulnerabilities. Security researchers who follow our disclosure process will be acknowledged in security advisories (unless they prefer to remain anonymous).
