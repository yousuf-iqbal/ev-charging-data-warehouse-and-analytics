# EV Charging Demand and Energy Utilization Analytics

DL3004 Data Warehousing and BI Lab, Final Project (FAST-NUCES Lahore, Fall 2026)
Group: Laiba Shahzad (24L-2600), Abdul Ahad (24L-2594), Yousuf Iqbal (24L-2539)

A PostgreSQL data warehouse for residential EV charging data from a housing cooperative in Trondheim, Norway. It holds real charging sessions, synthetic hourly charging load for private and shared charge points, and real smart meter readings for garage Bl2.

Data source: "Residential electric vehicle charging datasets from apartment buildings", Sorensen, Lindberg, Sartori and Andresen, Data in Brief 36 (2021) 107105. Files on Mendeley Data, DOI 10.17632/jbks2rcwyj.2.

## Architecture

```
CSV files (semicolon, decimal comma, NA for missing)
  -> ev_staging   raw_* tables (exact copy, all text) -> clean_* tables (typed, flagged)
                  etl_batch (audit log), etl_rejected_rows
  -> ev_dw        5 dimensions (surrogate keys) + 3 facts
  -> ev_reporting views (Phase 3)
```

Dimensions: dim_date (1096 days, 2018 to 2020), dim_time (24 hours, 8 dayparts), dim_user (109 rows: user + type, plus Unknown), dim_garage (25 rows, plus Unknown), dim_charging_type (Private, Shared).

Facts:

| Fact | Grain | Rows | Source |
|---|---|---|---|
| fact_charging_session | one charging session | 6,878 | Dataset 1 |
| fact_hourly_charging_load | one hour for one charging type | 19,045 | Datasets 3a and 3b |
| fact_garage_energy_hourly | one hour for garage Bl2 | 9,466 | Dataset 5 |

## Repository structure

```
01_Project_Documentation   Phase 1 documents and schema diagram, Data Cleaning Report, Data Quality Report
02_Data/raw_data           source CSV files (Datasets 1, 3a, 3b and 5 are loaded, Dataset 2 is not)
03_ETL                     staging.sql, dimensions.sql, facts.sql, data_quality.sql
04_Data_Warehouse          warehouse.sql
05_Analytics               (Phase 3)
06_Dashboard               (Phase 3)
README.md
```

## Run order (fresh database)

Run in pgAdmin, in one empty database. Highlight a block and press F5 when only part of a file must run.

1. `03_ETL/staging.sql`, from the top until the `alter table` lines (schemas, log tables, the 4 raw tables).
2. Import the 4 CSVs with pgAdmin (right click the table > Import/Export Data): Import, format csv, header yes, delimiter `;`, quote `"`, NULL strings left empty.
   - raw_sessions <- Dataset 1_EV charging reports.csv
   - raw_hourly_private <- Dataset 3a_Hourly EV loads - Aggregated private.csv
   - raw_hourly_shared <- Dataset 3b_Hourly EV loads - Aggregated shared.csv
   - raw_garage_ams <- Dataset 5_AMS data from garage Bl2.csv
3. `03_ETL/staging.sql`, from the `alter table` lines to the end (lineage columns, counts, log, profiling, clean layer).
4. `04_Data_Warehouse/warehouse.sql` (dimension and fact tables, reporting view).
5. `03_ETL/dimensions.sql`
6. `03_ETL/facts.sql`
7. `03_ETL/data_quality.sql` (run the 3 constraint tests one at a time, they must fail).


## Key results

| Check | Result |
|---|---|
| Raw rows = clean rows = fact rows | 35,389 = 35,389 = 35,389 |
| Rejected rows | 0 |
| Quality flags | sessions: 34 missing end, 22 duration mismatch; hourly and garage: repeated hours and missing values flagged, never set to 0 |
| Energy, raw vs fact | 87,493.28 kWh = 87,493.28 kWh |
| Hourly synthetic 3.6 kW load, raw vs fact | 87,462.60 = 87,462.60 |
| Garage AMS energy, raw vs fact | 28,275.25 kWh = 28,275.25 kWh |
| Orphan fact rows | 0 |
| Duplicate business keys (facts and dimensions) | 0 |
| Constraint tests (FK, unique, check) | 3 of 3 rejected |

## Notes

- The pipeline is ELT: files are loaded first, then cleaned with SQL inside PostgreSQL.
- Missing values (NA) are stored as NULL, never as 0.
- Every load uses unique business keys with on conflict do nothing, so running a load again adds no duplicate rows.
- Dataset 2 is in the raw data folder only. It is outside the Phase 1 scope and is not loaded.
- Phase 2 added a few columns to the Phase 1 schema: hour_occurrence, data_quality_flag, batch_id and loaded_at on the facts, a description column on dim_charging_type, and Unknown rows (key -1) in dim_user and dim_garage. simultaneous_if_3_6kw is an integer count because the source defines it as a count of sessions.
