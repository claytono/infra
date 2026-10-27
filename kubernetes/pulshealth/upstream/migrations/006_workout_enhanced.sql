-- Enhanced workouts: intra-workout quantity-series streams, richer per-type
-- statistics (min/avg/max/sum), workout events (laps/segments/pauses),
-- multi-sport sub-activities, and the user profile (DOB/sex) for HR zones.
--
-- Idempotent (IF NOT EXISTS / ADD COLUMN IF NOT EXISTS): it predates the
-- migrate service and was applied by hand to live databases whose volume
-- predated the file.

-- Intra-workout time series: heart rate, power, cadence, speed, etc. — one row
-- per datum, keyed by owning workout + quantity type. Hypertable so old chunks
-- compress like quantity_samples. Values are in the type's canonical unit.
CREATE TABLE IF NOT EXISTS workout_series_points (
    workout_uuid uuid        NOT NULL,
    type_id      smallint    NOT NULL REFERENCES sample_types (type_id),
    ts           timestamptz NOT NULL,
    value        float8      NOT NULL,
    user_id      uuid        NOT NULL REFERENCES users (id)
                             DEFAULT '5ea4d000-0000-4000-8000-000000000001',
    PRIMARY KEY (workout_uuid, type_id, ts)
);

SELECT create_hypertable('workout_series_points', 'ts',
                         chunk_time_interval => INTERVAL '1 month',
                         if_not_exists => TRUE);

CREATE INDEX IF NOT EXISTS workout_series_points_workout_idx
    ON workout_series_points (workout_uuid, type_id, ts);

-- Columnstore compression: segment by workout so the deletion cascade
-- (DELETE ... WHERE workout_uuid = ANY(...)) prunes columnstore batches.
ALTER TABLE workout_series_points SET (
    timescaledb.enable_columnstore = true,
    timescaledb.segmentby = 'workout_uuid',
    timescaledb.orderby = 'ts'
);
CALL add_columnstore_policy('workout_series_points', after => INTERVAL '30 days',
                            if_not_exists => TRUE);

-- Richer workout columns: per-type min/avg/max/sum, events, sub-activities.
ALTER TABLE workouts ADD COLUMN IF NOT EXISTS stats_detail jsonb;
ALTER TABLE workouts ADD COLUMN IF NOT EXISTS events       jsonb;
ALTER TABLE workouts ADD COLUMN IF NOT EXISTS activities   jsonb;

-- The user profile (DOB + biological sex) for derived metrics such as
-- heart-rate zones lives in the per-user `users` table (see 000_users.sql);
-- it replaced the old single-row `profile` table.
