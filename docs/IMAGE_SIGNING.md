# Container Image Signing with Cosign

## Overview

This document details container image signing using **Cosign** for the ml-platform-engineering-practicum project. Image signing establishes cryptographic proof of image provenance and integrity, protecting against supply chain attacks and unauthorized modifications.

## Why Image Signing Matters

**Threats:** Compromised registries | MITM attacks | Unauthorized images | Configuration drift

**Benefits:** Provenance verification ✅ | Integrity protection ✅ | Non-repudiation ✅ | Policy enforcement ✅

## Sigstore and Cosign

[Sigstore][sigstore] provides transparent cryptographic signing infrastructure. **Cosign** features:

- **Keyless signing**: OIDC identity instead of key management
- **OCI registry storage**: Signatures alongside images
- **Transparency log**: Immutable audit via Rekor
- **Kubernetes integration**: Admission controller support

## Implementation Approach

This project uses **keyless signing** via GitHub Actions OIDC.

### Keyless Signing (Implemented)

**Flow:** GitHub Actions OIDC token → Cosign ephemeral keys → Fulcio certificate → OCI registry + Rekor log

**Pros:** No key management ✅ | Auto rotation ✅ | Audit trail ✅ | Identity-bound ✅
**Cons:** Requires OIDC ❌ | Depends on Sigstore infrastructure ❌ | Not air-gapped ❌

### Key-Based Signing (Alternative)

```bash
cosign generate-key-pair                          # Generate keys
cosign sign --key cosign.key image:tag            # Sign
cosign verify --key cosign.pub image:tag          # Verify
```

**When to use:** Air-gapped environments | Local key management policy | No OIDC provider

## CI/CD Pipeline Integration

### Implementation Phases

#### Phase 1: Offline/Local Signing (Current)

**Status:** Demo/testing - signatures don't persist

**Benefits:** OIDC validation ✅ | No registry needed ✅
**Limitations:** Ephemeral files ⚠️ | Not production-ready ⚠️

#### Phase 2: Registry Signing ([Issue #94][issue-94])

Once ECR provisioned: Push to ECR → Sign registry images → Signatures persist → Kubernetes verification enabled

**Why Phase 1 first?** Focused PR reviews | Validate workflow | Phased approach

### Workflow Configuration

```yaml
permissions:
  id-token: write    # Request OIDC token for keyless signing
  contents: read
  security-events: write
```

### Signing Steps

**Install Cosign:**

```yaml
- uses: sigstore/cosign-installer@dc72c7d5c4d10cd6bcb8cf6e3fd625a9e5e537da  # v3.7.0
  with:
    cosign-release: 'v2.4.1'
```

**Sign (Phase 1 Offline):**

```yaml
- name: Sign image (keyless - offline)
  env:
    COSIGN_EXPERIMENTAL: "1"
  run: |
    cosign sign --yes --upload=false \
      --output-signature=ml-platform-api.sig \
      --output-certificate=ml-platform-api.crt \
      ml-platform-api:${{ github.sha }}
```

**Verify:**

```yaml
- name: Verify signature
  env:
    COSIGN_EXPERIMENTAL: "1"
  run: |
    cosign verify \
      --signature=ml-platform-api.sig \
      --certificate=ml-platform-api.crt \
      --certificate-identity-regexp="https://github.com/${{ github.repository }}/*" \
      --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
      ml-platform-api:${{ github.sha }}
```

**Key flags:** `--upload=false` (offline) | `--output-signature` (file) | `--certificate-identity-regexp` (validate workflow) | `--certificate-oidc-issuer` (validate GitHub)

## Local Testing

### Install Cosign

```bash
brew install cosign                    # macOS
cosign version                         # Verify
```

### Sign & Verify

**Keyless (requires OIDC):**

```bash
export COSIGN_EXPERIMENTAL=1
cosign sign ml-platform-api:local      # Opens browser for GitHub auth
cosign verify \
  --certificate-identity-regexp="https://github.com/wlevan3/ml-platform-engineering-practicum/*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ml-platform-api:local
```

**Key-based (local testing):**

```bash
cosign generate-key-pair                           # Generate test keys
cosign sign --key cosign.key ml-platform-api:local
cosign verify --key cosign.pub ml-platform-api:local
```

### Inspect Signatures

```bash
cosign tree ml-platform-api:local      # View signature details
```

## Kubernetes Verification

Admission controllers enforce signature verification before pod creation.

