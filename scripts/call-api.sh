#!/usr/bin/env bash
set -euo pipefail

# Call tiny REST API endpoints from terminal.
#
# Defaults:
#   API_BASE=https://tinyjobsapi.elladali.com
#   API_TIMEOUT=15
#   API_KEY=(unset; no auth header sent)
#
# Usage:
#   chmod +x scripts/call-api.sh
#   ./scripts/call-api.sh health
#   ./scripts/call-api.sh enqueue --json '{"type":"email","to":"a@example.com"}'
#   ./scripts/call-api.sh enqueue --file payload.json --priority 100 --delay-seconds 2 --ttr-seconds 30
#
# Environment variables:
#   API_BASE     Base URL of API (default: https://tinyjobsapi.elladali.com)
#   API_TIMEOUT  Curl max time in seconds (default: 15)
#   API_KEY      Optional bearer token; sent as Authorization: Bearer <API_KEY>

API_BASE="${API_BASE:-https://tinyjobsapi.elladali.com}"
API_TIMEOUT="${API_TIMEOUT:-15}"
API_KEY="${API_KEY:-}"

print_usage() {
  cat <<'EOF'
Usage:
  scripts/call-api.sh health
  scripts/call-api.sh enqueue [--json JSON_STRING | --file JSON_FILE] [--priority N] [--delay-seconds N] [--ttr-seconds N]

Commands:
  health
    GET /healthz

  enqueue
    POST /jobs with a JSON body

Options for enqueue:
  --json JSON_STRING      Inline JSON payload
  --file JSON_FILE        Read JSON payload from file
  --priority N            Query param priority
  --delay-seconds N       Query param delay_seconds
  --ttr-seconds N         Query param ttr_seconds
  -h, --help              Show help

Environment:
  API_BASE     API base URL (default: https://tinyjobsapi.elladali.com)
  API_TIMEOUT  Curl max time in seconds (default: 15)
  API_KEY      Optional bearer token for Authorization header
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

do_health() {
  require_cmd curl

  local url="${API_BASE%/}/healthz"
  echo "GET $url"

  curl -sS --max-time "$API_TIMEOUT" "$url"
  echo
}

do_enqueue() {
  require_cmd curl

  local json_payload=""
  local json_file=""
  local priority=""
  local delay_seconds=""
  local ttr_seconds=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        [[ $# -ge 2 ]] || { echo "Missing value for --json" >&2; exit 1; }
        json_payload="$2"
        shift 2
        ;;
      --file)
        [[ $# -ge 2 ]] || { echo "Missing value for --file" >&2; exit 1; }
        json_file="$2"
        shift 2
        ;;
      --priority)
        [[ $# -ge 2 ]] || { echo "Missing value for --priority" >&2; exit 1; }
        priority="$2"
        shift 2
        ;;
      --delay-seconds)
        [[ $# -ge 2 ]] || { echo "Missing value for --delay-seconds" >&2; exit 1; }
        delay_seconds="$2"
        shift 2
        ;;
      --ttr-seconds)
        [[ $# -ge 2 ]] || { echo "Missing value for --ttr-seconds" >&2; exit 1; }
        ttr_seconds="$2"
        shift 2
        ;;
      -h|--help)
        print_usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        print_usage
        exit 1
        ;;
    esac
  done

  if [[ -n "$json_payload" && -n "$json_file" ]]; then
    echo "Use either --json or --file, not both." >&2
    exit 1
  fi

  if [[ -n "$json_file" ]]; then
    if [[ ! -f "$json_file" ]]; then
      echo "JSON file not found: $json_file" >&2
      exit 1
    fi
    json_payload="$(cat "$json_file")"
  fi

  if [[ -z "$json_payload" ]]; then
    echo "Missing payload. Provide --json or --file." >&2
    exit 1
  fi

  local url="${API_BASE%/}/jobs"
  local query=()

  if [[ -n "$priority" ]]; then
    query+=("priority=$priority")
  fi
  if [[ -n "$delay_seconds" ]]; then
    query+=("delay_seconds=$delay_seconds")
  fi
  if [[ -n "$ttr_seconds" ]]; then
    query+=("ttr_seconds=$ttr_seconds")
  fi

  if [[ ${#query[@]} -gt 0 ]]; then
    local sep='?'
    local item
    for item in "${query[@]}"; do
      url+="$sep$item"
      sep='&'
    done
  fi

  echo "POST $url"

  if [[ -n "$API_KEY" ]]; then
    curl -sS --max-time "$API_TIMEOUT" -X POST "$url" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      --data "$json_payload"
  else
    curl -sS --max-time "$API_TIMEOUT" -X POST "$url" \
      -H "Content-Type: application/json" \
      --data "$json_payload"
  fi
  echo
}

main() {
  if [[ $# -lt 1 ]]; then
    print_usage
    exit 1
  fi

  case "$1" in
    health)
      shift
      do_health "$@"
      ;;
    enqueue)
      shift
      do_enqueue "$@"
      ;;
    -h|--help)
      print_usage
      ;;
    *)
      echo "Unknown command: $1" >&2
      print_usage
      exit 1
      ;;
  esac
}

main "$@"
