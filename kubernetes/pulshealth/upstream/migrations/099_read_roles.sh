#!/bin/bash
# Creates/updates the scoped database roles with passwords taken from
# environment variables (see docker-compose.yml / .env):
#
#   grafana     read-only; Grafana datasource + web viewer   GRAFANA_DB_PASSWORD (required)
#               (SELECT on every table except device_tokens, which holds
#               credential hashes and is revoked on every run)
#   api_reader  read-only; product API, exact SELECT set     API_DB_PASSWORD     (required)
#   ingest      writer for the ingest server: an exact list  INGEST_DB_PASSWORD  (see below)
#               of the tables server/ingest uses, and on
#               each only the privileges it uses
#   web_app     the web viewer in accounts mode: reads health WEB_DB_PASSWORD     (optional)
#               data only through the per-user views in schema
#               `web` (015_web_accounts.sql), and keeps the
#               viewer's accounts in schema `auth`
#
# The migrate service (db/migrate.sh) runs this script on every invocation,
# i.e. on every `docker compose up -d`, with all three passwords from .env —
# Compose requires INGEST_DB_PASSWORD, and the ingest service connects as the
# `ingest` role by default. It is safe to rerun: it creates missing roles,
# rotates passwords to the current .env values and re-applies the exact
# grants, so rotating a database password is "edit .env, docker compose up -d".
#
# INGEST_DB_PASSWORD is only optional when the script is run by hand outside
# Compose: unset, it skips the ingest role and says so. WEB_DB_PASSWORD is
# optional everywhere: only the web viewer's accounts mode (WEB_ACCOUNTS=true)
# connects as web_app, so unset, the role is not created, and an existing one
# is set NOLOGIN so a password from before stops working. Connection comes from
# PGHOST/PGPORT/PGPASSWORD in the environment (set by migrate.sh);
# POSTGRES_USER / POSTGRES_DB default to postgres/postgres.
set -euo pipefail

: "${GRAFANA_DB_PASSWORD:?GRAFANA_DB_PASSWORD must be set}"
: "${API_DB_PASSWORD:?API_DB_PASSWORD must be set}"
INGEST_DB_PASSWORD="${INGEST_DB_PASSWORD:-}"
WEB_DB_PASSWORD="${WEB_DB_PASSWORD:-}"

# The placeholder in .env.example must never become a real role password (the
# Go services refuse a token of change-me the same way). scripts/bootstrap.sh
# generates every secret; by hand it is `openssl rand -hex 32`.
for name in GRAFANA_DB_PASSWORD API_DB_PASSWORD INGEST_DB_PASSWORD WEB_DB_PASSWORD; do
  if [[ ${!name} == change-me ]]; then
    echo "099_read_roles.sh: $name is still 'change-me' in server/.env; set it (openssl rand -hex 32) or delete .env and run scripts/bootstrap.sh" >&2
    exit 1
  fi
done

POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-postgres}"

psql -q -v ON_ERROR_STOP=1 \
     -v grafana_password="${GRAFANA_DB_PASSWORD}" \
     -v api_password="${API_DB_PASSWORD}" \
     --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'EOSQL'
BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'grafana') THEN
    CREATE ROLE grafana LOGIN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'api_reader') THEN
    CREATE ROLE api_reader LOGIN;
  END IF;
END
$$;

ALTER ROLE grafana LOGIN PASSWORD :'grafana_password';

-- Refuse to automate through unexpected ownership: DROP OWNED would delete
-- objects owned by this role. With ownership proven absent, it is the safest
-- way to clear every direct grant, including privileges added in new schemas.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_shdepend
    WHERE refclassid = 'pg_authid'::regclass
      AND refobjid = (SELECT oid FROM pg_roles WHERE rolname = 'api_reader')
      AND deptype = 'o'
  ) THEN
    RAISE EXCEPTION 'api_reader owns database objects; refusing automatic reconciliation';
  END IF;
END
$$;

DO $$
DECLARE
  membership record;
BEGIN
  FOR membership IN
    SELECT parent.rolname
    FROM pg_auth_members m
    JOIN pg_roles parent ON parent.oid = m.roleid
    WHERE m.member = (SELECT oid FROM pg_roles WHERE rolname = 'api_reader')
  LOOP
    EXECUTE format('REVOKE %I FROM api_reader', membership.rolname);
  END LOOP;

  FOR membership IN
    SELECT child.rolname
    FROM pg_auth_members m
    JOIN pg_roles child ON child.oid = m.member
    WHERE m.roleid = (SELECT oid FROM pg_roles WHERE rolname = 'api_reader')
  LOOP
    EXECUTE format('REVOKE api_reader FROM %I', membership.rolname);
  END LOOP;
END
$$;

DROP OWNED BY api_reader;
ALTER ROLE api_reader
  LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION
  NOBYPASSRLS CONNECTION LIMIT -1 VALID UNTIL 'infinity'
  PASSWORD :'api_password';
ALTER ROLE api_reader RESET ALL;
ALTER ROLE api_reader IN DATABASE :"DBNAME" RESET ALL;

GRANT CONNECT ON DATABASE :"DBNAME" TO grafana;
GRANT CONNECT ON DATABASE :"DBNAME" TO api_reader;
GRANT USAGE ON SCHEMA public TO grafana;
GRANT USAGE ON SCHEMA public TO api_reader;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO grafana;

-- pg_sequences.last_value silently reads NULL for sequences the role cannot
-- select, so the "Lookup sequence near exhaustion" alert would evaluate to 0
-- and never fire — the exact blind spot behind the 2026-08-13 outage. SELECT
-- on a sequence exposes only its current value; it grants no ability to
-- advance it (that needs UPDATE/USAGE).
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO grafana;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO grafana;

-- Continuous aggregates live in materialized hypertables under the
-- _timescaledb_internal schema; Grafana queries the user-facing view, which
-- needs read access to the backing objects.
GRANT USAGE ON SCHEMA _timescaledb_internal TO grafana;
GRANT SELECT ON ALL TABLES IN SCHEMA _timescaledb_internal TO grafana;
ALTER DEFAULT PRIVILEGES IN SCHEMA _timescaledb_internal GRANT SELECT ON TABLES TO grafana;

