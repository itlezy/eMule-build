"""Workspace topology loading and path resolution."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .process import run_captured


@dataclass(frozen=True)
class Dependency:
    """One dependency entry from the build manifest."""

    name: str
    path: str
    project: str
    header_only: bool = False


@dataclass(frozen=True)
class AppVariant:
    """One managed app worktree variant from the workspace manifest."""

    name: str
    path: Path
    branch: str


@dataclass(frozen=True)
class TestTargets:
    """Default app variants used by shared test flows."""

    test_build_variant: str
    test_run_variant: str
    baseline_variant: str


@dataclass(frozen=True)
class WorkspaceLayout:
    """Resolved layout for one materialized eMule workspace."""

    emule_workspace_root: Path
    workspace_name: str
    workspace_root: Path
    build_repo_root: Path
    tests_repo_root: Path
    tooling_repo_root: Path
    seed_repo_path: Path
    seed_repo_branch: str
    dependencies: tuple[Dependency, ...]
    app_variants: tuple[AppVariant, ...]
    test_targets: TestTargets
    toolset_override_variable: str

    def resolve_workspace_path(self, relative_path: str) -> Path:
        """Resolves a root-relative workspace path."""

        return (self.emule_workspace_root / relative_path).resolve()

    def get_app_variant(self, name: str) -> AppVariant:
        """Returns one configured app variant by name."""

        for variant in self.app_variants:
            if variant.name == name:
                return variant
        raise RuntimeError(f"App variant '{name}' is not defined in deps.psd1.")

    def build_log_directory(self, stamp: str) -> Path:
        """Returns and creates the workspace build-log directory for one session."""

        directory = self.workspace_root / "state" / "build-logs" / stamp
        directory.mkdir(parents=True, exist_ok=True)
        return directory


def build_repo_root() -> Path:
    """Returns the repository root that owns this package."""

    return Path(__file__).resolve().parents[1]


def load_layout(emule_workspace_root: Path, workspace_name: str | None = None) -> WorkspaceLayout:
    """Loads and resolves the build and workspace manifests."""

    repo_root = build_repo_root()
    build_manifest = _load_psd1(repo_root / "deps.psd1")
    build_workspace = _required_dict(build_manifest, "Workspace")
    resolved_workspace_name = workspace_name or str(build_workspace.get("Name") or "v0.72a")
    workspace_root = (emule_workspace_root / "workspaces" / resolved_workspace_name).resolve()
    workspace_manifest_path = workspace_root / "deps.psd1"
    if not workspace_manifest_path.is_file():
        raise RuntimeError(
            f"Workspace manifest is missing: {workspace_manifest_path}. "
            "Run eMulebb-setup init/materialize/sync for this workspace."
        )

    workspace_manifest = _load_psd1(workspace_manifest_path)
    workspace_topology = _required_dict(workspace_manifest, "Workspace")
    app_repo = _required_dict(workspace_topology, "AppRepo")
    seed_repo = _required_dict(app_repo, "SeedRepo")
    repos = _required_dict(workspace_topology, "Repos")
    build_app_repo = _required_dict(build_workspace, "AppRepo")
    test_targets = _required_dict(build_app_repo, "TestTargets")
    toolchain = _required_dict(build_workspace, "Toolchain")

    variants = tuple(
        AppVariant(
            name=str(raw["Name"]),
            path=_resolve_workspace_manifest_path(workspace_root, raw["Path"]),
            branch=str(raw["Branch"]),
        )
        for raw in _required_list(app_repo, "Variants")
    )
    dependencies = tuple(
        Dependency(
            name=str(raw["Name"]),
            path=str(raw["Path"]),
            project=str(raw["Project"]),
            header_only=bool(raw.get("HeaderOnly", False)),
        )
        for raw in _required_list(build_workspace, "Dependencies")
    )

    return WorkspaceLayout(
        emule_workspace_root=emule_workspace_root.resolve(),
        workspace_name=resolved_workspace_name,
        workspace_root=workspace_root,
        build_repo_root=repo_root,
        tests_repo_root=_resolve_workspace_manifest_path(workspace_root, repos["Tests"]),
        tooling_repo_root=_resolve_workspace_manifest_path(workspace_root, repos["Tooling"]),
        seed_repo_path=_resolve_workspace_manifest_path(workspace_root, seed_repo["Path"]),
        seed_repo_branch=str(seed_repo["Branch"]),
        dependencies=dependencies,
        app_variants=variants,
        test_targets=TestTargets(
            test_build_variant=str(test_targets["TestBuildVariant"]),
            test_run_variant=str(test_targets["TestRunVariant"]),
            baseline_variant=str(test_targets["BaselineVariant"]),
        ),
        toolset_override_variable=str(toolchain.get("ToolsetOverrideVariable") or ""),
    )


def get_test_build_tag(workspace_root: Path, app_root: Path | None = None) -> str:
    """Returns the native-test build tag used by existing harness outputs."""

    resolved_workspace_root = workspace_root.resolve()
    workspace_leaf = resolved_workspace_root.name
    workspace_owner = resolved_workspace_root.parent.parent.name
    segments = [segment for segment in (workspace_owner, workspace_leaf) if segment]
    if app_root is not None:
        segments.append(app_root.resolve().name)
    return re.sub(r"[^A-Za-z0-9._-]", "_", "-".join(segments))


def file_token(value: str) -> str:
    """Converts free-form text into a stable log filename token."""

    token = re.sub(r'[\\/:*?"<>|\s]+', "-", value)
    token = re.sub(r"[^A-Za-z0-9._-]+", "-", token).strip("-")
    return token or "build"


def _load_psd1(path: Path) -> dict[str, Any]:
    """Loads a PowerShell data file using PowerShell's data-file parser."""

    command = [
        "pwsh",
        "-NoLogo",
        "-NoProfile",
        "-Command",
        "& { param($p) $m=Import-PowerShellDataFile -LiteralPath $p; $m | ConvertTo-Json -Depth 20 }",
        str(path),
    ]
    output = run_captured(command, label=f"load manifest {path}", cwd=path.parent)
    payload = json.loads(output)
    if not isinstance(payload, dict):
        raise RuntimeError(f"Manifest did not load as an object: {path}")
    return payload


def _resolve_workspace_manifest_path(workspace_root: Path, relative_path: str | Path) -> Path:
    """Resolves a path relative to the workspace manifest's workspace root."""

    return (workspace_root / Path(str(relative_path))).resolve()


def _required_dict(payload: dict[str, Any], key: str) -> dict[str, Any]:
    value = payload.get(key)
    if not isinstance(value, dict):
        raise RuntimeError(f"Manifest is missing object '{key}'.")
    return value


def _required_list(payload: dict[str, Any], key: str) -> list[dict[str, Any]]:
    value = payload.get(key)
    if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
        raise RuntimeError(f"Manifest is missing object list '{key}'.")
    return value
