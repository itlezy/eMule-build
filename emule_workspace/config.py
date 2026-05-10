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


class VariantComparisonOptions(BaseModel):
    """Options for commands that compare two managed app variants."""

    model_config = ConfigDict(frozen=True)

    test_run_variant: str | None = None
    baseline_variant: str | None = None


class LiveE2eOptions(BaseModel):
    """Options forwarded to the aggregate live E2E suite runner."""

    model_config = ConfigDict(frozen=True)

    suites: tuple[str, ...] = ()
    fail_fast: bool = False
    skip_live_seed_refresh: bool = False
    startup_trace_mode: str = "required"
    shared_root: str | None = None
    shared_files_ui_scenarios: tuple[str, ...] = ()
    shared_files_tree_stress_churn_cycles: int = -1
    p2p_bind_interface_name: str = "hide.me"
    rest_server_search_count: int = 6
    rest_kad_search_count: int = 6
    rest_download_trigger_count: int = 1
    rest_search_method_override: str = ""
    rest_webserver_scheme: str = "http"
    rest_coverage_budget: str = "contract"
    rest_stress_budget: str = "smoke"
    rest_stress_duration_seconds: float = 30.0
    rest_stress_concurrency: int = 4
    rest_stress_max_failures: int = 1
    rest_stress_request_timeout_seconds: float = 5.0
    rest_socket_adversity_budget: str = "off"
    rest_tls_handshake_adversity_budget: str = "off"
    rest_leak_churn_budget: str = "off"
    rest_leak_churn_cycles: int = -1
    rest_stop_start_after_churn: bool = False
    rest_cold_start_dump_stress_waves: int = 4
    rest_cold_start_dump_stress_searches_per_wave: int = 12
    rest_cold_start_dump_stress_max_concurrent_searches: int = 8
    rest_cold_start_dump_stress_downloads_per_wave: int = 12
    rest_cold_start_dump_stress_downloads_per_search: int = 1
    rest_cold_start_dump_stress_target_completed_downloads: int = 0
    rest_cold_start_dump_stress_completion_timeout_seconds: float = 1800.0
    rest_cold_start_dump_stress_max_active_downloads: int = 128
    rest_cold_start_dump_stress_download_churn_interval_seconds: float = 0.0
    rest_cold_start_dump_stress_download_remove_count_per_churn: int = 0
    rest_cold_start_dump_stress_resource_monitor_interval_seconds: float = 5.0
    rest_cold_start_dump_stress_post_drain_seconds: float = 30.0
    rest_cold_start_dump_stress_tool_timeout_seconds: float = 600.0
    rest_cold_start_dump_stress_enable_umdh: bool = False
    rest_cold_start_dump_stress_skip_dumps: bool = False


class AmutorrentSessionOptions(BaseModel):
    """Options forwarded to the aMuTorrent interactive session runner."""

    model_config = ConfigDict(frozen=True)

    live_network: bool = False


class CommunityCoverageOptions(VariantComparisonOptions):
    """Options forwarded to the community-core coverage runner."""

    rest_coverage_budget: str = "contract"
    rest_stress_budget: str = "smoke"


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
