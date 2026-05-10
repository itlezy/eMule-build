"""Workspace test and live-test orchestration."""

from __future__ import annotations

from pathlib import Path

from .config import (
    AmutorrentSessionOptions,
    CommunityCoverageOptions,
    LiveE2eOptions,
    VariantComparisonOptions,
    WorkspaceOptions,
)
from .layout import WorkspaceLayout, get_test_build_tag
from .process import get_python_invocation, run_native


def invoke_test_runs(layout: WorkspaceLayout, options: WorkspaceOptions) -> None:
    """Runs native parity/web_api suites, coverage, and live-diff."""

    _assert_test_execution_platform_supported(options)
    test_run_variant = layout.test_targets.test_run_variant
    app_root = layout.get_app_variant(test_run_variant).path
    build_tag = get_test_build_tag(layout.workspace_root, app_root)
    binary_path = layout.tests_repo_root / "build" / build_tag / options.platform / options.configuration / "emule-tests.exe"
    if not binary_path.is_file():
        raise RuntimeError(f"Built test executable not found: {binary_path}")

    for suite_name in ("parity", "web_api"):
        run_native(
            [binary_path, f"--test-suite={suite_name}"],
            label=f"{suite_name} tests {options.configuration}/{options.platform}",
            cwd=layout.tests_repo_root,
        )

    python = get_python_invocation()
    run_native(
        python.command(
            [
                layout.tests_repo_root / "scripts" / "run-native-coverage.py",
                "--test-repo-root",
                layout.tests_repo_root,
                "--app-root",
                app_root,
                "--configuration",
                options.configuration,
                "--platform",
                options.platform,
                "--suite-name",
                "parity",
                "--suite-name",
                "web_api",
            ]
        ),
        label="native coverage",
        cwd=layout.emule_workspace_root,
        env={"EMULE_WORKSPACE_ROOT": layout.emule_workspace_root},
    )
    invoke_live_diff_runs(layout, options, VariantComparisonOptions())


def invoke_live_diff_runs(
    layout: WorkspaceLayout,
    options: WorkspaceOptions,
    comparison_options: VariantComparisonOptions,
) -> None:
    """Runs live-diff between two configured app variants."""

    _assert_test_execution_platform_supported(options)
    test_run_variant = comparison_options.test_run_variant or layout.test_targets.test_run_variant
    baseline_variant = comparison_options.baseline_variant or layout.test_targets.baseline_variant
    test_run_app_root = layout.get_app_variant(test_run_variant).path
    baseline_app_root = layout.get_app_variant(baseline_variant).path
    python = get_python_invocation()
    run_native(
        python.command(
            [
                layout.tests_repo_root / "scripts" / "run-live-diff.py",
                "--test-repo-root",
                layout.tests_repo_root,
                "--test-run-app-root",
                test_run_app_root,
                "--baseline-app-root",
                baseline_app_root,
                "--configuration",
                options.configuration,
                "--platform",
                options.platform,
            ]
        ),
        label=f"live diff {test_run_variant} vs {baseline_variant}",
        cwd=layout.emule_workspace_root,
        env={"EMULE_WORKSPACE_ROOT": layout.emule_workspace_root},
    )


def invoke_community_core_coverage(
    layout: WorkspaceLayout,
    options: WorkspaceOptions,
    coverage_options: CommunityCoverageOptions,
) -> None:
    """Runs community-core coverage checks between two variants."""

    _assert_test_execution_platform_supported(options)
    test_run_variant = coverage_options.test_run_variant or layout.test_targets.test_run_variant
    baseline_variant = coverage_options.baseline_variant or layout.test_targets.baseline_variant
    test_run_app_root = layout.get_app_variant(test_run_variant).path
    baseline_app_root = layout.get_app_variant(baseline_variant).path
    python = get_python_invocation()
    run_native(
        python.command(
            [
                layout.tests_repo_root / "scripts" / "run-community-core-coverage.py",
                "--test-repo-root",
                layout.tests_repo_root,
                "--main-app-root",
                test_run_app_root,
                "--community-app-root",
                baseline_app_root,
                "--configuration",
                options.configuration,
                "--platform",
                options.platform,
                "--include-live-rest-e2e",
                "--rest-coverage-budget",
                coverage_options.rest_coverage_budget,
                "--rest-stress-budget",
                coverage_options.rest_stress_budget,
            ]
        ),
        label=f"community core coverage {test_run_variant} vs {baseline_variant}",
        cwd=layout.emule_workspace_root,
        env={"EMULE_WORKSPACE_ROOT": layout.emule_workspace_root},
    )


