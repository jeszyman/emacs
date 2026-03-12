# Moonshot Skill Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `/moonshot` skill — a Claude Code skill that orchestrates brainstorming → planning → autonomous background agent execution in an isolated git worktree.

**Architecture:** Single skill file (`~/.claude/skills/moonshot/SKILL.md`) tangled from an org-babel block. The skill orchestrates three phases: (1) invoke brainstorming skill, (2) invoke write-plans skill, (3) dispatch a background Agent with the spec+plan as prompt, running in a worktree with full permissions. No separate agent definition needed.

**Tech Stack:** Claude Code skills (markdown with YAML frontmatter), org-babel tangle, git worktrees, Agent tool with `isolation: "worktree"` and `run_in_background: true`.

---

## Chunk 1: Skill File

### Task 1: Write the moonshot skill markdown

**Files:**
- Create: `~/.claude/skills/moonshot/SKILL.md`

Note: This file will later become a tangle target from an org-babel block in `work.org`. For now, create it directly to test the skill before integrating into the org source-of-truth.

- [ ] **Step 1: Create the skill directory**

```bash
mkdir -p ~/.claude/skills/moonshot
```

- [ ] **Step 2: Write the SKILL.md file**

Write `~/.claude/skills/moonshot/SKILL.md` with the following content:

```markdown
---
name: moonshot
description: >
  Autonomous agent workflow for ambitious implementation attempts. Runs the full
  brainstorming + write-plans flow, then dispatches a background agent in an
  isolated git worktree with full permissions. User reviews the result after.
  Trigger on: "moonshot", "let it rip", "autonomous implementation", or when
  the user wants to hand off a feature build to run unattended.
---

# Moonshot: Autonomous Implementation Skill

You orchestrate a three-phase workflow: design → plan → autonomous execution.

## Phase 1: Design (Interactive)

Invoke the `superpowers:brainstorming` skill. Run the full brainstorming flow:
- Explore project context
- Ask clarifying questions (one at a time)
- Propose 2-3 approaches with recommendation
- Present design section by section, get approval
- Write spec doc to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
- Run spec review loop
- User reviews spec

Do NOT skip or abbreviate any brainstorming steps. Same rigor as a normal design.

## Phase 2: Plan (Interactive)

Invoke the `superpowers:writing-plans` skill. Run the full planning flow:
- Write implementation plan with bite-sized tasks
- Save to `docs/superpowers/plans/YYYY-MM-DD-<topic>-plan.md`
- Run plan review loop
- User approves plan

## Phase 3: Dispatch (Autonomous)

Once the plan is approved, transition to autonomous execution:

### Step 3a: Confirm budget and timeout

Ask the user:
> "Ready to launch the moonshot. Defaults: **$5 budget**, **30 min timeout**. Change these or hit enter to proceed."

Record the user's choices (or defaults).

### Step 3b: Read the spec and plan docs

Read the spec doc and plan doc that were written in Phases 1 and 2.
Store their full content for inclusion in the agent prompt.

### Step 3c: Assemble the agent prompt

Construct the prompt from three parts:

**Part 1 — System preamble:**

```
You are executing a moonshot implementation autonomously. Rules:

