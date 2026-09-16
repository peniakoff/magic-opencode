#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'parallel-worktrees-abort: %s\n' "$*" >&2
  exit 1
}

require_repository_root() {
  local root
  root="$(git rev-parse --show-toplevel)"
  [[ "$PWD" == "$root" ]] || die "run from repository root: $root"
  REPOSITORY_ROOT="$root"
}

require_trusted_wrapper() {
  local relative_path=".opencode/scripts/parallel-worktrees-abort.sh"
  local wrapper_directory invoked_path trusted_hash current_hash
  wrapper_directory="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  invoked_path="$wrapper_directory/$(basename -- "${BASH_SOURCE[0]}")"
  [[ "$invoked_path" == "$PWD/$relative_path" ]] ||
    die "abort wrapper must run from its canonical repository path"
  trusted_hash="$(git rev-parse "main:$relative_path" 2>/dev/null)" ||
    die "abort wrapper is not trusted by local main"
  current_hash="$(git hash-object "$relative_path")"
  [[ "$current_hash" == "$trusted_hash" ]] ||
    die "abort wrapper differs from trusted local main"
}

state_root() {
  local common_dir
  common_dir="$(git rev-parse --git-common-dir)"
  if [[ "$common_dir" != /* ]]; then
    common_dir="$REPOSITORY_ROOT/$common_dir"
  fi
  printf '%s\n' "$common_dir/opencode-parallel"
}

main() {
  [[ "$#" -eq 2 ]] || die "usage: <a|b> <expected-base-sha>"
  local slot="$1" expected_base="$2" state worktree base status
  [[ "$slot" == "a" || "$slot" == "b" ]] || die "slot must be 'a' or 'b'"
  [[ "$expected_base" =~ ^[0-9a-f]{40}$ ]] || die "invalid expected base SHA"

  command -v git >/dev/null 2>&1 || die "missing required command: git"
  require_repository_root
  require_trusted_wrapper
  [[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] ||
    die "root working tree must be clean before abandoning a parallel lane"

  state="$(state_root)/$slot"
  worktree="$REPOSITORY_ROOT/.opencode/worktrees/$slot"
  [[ -d "$state" && -f "$state/base" && -f "$state/status" ]] ||
    die "parallel lane '$slot' does not exist"
  [[ -d "$worktree" ]] || die "worktree directory is missing for slot '$slot'"

  base="$(cat "$state/base")"
  status="$(cat "$state/status")"
  [[ "$status" == "pending" ]] ||
    die "slot '$slot' is not pending; integrated lanes must use normal cleanup"
  [[ "$base" == "$expected_base" ]] || die "slot '$slot' base does not match expected SHA"
  [[ "$(git rev-parse HEAD)" == "$base" ]] ||
    die "root HEAD changed since slot '$slot' was created"
  [[ "$(git -C "$worktree" rev-parse HEAD)" == "$base" ]] ||
    die "slot '$slot' HEAD changed; refusing to discard ambiguous worktree state"

  git worktree remove --force "$worktree"
  rm -rf "$state"
  printf 'aborted slot=%s base=%s\n' "$slot" "$base"
}

main "$@"
