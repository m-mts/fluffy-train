// Shared guard logic — posts the "backmerge-guard" commit status on every
// open PR targeting main / release_*.
//
// A PR targeting branch B FAILS while any open back-merge PR into B exists,
// unless the PR is itself a back-merge PR (those always pass — they are the
// remedy). Back-merge PRs are identified by the `back-merge` label (set by
// the auto-backmerge workflow) or, legacy, a release_* head targeting its
// parent branch.
module.exports = async ({ github, context, core }) => {
  const CONTEXT = 'backmerge-guard';
  const relRe = /^release_(\d+)(?:\.(\d+))?$/;
  const parentOf = (b) => {
    const m = b.match(relRe);
    if (!m) return null;
    return m[2] !== undefined ? `release_${m[1]}` : 'main';
  };

  const { owner, repo } = context.repo;
  const prs = await github.paginate(github.rest.pulls.list, {
    owner, repo, state: 'open', per_page: 100,
  });

  const isBackmerge = (p) =>
    p.labels.some((l) => l.name === 'back-merge') ||
    (relRe.test(p.head.ref) && p.base.ref === parentOf(p.head.ref));

  const backmerges = prs.filter(isBackmerge);

  for (const pr of prs) {
    const base = pr.base.ref;
    if (base !== 'main' && !relRe.test(base)) continue; // unguarded base

    let state = 'success';
    let description = `No pending back-merges into ${base}.`;

    if (isBackmerge(pr)) {
      description = 'Back-merge PR — always allowed.';
    } else {
      const blockers = backmerges.filter(
        (b) => b.base.ref === base && b.number !== pr.number
      );
      if (blockers.length > 0) {
        state = 'failure';
        description = `Blocked by unmerged back-merge PR(s) into ${base}: ${blockers
          .map((b) => `#${b.number}`)
          .join(', ')}`.slice(0, 140);
      }
    }

    core.info(`PR #${pr.number} (${pr.head.ref} -> ${base}): ${state} — ${description}`);
    await github.rest.repos.createCommitStatus({
      owner, repo,
      sha: pr.head.sha,
      context: CONTEXT,
      state,
      description,
      target_url: `${context.serverUrl}/${owner}/${repo}/actions/runs/${context.runId}`,
    });
  }
};
