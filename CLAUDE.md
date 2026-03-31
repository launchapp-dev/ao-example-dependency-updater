# Dependency Updater — Agent Context

## What This Project Does

This is an AO workflow that automates dependency management for Node.js projects. It scans a target
repository for outdated packages, assesses the risk of upgrading each one, applies updates in safe
batches, runs the test suite, and opens a detailed GitHub PR.

## Directory Layout

```
dependency-updater/
├── .ao/workflows/          # AO workflow definitions
├── config/
│   ├── targets.json        # Which repo to scan (set repos[0].path to your repo)
│   ├── policy.json         # Update policy (auto-merge rules, batching strategy)
│   └── known-flaky-tests.json  # Test patterns to ignore during CI analysis
├── data/                   # Runtime: written by agents during execution (gitignored patterns)
│   ├── scan-results.json       # npm outdated output
│   ├── audit-results.json      # npm audit output
│   ├── classified-updates.json # Scanner's classification
│   ├── risk-assessment.json    # Risk-assessor's scoring
│   ├── update-plan.json        # Planner's batch strategy
│   ├── applied-updates.json    # What updater actually changed
│   ├── test-output.txt         # Raw test suite output
│   └── test-analysis.json      # Test analyst's verdict
├── output/                 # Final artifacts
│   ├── pr-summary.json         # PR URL and stats
│   └── audit-report.md         # Standalone audit report (quick-audit workflow)
├── scripts/
│   ├── scan-outdated.sh    # Runs npm outdated + npm audit against target repo
│   └── run-tests.sh        # Runs npm install + npm test against target repo
├── CLAUDE.md               # This file
└── README.md
```

## Agents and Their Responsibilities

**scanner (haiku)** — Speed-optimized classifier. Reads raw JSON from npm outdated and npm audit.
Produces a structured list of every outdated package with update_type (patch/minor/major), category
(runtime/dev/peer), and CVE flag. Does NOT analyze changelogs — that's risk-assessor's job.

**risk-assessor (sonnet)** — Deep analyst. Uses sequential-thinking MCP to reason through each
major and minor update. Fetches changelogs from the web using the fetch MCP server. Produces a
risk score (low/medium/high/critical) with justification. Patches automatically get "low".

**update-planner (sonnet)** — Strategist. Groups packages into ordered batches to minimize
the chance of test failures. Security patches first, then safe patches, then minors by ecosystem,
then one major at a time. Documents rollback commands for each batch.

**updater (sonnet)** — Executor. Creates a feature branch via GitHub MCP. Applies updates by
editing package.json and committing each batch separately. Does NOT run npm install —
that's handled by the run-tests command phase.

**test-runner-analyst (haiku)** — Classifier. Reads raw test output and exit code. Checks failures
against known-flaky-tests.json. Outputs one of: passing/flaky/failing/broken. "failing" triggers
a rework loop back to apply-updates (max 3 attempts).

**pr-author (sonnet)** — Writer. Reads all data files and produces a comprehensive PR description
with a summary table, changelog excerpts, breaking change migration notes, test results, and
rollback instructions. Creates the PR via GitHub MCP and sets appropriate labels.

## Workflows

**dependency-scan** (default) — Full pipeline. Runs on a schedule every Monday at 9am.
Terminates early if all packages are up-to-date.

**quick-audit** — Read-only. Just scans and generates a markdown report. Runs daily at 8am.
Does not apply any changes or create PRs.

## Important Notes for Agents

- The `data/` directory is ephemeral runtime state — always re-read it fresh, don't rely on cached state
- If `data/scan-results.json` is empty or contains `{}`, the target repo is up-to-date — output "up-to-date" verdict
- The target repo path is in `config/targets.json` — read it before trying to access any target repo files
- All data files use ISO 8601 timestamps (e.g., "2026-03-31T09:00:00Z")
- The updater modifies package.json but does NOT run npm install — the run-tests command phase does that
- If a rework is triggered (test failures), the updater should read its previous applied-updates.json
  and exclude the batch identified as the likely cause by the test-runner-analyst
- GitHub MCP operations require GH_TOKEN environment variable to be set