-- device_tokens (014) holds credential hashes and per-device labels: nothing
-- a dashboard or the web viewer needs, and the one table a read-only role
-- must not hand to a dashboard editor. The blanket grant above and the
-- default privileges cover it, so revoke it here — on every run, because
-- the ALTER DEFAULT PRIVILEGES line re-grants it on a fresh install where
-- 014 is applied in the same migrate run that created the role. Guarded so
-- a baseline run on a database that predates 014 does not fail.
DO $$
BEGIN
  IF to_regclass('public.device_tokens') IS NOT NULL THEN
    REVOKE ALL ON TABLE device_tokens FROM grafana;
  END IF;
END
$$;

-- The web viewer's account store (schema auth, 015) holds password hashes
-- and session ids: nothing a dashboard needs. grafana's blanket grants and
-- default privileges name schema public only, so it never gets them; revoke
-- anyway, on every run, so a hand-made grant cannot linger, and prove it.
-- Guarded like device_tokens for a baseline run before 015.
DO $$
BEGIN
  IF to_regnamespace('auth') IS NOT NULL THEN
    REVOKE ALL ON SCHEMA auth FROM grafana;
    REVOKE ALL ON ALL TABLES IN SCHEMA auth FROM grafana;
    IF EXISTS (
      SELECT 1 FROM pg_class c
      WHERE c.relnamespace = 'auth'::regnamespace
        AND (has_table_privilege('grafana', c.oid, 'SELECT')
             OR has_any_column_privilege('grafana', c.oid, 'SELECT'))
    ) THEN
      RAISE EXCEPTION 'grafana can read a table in schema auth';
    END IF;
  END IF;
END
$$;

-- Keep product API credentials scoped to the exact current query surface.
-- `sources` names the device or app behind a raw sample and `category_labels`
-- decodes a category sample's integer value; both joined by /v1/samples and
-- /v1/sleep/daily. `batches` is the upload log /v1/users aggregates per user
-- (last sync, batch and sample counts); it holds no credential — the token
-- that wrote a batch is only an integer id into device_tokens, which stays
-- off this list. An install created before those endpoints picks the tables
-- up on its next migrate run, because this file runs every time.
GRANT SELECT ON TABLE
  users,
  batches,
  sources,
  sample_types,
  category_labels,
  quantity_samples,
  category_samples,
  workouts,
  heartbeat_series,
  ecg_samples,
  state_of_mind,
  medication_dose_events,
  activity_summaries,
  aggregate_series,
  aggregate_samples,
  metric_daily,
  workout_route_points,
  workout_series_points
TO api_reader;

