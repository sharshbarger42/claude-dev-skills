"""Tests for env var and URL validation in gitea_workflow.server."""

from __future__ import annotations

import pytest

from gitea_workflow import server


def test_get_env_returns_value_when_set(monkeypatch):
    monkeypatch.setenv("SOME_VAR", "hello")
    assert server._get_env("SOME_VAR") == "hello"


def test_get_env_exits_when_missing(monkeypatch):
    monkeypatch.delenv("MISSING_VAR", raising=False)
    with pytest.raises(SystemExit):
        server._get_env("MISSING_VAR")


def test_get_env_exits_when_empty(monkeypatch):
    monkeypatch.setenv("EMPTY_VAR", "")
    with pytest.raises(SystemExit):
        server._get_env("EMPTY_VAR")


@pytest.mark.parametrize(
    "url",
    [
        "http://git.example.com",
        "https://git.home.superwerewolves.ninja",
        "https://gitea.local:3000",
    ],
)
def test_validate_base_url_accepts_valid(url):
    assert server._validate_base_url(url) == url


@pytest.mark.parametrize(
    "url",
    [
        "${GITEA_URL}",
        "git.example.com",
        "//git.example.com",
        "ftp://git.example.com",
        "",
    ],
)
def test_validate_base_url_rejects_invalid(url, capsys):
    with pytest.raises(SystemExit):
        server._validate_base_url(url)
    err = capsys.readouterr().err
    assert "GITEA_URL" in err
    assert "http://" in err
