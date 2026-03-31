# Dependency Update Pipeline — Plan

## Overview

Automated dependency update pipeline that scans repositories for outdated packages,
assesses breaking-change risk, applies updates in priority order, runs tests, and
opens PRs with detailed changelogs. Designed for teams managing multiple repos or
a monorepo with many packages.

---

## Agents

| Agent | Model | Role |
|---|---|---|
| **scanner** | claude-haiku-4-5 | Fast scan of package manifests, parse outdated output, classify update types (patch/minor/major) |
| **risk-assessor** | claude-sonnet-4-6 | Assess breaking-change risk per dependency using changelogs, release notes, and known issues. Uses sequential-thinking for structured risk analysis |
| **update-planner** | claude-sonnet-4-6 | Generate prioritized update plan — group safe patches, isolate risky majors, determine update order to avoid conflicts |
| **updater** | claude-sonnet-4-6 | Apply updates, resolve lockfile conflicts, handle peer dependency issues. Creates feature branches via GitHub MCP |
| **test-runner-analyst** | claude-haiku-4-5 | Analyze test output, classify failures (flaky vs real regression vs unrelated), recommend proceed/rollback |
| **pr-author** | claude-sonnet-4-6 | Write detailed PR descriptions with changelogs, breaking changes, migration notes, and compatibility matrix |

## MCP Servers

| Server | Purpose |
|---|---|
| `filesystem` | Read/write package.json, lockfiles, config, reports |
| `github` (gh-cli-mcp) | Create branches, open PRs, check CI status, read repo metadata |
| `sequential-thinking` | Structured risk assessment and update planning |

---

## Workflows

### 1. `dependency-scan` (primary workflow)

Full pipeline: scan -> assess -> plan -> update -> test -> PR.

**Phases:**

1. **scan-outdated** (command)
   - Runs `npm outdated --json` and `npx npm-check-updates --jsonUpgraded` against the target repo
   - Writes raw scan results to `data/scan-results.json`
   - Also checks for known vulnerabilities via `npm audit --json`
   - Timeout: 120s

2. **classify-updates** (agent: scanner)
   - Reads scan results, classifies each dependency:
     - Type: patch / minor / major
     - Category: runtime / dev / peer / optional
     - Has known CVE: yes / no
   - Writes `data/classified-updates.json`
   - If no outdated packages found, outputs verdict: `up-to-date` (terminates)

3. **assess-risk** (agent: risk-assessor)
   - For each major/minor update, uses sequential-thinking to evaluate:
     - Changelog analysis (breaking changes listed?)
     - Ecosystem impact (how many dependents affected?)
     - Historical update difficulty (has this package broken things before?)
   - Writes `data/risk-assessment.json` with per-dependency risk scores
   - Decision contract: `update-risk`
     - `safe` — all updates are low-risk patches → proceed to bulk update
     - `mixed` — mix of safe and risky → proceed to planning phase
     - `high-risk` — critical breaking changes detected → needs careful planning

4. **plan-updates** (agent: update-planner)
   - Groups updates into batches:
     - Batch 1: All safe patches (can be applied together)
     - Batch 2: Minor updates grouped by ecosystem (e.g., all React-related)
     - Batch 3+: Individual major updates (one per batch)
   - Orders batches by priority: security fixes first, then patches, then minors, then majors
   - Writes `data/update-plan.json`

5. **apply-updates** (agent: updater)
   - Creates a feature branch via GitHub MCP
   - Applies updates batch by batch per the plan
   - Runs `npm install` after each batch to resolve lockfile
   - Handles peer dependency conflicts (records any manual resolutions needed)
   - Writes `data/applied-updates.json` with what was actually changed
   - Commits changes to the feature branch

6. **run-tests** (command)
   - Runs the project's test suite: `npm test` (or configured test command)
   - Captures stdout/stderr to `data/test-output.txt`
   - Writes exit code to `data/test-result.json`
   - Timeout: 300s

7. **analyze-test-results** (agent: test-runner-analyst)
   - Reads test output, classifies result:
     - Which tests failed and why
     - Are failures related to the updates or pre-existing?
     - Are any failures flaky (known flaky tests from config)?
   - Decision contract: `test-result`
     - `passing` — all tests pass → proceed to PR
     - `flaky` — only known-flaky tests failed → proceed with note
     - `failing` — real regressions detected → rework (roll back risky batch, retry)
     - `broken` — test infra itself broken → skip, report issue
   - On `failing`: rework goes back to `apply-updates` with instructions to exclude the failing batch

8. **create-pr** (agent: pr-author)
   - Reads all data files to compile PR:
     - Title: "chore(deps): update N packages (YYYY-MM-DD)"
     - Body includes: summary table, per-dependency changelog excerpts, risk assessment highlights, test results, migration notes for breaking changes
   - Creates PR via GitHub MCP
   - Writes `output/pr-summary.json` with PR URL and details

**Routing:**