-- Prove the direct ACL and role configuration are exact before committing.
-- PUBLIC grants from extensions may still be effective; this assertion makes
-- sure api_reader itself never receives extra privileges.
DO $$
DECLARE
  api_oid oid := (SELECT oid FROM pg_roles WHERE rolname = 'api_reader');
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles
    WHERE oid = api_oid
      AND rolcanlogin
      AND NOT rolsuper
      AND NOT rolinherit
      AND NOT rolcreaterole
      AND NOT rolcreatedb
      AND NOT rolreplication
      AND NOT rolbypassrls
      AND rolconnlimit = -1
      AND rolconfig IS NULL
  ) THEN
    RAISE EXCEPTION 'api_reader role attributes are not exact';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_auth_members WHERE roleid = api_oid OR member = api_oid
  ) OR EXISTS (
    SELECT 1 FROM pg_shdepend
    WHERE refclassid = 'pg_authid'::regclass
      AND refobjid = api_oid
      AND deptype = 'o'
  ) OR EXISTS (
    SELECT 1 FROM pg_db_role_setting WHERE setrole = api_oid
  ) THEN
    RAISE EXCEPTION 'api_reader has memberships, ownership, or database settings';
  END IF;

  IF EXISTS (
    WITH expected_public(nspname, relname, privilege_type, is_grantable) AS (VALUES
      ('public', 'users', 'SELECT', false),
      ('public', 'batches', 'SELECT', false),
      ('public', 'sources', 'SELECT', false),
      ('public', 'sample_types', 'SELECT', false),
      ('public', 'category_labels', 'SELECT', false),
      ('public', 'quantity_samples', 'SELECT', false),
      ('public', 'category_samples', 'SELECT', false),
      ('public', 'workouts', 'SELECT', false),
      ('public', 'heartbeat_series', 'SELECT', false),
      ('public', 'ecg_samples', 'SELECT', false),
      ('public', 'state_of_mind', 'SELECT', false),
      ('public', 'medication_dose_events', 'SELECT', false),
      ('public', 'activity_summaries', 'SELECT', false),
      ('public', 'aggregate_series', 'SELECT', false),
      ('public', 'aggregate_samples', 'SELECT', false),
      ('public', 'metric_daily', 'SELECT', false),
      ('public', 'workout_route_points', 'SELECT', false),
      ('public', 'workout_series_points', 'SELECT', false)
    ), allowed_hypertables(hypertable_schema, hypertable_name) AS (VALUES
      ('public', 'quantity_samples'),
      ('public', 'workout_route_points'),
      ('public', 'workout_series_points')
    ),
    -- TimescaleDB copies a hypertable's ACL onto the relations that store
    -- it, so api_reader must hold exactly SELECT on each of them and on
    -- nothing else in _timescaledb_internal. They are named through public,
    -- version-stable catalogs only — _timescaledb_catalog's layout changed
    -- between 2.27 and 2.29 and broke the previous version of this check.
    -- Two kinds of relation:
    --   1. chunks, listed by timescaledb_information.chunks;
    --   2. columnstore storage: the table holding a chunk's compressed rows
    --      (2.29: <chunk>_compressed; up to 2.28: compress_hyper_N_M_chunk
    --      under a _compressed_hypertable_N parent — an upgraded database
    --      keeps the old-style chunks, with their grants, next to new-style
    --      ones). No public view names these, so they are recognised by a
    --      structure that has been stable since compression shipped: a
    --      table in _timescaledb_internal carrying TimescaleDB's _ts_meta_*
    --      bookkeeping columns whose remaining columns are exactly the
    --      column set of one allowed hypertable. (A future hypertable with
    --      an identical column set that api_reader may not read would make
    --      this check fail loudly rather than pass silently.)
    allowed_chunks(nspname, relname) AS (
      SELECT ch.chunk_schema::text, ch.chunk_name::text
      FROM timescaledb_information.chunks ch
      JOIN allowed_hypertables ah
        ON ah.hypertable_schema = ch.hypertable_schema::text
       AND ah.hypertable_name = ch.hypertable_name::text
    ), allowed_column_sets(cols) AS (
      SELECT array_agg(a.attname::text ORDER BY a.attname)
      FROM allowed_hypertables ah
      JOIN pg_class h
        ON h.oid = format('%I.%I', ah.hypertable_schema, ah.hypertable_name)::regclass
      JOIN pg_attribute a
        ON a.attrelid = h.oid AND a.attnum > 0 AND NOT a.attisdropped
      GROUP BY h.oid
    ), allowed_columnstore(nspname, relname) AS (
      SELECT n.nspname::text, c.relname::text
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = '_timescaledb_internal'
        AND c.relkind = 'r'
        AND EXISTS (SELECT 1 FROM pg_attribute a
                    WHERE a.attrelid = c.oid AND a.attname = '_ts_meta_count')
        AND (SELECT array_agg(a.attname::text ORDER BY a.attname)
             FROM pg_attribute a
             WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
               AND a.attname NOT LIKE '\_ts\_meta\_%')
            IN (SELECT cols FROM allowed_column_sets)
    ), managed_relations(nspname, relname, privilege_type, is_grantable) AS (
      SELECT nspname, relname, 'SELECT', false FROM allowed_chunks
      UNION
      SELECT nspname, relname, 'SELECT', false FROM allowed_columnstore
    ), expected AS (
      SELECT * FROM expected_public
      UNION
      SELECT * FROM managed_relations
    ), actual AS (
      SELECT n.nspname, c.relname, acl.privilege_type, acl.is_grantable
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      CROSS JOIN LATERAL aclexplode(c.relacl) acl
      WHERE acl.grantee = api_oid
        -- Up to TimescaleDB 2.28 a compressed hypertable also had a
        -- column-less parent table (_compressed_hypertable_N) that the grant
        -- hook copied the ACL to. It stores nothing (each compressed chunk
        -- carries its own columns), nothing public ties it to its
        -- hypertable, and the 2.29 extension update drops it — so
        -- non-grantable SELECT on such a table is tolerated, not required.
        AND NOT (n.nspname = '_timescaledb_internal'
                 AND c.relkind = 'r'
                 AND acl.privilege_type = 'SELECT'
                 AND NOT acl.is_grantable
                 AND NOT EXISTS (SELECT 1 FROM pg_attribute a
                                 WHERE a.attrelid = c.oid AND a.attnum > 0
                                   AND NOT a.attisdropped))
    )
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ) THEN
    RAISE EXCEPTION 'api_reader relation ACL set is not exact';
  END IF;

  IF EXISTS (
    WITH expected(nspname, privilege_type, is_grantable) AS (
      VALUES ('public', 'USAGE', false)
    ), actual AS (
      SELECT n.nspname, acl.privilege_type, acl.is_grantable
      FROM pg_namespace n
      CROSS JOIN LATERAL aclexplode(n.nspacl) acl
      WHERE acl.grantee = api_oid
    )
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ) THEN
    RAISE EXCEPTION 'api_reader schema ACL set is not exact';
  END IF;

  IF EXISTS (
    WITH expected(datname, privilege_type, is_grantable) AS (
      VALUES (current_database(), 'CONNECT', false)
    ), actual AS (
      SELECT d.datname, acl.privilege_type, acl.is_grantable
      FROM pg_database d
      CROSS JOIN LATERAL aclexplode(d.datacl) acl
      WHERE acl.grantee = api_oid
    )
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ) THEN
    RAISE EXCEPTION 'api_reader database ACL set is not exact';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_attribute a
    CROSS JOIN LATERAL aclexplode(a.attacl) acl
    WHERE acl.grantee = api_oid
  ) OR EXISTS (
    SELECT 1 FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(p.proacl) acl
    WHERE acl.grantee = api_oid
  ) OR EXISTS (
    SELECT 1 FROM pg_type t
    CROSS JOIN LATERAL aclexplode(t.typacl) acl
    WHERE acl.grantee = api_oid
  ) OR EXISTS (
    SELECT 1 FROM pg_default_acl d
    CROSS JOIN LATERAL aclexplode(d.defaclacl) acl
    WHERE acl.grantee = api_oid
  ) THEN
    RAISE EXCEPTION 'api_reader has unexpected column, function, type, or default ACLs';
  END IF;
END
$$;

COMMIT;
EOSQL

# ---------------------------------------------------------------------------
# ingest: the scoped writer the ingest server connects as once opted in.
# ---------------------------------------------------------------------------
if [[ -z "$INGEST_DB_PASSWORD" ]]; then
  echo "099_read_roles: INGEST_DB_PASSWORD is not set; skipping the ingest role." \
       "The Compose stack always sets it (the ingest service connects as ingest);" \
       "re-run with INGEST_DB_PASSWORD exported to create or rotate the role."
else
psql -q -v ON_ERROR_STOP=1 \
     -v ingest_password="${INGEST_DB_PASSWORD}" \
     --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'EOSQL'
BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ingest') THEN
    CREATE ROLE ingest LOGIN;
  END IF;
END
$$;

-- Same reconciliation as api_reader: refuse to continue if the role owns
-- anything (DROP OWNED would delete it), strip memberships, then DROP OWNED to
-- clear every direct grant and default privilege before re-applying the exact
-- set below. DROP OWNED also removes the role from every TimescaleDB chunk ACL
-- the earlier grants propagated to.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_shdepend
    WHERE refclassid = 'pg_authid'::regclass
      AND refobjid = (SELECT oid FROM pg_roles WHERE rolname = 'ingest')
      AND deptype = 'o'
  ) THEN
    RAISE EXCEPTION 'ingest owns database objects; refusing automatic reconciliation';
  END IF;
END
$$;

DO $$
DECLARE
  membership record;
