-- Per-device bearer tokens (SRV-8). Each row is one credential the ingest
-- server accepts in Authorization: Bearer, bound to the user whose rows it may
-- write and read, revocable on its own, and recorded on every batch it uploads.
--
-- Only a SHA-256 of the token is stored. A token is 32 bytes from
-- crypto/rand, hex-encoded (64 characters, the same shape as `openssl rand
-- -hex 32` and the shared PULS_TOKEN), so the preimage is 256 random bits and
-- no salt or KDF is needed: the hash is a lookup key, not a password. The
-- plaintext is shown once by `make devices ARGS='issue …'` and never logged;
-- token_prefix keeps the first eight characters so an operator can match a
-- row to the value on a phone.
--
-- The shared PULS_TOKEN is checked in memory before this table is consulted
-- and keeps working (PULS_ALLOW_SHARED_TOKEN); a request that authenticates
-- with a device token has its X-User-ID checked against user_id. The grafana
-- role's SELECT on this table is revoked by 099_read_roles.sh.

CREATE TABLE device_tokens (
    id           bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    token_hash   bytea       NOT NULL UNIQUE CHECK (octet_length(token_hash) = 32),
    -- First 8 characters of the plaintext, for `devices list`; never enough
    -- to authenticate with.
    token_prefix text        NOT NULL,
    user_id      uuid        NOT NULL REFERENCES users(id),
    -- Operator label ("Sean's iPhone"); the CLI caps it at 100 characters.
    name         text        NOT NULL DEFAULT '',
    status       text        NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
    created_at   timestamptz NOT NULL DEFAULT now(),
    revoked_at   timestamptz,
    -- Advanced by the ingest server at most once a minute per token.
    last_seen_at timestamptz
);

CREATE INDEX device_tokens_user_idx ON device_tokens (user_id);

-- Which device wrote each batch. NULL for the shared token and for batches
-- that predate this file.
ALTER TABLE batches ADD COLUMN device_token_id bigint REFERENCES device_tokens(id);
