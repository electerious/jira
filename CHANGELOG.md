# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0/).

## [1.0.0] - 2026-10-26

### Added

- Search Jira with assigned, mentioned, reported, recently viewed, or custom JQL queries
- List your open issues due soon with `jira issues due` and filter project issues with `jira issues project`
- View selected issue details with `jira issue info`; use `--verbose` to include every available field and changelog entry
- Get selected issue details as JSON, or use `--json --verbose` for the complete Jira REST response
- Read issue comments and change history with `jira issue comments` and `jira issue history`
- View parent, subtasks, and linked issues with `jira issue links`
- Open Jira issues in a browser by issue key or URL
