#!/usr/bin/env bash
# migrate.sh — applies the schema in server/db/migrations/ to the PulsHealth
# database and records what it applied in the schema_migrations table.
#
#   migrate.sh            apply every pending migration (the default)
#   migrate.sh baseline   mark an existing, hand-migrated database as current
#
# The Compose `migrate` service runs this before every app service starts
# (`docker compose up -d`), and operators run it by hand with
# `docker compose run --rm migrate [baseline]`. See server/README.md,
# "Schema migrations".
#
# Files in the migrations directory are applied in lexical order:
#
#   NNN_name.sql   one-shot. Applied once inside a single transaction
#                  (psql --single-transaction, ON_ERROR_STOP) together with the
#                  row that records it, so a failed file leaves nothing behind.
#                  An applied file is immutable: when its checksum no longer
#                  matches the recorded one this script refuses to continue.
#                  Two first-line markers change that:
#                    -- puls:rerun           re-applied whenever its checksum
#                                            changes (CREATE OR REPLACE files)
#                    -- puls:no-transaction  applied statement by statement,
#                                            for files with a statement that
#                                            cannot run in a transaction block
#                                            (refresh_continuous_aggregate)
#   NNN_name.sh    run on every invocation. These are idempotent and env-driven
#                  (roles and passwords, the calendar zone) and are never
#                  recorded.
#
# Runs are serialised: each holds a PostgreSQL advisory lock from just after
# the database answers until it exits, so a second run (`make migrate` during
# `docker compose up -d`) waits and then finds the first one's work recorded.
#
# Connection (the Compose service sets these; defaults suit it):
#   PGHOST (db)  PGPORT (5432)  POSTGRES_USER (postgres)  POSTGRES_DB (postgres)
#   PGPASSWORD, or POSTGRES_PASSWORD as its fallback
#   MIGRATIONS_DIR  defaults to ./migrations next to this script
# The *.sh migrations additionally read GRAFANA_DB_PASSWORD, API_DB_PASSWORD,
# INGEST_DB_PASSWORD and PULS_TIME_ZONE from the environment.
set -euo pipefail

usage() {
  echo "usage: $0 [migrate|baseline]" >&2
  exit 2
}

mode="${1:-migrate}"
[[ $# -le 1 ]] || usage
case "$mode" in
  migrate|baseline) ;;
  *) usage ;;
esac

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-$here/migrations}"
export PGHOST="${PGHOST:-db}"
export PGPORT="${PGPORT:-5432}"
export POSTGRES_USER="${POSTGRES_USER:-postgres}"
export POSTGRES_DB="${POSTGRES_DB:-postgres}"
export PGPASSWORD="${PGPASSWORD:-${POSTGRES_PASSWORD:-}}"
export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-5}"
# Lexical file order must not depend on the locale.
export LC_COLLATE=C

target="${POSTGRES_USER}@${PGHOST}:${PGPORT}/${POSTGRES_DB}"

log() { echo "migrate: $*"; }
die() { echo "migrate: $*" >&2; exit 1; }

[[ -d "$MIGRATIONS_DIR" ]] || die "migrations directory not found: $MIGRATIONS_DIR"

# sql: run a script from stdin as the superuser, unaligned tuples only.
# psql does not interpolate :'var' in -c strings, so everything that carries a
# value goes through -f - with -v variables.
sql() {
  psql -X -q -w -tA -v ON_ERROR_STOP=1 \
       --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" "$@" -f -
}

wait_for_db() {
  local attempt
  for attempt in $(seq 1 30); do
    if psql -X -q -w -tA --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
            -c 'SELECT 1' >/dev/null 2>&1; then
      return 0
    fi
    [[ $attempt -eq 1 ]] && log "waiting for $target"
    sleep 2
  done
  die "$target is unreachable (60 s)"
}

relation_exists() { # relation_exists <schema-qualified name> -> t | f
  sql -v r="$1" <<'EOSQL'
SELECT to_regclass(:'r') IS NOT NULL;
EOSQL
}

recorded_count() {
  sql <<'EOSQL'
SELECT count(*) FROM schema_migrations;
EOSQL
}

create_table() {
  sql <<'EOSQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
    filename   text        PRIMARY KEY,
    applied_at timestamptz NOT NULL DEFAULT now(),
    checksum   text
);
EOSQL
}

# recorded <filename>: prints nothing when the file has no row, otherwise
# "row|<checksum>" (an empty checksum is a baselined re-runnable file).
recorded() {
  sql -v f="$1" <<'EOSQL'
SELECT 'row|' || coalesce(checksum, '') FROM schema_migrations WHERE filename = :'f';
EOSQL
}

