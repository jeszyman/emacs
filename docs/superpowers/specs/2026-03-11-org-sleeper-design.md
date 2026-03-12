# org-sleeper: Autonomous Org-Mode Linting Agent

## Overview

A background agent that patrols org-mode files during Emacs idle time, applying small syntax/linting fixes autonomously. Runs on cron, gates on idle time and token budget, picks a random heading, fixes what it can from an approved fix set, commits, and logs.

## Components

### 1. Cron Entry

```cron
*/5 * * * * /bin/bash /home/jeszyman/repos/org/scripts/org-sleeper.sh
```

Fires every 5 minutes. All gating logic lives in the shell script — cron just triggers it.

### 2. Gate Script (`~/repos/org/scripts/org-sleeper.sh`)

Sequential gates, bail early and cheaply (zero tokens spent on gates):

1. **Emacs idle gate** — `emacsclient --socket-name ~/.emacs.d/server/server --eval '(current-idle-time)'`. Require >= 10 minutes idle. If nil or under threshold, exit 0.
2. **Local budget gate** — read the TSV log, sum `tokens_used` for the current month, compare against a configurable monthly token cap (set as a variable at the top of the script). Exit if over budget.
3. **Save buffers** — `emacsclient --eval '(save-some-buffers t)'`. Flushes all modified Emacs buffers to disk so the agent sees current state.
4. **Re-check idle** — confirm `(current-idle-time)` still >= threshold. If user returned to keyboard during save, abort.
5. **Random target selection**:
   - List agenda files from `emacsclient --eval 'org-agenda-files'`
   - Weight by file size (`wc -c`)
   - Pick one file randomly (weighted)
   - Get org outline via `emacsclient --eval` or MCP tool
   - Pick a random heading up to depth 6
6. **Invoke agent**:
   ```bash
   claude -p \
     --agent org-sleeper \
     --model claude-haiku-4-5-20251001 \
     --permission-mode bypassPermissions \
     --max-budget-usd 0.05 \
     --output-format json \
     "Fix: <file> heading: <heading>"
   ```
   The `--max-budget-usd 0.05` provides a per-run safety cap. The `-p` (print) flag runs non-interactively. `--output-format json` allows parsing token usage from the response.
7. **Post-run idle re-check** — confirm `(current-idle-time)` is still > 0 (user still idle). If user returned during the agent run:
   - `git checkout -- <file>` to discard uncommitted agent changes
   - Skip commit and revert steps
   - Log an `aborted` row to TSV
8. **Post-run diff validation** — parse `git diff --cached` (or the commit diff) to confirm all changed lines fall within the target subtree's line range. If changes are outside scope, `git reset HEAD~1` and log a `boundary-violation` row.
9. **Post-run revert** — revert all unmodified org buffers in Emacs:
   ```elisp
   (mapc (lambda (b)
           (with-current-buffer b
             (when (and (eq major-mode 'org-mode)
                        (not (buffer-modified-p)))
               (revert-buffer t t t))))
         (buffer-list))
   ```
10. **Post-run conflict warning** — check for org buffers where disk is newer than buffer AND buffer is modified (user started editing during run):
    ```elisp
    (mapc (lambda (b)
            (with-current-buffer b
              (when (and (eq major-mode 'org-mode)
                         (buffer-modified-p)
                         (not (verify-visited-file-modtime b)))
                (message "org-sleeper: %s was modified on disk; check for conflicts" (buffer-name)))))
          (buffer-list))
    ```

### 3. Agent (`~/.claude/agents/org-sleeper.md`)

- **Model:** Claude Haiku 4.5 (`claude-haiku-4-5-20251001`)
- **Tools:** Bash, Read, Edit
- **Input:** File path and heading path from the shell script

**Per-run behavior:**
1. Read the target subtree
2. Scan for fixable issues from the approved fix set
3. Apply fixes via Edit (only fix types with `status: applied`; log fix types with `status: proposed`)
4. Single `git commit` per repo with message: `org-sleeper: N fixes in <file>::<heading>`
5. Output TSV rows (one per fix) to stdout for the shell script to append to the log
6. If nothing to fix, output nothing and make no commit

