"""Python-native workspace materialization and sync commands."""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

from .layout import build_repo_root
from .process import find_tool, run_captured, run_native
from .topology import (
    AppRepo,
    SETUP_LOG_FILE_NAME,
    WORKSPACE_MANIFEST_NAME,
    WORKSPACE_PROPS_FILE_NAME,
    WorkspaceTopology,
    build_workspace_manifest,
    canonical_topology,
    write_json,
)
from .topology import ManagedRepo

ROOT_AGENTS_CONTENT = """ANALYZE THIS WORKSPACE, DIRECTORIES `repos` and `workspaces`
ALWAYS READ AND FOLLOW EMULE_WORKSPACE_ROOT\\repos\\eMule-tooling\\docs\\WORKSPACE_POLICY.md
"""


def derive_workspace_root_from_build_repo() -> Path:
    """Returns EMULE_WORKSPACE_ROOT from the required repos/eMule-build clone layout."""

    repo_root = build_repo_root().resolve()
    if repo_root.name != "eMule-build" or repo_root.parent.name != "repos":
        raise RuntimeError(
            "eMule-build must be cloned as <EMULE_WORKSPACE_ROOT>\\repos\\eMule-build "
            f"for materialization. Current path: {repo_root}"
        )
    return repo_root.parent.parent.resolve()


def resolve_setup_workspace_root(workspace_root: str | None) -> Path:
    """Resolves setup commands to an explicit or layout-derived workspace root."""

    if workspace_root:
        root = Path(workspace_root).expanduser().resolve()
        _assert_build_repo_matches_root(root)
        return root
    return derive_workspace_root_from_build_repo()


def _assert_build_repo_matches_root(root: Path) -> None:
    repo_root = build_repo_root().resolve()
    expected = (root / "repos" / "eMule-build").resolve()
    if repo_root != expected:
        raise RuntimeError(
            "eMule-build must be the clone at <EMULE_WORKSPACE_ROOT>\\repos\\eMule-build. "
            f"Expected {expected}, current package is {repo_root}."
        )


def materialize_workspace(
    *,
    workspace_root: str | None = None,
    workspace_name: str | None = None,
    artifacts_seed_root: str | None = None,
) -> None:
    """Materializes a new workspace around the required repos/eMule-build clone."""

    root = resolve_setup_workspace_root(workspace_root)
    topology = canonical_topology()
    resolved_workspace_name = workspace_name or topology.default_workspace_name
    assert_materialize_bootstrap_root(root)
    sync_workspace(
        workspace_root=str(root),
        workspace_name=resolved_workspace_name,
        artifacts_seed_root=artifacts_seed_root,
        include_worktrees=True,
        persist_environment=True,
    )
    legacy_status_path = root / "workspaces" / resolved_workspace_name / "state" / "EMULE-STATUS.md"
    legacy_status_path.unlink(missing_ok=True)
    log_line(root, "Materialize complete.")


def sync_workspace(
    *,
    workspace_root: str | None = None,
    workspace_name: str | None = None,
    artifacts_seed_root: str | None = None,
    include_worktrees: bool = True,
    persist_environment: bool = False,
) -> None:
    """Synchronizes setup-owned workspace state."""

    root = resolve_setup_workspace_root(workspace_root)
    topology = canonical_topology()
    resolved_workspace_name = workspace_name or topology.default_workspace_name
    ensure_required_tools()
    ensure_root_layout(root, topology, resolved_workspace_name)
    for repo in topology.all_repos():
        repo_path = ensure_repo_clone(root, repo)
        log_line(root, f"Repo ready: {repo.name} [{repo_path}]")
    overlay_seed_artifacts(root, topology, artifacts_seed_root)
    write_workspace_props(root)
    write_workspace_manifest(root, topology, resolved_workspace_name)
    if include_worktrees:
        ensure_app_worktrees(root, topology)
        remove_legacy_app_dependency_links(root, topology)
    write_compare_launchers(root)
    install_workspace_hooks(root, topology)
    if persist_environment:
        set_workspace_root_environment(root)
    log_line(root, "Sync complete.")


