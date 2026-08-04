# Release flow

Universal Hub uses three release lanes. A green test suite is necessary, but it is not a production promotion by itself.

## 1. Development

- Start each change in its own `codex/<lane>` branch and worktree from the current `origin/main` whenever possible. A long-running candidate may retain an older mainline ancestor, but staging must merge its exact reviewed SHA without rewriting it.
- Keep unrelated fixes in separate commits. Never copy a dirty checkout wholesale into another lane.
- Record the exact commit, focused tests, full `scripts/check.sh` result, and matching live evidence before selecting a candidate.
- A candidate that still needs a game state, server-observable result, or visual/performance proof remains local.

## 2. Staging

- Create `codex/staging-<date>-<build>` from the current `origin/main` without rewriting history.
- Create one merge commit whose first parent is the exact production base and whose second parent is the one selected candidate head. The checker independently recreates the conflict-free merge tree. That merge commit is the staging integration commit; undeclared staging-line commits, custom conflict resolutions, and hidden merges are rejected. A second candidate requires a new staging build after it has been rebased or replayed into one reviewed head.
- Add immutable `release/staging-manifest.tsv`, mutable `release/staging-gates.tsv`, and the automated evidence receipt in the commit immediately after integration. The checker locks that automated receipt at the identity commit. Use the tracked examples as their schemas.
- Run `./scripts/check-promotion.sh staging`. It verifies the remote-main base, staging branch/build identity, merge topology, exact candidate inclusion, committed evidence hashes, required gate inventory, clean worktree including untracked files, and every post-integration commit path.
- The repository ruleset allows the initial staging-branch creation, then requires squash-only pull requests for every update and rejects deletion or non-fast-forward pushes. Update only the gate file and tracked `release/evidence/<gate>.tsv` receipts through those PRs. The checker rejects any later identity-manifest edit, merge inside the staging history, or code change, even if a later commit reverts it. Do not amend an already shared staging receipt.
- Validate each protected staging head by dispatching the workflow from trusted `main`, for example `gh workflow run promotion.yml --ref main -f staging_ref=codex/staging-<date>-<build>`. There is intentionally no staging-push workflow sourced from a candidate branch.

Every staging build must report:

- an immutable build ID;
- the production base, each selected candidate SHA, and the integration SHA;
- the automated check receipt;
- a fixed-scene performance receipt;
- separate RIVALS, Counterblox, and Town live receipts;
- reload and final-cleanup evidence.

The performance receipt compares Hub stopped, UI-only, Adapter alive with all consumers disabled, and each enabled feature under test in the same fixed scene for at least 10 seconds. Production requires Adapter all-off work at or below `0.25 ms/frame`, zero hidden observations, rays, entity writes, or geometry while consumers are disabled, and both UI-only and Adapter all-off FPS at or above 95% of the stopped baseline.

## 3. Production

- Run `./scripts/check-promotion.sh production` on the exact staging head.
- The command refuses promotion unless every required gate is `pass`, its canonical tracked evidence file matches the recorded SHA-256, the evidence is bound to the immutable build/integration identity, and its gate-specific safety assertions pass.
- Open the production PR from the staging branch. Do not bypass staging with a candidate branch and do not force-push the staging or production branch.
- Merge to `main` only after the PR diff contains the selected candidates plus release receipts and the exact staging build is still green.
- The base-sourced `pull_request_target` workflow gives the candidate a read-only checkout with no secrets, installs the pinned toolchain, and runs the base branch's trusted `scripts/check.sh` and promotion checker against it. A product candidate cannot replace its workflow or validator, remove an established contract test, or hide a newly added contract from discovery. Production PRs also require `promotion / attest` through the protected `production-promotion` environment. Its required project-manager reviewer is the trust root for the committed performance and live-QA attestations; their hashes prove immutability, not that a measurement generated itself. Repository administrators are the release trust boundary and must not approve an attestation they have not independently checked.
- `main` protection must require pull requests and both production jobs, apply to administrators, and disallow direct/force pushes and deletion. The bootstrap PR that introduces this workflow uses the temporary required `bootstrap / promotion-flow` status, which the project manager marks successful only after the local full suite and five independent exact-SHA reviews pass. Immediately after merging it, replace that status requirement with `promotion / verify` and `promotion / attest`. Configure the protected environment and staging ruleset before creating the first staging build.

If a gate fails, leave the staging receipt intact, fix the problem in a focused development lane, and create a new staging integration. Do not repair an already tested staging tree in place.
