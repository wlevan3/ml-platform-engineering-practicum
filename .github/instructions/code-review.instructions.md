# GitHub Copilot Code Review Instructions

## General Review Guidelines

When reviewing pull requests in this repository, follow these guidelines:

### Code Quality

- Check for adherence to project conventions defined in `CLAUDE.md`
- Verify code follows Python PEP 8 standards (enforced by Black and Ruff)
- Ensure proper type hints are used
- Check for comprehensive docstrings

### Security

- Identify potential security vulnerabilities (SQL injection, XSS, etc.)
- Check for exposed secrets or credentials
- Verify input validation and sanitization
- Review authentication and authorization logic

### Testing

- Ensure new features have corresponding tests
- Check test coverage meets 80%+ threshold
- Verify tests are meaningful and not just placeholder

### Performance

- Identify potential performance bottlenecks
- Check for unnecessary database queries or API calls
- Review memory usage patterns

## Special Instructions for Dependency Updates

**IMPORTANT**: When reviewing dependency or version updates:

1. **DO NOT flag versions as invalid based solely on your training data cutoff date**
   - Your knowledge may be outdated
   - Versions released after your training cutoff are not automatically invalid

2. **Verify versions before raising concerns**:
   - Check the PR description for version verification evidence
   - Look for CI/CD checks that validate the dependencies
   - If the PR author has documented version verification, trust it
   - Suggest verification commands but don't assume versions are wrong

3. **Helpful dependency review checklist**:
   - ✅ Are breaking changes documented in the PR description?
   - ✅ Have the changes been tested locally?
   - ✅ Are there any security advisories for the old versions?
   - ✅ Do version numbers follow semantic versioning?
   - ⚠️ Major version bumps (X.0.0) may have breaking changes
   - ⚠️ Check if configuration updates are needed

4. **Example good feedback**:

   ```text
   ✅ GOOD: "Consider checking the release notes for Black 25.9.0
   to ensure no breaking changes affect your codebase."

   ❌ BAD: "Black 25.9.0 appears invalid - my knowledge only goes
   to version 24.x. Please verify this version exists."
   ```

5. **When to raise version concerns**:
   - ✅ Version number doesn't follow semver (e.g., `1.2.3.4.5`)
   - ✅ Major version jump without breaking change documentation
   - ✅ Dependency conflicts or incompatibilities mentioned
   - ❌ Version is newer than your training data cutoff

## Repository-Specific Context

### Project Type

- **ML Platform Learning Project**: Production-grade practices in a learning context
- Focus on hands-on experience with infrastructure, MLOps, and platform engineering

### Technology Stack

- Python 3.13 with `uv` package manager
- FastAPI for REST API
- Pre-commit hooks for code quality
- Docker for containerization
- Future: AWS EKS, Terraform, MLflow (Phases 2+)

### Branch Strategy

- `main` branch is protected
- Feature branches use format: `<type>/<description>`
- All changes via pull requests
- Squash merge to keep history clean

### CI/CD Pipeline

- Comprehensive checks: linting, testing, security scanning
- Non-blocking quality checks (continue-on-error pattern)
- Summary job shows all check results

## Tone and Style

- **Be constructive**: Focus on improvement, not criticism
- **Be specific**: Cite line numbers and provide examples
- **Be educational**: Explain the "why" behind suggestions
- **Be pragmatic**: Consider this is a learning project
- **Be objective**: Don't validate assumptions without evidence

## What NOT to Do

- ❌ Don't flag versions as invalid without verification
- ❌ Don't suggest adding features outside the PR scope
- ❌ Don't criticize for learning-appropriate shortcuts
- ❌ Don't assume outdated information is correct
- ❌ Don't over-engineer solutions for a learning project
