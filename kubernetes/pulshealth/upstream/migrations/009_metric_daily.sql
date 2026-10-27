-- puls:rerun
-- Unified daily "best guess of truth" per metric, per user (a VIEW, not a table:
-- always live, no backfill/refresh, no extra storage).
--
-- Two tiers, resolved per (type, user, day):
--   1. One canonical on-device aggregate series: sum for cumulative metrics or
--      average for discrete metrics, exactly 1 day, device_filter='all'.
--      HKStatisticsCollectionQuery applies HealthKit's cross-source dedup, so
--      this is the preferred truth. Hourly/weekly, min/max/mostRecent/duration,
--      and device-specific series never compete for the daily headline value.
--   2. Fallback for days/types not covered by tier 1: quantity_rollups, which is
--      derived from RAW samples (NOT deduped). For cumulative types that would
--      double-count across the iPhone + Watch, so pick the single highest-value
--      device that day; for discrete types take the cross-source weighted average.
--
-- Scope: types with a configured sum or average aggregate_series. Presence of
-- sum explicitly classifies the type as cumulative; otherwise average classifies
-- it as discrete. Types configured only with non-headline functions are omitted
-- instead of guessing their rollup semantics.
--
-- Day boundaries follow puls_time_zone(), i.e. the PULS_TIME_ZONE setting
-- (013_time_zone.sh stores it on the database; unset means UTC). It must
-- match the phone's zone: the on-device daily aggregates that form tier 1 are
-- computed in the phone's local calendar, and the Grafana dashboards read the
-- same function so every daily view agrees.
--
-- Idempotent (CREATE OR REPLACE) and marked `puls:rerun` on its first line:
-- the migrate service re-applies it whenever this file changes, so edit the
-- view definition here in place instead of adding a new numbered file. To
-- change the zone, set PULS_TIME_ZONE in .env and run the migrate service
-- again (013_time_zone.sh stores it; applies to new connections).

-- Include the not-yet-materialized portion of the current hour in reads from
-- quantity_rollups. Without real-time aggregation, metric_daily can lag until
-- the continuous-aggregate refresh policy completes the hour.
ALTER MATERIALIZED VIEW quantity_rollups SET (timescaledb.materialized_only = false);

-- The calendar zone every daily view/query is bucketed in. Read from the
-- puls.time_zone database setting (ALTER DATABASE … SET, written by
-- 013_time_zone.sh from PULS_TIME_ZONE); falls back to UTC when unset or
-- empty. STABLE, not IMMUTABLE: the setting can change between sessions.
-- Defined here rather than in a later file because migrations run in name
-- order and a view binds the functions it calls when it is created, so the
-- function has to exist before CREATE VIEW metric_daily below.
CREATE OR REPLACE FUNCTION puls_time_zone() RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(NULLIF(current_setting('puls.time_zone', true), ''), 'UTC')
$$;

CREATE OR REPLACE VIEW metric_daily AS
WITH type_semantics AS (
  SELECT type_id,
         CASE WHEN bool_or(agg_func = 'sum') THEN 'cumulative'
              WHEN bool_or(agg_func = 'average') THEN 'discrete' END AS semantic
  FROM aggregate_series
  GROUP BY type_id
  HAVING bool_or(agg_func IN ('sum', 'average'))
),
canonical_agg AS (
  SELECT s.type_id, b.user_id,
         (b.bucket_start AT TIME ZONE puls_time_zone())::date AS day,
         b.value,
         row_number() OVER (
           PARTITION BY s.type_id, b.user_id,
                        (b.bucket_start AT TIME ZONE puls_time_zone())::date
           ORDER BY b.updated_at DESC, b.bucket_start DESC
         ) AS preference
  FROM aggregate_samples b
  JOIN aggregate_series s USING (series_id)
  JOIN type_semantics ts USING (type_id)
  WHERE b.value IS NOT NULL
    AND s.interval_value = 1
    AND s.interval_unit = 'day'
    AND s.device_filter = 'all'
    AND ((ts.semantic = 'cumulative' AND s.agg_func = 'sum')
      OR (ts.semantic = 'discrete' AND s.agg_func = 'average'))
),
agg_daily AS (
  SELECT type_id, user_id, day, value
  FROM canonical_agg
  WHERE preference = 1
),
rollup_src AS (
  SELECT r.type_id, r.user_id, r.source_id, ts.semantic,
         (r.bucket AT TIME ZONE puls_time_zone())::date AS day,
         CASE WHEN ts.semantic = 'cumulative' THEN sum(r.sum_value)
              ELSE sum(r.avg_value * r.n) / nullif(sum(r.n), 0) END AS value,
         sum(r.n) AS n
  FROM quantity_rollups r
  JOIN type_semantics ts USING (type_id)
  GROUP BY r.type_id, r.user_id, r.source_id, ts.semantic, day
),
rollup_daily AS (
  SELECT type_id, user_id, day,
         CASE WHEN semantic = 'cumulative'
              THEN (array_agg(value ORDER BY value DESC))[1]
              ELSE sum(value * n) / nullif(sum(n), 0) END AS value
  FROM rollup_src
  GROUP BY type_id, user_id, day, semantic
)
SELECT t.identifier,
       COALESCE(a.type_id, r.type_id) AS type_id,
       COALESCE(a.user_id, r.user_id) AS user_id,
       COALESCE(a.day, r.day)         AS day,
       COALESCE(a.value, r.value)     AS value,
       CASE WHEN a.value IS NOT NULL THEN 'aggregate' ELSE 'rollup' END AS source
FROM agg_daily a
FULL JOIN rollup_daily r
  ON a.type_id = r.type_id AND a.user_id = r.user_id AND a.day = r.day
JOIN sample_types t ON t.type_id = COALESCE(a.type_id, r.type_id);

-- Read-only role grants are applied by 099_read_roles.sh after all relations
-- used by Grafana and the product API exist.

-- 008_quantity_rollups.sql drops quantity_rollups WITH CASCADE, which takes
-- this view with it, and CREATE OR REPLACE VIEW above then produces a brand-new
-- relation with no ACL. `grafana` recovers through its ALTER DEFAULT
-- PRIVILEGES, but api_reader deliberately has none (099_read_roles.sh asserts
-- an exact, non-default ACL), so re-running 008 then 009 on a live database
-- silently broke /v1/metrics/daily with permission-denied until 099 was re-run
-- by hand. Re-grant here so the documented "safe to re-run" sequence is.
-- Guarded: on a fresh database the roles do not exist yet (099 creates them,
-- and it runs after this file on every migrate run).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'api_reader') THEN
    GRANT SELECT ON metric_daily TO api_reader;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'grafana') THEN
    GRANT SELECT ON metric_daily TO grafana;
  END IF;
END
$$;
