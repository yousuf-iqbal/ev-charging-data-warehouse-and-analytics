-- schemas (warehouse.sql has them too, if not exists makes that safe)
create schema if not exists ev_staging;
create schema if not exists ev_dw;
create schema if not exists ev_reporting;

-- etl_batch = the audit log. One row for every load
-- It tells us how many rows were read, loaded and rejected, and if it worked
create table if not exists ev_staging.etl_batch (
    batch_id bigint generated always as identity primary key,
    run_name text not null, -- full_load
    step_name text not null, -- RAW_IMPORT, CLEAN, DIM_LOAD, FACT_LOAD
    source_name text not null, -- file or table
    logged_at timestamptz default now(),
    rows_read int,
    rows_loaded int,
    rows_rejected int default 0,
    status text not null,
    notes text
);

-- etl_rejected_rows = rows we refuse to load, with the reason
create table if not exists ev_staging.etl_rejected_rows (
    reject_id bigint generated always as identity primary key,
    batch_id bigint references ev_staging.etl_batch (batch_id),
    source_name text not null,
    source_row_id text,
    reason text not null,
    rejected_at timestamptz default now()
);


-- Dataset 1: charging sessions
create table ev_staging.raw_sessions (
    session_id text,
    garage_id text,
    user_id text,
    user_type text,
    shared_id text,
    start_plugin text,
    start_plugin_hour text,
    end_plugout text,
    end_plugout_hour text,
    el_kwh text,
    duration_hours text,
    month_plugin text,
    weekdays_plugin text,
    plugin_category text,
    duration_category text
);

-- hourly load, private charge points
create table ev_staging.raw_hourly_private (
    date_from text,
    daily_hour text,
    weekday text,
    month text,
    synthetic_3_6kw text,
    synthetic_7_2kw text,
    flex_3_6kw text,
    flex_7_2kw text,
    n_private text
);

-- hourly load, shared charge points
create table ev_staging.raw_hourly_shared (
    date_from text,
    daily_hour text,
    weekday text,
    month text,
    synthetic_3_6kw text,
    synthetic_7_2kw text,
    flex_3_6kw text,
    flex_7_2kw text,
    n_shared text
);

-- smart meter data of garage
create table ev_staging.raw_garage_ams (
    date_from text,
    date_to text,
    month text,
    ams_kwh text,
    synthetic_3_6kw text,
    synthetic_7_2kw text,
    simultaneous_if_3_6kw text
);

alter table ev_staging.raw_sessions
    add column raw_row_id bigint generated always as identity,
    add column source_file text default 'Dataset 1_EV charging reports.csv',
    add column loaded_at timestamptz default now();

alter table ev_staging.raw_hourly_private
    add column raw_row_id bigint generated always as identity,
    add column source_file text default 'Dataset 3a_Hourly EV loads - Aggregated private.csv',
    add column loaded_at timestamptz default now();

alter table ev_staging.raw_hourly_shared
    add column raw_row_id bigint generated always as identity,
    add column source_file text default 'Dataset 3b_Hourly EV loads - Aggregated shared.csv',
    add column loaded_at timestamptz default now();

alter table ev_staging.raw_garage_ams
    add column raw_row_id bigint generated always as identity,
    add column source_file text default 'Dataset 5_AMS data from garage Bl2.csv',
    add column loaded_at timestamptz default now();



--------------------------------
-- ROW COUNT CHECK
--------------------------------
select 'raw_sessions' as table_name, count(*) as rows_found, 6878 as rows_expected from ev_staging.raw_sessions
union all
select 'raw_hourly_private' as table_name, count(*) as rows_found, 9757 as rows_expected from ev_staging.raw_hourly_private
union all
select 'raw_hourly_shared' as table_name, count(*) as rows_found, 9288 as rows_expected from ev_staging.raw_hourly_shared
union all
select 'raw_garage_ams' as table_name, count(*) as rows_found, 9466 as rows_expected from ev_staging.raw_garage_ams;



-- quick look at the first rows
select * from ev_staging.raw_sessions order by raw_row_id limit 5;
select * from ev_staging.raw_hourly_private order by raw_row_id limit 5;
select * from ev_staging.raw_hourly_shared order by raw_row_id limit 5;
select * from ev_staging.raw_garage_ams order by raw_row_id limit 5;

-- log table
select batch_id, run_name, step_name, source_name, rows_read, rows_loaded, status
from ev_staging.etl_batch
order by batch_id;


