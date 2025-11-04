# OPT-06: Add API Request Timeout Configuration

## Overview

**Priority:** TIER 3 - Polish Optimization
**Estimated Time:** 2 minutes
**Impact:** Production resilience, prevents hung connections
**ROI:** MEDIUM

## Problem Statement

The Dockerfile CMD starts uvicorn without timeout configuration:

```dockerfile
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Issues:**
- No keep-alive timeout specified
- HTTP connections can hang indefinitely
- No timeout for slow clients
- Potential resource exhaustion in production

**Default behavior:**
- Uvicorn uses default timeout of 5 seconds for keep-alive
- No explicit configuration visible in code

## Solution

Add explicit timeout configuration to uvicorn command for production-grade resilience and resource management.

## Implementation Steps

### 1. Open the Dockerfile

```bash
# Open in your editor
vim Dockerfile
# OR
code Dockerfile
```

### 2. Locate the CMD instruction

**Current location:** Line 68

**Current CMD:**
```dockerfile
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### 3. Update with timeout configuration

**Replace line 68 with:**

```dockerfile
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--timeout-keep-alive", "30"]
```

### 4. Complete Dockerfile section

**Result:** Lines 60-68 should look like this:

```dockerfile
# Expose port
EXPOSE 8000

# Health check - uses liveness endpoint (checks if process is alive)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health/live', timeout=5)" || exit 1

# Run the application
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--timeout-keep-alive", "30"]
```

## Configuration Explanation

### --timeout-keep-alive 30

**What it does:**
- Sets the timeout for HTTP keep-alive connections to 30 seconds
- After 30 seconds of inactivity, the connection is closed
- Prevents idle connections from consuming resources

**Why 30 seconds?**
- Balances between connection reuse and resource management
- Common production value (AWS ALB default: 60s, we use 30s to close before ALB)
- Kubernetes best practice: shorter than ingress timeout

**Alternative values:**
- 5s: Aggressive (default, may close too quickly)
- 15s: Conservative (good for high-traffic APIs)
- 30s: Balanced (recommended for most use cases)
- 60s: Lenient (may hold resources longer)

### Other Timeout Options (Optional)

You can add additional timeout configurations:

```dockerfile
CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--timeout-keep-alive", "30", \
     "--timeout-graceful-shutdown", "10"]
```

**Additional options:**
- `--timeout-graceful-shutdown <seconds>`: Graceful shutdown timeout (default: 10s)
- `--limit-max-requests <int>`: Restart workers after N requests (memory leak protection)
- `--limit-concurrency <int>`: Max concurrent connections

**Recommendation:** Start with just `--timeout-keep-alive 30`, add others if needed.

## Verification Steps

### 1. Build Docker image

```bash
docker build -t ml-platform-api:timeout-test .
```

### 2. Run container

```bash
docker run -d -p 8000:8000 --name api-test ml-platform-api:timeout-test
```

### 3. Check uvicorn startup logs

```bash
docker logs api-test

# Expected output:
# INFO:     Started server process [1]
# INFO:     Waiting for application startup.
# INFO:     Application startup complete.
# INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

### 4. Verify timeout configuration

```bash
# Check the process command
docker exec api-test ps aux | grep uvicorn

# Should show: uvicorn app.main:app --host 0.0.0.0 --port 8000 --timeout-keep-alive 30
```

### 5. Test keep-alive behavior

```bash
# Open connection and keep idle for 35 seconds
# Connection should close after 30 seconds of inactivity

curl -v --no-keepalive http://localhost:8000/health/live

# Check connection header
# Should show: Connection: close (after timeout)
```

### 6. Clean up

```bash
docker stop api-test
docker rm api-test
```

## Testing Checklist

- [ ] Dockerfile updated with `--timeout-keep-alive 30`
- [ ] Docker image builds successfully
- [ ] Container starts without errors
- [ ] API endpoints respond correctly
- [ ] Uvicorn logs show proper startup
- [ ] Process command includes timeout flag
- [ ] No regression in existing tests (`pytest`)

## Expected Behavior

### Before (no explicit timeout)

```bash
docker logs api-container
# INFO: Uvicorn running on http://0.0.0.0:8000
# (uses default timeout: 5s, not visible in logs)
```

### After (explicit timeout)

```bash
docker logs api-container
# INFO: Uvicorn running on http://0.0.0.0:8000
# (timeout-keep-alive: 30s configured, visible in process args)
```

### Connection Behavior

**Scenario:** Client connects, sends request, idles

**Before (default 5s):**
```
Client → Server: GET /predict
Server → Client: 200 OK
[5 seconds idle]
Server: Connection closed
```

**After (configured 30s):**
```
Client → Server: GET /predict
Server → Client: 200 OK
[30 seconds idle]
Server: Connection closed
```

**Benefit:** More time for legitimate keep-alive reuse, but still closes idle connections.

## Git Workflow

### Branch name

```bash
git checkout -b infra/add-api-timeout-configuration
```

### Commit message

```
infra(docker): add uvicorn timeout configuration

