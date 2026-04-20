"""Gitea REST API client with label ID caching."""

from __future__ import annotations

import httpx

from .labels import PR_LABEL_PREFIX, STATUS_LABEL_PREFIX


class GiteaClient:
    """Thin wrapper around the Gitea REST API for label and PR operations."""

    def __init__(self, base_url: str, token: str, reviewer_token: str | None = None):
        self.base_url = base_url.rstrip("/")
        self.api_url = f"{self.base_url}/api/v1"
        self._token = token
        self._reviewer_token = reviewer_token
        self._label_cache: dict[str, dict[str, int]] = {}  # "owner/repo" -> {name: id}
        self._client = httpx.Client(
            headers={"Authorization": f"token {token}"},
            timeout=15.0,
        )
        # Reviewer client uses service account token if available, else main token
        self._reviewer_client = httpx.Client(
            headers={"Authorization": f"token {reviewer_token or token}"},
            timeout=15.0,
        )

    def _cache_key(self, owner: str, repo: str) -> str:
        return f"{owner}/{repo}"

    def _ensure_label_cache(self, owner: str, repo: str) -> dict[str, int]:
        """Populate label cache for a repo if not already cached."""
        key = self._cache_key(owner, repo)
        if key not in self._label_cache:
            labels = self._list_repo_labels(owner, repo)
            self._label_cache[key] = {lbl["name"]: lbl["id"] for lbl in labels}
        return self._label_cache[key]

    def _list_repo_labels(self, owner: str, repo: str) -> list[dict]:
        """Fetch all labels for a repo."""
        url = f"{self.api_url}/repos/{owner}/{repo}/labels"
        resp = self._client.get(url, params={"limit": 200})
        resp.raise_for_status()
        return resp.json()

    def get_label_id(self, owner: str, repo: str, label_name: str) -> int | None:
        """Get the ID of a label by name, or None if it doesn't exist."""
        cache = self._ensure_label_cache(owner, repo)
        return cache.get(label_name)

    def get_issue_labels(self, owner: str, repo: str, index: int) -> list[dict]:
        """Get current labels on an issue/PR."""
        url = f"{self.api_url}/repos/{owner}/{repo}/issues/{index}/labels"
        resp = self._client.get(url)
        resp.raise_for_status()
        return resp.json()

    def add_label(self, owner: str, repo: str, index: int, label_id: int) -> None:
        """Add a label to an issue/PR."""
        url = f"{self.api_url}/repos/{owner}/{repo}/issues/{index}/labels"
        resp = self._client.post(url, json={"labels": [label_id]})
        resp.raise_for_status()

    def remove_label(self, owner: str, repo: str, index: int, label_id: int) -> None:
        """Remove a label from an issue/PR."""
        url = f"{self.api_url}/repos/{owner}/{repo}/issues/{index}/labels/{label_id}"
        resp = self._client.delete(url)
        # 404 is fine — label wasn't there
        if resp.status_code != 404:
            resp.raise_for_status()

    def swap_label(
        self,
        owner: str,
        repo: str,
        index: int,
        prefix: str,
        new_label_name: str,
    ) -> str:
        """Remove all labels with the given prefix, then add the new one.

        Returns a status message.
        """
        new_label_id = self.get_label_id(owner, repo, new_label_name)
        if new_label_id is None:
            return f"Label '{new_label_name}' not found in {owner}/{repo} — skipped"

        # Get current labels on the issue
        current_labels = self.get_issue_labels(owner, repo, index)

        # Remove any labels with the matching prefix
        for label in current_labels:
            if label["name"].startswith(prefix):
                self.remove_label(owner, repo, index, label["id"])

        # Add the new label
        self.add_label(owner, repo, index, new_label_id)
        return f"Set '{new_label_name}' on {owner}/{repo}#{index}"

    def add_labels_by_name(
        self,
        owner: str,
        repo: str,
        index: int,
        label_names: list[str],
    ) -> str:
        """Add multiple labels by name. Skips any that don't exist."""
        added = []
        skipped = []
        for name in label_names:
            label_id = self.get_label_id(owner, repo, name)
            if label_id is None:
                skipped.append(name)
                continue
            self.add_label(owner, repo, index, label_id)
            added.append(name)

        parts = []
        if added:
            parts.append(f"Added: {', '.join(added)}")
        if skipped:
            parts.append(f"Skipped (not found): {', '.join(skipped)}")
        return "; ".join(parts) or "No labels to add"

    def swap_pr_label(
        self, owner: str, repo: str, index: int, new_label_name: str
    ) -> str:
        """Swap PR status label."""
        return self.swap_label(owner, repo, index, PR_LABEL_PREFIX, new_label_name)

    def swap_status_label(
        self, owner: str, repo: str, index: int, new_label_name: str
    ) -> str:
        """Swap issue status label."""
        return self.swap_label(owner, repo, index, STATUS_LABEL_PREFIX, new_label_name)

    def post_review(
        self,
        owner: str,
        repo: str,
        index: int,
        body: str,
        state: str = "COMMENT",
        comments: list[dict] | None = None,
        commit_id: str | None = None,
    ) -> dict:
        """Post a PR review using the reviewer service account.

        Args:
            owner: Repo owner
            repo: Repo name
            index: PR index
            body: Review body text
            state: Review state (COMMENT, APPROVED, REQUEST_CHANGES)
            comments: Inline comments [{path, body, new_position}, ...]
            commit_id: Commit SHA to review

        Returns:
            The API response dict.
        """
        url = f"{self.api_url}/repos/{owner}/{repo}/pulls/{index}/reviews"

        payload: dict = {
            "body": body,
            "event": state,
        }
        if comments:
            # REST API uses new_position, not new_line_num
            payload["comments"] = [
                {
                    "path": c.get("path", ""),
                    "body": c.get("body", ""),
                    "new_position": c.get("new_position", c.get("new_line_num", 0)),
                }
                for c in comments
            ]
        if commit_id:
            payload["commit_id"] = commit_id

        resp = self._reviewer_client.post(url, json=payload)
        resp.raise_for_status()
        return resp.json()

    def merge_pr(
        self,
        owner: str,
        repo: str,
        index: int,
        merge_style: str = "merge",
        delete_branch: bool = True,
    ) -> dict:
        """Merge a PR.

        Args:
            owner: Repo owner
            repo: Repo name
            index: PR index
            merge_style: One of merge, rebase, squash, fast-forward-only
            delete_branch: Whether to delete the head branch after merge

        Returns:
            The API response dict.
        """
        url = f"{self.api_url}/repos/{owner}/{repo}/pulls/{index}/merge"
        payload = {
            "Do": merge_style,
            "delete_branch_after_merge": delete_branch,
        }
        resp = self._client.post(url, json=payload)
        resp.raise_for_status()
        # Gitea returns empty body on successful merge
        if resp.status_code == 200 and resp.content:
            return resp.json()
        return {"status": "merged"}

    def list_milestone_issues(
        self,
        owner: str,
        repo: str,
        milestone: int,
        state: str = "open",
        page: int = 1,
        per_page: int = 30,
    ) -> list[dict]:
        """List issues belonging to a specific milestone.

        Wraps `GET /repos/{owner}/{repo}/issues` with the `milestones`
        filter and `type=issues` (excludes PRs).

        Returns an empty list if the milestone has no matching issues
        or does not exist.
        """
        url = f"{self.api_url}/repos/{owner}/{repo}/issues"
        params = {
            "milestones": str(milestone),
            "state": state,
            "type": "issues",
            "page": page,
            "limit": per_page,
        }
        resp = self._client.get(url, params=params)
        # A non-existent milestone ID can surface as 404 depending on server
        # version. Normalise to an empty list so the documented contract holds.
        if resp.status_code == 404:
            return []
        resp.raise_for_status()
        return resp.json()

    def dismiss_review(
        self,
        owner: str,
        repo: str,
        index: int,
        review_id: int,
        message: str = "",
    ) -> dict:
        """Dismiss a PR review."""
        url = f"{self.api_url}/repos/{owner}/{repo}/pulls/{index}/reviews/{review_id}/dismissals"
        payload = {"message": message}
        resp = self._client.post(url, json=payload)
        resp.raise_for_status()
        return resp.json()
