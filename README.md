# Build package for eMule Community

This repository provides a complete build workspace for eMule Community, making it easy to compile eMule and its pinned dependencies from source on Windows.

## Branch `v0.72a-experimental-clean`

This is the base workspace branch for the clean `v0.72a` ancestry:

- `v0.72a-experimental-clean`
- `v0.72a-bugfix-clean`
- `v0.72a-broadband-clean`
- `v0.72a-experimental-clean`

Branch policy:

- `v0.72a-build-clean` is the full-dependency base workspace for the `v0.72a` line
- `v0.72a-bugfix-clean` is its strict child and retargets the app repo to the minimal bugfix stage without changing the active dependency set
- `v0.72a-broadband-clean` is the stable child for BB-core app behavior while keeping the same workspace dependency superset
- `v0.72a-experimental-clean` is the top branch for oracle seams and other unstable changes
- legacy `v0.72a`, `v0.72a-community`, `v0.72a-broadband-dev`, and `v0.72a-oracle` remain published as frozen source branches

Supported app branch on this workspace branch:

- `v0.72a-build-clean`

Dependency policy:

- preserved third-party forks stay pinned as submodules where available
- the workspace keeps the same pinned dependency superset across all `v0.72a` clean branches
- child app stages may stop using a dep, but the dep remains present and pinned in the workspace

---

## What changed from v0.60d

### What changed from v0.60d

eMule v0.72a dropped two dependencies (CxImage, libpng) and upgraded several others. The full list of changes in this workspace versus the `main` branch:

**Removed deps (dropped in v0.72a):**
- CxImage 7.02 — image handling replaced in eMule source
- libpng 1.5.30 — no longer needed without CxImage

**Upgraded deps:**

The version columns show the upstream jump from `main` to the `irwir/eMule` v0.72a base; the last column calls out what this fork changes in the build workspace on top of that base.

