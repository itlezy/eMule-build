"""Click command surface for eMule workspace orchestration."""

from __future__ import annotations

from collections.abc import Callable
from functools import wraps
from typing import Any, TypeVar

import click

from .build_tests import invoke_build_tests
from .build import build_apps as invoke_build_apps
from .build import build_libs as invoke_build_libs
from .cleanup import cleanup_workspace
from .config import (
    AmutorrentCleanStartupOptions,
    AmutorrentEmulebbUiOptions,
    AmutorrentResilienceOptions,
    AmutorrentSessionOptions,
    BuildTestsOptions,
    CleanupOptions,
    CommunityCoverageOptions,
    LiveE2eOptions,
    PythonTestOptions,
    ReleasePackageOptions,
    VariantComparisonOptions,
    WorkspaceOptions,
    resolve_workspace_options,
)
from .layout import load_layout
from .locks import WorkspaceLock
from .materialize import materialize_workspace, sync_workspace
from .python_tests import invoke_python_tests
from .release import create_release_package
from .setup_commands import run_compare, write_dependency_update_report, write_materialization_status
from .status import write_dependency_status, write_workspace_summary
from .test_runs import (
    invoke_amutorrent_clean_startup,
    invoke_amutorrent_emulebb_ui,
    invoke_amutorrent_interactive_session,
    invoke_amutorrent_resilience,
    invoke_community_core_coverage,
    invoke_live_diff_runs,
    invoke_live_e2e_suite,
    invoke_native_test_suites,
    invoke_test_runs,
)
from .validation import validate_workspace

F = TypeVar("F", bound=Callable[..., Any])


def _common_options(function: F) -> F:
    @click.option("--workspace-root", envvar="EMULE_WORKSPACE_ROOT", help="Canonical EMULE_WORKSPACE_ROOT.")
    @click.option("--workspace-name", default=None, help="Workspace name. Defaults to build manifest value.")
    @click.option("--config", "configuration", type=click.Choice(["Debug", "Release"]), default="Release", show_default=True)
    @click.option("--platform", type=click.Choice(["x64", "ARM64"]), default="x64", show_default=True)
    @click.option(
        "--build-output-mode",
        type=click.Choice(["Full", "Warnings", "ErrorsOnly"]),
        default="ErrorsOnly",
        show_default=True,
    )
    @wraps(function)
    def wrapper(*args: Any, **kwargs: Any) -> Any:
        try:
            workspace_options = resolve_workspace_options(
                workspace_root=kwargs.pop("workspace_root"),
                workspace_name=kwargs.pop("workspace_name"),
                configuration=kwargs.pop("configuration"),
                platform=kwargs.pop("platform"),
                build_output_mode=kwargs.pop("build_output_mode"),
            )
            layout = load_layout(workspace_options.workspace_root, workspace_options.workspace_name)
        except Exception as exc:
            raise click.ClickException(str(exc)) from exc
        return function(*args, workspace_options=workspace_options, layout=layout, **kwargs)

    return wrapper  # type: ignore[return-value]


def _locked(command_name: str, function: F) -> F:
    @wraps(function)
    def wrapper(*args: Any, workspace_options: WorkspaceOptions, layout, **kwargs: Any) -> Any:
        lock = WorkspaceLock(layout=layout, command=command_name, options=workspace_options)
        if not lock.acquire():
            raise click.ClickException(
                f"Workspace busy: command '{command_name}' cannot start for "
                f"{layout.emule_workspace_root}. Active owner: {lock.active_owner_text()}."
            )
        try:
            try:
                return function(*args, workspace_options=workspace_options, layout=layout, **kwargs)
            except click.ClickException:
                raise
            except Exception as exc:
                raise click.ClickException(str(exc)) from exc
        finally:
            lock.release()

    return wrapper  # type: ignore[return-value]


def _comparison_options(function: F) -> F:
    @click.option("--test-run-variant", default=None, help="App variant to run as the test target.")
    @click.option("--baseline-variant", default=None, help="App variant to use as the comparison baseline.")
    @wraps(function)
    def wrapper(*args: Any, **kwargs: Any) -> Any:
        comparison_options = VariantComparisonOptions(
            test_run_variant=kwargs.pop("test_run_variant"),
            baseline_variant=kwargs.pop("baseline_variant"),
        )
        return function(*args, comparison_options=comparison_options, **kwargs)

    return wrapper  # type: ignore[return-value]


