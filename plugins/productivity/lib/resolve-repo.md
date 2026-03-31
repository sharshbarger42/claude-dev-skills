# Repo Resolution Logic

Use this shared logic to parse issue/PR/repo references in dev-workflow skills.

## Load the shorthand table

!`cat $HOME/.config/development-skills/config/repos.md`

## Parsing rules

**Input formats:**
- Full URL: `https://git.home.superwerewolves.ninja/super-werewolves/food-automation/issues/18`
- Owner/repo#N: `super-werewolves/food-automation#18`
- Shorthand#N: `food-automation#18`
- Repo only (no issue/PR): `food-automation` or `super-werewolves/food-automation`

**How to parse:**
- **Full URL**: extract owner/repo from the path segments, index from the last numeric segment
- **`owner/repo#N`**: split on `/` and `#`
- **`repo#N`** or **`repo`**: look up repo in the shorthand table above, extract index after `#` if present
- **Local path**: use the `Local path` column from the shorthand table for the resolved repo

If the repo doesn't match any known shorthand and no owner is given, stop and ask the user for the full `owner/repo`.