def assert_materialize_bootstrap_root(root: Path) -> None:
    """Allows an empty root or one containing only the required build clone."""

    if not root.exists():
        return
    build_repo = build_repo_root().resolve()
    allowed = {build_repo, build_repo.parent}
    unexpected: list[Path] = []
    for path in root.rglob("*"):
        resolved = path.resolve()
        if resolved == build_repo or resolved == build_repo.parent:
            continue
        if build_repo in resolved.parents:
            continue
        if resolved in allowed:
            continue
        unexpected.append(path)
        if len(unexpected) >= 5:
            break
    if unexpected:
        details = "\n".join(str(path) for path in unexpected)
        raise RuntimeError(
            f"Materialize expects an empty workspace root containing only repos\\eMule-build. "
            f"Refusing populated root '{root}'. Use sync for an existing workspace.\n{details}"
        )


def ensure_required_tools() -> None:
    """Checks command-line tools required by materialization."""

    for name in ("git",):
        if find_tool((f"{name}.exe", name)) is None:
            raise RuntimeError(f"Required tool '{name}' is not available on PATH.")


def ensure_root_layout(root: Path, topology: WorkspaceTopology, workspace_name: str) -> None:
    """Creates setup-owned root directories and root AGENTS.md."""

    root.mkdir(parents=True, exist_ok=True)
    for relative_path in topology.root_directories:
        (root / relative_path).mkdir(parents=True, exist_ok=True)
    (root / "AGENTS.md").write_text(ROOT_AGENTS_CONTENT, encoding="ascii")
    workspace_root = root / "workspaces" / workspace_name
    for relative_path in ("app", "artifacts", "logs", "scripts", "state"):
        (workspace_root / relative_path).mkdir(parents=True, exist_ok=True)


def ensure_repo_clone(root: Path, repo: ManagedRepo) -> Path:
    """Clones or fast-forwards one managed repository."""

    repo_path = (root / repo.relative_path).resolve()
    repo_path.parent.mkdir(parents=True, exist_ok=True)
    if not repo_path.exists():
        clone_args = ["git", "clone"]
        if repo.has_submodules:
            clone_args.append("--recurse-submodules")
        if not repo.branch_optional:
            clone_args.extend(["--branch", repo.branch])
        clone_args.extend([repo.url, str(repo_path)])
        run_native(clone_args, label=f"clone {repo.name}", cwd=root)
        ensure_repo_additional_remotes(repo_path, repo)
        return repo_path

    run_native(["git", "-C", repo_path, "fetch", "origin", "--prune"], label=f"fetch {repo.name}", cwd=root)
    ensure_repo_additional_remotes(repo_path, repo)
    if not isinstance(repo, AppRepo):
        run_native(["git", "-C", repo_path, "checkout", repo.branch], label=f"checkout {repo.name}", cwd=root)
        run_native(
            ["git", "-C", repo_path, "pull", "--ff-only", "origin", repo.branch],
            label=f"fast-forward {repo.name}",
            cwd=root,
        )
    if repo.has_submodules:
        run_native(
            ["git", "-C", repo_path, "submodule", "update", "--init", "--recursive"],
            label=f"submodules {repo.name}",
            cwd=root,
        )
    return repo_path


def ensure_repo_additional_remotes(repo_path: Path, repo: ManagedRepo) -> None:
    """Adds or updates configured secondary remotes."""

    existing = run_captured(["git", "-C", repo_path, "remote"], label=f"list remotes {repo.name}", cwd=repo_path)
    existing_names = {line.strip() for line in existing.splitlines() if line.strip()}
    for remote in repo.additional_remotes:
        if remote.name in existing_names:
            run_native(
                ["git", "-C", repo_path, "remote", "set-url", remote.name, remote.url],
                label=f"set remote {repo.name}/{remote.name}",
                cwd=repo_path,
            )
        else:
            run_native(
                ["git", "-C", repo_path, "remote", "add", remote.name, remote.url],
                label=f"add remote {repo.name}/{remote.name}",
                cwd=repo_path,
            )


