# eMule-build `v0.60d`

This branch is now the unified build workspace for the `eMule` `v0.60d-*` family.

Supported app branches:
- `v0.60d-build`
- `v0.60d-dev`
- `v0.60d-oracle`

The workspace keeps shared dependency repos and can keep multiple eMule worktrees side by side under this root.

## Requirements

- Visual Studio 2022 with C++ tools and MSBuild
- PowerShell 7 on `PATH`
- Git on `PATH`
- Python on `PATH`

Optional toolset override:
- `EMULE_V060_PLATFORM_TOOLSET`
- Default is `v143` when `incl_VCVARS64.cmd` is used
- Use it only when you intentionally need to override the checked-in project toolset

## Main commands

Batch wrapper:

```cmd
workspace.cmd env-check
workspace.cmd setup
workspace.cmd validate
workspace.cmd build-libs -Config Release
workspace.cmd build-app -Config Release
workspace.cmd build-all -Config Release
workspace.cmd normalize
```

Direct PowerShell:

```powershell
pwsh -File .\workspace.ps1 env-check
pwsh -File .\workspace.ps1 setup
pwsh -File .\workspace.ps1 build-all -Config Debug
```

## Fresh start

```cmd
001_clone_git_repos.cmd
workspace.cmd setup
workspace.cmd build-all -Config Release
```

`setup` does the following:
- creates `libs` and `libs_debug`
- ensures Python normalizer dependencies are installed
- creates additional `eMule-v0.60d-*` worktrees when possible
- validates the known app branch layout

## Legacy wrappers

These remain available and now forward into `workspace.cmd`:
- `00-setup-and-build-release.cmd`
- `003_build_MSBuild_ALL_libs.cmd`
- `003_build_MSBuild_ALL_libs_debug.cmd`
- `004_build_MSBuild_eMule.cmd`
- `build_MSBuild_eMule*.cmd`

## Normalization

The workspace includes `scripts/source-normalizer.py`, adapted from the existing helper script you pointed to.

Normalization policy:
- UTF-8 without BOM by default
- Windows-centric line endings
- conservative whitespace cleanup

Dependencies are installed from:

```text
requirements-normalizer.txt
```

Run a one-time rewrite:

```cmd
workspace.cmd normalize
```

Check only:

```cmd
workspace.cmd normalize-check
```

## Notes

- `002_create_symlinks.cmd` is deprecated. The supported path now uses direct dependency paths through `v0.60d-workspace.props`.
- The active in-tree `eMule` checkout is still supported. Additional variants live as `eMule-v0.60d-build` and `eMule-v0.60d-dev` worktrees under this workspace when created by `setup`.
- The current build flow is x64-focused. The workspace command surface accepts `ARM64` for project-readiness work, but the dependency/project cleanup is still in progress.
