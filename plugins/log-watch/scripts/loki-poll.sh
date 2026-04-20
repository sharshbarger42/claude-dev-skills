#!/usr/bin/env bash
# Thin wrapper around Loki's query_range endpoint.
#
# Usage:
#   loki-poll.sh <logql_query> [window_minutes] [limit]
#
# Defaults: window=15m, limit=500
# Endpoint defaults to http://192.168.0.147:30100 — override with LOKI_URL env var.

set -euo pipefail

QUERY="${1:?LogQL query required}"
WINDOW_MIN="${2:-15}"
LIMIT="${3:-500}"
LOKI_URL="${LOKI_URL:-http://192.168.0.147:30100}"

END_NS=$(date +%s%N)
START_NS=$(( END_NS - WINDOW_MIN * 60 * 1000000000 ))

curl -s -G "${LOKI_URL}/loki/api/v1/query_range" \
  --data-urlencode "query=${QUERY}" \
  --data-urlencode "start=${START_NS}" \
  --data-urlencode "end=${END_NS}" \
  --data-urlencode "limit=${LIMIT}" \
  --data-urlencode "direction=backward"
