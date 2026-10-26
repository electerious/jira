# Issue search and list commands.

show_issues_help() {
  cat <<EOF
Usage: $(basename "$0") issues COMMAND [OPTIONS] [JQL]

Commands:
  assigned [OPTIONS]       List your open assigned issues
  mentioned [OPTIONS]      List issues watching you (excluding assigned)
  reported [OPTIONS]       List your open reported issues
  recent [OPTIONS]         List recently viewed issues
  search [OPTIONS] [JQL]   Search with a Jira Query Language expression
  due [OPTIONS]            List your open issues due within 7 days
  project KEY [OPTIONS]    List issues in a project

Options:
  --json                   Print a JSON array
  --limit NUMBER           Maximum results (default: 25, maximum: 1000)
  due options: --within Nd (default: 7d)
  project options: --status TEXT
  -h, --help               Show this help message
EOF
}

show_due_help() {
  cat <<EOF
Usage: $(basename "$0") issues due [OPTIONS]

Options:
  --within DURATION  Due within a number of days, e.g. 7d (default: 7d)
  --limit NUMBER     Maximum results (default: 25, maximum: 1000)
  --json             Print a JSON array
  -h, --help         Show this help message
EOF
}

show_project_help() {
  cat <<EOF
Usage: $(basename "$0") issues project KEY [OPTIONS]

Options:
  --status TEXT  Only show issues with this status
  --limit NUMBER Maximum results (default: 25, maximum: 1000)
  --json         Print a JSON array
  -h, --help     Show this help message
EOF
}

search_issues() {
  local jql="$1"
  local include_due="${2:-false}"
  local fields='summary,issuetype,status'
  local body

  [[ "${include_due}" == true ]] && fields="${fields},duedate"
  load_credentials
  body="$(jira_api_get "/rest/api/2/search" \
    --data-urlencode "jql=${jql}" \
    --data-urlencode "fields=${fields}" \
    --data-urlencode "maxResults=${RESULT_LIMIT}")"

  printf '%s' "${body}" | jq -e 'type == "object" and (.issues | type == "array")' >/dev/null 2>&1 || die 'Jira returned an unexpected response; expected a search result'

  if [[ "${JSON_OUTPUT}" == true ]]; then
    printf '%s' "${body}" | jq --arg domain "${JIRA_DOMAIN}" --argjson include_due "${include_due}" '[.issues[] | {
      key,
      summary: (.fields.summary // ""),
      issue_type: (.fields.issuetype.name // "Unknown"),
      status: (.fields.status.name // "Unknown"),
      due_date: (if $include_due then .fields.duedate else null end),
      url: ("https://" + $domain + "/browse/" + .key)
    } | if $include_due then . else del(.due_date) end]'
    return
  fi

  if [[ "${include_due}" == true ]]; then
    printf '%s' "${body}" | jq -r --arg domain "${JIRA_DOMAIN}" '
      if (.issues | length) == 0 then
        "No Jira issues found."
      else
        .issues[] |
        "- \(.fields.duedate // "Unknown due date") · \(.key) · \(.fields.status.name // "Unknown")\n  \((.fields.summary // "") | gsub("[\\r\\n]+"; " "))\n  https://\($domain)/browse/\(.key)"
      end
    '
    return
  fi

  printf '%s' "${body}" | jq -r --arg domain "${JIRA_DOMAIN}" '
    if (.issues | length) == 0 then
      "No Jira issues found."
    else
      .issues[] |
      "- \(.key) · \(.fields.issuetype.name // "Unknown") · \(.fields.status.name // "Unknown")\n  \((.fields.summary // "") | gsub("[\\r\\n]+"; " "))\n  https://\($domain)/browse/\(.key)"
    end
  '
}

cmd_issues_due() {
  JSON_OUTPUT=false
  RESULT_LIMIT=25
  local within_days=7
  local limit_seen=false
  local within_seen=false

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
      --within)
        [[ $# -ge 2 ]] || die '--within requires a duration such as 7d'
        [[ "${2}" =~ ^[0-9]+d$ ]] || die '--within must be a positive number of days, such as 7d'
        [[ "${within_seen}" == false ]] || die '--within may only be specified once'
        local days="${2%d}"
        (( 10#${days} >= 1 && 10#${days} <= 3650 )) || die '--within must be between 1d and 3650d'
        within_days=$((10#${days}))
        within_seen=true
        shift 2
        ;;
      -h|--help)
        show_due_help
        return
        ;;
      *)
        die "Unexpected argument '$1'"
        ;;
    esac
  done

  local jql="assignee = currentUser() AND statusCategory != Done AND duedate >= startOfDay() AND duedate <= endOfDay(\"+${within_days}d\") ORDER BY duedate ASC"
  search_issues "${jql}" true
}

cmd_issues_project() {
  JSON_OUTPUT=false
  RESULT_LIMIT=25
  local project_key=""
  local status=""
  local status_seen=false
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
      --status)
        [[ $# -ge 2 && -n "$2" ]] || die '--status requires a value'
        [[ "${status_seen}" == false ]] || die '--status may only be specified once'
        status="$2"
        status_seen=true
        shift 2
        ;;
      -h|--help)
        show_project_help
        return
        ;;
      --)
        shift
        [[ $# -gt 0 ]] || die 'issues project requires a project key after --'
        [[ -z "${project_key}" ]] || die "Unexpected argument '$1'"
        project_key="$1"
        shift
        [[ $# -eq 0 ]] || die "Unexpected argument '$1'"
        ;;
      *)
        [[ -z "${project_key}" ]] || die "Unexpected argument '$1'"
        project_key="$1"
        shift
        ;;
    esac
  done

  [[ -n "${project_key}" ]] || die 'issues project requires a project key'
  [[ "${project_key}" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || die "Invalid Jira project key '${project_key}'"

  local jql="project = ${project_key}"
  if [[ -n "${status}" ]]; then
    local status_expression
    status_expression="$(jq -nr --arg status "${status}" '$status | @json')"
    jql="${jql} AND status = ${status_expression}"
  fi
  jql="${jql} ORDER BY updated DESC"

  search_issues "${jql}"
}

cmd_issues() {
  [[ $# -gt 0 ]] || { show_issues_help >&2; exit 1; }
  local command="$1"
  shift

  case "${command}" in
    due)
      cmd_issues_due "$@"
      ;;
    project)
      cmd_issues_project "$@"
      ;;
    assigned|mentioned|reported|recent|search)
      parse_list_options "$@"
      if [[ "${command}" != search ]]; then
        [[ ${#REMAINING_ARGUMENTS[@]} -eq 0 ]] || die "Unexpected argument '${REMAINING_ARGUMENTS[0]}'"
      fi
      local jql=""
      case "${command}" in
        assigned)
          jql='assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC'
          ;;
        mentioned)
          jql='watcher = currentUser() AND assignee != currentUser() AND statusCategory != Done ORDER BY updated DESC'
          ;;
        reported)
          jql='reporter = currentUser() AND statusCategory != Done ORDER BY updated DESC'
          ;;
        recent)
          jql='ORDER BY lastViewed DESC'
          ;;
        search)
          local query_part
          for query_part in "${REMAINING_ARGUMENTS[@]}"; do
            jql="${jql:+${jql} }${query_part}"
          done
          [[ -n "${jql}" ]] || die "issues search requires a JQL expression (try: $(basename "$0") issues search 'project = PROJ')"
          ;;
      esac
      search_issues "${jql}"
      ;;
    -h|--help)
      show_issues_help
      ;;
    *)
      die "Unknown issues command '${command}'"
      ;;
  esac
}