**Boundaries:**
- Never makes structural changes (moving headings, changing hierarchy)
- Never applies fixes outside the approved set
- Never touches content outside the target subtree
- One commit per repo per run, no commit if clean

### 4. TSV Log (`~/repos/org/logs/org-sleeper.tsv`)

**Columns:**
```
timestamp	commit_hash	file	heading	fix_type	status	description	tokens_used
```

**Status values:**
- `applied` — fix was made and committed
- `proposed` — fix was identified but not applied (propose-only mode for new fix types)
- `aborted` — agent ran but changes discarded (user returned during run)
- `boundary-violation` — agent made changes outside target subtree, reverted

**Example rows:**
```
2026-03-11T03:22:14	a1b2c3d	work.org	Modules/Flat/breast	missing-id	applied	Added :ID: to subheading "Notes"	1847
2026-03-11T03:22:14	a1b2c3d	work.org	Modules/Flat/breast	missing-nohelm	applied	Added :nohelm: to "Reference"	0
2026-03-11T03:22:14	NONE	work.org	Modules/Flat/breast	trailing-ws	proposed	Would remove trailing whitespace on L412	0
```

- One row per individual fix
- `commit_hash` groups fixes that were committed together (`NONE` for proposed/aborted)
- Runs that find nothing produce no rows and no commit
- `tokens_used` on first row of a commit group; 0 on subsequent rows

### 5. Fix Set

Starts minimal. Initial approved fixes TBD (to be trained/tested in a working session). Examples of candidate fix types:

- Missing `:ID:` properties on module instance subheadings
- Missing `:nohelm:` tags on standard structural headings (Reference, Agent, Claude skill, Notes, Test)
- Trailing whitespace in headings
- Missing blank lines between headings and content

Each fix type has a mode: `auto` (apply and commit) or `propose` (log only).

**Expansion process:**
- New fix types start in `propose` mode
- Manual eval sessions: review log, verify proposed fixes are correct
- Promote to `auto` after batch approval
- No automatic promotion — human gate always

## Concurrency Safety

The concurrent access problem is handled by bracketing the agent run with Emacs coordination:

1. **Pre-run:** `(save-some-buffers t)` forces all buffers to disk — agent sees what Emacs sees
2. **Pre-run:** Re-check idle to catch user returning during save
3. **Post-run:** Re-check idle before committing — if user returned, discard changes via `git checkout`
4. **Post-run:** Validate diff is within target subtree — revert commit if boundary violated
5. **Post-run:** Revert unmodified org buffers so Emacs picks up changes
6. **Post-run:** Warn on any modified buffers where disk is now newer (conflict detection)

Steps 3-4 address the race condition during agent execution identified in review. The window for silent data loss is eliminated: if the user returns at any point, changes are discarded rather than committed.

## Commit Message Convention

```
org-sleeper: N fixes in <filename>::<heading-path>
```

This deliberately identifies the autonomous agent as the author. Autonomous agent commits are transparent by design. (Note: collaborative human+AI work uses a different convention — no AI disclosure.)

## Token Budget

- Gates 1-5 cost zero tokens (pure shell + emacsclient)
- Agent runs on Haiku — cheap per invocation
- Per-run cap via `--max-budget-usd 0.05`
- Monthly cap tracked locally from TSV log `tokens_used` column
- TSV log enables trend analysis of spend over time

## Future Considerations

- **Log-aware target selection:** Agent reads its own log to avoid re-sampling unproductive targets (backoff). Planned for skill development phase, not initial build.
- **Circuit breaker on graduated fix types:** Alerting if a fix type starts producing reverts. Planned for later.
- **Subtree size check:** Skip depth-6 headings that exceed a token threshold for Haiku's context window. May be needed based on profiling.
