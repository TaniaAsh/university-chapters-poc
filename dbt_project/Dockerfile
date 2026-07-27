FROM python:3.12-slim

# Pinned to exactly what we already proved works interactively in Cloud
# Shell (dbt-core 1.12.0 / dbt-bigquery 1.12.0) -- no surprises between
# "it worked when I tested it" and "it works in the real job".
RUN pip install --no-cache-dir dbt-core==1.12.0 dbt-bigquery==1.12.0

WORKDIR /app

# The dbt project itself (models, macros, dbt_project.yml).
COPY dbt_project.yml .
COPY macros ./macros
COPY models ./models

# profiles.yml lives outside the dbt project by dbt convention, but inside
# the image we point DBT_PROFILES_DIR straight at it -- it holds no
# secrets, just project/dataset/location read from env vars at runtime.
COPY profiles.yml /home/appuser_profiles/profiles.yml

RUN useradd --create-home --shell /bin/bash appuser \
    && mkdir -p /home/appuser/.dbt \
    && cp /home/appuser_profiles/profiles.yml /home/appuser/.dbt/profiles.yml \
    && chown -R appuser:appuser /home/appuser/.dbt /app

USER appuser
ENV DBT_PROFILES_DIR=/home/appuser/.dbt

# `dbt build` = run + test in one command -- matches the HLD's "Cloud Run
# – dbt Transformation Job: runs dbt models, builds the curated layer,
# executes data quality tests and publishes only successful data."
ENTRYPOINT ["dbt", "build"]