def _live_e2e_options(function: F) -> F:
    @click.option("--suite", "suites", multiple=True, help="Live E2E suite to run.")
    @click.option(
        "--profile",
        type=click.Choice(["default", "beta-green", "controller-surface", "beta-release", "stabilization-stress", "cpu-heavy"]),
        default="default",
        show_default=True,
        help="Named live E2E suite profile.",
    )
    @click.option("--fail-fast", is_flag=True, help="Stop the live E2E suite after the first failure.")
    @click.option("--skip-live-seed-refresh", is_flag=True, help="Reuse the existing live seed state.")
    @click.option("--startup-trace-mode", type=click.Choice(["required", "optional"]), default="required", show_default=True)
    @click.option("--shared-root", default=None, help="Shared file root for live UI scenarios.")
    @click.option("--preference-ui-directories-tree-stress", is_flag=True, help="Exercise the Preferences Directories tree with a large shared-directory profile.")
    @click.option("--shared-files-ui-scenario", "shared_files_ui_scenarios", multiple=True)
    @click.option("--shared-files-tree-stress-churn-cycles", default=-1, show_default=True, type=int)
    @click.option("--live-wire-inputs-file", default=None, help="Runtime live-wire search input JSON.")
    @click.option("--radarr-movie-root", default=None, help="Radarr-visible movie root for Radarr import live checks.")
    @click.option("--sonarr-series-root", default=None, help="Sonarr-visible series root for Sonarr import live checks.")
    @click.option("--acquisition-timeout-minutes", default=None, type=float, help="Arr acquisition timeout forwarded to live suites.")
    @click.option("--p2p-bind-interface-name", default="hide.me", show_default=True)
    @click.option("--rest-server-search-count", default=6, show_default=True, type=int)
    @click.option("--rest-kad-search-count", default=6, show_default=True, type=int)
    @click.option("--rest-download-trigger-count", default=1, show_default=True, type=int)
    @click.option("--rest-search-method-override", type=click.Choice(["", "automatic", "server", "global", "kad"]), default="")
    @click.option("--rest-webserver-scheme", type=click.Choice(["http", "https"]), default="http", show_default=True)
    @click.option("--rest-coverage-budget", type=click.Choice(["smoke", "contract", "contract-stress"]), default="contract")
    @click.option("--rest-stress-budget", type=click.Choice(["off", "smoke", "soak"]), default="smoke")
    @click.option("--rest-stress-duration-seconds", default=30.0, show_default=True, type=float)
    @click.option("--rest-stress-concurrency", default=4, show_default=True, type=int)
    @click.option("--rest-stress-max-failures", default=1, show_default=True, type=int)
    @click.option("--rest-stress-request-timeout-seconds", default=5.0, show_default=True, type=float)
    @click.option("--rest-socket-adversity-budget", type=click.Choice(["off", "smoke"]), default="off")
    @click.option("--rest-tls-handshake-adversity-budget", type=click.Choice(["off", "smoke"]), default="off")
    @click.option("--rest-leak-churn-budget", type=click.Choice(["off", "smoke", "soak"]), default="off")
    @click.option("--rest-leak-churn-cycles", default=-1, show_default=True, type=int)
    @click.option("--rest-stop-start-after-churn", is_flag=True)
    @click.option("--search-ui-search-rounds", default=1, show_default=True, type=int)
    @click.option("--search-ui-download-lifecycle-count", default=1, show_default=True, type=int)
    @click.option("--rest-cold-start-dump-stress-waves", default=4, show_default=True, type=int)
    @click.option("--rest-cold-start-dump-stress-searches-per-wave", default=12, show_default=True, type=int)
    @click.option("--rest-cold-start-dump-stress-max-concurrent-searches", default=8, show_default=True, type=int)
    @click.option("--rest-cold-start-dump-stress-search-observation-timeout-seconds", default=60.0, show_default=True, type=float)
    @click.option("--rest-cold-start-dump-stress-downloads-per-wave", default=600, show_default=True, type=int)
    @click.option("--rest-cold-start-dump-stress-downloads-per-search", default=50, show_default=True, type=int)
    @click.option("--rest-cold-start-dump-stress-max-missing-download-triggers", default=0, show_default=True, type=int)
    @click.option("--rest-cold-start-dump-stress-synthetic-queue-fill-count", default=0, show_default=True, type=int)
    @click.option("--rest-cold-start-dump-stress-synthetic-queue-fill-size-bytes", default=1024 * 1024, show_default=True, type=int)
    @click.option("--rest-cold-start-dump-stress-synthetic-queue-fill-batch-size", default=50, show_default=True, type=int)
    @click.option("--rest-cold-start-dump-stress-target-completed-downloads", default=0, show_default=True, type=int)
    @click.option("--rest-cold-start-dump-stress-completion-timeout-seconds", default=1800.0, show_default=True, type=float)
    @click.option("--rest-cold-start-dump-stress-max-active-downloads", default=512, show_default=True, type=int)
    @click.option("--rest-cold-start-dump-stress-allow-required-zero-result-searches", is_flag=True)
    @click.option("--rest-cold-start-dump-stress-skip-transfer-cleanup", is_flag=True)
    @click.option("--rest-cold-start-dump-stress-download-churn-interval-seconds", default=0.0, show_default=True, type=float)
    @click.option("--rest-cold-start-dump-stress-download-remove-count-per-churn", default=0, show_default=True, type=int)
    @click.option("--rest-cold-start-dump-stress-resource-monitor-interval-seconds", default=5.0, show_default=True, type=float)
    @click.option("--rest-cold-start-dump-stress-post-drain-seconds", default=30.0, show_default=True, type=float)
    @click.option("--rest-cold-start-dump-stress-tool-timeout-seconds", default=60.0, show_default=True, type=float)
    @click.option("--rest-cold-start-dump-stress-enable-umdh", is_flag=True)
    @click.option("--rest-cold-start-dump-stress-skip-umdh-diffs", is_flag=True)
    @click.option("--rest-cold-start-dump-stress-cpu-profile", is_flag=True)
    @click.option("--rest-cold-start-dump-stress-cpu-profile-max-file-mb", default=512, show_default=True, type=int)
    @click.option("--rest-cold-start-dump-stress-cpu-profile-stack", is_flag=True)
    @click.option("--rest-cold-start-dump-stress-cpu-profile-stack-min-hits", default=10, show_default=True, type=int)
    @click.option(
        "--rest-cold-start-dump-stress-cpu-profile-symbols-required/--no-rest-cold-start-dump-stress-cpu-profile-symbols-required",
        default=True,
        show_default=True,
    )
    @click.option("--rest-cold-start-dump-stress-skip-dumps", is_flag=True)
    @wraps(function)
    def wrapper(*args: Any, **kwargs: Any) -> Any:
        live_options = LiveE2eOptions(**{key: kwargs.pop(key) for key in LiveE2eOptions.model_fields})
        return function(*args, live_options=live_options, **kwargs)

    return wrapper  # type: ignore[return-value]


