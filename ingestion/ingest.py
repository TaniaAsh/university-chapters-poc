"""
ingest.py

Pulls California, Oregon and Washington chapter data from the public
Ducks Unlimited University Chapters API, lands it in Cloud Storage and
BigQuery raw, and (optionally) triggers the downstream dbt transformation
job -- mirroring the HLD's ingestion Cloud Run Job.
"""

import json
import logging
import os
import uuid
from datetime import datetime, timezone

import requests
from google.cloud import bigquery, storage
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type

# --------------------------------------------------------------------------
# Configuration -- read from environment so the same image works locally,
# in Docker, and as the real Cloud Run Job (see terraform/cloud_run_jobs.tf).
# --------------------------------------------------------------------------
API_URL = (
    "https://services2.arcgis.com/5I7u4SJE1vUr79JC/arcgis/rest/services/"
    "UniversityChapters_Public/FeatureServer/0/query"
)
TARGET_STATES = ["CA", "OR", "WA"]

BQ_PROJECT = os.environ.get("BQ_PROJECT", "university-chapters-poc")
BQ_DATASET_RAW = os.environ.get("BQ_DATASET_RAW", "university_ch_raw")
BQ_TABLE_RAW = "chapters_raw"
BUCKET_NAME = os.environ.get("BUCKET_NAME", "university-chapters-poc-landing")
DBT_JOB_NAME = os.environ.get("DBT_JOB_NAME")  # e.g. "dbt-transform-job"
REGION = os.environ.get("REGION", "europe-west2")
LOCAL_DATA_DIR = "data/raw"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
log = logging.getLogger("ingestion")


class IngestionError(Exception):
    """Raised when the ingestion run cannot safely continue."""


@retry(
    reraise=True,
    stop=stop_after_attempt(5),
    wait=wait_exponential(multiplier=2, min=2, max=30),
    retry=retry_if_exception_type((requests.RequestException, IngestionError)),
)
def fetch_page(offset: int, page_size: int = 1000) -> dict:
    """Fetch one page of chapters for the target states, with retry/backoff
    on transient network or server errors -- mirrors the resilience
    requirement in the HLD architecture overview."""
    where_clause = "State IN ({})".format(
        ",".join(f"'{s}'" for s in TARGET_STATES)
    )
    params = {
        "where": where_clause,
        "outFields": "*",
        "outSR": 4326,
        "f": "json",
        "resultOffset": offset,
        "resultRecordCount": page_size,
    }
    response = requests.get(API_URL, params=params, timeout=30)
    response.raise_for_status()
    payload = response.json()

    if "error" in payload:
        # ArcGIS returns HTTP 200 with an "error" body on bad requests --
        # requests.raise_for_status() won't catch this, so we do.
        raise IngestionError(f"DU API returned an error payload: {payload['error']}")

    return payload


def fetch_all_chapters() -> list[dict]:
    """Page through the API until every matching record has been retrieved."""
    all_features = []
    offset = 0
    page_size = 1000

    while True:
        log.info("Fetching chapters (offset=%s, page_size=%s)", offset, page_size)
        payload = fetch_page(offset, page_size)
        features = payload.get("features", [])
        all_features.extend(features)

        if not payload.get("exceededTransferLimit"):
            break
        offset += page_size

    log.info("Fetched %s raw features from the DU API", len(all_features))
    return all_features


def transform(features: list[dict], run_id: str, ingestion_ts: datetime) -> list[dict]:
    """Flatten ArcGIS features into the raw schema from the HLD (section 4.2):
    chapter_id, chapter_name, city, state, latitude, longitude, plus
    ingestion metadata for audit and replay."""
    records = []
    skipped = 0

    for feature in features:
        attrs = feature.get("attributes", {})
        geometry = feature.get("geometry")

        chapter_id = attrs.get("ChapterID")
        state = attrs.get("State")

        if not chapter_id or not geometry:
            # Sanity check, not a full validation layer -- dbt tests own
            # that job downstream. This just stops obviously broken rows
            # from ever reaching BigQuery.
            skipped += 1
            continue

        records.append({
            "chapter_id": chapter_id,
            "chapter_name": attrs.get("University_Chapter"),
            "city": attrs.get("City"),
            "state": state,
            "latitude": geometry.get("y"),
            "longitude": geometry.get("x"),
            "source_object_id": attrs.get("OBJECTID"),
            "ingestion_timestamp": ingestion_ts.isoformat(),
            "ingestion_date": ingestion_ts.date().isoformat(),
            "run_id": run_id,
        })

    if skipped:
        log.warning("Skipped %s features with missing chapter_id or geometry", skipped)

    # Simple sanity check (HLD section 8: a row-count floor that flags a
    # run whose chapter count drops to zero). A full anomaly-detection
    # system would compare against history; for this POC, refusing to
    # publish an empty load is the honest minimum.
    if len(records) == 0:
        raise IngestionError(
            "Zero valid chapters after filtering to CA/OR/WA -- refusing to "
            "publish an empty raw load."
        )

    log.info("Transformed %s valid chapter records", len(records))
    return records


