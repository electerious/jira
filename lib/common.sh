# Shared CLI helpers, credential loading, and Jira API access.

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

parse_result_limit() {
  local value="$1"

  [[ "${value}" =~ ^[0-9]+$ ]] || die '--limit must be a positive integer'
  (( 10#${value} >= 1 && 10#${value} <= 1000 )) || die '--limit must be between 1 and 1000'
  printf '%s' "$((10#${value}))"
}

validate_issue_key() {
  local issue_key="$1"

  [[ "${issue_key}" =~ ^[A-Za-z][A-Za-z0-9_]*-[0-9]+$ ]] && return 0
  if [[ $# -gt 1 ]]; then
    die "$2"
  fi
  die "Invalid Jira issue key '${issue_key}'"
}

parse_issue_read_options() {
  local default_limit="$1"
  local supports_limit="$2"
  shift 2

  ISSUE_READ_KEY=""
  ISSUE_READ_JSON=false
  ISSUE_READ_LIMIT="${default_limit}"
  ISSUE_READ_HELP=false
  local limit_seen=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        ISSUE_READ_JSON=true
        shift
        ;;
      --limit)
        [[ "${supports_limit}" == true ]] || die '--limit is not supported for this command'
        [[ $# -ge 2 ]] || die '--limit requires a number'
        [[ "${limit_seen}" == false ]] || die '--limit may only be specified once'
        ISSUE_READ_LIMIT="$(parse_result_limit "$2")"
        limit_seen=true
        shift 2
        ;;
      -h|--help)
        ISSUE_READ_HELP=true
        return
        ;;
      --)
        shift
        [[ $# -gt 0 ]] || die 'an issue key is required after --'
        [[ -z "${ISSUE_READ_KEY}" ]] || die "Unexpected argument '$1'"
        ISSUE_READ_KEY="$1"
        shift
        [[ $# -eq 0 ]] || die "Unexpected argument '$1'"
        ;;
      *)
        [[ -z "${ISSUE_READ_KEY}" ]] || die "Unexpected argument '$1'"
        ISSUE_READ_KEY="$1"
        shift
        ;;
    esac
  done
}

load_credentials() {
  local credentials_file="${JIRA_CREDENTIALS_FILE:-}"

  if [[ -z "${credentials_file}" ]]; then
    [[ -n "${HOME:-}" ]] || die 'HOME is not set; set JIRA_CREDENTIALS_FILE'
    credentials_file="${HOME}/.config/jira/credentials"
  fi

  [[ -f "${credentials_file}" ]] || {
    printf 'Missing credentials file: %s\n' "${credentials_file}" >&2
    printf 'Create it with these settings:\n  JIRA_DOMAIN=your-instance.atlassian.net\n  JIRA_TOKEN=your-personal-access-token\n' >&2
    exit 1
  }
  [[ -r "${credentials_file}" ]] || die "Credentials file is not readable at '${credentials_file}'"

  # Keep the same shell-assignment format used by the existing Jira scripts.
  # shellcheck source=/dev/null
  source "${credentials_file}"

  [[ -n "${JIRA_DOMAIN:-}" ]] || die "JIRA_DOMAIN must be set in ${credentials_file}"
  [[ -n "${JIRA_TOKEN:-}" ]] || die "JIRA_TOKEN must be set in ${credentials_file}"
  [[ "${JIRA_DOMAIN}" =~ ^[A-Za-z0-9.-]+(:[0-9]+)?$ ]] || die 'JIRA_DOMAIN must be a hostname, optionally with a port'
}

jira_api_get() {
  local endpoint="$1"
  shift
  local response http_code body curl_status

  if response="$(curl -sS -G \
    --connect-timeout 10 \
    --max-time 60 \
    "$@" \
    -H 'Accept: application/json' \
    -H "Authorization: Bearer ${JIRA_TOKEN}" \
    -w $'\n%{http_code}' \
    "https://${JIRA_DOMAIN}${endpoint}")"; then
    curl_status=0
  else
    curl_status=$?
  fi

  (( curl_status == 0 )) || die "Could not reach Jira at ${JIRA_DOMAIN} (curl exit ${curl_status})"

  http_code="${response##*$'\n'}"
  body="${response%$'\n'*}"
  [[ "${http_code}" =~ ^2[0-9][0-9]$ ]] || {
    local detail
    detail="$(printf '%s' "${body}" | jq -r '(.errorMessages // .message // empty) | if type == "array" then join("; ") else . end' 2>/dev/null || true)"
    if [[ -n "${detail}" ]]; then
      die "Jira API returned HTTP ${http_code}: ${detail}"
    fi
    die "Jira API returned HTTP ${http_code}"
  }

  printf '%s' "${body}"
}

parse_list_options() {
  JSON_OUTPUT=false
  RESULT_LIMIT=25
  local limit_seen=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        JSON_OUTPUT=true
        shift
        ;;
      --limit)
        [[ $# -ge 2 ]] || die '--limit requires a number'
        [[ "${limit_seen}" == false ]] || die '--limit may only be specified once'
        RESULT_LIMIT="$(parse_result_limit "$2")"
        limit_seen=true
        shift 2
        ;;
      -h|--help)
        show_issues_help
        exit 0
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done

  REMAINING_ARGUMENTS=("$@")
}
