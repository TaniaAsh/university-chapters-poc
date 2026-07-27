with staged as (
    select * from {{ ref('stg_chapters_raw') }}
),

-- Keep only the latest ingestion run per chapter_id, so a chapter that
-- appears in multiple raw loads (e.g. re-run after a failure) doesn't
-- produce duplicate rows in the canonical curated table.
deduplicated as (
    select
        *,
        row_number() over (
            partition by chapter_id
            order by ingestion_timestamp desc
        ) as row_num
    from staged
),

validated as (
    select
        chapter_id,
        chapter_name,
        city,
        state,
        latitude,
        longitude,
        st_geogpoint(longitude, latitude) as location,
        ingestion_date as snapshot_date,
        run_id
    from deduplicated
    where row_num = 1
        -- Basic coordinate sanity check -- valid lat/long ranges only.
        -- Rows that fail this silently drop out of curated rather than
        -- blocking the whole run; dbt tests above catch anything that
        -- still looks wrong (nulls, duplicates, out-of-scope states).
        and latitude between -90 and 90
        and longitude between -180 and 180
)

select * from validated