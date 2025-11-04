# Container Image Signing with Cosign

## Overview

This document details the implementation of container image signing using **Cosign** for the
ml-platform-engineering-practicum project. Image signing establishes cryptographic proof of
image provenance and integrity, protecting against supply chain attacks and unauthorized
image modifications.

## Why Image Signing Matters

**Supply Chain Security Threats**:

- **Compromised registries**: Attackers modify images after upload
- **Man-in-the-middle attacks**: Images tampered during transit
- **Unauthorized images**: Malicious images deployed to production
- **Configuration drift**: Uncertainty about deployed image authenticity

**Image Signing Benefits**:

- **Provenance verification**: Cryptographically prove image source and build identity
- **Integrity protection**: Detect any modifications after signing
- **Non-repudiation**: Audit trail of who signed which images and when
- **Policy enforcement**: Kubernetes admission controllers block unsigned images

## Sigstore and Cosign

[Sigstore](https://www.sigstore.dev/) is an open-source project providing transparent
cryptographic signing infrastructure for software supply chains.

**Cosign** is Sigstore's container image signing tool:

- **Keyless signing**: Uses OpenID Connect (OIDC) identity instead of managing keys
- **OCI registry storage**: Signatures stored alongside images (no separate infrastructure)
- **Transparency log**: All signatures recorded in Rekor (immutable audit log)
- **Kubernetes integration**: Works with admission controllers for policy enforcement

## Implementation Approach

This project uses **keyless signing** via GitHub Actions OIDC identity.

### Keyless Signing (Implemented)

**How it works**:

1. GitHub Actions workflow requests OIDC token from `token.actions.githubusercontent.com`
2. Cosign signs image using ephemeral key pair
3. Fulcio (Sigstore CA) issues short-lived certificate bound to OIDC identity
4. Signature + certificate stored in OCI registry
5. Signature recorded in Rekor transparency log
6. Verification checks certificate identity and OIDC issuer

**Advantages**:

- ✅ No key management overhead (no private keys to secure)
- ✅ Automatic key rotation (ephemeral keys per signing)
- ✅ Audit trail via Rekor transparency log
- ✅ Certificate bound to GitHub Actions workflow identity

**Trade-offs**:

- Requires OIDC provider (GitHub Actions provides this)
- Depends on Sigstore public infrastructure (Fulcio, Rekor)
- Not suitable for air-gapped environments (use key-based signing instead)

### Key-Based Signing (Alternative)

**How it works**:

1. Generate key pair: `cosign generate-key-pair`
2. Store private key in GitHub Secrets (password-protected)
3. Sign with private key
4. Verify with public key

**When to use**:

- Air-gapped environments without internet access
- Organizational policy requires local key management
- Need to sign without OIDC provider

## CI/CD Pipeline Integration

### Workflow Configuration

The signing process is integrated into `.github/workflows/ci.yml` in the `docker-build-scan` job.

**Required permissions**:

```yaml
permissions:
  security-events: write  # Upload Trivy SARIF results
  contents: read          # Checkout code
  id-token: write         # Request OIDC token for keyless signing
```

### Signing Steps

**1. Install Cosign**:

```yaml
- name: Install Cosign
  uses: sigstore/cosign-installer@dc72c7d5c4d10cd6bcb8cf6e3fd625a9e5e537da  # v3.7.0
  with:
    cosign-release: 'v2.4.1'
```

**2. Sign Image (Keyless)**:

```yaml
- name: Sign container image (keyless)
  env:
    COSIGN_EXPERIMENTAL: "1"  # Enable keyless signing
  run: |
    echo "Signing image ml-platform-api:${{ github.sha }} with keyless signing (OIDC)"
    cosign sign --yes ml-platform-api:${{ github.sha }}
    echo "✅ Image signed successfully"
```

**3. Verify Signature**:

```yaml
- name: Verify container image signature
  env:
    COSIGN_EXPERIMENTAL: "1"
  run: |
    echo "Verifying signature for ml-platform-api:${{ github.sha }}"
    cosign verify \
      --certificate-identity-regexp="https://github.com/${{ github.repository }}/*" \
      --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
      ml-platform-api:${{ github.sha }}
    echo "✅ Signature verified successfully"
```

### Signature Storage

Signatures are stored in the **same OCI registry** as the image:

- Image: `ml-platform-api:sha256-abc123...`
- Signature: `ml-platform-api:sha256-abc123....sig` (OCI artifact)

This co-location ensures:

- Atomic operations (image + signature pushed together)
- No separate signature infrastructure needed
- Registry access controls apply to both image and signature

## Local Testing

### Prerequisites

Install Cosign locally:

```bash
# macOS (Homebrew)
brew install cosign

# Linux (binary download)
wget https://github.com/sigstore/cosign/releases/download/v2.4.1/cosign-linux-amd64
chmod +x cosign-linux-amd64
sudo mv cosign-linux-amd64 /usr/local/bin/cosign

# Verify installation
cosign version
```

### Build and Sign Image Locally

**1. Build Docker image**:

```bash
# Ensure model is trained
python train_model.py

# Build image
docker build -t ml-platform-api:local .
```

**2. Sign with keyless signing** (requires GitHub authentication):

```bash
# Enable keyless signing
export COSIGN_EXPERIMENTAL=1

# Sign image (opens browser for GitHub authentication)
cosign sign ml-platform-api:local

# Signature stored locally in Docker daemon
```

**Note**: Keyless signing locally requires authentication to an OIDC provider.
For purely local testing without OIDC, use key-based signing:

```bash
# Generate test key pair
cosign generate-key-pair

# Sign with private key (password prompt)
cosign sign --key cosign.key ml-platform-api:local

# Verify with public key
cosign verify --key cosign.pub ml-platform-api:local
```

### Verify Image Signature

**Keyless verification** (verifies certificate and OIDC identity):

```bash
export COSIGN_EXPERIMENTAL=1

# Verify with certificate identity regex
cosign verify \
  --certificate-identity-regexp="https://github.com/wlevan3/ml-platform-engineering-practicum/*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ml-platform-api:local
```

**Key-based verification**:

```bash
# Verify with public key
cosign verify --key cosign.pub ml-platform-api:local
```

**Expected output** (successful verification):

```json
[
  {
    "critical": {
      "identity": {
        "docker-reference": "ml-platform-api"
      },
      "image": {
        "docker-manifest-digest": "sha256:abc123..."
      },
      "type": "cosign container image signature"
    },
    "optional": {
      "Bundle": {
        "SignedEntryTimestamp": "...",
        "Payload": {
          "body": "...",
          "integratedTime": 1234567890,
          "logIndex": 12345678,
          "logID": "..."
        }
      }
    }
  }
]
```

### Inspect Signature Metadata

```bash
# View signature details
cosign tree ml-platform-api:local

# View certificate information
cosign verify --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ml-platform-api:local | jq -r '.[0].optional.Bundle.Payload.body' | base64 -d | jq
```

## Kubernetes Verification

Kubernetes admission controllers enforce signature verification before pod creation.
Two popular options:

### Option 1: Sigstore Policy Controller (Recommended for Keyless)

[Sigstore Policy Controller](https://docs.sigstore.dev/policy-controller/overview/) is
a Kubernetes admission controller enforcing Sigstore signatures.

**Installation**:

```bash
# Install with Helm
helm repo add sigstore https://sigstore.github.io/helm-charts
helm repo update

helm install policy-controller sigstore/policy-controller \
  --namespace sigstore-system \
  --create-namespace
```

**ClusterImagePolicy Example** (keyless verification):

```yaml
apiVersion: policy.sigstore.dev/v1beta1
kind: ClusterImagePolicy
metadata:
  name: ml-platform-images
spec:
  images:
    - glob: "**ml-platform-api**"  # Match all ml-platform-api images
  authorities:
    - keyless:
        url: https://fulcio.sigstore.dev  # Sigstore public Fulcio CA
        identities:
          - issuer: https://token.actions.githubusercontent.com
            subjectRegExp: "https://github.com/wlevan3/ml-platform-engineering-practicum/*"
```

**Behavior**:

- Pods with `ml-platform-api` images are only admitted if signatures verify
- Verification checks certificate identity matches GitHub repository
- Unsigned or tampered images are rejected at admission time

**Testing**:

```bash
# Deploy signed image (succeeds)
kubectl apply -f k8s/deployment.yaml

# Deploy unsigned image (rejected)
kubectl run test --image=ml-platform-api:unsigned
# Error: admission webhook denied the request: validation failed: no matching signatures
```

### Option 2: Kyverno (Flexible Policy Engine)

[Kyverno](https://kyverno.io/) is a Kubernetes policy engine supporting image verification.

**Installation**:

```bash
# Install with Helm
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace
```

**ClusterPolicy Example** (key-based verification):

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-ml-platform-images
spec:
  validationFailureAction: Enforce  # Reject non-compliant images
  rules:
    - name: verify-signature
      match:
        any:
          - resources:
              kinds:
                - Pod
      verifyImages:
        - imageReferences:
            - "ml-platform-api*"
          attestors:
            - entries:
                - keys:
                    publicKeys: |-
                      -----BEGIN PUBLIC KEY-----
                      <BASE64-ENCODED-PUBLIC-KEY>
                      -----END PUBLIC KEY-----
```

**ClusterPolicy Example** (keyless verification):

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-ml-platform-images-keyless
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-signature-keyless
      match:
        any:
          - resources:
              kinds:
                - Pod
      verifyImages:
        - imageReferences:
            - "ml-platform-api*"
          attestors:
            - entries:
                - keyless:
                    subject: "https://github.com/wlevan3/ml-platform-engineering-practicum/*"
                    issuer: "https://token.actions.githubusercontent.com"
                    rekor:
                      url: https://rekor.sigstore.dev
```

**Behavior**:

- Kyverno validates all pod creation requests
- Images must have valid signatures matching policy
- Violations are logged and rejected

**Testing**:

```bash
# Check policy status
kubectl get clusterpolicy

# View policy reports
kubectl get policyreport -A

# Test with signed image
kubectl apply -f k8s/deployment.yaml
# Pod creation succeeds

# Test with unsigned image
kubectl run test --image=ml-platform-api:unsigned
# Error: policy verify-ml-platform-images failed: image verification failed
```

## Comparison: Policy Controller vs. Kyverno

| Feature                  | Sigstore Policy Controller | Kyverno                         |
| ------------------------ | -------------------------- | ------------------------------- |
| **Keyless signing**      | Native support             | Supported                       |
| **Key-based signing**    | Supported                  | Native support                  |
| **Sigstore integration** | Deep integration           | Basic integration               |
| **Policy flexibility**   | Image verification only    | General-purpose policy engine   |
| **Learning curve**       | Low (focused scope)        | Moderate (broad capabilities)   |
| **Use case**             | Dedicated image signing    | Multi-policy enforcement        |
| **Recommendation**       | Best for keyless signing   | Best for mixed policy workloads |

**Recommendation**: Use **Sigstore Policy Controller** for this project since we're using
keyless signing with GitHub Actions OIDC.

## Security Best Practices

### 1. Signature Verification in Production

**Always verify signatures** before deploying to production:

```bash
# Manual verification before kubectl apply
cosign verify \
  --certificate-identity-regexp="https://github.com/wlevan3/ml-platform-engineering-practicum/*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  <image-ref>

# Deploy only if verification succeeds
kubectl apply -f k8s/deployment.yaml
```

### 2. Admission Controller Enforcement

**Enable admission controllers** in production Kubernetes clusters:

- Prevents human error (accidentally deploying unsigned images)
- Enforces policy consistently across all deployments
- Provides audit trail of verification attempts

### 3. Registry Access Controls

**Protect both images and signatures**:

- Use private registries with authentication
- Apply least-privilege access controls
- Enable registry audit logging
- Monitor for unauthorized pushes

### 4. Signature Transparency

**Leverage Rekor transparency log**:

- All signatures publicly auditable (immutable log)
- Detect backdating or signature forgery attempts
- Verify signature timestamp matches build time

**Query Rekor**:

```bash
# Search Rekor for image signatures
rekor-cli search --artifact ml-platform-api:latest

# Verify log entry
rekor-cli get --log-index <LOG_INDEX>
```

### 5. Rotate Keys Regularly

**For key-based signing**:

- Generate new key pairs quarterly
- Re-sign images with new keys
- Retire old keys after grace period
- Document key lifecycle in operations runbook

**For keyless signing**:

- Automatic rotation (ephemeral keys per signing)
- No manual key management required

## Troubleshooting

### Signature Verification Fails

**Error**: `Error: no matching signatures`

**Causes**:

1. Image not signed
2. Signature not pushed to registry
3. Incorrect certificate identity or issuer

**Solution**:

```bash
# Check if signature exists
cosign tree ml-platform-api:latest

# Verify with verbose output
cosign verify --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ml-platform-api:latest --debug
```

### OIDC Authentication Fails

**Error**: `Error: getting signer: getting key: getting OIDC token`

**Causes**:

1. Missing `id-token: write` permission in workflow
2. OIDC provider unavailable
3. GitHub Actions runner network issues

**Solution**:

```yaml
# Ensure workflow has correct permissions
permissions:
  id-token: write
  contents: read
```

### Registry Push Errors

**Error**: `Error: PUT https://registry.io/v2/ml-platform-api/manifests/sha256-...`

**Causes**:

1. Registry authentication missing
2. Insufficient permissions (write access required)
3. OCI artifact support disabled in registry

**Solution**:

- Authenticate to registry: `docker login <registry>`
- Verify OCI artifact support: Check registry documentation
- Enable OCI artifact support if using older registries

## Phase 2 Roadmap

Future enhancements for production deployment:

- [ ] Push signed images to AWS ECR
- [ ] Enable ECR vulnerability scanning on signed images
- [ ] Deploy Sigstore Policy Controller to EKS cluster
- [ ] Configure ClusterImagePolicy for ml-platform namespace
- [ ] Implement signature verification in ArgoCD/Flux
- [ ] Set up Rekor monitoring and alerting
- [ ] Document key-based signing for air-gapped scenarios
- [ ] Integrate with AWS KMS for key-based signing alternative

## References

- [Cosign Documentation](https://docs.sigstore.dev/cosign/overview/) - Official Cosign docs
- [Sigstore](https://www.sigstore.dev/) - Project homepage
- [Keyless Signing](https://docs.sigstore.dev/cosign/keyless/) - Keyless signing guide
- [Sigstore Policy Controller](https://docs.sigstore.dev/policy-controller/overview/) - Admission controller
- [Kyverno Image Verification](https://kyverno.io/docs/writing-policies/verify-images/) - Kyverno policies
- [Fulcio](https://docs.sigstore.dev/fulcio/overview/) - Certificate authority
- [Rekor](https://docs.sigstore.dev/rekor/overview/) - Transparency log
- [SLSA Framework](https://slsa.dev/) - Supply chain security framework
- [NIST SP 800-204D](https://csrc.nist.gov/publications/detail/sp/800-204d/draft) - Container image signing

## Maintenance

**When to re-verify signatures**:

- After pulling images from registry
- Before deploying to production
- During incident response (verify deployed images)
- Quarterly security audits

**Monitoring**:

- CI/CD pipeline signature verification success rate
- Admission controller rejection metrics
- Rekor transparency log entries
- Registry push/pull audit logs
