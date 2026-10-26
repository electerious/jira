# Detailed issue information output.

show_info_help() {
  cat <<EOF
Usage: $(basename "$0") issue info KEY [OPTIONS]

Options:
  --json       Print selected fields as JSON
  --verbose    Show all available fields and changelog entries
  -h, --help   Show this help message
EOF
}

cmd_info() {
  local issue_key=""
  local json_output=false
  local verbose=false
  local body

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        json_output=true
        shift
        ;;
      --verbose)
        verbose=true
        shift
        ;;
      -h|--help)
        show_info_help
        return
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          [[ -z "${issue_key}" ]] || die "Unexpected argument '$1'"
          issue_key="$1"
          shift
        done
        ;;
      *)
        [[ -z "${issue_key}" ]] || die "Unexpected argument '$1'"
        issue_key="$1"
        shift
        ;;
    esac
  done

  [[ -n "${issue_key}" ]] || die 'issue info requires a Jira issue key'
  validate_issue_key "${issue_key}"
  load_credentials

  # This endpoint is read-only; all fields and the issue changelog are requested.
  body="$(jira_api_get "/rest/api/2/issue/${issue_key}" \
    --data-urlencode 'fields=*all' \
    --data-urlencode 'expand=names,renderedFields,changelog')"

  printf '%s' "${body}" | jq -e 'type == "object" and (.key | type == "string") and (.fields | type == "object")' >/dev/null 2>&1 || die 'Jira returned an unexpected issue response'

  if [[ "${json_output}" == true && "${verbose}" == true ]]; then
    printf '%s' "${body}" | jq .
    return
  fi

  if [[ "${json_output}" == true ]]; then
    printf '%s' "${body}" | jq '
      def user_name($user):
        if $user == null then null
        else ($user.displayName // $user.name // $user.key // null)
        end;

      def issue_reference($value):
        if $value == null then null
        elif ($value | type) == "object" then
          ({
            key: ($value.key // $value.value // $value.name // null),
            summary: ($value.fields.summary // $value.summary // null)
          } | with_entries(select(.value != null)))
        else {key: $value}
        end;

      (.names // {} | to_entries | map(select((.value | ascii_downcase) == "epic link") | .key) | .[0] // null) as $epic_id
      | . as $issue
      | $issue.fields as $fields
      | {
          key: $issue.key,
          fields: {
            summary: $fields.summary,
            status: $fields.status.name,
            issuetype: $fields.issuetype.name,
            priority: $fields.priority.name,
            assignee: user_name($fields.assignee),
            reporter: user_name($fields.reporter),
            created: $fields.created,
            updated: $fields.updated,
            resolution: $fields.resolution.name,
            duedate: $fields.duedate,
            parent_or_epic: (
              if $fields.parent != null then
                ({
                  key: $fields.parent.key,
                  summary: $fields.parent.fields.summary
                } | with_entries(select(.value != null)))
              elif $epic_id != null then issue_reference($fields[$epic_id])
              else null
              end
            ),
            components: [($fields.components // [])[] | .name],
            labels: ($fields.labels // []),
            fixVersions: [($fields.fixVersions // [])[] | .name],
            description: $fields.description
          }
        }
    '
    return
  fi

  if [[ "${verbose}" == false ]]; then
    printf '%s' "${body}" | jq -r '
      def human_value:
        if . == null then ""
        elif type == "string" then .
        elif type == "number" or type == "boolean" then tostring
        elif type == "array" then map(human_value) | map(select(length > 0)) | join(", ")
        elif (.displayName? // null) != null then .displayName | human_value
        elif (.value? // null) != null then .value | human_value
        elif (.name? // null) != null then .name | human_value
        elif (.key? // null) != null then .key | human_value
        elif (.text? // null) != null then .text | human_value
        elif (.content? // null) != null then .content | human_value
        else tojson
        end;

      def field_line($label; $value):
        ($value | human_value) as $text
        | if $text == "" then null
          else "\($label):\n\($text | split("\n") | map("  " + .) | join("\n"))"
          end;

      (.names // {} | to_entries | map(select((.value | ascii_downcase) == "epic link") | .key) | .[0] // null) as $epic_id
      | . as $issue
      | $issue.fields as $fields
      | [
          "Issue \($issue.key) — \(($fields.summary // "(no summary)") | gsub("[\\r\\n]+"; " "))",
          "",
          field_line("Status"; $fields.status.name),
          field_line("Type"; $fields.issuetype.name),
          field_line("Priority"; $fields.priority.name),
          field_line("Assignee"; ($fields.assignee.displayName // $fields.assignee.name)),
          field_line("Reporter"; ($fields.reporter.displayName // $fields.reporter.name)),
          field_line("Created"; $fields.created),
          field_line("Updated"; $fields.updated),
          field_line("Resolution"; $fields.resolution.name),
          field_line("Due date"; $fields.duedate),
          field_line(
            "Parent/Epic";
            if $fields.parent != null then
              [($fields.parent.key // ""), ($fields.parent.fields.summary // "")]
              | map(select(. != ""))
              | join(" — ")
            elif $epic_id != null then $fields[$epic_id]
            else null
            end
          ),
          field_line("Components"; ($fields.components // [] | map(.name))),
          field_line("Labels"; $fields.labels),
          field_line("Fix versions"; ($fields.fixVersions // [] | map(.name))),
          field_line("Description"; $fields.description)
        ]
      | .[]
      | select(. != null)
    '
    return
  fi

  printf '%s' "${body}" | jq -r '
    def human_value:
      if . == null then ""
      elif type == "string" then .
      elif type == "number" or type == "boolean" then tostring
      elif type == "array" then map(human_value) | map(select(length > 0)) | join(", ")
      elif (.displayName? // null) != null then .displayName | human_value
      elif (.value? // null) != null then .value | human_value
      elif (.name? // null) != null then .name | human_value
      elif (.key? // null) != null then .key | human_value
      elif (.text? // null) != null then .text | human_value
      elif (.content? // null) != null then .content | human_value
      else tojson
      end;

    . as $issue
    | [
        "Issue \($issue.key)",
        "URL: \($issue.self | sub("/rest/api/2/issue/.*$"; "/browse/\($issue.key)"))",
        "",
        "Fields:"
      ]
      + (
        ($issue.names // {}) as $names
        | ($issue.fields // {})
        | to_entries
        | sort_by(($names[.key] // .key) | ascii_downcase)
        | map(
            .key as $field_id
            | (.value | human_value) as $value
            | select($value != "")
            | "\($names[$field_id] // $field_id):\n\($value | split("\n") | map("  " + .) | join("\n"))"
          )
      )
      + (
        ($issue.changelog.histories // []) as $histories
        | if ($histories | length) == 0 then []
          else
            ["", "Changelog:"] + [
              $histories[]
              | "\(.created // "Unknown date") · \(.author.displayName // .author.name // "Unknown author")\n\((.items // []) | map("  \(.field // .fieldId // "Field"): \(.fromString // .from // "—") → \(.toString // .to // "—")") | join("\n"))"
            ]
          end
      )
    | .[]
  '
}