```
scan-outdated → classify-updates
  └─ up-to-date → (terminate)
  └─ has-updates → assess-risk
      └─ safe → plan-updates → apply-updates → run-tests → analyze-test-results
      └─ mixed → plan-updates → apply-updates → run-tests → analyze-test-results
      └─ high-risk → plan-updates → apply-updates → run-tests → analyze-test-results
          analyze-test-results:
            └─ passing → create-pr
            └─ flaky → create-pr
            └─ failing → rework → apply-updates (max 3 attempts)
            └─ broken → (terminate with report)
```

### 2. `quick-audit` (lightweight workflow)

Fast check that just scans and reports — no updates applied.

**Phases:**

1. **scan-outdated** (reused command phase)
2. **classify-updates** (reused agent phase)
3. **generate-audit-report** (agent: pr-author)
   - Writes a markdown report of all outdated deps with risk levels
   - Output: `output/audit-report.md`

---

## Directory Structure

```
dependency-updater/
├── .ao/
│   └── workflows/
│       ├── agents.yaml
│       ├── phases.yaml
│       ├── workflows.yaml
│       ├── mcp-servers.yaml
│       └── schedules.yaml
├── config/
│   ├── targets.json          # List of repos/packages to scan
│   ├── policy.json           # Update policy (auto-merge patches, review majors, etc.)
│   └── known-flaky-tests.json # Tests to ignore in analysis
├── data/                     # Runtime data (written by agents)
│   └── .gitkeep
├── output/                   # Generated artifacts
│   └── .gitkeep
├── scripts/
│   ├── scan-outdated.sh      # Scan script for command phase
│   └── run-tests.sh          # Test runner script for command phase
├── CLAUDE.md
└── README.md
```

---

## Config Files

### config/targets.json
```json
{
  "repos": [
    {
      "name": "my-app",
      "path": "./target-repo",
      "test_command": "npm test",
      "package_manager": "npm",
      "auto_merge_policy": "patch-only"
    }
  ],
  "scan_options": {
    "include_dev": true,
    "include_optional": false,
    "ignore_packages": ["@types/*"]
  }
}
```

### config/policy.json
```json
{
  "auto_merge": {
    "patch": true,
    "minor": false,
    "major": false
  },
  "security": {
    "auto_merge_critical_patches": true,
    "block_on_high_severity_cve": true
  },
  "batching": {
    "max_packages_per_pr": 20,
    "group_by_ecosystem": true,
    "isolate_major_updates": true
  },
  "testing": {
    "required_before_pr": true,
    "max_rework_attempts": 3,
    "known_flaky_test_patterns": []
  }
}
```

---

## Schedules

| Schedule | Cron | Workflow | Purpose |
|---|---|---|---|
| `weekly-scan` | `0 9 * * 1` | dependency-scan | Full scan + update every Monday 9am |
| `daily-audit` | `0 8 * * *` | quick-audit | Lightweight audit report daily at 8am |

---

## AO Features Demonstrated

- **Command phases** — `scan-outdated` and `run-tests` use real CLI tools (npm, npx)
- **Multi-agent pipeline** — 6 specialized agents with different models
- **Multi-model routing** — Haiku for fast parsing/classification, Sonnet for analysis/planning
- **Decision contracts** — `update-risk` (safe/mixed/high-risk), `test-result` (passing/flaky/failing/broken), `classify` (up-to-date/has-updates)
- **Rework loops** — Test failures trigger rollback and retry (max 3 attempts)
- **Early termination** — Up-to-date repos skip the entire pipeline
- **Scheduled workflows** — Weekly full scans, daily lightweight audits
- **GitHub MCP integration** — Branch creation, PR authoring, CI status checks
- **Sequential-thinking** — Structured risk assessment reasoning
- **Reusable phases** — `scan-outdated` and `classify-updates` shared across workflows

---

## Sample Output

### PR Description (generated by pr-author)
```markdown
## chore(deps): update 12 packages (2026-03-31)

### Summary
| Package | From | To | Type | Risk |
|---|---|---|---|---|
| express | 4.18.2 | 4.19.0 | minor | low |
| typescript | 5.3.3 | 5.4.2 | minor | medium |
| react | 18.2.0 | 19.0.0 | major | high |
| lodash | 4.17.20 | 4.17.21 | patch | low |
...

### Batch 1: Safe Patches (auto-merged)
- lodash 4.17.20 → 4.17.21 (security fix: prototype pollution)
- ...

### Batch 2: Minor Updates
- express 4.18.2 → 4.19.0 (new: res.redirect accepts URL objects)
- typescript 5.3.3 → 5.4.2 (new: NoInfer utility type)

### Batch 3: Major Updates (review required)
- react 18.2.0 → 19.0.0
  - **Breaking:** useContext no longer needs Provider wrapper
  - **Migration:** See react.dev/blog/2026/03/react-19-upgrade-guide

### Test Results
✅ 142 passing | ⚠️ 1 flaky (known) | ❌ 0 failing

### Risk Assessment
Overall risk: **medium** — react@19 major update requires manual review
```
