from __future__ import annotations

from pathlib import Path

from emule_workspace.config import LiveE2eOptions, WorkspaceOptions
from emule_workspace.layout import AppVariant, TestTargets as LayoutTestTargets, WorkspaceLayout
from emule_workspace import test_runs


def make_layout(tmp_path: Path) -> WorkspaceLayout:
    """Builds a minimal layout with the live E2E runner script present."""

    emule_workspace_root = tmp_path
    workspace_root = emule_workspace_root / "workspaces" / "v0.72a"
    tests_repo_root = emule_workspace_root / "repos" / "eMule-build-tests"
    app_root = workspace_root / "app" / "eMule-main"
    (tests_repo_root / "scripts").mkdir(parents=True)
    (tests_repo_root / "scripts" / "run-live-e2e-suite.py").write_text("# test runner\n", encoding="utf-8")
    app_root.mkdir(parents=True)
    return WorkspaceLayout(
        emule_workspace_root=emule_workspace_root,
        workspace_name="v0.72a",
        workspace_root=workspace_root,
        build_repo_root=emule_workspace_root / "repos" / "eMule-build",
        tests_repo_root=tests_repo_root,
        tooling_repo_root=emule_workspace_root / "repos" / "eMule-tooling",
        seed_repo_path=emule_workspace_root / "repos" / "eMule",
        seed_repo_branch="main",
        dependencies=(),
        app_variants=(AppVariant(name="main", path=app_root, branch="main"),),
        test_targets=LayoutTestTargets(test_build_variant="main", test_run_variant="main", baseline_variant="community"),
        toolset_override_variable="",
    )


def option_values(command: list[str], option: str) -> list[str]:
    """Returns values that immediately follow an option in a captured command."""

    return [command[index + 1] for index, value in enumerate(command[:-1]) if value == option]


def test_live_e2e_forwards_cold_stress_cpu_profile_options(tmp_path: Path, monkeypatch) -> None:
    captured: dict[str, object] = {}

    def fake_run_native(command, *, label, cwd, env=None, allow_failure=False):
        captured["command"] = list(command)
        captured["label"] = label
        captured["cwd"] = cwd
        captured["env"] = dict(env or {})

    layout = make_layout(tmp_path)
    monkeypatch.setattr(test_runs, "run_native", fake_run_native)

    test_runs.invoke_live_e2e_suite(
        layout,
        WorkspaceOptions(workspace_root=tmp_path, platform="x64"),
        LiveE2eOptions(
            suites=("rest-cold-start-dump-stress",),
            rest_cold_start_dump_stress_enable_umdh=True,
            rest_cold_start_dump_stress_cpu_profile=True,
            rest_cold_start_dump_stress_cpu_profile_max_file_mb=64,
            rest_cold_start_dump_stress_cpu_profile_symbols_required=False,
            rest_cold_start_dump_stress_max_missing_download_triggers=1,
            rest_cold_start_dump_stress_search_observation_timeout_seconds=12.0,
        ),
    )

    command = captured["command"]
    assert isinstance(command, list)
    assert "--rest-cold-start-dump-stress-enable-umdh" in command
    assert "--rest-cold-start-dump-stress-cpu-profile" in command
    assert option_values(command, "--rest-cold-start-dump-stress-cpu-profile-max-file-mb") == ["64"]
    assert option_values(command, "--rest-cold-start-dump-stress-max-missing-download-triggers") == ["1"]
    assert option_values(command, "--rest-cold-start-dump-stress-search-observation-timeout-seconds") == ["12.0"]
    assert "--no-rest-cold-start-dump-stress-cpu-profile-symbols-required" in command
    assert "--rest-cold-start-dump-stress-skip-dumps" not in command
    assert captured["env"] == {"EMULE_WORKSPACE_ROOT": layout.emule_workspace_root}
