-- On-device aggregated metrics (HKStatisticsCollectionQuery buckets).
-- Unlike raw samples, recomputes overwrite: ingest upserts with
-- ON CONFLICT ... DO UPDATE, and an explicit null value clears the bucket.
-- Plain tables: even 5-minute buckets are ~105k rows/series/year.
--
-- Idempotent (IF NOT EXISTS everywhere): it predates the migrate service and
-- was applied by hand to live databases whose volume predated the file.

CREATE TABLE IF NOT EXISTS aggregate_series (
    series_id      smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type_id        smallint NOT NULL REFERENCES sample_types (type_id),
    agg_func       text     NOT NULL,
    interval_value int      NOT NULL,
    interval_unit  text     NOT NULL,
    device_filter  text     NOT NULL,
    unit           text,
    UNIQUE (type_id, agg_func, interval_value, interval_unit, device_filter)
);

-- aggregate_series is shared config (user-agnostic): the same (type, func,
-- interval, deviceFilter) definition is one series row. Per-user values live in
-- aggregate_samples, so user_id is part of the bucket primary key.
CREATE TABLE IF NOT EXISTS aggregate_samples (
    series_id    smallint    NOT NULL REFERENCES aggregate_series (series_id),
    bucket_start timestamptz NOT NULL,
    bucket_end   timestamptz NOT NULL,
    value        float8,
    user_id      uuid        NOT NULL REFERENCES users (id)
                             DEFAULT '5ea4d000-0000-4000-8000-000000000001',
    updated_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (series_id, bucket_start, user_id)
);

CREATE INDEX IF NOT EXISTS aggregate_samples_series_ts_idx
    ON aggregate_samples (series_id, bucket_start DESC);

ALTER TABLE batches ADD COLUMN IF NOT EXISTS aggregate_count int;
