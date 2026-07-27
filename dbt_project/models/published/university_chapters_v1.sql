select
    chapter_id,
    chapter_name,
    city,
    state,
    latitude,
    longitude,
    location,
    snapshot_date as as_of_date
from {{ ref('chapter_snapshot') }}