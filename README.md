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

eMule v0.72a dropped two dependencies (CxImage, libpng) and upgraded several others. The full list of changes in this workspace versus the `main` branch:

**Removed deps (dropped in v0.72a):**
- CxImage 7.02 — image handling replaced in eMule source
- libpng 1.5.30 — no longer needed without CxImage

**Upgraded deps:**
| Library | v0.60d | v0.72a |
|---------|--------|--------|
| eMule | v0.60d-community | v0.72a-community |
| cryptopp | 8.4.0 | 8.9.0 |
| mbedTLS | 2.28 | 4.0.0 |
| miniupnpc | 2.2.3 | 2.3.3 |
| zlib | 1.2.12 | 1.3.2 |
| id3lib | 3.9.1 | 3.9.1 (unchanged) |
| ResizableLib | — | latest master |

**Toolchain:**
- Visual Studio 2019 (v142) → Visual Studio 2022 (v143)
- ARM64 configs removed (require VS 2025 toolset v145, not yet released)

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
  003_build_MSBuild_ALL_libs.cmd
  003_build_MSBuild_ALL_libs_debug.cmd
  004_build_MSBuild_eMule.cmd
  build_MSBuild_eMule-*.cmd
```

### 2. Preflight and setup

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

Patches applied per dep:

| Dep | Patch | What it fixes |
|-----|-------|---------------|
| cryptopp | `cryptopp-CRYPTOPP_8_9_0.patch` | OutDir `Output\` subdir mismatch |
| id3lib | `id3lib-v3.9.1.patch` | zlib include path (`../zlib` → `../eMule-zlib`) |
| miniupnpc | `miniupnpc-miniupnpc_2_3_3.patch` | Full vcxproj rewrite: x64 configs, cscript PreBuildEvent, `/MT`+`/MTd` CRT, `_strnicmp` replacing deprecated `_memicmp` |
| ResizableLib | `resizablelib-master.patch` | SDK 8.1 → v143; OutDir `bin\` removed; Release\|x64 + Debug\|x64 Unicode+Static+`/MT`+`/MTd` |
| zlib | `zlib-v1.3.2.patch` | Adds `contrib/vstudio/vc/zlib.vcxproj` cmake wrapper and ignores generated `cmake-build/` noise |
| mbedtls | `mbedtls-mbedtls-4.0.0.patch` | Adds custom `mbedTLS.vcxproj` wrapper and ignores generated `visualc/VS2017` noise |
| tf-psa-crypto | `mbedtls-tf-psa-crypto-v1.0.0.patch` | Adds `threading_alt.h` and enables `MBEDTLS_THREADING_C` + `MBEDTLS_THREADING_ALT` |

### 3. Build

### Build all libraries (Release)

```
pwsh -File .\workspace.ps1 build-libs -Config Release
```

The compatibility wrapper `003_build_MSBuild_ALL_libs.cmd` still exists and delegates to the same backend.

### Build all libraries (Debug)

```
pwsh -File .\workspace.ps1 build-libs -Config Debug
```

### Build eMule

```
pwsh -File .\workspace.ps1 build-app -Config Release
```

Or open `eMule\srchybrid\emule.sln` in Visual Studio 2022 and build from the IDE.

**Output:**
- Release: `eMule\srchybrid\x64\Release\emule.exe` (~8.7 MB, static MFC)
- Debug: `eMule\srchybrid\x64\Debug\emule.exe` (~35 MB)

Individual dep build scripts are also available: `build_MSBuild_eMule-cryptopp.cmd`, `build_MSBuild_eMule-mbedtls.cmd`, etc.

---

### 4. Inspect or reset local build state

```
pwsh -File .\workspace.ps1 dep-status
pwsh -File .\workspace.ps1 clean-generated
pwsh -File .\workspace.ps1 repair
```

- `dep-status` shows the current branch, commit, patch state, and cleanliness for `eMule` and each dependency
- `clean-generated` removes generated build trees, logs, temp files, and app outputs without touching the disposable local build-branch commits
- `repair` reapplies setup and restores the selected build configuration (`Release` by default) so the workspace is immediately runnable again after `clean-generated`

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

`workspace.ps1` is the single backend for setup, env preflight, builds, IDE launch, binary launch, and packaging. The existing `.cmd` files remain as compatibility shims that call `workspace.cmd`, which in turn requires `pwsh`.

Mutating commands are serialized with a workspace lock, so concurrent `build-*`, `setup`, `repair`, `package`, and cleanup invocations wait instead of racing each other in the same tree.

Useful inspection commands:
- `pwsh -File .\workspace.ps1 env-check`
- `pwsh -File .\workspace.ps1 dep-status`
- `pwsh -File .\workspace.ps1 clean-generated`
- `pwsh -File .\workspace.ps1 repair`

### Dependency branch model

Third-party deps are not edited on detached HEAD anymore. `setup` switches each dep to a local `emule-build-v0.72a` branch, applies the matching patch if needed, and records it as a local commit. Root `.gitmodules` marks these deps with `ignore = all`, so the disposable local build branches do not spam normal root `git status` output.

### CRT policy

All dependency static libs must be compiled with `RuntimeLibrary=MultiThreaded` (`/MT`) for Release and `MultiThreadedDebug` (`/MTd`) for Debug. This matches eMule's static MFC link. Using `/MD` in any dep causes `__imp_*` linker errors at the eMule link step. All patches enforce this.

### MbedTLS 4.0

MbedTLS 4.0 removed the pre-built VS project files and restructured into 6 separate static libs under `tf-psa-crypto/`. The top-level patch adds `visualc/VS2017/mbedTLS.vcxproj` — a Utility project that builds all 6 components and combines them into a single `mbedtls.lib` via `lib.exe` in a PostBuildEvent. Because cmake generates the component vcxproj files, `workspace.ps1` still rewrites those generated files after configure so they use `/MT` and `/MTd` instead of `/MD` and `/MDd`. The source-tree threading changes now live in the dedicated `tf-psa-crypto` patch/branch rather than ad-hoc `.Replace()` calls. eMule source requires:
- `MBEDTLS_THREADING_C` + `MBEDTLS_THREADING_ALT` enabled in `psa/crypto_config.h` with `threading_alt.h` carried by the local `tf-psa-crypto` patch/branch using Windows `CRITICAL_SECTION`
- `MBEDTLS_ALLOW_PRIVATE_ACCESS` in `emule.vcxproj` preprocessor defines (for `private/sha1.h` access)

### zlib 1.3.2

zlib 1.3.2 removed `contrib/vstudio/` entirely. The patch adds a Utility vcxproj wrapper that invokes cmake to build `zlibstatic` and copies the output (`zs.lib` → `zlib.lib`). cmake must be on `PATH` — `workspace.ps1 setup` handles the one-time configure step.

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
