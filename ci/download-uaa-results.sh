#!/bin/bash
set -euo pipefail

# Downloads all UAA query result JSON files from the reporting S3 bucket into a
# local directory, preserving the timestamped key structure:
#
#   uaa/YYYY/MM/DD/HH/MM/SS/{active-users-by-origin,cloud-gov-users,login-gov-users}.json
#
# These objects are written hourly by ci/uaa-queries.sh via the Concourse
# run-uaa-queries-* jobs. This script is the read-side companion: it mirrors the
# uaa/ prefix locally so the results can be summarized offline (see
# ci/summarize-migration-trend.py).
#
# Usage:
#   ci/download-uaa-results.sh -b BUCKET [-o OUTPUT_DIR] [-r REGION]
#
#   -b BUCKET      S3 bucket name (REQUIRED). The production bucket name is the
#                  Concourse credential ((uaa-queries-s3-bucket-production))
#                  (see ci/config.yml: uaa-queries-s3-bucket-production /
#                  -staging). It is intentionally not hard-coded here.
#   -o OUTPUT_DIR  Local directory to sync into (default: ./uaa-results)
#   -r REGION      AWS region (default: $AWS_DEFAULT_REGION or us-gov-west-1)
#
# AWS credentials must be present in the environment / profile before running
# (e.g. run this from the host where your GovCloud creds can reach the bucket).
# It uses `aws s3 sync`, so re-runs only fetch new/changed objects.

# Bucket is required and must be passed in via -b; the value for production is
# the Concourse credential ((uaa-queries-s3-bucket-production)).
BUCKET=""
OUTPUT_DIR="./uaa-results"
REGION="${AWS_DEFAULT_REGION:-us-gov-west-1}"

usage() {
    # Print the leading comment block (the contiguous run of #-comment lines
    # that documents usage) as help text.
    sed -n '4,${/^#/!q;s/^# \{0,1\}//p;}' "$0"
    exit "${1:-0}"
}

while getopts ":b:o:r:h" opt; do
    case "$opt" in
        b) BUCKET="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        r) REGION="$OPTARG" ;;
        h) usage 0 ;;
        :) echo "ERROR: -$OPTARG requires an argument" >&2; usage 1 ;;
        \?) echo "ERROR: unknown option -$OPTARG" >&2; usage 1 ;;
    esac
done

if [ -z "$BUCKET" ]; then
    echo "ERROR: -b BUCKET is required" >&2
    echo "       Use the production bucket name from ((uaa-queries-s3-bucket-production))" >&2
    usage 1
fi

if ! command -v aws >/dev/null 2>&1; then
    echo "ERROR: aws CLI not found on PATH" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Syncing s3://${BUCKET}/uaa/ -> ${OUTPUT_DIR}/uaa/ (region ${REGION})"
aws s3 sync "s3://${BUCKET}/uaa/" "${OUTPUT_DIR}/uaa/" \
    --region "$REGION"

count="$(find "${OUTPUT_DIR}/uaa" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
echo "Done. ${count} JSON file(s) present under ${OUTPUT_DIR}/uaa/"