@click.group(context_settings={"help_option_names": ["-h", "--help"]})
def main() -> None:
    """Build, validate, test, and package an eMule BB workspace."""


@main.command()
@click.option("--workspace-root", default=None, help="Canonical EMULE_WORKSPACE_ROOT. Defaults from repos/eMule-build layout.")
@click.option("--workspace-name", default=None, help="Workspace name. Defaults to canonical topology.")
@click.option("--artifacts-seed-root", default=None, help="Optional third-party artifact seed root.")
def materialize(*, workspace_root: str | None, workspace_name: str | None, artifacts_seed_root: str | None) -> None:
    """Materialize a new canonical workspace around this eMule-build clone."""

    try:
        materialize_workspace(
            workspace_root=workspace_root,
            workspace_name=workspace_name,
            artifacts_seed_root=artifacts_seed_root,
        )
    except Exception as exc:
        raise click.ClickException(str(exc)) from exc


@main.command()
@click.option("--workspace-root", envvar="EMULE_WORKSPACE_ROOT", default=None, help="Canonical EMULE_WORKSPACE_ROOT.")
@click.option("--workspace-name", default=None, help="Workspace name. Defaults to canonical topology.")
@click.option("--artifacts-seed-root", default=None, help="Optional third-party artifact seed root.")
def sync(*, workspace_root: str | None, workspace_name: str | None, artifacts_seed_root: str | None) -> None:
    """Synchronize setup-owned workspace state."""

    try:
        sync_workspace(
            workspace_root=workspace_root,
            workspace_name=workspace_name,
            artifacts_seed_root=artifacts_seed_root,
        )
    except Exception as exc:
        raise click.ClickException(str(exc)) from exc


