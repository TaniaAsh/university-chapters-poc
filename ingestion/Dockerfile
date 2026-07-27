# Matches your local Python version (3.14) to avoid any "works on my
# machine" surprises between local test runs and the containerised job.
FROM python:3.14-slim

# Cloud Run Jobs execute as a one-shot batch process, not a long-running
# server, so we don't need to expose a port or run a web framework.
WORKDIR /app

# Copy and install dependencies first, in their own layer, so Docker can
# cache this step and skip reinstalling packages every time only ingest.py
# changes.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Now copy the actual application code.
COPY ingest.py .

# Run as a non-root user -- least privilege inside the container too,
# matching the HLD's security posture (section 8).
RUN useradd --create-home --shell /bin/bash appuser \
    && chown -R appuser:appuser /app
USER appuser

# No CMD arguments needed -- all configuration comes from environment
# variables injected by the Cloud Run Job definition
# (see terraform/cloud_run_jobs.tf).
ENTRYPOINT ["python", "ingest.py"]