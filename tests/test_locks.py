from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

from emule_workspace.config import WorkspaceOptions
from emule_workspace.locks import WorkspaceLock


def test_mutex_name_matches_legacy_workspace_prefix(tmp_path: Path) -> None:
    layout = SimpleNamespace(
        emule_workspace_root=(tmp_path / "WorkspaceRoot").resolve(),
        workspace_root=tmp_path / "WorkspaceRoot" / "workspaces" / "v0.72a",
    )
    options = WorkspaceOptions(workspace_root=layout.emule_workspace_root)

    lock = WorkspaceLock(layout=layout, command="validate", options=options)
    digest = lock._mutex_name().removeprefix("Global\\eMuleBuild-")

    assert lock._mutex_name().startswith("Global\\eMuleBuild-")
    assert digest == digest.upper()
    assert len(digest) == 64