BEGIN
  FOR membership IN
    SELECT parent.rolname
    FROM pg_auth_members m
    JOIN pg_roles parent ON parent.oid = m.roleid
    WHERE m.member = (SELECT oid FROM pg_roles WHERE rolname = 'ingest')
  LOOP
    EXECUTE format('REVOKE %I FROM ingest', membership.rolname);
  END LOOP;

  FOR membership IN
    SELECT child.rolname
    FROM pg_auth_members m
    JOIN pg_roles child ON child.oid = m.member
    WHERE m.roleid = (SELECT oid FROM pg_roles WHERE rolname = 'ingest')
  LOOP
    EXECUTE format('REVOKE ingest FROM %I', membership.rolname);
  END LOOP;
END
$$;

DROP OWNED BY ingest;
ALTER ROLE ingest
  LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION
  NOBYPASSRLS CONNECTION LIMIT -1 VALID UNTIL 'infinity'
  PASSWORD :'ingest_password';
ALTER ROLE ingest RESET ALL;
ALTER ROLE ingest IN DATABASE :"DBNAME" RESET ALL;

-- Exactly the tables, and on each exactly the privileges, the ingest server
-- uses (server/ingest: store.go for batches and the read endpoints,
-- devices.go for per-device tokens). The `ingest devices` CLI (`make
-- devices`, `make issue-device`) runs as this role too, so its writes are
-- here: issue = INSERT, revoke and rename = UPDATE — there is no DELETE on
-- device_tokens. SELECT goes with every table written, because an UPDATE or
-- DELETE reads its WHERE columns, ON CONFLICT DO UPDATE its arbiter, and
-- RETURNING its columns. Nothing on schema_migrations, category_labels,
-- quantity_rollups, metric_daily or the auth/web schemas. No CREATE on the
-- schema and no TRUNCATE/REFERENCES/TRIGGER, so an ingest bug or a leaked
-- token cannot alter the schema, drop data wholesale, change roles, or reach
-- superuser-only paths such as COPY TO PROGRAM.
--
-- A table the ingest server newly reads or writes goes on this list; the
-- assertion below then holds it to exactly that. Foreign-key checks run as
-- the referenced table's owner, so `users` needs no grant for them.
CREATE TEMP TABLE ingest_grants (relname text, privilege_type text) ON COMMIT DROP;
INSERT INTO ingest_grants (relname, privilege_type)
SELECT t.relname, p.privilege_type
FROM (VALUES
  -- ensureUser (INSERT … ON CONFLICT DO NOTHING) before every batch and every
  -- issued token; upsertUserSQL (ON CONFLICT DO UPDATE) for a profile line.
  ('users',                  ARRAY['SELECT', 'INSERT', 'UPDATE']),
  -- ensureTypes: new identifiers, a changed unit; resolveType, Stats.
  ('sample_types',           ARRAY['SELECT', 'INSERT', 'UPDATE']),
  -- ensureSources, ensureTemporalContexts, ensureAggregateSeries: insert the
  -- unknown, read back the ids.
  ('sources',                ARRAY['SELECT', 'INSERT']),
  ('temporal_contexts',      ARRAY['SELECT', 'INSERT']),
  ('aggregate_series',       ARRAY['SELECT', 'INSERT']),
  -- Upserted (aggregates overwrite; rings upsert by date).
  ('aggregate_samples',      ARRAY['SELECT', 'INSERT', 'UPDATE']),
  ('activity_summaries',     ARRAY['SELECT', 'INSERT', 'UPDATE']),
  -- Raw samples: inserted, deleted by a deletion line, read by Stats,
  -- Digest, UUIDs and the route endpoints. Never updated.
  ('quantity_samples',       ARRAY['SELECT', 'INSERT', 'DELETE']),
  ('category_samples',       ARRAY['SELECT', 'INSERT', 'DELETE']),
  ('workouts',               ARRAY['SELECT', 'INSERT', 'DELETE']),
  ('heartbeat_series',       ARRAY['SELECT', 'INSERT', 'DELETE']),
  ('ecg_samples',            ARRAY['SELECT', 'INSERT', 'DELETE']),
  ('state_of_mind',          ARRAY['SELECT', 'INSERT', 'DELETE']),
  ('medication_dose_events', ARRAY['SELECT', 'INSERT', 'DELETE']),
  ('workout_route_points',   ARRAY['SELECT', 'INSERT', 'DELETE']),
  ('workout_series_points',  ARRAY['SELECT', 'INSERT', 'DELETE']),
  -- Tombstones for deleted samples.
  ('deleted_samples',        ARRAY['SELECT', 'INSERT']),
  -- The batch reservation (ON CONFLICT (batch_id) DO NOTHING), its insert_ms,
  -- and Stats' last-batch times.
  ('batches',                ARRAY['SELECT', 'INSERT', 'UPDATE']),
  -- RecordRejection: a plain INSERT, never read back.
  ('ingest_rejections',      ARRAY['INSERT']),
  -- ResolveDeviceToken (lookup, last_seen_at), and the CLI's issue, revoke,
  -- rename and list.
  ('device_tokens',          ARRAY['SELECT', 'INSERT', 'UPDATE'])
) AS t(relname, privileges)
CROSS JOIN LATERAL unnest(t.privileges) AS p(privilege_type)
-- Present on every database this runs against after a normal migrate run;
-- the guard only spares a baseline of a database from before a table existed.
WHERE to_regclass(format('public.%I', t.relname)) IS NOT NULL;

-- The lookup tables' ids are identity columns, whose nextval runs without a
-- privilege check, so inserts need nothing on their sequences. SELECT makes
-- pg_sequences.last_value readable (TestIntegration_LookupSequencesDoNotBurnOnRepeat
-- watches these four as this role). No USAGE or UPDATE: nothing calls
-- nextval or setval itself.
INSERT INTO ingest_grants (relname, privilege_type)
SELECT s.relname, 'SELECT'
FROM (VALUES ('sample_types', 'type_id'), ('sources', 'source_id'),
             ('aggregate_series', 'series_id'), ('temporal_contexts', 'temporal_context_id')) AS v(tbl, col)
CROSS JOIN LATERAL (
  SELECT c.relname::text
  FROM pg_class c
  WHERE c.oid = pg_get_serial_sequence(format('public.%I', v.tbl), v.col)::regclass
) AS s
WHERE to_regclass(format('public.%I', v.tbl)) IS NOT NULL;

