---------------
-- COMPLETENESS
---------------
-- nulls in session fact 
-- only sessions without plug out should have a null end and duration
select
    count(*) as fact_rows,
    count(*) filter (where start_date_key is null) as null_start_date,
    count(*) filter (where end_date_key is null) as null_end_date,
    count(*) filter (where user_key is null) as null_user,
    count(*) filter (where garage_key is null) as null_garage,
    count(*) filter (where energy_kwh is null) as null_energy,
    count(*) filter (where duration_hours is null) as null_duration
from ev_dw.fact_charging_session;

-- rows per quality flag
select 'sessions' as fact, data_quality_flag, count(*) as rows from ev_dw.fact_charging_session group by data_quality_flag
union all
select 'hourly', data_quality_flag, count(*) from ev_dw.fact_hourly_charging_load group by data_quality_flag
union all
select 'garage', data_quality_flag, count(*) from ev_dw.fact_garage_energy_hourly group by data_quality_flag
order by fact, rows desc;



-----------
-- ACCURACY
-----------
-- raw csv rows vs fact rows
select
    (select count(*) from ev_staging.raw_sessions) as source_sessions,
    (select count(*) from ev_dw.fact_charging_session) as fact_sessions,
    (select count(*) from ev_staging.raw_hourly_private) + (select count(*) from ev_staging.raw_hourly_shared) as source_hourly,
    (select count(*) from ev_dw.fact_hourly_charging_load) as fact_hourly,
    (select count(*) from ev_staging.raw_garage_ams) as source_garage,
    (select count(*) from ev_dw.fact_garage_energy_hourly) as fact_garage;

-- raw csv totals vs fact totals
select
    round((select sum(replace(el_kwh, ',', '.')::numeric) from ev_staging.raw_sessions), 2) as source_energy,
    round((select sum(energy_kwh) from ev_dw.fact_charging_session), 2) as fact_energy,
    round((select sum(replace(synthetic_3_6kw, ',', '.')::numeric) from ev_staging.raw_hourly_private)
        + (select sum(replace(synthetic_3_6kw, ',', '.')::numeric) from ev_staging.raw_hourly_shared), 2) as source_synthetic_3_6,
    round((select sum(synthetic_3_6kw) from ev_dw.fact_hourly_charging_load), 2) as fact_synthetic_3_6,
    round((select sum(replace(ams_kwh, ',', '.')::numeric) from ev_staging.raw_garage_ams where ams_kwh <> 'NA'), 2) as source_ams,
    round((select sum(measured_ams_kwh) from ev_dw.fact_garage_energy_hourly), 2) as fact_ams;



------------
-- INTEGRITY
------------
-- fact rows with no matching dimension row
select
    (select count(*) from ev_dw.fact_charging_session f
     left join ev_dw.dim_date d on d.date_key = f.start_date_key
     left join ev_dw.dim_user u on u.user_key = f.user_key
     left join ev_dw.dim_garage g on g.garage_key = f.garage_key
     where d.date_key is null or u.user_key is null or g.garage_key is null) as session_orphans,
    (select count(*) from ev_dw.fact_hourly_charging_load f
     left join ev_dw.dim_date d on d.date_key = f.date_key
     left join ev_dw.dim_charging_type c on c.charging_type_key = f.charging_type_key
     where d.date_key is null or c.charging_type_key is null) as hourly_orphans,
    (select count(*) from ev_dw.fact_garage_energy_hourly f
     left join ev_dw.dim_date d on d.date_key = f.date_key
     left join ev_dw.dim_garage g on g.garage_key = f.garage_key
     where d.date_key is null or g.garage_key is null) as garage_orphans;

-- duplicate fact rows
select
    (select count(*) - count(distinct source_session_id) from ev_dw.fact_charging_session) as session_duplicates,
    (select count(*) - count(distinct (date_key, time_key, charging_type_key, hour_occurrence)) from ev_dw.fact_hourly_charging_load) as hourly_duplicates,
    (select count(*) - count(distinct (date_key, time_key, garage_key, hour_occurrence)) from ev_dw.fact_garage_energy_hourly) as garage_duplicates;



-------------------
-- CONSTRAINT TESTS
-------------------
-- these must fail

-- user_key 999999 does not exist (foreign key)
insert into ev_dw.fact_charging_session (source_session_id, start_date_key, start_time_key, user_key, garage_key, energy_kwh, data_quality_flag)
values (999999, 20190101, 10, 999999, 1, 5, 'TEST');

-- session 1 is already loaded (unique key)
insert into ev_dw.fact_charging_session (source_session_id, start_date_key, start_time_key, user_key, garage_key, energy_kwh, data_quality_flag)
values (1, 20190101, 10, 1, 1, 5, 'TEST');

-- negative energy check constraint
insert into ev_dw.fact_charging_session (source_session_id, start_date_key, start_time_key, user_key, garage_key, energy_kwh, data_quality_flag)
values (999998, 20190101, 10, 1, 1, -5, 'TEST');	