-- the import kept the text NA (it was not turned into null)
select
    count(*) filter (where end_plugout = 'NA') as end_plugout_na,
    count(*) filter (where shared_id = 'NA') as shared_id_na
from ev_staging.raw_sessions;


-- One log row per raw import. rows_read is the number of data rows in the csv file
insert into ev_staging.etl_batch (run_name, step_name, source_name, rows_read, rows_loaded, status, notes)
select 'full_load', 'RAW_IMPORT', 'Dataset 1_EV charging reports.csv', 6878, count(*),
       case when count(*) = 6878 then 'SUCCESS' else 'COUNT MISMATCH' end,
       'imported with pgAdmin, all columns stored as text'
from ev_staging.raw_sessions
having not exists (select 1 from ev_staging.etl_batch
                   where run_name = 'full_load' and step_name = 'RAW_IMPORT'
                     and source_name = 'Dataset 1_EV charging reports.csv');

insert into ev_staging.etl_batch (run_name, step_name, source_name, rows_read, rows_loaded, status, notes)
select 'full_load', 'RAW_IMPORT', 'Dataset 3a_Hourly EV loads - Aggregated private.csv', 9757, count(*),
       case when count(*) = 9757 then 'SUCCESS' else 'COUNT MISMATCH' end,
       'imported with pgAdmin, all columns stored as text'
from ev_staging.raw_hourly_private
having not exists (select 1 from ev_staging.etl_batch
                   where run_name = 'full_load' and step_name = 'RAW_IMPORT'
                     and source_name = 'Dataset 3a_Hourly EV loads - Aggregated private.csv');

insert into ev_staging.etl_batch (run_name, step_name, source_name, rows_read, rows_loaded, status, notes)
select 'full_load', 'RAW_IMPORT', 'Dataset 3b_Hourly EV loads - Aggregated shared.csv', 9288, count(*),
       case when count(*) = 9288 then 'SUCCESS' else 'COUNT MISMATCH' end,
       'imported with pgAdmin, all columns stored as text'
from ev_staging.raw_hourly_shared
having not exists (select 1 from ev_staging.etl_batch
                   where run_name = 'full_load' and step_name = 'RAW_IMPORT'
                     and source_name = 'Dataset 3b_Hourly EV loads - Aggregated shared.csv');

insert into ev_staging.etl_batch (run_name, step_name, source_name, rows_read, rows_loaded, status, notes)
select 'full_load', 'RAW_IMPORT', 'Dataset 5_AMS data from garage Bl2.csv', 9466, count(*),
       case when count(*) = 9466 then 'SUCCESS' else 'COUNT MISMATCH' end,
       'imported with pgAdmin, all columns stored as text'
from ev_staging.raw_garage_ams
having not exists (select 1 from ev_staging.etl_batch
                   where run_name = 'full_load' and step_name = 'RAW_IMPORT'
                     and source_name = 'Dataset 5_AMS data from garage Bl2.csv');

-- log table
select batch_id, run_name, step_name, source_name, rows_read, rows_loaded, status
from ev_staging.etl_batch
order by batch_id;



--------------------------------
-- STEP 3 PROFILING
-- KEY CHECK
-- session_id must be unique, and no session can be missing its id, user or garage
select
    count(*) as total_rows,
    count(distinct session_id) as distinct_session_ids,
    count(*) - count(distinct session_id) as duplicate_rows,
    count(*) filter (where session_id is null or session_id in ('', 'NA')) as blank_session_id,
    count(*) filter (where user_id is null or user_id in ('', 'NA')) as blank_user_id,
    count(*) filter (where garage_id is null or garage_id in ('', 'NA')) as blank_garage_id,
    count(distinct user_id) as distinct_users,
    count(distinct garage_id) as distinct_garages
from ev_staging.raw_sessions;

-- same user and same start time (possible duplicates)
select user_id, start_plugin, count(*) as sessions
from ev_staging.raw_sessions
group by user_id, start_plugin
having count(*) > 1
order by sessions desc;

-- extra spaces at the start or end of the text columns
select
    count(*) filter (where garage_id <> trim(garage_id)) as garage_id_spaces,
    count(*) filter (where user_id <> trim(user_id)) as user_id_spaces,
    count(*) filter (where user_type <> trim(user_type)) as user_type_spaces
from ev_staging.raw_sessions;

--  user_type
select user_type, count(*) as sessions
from ev_staging.raw_sessions
group by user_type;

-- the values of duration_category
select duration_category, count(*) as sessions
from ev_staging.raw_sessions
group by duration_category
order by duration_category;



