#!/usr/bin/env bash
# Release readiness check.
#
#   ./release-readiness.sh release_2          # is release_2 fully back-merged?
#   ./release-readiness.sh release_2.1        # hotfix: checks release_2.1 -> release_2 -> main
#   ./release-readiness.sh --all              # every release_* branch
#
# A branch is READY when, for every hop up to main:
#   * no commits exist on the branch that are missing from its parent
#     (git cherry / patch-id equivalence, so cherry-picked back-merges count), and
#   * no open `back-merge` PRs are pending on that hop.
#
# Exit code: 0 = ready, 1 = not ready, 2 = usage/env error.
# Requires: git (repo with all branches fetched) + gh (authenticated).

set -uo pipefail

REPO="${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)}"
[[ -z "$REPO" ]] && { echo "Cannot determine repo; set REPO=owner/name" >&2; exit 2; }

GH_MD="${GITHUB_STEP_SUMMARY:-/dev/null}"   # also write markdown when in Actions
say()  { echo -e "$1"; echo "$2" >> "$GH_MD"; }

parent_of() {
  if   [[ "$1" =~ ^release_([0-9]+)\.([0-9]+)$ ]]; then echo "release_${BASH_REMATCH[1]}"
  elif [[ "$1" =~ ^release_([0-9]+)$ ]];           then echo "main"
  else return 1; fi
}

ref() { # resolve a branch to a fetched ref
  git rev-parse --verify --quiet "refs/remotes/origin/$1" \
    || git rev-parse --verify --quiet "refs/heads/$1"
}

check_branch() {
  local branch="$1"
  local ready=0
  local current="$branch"

  say "\n=== $branch ===" "## \`$branch\`"

  if ! parent_of "$branch" >/dev/null; then
    say "  ✗ not a release branch (expected release_X or release_X.Y)" "- ✗ not a release branch"
    return 1
  fi
  if ! ref "$branch" >/dev/null; then
    say "  ✗ branch not found" "- ✗ branch not found"
    return 1
  fi

  while [[ "$current" != "main" ]]; do
    local parent; parent="$(parent_of "$current")"
    if ! ref "$parent" >/dev/null; then
      say "  ✗ $current -> $parent: parent branch missing" "- ✗ \`$current\` → \`$parent\`: parent missing"
      ready=1; break
    fi

    # 1. commits present on child but not on parent (patch-id aware)
    local missing
    missing="$(git cherry "$(ref "$parent")" "$(ref "$current")" 2>/dev/null | grep '^+' || true)"

    # 2. open back-merge PRs for this hop
    local open_prs
    open_prs="$(gh pr list --repo "$REPO" --state open --label back-merge --base "$parent" \
                  --json number,title,headRefName \
                  --jq '.[] | "#\(.number) \(.headRefName) — \(.title)"' 2>/dev/null || true)"

    # 3. open back-merge PRs coming INTO this branch (child hotfixes not landed)
    local inbound
    inbound="$(gh pr list --repo "$REPO" --state open --label back-merge --base "$current" \
                 --json number,headRefName --jq '.[] | "#\(.number) \(.headRefName)"' 2>/dev/null || true)"

    if [[ -z "$missing" && -z "$open_prs" ]]; then
      say "  ✓ $current -> $parent: fully merged" "- ✓ \`$current\` → \`$parent\`: fully merged"
    else
      ready=1
      say "  ✗ $current -> $parent: NOT fully merged" "- ✗ \`$current\` → \`$parent\`: **not fully merged**"
      if [[ -n "$missing" ]]; then
        say "      unmerged commits:" "  - unmerged commits:"
        while read -r line; do
          [[ -z "$line" ]] && continue
          local sha="${line:2}"
          say "        - $(git log -1 --format='%h %s' "$sha")" "    - \`$(git log -1 --format='%h' "$sha")\` $(git log -1 --format='%s' "$sha")"
        done <<< "$missing"
      fi
      if [[ -n "$open_prs" ]]; then
        say "      open back-merge PRs:" "  - open back-merge PRs:"
        while read -r p; do [[ -n "$p" ]] && say "        - $p" "    - $p"; done <<< "$open_prs"
      fi
    fi

    if [[ -n "$inbound" ]]; then
      ready=1
      say "  ! pending back-merges INTO $current (not yet landed here):" "- ! pending back-merges into \`$current\`:"
      while read -r p; do [[ -n "$p" ]] && say "        - $p" "    - $p"; done <<< "$inbound"
    fi

    current="$parent"
  done

  if [[ $ready -eq 0 ]]; then
    say "  ✅ $branch is READY to release — everything is merged up to main." "\n**✅ \`$branch\` is READY to release.**"
  else
    say "  ⛔ $branch is NOT ready — see above." "\n**⛔ \`$branch\` is NOT ready to release.**"
  fi
  return $ready
}

main() {
  local rc=0
  local branches=()
  if [[ "${1:-}" == "--all" || $# -eq 0 ]]; then
    while IFS= read -r b; do [[ -n "$b" ]] && branches+=("$b"); done < <(
      git for-each-ref --format='%(refname:short)' 'refs/remotes/origin/release_*' | sed 's#^origin/##' | sort -V
    )
    [[ ${#branches[@]} -eq 0 ]] && { echo "No release_* branches found."; exit 0; }
  else
    branches=("$@")
  fi
  for b in "${branches[@]}"; do
    check_branch "$b" || rc=1
  done
  exit $rc
}

main "$@"
