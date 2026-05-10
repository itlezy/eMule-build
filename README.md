# eMule-build

`eMule-build` is the canonical build and test orchestration layer for the
workspace rooted at `EMULE_WORKSPACE_ROOT`.

`eMulebb-setup` owns workspace materialization and generated workspace topology.
Once the workspace exists, this repo is responsible for:

- dependency builds under `repos\third_party`
- app builds for the canonical 0.72a app worktrees
- shared test builds from `repos\eMule-build-tests`
- parity, coverage, and live-diff execution against the canonical app variants

`python -m emule_workspace` is the authoritative orchestration surface.

## Purpose

Use the supported `emule_workspace` command after `eMulebb-setup` has
materialized the workspace. The package owns typed command parsing, workspace
topology loading, locking, subprocess routing, build/test execution, live-test
wrapping, and release packaging.

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
- `workspaces\v0.72a\app\eMule-v0.72a-community`
- `workspaces\v0.72a\app\eMule-v0.72a-broadband`
- `workspaces\v0.72a\app\eMule-v0.72a-tracing-harness-community`

`repos\eMule` is not a normal development checkout. `eMulebb-setup` owns it as
the canonical app anchor, and it is expected to stay detached at
`origin/main`. Active app development belongs in the managed worktrees under
`workspaces\v0.72a\app\...`, especially `eMule-main` for the mainline branch.

Canonical managed app variants:

- `main`
- `release/v0.72a-community`
- `release/v0.72a-broadband`
- `tracing-harness/v0.72a-community`

Branch roles, release intent, and baseline rules are owned by
`EMULE_WORKSPACE_ROOT\repos\eMule-tooling\docs\WORKSPACE_POLICY.md`.

The active app layout and workspace repo paths are topology-driven from the
generated workspace manifest at `workspaces\v0.72a\deps.psd1`, with
build-specific settings kept in this repo's `deps.psd1`. Test, coverage, and
live-diff flows resolve their app roots from configured variant names rather
than duplicating hardcoded worktree paths in the script.

For the full workspace topology and materialization behavior, use
`eMulebb-setup\README.md`.

## Supported Commands

Python-first commands:

```powershell
python -m emule_workspace env-check --workspace-root <workspace-root>
python -m emule_workspace dep-status --workspace-root <workspace-root>
python -m emule_workspace validate --workspace-root <workspace-root>
python -m emule_workspace build libs --workspace-root <workspace-root>
python -m emule_workspace build app --workspace-root <workspace-root>
python -m emule_workspace build tests --workspace-root <workspace-root>
python -m emule_workspace build all --workspace-root <workspace-root>
python -m emule_workspace test python --workspace-root <workspace-root>
python -m emule_workspace test all --workspace-root <workspace-root>
python -m emule_workspace test live-diff --workspace-root <workspace-root>
python -m emule_workspace test live-e2e --workspace-root <workspace-root>
python -m emule_workspace test amutorrent-session --workspace-root <workspace-root>
python -m emule_workspace test community-core-coverage --workspace-root <workspace-root>
python -m emule_workspace full --workspace-root <workspace-root>
python -m emule_workspace package-release --workspace-root <workspace-root>
```

Command behavior:

- `help` prints supported commands and common options.
- `env-check` verifies the core toolchain discovery for Git, Visual Studio, and MSBuild.
- `dep-status` reports branch and worktree status for the dependency repos and canonical app worktrees that exist locally.
- `validate` verifies required workspace paths, canonical app worktree presence, branch alignment, required test helper scripts, modified tracked-file editorconfig compliance, and the shared static policy audits from `eMule-tooling\ci`.
- The Python `package-release` command may reanchor a clean `repos\eMule`
  checkout back to detached `origin/main` before building package artifacts.
