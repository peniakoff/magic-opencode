# Security Policy

## Supported versions

Security fixes apply to the latest commit on the default branch (`main`) of this
repository. Older commits and forks are not supported.

This project ships **portable agent packs and trusted bash wrappers** for
[OpenCode](https://opencode.ai) and [Cursor](https://cursor.com). It does not
ship a hosted service or runtime binary.

## Reporting a vulnerability

Please **do not** open a public issue for security problems in this repository.

Use GitHub’s **private vulnerability reporting** for this repo:

1. Open [Security advisories](https://github.com/peniakoff/magic-opencode/security/advisories/new)
2. Describe the issue, affected paths, and a minimal reproduction if possible
3. Include impact assessment (what an attacker could do with the pack as shipped)

You should receive an acknowledgment within a few days. If a fix is accepted, we
will coordinate disclosure through a GitHub Security Advisory.

## In scope

- Prompt/agent/command/skill content that could cause unsafe automation when
  used as documented
- Bash wrappers under `.opencode/scripts/` and `.cursor/scripts/` (for example
  secret leakage, unsafe git/`gh` mutations, path traversal, or privilege
  escalation relative to the documented trust model)
- Project config such as `opencode.json` that enables dangerous defaults

## Out of scope

- Vulnerabilities in **target applications** where someone runs `/implement` or
  `/work` (report those to the target project’s maintainers)
- Issues that require ignoring the documented isolation guidance (running
  untrusted repositories with production credentials)
- Model provider / MCP third-party service outages or rate limits
- Social engineering against individual developers

## Trust model (summary)

- Delivery and parallel-worktree mutations are intended to go through the
  shipped wrappers, which refuse stash/reset/force-push/deploy/publish by design
- OpenCode/Cursor permissions constrain agent tool calls; they do **not** sandbox
  code executed by a target repository’s tests or build scripts
- For untrusted repositories or dependencies, use a dedicated OS account,
  development container, or disposable VM with minimal credentials

Never commit API keys, tokens, or other secrets into this repository or into
copies of these packs. Context7 (and similar) credentials must stay in
environment variables or local user config.