@main.command()
@_common_options
@click.pass_context
def validate(ctx: click.Context, *, workspace_options: WorkspaceOptions, layout) -> None:
    """Run workspace validation and centralized policy audits."""

    del ctx
    _locked("validate", lambda **kwargs: validate_workspace(kwargs["layout"]))(
        workspace_options=workspace_options,
        layout=layout,
    )


@main.command("cleanup")
@_common_options
@click.option("--apply", "apply_cleanup", is_flag=True, help="Delete selected artifacts. Omit for a dry run.")
@click.option("--profile", type=click.Choice(["routine", "deep"]), default="routine", show_default=True)
@click.option("--report-payload-retention-hours", default=24.0, show_default=True, type=float)
@click.option("--report-run-retention-days", default=7.0, show_default=True, type=float)
@click.option("--arr-acquisition-retention-hours", default=24.0, show_default=True, type=float)
@click.option("--build-log-retention-days", default=14.0, show_default=True, type=float)
@click.option("--keep-build-log-runs", default=25, show_default=True, type=int)
@click.option("--include-build-outputs", is_flag=True, help="Also prune generated app/test/dependency build outputs.")
@click.option("--include-release-state", is_flag=True, help="Also prune superseded release rehearsal state.")
def cleanup(
    *,
    apply_cleanup: bool,
    profile: str,
    report_payload_retention_hours: float,
    report_run_retention_days: float,
    arr_acquisition_retention_hours: float,
    build_log_retention_days: float,
    keep_build_log_runs: int,
    include_build_outputs: bool,
    include_release_state: bool,
    workspace_options: WorkspaceOptions,
    layout,
) -> None:
    """Prune generated workspace artifacts, dry-run by default."""

    cleanup_options = CleanupOptions(
        apply=apply_cleanup,
        profile=profile,
        report_payload_retention_hours=report_payload_retention_hours,
        report_run_retention_days=report_run_retention_days,
        arr_acquisition_retention_hours=arr_acquisition_retention_hours,
        build_log_retention_days=build_log_retention_days,
        keep_build_log_runs=keep_build_log_runs,
        include_build_outputs=include_build_outputs,
        include_release_state=include_release_state,
    )
    _locked("cleanup", lambda **kwargs: cleanup_workspace(kwargs["layout"], cleanup_options))(
        workspace_options=workspace_options,
        layout=layout,
    )


@main.command("dep-status")
@_common_options
def dep_status(*, workspace_options: WorkspaceOptions, layout) -> None:
    """Report dependency and app worktree status."""

    _locked("dep-status", lambda **kwargs: write_dependency_status(kwargs["layout"]))(
        workspace_options=workspace_options,
        layout=layout,
    )


@main.command("status")
@click.option("--workspace-root", envvar="EMULE_WORKSPACE_ROOT", default=None, help="Canonical EMULE_WORKSPACE_ROOT.")
def materialization_status(*, workspace_root: str | None) -> None:
    """Report setup-managed repository status."""

    try:
        write_materialization_status(workspace_root=workspace_root)
    except Exception as exc:
        raise click.ClickException(str(exc)) from exc


