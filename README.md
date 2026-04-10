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

`eMulebb-setup` is the source of truth for workspace materialization and the full
layout contract. This repo assumes that canonical workspace already exists and
uses the standard `EMULE_WORKSPACE_ROOT\repos\...` plus
`EMULE_WORKSPACE_ROOT\workspaces\v0.72a\...` layout.

In practice this repo needs:

- `repos\eMule`
- `repos\eMule-build`
- `repos\eMule-build-tests`
- `repos\third_party\...`
- `workspaces\v0.72a\app\eMule-main`
- `workspaces\v0.72a\app\eMule-v0.72a-oracle`
- `workspaces\v0.72a\app\eMule-v0.72a-build`
- `workspaces\v0.72a\app\eMule-v0.72a-bugfix`
- `workspaces\v0.72a\app\eMule-v0.72a-tracing`
- `workspaces\v0.72a\app\eMule-v0.72a-tracing-harness`

Canonical managed app variants:

- `main`
- `oracle/v0.72a-build`
- `release/v0.72a-build`
- `release/v0.72a-bugfix`
- `tracing/v0.72a`
- `tracing-harness/v0.72a`

The active app layout is topology-driven from the generated workspace manifest
at `workspaces\v0.72a\deps.psd1`, with build-specific settings kept in this
repo's `deps.psd1`. Test, coverage, and live-diff flows resolve their app roots
from the configured variant names rather than duplicating hardcoded worktree
paths in the script.

`oracle/v0.72a-build` is a special-purpose seam-enabled oracle branch derived
from `release/v0.72a-build`. It is built like the other canonical app variants,
but it is not a normal feature-development line. `tracing/v0.72a` is the
observability-only derivative of oracle, and `tracing-harness/v0.72a` is the
behavior-changing experimental harness layer derived from tracing.

For the full workspace topology and materialization behavior, use
`eMulebb-setup\README.md`.

## Supported Commands

```powershell
pwsh -File .\workspace.ps1 env-check   -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 dep-status  -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 validate    -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 build-libs  -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 build-app   -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 build-tests -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 test        -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 live-diff   -EmuleWorkspaceRoot <workspace-root>
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
- `validate` verifies required workspace paths, canonical app worktree presence, branch alignment, required test helper scripts, modified tracked-file editorconfig compliance, and the shared static policy audits from `eMule-tooling\ci`.
- `build-libs` builds the shared dependency set for the selected `-Config` and `-Platform`.
- `build-app` builds all canonical app variants for the selected `-Config` and `-Platform`.
- `build-tests` builds the shared test harness against the configured build variant.
- `test` runs parity tests, native coverage, and live diff using the configured test target variants.
- `live-diff` runs parity and divergence comparison directly against any two configured app variants.
- `build-all` runs `build-libs`, `build-app`, and `build-tests`.
- `full` runs `build-all`, then `test`, then prints a workspace summary.

All top-level `workspace.ps1` commands are serialized per workspace root. If
another command already owns the workspace lock, the next command fails fast
with a clear owner message instead of running concurrently against the same
workspace.

## Build Scope

Dependencies and app builds honor the selected invocation parameters:

- `-Config Debug|Release`
- `-Platform x64|ARM64`
- `-BuildOutputMode Full|Warnings|ErrorsOnly`
- `-Clean`
- `Win32` is not part of the active workspace build matrix

Examples:

- `build-app -Config Debug -Platform x64` builds only `Debug|x64`
- `build-libs -Config Release -Platform ARM64` builds only `Release|ARM64`
- `build-all` and `full` use the same selected target instead of expanding to a hidden multi-target matrix

Build commands default to a quiet filtered console view plus a short step recap.
Use `-BuildOutputMode Full` when you want raw MSBuild output for troubleshooting.
Use `-Clean` when you explicitly want rebuild/cleanup behavior; normal runs stay incremental.
Build runs write text logs, MSBuild binary logs, and a machine-readable recap under
`workspaces\<workspace>\state\build-logs\`.

Shared test builds support `x64` and `ARM64`. Test execution remains `x64`
only:

- `test -Platform ARM64` fails with a clear unsupported-platform error

ARM64 remains available for dependency and app builds, but x64 is still the
primary stabilized acceptance path for the end-to-end canonical workflow.

Live-diff examples:

- `live-diff -Config Debug -Platform x64` uses the manifest defaults (`main` vs `oracle`)
- `live-diff -Config Debug -Platform x64 -DevVariant bugfix -OracleVariant build` compares the frozen release lines directly
- `live-diff -Config Release -Platform x64 -DevVariant bugfix -OracleVariant oracle` compares bugfix behavior against the seam-enabled build-derived oracle

## Validation And Test Model

`validate` is intended to catch canonical workspace drift before a longer build:

- missing `repos` or `workspaces` roots
- missing dependency repos
- missing canonical app worktrees
- app worktrees checked out on the wrong branches
- dependency repos not aligned with their active local `origin/HEAD` pins
- active documentation hardcoding machine-specific absolute paths
- active workflow docs/scripts drifting back to `.sln` / `.slnx` entrypoints
- active warning suppressions drifting beyond the approved narrow third-party exceptions
- modified tracked text files drifting from repo `.editorconfig` / `.gitattributes`
- missing shared test helper scripts

Tracked-file cleanliness is intentionally a separate explicit audit via
`repos\eMule-tooling\ci\check-clean-worktree.ps1`, so in-progress feature work
does not get blocked by routine `validate`.

The test flows use the manifest-configured app variants:

- test build target: `main`
- coverage target: `main`
- live-diff oracle target: `oracle`

The tracing variants are part of the canonical buildable app set, but they are
not the default coverage or oracle targets unless explicitly selected.

`build-tests` honors the selected `-Config` value for both `x64` and `ARM64`.
`test` honors the selected `-Config` value, but requires `-Platform x64`.

## Implementation Notes

- ARM64 Crypto++ overrides are generated under `workspaces\<workspace>\state\`
  instead of the workspace root.
- Tool-install fallbacks are allowed where they are genuinely about tool
  discovery, such as standard Perl or Visual Studio install locations.
- Workspace-specific hardcoded local paths are not part of the supported model.
- Legacy pre-canonical branch names are not part of the supported workflow.
