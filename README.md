# Build package for eMule Community

This repository provides a complete build workspace for eMule Community, making it easy to compile eMule and all its dependencies from source on Windows.

Two build tracks are maintained:

| Branch | eMule version | Visual Studio | Status |
|--------|--------------|---------------|--------|
| `main` | v0.60d | VS 2019 (v142) | stable |
| `v0.72a` | v0.72a | VS 2022 (v143) | stable |

---

## Branch `v0.72a` — eMule-ootb v0.72a on VS 2022

This branch upgrades the build workspace to target [irwir/eMule](https://github.com/irwir/eMule) tag `eMule_v0.72a-community`.

### What changed from v0.60d

eMule v0.72a dropped four dependencies (CxImage, libpng, id3lib, mbedtls) and upgraded several others. The full list of changes in this workspace versus the `main` branch:

**Removed deps (dropped in v0.72a):**
- CxImage 7.02 — image handling replaced in eMule source
- libpng 1.5.30 — no longer needed without CxImage
- id3lib — initially ported, then dropped from the eMule source (MP3 tag handling removed)
- mbedtls — initially ported for TLS support, then dropped after SMTP and web services were removed from the eMule source

**Upgraded deps:**

The version columns show the upstream jump from `main` to the `irwir/eMule` v0.72a base; the last column calls out what this fork changes in the build workspace on top of that base.

| Library | v0.60d | v0.72a base | This fork here: workspace delta vs irwir |
|---------|--------|-------------|------------------------------------------|
| eMule | v0.60d-community | `irwir/eMule @ eMule_v0.72a-community` | Tracked directly in [`itlezy/eMule`](https://github.com/itlezy/eMule) on `v0.72a-broadband-dev`; `emule.sln`, `emule.slnx`, `emule.vcxproj`, and source includes were retargeted from the old sibling/junction-style dep paths to the real workspace-root `eMule-*` submodules, with shared `WorkspaceRoot` path variables in the project |
| cryptopp | 8.4.0 | 8.9.0 | Tracked as forked submodule [`itlezy/eMule-cryptopp`](https://github.com/itlezy/eMule-cryptopp) on `emule-build-v0.72a`; the branch carries the VS 2022 + ARM64 project normalization needed by this workspace |
| miniupnpc | 2.2.3 | 2.3.3 | Tracked as forked submodule [`itlezy/eMule-miniupnp`](https://github.com/itlezy/eMule-miniupnp) on `emule-build-v0.72a`; the branch carries the static CRT, `cscript //nologo`, x64, and ARM64 project fixes needed by the app |
| zlib | 1.2.12 | 1.3.2 | Tracked as forked submodule [`itlezy/eMule-zlib`](https://github.com/itlezy/eMule-zlib) on `emule-build-v0.72a`; the fork carries the committed `contrib/vstudio/vc/zlib.vcxproj` cmake wrapper because upstream 1.3.x dropped `contrib/vstudio` |
| ResizableLib | — | latest master | Tracked as forked submodule [`itlezy/eMule-ResizableLib`](https://github.com/itlezy/eMule-ResizableLib) on `emule-build-v0.72a`; the branch carries the `v143`/SDK `10.0`, x64, and ARM64 MFC project fixes required by the workspace |

**Repository / workspace split:**

This is the higher-level difference between [`irwir/eMule` `v0.72a`](https://github.com/irwir/eMule/commits/v0.72a) and [`itlezy/eMule-build` `v0.72a`](https://github.com/itlezy/eMule-build/tree/v0.72a): the former is the application source branch, the latter is the reproducible build workspace wrapped around that source.

| Aspect | `irwir/eMule` `v0.72a` | `itlezy/eMule-build` `v0.72a` |
|--------|-------------------------|-------------------------------|
| Repo role | App-source branch for eMule Community v0.72a; the tree is essentially `srchybrid/` plus the project/solution files needed for this fork | Full Windows build workspace for that app branch, with root-level tooling, dependency pins, packaging, and validation |
| What is versioned here | eMule source changes, solution/project files, and app-side fixes like the VS 2022/x64/ARM64 porting and feature removals | The whole build environment: root scripts, `workspace.ps1`, `deps.psd1`, packaging metadata, smoke-test automation, and submodule refs for `eMule` plus the remaining third-party deps |
| Dependency ownership model | Not the place where the full dependency fleet is pinned and maintained as separate repos | Deps are pinned as workspace-root git submodules (`eMule-*`), and their workspace-specific changes live in the fork branches that are pinned by gitlink |
| Build-path assumptions | Contains the app-side project changes needed to reference the workspace-root deps | Owns the actual root layout and enforces it: shared manifest paths, submodule locations, dependency build conventions, and the commands that prepare the tree into a buildable state |
| Setup work | You still need an external workspace around the app repo to fetch, configure, and build every dependency consistently | `workspace.ps1 setup`/`repair` sync submodules, ensure the published dependency branches are checked out, configure generated trees, and restore a known-good state from a fresh clone |
| Dependency patching | App repo contains only the eMule-side adjustments that must live with the application sources | Third-party dep changes are versioned directly in the dependency forks and pinned by submodule commit instead of replayed from patch files |
| Build orchestration | No root manifest-backed orchestration layer for env checks, dep status, cleanup, validation, or packaging | `workspace.ps1` is the supported backend for `env-check`, `dep-status`, `validate`, `setup`, `repair`, `build-*`, `run-binary`, `package`, and cleanup |
| Reproducibility | Source branch only | Reproducible workspace state: pinned submodule SHAs, centralized metadata in `deps.psd1`, serialized mutating commands via a workspace lock, and smoke-test coverage for clone -> repair -> validate -> package |
| Deliverable | Source tree / Visual Studio project side of the port | Source tree plus a documented path to built artifacts and the packaged Release zip under `dist\` |

**Dependency handling vs app repo:**

This table answers a narrower question than the one above: for each dependency used by the v0.72a build, what does the plain app repo carry, and what does this workspace add on top?

| Dependency | `irwir/eMule` `v0.72a` | `itlezy/eMule-build` `v0.72a` |
|------------|-------------------------|-------------------------------|
| Crypto++ | Not versioned in the repo; `emule.sln` / `emule.vcxproj` expect an external sibling checkout at `..\eMule-cryptopp\` | Pinned as root submodule `eMule-cryptopp/` from `itlezy/eMule-cryptopp` on `emule-build-v0.72a`, with the VS 2022/x64/ARM64 project fixes versioned in the fork |
| miniupnpc | Not versioned in the repo; build files expect `..\eMule-miniupnp\` | Pinned as root submodule `eMule-miniupnp/` from `itlezy/eMule-miniupnp` on `emule-build-v0.72a`, with the static CRT, `cscript`, x64, and ARM64 fixes versioned in the fork |
| ResizableLib | Not versioned in the repo; build files expect `..\eMule-ResizableLib\` | Pinned as root submodule `eMule-ResizableLib/` from `itlezy/eMule-ResizableLib` on `emule-build-v0.72a`, with the `v143`/SDK `10.0`, x64, and ARM64 MFC fixes versioned in the fork |
| zlib | Not versioned in the repo; build files expect `..\eMule-zlib\contrib\vstudio\vc\zlib.vcxproj` to already exist | Pinned as root submodule `eMule-zlib/` from `itlezy/eMule-zlib` on `emule-build-v0.72a`; the fork commits the compatibility wrapper project and `setup` configures the generated build tree |
| CxImage | Removed from the v0.72a app line; not present in the repo | Not present in the workspace either; the dependency is intentionally gone on `v0.72a` |
| libpng | Removed from the v0.72a app line; not present in the repo | Not present in the workspace either; no separate pin is needed once CxImage is gone |
| id3lib | Initially present in the v0.72a source for MP3 tag parsing | Dropped from both the eMule source and workspace after the feature was removed |
| mbedtls | Initially present in the v0.72a source for TLS (SMTP, web services) | Dropped from both the eMule source and workspace after SMTP and web services were removed |

**Toolchain:**
- Visual Studio 2019 (v142) → Visual Studio 2022 (v143)
- ARM64 builds supported on Visual Studio 2022 (v143) when ARM64 MFC/ATL and Windows SDK components are installed
- Supported handwritten VC projects are normalized to `PlatformToolset=v143` and `WindowsTargetPlatformVersion=10.0`

**Architecture:**
- Deps are now **git submodules** at fixed tags instead of runtime-cloned directories
- `emule.sln`, `emule.slnx`, `emule.vcxproj`, and the affected source includes were retargeted to the real workspace-root dependency paths
- eMule itself is tracked directly in the `eMule` fork; third-party deps are tracked in dedicated dependency forks on `emule-build-v0.72a`
- Third-party dependency changes are versioned in those forks and pinned by submodule commit
- Shared dependency metadata is centralized in `deps.psd1`
- zlib 1.3.2 removed its VS project files upstream — built via cmake instead

---

## Prerequisites

1. **Visual Studio 2022** (Professional or Community) with:
   - Desktop development with C++ workload
   - MSVC v143 toolset
   - MFC and ATL for latest build tools
   - Windows SDK 10.0 (any recent version)

2. **PowerShell 7 (`pwsh`)** on `PATH`

3. **Git** on `PATH` (includes git submodule support)

4. **CMake 3.15+** on `PATH` — required for zlib build
   Download from [cmake.org](https://cmake.org/download/) or install via Visual Studio Installer

SDK/toolset policy for this workspace:
- Use Visual Studio 2022 `v143`
- Use `WindowsTargetPlatformVersion=10.0` in committed project files
- Let each machine resolve that to an installed Windows 10/11 SDK instead of pinning an exact SDK build number in source control

This workspace intentionally targets one known-good compiler configuration only: Visual Studio 2022 with the `v143` toolset. `PlatformToolset` is not treated as a user-configurable manifest setting.

---

## Daily Workflow

### 1. Clone the workspace

```
git clone --recurse-submodules https://github.com/itlezy/eMule-build.git
cd eMule-build
git checkout v0.72a
git submodule update --init --recursive
```

This gives you the following layout:

```
eMule-build/
  eMule/                  ← eMule source (itlezy/eMule @ v0.72a)
  eMule-cryptopp/         ← weidai11/cryptopp @ CRYPTOPP_8_9_0
  eMule-miniupnp/         ← miniupnp/miniupnp @ miniupnpc_2_3_3
  eMule-ResizableLib/     ← ppescher/resizablelib @ master
  eMule-zlib/             ← madler/zlib @ v1.3.2
  ../eMule-build-tests/   ← shared optional test repo (doctest-based)
  00-setup-and-build-release.cmd
  10-build-libs-release.cmd
  11-build-libs-debug.cmd
  20-build-emule-*.cmd
  26-build-emule-tests-debug.cmd
  30-run-emule-*.cmd
  36-run-emule-tests-debug.cmd
  37-run-emule-tests-live-diff.cmd
  40-package-release.cmd
  41-clean-release-config.cmd
  scripts\10-open-*.cmd
  scripts\20-open-project-*.cmd
  scripts\30-build-*-release.cmd
  scripts\31-build-*-debug.cmd
  scripts\check-dep-updates.ps1
```

### 2. Preflight and setup

Fastest path from a fresh clone:

```
.\00-setup-and-build-release.cmd
```

That helper initializes submodules, runs `setup`, builds the Release libraries and app, and creates the Release package.

```
pwsh -File .\workspace.ps1 env-check
pwsh -File .\workspace.ps1 dep-status
pwsh -File .\workspace.ps1 setup
```

The setup flow does two things:

1. **Checks out the published dep build branches** named `emule-build-v0.72a` from the dependency forks. The pinned gitlink remains the workspace baseline, and setup moves each dep onto the matching local branch when needed.

2. **Configures the zlib cmake build** — runs cmake once with the correct generator and `/MT` runtime library flag. Only needed on first run; idempotent thereafter.

`env-check` still verifies that `git user.name` and `git user.email` are configured because workspace maintenance uses git-backed operations and submodule synchronization.

For a single consolidated health check after setup or after a build, use:

```
pwsh -File .\workspace.ps1 validate
```

`validate` runs the same environment and workspace checks, shows dependency state, verifies expected outputs for the selected configuration, and for `Release` also inspects the package zip when present.

Dependency fork responsibilities:

| Dep | Fork branch carries |
|-----|---------------------|
| cryptopp | VS 2022/x64/ARM64 project normalization and Windows ARM64 source fixes |
| miniupnpc | Static CRT, `cscript` PreBuildEvent handling, stable output paths, and x64/ARM64 project configs |
| ResizableLib | `v143`/SDK `10.0`, x64/ARM64 static-MFC configs, and layout-anchor cleanup |
| zlib | Generated-output ignore rules; the workspace still owns the generated cmake wrapper project |

### 3. Build

### Build all libraries (Release)

```
pwsh -File .\workspace.ps1 build-libs -Config Release
```

Convenience wrapper: `.\10-build-libs-release.cmd`

### Build all libraries (Debug)

```
pwsh -File .\workspace.ps1 build-libs -Config Debug
```

### Build eMule

```
pwsh -File .\workspace.ps1 build-app -Config Release
```

Convenience wrappers:
- `.\20-build-emule-release.cmd`
- `.\21-build-emule-debug.cmd`
- `.\22-build-emule-release-incremental.cmd`
- `.\23-build-emule-debug-incremental.cmd`
- `.\24-build-emule-release-incremental-run-and-package.cmd`
- `.\25-build-emule-debug-incremental-and-run.cmd`

Or open `eMule\srchybrid\emule.sln` in Visual Studio 2022 and build from the IDE.

**Output:**
- Release: `eMule\srchybrid\x64\Release\emule.exe` (~8.7 MB, static MFC)
- Debug: `eMule\srchybrid\x64\Debug\emule.exe` (~35 MB)

Root `.cmd` files are now limited to the main clone/setup/build/run/package flows. Dependency build wrappers and Visual Studio open helpers live under `scripts\`, but `workspace.ps1` remains the supported backend.

### 3b. Package the Release build

```
pwsh -File .\workspace.ps1 package
```

Convenience wrapper: `.\40-package-release.cmd`

By default on `v0.72a`, the package zip is written under `dist\`. The location and archive name are workspace variables in `deps.psd1` under `Workspace.Package.Release`.

The package flow also builds `srchybrid\lang\lang.sln` in `Dynamic|<Platform>` and stages the generated translation DLLs under `lang\` beside `emule.exe` in the final zip.

The zip now contains a top-level release folder plus build metadata:

```
dist\eMule0.72a-broadband_x64-snapshot.zip
  eMule0.72a-broadband_x64/
    emule.exe
    LICENSE
    BUILD-INFO.txt
```

---

### 3c. Testing

The workspace uses the shared sibling repo `..\eMule-build-tests` for the standalone doctest-based test project that builds against the local `eMule` checkout.

#### Build and run tests

```
.\26-build-emule-tests-debug.cmd
.\36-run-emule-tests-debug.cmd
```

The test project (`..\eMule-build-tests\emule-tests.vcxproj`) is a console application that uses the [doctest](https://github.com/doctest/doctest) single-header framework and links against the selected workspace's `eMule` source directly. It is built and run independently from the main `emule.sln`.

#### Test suites

Tests are organized into two suites:

| Suite | Purpose |
|-------|---------|
| `parity` | Cases that must pass in both the dev and oracle (pre-refactor) workspaces |
| `divergence` | Cases that are expected to pass on dev and fail on the pre-refactor oracle |

Current coverage includes protocol guard validation and circular buffer (`CRing`) behavior.

#### Live dev-vs-oracle comparison

The live-diff harness builds and runs the test suites in two side-by-side workspaces (dev and oracle), then compares the results:

```
.\37-run-emule-tests-live-diff.cmd
```

This runs `..\eMule-build-tests\scripts\run-live-diff.ps1`, which:
1. Builds the test project in both the dev (`eMule-build`) and oracle (`eMule-build-oracle`) workspaces
2. Runs parity and divergence suites in each, capturing doctest XML output
3. Compares pass/fail results and writes a summary to `..\eMule-build-tests\reports\live-diff-summary.txt`
4. Validates that parity cases pass in both, and divergence cases show the expected dev-pass / oracle-fail pattern

---

### 4. Inspect or reset local build state

```
pwsh -File .\workspace.ps1 validate
pwsh -File .\workspace.ps1 dep-status
pwsh -File .\workspace.ps1 clean-generated
pwsh -File .\workspace.ps1 repair
```

- `validate` is the canonical one-shot health check for the workspace
- `dep-status` shows the current branch, commit, and cleanliness for `eMule` and each dependency
- `clean-generated` removes generated build trees, logs, temp files, and app outputs without rewriting the pinned dependency forks
- `repair` reapplies setup and restores the selected build configuration (`Release` by default) so the workspace is immediately runnable again after `clean-generated`

For a disposable end-to-end regression check of the script surface itself, run:

```
pwsh -File .\scripts\smoke-test.ps1
```

That script clones the current repo into a temporary workspace, runs `clean-generated`, `repair`, `validate`, `package`, and a final `validate`, then deletes the disposable clone unless `-KeepWorkspace` is used.

---

## Maintenance Workflow

This section is only for maintaining the build workspace itself.

Third-party dependency branches are long-lived fork state:
- they are published in the `itlezy/eMule-*` dependency forks
- the parent workspace pins exact SHAs from those forks
- if they drift locally, reset them to the pinned fork state instead of regenerating patches

---

## Architecture notes

### Flat submodule layout without junctions

Deps stay at workspace root and the build files now point there directly. No junctions or symlinks are required in the supported workflow.

### Tooling entrypoint

`workspace.ps1` is the single supported backend for setup, env preflight, validation, builds, IDE launch, binary launch, and packaging. The existing `.cmd` files remain only as compatibility shims for older habits and should not be treated as separate build implementations.

Mutating commands are serialized with a workspace lock, so concurrent `build-*`, `setup`, `repair`, `package`, and cleanup invocations wait instead of racing each other in the same tree.

Useful inspection commands:
- `pwsh -File .\workspace.ps1 env-check`
- `pwsh -File .\workspace.ps1 validate`
- `pwsh -File .\workspace.ps1 dep-status`
- `pwsh -File .\workspace.ps1 clean-generated`
- `pwsh -File .\workspace.ps1 repair`

Build and packaging logs are written to timestamped per-run subdirectories under `logs\`, which avoids stale-file ambiguity between successive runs.

Package layout, package destination, generated-project configure readiness, and cleanup targets are all manifest-backed in `deps.psd1` rather than spread across `workspace.ps1`.

### Dependency branch model

Third-party deps are not edited on detached HEAD anymore. `setup` switches each dep to the published `emule-build-v0.72a` branch from its fork when needed. Root `.gitmodules` marks these deps with `ignore = all`, so normal day-to-day work in the parent repo stays focused on the workspace itself.

### Shared Test Repo

The `..\eMule-build-tests` sibling repository contains the shared test project. Unlike the `eMule-*` third-party dependency submodules, it is not a build dependency and is not embedded inside each workspace anymore. It is a workspace-level test asset that compiles against whichever local `eMule` checkout the wrapper scripts target.

The test project uses C++17 and the doctest single-header framework. Tests are organized into parity and divergence suites to support live comparison against the oracle workspace. Test scripts, XML reports, and the live-diff summary all live in the shared `eMule-build-tests` repo.

### Upstream dependency tracking

`scripts\check-dep-updates.ps1` queries upstream repositories for each pinned dependency and reports whether newer versions are available. This is an informational check only — it does not modify the workspace.

### CRT policy

All dependency static libs must be compiled with `RuntimeLibrary=MultiThreaded` (`/MT`) for Release and `MultiThreadedDebug` (`/MTd`) for Debug. This matches eMule's static MFC link. Using `/MD` in any dep causes `__imp_*` linker errors at the eMule link step. The dependency fork branches enforce this.

### zlib 1.3.2

zlib 1.3.2 removed `contrib/vstudio/` entirely. The `eMule-zlib` fork therefore commits a Utility vcxproj wrapper at `contrib\vstudio\vc\zlib.vcxproj` that invokes cmake to build `zlibstatic` and copies the output (`zs.lib` → `zlib.lib`). cmake must be on `PATH` — `workspace.ps1 setup` handles the one-time configure step.

---

## Updating a dependency

To bump a dep to a newer version:

1. Update the dependency fork branch with the required project/source changes and push `emule-build-v0.72a`
2. Update the submodule in the parent workspace to the new fork commit SHA
3. Update `.gitmodules` only if the fork location or tracking metadata changes
4. Commit the workspace metadata from the root repo

---

## Validated build environment

| Component | Version |
|-----------|---------|
| OS | Windows 10 x64 |
| Visual Studio | 2022 Professional |
| Toolset | v143 |
| Windows SDK | 10.0.26100.0 |
| CMake | 3.x |
| Result (Release) | `emule.exe` 8.7 MB |
| Result (Debug) | `emule.exe` 35 MB |