def invoke_live_e2e_suite(layout: WorkspaceLayout, options: WorkspaceOptions, live_options: LiveE2eOptions) -> None:
    """Runs the aggregate live E2E suite."""

    _assert_test_execution_platform_supported(options)
    app_root = layout.get_app_variant(layout.test_targets.test_run_variant).path
    script_path = layout.tests_repo_root / "scripts" / "run-live-e2e-suite.py"
    if not script_path.is_file():
        raise RuntimeError(f"Missing live E2E suite runner: {script_path}")

    args: list[str | Path | int | float] = [
        script_path,
        "--app-root",
        app_root,
        "--configuration",
        options.configuration,
        "--startup-trace-mode",
        live_options.startup_trace_mode,
        "--rest-server-search-count",
        live_options.rest_server_search_count,
        "--rest-kad-search-count",
        live_options.rest_kad_search_count,
        "--rest-download-trigger-count",
        live_options.rest_download_trigger_count,
        "--rest-coverage-budget",
        live_options.rest_coverage_budget,
        "--rest-stress-budget",
        live_options.rest_stress_budget,
        "--rest-stress-duration-seconds",
        live_options.rest_stress_duration_seconds,
        "--rest-stress-concurrency",
        live_options.rest_stress_concurrency,
        "--rest-stress-max-failures",
        live_options.rest_stress_max_failures,
        "--rest-stress-request-timeout-seconds",
        live_options.rest_stress_request_timeout_seconds,
        "--rest-socket-adversity-budget",
        live_options.rest_socket_adversity_budget,
        "--rest-tls-handshake-adversity-budget",
        live_options.rest_tls_handshake_adversity_budget,
        "--rest-leak-churn-budget",
        live_options.rest_leak_churn_budget,
        "--p2p-bind-interface-name",
        live_options.p2p_bind_interface_name,
        "--rest-cold-start-dump-stress-waves",
        live_options.rest_cold_start_dump_stress_waves,
        "--rest-cold-start-dump-stress-searches-per-wave",
        live_options.rest_cold_start_dump_stress_searches_per_wave,
        "--rest-cold-start-dump-stress-max-concurrent-searches",
        live_options.rest_cold_start_dump_stress_max_concurrent_searches,
        "--rest-cold-start-dump-stress-downloads-per-wave",
        live_options.rest_cold_start_dump_stress_downloads_per_wave,
        "--rest-cold-start-dump-stress-downloads-per-search",
        live_options.rest_cold_start_dump_stress_downloads_per_search,
        "--rest-cold-start-dump-stress-target-completed-downloads",
        live_options.rest_cold_start_dump_stress_target_completed_downloads,
        "--rest-cold-start-dump-stress-completion-timeout-seconds",
        live_options.rest_cold_start_dump_stress_completion_timeout_seconds,
        "--rest-cold-start-dump-stress-max-active-downloads",
        live_options.rest_cold_start_dump_stress_max_active_downloads,
        "--rest-cold-start-dump-stress-download-churn-interval-seconds",
        live_options.rest_cold_start_dump_stress_download_churn_interval_seconds,
        "--rest-cold-start-dump-stress-download-remove-count-per-churn",
        live_options.rest_cold_start_dump_stress_download_remove_count_per_churn,
        "--rest-cold-start-dump-stress-resource-monitor-interval-seconds",
        live_options.rest_cold_start_dump_stress_resource_monitor_interval_seconds,
        "--rest-cold-start-dump-stress-post-drain-seconds",
        live_options.rest_cold_start_dump_stress_post_drain_seconds,
        "--rest-cold-start-dump-stress-tool-timeout-seconds",
        live_options.rest_cold_start_dump_stress_tool_timeout_seconds,
    ]
    _append_optional_flag(args, live_options.rest_cold_start_dump_stress_enable_umdh, "--rest-cold-start-dump-stress-enable-umdh")
    _append_optional_flag(args, live_options.rest_cold_start_dump_stress_skip_dumps, "--rest-cold-start-dump-stress-skip-dumps")
    if live_options.rest_leak_churn_cycles >= 0:
        args.extend(["--rest-leak-churn-cycles", live_options.rest_leak_churn_cycles])
    _append_optional_flag(args, live_options.rest_stop_start_after_churn, "--rest-stop-start-after-churn")
    if live_options.shared_root:
        args.extend(["--shared-root", live_options.shared_root])
    for scenario_name in live_options.shared_files_ui_scenarios:
        args.extend(["--shared-files-ui-scenario", scenario_name])
    if live_options.shared_files_tree_stress_churn_cycles >= 0:
        args.extend(["--shared-files-tree-stress-churn-cycles", live_options.shared_files_tree_stress_churn_cycles])
    if live_options.rest_search_method_override:
        args.extend(["--rest-search-method-override", live_options.rest_search_method_override])
    args.extend(["--rest-webserver-scheme", live_options.rest_webserver_scheme])
    for suite_name in live_options.suites:
        args.extend(["--suite", suite_name])
    _append_optional_flag(args, live_options.fail_fast, "--fail-fast")
    _append_optional_flag(args, live_options.skip_live_seed_refresh, "--skip-live-seed-refresh")

    python = get_python_invocation()
    run_native(
        python.command(args),
        label="live E2E suite",
        cwd=layout.emule_workspace_root,
        env={"EMULE_WORKSPACE_ROOT": layout.emule_workspace_root},
    )


def invoke_amutorrent_interactive_session(
    layout: WorkspaceLayout,
    options: WorkspaceOptions,
    session_options: AmutorrentSessionOptions,
) -> None:
    """Starts a disposable interactive aMuTorrent session."""

    _assert_test_execution_platform_supported(options)
    app_root = layout.get_app_variant(layout.test_targets.test_run_variant).path
    script_path = layout.tests_repo_root / "scripts" / "amutorrent-interactive-session.py"
    if not script_path.is_file():
        raise RuntimeError(f"Missing aMuTorrent interactive session runner: {script_path}")

    args: list[str | Path] = [
        script_path,
        "--app-root",
        app_root,
        "--configuration",
        options.configuration,
    ]
    _append_optional_flag(args, session_options.live_network, "--live-network")
    python = get_python_invocation()
    run_native(
        python.command(args),
        label="aMuTorrent interactive session",
        cwd=layout.emule_workspace_root,
        env={"EMULE_WORKSPACE_ROOT": layout.emule_workspace_root},
    )


def _append_optional_flag(args: list, enabled: bool, flag: str) -> None:
    if enabled:
        args.append(flag)


def _assert_test_execution_platform_supported(options: WorkspaceOptions) -> None:
    if options.platform != "x64":
        raise RuntimeError("Test execution supports x64 only.")
