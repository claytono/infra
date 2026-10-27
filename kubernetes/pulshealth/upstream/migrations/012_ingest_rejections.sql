-- Durable operational record of authenticated batch requests that failed before
-- they could be committed to `batches`. Container logs are ephemeral across
-- deploys, so without this table malformed payloads and insert failures vanish.

CREATE TABLE IF NOT EXISTS ingest_rejections (
    rejection_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    received_at     timestamptz NOT NULL DEFAULT now(),
    batch_id        text,
    user_id         text,
    wake_id         text,
    trigger         text,
    status          smallint NOT NULL,
    stage           text NOT NULL,
    error_message   text NOT NULL,
    bytes            bigint NOT NULL DEFAULT 0,
    content_encoding text
);

CREATE INDEX IF NOT EXISTS ingest_rejections_received_at_idx
    ON ingest_rejections (received_at DESC);

CREATE INDEX IF NOT EXISTS ingest_rejections_wake_id_idx
    ON ingest_rejections (wake_id, received_at DESC)
    WHERE wake_id IS NOT NULL;
