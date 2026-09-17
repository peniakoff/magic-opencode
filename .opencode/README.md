# Portable OpenCode engineering workflow

This directory contains a repository-agnostic workflow for web, mobile, API,
SaaS, data, and infrastructure projects. Agents discover the actual stack and
follow the target repository's `AGENTS.md`, manifests, CI, and conventions.
All versioned prompts, commands, helper messages, and documentation under
`.opencode/` use English consistently for reliable behavior across models.

## Operating model

The workflow deliberately separates thinking roles from the writer:

- `orchestrator` owns scope, evidence, decomposition, validation, review, and
  explicitly requested GitHub delivery. It cannot edit files.
- `research-explorer` resolves repository/API/compatibility facts before a
  writer is dispatched.
- `architect` resolves material design decisions when a change crosses
  contracts, persistence, migrations, security, infrastructure, or major
  compatibility boundaries.
- `implementer` is the only agent type allowed to edit repository files. It is
  intentionally a bounded writer, not a researcher.
- `test-debugger`, `reviewer`, `browser-qa`, and `security-reviewer` are
  read-only specialists.

The default flow is:

```text
inspect / research
        ↓
decide architecture and compatibility
        ↓
plan bounded implementation slices
        ↓
implement slice 1 → inspect
implement slice 2 → inspect
...
        ↓
preliminary review → validation → final review
```

One implementer is the default. At most two implementer instances may run in
parallel, and only when two write-ready slices are proven independent and use
separate trusted worktrees. The orchestrator must load skill `parallel-lanes`
before creating any worktree.

Commands:

- `/work <task>` — local implementation/validation/review without GitHub
  delivery.
- `/implement <GitHub issue URL>` — branch, research, bounded implementation,
  validate, review, open a PR, wait for Actions, squash-merge, and clean up.
- `/research`, `/design`, `/debug`, `/review`, `/qa`, and `/security` — focused
  report-only specialist workflows.

## Why implementation is sliced

The writer has a bounded step budget. A large brief that asks one implementer
to discover the repository, verify external APIs, edit many unrelated files,
write tests, update documentation, and prepare release metadata can consume the
entire budget before the first edit.

This workflow prevents that failure mode structurally rather than merely asking
the model to be faster.

### Research belongs before the writer

Use `research-explorer` for:

- version-sensitive library/API behavior;
- dependency compatibility;
- unknown behavior location and call paths;
- broad consumer/blast-radius analysis;
- repository conventions that require exploration;
- facts that would otherwise make a writer inspect `node_modules`, Context7,
  vendor sources, or the web.

The researcher returns an implementation-ready evidence packet. The
orchestrator copies only decision-relevant verified facts into the writer brief.
The implementer must not re-verify them unless checked-in repository evidence
contradicts the brief.

### Bounded writer slices

A normal writer slice has one cohesive objective and preferably about 1-6
files. More than 8 non-mechanical files should normally be decomposed. Keep
focused tests with the behavior they prove when practical; move docs/version/
changelog work into a small mechanical follow-up slice when that keeps the core
writer task clearer.

The implementer has a hard progress contract:

- first repository edit by tool call 8;
- at most 6 read/grep/LSP calls before that edit;
- no web/Context7/semantic-index/node_modules research tools;
- exact scope supplied by the orchestrator;
- if facts are missing, return `NEEDS_RESEARCH` instead of continuing to read;
- if the assignment is too large, return `SCOPE_TOO_LARGE` instead of spending
  the step budget on reconnaissance.

Expected statuses are:

```text
IMPLEMENTED
NEEDS_RESEARCH
SCOPE_TOO_LARGE
BLOCKED_CONFLICT
```

A step-limit result, empty subagent result, or completed writer session with no
edits where edits were expected is treated as an orchestration failure. Reuse
any verified facts, shrink the slice, and do not replay the same brief.

Sequential slices share the normal root working tree. Only one writer runs at a
time, and later slices may consume earlier uncommitted output when the
orchestrator explicitly planned that dependency. The orchestrator inspects the
actual diff after every slice; writer summaries are not trusted as proof.

## Models

Project agents do not pin provider-specific model IDs. The primary agent uses
the model selected globally/currently and subagents inherit it by default.
Role-specific local overrides may be configured in
`~/.config/opencode/opencode.json`:

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

Use IDs reported by `opencode models`.

## Semantic codebase index

The project enables the `open-codebase-index` plugin through `opencode.json`.
OpenCode installs configured npm plugins into its cache at startup, so target
applications do not add the plugin to their own manifests/lockfiles.

Configuration lives in `.opencode/codebase-index.json`. Initial indexing is
explicit (`autoIndex: false`) and file watching is enabled afterward. On a new
checkout:

```text
/status
/index
```

The generated `.opencode/index/` directory is local runtime state and must stay
ignored. If no embedding provider is available, indexing must fail fast and the
workflow falls back to LSP/targeted repository search. The writer does not try
to build or repair the index.

Discovery ownership is intentionally asymmetric:

1. orchestrator/researcher: semantic context/peek for conceptual discovery;
2. orchestrator/researcher: implementation lookup/call graph when useful;
3. all appropriate read-only roles: LSP for precise definitions/references;
4. targeted grep for exact/exhaustive textual matches;
5. implementer: only targeted read/LSP/grep inside a write-ready slice.

## MCP servers

`opencode.json` enables Context7 and Playwright MCP in addition to the local
codebase-index plugin.

- Context7 is for research, architecture, and diagnostic roles. The implementer
  intentionally does not have Context7/web access; version/API facts must be
  resolved before writing.