def write_ndjson_local(records: list[dict], run_id: str) -> str:
    """Write NDJSON to a local file first, so a failed upload never loses
    data (mirrors the HLD's Cloud Storage landing pattern)."""
    os.makedirs(LOCAL_DATA_DIR, exist_ok=True)
    path = os.path.join(LOCAL_DATA_DIR, f"chapters_{run_id}.ndjson")

    with open(path, "w", encoding="utf-8") as f:
        for record in records:
            f.write(json.dumps(record) + "\n")

    log.info("Wrote %s records to %s", len(records), path)
    return path


def upload_to_gcs(local_path: str, run_id: str) -> str:
    """Upload the NDJSON file to the landing bucket -- the audit trail
    described in ADR-003."""
    client = storage.Client(project=BQ_PROJECT)
    bucket = client.bucket(BUCKET_NAME)
    blob_name = f"chapters_raw/run_id={run_id}/records.ndjson"
    blob = bucket.blob(blob_name)
    blob.upload_from_filename(local_path)

    gcs_uri = f"gs://{BUCKET_NAME}/{blob_name}"
    log.info("Uploaded landing file to %s", gcs_uri)
    return gcs_uri


def load_to_bigquery(records: list[dict]) -> None:
    """Append the batch into the raw table. Raw is append-only by design
    (HLD section 4.2) -- each run adds a new ingestion_date/run_id slice
    rather than overwriting."""
    client = bigquery.Client(project=BQ_PROJECT)
    table_ref = f"{BQ_PROJECT}.{BQ_DATASET_RAW}.{BQ_TABLE_RAW}"

    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
        autodetect=True,
        time_partitioning=bigquery.TimePartitioning(field="ingestion_date"),
    )

    load_job = client.load_table_from_json(records, table_ref, job_config=job_config)
    load_job.result()  # blocks until the load finishes or raises

    log.info(
        "Loaded %s rows into %s (job id: %s)",
        load_job.output_rows, table_ref, load_job.job_id,
    )


def trigger_dbt_job() -> None:
    """Call the Cloud Run Admin API to start the dbt transformation job --
    the 'Trigger dbt job after successful RAW load' arrow in the HLD
    architecture diagram. Skipped automatically if DBT_JOB_NAME isn't set
    (e.g. during a purely local test run)."""
    if not DBT_JOB_NAME:
        log.info("DBT_JOB_NAME not set -- skipping dbt trigger (local test mode)")
        return

    import google.auth
    from google.auth.transport.requests import AuthorizedSession

    credentials, _ = google.auth.default()
    session = AuthorizedSession(credentials)

    url = (
        f"https://run.googleapis.com/v2/projects/{BQ_PROJECT}/locations/"
        f"{REGION}/jobs/{DBT_JOB_NAME}:run"
    )
    response = session.post(url)
    response.raise_for_status()
    log.info("Triggered dbt job: %s", DBT_JOB_NAME)


def main() -> None:
    run_id = str(uuid.uuid4())
    ingestion_ts = datetime.now(timezone.utc)

    log.info("Starting ingestion run %s", run_id)

    features = fetch_all_chapters()
    records = transform(features, run_id, ingestion_ts)

    local_path = write_ndjson_local(records, run_id)
    upload_to_gcs(local_path, run_id)
    load_to_bigquery(records)
    trigger_dbt_job()

    log.info("Ingestion run %s completed successfully", run_id)


if __name__ == "__main__":
    main()