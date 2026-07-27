with source as (
    select * from {{ source('university_ch_raw', 'chapters_raw') }}
),

renamed as (
    select
        trim(chapter_id)   as chapter_id,
        trim(chapter_name)  as chapter_name,
        trim(city)          as city,
        trim(state)         as state,
        latitude,
        longitude,
        source_object_id,
        ingestion_timestamp,
        ingestion_date,
        run_id
    from source
)

select * from renamed