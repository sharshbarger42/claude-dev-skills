# Hallucination Check

Verify a plan's concrete claims against reality and flag vague or unexecutable sections. Catches AI-generated hallucinations (non-existent libraries, wrong APIs, fabricated file paths) and human hand-waving (vague steps, missing details, unstated assumptions).

**Input:** Path to a plan markdown file, or a plan directory slug.

**Accepted formats:**
- Absolute path: `/home/claude-user/plans/2026-03-28-gpu-workstation/plan.md`
- Plan slug: `gpu-workstation` (resolves to `~/plans/*-gpu-workstation/plan.md`)
- Relative path: `plan.md` (uses current directory)
- Gitea issue URL or reference: `homelab-setup#776` (reads the issue body as the plan)

If no argument is provided, look for `plan.md` in the current directory.

## Step 1: Load the plan

### From file path or slug

1. Resolve the path:
   - If argument is an absolute path, use it directly
   - If argument looks like a slug (no `/` or `.`), search `~/plans/*-{slug}/plan.md`
   - If argument is a relative path, resolve from `pwd`
2. Read the plan file
3. If an `analysis.md` exists in the same directory, read it too — it provides additional context

### From Gitea issue

1. Parse using repo resolution logic:

# Repo Resolution Logic

Use this shared logic to parse issue/PR/repo references in dev-workflow skills.

## Load the shorthand table

!`cat $HOME/.claude/development-skills/config/repos.md`

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

2. Fetch the issue body via `mcp__gitea__issue_read`
3. Also fetch comments — they may contain additional plan details or sub-issue breakdowns
4. If the issue references sub-issues, fetch those too for the full picture

### Identify the target repo

If the plan references a specific repo (e.g., in a "Target Repo" field or file paths like `src/...`), resolve it to a local path. This repo will be used for code verification in Step 3.

