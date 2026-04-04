# eMule-build `v0.60d-experimental-clean`

This branch is the `experimental-clean` child workspace for the `eMule` `v0.60d` four-stage app stack.

Supported app branches:
- `v0.60d-build-clean`
- `v0.60d-bugfix-clean`
- `v0.60d-broadband-clean`
- `v0.60d-experimental-clean`

Legacy note:
- The legacy workspace remains on branch `v0.60d`
- That branch still targets `v0.60d-build`, `v0.60d-dev`, and `v0.60d-oracle`
- Older clean residues `v0.60d-dev-clean` and `v0.60d-oracle-clean` may remain published for reference, but they are no longer the supported lineage

Clean workspace family:
- `v0.60d-build-clean` is the frozen base workspace branch for the `v0.60d` clean line
- `v0.60d-bugfix-clean` is the shared correctness-only child of `v0.60d-build-clean`
- `v0.60d-broadband-clean` is the stable broadband child of `v0.60d-bugfix-clean`
- `v0.60d-experimental-clean` is the parity and investigation child of `v0.60d-broadband-clean`
- New `v0.60d` line changes should only land on `v0.60d-experimental-clean` for parity-test work
- If an experimental-side fix proves shared, promote it downward first and then restack descendants

Status:
- The `v0.60d` line is otherwise frozen
- `v0.60d-clean` is superseded by the layered family above

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
workspace.cmd bootstrap -Config Release
workspace.cmd validate
workspace.cmd build-libs -Config Release
workspace.cmd build-app -Config Release
workspace.cmd build-all -Config Release
```

Direct PowerShell:

```powershell
pwsh -File .\workspace.ps1 env-check
pwsh -File .\workspace.ps1 bootstrap -Config Release
pwsh -File .\workspace.ps1 build-all -Config Debug
```

## Fresh start

```cmd
workspace.cmd bootstrap -Config Release
```

`bootstrap` does the following:
- validates Visual Studio, Git, PowerShell, and Python
- clones or refreshes dependency repos
- clones or refreshes the clean build seed app repo
- repairs and creates `eMule-v0.60d-*-clean` worktrees when needed
- creates `libs` and `libs_debug`
- ensures Python helper packages are installed
- builds shared libraries
- builds all present valid app variants

`setup` remains available for repo/bootstrap preparation without building. It does the following:
- creates `libs` and `libs_debug`
- clones or refreshes dependency repos
- clones or refreshes the clean build seed app repo
- repairs and creates additional `eMule-v0.60d-*-clean` worktrees when possible
- ensures Python helper dependencies are installed
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

Manual rewrite:

```cmd
workspace.cmd normalize
```

Manual check:

```cmd
workspace.cmd normalize-check
```

## Notes

- `002_create_symlinks.cmd` is deprecated. The supported path now uses direct dependency paths through `v0.60d-workspace.props`.
- The clean experimental seed repo lives at `eMule-v0.60d-experimental-clean`. Additional variants live as `eMule-v0.60d-build-clean`, `eMule-v0.60d-bugfix-clean`, and `eMule-v0.60d-broadband-clean` worktrees under this workspace when created by `setup` or `bootstrap`.
- The legacy layout remains available on branch `v0.60d` for the pre-restack app family.
- The clean workspace branches follow the same ancestry rule as the app repo: `build-clean` base, `bugfix-clean` child, `broadband-clean` child of `bugfix-clean`, and `experimental-clean` child of `broadband-clean`.
- The current build flow is x64-focused. The workspace command surface accepts `ARM64` for project-readiness work, but the dependency/project cleanup is still in progress.
