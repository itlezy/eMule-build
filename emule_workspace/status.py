"""Workspace status reporting helpers."""

from __future__ import annotations

from .git import repo_branch, repo_head, repo_status_lines
from .layout import WorkspaceLayout


def write_dependency_status(layout: WorkspaceLayout) -> None:
    """Prints dependency and app worktree status."""

    for dependency in layout.dependencies:
        repo_path = layout.resolve_workspace_path(dependency.path)
        if not repo_path.exists():
            print(f"MISSING {dependency.name} -> {repo_path}")
            continue
        print(f"DEP {dependency.name} [{repo_branch(repo_path)}] {'; '.join(repo_status_lines(repo_path))}")
    for app in layout.app_variants:
        print(f"APP {app.path} [{repo_branch(app.path)}] {'; '.join(repo_status_lines(app.path))}")


def write_workspace_summary(layout: WorkspaceLayout) -> None:
    """Prints a concise dependency and app commit summary."""

    print("")
    print("Workspace summary")
    for dependency in layout.dependencies:
        repo_path = layout.resolve_workspace_path(dependency.path)
        if not repo_path.exists():
            continue
        print(f"DEP {dependency.name:<12} {repo_branch(repo_path)} {repo_head(repo_path)}")
    for app in layout.app_variants:
        print(f"APP {app.name:<12} {repo_branch(app.path)} {repo_head(app.path)}")
