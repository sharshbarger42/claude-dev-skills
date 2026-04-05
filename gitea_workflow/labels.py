"""Label definitions and state machine for PR and issue workflow labels."""

from __future__ import annotations

# PR status labels — tracks pull request workflow state
PR_LABELS = {
    "needs-review": "pr: needs-review",
    "comments-pending": "pr: comments-pending",
    "awaiting-dev-verification": "pr: awaiting-dev-verification",
    "ready-to-merge": "pr: ready-to-merge",
    "awaiting-prod-verification": "pr: awaiting-prod-verification",
}

PR_LABEL_PREFIX = "pr: "

# Issue status labels — tracks issue lifecycle
STATUS_LABELS = {
    "backlog": "status: backlog",
    "in-progress": "status: in-progress",
    "ready-to-test": "status: ready-to-test",
    "in-review": "status: in-review",
    "done": "status: done",
}

STATUS_LABEL_PREFIX = "status: "

# Issue type labels
TYPE_LABELS = {"bug", "enhancement", "feature"}

# Issue priority labels
PRIORITY_LABELS = {"priority: high", "priority: medium", "priority: low"}

# Review verdicts
VERDICT_APPROVE = "APPROVE"
VERDICT_COMMENT = "COMMENT"
VERDICT_REQUEST_CHANGES = "REQUEST_CHANGES"


def pr_label_for_verdict(verdict: str, *, has_dev_deploy: bool) -> str:
    """Determine the correct PR label after a review verdict.

    Args:
        verdict: One of APPROVE, COMMENT, REQUEST_CHANGES
        has_dev_deploy: Whether the repo has a dev deploy environment

    Returns:
        The full PR label name to apply.
    """
    if verdict == VERDICT_REQUEST_CHANGES:
        return PR_LABELS["comments-pending"]
    if verdict == VERDICT_COMMENT:
        # Warnings but no criticals — still needs attention
        return PR_LABELS["comments-pending"]
    # APPROVE — clean review
    if has_dev_deploy:
        return PR_LABELS["awaiting-dev-verification"]
    return PR_LABELS["ready-to-merge"]


def pr_label_after_fix(*, has_dev_deploy: bool) -> str:
    """Determine PR label after comments are addressed."""
    if has_dev_deploy:
        return PR_LABELS["awaiting-dev-verification"]
    return PR_LABELS["ready-to-merge"]


def pr_label_after_merge(*, has_prod_deploy: bool) -> str | None:
    """Determine PR label after merge. Returns None if no label needed."""
    if has_prod_deploy:
        return PR_LABELS["awaiting-prod-verification"]
    return None
