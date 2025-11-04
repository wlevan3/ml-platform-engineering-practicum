# OPT-07: Add CORS Configuration (Conditional)

## Overview

**Priority:** TIER 3 - Conditional Optimization
**Estimated Time:** 5 minutes
**Impact:** Enables browser-based API calls, frontend integration
**ROI:** LOW (only if frontend planned)

## Problem Statement

Currently, the FastAPI application has no CORS (Cross-Origin Resource Sharing) middleware configured.

**Current state:**
- CORS not enabled
- Browser requests from different origins will be blocked
- No cross-origin API calls possible

**When is this needed?**
- Frontend application on different domain (e.g., `app.example.com` → `api.example.com`)
- Local development (e.g., `localhost:3000` → `localhost:8000`)
- Public API accessed from browser applications
- JavaScript-based testing tools

**When is this NOT needed?**
- API only accessed server-to-server
- All clients in same origin (e.g., mobile apps, backend services)
- No browser-based clients planned

## Decision Point

**Before implementing this optimization, ask:**

1. Will this API be accessed from web browsers?
2. Will frontend and API be on different domains/ports?
3. Is local frontend development planned (React, Vue, etc.)?

**If YES to any:** Implement this optimization.
**If NO to all:** Skip this optimization (can add later if needed).

## Solution

Add FastAPI CORS middleware with appropriate configuration for your use case.

## Implementation Steps

### Option A: Development-Friendly (Permissive)

**Use case:** Local development, experimentation, internal tools

### 1. Open app/main.py

```bash
# Open in your editor
vim app/main.py
# OR
code app/main.py
```

### 2. Add CORS import

**Location:** Line 8 (after existing imports)

**Add:**
```python
from fastapi.middleware.cors import CORSMiddleware
```

### 3. Configure CORS middleware

**Location:** After line 44 (after `app = FastAPI(...)`)

**Add:**
```python
# CORS configuration for local development
# WARNING: Do not use in production without restricting origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins (development only!)
    allow_credentials=True,
    allow_methods=["*"],  # Allow all HTTP methods
    allow_headers=["*"],  # Allow all headers
)
```

**Result:** Lines 45-52 contain CORS configuration.

### Option B: Production-Ready (Restrictive)

**Use case:** Production deployment with specific frontend domains

### 1-2. Same as Option A

### 3. Configure CORS middleware (restrictive)

**Location:** After line 44 (after `app = FastAPI(...)`)

**Add:**
```python
# CORS configuration for production
# Only allow specific origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://app.example.com",      # Production frontend
        "https://staging.example.com",  # Staging frontend
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],  # Only needed methods
    allow_headers=["Content-Type", "Authorization"],  # Only needed headers
)
```

### Option C: Environment-Based (Recommended)

**Use case:** Different CORS settings for dev/staging/prod

### 1-2. Same as Option A

### 3. Install pydantic-settings (if not already installed)

```bash
# Check if already installed
pip list | grep pydantic-settings

# If not installed
pip install pydantic-settings
```

### 4. Create settings configuration

**File:** `app/config.py` (new file)

**Create:**
```python
"""
Application configuration using environment variables.
"""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings loaded from environment."""

    # CORS configuration
    cors_origins: list[str] = ["http://localhost:3000", "http://localhost:8000"]
    cors_allow_credentials: bool = True
    cors_allow_methods: list[str] = ["*"]
    cors_allow_headers: list[str] = ["*"]

    # API configuration
    api_title: str = "Iris Classification API"
    api_version: str = "1.0.0"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


settings = Settings()
```

### 5. Update app/main.py to use settings

**Location:** After imports

**Add:**
```python
from app.config import settings
```

**After `app = FastAPI(...)`:**
```python
# CORS configuration from environment
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=settings.cors_allow_credentials,
    allow_methods=settings.cors_allow_methods,
    allow_headers=settings.cors_allow_headers,
)
```

### 6. Create .env file (local development)

**File:** `.env` (root directory)

**Create:**
```bash
# CORS Configuration
CORS_ORIGINS=["http://localhost:3000","http://localhost:8000"]
CORS_ALLOW_CREDENTIALS=true
CORS_ALLOW_METHODS=["*"]
CORS_ALLOW_HEADERS=["*"]
```

### 7. Update .env.example (template)

**File:** `.env.example` (new file)

**Create:**
```bash
# CORS Configuration
# Comma-separated list of allowed origins
CORS_ORIGINS=["http://localhost:3000"]
CORS_ALLOW_CREDENTIALS=true
CORS_ALLOW_METHODS=["GET","POST","OPTIONS"]
CORS_ALLOW_HEADERS=["Content-Type","Authorization"]
```

