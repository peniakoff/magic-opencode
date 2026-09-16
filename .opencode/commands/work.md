---
description: Run a local research-first workflow using bounded implementation slices, validation, and review without GitHub delivery.
agent: orchestrator
---

Own this local repository task end to end using the smallest effective workflow: $ARGUMENTS

Establish acceptance criteria and inspect repository guidance/current state. Resolve version-sensitive APIs, unknown behavior locations, broad consumer impact, and other discovery questions with orchestrator tools or `research-explorer` before dispatching a writer. Use `architect` only when material design decisions require it.

Create an ordered implementation-slice plan before calling `implementer`. Sequential slices are the default. Each writer slice should be cohesive, preferably about 1-6 files, have an exact allowed scope, contain already-verified external/API facts, include focused tests where practical, and be small enough for the implementer to reach its first edit within 8 tool calls. Do not send one large brief containing research, implementation, broad tests, documentation, and release work when those concerns can be split safely.

The implementer is write-only in purpose: never ask it to research Context7/web docs, inspect `node_modules`, establish architecture, or broadly audit the repository. Handle `NEEDS_RESEARCH` by resolving the exact question outside the writer and redispatching a small write-ready slice. Handle `SCOPE_TOO_LARGE` by splitting the slice. If a writer returns empty output, hits a step limit, or makes no edits where edits were expected, do not replay the same brief unchanged; reuse any verified facts and shrink the task.

After every sequential slice, inspect the actual root diff and verify scope before dispatching the next writer. Later slices may intentionally consume earlier uncommitted root changes when the plan says so. Use at most two parallel implementers only when the orchestrator proves two write-ready slices have disjoint scopes, no shared mutable contract, and no dependency on each other's uncommitted output; isolate them through the trusted worktree workflow and integrate only reviewed lanes.

Before running changed repository code, preliminarily inspect/review executable inputs. Then use repository-native checks in increasing cost order. Use `test-debugger` for ambiguous failures, `browser-qa` for supplementary exploratory user-flow checks, `security-reviewer` for sensitive boundaries, and `reviewer` for substantial/risky final diffs. Route every confirmed code correction through another bounded implementer slice.

Do not commit, push, publish, deploy, or alter remote resources unless I explicitly requested it. Use `/implement <issue-url>` for the complete GitHub delivery workflow.
