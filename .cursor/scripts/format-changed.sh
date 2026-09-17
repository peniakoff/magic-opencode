#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'format-changed: %s\n' "$*" >&2
  exit 1
}

require_repository_root() {
  local root
  root="$(git rev-parse --show-toplevel)"
  [[ "$PWD" == "$root" ]] || die "run from repository root: $root"
}

require_trusted_wrapper() {
  local relative_path=".cursor/scripts/format-changed.sh"
  local wrapper_directory invoked_path trusted_hash current_hash
  wrapper_directory="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  invoked_path="$wrapper_directory/$(basename -- "${BASH_SOURCE[0]}")"
  [[ "$invoked_path" == "$PWD/$relative_path" ]] ||
    die "format wrapper must run from its canonical repository path"
  trusted_hash="$(git rev-parse "main:$relative_path" 2>/dev/null)" ||
    die "format wrapper is not trusted by local main"
  current_hash="$(git hash-object "$relative_path")"
  [[ "$current_hash" == "$trusted_hash" ]] ||
    die "format wrapper differs from trusted local main"
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

fingerprint_path() {
  local path="$1"
  [[ ! -L "$path" ]] || die "refusing symlink path: $path"
  [[ -f "$path" ]] || die "format target is not a regular file: $path"
  git hash-object --no-filters -- "$path"
}

collect_changed_paths() {
  {
    git diff --name-only -z --diff-filter=ACMR --no-renames -- .
    git ls-files -z --others --exclude-standard
  }
}

run_formatter() {
  local -a targets=("$@")

  if [[ -x node_modules/.bin/prettier ]]; then
    node_modules/.bin/prettier --write -- "${targets[@]}"
    node_modules/.bin/prettier --check -- "${targets[@]}"
    return 0
  fi

  die "no trusted path-scoped formatter available; currently supported: repository-local Prettier"
}

main() {
  [[ "$#" -ge 1 ]] || die "usage: <changed-path>..."

  require_repository_root
  require_trusted_wrapper

  local path hash
  local -a targets=("$@")
  declare -A target_set=()
  declare -A changed_set=()
  declare -A outside_before=()

  while IFS= read -r -d '' path; do
    changed_set["$path"]=1
  done < <(collect_changed_paths)

  [[ "${#changed_set[@]}" -gt 0 ]] || die "working tree has no changed paths to format"

  for path in "${targets[@]}"; do
    [[ -n "$path" && "$path" != /* && "$path" != -* ]] ||
      die "invalid relative path: $path"
    [[ "$path" != *$'\n'* && "$path" != *$'\r'* ]] ||
      die "path contains a newline: $path"
    [[ "$path" != ".." && "$path" != ../* && "$path" != */../* && "$path" != */.. ]] ||
      die "path traversal is not allowed: $path"
    [[ -z "${target_set[$path]+x}" ]] || die "duplicate target: $path"
    [[ -n "${changed_set[$path]+x}" ]] ||
      die "target is not currently changed or untracked: $path"
    is_sensitive_path "$path" && die "refusing sensitive format target: $path"
    fingerprint_path "$path" >/dev/null
    target_set["$path"]=1
  done

  for path in "${!changed_set[@]}"; do
    [[ -n "${target_set[$path]+x}" ]] && continue
    [[ ! -L "$path" ]] || die "refusing to operate with changed symlink outside format scope: $path"
    [[ -f "$path" ]] || die "changed path outside format scope is not a regular file: $path"
    outside_before["$path"]="$(git hash-object --no-filters -- "$path")"
  done

  run_formatter "${targets[@]}"

  declare -A after_changed=()
  while IFS= read -r -d '' path; do
    after_changed["$path"]=1
  done < <(collect_changed_paths)

  for path in "${!after_changed[@]}"; do
    [[ -n "${target_set[$path]+x}" ]] && continue
    [[ -n "${outside_before[$path]+x}" ]] ||
      die "formatter created or changed an out-of-scope path: $path"
    hash="$(fingerprint_path "$path")"
    [[ "$hash" == "${outside_before[$path]}" ]] ||
      die "formatter modified an out-of-scope path: $path"
  done

  for path in "${!outside_before[@]}"; do
    [[ -n "${after_changed[$path]+x}" ]] ||
      die "formatter removed an out-of-scope change: $path"
    hash="$(fingerprint_path "$path")"
    [[ "$hash" == "${outside_before[$path]}" ]] ||
      die "formatter modified an out-of-scope path: $path"
  done

  git diff --check -- "${targets[@]}"
  printf 'format-changed: formatted and verified %d path(s)\n' "${#targets[@]}"
}

main "$@"
