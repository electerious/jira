# Comments, history, links, and browser commands for individual issues.

show_comments_help() {
  cat <<EOF
Usage: $(basename "$0") issue comments KEY [OPTIONS]

Options:
  --json          Print comments as JSON
  --limit NUMBER  Maximum comments to return (default: 100, maximum: 1000)
  -h, --help      Show this help message
EOF
}

show_history_help() {
  cat <<EOF
Usage: $(basename "$0") issue history KEY [OPTIONS]

Options:
  --json          Print history as JSON
  --limit NUMBER  Maximum history entries (default: 20, maximum: 1000)
  -h, --help      Show this help message
EOF
}

show_links_help() {
  cat <<EOF
Usage: $(basename "$0") issue links KEY [--json]

Options:
  --json      Print linked issue details as JSON
  -h, --help  Show this help message
EOF
}

show_issue_help() {
  cat <<EOF
Usage: $(basename "$0") issue COMMAND

Commands:
  info KEY [OPTIONS]       Show key issue fields
  comments KEY [OPTIONS]   List issue comments
  history KEY [OPTIONS]    List issue change history
  links KEY [--json]       Show parent, subtasks, and linked issues
  open KEY_OR_URL          Open an issue in your browser
EOF
}

cmd_issue_comments() {
  parse_issue_read_options 100 true "$@"
  if [[ "${ISSUE_READ_HELP}" == true ]]; then
    show_comments_help
    return
  fi

  [[ -n "${ISSUE_READ_KEY}" ]] || die 'issue comments requires a Jira issue key'
  validate_issue_key "${ISSUE_READ_KEY}"
  load_credentials

  local body
  body="$(jira_api_get "/rest/api/2/issue/${ISSUE_READ_KEY}/comment" \
    --data-urlencode 'startAt=0' \
    --data-urlencode "maxResults=${ISSUE_READ_LIMIT}")"
  printf '%s' "${body}" | jq -e 'type == "object" and (.comments | type == "array")' >/dev/null 2>&1 || die 'Jira returned an unexpected comments response'

  if [[ "${ISSUE_READ_JSON}" == true ]]; then
    printf '%s' "${body}" | jq --arg key "${ISSUE_READ_KEY}" '{
      key: $key,
      startAt: (.startAt // 0),
      maxResults: (.maxResults // (.comments | length)),
      total: (.total // (.comments | length)),
      comments: [.comments[] | {
        id,
        author: (.author.displayName // .author.name // "Unknown author"),
        created,
        updated,
        body
      }]
    }'
    return
  fi

  printf '%s' "${body}" | jq -r --arg key "${ISSUE_READ_KEY}" '
    def comment_text: if type == "string" then . else tojson end;
    if (.comments | length) == 0 then
      "No comments on \($key)."
    else
      "Comments on \($key) (showing \(.comments | length) of \(.total // (.comments | length))):",
      (.comments[] |
        "- \(.author.displayName // .author.name // "Unknown author") · \(.created // "Unknown date")\n  \((.body // "") | comment_text | split("\n") | map("  " + .) | join("\n"))"
      )
    end
  '
}

cmd_issue_history() {
  parse_issue_read_options 20 true "$@"
  if [[ "${ISSUE_READ_HELP}" == true ]]; then
    show_history_help
    return
  fi

  [[ -n "${ISSUE_READ_KEY}" ]] || die 'issue history requires a Jira issue key'
  validate_issue_key "${ISSUE_READ_KEY}"
  load_credentials

  local body history
  body="$(jira_api_get "/rest/api/2/issue/${ISSUE_READ_KEY}" \
    --data-urlencode 'fields=summary' \
    --data-urlencode 'expand=changelog')"
  printf '%s' "${body}" | jq -e 'type == "object" and (.changelog.histories | type == "array")' >/dev/null 2>&1 || die 'Jira returned an unexpected history response'
  history="$(printf '%s' "${body}" | jq --arg key "${ISSUE_READ_KEY}" --argjson limit "${ISSUE_READ_LIMIT}" '
    . as $issue
    | ($issue.changelog.histories // []) as $all
    | ($all | length) as $returned
    | ($all | .[-$limit:]) as $selected
    | {
        key: $key,
        startAt: (($issue.changelog.startAt // 0) + ($returned - ($selected | length))),
        maxResults: ($selected | length),
        total: ($issue.changelog.total // $returned),
        histories: [$selected[] | {
          id,
          created,
          author: (.author.displayName // .author.name // "Unknown author"),
          items: [(.items // [])[] | {
            field,
            from: (.fromString // .from),
            to: (.toString // .to)
          }]
        }]
      }
  ')"

  if [[ "${ISSUE_READ_JSON}" == true ]]; then
    printf '%s\n' "${history}" | jq .
    return
  fi

  printf '%s\n' "${history}" | jq -r --arg key "${ISSUE_READ_KEY}" '
    if (.histories | length) == 0 then
      "No change history for \($key)."
    else
      "History for \($key) (latest \(.histories | length) of \(.total // (.histories | length))):",
      (.histories[] |
        "- \(.created // "Unknown date") · \(.author // "Unknown author")\n\((.items // []) | map("  \(.field // "Field"): \(.from // "—") → \(.to // "—")") | join("\n"))"
      )
    end
  '
}

cmd_issue_links() {
  parse_issue_read_options 0 false "$@"
  if [[ "${ISSUE_READ_HELP}" == true ]]; then
    show_links_help
    return
  fi

  [[ -n "${ISSUE_READ_KEY}" ]] || die 'issue links requires a Jira issue key'
  validate_issue_key "${ISSUE_READ_KEY}"
  load_credentials

  local body links
  body="$(jira_api_get "/rest/api/2/issue/${ISSUE_READ_KEY}" \
    --data-urlencode 'fields=issuelinks,parent,subtasks')"
  printf '%s' "${body}" | jq -e 'type == "object" and (.key | type == "string") and (.fields | type == "object")' >/dev/null 2>&1 || die 'Jira returned an unexpected issue response'

  links="$(printf '%s' "${body}" | jq '
    def issue_summary($issue): {
      key: $issue.key,
      summary: ($issue.fields.summary // ""),
      status: ($issue.fields.status.name // null),
      issue_type: ($issue.fields.issuetype.name // null)
    } | with_entries(select(.value != null));

    {
      key,
      parent: (if .fields.parent == null then null else issue_summary(.fields.parent) end),
      subtasks: [(.fields.subtasks // [])[] | issue_summary(.)],
      links: [(.fields.issuelinks // [])[] |
        if .outwardIssue != null then
          {relationship: (.type.outward // .type.name // "Related"), issue: issue_summary(.outwardIssue)}
        elif .inwardIssue != null then
          {relationship: (.type.inward // .type.name // "Related"), issue: issue_summary(.inwardIssue)}
        else empty
        end
      ]
    }
  ')"

  if [[ "${ISSUE_READ_JSON}" == true ]]; then
    printf '%s\n' "${links}" | jq .
    return
  fi

  printf '%s\n' "${links}" | jq -r '
    if .parent == null and (.subtasks | length) == 0 and (.links | length) == 0 then
      "No parent, subtasks, or linked issues for \(.key)."
    else
      "Issue \(.key)",
      (if .parent == null then empty else "Parent: \(.parent.key) · \(.parent.summary)" end),
      (if (.subtasks | length) == 0 then empty else "Subtasks:" end),
      (.subtasks[] | "- \(.key) · \(.summary) · \(.status // "Unknown")"),
      (if (.links | length) == 0 then empty else "Linked issues:" end),
      (.links[] | "- \(.relationship): \(.issue.key) · \(.issue.summary) · \(.issue.status // "Unknown")")
    end
  '
}

cmd_open() {
  [[ $# -eq 1 ]] || die 'issue open requires an issue key or URL'
  local input="$1"
  local url

  load_credentials
  if [[ "${input}" == http://* || "${input}" == https://* ]]; then
    url="${input}"
  else
    validate_issue_key "${input}" "Invalid Jira issue key or URL '${input}'"
    url="https://${JIRA_DOMAIN}/browse/${input}"
  fi

  command -v open >/dev/null 2>&1 || die "The 'open' command is required to launch the browser"
  open "${url}"
  printf 'Opened issue: %s\n' "${url}"
}
