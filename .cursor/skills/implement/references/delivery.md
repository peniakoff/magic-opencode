# GitHub delivery sequence

Used only by `/implement`. Every `github-delivery.sh` action is a **standalone**
bash tool call from the repository root. Do not combine with `;`, `&&`, `||`,
`|`, redirection, or command substitution.

Treat wrapper inputs as argv. Multi-word/free-text arguments must be one quoted
argument. The Conventional Commit subject must always be exactly one quoted
argument.

Correct:

```bash
bash .cursor/scripts/github-delivery.sh commit "feat(config): add YAML parser" path1 path2
```

Incorrect:

```bash
bash .cursor/scripts/github-delivery.sh commit feat(config): add YAML parser path1 path2
```

## Preflight

1. Validate the canonical issue URL; extract owner, repository, issue number.
2. `gh auth status`
3. `gh issue view <url-or-number>` — require open.
4. Read repository policy and the narrow source/test area needed.
5. `bash .cursor/scripts/github-delivery.sh prepare <issue-url>`
6. Ask the user only for unresolved material product/compatibility decisions.

Do not probe with bare speculative `git` / `gh` discovery. Prefer the wrappers
and targeted repository reads. Do not try to list PRs via `gh pr view` before
this workflow creates a PR.

## Delivery after review

1. Mark delivery `in_progress`; final `inspect`; then
   `commit <quoted-conventional-message> <exact-task-owned-paths>...`
2. `push` as a separate call.
3. `create-pr <issue-url> <quoted-title> <quoted-body>` separately. Body must
   summarize implementation, exact local validation, risks/migrations, and
   include `Closes #<issue-number>`.
4. Mark CI `in_progress`; `wait-checks <pr-number>` **once**.
5. CI failures: diagnose evidence first; at most two evidence-backed repair
   rounds. Any pushed repair invalidates the old CI proof — re-validate/review
   and `wait-checks` again for the new head.
6. After successful `wait-checks`, mark merge `in_progress`, record
   `headRefOid`, run `merge <pr-number> <head-sha>`. If head or check set
   changed, stop and `wait-checks` again — never bypass the proof.

## Cleanup

After squash merge confirmation:

```bash
bash .cursor/scripts/github-delivery.sh cleanup <issue-url> <pr-number>
```

Require: merged PR, closed issue, local `main` fast-forwarded, remote feature
branch gone, local feature branch removed when appropriate, clean tree.

## Final report

Report issue URL, PR URL, final commit on `main`, behavior changed, slices used,
exact validation results, review result, Actions outcome, squash merge, issue
state, and branch cleanup. Never claim completion from an agent summary alone.

## Authorizations

Invoking `/implement` with a canonical issue URL authorizes branch creation,
repository edits through implementers, validation, commit, push, PR, CI wait,
squash merge, issue closure, and branch cleanup. It does **not** authorize
deployment, publication, cloud mutations, secret exposure, or discarding
existing unrelated work.
