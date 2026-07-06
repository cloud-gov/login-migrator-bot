#!/bin/bash
set -u -o pipefail

# Runs the daily read-only UAA reporting queries in ci/uaa-queries.sql and
# prints the results to the build output.
#
# DB_URI is a secret (a full libpq connection URI in the form
# postgres://user:pass@host:5432/dbname) injected from CredHub by the pipeline.
# It MUST NOT be echoed to the build log. Do not enable `set -x`.

if [ -z "${DB_URI:-}" ]; then
    echo "ERROR: DB_URI is not set" >&2
    exit 1
fi

# ON_ERROR_STOP makes a failing query fail the build.
# default_transaction_read_only enforces a read-only session as defense-in-depth
# so no statement in the SQL file can modify data.
psql "$DB_URI" \
    --set=ON_ERROR_STOP=on \
    -c "SET default_transaction_read_only = on;" \
    -f git-login-migrator-bot/ci/uaa-queries.sql
