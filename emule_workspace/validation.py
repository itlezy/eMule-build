"""Workspace validation commands and policy-audit routing."""

from __future__ import annotations

from pathlib import Path

from .git import repo_branch, repo_status_lines, test_app_branch_allowed
from .layout import WorkspaceLayout
from .process import find_tool, run_native


def env_check(layout: WorkspaceLayout) -> None:
    """Validates basic command-line tool discovery."""

    if find_tool(("git.exe", "git")) is None:
        raise RuntimeError("git not found on PATH.")
    if find_tool(("pwsh.exe", "pwsh")) is None:
        raise RuntimeError("pwsh not found on PATH.")
    print(f"Python workspace CLI: {layout.build_repo_root}")
    print(f"Toolset override variable: {layout.toolset_override_variable}")


def assert_required_workspace_paths(layout: WorkspaceLayout) -> None:
    """Checks that the canonical workspace paths needed by orchestration exist."""

    required_paths = [
        layout.emule_workspace_root,
        layout.workspace_root,
        layout.seed_repo_path,
        layout.tests_repo_root,
        layout.tooling_repo_root,
        *(layout.resolve_workspace_path(dependency.path) for dependency in layout.dependencies),
        *(variant.path for variant in layout.app_variants),
    ]
    missing = sorted({path for path in required_paths if not path.exists()})
    if missing:
        details = "\n".join(str(path) for path in missing)
        raise RuntimeError(f"Missing required workspace paths:\n{details}")


def assert_app_layout(layout: WorkspaceLayout) -> None:
    """Checks that configured app worktrees exist and match their expected branches."""

    missing = [variant.path for variant in layout.app_variants if not variant.path.exists()]
    if missing:
        raise RuntimeError("Missing app worktrees:\n" + "\n".join(str(path) for path in missing))
    for variant in layout.app_variants:
        current_branch = repo_branch(variant.path)
        if not test_app_branch_allowed(variant.branch, current_branch):
            raise RuntimeError(
                f"App checkout '{variant.path}' is on branch '{current_branch}', "
                f"expected '{variant.branch}'."
            )


def assert_required_test_helpers(layout: WorkspaceLayout) -> None:
    """Checks that maintained shared test helper entrypoints are present."""

    helpers = (
        "scripts/build-emule-tests.py",
        "scripts/run-native-coverage.py",
        "scripts/run-live-diff.py",
        "scripts/run-community-core-coverage.py",
        "scripts/run-live-e2e-suite.py",
        "scripts/amutorrent-interactive-session.py",
    )
    for relative_path in helpers:
        path = layout.tests_repo_root / Path(relative_path)
        if not path.is_file():
            raise RuntimeError(f"Missing required test helper: {path}")


def ensure_canonical_app_anchor(layout: WorkspaceLayout) -> None:
    """Verifies the canonical app anchor is clean enough for current validation."""

    if not layout.seed_repo_path.is_dir():
        raise RuntimeError(f"Canonical app repo is missing: {layout.seed_repo_path}")
    status_lines = repo_status_lines(layout.seed_repo_path)
    if len(status_lines) > 1:
        raise RuntimeError(
            "Canonical app repo has local changes and cannot be re-anchored automatically: "
            f"{layout.seed_repo_path}"
        )


def run_policy_audits(layout: WorkspaceLayout) -> None:
    """Runs the centralized workspace policy audits owned by eMule-tooling."""

    audit_names = (
        ("build policy audit", "ci/check-build-policy.ps1"),
        ("branch policy audit", "ci/check-branch-policy.ps1"),
        ("dependency pin audit", "ci/check-dependency-pins.ps1"),
        ("documentation path audit", "ci/check-doc-paths.ps1"),
        ("editorconfig policy audit", "ci/check-editorconfig-policy.ps1"),
        ("project entrypoint audit", "ci/check-project-entrypoints.ps1"),
        ("warning policy audit", "ci/check-warning-policy.ps1"),
    )
    for label, relative_path in audit_names:
        audit_path = layout.tooling_repo_root / Path(relative_path)
        if not audit_path.is_file():
            raise RuntimeError(f"Missing required policy audit: {audit_path}")
        run_native(
            [
                "pwsh",
                "-NoLogo",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                audit_path,
                "-EmuleWorkspaceRoot",
                layout.emule_workspace_root,
            ],
            label=label,
            cwd=layout.emule_workspace_root,
        )


def validate_workspace(layout: WorkspaceLayout) -> None:
    """Runs the first Python-native workspace validation pass."""

    env_check(layout)
    assert_required_workspace_paths(layout)
    assert_app_layout(layout)
    ensure_canonical_app_anchor(layout)
    run_policy_audits(layout)
    assert_required_test_helpers(layout)
    print("Workspace validation passed.")
