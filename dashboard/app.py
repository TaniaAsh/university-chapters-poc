"""
Streamlit dashboard for the University Chapters published data product.
Reads directly from university_chapters_v1 -- the same stable, versioned
interface described in the HLD's Data Product Contract (section 5).
"""

import os

import pandas as pd
import streamlit as st
from google.cloud import bigquery

BQ_PROJECT = os.environ.get("BQ_PROJECT", "university-chapters-poc")
BQ_DATASET_PUBLISHED = os.environ.get("BQ_DATASET_PUBLISHED", "university_ch_published")
BQ_VIEW = "university_chapters_v1"

st.set_page_config(page_title="University Chapters", layout="wide")


@st.cache_data(ttl=3600)
def load_published_chapters() -> pd.DataFrame:
    """Query the published view. Cached for an hour -- the data product
    only refreshes once a day, so there's no need to hit BigQuery on
    every widget interaction."""
    client = bigquery.Client(project=BQ_PROJECT)
    query = f"""
        select chapter_id, chapter_name, city, state, latitude, longitude, as_of_date
        from `{BQ_PROJECT}.{BQ_DATASET_PUBLISHED}.{BQ_VIEW}`
        order by state, chapter_name
    """
    return client.query(query).to_dataframe()


st.title("University Chapters")
st.caption(f"Source: `{BQ_PROJECT}.{BQ_DATASET_PUBLISHED}.{BQ_VIEW}` (published, versioned interface)")

try:
    df = load_published_chapters()
except Exception as e:
    st.error(f"Could not load data from BigQuery: {e}")
    st.stop()

if df.empty:
    st.warning("No chapters found in the published view.")
    st.stop()

# --- Status block -- makes the SLA/versioning from the HLD tangible ---
as_of = df["as_of_date"].max()
col1, col2, col3 = st.columns(3)
col1.metric("Chapters (in scope)", len(df))
col2.metric("States covered", df["state"].nunique())
col3.metric("Data as of", str(as_of))

st.divider()

# --- Map ---
st.subheader("Chapter locations")
map_df = df.rename(columns={"latitude": "lat", "longitude": "lon"})
st.map(map_df[["lat", "lon"]])

# --- Chapters by state ---
st.subheader("Chapters by state")
state_counts = df["state"].value_counts().sort_index()
st.bar_chart(state_counts)

# --- Full table ---
st.subheader("All published chapters")
st.dataframe(df, use_container_width=True)