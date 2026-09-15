#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'dependency-update: %s\n' "$*" >&2
  exit 1
}

require_repository_root() {
  local root
  root="$(git rev-parse --show-toplevel)"
  [[ "$PWD" == "$root" ]] || die "run from repository root: $root"
}

require_trusted_wrapper() {
  local relative_path=".opencode/scripts/dependency-update.sh"
  local wrapper_directory invoked_path trusted_hash current_hash
  wrapper_directory="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  invoked_path="$wrapper_directory/$(basename -- "${BASH_SOURCE[0]}")"
  [[ "$invoked_path" == "$PWD/$relative_path" ]] ||
    die "dependency wrapper must run from its canonical repository path"
  trusted_hash="$(git rev-parse "main:$relative_path" 2>/dev/null)" ||
    die "dependency wrapper is not trusted by local main"
  current_hash="$(git hash-object "$relative_path")"
  [[ "$current_hash" == "$trusted_hash" ]] ||
    die "dependency wrapper differs from trusted local main"
}

validate_package() {
  local action="$1" package="$2"
  [[ "$package" != -* && "$package" != *..* && "$package" != */../* ]] ||
    die "invalid package identifier: $package"
  if [[ "$action" == "add" || "$action" == "add-dev" ]]; then
    [[ "$package" =~ ^(@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*(@[~^]?[0-9A-Za-z][0-9A-Za-z.+_-]*)?$ ]] ||
      die "only registry package identifiers and versions are allowed: $package"
  else
    [[ "$package" =~ ^(@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*$ ]] ||
      die "invalid package name for removal: $package"
  fi
}

require_only_dependency_metadata_changes() {
  local path
  while IFS= read -r -d '' path; do
    case "$path" in
      package.json | */package.json | package-lock.json | */package-lock.json | \
        npm-shrinkwrap.json | */npm-shrinkwrap.json | yarn.lock | */yarn.lock | \
        pnpm-lock.yaml | */pnpm-lock.yaml | bun.lock | */bun.lock | bun.lockb | \
        */bun.lockb)
        ;;
      *) die "package manager changed a non-metadata path: $path" ;;
    esac
  done < <({
    git diff --name-only -z --no-renames -- .
    git ls-files -z --others --exclude-standard
  })
}

run_update() {
  local action="$1" manager="$2"
  shift 2
  case "$action:$manager" in
    add:npm) npm install --ignore-scripts "$@" ;;
    add-dev:npm) npm install --save-dev --ignore-scripts "$@" ;;
    remove:npm) npm uninstall --ignore-scripts "$@" ;;
    add:yarn) yarn add --ignore-scripts "$@" ;;
    add-dev:yarn) yarn add --dev --ignore-scripts "$@" ;;
    remove:yarn) yarn remove --ignore-scripts "$@" ;;
    add:pnpm) pnpm add --ignore-scripts "$@" ;;
    add-dev:pnpm) pnpm add --save-dev --ignore-scripts "$@" ;;
    remove:pnpm) pnpm remove --ignore-scripts "$@" ;;
    add:bun) bun add --ignore-scripts "$@" ;;
    add-dev:bun) bun add --dev --ignore-scripts "$@" ;;
    remove:bun) bun remove --ignore-scripts "$@" ;;
  esac
  require_only_dependency_metadata_changes
}

main() {
  [[ "$#" -ge 3 ]] || die "usage: <add|add-dev|remove|batch> <npm|yarn|pnpm|bun> <package-or-operation>..."
  local action="$1" manager="$2" package operation token current_branch
  local -a add_packages=() dev_packages=() remove_packages=()
  shift 2
  [[ "$action" == "add" || "$action" == "add-dev" || "$action" == "remove" || "$action" == "batch" ]] ||
    die "invalid action"
  case "$manager" in
    npm | yarn | pnpm | bun) ;;
    *) die "unsupported package manager" ;;
  esac
  command -v "$manager" >/dev/null 2>&1 || die "missing package manager: $manager"
  require_repository_root
  require_trusted_wrapper
  current_branch="$(git branch --show-current)"
  [[ "$current_branch" =~ ^feature/[0-9]+-[a-z0-9]+([a-z0-9-]*[a-z0-9])?$ ]] ||
    die "dependency update requires a validated feature branch"
  [[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] ||
    die "dependency update must be the first mutation on a clean feature branch"
  if [[ "$action" == "batch" ]]; then
    for token in "$@"; do
      operation="${token%%:*}"
      package="${token#*:}"
      [[ "$operation" != "$token" ]] || die "batch entries require <add|add-dev|remove>:<package>"
      [[ "$operation" == "add" || "$operation" == "add-dev" || "$operation" == "remove" ]] ||
        die "invalid batch operation: $operation"
      validate_package "$operation" "$package"
      case "$operation" in
        add) add_packages+=("$package") ;;
        add-dev) dev_packages+=("$package") ;;
        remove) remove_packages+=("$package") ;;
      esac
    done
    [[ "${#remove_packages[@]}" -eq 0 ]] || run_update remove "$manager" "${remove_packages[@]}"
    [[ "${#add_packages[@]}" -eq 0 ]] || run_update add "$manager" "${add_packages[@]}"
    [[ "${#dev_packages[@]}" -eq 0 ]] || run_update add-dev "$manager" "${dev_packages[@]}"
  else
    for package in "$@"; do
      validate_package "$action" "$package"
    done
    run_update "$action" "$manager" "$@"
  fi
}

main "$@"