Add explicit keep-alive timeout configuration (30s) to uvicorn command
in Dockerfile for production-grade resource management.

Configuration:
--timeout-keep-alive 30

Benefits:
- Explicit timeout visible in configuration
- Prevents indefinitely hung connections
- Better resource management in production
- Aligns with Kubernetes/AWS best practices
- Closes connections before ingress timeout

Rationale:
- 30s balances connection reuse and resource cleanup
- Shorter than typical load balancer timeouts (60s)
- Production-ready configuration

Related: OPT-06 (optimization initiative)
```

### Push and create PR

```bash
git add Dockerfile
git commit -m "infra(docker): add uvicorn timeout configuration"
git push -u origin infra/add-api-timeout-configuration

# Create PR
gh pr create --title "infra: Add uvicorn timeout configuration" \
  --body "## Changes
- Add \`--timeout-keep-alive 30\` to uvicorn command in Dockerfile

## Problem
Currently, uvicorn uses default timeout settings (5s) which are:
- Not explicitly configured (implicit)
- Not visible in configuration
- May be too aggressive for some use cases

## Solution
Add explicit keep-alive timeout of 30 seconds:
\`\`\`dockerfile
CMD [\"uvicorn\", \"app.main:app\", \"--host\", \"0.0.0.0\", \"--port\", \"8000\", \"--timeout-keep-alive\", \"30\"]
\`\`\`

## Benefits
- 🔒 Explicit configuration (no surprises)
- 🛡️ Prevents hung connections
- ⚖️ Balanced timeout (connection reuse vs resource cleanup)
- 🌐 Aligns with load balancer timeouts (AWS ALB: 60s)
- ☸️ Kubernetes best practice (shorter than ingress timeout)

## Rationale: Why 30 seconds?
- **Too short (5s):** Closes connections aggressively, reduces keep-alive benefits
- **Too long (60s+):** Holds resources longer, may accumulate idle connections
- **30s (sweet spot):** Balances connection reuse and resource management
- Closes connections before typical load balancer timeouts (60s)

## Testing
- [x] Docker image builds successfully
- [x] Container starts without errors
- [x] API endpoints respond correctly
- [x] Timeout flag visible in process command
- [ ] CI passes (will verify)

## Related
Part of optimization initiative OPT-06"
```

## Rollback Plan

If timeout causes issues:

```bash
git revert <commit-sha>
```

Or manually revert Dockerfile line 68:
```dockerfile
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

## Production Considerations

### Load Balancer Timeout Alignment

**AWS Application Load Balancer:**
- Default idle timeout: 60 seconds
- Recommendation: Set uvicorn timeout < ALB timeout (e.g., 30s < 60s)
- Reason: Close connection before load balancer does

**Kubernetes Ingress:**
- Default timeouts vary by controller (nginx: 60s, traefik: 180s)
- Recommendation: Set uvicorn timeout < ingress timeout

### Monitoring Recommendations

After deployment, monitor:
- Connection pool statistics
- Request latency percentiles (p50, p95, p99)
- Connection timeout errors
- Connection churn rate

**Metrics to watch:**
```
# Prometheus/Grafana queries
uvicorn_requests_total
uvicorn_requests_duration_seconds
uvicorn_connection_count
```

### Tuning Guide

**If you see:**
- High connection churn → Increase timeout (e.g., 45s)
- Resource exhaustion → Decrease timeout (e.g., 15s)
- Many timeout errors → Increase timeout or investigate slow clients

**Typical values by environment:**
- Development: 30s (balanced)
- Staging: 30s (production-like)
- Production (high traffic): 15-30s (more aggressive)
- Production (low traffic): 30-60s (more lenient)

## Additional Timeout Configurations

### For Future Enhancement

Once this optimization is merged, consider adding:

#### 1. Graceful Shutdown Timeout

```dockerfile
CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--timeout-keep-alive", "30", \
     "--timeout-graceful-shutdown", "10"]
```

**Purpose:** Time to finish in-flight requests during shutdown

#### 2. Worker Restart (Memory Leak Protection)

```dockerfile
CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--timeout-keep-alive", "30", \
     "--limit-max-requests", "10000", \
     "--limit-max-requests-jitter", "1000"]
```

**Purpose:** Restart workers after N requests (prevents memory leaks)

#### 3. Concurrency Limits

```dockerfile
CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--timeout-keep-alive", "30", \
     "--limit-concurrency", "100"]
```

**Purpose:** Max concurrent connections (backpressure)

**Recommendation:** Add these incrementally in future PRs based on production needs.

## References

- [Uvicorn Settings Documentation](https://www.uvicorn.org/settings/)
- [Uvicorn Deployment Guide](https://www.uvicorn.org/deployment/)
- [AWS ALB Idle Timeout](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html#connection-idle-timeout)
- [Kubernetes Best Practices: Timeouts](https://kubernetes.io/docs/concepts/configuration/overview/#timeout-configuration)
- Project: ml-platform-engineering-practicum
- Issue: Optimization Initiative (OPT-06)
