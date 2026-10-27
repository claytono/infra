-- Temporal context for reconstructing local wall time.
--
-- UTC instants remain stored in timestamptz columns. These nullable foreign keys
-- capture the IANA timezone ID, UTC offset at that instant, and provenance for
-- rows whose local time needs to be reconstructed later. Existing rows and old
-- clients remain valid; new clients populate context where it is available or
-- inferred.
--
-- The referencing columns are plain nullable integers rather than FK-constrained
-- columns because TimescaleDB rejects adding constrained columns to some
-- hypertables once columnstore is enabled.

CREATE TABLE IF NOT EXISTS temporal_contexts (
    temporal_context_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    time_zone_id        text    NOT NULL,
    utc_offset_seconds  integer NOT NULL,
    source              text    NOT NULL,
    confidence          text    NOT NULL,
    tzdb_version        text    NOT NULL DEFAULT '',
    CHECK (utc_offset_seconds BETWEEN -86400 AND 86400),
    UNIQUE (time_zone_id, utc_offset_seconds, source, confidence, tzdb_version)
);

ALTER TABLE quantity_samples
    ADD COLUMN IF NOT EXISTS start_temporal_context_id integer,
    ADD COLUMN IF NOT EXISTS end_temporal_context_id   integer;

ALTER TABLE category_samples
    ADD COLUMN IF NOT EXISTS start_temporal_context_id integer,
    ADD COLUMN IF NOT EXISTS end_temporal_context_id   integer;

ALTER TABLE workouts
    ADD COLUMN IF NOT EXISTS start_temporal_context_id integer,
    ADD COLUMN IF NOT EXISTS end_temporal_context_id   integer;

ALTER TABLE heartbeat_series
    ADD COLUMN IF NOT EXISTS start_temporal_context_id integer,
    ADD COLUMN IF NOT EXISTS end_temporal_context_id   integer;

ALTER TABLE ecg_samples
    ADD COLUMN IF NOT EXISTS start_temporal_context_id integer,
    ADD COLUMN IF NOT EXISTS end_temporal_context_id   integer;

ALTER TABLE state_of_mind
    ADD COLUMN IF NOT EXISTS start_temporal_context_id integer,
    ADD COLUMN IF NOT EXISTS end_temporal_context_id   integer;

ALTER TABLE medication_dose_events
    ADD COLUMN IF NOT EXISTS start_temporal_context_id     integer,
    ADD COLUMN IF NOT EXISTS end_temporal_context_id       integer,
    ADD COLUMN IF NOT EXISTS scheduled_temporal_context_id integer;

ALTER TABLE workout_route_points
    ADD COLUMN IF NOT EXISTS temporal_context_id integer;

ALTER TABLE workout_series_points
    ADD COLUMN IF NOT EXISTS temporal_context_id integer;

ALTER TABLE aggregate_samples
    ADD COLUMN IF NOT EXISTS bucket_start_temporal_context_id integer,
    ADD COLUMN IF NOT EXISTS bucket_end_temporal_context_id   integer;

ALTER TABLE activity_summaries
    ADD COLUMN IF NOT EXISTS temporal_context_id integer;
