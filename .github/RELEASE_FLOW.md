# Release branch flow

Branch hierarchy and back-merge direction:

```
release_2.1 (hotfix) ──> release_2 ──> main
```

Branch naming: `release_<major>` (e.g. `release_2`), `release_<major>.<minor>` for hotfixes (e.g. `release_2.1`).

`main` and all `release_*` branches are protected: **changes land only via PR** (direct pushes rejected), and the **backmerge-guard** status check is required. Creating new `release_*` branches is still allowed.

## Automations

### 1. `auto-backmerge-pr.yml` — granular back-merge PRs

When a PR merges into a `release_*` branch, the workflow cherry-picks **only that PR's changes** onto the parent branch (`release_X.Y → release_X`, `release_X → main`) in a new branch named `<original-branch>-to-<parent>`, and opens a dedicated PR labeled `back-merge`.

Example — two fixes merged into `release_2`:

```
my-release-fix-1 ──PR──> release_2   =>  my-release-fix-1-to-main ──PR──> main
my-release-fix-2 ──PR──> release_2   =>  my-release-fix-2-to-main ──PR──> main
```

Each PR to `main` contains only its own fix. Hotfixes cascade: a PR merged into `release_2.1` produces `<name>-to-release_2 → release_2`, and merging that produces `<name>-to-main → main` (the `-to-*` suffix doesn't accumulate).

All merge methods are supported (merge commit, squash, rebase). On a cherry-pick conflict the workflow comments on the original PR with manual back-merge instructions and fails the run.

### 2. `backmerge-guard.yml` + `scripts/backmerge-guard.cjs`

Posts the required `backmerge-guard` status on every open PR targeting `main`/`release_*`:

- PRs **labeled `back-merge`** always pass — they are the remedy.
- Any other PR targeting branch `B` **fails while an open `back-merge` PR into `B` exists** — pending back-merges must land first.

Statuses refresh on PR open/update/close/label events and after each auto back-merge; manual refresh via workflow_dispatch in the Actions tab.

Note: merging more fixes into `release_2` is *not* blocked while its back-merges to `main` are open — by design, each fix produces its own granular PR to `main`.

### 3. Branch ruleset `backmerge-guard` (id 19781015, active)

Targets `main` and `release_*`. Rules: pull request required (0 approvals — raise in Settings → Rules if you want reviews), `backmerge-guard` status check required (from GitHub Actions), branch creation exempt. Repo also has *delete branch on merge* enabled, so `*-to-*` helper branches clean themselves up.

## Typical cycle

1. Branch `my-release-fix-1` off `release_2`, open PR into `release_2`, merge when guard is green.
2. Automation opens `my-release-fix-1-to-main → main` with just that fix. Other (non-back-merge) PRs into `main` are blocked until it merges.
3. Merge it into `main`; guard goes green everywhere.

Same for hotfix branches, with one extra hop: `release_2.1 → release_2 → main`.