DO $$
DECLARE
  g record;
BEGIN
  FOR g IN
    SELECT relname, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
    FROM ingest_grants
    GROUP BY relname
  LOOP
    -- TimescaleDB's grant hook carries a hypertable's grant to its chunks
    -- and their columnstore storage, as it did for the blanket grant.
    EXECUTE format('GRANT %s ON public.%I TO ingest', g.privileges, g.relname);
  END LOOP;
END
$$;
GRANT CONNECT ON DATABASE :"DBNAME" TO ingest;
GRANT USAGE ON SCHEMA public TO ingest;

-- InsertBatch opens every transaction with this SET LOCAL. Prove the role may
-- set it now, on every migrate run, instead of finding out as 500s on the first batch if
-- a TimescaleDB upgrade ever turns the GUC superuser-only.
SET ROLE ingest;
SET LOCAL timescaledb.max_tuples_decompressed_per_dml_transaction = 0;
RESET ROLE;

-- Prove the role configuration and ACL set are exact before committing, like
-- api_reader: exactly the list above on relations outside TimescaleDB's
-- internal schema, and in it only what the grant hook derived from that list.
DO $$
DECLARE
  ingest_oid oid := (SELECT oid FROM pg_roles WHERE rolname = 'ingest');
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles
    WHERE oid = ingest_oid
      AND rolcanlogin
      AND NOT rolsuper
      AND NOT rolinherit
      AND NOT rolcreaterole
      AND NOT rolcreatedb
      AND NOT rolreplication
      AND NOT rolbypassrls
      AND rolconnlimit = -1
      AND rolconfig IS NULL
  ) THEN
    RAISE EXCEPTION 'ingest role attributes are not exact';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_auth_members WHERE roleid = ingest_oid OR member = ingest_oid
  ) OR EXISTS (
    SELECT 1 FROM pg_shdepend
    WHERE refclassid = 'pg_authid'::regclass
      AND refobjid = ingest_oid
      AND deptype = 'o'
  ) OR EXISTS (
    SELECT 1 FROM pg_db_role_setting WHERE setrole = ingest_oid
  ) THEN
    RAISE EXCEPTION 'ingest has memberships, ownership, or database settings';
  END IF;

  IF EXISTS (
    WITH expected(nspname, privilege_type, is_grantable) AS (
      VALUES ('public', 'USAGE', false)
    ), actual AS (
      SELECT n.nspname::text, acl.privilege_type, acl.is_grantable
      FROM pg_namespace n
      CROSS JOIN LATERAL aclexplode(n.nspacl) acl
      WHERE acl.grantee = ingest_oid
    )
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ) THEN
    RAISE EXCEPTION 'ingest schema ACL set is not exact';
  END IF;

  IF EXISTS (
    WITH expected(datname, privilege_type, is_grantable) AS (
      VALUES (current_database(), 'CONNECT', false)
    ), actual AS (
      SELECT d.datname::text, acl.privilege_type, acl.is_grantable
      FROM pg_database d
      CROSS JOIN LATERAL aclexplode(d.datacl) acl
      WHERE acl.grantee = ingest_oid
    )
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ) THEN
    RAISE EXCEPTION 'ingest database ACL set is not exact';
  END IF;

  -- Every schema but TimescaleDB's internal one: exactly the list. The
  -- tables, their sequences, nothing else in public and nothing anywhere else.
  IF EXISTS (
    WITH expected AS (
      SELECT 'public'::text AS nspname, relname, privilege_type, false AS is_grantable
      FROM ingest_grants
    ), actual AS (
      SELECT n.nspname::text, c.relname::text, acl.privilege_type, acl.is_grantable
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      CROSS JOIN LATERAL aclexplode(c.relacl) acl
      WHERE acl.grantee = ingest_oid
        AND n.nspname <> '_timescaledb_internal'
    )
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ) THEN
    RAISE EXCEPTION 'ingest relation ACL set is not exactly the list in 099_read_roles.sh';
  END IF;

  -- _timescaledb_internal: only what the grant hook derives from the list —
  -- a chunk carrying a privilege its hypertable has, or columnstore storage
  -- (recognised as in the api_reader check above) carrying a DML privilege.
  -- Never a continuous aggregate's internals: ingest has no grant on
  -- quantity_rollups, and its inserts log invalidations through
  -- TimescaleDB's own catalog access, not through a grant.
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    CROSS JOIN LATERAL aclexplode(c.relacl) acl
    WHERE acl.grantee = ingest_oid
      AND n.nspname = '_timescaledb_internal'
      AND NOT (
        NOT acl.is_grantable
        AND (
          -- a chunk of a hypertable on the list, with one of its privileges
          EXISTS (SELECT 1
                  FROM timescaledb_information.chunks ch
                  JOIN ingest_grants g
                    ON ch.hypertable_schema = 'public'
                   AND g.relname = ch.hypertable_name::text
                  WHERE ch.chunk_schema = n.nspname AND ch.chunk_name = c.relname
                    AND g.privilege_type = acl.privilege_type)
          OR (acl.privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
              AND c.relkind = 'r'
              AND (
                -- columnstore storage of a hypertable, old or new layout
                EXISTS (SELECT 1 FROM pg_attribute a
                        WHERE a.attrelid = c.oid AND a.attname = '_ts_meta_count')
                -- TimescaleDB <= 2.28's column-less compressed-hypertable
                -- parent (see the api_reader check above)
                OR NOT EXISTS (SELECT 1 FROM pg_attribute a
                               WHERE a.attrelid = c.oid AND a.attnum > 0
                                 AND NOT a.attisdropped)))
        )
      )
  ) THEN
    RAISE EXCEPTION 'ingest holds a privilege in _timescaledb_internal that no grant on the list explains';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_attribute a
    CROSS JOIN LATERAL aclexplode(a.attacl) acl
    WHERE acl.grantee = ingest_oid
  ) OR EXISTS (
    SELECT 1 FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(p.proacl) acl
    WHERE acl.grantee = ingest_oid
  ) OR EXISTS (
    SELECT 1 FROM pg_type t
    CROSS JOIN LATERAL aclexplode(t.typacl) acl
    WHERE acl.grantee = ingest_oid
  ) OR EXISTS (
    SELECT 1 FROM pg_parameter_acl p
    CROSS JOIN LATERAL aclexplode(p.paracl) acl
    WHERE acl.grantee = ingest_oid
  ) OR EXISTS (
    -- No default privileges any more: a table a later migration adds is not
    -- writable until it is on the list above (DROP OWNED cleared the
    -- blanket ones earlier versions of this file set).
    SELECT 1 FROM pg_default_acl d
    CROSS JOIN LATERAL aclexplode(d.defaclacl) acl
    WHERE acl.grantee = ingest_oid
  ) THEN
    RAISE EXCEPTION 'ingest has unexpected column, function, type, parameter, or default ACLs';
  END IF;