--------------------------------
-- FORMAT CHECK
--------------------------------
-- dates must look like dd.mm.yyyy hh:mi and numbers like 12 or 12,34 (NA is allowed in the end columns)
select
    count(*) filter (where start_plugin !~ '^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}$') as bad_start,
    count(*) filter (where end_plugout <> 'NA' and end_plugout !~ '^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}$') as bad_end,
    count(*) filter (where el_kwh !~ '^\d+(,\d+)?$') as bad_energy,
    count(*) filter (where duration_hours <> 'NA' and duration_hours !~ '^\d+(,\d+)?$') as bad_duration
from ev_staging.raw_sessions;

-- how many NA values in each end column, and are they the same rows
select
    count(*) filter (where end_plugout = 'NA') as end_plugout_na,
    count(*) filter (where end_plugout_hour = 'NA') as end_hour_na,
    count(*) filter (where duration_hours = 'NA') as duration_na,
    count(*) filter (where duration_category = 'NA') as duration_category_na,
    count(*) filter (where end_plugout = 'NA' and end_plugout_hour = 'NA'
                       and duration_hours = 'NA' and duration_category = 'NA') as all_four_na
from ev_staging.raw_sessions;

-- sessions with no end still have a start time and energy, so we keep them and flag them (not delete)
select session_id, user_id, garage_id, start_plugin, el_kwh
from ev_staging.raw_sessions
where end_plugout = 'NA'
order by raw_row_id;



--------------------------------
-- DURATION CHECK
--------------------------------
-- does duration hours equal end minus start? sessions that differ by more than 1 minute
select session_id, start_plugin, end_plugout, duration_hours,
    round(extract(epoch from to_timestamp(end_plugout, 'DD.MM.YYYY HH24:MI') - to_timestamp(start_plugin, 'DD.MM.YYYY HH24:MI')) / 3600
          - replace(duration_hours, ',', '.')::numeric, 2) as difference_hours
from ev_staging.raw_sessions
where end_plugout <> 'NA'
  and abs(extract(epoch from to_timestamp(end_plugout, 'DD.MM.YYYY HH24:MI') - to_timestamp(start_plugin, 'DD.MM.YYYY HH24:MI')) / 3600
          - replace(duration_hours, ',', '.')::numeric) > 1 / 60.0
order by difference_hours;


-- USER TYPE
-- a user should have one type, but some users moved between private and shared charge points
select user_id,
    count(*) filter (where user_type = 'Private') as private_sessions,
    count(*) filter (where user_type = 'Shared') as shared_sessions
from ev_staging.raw_sessions
group by user_id
having count(distinct user_type) > 1
order by user_id;



-- HOURLY private and shared csv files 
-- NA values and the range of the user count, one row per file
select 'private (3a)' as file, count(*) as total_rows,
    count(*) filter (where 'NA' in (synthetic_3_6kw, synthetic_7_2kw, flex_3_6kw, flex_7_2kw, n_private)) as rows_with_na,
    min(n_private::int) as min_n_count, max(n_private::int) as max_n_count
from ev_staging.raw_hourly_private
union all
select 'shared (3b)', count(*),
    count(*) filter (where 'NA' in (synthetic_3_6kw, synthetic_7_2kw, flex_3_6kw, flex_7_2kw, n_shared)),
    min(n_shared::int), max(n_shared::int)
from ev_staging.raw_hourly_shared;

-- hours that appear twice (there should be one row per hour)
select 'private (3a)' as file, date_from, count(*) as times_seen
from ev_staging.raw_hourly_private
group by date_from
having count(*) > 1
union all
select 'shared (3b)', date_from, count(*)
from ev_staging.raw_hourly_shared
group by date_from
having count(*) > 1;

-- load values that are not a plain number like 12 or 12,34 (NA is skipped)
select 'private (3a)' as file, synthetic_3_6kw, synthetic_7_2kw, flex_3_6kw, flex_7_2kw
from ev_staging.raw_hourly_private
where synthetic_3_6kw !~ '^(\d+(,\d+)?|NA)$' or synthetic_7_2kw !~ '^(\d+(,\d+)?|NA)$'
   or flex_3_6kw !~ '^(\d+(,\d+)?|NA)$' or flex_7_2kw !~ '^(\d+(,\d+)?|NA)$'
union all
select 'shared (3b)', synthetic_3_6kw, synthetic_7_2kw, flex_3_6kw, flex_7_2kw
from ev_staging.raw_hourly_shared
where synthetic_3_6kw !~ '^(\d+(,\d+)?|NA)$' or synthetic_7_2kw !~ '^(\d+(,\d+)?|NA)$'
   or flex_3_6kw !~ '^(\d+(,\d+)?|NA)$' or flex_7_2kw !~ '^(\d+(,\d+)?|NA)$'
