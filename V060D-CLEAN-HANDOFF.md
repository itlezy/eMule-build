# v0.60d Clean Restack Handoff

## Current target

The `v0.60d` line now uses the same four-stage clean family in both repos:

- `v0.60d-build-clean`
- `v0.60d-bugfix-clean`
- `v0.60d-broadband-clean`
- `v0.60d-experimental-clean`

Strict ancestry is required:

- `build-clean`
- `bugfix-clean` descends from `build-clean`
- `broadband-clean` descends from `bugfix-clean`
- `experimental-clean` descends from `broadband-clean`

Legacy refs remain frozen:

- app repo legacy branches: `v0.60d-build`, `v0.60d-dev`, `v0.60d-oracle`
- workspace legacy branch: `v0.60d`
- older clean residues such as `v0.60d-dev-clean` and `v0.60d-oracle-clean` may remain published for historical reference, but they are not the supported clean lineage

## Layer policy

- `build-clean` contains the practical shared buildable base and shared workspace compatibility
- `bugfix-clean` contains only shared correctness fixes
- `broadband-clean` carries the former `dev` semantics and is the stable default branch for the frozen `v0.60d` line
- `experimental-clean` carries parity, logging, and investigation work only
- new `v0.60d` work should only land on `v0.60d-experimental-clean`
- if an experimental-side fix proves shared, promote it downward first

## Workspace shape

The supported app checkout layout is:

- `eMule-v0.60d-build-clean`
- `eMule-v0.60d-bugfix-clean`
- `eMule-v0.60d-broadband-clean`
- `eMule-v0.60d-experimental-clean`

The workspace keeps preserved dependency repos side by side under the same root.

## Validation target

Before treating the rewrite as complete:

- `workspace.ps1 setup -Config Release` must succeed from a fresh clone
- `workspace.ps1 validate -Config Release` must succeed
- shared libs must build
- the active app branch for this workspace branch must build

## Backups and safety

Before the rewrite, full mirrors, refs, metadata, and worktree snapshots were captured under `C:\backup`.

Timestamped temp restack work happened under `C:\tmp` and should be preserved as breadcrumbs for review.
