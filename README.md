# dependency-updater

Automated dependency update pipeline that scans repos for outdated packages, assesses breaking-change risk per dependency, applies updates in safe batches, runs the test suite, and opens detailed PRs via the GitHub CLI.

## Workflow Diagram

```
                         ┌─────────────────┐
                         │  scan-outdated   │  (command: npm outdated + npm audit)
                         └────────┬────────┘
                                  │
                         ┌────────▼────────┐
                         │ classify-updates │  (scanner / haiku)
                         └────────┬────────┘
                                  │
                     ┌────────────┴────────────┐
                     │ up-to-date              │ has-updates
                     ▼                         ▼
                  (done)             ┌─────────────────┐
                                     │   assess-risk    │  (risk-assessor / sonnet)
                                     └────────┬────────┘
                                              │
                                     ┌────────▼────────┐
                                     │  plan-updates    │  (update-planner / sonnet)
                                     └────────┬────────┘
                                              │
                                     ┌────────▼────────┐
                              ┌──────│  apply-updates   │◄──────────────┐
                              │      └────────┬────────┘               │
                              │               │                         │ rework
                              │      ┌────────▼────────┐               │ (max 3x)
                              │      │   run-tests      │  (command)    │
                              │      └────────┬────────┘               │
                              │               │                         │
                              │      ┌────────▼────────┐               │
                              │      │analyze-test-res  │  (analyst)    │
                              │      └────────┬────────┘               │
                              │               │                         │
                              │    ┌──────────┼──────────┐             │
                              │    │          │          │             │
                              │  passing   flaky      failing──────────┘
                              │    │          │
                              │    └────┬─────┘
                              │         │
                              │  ┌──────▼──────┐         broken
                              │  │  create-pr  │  ◄──── (terminate)
                              └─►│  (pr-author)│
                                 └─────────────┘
```

### quick-audit (lightweight, read-only)

```
scan-outdated → classify-updates → generate-audit-report → output/audit-report.md
```

## Quick Start

```bash
cd examples/dependency-updater

# 1. Point the scanner at your repo
edit config/targets.json  # set repos[0].path to your repo

# 2. Set your GitHub token
export GH_TOKEN=<your-token>

# 3. Start the daemon
ao daemon start

# 4. Run a full update cycle
ao queue enqueue \
  --title "dependency-updater" \
  --description "Scan and update all outdated packages" \
  --workflow-ref dependency-scan

# OR run a quick audit (no changes made)
ao queue enqueue \
  --title "dependency-updater" \
  --description "Quick audit only" \
  --workflow-ref quick-audit
```

Scheduled runs happen automatically:
- **Daily at 8am** — quick audit, report only
- **Monday at 9am** — full update pipeline with PR

## Agents

| Agent | Model | Role |
|---|---|---|
| **scanner** | claude-haiku-4-5 | Parses npm outdated/audit output, classifies each package by update type (patch/minor/major), category (runtime/dev), and CVE presence |
| **risk-assessor** | claude-sonnet-4-6 | Researches changelogs and release notes, uses sequential-thinking to score each update's breaking-change risk |
| **update-planner** | claude-sonnet-4-6 | Groups updates into ordered batches: security patches first, then safe patches, then minors, then one-at-a-time majors |
| **updater** | claude-sonnet-4-6 | Creates a feature branch via GitHub MCP, applies batch updates to package.json, commits each batch separately |
| **test-runner-analyst** | claude-haiku-4-5 | Reads test output, distinguishes real regressions from flaky tests, recommends which batch to rollback if needed |
| **pr-author** | claude-sonnet-4-6 | Writes comprehensive PR descriptions with changelogs, breaking changes, migration steps, and test results |

## AO Features Demonstrated

- **Command phases** — `scan-outdated` and `run-tests` invoke real CLI tools (`npm outdated`, `npm audit`, `npm install`, `npm test`)
- **Multi-agent pipeline** — 6 specialized agents in sequence, each with a focused role
- **Multi-model routing** — Haiku for fast classification tasks, Sonnet for deep analysis
- **Decision contracts** — `classify-updates` (up-to-date/has-updates), `assess-risk` (safe/mixed/high-risk), `analyze-test-results` (passing/flaky/failing/broken)
- **Rework loops** — Test failures route back to `apply-updates` with instructions to exclude the failing batch (max 3 attempts)
- **Early termination** — Up-to-date repos skip the entire pipeline immediately after scanning
- **Scheduled workflows** — Weekly full scans, daily lightweight audits
- **GitHub MCP integration** — Branch creation, PR authoring, label management
- **Sequential-thinking MCP** — Structured reasoning chains for risk assessment
- **Reusable phases** — `scan-outdated` and `classify-updates` shared across both workflows

## Requirements

| Requirement | Details |
|---|---|
| **GH_TOKEN** | GitHub personal access token with `repo` scope |
| **Node.js** | v18+ required for npm scan commands |
| **Target repo** | Path set in `config/targets.json` must have a `package.json` |
| **gh CLI** | Must be installed (`brew install gh`) and authenticated |

## Configuration

### `config/targets.json`
Define which repo to scan. Set `path` to the local checkout of your repository.

### `config/policy.json`
Controls auto-merge behavior (patch-only by default), batching rules, and PR settings.

### `config/known-flaky-tests.json`
Add test name patterns here to prevent flaky tests from blocking the update pipeline.

## Output Files

| File | Description |
|---|---|
| `data/scan-results.json` | Raw npm outdated output |
| `data/audit-results.json` | Raw npm audit output |
| `data/classified-updates.json` | Classified packages (type, category, CVE) |
| `data/risk-assessment.json` | Per-package risk scores and breaking change analysis |
| `data/update-plan.json` | Ordered batches with rollback instructions |
| `data/applied-updates.json` | What was actually changed, branch name, commit messages |
| `data/test-output.txt` | Full test suite stdout/stderr |
| `data/test-analysis.json` | Failure classification and rollback recommendation |
| `output/pr-summary.json` | PR URL, number, and summary stats |
| `output/audit-report.md` | Standalone markdown report (quick-audit workflow) |
