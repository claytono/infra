-- Users. Every data row carries a user_id foreign key into this table so the
-- database can hold more than one person's HealthKit export. Created first
-- (file 000) so the data tables in 001+ can reference it.
--
-- The client sends its user_id in the X-User-ID HTTP header on every batch; the
-- ingest server tags all rows with it and upserts the richer identity fields
-- (name/email/dob/sex) from the {"profile":…} NDJSON line. The DOB/sex feed
-- derived metrics such as heart-rate zones (see web getProfile).
--
-- The default user below is seeded with a fixed id and no identity so a fresh
-- database renders immediately and the iOS app (which ships preconfigured with
-- the same id) has a valid FK target before its first profile line arrives.
-- Name, email, DOB and sex are deliberately NULL here: identity is never
-- baked into the schema, it arrives with the first {"profile":…} line the
-- app uploads. ensureUser in the ingest server re-inserts the row
-- ON CONFLICT DO NOTHING, so the seed and the client agree.
CREATE TABLE users (
    id             uuid        PRIMARY KEY,
    name           text,
    email          text,
    dob            date,
    biological_sex text,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);

INSERT INTO users (id, name, email, dob, biological_sex)
VALUES ('5ea4d000-0000-4000-8000-000000000001', NULL, NULL, NULL, NULL)
ON CONFLICT (id) DO NOTHING;
