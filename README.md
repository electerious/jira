<div align="center">

# jira

Search, inspect, and open Jira issues from the command line.

<br/>

![jira in action](https://s.electerious.com/images/jira/readme.png)

</div>

## Contents

- [Description](#description)
- [Requirements](#requirements)
- [Install](#install)
- [Usage](#usage)
- [Configuration](#configuration)
- [Development](#development)
- [Troubleshooting](#troubleshooting)

## Description

`jira` is a macOS CLI for searching Jira issues, viewing all available issue fields and changelog entries, and opening issues in a browser. Jira operations are read-only; the CLI does not modify issues. It supports readable terminal output and JSON.

## Requirements

- macOS
- Bash 3.2 or newer (included with macOS)
- `curl` and [`jq`](https://jqlang.org/)
- A Jira Server or Data Center personal access token

## Install

### Homebrew

Install with Homebrew from the [electerious tap](https://github.com/electerious/homebrew-tap):

```bash
brew tap electerious/tap
brew install jira
```

### From source

Clone the repository:

```bash
git clone <repository-url>
cd jira
```

Make the script executable:

```bash
chmod +x bin/jira
```

Run it directly:

```bash
bin/jira --help
```

Add it to your `PATH` (optional):

```bash
# Using symlink
sudo ln -s "$(pwd)/bin/jira" /usr/local/bin/jira

# Or add the bin directory to your shell profile
export PATH="$PATH:$(pwd)/bin"
```

## Usage

### List Issues

```bash
# Issues assigned to you
jira issues assigned

# Issues that mention you, excluding issues assigned to you
jira issues mentioned

# Issues reported by you
jira issues reported

# Recently viewed issues
jira issues recent
```

Use `--limit` to change the maximum number of results. The default is 25 and the maximum is 1000; Jira may enforce a lower instance limit:

```bash
jira issues assigned --limit 50
```

The `mentioned` command uses Jira's watcher list as a proxy for @mentions.

List your open issues that are due within the next week, or set a different window:

```bash
jira issues due
jira issues due --within 14d --limit 50
```

List issues from a project, optionally filtered by status:

```bash
jira issues project PROJ
jira issues project PROJ --status "In Progress"
```

### Search Issues

Pass a Jira Query Language (JQL) expression in quotes:

```bash
jira issues search 'project = PROJ AND status = "In Progress"'
jira issues search 'assignee = currentUser() ORDER BY updated DESC'
```

### View Issue Details

`issue info` shows the issue key and summary, status, type, priority, assignee, reporter, created and updated dates, resolution, due date, parent or epic, components, labels, fix versions, and the full description. Empty fields are omitted:

```bash
jira issue info PROJ-123
```

Pass `--json` to return those selected fields as JSON. Use `--verbose` in either output mode to show every available field and changelog entry:

```bash
jira issue info PROJ-123 --json
jira issue info PROJ-123 --verbose
jira issue info PROJ-123 --json --verbose
```

### Read Comments and History

Comments return up to 100 entries by default. History returns the latest available page of up to 20 entries by default. Use `--limit` to adjust the page size and `--json` for JSON output:

```bash
jira issue comments PROJ-123
jira issue comments PROJ-123 --json --limit 50
jira issue history PROJ-123 --limit 20
jira issue history PROJ-123 --json
```

### View Issue Links

Show an issue's parent, subtasks, and linked issues:

```bash
jira issue links PROJ-123
jira issue links PROJ-123 --json
```

### Open an Issue

Open an issue by key or URL:

```bash
jira issue open PROJ-123
jira issue open https://your-instance.atlassian.net/browse/PROJ-123
```

### JSON Output

Add `--json` to issue list commands to get an array with each issue's key, summary, type, status, and URL:

```bash
jira issues assigned --json
jira issues search --json 'project = PROJ'
```

### Help and Version

```bash
jira --help
jira issues --help
jira issue info --help
jira --version
```

## Configuration

### Credentials

The CLI reads credentials from the same file as the existing Jira scripts:

```text
~/.config/jira/credentials
```

Create the file with these shell assignments:

```bash
JIRA_DOMAIN=your-instance.atlassian.net
JIRA_TOKEN=your-personal-access-token
```

Keep the token private. To use a different credentials file, set `JIRA_CREDENTIALS_FILE`:

```bash
export JIRA_CREDENTIALS_FILE="$HOME/.config/jira/credentials"
```

## Development

The executable in `bin/jira` loads shared helpers and command implementations from `lib/`.

Check the Bash script syntax from the project directory:

```bash
for script in bin/jira lib/*.sh; do
  bash -n "$script"
done
```

## Troubleshooting

**Credentials file not found**

Create `~/.config/jira/credentials` with `JIRA_DOMAIN` and `JIRA_TOKEN`, or set `JIRA_CREDENTIALS_FILE` to its location.

**Jira returns an authentication or permission error**

Check that the domain and personal access token are correct and that the account has permission to view the project and issue.

**`jq` is not installed**

Install `jq` with Homebrew:

```bash
brew install jq
```