| Library | v0.60d | v0.72a base | This fork here: workspace delta vs irwir |
|---------|--------|-------------|------------------------------------------|
| eMule | v0.60d-community | `irwir/eMule @ eMule_v0.72a-community` | Tracked directly in [`itlezy/eMule`](https://github.com/itlezy/eMule) on `emule-build-v0.72a-dev`; `emule.sln`, `emule.slnx`, `emule.vcxproj`, and source includes were retargeted from the old sibling/junction-style dep paths to the real workspace-root `eMule-*` submodules, with shared `WorkspaceRoot` path variables in the project |
| cryptopp | 8.4.0 | 8.9.0 | Uses upstream `weidai11/cryptopp` as a pinned submodule plus a local `emule-build-v0.72a` build branch; patch normalizes the library output path and defaults the handwritten vcxproj to `v143`/SDK `10.0` so `emule.vcxproj` can link it without extra path glue |
| mbedTLS | 2.28 | 4.0.0 | Uses upstream `Mbed-TLS/mbedtls` plus `TF-PSA-Crypto` with workspace-owned wrapper/build logic; `setup` materializes `visualc/VS2017/mbedTLS.vcxproj`, rewrites generated component projects to `/MT`/`/MTd`, and carries the threading patch on local build branches instead of leaving ad-hoc tree edits in place |
| miniupnpc | 2.2.3 | 2.3.3 | Uses upstream `miniupnp/miniupnp` as a pinned submodule plus local patch branch; patch adds x64 static configs, switches the PreBuild step to `cscript //nologo`, changes static CRT to `/MT`/`/MTd`, and fixes output layout so the workspace can build/link it consistently on VS 2022 |
| zlib | 1.2.12 | 1.3.2 | Uses upstream `madler/zlib` as a pinned submodule; because upstream 1.3.x dropped `contrib/vstudio`, `setup` materializes a workspace-owned `contrib/vstudio/vc/zlib.vcxproj` cmake wrapper and keeps the generated tree disposable/rebuildable instead of checking in a private project fork |
| id3lib | 3.9.1 | 3.9.1 (unchanged) | Still the same legacy code level, but this workspace owns it via [`itlezy/eMule-id3lib`](https://github.com/itlezy/eMule-id3lib) rather than relying on `irwir/id3lib`; patch retargets the zlib include path to `eMule-zlib` and updates the vcxproj from `v142` to `v143` |
| ResizableLib | — | latest master | Pulled from upstream `ppescher/resizablelib` as a pinned submodule and normalized for this workspace; patch moves it off the old `v141_xp`/SDK 8.1 settings, fixes output dirs, forces the x64 configs eMule actually needs (`Unicode` + static MFC / `v143`), and cleans stale layout anchors to avoid leaked entries after child windows are destroyed |

**Repository / workspace split:**

This is the higher-level difference between [`irwir/eMule` `v0.72a`](https://github.com/irwir/eMule/commits/v0.72a) and [`itlezy/eMule-build` `v0.72a`](https://github.com/itlezy/eMule-build/tree/v0.72a): the former is the application source branch, the latter is the reproducible build workspace wrapped around that source.

| Aspect | `irwir/eMule` `v0.72a` | `itlezy/eMule-build` `v0.72a` |
|--------|-------------------------|-------------------------------|
| Repo role | App-source branch for eMule Community v0.72a; the tree is essentially `srchybrid/` plus the in-tree `mbedtls/` subtree | Full Windows build workspace for that app branch, with root-level tooling, dependency pins, patches, packaging, and validation |
| What is versioned here | eMule source changes, solution/project files, and app-side fixes like the VS 2022/x64 porting and `WebSocket.cpp` updates | The whole build environment: root scripts, `workspace.ps1`, `deps.psd1`, `patches/`, packaging metadata, smoke-test automation, and submodule refs for `eMule` plus all third-party deps |
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
| id3lib | Not versioned in the repo; build files expect `..\eMule-id3lib\` beside the app tree | Pinned as root submodule `eMule-id3lib/` from [`itlezy/eMule-id3lib`](https://github.com/itlezy/eMule-id3lib) at `v3.9.1`, with the workspace patch carrying the zlib include-path retarget and `v143` update |
| miniupnpc | Not versioned in the repo; build files expect `..\eMule-miniupnp\` | Pinned as root submodule `eMule-miniupnp/` from `miniupnp/miniupnp` at `miniupnpc_2_3_3`, with a workspace patch adding x64 static configs, `cscript` prebuild handling, `/MT`/`/MTd`, and stable output paths |
| ResizableLib | Not versioned in the repo; build files expect `..\eMule-ResizableLib\` | Pinned as root submodule `eMule-ResizableLib/` from `ppescher/resizablelib` on `master`, with a workspace patch moving the project to `v143` / SDK `10.0`, forcing the x64 static-MFC settings eMule actually links against, and pruning stale layout anchors before duplicate state accumulates |
| zlib | Not versioned in the repo; build files expect `..\eMule-zlib\contrib\vstudio\vc\zlib.vcxproj` to already exist | Pinned as root submodule `eMule-zlib/` from `madler/zlib` at `v1.3.2`; because upstream no longer ships `contrib/vstudio`, `setup` materializes the workspace-owned wrapper project and generated build tree |
| Mbed TLS / TF-PSA-Crypto | The repo only carries the eMule-side helper file `mbedtls/tf-psa-crypto/include/mbedtls/threading_alt.h`; the actual build still points at an external sibling `..\eMule-mbedtls\` tree | Pinned as root submodule `eMule-mbedtls/` from `Mbed-TLS/mbedtls` at `mbedtls-4.0.0`; `setup` configures the generated VS tree, applies the TF-PSA threading patch on local build branches, and materializes the wrapper that combines the split 4.x libraries into `mbedtls.lib` |
| CxImage | Removed from the v0.72a app line; not present in the repo | Not present in the workspace either; the dependency is intentionally gone on `v0.72a` |
| libpng | Removed from the v0.72a app line; not present in the repo | Not present in the workspace either; no separate pin is needed once CxImage is gone |

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

5. **Perl** for regenerating the mbedtls Visual Studio tree during fresh setup or `repair`
   Git for Windows usually already provides this at `C:\Program Files\Git\usr\bin\perl.exe`, and `workspace.ps1` will auto-detect it.

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
  eMule-id3lib/           ← itlezy/eMule-id3lib @ v3.9.1
  eMule-miniupnp/         ← miniupnp/miniupnp @ miniupnpc_2_3_3
  eMule-ResizableLib/     ← ppescher/resizablelib @ master
  eMule-zlib/             ← madler/zlib @ v1.3.2
  eMule-mbedtls/          ← Mbed-TLS/mbedtls @ mbedtls-4.0.0
  patches/                ← VS2022 porting patches for each dep
  00-setup-and-build-release.cmd
  10-build-libs-release.cmd
  11-build-libs-debug.cmd
  20-build-emule-*.cmd
  30-run-emule-*.cmd
  40-package-release.cmd
  41-clean-release-config.cmd
  scripts\10-open-*.cmd
  scripts\20-open-project-*.cmd
  scripts\30-build-*-release.cmd
  scripts\31-build-*-debug.cmd
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

The setup flow does five things:

1. **Creates or reuses local dep build branches** named `emule-build-v0.72a`, then records the workspace patch as a local commit in each third-party dep. The upstream-pinned checkout remains the superproject baseline; the local branch is the developer build state.

2. **Configures the mbedtls cmake build** — generates the VS project files under `eMule-mbedtls\visualc\VS2017\`.

3. **Normalizes generated mbedtls vcxproj files** — rewrites their CRT setting from `/MD`+`/MDd` to `/MT`+`/MTd` after cmake generation.

4. **Keeps mbedtls threading support in source control** — `tf-psa-crypto` gets its own local build commit with `threading_alt.h` and `MBEDTLS_THREADING_C` + `MBEDTLS_THREADING_ALT` enabled.

5. **Configures the zlib cmake build** — runs cmake once with the correct generator and `/MT` runtime library flag. Only needed on first run; idempotent thereafter.

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
| id3lib | `id3lib-v3.9.1.patch` | zlib include path (`../zlib` → `../eMule-zlib`) |
| miniupnpc | `miniupnpc-miniupnpc_2_3_3.patch` | Full vcxproj rewrite: x64 configs, cscript PreBuildEvent, `/MT`+`/MTd` CRT, `_strnicmp` replacing deprecated `_memicmp` |
| ResizableLib | `resizablelib-master.patch` | SDK 8.1 → v143; OutDir `bin\` removed; Release\|x64 + Debug\|x64 Unicode+Static+`/MT`+`/MTd`; stale `CResizableLayout` anchors are purged before reinsertion |
| zlib | `zlib-v1.3.2.patch` | Ignores generated `cmake-build/` noise; `setup` materializes the workspace-owned `contrib/vstudio/vc/zlib.vcxproj` wrapper |
| mbedtls | `mbedtls-mbedtls-4.0.0.patch` | Ignores generated `visualc/VS2017` noise; `setup` materializes the workspace-owned `mbedTLS.vcxproj` wrapper |
| tf-psa-crypto | `mbedtls-tf-psa-crypto-v1.0.0.patch` | Adds `threading_alt.h` and enables `MBEDTLS_THREADING_C` + `MBEDTLS_THREADING_ALT` |

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

### CRT policy

All dependency static libs must be compiled with `RuntimeLibrary=MultiThreaded` (`/MT`) for Release and `MultiThreadedDebug` (`/MTd`) for Debug. This matches eMule's static MFC link. Using `/MD` in any dep causes `__imp_*` linker errors at the eMule link step. All patches enforce this.

### MbedTLS 4.0

MbedTLS 4.0 removed the pre-built VS project files and restructured into 6 separate static libs under `tf-psa-crypto/`. `workspace.ps1 setup` materializes the workspace-owned `visualc/VS2017/mbedTLS.vcxproj` wrapper, which builds all 6 components and combines them into a single `mbedtls.lib` via `lib.exe` in a PostBuildEvent. Because cmake generates the component vcxproj files, `workspace.ps1` rewrites those generated files after configure so they use `/MT` and `/MTd` instead of `/MD` and `/MDd`. The source-tree threading changes now live in the dedicated `tf-psa-crypto` patch/branch rather than ad-hoc `.Replace()` calls. eMule source requires:
- `MBEDTLS_THREADING_C` + `MBEDTLS_THREADING_ALT` enabled in `psa/crypto_config.h` with `threading_alt.h` carried by the local `tf-psa-crypto` patch/branch using Windows `CRITICAL_SECTION`
- `MBEDTLS_ALLOW_PRIVATE_ACCESS` in `emule.vcxproj` preprocessor defines (for `private/sha1.h` access)

### zlib 1.3.2

zlib 1.3.2 removed `contrib/vstudio/` entirely. `workspace.ps1 setup` materializes a workspace-owned Utility vcxproj wrapper that invokes cmake to build `zlibstatic` and copies the output (`zs.lib` → `zlib.lib`). cmake must be on `PATH` — `workspace.ps1 setup` handles the one-time configure step.

### WebSocket.cpp (Unicode-safe cert/key loading)

eMule's WebSocket implementation was updated to load TLS certificates and private keys using MFC `CFile` (which uses `CreateFileW` internally) rather than MbedTLS's `parse_file` functions. This avoids ANSI code page conversion issues for paths containing non-ASCII characters.

### bcrypt.lib

MbedTLS 4.0 calls `BCryptGenRandom()` from `bcrypt.dll`. This import library must be listed explicitly in `emule.vcxproj` `AdditionalDependencies` for both Debug and Release configurations. It is not pulled in automatically by static MFC linking.

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