def ensure_app_worktrees(root: Path, topology: WorkspaceTopology) -> None:
    """Ensures all active app worktrees exist and match their managed branches."""

    repo_path = (root / topology.app_repo.relative_path).resolve()
    run_native(["git", "-C", repo_path, "fetch", "origin", "--prune"], label="fetch app repo", cwd=root)
    for worktree in topology.app_repo.worktrees:
        if not worktree.active:
            continue
        branch_exists = run_native(
            ["git", "-C", repo_path, "show-ref", "--verify", "--quiet", f"refs/heads/{worktree.branch}"],
            label=f"check app branch {worktree.branch}",
            cwd=root,
            allow_failure=True,
        )
        if branch_exists.returncode != 0:
            run_native(
                [
                    "git",
                    "-C",
                    repo_path,
                    "fetch",
                    "origin",
                    f"refs/heads/{worktree.branch}:refs/remotes/origin/{worktree.branch}",
                ],
                label=f"fetch app branch {worktree.branch}",
                cwd=root,
            )
            run_native(
                ["git", "-C", repo_path, "branch", "--track", worktree.branch, f"origin/{worktree.branch}"],
                label=f"track app branch {worktree.branch}",
                cwd=root,
            )
    current_branch = run_captured(
        ["git", "-C", repo_path, "branch", "--show-current"],
        label="current app anchor branch",
        cwd=root,
    ).strip()
    if current_branch == topology.app_repo.branch:
        run_native(
            ["git", "-C", repo_path, "checkout", "--detach", f"refs/remotes/origin/{topology.app_repo.branch}"],
            label="detach app anchor",
            cwd=root,
        )
    for worktree in topology.app_repo.worktrees:
        if worktree.active:
            ensure_app_worktree(root, repo_path, worktree.relative_path, worktree.branch)


def ensure_app_worktree(root: Path, repo_path: Path, relative_path: str, branch: str) -> None:
    """Ensures one managed app worktree exists and can fast-forward when clean."""

    target_path = (root / relative_path).resolve()
    target_path.parent.mkdir(parents=True, exist_ok=True)
    if not target_path.exists():
        run_native(
            ["git", "-C", repo_path, "worktree", "add", str(target_path), branch],
            label=f"add app worktree {branch}",
            cwd=root,
        )
        return
    run_native(["git", "-C", target_path, "fetch", "origin", "--prune"], label=f"fetch worktree {branch}", cwd=root)
    run_native(["git", "-C", target_path, "checkout", branch], label=f"checkout worktree {branch}", cwd=root)
    status = run_captured(["git", "-C", target_path, "status", "--short"], label=f"status worktree {branch}", cwd=root)
    if status.strip():
        print(f"WARNING: Worktree '{target_path}' is dirty; skipping fast-forward for managed branch '{branch}'.")
        return
    remote_ref = f"refs/remotes/origin/{branch}"
    remote_exists = run_native(
        ["git", "-C", target_path, "show-ref", "--verify", "--quiet", remote_ref],
        label=f"check remote {branch}",
        cwd=root,
        allow_failure=True,
    )
    if remote_exists.returncode == 0:
        run_native(["git", "-C", target_path, "merge", "--ff-only", remote_ref], label=f"fast-forward {branch}", cwd=root)


def remove_legacy_app_dependency_links(root: Path, topology: WorkspaceTopology) -> None:
    """Removes old dependency reparse links from managed app worktrees."""

    for worktree in topology.app_repo.worktrees:
        if not worktree.active:
            continue
        worktree_root = root / worktree.relative_path
        for name in ("cryptopp", "id3lib", "mbedtls", "miniupnpc", "ResizableLib", "zlib"):
            candidate = worktree_root / name
            if candidate.exists() and candidate.is_symlink():
                candidate.unlink()


def overlay_seed_artifacts(root: Path, topology: WorkspaceTopology, seed_root: str | None) -> None:
    """Copies optional third-party artifact seeds into managed dependency repos."""

    if not seed_root:
        return
    resolved_seed_root = Path(seed_root).expanduser().resolve()
    if not resolved_seed_root.is_dir():
        raise RuntimeError(f"Artifacts seed root '{resolved_seed_root}' does not exist.")
    for repo in topology.third_party_repos:
        source = resolved_seed_root / repo.name
        if not source.is_dir():
            continue
        destination = root / repo.relative_path
        shutil.copytree(source, destination, dirs_exist_ok=True)


def write_workspace_props(root: Path) -> None:
    """Writes the generated MSBuild workspace props file."""

    content = """<?xml version="1.0" encoding="utf-8"?>
<Project ToolsVersion="Current" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <WorkspaceRoot>$([MSBuild]::EnsureTrailingSlash('$(WorkspaceRoot)'))</WorkspaceRoot>
    <ReposRoot>$(WorkspaceRoot)repos\\</ReposRoot>
    <ThirdPartyRoot>$(ReposRoot)third_party\\</ThirdPartyRoot>
    <NlohmannJsonRoot>$(ThirdPartyRoot)eMule-nlohmann-json\\single_include\\</NlohmannJsonRoot>
  </PropertyGroup>
  <ItemDefinitionGroup>
    <ClCompile>
      <AdditionalIncludeDirectories>$(NlohmannJsonRoot);$(ThirdPartyRoot)eMule-cryptopp;$(ThirdPartyRoot)eMule-ResizableLib;$(ThirdPartyRoot)eMule-zlib;$(ThirdPartyRoot)eMule-miniupnp;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>
    </ClCompile>
  </ItemDefinitionGroup>
</Project>
"""
    (root / WORKSPACE_PROPS_FILE_NAME).write_text(content, encoding="utf-8")


