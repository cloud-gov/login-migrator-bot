#!/bin/bash
set -euo pipefail

# Concourse task entrypoint: download the production UAA query results from S3
# and print the daily cloud.gov/login.gov active-user summary to the build log.
#
# It wraps the two committed scripts:
#   - ci/download-uaa-results.sh   (aws s3 sync of the uaa/ prefix)
#   - ci/summarize-migration-daily.py (last-snapshot-per-UTC-day counts)
#
# Required environment (supplied by ci/daily-summary.yml params):
#   S3_BUCKET  reporting bucket name; production is ((uaa-queries-s3-bucket-production))
# Optional:
#   AWS_DEFAULT_REGION  defaults to us-gov-west-1 (set below if unset)
#
# AWS credentials to read the bucket are provided to the task by the pipeline
# (env params or the task's instance role). This script does not read keys here.

if [ -z "${S3_BUCKET:-}" ]; then
    echo "ERROR: S3_BUCKET is not set" >&2
    exit 1
fi

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-gov-west-1}"

REPO_DIR="git-login-migrator-bot"
OUTPUT_DIR="$(mktemp -d)"
trap 'rm -rf "$OUTPUT_DIR"' EXIT

"${REPO_DIR}/ci/download-uaa-results.sh" -b "$S3_BUCKET" -o "$OUTPUT_DIR"

echo
echo "=== Daily cloud.gov / login.gov active-user summary ==="
python3 "${REPO_DIR}/ci/summarize-migration-daily.py" -d "$OUTPUT_DIR"
