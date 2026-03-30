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
| eMule | v0.60d-community | `irwir/eMule @ eMule_v0.72a-community` | Tracked directly in [`itlezy/eMule`](https://github.com/itlezy/eMule) on `emule-build-v0.72a-dev`; `emule.sln`, `emule.slnx`, `emule.vcxproj`, and source includes were retargeted from the old sibling/junction-style dep paths to the real workspace-root `eMule-*` submodules, with shared `WorkspaceRoot` path variables in the project |
| cryptopp | 8.4.0 | 8.9.0 | Uses upstream `weidai11/cryptopp` as a pinned submodule plus a local `emule-build-v0.72a` build branch; patch normalizes the library output path and defaults the handwritten vcxproj to `v143`/SDK `10.0` so `emule.vcxproj` can link it without extra path glue |
| miniupnpc | 2.2.3 | 2.3.3 | Uses upstream `miniupnp/miniupnp` as a pinned submodule plus local patch branch; patch adds x64 static configs, switches the PreBuild step to `cscript //nologo`, changes static CRT to `/MT`/`/MTd`, and fixes output layout so the workspace can build/link it consistently on VS 2022 |
| zlib | 1.2.12 | 1.3.2 | Uses upstream `madler/zlib` as a pinned submodule; because upstream 1.3.x dropped `contrib/vstudio`, `setup` materializes a workspace-owned `contrib/vstudio/vc/zlib.vcxproj` cmake wrapper and keeps the generated tree disposable/rebuildable instead of checking in a private project fork |
| ResizableLib | — | latest master | Pulled from upstream `ppescher/resizablelib` as a pinned submodule and normalized for this workspace; patch moves it off the old `v141_xp`/SDK 8.1 settings, fixes output dirs, forces the x64 configs eMule actually needs (`Unicode` + static MFC / `v143`), and cleans stale layout anchors to avoid leaked entries after child windows are destroyed |

**Repository / workspace split:**

This is the higher-level difference between [`irwir/eMule` `v0.72a`](https://github.com/irwir/eMule/commits/v0.72a) and [`itlezy/eMule-build` `v0.72a`](https://github.com/itlezy/eMule-build/tree/v0.72a): the former is the application source branch, the latter is the reproducible build workspace wrapped around that source.

| Aspect | `irwir/eMule` `v0.72a` | `itlezy/eMule-build` `v0.72a` |
|--------|-------------------------|-------------------------------|
| Repo role | App-source branch for eMule Community v0.72a; the tree is essentially `srchybrid/` plus the project/solution files needed for this fork | Full Windows build workspace for that app branch, with root-level tooling, dependency pins, patches, packaging, and validation |
| What is versioned here | eMule source changes, solution/project files, and app-side fixes like the VS 2022/x64 porting and feature removals | The whole build environment: root scripts, `workspace.ps1`, `deps.psd1`, `patches/`, packaging metadata, smoke-test automation, and submodule refs for `eMule` plus the remaining third-party deps |
| Dependency ownership model | Not the place where the full dependency fleet is pinned and maintained as separate repos | Deps are pinned as workspace-root git submodules (`eMule-*`), with local `emule-build-v0.72a` build branches used to carry workspace-only changes cleanly |
| Build-path assumptions | Contains the app-side project changes needed to reference the workspace-root deps | Owns the actual root layout and enforces it: shared manifest paths, submodule locations, generated wrapper projects, and the commands that prepare the tree into a buildable state |
| Setup work | You still need an external workspace around the app repo to fetch, patch, configure, and build every dependency consistently | `workspace.ps1 setup`/`repair` create or reuse dep build branches, apply recorded patches, configure generated trees, and restore a known-good state from a fresh clone |
| Dependency patching | App repo contains only the eMule-side adjustments that must live with the application sources | Third-party dep changes are kept as explicit patch files in `patches/` and recorded as local commits on the dep build branches instead of being hidden as manual edits inside each checkout |
| Build orchestration | No root manifest-backed orchestration layer for env checks, dep status, cleanup, validation, or packaging | `workspace.ps1` is the supported backend for `env-check`, `dep-status`, `validate`, `setup`, `repair`, `build-*`, `run-binary`, `package`, and cleanup |
| Reproducibility | Source branch only | Reproducible workspace state: pinned submodule SHAs, centralized metadata in `deps.psd1`, serialized mutating commands via a workspace lock, and smoke-test coverage for clone -> repair -> validate -> package |
| Deliverable | Source tree / Visual Studio project side of the port | Source tree plus a documented path to built artifacts and the packaged Release zip under `dist\` |

**Dependency handling vs app repo:**

This table answers a narrower question than the one above: for each dependency used by the v0.72a build, what does the plain app repo carry, and what does this workspace add on top?

| Dependency | `irwir/eMule` `v0.72a` | `itlezy/eMule-build` `v0.72a` |
|------------|-------------------------|-------------------------------|
| Crypto++ | Not versioned in the repo; `emule.sln` / `emule.vcxproj` expect an external sibling checkout at `..\eMule-cryptopp\` | Pinned as root submodule `eMule-cryptopp/` from `weidai11/cryptopp` at `CRYPTOPP_8_9_0`, with a local build-branch patch for VS 2022 output/toolset normalization |
| miniupnpc | Not versioned in the repo; build files expect `..\eMule-miniupnp\` | Pinned as root submodule `eMule-miniupnp/` from `miniupnp/miniupnp` at `miniupnpc_2_3_3`, with a workspace patch adding x64 static configs, `cscript` prebuild handling, `/MT`/`/MTd`, and stable output paths |
| ResizableLib | Not versioned in the repo; build files expect `..\eMule-ResizableLib\` | Pinned as root submodule `eMule-ResizableLib/` from `ppescher/resizablelib` on `master`, with a workspace patch moving the project to `v143` / SDK `10.0`, forcing the x64 static-MFC settings eMule actually links against, and pruning stale layout anchors before duplicate state accumulates |
| zlib | Not versioned in the repo; build files expect `..\eMule-zlib\contrib\vstudio\vc\zlib.vcxproj` to already exist | Pinned as root submodule `eMule-zlib/` from `madler/zlib` at `v1.3.2`; because upstream no longer ships `contrib/vstudio`, `setup` materializes the workspace-owned wrapper project and generated build tree |
| CxImage | Removed from the v0.72a app line; not present in the repo | Not present in the workspace either; the dependency is intentionally gone on `v0.72a` |
| libpng | Removed from the v0.72a app line; not present in the repo | Not present in the workspace either; no separate pin is needed once CxImage is gone |
| id3lib | Initially present in the v0.72a source for MP3 tag parsing | Dropped from both the eMule source and workspace after the feature was removed |
| mbedtls | Initially present in the v0.72a source for TLS (SMTP, web services) | Dropped from both the eMule source and workspace after SMTP and web services were removed |

**Toolchain:**
- Visual Studio 2019 (v142) → Visual Studio 2022 (v143)
- ARM64 configs removed (require VS 2025 toolset v145, not yet released)
- Supported handwritten VC projects are normalized to `PlatformToolset=v143` and `WindowsTargetPlatformVersion=10.0`

**Architecture:**
- Deps are now **git submodules** at fixed tags instead of runtime-cloned directories
- `emule.sln`, `emule.slnx`, `emule.vcxproj`, and the affected source includes were retargeted to the real workspace-root dependency paths
- eMule itself is tracked directly in the `eMule` fork; third-party deps use disposable local build branches created by setup
- Dep patches are stored as `git diff` patch files in `patches/` and recorded as local commits on each dep's `emule-build-v0.72a` branch
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
  tests/                  ← shared test submodule (doctest-based)
  patches/                ← VS2022 porting patches for each dep
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

1. **Creates or reuses local dep build branches** named `emule-build-v0.72a`, then records the workspace patch as a local commit in each third-party dep. The upstream-pinned checkout remains the superproject baseline; the local branch is the developer build state.

2. **Configures the zlib cmake build** — runs cmake once with the correct generator and `/MT` runtime library flag. Only needed on first run; idempotent thereafter.

`env-check` now also verifies that `git user.name` and `git user.email` are configured, because setup records local build commits in dependency branches.

For a single consolidated health check after setup or after a build, use:

```
pwsh -File .\workspace.ps1 validate
```

`validate` runs the same environment and workspace checks, shows dependency state, verifies expected outputs for the selected configuration, and for `Release` also inspects the package zip when present.

Patches applied per dep:

| Dep | Patch | What it fixes |
|-----|-------|---------------|
| cryptopp | `cryptopp-CRYPTOPP_8_9_0.patch` | OutDir `Output\` subdir mismatch |
| miniupnpc | `miniupnpc-miniupnpc_2_3_3.patch` | Full vcxproj rewrite: x64 configs, cscript PreBuildEvent, `/MT`+`/MTd` CRT, `_strnicmp` replacing deprecated `_memicmp` |
| ResizableLib | `resizablelib-master.patch` | SDK 8.1 → v143; OutDir `bin\` removed; Release\|x64 + Debug\|x64 Unicode+Static+`/MT`+`/MTd`; stale `CResizableLayout` anchors are purged before reinsertion |
| zlib | `zlib-v1.3.2.patch` | Ignores generated `cmake-build/` noise; `setup` materializes the workspace-owned `contrib/vstudio/vc/zlib.vcxproj` wrapper |

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

The workspace includes a shared test submodule (`tests/`) with a standalone doctest-based test project that builds against the local `eMule` checkout.

#### Build and run tests

```
.\26-build-emule-tests-debug.cmd
.\36-run-emule-tests-debug.cmd
```

The test project (`tests\emule-tests.vcxproj`) is a console application that uses the [doctest](https://github.com/doctest/doctest) single-header framework and links against eMule source directly. It is built and run independently from the main `emule.sln`.

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

This runs `tests\scripts\run-live-diff.ps1`, which:
1. Builds the test project in both the dev (`eMulebb`) and oracle (`eMulebb-oracle`) workspaces
2. Runs parity and divergence suites in each, capturing doctest XML output
3. Compares pass/fail results and writes a summary to `tests\reports\live-diff-summary.txt`
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
- `dep-status` shows the current branch, commit, patch state, and cleanliness for `eMule` and each dependency
- `clean-generated` removes generated build trees, logs, temp files, and app outputs without touching the disposable local build-branch commits
- `repair` reapplies setup and restores the selected build configuration (`Release` by default) so the workspace is immediately runnable again after `clean-generated`

For a disposable end-to-end regression check of the script surface itself, run:

```
pwsh -File .\scripts\smoke-test.ps1
```

That script clones the current repo into a temporary workspace, runs `clean-generated`, `repair`, `validate`, `package`, and a final `validate`, then deletes the disposable clone unless `-KeepWorkspace` is used.

---

## Maintenance Workflow

This section is only for maintaining the build workspace itself.

Third-party dependency branches are disposable local build state:
- they exist only to build eMule
- they are not treated as long-lived forks
- if they drift or get messy, prefer `clean-generated`, `repair`, or recreating them from the tracked patch files

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

Third-party deps are not edited on detached HEAD anymore. `setup` switches each dep to a local `emule-build-v0.72a` branch, applies the matching patch if needed, and records it as a local commit. Root `.gitmodules` marks these deps with `ignore = all`, so the disposable local build branches do not spam normal root `git status` output.

### Test submodule

The `tests/` directory is a git submodule containing the shared test project. Unlike the `eMule-*` third-party dependency submodules, it is not a build dependency — it is a workspace-level test asset that compiles against the local `eMule` checkout.

The test project uses C++17 and the doctest single-header framework. Tests are organized into parity and divergence suites to support live comparison against the oracle (pre-refactor) workspace. Test scripts, XML reports, and the live-diff summary are all kept inside the submodule.

### Upstream dependency tracking

`scripts\check-dep-updates.ps1` queries upstream repositories for each pinned dependency and reports whether newer versions are available. This is an informational check only — it does not modify the workspace.

### CRT policy

All dependency static libs must be compiled with `RuntimeLibrary=MultiThreaded` (`/MT`) for Release and `MultiThreadedDebug` (`/MTd`) for Debug. This matches eMule's static MFC link. Using `/MD` in any dep causes `__imp_*` linker errors at the eMule link step. All patches enforce this.

### zlib 1.3.2

zlib 1.3.2 removed `contrib/vstudio/` entirely. `workspace.ps1 setup` materializes a workspace-owned Utility vcxproj wrapper that invokes cmake to build `zlibstatic` and copies the output (`zs.lib` → `zlib.lib`). cmake must be on `PATH` — `workspace.ps1 setup` handles the one-time configure step.

---

## Updating a dependency

To bump a dep to a newer version:

1. Update the submodule commit: `cd eMule-depname && git fetch && git checkout NEW_TAG`
2. Recreate or update the local `emule-build-v0.72a` branch changes for that dep
3. Regenerate the patch from the dep build branch: `git diff HEAD~1..HEAD > ../patches/depname-NEW_TAG.patch`
4. Update `.gitmodules` if the upstream tracking metadata changes
5. Commit the workspace metadata from the root repo

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
