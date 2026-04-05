"""Parse deploy-config.md to determine which repos have dev/prod environments."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_CONFIG_PATH = os.path.expanduser(
    "~/.config/development-skills/deploy-config.md"
)


@dataclass
class RepoDeployConfig:
    dev: bool = False
    prod: bool = False


@dataclass
class DeployConfig:
    repos: dict[str, RepoDeployConfig] = field(default_factory=dict)

    def has_dev(self, repo: str) -> bool:
        return self.repos.get(repo, RepoDeployConfig()).dev

    def has_prod(self, repo: str) -> bool:
        return self.repos.get(repo, RepoDeployConfig()).prod


def parse_deploy_config(path: str | None = None) -> DeployConfig:
    """Parse deploy-config.md and return a DeployConfig."""
    config_path = Path(path or DEFAULT_CONFIG_PATH)
    if not config_path.exists():
        return DeployConfig()

    text = config_path.read_text()
    config = DeployConfig()

    # Split into sections by ## headings
    sections = re.split(r"^## ", text, flags=re.MULTILINE)

    for section in sections:
        lines = section.strip().splitlines()
        if not lines:
            continue

        heading = lines[0].strip().lower()
        is_dev = "dev" in heading
        is_prod = "prod" in heading

        if not (is_dev or is_prod):
            continue

        # Parse markdown table rows (skip header and separator)
        for line in lines:
            line = line.strip()
            if not line.startswith("|") or line.startswith("| Repo") or "---" in line:
                continue
            cells = [c.strip() for c in line.split("|")]
            # cells[0] is empty (before first |), cells[1] is repo name
            if len(cells) >= 2:
                repo_name = cells[1].strip("`").strip()
                if not repo_name:
                    continue
                if repo_name not in config.repos:
                    config.repos[repo_name] = RepoDeployConfig()
                if is_dev:
                    config.repos[repo_name].dev = True
                if is_prod:
                    config.repos[repo_name].prod = True

    return config
