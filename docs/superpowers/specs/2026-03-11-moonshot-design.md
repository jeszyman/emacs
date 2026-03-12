# Moonshot Skill Design

## Overview

`/moonshot` is a Claude Code skill that wraps the full superpowers design flow (brainstorm → write-plans) but replaces the normal interactive execution phase with an autonomous background agent. The agent runs in an isolated git worktree with `--dangerously-skip-permissions`, attempts the full implementation in one pass, and reports results back to the user's active session.

**Goal:** Reduce the overhead of spec-plan-execute for tasks where a single autonomous pass is worth trying. Fail fast, review the diff.

## Flow

1. User invokes `/moonshot` in any repo
2. Skill runs the standard **brainstorming** skill (interactive — full question flow, approach selection, design approval)
3. Skill runs the standard **write-plans** skill (interactive — produces step-by-step implementation plan)
4. Once the plan is approved, skill:
   a. Creates a git worktree on branch `moonshot/<slugified-topic>-<YYYY-MM-DD>`
   b. Assembles the agent prompt from the spec doc + plan doc + a system preamble
   c. Launches a background agent in the worktree (`run_in_background: true`, `isolation: "worktree"`)
5. User continues working in their current session
6. When the agent completes, user receives an inline notification with a results summary

## Agent Behavior

### Prompt Construction

The agent prompt is assembled from three parts:

1. **System preamble:**
   > You are executing a moonshot implementation. Work best-effort through the plan. Commit after each major step. If something fails, note what went wrong and continue with the next step. Do not stop to ask questions — make reasonable decisions and document your choices in commit messages.

2. **Spec document** (full content of the brainstorming output)

3. **Plan document** (full content of the write-plans output)

### Execution Model

- **Best effort:** The agent pushes as far as it can. If a step fails, it notes the failure and moves to the next step.
- **Incremental commits:** The agent commits after each major plan step, so partial progress is preserved and reviewable.
- **Read access beyond worktree:** The agent can read any repo on disk (e.g., `~/repos/org/`, `~/repos/basecamp/`) for reference, but writes only to the worktree.

### Permissions & Isolation

- **Worktree branch:** `moonshot/<slugified-topic>-<YYYY-MM-DD>`. If the branch already exists, append a short counter (e.g., `-2`, `-3`).
- **`--dangerously-skip-permissions`:** Full autonomy for all tool calls. The worktree isolates the git working directory from the main branch, but does **not** sandbox shell commands — the agent can run arbitrary bash. This is an accepted risk given the "fail fast, kill the branch" philosophy.
- **Read access beyond worktree:** Agent reads other repos as needed but should only modify files in the worktree. This is enforced by prompt instruction, not a technical sandbox.
- **Cleanup:** If abandoned, `git worktree remove <path>` and `git branch -D <branch>` clean up.

### Budget & Timeout

- **Budget cap:** The skill asks the user for a max budget before dispatch (default: `$5.00`). Included in the agent's system preamble as a soft limit (the Agent tool does not support hard budget enforcement). The agent is instructed to stop and commit when it estimates it has reached the budget.
- **Timeout:** Default 30 minutes wall-clock. Included in the agent's system preamble as a soft limit. For hard enforcement, the user can manually abort via TaskStop.
- **Abort:** The user can kill the background agent at any time via TaskStop. The skill prints the agent ID at dispatch time so the user can reference it.

### Validation

After completing the implementation (or as much as it can), the agent should:
1. Run any test suite present in the repo (`make test`, `npm test`, `pytest`, etc.) if one exists
2. Attempt a build/compile if applicable
3. Include test/build results in the final commit message
4. Report pass/fail status in the results summary

## Results Summary

When the agent completes, the user sees:

- Plan steps completed vs. total
- Files changed (`git diff --stat` against the base branch)
- Errors or skipped steps with brief explanations
- Branch name and worktree path
- Suggested next actions: review diff, merge, cherry-pick, or discard

## Implementation Scope

### What gets built

1. **Skill file** (`~/.claude/skills/moonshot/moonshot.md`) — the `/moonshot` entry point. Orchestrates the full flow: invokes brainstorming, invokes write-plans, creates the worktree, dispatches the background agent, and handles the results notification.

2. **Source block in `emacs.org`** — the skill markdown is tangled from an org-babel block, following the existing pattern where skills are derived artifacts and org is the source of truth.

### What does NOT get built

- No separate agent definition file (unlike `org-sleeper`). The agent is a regular Claude Code invocation dispatched via the Agent tool.
- No new hooks or settings changes.
- No multi-repo branching — only the current repo gets a worktree branch. Other repos are read-only.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Trigger | `/moonshot` skill | Interactive — user stays in control through spec phase |
| Spec quality | Full brainstorming + write-plans | No abbreviation — same rigor as normal flow |
| Execution | Background agent in worktree | User keeps working; isolated from main branch |
| Permissions | `--dangerously-skip-permissions` | Worktree isolates git state; shell risk accepted for "kill the branch" workflow |
| Budget | Default $5, user-configurable | Prevents runaway costs |
| Timeout | 30 min default | Prevents stuck agents |
| Validation | Run tests/build if present | Catch obvious breakage before reporting success |
| Failure mode | Best effort | Commit partial progress; don't roll back |
| Multi-repo | Read-only access to other repos | Only current repo gets a branch |
| Review | Inline results summary | User decides merge/cherry-pick/discard |
