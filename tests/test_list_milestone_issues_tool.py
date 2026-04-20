"""Tests for the list_milestone_issues MCP tool's input validation."""

from __future__ import annotations

import pytest

from gitea_workflow import server


@pytest.mark.parametrize("state", ["", "pending", "OPEN", "all ", "everything"])
def test_invalid_state_raises(state):
    with pytest.raises(ValueError, match="Invalid state"):
        server.list_milestone_issues("o", "r", milestone=1, state=state)


@pytest.mark.parametrize("page", [0, -1, -10])
def test_invalid_page_raises(page):
    with pytest.raises(ValueError, match="page must be >= 1"):
        server.list_milestone_issues("o", "r", milestone=1, page=page)


@pytest.mark.parametrize("per_page", [0, -1, 51, 100])
def test_invalid_per_page_raises(per_page):
    with pytest.raises(ValueError, match="per_page must be between 1 and 50"):
        server.list_milestone_issues("o", "r", milestone=1, per_page=per_page)


def test_valid_inputs_do_not_raise_validation_error(monkeypatch):
    """Valid inputs pass validation and call the client (which we stub)."""
    calls = {}

    class FakeClient:
        def list_milestone_issues(self, *args, **kwargs):
            calls["args"] = args
            calls["kwargs"] = kwargs
            return []

    monkeypatch.setattr(server, "_get_client", lambda: FakeClient())
    result = server.list_milestone_issues(
        "o", "r", milestone=1, state="open", page=1, per_page=50
    )
    assert result == []
    assert calls["kwargs"]["state"] == "open"
    assert calls["kwargs"]["per_page"] == 50
