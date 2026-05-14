"""Workspace test and live-test orchestration."""

from __future__ import annotations

from collections.abc import Sequence
from pathlib import Path

from .config import (
    AmutorrentCleanStartupOptions,
    AmutorrentResilienceOptions,
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

    invoke_native_test_suites(layout, options, None, ("parity", "web_api"))

    python = get_python_invocation()
    test_run_variant = layout.test_targets.test_run_variant
    app_root = layout.get_app_variant(test_run_variant).path
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


def invoke_native_test_suites(
    layout: WorkspaceLayout,
    options: WorkspaceOptions,
    test_run_variant: str | None,
    suite_names: Sequence[str],
) -> None:
    """Runs the native emule-tests executable without live-diff or live E2E work."""

    _assert_test_execution_platform_supported(options)
    selected_variant = test_run_variant or layout.test_targets.test_run_variant
    app_root = layout.get_app_variant(selected_variant).path
    build_tag = get_test_build_tag(layout.workspace_root, app_root)
    binary_path = layout.tests_repo_root / "build" / build_tag / options.platform / options.configuration / "emule-tests.exe"
    if not binary_path.is_file():
        raise RuntimeError(f"Built test executable not found: {binary_path}")

    suites = tuple(suite_names) if suite_names else ("parity", "web_api")
    for suite_name in suites:
        run_native(
            [binary_path, f"--test-suite={suite_name}"],
            label=f"{suite_name} tests {selected_variant} {options.configuration}/{options.platform}",
            cwd=layout.tests_repo_root,
        )


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
        "--rest-cold-start-dump-stress-search-observation-timeout-seconds",
        live_options.rest_cold_start_dump_stress_search_observation_timeout_seconds,
        "--rest-cold-start-dump-stress-downloads-per-wave",
        live_options.rest_cold_start_dump_stress_downloads_per_wave,
        "--rest-cold-start-dump-stress-downloads-per-search",
        live_options.rest_cold_start_dump_stress_downloads_per_search,
        "--rest-cold-start-dump-stress-max-missing-download-triggers",
        live_options.rest_cold_start_dump_stress_max_missing_download_triggers,
        "--rest-cold-start-dump-stress-synthetic-queue-fill-count",
        live_options.rest_cold_start_dump_stress_synthetic_queue_fill_count,
        "--rest-cold-start-dump-stress-synthetic-queue-fill-size-bytes",
        live_options.rest_cold_start_dump_stress_synthetic_queue_fill_size_bytes,
        "--rest-cold-start-dump-stress-synthetic-queue-fill-batch-size",
        live_options.rest_cold_start_dump_stress_synthetic_queue_fill_batch_size,
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
        "--rest-cold-start-dump-stress-cpu-profile-max-file-mb",
        live_options.rest_cold_start_dump_stress_cpu_profile_max_file_mb,
        "--rest-cold-start-dump-stress-cpu-profile-stack-min-hits",
        live_options.rest_cold_start_dump_stress_cpu_profile_stack_min_hits,
    ]
    _append_optional_flag(args, live_options.rest_cold_start_dump_stress_enable_umdh, "--rest-cold-start-dump-stress-enable-umdh")
    _append_optional_flag(args, live_options.rest_cold_start_dump_stress_cpu_profile, "--rest-cold-start-dump-stress-cpu-profile")
    _append_optional_flag(args, live_options.rest_cold_start_dump_stress_cpu_profile_stack, "--rest-cold-start-dump-stress-cpu-profile-stack")
    _append_optional_flag(
        args,
        live_options.rest_cold_start_dump_stress_allow_required_zero_result_searches,
        "--rest-cold-start-dump-stress-allow-required-zero-result-searches",
    )
    _append_optional_flag(
        args,
        live_options.rest_cold_start_dump_stress_skip_transfer_cleanup,
        "--rest-cold-start-dump-stress-skip-transfer-cleanup",
    )
    _append_optional_flag(args, live_options.rest_cold_start_dump_stress_skip_umdh_diffs, "--rest-cold-start-dump-stress-skip-umdh-diffs")
    if not live_options.rest_cold_start_dump_stress_cpu_profile_symbols_required:
        args.append("--no-rest-cold-start-dump-stress-cpu-profile-symbols-required")
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
    if live_options.live_wire_inputs_file:
        args.extend(["--live-wire-inputs-file", live_options.live_wire_inputs_file])
    if live_options.radarr_movie_root:
        args.extend(["--radarr-movie-root", live_options.radarr_movie_root])
    if live_options.sonarr_series_root:
        args.extend(["--sonarr-series-root", live_options.sonarr_series_root])
    if live_options.acquisition_timeout_minutes is not None:
        args.extend(["--media-acquisition-timeout-minutes", live_options.acquisition_timeout_minutes])
    if live_options.rest_search_method_override:
        args.extend(["--rest-search-method-override", live_options.rest_search_method_override])
    args.extend(["--rest-webserver-scheme", live_options.rest_webserver_scheme])
    if live_options.profile != "default":
        args.extend(["--profile", live_options.profile])
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


