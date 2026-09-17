# Implementer brief template

Pass this structure to Task → `implementer`. Subagents have no parent chat
history — include every decision-ready fact in the prompt.

```markdown
## Objective
<one cohesive slice objective>

## Acceptance criteria
- <criterion>
- <criterion>

## Allowed write scope
- <exact file or directory paths>

## Relevant files / symbols
- <path>: <symbol or note>

## Verified facts (do not re-verify unless repo contradicts)
- <API/version/compatibility facts>
- <invariants to preserve>

## Behavior to preserve
- <existing behavior that must not change>

## Tests
- Add/update: <paths or cases>
- Later validation commands for the orchestrator:
  - <focused command>
  - <full suite command if known>

## Mode
normal-root | parallel lane a | parallel lane b

## Lane root (parallel only)
.cursor/worktrees/<slot>
```

## Brief quality rules

- Contract, not a pseudopatch: no line-by-line algorithms or near-complete
  replacement functions unless an exact external API shape is itself a verified
  fact.
- Keep the brief concise and decision-ready.
- Never instruct the writer to research docs, inspect `node_modules`, audit all
  consumers, or choose architecture/product direction.
