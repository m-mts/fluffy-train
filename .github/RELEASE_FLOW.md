# Release branch flow

Branch hierarchy and back-merge direction:

```
release_2.1 (hotfix) ──PR──> release_2 ──PR──> main
```

Branch naming: `release_<major>` (e.g. `release_2`), `release_<major>.<minor>` for hotfixes (e.g. `release_2.1`).

## Automations

### 1. `auto-backmerge-pr.yml`

On every push to a `release_*` branch, automatically opens a PR back to the parent branch (`release_X.Y → release_X`, `release_X → main`). If an open back-merge PR already exists, new commits ride along. Skips when there is nothing to merge or the parent branch doesn't exist. PRs get the `back-merge` label.

### 2. `backmerge-guard.yml`

Posts a commit status (context `backmerge-guard`) on every open PR targeting `main` or `release_*`. A PR targeting branch `B` **fails** the check when an open back-merge PR into `B` exists, or `B` itself has an unmerged back-merge PR to its parent. Auto back-merge PRs always pass — they are the remedy. Statuses refresh automatically when PRs open, update, or close; you can also trigger a refresh manually from the Actions tab (workflow_dispatch).

### 3. Branch ruleset `backmerge-guard` (id 19781015, active)

Targets `release_*` branches and requires the `backmerge-guard` status check (from GitHub Actions) before the branch can be updated.

Consequences to be aware of:

- All changes to `release_*` branches must go through PRs — direct pushes are rejected, because a directly-pushed commit can never carry a passing `backmerge-guard` status. This is a GitHub limitation: push-time rules can't depend on external state, so PR-only flow is what makes the conditional blocking enforceable.
- Creating a new `release_*` branch is still allowed (`do_not_enforce_on_create`).
- `main` is intentionally **not** in the ruleset — the guard status still appears on PRs targeting `main`, but it isn't required there. To enforce it on `main` too, add `refs/heads/main` to the ruleset's included refs (Settings → Rules → Rulesets → backmerge-guard).

## Typical hotfix cycle

1. Branch a fix off `release_2.1`, open a PR into `release_2.1`, merge it (guard is green when `release_2.1` has no pending back-merge).
2. The merge push triggers auto-creation of PR `release_2.1 → release_2`. While it's open, other PRs into `release_2` (and into `release_2.1`) are blocked.
3. Merge the back-merge PR into `release_2`. That push triggers PR `release_2 → main`.
4. Merge into `main`. Everything is green again.
