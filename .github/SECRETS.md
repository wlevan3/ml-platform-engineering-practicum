# GitHub Secrets Documentation

This document describes all secrets used in GitHub Actions workflows for this repository.

## Table of Contents

- [Claude Code Authentication](#claude-code-authentication)
  - [CLAUDE_CODE_OAUTH_TOKEN](#claude_code_oauth_token)
  - [CLAUDE_CODE_APP_ID](#claude_code_app_id)
  - [CLAUDE_CODE_APP_PRIVATE_KEY](#claude_code_app_private_key)
- [SonarCloud](#sonarcloud)
  - [SONAR_TOKEN](#sonar_token)
- [Setup Instructions](#setup-instructions)
- [Rotation Procedures](#rotation-procedures)

---

## Claude Code Authentication

Claude Code workflows require two types of authentication: **Anthropic API authentication** and **GitHub API authentication**.

### CLAUDE_CODE_OAUTH_TOKEN

**Purpose**: Authenticates with Anthropic's Claude Code service to enable AI-powered code analysis and PR reviews.

**Type**: OAuth token from Anthropic

**Permissions**: Access to Claude Code API

**Used In**:

- `.github/workflows/claude.yml` - Interactive @claude mentions
- `.github/workflows/claude-code-review.yml` - Automatic PR reviews

**Setup**:

1. Sign up for Claude Code at <https://claude.ai/code>
2. Navigate to your profile settings
3. Generate an OAuth token
4. Add as repository secret: `CLAUDE_CODE_OAUTH_TOKEN`  <!-- pragma: allowlist secret -->

**Rotation**:

- **Frequency**: When token expires or is compromised
- **Owner**: Repository administrator
- **Procedure**: Generate new token in Claude Code dashboard, update secret in GitHub

**Notes**: This token is separate from GitHub authentication and only provides access to Anthropic's services.

---

### CLAUDE_CODE_APP_ID

**Purpose**: Identifies the GitHub App used to generate short-lived tokens for Claude Code to interact with GitHub (read PRs, post comments).

**Type**: GitHub App ID (numeric)

**Permissions**: N/A (permissions are defined in the GitHub App configuration)

**Used In**:

- `.github/workflows/claude.yml`
- `.github/workflows/claude-code-review.yml`

**Setup**:

1. Create a GitHub App (see [Setup Instructions](#setup-instructions))
2. Note the App ID from the app settings page
3. Add as repository secret: `CLAUDE_CODE_APP_ID`  <!-- pragma: allowlist secret -->

**Value**: `2213982` (for this repository's `claude-code-ml-platform` app)

**Rotation**:

- **Frequency**: Never (App ID is immutable)
- **Owner**: Repository administrator
- **Procedure**: N/A - if the app needs to be replaced, create a new app and update this secret

---

### CLAUDE_CODE_APP_PRIVATE_KEY

**Purpose**: Private key for the GitHub App, used to generate short-lived installation tokens (1-hour expiration) that allow Claude Code to authenticate with GitHub's API.

**Type**: RSA private key (PEM format)

**Permissions**: Defined by the GitHub App installation:

- **Pull requests**: Read & Write (post comments, read PR content)
- **Issues**: Read & Write (post comments, read issues)
- **Contents**: Read (access repository files)
- **Metadata**: Read (auto-added by GitHub)

**Repository Access**: `ml-platform-engineering-practicum` only

**Used In**:

- `.github/workflows/claude.yml`
- `.github/workflows/claude-code-review.yml`

**Setup**:

1. Create a GitHub App (see [Setup Instructions](#setup-instructions))
2. Generate a private key from the app settings page
3. Download the `.pem` file
4. Add as repository secret: `CLAUDE_CODE_APP_PRIVATE_KEY`  <!-- pragma: allowlist secret -->

   ```bash
   gh secret set CLAUDE_CODE_APP_PRIVATE_KEY --body "$(cat path/to/key.pem)"
   ```

**Security Benefits Over PAT**:

- ✅ Short-lived tokens (1 hour vs 1 year for PATs)
- ✅ Automatic rotation on each workflow run
- ✅ Better audit trail (actions appear as app, not user)
- ✅ No user account dependency
- ✅ Repository-specific installation

**Rotation**:

- **Frequency**:
  - Every 12 months (recommended)
  - Immediately if compromised
  - When changing repository access
- **Owner**: Repository administrator
- **Procedure**:
  1. Go to GitHub App settings: <https://github.com/settings/apps>
  2. Select `claude-code-ml-platform`
  3. Scroll to "Private keys"
  4. Click "Generate a private key"
  5. Download the new `.pem` file
  6. Update secret: `gh secret set CLAUDE_CODE_APP_PRIVATE_KEY --body "$(cat new-key.pem)"`
  7. **Optional**: Revoke the old key after verifying the new one works

**Notes**:

- The private key never expires, but the tokens it generates do (1-hour expiration)
- Keep the `.pem` file secure and never commit it to the repository
- Multiple private keys can exist simultaneously for zero-downtime rotation

---

## SonarCloud

### SONAR_TOKEN

**Purpose**: Authenticates with SonarCloud for code quality and security analysis.

**Type**: SonarCloud project token

**Permissions**: Execute analysis on the project

**Used In**:

- `.github/workflows/ci.yml` - SonarCloud analysis job

**Setup**:

1. Log in to <https://sonarcloud.io>
2. Go to your project settings
3. Generate a new token
4. Add as repository secret: `SONAR_TOKEN`  <!-- pragma: allowlist secret -->

**Rotation**:

- **Frequency**: Every 90 days (recommended) or when compromised
- **Owner**: Repository administrator
- **Procedure**: Generate new token in SonarCloud, update secret in GitHub

---

## Setup Instructions

### Creating a GitHub App for Claude Code

**Step 1: Create the GitHub App**

1. Navigate to <https://github.com/settings/apps>
2. Click **"New GitHub App"**
3. Configure:
   - **Name**: `claude-code-ml-platform` (or unique name)
   - **Homepage URL**: `https://github.com/YOUR_USERNAME/ml-platform-engineering-practicum`
   - **Webhook**: Uncheck "Active" (not needed)

**Step 2: Set Permissions**

Configure **Repository permissions**:

- **Contents**: Read-only
- **Issues**: Read and write
- **Pull requests**: Read and write
- **Metadata**: Read-only (auto-added)

**Step 3: Installation Settings**

- **Where can this GitHub App be installed?**: Only on this account

**Step 4: Create the App**

Click **"Create GitHub App"**

**Step 5: Install the App**

1. Click **"Install App"** in the left sidebar
2. Select your account
3. Choose **"Only select repositories"**
4. Select `ml-platform-engineering-practicum`
5. Click **"Install"**

**Step 6: Generate Private Key**

1. Go back to app settings: <https://github.com/settings/apps>
2. Click on your app name
3. Scroll to **"Private keys"**
4. Click **"Generate a private key"**
5. Save the downloaded `.pem` file securely

**Step 7: Get App ID**

On the app settings page, note the **App ID** at the top (e.g., `2213982`)

**Step 8: Add Secrets to Repository**

```bash
# Add App ID
gh secret set CLAUDE_CODE_APP_ID --body "2213982"

# Add Private Key
gh secret set CLAUDE_CODE_APP_PRIVATE_KEY --body "$(cat ~/Downloads/claude-code-ml-platform.*.private-key.pem)"
```

---

## Rotation Procedures

### Emergency Rotation (Compromised Secret)

If a secret is compromised:

1. **Immediately revoke** the compromised credential:
   - **GitHub App**: Generate new private key, delete old one
   - **OAuth Token**: Revoke in Claude Code dashboard
   - **SonarCloud**: Revoke in SonarCloud settings

2. **Generate new credential** following setup instructions above

3. **Update GitHub secret**:

   ```bash
   gh secret set SECRET_NAME --body "NEW_VALUE"
   ```

4. **Verify workflows** run successfully with new secret

5. **Document the incident** (who, what, when, why)

### Routine Rotation Schedule

| Secret | Frequency | Owner |
|--------|-----------|-------|
| `CLAUDE_CODE_OAUTH_TOKEN` | As needed (when expired) | Repository admin |
| `CLAUDE_CODE_APP_PRIVATE_KEY` | Every 12 months | Repository admin |
| `SONAR_TOKEN` | Every 90 days | Repository admin |

### Rotation Best Practices

1. **Test in a branch first**: Update secret, push to test branch, verify workflow runs
2. **Zero-downtime rotation**: For GitHub App, generate new key before revoking old one
3. **Document rotation**: Note date and reason in a secure location
4. **Verify all workflows**: Check that all dependent workflows pass after rotation

---

## Troubleshooting

### Claude Code Authentication Failures

**Error**: `Failed to setup GitHub token: Error: User does not have write access`

**Cause**: Missing or incorrect `CLAUDE_CODE_APP_PRIVATE_KEY` or `CLAUDE_CODE_APP_ID`

**Solution**:

1. Verify secrets are set: `gh secret list`
2. Verify GitHub App is installed on the repository
3. Verify App has correct permissions (Pull requests: read/write)
4. Generate a new private key and update the secret

### Expired or Invalid Tokens

**Error**: Various authentication errors

**Solution**:

1. Check token expiration in the service's dashboard
2. Generate a new token
3. Update the corresponding GitHub secret

---

## Security Notes

### Never Commit Secrets

- ❌ Never commit secrets to the repository
- ❌ Never log secrets in workflow output
- ❌ Never share secrets via insecure channels

### Secret Scope

- Secrets are **repository-scoped** by default
- Organization secrets can be shared across repositories if needed
- Limit access to secrets to only necessary workflows

### Audit Trail

GitHub provides an audit log for secret access:

1. Go to **Settings → Security → Audit log**
2. Filter by `action:repo.secret_access`
3. Review when secrets were used and by which workflows

---

## Contact

For questions or issues with secrets:

- **Repository Owner**: @wlevan3
- **Security Concerns**: Create a private security advisory

Last Updated: 2025-10-31
