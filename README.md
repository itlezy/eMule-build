# eMule-build

`eMule-build` is the canonical build and test orchestration layer for the
workspace rooted at `EMULE_WORKSPACE_ROOT`.

`eMulebb-setup` owns workspace materialization. Once the workspace exists, this
repo is responsible for:

- dependency builds under `repos\third_party`
- app builds for the canonical 0.72a app worktrees
- shared test builds from `repos\eMule-build-tests`
- parity, coverage, and live-diff execution against the canonical app variants

`workspace.ps1` and `workspace.cmd` are the only supported operational
entrypoints.

## Workspace Assumption

```text
EMULE_WORKSPACE_ROOT\
  repos\
    eMule\
    eMule-build\
    eMule-build-tests\
    eMule-tooling\
    eMule-remote\
    third_party\
      eMule-cryptopp\
      eMule-id3lib\
      eMule-mbedtls\
      eMule-miniupnp\
      eMule-ResizableLib\
      eMule-zlib\
  workspaces\
    v0.72a\
      app\
        eMule-main\
        eMule-v0.72a-build\
        eMule-v0.72a-bugfix\
      state\
```

`eMulebb-setup` is the source of truth for workspace materialization and the full
layout contract. This repo assumes that canonical workspace already exists.

Canonical app branches:

- `main`
- `release/v0.72a-build`
- `release/v0.72a-bugfix`

The active app layout is manifest-driven from `deps.psd1`. Test, coverage, and
live-diff flows resolve their app roots from the configured variant names rather
than duplicating hardcoded worktree paths in the script.

## Supported Commands

```powershell
pwsh -File .\workspace.ps1 env-check   -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 dep-status  -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 validate    -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 build-libs  -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 build-app   -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 build-tests -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 test        -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 build-all   -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 full        -EmuleWorkspaceRoot <workspace-root>
```

From `cmd.exe`:

```cmd
workspace.cmd build-app -EmuleWorkspaceRoot <workspace-root>
```

Command behavior:

- `env-check` verifies the core toolchain discovery for Git, Visual Studio, and MSBuild.
- `dep-status` reports branch and worktree status for the dependency repos and canonical app worktrees that exist locally.
- `validate` verifies required workspace paths, canonical app worktree presence, branch alignment, and required test helper scripts.
- `build-libs` builds the shared dependency set for the selected `-Config` and `-Platform`.
- `build-app` builds all canonical app variants for the selected `-Config` and `-Platform`.
- `build-tests` builds the shared test harness against the configured build variant.
- `test` runs parity tests, native coverage, and live diff using the configured test target variants.
- `build-all` runs `build-libs`, `build-app`, and `build-tests`.
- `full` runs `build-all`, then `test`, then prints a workspace summary.

## Build Scope

Dependencies and app builds honor the selected invocation parameters:

- `-Config Debug|Release`
- `-Platform x64|ARM64`

Examples:

- `build-app -Config Debug -Platform x64` builds only `Debug|x64`
- `build-libs -Config Release -Platform ARM64` builds only `Release|ARM64`
- `build-all` and `full` use the same selected target instead of expanding to a hidden multi-target matrix

Shared test builds and test execution currently support `x64` only:

- `build-tests -Platform ARM64` fails with a clear unsupported-platform error
- `test -Platform ARM64` fails with a clear unsupported-platform error

ARM64 remains available for dependency and app builds, but x64 is still the
primary stabilized acceptance path for the end-to-end canonical workflow.

## Validation And Test Model

`validate` is intended to catch canonical workspace drift before a longer build:

- missing `repos` or `workspaces` roots
- missing dependency repos
- missing canonical app worktrees
- app worktrees checked out on the wrong branches
- missing shared test helper scripts

The test flows use the manifest-configured app variants:

- test build target: `bugfix`
- coverage target: `bugfix`
- live-diff oracle target: `build`

`build-tests` and `test` honor the selected `-Config` value, but require
`-Platform x64`.

## Implementation Notes

- ARM64 Crypto++ overrides are generated under `workspaces\<workspace>\state\`
  instead of the workspace root.
- Tool-install fallbacks are allowed where they are genuinely about tool
  discovery, such as standard Perl or Visual Studio install locations.
- Workspace-specific hardcoded local paths are not part of the supported model.
- Legacy pre-canonical branch names are not part of the supported workflow.