### 8. Update .gitignore

**Ensure `.env` is ignored:**
```bash
# Check if .env is already in .gitignore
grep "^\.env$" .gitignore

# If not found, add it
echo ".env" >> .gitignore
```

### 9. Update Dockerfile for production

**File:** `Dockerfile`

**Add environment variables (optional, can also set in k8s):**
```dockerfile
# CORS configuration (override at runtime)
ENV CORS_ORIGINS='["https://app.example.com"]'
ENV CORS_ALLOW_CREDENTIALS=true
ENV CORS_ALLOW_METHODS='["GET","POST","OPTIONS"]'
ENV CORS_ALLOW_HEADERS='["Content-Type","Authorization"]'
```

## Verification Steps

### 1. Run linting

```bash
# Format code
black app/

# Check with ruff
ruff check app/

# Type checking
mypy app/
```

### 2. Run tests

```bash
# Ensure all tests pass
pytest -v
```

### 3. Test locally without frontend

```bash
# Start API
uvicorn app.main:app --reload

# In another terminal, test CORS headers
curl -v -X OPTIONS http://localhost:8000/predict \
  -H "Origin: http://localhost:3000" \
  -H "Access-Control-Request-Method: POST"

# Expected response headers:
# access-control-allow-origin: http://localhost:3000
# access-control-allow-credentials: true
# access-control-allow-methods: POST
```

### 4. Test with browser (if frontend exists)

```javascript
// In browser console (on http://localhost:3000)
fetch('http://localhost:8000/health/live')
  .then(r => r.json())
  .then(data => console.log('CORS working:', data))
  .catch(err => console.error('CORS error:', err));

// Should log: CORS working: {status: "alive"}
```

### 5. Check OpenAPI docs

```bash
# Open http://localhost:8000/docs
# Try "Try it out" feature - should work
```

## Testing Checklist

- [ ] CORS middleware imported
- [ ] CORS middleware configured in app
- [ ] CORS origins appropriate for environment
- [ ] All tests pass (`pytest`)
- [ ] Code formatted (`black`)
- [ ] No linting errors (`ruff check`)
- [ ] OPTIONS requests return CORS headers
- [ ] Browser-based requests work (if frontend exists)
- [ ] `.env` file added to `.gitignore`

## Expected Behavior

### Without CORS (current state)

**Browser Console Error:**
```
Access to fetch at 'http://localhost:8000/predict' from origin 'http://localhost:3000'
has been blocked by CORS policy: No 'Access-Control-Allow-Origin' header is present.
```

### With CORS (after implementation)

**Response Headers:**
```
HTTP/1.1 200 OK
access-control-allow-origin: http://localhost:3000
access-control-allow-credentials: true
access-control-allow-methods: GET, POST, OPTIONS
access-control-allow-headers: Content-Type, Authorization
```

**Browser Console:**
```
✓ CORS working: {status: "alive"}
```

## Git Workflow

### Branch name

```bash
git checkout -b feat/add-cors-configuration
```

### Commit message

**For Option A/B (simple):**
```
feat(api): add CORS middleware for cross-origin requests

Add FastAPI CORS middleware to enable browser-based API calls
from different origins.

Configuration:
- Allow origins: [configurable list]
- Allow credentials: true
- Allow methods: [configurable list]
- Allow headers: [configurable list]

Benefits:
- Enables frontend integration (React, Vue, etc.)
- Supports local development (localhost:3000 → localhost:8000)
- Production-ready with origin restrictions

Related: OPT-07 (optimization initiative)
```

**For Option C (environment-based):**
```
feat(api): add environment-based CORS configuration

Add FastAPI CORS middleware with environment-based configuration
for flexible cross-origin request handling across environments.

Changes:
- Add app/config.py for centralized settings
- Add CORS middleware with env-based configuration
- Add .env.example template
- Update .gitignore to exclude .env
- Update Dockerfile with CORS env vars

Configuration sources:
- Local: .env file
- Docker: ENV variables in Dockerfile
- Kubernetes: ConfigMap/environment variables

Benefits:
- Environment-specific CORS policies
- Development: permissive (all origins)
- Production: restrictive (specific domains)
- No code changes between environments

Related: OPT-07 (optimization initiative)
```

### Push and create PR