union all
select 'garage bl2 (5)', ams_kwh, synthetic_3_6kw, synthetic_7_2kw, simultaneous_if_3_6kw
from ev_staging.raw_garage_ams
where ams_kwh !~ '^(\d+(,\d+)?|NA)$' or synthetic_3_6kw !~ '^(\d+(,\d+)?|NA)$' or synthetic_7_2kw !~ '^(\d+(,\d+)?|NA)$';


-- GARAGE BL2 (DATASET 5)
-- NA and blank values per column
select
    count(*) as total_rows,
    count(*) filter (where ams_kwh = 'NA') as ams_na,
    count(*) filter (where synthetic_3_6kw = 'NA') as synthetic_3_6_na,
    count(*) filter (where synthetic_7_2kw = 'NA') as synthetic_7_2_na,
    count(*) filter (where simultaneous_if_3_6kw = 'NA') as simultaneous_na,
    count(*) filter (where date_to is null) as blank_date_to
from ev_staging.raw_garage_ams;

-- garage Bl2 must exist in the sessions file, so dataset 5 can join to dim_garage
select count(*) as bl2_sessions
from ev_staging.raw_sessions
where garage_id = 'Bl2';


-- DATE RANGE
-- first and last date of every file, dim_date must cover all of them
select 'sessions' as source,
    min(to_timestamp(start_plugin, 'DD.MM.YYYY HH24:MI')) as first_date,
    max(to_timestamp(start_plugin, 'DD.MM.YYYY HH24:MI')) as last_date
from ev_staging.raw_sessions
union all
select 'hourly private (3a)', min(to_timestamp(date_from, 'DD.MM.YYYY HH24:MI')), max(to_timestamp(date_from, 'DD.MM.YYYY HH24:MI'))
from ev_staging.raw_hourly_private
union all
select 'hourly shared (3b)', min(to_timestamp(date_from, 'DD.MM.YYYY HH24:MI')), max(to_timestamp(date_from, 'DD.MM.YYYY HH24:MI'))
from ev_staging.raw_hourly_shared
union all
select 'garage bl2 (5)', min(to_timestamp(date_from, 'DD.MM.YYYY HH24:MI')), max(to_timestamp(date_from, 'DD.MM.YYYY HH24:MI'))
from ev_staging.raw_garage_ams;



-- raw tables are never changed. bad rows go to etl_rejected_rows with a reason
-- a valid number can also be written in scientific notation
-- every load has 4 parts: open the log row, set aside bad rows, load good rows, close the log row

-- 4.1 CLEAN TABLES
-- one row per charging session
create table if not exists ev_staging.clean_sessions (
    session_id bigint primary key,
    garage_id text,
    user_id text,
    user_type text,
    shared_id text,
    start_ts timestamp not null,
    end_ts timestamp, 
    start_hour int,
    end_hour int,
    energy_kwh numeric not null,
    duration_hours numeric,
    plugin_category text,
    duration_category text,
    data_quality_flag text not null, -- COMPLETE, MISSING_END, DURATION_MISMATCH
    raw_row_id bigint,
    source_file text,
    cleaned_at timestamptz default now()
);

-- one row per hour per charging type (private file 3a and shared file 3b together)
create table if not exists ev_staging.clean_hourly_load (
    charging_type text not null, -- Private (3a) or Shared (3b)
    hour_start timestamp not null,
    hour_occurrence int not null, -- 1, or 2, 3.. if the same hour appears again in the file
    synthetic_3_6kw numeric,
    synthetic_7_2kw numeric,
    flex_3_6kw numeric,
    flex_7_2kw numeric,
    n_users int, -- n_private or n_shared
    data_quality_flag text not null, -- COMPLETE, REPEATED_HOUR
    raw_row_id bigint,
    source_file text,
    cleaned_at timestamptz default now(),
    unique (charging_type, hour_start, hour_occurrence)
);

-- one row per hour for garage
create table if not exists ev_staging.clean_garage_ams (
    garage_id text not null default 'Bl2',
    hour_start timestamp not null,
    hour_end timestamp, 
    hour_occurrence int not null,
    ams_kwh numeric, -- measured energy
    synthetic_3_6kw numeric,
    synthetic_7_2kw numeric,
    simultaneous_if_3_6kw int, -- a count of sessions, null means no sessions that hour
    data_quality_flag text not null, -- COMPLETE, MISSING_DATE_TO, REPEATED_HOUR, MISSING_AMS, MISSING_SYNTHETIC
    raw_row_id bigint,
    source_file text,
    cleaned_at timestamptz default now(),
    unique (hour_start, hour_occurrence)
);


