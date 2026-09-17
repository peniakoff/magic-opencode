# Portable Cursor multi-agent implement pack

Self-contained Cursor skills, custom subagents, and trusted bash wrappers for
end-to-end GitHub issue implementation. Copy **only** this `.cursor/` folder
into another repository root — no `.opencode/`, OpenCode install, or MCP plugins
are required.

## Install into another repository

1. Copy this entire `.cursor/` directory to the target repository root.
2. Merge these ignore rules into the target root `.gitignore` (recommended):

   ```gitignore
   .cursor/worktrees/
   .artifacts/
   ```

   This pack also ships `.cursor/.gitignore` for `worktrees/` and `index/`.
3. Commit `.cursor/` to the default branch trusted by the wrappers (`main`).
   Delivery scripts refuse to run until they match `main:.cursor/scripts/...`.
4. Authenticate GitHub CLI:

   ```bash
   gh auth login
   gh auth status
   ```
5. Start with a clean working tree, then in Cursor Agent chat:

   ```text
   /implement https://github.com/owner/repository/issues/123
   ```

   For local work without GitHub delivery:

   ```text
   /work <task description>
   ```

## What you get

| Path | Role |
|------|------|
| `skills/implement/` | `/implement` — research, bounded slices, validate, review, PR, CI, squash merge, cleanup |
| `skills/work/` | `/work` — same loop without commit/push/PR/merge |
| `agents/` | Task specialists: research, architecture, writing, debug, review, browser QA, security |
| `scripts/` | Trusted wrappers for GitHub delivery, formatting, dependencies, parallel worktrees |

## Operating model

The parent chat that runs `/implement` or `/work` is the **orchestrator**. It
owns scope, evidence, slicing, validation, review, and (for `/implement`)
delivery. It must **not** edit repository files.

- `research-explorer` / `architect` resolve facts and design before writing.
- `implementer` is the only agent that edits files (bounded write-ready slices).
- `test-debugger`, `reviewer`, `browser-qa`, and `security-reviewer` are
  read-only specialists.

Default flow:

```text
inspect / research
        ↓
decide architecture and compatibility
        ↓
plan bounded implementation slices
        ↓
implement slice → inspect
...
        ↓
final-tree validation → review
        ↓
(/implement only) commit → PR → CI → squash merge → cleanup
```

Sequential slices are the default. At most two parallel lanes, only when scopes
are proven independent, via `.cursor/scripts/parallel-worktrees.sh`.

## What you see in Cursor

A well-run `/implement` or `/work` session should show:

- a **todo list** from the first tool call (preflight through review, plus
  delivery for `/implement`), with one item in progress;
- **named subagent cards** such as `research-explorer: resolve API facts`,
  not a bare "Task";
- **named shell cards** such as `Prepare feature branch from issue`, not a
  bare "Run command";
- a short sentence before each phase and before each subagent dispatch.

When editing files under `agents/`, keep the YAML `description` on **one
line**. Cursor's Task catalog treats a folded `description: >-` block as the
literal string `>-`, so the agent appears to have no description.

## Script discipline

Run wrappers from the repository root as standalone bash calls. Do not combine
commands with `;`, `&&`, `||`, `|`, redirection, or command substitution.

```bash
bash .cursor/scripts/github-delivery.sh prepare <issue-url>
bash .cursor/scripts/github-delivery.sh inspect
bash .cursor/scripts/format-changed.sh <exact-path>...
bash .cursor/scripts/dependency-update.sh <add|add-dev|remove> <npm|yarn|pnpm|bun> <package>...
```

Cursor cannot hard-enforce OpenCode-style bash allowlists. Prefer these wrappers
over raw `git` / `gh` mutations. The wrappers do not stash, reset, force-push,
deploy, or publish.

## Prerequisites

- Cursor Agent with project skills and custom subagents enabled
- `gh` authenticated to the repository
- Repository-native test/lint/build commands available as needed
- For `/implement`: clean tree, wrappers committed on trusted `main`

## Independence from OpenCode

This pack may coexist with an OpenCode `.opencode/` pack in the same repo, but
it does not call it. Paths, worktrees, and trust checks are entirely under
`.cursor/`.