1. Work best-effort through the plan below. Complete as many steps as you can.
2. Commit after each major plan task (not every sub-step — after each ### Task).
3. If a step fails, note what went wrong in a commit message and continue to the next task.
4. Do not stop to ask questions — make reasonable decisions and document choices in commits.
5. Only modify files in your current working directory (the worktree). You may read files anywhere on disk for reference.
6. BUDGET: Do not exceed approximately $<BUDGET> in token usage. If you estimate you are approaching the limit, commit your progress and stop.
7. TIMEOUT: You have approximately <TIMEOUT> minutes. If you are running long, prioritize committing progress over completing all steps.
8. After completing the plan (or as much as you can):
   - Attempt a build/compile if the repo has one (make, npm build, cargo build, etc.)
   - Run any test suite present in the repo if one exists (make test, npm test, pytest, etc.)
   - Include build and test results in your final commit message
9. Your final output message must be a results summary in this format:

## Moonshot Results
- **Steps completed:** X/Y
- **Steps skipped/failed:** [list with brief reasons]
- **Build results:** [pass/fail/N/A]
- **Test results:** [pass/fail/no tests found]
- **Key decisions made:** [any judgment calls you made autonomously]
```

**Part 2 — Spec document** (full content)

**Part 3 — Plan document** (full content)

### Step 3d: Check for branch collision

Before dispatching, check if the branch name already exists:

```bash
git branch --list "moonshot/<topic>-<date>"
```

If it exists, append a counter: `moonshot/<topic>-<date>-2`, `-3`, etc. Check each until an unused name is found.

### Step 3e: Dispatch the background agent

Use the Agent tool with these parameters:
- `description`: "moonshot: <topic>"
- `prompt`: the assembled prompt from Step 3c
- `isolation`: "worktree"
- `run_in_background`: true

After dispatch, capture the agent ID from the tool response.

Print to the user:
> "Moonshot launched in background. You'll be notified when it completes.
> Branch: `moonshot/<topic>-<date>`
> Budget: $X | Timeout: Y min
> Agent ID: `<id>` (use TaskStop to abort if needed)"

### Step 3f: Handle completion

When the background agent completes and you receive the notification:

1. Print the agent's results summary to the user
2. Run `git diff --stat` against the base branch in the worktree to show files changed
3. Print cleanup options:
   > **Next steps:**
   > - Review: `git log moonshot/<branch>` / `git diff main...moonshot/<branch>`
   > - Merge: `git merge moonshot/<branch>`
   > - Discard: `git worktree remove <path> && git branch -D moonshot/<branch>`

## Notes

- The brainstorming and write-plans phases are fully interactive — the user is in the loop
- Only Phase 3 (execution) runs autonomously in the background
- If the user wants to abort mid-run, they can use TaskStop with the agent ID
- The worktree isolates git working directory state but does NOT sandbox shell commands — this is an accepted risk
```

- [ ] **Step 3: Verify the skill file exists and has valid frontmatter**

```bash
head -3 ~/.claude/skills/moonshot/SKILL.md
```

Expected output:
```
---
name: moonshot
description: >
```

Note: `~/.claude/skills/` is not inside a git repo. The git-tracked version comes in Task 2 when we add the org source block to `emacs.org`. No commit needed here.

---

### Task 2: Add org source block to emacs.org

**Files:**
- Modify: `/home/jeszyman/repos/emacs/emacs.org` (replace the Moonshot agent idea heading with a full skill block)

- [ ] **Step 1: Save the Emacs buffer**

```bash
emacsclient --socket-name ~/.emacs.d/server/server --eval \
  '(with-current-buffer (find-file-noselect "/home/jeszyman/repos/emacs/emacs.org") (save-buffer) "saved")'
```

- [ ] **Step 2: Update the heading text and properties**

Find the heading `*** Moonshot agent [#Y]` at the end of emacs.org (~line 8138).
Change it to `*** Moonshot skill` (remove the priority tag). Keep the `:PROPERTIES:` drawer and ID unchanged.

Replace the body text (everything between `:END:` and end of file) with:

```org

Autonomous implementation skill — runs full brainstorm + plan interactively,
then dispatches a background agent in a worktree.

See [[file:docs/superpowers/specs/2026-03-11-moonshot-design.md][design spec]].
```

- [ ] **Step 3: Insert the skill source block**

After the body text added in Step 2, add a sub-heading with the tangle block.
Read the content of `~/.claude/skills/moonshot/SKILL.md` (created in Task 1) and insert it as the block body:

```org
**** Claude skill

#+begin_src markdown :tangle ~/.claude/skills/moonshot/SKILL.md :mkdirp yes :comments no
<contents of ~/.claude/skills/moonshot/SKILL.md read from disk>
#+end_src
```

- [ ] **Step 4: Tangle to verify the output matches**

```bash
emacsclient --socket-name ~/.emacs.d/server/server --eval \
  '(with-current-buffer (find-file-noselect "/home/jeszyman/repos/emacs/emacs.org")
     (org-babel-tangle)
     "tangled")'
```

Verify `~/.claude/skills/moonshot/SKILL.md` matches expected content:

```bash
head -5 ~/.claude/skills/moonshot/SKILL.md
```

Expected: YAML frontmatter starting with `---` and `name: moonshot`.

- [ ] **Step 5: Commit**

```bash
cd /home/jeszyman/repos/emacs
git add emacs.org
git commit -m "feat: add moonshot skill org source block

Replaces the Moonshot agent idea heading with a proper skill section
including a tangle block that produces ~/.claude/skills/moonshot/SKILL.md"
```

---

### Task 3: Manual smoke test

- [ ] **Step 1: Invoke `/moonshot` in a test repo**

Open a Claude Code session in any repo and type `/moonshot`. Verify:
- The skill loads and begins the brainstorming flow
- It asks clarifying questions one at a time
- After design approval, it transitions to write-plans
- After plan approval, it asks about budget/timeout
- It dispatches the background agent and prints the launch message

- [ ] **Step 2: Wait for completion**

Let the agent run. When it completes, verify:
- Results summary is printed inline
- `git diff --stat` output appears
- Branch name and cleanup options are shown

- [ ] **Step 3: Review and clean up**

```bash
git log moonshot/<branch> --oneline
git diff main...moonshot/<branch> --stat
# If satisfied:
git merge moonshot/<branch>
# Or discard:
git worktree remove <path> && git branch -D moonshot/<branch>
```
