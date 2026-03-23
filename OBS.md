# Build Workspace Observations

## Bugs

### 1. `BuiltUtc` timestamp in BUILD-INFO.txt (`workspace.ps1:897`)

```powershell
"BuiltUtc: $(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')"
```

In a double-quoted string, `$(Get-Date)` is expanded and stringified via the default `.ToString()` — producing local time in the system's locale format (e.g. `03/23/2026 14:30:00`). The `.ToUniversalTime().ToString(...)` chain that follows is outside the `$(...)` and is treated as **literal text**, not a method call.

Actual BUILD-INFO.txt output:
```
BuiltUtc: 03/23/2026 14:30:00.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
```

Fix:
```powershell
"BuiltUtc: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
```

Affects every release package produced — the `BuiltUtc` field in BUILD-INFO.txt is malformed and shows local time in locale-specific format with literal method-call text appended.

---

## Silent failures / correctness risks

### 2. `Invoke-Git` discards stderr unconditionally (`workspace.ps1:91`)

```powershell
$output = & $git -C $Repo @ArgumentList 2>$null
```

`2>$null` is always applied. When a git operation fails, the thrown exception says `"<Label> failed with exit code N"` with no diagnostic context. Git's error output is gone. Makes debugging setup failures (wrong branch, locked index, bad ref) unnecessarily hard.

### 3. `CMP0091` not set in mbedtls — XML fixup is a workaround for this

`deps.psd1` passes `-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded$<$<CONFIG:Debug>:Debug>` to cmake. But mbedtls's `CMakeLists.txt` only sets CMP0011, CMP0012, CMP0090 — never `CMP0091`. That policy (`NEW` = honour `CMAKE_MSVC_RUNTIME_LIBRARY`) must be opted into. Without it, the generator expression is silently ignored and cmake emits `/MD`/`/MDd` anyway.

This is the root cause requiring `Normalize-MbedTlsGeneratedProjects` to do a post-configure string replace on generated vcxproj files.

Fix: add `-DCMAKE_POLICY_DEFAULT_CMP0091=NEW` to the mbedtls configure arguments in `deps.psd1`. If confirmed working, `StaticRuntimeProjects` and the runtime-fixing code in `Normalize-MbedTlsGeneratedProjects` can be removed.

### 4. `Toolchain.PlatformToolset` is defined but never used (`deps.psd1:5`)

```
PlatformToolset = 'v143'
```

`workspace.ps1` reads `$Toolchain.WindowsTargetPlatformVersion` but `PlatformToolset` is never read anywhere. Either wire it into MSBuild calls as `/p:PlatformToolset=v143`, or remove it. Currently a false signal — someone maintaining `deps.psd1` might expect changing this value to have an effect.

---

## Build system

### 5. `Build-Libs` `ThrottleLimit 6` is hardcoded to the current project count

```powershell
} -ThrottleLimit 6
```

There are exactly 6 entries in `BuildProjects` today. If a project is added, the limit doesn't grow.

Suggested:
```powershell
} -ThrottleLimit ([Math]::Max(1, [Environment]::ProcessorCount - 1))
```

Or at minimum: `$BuildProjects.Count`.

### 6. `Normalize-MbedTlsGeneratedProjects` runs every `setup` even when configure is skipped

`Run-Setup` (`workspace.ps1:765`):
```powershell
if (-not (Test-GeneratedProjectReady 'mbedtls')) {
    Clean-MbedTlsGenerated
    Invoke-GeneratedProjectConfigure 'mbedtls' $envReport
}
Install-MbedTlsWrapper
Normalize-MbedTlsGeneratedProjects $mbedBuild   # always runs
```

When configure is already done, Normalize still walks all generated vcxproj files with `Get-ChildItem -Recurse`. Negligible on fast SSD but unnecessary when files haven't changed. A sentinel file written after a successful normalize would make this conditional.

### 7. `Sync-NestedBuildSubmodule` hardcodes `eMule-mbedtls`/`tf-psa-crypto` (`workspace.ps1:210-223`)

If another nested submodule were ever added, this function wouldn't cover it. The relationship could be encoded in `deps.psd1` (a `NestedSubmodules` map under the parent dep) to keep `workspace.ps1` data-driven — consistent with how everything else is structured.

---

## Structural / root clutter

### 8. 36 `.cmd` files in the workspace root

Every permutation of build/launch/debug/release has its own file. They're all 2-3 line shells that call `workspace.cmd`. 36 files, ~162 lines total across all of them.

The canonical interface is already `workspace.cmd <command> [-Config ...] [-Project ...]`. The individual wrappers predate that and don't add capability. Move to `legacy/` or delete.

---

## Testing / CI

### 9. `smoke-test.ps1` requires live internet (`scripts/smoke-test.ps1:51`)

```powershell
& $git -C $workspace submodule update --init --recursive
```

Fetches submodules from upstream GitHub URLs. Fails in disconnected environments or if an upstream repo is temporarily unavailable. A `--reference` approach or documenting the requirement would help.

### 10. No CI/CD pipeline

No `.github/workflows/` directory. The smoke test provides a good manual regression gate but requires a Windows machine with VS 2022. A self-hosted Windows runner running `smoke-test.ps1` on push to `v0.72a` would catch regressions automatically.

---

## Dependency health

### 11. `id3lib` — upstream effectively dead

Pins id3lib v3.9.1, ~2003. The upstream (`id3lib/id3lib`) has had no meaningful activity in 20 years. GNU autotools, CVS-era history (ChangeLog is 332KB), hand-maintained `libprj/id3lib.vcxproj` not part of upstream.

Risk: if a C++ standards or Windows SDK change breaks a compile, there is no upstream to fix it. TagLib is the functional successor and actively maintained, but migration touches eMule's tag-reading code. Long-tail liability, not an immediate blocker.

### 12. `ResizableLib` — minimal upstream activity

`ppescher/resizablelib` has effectively two visible commits in recent history. Patch works and the library is stable (pure MFC helper code). Same scenario applies as id3lib — no upstream to lean on if something breaks. Low risk currently.

---

## Summary

| # | Area | Severity | Action |
|---|------|----------|--------|
| 1 | `BuiltUtc` timestamp bug | **Bug** | Fix `$((Get-Date).ToUniversalTime()...)` |
| 2 | `Invoke-Git` swallows stderr | **Risk** | Capture and include in error message |
| 3 | `CMP0091` not set in mbedtls | **Risk** | Add `-DCMAKE_POLICY_DEFAULT_CMP0091=NEW`; may eliminate XML fixup |
| 4 | `Toolchain.PlatformToolset` unused | Misleading config | Wire it up or remove it |
| 5 | `ThrottleLimit 6` hardcoded | Minor | Use `ProcessorCount` or `$BuildProjects.Count` |
| 6 | Normalize runs on every setup | Minor | Guard with configure-ready check |
| 7 | Nested submodule path hardcoded | Minor | Encode in `deps.psd1` |
| 8 | 36 legacy `.cmd` files in root | Clutter | Move to `legacy/` or delete |
| 9 | Smoke test requires internet | Minor | Use `--reference` or document |
| 10 | No CI/CD | Gap | Self-hosted Windows runner |
| 11 | id3lib dead upstream | Long-term liability | Evaluate TagLib migration |
| 12 | ResizableLib minimal upstream | Low risk | Monitor |
