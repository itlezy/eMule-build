from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import pytest

from emule_workspace import release
from emule_workspace.layout import AppVariant


def test_package_release_dirty_guard_reports_all_provenance_inputs(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    app_root = tmp_path / "workspaces" / "v0.72a" / "app" / "eMule-main"
    build_root = tmp_path / "repos" / "eMule-build"
    tests_root = tmp_path / "repos" / "eMule-build-tests"
    tooling_root = tmp_path / "repos" / "eMule-tooling"
    for path in (app_root, build_root, tests_root, tooling_root):
        path.mkdir(parents=True)

    dirty = {
        app_root: ["## main...origin/main", " M srchybrid/Preferences.cpp"],
        build_root: ["## main...origin/main"],
        tests_root: ["## main...origin/main", "?? tests/python/test_release_update_urls.py"],
        tooling_root: ["## main...origin/main", " M docs/active/RELEASE-0.7.3.md"],
    }
    monkeypatch.setattr(release, "repo_status_lines", lambda repo: dirty[repo])
    layout = SimpleNamespace(
        build_repo_root=build_root,
        tests_repo_root=tests_root,
        tooling_repo_root=tooling_root,
    )

    with pytest.raises(RuntimeError, match="clean provenance inputs") as excinfo:
        release._assert_clean_release_inputs(layout, app_root)

    message = str(excinfo.value)
    assert "app source" in message
    assert "build orchestration" not in message
    assert "build tests" in message
    assert "tooling docs" in message
    assert "Preferences.cpp" in message
    assert "test_release_update_urls.py" in message
    assert "RELEASE-0.7.3.md" in message


def test_package_release_requires_main_app_source_branch(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    app_root = tmp_path / "workspaces" / "v0.72a" / "app" / "eMule-main"
    app_root.mkdir(parents=True)
    app_variant = AppVariant(name="main", path=app_root, branch="main")
    monkeypatch.setattr(release, "repo_branch", lambda repo: "feature/release-drift")

    with pytest.raises(RuntimeError, match="requires app variant 'main'.*branch 'main'"):
        release._assert_release_source_branch(app_variant)


def test_release_manifest_records_explicit_source_provenance(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    app_root = tmp_path / "workspaces" / "v0.72a" / "app" / "eMule-main"
    build_root = tmp_path / "repos" / "eMule-build"
    tests_root = tmp_path / "repos" / "eMule-build-tests"
    tooling_root = tmp_path / "repos" / "eMule-tooling"
    release_root = tmp_path / "workspaces" / "v0.72a" / "state" / "release" / "emule-bb-v0.7.3"
    zip_path = release_root / "eMule-broadband-0.7.3-x64.zip"
    for path in (app_root, build_root, tests_root, tooling_root, release_root):
        path.mkdir(parents=True)

    branches = {
        app_root: "main",
        build_root: "main",
        tests_root: "main",
        tooling_root: "main",
    }
    heads = {
        app_root: "app1234",
        build_root: "build12",
        tests_root: "tests12",
        tooling_root: "tools12",
    }
    monkeypatch.setattr(release, "repo_branch", lambda repo: branches[repo])
    monkeypatch.setattr(release, "repo_head", lambda repo: heads[repo])

    manifest = release._build_release_manifest(
        layout=SimpleNamespace(
            build_repo_root=build_root,
            tests_repo_root=tests_root,
            tooling_repo_root=tooling_root,
        ),
        workspace_options=SimpleNamespace(configuration="Release", platform="x64"),
        package_options=SimpleNamespace(release_version="0.7.3"),
        app_variant=AppVariant(name="main", path=app_root, branch="main"),
        app_root=app_root,
        zip_path=zip_path,
        release_root=release_root,
        zip_hash="zip-sha",
        exe_hash="exe-sha",
    )

    assert manifest["appVariant"] == "main"
    assert manifest["appBranch"] == "main"
    assert manifest["appCommit"] == "app1234"
    assert manifest["buildBranch"] == "main"
    assert manifest["buildCommit"] == "build12"
    assert manifest["buildTestsBranch"] == "main"
    assert manifest["buildTestsCommit"] == "tests12"
    assert manifest["toolingBranch"] == "main"
    assert manifest["toolingCommit"] == "tools12"