def invoke_amutorrent_clean_startup(
    layout: WorkspaceLayout,
    options: WorkspaceOptions,
    clean_options: AmutorrentCleanStartupOptions,
) -> None:
    """Runs the automated aMuTorrent first-run wizard integration proof."""

    _assert_test_execution_platform_supported(options)
    app_root = layout.get_app_variant(layout.test_targets.test_run_variant).path
    script_path = layout.tests_repo_root / "scripts" / "amutorrent-clean-startup.py"
    if not script_path.is_file():
        raise RuntimeError(f"Missing aMuTorrent clean-startup runner: {script_path}")

    args: list[str | Path | float] = [
        script_path,
        "--app-root",
        app_root,
        "--configuration",
        options.configuration,
        "--p2p-bind-interface-name",
        clean_options.p2p_bind_interface_name,
        "--ready-timeout-seconds",
        clean_options.ready_timeout_seconds,
        "--network-ready-timeout-seconds",
        clean_options.network_ready_timeout_seconds,
        "--search-observation-timeout-seconds",
        clean_options.search_observation_timeout_seconds,
    ]
    if clean_options.live_wire_inputs_file:
        args.extend(["--live-wire-inputs-file", clean_options.live_wire_inputs_file])
    _append_optional_flag(args, clean_options.keep_artifacts, "--keep-artifacts")

    python = get_python_invocation()
    run_native(
        python.command(args),
        label="aMuTorrent clean startup",
        cwd=layout.emule_workspace_root,
        env={"EMULE_WORKSPACE_ROOT": layout.emule_workspace_root},
    )


def invoke_amutorrent_resilience(
    layout: WorkspaceLayout,
    options: WorkspaceOptions,
    resilience_options: AmutorrentResilienceOptions,
) -> None:
    """Runs the automated aMuTorrent resilience live E2E proof."""

    _assert_test_execution_platform_supported(options)
    app_root = layout.get_app_variant(layout.test_targets.test_run_variant).path
    script_path = layout.tests_repo_root / "scripts" / "amutorrent-resilience-live.py"
    if not script_path.is_file():
        raise RuntimeError(f"Missing aMuTorrent resilience live runner: {script_path}")

    args: list[str | Path | float] = [
        script_path,
        "--app-root",
        app_root,
        "--configuration",
        options.configuration,
        "--p2p-bind-interface-name",
        resilience_options.p2p_bind_interface_name,
        "--ready-timeout-seconds",
        resilience_options.ready_timeout_seconds,
        "--network-ready-timeout-seconds",
        resilience_options.network_ready_timeout_seconds,
        "--search-observation-timeout-seconds",
        resilience_options.search_observation_timeout_seconds,
        "--reconnect-timeout-seconds",
        resilience_options.reconnect_timeout_seconds,
    ]
    if resilience_options.live_wire_inputs_file:
        args.extend(["--live-wire-inputs-file", resilience_options.live_wire_inputs_file])
    _append_optional_flag(args, resilience_options.keep_artifacts, "--keep-artifacts")

    python = get_python_invocation()
    run_native(
        python.command(args),
        label="aMuTorrent resilience live",
        cwd=layout.emule_workspace_root,
        env={"EMULE_WORKSPACE_ROOT": layout.emule_workspace_root},
    )


def _append_optional_flag(args: list, enabled: bool, flag: str) -> None:
    if enabled:
        args.append(flag)


def _assert_test_execution_platform_supported(options: WorkspaceOptions) -> None:
    if options.platform != "x64":
        raise RuntimeError("Test execution supports x64 only.")
