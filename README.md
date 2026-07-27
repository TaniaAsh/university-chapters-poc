# University Chapters Data Product — POC

A working, end-to-end proof of concept for the University Chapters data
product described in the accompanying HLD (`University_Chapters_HLD_Runbook.docx`).
Every component below is deployed and has been verified running for real
on GCP — not just designed on paper.

## What this proves

```
Ducks Unlimited API
  → ingestion-job (Cloud Run)          -- calls the API, writes to GCS + BigQuery raw
    → dbt-transform-job (Cloud Run)    -- triggered automatically by ingestion-job
      → staging → curated → published -- 17 dbt tests, all passing
        → university_chapters_v1      -- the stable, versioned consumer interface
          → Streamlit dashboard        -- reads the published view
```

Cloud Scheduler triggers this daily at 05:00 UTC. The full chain has also
been run manually and confirmed working end to end (see "Verified runs" below).

## Repo structure

```
UC_DP/
├── terraform/        # all GCP infrastructure (see terraform/README.md for apply order)
├── ingestion/         # Python ingestion script + Dockerfile
├── dbt_project/       # staging/curated/published models, tests, Dockerfile
├── dashboard/         # Streamlit app reading the published view
└── README.md          # this file
```

## Real deployed resources (project: `university-chapters-poc`, region: `europe-west2`)

| Component | Resource |
|---|---|
| Raw / curated / published datasets | `university_ch_raw`, `university_ch_curated`, `university_ch_published` |
| Landing bucket | `gs://university-chapters-poc-landing` (90-day lifecycle) |
| Ingestion job | Cloud Run Job `ingestion-job` |
| dbt job | Cloud Run Job `dbt-transform-job` |
| Daily trigger | Cloud Scheduler `daily-ingestion-trigger` (05:00 UTC) |
| Images | Artifact Registry `europe-west2-docker.pkg.dev/university-chapters-poc/university-chapters/{ingestion,dbt}:latest` |
| Cost guardrail | Billing budget alert, £5/month, plus a project-level BigQuery query quota capped at 1 TiB/day |

## How to reproduce

1. `terraform/` — provision everything (see `terraform/README.md` for the exact apply order — infra first with placeholder images, then real images, then a second apply).
2. Build and push both images via Cloud Build (no local Docker required):
   ```
   cd ingestion && gcloud builds submit --tag europe-west2-docker.pkg.dev/<project>/university-chapters/ingestion:latest .
   cd dbt_project && gcloud builds submit --tag europe-west2-docker.pkg.dev/<project>/university-chapters/dbt:latest .
   ```
3. Update `terraform.tfvars` with the real image tags, `terraform apply` again.
4. Trigger manually to verify: `gcloud run jobs execute ingestion-job --region europe-west2` (this in turn triggers the dbt job automatically).

## Verified runs

- **Ingestion (Cloud Run)**: run `738218d4...`, 2026-07-27 15:59 UTC — 3 chapters fetched, written to GCS, loaded to `chapters_raw`, dbt job triggered successfully.
- **dbt (Cloud Run)**: run following the above trigger, 2026-07-27 16:09 UTC — `Completed successfully`, `PASS=20, ERROR=0` (3 models + 17 tests).
- **Dashboard**: verified against the live `university_chapters_v1` view — table, map, and per-state chart all rendering correctly.

## Real data, as discovered

A few things only became visible once this ran against the live API, worth
knowing before reading the numbers:

- **The dataset is small.** Filtering to CA/OR/WA currently returns exactly
  3 chapters, all in California — Oregon and Washington have no active DU
  university chapters at the time of writing. This is a fact about the
  source data, not a bug in the filter.
- **Source `ChapterID` formatting is inconsistent** (`"FL-0110"` vs
  `"GA0147"` vs blank suffixes like `"PA-"`). This is exactly the kind of
  issue the dbt uniqueness/format tests exist to catch.
- **`dbt-bigquery==1.12.0` pulls in a lot more than a SQL-only project
  needs** (`google-cloud-aiplatform`, `pandas`, `jupyter-core`, etc.) —
  this version bundles BigQuery DataFrames support for Python models, which
  this project doesn't use, since all three models are plain SQL. A leaner
  pin is possible; it wasn't necessary at this scale, and matching the
  exact version already verified in development mattered more than image size.

## Local development notes

- `ingestion/` was developed and tested locally (Python 3.14) before being
  containerised — the container uses the same code, run as a non-root
  user inside Cloud Run.
- `dbt_project/` and `dashboard/` were developed and tested via **Cloud
  Shell** (Python 3.12), not the local machine — `dbt-core` does not yet
  support Python 3.14, and keeping `streamlit` in a separate venv from
  `dbt` avoided a `protobuf` version conflict between the two.
- The dashboard is currently run ad hoc via `streamlit run` in Cloud Shell
  with Web Preview — it is not (yet) deployed as a standing service. It
  reads live data from `university_chapters_v1` regardless of how it's run.

## Cost

Billing is enabled on this project (Cloud Run, Scheduler and Artifact
Registry all require it — there's no zero-billing sandbox equivalent for
those services, unlike BigQuery). Actual spend at this data volume is
negligible; guardrails in place: a £5 budget alert (50/90/100% thresholds)
and a hard 1 TiB/day BigQuery query quota, so the worst case is a failed
query, not a surprise bill.

## What's intentionally not included

- **`docker-compose.yml` for fully offline local execution** — optional
  per the assessment (Task 6); the real Cloud Run deployment above already
  demonstrates the working pipeline end to end, which this POC prioritised
  over a separate offline demo path.
- **Clustering, surrogate keys** on BigQuery tables — considered and
  deliberately not applied at this data volume; see ADR-007 in the HLD.
