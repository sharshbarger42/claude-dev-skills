"""Gitea Workflow MCP server — high-level workflow tools with label management."""

from __future__ import annotations

import os
import sys
from pathlib import Path

from mcp.server.fastmcp import FastMCP

from .deploy_config import parse_deploy_config
from .gitea_client import GiteaClient
from .labels import (
    PR_LABELS,
    PRIORITY_LABELS,
    STATUS_LABELS,
    TYPE_LABELS,
    pr_label_after_fix,
    pr_label_after_merge,
    pr_label_for_verdict,
)

mcp = FastMCP("gitea-workflow")

# --- Initialization ---


def _get_env(name: str, default: str | None = None) -> str:
    val = os.environ.get(name, default)
    if val is None:
        print(f"Error: {name} environment variable is required", file=sys.stderr)
        sys.exit(1)
    return val


def _init_client() -> GiteaClient:
    base_url = _get_env("GITEA_URL")
    token = _get_env("GITEA_TOKEN")

    # Optional reviewer token for posting reviews as a service account
    reviewer_token = None
    reviewer_token_path = os.path.expanduser("~/.config/code-review-agent/token")
    if os.path.exists(reviewer_token_path):
        reviewer_token = Path(reviewer_token_path).read_text().strip()

    return GiteaClient(base_url, token, reviewer_token)


_client: GiteaClient | None = None
_deploy_config = parse_deploy_config()


def _get_client() -> GiteaClient:
    global _client
    if _client is None:
        _client = _init_client()
    return _client


# --- PR Label Tools ---


@mcp.tool()
def set_pr_label(owner: str, repo: str, index: int, verdict: str) -> str:
    """Set the appropriate PR status label based on a review verdict.

    Automatically removes any existing pr: label and adds the correct one
    based on the verdict and the repo's deploy configuration.

    Args:
        owner: Repository owner (e.g., "super-werewolves")
        repo: Repository name (e.g., "food-automation")
        index: PR index number
        verdict: Review verdict — one of "APPROVE", "COMMENT", "REQUEST_CHANGES",
                 or a direct label key: "needs-review", "comments-pending",
                 "awaiting-dev-verification", "ready-to-merge", "awaiting-prod-verification"
    """
    client = _get_client()

    valid_verdicts = {"APPROVE", "COMMENT", "REQUEST_CHANGES"}

    # Allow direct label keys as well as verdicts
    if verdict in PR_LABELS:
        target_label = PR_LABELS[verdict]
    elif verdict in valid_verdicts:
        has_dev = _deploy_config.has_dev(repo)
        target_label = pr_label_for_verdict(verdict, has_dev_deploy=has_dev)
    else:
        return (
            f"Invalid verdict '{verdict}'. "
            f"Valid: {', '.join(sorted(valid_verdicts | set(PR_LABELS.keys())))}"
        )

    return client.swap_pr_label(owner, repo, index, target_label)


@mcp.tool()
def set_issue_status(owner: str, repo: str, index: int, status: str) -> str:
    """Set an issue's status label, removing any existing status: label first.

    Args:
        owner: Repository owner
        repo: Repository name
        index: Issue index number
        status: Target status — one of "backlog", "in-progress", "ready-to-test",
                "in-review", "done", "needs-human-review"
    """
    if status not in STATUS_LABELS:
        return f"Invalid status '{status}'. Valid: {', '.join(sorted(STATUS_LABELS))}"

    client = _get_client()
    return client.swap_status_label(owner, repo, index, STATUS_LABELS[status])


@mcp.tool()
def label_issue(
    owner: str,
    repo: str,
    index: int,
    type_label: str | None = None,
    priority: str | None = None,
) -> str:
    """Add type and/or priority labels to an issue in one call.

    Args:
        owner: Repository owner
        repo: Repository name
        index: Issue index number
        type_label: Issue type — one of "bug", "enhancement", "feature",
                    "chore", "polish", "contract", "sub-issue", "design"
        priority: Priority level — one of "high", "medium", "low"
    """
    labels_to_add = []
    errors = []

    if type_label:
        if type_label in TYPE_LABELS:
            labels_to_add.append(type_label)
        else:
            errors.append(
                f"Invalid type '{type_label}'. Valid: {', '.join(sorted(TYPE_LABELS))}"
            )

    if priority:
        full_priority = (
            f"priority: {priority}"
            if not priority.startswith("priority:")
            else priority
        )
        if full_priority in PRIORITY_LABELS:
            labels_to_add.append(full_priority)
        else:
            errors.append(f"Invalid priority '{priority}'. Valid: high, medium, low")

    if errors:
        return "; ".join(errors)

    if not labels_to_add:
        return "No labels specified"

    client = _get_client()
    return client.add_labels_by_name(owner, repo, index, labels_to_add)


