# Portable OpenCode engineering workflow

This directory contains a repository-agnostic workflow for web, mobile, API,
SaaS, data, and infrastructure projects. Agents discover the actual stack and
follow the target repository's `AGENTS.md`, manifests, CI, and conventions.
All versioned prompts, commands, helper messages, and documentation under
`.opencode/` use English consistently for reliable behavior across models.

## Operating model

- `orchestrator` owns scope, delegation, validation, review, and explicitly
  requested GitHub delivery. It cannot edit files.
- `implementer` is the only agent type allowed to edit repository files.
- One implementer is the default. At most two implementer instances may run in
  parallel when their write scopes are proven independent and each works in a
  separate detached worktree managed by the trusted parallel-worktree wrapper.
- `research-explorer`, `architect`, `test-debugger`, `reviewer`,
  `browser-qa`, and `security-reviewer` are read-only specialists.
- Independent read-only investigations may run in parallel freely. Parallel
  implementation is deliberately narrower: disjoint scopes, no shared mutable
  contract, no dependency on the other lane's uncommitted output, and a final
  combined review and validation gate.
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

## Semantic codebase index

The project enables the `open-codebase-index` OpenCode plugin directly through
`opencode.json`. OpenCode installs configured npm plugins into its cache at
startup, so the target repository does not need to add this plugin to its own
application dependencies or lockfile.

Project configuration lives in `.opencode/codebase-index.json`. The initial
index is intentionally explicit (`autoIndex: false`) while file watching is
enabled after indexing. This avoids an unexpected expensive first scan while
still keeping an established index current during normal work.

On a new checkout, start OpenCode and run:

```text
/status
/index
```

The generated index is local runtime state under `.opencode/index/`; never
commit it. The supplied ignore rules also exclude that directory from the
OpenCode watcher. Current releases of `open-codebase-index` require Node.js
22.13 or newer; Node.js 24 LTS is the recommended runtime upstream.

Agent discovery follows a cost-aware order:

1. semantic context/peek when the location of behavior is unknown;
2. symbol lookup or call-graph tools for targeted structural questions;
3. LSP for exact definitions and references;
4. grep for exact or exhaustive textual matches.

If the index is unavailable, stale, or its embedding provider cannot start,
agents fall back to LSP and targeted repository search. Index availability is
never a correctness prerequisite.

## MCP servers

The project `opencode.json` enables two MCP servers in addition to the local
codebase-index plugin:

- Context7 supplies current, version-aware library documentation to research,
  architecture, implementation, and diagnostic roles.
- Playwright MCP gives `browser-qa` persistent exploratory browser access.

Both MCP tool families are denied globally and enabled only for the roles that
need them. GitHub uses the `gh` CLI instead of GitHub MCP because its concise,
deterministic output consumes less model context. Filesystem, memory, and
sequential-thinking MCPs are intentionally omitted because built-in tools,
semantic indexing, and repository evidence already cover those responsibilities.

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

## Parallel implementation

Parallel implementation uses exactly two optional slots, `a` and `b`. It is an
optimization for genuinely independent work, not a way to split arbitrary
files between agents.

The orchestrator may select parallel mode only when both units have disjoint
write scopes, neither depends on the other's uncommitted result, and neither
changes a shared mutable contract or integration hotspot such as manifests,
lockfiles, migrations, generated registries, central exports, or schemas.
Dependency changes always use sequential mode.

The trusted wrapper owns the worktree lifecycle:

```bash
bash .opencode/scripts/parallel-worktrees.sh create a src/module-a tests/module-a
bash .opencode/scripts/parallel-worktrees.sh create b src/module-b tests/module-b
bash .opencode/scripts/parallel-worktrees.sh inspect a
bash .opencode/scripts/parallel-worktrees.sh inspect b
bash .opencode/scripts/parallel-worktrees.sh integrate a
bash .opencode/scripts/parallel-worktrees.sh integrate b
bash .opencode/scripts/parallel-worktrees.sh cleanup a
bash .opencode/scripts/parallel-worktrees.sh cleanup b
```

`create` starts detached worktrees from the same clean HEAD under
`.opencode/worktrees/<slot>` and stores scope/base metadata in Git's common
metadata directory rather than in versioned files. It rejects overlapping
scopes.

Implementers may edit only their assigned nested worktree and scope. They may
not stage, commit, switch branches, integrate, or clean up lanes. `inspect`
rejects changed paths outside the lane, staged changes, lane commits, sensitive
paths, secret-like additions, and whitespace errors before exposing a redacted
diff for review.

`integrate` applies one reviewed lane back to the unchanged root HEAD and
refuses changed-path overlap with work already integrated there. After both
lanes are integrated, the ordinary root `github-delivery.sh inspect`, review,
and validation gates apply to the combined result. `cleanup` removes only a
lane already marked as integrated.

`.opencode/worktrees/` is ephemeral and must stay ignored by both Git and the
OpenCode watcher. Never run two implementers against the same working tree.
If scope independence becomes uncertain, stop parallelization instead of
weakening these checks.

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
fixed actions, and always disables dependency lifecycle scripts. The wrapper
also supports one validated mixed `batch` transaction and refuses manager
output outside manifests and lockfiles. The resulting manifest and lockfile
return through `inspect` and preliminary review before repository code runs.
Project-specific generators and migrations must be exposed as reviewed
repository scripts with an explicit local permission override, or run by the
user; the portable pack does not auto-approve arbitrary generators.

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
a `feature/<issue-number>-<slug>` branch, one writer by default or at most two
isolated worktree lanes when independence is proven, repository-native tests,
independent review, a Conventional Commit, and a PR containing
`Closes #<issue-number>`. It refuses to merge without reported successful
GitHub Actions checks, a mergeable PR, completed review, and no active parallel
lanes. CI repair is limited to two evidence-backed rounds. Success ends with
squash merge, issue closure verification, remote and local branch cleanup, a
fast-forwarded local `main`, and a clean working tree.

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

All delivery Git and GitHub mutations are routed through the versioned
`.opencode/scripts/github-delivery.sh` wrapper. It validates repository, issue,
branch, PR, status checks, review state, and the exact reviewed head SHA before
executing a bounded operation; raw mutation commands are denied to the
orchestrator. Its argument-free `inspect` action is the shell-backed Git
inspection surface for the canonical/root checkout.

Parallel worktree creation, inspection, integration, and cleanup are routed
through `.opencode/scripts/parallel-worktrees.sh`. That wrapper accepts only
fixed actions and validated slot/scope arguments; implementers receive only its
read-only lane `inspect` action.

## Reusing in another repository

1. Copy `opencode.json`, `.opencode/agents/`, `.opencode/commands/`,
   `.opencode/scripts/`, `.opencode/codebase-index.json`, and this README.
2. Merge these ignore rules into the target repository's `.gitignore` instead
   of overwriting existing rules:

   ```gitignore
   .artifacts/
   .opencode/index/
   .opencode/worktrees/
   ```

3. Do not copy local index data, worktrees, `.opencode/package.json`, lockfiles,
   `node_modules/`, or other local OpenCode state.
4. Create a fresh project-specific `AGENTS.md` or run `/init`. Never copy
   another project's architecture, commands, privacy rules, or release policy
   unchanged.
5. Verify available models with `opencode models`. Project files require no
   edits unless you intentionally add role-specific overrides.
6. Warm the Playwright package cache, restart OpenCode, and validate:

```bash
opencode debug config
opencode agent list
opencode mcp list
```

Then run `/status` and `/index` once to initialize the semantic project index.
Configuration, agents, commands, skills, plugins, and MCP servers are loaded at
session startup, so start a new session after changing the pack.
