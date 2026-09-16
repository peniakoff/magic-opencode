#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'parallel-worktrees: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_repository_root() {
  local root
  root="$(git rev-parse --show-toplevel)"
  [[ "$PWD" == "$root" ]] || die "run from repository root: $root"
  REPOSITORY_ROOT="$root"
}

require_trusted_wrapper() {
  local relative_path=".opencode/scripts/parallel-worktrees.sh"
  local wrapper_directory invoked_path trusted_hash current_hash
  wrapper_directory="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  invoked_path="$wrapper_directory/$(basename -- "${BASH_SOURCE[0]}")"
  [[ "$invoked_path" == "$PWD/$relative_path" ]] ||
    die "parallel wrapper must run from its canonical repository path"
  trusted_hash="$(git rev-parse "main:$relative_path" 2>/dev/null)" ||
    die "parallel wrapper is not trusted by local main"
  current_hash="$(git hash-object "$relative_path")"
  [[ "$current_hash" == "$trusted_hash" ]] ||
    die "parallel wrapper differs from trusted local main"
}

require_clean_root() {
  [[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] ||
    die "root working tree must be clean before creating parallel lanes"
}

require_slot() {
  [[ "${1:-}" == "a" || "${1:-}" == "b" ]] || die "slot must be 'a' or 'b'"
}

other_slot() {
  if [[ "$1" == "a" ]]; then
    printf 'b\n'
  else
    printf 'a\n'
  fi
}

state_root() {
  local common_dir
  common_dir="$(git rev-parse --git-common-dir)"
  if [[ "$common_dir" != /* ]]; then
    common_dir="$REPOSITORY_ROOT/$common_dir"
  fi
  printf '%s\n' "$common_dir/opencode-parallel"
}

slot_state_dir() {
  printf '%s/%s\n' "$(state_root)" "$1"
}

slot_worktree() {
  printf '%s/.opencode/worktrees/%s\n' "$REPOSITORY_ROOT" "$1"
}

relative_worktree() {
  printf '.opencode/worktrees/%s\n' "$1"
}

validate_scope_path() {
  local path="$1"
  [[ -n "$path" && "$path" != "." && "$path" != /* && "$path" != -* ]] ||
    die "invalid scope path: $path"
  [[ "$path" =~ ^[A-Za-z0-9._/-]+$ ]] ||
    die "scope path contains unsupported characters: $path"
  [[ "$path" != *"//"* && "$path" != ".." && "$path" != ../* &&
     "$path" != */../* && "$path" != */.. ]] ||
    die "scope path escapes repository: $path"
  case "/$path" in
    /.git | /.git/* | /.opencode/worktrees | /.opencode/worktrees/* | \
      /.opencode/index | /.opencode/index/*)
      die "scope path is reserved: $path"
      ;;
  esac
}

normalize_scope_path() {
  local path="$1"
  while [[ "$path" == */ ]]; do
    path="${path%/}"
  done
  printf '%s\n' "$path"
}

path_within_scope() {
  local path="$1" scope_file="$2" scope
  while IFS= read -r scope; do
    [[ -n "$scope" ]] || continue
    if [[ "$path" == "$scope" || "$path" == "$scope/"* ]]; then
      return 0
    fi
  done <"$scope_file"
  return 1
}

scopes_overlap() {
  local first="$1" second="$2" a b
  while IFS= read -r a; do
    [[ -n "$a" ]] || continue
    while IFS= read -r b; do
      [[ -n "$b" ]] || continue
      if [[ "$a" == "$b" || "$a" == "$b/"* || "$b" == "$a/"* ]]; then
        return 0
      fi
    done <"$second"
  done <"$first"
  return 1
}

require_lane() {
  local slot="$1" state worktree base
  require_slot "$slot"
  state="$(slot_state_dir "$slot")"
  [[ -d "$state" && -f "$state/base" && -f "$state/scope" && -f "$state/status" ]] ||
    die "parallel lane '$slot' does not exist"
  worktree="$(slot_worktree "$slot")"
  [[ -d "$worktree" ]] || die "worktree directory is missing for slot '$slot'"
  base="$(cat "$state/base")"
  [[ "$base" =~ ^[0-9a-f]{40}$ ]] || die "invalid base SHA for slot '$slot'"
  [[ "$(git -C "$worktree" rev-parse HEAD)" == "$base" ]] ||
    die "slot '$slot' HEAD changed; parallel implementers must not commit"
}

