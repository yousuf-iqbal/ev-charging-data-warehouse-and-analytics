-- ev_staging = raw tables, clean tables and the log tables
-- ev_dw = dimensions and facts
-- ev_reporting = views for reports
create schema if not exists ev_staging;
create schema if not exists ev_dw;
create schema if not exists ev_reporting;

--------------------------------
-- DIMENSIONS
--------------------------------
-- one row per day, date key is yyyymmdd
create table if not exists ev_dw.dim_date (
    date_key int primary key,
    full_date date not null unique,
    day_of_month int not null,
    weekday_name text not null,
    weekday_number int not null check (weekday_number between 1 and 7), -- monday = 1
    month_number int not null check (month_number between 1 and 12),
    month_name text not null,
    quarter_number int not null check (quarter_number between 1 and 4),
    year_number int not null
);

-- one row per hour
create table if not exists ev_dw.dim_time (
    time_key int primary key,
    hour_number int not null unique check (hour_number between 0 and 23),
    hour_label text not null,
    daypart text not null -- same 8 blocks of 3 hours as the source
);

-- one row per user and user type, -1 = Unknown
create table if not exists ev_dw.dim_user (
    user_key serial primary key,
    source_user_id text not null,
    user_type text not null,
    unique (source_user_id, user_type)
);

-- one row per garage, -1 = Unknown
create table if not exists ev_dw.dim_garage (
    garage_key serial primary key,
    source_garage_id text not null unique,
    garage_name text not null
);

-- Private or Shared
create table if not exists ev_dw.dim_charging_type (
    charging_type_key serial primary key,
    charging_type_name text not null unique,
    description text
);



--------------------------------
-- FACTS
--------------------------------
-- one row per charging session
create table if not exists ev_dw.fact_charging_session (
    charging_session_key bigint generated always as identity primary key,
    source_session_id bigint not null unique,
    start_date_key int not null references ev_dw.dim_date (date_key),
    start_time_key int not null references ev_dw.dim_time (time_key),
    end_date_key int references ev_dw.dim_date (date_key),
    end_time_key int references ev_dw.dim_time (time_key),
    user_key int not null references ev_dw.dim_user (user_key),
    garage_key int not null references ev_dw.dim_garage (garage_key),
    energy_kwh decimal(12,3) not null check (energy_kwh >= 0),
    duration_hours decimal(12,3) check (duration_hours >= 0),
    session_count int not null default 1 check (session_count = 1),
    data_quality_flag varchar(40) not null,
    source_file varchar(255),
    batch_id bigint references ev_staging.etl_batch (batch_id),
    loaded_at timestamptz default now()
);

-- one row per hour per charging type
create table if not exists ev_dw.fact_hourly_charging_load (
    hourly_load_key bigint generated always as identity primary key,
    date_key int not null references ev_dw.dim_date (date_key),
    time_key int not null references ev_dw.dim_time (time_key),
    charging_type_key int not null references ev_dw.dim_charging_type (charging_type_key),
    hour_occurrence int not null default 1 check (hour_occurrence >= 1),
    synthetic_3_6kw decimal(14,4) check (synthetic_3_6kw >= 0),
    synthetic_7_2kw decimal(14,4) check (synthetic_7_2kw >= 0),
    flex_3_6kw decimal(14,4) check (flex_3_6kw >= 0),
    flex_7_2kw decimal(14,4) check (flex_7_2kw >= 0),
    represented_count int,
    source_count_private int,
    source_count_shared int,
    data_quality_flag varchar(40) not null,
    source_file varchar(255),
    batch_id bigint references ev_staging.etl_batch (batch_id),
    loaded_at timestamptz default now(),
    unique (date_key, time_key, charging_type_key, hour_occurrence)
);

-- one row per hour for garage Bl2
create table if not exists ev_dw.fact_garage_energy_hourly (
    garage_energy_key bigint generated always as identity primary key,
    date_key int not null references ev_dw.dim_date (date_key),
    time_key int not null references ev_dw.dim_time (time_key),
    garage_key int not null references ev_dw.dim_garage (garage_key),
    hour_occurrence int not null default 1 check (hour_occurrence >= 1),
    measured_ams_kwh decimal(14,4) check (measured_ams_kwh >= 0),
    synthetic_3_6kw decimal(14,4) check (synthetic_3_6kw >= 0),
    synthetic_7_2kw decimal(14,4) check (synthetic_7_2kw >= 0),
    simultaneous_if_3_6kw int check (simultaneous_if_3_6kw >= 0),
    data_quality_flag varchar(40) not null,
    source_file varchar(255),
    batch_id bigint references ev_staging.etl_batch (batch_id),
    loaded_at timestamptz default now(),
    unique (date_key, time_key, garage_key, hour_occurrence)
);



--------------------------------
-- REPORTING VIEW
--------------------------------
-- sessions and energy per month
create or replace view ev_reporting.vw_sessions_per_month as
select d.year_number, d.month_number, d.month_name,
    sum(f.session_count) as sessions,
    sum(f.energy_kwh) as energy_kwh
from ev_dw.fact_charging_session f
join ev_dw.dim_date d on d.date_key = f.start_date_key
group by d.year_number, d.month_number, d.month_name;

-- tables and views created
select table_schema, table_name, table_type
from information_schema.tables
where table_schema in ('ev_dw', 'ev_reporting')
order by table_schema, table_type, table_name;