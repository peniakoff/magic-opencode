# Portable OpenCode engineering workflow

This directory contains a repository-agnostic workflow for web, mobile, API,
SaaS, data, and infrastructure projects. Agents discover the actual stack and
follow the target repository's `AGENTS.md`, manifests, CI, and conventions.
All versioned prompts, commands, helper messages, and documentation under
`.opencode/` use English consistently for reliable behavior across models.

## Operating model

- `orchestrator` owns scope, delegation, validation, review, and explicitly
  requested GitHub delivery. It cannot edit files.
- `implementer` is the only agent allowed to edit repository files.
- `research-explorer`, `architect`, `test-debugger`, `reviewer`,
  `browser-qa`, and `security-reviewer` are read-only specialists.
- Only independent read-only investigations may run in parallel. A single
  implementer owns every coherent patch, preventing overlapping writes.
- Specialists are called only when their distinct expertise affects the result;
  step limits bound unproductive loops and cost.

Commands:

- `/work <task>` — complete a local implementation and validation workflow
  without GitHub delivery.
- `/implement <GitHub issue URL>` — branch, implement, validate, review, push,
  open a PR, wait for Actions, squash-merge, and clean up.
- `/research`, `/design`, `/debug`, `/review`, `/qa`, and `/security`
  — focused report-only specialist workflows.

## Models

Project agents do not pin provider-specific model IDs. The primary agent uses
the model selected globally or for the current session, and subagents inherit
the primary agent's model. This keeps the pack reusable when providers rename
or retire models.

To opt into role-specific models on one machine, override only the required
agents in `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "agent": {
    "orchestrator": {
      "model": "provider/model-id"
    },
    "implementer": {
      "model": "provider/other-model-id"
    }
  }
}
```

Always select IDs reported by `opencode models`.

## MCP servers

The project `opencode.json` enables only two MCP servers:

- Context7 supplies current, version-aware library documentation to research,
  architecture, implementation, and diagnostic roles.
- Playwright MCP gives `browser-qa` persistent exploratory browser access.

Both tool families are denied globally and enabled only for the roles that need
them. GitHub uses the `gh` CLI instead of GitHub MCP because its concise,
deterministic output consumes less model context. Filesystem, memory, and
sequential-thinking MCPs are intentionally omitted because built-in tools and
repository evidence already cover those responsibilities.

### Context7 authentication

The public endpoint works without committing credentials. For higher rate
limits, add an API key only to the global config so it merges with the project
server definition:

```json
{
  "mcp": {
    "context7": {
      "headers": {
        "CONTEXT7_API_KEY": "{env:CONTEXT7_API_KEY}"
      }
    }
  }
}
```

Export `CONTEXT7_API_KEY` before starting OpenCode. Never store the value in
the repository.

### Playwright preflight

The Playwright MCP package is pinned to `0.0.80`. On a new machine, warm the
`npx` cache once before starting OpenCode:

```bash
npx -y @playwright/mcp@0.0.80 --help
opencode mcp list
```

`opencode mcp list` must finish and report both `playwright` and `context7`
as connected. If it hangs on first use, complete the package download and
restart OpenCode. Browser output is isolated under `.artifacts/playwright`
and ignored by Git and the OpenCode watcher.

`browser-qa` denies the RCE-equivalent
`playwright_browser_run_code_unsafe` tool. Use synthetic data and local,
preview, staging, or another explicitly approved environment; never assume
production is safe to operate.

## Testing policy

Unit and integration tests must use the runner and scripts declared by the
repository. Durable E2E coverage must be committed in the established framework
such as Playwright Test or Cypress. If required coverage has no runner yet, add
a normal dependency, configuration, script, and maintainable tests.

Playwright MCP is supplementary exploratory QA for user journeys, responsive
behavior, accessibility signals, console errors, and network failures. It is
not a replacement for repeatable tests. Agents must never create ad hoc Python,
Node.js, shell, or HTML scripts as a substitute for repository-native unit,
integration, or E2E coverage.

Required registry dependency changes use the trusted
`.opencode/scripts/dependency-update.sh` wrapper. It must be the first mutation
on a clean feature branch, accepts only validated package identifiers for npm,
Yarn, pnpm, or Bun, distinguishes runtime and development dependencies through
fixed actions, and always disables dependency lifecycle scripts. The resulting
wrapper also supports one validated mixed `batch` transaction and refuses
manager output outside manifests and lockfiles. The resulting manifest and lockfile return through
`inspect` and preliminary review before repository code runs. Project-specific
generators and migrations must be exposed as reviewed repository scripts with
an explicit local permission override, or run by the user; the portable pack
does not auto-approve arbitrary generators.

## GitHub delivery

Before using `/implement`, authenticate GitHub CLI:

```bash
gh auth login
gh auth status
```

Invoke the complete workflow from a clean checkout:

```text
/implement https://github.com/owner/repository/issues/123
```

The command accepts exactly one open issue from the current `origin`. It uses
a `feature/<issue-number>-<slug>` branch, one writer, repository-native tests,
independent review, a Conventional Commit, and a PR containing
`Closes #<issue-number>`. It refuses to merge without reported successful
GitHub Actions checks, a mergeable PR, and completed review. CI repair is
limited to two evidence-backed rounds. Success ends with squash merge, issue
closure verification, remote and local branch cleanup, a fast-forwarded local
`main`, and a clean working tree.

The workflow never stashes, resets, cleans, force-pushes, deploys, publishes, or
mutates cloud resources by implication.

### Process isolation boundary

OpenCode permissions constrain agent tool calls; they do not sandbox code run
by a repository's test or build scripts. Such code executes as the operating
system user and can read credentials available to that user. Run OpenCode in a
dedicated OS account, development container, or disposable VM with only the
minimum project credentials whenever the repository, dependencies, issue text,
or generated patch is not fully trusted. Do not keep unrelated production or
personal credentials in that execution environment. Independent review must
inspect package scripts, hooks, CI changes, and other executable inputs before
the orchestrator runs changed repository code.

All Git and GitHub mutations are routed through the versioned
`.opencode/scripts/github-delivery.sh` wrapper. It validates repository, issue,
branch, PR, status checks, review state, and the exact reviewed head SHA before
executing a bounded operation; raw mutation commands are denied to the
orchestrator. Its argument-free `inspect` action is the only shell-backed Git
inspection surface for read-only roles; it returns fixed branch, status,
changed-path, and diff evidence without accepting Git flags or paths.

## Reusing in another repository

1. Copy `opencode.json`, `.opencode/agents/`, `.opencode/commands/`,
   `.opencode/scripts/`, this README, and the `.artifacts/` ignore rule.
2. Do not copy `.opencode/package.json`, lockfiles, `node_modules/`, or other
   local OpenCode state.
3. Create a fresh project-specific `AGENTS.md` or run `/init`. Never copy
   another project's architecture, commands, privacy rules, or release policy
   unchanged.
4. Verify available models with `opencode models`. Project files require no
   edits unless you intentionally add role-specific overrides.
5. Warm the Playwright package cache, restart OpenCode, and validate:

```bash
opencode debug config
opencode agent list
opencode mcp list
```

Configuration, agents, commands, skills, and MCP servers are loaded at session
startup, so start a new session after changing the pack.
