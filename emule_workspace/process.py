"""Subprocess and tool-resolution helpers for workspace commands."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence


@dataclass(frozen=True)
class PythonInvocation:
    """Resolved Python executable and launcher prefix."""

    executable: Path
    prefix: tuple[str, ...] = ()

    def command(self, args: Sequence[str | os.PathLike[str]]) -> list[str]:
        """Returns a complete command line using this Python launcher."""

        return [str(self.executable), *self.prefix, *[str(arg) for arg in args]]


def find_tool(names: Sequence[str]) -> Path | None:
    """Returns the first executable found on PATH for one of the supplied names."""

    for name in names:
        resolved = shutil.which(name)
        if resolved:
            return Path(resolved).resolve()
    return None


def get_python_invocation() -> PythonInvocation:
    """Resolves a Python 3 invocation matching the legacy workspace behavior."""

    python = find_tool(("python.exe", "python"))
    if python is not None:
        return PythonInvocation(executable=python)
    py = find_tool(("py.exe", "py"))
    if py is not None:
        return PythonInvocation(executable=py, prefix=("-3",))
    raise RuntimeError("Python 3 was not found on PATH.")


def run_native(
    command: Sequence[str | os.PathLike[str]],
    *,
    label: str,
    cwd: Path,
    env: Mapping[str, str] | None = None,
    allow_failure: bool = False,
) -> subprocess.CompletedProcess[str]:
    """Runs a native command and raises with a concise label on failure."""

    merged_env = os.environ.copy()
    if env:
        merged_env.update({key: str(value) for key, value in env.items()})

    completed = subprocess.run(
        [str(part) for part in command],
        cwd=str(cwd),
        env=merged_env,
        text=True,
        check=False,
    )
    if completed.returncode != 0 and not allow_failure:
        raise RuntimeError(f"{label} failed with exit code {completed.returncode}.")
    return completed


def run_captured(
    command: Sequence[str | os.PathLike[str]],
    *,
    label: str,
    cwd: Path,
) -> str:
    """Runs a command and returns stdout, raising with stderr on failure."""

    completed = subprocess.run(
        [str(part) for part in command],
        cwd=str(cwd),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        tail = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(f"{label} failed with exit code {completed.returncode}.\n{tail}")
    return completed.stdout


def current_python_module_command(module_name: str, args: Sequence[str]) -> list[str]:
    """Returns a command that invokes a module with the current Python runtime."""

    return [sys.executable, "-m", module_name, *args]
