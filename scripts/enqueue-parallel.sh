#!/usr/bin/env sh
set -eu

# Enqueue many jobs in parallel for stress testing.
#
# Usage examples:
#   sh scripts/enqueue-parallel.sh
#   sh scripts/enqueue-parallel.sh --count 5000 --concurrency 100
#   sh scripts/enqueue-parallel.sh --api-base http://127.0.0.1:8080 --count 10000 --concurrency 200

COUNT=20000
CONCURRENCY=5
JOB_TYPE="email"
TO="user@example.com"
SUBJECT_PREFIX="Hello from tiny"
API_BASE="${API_BASE:-https://tinyjobsapi.elladali.com}"
API_TIMEOUT="${API_TIMEOUT:-10}"
API_KEY="${API_KEY:-}"

usage() {
  cat <<'EOF'
Usage:
  scripts/enqueue-parallel.sh [options]

Options:
  --count N             Total number of jobs to enqueue (default: 20000)
  --concurrency N       Number of parallel workers (default: 5)
  --api-base URL        API base URL (default: https://tinyjobsapi.elladali.com)
  --timeout N           Curl max time seconds per request (default: 10)
  --type TYPE           Job type field (default: email)
  --to EMAIL            Recipient email field (default: user@example.com)
  --subject-prefix TXT  Subject prefix; script appends " #<n>" (default: Hello from tiny)
  -h, --help            Show help

Environment:
  API_BASE, API_KEY, API_TIMEOUT
EOF
}

is_uint() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --count)
      [ "$#" -ge 2 ] || { echo "Missing value for --count" >&2; exit 1; }
      COUNT="$2"
      shift 2
      ;;
    --concurrency)
      [ "$#" -ge 2 ] || { echo "Missing value for --concurrency" >&2; exit 1; }
      CONCURRENCY="$2"
      shift 2
      ;;
    --api-base)
      [ "$#" -ge 2 ] || { echo "Missing value for --api-base" >&2; exit 1; }
      API_BASE="$2"
      shift 2
      ;;
    --timeout)
      [ "$#" -ge 2 ] || { echo "Missing value for --timeout" >&2; exit 1; }
      API_TIMEOUT="$2"
      shift 2
      ;;
    --type)
      [ "$#" -ge 2 ] || { echo "Missing value for --type" >&2; exit 1; }
      JOB_TYPE="$2"
      shift 2
      ;;
    --to)
      [ "$#" -ge 2 ] || { echo "Missing value for --to" >&2; exit 1; }
      TO="$2"
      shift 2
      ;;
    --subject-prefix)
      [ "$#" -ge 2 ] || { echo "Missing value for --subject-prefix" >&2; exit 1; }
      SUBJECT_PREFIX="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

command -v curl >/dev/null 2>&1 || {
  echo "curl command not found" >&2
  exit 1
}

is_uint "$COUNT" || { echo "--count must be an integer >= 1" >&2; exit 1; }
is_uint "$CONCURRENCY" || { echo "--concurrency must be an integer >= 1" >&2; exit 1; }
[ -n "$API_BASE" ] || { echo "--api-base must not be empty" >&2; exit 1; }
[ -n "$API_TIMEOUT" ] || { echo "--timeout must not be empty" >&2; exit 1; }
[ "$COUNT" -ge 1 ] || { echo "--count must be >= 1" >&2; exit 1; }
[ "$CONCURRENCY" -ge 1 ] || { echo "--concurrency must be >= 1" >&2; exit 1; }

if [ "$CONCURRENCY" -gt "$COUNT" ]; then
  CONCURRENCY="$COUNT"
fi

URL="${API_BASE%/}/jobs"
SUCCESS_FILE="$(mktemp)"
FAIL_FILE="$(mktemp)"
trap 'rm -f "$SUCCESS_FILE" "$FAIL_FILE"' EXIT

echo "Enqueuing $COUNT jobs with concurrency=$CONCURRENCY to $URL"

export URL JOB_TYPE TO SUBJECT_PREFIX API_TIMEOUT API_KEY SUCCESS_FILE FAIL_FILE

seq "$COUNT" | xargs -n1 -P "$CONCURRENCY" sh -c '
  i="$1"
  payload=$(printf "{\"type\":\"%s\",\"to\":\"%s\",\"subject\":\"%s #%s\"}" "$JOB_TYPE" "$TO" "$SUBJECT_PREFIX" "$i")
  if [ -n "$API_KEY" ]; then
    code=$(curl -sS --max-time "$API_TIMEOUT" -o /dev/null -w "%{http_code}" -X POST "$URL" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      --data "$payload") || code="000"
  else
    code=$(curl -sS --max-time "$API_TIMEOUT" -o /dev/null -w "%{http_code}" -X POST "$URL" \
      -H "Content-Type: application/json" \
      --data "$payload") || code="000"
  fi

  if [ "$code" = "201" ]; then
    printf "." >&2
    printf "1\n" >> "$SUCCESS_FILE"
  else
    printf "!" >&2
    printf "%s\n" "$code" >> "$FAIL_FILE"
  fi
' sh

echo
ok=$(wc -l < "$SUCCESS_FILE" | tr -d ' ')
fail=$(wc -l < "$FAIL_FILE" | tr -d ' ')
echo "Done. success=$ok failed=$fail"

if [ "$fail" -gt 0 ]; then
  echo "Top failure status codes:"
  sort "$FAIL_FILE" | uniq -c | sort -nr | head -n 10
  exit 1
fi
