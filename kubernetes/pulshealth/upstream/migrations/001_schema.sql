-- PulsHealth base schema. Applied once by the `migrate` service (db/migrate.sh)
-- and recorded in schema_migrations; later changes go in new numbered files.

CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Lazily populated from ingest on first sight of each HealthKit identifier.
CREATE TABLE sample_types (
    type_id    smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    identifier text NOT NULL UNIQUE,
    kind       text,
    unit       text
);

-- Lazily populated; NULL source fields are normalized to '' by the ingest
-- server so the unique constraint deduplicates correctly.
CREATE TABLE sources (
    source_id smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name      text NOT NULL DEFAULT '',
    bundle_id text NOT NULL DEFAULT '',
    version   text NOT NULL DEFAULT '',
    UNIQUE (name, bundle_id, version)
);

-- High-volume numeric samples (heart rate, steps, energy, ...). Hypertable.
CREATE TABLE quantity_samples (
    uuid      uuid        NOT NULL,
    type_id   smallint    NOT NULL REFERENCES sample_types (type_id),
    start_ts  timestamptz NOT NULL,
    end_ts    timestamptz NOT NULL,
    value     float8,
    source_id smallint    REFERENCES sources (source_id),
    metadata  jsonb,
    user_id   uuid        NOT NULL REFERENCES users (id)
                          DEFAULT '5ea4d000-0000-4000-8000-000000000001',
    PRIMARY KEY (uuid, start_ts)
);

SELECT create_hypertable('quantity_samples', 'start_ts',
                         chunk_time_interval => INTERVAL '1 month');

CREATE INDEX quantity_samples_type_ts_idx ON quantity_samples (type_id, start_ts DESC);
CREATE INDEX quantity_samples_uuid_idx ON quantity_samples (uuid);

-- Columnstore compression: segment by type, order by time; compress chunks
-- older than 30 days.
ALTER TABLE quantity_samples SET (
    timescaledb.enable_columnstore = true,
    timescaledb.segmentby = 'type_id',
    timescaledb.orderby = 'start_ts'
);
CALL add_columnstore_policy('quantity_samples', after => INTERVAL '30 days');

-- Lower-volume enum-like samples (sleep stages, mindfulness, ...).
CREATE TABLE category_samples (
    uuid      uuid        PRIMARY KEY,
    type_id   smallint    NOT NULL REFERENCES sample_types (type_id),
    start_ts  timestamptz NOT NULL,
    end_ts    timestamptz NOT NULL,
    value     smallint    NOT NULL,
    source_id smallint    REFERENCES sources (source_id),
    metadata  jsonb,
    user_id   uuid        NOT NULL REFERENCES users (id)
                          DEFAULT '5ea4d000-0000-4000-8000-000000000001'
);

CREATE INDEX category_samples_type_ts_idx ON category_samples (type_id, start_ts DESC);

CREATE TABLE workouts (
    uuid          uuid        PRIMARY KEY,
    activity_type text        NOT NULL,
    start_ts      timestamptz NOT NULL,
    end_ts        timestamptz NOT NULL,
    duration_s    float8,
    energy_kcal   float8,
    distance_m    float8,
    stats         jsonb,
    source_id     smallint    REFERENCES sources (source_id),
    metadata      jsonb,
    user_id       uuid        NOT NULL REFERENCES users (id)
                              DEFAULT '5ea4d000-0000-4000-8000-000000000001'
);

CREATE INDEX workouts_start_ts_idx ON workouts (start_ts DESC);

-- Tombstones from HKAnchoredObjectQuery deletions.
CREATE TABLE deleted_samples (
    uuid            uuid PRIMARY KEY,
    type_identifier text NOT NULL,
    user_id         uuid NOT NULL REFERENCES users (id)
                         DEFAULT '5ea4d000-0000-4000-8000-000000000001',
    deleted_at      timestamptz NOT NULL DEFAULT now()
);

-- One row per received batch; batch_id PK makes client retries observable.
CREATE TABLE batches (
    batch_id        uuid PRIMARY KEY,
    device_id       text,
    user_id         uuid,
    type_identifier text,
    reason          text,
    sample_count    int,
    deletion_count  int,
    bytes           int,
    exported_at     timestamptz,
    received_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX batches_received_at_idx ON batches (received_at DESC);
CREATE INDEX batches_type_idx ON batches (type_identifier, received_at DESC);

-- Hourly rollup of quantity_samples used by Grafana for multi-year panels.
-- Split by source (device) AND user: each row is one source's rollup for one
-- user. This lets readers pick a single source per bucket instead of summing
-- overlapping multi-device samples (iPhone + Watch both log steps -> double
-- counting). Discrete types (avg) may still blend sources via a weighted mean.
CREATE MATERIALIZED VIEW quantity_rollups
WITH (timescaledb.continuous) AS
SELECT type_id,
       source_id,
       user_id,
       time_bucket('1 hour', start_ts) AS bucket,
       sum(value)  AS sum_value,
       avg(value)  AS avg_value,
       min(value)  AS min_value,
       max(value)  AS max_value,
       count(*)    AS n
FROM quantity_samples
GROUP BY type_id, source_id, user_id, bucket
WITH NO DATA;

-- start_offset => NULL refreshes the whole range, which matters for
-- multi-year backfills arriving long after the fact.
SELECT add_continuous_aggregate_policy('quantity_rollups',
    start_offset      => NULL,
    end_offset        => INTERVAL '1 hour',
    schedule_interval => INTERVAL '30 minutes');
