from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import pytest

from emule_workspace import validation


def test_policy_audits_receive_workspace_root_through_environment(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    tooling_root = tmp_path / "repos" / "eMule-tooling"
    audit_path = tooling_root / "ci" / "check-workspace-policy.py"
    audit_path.parent.mkdir(parents=True, exist_ok=True)
    audit_path.write_text("#!/usr/bin/env python3\n", encoding="utf-8")
    calls: list[dict[str, object]] = []

    def fake_run_native(command, **kwargs):
        calls.append({"command": command, **kwargs})
        return SimpleNamespace(returncode=0)

    monkeypatch.setattr(validation, "run_native", fake_run_native)
    layout = SimpleNamespace(emule_workspace_root=tmp_path, tooling_repo_root=tooling_root)

    validation.run_policy_audits(layout)

    assert calls
    for call in calls:
        assert "-EmuleWorkspaceRoot" not in call["command"]
        assert "pwsh" not in call["command"]
        assert call["command"][-2] == str(audit_path)
        assert call["env"] == {"EMULE_WORKSPACE_ROOT": tmp_path}


def test_validation_reanchors_clean_canonical_app_anchor(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    canonical_repo = tmp_path / "repos" / "eMule"
    canonical_repo.mkdir(parents=True)
    calls: list[tuple[str, ...]] = []

    def fake_git_output(repo: Path, *args: str) -> str:
        assert repo == canonical_repo
        calls.append(args)
        if args == ("rev-parse", "refs/remotes/origin/main"):
            return "expected-head\n"
        if args == ("rev-parse", "HEAD"):
            return "stale-head\n"
        if args == ("checkout", "--detach", "refs/remotes/origin/main"):
            return ""
        raise AssertionError(f"unexpected git call: {args}")

    monkeypatch.setattr(validation, "repo_status_lines", lambda repo: ["## HEAD (no branch)"])
    monkeypatch.setattr(validation, "repo_branch", lambda repo: "HEAD")
    monkeypatch.setattr(validation, "git_output", fake_git_output)
    layout = SimpleNamespace(seed_repo_path=canonical_repo, seed_repo_branch="main")

    validation.ensure_canonical_app_anchor(layout)

    assert calls[-1] == ("checkout", "--detach", "refs/remotes/origin/main")


def test_validation_refuses_dirty_canonical_app_anchor(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    canonical_repo = tmp_path / "repos" / "eMule"
    canonical_repo.mkdir(parents=True)
    calls: list[tuple[str, ...]] = []

    def fake_git_output(repo: Path, *args: str) -> str:
        calls.append(args)
        return ""

    monkeypatch.setattr(validation, "repo_status_lines", lambda repo: ["## HEAD (no branch)", " M srchybrid/emule.rc"])
    monkeypatch.setattr(validation, "git_output", fake_git_output)
    layout = SimpleNamespace(seed_repo_path=canonical_repo, seed_repo_branch="main")

    with pytest.raises(RuntimeError, match="local changes"):
        validation.ensure_canonical_app_anchor(layout)

    assert calls == []