### Option 1: Sigstore Policy Controller (⭐ Recommended for Keyless)

**Install:**

```bash
helm repo add sigstore https://sigstore.github.io/helm-charts
helm install policy-controller sigstore/policy-controller --namespace sigstore-system --create-namespace
```

**Policy:**

```yaml
apiVersion: policy.sigstore.dev/v1beta1
kind: ClusterImagePolicy
metadata:
  name: ml-platform-images
spec:
  images:
    - glob: "**ml-platform-api**"
  authorities:
    - keyless:
        url: https://fulcio.sigstore.dev
        identities:
          - issuer: https://token.actions.githubusercontent.com
            subjectRegExp: "https://github.com/wlevan3/ml-platform-engineering-practicum/*"
```

**Testing:**

```bash
kubectl apply -f k8s/deployment.yaml    # Signed image → succeeds
kubectl run test --image=ml-platform-api:unsigned  # Unsigned → rejected
```

### Option 2: Kyverno (Flexible Policy Engine)

**Install:** `helm install kyverno kyverno/kyverno --namespace kyverno --create-namespace`

**Policy (keyless):**

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-ml-platform-images
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-signature
      match:
        any:
          - resources:
              kinds: [Pod]
      verifyImages:
        - imageReferences: ["ml-platform-api*"]
          attestors:
            - entries:
                - keyless:
                    subject: "https://github.com/wlevan3/ml-platform-engineering-practicum/*"
                    issuer: "https://token.actions.githubusercontent.com"
                    rekor:
                      url: https://rekor.sigstore.dev
```

### Comparison

| Feature | Sigstore Policy Controller | Kyverno |
|---------|----------------------------|---------|
| **Keyless signing** | Native ✅ | Supported ✅ |
| **Key-based signing** | Supported ✅ | Native ✅ |
| **Sigstore integration** | Deep ✅ | Basic ⚠️ |
| **Policy flexibility** | Image verification only | General-purpose ✅ |
| **Learning curve** | Low ✅ | Moderate ⚠️ |
| **Recommendation** | Best for keyless | Best for mixed policies |

**Recommendation:** Use **Sigstore Policy Controller** for this project (keyless signing with GitHub Actions OIDC).

## Security Best Practices

### Verification Commands (Production)

```bash
# Manual verification before deploy
cosign verify \
  --certificate-identity-regexp="https://github.com/wlevan3/ml-platform-engineering-practicum/*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  <image-ref>
```

### Best Practices Checklist

- [ ] **Admission controllers** - Enforce policy consistently, prevent human error
- [ ] **Registry access controls** - Private registries, least-privilege, audit logging
- [ ] **Transparency log** - Leverage Rekor for public auditability (`rekor-cli search --artifact <image>`)
- [ ] **Key rotation** - Keyless: automatic ✅ | Key-based: quarterly rotation ⚠️

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| `no matching signatures` | Not signed / Not pushed / Wrong identity | `cosign tree <image>` to check |
| `getting OIDC token` | Missing `id-token: write` | Add permission to workflow |
| `PUT registry.io/v2/...` | Auth missing / No write perms / No OCI support | `docker login <registry>` |

## Phase 2 Roadmap

- [ ] Push signed images to AWS ECR
- [ ] Deploy Sigstore Policy Controller to EKS
- [ ] Configure ClusterImagePolicy
- [ ] Integrate with ArgoCD/Flux
- [ ] Set up Rekor monitoring

## References

- [Cosign Documentation][cosign] - Official docs
- [Sigstore][sigstore] - Project homepage
- [Keyless Signing][keyless] - Keyless guide
- [Policy Controller][policy-controller] - Admission controller
- [Kyverno Image Verification][kyverno] - Kyverno policies
- [SLSA Framework][slsa] - Supply chain security

## Maintenance

**When to verify:** After pull | Before production | During incident response | Quarterly audits

**Monitoring:** CI success rate | Admission rejections | Rekor entries | Registry audit logs

[sigstore]: https://www.sigstore.dev/
[cosign]: https://docs.sigstore.dev/cosign/overview/
[keyless]: https://docs.sigstore.dev/cosign/keyless/
[policy-controller]: https://docs.sigstore.dev/policy-controller/overview/
[kyverno]: https://kyverno.io/docs/writing-policies/verify-images/
[slsa]: https://slsa.dev/
[issue-94]: https://github.com/wlevan3/ml-platform-engineering-practicum/issues/94
