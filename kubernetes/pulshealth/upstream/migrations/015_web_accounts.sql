-- Accounts for the web viewer, and the per-user surface its role reads.
--
-- With WEB_ACCOUNTS=true the viewer signs people in and shows each of them
-- only their own records. The database, not the viewer's WHERE clauses,
-- enforces that separation: the viewer connects as `web_app`
-- (099_read_roles.sh creates it when WEB_DB_PASSWORD is set), a role with no
-- grant on any table that holds health data. It reads them only through the
-- views in schema `web` below, each filtered on `puls_viewer_user()`, which
-- the viewer sets per transaction from the signed-in session
-- (SELECT set_config('puls.user_id', <uuid>, true)). A query that forgets its
-- `WHERE user_id = …` therefore returns that person's rows and nobody
-- else's, and a query run without the setting returns nothing.
--
-- Why views and not row-level security: TimescaleDB refuses
-- ALTER TABLE … ENABLE ROW LEVEL SECURITY on a hypertable with columnstore
-- enabled ("operation not supported on hypertables that have columnstore
-- enabled"), and quantity_samples and workout_series_points are compressed
-- on every install. A security-barrier view gives the same guarantee for one
-- role without touching the tables, so Grafana, the product API and ingest
-- read and write exactly as before.
--
-- Nothing here changes behaviour until an operator turns accounts on: Basic
-- mode keeps connecting as `grafana` and never touches either schema.
-- See web/README.md, "Access control".

-- ── accounts ────────────────────────────────────────────────────────────────
-- Account identity lives here, never in `users`: users.name and users.email
-- are the phone's HealthKit profile, overwritten by every {"profile":…} line.
-- One account per user; the account's email is its sign-in name.
CREATE SCHEMA auth;
REVOKE ALL ON SCHEMA auth FROM PUBLIC;

CREATE TABLE auth.accounts (
    id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid        NOT NULL UNIQUE REFERENCES users (id),
    -- Normalised by the viewer (trimmed, lower-cased) before it gets here;
    -- the CHECK keeps a hand-written INSERT from creating a second spelling
    -- of the same address that the UNIQUE constraint would not catch.
    email               text        NOT NULL UNIQUE
                                    CHECK (email = lower(btrim(email)) AND email <> ''),
    -- scrypt$N$r$p$<salt>$<hash> (web/lib/accounts/password.ts). NULL only
    -- for an account whose sign-in has been withdrawn by an operator.
    password_hash       text,
    is_admin            boolean     NOT NULL DEFAULT false,
    created_at          timestamptz NOT NULL DEFAULT now(),
    password_changed_at timestamptz,
    -- Set to stop an account signing in without deleting it; its sessions
    -- stop working on their next request.
    disabled_at         timestamptz
);

-- One row per signed-in browser. The cookie carries 32 random bytes; only
-- their SHA-256 is stored, so a copy of this table signs nobody in (the same
-- rule as device_tokens: the preimage is 256 random bits, so no salt or KDF).
CREATE TABLE auth.sessions (
    id           bytea       PRIMARY KEY CHECK (octet_length(id) = 32),
    account_id   uuid        NOT NULL REFERENCES auth.accounts (id) ON DELETE CASCADE,
    created_at   timestamptz NOT NULL DEFAULT now(),
    expires_at   timestamptz NOT NULL,
    -- Advanced at most once an hour per session (sliding expiry).
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    -- Shown on the account page so a person can tell their sessions apart.
    user_agent   text,
    ip           inet
);
CREATE INDEX sessions_account_idx ON auth.sessions (account_id);
CREATE INDEX sessions_expires_idx ON auth.sessions (expires_at);

-- One-time links that create an account (or reset an existing account's
-- password). Issued by an operator with `make web-invite`; the plaintext
-- token appears once, in the printed URL, and only its SHA-256 is kept.
CREATE TABLE auth.invites (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    token_hash  bytea       NOT NULL UNIQUE CHECK (octet_length(token_hash) = 32),
    user_id     uuid        NOT NULL REFERENCES users (id),
    email       text        NOT NULL CHECK (email = lower(btrim(email)) AND email <> ''),
    is_admin    boolean     NOT NULL DEFAULT false,
    -- NULL when issued from the command line rather than by an account.
    created_by  uuid        REFERENCES auth.accounts (id) ON DELETE SET NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    expires_at  timestamptz NOT NULL,
    accepted_at timestamptz
);
CREATE INDEX invites_user_idx ON auth.invites (user_id);

-- ── the viewer's user ───────────────────────────────────────────────────────
-- The user the current transaction may read: the transaction-local setting
-- the viewer writes from its session, or NULL when nothing set it (a
-- placeholder setting reads as '' once any transaction in the session has
-- used it, hence the nullif). NULL matches no row.
-- PARALLEL SAFE: parallel workers inherit the transaction's settings, and
-- without the label no query that touches the views could run in parallel.
CREATE FUNCTION puls_viewer_user() RETURNS uuid
LANGUAGE sql STABLE PARALLEL SAFE AS $$
  SELECT nullif(current_setting('puls.user_id', true), '')::uuid
$$;

-- ── the per-user surface ────────────────────────────────────────────────────
-- One view per relation the viewer reads, named like the relation, so the
-- role's search_path (web, public — set by 099_read_roles.sh) resolves the
-- viewer's unqualified SQL to these for web_app and to the tables for
-- grafana. Owned by the migrating superuser, so they read the tables with
-- its rights; web_app gets SELECT on the views and on nothing beneath them.
--
-- security_barrier keeps a caller's own predicates from being evaluated
-- before the user filter (a leaky function could otherwise see filtered-out
-- rows). The filter compares against a sub-SELECT so the setting is read once
-- per query (an InitPlan, handed to parallel workers) rather than once per
-- row; chunk exclusion and the tables' indexes still apply, compressed
-- chunks included.
--
-- The views are made by a function rather than written out here, and
-- 099_read_roles.sh calls it on every migrate run, just before it grants
-- web_app SELECT on them. Rebuilding quantity_rollups (008, documented as
-- re-runnable) drops metric_daily and, by CASCADE, web.metric_daily with it;
-- a base table that gains, loses or retypes a column needs its `SELECT *`
-- view rebuilt. Both repair themselves on the next `docker compose up -d`
-- instead of failing it. A change to the set of views or their filters is a
-- new migration that replaces this function, plus the GRANT and expected
-- rows in 099_read_roles.sh, whose assertion fails the run on any relation
-- in `web` it does not expect.
CREATE SCHEMA web;
REVOKE ALL ON SCHEMA web FROM PUBLIC;

CREATE FUNCTION puls_create_web_views() RETURNS void
LANGUAGE plpgsql AS $fn$
BEGIN
  -- No CASCADE: something unexpected that depends on these should stop the
  -- run loudly, not vanish with them.
  DROP VIEW IF EXISTS web.users, web.quantity_samples, web.category_samples,
    web.workouts, web.sources, web.workout_route_points, web.workout_series_points,
    web.activity_summaries, web.metric_daily;

  CREATE VIEW web.users WITH (security_barrier) AS
    SELECT * FROM public.users WHERE id = (SELECT puls_viewer_user());

  CREATE VIEW web.quantity_samples WITH (security_barrier) AS
    SELECT * FROM public.quantity_samples WHERE user_id = (SELECT puls_viewer_user());

  CREATE VIEW web.category_samples WITH (security_barrier) AS
    SELECT * FROM public.category_samples WHERE user_id = (SELECT puls_viewer_user());

  CREATE VIEW web.workouts WITH (security_barrier) AS
    SELECT * FROM public.workouts WHERE user_id = (SELECT puls_viewer_user());

  -- `sources` has no user_id, but it is not a neutral lookup: its names are
  -- device names ("<name>'s Apple Watch") and its bundle ids name the apps
  -- someone uses, for everyone on the server. The viewer only joins it for a
  -- workout's source, so only the sources the viewer's own workouts name.
  -- (sample_types stays a plain grant: it is the list of HealthKit
  -- identifiers seen on this server, and the viewer's queries join it by
  -- identifier.)
  CREATE VIEW web.sources WITH (security_barrier) AS
    SELECT s.* FROM public.sources s
     WHERE EXISTS (SELECT 1 FROM public.workouts w
                    WHERE w.source_id = s.source_id
                      AND w.user_id = (SELECT puls_viewer_user()));

  CREATE VIEW web.workout_route_points WITH (security_barrier) AS
    SELECT * FROM public.workout_route_points WHERE user_id = (SELECT puls_viewer_user());

  CREATE VIEW web.workout_series_points WITH (security_barrier) AS
    SELECT * FROM public.workout_series_points WHERE user_id = (SELECT puls_viewer_user());

  CREATE VIEW web.activity_summaries WITH (security_barrier) AS
    SELECT * FROM public.activity_summaries WHERE user_id = (SELECT puls_viewer_user());

  -- metric_daily (009) reads the quantity_rollups continuous aggregate, which
  -- cannot be filtered per role any other way. 009 is re-runnable and
  -- replaces its view in place (CREATE OR REPLACE); that keeps working under
  -- this one while its column list only grows. A 009 change that drops or
  -- retypes a column has to DROP VIEW IF EXISTS web.metric_daily first (the
  -- next 099 run recreates it).
  CREATE VIEW web.metric_daily WITH (security_barrier) AS
    SELECT * FROM public.metric_daily WHERE user_id = (SELECT puls_viewer_user());
END
$fn$;
REVOKE ALL ON FUNCTION puls_create_web_views() FROM PUBLIC;

SELECT puls_create_web_views();
