-- DIM_DATE
insert into ev_dw.dim_date
    (date_key, full_date, day_of_month, weekday_name, weekday_number, month_number, month_name, quarter_number, year_number)
with all_dates as (
    select start_ts::date as d from ev_staging.clean_sessions
    union all select end_ts::date from ev_staging.clean_sessions
    union all select hour_start::date from ev_staging.clean_hourly_load
    union all select hour_start::date from ev_staging.clean_garage_ams
)
select
    to_char(d, 'YYYYMMDD')::int,
    d::date,
    extract(day from d),
    to_char(d, 'FMDay'),
    extract(isodow from d), -- monday = 1
    extract(month from d),
    to_char(d, 'FMMonth'),
    extract(quarter from d),
    extract(year from d)
from generate_series((select date_trunc('year', min(d)) from all_dates),
                     (select date_trunc('year', max(d)) + interval '1 year - 1 day' from all_dates),
                     interval '1 day') as d
on conflict (date_key) do nothing;

insert into ev_staging.etl_batch (run_name, step_name, source_name, rows_read, rows_loaded, status)
-- rows read = days from the first to the last date, SUCCESS if no day is missing
select 'full_load', 'DIM_LOAD', 'dim_date', max(full_date) - min(full_date) + 1, count(*),
    case when count(*) = max(full_date) - min(full_date) + 1 then 'SUCCESS' else 'COUNT MISMATCH' end
from ev_dw.dim_date;



-- DIM_TIME
insert into ev_dw.dim_time (time_key, hour_number, hour_label, daypart)
select
    h, h,
    lpad(h::text, 2, '0') || ':00',
    case
        when h < 3 then 'early night (midnight-3)'
        when h < 6 then 'late night (3-6)'
        when h < 9 then 'early morning (6-9)'
        when h < 12 then 'late morning (9-12)'
        when h < 15 then 'early afternoon (12-15)'
        when h < 18 then 'late afternoon (15-18)'
        when h < 21 then 'early evening (18-21)'
        else 'late evening (21-midnight)'
    end
from generate_series(0, 23) as h
on conflict (time_key) do nothing;

insert into ev_staging.etl_batch (run_name, step_name, source_name, rows_read, rows_loaded, status)
select 'full_load', 'DIM_LOAD', 'dim_time', 24, count(*),
    case when count(*) = 24 then 'SUCCESS' else 'COUNT MISMATCH' end
from ev_dw.dim_time;



-- DIM_USER
-- unknown row first then one row per user_id + user_type
insert into ev_dw.dim_user (user_key, source_user_id, user_type)
values (-1, 'UNKNOWN', 'Unknown')
on conflict do nothing;

insert into ev_dw.dim_user (source_user_id, user_type)
select distinct user_id, user_type
from ev_staging.clean_sessions
where user_id is not null and user_type is not null
order by user_id, user_type
on conflict (source_user_id, user_type) do nothing;

insert into ev_staging.etl_batch (run_name, step_name, source_name, rows_read, rows_loaded, status)
select 'full_load', 'DIM_LOAD', 'dim_user', p.pairs + 1, count(*),
    case when count(*) = p.pairs + 1 then 'SUCCESS' else 'COUNT MISMATCH' end
from ev_dw.dim_user,
    (select count(*) as pairs from (select distinct user_id, user_type from ev_staging.clean_sessions
                                    where user_id is not null and user_type is not null) x) p
group by p.pairs;



-- DIM_GARAGE
-- Unknown row first, then every garage id from the sessions and the garage file
insert into ev_dw.dim_garage (garage_key, source_garage_id, garage_name)
values (-1, 'UNKNOWN', 'Unknown')
on conflict do nothing;

insert into ev_dw.dim_garage (source_garage_id, garage_name)
select garage_id, garage_id
from (select garage_id from ev_staging.clean_sessions where garage_id is not null
      union
      select garage_id from ev_staging.clean_garage_ams) g
order by garage_id
on conflict (source_garage_id) do nothing;


insert into ev_staging.etl_batch (run_name, step_name, source_name, rows_read, rows_loaded, status)
select 'full_load', 'DIM_LOAD', 'dim_garage', g.garages + 1, count(*),
    case when count(*) = g.garages + 1 then 'SUCCESS' else 'COUNT MISMATCH' end
from ev_dw.dim_garage,
    (select count(*) as garages from (select garage_id from ev_staging.clean_sessions where garage_id is not null
                                      union
                                      select garage_id from ev_staging.clean_garage_ams) x) g
group by g.garages;



-- DIM_CHARGING_TYPE
insert into ev_dw.dim_charging_type (charging_type_name, description)
values
    ('Private', 'charge point on a resident''s private parking space'),
    ('Shared', 'charge point in a shared parking area open to all registered residents')
on conflict (charging_type_name) do nothing;

insert into ev_staging.etl_batch (run_name, step_name, source_name, rows_read, rows_loaded, status)
select 'full_load', 'DIM_LOAD', 'dim_charging_type', 2, count(*),
    case when count(*) = 2 then 'SUCCESS' else 'COUNT MISMATCH' end
from ev_dw.dim_charging_type;



-- checks
select 'dim_date' as dimension, count(*) as total_rows, count(distinct full_date) as distinct_keys from ev_dw.dim_date
union all
select 'dim_time', count(*), count(distinct hour_number) from ev_dw.dim_time
union all
select 'dim_user', count(*), count(distinct (source_user_id, user_type)) from ev_dw.dim_user
union all
select 'dim_garage', count(*), count(distinct source_garage_id) from ev_dw.dim_garage
union all
select 'dim_charging_type', count(*), count(distinct charging_type_name) from ev_dw.dim_charging_type;

-- our daypart vs the source plugin_category
select count(*) as sessions, count(*) filter (where t.daypart <> s.plugin_category) as daypart_mismatch
from ev_staging.clean_sessions s
join ev_dw.dim_time t on t.hour_number = s.start_hour;

-- log of the dimension load
select batch_id, step_name, source_name, rows_read, rows_loaded, status
from ev_staging.etl_batch
where step_name = 'DIM_LOAD'
order by batch_id;
