# Contributing

Thanks for helping improve **MAGIC OpenCode** — portable multi-agent implement
packs for OpenCode and Cursor.

## Before you start

1. Read the root [README.md](README.md) and the pack docs you touch:
   - [`.opencode/README.md`](.opencode/README.md)
   - [`.cursor/README.md`](.cursor/README.md)
2. Follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
3. For security-sensitive reports, use [SECURITY.md](SECURITY.md) — not public issues

## Dual-pack rule

This repository maintains **two packs that share one operating model**:

| Pack | Path |
|------|------|
| OpenCode | `.opencode/` (+ root `opencode.json`) |
| Cursor | `.cursor/` |

When you change **behavior** (roles, contracts, delivery rules, wrapper
semantics), update **both packs** in the same pull request unless the change is
genuinely runtime-specific (for example OpenCode permission YAML vs Cursor
skill frontmatter).

## Language

All versioned prompts, commands, skills, agent instructions, helper messages,
and documentation under `.opencode/` and `.cursor/` must stay in **English** for
reliable model behavior.

## What to change where

- **Agents** — role contracts, tool boundaries, output statuses
- **Commands / skills** — orchestration steps users invoke (`/implement`, `/work`, …)
- **Scripts** — trusted wrappers only; keep refuse-lists for destructive git/`gh` ops
- **Root docs** — public landing (`README.md`) and community/legal files

Do not commit:

- API keys, tokens, or `.env` files
- Local index/worktree/artifact directories (see `.gitignore`)
- `.opencode/node_modules` or local OpenCode package lock state

## Development workflow

1. Branch from `main`
2. Make a focused change (prefer Conventional Commits: `feat:`, `fix:`, `docs:`)
3. If you edit bash wrappers, ensure they still parse:

   ```bash
   bash -n .opencode/scripts/*.sh .cursor/scripts/*.sh
   ```

4. Open a pull request using the template
5. Keep the PR reviewable: one concern when practical; call out dual-pack sync

## Pull request expectations

- Describe **why**, not only what
- Note whether OpenCode and Cursor packs were kept in sync
- Link related issues
- Do not expand scope into unrelated refactors

## Questions

Use GitHub Discussions or Issues for product/docs questions. Use private
vulnerability reporting for security topics ([SECURITY.md](SECURITY.md)).
