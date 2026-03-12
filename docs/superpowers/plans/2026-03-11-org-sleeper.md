# org-sleeper Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a cron-triggered background agent that patrols org-mode files during Emacs idle time, applying small syntax/linting fixes autonomously.

**Architecture:** Shell gate script handles all pre/post coordination (idle check, budget, Emacs buffer sync, target selection). Claude Haiku agent runs headless via `claude -p --agent`, does the actual org-mode fixes. TSV log tracks all activity.

**Tech Stack:** Bash (gate script), Claude CLI (`claude -p`), Emacs (`emacsclient --eval`), git

**Spec:** `docs/superpowers/specs/2026-03-11-org-sleeper-design.md`

---

## Chunk 1: Infrastructure

### Task 1: Create log directory and TSV header

**Files:**
- Create: `~/repos/org/logs/org-sleeper.tsv`

- [ ] **Step 1: Create the logs directory**

```bash
mkdir -p ~/repos/org/logs
```

- [ ] **Step 2: Write the TSV header file**

```bash
printf 'timestamp\tcommit_hash\tfile\theading\tfix_type\tstatus\tdescription\ttokens_used\n' > ~/repos/org/logs/org-sleeper.tsv
```

- [ ] **Step 3: Verify**

```bash
cat ~/repos/org/logs/org-sleeper.tsv
```
Expected: single header line with 8 tab-separated column names.

- [ ] **Step 4: Commit**

```bash
cd ~/repos/org && git add logs/org-sleeper.tsv && git commit -m "org-sleeper: add TSV log with header"
```

---

### Task 2: Write the agent definition

**Files:**
- Create: `~/.claude/agents/org-sleeper.md`

The agent definition uses YAML frontmatter (matching existing agents like `org-hygiene.md`). The agent receives a file path and heading path, reads the subtree, applies fixes from the approved set, outputs TSV rows to stdout, and optionally commits.

- [ ] **Step 1: Write the agent definition**

Create `~/.claude/agents/org-sleeper.md` with this content:

```markdown
---
name: org-sleeper
description: Autonomous background org-mode linter. Reads a target subtree, applies approved fixes, commits, and outputs TSV log rows. Invoked headless by cron via org-sleeper.sh.
model: claude-haiku-4-5-20251001
tools:
  - Bash
  - Read
  - Edit
---

You are the org-sleeper agent — an autonomous background linter for org-mode files. You run headless via cron during Emacs idle time.

## Input

You receive a prompt like: `Fix: /home/jeszyman/repos/org/work.org heading: Modules/Flat/breast`

The file path is absolute. The heading path uses `/` separators for nested headings.

## Behavior

1. Read the target file. Find the heading matching the path.
2. Identify the line range of the target subtree (from the heading line to the line before the next heading at same or higher level).
3. Scan the subtree for fixable issues from the **Approved Fix Set** below.
4. For each issue found:
   - If the fix type mode is `auto`: apply the fix using the Edit tool.
   - If the fix type mode is `propose`: do NOT apply. Just note it for logging.
5. After all fixes are applied, if any `auto` fixes were made:
   - Stage the changed file: `git add <file>`
   - Count the applied fixes. Commit: `git commit -m "org-sleeper: N fixes in <basename>::<heading>"`
6. Output TSV rows to stdout — one row per fix (both applied and proposed). Format:
   ```
   <timestamp>\t<commit_hash>\t<basename>\t<heading>\t<fix_type>\t<status>\t<description>\t<tokens_used>
   ```
   - `timestamp`: ISO 8601 (e.g., `2026-03-11T03:22:14`)
   - `commit_hash`: short hash from the commit, or `NONE` if proposed/no commit
   - `basename`: filename only (e.g., `work.org`)
   - `heading`: the heading path as received
   - `fix_type`: identifier from the fix set (e.g., `trailing-ws`)
   - `status`: `applied` or `proposed`
   - `description`: brief human-readable note
   - `tokens_used`: put total token count on the first row, `0` on subsequent rows
7. If nothing to fix, output nothing.

## Boundaries

- NEVER make structural changes (move/delete/add headings, change hierarchy).
- NEVER touch content outside the target subtree's line range.
- NEVER apply fix types not listed in the Approved Fix Set.
- ONE commit per run, or no commit if nothing was auto-fixed.

## Approved Fix Set

### trailing-ws (mode: auto)
Remove trailing whitespace from any line in the subtree.
- Match: lines ending with `[ \t]+$`
- Fix: remove the trailing whitespace
- Do NOT modify lines inside `#+begin_src` / `#+end_src` blocks (code blocks are exempt)