@main.command("dep-updates")
@click.option("--workspace-root", envvar="EMULE_WORKSPACE_ROOT", default=None, help="Canonical EMULE_WORKSPACE_ROOT.")
@click.option("--workspace-name", default=None, help="Workspace name. Defaults to canonical topology.")
def dep_updates(*, workspace_root: str | None, workspace_name: str | None) -> None:
    """Report advisory third-party dependency updates."""

    try:
        write_dependency_update_report(workspace_root=workspace_root, workspace_name=workspace_name)
    except Exception as exc:
        raise click.ClickException(str(exc)) from exc


@main.command("compare")
@click.argument("preset_key", required=False)
@click.option("--workspace-root", envvar="EMULE_WORKSPACE_ROOT", default=None, help="Canonical EMULE_WORKSPACE_ROOT.")
def compare_command(*, preset_key: str | None, workspace_root: str | None) -> None:
    """Show or launch WinMerge comparison presets."""

    try:
        run_compare(preset_key=preset_key, workspace_root=workspace_root)
    except Exception as exc:
        raise click.ClickException(str(exc)) from exc


@main.group()
def build() -> None:
    """Build workspace targets."""


@build.command("libs")
@_common_options
@click.option("--clean", is_flag=True, help="Clean selected dependency outputs before building.")
def build_libs(
    *,
    clean: bool,
    workspace_options: WorkspaceOptions,
    layout,
) -> None:
    """Build the shared dependency set."""

    _locked(
        "build libs",
        lambda **kwargs: invoke_build_libs(kwargs["layout"], kwargs["workspace_options"], clean=clean),
    )(workspace_options=workspace_options, layout=layout)


@build.command("app")
@_common_options
@click.option("--clean", is_flag=True, help="Clean selected app outputs before building.")
@click.option("--variant", "app_variants", multiple=True, help="App variant to build. Defaults to all variants.")
def build_app(
    *,
    clean: bool,
    app_variants: tuple[str, ...],
    workspace_options: WorkspaceOptions,
    layout,
) -> None:
    """Build selected app worktrees."""

    _locked(
        "build app",
        lambda **kwargs: invoke_build_apps(
            kwargs["layout"],
            kwargs["workspace_options"],
            clean=clean,
            app_variant_names=app_variants,
        ),
    )(workspace_options=workspace_options, layout=layout)


@build.command("tests")
@_common_options
@click.option("--clean", is_flag=True, help="Clean native test intermediates before building.")
@click.option("--test-run-variant", default=None, help="App variant used as the native-test build target.")
def build_tests(
    *,
    clean: bool,
    test_run_variant: str | None,
    workspace_options: WorkspaceOptions,
    layout,
) -> None:
    """Build the shared native emule-tests executable."""

    build_options = BuildTestsOptions(clean=clean, test_run_variant=test_run_variant)
    _locked(
        "build tests",
        lambda **kwargs: invoke_build_tests(kwargs["layout"], kwargs["workspace_options"], build_options),
    )(workspace_options=workspace_options, layout=layout)


@build.command("all")
@_common_options
@click.option("--clean", is_flag=True, help="Clean selected build outputs before building.")
@click.option("--variant", "app_variants", multiple=True, help="App variant to build. Defaults to all variants.")
@click.option("--test-run-variant", default=None, help="App variant used as the native-test build target.")
def build_all(
    *,
    clean: bool,
    app_variants: tuple[str, ...],
    test_run_variant: str | None,
    workspace_options: WorkspaceOptions,
    layout,
) -> None:
    """Build dependencies, app variants, and the native test executable."""

    build_options = BuildTestsOptions(clean=clean, test_run_variant=test_run_variant)

    def run_all(**kwargs: Any) -> None:
        invoke_build_libs(kwargs["layout"], kwargs["workspace_options"], clean=clean)
        invoke_build_apps(kwargs["layout"], kwargs["workspace_options"], clean=clean, app_variant_names=app_variants)
        invoke_build_tests(kwargs["layout"], kwargs["workspace_options"], build_options)

    _locked("build all", run_all)(workspace_options=workspace_options, layout=layout)


@main.group()
def test() -> None:
    """Run workspace test suites."""