is_sensitive_path() {
  local normalized_path
  normalized_path="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "/$normalized_path" in
    */../* | */.git/* | */.env | */.env.* | */.npmrc | */.pypirc | */.netrc | \
      */.docker/config.json | */.kube/config | */.aws/credentials | \
      */.config/gh/hosts.yml | */id_rsa | */id_dsa | */id_ecdsa | \
      */id_ed25519 | *.pem | *.key | *.p12 | *.pfx | *.jks | *.keystore | \
      */credentials.json | */credentials-*.json | */service-account.json | \
      */service-account-*.json)
      return 0
      ;;
  esac
  return 1
}

SECRET_PATTERN="BEGIN [A-Z ]*PRIVATE KEY|github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9_]+|AKIA[0-9A-Z]{16}|npm_[A-Za-z0-9]{20,}|(api[_-]?key|access[_-]?token|client[_-]?secret|password)[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9_./+=-]{16,}"

emit_redacted_diff() {
  awk '
    {
      lowered = tolower($0)
      if (lowered ~ /begin [a-z ]*private key/ || lowered ~ /github_pat_[a-z0-9_]+/ || lowered ~ /gh[pousr]_[a-z0-9_]+/ || $0 ~ /AKIA[0-9A-Z]{16}/ || lowered ~ /npm_[a-z0-9]{20,}/ || lowered ~ /(api[_-]?key|access[_-]?token|client[_-]?secret|password)[[:space:]]*[:=][[:space:]]*["\047]?[a-z0-9_./+=-]{16,}/) {
        print "[REDACTED SECRET-LIKE DIFF LINE]"
      } else {
        print
      }
    }
  '
}

lane_changed_paths() {
  local slot="$1" worktree
  worktree="$(slot_worktree "$slot")"
  {
    git -C "$worktree" diff --name-only --no-renames --no-ext-diff --no-textconv HEAD -- .
    git -C "$worktree" ls-files --others --exclude-standard
  } | sed '/^$/d' | sort -u
}

root_changed_paths() {
  {
    git diff --name-only --no-renames --no-ext-diff --no-textconv HEAD -- .
    git ls-files --others --exclude-standard
  } | sed '/^$/d' | sort -u
}

file_fingerprint() {
  local path="$1"
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    printf 'deleted\n'
    return
  fi
  [[ ! -L "$path" ]] || die "parallel lanes do not support symlink changes: $path"
  [[ -f "$path" ]] || die "parallel lanes support regular files only: $path"
  git hash-object -- "$path"
}

record_integrated_manifest() {
  local slot="$1" state path fingerprint
  state="$(slot_state_dir "$slot")"
  : >"$state/integrated-manifest"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    fingerprint="$(file_fingerprint "$path")"
    printf '%s\t%s\n' "$fingerprint" "$path" >>"$state/integrated-manifest"
  done < <(lane_changed_paths "$slot")
}

manifest_contains_exact_state() {
  local manifest="$1" wanted_path="$2" fingerprint path current
  while IFS=$'\t' read -r fingerprint path; do
    [[ "$path" == "$wanted_path" ]] || continue
    current="$(file_fingerprint "$path")"
    [[ "$current" == "$fingerprint" ]]
    return
  done <"$manifest"
  return 1
}

manifest_entries_match() {
  local manifest="$1" fingerprint path current
  [[ -f "$manifest" ]] || return 1
  while IFS=$'\t' read -r fingerprint path; do
    [[ -n "$path" ]] || continue
    current="$(file_fingerprint "$path")"
    [[ "$current" == "$fingerprint" ]] || return 1
  done <"$manifest"
  return 0
}

root_changes_are_integrated_lanes() {
  local path slot state matched
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    matched="false"
    for slot in a b; do
      state="$(slot_state_dir "$slot")"
      if [[ -f "$state/status" && "$(cat "$state/status")" == "integrated" &&
            -f "$state/integrated-manifest" ]] &&
         manifest_contains_exact_state "$state/integrated-manifest" "$path"; then
        matched="true"
        break
      fi
    done
    [[ "$matched" == "true" ]] || return 1
  done < <(root_changed_paths)
  return 0
}

validate_lane_changes() {
  local slot="$1" state worktree path scan_status
  state="$(slot_state_dir "$slot")"
  worktree="$(slot_worktree "$slot")"
  [[ -z "$(git -C "$worktree" diff --cached --name-only)" ]] ||
    die "slot '$slot' staged changes are not allowed"

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    is_sensitive_path "$path" && die "slot '$slot' changed sensitive path: $path"
    path_within_scope "$path" "$state/scope" ||
      die "slot '$slot' changed path outside assigned scope: $path"
    if [[ -e "$worktree/$path" || -L "$worktree/$path" ]]; then
      [[ ! -L "$worktree/$path" ]] ||
        die "slot '$slot' changed symlink, which parallel lanes do not support: $path"
      [[ -f "$worktree/$path" ]] ||
        die "slot '$slot' changed non-regular file: $path"
    fi
  done < <(lane_changed_paths "$slot")

  git -C "$worktree" diff --check HEAD -- . >/dev/null ||
    die "slot '$slot' diff failed whitespace validation"

  scan_status=0
  git -C "$worktree" diff --no-renames --no-ext-diff --no-textconv -U0 HEAD -- . |
    grep '^+' | grep -Ei "$SECRET_PATTERN" >/dev/null || scan_status="$?"
  [[ "$scan_status" -eq 1 ]] || {
    [[ "$scan_status" -eq 0 ]] && die "slot '$slot' additions resemble a secret"
    die "failed to scan slot '$slot' additions"
  }

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    scan_status=0
    grep -a -Ei "$SECRET_PATTERN" "$worktree/$path" >/dev/null || scan_status="$?"
    [[ "$scan_status" -eq 1 ]] || {
      [[ "$scan_status" -eq 0 ]] && die "slot '$slot' untracked content resembles a secret: $path"
      die "failed to scan slot '$slot' untracked file: $path"
    }
  done < <(git -C "$worktree" ls-files --others --exclude-standard)
}

create_lane() {
  local slot="${1:-}"
  shift || true
  require_slot "$slot"
  [[ "$#" -ge 1 ]] || die "usage: create <a|b> <scope-path>..."
  require_clean_root
  git check-ignore -q .opencode/worktrees/probe ||
    die ".opencode/worktrees/ must be ignored by Git before using parallel lanes"

  local state worktree scope_tmp other other_state path normalized
  state="$(slot_state_dir "$slot")"
  worktree="$(slot_worktree "$slot")"
  [[ ! -e "$state" && ! -e "$worktree" ]] || die "slot '$slot' already exists"
  scope_tmp="$(mktemp "${TMPDIR:-/tmp}/opencode-scope.XXXXXX")"
  trap 'rm -f "${scope_tmp:-}"' EXIT

  for path in "$@"; do
    validate_scope_path "$path"
    normalized="$(normalize_scope_path "$path")"
    printf '%s\n' "$normalized" >>"$scope_tmp"
  done
  sort -u -o "$scope_tmp" "$scope_tmp"

  other="$(other_slot "$slot")"
  other_state="$(slot_state_dir "$other")"
  if [[ -f "$other_state/scope" ]] && scopes_overlap "$scope_tmp" "$other_state/scope"; then
    die "slot '$slot' scope overlaps active slot '$other'"
  fi

  mkdir -p "$(dirname "$worktree")"
  git worktree add --detach "$worktree" HEAD >/dev/null
  mkdir -p "$state"
  git rev-parse HEAD >"$state/base"
  cp "$scope_tmp" "$state/scope"
  printf '%s\n' "pending" >"$state/status"
  rm -f "$scope_tmp"
  scope_tmp=""
  trap - EXIT

  printf 'slot=%s\npath=%s\nbase=%s\n' \
    "$slot" "$(relative_worktree "$slot")" "$(cat "$state/base")"
  while IFS= read -r path; do
    printf 'scope=%s\n' "$path"
  done <"$state/scope"
}

inspect_lane() {
  local slot="${1:-}" state worktree path diff_status artifact scan_status
  [[ "$#" -eq 1 ]] || die "usage: inspect <a|b>"
  require_lane "$slot"
  validate_lane_changes "$slot"
  state="$(slot_state_dir "$slot")"
  worktree="$(slot_worktree "$slot")"
  artifact="$(mktemp "${TMPDIR:-/tmp}/opencode-lane-inspect.XXXXXX")"
  LANE_ARTIFACT="$artifact"
  trap 'rm -f "${LANE_ARTIFACT:-}"' EXIT

  {
    printf '## Parallel lane %s\n' "$slot"
    printf 'worktree=%s\nbase=%s\nstatus=%s\n' \
      "$(relative_worktree "$slot")" "$(cat "$state/base")" "$(cat "$state/status")"
    printf '%s\n' "## Assigned scope"
    cat "$state/scope"
    printf '%s\n' "## Changed paths"
    lane_changed_paths "$slot"
    printf '%s\n' "## Diff"
    git -C "$worktree" diff --no-renames --no-ext-diff --no-textconv HEAD -- . |
      emit_redacted_diff

    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      diff_status=0
      (
        cd "$worktree"
        git diff --no-ext-diff --no-textconv --no-index -- /dev/null "$path"
      ) | emit_redacted_diff || diff_status="$?"
      [[ "$diff_status" -eq 0 || "$diff_status" -eq 1 ]] ||
        die "failed to inspect slot '$slot' untracked file: $path"
    done < <(git -C "$worktree" ls-files --others --exclude-standard)
  } >"$artifact"

  scan_status=0
  grep -a -Ei "$SECRET_PATTERN" "$artifact" >/dev/null || scan_status="$?"
  [[ "$scan_status" -eq 1 ]] || {
    [[ "$scan_status" -eq 0 ]] && die "slot '$slot' inspection snapshot still resembles a secret"
    die "failed to scan slot '$slot' inspection snapshot"
  }

  command cat "$artifact"
  rm -f "$artifact"
  LANE_ARTIFACT=""
  trap - EXIT
}

integrate_lane() {
  local slot="${1:-}" state worktree base patch path
  [[ "$#" -eq 1 ]] || die "usage: integrate <a|b>"
  require_lane "$slot"
  validate_lane_changes "$slot"
  state="$(slot_state_dir "$slot")"
  worktree="$(slot_worktree "$slot")"
  base="$(cat "$state/base")"

  [[ "$(cat "$state/status")" == "pending" ]] || die "slot '$slot' is already integrated"
  [[ "$(git rev-parse HEAD)" == "$base" ]] ||
    die "root HEAD changed since slot '$slot' was created"
  root_changes_are_integrated_lanes ||
    die "root working tree contains changes not produced by already integrated lanes"
  [[ -n "$(lane_changed_paths "$slot")" ]] || die "slot '$slot' has no changes to integrate"

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if root_changed_paths | grep -Fx -- "$path" >/dev/null; then
      die "slot '$slot' overlaps an existing root change: $path"
    fi
  done < <(lane_changed_paths "$slot")

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    [[ ! -e "$path" && ! -L "$path" ]] ||
      die "untracked target already exists in root: $path"
  done < <(git -C "$worktree" ls-files --others --exclude-standard)

  patch="$(mktemp "${TMPDIR:-/tmp}/opencode-lane-patch.XXXXXX")"
  INTEGRATION_PATCH="$patch"
  trap 'rm -f "${INTEGRATION_PATCH:-}"' EXIT
  git -C "$worktree" diff --binary --full-index --no-renames HEAD -- . >"$patch"

  if [[ -s "$patch" ]]; then
    git apply --check "$patch"
    git apply "$patch"
  fi

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    mkdir -p "$(dirname "$path")"
    cp -p -- "$worktree/$path" "$path"
  done < <(git -C "$worktree" ls-files --others --exclude-standard)

  record_integrated_manifest "$slot"
  printf '%s\n' "integrated" >"$state/status"
  rm -f "$patch"
  INTEGRATION_PATCH=""
  trap - EXIT

  printf 'integrated slot=%s\n' "$slot"
  root_changed_paths
}

cleanup_lane() {
  local slot="${1:-}" state worktree other other_state
  [[ "$#" -eq 1 ]] || die "usage: cleanup <a|b>"
  require_lane "$slot"
  state="$(slot_state_dir "$slot")"
  worktree="$(slot_worktree "$slot")"
  [[ "$(cat "$state/status")" == "integrated" ]] ||
    die "slot '$slot' must be integrated before cleanup"
  [[ -f "$state/integrated-manifest" ]] ||
    die "slot '$slot' has no integration manifest"
  manifest_entries_match "$state/integrated-manifest" ||
    die "root changes no longer match slot '$slot' integration manifest"

  other="$(other_slot "$slot")"
  other_state="$(slot_state_dir "$other")"
  if [[ -f "$other_state/status" && "$(cat "$other_state/status")" != "integrated" ]]; then
    die "cannot clean slot '$slot' while slot '$other' is still pending"
  fi

  git worktree remove --force "$worktree"
  rm -rf "$state"
  printf 'cleaned slot=%s\n' "$slot"
}

list_lanes() {
  [[ "$#" -eq 0 ]] || die "usage: list"
  local slot state
  for slot in a b; do
    state="$(slot_state_dir "$slot")"
    if [[ -d "$state" ]]; then
      printf 'slot=%s status=%s path=%s\n' \
        "$slot" "$(cat "$state/status" 2>/dev/null || printf unknown)" \
        "$(relative_worktree "$slot")"
    fi
  done
}

main() {
  require_command git
  require_command grep
  require_command sed
  require_command sort
  require_command awk
  require_command cp
  require_repository_root
  require_trusted_wrapper

  local action="${1:-}"
  [[ -n "$action" ]] || die "missing action"
  shift
  case "$action" in
    create) create_lane "$@" ;;
    inspect) inspect_lane "$@" ;;
    integrate) integrate_lane "$@" ;;
    cleanup) cleanup_lane "$@" ;;
    list) list_lanes "$@" ;;
    *) die "unsupported action: $action" ;;
  esac
}

main "$@"
