# eMule Community v0.72a Build Workspace

This repo is the Windows build workspace for the `v0.72a` eMule line. It owns the app worktrees, the dependency forks, the generated-project wrappers, validation, packaging, and the command surface used to rebuild the tree in a repeatable way.

## Branch Layout

- `bb/v0.72a/build`: canonical build baseline derived from `community-0.72`
- `bb/v0.72a/test`: seam and test-surface child branch
- `bb/v0.72a/bugfix`: canonical bugfix child branch

Rules for `build`:

- keep app source as close to `community-0.72` as possible
- keep ARM64 surface from community
- normalize handwritten Visual Studio projects to `v143`
- do not carry bugfixes or behavioral changes in `build`
- do not encode workspace layout in app source includes

## Dependency Policy

- `id3lib`: frozen
- `ResizableLib`: frozen
- `cryptopp`, `mbedtls`, `miniupnpc`, `zlib`: track latest relevant upstream release

Rules:

- dependency forks are the source of truth
- patch files are not part of the normal workflow
- keep dependency changes minimal
- prefer project, props, wrapper, or CMake integration over source edits
- avoid include-path rewrites in dependency code

The current `ResizableLib` fork already includes the eMuleAI stale-anchor memory leak fix.

## Workspace Layout

The workspace mirrors the canonical branch layout in filesystem-safe `eMule-*` worktree names:

```text
eMule-build-v0.72/
  eMule-bb-v0.72a-build/
  eMule-bb-v0.72a-test/
  eMule-bb-v0.72a-bugfix/
  eMule-cryptopp/
  eMule-id3lib/
  eMule-miniupnp/
  eMule-ResizableLib/
  eMule-zlib/
  eMule-mbedtls/
```

Include-facing layout is normalized so community-style includes resolve through project paths instead of source hacks:

- `eMule-cryptopp\cryptopp\...`
- `eMule-ResizableLib\ResizableLib\...`
- `eMule-zlib\zlib\...`

No `../../eMule-*` includes should appear in app source.

## Toolchain

- Visual Studio 2022
- `PlatformToolset=v143`
- `WindowsTargetPlatformVersion=10.0`
- PowerShell 7
- Git
- CMake
- Perl for `mbedtls` generation

## Generated Projects

Generated-project ownership:

- `zlib`: upstream source under `eMule-zlib\zlib`, workspace-owned wrapper at `eMule-zlib\zlib\contrib\vstudio\vc\zlib.vcxproj`
- `mbedtls`: upstream source under `eMule-mbedtls`, workspace-owned wrapper at `eMule-mbedtls\visualc\VS2017\mbedTLS.vcxproj`

Generated directories are disposable:

- `eMule-zlib\cmake-build-*`
- `eMule-mbedtls\visualc\VS2017-*`

## Commands

Main entry point:

```powershell
pwsh -File .\workspace.ps1 <command>
```

Important commands:

- `env-check`
- `dep-status`
- `validate`
- `validate-full`
- `setup`
- `repair`
- `build-libs`
- `build-app`
- `build-all`
- `build-project`
- `open-app`
- `open-project`
- `run-binary`
- `package`
- `clean-config`
- `clean-generated`

Validation levels:

- `validate`: structural readiness, including generated-project readiness
- `validate-full`: structural readiness plus expected outputs and release package checks

## Typical Flow

Fresh or repaired workspace:

```powershell
pwsh -File .\workspace.ps1 env-check
pwsh -File .\workspace.ps1 setup
pwsh -File .\workspace.ps1 validate
```

Build:

```powershell
pwsh -File .\workspace.ps1 build-libs -Config Release
pwsh -File .\workspace.ps1 build-app -Config Release
pwsh -File .\workspace.ps1 validate-full -Config Release
pwsh -File .\workspace.ps1 package
```

## Setup Behavior

`setup` does this:

1. Initializes submodules.
2. Ensures the app seed repo and worktrees are on the expected branches.
3. Ensures dependency forks are on the workspace build branch.
4. Regenerates `mbedtls` and `zlib` generated projects when needed.
5. Installs the tracked wrapper projects for `mbedtls` and `zlib`.

It does not apply patch files.

## App Surface

`build` uses:

- `srchybrid\emule.vcxproj`

`emule.sln` and `emule.slnx` are intentionally not used here.

## Packaging

Release packaging produces:

- `dist\eMule0.72a-build_x64-snapshot.zip`

The package includes:

- `emule.exe`
- `LICENSE`
- generated `BUILD-INFO.txt`

## Notes

- `MBEDTLS_ALLOW_PRIVATE_ACCESS` and `bcrypt.lib` are intentional project-level integration details for the current `mbedtls` fork and the community source contract.
- The `mbedtls` fork already carries the threading-alt configuration needed by eMule in `tf-psa-crypto\include\psa\crypto_config.h`.
- If `build` needs a behavioral fix, move it to `bugfix` instead of keeping it in the base branch.