def write_workspace_manifest(root: Path, topology: WorkspaceTopology, workspace_name: str) -> None:
    """Writes the generated JSON workspace manifest."""

    path = root / "workspaces" / workspace_name / WORKSPACE_MANIFEST_NAME
    write_json(path, build_workspace_manifest(topology, workspace_name))


def write_compare_launchers(root: Path) -> None:
    """Writes simple compare launchers that route back through the Python CLI."""

    from .setup_commands import compare_presets

    topology = canonical_topology()
    compare_root = root / "analysis" / "compare"
    mods_root = compare_root / "mods-archive"
    compare_root.mkdir(parents=True, exist_ok=True)
    mods_root.mkdir(parents=True, exist_ok=True)
    _write_cmd(compare_root / "open-compare-menu.cmd", f'python -m emule_workspace compare --workspace-root "{root}"\n')
    _write_cmd(
        mods_root / "open-mods-archive-menu.cmd",
        f'python -m emule_workspace compare mods-archive --workspace-root "{root}"\n',
    )
    for preset in compare_presets(root, topology):
        destination_root = mods_root if preset.category == "Mods Archive" else compare_root
        _write_cmd(
            destination_root / f"{preset.key}.cmd",
            f'python -m emule_workspace compare "{preset.key}" --workspace-root "{root}"\n',
        )


def install_workspace_hooks(root: Path, topology: WorkspaceTopology) -> None:
    """Configures workspace repos and worktrees to use the shared hook path."""

    hooks_path = root / "repos" / "eMule-tooling" / "hooks"
    if not (hooks_path / "pre-commit").is_file():
        raise RuntimeError(f"Shared pre-commit hook is missing: {hooks_path / 'pre-commit'}")
    hook_repo_names = {"eMule-build", "eMule-build-tests", "eMule-tooling"}
    targets = [root / repo.relative_path for repo in topology.repos if repo.name in hook_repo_names]
    targets.extend(root / worktree.relative_path for worktree in topology.app_repo.worktrees if worktree.active)
    for target in targets:
        if not target.is_dir():
            raise RuntimeError(f"Missing hook install target: {target}")
        configured = run_native(
            ["git", "-C", target, "config", "--local", "--get", "core.hooksPath"],
            label=f"read hooks path {target}",
            cwd=root,
            allow_failure=True,
        )
        current = run_captured(
            ["git", "-C", target, "config", "--local", "--get", "core.hooksPath"],
            label=f"hooks path {target}",
            cwd=root,
        ).strip() if configured.returncode == 0 else ""
        if current:
            current_path = (target / current).resolve() if not Path(current).is_absolute() else Path(current).resolve()
            if current_path != hooks_path.resolve():
                raise RuntimeError(f"Refusing to replace unmanaged core.hooksPath for '{target}'.")
        run_native(["git", "-C", target, "config", "--local", "core.hooksPath", str(hooks_path)], label=f"install hooks {target}", cwd=root)
        run_native(["git", "-C", target, "config", "--local", "core.autocrlf", "false"], label=f"configure autocrlf {target}", cwd=root)


def set_workspace_root_environment(root: Path) -> None:
    """Sets EMULE_WORKSPACE_ROOT for this process and the Windows user environment."""

    resolved = str(root.resolve())
    os.environ["EMULE_WORKSPACE_ROOT"] = resolved
    if sys.platform == "win32":
        import winreg

        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment", 0, winreg.KEY_SET_VALUE) as key:
            winreg.SetValueEx(key, "EMULE_WORKSPACE_ROOT", 0, winreg.REG_EXPAND_SZ, resolved)
    print(f"EMULE_WORKSPACE_ROOT={resolved}")
    print("Restart existing shells to pick up the persisted user environment value.")


def log_line(root: Path, message: str) -> None:
    """Appends one setup log line under the workspace root."""

    log_path = root / SETUP_LOG_FILE_NAME
    with log_path.open("a", encoding="utf-8", newline="\n") as stream:
        stream.write(message + "\n")


def _write_cmd(path: Path, command: str) -> None:
    path.write_text("@ECHO OFF\r\n" + command.replace("\n", "\r\n"), encoding="ascii", newline="")
