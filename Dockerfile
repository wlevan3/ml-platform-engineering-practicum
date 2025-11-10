# ==========================================
# Stage 1: Builder - Install dependencies
# ==========================================
FROM python:3.14-slim@sha256:9813eecff3a08a6ac88aea5b43663c82a931fd9557f6aceaa847f0d8ce738978 AS builder

# Set working directory
WORKDIR /app

# Install system dependencies needed for building Python packages
# Note: gcc may be needed for some Python packages, but g++ is typically unnecessary
# as most ML packages (numpy, scikit-learn) ship pre-built wheels
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Create virtual environment
RUN python -m venv /opt/venv

# Activate virtual environment
ENV PATH="/opt/venv/bin:$PATH"

# Copy requirements and install dependencies in the venv
COPY requirements.txt .
# FIX CVE-2025-8869: Upgrade pip to 25.3 (fixes symlink extraction vulnerability)
RUN pip install --no-cache-dir --upgrade pip==25.3 && \
    pip install --no-cache-dir -r requirements.txt

# ==========================================
# Stage 2: Runtime - Minimal production image
# ==========================================
FROM python:3.14-slim@sha256:9813eecff3a08a6ac88aea5b43663c82a931fd9557f6aceaa847f0d8ce738978 AS runtime

# FIX CVE-2025-8869: Upgrade system pip to 25.3
# Even though venv pip (upgraded in builder stage) is used at runtime,
# Trivy scans all files including unused system pip, so we upgrade both
RUN pip install --no-cache-dir --upgrade pip==25.3

# Set working directory
WORKDIR /app

# Copy virtual environment from builder stage
COPY --from=builder /opt/venv /opt/venv

# Set environment to use the virtual environment
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

# Copy application code and model artifacts
COPY services/api/ ./services/api/

# Create non-root user for security (UID > 10000)
RUN useradd -m -u 10001 -s /bin/bash appuser && \
    mkdir -p /home/appuser/.cache && \
    chown -R appuser:appuser /app /home/appuser/.cache

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 8000

# Health check - uses liveness endpoint (checks if process is alive)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health/live', timeout=5)" || exit 1

# Run the application
CMD ["uvicorn", "services.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
