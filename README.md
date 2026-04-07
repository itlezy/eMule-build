# eMule-build

`eMule-build` owns the canonical build and test orchestration for the 0.72a
workspace rooted at `EMULE_WORKSPACE_ROOT`.

`eMulebb-setup` is responsible only for materializing the workspace and then
triggering this repo. This repo owns:

- shared dependency build orchestration
- app build orchestration for the active 0.72a branches
- shared test builds
- parity, coverage, and live-diff launch flows

## Canonical layout

```text
EMULE_WORKSPACE_ROOT\
  repos\
    eMule\
    eMule-build\
    eMule-build-tests\
    eMule-tooling\
    eMule-remote\
    third_party\...
  workspaces\
    v0.72a\
      app\
        eMule-main\
        eMule-v0.72a-build\
        eMule-v0.72a-bugfix\
```

Active app branches:

- `main`
- `release/v0.72a-build`
- `release/v0.72a-bugfix`

## Entry points

```powershell
pwsh -File .\workspace.ps1 env-check   -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 build-libs  -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 build-app   -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 build-tests -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 test        -EmuleWorkspaceRoot <workspace-root>
pwsh -File .\workspace.ps1 full        -EmuleWorkspaceRoot <workspace-root>
```

Or from `cmd.exe`:

```cmd
workspace.cmd build-app -EmuleWorkspaceRoot <workspace-root>
```

Supported build matrix:

- app and dependencies: `Debug|x64`, `Release|x64`, `Debug|ARM64`, `Release|ARM64`
- shared tests: `Debug|x64`, `Release|x64`

The legacy batch files remain in the repo for historical compatibility, but the
canonical maintained entrypoint is `workspace.ps1`. Legacy pre-canonical branch
names are not part of the supported workflow.
