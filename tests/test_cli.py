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
