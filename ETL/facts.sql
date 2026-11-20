-- every fact load: open the log row, load with business key to surrogate key mapping, close the log row

--------------------------------
-- FACT_CHARGING_SESSION
--------------------------------
insert into ev_staging.etl_batch (run_name, step_name, source_name, rows_read, status)
select 'full_load', 'FACT_LOAD', 'fact_charging_session', count(*), 'STARTED'
from ev_staging.clean_sessions;

-- unknown user or garage goes to the Unknown row (-1), so no session is dropped
insert into ev_dw.fact_charging_session
    (source_session_id, start_date_key, start_time_key, end_date_key, end_time_key, user_key, garage_key,
     energy_kwh, duration_hours, session_count, data_quality_flag, source_file, batch_id)
select
    s.session_id,
    sd.date_key,
    st.time_key,
    ed.date_key,
    et.time_key,
    coalesce(u.user_key, -1),
    coalesce(g.garage_key, -1),
    round(s.energy_kwh, 3),
    round(s.duration_hours, 3),
    1,
    s.data_quality_flag,
    s.source_file,
    (select max(batch_id) from ev_staging.etl_batch where step_name = 'FACT_LOAD' and source_name = 'fact_charging_session')
from ev_staging.clean_sessions s
join ev_dw.dim_date sd on sd.full_date = s.start_ts::date
join ev_dw.dim_time st on st.hour_number = s.start_hour
left join ev_dw.dim_date ed on ed.full_date = s.end_ts::date
left join ev_dw.dim_time et on et.hour_number = s.end_hour
left join ev_dw.dim_user u on u.source_user_id = s.user_id and u.user_type = s.user_type
left join ev_dw.dim_garage g on g.source_garage_id = s.garage_id
on conflict (source_session_id) do nothing;

update ev_staging.etl_batch b
set rows_loaded = (select count(*) from ev_dw.fact_charging_session),
    status = case when b.rows_read = (select count(*) from ev_dw.fact_charging_session) then 'SUCCESS' else 'COUNT MISMATCH' end
where b.batch_id = (select max(batch_id) from ev_staging.etl_batch where step_name = 'FACT_LOAD' and source_name = 'fact_charging_session');



--------------------------------
-- FACT_HOURLY_CHARGING_LOAD
--------------------------------
insert into ev_staging.etl_batch (run_name, step_name, source_name, rows_read, status)
select 'full_load', 'FACT_LOAD', 'fact_hourly_charging_load', count(*), 'STARTED'
from ev_staging.clean_hourly_load;

-- represented_count = n_users for both types
insert into ev_dw.fact_hourly_charging_load
    (date_key, time_key, charging_type_key, hour_occurrence, synthetic_3_6kw, synthetic_7_2kw, flex_3_6kw, flex_7_2kw,
     represented_count, source_count_private, source_count_shared, data_quality_flag, source_file, batch_id)
select
    d.date_key,
    t.time_key,
    ct.charging_type_key,
    h.hour_occurrence,
    round(h.synthetic_3_6kw, 4),
    round(h.synthetic_7_2kw, 4),
    round(h.flex_3_6kw, 4),
    round(h.flex_7_2kw, 4),
    h.n_users,
    case when h.charging_type = 'Private' then h.n_users end,
    case when h.charging_type = 'Shared' then h.n_users end,
    h.data_quality_flag,
    h.source_file,
    (select max(batch_id) from ev_staging.etl_batch where step_name = 'FACT_LOAD' and source_name = 'fact_hourly_charging_load')
from ev_staging.clean_hourly_load h
join ev_dw.dim_date d on d.full_date = h.hour_start::date
join ev_dw.dim_time t on t.hour_number = extract(hour from h.hour_start)
join ev_dw.dim_charging_type ct on ct.charging_type_name = h.charging_type
on conflict (date_key, time_key, charging_type_key, hour_occurrence) do nothing;

update ev_staging.etl_batch b
set rows_loaded = (select count(*) from ev_dw.fact_hourly_charging_load),
    status = case when b.rows_read = (select count(*) from ev_dw.fact_hourly_charging_load) then 'SUCCESS' else 'COUNT MISMATCH' end
where b.batch_id = (select max(batch_id) from ev_staging.etl_batch where step_name = 'FACT_LOAD' and source_name = 'fact_hourly_charging_load');



--------------------------------
-- FACT_GARAGE_ENERGY_HOURLY
--------------------------------
insert into ev_staging.etl_batch (run_name, step_name, source_name, rows_read, status)
select 'full_load', 'FACT_LOAD', 'fact_garage_energy_hourly', count(*), 'STARTED'
from ev_staging.clean_garage_ams;

insert into ev_dw.fact_garage_energy_hourly
    (date_key, time_key, garage_key, hour_occurrence, measured_ams_kwh, synthetic_3_6kw, synthetic_7_2kw,
     simultaneous_if_3_6kw, data_quality_flag, source_file, batch_id)
select
    d.date_key,
    t.time_key,
    coalesce(g.garage_key, -1),
    a.hour_occurrence,
    round(a.ams_kwh, 4),
    round(a.synthetic_3_6kw, 4),
    round(a.synthetic_7_2kw, 4),
    a.simultaneous_if_3_6kw,
    a.data_quality_flag,
    a.source_file,
    (select max(batch_id) from ev_staging.etl_batch where step_name = 'FACT_LOAD' and source_name = 'fact_garage_energy_hourly')
from ev_staging.clean_garage_ams a
join ev_dw.dim_date d on d.full_date = a.hour_start::date
join ev_dw.dim_time t on t.hour_number = extract(hour from a.hour_start)
left join ev_dw.dim_garage g on g.source_garage_id = a.garage_id
on conflict (date_key, time_key, garage_key, hour_occurrence) do nothing;

update ev_staging.etl_batch b
set rows_loaded = (select count(*) from ev_dw.fact_garage_energy_hourly),
    status = case when b.rows_read = (select count(*) from ev_dw.fact_garage_energy_hourly) then 'SUCCESS' else 'COUNT MISMATCH' end
where b.batch_id = (select max(batch_id) from ev_staging.etl_batch where step_name = 'FACT_LOAD' and source_name = 'fact_garage_energy_hourly');



-- checks rows per fact
select 'fact_charging_session' as fact, count(*) as rows from ev_dw.fact_charging_session
union all
select 'fact_hourly_charging_load', count(*) from ev_dw.fact_hourly_charging_load
union all
select 'fact_garage_energy_hourly', count(*) from ev_dw.fact_garage_energy_hourly;

-- source business keys next to the surrogate keys stored in the fact
select s.session_id, s.user_id, s.garage_id, s.start_ts,
    f.user_key, f.garage_key, f.start_date_key, f.start_time_key, f.end_date_key, f.energy_kwh
from ev_staging.clean_sessions s
join ev_dw.fact_charging_session f on f.source_session_id = s.session_id
order by s.session_id
limit 5;

-- log of the fact load
select batch_id, step_name, source_name, rows_read, rows_loaded, status
from ev_staging.etl_batch
where step_name = 'FACT_LOAD'
order by batch_id;