END
$$;

COMMIT;
EOSQL
fi

# ---------------------------------------------------------------------------
# web_app: the web viewer's role in accounts mode (WEB_ACCOUNTS=true).
#
# The database decides what a signed-in person can read. web_app holds no
# grant on any table with health data in it: it reads the views in schema
# `web` (015_web_accounts.sql), each filtered on puls_viewer_user(), which the
# viewer sets per transaction from the session. Its search_path puts `web`
# first, so the viewer's SQL names the same relations in both modes and
# resolves to the views here and to the tables for grafana. The checks below
# fail the migrate run, and so keep the app services down, if that ever stops
# being true — a grant on a base table, a view without the filter, a missing
# search_path. A relation the viewer newly reads needs a view, a GRANT below
# and an expected_rel row.
# ---------------------------------------------------------------------------
if [[ -z "$WEB_DB_PASSWORD" ]]; then
  psql -q -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'EOSQL'
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'web_app') THEN
    ALTER ROLE web_app NOLOGIN;
  END IF;
END
$$;
EOSQL
  echo "099_read_roles: WEB_DB_PASSWORD is not set; skipping the web_app role" \
       "(only the web viewer's accounts mode uses it; an existing one is now NOLOGIN)."
  exit 0
fi

# A database baselined from before 015/016/018 has no views or functions to
# grant yet; the next plain migrate run applies them, and this section with it.
if [[ "$(psql -X -q -tA --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
          -c "SELECT to_regprocedure('puls_create_web_views()') IS NOT NULL
                 AND to_regprocedure('auth.purge_user(bytea,uuid)') IS NOT NULL
                 AND to_regprocedure('auth.decline_signups(bytea,uuid[])') IS NOT NULL")" != t ]]; then
  echo "099_read_roles: 015_web_accounts.sql, 016_web_signups.sql or 018_web_accounts_hardening.sql is not applied yet; skipping the web_app role."
  exit 0
fi

psql -q -v ON_ERROR_STOP=1 \
     -v web_password="${WEB_DB_PASSWORD}" \
     --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'EOSQL'
BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'web_app') THEN
    CREATE ROLE web_app LOGIN;
  END IF;
END
$$;

-- Same reconciliation as api_reader: refuse to continue if the role owns
-- anything (DROP OWNED would delete it), strip memberships, then DROP OWNED to
-- clear every direct grant before re-applying the exact set below.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_shdepend
    WHERE refclassid = 'pg_authid'::regclass
      AND refobjid = (SELECT oid FROM pg_roles WHERE rolname = 'web_app')
      AND deptype = 'o'
  ) THEN
    RAISE EXCEPTION 'web_app owns database objects; refusing automatic reconciliation';
  END IF;
END
$$;

DO $$
DECLARE
  membership record;
BEGIN
  FOR membership IN
    SELECT parent.rolname
    FROM pg_auth_members m
    JOIN pg_roles parent ON parent.oid = m.roleid
    WHERE m.member = (SELECT oid FROM pg_roles WHERE rolname = 'web_app')
  LOOP
    EXECUTE format('REVOKE %I FROM web_app', membership.rolname);
  END LOOP;

  FOR membership IN
    SELECT child.rolname
    FROM pg_auth_members m
    JOIN pg_roles child ON child.oid = m.member
    WHERE m.roleid = (SELECT oid FROM pg_roles WHERE rolname = 'web_app')
  LOOP
    EXECUTE format('REVOKE web_app FROM %I', membership.rolname);
  END LOOP;
END
$$;

DROP OWNED BY web_app;
ALTER ROLE web_app
  LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION
  NOBYPASSRLS CONNECTION LIMIT -1 VALID UNTIL 'infinity'
  PASSWORD :'web_password';
