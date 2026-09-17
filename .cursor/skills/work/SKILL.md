---
name: work
description: >-
  Run a local research-first workflow with bounded implementation slices, one
  final-tree validation pass, and review without GitHub delivery. Use when the
  user runs /work or wants local implementation without commit, PR, or merge.
disable-model-invocation: true
---

# Local work without GitHub delivery

Own this local repository task end to end using the smallest effective workflow:
$ARGUMENTS

You are the **orchestrator**. You never edit repository files. Delegate writes
only to Task → `implementer`.

Read and follow the shared playbook:

- [../implement/references/orchestration.md](../implement/references/orchestration.md)
- [../implement/references/brief-template.md](../implement/references/brief-template.md)

Do **not** follow [../implement/references/delivery.md](../implement/references/delivery.md).
Do not commit, push, create or merge a pull request, close issues, or clean
remote branches unless the user separately and explicitly asks. For full GitHub
delivery, tell the user to run `/implement` with a canonical issue URL.

## Workflow

1. Establish acceptance criteria; preserve semantic scope. Do not add unrelated
   behavioral hardening unless the user request or a checked-in contract requires
   it.
2. Resolve version-sensitive APIs, unknown locations, broad impact, and material
   discovery with your own tools or Task → `research-explorer` before writing.
   Use Task → `architect` only when material design decisions require it.
3. Create an ordered write-ready slice plan; materialize with TodoWrite (normally
   4–10 items: slices + final validation + review).
4. Dispatch one `implementer` at a time by default. After each slice, inspect the
   actual diff and verify scope. Run only cheap focused checks that prove that
   slice when useful. Formatting-only failures on task-owned paths:
   `bash .cursor/scripts/format-changed.sh <exact-path>...`
5. After all planned slices, validate the **final combined tree** once in
   increasing cost order, then Task → `reviewer`. Route repairs through bounded
   implementer slices and re-validate.
6. Finalize TodoWrite. Report changed behavior, files, exact checks/results,
   risks, and that delivery was intentionally not performed.

Parallel lanes (at most two) follow the same rules and scripts as in
orchestration.md under `.cursor/scripts/parallel-worktrees.sh`.
