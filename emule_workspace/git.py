"""Small Git helpers used by workspace validation."""

from __future__ import annotations

from pathlib import Path

from .process import run_captured


def git_output(repo: Path, *args: str) -> str:
    """Runs git in one repository and returns stdout."""

    return run_captured(["git", "-C", str(repo), *args], label=f"git {' '.join(args)}", cwd=repo)


def repo_branch(repo: Path) -> str:
    """Returns the current branch name or HEAD for detached repositories."""

    return git_output(repo, "rev-parse", "--abbrev-ref", "HEAD").strip()


def repo_head(repo: Path) -> str:
    """Returns the current short commit id."""

    return git_output(repo, "rev-parse", "--short", "HEAD").strip()


def repo_status_lines(repo: Path) -> list[str]:
    """Returns non-empty `git status --short --branch` lines."""

    return [line for line in git_output(repo, "status", "--short", "--branch").splitlines() if line]


def test_app_branch_allowed(expected_branch: str, current_branch: str) -> bool:
    """Returns whether a current app branch is allowed for the expected role."""

    return current_branch == expected_branch or (
        expected_branch == "main"
        and (
            current_branch.startswith("feature/")
            or current_branch.startswith("fix/")
            or current_branch.startswith("chore/")
        )
    )