```bash
# For simple implementation
git add app/main.py
git commit -m "feat(api): add CORS middleware for cross-origin requests"

# For environment-based implementation
git add app/main.py app/config.py .env.example .gitignore Dockerfile
git commit -m "feat(api): add environment-based CORS configuration"

git push -u origin feat/add-cors-configuration

# Create PR
gh pr create --title "feat: Add CORS configuration" \
  --body "## Changes
- ✅ Add CORS middleware to FastAPI app
- ✅ Configure allowed origins, methods, headers
- ✅ Environment-based configuration (Option C only)
- ✅ Production-ready security defaults

## Problem
Currently, the API blocks cross-origin requests from browsers.
This prevents:
- Frontend development (React, Vue, etc.)
- Browser-based API testing
- Public API access from web apps

## Solution
Add FastAPI CORS middleware with configurable policies.

## Configuration

### Development
\`\`\`
CORS_ORIGINS=[\"http://localhost:3000\"]
\`\`\`

### Production
\`\`\`
CORS_ORIGINS=[\"https://app.example.com\"]
\`\`\`

## Security Considerations
- ⚠️ **Never use \`allow_origins=[\"*\"]\` in production**
- ✅ Specify exact origins (no wildcards)
- ✅ Restrict methods to only those needed
- ✅ Restrict headers to only those needed
- ✅ Use environment variables for configuration

## Testing
- [x] All tests pass (\`pytest\`)
- [x] Code formatted (\`black\`)
- [x] CORS headers present in OPTIONS requests
- [ ] Browser-based requests work (will test with frontend)

## Related
Part of optimization initiative OPT-07

## Note
This PR is marked as **conditional**. Merge only if:
- Frontend development is planned
- Cross-origin API access is required
- Browser-based clients will be used

If not needed now, this can be implemented later when requirements change."
```

## Rollback Plan

If CORS causes issues:

```bash
git revert <commit-sha>
```

Or manually remove:
1. CORS import from `app/main.py`
2. `app.add_middleware(CORSMiddleware, ...)` block
3. `app/config.py` (if created)

## Security Considerations

### ⚠️ Common Pitfalls

**DON'T DO THIS in production:**
```python
# ❌ BAD: Allows any origin
allow_origins=["*"]

# ❌ BAD: Allows credentials with wildcard (security risk)
allow_origins=["*"],
allow_credentials=True  # This combination is dangerous!
```

**DO THIS instead:**
```python
# ✅ GOOD: Specific origins only
allow_origins=["https://app.example.com", "https://staging.example.com"]

# ✅ GOOD: No credentials if using wildcard
allow_origins=["*"],
allow_credentials=False  # Safer (but still not ideal for prod)
```

### Production Checklist

- [ ] Origins list is explicit (no wildcards)
- [ ] Origins use HTTPS (not HTTP)
- [ ] Methods are restricted (not `["*"]`)
- [ ] Headers are restricted (not `["*"]`)
- [ ] `.env` file is in `.gitignore`
- [ ] Environment variables documented in `.env.example`

### OWASP Recommendations

1. **Whitelist, don't blacklist:** Explicitly allow origins, don't try to block bad ones
2. **HTTPS only in production:** Enforce secure connections
3. **Minimal permissions:** Only allow methods/headers actually needed
4. **Credentials carefully:** Only enable if absolutely necessary
5. **Validate origins:** Use exact matches, not regex patterns

## Additional Notes

### Performance Impact

CORS middleware adds minimal overhead:
- Preflight requests (OPTIONS): ~1-2ms
- Regular requests with CORS headers: <0.1ms

**Optimization:** Cache preflight responses:
```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://app.example.com"],
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
    max_age=3600,  # Cache preflight for 1 hour
)
```

### CORS vs API Gateway

**If using AWS API Gateway or similar:**
- Configure CORS in API Gateway, not in application
- Removes CORS logic from application code
- Centralized CORS management
- Better for microservices architecture

**If deploying directly to Kubernetes:**
- Configure CORS in application (this PR)
- Or configure in Ingress (nginx annotations)
- Application-level gives more control

### Future Enhancement: Dynamic Origins

For SaaS with custom domains:
```python
# app/middleware.py
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

class DynamicCORSMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        origin = request.headers.get("origin")

        # Check if origin is allowed (database lookup, pattern matching, etc.)
        if is_allowed_origin(origin):
            response = await call_next(request)
            response.headers["Access-Control-Allow-Origin"] = origin
            return response

        return await call_next(request)
```

## References

- [FastAPI CORS Documentation](https://fastapi.tiangolo.com/tutorial/cors/)
- [MDN CORS Documentation](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS)
- [OWASP CORS Security Cheatsheet](https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html)
- [Starlette CORS Middleware](https://www.starlette.io/middleware/#corsmiddleware)
- Project: ml-platform-engineering-practicum
- Issue: Optimization Initiative (OPT-07)