--------------------
-- CLEANING SESSIONS
--------------------
-- accepted rows log 
insert into ev_staging.etl_batch (run_name, step_name, source_name, rows_read, status)
select 'full_load', 'CLEAN', 'raw_sessions', count(*), 'STARTED'
from ev_staging.raw_sessions;

-- rejected rows log with reason
insert into ev_staging.etl_rejected_rows (batch_id, source_name, source_row_id, reason)
select
    (select max(batch_id) from ev_staging.etl_batch where step_name = 'CLEAN' and source_name = 'raw_sessions'),
    'raw_sessions', r.raw_row_id::text, r.reason
from (
    select raw_row_id,
        case
            when session_id is null or trim(session_id) !~ '^\d+$' then 'session_id missing or not a number'
            when start_plugin is null or start_plugin !~ '^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}$' then 'start_plugin is not a valid date'
            when end_plugout <> 'NA' and end_plugout !~ '^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}$' then 'end_plugout is not a valid date'
            when el_kwh is null or el_kwh !~ '^\d+(,\d+)?(E-?\d+)?$' then 'el_kwh is not a number'
            when duration_hours <> 'NA' and duration_hours !~ '^\d+(,\d+)?(E-?\d+)?$' then 'duration_hours is not a number'
        end as reason
    from ev_staging.raw_sessions
) r
where r.reason is not null
and not exists (select 1 from ev_staging.etl_rejected_rows x
                where x.source_name = 'raw_sessions' and x.source_row_id = r.raw_row_id::text);

-- c) loading the good rows
-- trim the text, NA becomes null, comma becomes dot, extra spaces inside text become one space
-- the source duration is kept. if it does not match end minus start (more than 1 minute off) the row is flagged
insert into ev_staging.clean_sessions
    (session_id, garage_id, user_id, user_type, shared_id, start_ts, end_ts, start_hour, end_hour,
     energy_kwh, duration_hours, plugin_category, duration_category, data_quality_flag, raw_row_id, source_file)
select
    p.session_id, p.garage_id, p.user_id, p.user_type, p.shared_id, p.start_ts, p.end_ts,
    extract(hour from p.start_ts), extract(hour from p.end_ts),
    p.energy_kwh, p.duration_hours, p.plugin_category, p.duration_category,
    case
        when p.end_ts is null or p.duration_hours is null then 'MISSING_END'
        when abs(p.duration_hours - extract(epoch from p.end_ts - p.start_ts) / 3600) > 1 / 60.0 then 'DURATION_MISMATCH'
        else 'COMPLETE'
    end,
    p.raw_row_id, p.source_file
from (
    select
        trim(session_id)::bigint as session_id,
        nullif(nullif(trim(garage_id), ''), 'NA') as garage_id,
        nullif(nullif(trim(user_id), ''), 'NA') as user_id,
        nullif(nullif(initcap(trim(user_type)), ''), 'Na') as user_type,
        nullif(nullif(trim(shared_id), ''), 'NA') as shared_id,
        to_timestamp(start_plugin, 'DD.MM.YYYY HH24:MI')::timestamp as start_ts,
        case when end_plugout <> 'NA' then to_timestamp(end_plugout, 'DD.MM.YYYY HH24:MI')::timestamp end as end_ts,
        replace(el_kwh, ',', '.')::numeric as energy_kwh,
        case when duration_hours <> 'NA' then replace(duration_hours, ',', '.')::numeric end as duration_hours,
        trim(plugin_category) as plugin_category,
        nullif(regexp_replace(trim(duration_category), '\s+', ' ', 'g'), 'NA') as duration_category,
        raw_row_id, source_file
    from ev_staging.raw_sessions s
    where not exists (select 1 from ev_staging.etl_rejected_rows x
                      where x.source_name = 'raw_sessions' and x.source_row_id = s.raw_row_id::text)
) p
on conflict (session_id) do nothing;

-- d) close the log row
update ev_staging.etl_batch b
set rows_loaded = (select count(*) from ev_staging.clean_sessions),
    rows_rejected = (select count(*) from ev_staging.etl_rejected_rows where source_name = 'raw_sessions'),
    status = case when b.rows_read = (select count(*) from ev_staging.clean_sessions)
                                   + (select count(*) from ev_staging.etl_rejected_rows where source_name = 'raw_sessions')
                  then 'SUCCESS' else 'COUNT MISMATCH' end,
    notes = 'text to timestamp and numeric, NA to null, quality flags set'