@mcp.tool()
def post_review(
    owner: str,
    repo: str,
    index: int,
    body: str,
    verdict: str,
    comments: list[dict] | None = None,
    commit_id: str | None = None,
    state: str = "COMMENT",
) -> str:
    """Post a PR review and set the appropriate PR status label.

    Posts the review as the code-review-agent service account (if configured)
    and automatically sets the PR label based on the verdict.

    Args:
        owner: Repository owner
        repo: Repository name
        index: PR index number
        body: Review body text (markdown)
        verdict: Review verdict — "APPROVE", "COMMENT", or "REQUEST_CHANGES"
        comments: Optional inline comments. Each dict should have:
                  "path" (file path), "body" (comment text),
                  "new_line_num" (line number in new file)
        commit_id: Optional commit SHA to attach the review to
        state: Gitea review state to post — "COMMENT" (default, informational),
               "APPROVED" (marks PR as approved in Gitea), or "REQUEST_CHANGES".
               Most reviews should use COMMENT; use APPROVED only when the review
               is an actual approval (e.g., review-deps low-risk).
    """
    valid_verdicts = {"APPROVE", "COMMENT", "REQUEST_CHANGES"}
    if verdict not in valid_verdicts:
        return (
            f"Invalid verdict '{verdict}'. Valid: {', '.join(sorted(valid_verdicts))}"
        )

    client = _get_client()

    review_result = client.post_review(
        owner,
        repo,
        index,
        body=body,
        state=state,
        comments=comments,
        commit_id=commit_id,
    )

    # Set the PR label based on verdict
    has_dev = _deploy_config.has_dev(repo)
    target_label = pr_label_for_verdict(verdict, has_dev_deploy=has_dev)
    label_result = client.swap_pr_label(owner, repo, index, target_label)

    review_id = review_result.get("id", "unknown")
    return f"Review posted (id: {review_id}). {label_result}"


@mcp.tool()
def merge_pr(
    owner: str,
    repo: str,
    index: int,
    merge_style: str = "merge",
    delete_branch: bool = True,
) -> str:
    """Merge a PR and set the appropriate post-merge label.

    Args:
        owner: Repository owner
        repo: Repository name
        index: PR index number
        merge_style: One of "merge", "rebase", "squash", "fast-forward-only"
        delete_branch: Whether to delete the head branch after merge (default: true)
    """
    client = _get_client()

    client.merge_pr(owner, repo, index, merge_style, delete_branch)

    # Set post-merge label — best-effort, merge already succeeded
    try:
        has_prod = _deploy_config.has_prod(repo)
        post_merge_label = pr_label_after_merge(has_prod_deploy=has_prod)

        if post_merge_label:
            label_result = client.swap_pr_label(owner, repo, index, post_merge_label)
        else:
            # No prod deploy — remove all PR labels
            current_labels = client.get_issue_labels(owner, repo, index)
            for label in current_labels:
                if label["name"].startswith("pr: "):
                    client.remove_label(owner, repo, index, label["id"])
            label_result = "No prod deploy — removed PR labels"
    except Exception as exc:
        label_result = f"Label update failed (merge succeeded): {exc}"

    return f"PR #{index} merged ({merge_style}). {label_result}"


@mcp.tool()
def dismiss_review(
    owner: str,
    repo: str,
    index: int,
    review_id: int,
    message: str = "",
) -> str:
    """Dismiss a PR review and advance the PR label.

    Dismisses the review and sets the next label based on deploy config
    (from comments-pending to ready-to-merge or awaiting-dev-verification).

    Args:
        owner: Repository owner
        repo: Repository name
        index: PR index number
        review_id: The review ID to dismiss
        message: Reason for dismissal
    """
    client = _get_client()

    client.dismiss_review(owner, repo, index, review_id, message)

    has_dev = _deploy_config.has_dev(repo)
    target_label = pr_label_after_fix(has_dev_deploy=has_dev)
    label_result = client.swap_pr_label(owner, repo, index, target_label)

    return f"Review {review_id} dismissed. {label_result}"


def main():
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
