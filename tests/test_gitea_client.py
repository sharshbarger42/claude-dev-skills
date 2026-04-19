"""Tests for GiteaClient.list_milestone_issues using httpx MockTransport."""

from __future__ import annotations

import httpx
import pytest

from gitea_workflow.gitea_client import GiteaClient


def _make_client(handler) -> GiteaClient:
    """Build a GiteaClient whose HTTP transport is driven by `handler`."""
    client = GiteaClient("https://git.example.com", token="fake-token")
    transport = httpx.MockTransport(handler)
    client._client = httpx.Client(
        headers={"Authorization": "token fake-token"},
        transport=transport,
        timeout=5.0,
    )
    client._reviewer_client = httpx.Client(
        headers={"Authorization": "token fake-token"},
        transport=transport,
        timeout=5.0,
    )
    return client


def test_list_milestone_issues_sends_correct_request():
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["params"] = dict(request.url.params)
        return httpx.Response(
            200,
            json=[
                {
                    "number": 42,
                    "title": "Test issue",
                    "state": "open",
                    "labels": [{"name": "bug"}, {"name": "priority: high"}],
                    "body": "Some description",
                    "html_url": "https://git.example.com/o/r/issues/42",
                }
            ],
        )

    client = _make_client(handler)
    issues = client.list_milestone_issues(
        "owner", "repo", milestone=49, state="open", page=2, per_page=10
    )

    assert captured["url"].startswith(
        "https://git.example.com/api/v1/repos/owner/repo/issues"
    )
    assert captured["params"]["milestones"] == "49"
    assert captured["params"]["state"] == "open"
    assert captured["params"]["type"] == "issues"
    assert captured["params"]["page"] == "2"
    assert captured["params"]["limit"] == "10"

    assert len(issues) == 1
    assert issues[0]["number"] == 42


def test_list_milestone_issues_empty_for_unknown_milestone():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=[])

    client = _make_client(handler)
    issues = client.list_milestone_issues("owner", "repo", milestone=9999)
    assert issues == []


def test_list_milestone_issues_raises_on_http_error():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, json={"message": "boom"})

    client = _make_client(handler)
    with pytest.raises(httpx.HTTPStatusError):
        client.list_milestone_issues("owner", "repo", milestone=1)
