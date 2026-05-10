from __future__ import annotations

from pathlib import Path

from emule_workspace.layout import file_token, get_test_build_tag


def test_get_test_build_tag_matches_existing_harness_shape(tmp_path: Path) -> None:
    workspace_root = tmp_path / "owner" / "workspaces" / "v0.72a"
    app_root = workspace_root / "app" / "eMule-main"

    assert get_test_build_tag(workspace_root, app_root) == "owner-v0.72a-eMule-main"


def test_file_token_matches_legacy_filename_sanitization() -> None:
    assert file_token('repos\\eMule-build-tests: bad/name') == "repos-eMule-build-tests-bad-name"
