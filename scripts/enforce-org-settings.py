#!/usr/bin/env python3
"""Org-wide repository settings enforcer for the super-werewolves Gitea org.

Checks all repos against the desired configuration and auto-fixes what it can.
Creates Gitea issues for anything that requires manual intervention.

Usage:
    python scripts/enforce-org-settings.py [--dry-run] [--repo REPO_NAME] [--no-discord]

Environment:
    GITEA_TOKEN  Required. Gitea personal access token with repo + admin scope.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass, field

import httpx

GITEA_URL = "http://git.home.superwerewolves.ninja"
ORG = "super-werewolves"
TEMPLATE_REPO = "repo-template"
COLLABORATOR_USER = "code-review-agent"
COLLABORATOR_PERMISSION = "read"

# Desired merge / cleanup policy applied to every repo
DESIRED_REPO_SETTINGS: dict[str, object] = {
    "allow_merge_commits": False,
    "allow_rebase": True,
    "allow_rebase_explicit": True,
    "allow_squash_merge": True,
    "default_merge_style": "rebase",
    "default_delete_branch_after_merge": True,
}


@dataclass
class RepoResult:
    name: str
    compliant: bool = True
    fixed: list[str] = field(default_factory=list)
    manual_needed: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


class OrgEnforcer:
    def __init__(self, token: str, dry_run: bool = False) -> None:
        self.dry_run = dry_run
        self.client = httpx.Client(
            base_url=f"{GITEA_URL}/api/v1",
            headers={"Authorization": f"token {token}"},
            timeout=30.0,
        )

    # ------------------------------------------------------------------
    # Repo discovery
    # ------------------------------------------------------------------

    def get_all_org_repos(self) -> list[dict]:
        repos: list[dict] = []
        page = 1
        while True:
            resp = self.client.get(
                f"/orgs/{ORG}/repos", params={"limit": 50, "page": page}
            )
            resp.raise_for_status()
            batch: list[dict] = resp.json()
            if not batch:
                break
            repos.extend(batch)
            if len(batch) < 50:
                break
            page += 1
        return repos

    def get_repo(self, name: str) -> dict:
        resp = self.client.get(f"/repos/{ORG}/{name}")
        resp.raise_for_status()
        return resp.json()

    # ------------------------------------------------------------------
    # Template hook
    # ------------------------------------------------------------------

    def get_template_hook(self) -> str | None:
        try:
            resp = self.client.get(
                f"/repos/{ORG}/{TEMPLATE_REPO}/git/hooks/pre-receive"
            )
            if resp.status_code == 200:
                content = resp.json().get("content", "")
                return content if content else None
        except httpx.HTTPError as exc:
            print(f"  [WARN] Could not fetch template hook: {exc}")
        return None

    # ------------------------------------------------------------------
    # Per-repo enforcement
    # ------------------------------------------------------------------

    def enforce_repo(self, repo: dict, template_hook: str | None) -> RepoResult:
        result = RepoResult(name=repo["name"])
        try:
            self._enforce_merge_policy(repo, result)
            self._enforce_branch_protection(repo, result)
            if template_hook is not None:
                self._enforce_pre_receive_hook(repo, template_hook, result)
            self._enforce_collaborator(repo, result)
        except httpx.HTTPError as exc:
            result.compliant = False
            result.errors.append(f"Unexpected network error during enforcement: {exc}")
        if result.manual_needed:
            self._create_manual_issue(repo, result)
        return result

    def _enforce_merge_policy(self, repo: dict, result: RepoResult) -> None:
        patches: dict[str, object] = {}
        for key, desired in DESIRED_REPO_SETTINGS.items():
            if repo.get(key) != desired:
                patches[key] = desired

        if not patches:
            return

        result.compliant = False
        if self.dry_run:
            for key, val in patches.items():
                result.fixed.append(f"[DRY-RUN] Would set {key}={val}")
            return

        resp = self.client.patch(f"/repos/{ORG}/{repo['name']}", json=patches)
        if resp.status_code in (200, 201):
            for key, val in patches.items():
                result.fixed.append(f"Set {key}={val}")
        else:
            result.errors.append(
                f"Failed to patch merge/cleanup settings: HTTP {resp.status_code} — {resp.text[:200]}"
            )

    def _enforce_branch_protection(self, repo: dict, result: RepoResult) -> None:
        default_branch: str = repo.get("default_branch", "main")

        resp = self.client.get(f"/repos/{ORG}/{repo['name']}/branch_protections")
        if resp.status_code != 200:
            result.errors.append(
                f"Could not fetch branch protections: HTTP {resp.status_code}"
            )
            return

        protections: list[dict] = resp.json()
        existing = next(
            (p for p in protections if p.get("branch_name") == default_branch),
            None,
        )

        if existing is None:
            result.compliant = False
            if self.dry_run:
                result.fixed.append(
                    f"[DRY-RUN] Would create branch protection for {default_branch}"
                )
                return
            create_body = {
                "branch_name": default_branch,
                "enable_push": True,
                "enable_push_whitelist": True,
                "push_whitelist_usernames": [],
                "push_whitelist_teams": [],
                "enable_merge_whitelist": False,
                "require_signed_commits": False,
                "block_on_rejected_reviews": False,
                "dismiss_stale_approvals": False,
                # Don't touch status checks — leave empty so repo-specific CI isn't overwritten
                "enable_status_check": False,
                "status_check_contexts": [],
                "require_approvals": 0,
            }
            r = self.client.post(
                f"/repos/{ORG}/{repo['name']}/branch_protections",
                json=create_body,
            )
            if r.status_code in (200, 201):
                result.fixed.append(
                    f"Created branch protection for {default_branch} (no direct pushes)"
                )
            else:
                result.errors.append(
                    f"Failed to create branch protection: HTTP {r.status_code} — {r.text[:200]}"
                )
            return

        # Protection exists — check force push and push restrictions
        patches: dict[str, object] = {}
        if existing.get("enable_force_push", False):
            patches["enable_force_push"] = False
        if not existing.get("enable_push", False):
            # enable_push: false means direct pushes are unrestricted; lock it down
            patches["enable_push"] = True
            patches["enable_push_whitelist"] = True
            patches["push_whitelist_usernames"] = []
            patches["push_whitelist_teams"] = []

        if not patches:
            return

        result.compliant = False
        if self.dry_run:
            if "enable_force_push" in patches:
                result.fixed.append(
                    f"[DRY-RUN] Would disable force push on {default_branch}"
                )
            if "enable_push" in patches:
                result.fixed.append(
                    f"[DRY-RUN] Would enable push restriction on {default_branch} (no direct pushes)"
                )
            return
        protection_id = existing.get("id")
        if not protection_id:
            result.errors.append("Branch protection record has no id — cannot patch")
            return
        r = self.client.patch(
            f"/repos/{ORG}/{repo['name']}/branch_protections/{protection_id}",
            json=patches,
        )
        if r.status_code in (200, 201):
            if "enable_force_push" in patches:
                result.fixed.append(f"Disabled force push on {default_branch}")
            if "enable_push" in patches:
                result.fixed.append(
                    f"Enabled push restriction on {default_branch} (no direct pushes)"
                )
        else:
            result.errors.append(
                f"Failed to patch branch protection: HTTP {r.status_code} — {r.text[:200]}"
            )

    def _enforce_pre_receive_hook(
        self, repo: dict, template_hook: str, result: RepoResult
    ) -> None:
        try:
            resp = self.client.get(f"/repos/{ORG}/{repo['name']}/git/hooks/pre-receive")
            current_hook = ""
            if resp.status_code == 200:
                current_hook = resp.json().get("content", "")

            if current_hook.strip() == template_hook.strip():
                return

            result.compliant = False
            if self.dry_run:
                result.fixed.append(
                    "[DRY-RUN] Would sync pre-receive hook from repo-template"
                )
                return

            r = self.client.patch(
                f"/repos/{ORG}/{repo['name']}/git/hooks/pre-receive",
                json={"content": template_hook},
            )
            if r.status_code in (200, 201):
                result.fixed.append("Synced pre-receive hook from repo-template")
            else:
                result.errors.append(
                    f"Hook update failed: HTTP {r.status_code} — {r.text[:200]}"
                )
                result.manual_needed.append(
                    f"Pre-receive hook is out of date. Automatic update failed "
                    f"(HTTP {r.status_code}) — the token may lack git-hook admin permission. "
                    "Manually copy the hook content from `super-werewolves/repo-template` "
                    "via **Settings → Git Hooks → pre-receive**."
                )
        except httpx.HTTPError as exc:
            result.errors.append(f"Hook check error: {exc}")

    def _enforce_collaborator(self, repo: dict, result: RepoResult) -> None:
        resp = self.client.get(
            f"/repos/{ORG}/{repo['name']}/collaborators/{COLLABORATOR_USER}"
        )
        if resp.status_code == 204:
            # Already a collaborator — check permission level
            perm_resp = self.client.get(
                f"/repos/{ORG}/{repo['name']}/collaborators/{COLLABORATOR_USER}/permission"
            )
            if perm_resp.status_code == 200:
                perm = perm_resp.json().get("permission", "")
                if perm == COLLABORATOR_PERMISSION:
                    return
                # Permission is higher than required — downgrade to read
                result.compliant = False
                if self.dry_run:
                    result.fixed.append(
                        f"[DRY-RUN] Would downgrade {COLLABORATOR_USER} from {perm} to {COLLABORATOR_PERMISSION}"
                    )
                    return
                r = self.client.put(
                    f"/repos/{ORG}/{repo['name']}/collaborators/{COLLABORATOR_USER}",
                    json={"permission": COLLABORATOR_PERMISSION},
                )
                if r.status_code in (200, 201, 204):
                    result.fixed.append(
                        f"Downgraded {COLLABORATOR_USER} from {perm} to {COLLABORATOR_PERMISSION}"
                    )
                else:
                    result.errors.append(
                        f"Failed to downgrade {COLLABORATOR_USER}: "
                        f"HTTP {r.status_code} — {r.text[:200]}"
                    )
                return
            else:
                # Can't determine — leave as-is
                return
        elif resp.status_code != 404:
            result.compliant = False
            result.errors.append(
                f"Could not check collaborator status: HTTP {resp.status_code}"
            )
            return

        # User is not a collaborator (404) — add them
        result.compliant = False
        if self.dry_run:
            result.fixed.append(
                f"[DRY-RUN] Would add {COLLABORATOR_USER} as collaborator "
                f"with {COLLABORATOR_PERMISSION} permission"
            )
            return

        r = self.client.put(
            f"/repos/{ORG}/{repo['name']}/collaborators/{COLLABORATOR_USER}",
            json={"permission": COLLABORATOR_PERMISSION},
        )
        if r.status_code in (200, 201, 204):
            result.fixed.append(
                f"Added {COLLABORATOR_USER} as collaborator "
                f"with {COLLABORATOR_PERMISSION} permission"
            )
        else:
            result.errors.append(
                f"Failed to add {COLLABORATOR_USER} as collaborator: "
                f"HTTP {r.status_code} — {r.text[:200]}"
            )

    # ------------------------------------------------------------------
    # Issue creation for manual items
    # ------------------------------------------------------------------

    def _create_manual_issue(self, repo: dict, result: RepoResult) -> None:
        if self.dry_run:
            print(f"  [DRY-RUN] Would create issue for manual items in {repo['name']}")
            return

        title = "[repo-enforcer] Manual attention required for repo settings"

        # Deduplication: skip if an open issue with this title already exists
        search_resp = self.client.get(
            f"/repos/{ORG}/{repo['name']}/issues",
            params={
                "type": "issues",
                "state": "open",
                "q": "[repo-enforcer]",
                "limit": 50,
            },
        )
        if search_resp.status_code == 200:
            existing_issues = search_resp.json()
            if any(i.get("title") == title for i in existing_issues):
                print(
                    f"  [SKIP] Open issue already exists for manual items in {repo['name']}"
                )
                return

        items = "\n".join(f"- {item}" for item in result.manual_needed)
        body = (
            "The org-settings enforcer detected items that require manual attention:\n\n"
            f"{items}\n\n"
            "_Created automatically by the [org-settings enforcer]"
            f"(https://git.home.superwerewolves.ninja/{ORG}/development-skills/src/branch/main/scripts/enforce-org-settings.py)._"
        )
        resp = self.client.post(
            f"/repos/{ORG}/{repo['name']}/issues",
            json={"title": title, "body": body},
        )
        if resp.status_code in (200, 201):
            issue = resp.json()
            print(f"  [ISSUE #{issue['number']}] Created: {title}")
        else:
            print(
                f"  [ERROR] Failed to create issue: HTTP {resp.status_code} — {resp.text[:200]}"
            )


# ------------------------------------------------------------------
# Discord summary
# ------------------------------------------------------------------


def post_discord_summary(results: list[RepoResult], dry_run: bool) -> None:
    # Prefer env var (works in Gitea Actions); fall back to local config file
    webhook_url = os.environ.get("DISCORD_WEBHOOK_URL", "")
    if not webhook_url:
        webhook_file = os.path.expanduser(
            "~/.config/development-skills/discord-webhook"
        )
        try:
            with open(webhook_file) as fh:
                webhook_url = fh.read().strip()
        except FileNotFoundError:
            return
    if not webhook_url:
        return

    compliant = [r for r in results if r.compliant and not r.fixed]
    fixed = [r for r in results if r.fixed]
    manual = [r for r in results if r.manual_needed]
    errored = [r for r in results if r.errors]

    lines = [
        f"**Compliant (no changes):** {len(compliant)}",
        f"**Auto-fixed:** {len(fixed)}",
        f"**Needs manual attention:** {len(manual)}",
        f"**Errors:** {len(errored)}",
    ]
    if fixed:
        lines.append("\n**Fixed repos:**")
        for r in fixed[:5]:
            sample = ", ".join(r.fixed[:2])
            lines.append(f"  • `{r.name}`: {sample}")
        if len(fixed) > 5:
            lines.append(f"  … and {len(fixed) - 5} more")
    if manual:
        lines.append("\n**Manual attention needed:**")
        for r in manual[:3]:
            lines.append(f"  • `{r.name}`")
        if len(manual) > 3:
            lines.append(f"  … and {len(manual) - 3} more")

    description = "\n".join(lines)
    color = 3066993 if not manual and not errored else 15158332  # green or red
    title = "Org Settings Enforcer"
    if dry_run:
        title += " — Dry Run"

    payload = json.dumps(
        {
            "embeds": [
                {
                    "title": title,
                    "description": description,
                    "color": color,
                }
            ]
        }
    )
    try:
        httpx.post(
            webhook_url,
            content=payload,
            headers={"Content-Type": "application/json"},
        )
    except httpx.HTTPError as exc:
        print(f"[WARN] Discord post failed: {exc}")  # best-effort, don't fail the run


# ------------------------------------------------------------------
# Entry point
# ------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Enforce org-wide repo settings for super-werewolves."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would change without making any changes.",
    )
    parser.add_argument(
        "--repo",
        metavar="NAME",
        help="Only enforce on a single repo by name (not owner/repo).",
    )
    parser.add_argument(
        "--no-discord",
        action="store_true",
        help="Skip posting a summary to Discord.",
    )
    args = parser.parse_args()

    if args.repo and "/" in args.repo:
        parser.error(
            f"--repo takes a bare repo name, not 'owner/repo' (got: {args.repo!r})"
        )

    token = os.environ.get("GITEA_TOKEN", "")
    if not token:
        print("ERROR: GITEA_TOKEN environment variable is not set.", file=sys.stderr)
        sys.exit(1)

    if args.dry_run:
        print("=== DRY RUN — no changes will be made ===\n")

    enforcer = OrgEnforcer(token=token, dry_run=args.dry_run)
    try:
        # Fetch template hook once
        print(f"Fetching pre-receive hook from {ORG}/{TEMPLATE_REPO}…")
        template_hook = enforcer.get_template_hook()
        if template_hook is None:
            print(
                "  [WARN] Template hook unavailable — hook sync will be skipped for all repos."
            )

        # Resolve repo list
        if args.repo:
            repos = [enforcer.get_repo(args.repo)]
        else:
            print(f"Fetching all repos in the {ORG} org…")
            repos = enforcer.get_all_org_repos()

        print(f"Found {len(repos)} repo(s) to check.\n")

        results: list[RepoResult] = []
        for repo in repos:
            name = repo["name"]
            print(f"Checking {name}…")
            result = enforcer.enforce_repo(repo, template_hook)
            results.append(result)

            if result.compliant and not result.fixed:
                print("  [OK] Compliant — no changes needed.")
            for msg in result.fixed:
                print(f"  [FIXED] {msg}")
            for msg in result.manual_needed:
                print(f"  [MANUAL] {msg}")
            for msg in result.errors:
                print(f"  [ERROR] {msg}")
    finally:
        enforcer.client.close()

    # Print summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    compliant_repos = [r for r in results if r.compliant and not r.fixed]
    fixed_repos = [r for r in results if r.fixed]
    manual_repos = [r for r in results if r.manual_needed]
    error_repos = [r for r in results if r.errors]
    print(f"  Compliant (no changes):  {len(compliant_repos)}")
    print(f"  Auto-fixed:              {len(fixed_repos)}")
    print(f"  Needs manual attention:  {len(manual_repos)}")
    print(f"  Errors:                  {len(error_repos)}")

    if not args.no_discord and not args.dry_run:
        post_discord_summary(results, dry_run=False)
    elif args.dry_run and not args.no_discord:
        post_discord_summary(results, dry_run=True)

    if manual_repos or error_repos:
        sys.exit(1)


if __name__ == "__main__":
    main()
