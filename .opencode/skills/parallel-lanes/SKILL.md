---
name: parallel-lanes
description: Run at most two isolated implementation lanes in git worktrees when two slices are provably independent. Load before creating any worktree.
---

# Parallel implementation lanes

Parallel implementation is an optimization, never the default. Use exactly two
lanes (`a` and `b`) only when both slices are independently implementable.

All of the following must hold:

- two coherent units with explicit disjoint file/directory scopes;
- neither depends on the other's uncommitted output;
- no shared mutable contract, manifest, lockfile, migration, generated
  registry, central export, schema, or other integration hotspot;
- both can start from the same clean HEAD;
- each lane independently satisfies the normal write-ready and first-edit
  requirements.

## Workflow

1. Define lane `a` and `b` objectives, acceptance criteria, exact scopes, and
   shared no-touch paths.
2. Create both detached worktrees from the same HEAD; record each base SHA.
3. Mark one parent parallel-implementation todo item `in_progress`, then
   dispatch two implementers concurrently only when the runtime supports it.
   Each brief includes its slot and `.opencode/worktrees/<slot>` root.
4. Each implementer runs lane `inspect` before handoff. Independently review
   each lane's actual diff.
5. Integrate reviewed lanes one at a time using the trusted wrapper, inspect
   the combined root diff, then clean both integrated lanes and mark the parent
   parallel todo item completed.
6. Validate and review the combined root result normally.

```bash
bash .opencode/scripts/parallel-worktrees.sh create a <scope-path>...
bash .opencode/scripts/parallel-worktrees.sh create b <scope-path>...
bash .opencode/scripts/parallel-worktrees.sh inspect a
bash .opencode/scripts/parallel-worktrees.sh inspect b
bash .opencode/scripts/parallel-worktrees.sh integrate a
bash .opencode/scripts/parallel-worktrees.sh integrate b
bash .opencode/scripts/parallel-worktrees.sh cleanup a
bash .opencode/scripts/parallel-worktrees.sh cleanup b
```

## Abort

If the second lane cannot be created or a cross-lane dependency appears before
integration, abort pending unintegrated lanes while root is clean:

```bash
bash .opencode/scripts/parallel-worktrees-abort.sh <slot> <recorded-base-sha>
```

Replace the parallel todo item with the new sequential plan and restart
sequentially. Never weaken the scope checks. If any lane is already integrated,
stop and resolve the combined root deliberately rather than aborting it.
