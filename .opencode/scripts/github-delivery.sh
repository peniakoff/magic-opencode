#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'github-delivery: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_repository_root() {
  local root
  root="$(git rev-parse --show-toplevel)"
  [[ "$PWD" == "$root" ]] || die "run from repository root: $root"
}

repository_from_origin() {
  local origin
  origin="$(git config --get remote.origin.url)"
  case "$origin" in
    git@github.com:*.git)
      printf '%s\n' "${origin#git@github.com:}" | sed 's/\.git$//'
      ;;
    https://github.com/*.git | https://github.com/*)
      printf '%s\n' "${origin#https://github.com/}" | sed 's/\.git$//'
      ;;
    *) die "origin is not a supported GitHub remote" ;;
  esac
}

require_trusted_wrapper() {
  local relative_path=".opencode/scripts/github-delivery.sh"
  local wrapper_directory invoked_path trusted_hash current_hash
  wrapper_directory="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  invoked_path="$wrapper_directory/$(basename -- "${BASH_SOURCE[0]}")"
  [[ "$invoked_path" == "$PWD/$relative_path" ]] ||
    die "delivery wrapper must run from its canonical repository path"
  trusted_hash="$(git rev-parse "main:$relative_path" 2>/dev/null)" ||
    die "delivery wrapper is not trusted by local main"
  current_hash="$(git hash-object "$relative_path")"
  [[ "$current_hash" == "$trusted_hash" ]] ||
    die "delivery wrapper differs from trusted local main"
}

parse_issue_url() {
  local url="$1"
  if [[ ! "$url" =~ ^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/issues/([1-9][0-9]*)/?$ ]]; then
    die "expected exactly one canonical GitHub issue URL"
  fi
  ISSUE_REPOSITORY="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  ISSUE_NUMBER="${BASH_REMATCH[3]}"
}

require_issue_repository() {
  local origin_repository normalized_issue_repository normalized_origin_repository
  parse_issue_url "$1"
  origin_repository="$(repository_from_origin)"
  normalized_issue_repository="$(printf '%s' "$ISSUE_REPOSITORY" | tr '[:upper:]' '[:lower:]')"
  normalized_origin_repository="$(printf '%s' "$origin_repository" | tr '[:upper:]' '[:lower:]')"
  [[ "$normalized_issue_repository" == "$normalized_origin_repository" ]] ||
    die "issue repository does not match origin"
  REPOSITORY="$origin_repository"
}

require_feature_branch() {
  CURRENT_BRANCH="$(git branch --show-current)"
  [[ "$CURRENT_BRANCH" =~ ^feature/[0-9]+-[a-z0-9]+([a-z0-9-]*[a-z0-9])?$ ]] ||
    die "current branch is not a validated feature branch"
}

require_clean_tree() {
  [[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] ||
    die "working tree must be clean"
}

require_pr_number() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]] || die "invalid pull request number"
}

read_pr() {
  local number="$1"
  gh pr view "$number" --repo "$REPOSITORY" \
    --json number,state,mergeable,reviewDecision,headRefName,headRefOid,baseRefName,mergedAt,mergeCommit,statusCheckRollup
}

require_pr_binding() {
  local number="$1"
  local pr_json="$2"
  local actual_number base head local_head remote_head
  actual_number="$(jq -r '.number' <<<"$pr_json")"
  base="$(jq -r '.baseRefName' <<<"$pr_json")"
  head="$(jq -r '.headRefName' <<<"$pr_json")"
  remote_head="$(jq -r '.headRefOid' <<<"$pr_json")"
  local_head="$(git rev-parse HEAD)"
  [[ "$actual_number" == "$number" ]] || die "pull request number changed"
  [[ "$base" == "main" ]] || die "pull request base is not main"
  [[ "$head" == "$CURRENT_BRANCH" ]] || die "pull request head does not match current branch"
  [[ "$remote_head" == "$local_head" ]] ||
    die "pull request head does not match locally reviewed HEAD"
}