checksum() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1"
  else
    shasum -a 256 "$1"
  fi | cut -c1-64
}

# has_marker <file> <flag>: true when the file's leading comment block carries
# the exact line "-- puls:<flag>". By convention the marker is the first line.
has_marker() {
  awk -v want="-- puls:$2" '
    /^--/ { if ($0 == want) found = 1; next }
    { exit }
    END { exit !found }' "$1"
}

# apply_sql <path> <filename> <checksum>: run the file and record it. Inside
# one transaction unless the file opts out, in which case the record is
# written by the same session right after the last statement succeeds.
apply_sql() {
  local txn=(--single-transaction)
  if has_marker "$1" no-transaction; then
    txn=()
  fi
  # -q drops command tags and -o drops result sets (create_hypertable and
  # friends return rows); errors, NOTICEs and WARNINGs still reach stderr.
  psql -X -q -w -o /dev/null -v ON_ERROR_STOP=1 ${txn[@]+"${txn[@]}"} \
       -v f="$2" -v c="$3" \
       --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
       -f "$1" -f - <<'EOSQL'
INSERT INTO schema_migrations (filename, checksum) VALUES (:'f', :'c')
ON CONFLICT (filename) DO UPDATE SET checksum = EXCLUDED.checksum, applied_at = now();
EOSQL
}

# record_baseline <filename> <checksum or empty>
record_baseline() {
  sql -v f="$1" -v c="$2" <<'EOSQL'
INSERT INTO schema_migrations (filename, checksum) VALUES (:'f', NULLIF(:'c', ''))
ON CONFLICT (filename) DO NOTHING;
EOSQL
}

run_script() { # run_script <path> <filename>
  bash "$1" || die "$2 failed"
  log "$2 ran"
}

