---
description: Run the full research, design, implementation, validation, and review workflow.
agent: orchestrator
---

Own this local repository task end to end using the smallest effective workflow: $ARGUMENTS

Establish acceptance criteria, inspect repository guidance and current state, and delegate all edits to `implementer`. Use one implementer by default. Use the two-lane parallel worktree workflow only when the orchestrator can prove exactly two coherent implementation units have disjoint write scopes, no shared mutable contract, and no dependency on each other's uncommitted output. Otherwise stay sequential.

Use semantic codebase discovery when the index is available, then LSP or exact grep for precise references. Use other specialists only where their expertise adds value. Use repository-native test runners; never substitute ad hoc Python, Node.js, shell, or HTML scripts for maintainable tests. Use `test-debugger` for ambiguous failures, `browser-qa` for supplementary exploratory checks of changed web flows, `security-reviewer` for sensitive boundaries, and `reviewer` for substantial or risky diffs. Route confirmed findings back to the responsible implementer, integrate parallel lanes only through `.opencode/scripts/parallel-worktrees.sh`, and finish with exact validation evidence from the combined root checkout.

Do not commit, push, publish, deploy, or alter remote resources unless I explicitly requested it. Use `/implement <issue-url>` for the complete GitHub delivery workflow.
