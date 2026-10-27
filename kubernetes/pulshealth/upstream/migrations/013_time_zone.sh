#!/bin/bash
# Stores the calendar time zone on the database so puls_time_zone() (defined in
# 009_metric_daily.sql, read by the metric_daily view and the Grafana
# dashboards' hidden `tz` variable) returns it in every session.
#
#   PULS_TIME_ZONE   IANA zone name, e.g. America/Los_Angeles. Default: UTC.
#
# It MUST match the phone's zone: the on-device daily aggregates
# (HKStatisticsCollectionQuery buckets, activity rings) are computed in the
# phone's local calendar, and the server-side daily views bucket raw samples in
# this zone to line up with them. Set it in .env before first start.
#
# The value is validated against pg_timezone_names (exact, case-sensitive, so
# the same string also satisfies Go's time.LoadLocation in the api service)
# and written with ALTER DATABASE … SET, which applies to connections opened
# after it runs. The migrate service (db/migrate.sh) runs this script on every
# invocation, before the app services start, so a fresh install picks the zone
# up immediately and changing it later is: edit PULS_TIME_ZONE in .env, then
# `docker compose up -d` (migrate re-runs this; the app containers are
# recreated because their environment changed). Without Compose the same
# effect is:
#
#   docker compose exec db psql -U postgres -d postgres \
#     -c "ALTER DATABASE postgres SET puls.time_zone = 'Europe/Berlin'"
#
# then restart the app containers (or wait for their pools to reconnect).
# Connection comes from PGHOST/PGPORT/PGPASSWORD in the environment (set by
# migrate.sh); POSTGRES_USER / POSTGRES_DB default to postgres/postgres.
set -euo pipefail

PULS_TIME_ZONE="${PULS_TIME_ZONE:-UTC}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-postgres}"

known="$(psql -v ON_ERROR_STOP=1 -tA -v tz="${PULS_TIME_ZONE}" \
              --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'EOSQL'
SELECT count(*) FROM pg_timezone_names WHERE name = :'tz';
EOSQL
)"
if [[ "$known" != "1" ]]; then
  echo "013_time_zone: PULS_TIME_ZONE='${PULS_TIME_ZONE}' is not an IANA zone" \
       "known to this PostgreSQL (see: SELECT name FROM pg_timezone_names)." >&2
  exit 1
fi

psql -q -v ON_ERROR_STOP=1 -v tz="${PULS_TIME_ZONE}" \
     --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'EOSQL'
ALTER DATABASE :"DBNAME" SET puls.time_zone = :'tz';
EOSQL

echo "013_time_zone: puls.time_zone set to ${PULS_TIME_ZONE} on database ${POSTGRES_DB}" \
     "(applies to new connections; re-run with a different PULS_TIME_ZONE to change it)."
