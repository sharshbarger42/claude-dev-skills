### Deploy-Aware PR Label Selection

When a skill needs to set a "next step" PR label after approval or fixes, the correct label depends on whether the repo has a dev or prod deploy configuration.

#### How to check

Load `~/.config/development-skills/deploy-config.md` and check the **Service Deploy Config** tables:

1. **Dev deploy check:** Look for the repo name in the `### Dev Environment` table. If the repo appears → it has a dev environment.
2. **Prod deploy check:** Look for the repo name in the `### Prod Environment` table. If the repo appears → it has a prod environment.

#### Label selection rules

**After review approval or fix completion (pre-merge):**
- Repo **has** dev deploy config → set `pr: awaiting-dev-verification`
- Repo has **no** dev deploy config → set `pr: ready-to-merge`

**After merge (post-merge):**
- Repo **has** prod deploy config → set `pr: awaiting-prod-verification`
- Repo has **no** prod deploy config → no label needed (PR is done)

#### Removing post-merge labels

After prod health checks and post-merge verification pass, remove `pr: awaiting-prod-verification` from the PR. If checks fail, leave the label in place — the bug issue created by the merge skill serves as the follow-up.