### blank-after-heading (mode: auto)
Ensure there is exactly one blank line between a heading line (or its PROPERTIES drawer / planning line) and the first content line.
- Match: heading line (or PROPERTIES :END: / DEADLINE / SCHEDULED line) immediately followed by a non-blank content line (not another heading, not a blank line)
- Fix: insert one blank line
- Do NOT insert blank lines between a heading and its PROPERTIES drawer, or between PROPERTIES :END: and DEADLINE/SCHEDULED lines — those should remain adjacent

(Additional fix types will be added here as they are trained and promoted.)
```

- [ ] **Step 2: Verify the agent loads**

```bash
claude agents 2>&1 | grep org-sleeper
```
Expected: `org-sleeper` appears in the agent list.

- [ ] **Step 3: Smoke test the agent on a known heading**

Pick a heading you know has trailing whitespace or missing blank lines:
```bash
claude -p --agent org-sleeper --model claude-haiku-4-5-20251001 --permission-mode bypassPermissions --max-budget-usd 0.05 "Fix: /home/jeszyman/repos/org/work.org heading: <test-heading>"
```
Expected: TSV rows on stdout (or no output if heading is clean). Inspect `git log -1` and `git diff HEAD~1` if a commit was made.

**IMPORTANT:** After smoke test, revert the commit if one was made (`git reset HEAD~1 && git checkout -- <file>`) — this is a test, not a real run.

---

### Task 3: Write the gate script

**Files:**
- Create: `~/repos/org/scripts/org-sleeper.sh`

This is the largest component. The script gates on idle time and budget, selects a random target, invokes the agent, and handles post-run safety.

- [ ] **Step 1: Write the gate script**

Create `~/repos/org/scripts/org-sleeper.sh`:

```bash
#!/bin/bash
# org-sleeper gate script — cron fires this every 5 minutes.
# Gates on Emacs idle time and monthly token budget.
# Picks a random org heading, invokes the org-sleeper agent, handles post-run safety.

set -euo pipefail

# --- Configuration ---
IDLE_THRESHOLD_SECONDS=600  # 10 minutes
MONTHLY_TOKEN_CAP=500000    # tokens per month
MAX_BUDGET_PER_RUN=0.05     # USD
EMACS_SOCKET="$HOME/.emacs.d/server/server"
TSV_LOG="$HOME/repos/org/logs/org-sleeper.tsv"
MAX_HEADING_DEPTH=6

EC="emacsclient --socket-name $EMACS_SOCKET"

# --- Helper: log a TSV row ---
log_row() {
    local timestamp commit_hash file heading fix_type status description tokens_used
    timestamp="$1"; commit_hash="$2"; file="$3"; heading="$4"
    fix_type="$5"; status="$6"; description="$7"; tokens_used="$8"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$timestamp" "$commit_hash" "$file" "$heading" \
        "$fix_type" "$status" "$description" "$tokens_used" \
        >> "$TSV_LOG"
}

# --- Gate 1: Emacs idle check ---
idle_seconds() {
    local raw
    raw=$($EC --eval '(let ((it (current-idle-time))) (if it (float-time it) -1))' 2>/dev/null) || echo "-1"
    # raw is a float like "623.45" or "-1" if not idle
    printf '%s' "$raw" | sed 's/\..*//'  # truncate to integer
}

IDLE=$(idle_seconds)
if [[ "$IDLE" -lt "$IDLE_THRESHOLD_SECONDS" ]]; then
    exit 0
fi

