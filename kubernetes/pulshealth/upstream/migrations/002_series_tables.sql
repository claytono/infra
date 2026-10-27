-- PulsHealth series tables: workout routes, heartbeat series, ECG,
-- state of mind, medication dose events.
--
-- Idempotent (IF NOT EXISTS everywhere): it predates the migrate service and
-- was applied by hand to live databases whose volume predated the file.

-- GPS points from HKWorkoutRoute, keyed by owning workout. Hypertable.
CREATE TABLE IF NOT EXISTS workout_route_points (
    workout_uuid uuid        NOT NULL,
    ts           timestamptz NOT NULL,
    lat          float8      NOT NULL,
    lon          float8      NOT NULL,
    altitude_m   float8,
    h_acc_m      float8,
    v_acc_m      float8,
    speed_mps    float8,
    course_deg   float8,
    user_id      uuid        NOT NULL REFERENCES users (id)
                             DEFAULT '5ea4d000-0000-4000-8000-000000000001',
    PRIMARY KEY (workout_uuid, ts)
);

SELECT create_hypertable('workout_route_points', 'ts',
                         chunk_time_interval => INTERVAL '1 month',
                         if_not_exists => TRUE);

-- One row per HKHeartbeatSeriesSample; beats is a JSON array of
-- [secondsSinceSeriesStart, precededByGap] pairs.
CREATE TABLE IF NOT EXISTS heartbeat_series (
    uuid       uuid        PRIMARY KEY,
    start_ts   timestamptz NOT NULL,
    end_ts     timestamptz NOT NULL,
    beat_count int         NOT NULL,
    beats      jsonb       NOT NULL,
    source_id  smallint    REFERENCES sources (source_id),
    metadata   jsonb,
    user_id    uuid        NOT NULL REFERENCES users (id)
                           DEFAULT '5ea4d000-0000-4000-8000-000000000001'
);

CREATE INDEX IF NOT EXISTS heartbeat_series_start_ts_idx ON heartbeat_series (start_ts DESC);

-- One row per HKElectrocardiogram, voltages in microvolts.
CREATE TABLE IF NOT EXISTS ecg_samples (
    uuid            uuid        PRIMARY KEY,
    start_ts        timestamptz NOT NULL,
    end_ts          timestamptz NOT NULL,
    classification  text,
    average_hr_bpm  float8,
    sampling_hz     float8,
    symptoms_status text,
    voltage_uv      real[],
    source_id       smallint    REFERENCES sources (source_id),
    metadata        jsonb,
    user_id         uuid        NOT NULL REFERENCES users (id)
                                DEFAULT '5ea4d000-0000-4000-8000-000000000001'
);

CREATE INDEX IF NOT EXISTS ecg_samples_start_ts_idx ON ecg_samples (start_ts DESC);

-- HKStateOfMind (momentary emotion / daily mood) entries.
CREATE TABLE IF NOT EXISTS state_of_mind (
    uuid          uuid        PRIMARY KEY,
    start_ts      timestamptz NOT NULL,
    end_ts        timestamptz NOT NULL,
    kind          text        NOT NULL,
    valence       float8,
    valence_class text,
    labels        text[],
    associations  text[],
    source_id     smallint    REFERENCES sources (source_id),
    metadata      jsonb,
    user_id       uuid        NOT NULL REFERENCES users (id)
                              DEFAULT '5ea4d000-0000-4000-8000-000000000001'
);

CREATE INDEX IF NOT EXISTS state_of_mind_start_ts_idx ON state_of_mind (start_ts DESC);

-- HKMedicationDoseEvent (logged/skipped medication doses).
CREATE TABLE IF NOT EXISTS medication_dose_events (
    uuid          uuid        PRIMARY KEY,
    start_ts      timestamptz NOT NULL,
    end_ts        timestamptz NOT NULL,
    medication    text,
    status        text,
    scheduled_ts  timestamptz,
    dose_quantity float8,
    dose_unit     text,
    source_id     smallint    REFERENCES sources (source_id),
    metadata      jsonb,
    user_id       uuid        NOT NULL REFERENCES users (id)
                              DEFAULT '5ea4d000-0000-4000-8000-000000000001'
);

CREATE INDEX IF NOT EXISTS medication_dose_events_start_ts_idx ON medication_dose_events (start_ts DESC);