@test.command("python", context_settings={"ignore_unknown_options": True, "allow_extra_args": True})
@_common_options
@click.option("--quiet", "-q", is_flag=True, help="Pass -q to pytest.")
@click.option("--path", "paths", multiple=True, help="Pytest path to run, relative to eMule-build-tests.")
@click.option("--expression", "-k", default=None, help="Pytest -k expression.")
@click.argument("extra_args", nargs=-1, type=click.UNPROCESSED)
def test_python(
    *,
    quiet: bool,
    paths: tuple[str, ...],
    expression: str | None,
    extra_args: tuple[str, ...],
    workspace_options: WorkspaceOptions,
    layout,
) -> None:
    """Run the fast pytest harness suite."""

    test_options = PythonTestOptions(
        quiet=quiet,
        paths=paths,
        expression=expression,
        extra_args=extra_args,
    )
    _locked(
        "test python",
        lambda **kwargs: invoke_python_tests(kwargs["layout"], test_options),
    )(workspace_options=workspace_options, layout=layout)


@test.command("native")
@_common_options
@click.option("--test-run-variant", default=None, help="App variant used as the native-test target.")
@click.option("--suite-name", multiple=True, help="Native doctest suite to run. Defaults to parity and web_api.")
def test_native(
    *,
    test_run_variant: str | None,
    suite_name: tuple[str, ...],
    workspace_options: WorkspaceOptions,
    layout,
) -> None:
    """Run native emule-tests suites without live-diff or live E2E work."""

    _locked(
        "test native",
        lambda **kwargs: invoke_native_test_suites(
            kwargs["layout"],
            kwargs["workspace_options"],
            test_run_variant,
            suite_name,
        ),
    )(workspace_options=workspace_options, layout=layout)


@test.command("all")
@_common_options
def test_all(*, workspace_options: WorkspaceOptions, layout) -> None:
    """Run native parity, coverage, and live-diff checks."""

    _locked("test all", lambda **kwargs: invoke_test_runs(kwargs["layout"], kwargs["workspace_options"]))(
        workspace_options=workspace_options,
        layout=layout,
    )


@test.command("live-diff")
@_common_options
@_comparison_options
def test_live_diff(
    *,
    comparison_options: VariantComparisonOptions,
    workspace_options: WorkspaceOptions,
    layout,
) -> None:
    """Compare two configured app variants."""

    _locked(
        "test live-diff",
        lambda **kwargs: invoke_live_diff_runs(kwargs["layout"], kwargs["workspace_options"], comparison_options),
    )(workspace_options=workspace_options, layout=layout)


@test.command("community-core-coverage")
@_common_options
@click.option("--test-run-variant", default=None, help="App variant to run as the test target.")
@click.option("--baseline-variant", default=None, help="App variant to use as the comparison baseline.")
@click.option("--rest-coverage-budget", type=click.Choice(["smoke", "contract", "contract-stress"]), default="contract")
@click.option("--rest-stress-budget", type=click.Choice(["off", "smoke", "soak"]), default="smoke")
def test_community_core_coverage(
    *,
    test_run_variant: str | None,
    baseline_variant: str | None,
    rest_coverage_budget: str,
    rest_stress_budget: str,
    workspace_options: WorkspaceOptions,
    layout,
) -> None:
    """Run community-core coverage checks."""

    coverage_options = CommunityCoverageOptions(
        test_run_variant=test_run_variant,
        baseline_variant=baseline_variant,
        rest_coverage_budget=rest_coverage_budget,
        rest_stress_budget=rest_stress_budget,
    )
    _locked(
        "test community-core-coverage",
        lambda **kwargs: invoke_community_core_coverage(kwargs["layout"], kwargs["workspace_options"], coverage_options),
    )(workspace_options=workspace_options, layout=layout)


@test.command("live-e2e")
@_common_options
@_live_e2e_options
def test_live_e2e(
    *,
    live_options: LiveE2eOptions,
    workspace_options: WorkspaceOptions,
    layout,
) -> None:
    """Run aggregate live E2E suites."""

    _locked(
        "test live-e2e",
        lambda **kwargs: invoke_live_e2e_suite(kwargs["layout"], kwargs["workspace_options"], live_options),
    )(workspace_options=workspace_options, layout=layout)


