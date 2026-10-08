# Planning

Tracks planning-with-files (PWF) artifacts for structured task execution.

## Structure

    planning/
      active/           <- Current work-in-progress PWF files
        task_plan.md
        findings.md
        progress.md
      archive/          <- Completed issues
        YYYY-MM-issue-N-slug/

## Workflow

See `feature-workflow.md` convention in CLAUDE.md for the full sequence:
issue → /planning-init <N> → tests → code-check → atomic commits → /planning-archive.

In this fork, feature branches come off `newgraph` and PRs target `newgraph`; `main` mirrors upstream.

## Skills

- `/planning-init` — create this structure
- `/planning-init <N>` — start issue N (branch + PWF baseline derived from issue body)
- `/planning-update` — sync checkboxes mid-session
- `/planning-archive` — archive completed work, create fresh active/
