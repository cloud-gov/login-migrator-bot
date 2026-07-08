#!/bin/bash
set -u -o pipefail

# Runs the daily read-only UAA reporting queries and writes each query's result
# set as a JSON file to S3 under a per-run, second-granularity key prefix:
#
#   s3://$S3_BUCKET/uaa/YYYY/MM/DD/HH/MM/SS/<query>.json
#
# Three files are written (one per query):
#   - active-users-by-origin.json
#   - cloud-gov-users.json
#   - login-gov-users.json
#
# DB_URI is a secret (a full libpq connection URI in the form
# postgres://user:pass@host:5432/dbname) injected from CredHub by the pipeline.
# It MUST NOT be echoed to the build log. Do not enable `set -x`.
#
# AWS credentials are provided by the task's instance role (IRSA / EC2 role);
# no access keys are read from the environment here.

if [ -z "${DB_URI:-}" ]; then
    echo "ERROR: DB_URI is not set" >&2
    exit 1
fi

if [ -z "${S3_BUCKET:-}" ]; then
    echo "ERROR: S3_BUCKET is not set" >&2
    exit 1
fi

# Timestamped key prefix. Use UTC for a stable, sortable path.
TS_PREFIX="$(date -u +'uaa/%Y/%m/%d/%H/%M/%S')"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# run_query <output-file> <sql>
#
# Executes a single read-only query and writes its result set as a JSON array
# of row objects. psql emits one JSON document per row via row_to_json; we wrap
# those rows into a single JSON array with jq -s so each file is valid JSON.
#
# ON_ERROR_STOP fails the build on a bad query. default_transaction_read_only
# enforces a read-only session as defense-in-depth so no statement can modify
# data. -A -t -q keep psql output to just the row_to_json values.
run_query() {
    local outfile="$1"
    local sql="$2"

    psql "$DB_URI" \
        --set=ON_ERROR_STOP=on \
        -A -t -q \
        -c "SET default_transaction_read_only = on;" \
        -c "SELECT row_to_json(t) FROM ($sql) t;" \
        | jq -s '.' > "$outfile"
}

run_query "$WORKDIR/active-users-by-origin.json" \
    "select origin, count(*) as count from users where active=true group by origin order by 2 desc"

run_query "$WORKDIR/cloud-gov-users.json" \
    "select email, split_part(email, '@', 2) as domain, id from users where origin='cloud.gov' and active=true order by 2,1"

run_query "$WORKDIR/login-gov-users.json" \
    "select email, split_part(email, '@', 2) as domain, id from users where origin='login.gov' and active=true order by 2,1"

for f in active-users-by-origin.json cloud-gov-users.json login-gov-users.json; do
    dest="s3://${S3_BUCKET}/${TS_PREFIX}/${f}"
    echo "Uploading ${f} to ${dest}"
    aws s3 cp "$WORKDIR/$f" "$dest" --content-type application/json
done

echo "UAA query results written to s3://${S3_BUCKET}/${TS_PREFIX}/"
