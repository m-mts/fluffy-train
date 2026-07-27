# fluffy-train

Release-branch automation for GitHub: every fix that lands on a release branch automatically gets its **own** back-merge PR up the chain, and nothing can be released — or merged past — until those back-merges land.

```
                 my-fix-1 ──┐                    ┌──> my-fix-1-to-main ──┐
                 my-fix-2 ──┼──> release_2 ──────┼──> my-fix-2-to-main ──┼──> main
   my-hotfix ──> release_2.1 ──> (to release_2) ─┘                       ┘
```

## What you get

| Piece | What it does |
| --- | --- |
| `.github/workflows/auto-backmerge-pr.yml` | On merge into `release_*`, cherry-picks **only that PR's changes** onto the parent branch and opens a labeled `back-merge` PR named `<branch>-to-<parent>` |
| `.github/workflows/backmerge-guard.yml` + `.github/scripts/backmerge-guard.cjs` | Required `backmerge-guard` status: blocks merging into a branch while back-merge PRs into it are open |
| `.github/workflows/release-readiness.yml` + `.github/scripts/release-readiness.sh` | Answers "is `release_X` good to release?" — on demand, on a schedule, or locally |
| `.github/workflows/release.yml` | Sample release pipeline that refuses to run until the branch is fully back-merged |
| Branch ruleset `backmerge-guard` | `main` + `release_*` are PR-only and require the guard check |

Branch naming: `release_<major>` (e.g. `release_2`) and `release_<major>.<minor>` for hotfixes (e.g. `release_2.1`). Back-merge direction is `release_X.Y → release_X → main`.

## How to use it

### Ship a fix on a release branch

```bash
git checkout -b my-release-fix-1 origin/release_2
# ...work...
git push -u origin my-release-fix-1
gh pr create --base release_2 --head my-release-fix-1 --title "Fix 1"
```

Merge the PR (any merge method). Within ~30s the automation opens **`my-release-fix-1-to-main → main`** containing only that fix. Merge it and you're done. Two fixes merged into `release_2` produce two independent PRs to `main` — you can merge, review, or revert them separately.

Hotfixes cascade one extra hop: a PR merged into `release_2.1` opens `<branch>-to-release_2`, and merging *that* opens `<branch>-to-main`.

### Check whether a release branch is ready

Any of these three:

```bash
# locally (needs gh + fetched branches)
REPO=m-mts/fluffy-train .github/scripts/release-readiness.sh release_2
REPO=m-mts/fluffy-train .github/scripts/release-readiness.sh --all
```

- **Actions → Release readiness → Run workflow** — optional branch input (blank = all release branches). Also runs weekdays 07:00 UTC. Report appears in the run's job summary.
- **Actions → Release → Run workflow** from a release branch (or push a `v*` tag on one) — the release is gated on the same check.

Sample output when work is outstanding:

```
=== release_2 ===
  ✗ release_2 -> main: NOT fully merged
      unmerged commits:
        - 1f8995f Fix 2: add fix2.txt (#5)
      open back-merge PRs:
        - #7 my-release-fix-2-to-main — Back-merge to main: Fix 2
  ⛔ release_2 is NOT ready — see above.
```

Readiness uses `git cherry` (patch-id equivalence), so cherry-picked back-merges count as merged even though their SHAs differ. For hotfix branches every hop up to `main` is checked, and pending back-merges *into* the branch are flagged too.

### Cut a release

Replace the placeholder step in `.github/workflows/release.yml` with your real build/publish steps. The `verify-backmerged` job runs first and fails the whole run if anything is unmerged. `allow_unmerged: true` is the emergency override.

## Rules in effect

- `main` and `release_*` accept changes **only via PR** — direct pushes are rejected (GitHub can't make push rules conditional, so PR-only is what makes the guard enforceable). Creating a new `release_*` branch is still allowed.
- The `backmerge-guard` status is **required** on those branches. PRs labeled `back-merge` always pass it; every other PR into a branch fails while a back-merge PR into that branch is open.
- Merging more fixes into `release_2` is *not* blocked while its back-merges to `main` are open — by design, each fix gets its own PR upward.
- *Delete branch on merge* is on, so `*-to-*` helper branches clean themselves up.

## Troubleshooting

**Cherry-pick conflict.** The workflow comments on the original PR with the exact manual recipe and fails the run:

```bash
git checkout -b my-fix-to-main origin/main
git cherry-pick <merge-sha>       # add -m 1 if it was a merge commit
git push -u origin my-fix-to-main
gh pr create --base main --head my-fix-to-main --label back-merge
```

The `back-merge` label is what makes the guard treat it as a remedy — don't omit it.

**A PR is stuck red on `backmerge-guard`.** Something with the `back-merge` label is still open against the same base branch. Merge it, or re-run **Actions → backmerge-guard → Run workflow** to refresh statuses if a PR closed without a refresh.

**Readiness says unmerged but you merged it.** Squashing a multi-commit PR rewrites the patch, so `git cherry` can't always match it. Confirm with `git log origin/main --oneline | grep <subject>`; if it's genuinely there, it's a false positive on that one commit.

**No back-merge PR appeared.** Check that the base branch matched `release_X`/`release_X.Y` exactly (underscore, no suffix), that the parent branch exists, and Actions → *Auto back-merge PR* for the run. Settings → Actions → General must keep "Allow GitHub Actions to create and approve pull requests" enabled.

## Reproducing this setup on another repo

Copy `.github/` over, then:

```bash
gh label create back-merge --color d93f0b --description "Automated back-merge PR"
gh api repos/OWNER/REPO --method PATCH -F delete_branch_on_merge=true
gh api repos/OWNER/REPO/actions/permissions/workflow --method PUT \
  -F default_workflow_permissions=read -F can_approve_pull_request_reviews=true
```

Then create a branch ruleset targeting `refs/heads/main` and `refs/heads/release_*` with a *pull request* rule and a *required status check* on `backmerge-guard` (GitHub Actions, integration id 15368) with "do not enforce on create" enabled. Full ruleset JSON and rationale: [`.github/RELEASE_FLOW.md`](.github/RELEASE_FLOW.md).
