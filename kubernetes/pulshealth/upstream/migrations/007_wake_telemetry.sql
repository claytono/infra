-- Wake telemetry on the batches log: correlate each upload with the iOS
-- background wake that produced it, so a field study can reconstruct "how often
-- did the device get background execution time, and what did each wake do".
--
-- The client sends these as HTTP headers (like X-User-ID), not in the NDJSON
-- body: X-Wake-ID (a UUID matching a device-side wake record) and
-- X-Wake-Trigger (observer | backgroundProcessing | backgroundContinued |
-- foreground | manual). parse_ms/insert_ms are server-measured timings, persisted
-- here so they survive container restarts (they were previously log-only).
--
-- Idempotent (IF NOT EXISTS): it predates the migrate service and was applied
-- by hand to live databases whose volume predated the file.

ALTER TABLE batches ADD COLUMN IF NOT EXISTS wake_id   uuid;
ALTER TABLE batches ADD COLUMN IF NOT EXISTS trigger   text;
ALTER TABLE batches ADD COLUMN IF NOT EXISTS parse_ms  int;
ALTER TABLE batches ADD COLUMN IF NOT EXISTS insert_ms int;

-- Group all of one wake's batches together (the join key to device wake records).
CREATE INDEX IF NOT EXISTS batches_wake_id_idx ON batches (wake_id) WHERE wake_id IS NOT NULL;
