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
    for relative_path in (
        "ci/check-build-policy.ps1",
        "ci/check-branch-policy.ps1",
        "ci/check-dependency-pins.ps1",
        "ci/check-doc-paths.ps1",
        "ci/check-editorconfig-policy.ps1",
        "ci/check-project-entrypoints.ps1",
        "ci/check-warning-policy.ps1",
    ):
        audit_path = tooling_root / relative_path
        audit_path.parent.mkdir(parents=True, exist_ok=True)
        audit_path.write_text("#Requires -Version 7.6\n", encoding="utf-8")
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
        assert call["env"] == {"EMULE_WORKSPACE_ROOT": tmp_path}
