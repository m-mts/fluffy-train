# Release branch flow — reference

Day-to-day usage and troubleshooting live in the [README](../README.md). This file is the design/config reference.

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

Exact configuration (`gh api repos/OWNER/REPO/rulesets --method POST --input ruleset.json`):

```json
{
  "name": "backmerge-guard",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": { "include": ["refs/heads/main", "refs/heads/release_*"], "exclude": [] }
  },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["merge", "squash", "rebase"]
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "do_not_enforce_on_create": true,
        "required_status_checks": [
          { "context": "backmerge-guard", "integration_id": 15368 }
        ]
      }
    }
  ]
}
```

`integration_id` 15368 is the GitHub Actions app — pinning it means an arbitrary token can't post a green `backmerge-guard` status. `do_not_enforce_on_create: true` keeps `git push origin main:release_3` working for new release branches.

### Why `pull_request_target`

Both workflows need a write-capable token and must run from trusted code. `pull_request_target` runs the **base branch's** workflow definition with a write token; neither workflow checks out or executes PR head code (auto-backmerge only cherry-picks already-merged commits; the guard only calls the API), so fork PRs are handled safely.

### Why direct pushes to release branches are rejected

A required status check can only be evaluated on a PR. GitHub's push rules can't depend on external state like "are there open back-merge PRs", so PR-only flow is what makes conditional blocking enforceable at all.

### 4. Is `release_X` good to release?

`scripts/release-readiness.sh` walks every hop up to `main` and reports, per hop, commits that haven't landed in the parent (`git cherry`, patch-id based, so cherry-picked back-merges count as merged) plus any open `back-merge` PRs. Exit 0 = ready.

```
$ .github/scripts/release-readiness.sh release_2
=== release_2 ===
  ✗ release_2 -> main: NOT fully merged
      unmerged commits:
        - 1f8995f Fix 2: add fix2.txt (#5)
      open back-merge PRs:
        - #7 my-release-fix-2-to-main — Back-merge to main: Fix 2
  ⛔ release_2 is NOT ready — see above.
```

Ways to run it:

- **Actions → Release readiness → Run workflow** (optional branch input; blank = all release branches). Also runs weekdays 07:00 UTC. Results land in the run's job summary.
- Locally: `REPO=m-mts/fluffy-train .github/scripts/release-readiness.sh release_2` (needs `gh` + fetched branches; `--all` for every release branch).
- `release.yml` calls it as a hard gate — see below.

Hotfix branches are checked through the whole chain (`release_2.1 → release_2 → main`), and pending back-merges *into* the branch are flagged too.

### 5. `release.yml` — sample gated release

Dispatch from a `release_*` branch (or push a `v*` tag on one). The `verify-backmerged` job fails the release when anything is unmerged or a back-merge PR is still open; the actual release job only runs after it passes. `allow_unmerged: true` is an emergency override. Replace the placeholder build/publish step with your real release steps.

## Typical cycle

1. Branch `my-release-fix-1` off `release_2`, open PR into `release_2`, merge when guard is green.
2. Automation opens `my-release-fix-1-to-main → main` with just that fix. Other (non-back-merge) PRs into `main` are blocked until it merges.
3. Merge it into `main`; guard goes green everywhere.

Same for hotfix branches, with one extra hop: `release_2.1 → release_2 → main`.