where b.batch_id = (select max(batch_id) from ev_staging.etl_batch where step_name = 'CLEAN' and source_name = 'raw_sessions');



------------------------------------
-- CLEANING HOURLY SHARED/PRIV DATA
------------------------------------
-- one table for both shared and private, charging_type says shared/private
-- if the same hour appears more than once, every row is kept: hour_occurrence numbers them and they are flagged
-- private file (3a)
insert into ev_staging.etl_batch (run_name, step_name, source_name, rows_read, status)
select 'full_load', 'CLEAN', 'raw_hourly_private', count(*), 'STARTED'
from ev_staging.raw_hourly_private;

insert into ev_staging.etl_rejected_rows (batch_id, source_name, source_row_id, reason)
select
    (select max(batch_id) from ev_staging.etl_batch where step_name = 'CLEAN' and source_name = 'raw_hourly_private'),
    'raw_hourly_private', r.raw_row_id::text, r.reason
from (
    select raw_row_id,
        case
            when date_from is null or date_from !~ '^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}$' then 'date_from is not a valid date'
            when synthetic_3_6kw !~ '^(\d+(,\d+)?(E-?\d+)?|NA)$' or synthetic_7_2kw !~ '^(\d+(,\d+)?(E-?\d+)?|NA)$'
              or flex_3_6kw !~ '^(\d+(,\d+)?(E-?\d+)?|NA)$' or flex_7_2kw !~ '^(\d+(,\d+)?(E-?\d+)?|NA)$' then 'load value is not a number'
            when n_private !~ '^(\d+|NA)$' then 'n_private is not a whole number'
        end as reason
    from ev_staging.raw_hourly_private
) r
where r.reason is not null
and not exists (select 1 from ev_staging.etl_rejected_rows x
                where x.source_name = 'raw_hourly_private' and x.source_row_id = r.raw_row_id::text);

insert into ev_staging.clean_hourly_load
    (charging_type, hour_start, hour_occurrence, synthetic_3_6kw, synthetic_7_2kw, flex_3_6kw, flex_7_2kw,
     n_users, data_quality_flag, raw_row_id, source_file)
select
    'Private',
    to_timestamp(date_from, 'DD.MM.YYYY HH24:MI')::timestamp,
    row_number() over (partition by date_from order by raw_row_id),
    replace(nullif(synthetic_3_6kw, 'NA'), ',', '.')::numeric,
    replace(nullif(synthetic_7_2kw, 'NA'), ',', '.')::numeric,
    replace(nullif(flex_3_6kw, 'NA'), ',', '.')::numeric,
    replace(nullif(flex_7_2kw, 'NA'), ',', '.')::numeric,
    nullif(n_private, 'NA')::int,
    case when count(*) over (partition by date_from) > 1 then 'REPEATED_HOUR' else 'COMPLETE' end,
    raw_row_id, source_file
from ev_staging.raw_hourly_private h
where not exists (select 1 from ev_staging.etl_rejected_rows x
                  where x.source_name = 'raw_hourly_private' and x.source_row_id = h.raw_row_id::text)
on conflict (charging_type, hour_start, hour_occurrence) do nothing;

update ev_staging.etl_batch b
set rows_loaded = (select count(*) from ev_staging.clean_hourly_load where charging_type = 'Private'),
    rows_rejected = (select count(*) from ev_staging.etl_rejected_rows where source_name = 'raw_hourly_private'),
    status = case when b.rows_read = (select count(*) from ev_staging.clean_hourly_load where charging_type = 'Private')
                                   + (select count(*) from ev_staging.etl_rejected_rows where source_name = 'raw_hourly_private')
                  then 'SUCCESS' else 'COUNT MISMATCH' end,
    notes = 'loaded as charging_type Private, hour_occurrence added'
where b.batch_id = (select max(batch_id) from ev_staging.etl_batch where step_name = 'CLEAN' and source_name = 'raw_hourly_private');

-- shared file (3b)
insert into ev_staging.etl_batch (run_name, step_name, source_name, rows_read, status)
select 'full_load', 'CLEAN', 'raw_hourly_shared', count(*), 'STARTED'
from ev_staging.raw_hourly_shared;

