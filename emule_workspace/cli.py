"""Click command surface for eMule workspace orchestration."""

from __future__ import annotations

from collections.abc import Callable
from functools import wraps
from typing import Any, TypeVar

import click

from .build_tests import invoke_build_tests
from .config import (
    BuildTestsOptions,
    PythonTestOptions,
    WorkspaceOptions,
    resolve_workspace_options,
)
from .layout import load_layout
from .locks import WorkspaceLock
from .python_tests import invoke_python_tests
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


@click.group(context_settings={"help_option_names": ["-h", "--help"]})
def main() -> None:
    """Build, validate, test, and package an eMule BB workspace."""


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


@main.group()
def build() -> None:
    """Build workspace targets."""


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


@main.command("env-check")
@_common_options
def env_check(*, workspace_options: WorkspaceOptions, layout) -> None:
    """Verify basic tool discovery and manifest loading."""

    from .validation import env_check as run_env_check

    _locked("env-check", lambda **kwargs: run_env_check(kwargs["layout"]))(
        workspace_options=workspace_options,
        layout=layout,
    )