@test.command("amutorrent-session")
@_common_options
@click.option("--live-network", is_flag=True, help="Allow the aMuTorrent session to use the live network.")
def test_amutorrent_session(
    *,
    live_network: bool,
    workspace_options: WorkspaceOptions,
    layout,
) -> None:
    """Start an interactive aMuTorrent test session."""

    session_options = AmutorrentSessionOptions(live_network=live_network)
    _locked(
        "test amutorrent-session",
        lambda **kwargs: invoke_amutorrent_interactive_session(kwargs["layout"], kwargs["workspace_options"], session_options),
    )(workspace_options=workspace_options, layout=layout)


@test.command("amutorrent-clean-startup")
@_common_options
@click.option("--live-wire-inputs-file", default=None, help="Runtime live-wire search/download input JSON.")
@click.option("--keep-artifacts", is_flag=True, help="Keep source artifacts after the clean-startup run.")
@click.option("--ready-timeout-seconds", default=60.0, show_default=True, type=float)
@click.option("--network-ready-timeout-seconds", default=180.0, show_default=True, type=float)
@click.option("--search-observation-timeout-seconds", default=120.0, show_default=True, type=float)
@click.option("--p2p-bind-interface-name", default="hide.me", show_default=True)
def test_amutorrent_clean_startup(
    *,
    live_wire_inputs_file: str | None,
    keep_artifacts: bool,
    ready_timeout_seconds: float,
    network_ready_timeout_seconds: float,
    search_observation_timeout_seconds: float,
    p2p_bind_interface_name: str,
    workspace_options: WorkspaceOptions,
    layout,
) -> None:
    """Run the automated aMuTorrent first-run wizard live proof."""

    clean_options = AmutorrentCleanStartupOptions(
        live_wire_inputs_file=live_wire_inputs_file,
        keep_artifacts=keep_artifacts,
        ready_timeout_seconds=ready_timeout_seconds,
        network_ready_timeout_seconds=network_ready_timeout_seconds,
        search_observation_timeout_seconds=search_observation_timeout_seconds,
        p2p_bind_interface_name=p2p_bind_interface_name,
    )
    _locked(
        "test amutorrent-clean-startup",
        lambda **kwargs: invoke_amutorrent_clean_startup(kwargs["layout"], kwargs["workspace_options"], clean_options),
    )(workspace_options=workspace_options, layout=layout)


@test.command("amutorrent-resilience")
@_common_options
@click.option("--live-wire-inputs-file", default=None, help="Runtime live-wire search/download input JSON.")
@click.option("--keep-artifacts", is_flag=True, help="Keep source artifacts after the resilience run.")
@click.option("--ready-timeout-seconds", default=60.0, show_default=True, type=float)
@click.option("--network-ready-timeout-seconds", default=180.0, show_default=True, type=float)
@click.option("--search-observation-timeout-seconds", default=120.0, show_default=True, type=float)
@click.option("--reconnect-timeout-seconds", default=120.0, show_default=True, type=float)
@click.option("--p2p-bind-interface-name", default="hide.me", show_default=True)
def test_amutorrent_resilience(
    *,
    live_wire_inputs_file: str | None,
    keep_artifacts: bool,
    ready_timeout_seconds: float,
    network_ready_timeout_seconds: float,
    search_observation_timeout_seconds: float,
    reconnect_timeout_seconds: float,
    p2p_bind_interface_name: str,
    workspace_options: WorkspaceOptions,
    layout,
) -> None:
    """Run the automated aMuTorrent resilience live proof."""

    resilience_options = AmutorrentResilienceOptions(
        live_wire_inputs_file=live_wire_inputs_file,
        keep_artifacts=keep_artifacts,
        ready_timeout_seconds=ready_timeout_seconds,
        network_ready_timeout_seconds=network_ready_timeout_seconds,
        search_observation_timeout_seconds=search_observation_timeout_seconds,
        reconnect_timeout_seconds=reconnect_timeout_seconds,
        p2p_bind_interface_name=p2p_bind_interface_name,
    )
    _locked(
        "test amutorrent-resilience",
        lambda **kwargs: invoke_amutorrent_resilience(kwargs["layout"], kwargs["workspace_options"], resilience_options),
    )(workspace_options=workspace_options, layout=layout)


