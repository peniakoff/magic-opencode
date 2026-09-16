---
description: Run a local research-first workflow using bounded implementation slices, one final-tree validation pass, and review without GitHub delivery.
agent: orchestrator
---

Own this local repository task end to end using the smallest effective workflow: $ARGUMENTS

Establish acceptance criteria and preserve their semantic scope. Do not add unrelated behavioral hardening unless the user request or a checked-in repository contract requires it. Resolve version-sensitive APIs, unknown behavior locations, broad consumer impact, and other material discovery questions with orchestrator tools or `research-explorer` before dispatching a writer. Use `architect` only when material design decisions require it.

Create an ordered implementation-slice plan before calling `implementer`. Sequential slices are the default. Each writer slice should be cohesive, preferably about 1-6 files, have an exact allowed scope, contain already-verified external/API facts, include focused tests where practical, and be small enough for the implementer to reach its first edit within 8 tool calls.

Give the writer a contract, not a pseudopatch: objective, acceptance criteria, allowed paths, relevant symbols, verified constraints, invariants to preserve, focused test expectations, and later validation commands. Do not provide a near-complete replacement function or line-by-line algorithm unless exact external API syntax is itself a verified compatibility fact.

Immediately after the slice plan is stable and before the first implementer call, materialize it with `todowrite` in the parent orchestrator session. Keep the list concise, normally 4-10 items: meaningful slices plus final validation and review. Before a sequential phase, mark exactly that item `in_progress`; after verifying it, mark it `completed`. Update the list immediately when research, repair, `SCOPE_TOO_LARGE`, or another event changes the plan. The orchestrator owns this list.

The implementer is write-only in purpose: never ask it to research Context7/web docs, inspect `node_modules`, establish architecture, or broadly audit the repository. Handle `NEEDS_RESEARCH` outside the writer. Handle `SCOPE_TOO_LARGE` by splitting the slice. If a writer returns empty output, hits a step limit, or makes no edits where edits were expected, reuse verified facts and shrink the task instead of replaying the same brief.

After every sequential slice, inspect the actual root diff and verify scope. Run only cheap focused checks needed to prove that slice when useful, such as its focused test and formatting check. If formatting alone fails on task-owned changed files, use `bash .opencode/scripts/format-changed.sh <exact-failing-path>...`; never delegate deterministic whitespace/wrapping/comma/import-layout repairs to an LLM.

Do not run the full repository validation suite between slices. After all planned code, tests, docs, manifest, and metadata slices are complete, preliminarily inspect executable inputs, mark final-tree validation `in_progress`, and run repository-native checks in increasing cost order. Run the required full suite once for that final combined tree. Any later semantic/code repair invalidates the relevant validation and must be followed by the affected checks plus the required final-tree validation.

Use at most two parallel implementers only when the orchestrator proves two write-ready slices have disjoint scopes, no shared mutable contract, and no dependency on each other's uncommitted output. Isolate them through the trusted worktree workflow and integrate only reviewed lanes.

Use `test-debugger` for ambiguous failures, `browser-qa` for supplementary exploratory user-flow checks, `security-reviewer` for sensitive boundaries, and `reviewer` for substantial/risky final diffs. The reviewer must treat malformed/invalid input that succeeds when the contract requires rejection as an actionable correctness defect, even if the produced value coincidentally matches a corrected input. Standards/protocol compliance claims must match the actual supported subset.

Mark final review `in_progress` and complete it only when no actionable finding remains. Before the final response, finalize `todowrite` so no stale `in_progress` item remains. Do not commit, push, publish, deploy, or alter remote resources unless explicitly requested. Use `/implement <issue-url>` for the complete GitHub delivery workflow.