# --- Gate 2: Monthly token budget ---
CURRENT_MONTH=$(date +%Y-%m)
MONTH_TOKENS=$(awk -F'\t' -v month="$CURRENT_MONTH" '
    NR > 1 && substr($1, 1, 7) == month { sum += $8 }
    END { print sum+0 }
' "$TSV_LOG" 2>/dev/null || echo "0")

if [[ "$MONTH_TOKENS" -ge "$MONTHLY_TOKEN_CAP" ]]; then
    exit 0
fi

# --- Gate 3: Save all Emacs buffers ---
$EC --eval '(save-some-buffers t)' >/dev/null 2>&1

# --- Gate 4: Re-check idle after save ---
IDLE=$(idle_seconds)
if [[ "$IDLE" -lt "$IDLE_THRESHOLD_SECONDS" ]]; then
    exit 0
fi

# --- Gate 5: Random target selection ---

# Get agenda files as a bash array
AGENDA_FILES_RAW=$($EC --eval '(mapconcat #'\''identity (org-agenda-files) "\n")' 2>/dev/null)
# Strip surrounding quotes and unescape
AGENDA_FILES_RAW=$(echo "$AGENDA_FILES_RAW" | sed 's/^"//;s/"$//;s/\\n/\n/g')

# Build array of files with sizes for weighted selection
declare -a FILES
declare -a SIZES
TOTAL_SIZE=0
while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    sz=$(wc -c < "$f")
    FILES+=("$f")
    SIZES+=("$sz")
    TOTAL_SIZE=$((TOTAL_SIZE + sz))
done <<< "$AGENDA_FILES_RAW"

if [[ ${#FILES[@]} -eq 0 || $TOTAL_SIZE -eq 0 ]]; then
    exit 0
fi

# Weighted random file selection
RAND=$((RANDOM % TOTAL_SIZE))
CUMULATIVE=0
CHOSEN_FILE=""
for i in "${!FILES[@]}"; do
    CUMULATIVE=$((CUMULATIVE + SIZES[i]))
    if [[ $RAND -lt $CUMULATIVE ]]; then
        CHOSEN_FILE="${FILES[$i]}"
        break
    fi
done
[[ -n "$CHOSEN_FILE" ]] || exit 0

# Get headings up to MAX_HEADING_DEPTH from the chosen file
# Use grep to extract heading lines with their text
HEADINGS=$(grep -n '^\*\{1,'"$MAX_HEADING_DEPTH"'\} ' "$CHOSEN_FILE" | head -500)
HEADING_COUNT=$(echo "$HEADINGS" | wc -l)

if [[ $HEADING_COUNT -eq 0 ]]; then
    exit 0
fi

# Pick a random heading
RAND_IDX=$(( (RANDOM % HEADING_COUNT) + 1 ))
CHOSEN_LINE=$(echo "$HEADINGS" | sed -n "${RAND_IDX}p")
# Extract heading text (strip line number prefix and stars)
CHOSEN_HEADING=$(echo "$CHOSEN_LINE" | sed 's/^[0-9]*:\**[[:space:]]*//')
# Strip tags (e.g., :tag1:tag2:) from the end
CHOSEN_HEADING=$(echo "$CHOSEN_HEADING" | sed 's/[[:space:]]*:[a-zA-Z0-9_@:]*:[[:space:]]*$//')

CHOSEN_BASENAME=$(basename "$CHOSEN_FILE")
CHOSEN_REPO=$(cd "$(dirname "$CHOSEN_FILE")" && git rev-parse --show-toplevel 2>/dev/null || echo "")

# --- Gate 6: Invoke the agent ---
TIMESTAMP=$(date -Iseconds)

AGENT_OUTPUT=$(claude -p \
    --agent org-sleeper \
    --model claude-haiku-4-5-20251001 \
    --permission-mode bypassPermissions \
    --max-budget-usd "$MAX_BUDGET_PER_RUN" \
    --output-format json \
    "Fix: $CHOSEN_FILE heading: $CHOSEN_HEADING" 2>/dev/null) || true

# --- Gate 7: Post-run idle re-check ---
IDLE=$(idle_seconds)
if [[ "$IDLE" -le 0 ]]; then
    # User returned — discard any uncommitted changes
    if [[ -n "$CHOSEN_REPO" ]]; then
        cd "$CHOSEN_REPO"
        git checkout -- "$CHOSEN_FILE" 2>/dev/null || true
    fi
    log_row "$TIMESTAMP" "NONE" "$CHOSEN_BASENAME" "$CHOSEN_HEADING" \
        "n/a" "aborted" "User returned during agent run" "0"
    exit 0
fi

# --- Gate 8: Post-run diff validation ---
# Check if agent made a commit. If so, verify changes are within the target file.
if [[ -n "$CHOSEN_REPO" ]]; then
    cd "$CHOSEN_REPO"
    LATEST_MSG=$(git log -1 --pretty=%s 2>/dev/null || echo "")
    if [[ "$LATEST_MSG" == org-sleeper:* ]]; then
        # Verify only the target file was changed
        CHANGED_FILES=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || echo "")
        EXPECTED_REL=$(git ls-files --full-name "$CHOSEN_FILE" 2>/dev/null || echo "")
        if [[ "$CHANGED_FILES" != "$EXPECTED_REL" ]]; then
            git reset HEAD~1 --hard 2>/dev/null || true
            log_row "$TIMESTAMP" "NONE" "$CHOSEN_BASENAME" "$CHOSEN_HEADING" \
                "n/a" "boundary-violation" "Agent modified files outside target: $CHANGED_FILES" "0"
            # Revert buffers after reset
            $EC --eval '(mapc (lambda (b) (with-current-buffer b (when (and (eq major-mode (quote org-mode)) (not (buffer-modified-p))) (revert-buffer t t t)))) (buffer-list))' >/dev/null 2>&1
            exit 0
        fi
    fi
fi

# --- Gate 9: Post-run revert org buffers ---
$EC --eval '(mapc (lambda (b) (with-current-buffer b (when (and (eq major-mode (quote org-mode)) (not (buffer-modified-p))) (revert-buffer t t t)))) (buffer-list))' >/dev/null 2>&1

# --- Gate 10: Conflict warning ---
$EC --eval '(mapc (lambda (b) (with-current-buffer b (when (and (eq major-mode (quote org-mode)) (buffer-modified-p) (not (verify-visited-file-modtime b))) (message "org-sleeper: %s was modified on disk; check for conflicts" (buffer-name))))) (buffer-list))' >/dev/null 2>&1

# --- Append agent output to TSV log ---
# Agent outputs raw TSV rows (no header). Append if non-empty.
if [[ -n "$AGENT_OUTPUT" ]]; then
    # If output-format is json, extract the text content
    RESULT_TEXT=$(echo "$AGENT_OUTPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # claude -p --output-format json returns {result: string, ...}
    print(d.get('result', ''))
except:
    print(sys.stdin.read())
" 2>/dev/null || echo "$AGENT_OUTPUT")
    if [[ -n "$RESULT_TEXT" ]]; then
        echo "$RESULT_TEXT" >> "$TSV_LOG"
    fi
fi
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x ~/repos/org/scripts/org-sleeper.sh
```

- [ ] **Step 3: Shellcheck**

```bash
shellcheck ~/repos/org/scripts/org-sleeper.sh
```
Expected: no errors (warnings about RANDOM are acceptable).

- [ ] **Step 4: Test Gate 1 in isolation (idle check)**

While actively using Emacs (not idle):
```bash
bash ~/repos/org/scripts/org-sleeper.sh && echo "exited cleanly (gated)"
```
Expected: exits immediately and silently because Emacs is not idle.

- [ ] **Step 5: Commit**

```bash
cd ~/repos/org && git add scripts/org-sleeper.sh && git commit -m "org-sleeper: add gate script"
```

---

### Task 4: Add cron entry

Existing cron entries are Ansible-managed (prefixed with `#Ansible:`). The org-sleeper cron entry should follow the same pattern so it persists across Ansible runs.

- [ ] **Step 1: Identify where cron entries are defined in Ansible**

Check the crontab source. Based on existing entries with `#Ansible:` prefix, find the Ansible task that manages cron in either:
- `~/repos/basecamp/basecamp.org` (public ansible)
- `~/repos/org/private.org` (private ansible)

Search for `ical2org` or `cron` in those files to find the block.

- [ ] **Step 2: Add the cron entry to the Ansible playbook**

Add to the appropriate Ansible cron task block:

```yaml
- name: org-sleeper cron
  ansible.builtin.cron:
    name: "org-sleeper"
    minute: "*/5"
    job: "/bin/bash /home/jeszyman/repos/org/scripts/org-sleeper.sh 2>/dev/null"
```

- [ ] **Step 3: For immediate testing, add manually to crontab**

```bash
(crontab -l 2>/dev/null; echo '*/5 * * * * /bin/bash /home/jeszyman/repos/org/scripts/org-sleeper.sh 2>/dev/null') | crontab -
```

- [ ] **Step 4: Verify crontab**

```bash
crontab -l | grep org-sleeper
```
Expected: the entry appears.

---

## Chunk 2: Integration Testing

### Task 5: End-to-end dry run

Test the full pipeline manually by simulating the conditions.

- [ ] **Step 1: Create a test org file with known issues**

Create a temporary test file `~/repos/org/test-sleeper.org`:
```org
* Test heading for org-sleeper
Some content immediately after heading with no blank line.

** Sub heading with trailing spaces
Content here.
```

Note: the heading lines have trailing spaces, and content follows headings without blank lines.

- [ ] **Step 2: Add test file to agenda temporarily**

```bash
emacsclient --socket-name ~/.emacs.d/server/server --eval '(add-to-list '\''org-agenda-files "/home/jeszyman/repos/org/test-sleeper.org")'
```

- [ ] **Step 3: Run the agent directly on the test file**

```bash
claude -p \
    --agent org-sleeper \
    --model claude-haiku-4-5-20251001 \
    --permission-mode bypassPermissions \
    --max-budget-usd 0.05 \
    "Fix: /home/jeszyman/repos/org/test-sleeper.org heading: Test heading for org-sleeper"
```

Expected: TSV rows on stdout showing `trailing-ws` and/or `blank-after-heading` fixes with status `applied`.

- [ ] **Step 4: Inspect the commit**

```bash
cd ~/repos/org && git log -1 --oneline && git diff HEAD~1
```

Expected: commit message matches `org-sleeper: N fixes in test-sleeper.org::Test heading for org-sleeper`. Diff shows trailing whitespace removed and/or blank line inserted.

- [ ] **Step 5: Verify TSV output format**

Take the stdout from step 3 and verify it has 8 tab-separated columns matching the header.

- [ ] **Step 6: Clean up test file**

```bash
cd ~/repos/org && git reset HEAD~1 --hard
rm -f ~/repos/org/test-sleeper.org
emacsclient --socket-name ~/.emacs.d/server/server --eval '(setq org-agenda-files (remove "/home/jeszyman/repos/org/test-sleeper.org" org-agenda-files))'
```

- [ ] **Step 7: Verify the gate script end-to-end**

Leave Emacs idle for 10+ minutes, then manually run:
```bash
bash ~/repos/org/scripts/org-sleeper.sh
```

Check:
- `git log -1` in the repo of whichever file was chosen
- `tail -5 ~/repos/org/logs/org-sleeper.tsv` for new rows
- If the chosen heading was already clean, no commit and no new rows is expected

---

### Task 6: Validate concurrency safety

- [ ] **Step 1: Test idle abort path**

Start the gate script, then immediately start typing in Emacs. The post-run idle check should cause an abort:
- Check TSV log for an `aborted` row
- Check `git log` to confirm no commit was made

- [ ] **Step 2: Test buffer revert path**

Leave Emacs idle. Run the gate script. After it completes:
- Check that org buffers in Emacs show the agent's changes (if any were made)
- Verify no "modified on disk" warnings in `*Messages*` buffer

---

## Notes for future sessions

- **Fix set expansion**: To add a new fix type, add it to the `## Approved Fix Set` section of `~/.claude/agents/org-sleeper.md` with `mode: propose` first. Review TSV log entries with `status=proposed`, verify correctness, then change mode to `auto`.
- **Ansible integration**: Task 4 step 2 needs to be done in the appropriate org file that tangles the Ansible playbook. This is tracked but not fully specified because it depends on which playbook manages this host's cron.
- **work.org module**: The agent definition should eventually be tangled from a `work.org` module heading, matching the pattern of `org-hygiene`. Not in scope for initial build.
