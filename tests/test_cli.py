from __future__ import annotations

from pathlib import Path

from click.testing import CliRunner

from emule_workspace import cli


def test_cli_requires_workspace_root() -> None:
    runner = CliRunner()

    result = runner.invoke(cli.main, ["env-check"], env={"EMULE_WORKSPACE_ROOT": ""})

    assert result.exit_code != 0
    assert "EMULE_WORKSPACE_ROOT or --workspace-root is required" in result.output


def test_build_tests_help_exposes_clean_architecture_command() -> None:
    runner = CliRunner()

    result = runner.invoke(cli.main, ["build", "tests", "--help"])

    assert result.exit_code == 0
    assert "--test-run-variant" in result.output
    assert "--build-output-mode" in result.output


def test_build_app_help_exposes_variant_selection() -> None:
    runner = CliRunner()

    result = runner.invoke(cli.main, ["build", "app", "--help"])

    assert result.exit_code == 0
    assert "--variant" in result.output
    assert "--clean" in result.output


def test_build_libs_help_exposes_clean_option() -> None:
    runner = CliRunner()

    result = runner.invoke(cli.main, ["build", "libs", "--help"])

    assert result.exit_code == 0
    assert "--clean" in result.output


def test_python_test_help_exposes_pytest_options() -> None:
    runner = CliRunner()

    result = runner.invoke(cli.main, ["test", "python", "--help"])

    assert result.exit_code == 0
    assert "--path" in result.output
    assert "--expression" in result.output


def test_test_live_e2e_help_exposes_live_options() -> None:
    runner = CliRunner()

    result = runner.invoke(cli.main, ["test", "live-e2e", "--help"])

    assert result.exit_code == 0
    assert "--suite" in result.output
    assert "--p2p-bind-interface-name" in result.output


def test_build_all_help_exposes_composed_build_options() -> None:
    runner = CliRunner()

    result = runner.invoke(cli.main, ["build", "all", "--help"])

    assert result.exit_code == 0
    assert "--variant" in result.output
    assert "--test-run-variant" in result.output


def test_dep_status_help_is_available() -> None:
    runner = CliRunner()

    result = runner.invoke(cli.main, ["dep-status", "--help"])

    assert result.exit_code == 0
    assert "Report dependency" in result.output


def test_package_release_help_exposes_release_version() -> None:
    runner = CliRunner()

    result = runner.invoke(cli.main, ["package-release", "--help"])

    assert result.exit_code == 0
    assert "--release-version" in result.output


def test_materialize_help_exposes_bootstrap_options() -> None:
    runner = CliRunner()

    result = runner.invoke(cli.main, ["materialize", "--help"])

    assert result.exit_code == 0
    assert "--artifacts-seed-root" in result.output


def test_sync_help_exposes_bootstrap_options() -> None:
    runner = CliRunner()

    result = runner.invoke(cli.main, ["sync", "--help"])

    assert result.exit_code == 0
    assert "--workspace-root" in result.output


def test_setup_status_help_is_available() -> None:
    runner = CliRunner()

    result = runner.invoke(cli.main, ["status", "--help"])

    assert result.exit_code == 0
    assert "setup-managed" in result.output


def test_dep_updates_help_is_available() -> None:
    runner = CliRunner()

    result = runner.invoke(cli.main, ["dep-updates", "--help"])

    assert result.exit_code == 0
    assert "third-party" in result.output


def test_compare_help_is_available() -> None:
    runner = CliRunner()

    result = runner.invoke(cli.main, ["compare", "--help"])

    assert result.exit_code == 0
    assert "WinMerge" in result.output