checks_json() {
  gh pr checks "$1" --repo "$REPOSITORY" --json name,state,bucket 2>/dev/null ||
    printf '[]\n'
}

require_passing_checks() {
  local number="$1"
  local checks
  checks="$(checks_json "$number")"
  [[ "$(jq 'length' <<<"$checks")" -gt 0 ]] || die "pull request has no checks"
  jq -e 'all(.[]; .bucket == "pass")' <<<"$checks" >/dev/null ||
    die "not every pull request check passed"
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

scan_changed_paths() {
  local path
  while IFS= read -r -d '' path; do
    is_sensitive_path "$path" && die "refusing sensitive changed path: $path"
  done < <({
    git diff --name-only -z --no-renames --no-ext-diff --no-textconv -- .
    git ls-files -z --others --exclude-standard
  })
  return 0
}

scan_secret_additions() {
  local path scan_status
  scan_status=0
  git diff --no-renames --no-ext-diff --no-textconv -U0 -- . | \
    grep '^+' | grep -Ei "$SECRET_PATTERN" >/dev/null || scan_status="$?"
  [[ "$scan_status" -eq 1 ]] || {
    [[ "$scan_status" -eq 0 ]] && die "changed additions resemble a secret"
    die "failed to scan changed additions"
  }

  while IFS= read -r -d '' path; do
    scan_status=0
    grep -Ei "$SECRET_PATTERN" "$path" >/dev/null || scan_status="$?"
    [[ "$scan_status" -eq 1 ]] || {
      [[ "$scan_status" -eq 0 ]] && die "untracked content resembles a secret: $path"
      die "failed to scan untracked file: $path"
    }
  done < <(git ls-files -z --others --exclude-standard)
  return 0
}

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

scan_index_secrets() {
  local path scan_status
  while IFS= read -r -d '' path; do
    git cat-file -e ":$path" 2>/dev/null || continue
    scan_status=0
    git cat-file blob ":$path" | grep -a -Ei "$SECRET_PATTERN" >/dev/null ||
      scan_status="$?"
    [[ "$scan_status" -eq 1 ]] || {
      [[ "$scan_status" -eq 0 ]] && return 0
      return 2
    }
  done < <(git diff --cached --name-only -z --diff-filter=ACMR)
  return 1
}

clear_index() {
  git restore --staged -- "$@" >/dev/null 2>&1 || git read-tree HEAD
  [[ -z "$(git diff --cached --name-only)" ]] ||
    die "failed to clear rejected staged changes"
}

inspect_repository() {
  local path diff_status artifact scan_status
  [[ "$#" -eq 0 ]] || die "usage: inspect"
  scan_changed_paths
  artifact="$(mktemp "${TMPDIR:-/tmp}/opencode-inspect.XXXXXX")"
  INSPECTION_ARTIFACT="$artifact"
  trap 'rm -f "${INSPECTION_ARTIFACT:-}"' EXIT
  {
    printf '%s\n' "## Branch and status"
    git -c core.fsmonitor=false --no-pager status --short --branch --untracked-files=all
    printf '%s\n' "## Changed paths"
    git -c core.fsmonitor=false --no-pager diff --name-status --no-renames \
      --no-ext-diff --no-textconv -- .
    while IFS= read -r -d '' path; do
      printf '??\t%s\n' "$path"
    done < <(git ls-files -z --others --exclude-standard)
    printf '%s\n' "## Diff"
    git -c core.fsmonitor=false --no-pager diff --no-renames --no-ext-diff \
      --no-textconv -- . | emit_redacted_diff
    while IFS= read -r -d '' path; do
      diff_status=0
      git -c core.fsmonitor=false --no-pager diff --no-ext-diff --no-textconv \
        --no-index -- /dev/null "$path" | emit_redacted_diff || diff_status="$?"
      [[ "$diff_status" -eq 0 || "$diff_status" -eq 1 ]] ||
        die "failed to inspect untracked file: $path"
    done < <(git ls-files -z --others --exclude-standard)
  } >"$artifact"
  scan_status=0
  grep -a -Ei "$SECRET_PATTERN" "$artifact" >/dev/null || scan_status="$?"
  [[ "$scan_status" -eq 1 ]] || {
    [[ "$scan_status" -eq 0 ]] && die "inspection snapshot still resembles a secret"
    die "failed to scan inspection snapshot"
  }
  command cat "$artifact"
  rm -f "$artifact"
  INSPECTION_ARTIFACT=""
  trap - EXIT
}

prepare() {
  [[ "$#" -eq 1 ]] || die "usage: prepare <issue-url>"
  require_issue_repository "$1"
  require_clean_tree
  gh auth status --hostname github.com >/dev/null

  local issue_json state title slug branch
  issue_json="$(gh issue view "$ISSUE_NUMBER" --repo "$REPOSITORY" --json state,title)"
  state="$(jq -r '.state' <<<"$issue_json")"
  [[ "$state" == "OPEN" ]] || die "issue is not open"
  [[ -d .github/workflows ]] || die "GitHub Actions workflows are missing"
  local workflow workflow_found="false"
  for workflow in .github/workflows/*.yml .github/workflows/*.yaml; do
    if [[ -f "$workflow" ]]; then
      workflow_found="true"
      break
    fi
  done
  [[ "$workflow_found" == "true" ]] || die "GitHub Actions workflows are missing"
  git show-ref --verify --quiet refs/heads/main || die "local main branch is missing"

  title="$(jq -r '.title' <<<"$issue_json")"
  slug="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-48)"
  slug="${slug%-}"
  [[ -n "$slug" ]] || slug="issue"
  branch="feature/${ISSUE_NUMBER}-${slug}"
  git show-ref --verify --quiet "refs/heads/$branch" && die "local feature branch already exists"
  [[ -z "$(git ls-remote --heads origin "$branch")" ]] || die "remote feature branch already exists"

  git fetch origin main
  git switch main
  git pull --ff-only origin main
  git switch -c "$branch"
  printf '%s\n' "$branch"
}

commit_changes() {
  [[ "$#" -ge 2 ]] || die "usage: commit <conventional-message> <path>..."
  require_feature_branch
  [[ -z "$(git diff --cached --name-only)" ]] || die "index must be empty before staging"

  local message="$1"
  shift
  [[ "$message" != *$'\n'* ]] || die "commit message must be one line"
  [[ "$message" =~ ^(feat|fix|docs|refactor|test|build|ci|chore|perf)(\([a-z0-9._/-]+\))?\!?:\ .+ ]] ||
    die "commit message is not Conventional Commit format"

  local path requested_paths changed_paths
  local -a pathspecs=()
  for path in "$@"; do
    [[ -n "$path" && "$path" != "." && "$path" != -* && "$path" != /* && "$path" != *$'\n'* ]] ||
      die "invalid staged path"
    [[ ! -d "$path" ]] || die "staged paths must name files, not directories: $path"
    is_sensitive_path "$path" && die "refusing sensitive or escaping path: $path"
    pathspecs+=(":(literal)$path")
  done

  requested_paths="$(printf '%s\n' "$@" | sed 's#^\./##' | sort -u)"
  changed_paths="$({
    git diff --name-only --no-renames --no-ext-diff --no-textconv -- .
    git ls-files --others --exclude-standard
  } | sort -u)"
  [[ -n "$changed_paths" ]] || die "working tree has no changes"
  [[ "$changed_paths" == "$requested_paths" ]] ||
    die "explicit file list does not match every working-tree change"
  scan_changed_paths
  scan_secret_additions

  git add -- "${pathspecs[@]}"
  if [[ -z "$(git diff --cached --name-only)" ]]; then
    clear_index "${pathspecs[@]}"
    die "nothing was staged"
  fi
  local staged_paths
  staged_paths="$(git diff --cached --name-only | sort -u)"
  if [[ "$staged_paths" != "$requested_paths" ]]; then
    clear_index "${pathspecs[@]}"
    die "staged files differ from the explicit file list"
  fi
  local index_scan_status=0
  scan_index_secrets || index_scan_status="$?"
  if [[ "$index_scan_status" -ne 1 ]]; then
    clear_index "${pathspecs[@]}"
    [[ "$index_scan_status" -eq 0 ]] && die "staged blob content resembles a secret"
    die "failed to scan staged blob content"
  fi
  if ! git diff --cached --check; then
    clear_index "${pathspecs[@]}"
    die "staged diff failed whitespace validation"
  fi
  git commit -m "$message"
  require_clean_tree
}

push_branch() {
  [[ "$#" -eq 0 ]] || die "usage: push"
  require_feature_branch
  require_clean_tree
  REPOSITORY="$(repository_from_origin)"
  git push --set-upstream origin "$CURRENT_BRANCH"
}

create_pr() {
  [[ "$#" -eq 3 ]] || die "usage: create-pr <issue-url> <title> <body>"
  require_issue_repository "$1"
  require_feature_branch
  local title="$2" body="$3"
  [[ "$CURRENT_BRANCH" == "feature/${ISSUE_NUMBER}-"* ]] ||
    die "current branch does not belong to the issue"
  [[ "$title" != *$'\n'* && -n "$title" ]] || die "pull request title must be one line"
  [[ "$body" == *"Closes #${ISSUE_NUMBER}"* ]] || die "pull request body must close the issue"
  gh pr create --repo "$REPOSITORY" --base main --head "$CURRENT_BRANCH" \
    --title "$title" --body "$body"
}

wait_checks() {
  [[ "$#" -eq 1 ]] || die "usage: wait-checks <pr-number>"
  require_pr_number "$1"
  REPOSITORY="$(repository_from_origin)"
  require_feature_branch

  local pr_json check_count attempt known_checks current_checks stable_rounds watch_rounds
  check_count=0
  for attempt in 1 2 3 4 5 6 7; do
    pr_json="$(read_pr "$1")"
    require_pr_binding "$1" "$pr_json"
    check_count="$(jq '.statusCheckRollup | length' <<<"$pr_json")"
    [[ "$attempt" -eq 7 ]] || sleep 10
  done
  [[ "$check_count" -gt 0 ]] || die "no checks appeared during the 60-second registration window"
  known_checks="$(jq -r '.statusCheckRollup[].name' <<<"$pr_json" | sort -u)"
  stable_rounds=0
  watch_rounds=0
  while [[ "$stable_rounds" -lt 4 && "$watch_rounds" -lt 18 ]]; do
    watch_rounds=$((watch_rounds + 1))
    gh pr checks "$1" --repo "$REPOSITORY" --watch --interval 10
    pr_json="$(read_pr "$1")"
    require_pr_binding "$1" "$pr_json"
    current_checks="$(jq -r '.statusCheckRollup[].name' <<<"$pr_json" | sort -u)"
    [[ -n "$current_checks" ]] || die "pull request check set became empty"
    if [[ "$current_checks" != "$known_checks" ]]; then
      known_checks="$current_checks"
      stable_rounds=0
    else
      require_passing_checks "$1"
      stable_rounds=$((stable_rounds + 1))
    fi
    [[ "$stable_rounds" -ge 4 ]] || sleep 10
  done
  [[ "$stable_rounds" -ge 4 ]] || die "pull request check set did not stabilize"
}

merge_pr() {
  [[ "$#" -eq 2 ]] || die "usage: merge <pr-number> <expected-head-sha>"
  require_pr_number "$1"
  [[ "$2" =~ ^[0-9a-f]{40}$ ]] || die "invalid expected head SHA"
  REPOSITORY="$(repository_from_origin)"
  require_feature_branch
  wait_checks "$1"

  local pr_json state mergeable review_decision head_sha
  pr_json="$(read_pr "$1")"
  require_pr_binding "$1" "$pr_json"
  state="$(jq -r '.state' <<<"$pr_json")"
  mergeable="$(jq -r '.mergeable' <<<"$pr_json")"
  review_decision="$(jq -r '.reviewDecision // ""' <<<"$pr_json")"
  head_sha="$(jq -r '.headRefOid' <<<"$pr_json")"
  [[ "$state" == "OPEN" ]] || die "pull request is not open"
  [[ "$mergeable" == "MERGEABLE" ]] || die "pull request is not mergeable"
  [[ "$review_decision" != "CHANGES_REQUESTED" && "$review_decision" != "REVIEW_REQUIRED" ]] ||
    die "pull request review is incomplete"
  [[ "$head_sha" == "$2" ]] || die "pull request head changed after validation"
  require_passing_checks "$1"
  gh pr merge "$1" --repo "$REPOSITORY" --squash --delete-branch \
    --match-head-commit "$2"
}

cleanup() {
  [[ "$#" -eq 2 ]] || die "usage: cleanup <issue-url> <pr-number>"
  require_issue_repository "$1"
  require_pr_number "$2"
  require_clean_tree

  local pr_json actual_number state base merged_at merge_commit head head_sha issue_state local_tip
  pr_json="$(read_pr "$2")"
  actual_number="$(jq -r '.number' <<<"$pr_json")"
  state="$(jq -r '.state' <<<"$pr_json")"
  base="$(jq -r '.baseRefName' <<<"$pr_json")"
  merged_at="$(jq -r '.mergedAt // ""' <<<"$pr_json")"
  merge_commit="$(jq -r '.mergeCommit.oid // ""' <<<"$pr_json")"
  head="$(jq -r '.headRefName' <<<"$pr_json")"
  head_sha="$(jq -r '.headRefOid' <<<"$pr_json")"
  [[ "$actual_number" == "$2" ]] || die "pull request number changed"
  [[ "$state" == "MERGED" ]] || die "pull request is not merged"
  [[ "$base" == "main" ]] || die "merged pull request base is not main"
  [[ -n "$merged_at" ]] || die "pull request is not merged"
  [[ "$merge_commit" =~ ^[0-9a-f]{40}$ ]] || die "merged pull request has no valid merge commit"
  [[ "$head" =~ ^feature/${ISSUE_NUMBER}-[a-z0-9]+([a-z0-9-]*[a-z0-9])?$ ]] ||
    die "merged pull request head does not match issue"
  if git show-ref --verify --quiet "refs/heads/$head"; then
    local_tip="$(git rev-parse "refs/heads/$head")"
    [[ "$local_tip" == "$head_sha" ]] ||
      die "local feature branch tip differs from the merged pull request head"
  fi

  git switch main
  git pull --ff-only origin main
  git merge-base --is-ancestor "$merge_commit" HEAD ||
    die "GitHub merge commit is not present in local main"
  if git show-ref --verify --quiet "refs/heads/$head"; then
    git branch -D -- "$head"
  fi
  [[ -z "$(git ls-remote --heads origin "$head")" ]] || die "remote feature branch still exists"
  issue_state="$(gh issue view "$ISSUE_NUMBER" --repo "$REPOSITORY" --json state --jq '.state')"
  if [[ "$issue_state" == "OPEN" ]]; then
    gh issue close "$ISSUE_NUMBER" --repo "$REPOSITORY" --reason completed
  fi
  require_clean_tree
}

main() {
  require_command git
  require_command gh
  require_command jq
  require_command sed
  require_repository_root
  require_trusted_wrapper
  local action="${1:-}"
  [[ -n "$action" ]] || die "missing action"
  shift
  case "$action" in
    inspect) inspect_repository "$@" ;;
    prepare) prepare "$@" ;;
    commit) commit_changes "$@" ;;
    push) push_branch "$@" ;;
    create-pr) create_pr "$@" ;;
    wait-checks) wait_checks "$@" ;;
    merge) merge_pr "$@" ;;
    cleanup) cleanup "$@" ;;
    *) die "unsupported action: $action" ;;
  esac
}

main "$@"