@test.command("amutorrent-emulebb-ui")
@_common_options
@click.option("--live-wire-inputs-file", default=None, help="Runtime live-wire search/download input JSON.")
@click.option("--keep-artifacts", is_flag=True, help="Keep source artifacts after the eMule BB UI run.")
@click.option("--ready-timeout-seconds", default=60.0, show_default=True, type=float)
@click.option("--network-ready-timeout-seconds", default=180.0, show_default=True, type=float)
@click.option("--search-observation-timeout-seconds", default=120.0, show_default=True, type=float)
@click.option("--p2p-bind-interface-name", default="hide.me", show_default=True)
def test_amutorrent_emulebb_ui(
    *,
    live_wire_inputs_file: str | None,
    keep_artifacts: bool,
    ready_timeout_seconds: float,
    network_ready_timeout_seconds: float,
    search_observation_timeout_seconds: float,
    p2p_bind_interface_name: str,
    workspace_options: WorkspaceOptions,
    layout,
) -> None:
    """Run the automated aMuTorrent eMule BB UI live proof."""

    ui_options = AmutorrentEmulebbUiOptions(
        live_wire_inputs_file=live_wire_inputs_file,
        keep_artifacts=keep_artifacts,
        ready_timeout_seconds=ready_timeout_seconds,
        network_ready_timeout_seconds=network_ready_timeout_seconds,
        search_observation_timeout_seconds=search_observation_timeout_seconds,
        p2p_bind_interface_name=p2p_bind_interface_name,
    )
    _locked(
        "test amutorrent-emulebb-ui",
        lambda **kwargs: invoke_amutorrent_emulebb_ui(kwargs["layout"], kwargs["workspace_options"], ui_options),
    )(workspace_options=workspace_options, layout=layout)


@main.command()
@_common_options
@click.option("--clean", is_flag=True, help="Clean selected build outputs before building.")
@click.option("--variant", "app_variants", multiple=True, help="App variant to build. Defaults to all variants.")
@click.option("--test-run-variant", default=None, help="App variant used as the native-test build target.")
def full(
    *,
    clean: bool,
    app_variants: tuple[str, ...],
    test_run_variant: str | None,
    workspace_options: WorkspaceOptions,
    layout,
) -> None:
    """Run build all, test all, and a workspace summary."""

    build_options = BuildTestsOptions(clean=clean, test_run_variant=test_run_variant)

    def run_full(**kwargs: Any) -> None:
        invoke_build_libs(kwargs["layout"], kwargs["workspace_options"], clean=clean)
        invoke_build_apps(kwargs["layout"], kwargs["workspace_options"], clean=clean, app_variant_names=app_variants)
        invoke_build_tests(kwargs["layout"], kwargs["workspace_options"], build_options)
        invoke_test_runs(kwargs["layout"], kwargs["workspace_options"])
        write_workspace_summary(kwargs["layout"])

    _locked("full", run_full)(workspace_options=workspace_options, layout=layout)


@main.command("package-release")
@_common_options
@click.option("--clean", is_flag=True, help="Clean selected package build outputs before building.")
@click.option("--release-version", default="0.7.3", show_default=True, help="Release version in MAJOR.MINOR.PATCH form.")
def package_release(
    *,
    clean: bool,
    release_version: str,
    workspace_options: WorkspaceOptions,
    layout,
) -> None:
    """Build the main app and create release package artifacts."""

    package_options = ReleasePackageOptions(release_version=release_version, clean=clean)
    _locked(
        "package release",
        lambda **kwargs: create_release_package(kwargs["layout"], kwargs["workspace_options"], package_options),
    )(workspace_options=workspace_options, layout=layout)


@main.command("env-check")
@_common_options
def env_check(*, workspace_options: WorkspaceOptions, layout) -> None:
    """Verify basic tool discovery and manifest loading."""

    from .validation import env_check as run_env_check

    _locked("env-check", lambda **kwargs: run_env_check(kwargs["layout"]))(
        workspace_options=workspace_options,
        layout=layout,
    )