If no repo is identifiable, ask the user which repo the plan targets (or if it's repo-independent).

## Step 1b: Ensure repos are on latest main

Before verifying any code claims, pull the latest from the default branch for every repo that will be checked:

```bash
cd {repo_local_path}
git fetch origin
git checkout {default_branch}
git pull origin {default_branch}
```

If the repo has uncommitted changes (dirty tree), stash them first:

```bash
git stash
git pull origin {default_branch}
# Do NOT pop the stash — leave the tree clean for verification
```

**This is critical.** Verifying against stale code defeats the purpose of the skill. Always confirm the HEAD SHA matches `origin/{default_branch}` before proceeding.

If the repo isn't cloned locally, clone it:

```bash
git clone {ssh_url} {repo_local_path}
```

## Step 2: Extract verifiable claims

Parse the plan and extract every concrete, testable claim into a checklist. Claims fall into these categories:

### 2a. Code & file references
- File paths mentioned (`src/api/routes.ts`, `k8s/deployment.yaml`)
- Function/class/method names (`handleWebhook()`, `class RecipeParser`)
- Import statements or module references
- Configuration file formats or fields

### 2b. Libraries & dependencies
- Package names (`@anthropic-ai/sdk`, `fastapi`, `helm chart bitnami/postgresql`)
- Version numbers or constraints (`>=3.0`, `v0.99.0`)
- Specific APIs or functions from libraries (`ollama.chat()`, `vLLM.generate()`)
- CLI tools assumed to be available (`kubectl`, `helm`, `terraform`)

### 2c. Infrastructure & network
- IP addresses, hostnames, DNS entries
- Port numbers and service endpoints
- Container/VM IDs, node assignments
- Network paths (service A connects to service B on port X)

### 2d. API & data claims
- Endpoint paths and methods (`POST /api/v1/recipes`)
- Request/response schemas or field names
- Database table/collection names and fields
- Authentication mechanisms described

### 2e. Architecture claims
- "X communicates with Y via Z" statements
- Data flow descriptions
- Deployment topology claims
- Technology stack assertions (e.g., "uses Redis for caching")

### 2f. External service claims
- Third-party API availability and behavior
- SaaS integrations and their capabilities
- Hardware specifications and compatibility claims

For each claim, record:
- **Location** — section and line in the plan where the claim appears
- **Claim text** — the exact assertion
- **Category** — from the list above
- **Verification method** — how to check it (see Step 3)

## Step 3: Verify claims (Pass 1 — Fact-checking)

For each extracted claim, attempt verification using the most reliable method available. Work through claims by category:

### 3a. Code & file verification

If a target repo is available locally:

```bash
# Check if file exists
test -f "{repo_path}/{claimed_file}" && echo "EXISTS" || echo "MISSING"

# Check if function/class exists
grep -rn "function {name}\|class {name}\|def {name}\|func {name}" "{repo_path}/" 2>/dev/null
```

If the repo is only on Gitea (not cloned locally), use `mcp__gitea__get_file_contents` and `mcp__gitea__get_dir_contents` to check.

**Verdict:**
- `[verified]` — file/function exists as described
- `[false]` — file/function does not exist, or exists but differs significantly from description
- `[unverifiable]` — repo not available or code hasn't been written yet (plan describes future state)

### 3b. Library & dependency verification

For each library claim:

1. **Check if the package exists** — use `WebSearch` to confirm the package exists on the relevant registry (npm, PyPI, crates.io, Go modules, Helm Hub)
2. **Check version claims** — verify the claimed version exists
3. **Check API claims** — if the plan says "use `library.specificFunction()`", search the library's docs or source to confirm that function exists
4. **Check CLI tools** — `command -v {tool}` on the local machine, or verify the tool exists via web search

**Verdict:**
- `[verified]` — package exists, version is real, API is correct
- `[false]` — package doesn't exist, version is fabricated, or API is wrong (common hallucination)
- `[unverifiable]` — can't confirm without installing/testing

### 3c. Infrastructure verification

Cross-reference claims against the infrastructure reference injected by the productivity-hooks plugin, and against live checks where safe:

1. **DNS entries** — `dig {hostname} @192.168.0.225` to check Pi-hole resolution
2. **Service reachability** — `curl -s -o /dev/null -w "%{http_code}" http://{host}:{port}` (only for HTTP services, only GET, never POST)
3. **IP assignments** — compare against infrastructure.md
4. **Proxmox resources** — compare claimed VM/LXC IDs and node assignments against infrastructure reference

**Safety:** Only perform read-only checks. Never create, modify, or delete any infrastructure resource during verification.

**Verdict:**
- `[verified]` — infrastructure matches the claim
- `[false]` — IP/hostname/port is wrong, service doesn't exist at claimed location
- `[unverifiable]` — can't reach the service or resource to check (might be planned but not deployed)

### 3d. API & data verification

If the plan describes existing APIs:

1. **Check OpenAPI/Swagger specs** — look for `openapi.yaml`, `swagger.json` in the repo
2. **Check route definitions** — grep the codebase for endpoint paths
3. **Check data models** — look for schema definitions, ORM models, migration files

If the plan describes APIs to be built (future state), mark as `[unverifiable]` — these are design claims, not fact claims.

**Verdict:**
- `[verified]` — endpoint/schema exists as described
- `[false]` — endpoint exists but method/path/schema differs, or doesn't exist when it should
- `[unverifiable]` — describes future state (to be built)

### 3e. Architecture & connection verification

For claims about how services connect:

1. **Check config files** — environment variables, connection strings (without printing secrets), helm values
2. **Check docker-compose/k8s manifests** — service names, ports, volume mounts
3. **Check network policies** — if the plan claims "A can reach B", verify there's no network policy blocking it

**Verdict:**
- `[verified]` — connection path exists as described
- `[false]` — services don't connect as claimed (wrong port, missing config, network policy blocks it)
- `[unverifiable]` — connection path can't be confirmed without runtime testing

### 3f. External service verification

For third-party service claims:

1. **Web search** to confirm the service exists and has the described capabilities
2. **Check pricing/availability claims** if made
3. **Verify API compatibility claims** against official docs

**Verdict:**
- `[verified]` — service exists with described capabilities
- `[false]` — service doesn't exist, API has changed, or capability is fabricated
- `[unverifiable]` — can't confirm without account/access

## Step 4: Detect vagueness (Pass 2 — Executability check)

Read through the plan again looking for sections that would block an implementer. Flag anything where a developer (human or AI) would need to stop and ask questions.

### 4a. Missing "how" — vague implementation steps

Flag sections that say *what* to do but not *how*:
- "Configure the service" — configure what settings? What values?
- "Set up authentication" — which auth method? What credentials flow?
- "Integrate with X" — via API? SDK? Webhook? What endpoint?
- "Deploy to production" — how? Manual? CI/CD? Which pipeline?

### 4b. Gaps in the plan — missing steps between A and C

Look for logical jumps where intermediate steps are omitted:
- Data needs to get from A to B, but no step describes the transfer mechanism
- A service is referenced but never created or deployed
- A config value is used but never defined or explained where it comes from

### 4c. Assumptions stated as facts

Flag implicit assumptions that aren't validated:
- "The database already has table X" — is that verified?
- "Users will have access to Y" — how is access provisioned?
- "The network allows traffic on port Z" — is there a firewall rule?

### 4d. Ambiguous technology choices

Flag decisions that are deferred or unclear:
- "Use Redis or Memcached for caching" — which one? Different setup for each
- "Either approach would work" — but which is the plan?
- "TBD" or "to be decided" sections

### 4e. Missing error handling & edge cases

Flag steps that describe the happy path but not failure modes:
- What happens if the external API is down?
- What if the migration fails halfway?
- What if the disk fills up?

For each vagueness finding, record:
- **Location** — section in the plan
- **Issue** — what's vague or missing
- **Impact** — how this blocks execution (can't proceed, might choose wrong approach, etc.)
- **Suggestion** — what specific information needs to be added

## Step 5: Generate report

Present findings in a structured report, ordered by severity:

```markdown
## Hallucination Check Report

**Plan:** {plan file path or issue reference}
**Checked:** {timestamp}
**Claims found:** {total count}

### Summary

| Category | Verified | False | Unverifiable | Vague |
|----------|----------|-------|--------------|-------|
| Code & files | X | X | X | — |
| Libraries | X | X | X | — |
| Infrastructure | X | X | X | — |
| APIs & data | X | X | X | — |
| Architecture | X | X | X | — |
| External services | X | X | X | — |
| Executability | — | — | — | X |
| **Total** | **X** | **X** | **X** | **X** |

### False Claims (fix these)

These are factually wrong — the plan states something that contradicts reality.

1. **[false] {category}** — _{location in plan}_
   **Claim:** {what the plan says}
   **Reality:** {what's actually true}
   **Fix:** {specific correction to make}

2. ...

### Vague Sections (clarify these)

These would block an implementer — not enough detail to execute.

1. **[vague]** — _{location in plan}_
   **Issue:** {what's unclear}
   **Impact:** {why this blocks execution}
   **Needed:** {what specific information to add}

2. ...

### Unverifiable Claims (acknowledge these)

Can't confirm right now — either describes future state or requires access we don't have.

1. **[unverifiable] {category}** — _{location in plan}_
   **Claim:** {what the plan says}
   **Why unverifiable:** {what would be needed to verify}

2. ...

### Verified Claims ({count})

<details>
<summary>Expand to see all verified claims</summary>

1. **[verified] {category}** — {claim} — {evidence}
2. ...

</details>

### Confidence Score

**{X}%** of verifiable claims checked out. {Y} false claims need fixing, {Z} sections are too vague to execute.

{One-paragraph overall assessment: is this plan ready to execute, or does it need another pass?}
```

## Step 6: Save report (optional)

If the plan came from a plan directory (`~/plans/{slug}/`), save the report as `hallucination-check.md` in the same directory.

If the plan came from a Gitea issue, offer to post the report as a comment on the issue.

## Rules

- **Read-only verification** — never create, modify, or delete anything during checks. Only read files, query APIs with GET, check DNS, search the web.
- **No secrets in output** — if you find connection strings or credentials in config files during verification, confirm they exist but never print the values.
- **Be precise about what you checked** — always state your evidence. "Verified" means you actually confirmed it, not that it sounds right.
- **Don't guess** — if you can't verify something, mark it `[unverifiable]` rather than guessing. The whole point of this skill is to separate known-true from assumed-true.
- **Focus on actionable findings** — the user wants to know what to fix. Prioritize `[false]` and `[vague]` findings. Don't bury them under pages of `[verified]` claims.
- **Web search for libraries** — AI models frequently hallucinate package names and APIs. Always verify library claims externally, don't rely on training data.
