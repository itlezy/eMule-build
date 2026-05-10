# Rules

- Read `EMULE_WORKSPACE_ROOT\repos\eMule-tooling\docs\WORKSPACE_POLICY.md`
  before build or test orchestration work; it is authoritative for
  workspace-wide rules.
- This file contains build-repo local deltas only. Do not duplicate branch,
  worktree, setup, dependency, or app-source policy here.
- `python -m emule_workspace` is the new Python-first orchestration surface for
  ported commands.
- `workspace.ps1` remains a legacy operational entrypoint until each command it
  owns has been ported into `emule_workspace`.
- Keep build orchestration topology-driven from the generated workspace
  manifest and repo-local `deps.psd1`.
- Do not add direct app-project build instructions to docs; route operators
  through this repo's supported entrypoints.
