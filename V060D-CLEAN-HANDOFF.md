# v0.60d Restack Handoff

## Current state

The `eMule` app repo now has a new clean layered branch family:

- `v0.60d-build-clean` at `111d452`
- `v0.60d-dev-clean` at `ae86ab6`
- `v0.60d-oracle-clean` at `32b4d8c`

These are pushed to `origin` in `https://github.com/itlezy/eMule.git`.

The legacy branches were intentionally left unchanged:

- `v0.60d-build`
- `v0.60d-dev`
- `v0.60d-oracle`

The clean stack ancestry is strict:

- `v0.60d-build-clean`
- `v0.60d-dev-clean` descends from `v0.60d-build-clean`
- `v0.60d-oracle-clean` descends from `v0.60d-dev-clean`

## Decisions locked

- The clean family uses `-clean` suffixes.
- Legacy `v0.60d-*` branches stay published and frozen.
- This first pass was app-repo only.
- `eMule-build` was intentionally not updated yet.
- The clean history is aggressively collapsed.
- There is one curated commit per clean branch layer.
- Old merge topology was flattened.
- `build-clean` contains only proven common fixes plus shared technical/build fixes.
- `dev-clean` contains the substantive dev layer and drops most README/cosmetic noise.
- `oracle-clean` is a pure `dev-clean` derivative carrying the oracle instrumentation layer.
- If a fix discovered during oracle cleanup is truly shared, it should be promoted downward first.
- Before publishing the clean stack, the required validation gate was `Release` and `Debug` app builds.

## Source mapping used

The clean branches were synthesized from these exact source ranges:

- `build-clean`: `2f5a2d4..v0.60d-build`
- `dev-clean`: `v0.60d-build..v0.60d-dev`
- `oracle-clean`: `v0.60d-dev..v0.60d-oracle`

Resulting curated commits:

- `111d452` `Restack clean build layer`
- `ae86ab6` `Restack clean dev layer`
- `32b4d8c` `Restack clean oracle layer`

## Verification already done

Shared dependency libs:

- `workspace.ps1 build-libs -Config Debug` succeeded
- `libs_debug\` contains all expected debug artifacts

App builds:

- `v0.60d-build-clean` built in `Release` and `Debug`
- `v0.60d-dev-clean` built in `Release` and `Debug`
- `v0.60d-oracle-clean` built in `Release` and `Debug`

Builds were run directly with MSBuild against the current workspace root using `WorkspaceRoot`.

## Important context

Before the restack, there were leftover uncommitted include-rewrite experiments in the three legacy app worktrees. Those were removed before creating the clean branches.

The old wrapper-header discussion is unresolved at the workspace/dependency level. The app restack did not revisit that. The clean app branches are built from the currently working content, not from a new include-strategy redesign.

## Next step: do the same for eMule-build

Target direction for the next session:

- Create a new clean branch family or clean branch path in `eMule-build` that targets the `-clean` app stack.
- Keep the current `v0.60d` build branch working as the legacy workspace branch.
- Add explicit workspace support for:
  - `eMule-v0.60d-build-clean`
  - `eMule-v0.60d-dev-clean`
  - `eMule-v0.60d-oracle-clean`
- Do not mutate the current documented bootstrap path until the clean build branch is green.
- Acceptance gate for that follow-up:
  - `workspace.cmd bootstrap -Config Release` green against the clean app stack

Suggested order:

1. Fork `eMule-build` work onto a new branch instead of touching `v0.60d` directly.
2. Teach `deps.psd1` and `workspace.ps1` about the clean app directories/branches.
3. Keep the legacy app entries available during transition.
4. Verify `build-libs`, `build-app`, and `bootstrap` against the clean stack.
5. Only then decide whether the clean workspace branch becomes preferred.

## Next step after that: v0.7 family

Planned pattern:

- Repeat the same branch-family cleanup approach on the `v0.7` line.
- First inspect actual ancestry and content overlap.
- Prefer strict layering over loosely related branch families.
- Use `-clean` naming again unless there is a strong reason not to.
- Keep legacy published branches intact.
- Produce the same artifacts:
  - commit mapping table
  - clean layered branches
  - verification builds
  - handoff note

## Resume checklist

When resuming:

1. Start in `eMule-build`.
2. Read this file first.
3. Confirm the clean app branches still exist on `origin`.
4. Create the clean follow-up branch for `eMule-build`.
5. Update workspace metadata to target the `-clean` app family.
6. Run `workspace.cmd bootstrap -Config Release`.
7. If green, decide how to document legacy vs clean workspace paths.

## Follow-up completed in eMule-build

On April 4, 2026, the workspace follow-up was resumed in `eMule-build` and moved onto a dedicated clean branch:

- local branch created: `v0.60d-clean`
- legacy branch preserved: `v0.60d`
- `deps.psd1` now targets:
  - seed repo `eMule-v0.60d-oracle-clean`
  - variants `eMule-v0.60d-build-clean`
  - variants `eMule-v0.60d-dev-clean`
  - variants `eMule-v0.60d-oracle-clean`
- `README.md` now documents `v0.60d-clean` as the clean workspace branch and explicitly points legacy users to `v0.60d`

## Verification completed for eMule-build clean branch

The required workspace acceptance gate passed on April 4, 2026:

- `pwsh -File .\workspace.ps1 validate -Config Release` succeeded
- `pwsh -File .\workspace.ps1 bootstrap -Config Release` succeeded

Bootstrap summary at completion:

- APP `build` -> `v0.60d-build-clean` at `111d452`
- APP `dev` -> `v0.60d-dev-clean` at `ae86ab6`
- APP `oracle` -> `v0.60d-oracle-clean` at `32b4d8c`

## Remaining next step

Decide whether to publish and document `v0.60d-clean` as the preferred workspace branch, now that the clean bootstrap path is green.

## Freeze policy for the v0.60d line

Locked policy after the clean restack:

- the `v0.60d` line is frozen outside oracle parity-test work
- the app repo should only accept new `v0.60d` changes on `v0.60d-oracle-clean`
- if an oracle-side fix proves shared, promote it downward before restacking descendants
- the workspace repo should mirror the same ancestor chain with consistent names

## Planned workspace branch family

The preferred clean workspace shape is now:

- `v0.60d-build-clean` as the frozen base workspace branch
- `v0.60d-dev-clean` as a strict child branch kept for ancestry parity and policy-only layering
- `v0.60d-oracle-clean` as the only `v0.60d` workspace branch expected to receive new parity-test related changes

The previously published single-branch workspace path:

- `v0.60d-clean`

is transitional and superseded by the layered family above.