insert into ev_staging.etl_rejected_rows (batch_id, source_name, source_row_id, reason)
select
    (select max(batch_id) from ev_staging.etl_batch where step_name = 'CLEAN' and source_name = 'raw_hourly_shared'),
    'raw_hourly_shared', r.raw_row_id::text, r.reason
from (
    select raw_row_id,
        case
            when date_from is null or date_from !~ '^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}$' then 'date_from is not a valid date'
            when synthetic_3_6kw !~ '^(\d+(,\d+)?(E-?\d+)?|NA)$' or synthetic_7_2kw !~ '^(\d+(,\d+)?(E-?\d+)?|NA)$'
              or flex_3_6kw !~ '^(\d+(,\d+)?(E-?\d+)?|NA)$' or flex_7_2kw !~ '^(\d+(,\d+)?(E-?\d+)?|NA)$' then 'load value is not a number'
            when n_shared !~ '^(\d+|NA)$' then 'n_shared is not a whole number'
        end as reason
    from ev_staging.raw_hourly_shared
) r
where r.reason is not null
and not exists (select 1 from ev_staging.etl_rejected_rows x
                where x.source_name = 'raw_hourly_shared' and x.source_row_id = r.raw_row_id::text);

insert into ev_staging.clean_hourly_load
    (charging_type, hour_start, hour_occurrence, synthetic_3_6kw, synthetic_7_2kw, flex_3_6kw, flex_7_2kw,
     n_users, data_quality_flag, raw_row_id, source_file)
select
    'Shared',
    to_timestamp(date_from, 'DD.MM.YYYY HH24:MI')::timestamp,
    row_number() over (partition by date_from order by raw_row_id),
    replace(nullif(synthetic_3_6kw, 'NA'), ',', '.')::numeric,
    replace(nullif(synthetic_7_2kw, 'NA'), ',', '.')::numeric,
    replace(nullif(flex_3_6kw, 'NA'), ',', '.')::numeric,
    replace(nullif(flex_7_2kw, 'NA'), ',', '.')::numeric,
    nullif(n_shared, 'NA')::int,
    case when count(*) over (partition by date_from) > 1 then 'REPEATED_HOUR' else 'COMPLETE' end,
    raw_row_id, source_file
from ev_staging.raw_hourly_shared h
where not exists (select 1 from ev_staging.etl_rejected_rows x
                  where x.source_name = 'raw_hourly_shared' and x.source_row_id = h.raw_row_id::text)
on conflict (charging_type, hour_start, hour_occurrence) do nothing;

update ev_staging.etl_batch b
set rows_loaded = (select count(*) from ev_staging.clean_hourly_load where charging_type = 'Shared'),
    rows_rejected = (select count(*) from ev_staging.etl_rejected_rows where source_name = 'raw_hourly_shared'),
    status = case when b.rows_read = (select count(*) from ev_staging.clean_hourly_load where charging_type = 'Shared')
                                   + (select count(*) from ev_staging.etl_rejected_rows where source_name = 'raw_hourly_shared')
                  then 'SUCCESS' else 'COUNT MISMATCH' end,
    notes = 'loaded as charging_type Shared, hour_occurrence added'
where b.batch_id = (select max(batch_id) from ev_staging.etl_batch where step_name = 'CLEAN' and source_name = 'raw_hourly_shared');



--------------------------------
-- CLEANing GARAGE (DATASET 5)
--------------------------------
-- NA becomes null and odd rows are kept and flagged
insert into ev_staging.etl_batch (run_name, step_name, source_name, rows_read, status)
select 'full_load', 'CLEAN', 'raw_garage_ams', count(*), 'STARTED'
from ev_staging.raw_garage_ams;

insert into ev_staging.etl_rejected_rows (batch_id, source_name, source_row_id, reason)
select
    (select max(batch_id) from ev_staging.etl_batch where step_name = 'CLEAN' and source_name = 'raw_garage_ams'),
    'raw_garage_ams', r.raw_row_id::text, r.reason
from (
    select raw_row_id,
        case
            when date_from is null or date_from !~ '^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}$' then 'date_from is not a valid date'
            when date_to is not null and date_to !~ '^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}$' then 'date_to is not a valid date'
            when ams_kwh !~ '^(\d+(,\d+)?(E-?\d+)?|NA)$' or synthetic_3_6kw !~ '^(\d+(,\d+)?(E-?\d+)?|NA)$'
              or synthetic_7_2kw !~ '^(\d+(,\d+)?(E-?\d+)?|NA)$' then 'energy value is not a number'
            when simultaneous_if_3_6kw !~ '^(\d+|NA)$' then 'simultaneous_if_3_6kw is not a whole number'
        end as reason
    from ev_staging.raw_garage_ams
) r
where r.reason is not null
and not exists (select 1 from ev_staging.etl_rejected_rows x
                where x.source_name = 'raw_garage_ams' and x.source_row_id = r.raw_row_id::text);

