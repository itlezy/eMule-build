"""Typed command configuration for eMule workspace orchestration."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

BuildConfiguration = Literal["Debug", "Release"]
BuildPlatform = Literal["x64", "ARM64"]
BuildOutputMode = Literal["Full", "Warnings", "ErrorsOnly"]


class WorkspaceOptions(BaseModel):
    """Common workspace command options resolved from CLI input and environment."""

    model_config = ConfigDict(frozen=True)

    workspace_root: Path = Field(description="Canonical EMULE_WORKSPACE_ROOT path.")
    workspace_name: str = Field(default="v0.72a")
    configuration: BuildConfiguration = "Release"
    platform: BuildPlatform = "x64"
    build_output_mode: BuildOutputMode = "ErrorsOnly"

    @field_validator("workspace_root")
    @classmethod
    def resolve_workspace_root(cls, value: Path) -> Path:
        """Stores the workspace root as an absolute path."""

        return value.expanduser().resolve()


class PythonTestOptions(BaseModel):
    """Options for running the fast Python harness tests."""

    model_config = ConfigDict(frozen=True)

    quiet: bool = False
    paths: tuple[str, ...] = ()
    expression: str | None = None
    extra_args: tuple[str, ...] = ()


class BuildTestsOptions(BaseModel):
    """Options for building the native eMule shared test executable."""

    model_config = ConfigDict(frozen=True)

    clean: bool = False
    test_run_variant: str | None = None


def resolve_workspace_options(
    *,
    workspace_root: str | None,
    workspace_name: str | None,
    configuration: str,
    platform: str,
    build_output_mode: str,
) -> WorkspaceOptions:
    """Builds common workspace options from Click values and environment."""

    resolved_root = workspace_root or os.environ.get("EMULE_WORKSPACE_ROOT")
    if not resolved_root:
        raise ValueError("EMULE_WORKSPACE_ROOT or --workspace-root is required.")
    return WorkspaceOptions(
        workspace_root=Path(resolved_root),
        workspace_name=workspace_name or "v0.72a",
        configuration=configuration,
        platform=platform,
        build_output_mode=build_output_mode,
    )