ALTER ROLE web_app RESET ALL;
ALTER ROLE web_app IN DATABASE :"DBNAME" RESET ALL;
-- The per-user views, rebuilt every run (015_web_accounts.sql): a view a
-- CASCADE took with it (rebuilding quantity_rollups drops metric_daily's) or
-- one a base-table column change left stale comes back here, before the
-- grants below, instead of failing them.
SELECT puls_create_web_views();

-- The viewer's unqualified table names resolve to the per-user views first.
-- Without this the role still reads nothing it should not (it has no grant
-- on the tables); the viewer just gets "permission denied" everywhere.
ALTER ROLE web_app SET search_path = web, public;

GRANT CONNECT ON DATABASE :"DBNAME" TO web_app;
-- public for sample_types and the functions the viewer's SQL calls
-- (time_bucket, puls_time_zone, puls_viewer_user); EXECUTE on those is
-- PostgreSQL's default PUBLIC grant.
GRANT USAGE ON SCHEMA public, web, auth TO web_app;

GRANT SELECT ON TABLE
  web.users,
  web.quantity_samples,
  web.category_samples,
  web.workouts,
  web.sources,
  web.workout_route_points,
  web.workout_series_points,
  web.activity_summaries,
  web.metric_daily
TO web_app;

-- The HealthKit identifiers seen on this server and their units. Shared by
-- every user; the viewer's queries join it by identifier.
GRANT SELECT ON TABLE public.sample_types TO web_app;

-- The account store. The viewer looks accounts up by email to sign people
-- in, so it reads every row here; it never reads another user's health data.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  auth.accounts,
  auth.sessions,
  auth.invites,
  auth.signup_requests
TO web_app;

-- The privileged steps of sign-up and self-service (016_web_signups.sql,
-- 018_web_accounts_hardening.sql): each a SECURITY DEFINER function that
-- checks the caller's session itself.
-- web_app gets EXECUTE on exactly these and on no other function of its own
-- (PostgreSQL's default PUBLIC EXECUTE covers built-ins like time_bucket).
GRANT EXECUTE ON FUNCTION
  auth.approve_signup(bytea, uuid),
  auth.set_account_disabled(bytea, uuid, boolean),
  auth.purge_user(bytea, uuid),
  auth.issue_device_token(bytea, bytea, text, text),
  auth.my_devices(bytea),
  auth.revoke_my_device(bytea, bigint),
  auth.delete_my_account(bytea),
  auth.decline_signups(bytea, uuid[])
TO web_app;

-- Which users those functions may act on (written only by approve_signup).
GRANT SELECT ON TABLE auth.self_service_users TO web_app;

DO $$
DECLARE
  web_oid oid := (SELECT oid FROM pg_roles WHERE rolname = 'web_app');
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles
    WHERE oid = web_oid
      AND rolcanlogin
      AND NOT rolsuper
      AND NOT rolinherit
      AND NOT rolcreaterole
      AND NOT rolcreatedb
      AND NOT rolreplication
      AND NOT rolbypassrls
      AND rolconnlimit = -1
  ) THEN
    RAISE EXCEPTION 'web_app role attributes are not exact';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_auth_members WHERE roleid = web_oid OR member = web_oid
  ) OR EXISTS (
    SELECT 1 FROM pg_shdepend
    WHERE refclassid = 'pg_authid'::regclass
      AND refobjid = web_oid
      AND deptype = 'o'
  ) THEN
    RAISE EXCEPTION 'web_app has memberships or owns objects';
  END IF;

  -- Exactly one setting: the search_path, for every database.
  IF EXISTS (
    WITH expected(setdatabase, setconfig) AS (
      VALUES (0::oid, ARRAY['search_path=web, public']::text[])
    ), actual AS (
      SELECT setdatabase, setconfig FROM pg_db_role_setting WHERE setrole = web_oid
    )
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ) THEN
    RAISE EXCEPTION 'web_app role settings are not exactly search_path = web, public';
  END IF;

  IF EXISTS (
    WITH expected(nspname, relname, privilege_type, is_grantable) AS (VALUES
      ('web', 'users', 'SELECT', false),
      ('web', 'quantity_samples', 'SELECT', false),
      ('web', 'category_samples', 'SELECT', false),
      ('web', 'workouts', 'SELECT', false),
      ('web', 'sources', 'SELECT', false),
      ('web', 'workout_route_points', 'SELECT', false),
      ('web', 'workout_series_points', 'SELECT', false),
      ('web', 'activity_summaries', 'SELECT', false),
      ('web', 'metric_daily', 'SELECT', false),
      ('public', 'sample_types', 'SELECT', false),
      ('auth', 'accounts', 'SELECT', false),
      ('auth', 'accounts', 'INSERT', false),
      ('auth', 'accounts', 'UPDATE', false),
      ('auth', 'accounts', 'DELETE', false),
      ('auth', 'sessions', 'SELECT', false),
      ('auth', 'sessions', 'INSERT', false),
      ('auth', 'sessions', 'UPDATE', false),
      ('auth', 'sessions', 'DELETE', false),
      ('auth', 'invites', 'SELECT', false),
      ('auth', 'invites', 'INSERT', false),
      ('auth', 'invites', 'UPDATE', false),
      ('auth', 'invites', 'DELETE', false),
      ('auth', 'signup_requests', 'SELECT', false),
      ('auth', 'signup_requests', 'INSERT', false),
      ('auth', 'signup_requests', 'UPDATE', false),
      ('auth', 'signup_requests', 'DELETE', false),
      ('auth', 'self_service_users', 'SELECT', false)
    ), actual AS (
      SELECT n.nspname::text, c.relname::text, acl.privilege_type, acl.is_grantable
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      CROSS JOIN LATERAL aclexplode(c.relacl) acl
      WHERE acl.grantee = web_oid
    )
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ) THEN
    RAISE EXCEPTION 'web_app relation ACL set is not exact';
  END IF;

  IF EXISTS (
    WITH expected(nspname, privilege_type, is_grantable) AS (VALUES
      ('public', 'USAGE', false),
      ('web', 'USAGE', false),
      ('auth', 'USAGE', false)
    ), actual AS (
      SELECT n.nspname::text, acl.privilege_type, acl.is_grantable
      FROM pg_namespace n
      CROSS JOIN LATERAL aclexplode(n.nspacl) acl
      WHERE acl.grantee = web_oid
    )
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ) THEN
    RAISE EXCEPTION 'web_app schema ACL set is not exact';
  END IF;

  IF EXISTS (
    WITH expected(datname, privilege_type, is_grantable) AS (
      VALUES (current_database()::text, 'CONNECT', false)
    ), actual AS (
      SELECT d.datname::text, acl.privilege_type, acl.is_grantable
      FROM pg_database d
      CROSS JOIN LATERAL aclexplode(d.datacl) acl
      WHERE acl.grantee = web_oid
    )
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ) THEN
    RAISE EXCEPTION 'web_app database ACL set is not exact';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_attribute a
    CROSS JOIN LATERAL aclexplode(a.attacl) acl
    WHERE acl.grantee = web_oid
  ) OR EXISTS (
    SELECT 1 FROM pg_type t
    CROSS JOIN LATERAL aclexplode(t.typacl) acl
    WHERE acl.grantee = web_oid
  ) OR EXISTS (
    SELECT 1 FROM pg_default_acl d
    CROSS JOIN LATERAL aclexplode(d.defaclacl) acl
    WHERE acl.grantee = web_oid
  ) OR EXISTS (
    SELECT 1 FROM pg_parameter_acl p
    CROSS JOIN LATERAL aclexplode(p.paracl) acl
    WHERE acl.grantee = web_oid
  ) THEN
    RAISE EXCEPTION 'web_app has unexpected column, type, default, or parameter ACLs';
  END IF;

  -- Functions: EXECUTE on exactly the sign-up and self-service steps, each a
  -- SECURITY DEFINER function pinned to search_path pg_catalog — counting
  -- every definer function web_app can run by any route, PUBLIC's default
  -- EXECUTE included (has_function_privilege), not only direct grants, so a
  -- future definer function left executable by everyone fails the run.
  -- Extensions' own functions are theirs to answer for.
  IF EXISTS (
    WITH expected(signature) AS (VALUES
      ('auth.approve_signup(bytea,uuid)'),
      ('auth.set_account_disabled(bytea,uuid,boolean)'),
      ('auth.purge_user(bytea,uuid)'),
      ('auth.issue_device_token(bytea,bytea,text,text)'),
      ('auth.my_devices(bytea)'),
      ('auth.revoke_my_device(bytea,bigint)'),
      ('auth.delete_my_account(bytea)'),
      ('auth.decline_signups(bytea,uuid[])')
    ), granted AS (
      SELECT p.oid::regprocedure::text AS signature
      FROM pg_proc p
      CROSS JOIN LATERAL aclexplode(p.proacl) acl
      WHERE acl.grantee = web_oid AND acl.privilege_type = 'EXECUTE' AND NOT acl.is_grantable
    ), runnable_definers AS (
      SELECT p.oid::regprocedure::text AS signature
      FROM pg_proc p
      WHERE p.prosecdef
        AND has_function_privilege(web_oid, p.oid, 'EXECUTE')
        AND NOT EXISTS (SELECT 1 FROM pg_depend d
                        WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')
    )
    (SELECT * FROM expected EXCEPT SELECT * FROM granted)
    UNION ALL
    (SELECT * FROM granted EXCEPT SELECT * FROM expected)
    UNION ALL
    (SELECT * FROM runnable_definers EXCEPT SELECT * FROM expected)
  ) OR EXISTS (
    SELECT 1 FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(p.proacl) acl
    WHERE acl.grantee = web_oid AND acl.privilege_type <> 'EXECUTE'
  ) OR EXISTS (
    SELECT 1 FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(p.proacl) acl
    WHERE acl.grantee = web_oid
      AND NOT (p.prosecdef AND p.proconfig @> ARRAY['search_path=pg_catalog, pg_temp'])
  ) THEN
    RAISE EXCEPTION 'web_app function ACL set is not exactly the sign-up and self-service functions';
  END IF;

  -- The invariant itself, independent of how the grants above are spelled
  -- (and of PUBLIC grants, which has_table_privilege includes): outside the
  -- `web` views and the account store, web_app cannot read any relation in
  -- any schema that carries a user_id — tables, chunks, compressed chunks,
  -- continuous-aggregate internals — nor `users` or `sources`.
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind IN ('r', 'p', 'v', 'm', 'f')
      AND n.nspname NOT IN ('web', 'auth')
      AND (EXISTS (SELECT 1 FROM pg_attribute a
                   WHERE a.attrelid = c.oid AND a.attname = 'user_id'
                     AND a.attnum > 0 AND NOT a.attisdropped)
           OR c.oid IN ('public.users'::regclass, 'public.sources'::regclass))
      AND (has_table_privilege(web_oid, c.oid, 'SELECT')
           OR has_any_column_privilege(web_oid, c.oid, 'SELECT'))
  ) THEN
    RAISE EXCEPTION 'web_app can read a table holding per-user data directly';
  END IF;

  -- Nor write anything by any route, PUBLIC's grants included: outside the
  -- account store in schema auth, web_app can change no relation or
  -- sequence (nor add a trigger or a foreign key to one), and in it not
  -- auth.self_service_users, the list the definer functions trust.
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind IN ('r', 'p', 'v', 'm', 'f', 'S')
      AND n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND (n.nspname <> 'auth' OR c.oid = 'auth.self_service_users'::regclass)
      AND CASE WHEN c.relkind = 'S' THEN
            has_sequence_privilege(web_oid, c.oid, 'UPDATE')
            OR has_sequence_privilege(web_oid, c.oid, 'USAGE')
          ELSE
            has_table_privilege(web_oid, c.oid, 'INSERT')
            OR has_table_privilege(web_oid, c.oid, 'UPDATE')
            OR has_table_privilege(web_oid, c.oid, 'DELETE')
            OR has_table_privilege(web_oid, c.oid, 'TRUNCATE')
            OR has_table_privilege(web_oid, c.oid, 'TRIGGER')
            OR has_table_privilege(web_oid, c.oid, 'REFERENCES')
            OR has_any_column_privilege(web_oid, c.oid, 'INSERT')
            OR has_any_column_privilege(web_oid, c.oid, 'UPDATE')
            OR has_any_column_privilege(web_oid, c.oid, 'REFERENCES')
          END
  ) THEN
    RAISE EXCEPTION 'web_app can write a relation outside the account store';
  END IF;

  -- A trigger runs without any EXECUTE check, so a SECURITY DEFINER trigger
  -- on a table web_app writes would slip past the function check above:
  -- schema auth has none (foreign keys' internal triggers aside).
  IF EXISTS (
    SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relnamespace = 'auth'::regnamespace AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'schema auth has a trigger, which web_app''s writes would run';
  END IF;

  -- Schema `web` holds exactly the views puls_create_web_views() just made,
  -- each a security barrier. Their definitions are that function's, rebuilt
  -- above on every run, so a hand-edited or hand-added view cannot outlive
  -- this check; the substring test is a last sanity check on the function
  -- itself, not the proof (the integration test is:
  -- web/lib/webapp.integration.test.ts).
  IF EXISTS (
    WITH expected(relname) AS (VALUES
      ('users'), ('quantity_samples'), ('category_samples'), ('workouts'),
      ('sources'), ('workout_route_points'), ('workout_series_points'),
      ('activity_summaries'), ('metric_daily')
    ), actual AS (
      SELECT c.relname::text FROM pg_class c
      WHERE c.relnamespace = 'web'::regnamespace
        AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
    )
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ) OR EXISTS (
    SELECT 1
    FROM pg_class c
    WHERE c.relnamespace = 'web'::regnamespace
      AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
      AND (c.relkind <> 'v'
           OR NOT coalesce(c.reloptions @> ARRAY['security_barrier=true'], false)
           OR pg_get_viewdef(c.oid) NOT LIKE '%puls_viewer_user()%')
  ) THEN
    RAISE EXCEPTION 'schema web does not hold exactly the per-user security-barrier views';
  END IF;
END
$$;

COMMIT;
EOSQL