insert into ev_staging.clean_garage_ams
    (garage_id, hour_start, hour_end, hour_occurrence, ams_kwh, synthetic_3_6kw, synthetic_7_2kw,
     simultaneous_if_3_6kw, data_quality_flag, raw_row_id, source_file)
select
    'Bl2',
    to_timestamp(date_from, 'DD.MM.YYYY HH24:MI')::timestamp,
    case when date_to is not null then to_timestamp(date_to, 'DD.MM.YYYY HH24:MI')::timestamp end,
    row_number() over (partition by date_from order by raw_row_id),
    replace(nullif(ams_kwh, 'NA'), ',', '.')::numeric,
    replace(nullif(synthetic_3_6kw, 'NA'), ',', '.')::numeric,
    replace(nullif(synthetic_7_2kw, 'NA'), ',', '.')::numeric,
    nullif(simultaneous_if_3_6kw, 'NA')::int,
    case
        when date_to is null then 'MISSING_DATE_TO'
        when count(*) over (partition by date_from) > 1 then 'REPEATED_HOUR'
        when ams_kwh = 'NA' then 'MISSING_AMS'
        when synthetic_3_6kw = 'NA' or synthetic_7_2kw = 'NA' then 'MISSING_SYNTHETIC'
        else 'COMPLETE'
    end,
    raw_row_id, source_file
from ev_staging.raw_garage_ams g
where not exists (select 1 from ev_staging.etl_rejected_rows x
                  where x.source_name = 'raw_garage_ams' and x.source_row_id = g.raw_row_id::text)
on conflict (hour_start, hour_occurrence) do nothing;

update ev_staging.etl_batch b
set rows_loaded = (select count(*) from ev_staging.clean_garage_ams),
    rows_rejected = (select count(*) from ev_staging.etl_rejected_rows where source_name = 'raw_garage_ams'),
    status = case when b.rows_read = (select count(*) from ev_staging.clean_garage_ams)
                                   + (select count(*) from ev_staging.etl_rejected_rows where source_name = 'raw_garage_ams')
                  then 'SUCCESS' else 'COUNT MISMATCH' end,
    notes = 'NA kept as null, odd rows flagged, hour_occurrence added'
where b.batch_id = (select max(batch_id) from ev_staging.etl_batch where step_name = 'CLEAN' and source_name = 'raw_garage_ams');



-- checks
-- raw rows vs clean rows vs rejected rows
select 'sessions' as source,
    (select count(*) from ev_staging.raw_sessions) as raw_rows,
    (select count(*) from ev_staging.clean_sessions) as clean_rows,
    (select count(*) from ev_staging.etl_rejected_rows where source_name = 'raw_sessions') as rejected_rows
union all
select 'hourly private (3a)',
    (select count(*) from ev_staging.raw_hourly_private),
    (select count(*) from ev_staging.clean_hourly_load where charging_type = 'Private'),
    (select count(*) from ev_staging.etl_rejected_rows where source_name = 'raw_hourly_private')
union all
select 'hourly shared (3b)',
    (select count(*) from ev_staging.raw_hourly_shared),
    (select count(*) from ev_staging.clean_hourly_load where charging_type = 'Shared'),
    (select count(*) from ev_staging.etl_rejected_rows where source_name = 'raw_hourly_shared')
union all
select 'garage bl2 (5)',
    (select count(*) from ev_staging.raw_garage_ams),
    (select count(*) from ev_staging.clean_garage_ams),
    (select count(*) from ev_staging.etl_rejected_rows where source_name = 'raw_garage_ams');

-- rows per quality flag
select 'sessions' as source, data_quality_flag, count(*) as rows from ev_staging.clean_sessions group by data_quality_flag
union all
select 'hourly ' || charging_type, data_quality_flag, count(*) from ev_staging.clean_hourly_load group by charging_type, data_quality_flag
union all
select 'garage bl2', data_quality_flag, count(*) from ev_staging.clean_garage_ams group by data_quality_flag
order by source, rows desc;

-- the log of the clean step
select batch_id, run_name, step_name, source_name, rows_read, rows_loaded, rows_rejected, status
from ev_staging.etl_batch
where step_name = 'CLEAN'
order by batch_id;