# Every file in the directory must be a migration; anything else is a mistake
# that would otherwise be silently ignored.
files=()
for path in "$MIGRATIONS_DIR"/*; do
  name="$(basename "$path")"
  [[ $name =~ ^[0-9]{3}_[A-Za-z0-9_-]+\.(sql|sh)$ ]] \
    || die "unexpected file in $MIGRATIONS_DIR: $name (expected NNN_name.sql or NNN_name.sh)"
  files+=("$path")
done
[[ ${#files[@]} -gt 0 ]] || die "no migrations found in $MIGRATIONS_DIR"

wait_for_db

# One run at a time. Two runs at once — `make migrate` while `docker compose
# up -d` starts the migrate service — would both see a pending file as
# unrecorded and apply it twice. The lock is a session-level advisory lock,
# and this script talks to the database through many short psql sessions
# (and the *.sh files through their own), so one session lives for the whole
# run just to hold it: a psql in the background reading its commands from a
# pipe this script keeps open. Nothing more is ever written to the pipe; it
# closes when this script exits, however it exits (an error, a signal, the
# container stopping), and psql then ends its session, which releases the
# lock. The other sessions poll pg_locks until that session holds it, so a
# second run waits here, before reading anything, and then sees the first
# run's records.
MIGRATE_LOCK_KEY="1886743667, 1" # ('puls' as an int4, 1): pg_advisory_lock(int, int)
lock_app="puls-migrate-lock-$$"
take_migrate_lock() {
  local state waited=0 lock_pid
  exec {lock_fd}> >(PGAPPNAME="$lock_app" exec psql -X -q -w -o /dev/null -v ON_ERROR_STOP=1 \
                      --username "$POSTGRES_USER" --dbname "$POSTGRES_DB")
  lock_pid=$!
  printf 'SELECT pg_advisory_lock(%s);\n' "$MIGRATE_LOCK_KEY" >&"$lock_fd"
  while :; do
    # t: held; f: queued behind another run; empty: not connected yet.
    state="$(sql -v app="$lock_app" <<'EOSQL'
SELECT l.granted
FROM pg_stat_activity a
JOIN pg_locks l ON l.pid = a.pid AND l.locktype = 'advisory'
WHERE a.application_name = :'app' AND a.datname = current_database();
EOSQL
)"
    [[ $state == t ]] && return 0
    kill -0 "$lock_pid" 2>/dev/null || die "could not take the migration lock on $target (its psql session ended)"
    if [[ $state == f ]] && (( waited % 30 == 0 )); then
      log "another migrate run holds the migration lock on $target; waiting for it to finish"
    fi
    sleep 1
    waited=$((waited + 1))
  done
}
take_migrate_lock

# The timescaledb-ha image ships every versioned timescaledb-*.so back to
# 2.17 and does not run ALTER EXTENSION on an existing volume, so a database
# created under an older image keeps working on its old extension version
# after the image is bumped — silently. Say so; upgrading the extension is a
# deliberate operator step (server/README.md, "Upgrading the database image").
ext_versions="$(sql <<'EOSQL'
SELECT installed_version || ' ' || default_version
FROM pg_available_extensions WHERE name = 'timescaledb' AND installed_version <> default_version;
EOSQL
)"
if [[ -n $ext_versions ]]; then
  log "NOTE: timescaledb extension is ${ext_versions% *} on $target but this image ships ${ext_versions#* };" \
      "run 'docker compose exec db psql -X -U postgres -d postgres -c \"ALTER EXTENSION timescaledb UPDATE\"'" \
      "when no app service is connected (see server/README.md, \"Upgrading the database image\")."
fi

have_table="$(relation_exists public.schema_migrations)"
have_users="$(relation_exists public.users)"
tracked=f
if [[ $have_table == t && "$(recorded_count)" -gt 0 ]]; then
  tracked=t
fi

if [[ $mode == baseline ]]; then
  [[ $have_users == t ]] \
    || die "nothing to baseline: $target has no PulsHealth schema. Run 'docker compose run --rm migrate' (or 'docker compose up -d') instead."
  [[ $tracked == f ]] \
    || die "$target already has schema_migrations rows; it is tracked. Run 'docker compose run --rm migrate' instead."
  log "baseline: recording every *.sql file as already applied to $target without running it"
  create_table
  count=0
  for path in "${files[@]}"; do
    name="$(basename "$path")"
    case "$name" in
      *.sql)
        if has_marker "$path" rerun; then
          record_baseline "$name" ""
          log "$name recorded without a checksum (re-runnable: the next migrate run applies it)"
        else
          record_baseline "$name" "$(checksum "$path")"
          log "$name recorded as applied"
        fi
        count=$((count + 1))
        ;;
      *.sh)
        run_script "$path" "$name"
        ;;
    esac
  done
  log "baseline complete: $count file(s) recorded. Run 'docker compose up -d' (or 'docker compose run --rm migrate') to apply the re-runnable files and start the stack."
  exit 0
fi

if [[ $tracked == f && $have_users == t ]]; then
  die "$target already has a PulsHealth schema but no schema_migrations records." \
      "It was created before the migrate service existed, so this script cannot tell which files it has." \
      "If every file in server/db/migrations/ has been applied to it (by the old first-start init or by hand)," \
      "run: docker compose run --rm migrate baseline" \
      "— which records them without executing anything — then retry. See server/README.md, \"Schema migrations\"."
fi

if [[ $have_table == f ]]; then
  create_table
  log "created schema_migrations on $target"
fi

# Records for files that no longer exist are as suspicious as edited files:
# a renamed migration would be applied a second time under its new name.
missing="$(sql <<'EOSQL'
SELECT filename FROM schema_migrations ORDER BY filename;
EOSQL
)"
for name in $missing; do
  [[ -e "$MIGRATIONS_DIR/$name" ]] \
    || die "$name is recorded in schema_migrations but is not in $MIGRATIONS_DIR. Applied migrations are never renamed or deleted; restore the file."
done

applied=0 rerun=0 skipped=0 scripts=0
for path in "${files[@]}"; do
  name="$(basename "$path")"
  case "$name" in
    *.sh)
      run_script "$path" "$name"
      scripts=$((scripts + 1))
      ;;
    *.sql)
      sum="$(checksum "$path")"
      rec="$(recorded "$name")"
      if has_marker "$path" rerun; then
        if [[ $rec == "row|$sum" ]]; then
          log "$name skipped (re-runnable, unchanged)"
          skipped=$((skipped + 1))
        elif [[ -z $rec ]]; then
          apply_sql "$path" "$name" "$sum" || die "$name failed"
          log "$name applied"
          applied=$((applied + 1))
        else
          apply_sql "$path" "$name" "$sum" || die "$name failed"
          log "$name rerun (content changed)"
          rerun=$((rerun + 1))
        fi
      elif [[ -z $rec ]]; then
        apply_sql "$path" "$name" "$sum" || die "$name failed"
        log "$name applied"
        applied=$((applied + 1))
      elif [[ $rec == "row|$sum" ]]; then
        log "$name skipped (already applied)"
        skipped=$((skipped + 1))
      else
        die "$name was applied to $target with different content (recorded ${rec#row|}, file $sum)." \
            "Applied migrations are immutable: revert the edit and put the change in a new NNN_name.sql," \
            "or, only for a file that is safe to execute again, mark it with a first line of '-- puls:rerun'."
      fi
      ;;
  esac
done

log "done on $target: $applied applied, $rerun rerun, $skipped skipped, $scripts script(s) ran"
