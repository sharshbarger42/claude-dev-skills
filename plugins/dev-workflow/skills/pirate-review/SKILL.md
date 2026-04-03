---
name: pirate-review
description: Review code, files, or PRs with best-practice analysis delivered in full pirate voice. Ends with a joke or shanty.
args: "<file|dir|URL|repo#N>"
---

# Pirate Review

Ahoy! Review any code, config, or PR — research what best practices apply, then deliver the verdict in full pirate voice. Finish with a pirate joke or sea shanty.

**Input:** One of:
- A local file path: `/home/user/project/app.py`
- A local directory: `./src/components/`
- A URL (raw file, gist, etc.)
- A PR reference: `food-automation#32`, `super-werewolves/homelab-setup#771`, or a full Gitea URL

## Step 1: Determine input type and fetch content

Parse the argument to determine what we're reviewing:

### Local file
If the argument looks like a file path (starts with `/`, `./`, `~/`, or has a file extension):
1. Read the file with the Read tool
2. Note the language/format from the extension

### Local directory
If the argument is a directory:
1. List files with `ls -la`
2. Read key files (README, config files, entry points — up to 10 files, prioritize by relevance)
3. Note the project type and languages used

### URL
If the argument starts with `http://` or `https://` and is NOT a Gitea PR URL:
1. Fetch the content with WebFetch
2. Note the content type

### PR reference
If the argument matches a PR pattern (`repo#N`, `owner/repo#N`, or a Gitea pulls URL):
1. Extract `owner`, `repo`, and `index`

#### Repo resolution

!`cat $HOME/.config/development-skills/lib/resolve-repo.md`

2. Fetch PR metadata with `mcp__gitea__pull_request_read` (method: `get`)
3. Fetch the diff with `mcp__gitea__pull_request_read` (method: `get_diff`)
4. Record that this is a PR review — the output will be posted as a PR comment

## Step 2: Identify what we're looking at

Determine the category of the content so we can research the right best practices:

- **Programming language** (Python, TypeScript, Go, Rust, Bash, etc.)
- **Config format** (YAML, JSON, TOML, HCL, Dockerfile, etc.)
- **Infrastructure** (Kubernetes manifests, Terraform, Ansible, Helm charts, CI/CD workflows)
- **Documentation** (Markdown, RST, plain text)
- **Web** (HTML, CSS, React components, API endpoints)
- **Other** (binary, unknown — do your best)

Record: `{content_type}`, `{language}`, `{framework}` (if detectable).

## Step 3: Research best practices

Based on the content type identified in Step 2, research what best practices apply. Use your knowledge of:

- Language-specific idioms and conventions (PEP 8, Go proverbs, Rust patterns, etc.)
- Framework best practices (FastAPI, React, Express, etc.)
- Security best practices (OWASP, injection prevention, secrets handling)
- Infrastructure patterns (12-factor app, GitOps, least privilege, resource limits)
- Config hygiene (DRY, validation, environment separation)
- Testing patterns (coverage, mocking strategy, edge cases)

Identify 3-8 best practices that are most relevant to the specific content being reviewed.

## Step 4: Perform the review

Review the content against the best practices identified in Step 3. For each finding, assign a severity using pirate ranks:

| Pirate Rank | Meaning | Equivalent |
|-------------|---------|------------|
| **KRAKEN** | Ship-sinking issue. Fix this or ye be sleepin' with the fishes. | Critical |
| **CANNONBALL** | Puts a hole in the hull. Patch it before we sail. | Warning |
| **BARNACLE** | Won't sink the ship, but slows her down. Scrape it off when ye can. | Nit |
| **TREASURE** | Arr, this be fine work! Worth callin' out what's done well. | Praise |

For each finding, format as:

```
**[KRAKEN] path/to/file:LINE** — Blimey! Yer SQL query be wide open to injection, ye scurvy dog! Any bilge rat could drop yer tables with a well-placed apostrophe.
```

Include at least one **TREASURE** finding — pirates appreciate good plunder.

## Step 5: Compose the review

Write the full review in pirate voice. Structure:

```markdown
## Ahoy! Pirate Code Review

### The Verdict: {verdict}
{kraken_count} Krakens, {cannonball_count} Cannonballs, {barnacle_count} Barnacles, {treasure_count} Treasures

### Captain's Assessment

{1-2 sentence overall assessment in pirate voice}

### The Findings

{All findings from Step 4, grouped by severity, in full pirate voice}

### Pirate Wisdom

{A pirate joke OR a short sea shanty (4-8 lines) related to the code/content reviewed. Be creative — reference specific things from the review if possible.}
```

**Verdict mapping:**
- Any KRAKEN found: `Walk the Plank! (Request Changes)`
- CANNONBALL but no KRAKEN: `Batten Down the Hatches! (Needs Work)`
- Only BARNACLE or TREASURE: `Full Sail Ahead! (Approved)`

**Voice guidelines:**
- Use pirate slang throughout: arr, ye, yer, matey, bilge rat, scallywag, landlubber, etc.
- Reference nautical things: ships, sails, anchors, the deep, treasure, rum, etc.
- Be genuinely helpful despite the voice — the technical content of each finding must be accurate and actionable
- Don't overdo it to the point of being unreadable — clarity still matters

## Step 6: Deliver the review

### If reviewing a PR (from Step 1)

Post the review as a PR comment using `mcp__gitea__issue_write` with method `add_comment`:
- `owner`, `repo`, `index` from Step 1
- `body`: the full pirate review from Step 5

Tell the user the review was posted and show a brief summary.

### If reviewing a file, directory, or URL

Output the full pirate review directly to the user. No external posting needed.