- `build libs` builds the shared dependency set for the selected `--config` and `--platform`.
- `build libs` includes the CMake-built `libpcpnatpmp` static library, and the current `main` app build now links it for the PCP/NAT-PMP NAT-mapping backend.
- `build app` builds all canonical app variants for the selected `--config` and `--platform`.
- `build tests` builds the shared test harness against the configured build variant.
- `test python` runs the fast pytest harness suite from `eMule-build-tests`; use `--path`, `--expression`, and `--quiet` to narrow the pytest selection.
- `test all` runs parity tests, native coverage, and live diff using the configured test target variants.
- `test live-diff` runs parity and divergence comparison directly against any two configured app variants.
- `test live-e2e` runs the aggregate UI, REST API, and live-wire E2E suite from `eMule-build-tests`.
- `test amutorrent-session` starts a disposable interactive aMuTorrent session against eMule BB REST and leaves both processes running for operator testing.
- `test community-core-coverage` runs community-core coverage checks with live REST E2E coverage enabled.
- `build all` runs `build libs`, `build app`, and `build tests`.
- `full` runs `build all`, then `test all`, then prints a workspace summary.
- `package-release` builds the main Release app, language DLLs, release ZIP, and release manifest.

All top-level `emule_workspace` commands are serialized per workspace root.
This single-owner workspace lock is intentional. It prevents overlapping
`env-check`, build, test, and live-diff commands from trampling shared state,
logs, and outputs in the same workspace.

If another command already owns the workspace lock, the next command fails fast
with a clear owner message instead of running concurrently against the same
workspace. When commands are launched back-to-back, the second command may need
to wait briefly for the first command's lock window to close fully before it
can start.

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

- `test all --platform ARM64` fails with a clear unsupported-platform error

ARM64 remains available for dependency and app builds, but x64 is still the
primary stabilized acceptance path for the end-to-end canonical workflow.

Live-diff examples:

- `live-diff -Config Debug -Platform x64` uses the configured defaults (`main` vs `community`)
- `live-diff -Config Debug -Platform x64 -TestRunVariant main -BaselineVariant community` compares main against the parity/regression baseline
- `live-diff -Config Release -Platform x64 -TestRunVariant broadband -BaselineVariant community` compares broadband behavior against the parity/regression baseline

Live E2E examples:

- `live-e2e -Config Release -Platform x64` runs the full maintained UI, REST API, and live-wire lane, including the default six-term server/Kad release search matrix and one paused live search-result download trigger
- `live-e2e -Config Release -Platform x64 -RestDownloadTriggerCount 0` disables the REST live download trigger for diagnosis
- `live-e2e -Config Release -Platform x64 -LiveSuite preference-ui -LiveSuite rest-api` runs a focused subset
- `live-e2e -Config Release -Platform x64 -SkipLiveSeedRefresh` reuses the checked-in live seed files for offline diagnosis

Interactive aMuTorrent example:

- `amutorrent-session -Config Debug -Platform x64 -LiveNetwork` launches Debug x64 eMule BB with a disposable profile, starts aMuTorrent against the eMule BB REST API, opens the aMuTorrent URL, and writes a `stop-session.ps1` helper into the session report directory.

Python test examples:

- `python-tests` runs the default fast pytest collection
- `python-tests -PythonTestPath tests/python/test_auto_browse_live.py -PythonTestExpression pending -PythonTestQuiet` runs one focused pytest expression

## Validation And Test Model

`validate` is intended to catch canonical workspace drift before a longer build:

- missing `repos` or `workspaces` roots
- missing dependency repos
- missing canonical app worktrees
- stale canonical app anchor state in `repos\eMule`
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

The setup/build contract is intentionally narrow:

- `eMulebb-setup` owns workspace topology, managed app worktree creation, and full `sync` reconciliation.
- `eMule-build` assumes that topology exists and only self-heals the clean setup-owned `repos\eMule` anchor when validation needs it to match current `origin/main`.

The test flows use the manifest-configured app variants:

- test build target: `community`
- test run target: `main`
- live-diff baseline target: `community`

The tracing harness variant is part of the canonical buildable app set, but it
is not the default test-run or baseline target unless explicitly selected.

`build-tests` honors the selected `-Config` value for both `x64` and `ARM64`.
`test` honors the selected `-Config` value, but requires `-Platform x64`.

## Implementation Notes

- ARM64 Crypto++ overrides are generated under `workspaces\<workspace>\state\`
  instead of the workspace root.
- Tool-install fallbacks are allowed where they are genuinely about tool
  discovery, such as standard Perl or Visual Studio install locations.
- Workspace-specific hardcoded local paths are not part of the supported model.
- Legacy pre-canonical branch names are not part of the supported workflow.
