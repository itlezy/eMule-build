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