- Playwright MCP gives `browser-qa` persistent exploratory browser access.

Both MCP families are denied globally and enabled only for roles that need
them. GitHub delivery uses the constrained `gh`/wrapper workflow rather than a
broad GitHub MCP inside OpenCode.

### Context7 authentication

The public endpoint works without committing credentials. For higher rate
limits configure the key globally:

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

Never store the key in the repository.

### Playwright preflight

The Playwright MCP package is pinned in `opencode.json`. On a new machine warm
the package cache and check MCP connectivity before relying on browser QA.
Browser artifacts are isolated under `.artifacts/playwright` and ignored.

`browser-qa` must use synthetic data and a local/preview/staging or otherwise
explicitly approved environment. Exploratory MCP automation supplements but
never replaces durable repository E2E tests.

## Parallel implementation

Parallel mode uses exactly two optional slots, `a` and `b`. It parallelizes
independent writer slices, not arbitrary files.

Both slices must:

- already be write-ready;
- have disjoint write scopes;
- have no dependency on the other's uncommitted output;
- share no mutable contract/schema/manifest/lockfile/migration/generated
  registry/central export/integration hotspot;
- start from the same clean HEAD.

The trusted wrapper owns lane lifecycle:

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

`create` uses detached worktrees under `.opencode/worktrees/<slot>` and records
scope/base metadata outside versioned files. It rejects overlapping scopes.
Implementers cannot create, integrate, clean, or abort lanes. Lane `inspect`
rejects commits/staging, out-of-scope writes, sensitive paths, secret-like
additions, symlink/non-regular-file changes, and whitespace errors.

If parallel mode becomes invalid before integration, discard pending temporary
lanes only through the SHA-bound abort wrapper and restart sequentially. Once a
lane is integrated, do not abort it; resolve the combined root deliberately.

After integration, all validation and final review operate on the combined root
checkout.

## Dependency changes

Dependency changes are a dedicated sequential first slice. The researcher first
establishes the exact compatible package/version/API facts. The implementer then
receives only the exact operation and runs the trusted
`.opencode/scripts/dependency-update.sh` wrapper.

The wrapper validates package identifiers, supports npm/Yarn/pnpm/Bun, disables
lifecycle scripts, and refuses manager output outside package manifests and
lockfiles. Manifest/lockfile changes are inspected and preliminarily reviewed
before feature-code slices begin.

Do not combine dependency research, package installation, and feature coding in
one implementer session.

## Testing and review policy

Implementers edit and return validation commands; they do not execute changed
repository code.

After preliminary inspection/review of executable inputs, the orchestrator or
`test-debugger` runs repository-native validation in increasing cost order:
focused tests, formatting/static checks, type checking, broader tests, then
build/package/synthesis checks required by repository policy/CI.

Use `test-debugger` for ambiguous failures, then route a confirmed repair back
to a bounded implementer slice. `reviewer` performs independent final review;
`security-reviewer` handles sensitive trust boundaries; `browser-qa` provides
supplementary exploratory checks for changed user flows.

Never create ad hoc Python/Node/shell/HTML scripts as substitutes for the
repository's established unit/integration/E2E framework.

## GitHub delivery

Authenticate GitHub CLI before `/implement`:

```bash
gh auth login
gh auth status
```

Then invoke:

```text
/implement https://github.com/owner/repository/issues/123
```

The command validates the issue/repository, creates a
`feature/<issue-number>-<slug>` branch, resolves research before writing,
implements through bounded slices, validates/reviews the combined result,
creates a Conventional Commit and PR with `Closes #<issue-number>`, waits for a
stable passing Actions set, and squash-merges only the reviewed exact head.
Cleanup verifies merge/issue state, removes the exact feature branch, updates
local `main` by fast-forward only, and requires a clean tree.

The delivery workflow never stashes, resets, cleans, force-pushes, deploys,
publishes, or mutates cloud resources by implication.

### Process isolation boundary

OpenCode permissions constrain agent tool calls; they do not sandbox code run
by repository tests/build scripts. Such code runs as the OS user and may access
that user's credentials. For untrusted repositories/dependencies/issues, use a
dedicated OS account, development container, or disposable VM with minimal
credentials. Preliminary review must inspect changed executable inputs before
the orchestrator runs them.

Git/GitHub mutations are routed through
`.opencode/scripts/github-delivery.sh`. Parallel worktrees are routed through
`.opencode/scripts/parallel-worktrees.sh` and the separate abort wrapper.

## Reusing in another repository

1. Copy `opencode.json`, `.opencode/agents/`, `.opencode/commands/`,
   `.opencode/skills/`, `.opencode/scripts/`, `.opencode/codebase-index.json`,
   and this README.
2. Merge these ignore rules into the target `.gitignore`:

   ```gitignore
   .artifacts/
   .opencode/index/
   .opencode/worktrees/
   ```

3. Do not copy local index data, worktrees, local OpenCode package state, or
   `node_modules`.
4. Create a project-specific `AGENTS.md` or run `/init`; never copy another
   project's product/privacy/release rules blindly.
5. Verify models with `opencode models`.
6. Validate configuration after copying:

```bash
opencode debug config
opencode agent list
opencode mcp list
```

Then run `/status` and `/index` when an embedding-capable provider is available.
Configuration, agents, commands, skills, plugins, and MCP servers are loaded at
session startup, so start a new OpenCode session after changing the pack.
Skills under `.opencode/skills/` are discovered then and loaded on demand via
the `skill` tool.
