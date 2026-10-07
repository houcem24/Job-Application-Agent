#!/usr/bin/env bash
#
# batch-apply.sh -- Parallel job application orchestrator
#
# Usage:
#   ./scripts/batch-apply.sh [--parallel N] [--dry-run] [--max M] [--ats TYPE] [--model MODEL] [--effort LEVEL] [--headless] [--worker-timeout SEC] [--fulltime]
#
# Options:
#   --parallel N       Number of parallel workers (default: 3)
#   --dry-run          Show what would be applied to without launching workers
#   --max M            Maximum number of positions to process (default: all)
#   --ats TYPE         Only process positions from this ATS (workday|greenhouse|ashby|lever|other)
#   --model MODEL      Claude model to use: opus, sonnet, haiku (default: sonnet)
#   --effort LEVEL     Reasoning effort: low, medium, high, max (default: medium)
#   --headless         Run browsers with no visible window (default: visible, so you can watch it apply)
#   --worker-timeout SEC  Force-kill a single worker (and its browser) after this many seconds
#                         if it hasn't finished (default: 900 = 15 min). Prevents a stuck/hung
#                         worker from blocking the script from ever reaching the merge step.
#   --fulltime          Operate on the "full time applications/" track instead of the default
#                         "working student applications/" track (separate positions.md/applied.md/
#                         needs_manual_email.md, separate FT-prefixed IDs). Also tells each worker
#                         this is a full-time entry-level application (data analyst/analytics/
#                         visualization/engineer only -- no data scientist/AI/GenAI engineer roles)
#                         so cover letters and answers are framed accordingly.
#
# If Claude's own usage/session limit is hit mid-run (detected from a worker's log output),
# the script stops launching NEW workers, waits for already-running ones to finish (or hit
# --worker-timeout), and still runs the merge step -- so a limit mid-batch no longer leaves
# completed applications unmerged in scripts/.work.
#
# Each worker is a `claude -p` instance with its own isolated Playwright browser. By default
# each worker's browser window is visible on screen so you can watch the applications happen;
# pass --headless to run without visible windows (e.g. for overnight/unattended runs).
# Workers write results to individual temp files; this script merges them into applied.md.
#
# HOW PARALLEL BROWSERS WORK:
# The Playwright MCP server (stdio) shares a browser profile by default, so multiple
# workers would fight over one browser. To fix this, each worker gets:
#   1. Its own temp directory with a .claude.json configuring Playwright with a
#      unique --user-data-dir (isolated browser profile), headed unless --headless is passed
#   2. A symlink to the repo so the worker can still read JOB_APPLICATION_AGENT.md etc.
# This gives each worker a fully independent Chromium instance, visible by default.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
REPO_DIR="$(dirname "$APP_DIR")"
AGENT_FILE="$APP_DIR/JOB_APPLICATION_AGENT.md"
PROFILE_FILE="$REPO_DIR/profile/candidate.md"

# Defaults
PARALLEL=3
DRY_RUN=false
MAX_POSITIONS=999
ATS_FILTER=""
MODEL="sonnet"
EFFORT="medium"
HEADLESS=false
WORKER_TIMEOUT=900   # seconds per worker before it's force-killed (default 15 min)
FULLTIME=false

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --parallel) PARALLEL="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --max) MAX_POSITIONS="$2"; shift 2 ;;
    --ats) ATS_FILTER="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --headless) HEADLESS=true; shift ;;
    --worker-timeout) WORKER_TIMEOUT="$2"; shift 2 ;;
    --fulltime) FULLTIME=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Track folder: two independent application tracks live side by side under
# applications/, each with its own positions.md/applied.md/needs_manual_email.md
# and its own FT-prefixed (full-time) or bare-numbered (working-student) IDs.
if [[ "$FULLTIME" == "true" ]]; then
  TRACK_DIR="$APP_DIR/full time applications"
  TRACK_LABEL="full-time"
else
  TRACK_DIR="$APP_DIR/working student applications"
  TRACK_LABEL="working-student"
fi
POSITIONS_FILE="$TRACK_DIR/positions.md"
APPLIED_FILE="$TRACK_DIR/applied.md"
NEEDS_MANUAL_EMAIL_FILE="$TRACK_DIR/needs_manual_email.md"
if [[ "$DRY_RUN" != "true" && ! -f "$PROFILE_FILE" ]]; then
  echo "Missing $PROFILE_FILE -- copy profile/candidate.example.md to profile/candidate.md and fill it in first." >&2
  exit 1
fi
# Each track gets its own .work scratch dir so a working-student batch run and a
# full-time batch run can never collide over the same positions.tsv/result/log files.
WORK_DIR="$APP_DIR/scripts/.work/$([[ "$FULLTIME" == "true" ]] && echo "fulltime" || echo "working_student")"
LOG_DIR="$WORK_DIR/logs"
WORKERS_DIR="$WORK_DIR/workers"

# Detects Claude's own usage/session-limit message in a worker's log. Once this
# fires, no NEW workers are launched -- already-running ones are still waited on
# (bounded by --worker-timeout so nothing can hang forever), then the merge step
# runs as normal so nothing that did complete is left stranded.
LIMIT_HIT=false
check_limit_hit() {
  local log_file="$1"
  if [[ -f "$log_file" ]] && grep -qiE "session limit|usage limit|rate.?limit" "$log_file"; then
    if [[ "$LIMIT_HIT" == "false" ]]; then
      echo ""
      echo "!!! Claude usage/session limit detected in $log_file -- stopping launch of new workers."
      echo "!!! Already-running workers will finish (or be killed after ${WORKER_TIMEOUT}s), then results will be merged."
    fi
    LIMIT_HIT=true
  fi
}

APPLIED_COUNT=0
DEAD_COUNT=0
VERIFY_COUNT=0
EMAIL_COUNT=0
NO_RESULT=0

# Ensures positions.md has a "## Need Verification" section before we append an
# entry to it. Need Verification must stay ABOVE "## Skipped" (the user wants new
# verification entries listed before the skipped-jobs section, never after it),
# so this is created right before "## Skipped" if that section already exists,
# otherwise at the end of the file as before.
#
# NOTE: entries here are NOT a markdown pipe-table. A table forces every entry
# onto one unbroken line with no blank-line separation (blank lines end a
# table), which is unreadable once the Reason text is a full sentence or two --
# and previously caused all these entries to render as one cramped wall of
# text. Each entry below is instead a small blank-line-separated block. Also
# deliberately avoids `#`/`##`/etc. headings per entry: extract_positions()
# (see below) treats ANY line starting with 1-4 `#` characters as a new
# section header and re-checks whether ITS title contains "need verification"
# -- a per-entry heading would flip that flag off mid-section and cause these
# entries to be mis-parsed as fresh "to apply" rows and re-dispatched to workers.
ensure_need_verification_section() {
  if ! grep -qi '^## Need Verification' "$POSITIONS_FILE"; then
    if grep -qi '^## Skipped' "$POSITIONS_FILE"; then
      insert_before_skipped $'\n## Need Verification'
    else
      {
        echo ""
        echo "## Need Verification"
      } >> "$POSITIONS_FILE"
    fi
  fi
}

# Appends $1 (a block of one or more lines) into positions.md right before the
# "## Skipped" section header, so Need Verification entries always land above
# Skipped rather than after it. Falls back to appending at end of file if no
# "## Skipped" section exists yet.
insert_before_skipped() {
  local text="$1"
  if grep -qi '^## Skipped' "$POSITIONS_FILE"; then
    python3 - "$POSITIONS_FILE" "$text" <<'PYEOF'
import sys
filepath, text = sys.argv[1], sys.argv[2]
with open(filepath, encoding="utf-8") as f:
    lines = f.readlines()
idx = next(i for i, l in enumerate(lines) if l.strip().lower() == "## skipped")
insertion = [line + "\n" for line in text.split("\n")]
lines[idx:idx] = insertion
with open(filepath, "w", encoding="utf-8") as f:
    f.writelines(lines)
PYEOF
  else
    printf '%s\n' "$text" >> "$POSITIONS_FILE"
  fi
}

# Moves a position into the Need Verification section with a specific reason,
# removing its old "to apply" row (if any) so it isn't listed twice. Used both
# for explicit VERIFY results and for workers that produced no result at all.
move_to_need_verification() {
  local pos_id="$1" role="$2" section="$3" url="$4" reason="$5"
  if [[ -n "$url" ]] && grep -qF "$url" "$POSITIONS_FILE"; then
    # If this URL is already recorded as a Need Verification entry (can happen
    # if a position is retried across runs, or re-merged), don't add a second
    # entry for it -- just leave the existing one in place.
    if awk '/^## Need Verification/{f=1} /^## Skipped/{f=0} f' "$POSITIONS_FILE" | grep -qF "$url"; then
      echo "  Skipping duplicate Need Verification entry (already recorded): $role"
      return 0
    fi
    grep -v -F "$url" "$POSITIONS_FILE" > "$POSITIONS_FILE.tmp" && mv "$POSITIONS_FILE.tmp" "$POSITIONS_FILE"
  fi
  ensure_need_verification_section
  echo "  Needs verification (moved): $role -- ${reason:-no reason given}"
  VERIFY_COUNT=$((VERIFY_COUNT + 1))
  local found apply_line
  found=$(date +%Y-%m-%d)
  if [[ -n "$url" ]]; then
    apply_line="[Apply]($url)"
  else
    apply_line="no link found -- needs manual lookup"
  fi
  local entry
  entry=$'\n'"- **#${pos_id} -- ${section} -- ${role}**"$'\n'"  Found: ${found} | Reason: ${reason:-No reason given}"$'\n'"  Apply: ${apply_line}"
  insert_before_skipped "$entry"
}

# Positions whose only application path is emailing materials directly (no web
# form exists at all) live in their own standalone file, needs_manual_email.md
# -- NOT a section inside positions.md. Same blank-line-separated block format
# as Need Verification, just in a separate file. Creates the file with a header
# on first use.
ensure_needs_manual_email_file() {
  if [[ ! -f "$NEEDS_MANUAL_EMAIL_FILE" ]]; then
    {
      echo "# Needs Manual Email"
      echo ""
      echo "> Positions whose only application path is emailing materials directly -- no web application form exists at all. Attach the documents (resume, cover letter, transcript, reference letter as applicable) and send manually."
    } > "$NEEDS_MANUAL_EMAIL_FILE"
  fi
}

# Moves a position into needs_manual_email.md. Mirrors move_to_need_verification()
# but for the EMAIL result status, and targets the standalone file instead of a
# section within positions.md.
move_to_needs_manual_email() {
  local pos_id="$1" role="$2" section="$3" url="$4" reason="$5"
  if [[ -n "$url" ]] && grep -qF "$url" "$POSITIONS_FILE"; then
    grep -v -F "$url" "$POSITIONS_FILE" > "$POSITIONS_FILE.tmp" && mv "$POSITIONS_FILE.tmp" "$POSITIONS_FILE"
  fi
  ensure_needs_manual_email_file
  if [[ -n "$url" ]] && grep -qF "$url" "$NEEDS_MANUAL_EMAIL_FILE"; then
    echo "  Skipping duplicate Needs Manual Email entry (already recorded): $role"
    return 0
  fi
  echo "  Needs manual email (moved): $role -- ${reason:-no reason given}"
  EMAIL_COUNT=$((EMAIL_COUNT + 1))
  local found apply_line
  found=$(date +%Y-%m-%d)
  if [[ -n "$url" ]]; then
    apply_line="[Apply]($url)"
  else
    apply_line="no link found -- needs manual lookup"
  fi
  {
    echo ""
    echo "- **#${pos_id} -- ${section} -- ${role}**"
    echo "  Found: ${found} | Email: ${reason:-No reason given}"
    echo "  Apply: ${apply_line}"
  } >> "$NEEDS_MANUAL_EMAIL_FILE"
}

# Merges a single worker's result file into applied.md / positions.md IMMEDIATELY.
# Called right when each worker finishes (not batched at the very end) so a job is
# never left showing as "unapplied" in positions.md after it has actually been
# submitted -- that gap is what let the same position get applied to twice across
# separate/overlapping runs.
#
# Removes a single position's row (matched by URL) from positions.md, then --
# same rule check-listings.sh already follows -- if that was the only data row
# left under its "### Company" section, deletes the now-empty header+table too
# instead of leaving an orphaned section behind. Used for both APPLIED and DEAD
# results below; previously each did a bare `grep -v "$url"` that stripped the
# row but never touched the section, so applying to (or losing) a company's
# only listing left a permanent empty "### Company" tombstone in the file --
# these had been silently accumulating across passes.
remove_position_row() {
  local url="$1"
  python3 - "$POSITIONS_FILE" "$url" <<'PYEOF'
import re, sys

filepath, target_url = sys.argv[1], sys.argv[2]
with open(filepath, "r", encoding="utf-8") as f:
    lines = f.readlines()

step1 = []
for line in lines:
    stripped = line.strip()
    if target_url and target_url in line and stripped.startswith('|') and not re.fullmatch(r'[|:\-\s]+', stripped):
        continue
    step1.append(line)

out = []
i, n = 0, len(step1)
while i < n:
    line = step1[i]
    if re.match(r'^###\s+', line):
        j = i + 1
        data_row_found = False
        while j < n and not re.match(r'^#{1,4}\s+', step1[j]):
            s = step1[j].strip()
            if s.startswith('|') and not re.fullmatch(r'[|:\-\s]+', s):
                data_row_found = True
            j += 1
        if not data_row_found:
            i = j
            continue
        out.extend(step1[i:j])
        i = j
        continue
    out.append(line)
    i += 1

with open(filepath, "w", encoding="utf-8") as f:
    f.writelines(out)
PYEOF
}

# $2/$3 (ats/section) are looked up from the worker_id's original TSV row.
# $4/$5/$6 (url/role/log_file) are the ORIGINAL position's url/role and the
# worker's log path -- only used as a fallback when the result file is missing
# entirely (worker crashed/timed out/exited without writing one), so that case
# still produces a Need Verification entry instead of silently doing nothing.
merge_result_file() {
  local result_file="$1" ats="$2" section="$3" orig_url="${4:-}" orig_role="${5:-}" log_file="${6:-}"
  if [[ ! -f "$result_file" ]]; then
    if [[ -n "$orig_url" ]]; then
      local reason="Worker exited without writing a result (crash, timeout, or stopped early) -- application status unknown, verify manually before retrying."
      if [[ -n "$log_file" && -s "$log_file" ]]; then
        reason="Worker exited without a result. Last worker output: $(tail -c 400 "$log_file" | tr '\n' ' ' | tr -s ' ')"
      fi
      move_to_need_verification "?" "${orig_role:-Unknown role}" "$section" "$orig_url" "$reason"
    fi
    return 0
  fi
  local today; today=$(date +%Y-%m-%d)
  # Only parse the FIRST line of each result file (workers may append extra text below)
  local first_line status pos_id role url reason_or_date
  first_line=$(head -1 "$result_file")
  IFS='|' read -r status pos_id role url reason_or_date <<< "$first_line"
  case "$status" in
    APPLIED)
      if [[ -n "$url" ]] && grep -qF "$url" "$APPLIED_FILE"; then
        echo "  Skipping (already recorded in applied.md): $role"
      else
        echo "  Applied (recording now): $role"
        APPLIED_COUNT=$((APPLIED_COUNT + 1))
        {
          echo ""
          echo "## $section"
          echo ""
          echo "| Role | Date Applied | Platform | Status |"
          echo "|------|--------------|----------|--------|"
          echo "| [$role]($url) | ${reason_or_date:-$today} | $ats | Submitted |"
        } >> "$APPLIED_FILE"
      fi
      if [[ -n "$url" ]]; then
        remove_position_row "$url"
      fi
      ;;
    DEAD)
      echo "  Dead listing (removed): $role"
      DEAD_COUNT=$((DEAD_COUNT + 1))
      if [[ -n "$url" ]]; then
        remove_position_row "$url"
      fi
      ;;
    VERIFY)
      move_to_need_verification "$pos_id" "$role" "$section" "$url" "$reason_or_date"
      ;;
    EMAIL)
      move_to_needs_manual_email "$pos_id" "$role" "$section" "$url" "$reason_or_date"
      ;;
    *)
      echo "  No parseable result yet: $(basename "$result_file")"
      NO_RESULT=$((NO_RESULT + 1))
      return 1
      ;;
  esac
  # Keep counters live after every single merge, not just at the end of the whole batch
  if [[ "$FULLTIME" == "true" ]]; then
    "$SCRIPT_DIR/update-counters.sh" --fulltime > /dev/null
  else
    "$SCRIPT_DIR/update-counters.sh" > /dev/null
  fi
  return 0
}

mkdir -p "$WORK_DIR" "$LOG_DIR" "$WORKERS_DIR"

# ------------------------------------------------------------------
# Step 1: Extract unapplied positions from positions.md
# ------------------------------------------------------------------
extract_positions() {
  python3 - "$POSITIONS_FILE" <<'PYEOF'
import re, sys

filepath = sys.argv[1]
with open(filepath, "r") as f:
    lines = f.readlines()

current_section = ""
in_skip_section = False
results = []

for i, line in enumerate(lines):
    header_match = re.match(r'^#{1,4}\s+(.+)', line)
    if header_match:
        current_section = header_match.group(1).strip()
        title_lower = current_section.lower()
        in_skip_section = "need verification" in title_lower or "needs manual email" in title_lower
        continue

    if in_skip_section:
        continue

    # Skip non-table rows and header/separator rows
    stripped_line = line.strip()
    if not stripped_line.startswith('|'):
        continue
    if re.fullmatch(r'[|:\-\s]+', stripped_line):
        continue

    # Greedy \S+ (not [^\s)]+) so a URL that itself contains parentheses --
    # e.g. https://jobs.sap.com/job/Walldorf-Working-Student-(fmd)-... -- isn't
    # truncated at the first ")" it finds. Backtracking finds the rightmost ")"
    # that still lets the rest of the pattern (end of line, optional trailing
    # " |") match, which correctly closes on the real end of the URL instead.
    url_match = re.search(r'\[(?:Apply|Search|LinkedIn|Sign up)\]\((https?://\S+)\)\s*\|?\s*$', line)
    if not url_match:
        continue

    url = url_match.group(1)

    ats = "other"
    if "myworkdayjobs.com" in url:
        ats = "workday"
    elif "greenhouse.io" in url:
        ats = "greenhouse"
    elif "ashbyhq.com" in url:
        ats = "ashby"
    elif "lever.co" in url:
        ats = "lever"
    elif "workable.com" in url:
        ats = "workable"
    elif "recruitee.com" in url:
        ats = "recruitee"

    cols = [c.strip() for c in line.split('|')[1:-1]]
    pos_id = cols[0] if len(cols) > 0 else f"L{i}"
    role = cols[1] if len(cols) > 1 else "Unknown"

    results.append(f"{i}\t{pos_id}\t{role}\t{url}\t{ats}\t{current_section}")

for r in results:
    print(r)
PYEOF
}

echo "=== Batch Apply Orchestrator ==="
echo "Track: $TRACK_LABEL"
echo "Positions file: $POSITIONS_FILE"
echo "Parallel workers: $PARALLEL"
echo "Model: $MODEL | Effort: $EFFORT | Browser windows: $([[ "$HEADLESS" == "true" ]] && echo "hidden (headless)" || echo "visible")"
echo ""

# Extract all unapplied positions
POSITIONS_TSV="$WORK_DIR/positions.tsv"
extract_positions > "$POSITIONS_TSV"

TOTAL=$(wc -l < "$POSITIONS_TSV" | tr -d ' ')
echo "Found $TOTAL unapplied positions"

# Filter by ATS if specified
if [[ -n "$ATS_FILTER" ]]; then
  FILTERED="$WORK_DIR/positions_filtered.tsv"
  awk -F'\t' -v ats="$ATS_FILTER" '$5 == ats' "$POSITIONS_TSV" > "$FILTERED"
  POSITIONS_TSV="$FILTERED"
  TOTAL=$(wc -l < "$POSITIONS_TSV" | tr -d ' ')
  echo "After ATS filter ($ATS_FILTER): $TOTAL positions"
fi

# Apply max limit
if [[ "$MAX_POSITIONS" -lt "$TOTAL" ]]; then
  head -n "$MAX_POSITIONS" "$POSITIONS_TSV" > "$WORK_DIR/positions_limited.tsv"
  POSITIONS_TSV="$WORK_DIR/positions_limited.tsv"
  TOTAL=$MAX_POSITIONS
  echo "Limited to $MAX_POSITIONS positions"
fi

if [[ "$TOTAL" -eq 0 ]]; then
  echo "No positions to apply to. Exiting."
  exit 0
fi

echo ""
echo "Positions to process:"
echo "---------------------"
n=0
while IFS=$'\t' read -r lineno pos_id role url ats section; do
  n=$((n + 1))
  printf "  %7s  [%s] %-5s %-60s %s\n" "$n/$TOTAL" "$ats" "$pos_id" "${role:0:60}" "${url:0:50}..."
done < "$POSITIONS_TSV"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY RUN] Would launch $TOTAL workers. Exiting."
  exit 0
fi

# ------------------------------------------------------------------
# Step 2: Create per-worker isolated environments and launch
# ------------------------------------------------------------------

# Each worker gets its own directory with:
#   - .claude.json: Playwright MCP configured with --headless + unique --user-data-dir#   - This ensures each worker has a fully independent browser instance
create_worker_env() {
  local worker_num="$1"
  local worker_dir="$WORKERS_DIR/worker_${worker_num}"
  local browser_data_dir="$worker_dir/browser_data"

  mkdir -p "$worker_dir" "$browser_data_dir"

  # Create .claude.json with isolated Playwright config
  local headless_json_arg=""
  if [[ "$HEADLESS" == "true" ]]; then
    headless_json_arg='        "--headless",
'
  fi
  cat > "$worker_dir/.claude.json" <<MCPEOF
{
  "mcpServers": {
    "playwright": {
      "type": "stdio",
      "command": "npx",
      "args": [
        "@playwright/mcp@latest",
${headless_json_arg}        "--user-data-dir", "$browser_data_dir"
      ],
      "env": {}
    }
  }
}
MCPEOF

  echo "$worker_dir"
}

# Per-track framing injected into every worker's prompt below -- keeps the same
# worker/prompt logic for both tracks while changing how it talks about the role
# and how it should frame cover letters/open-ended answers.
if [[ "$FULLTIME" == "true" ]]; then
  TRACK_NOTE="TRACK: FULL-TIME. This position is from the full-time entry-level track (same role scope as the working-student track, see the agent file). Only flag a mismatch for a genuine disqualifier (multi-year experience requirement, location outside the target country, or the role turning out to be a working-student/internship position). Frame the cover letter and any open-ended answers as a candidate seeking a full-time entry-level role, not a working-student/internship position."
else
  TRACK_NOTE="TRACK: WORKING-STUDENT. Frame the cover letter and any open-ended answers as a current student seeking a working-student position, as usual."
fi

RUNNING=0
COMPLETED=0
FAILED=0
WORKER_NUM=0
FINISHED=0
PIDS=()
# worker_id -> "N/TOTAL" job number, so every start/finish line says which job it is
declare -A JOB_TAG

# Prints the finish line for one job plus the running "X/TOTAL finished" count.
report_finished() {
  local wid="$1" status="$2"
  FINISHED=$((FINISHED + 1))
  echo ">>> [JOB ${JOB_TAG[$wid]:-?/$TOTAL}] $wid -- $status   (progress: $FINISHED/$TOTAL finished)"
}

launch_worker() {
  local lineno="$1" pos_id="$2" role="$3" url="$4" ats="$5" section="$6"
  local worker_id="${pos_id//\//_}"
  local log_file="$LOG_DIR/worker_${worker_id}.log"
  local result_file="$WORK_DIR/result_${worker_id}.md"

  # Create isolated worker environment
  WORKER_NUM=$((WORKER_NUM + 1))
  local worker_dir
  worker_dir=$(create_worker_env "$WORKER_NUM")

  local prompt
  prompt=$(cat <<PROMPT
You are applying to a job on behalf of the candidate described in $PROFILE_FILE.

$TRACK_NOTE

⚠️ MANDATORY: Read $AGENT_FILE FIRST and follow EVERY instruction in it strictly. Together with $PROFILE_FILE (candidate details, standing answers, credentials), that file is your single source of truth for form-filling rules, ATS-specific workarounds, writing tone, and all application behavior. Do NOT deviate from it. Do NOT guess candidate details -- they are all in $PROFILE_FILE.

POSITION DETAILS:
- Position ID: $pos_id
- Role: $role
- URL: $url
- ATS Type: $ats
- Company Section: $section

YOUR TASK:
1. Navigate to the URL above using browser_navigate
2. If the URL leads to a generic careers page (not a specific job posting), navigate it, find all relevant ML/AI/DS roles, and apply to each one
3. Apply to this position following the JOB_APPLICATION_AGENT.md instructions exactly
4. Use the SPEED OPTIMIZATIONS: minimize snapshots (one at start, batch all actions in browser_run_code, one to verify before submit)
5. For email verification / OTP: use the candidate email from $PROFILE_FILE and retrieve codes via Gmail MCP (see agent file for details)
6. After successful submission -- meaning you actually clicked the final Submit/Apply button AND saw a confirmation (a "thank you"/"application received" page or message) -- write the result to: $result_file
   Format: "APPLIED|$pos_id|$role|$url|$(date +%Y-%m-%d)"
   NEVER write APPLIED if you did not see that confirmation. If you filled the form but are not certain it actually submitted, that is a VERIFY case (see below), not APPLIED.
7. If the listing is dead/closed, write: "DEAD|$pos_id|$role|$url"
8. If the site shows a simple one-click captcha checkbox and it clears immediately, continue. But if a real challenge appears (image puzzle, text challenge, multiple-step verification, or repeated anti-bot gate), do NOT keep retrying. Write: "VERIFY|$pos_id|$role|$url|captcha challenge requires manual handling"
9. If the application is hosted on iCIMS or the page shows "Software Powered by iCIMS" / "www.icims.com", do NOT apply in batch mode. Write: "VERIFY|$pos_id|$role|$url|iCIMS requires manual handling"
10. If no web application form exists at all for this role and the only way to apply is emailing your materials directly to an address, do NOT try to send it yourself. Write: "EMAIL|$pos_id|$role|$url|<the email address to send to> -- <one-line note on what to send>"
11. **MANDATORY CATCH-ALL -- every job MUST end in exactly one of APPLIED / DEAD / VERIFY / EMAIL, no exceptions.** There is no "skip silently" outcome and no user available to ask mid-run. If you open this listing and, for ANY reason not covered above, do not end up submitting it -- an unclear/ambiguous screening question, an error, a field you can't fill, running low on time, genuine uncertainty about an answer -- you MUST still write a VERIFY result with your best specific explanation of why, e.g.:
   "VERIFY|$pos_id|$role|$url|unclear screening question: '<exact question text>' -- needs a human answer before this can be submitted"
   Do NOT end your turn having written nothing to $result_file. A job you opened but didn't finish is a VERIFY with a reason, never a silent nothing.

CRITICAL RULES (all from $AGENT_FILE -- re-read it if unsure):
- Work authorization, visa sponsorship, availability, travel, and enrollment: use the standing answers in $PROFILE_FILE. If asked about authorization for a country not covered there, STOP and write a VERIFY result instead of guessing.
- If a Login/Sign in option exists, ALWAYS try logging in first before anything else -- it saves tokens versus filling everything manually and often unlocks autofill-from-profile shortcuts.
- Pick answers that MAXIMIZE interview probability
- Do NOT be verbose in open-ended answers
- Resume PDF: $APP_DIR/documents/resume.pdf
- Transcript: $APP_DIR/documents/transcript.pdf
- All documents live in $APP_DIR/documents/ -- upload them straight from there. NEVER copy any document into $APP_DIR (or anywhere else), even if a path seems missing; list $APP_DIR/documents/ and report a truly missing file in your result instead.
- ALWAYS provide a cover letter if the form has a required or optional cover letter / motivation field -- do not skip it just because it's optional. Save a copy to $APP_DIR/cover_letters/.
- ALWAYS attach the reference letter ($APP_DIR/documents/reference_letter.pdf) whenever the form has ANY upload slot beyond the resume alone -- "additional documents", "references", "attachments", "other files", a second file-upload button, etc. This is not optional or situational -- check every form for such a slot and attach it. Only skip if the form truly allows just a single resume upload with no other file field anywhere.
- Workday "How Did You Hear About Us?" is ALWAYS a cascaded/nested dropdown -- select a sub-option, not just the category, then press Escape
- Do NOT abandon an application mid-form just because the page/form turns out to be in German. The German-language exclusion is a collection-time filter only (whether a listing gets added to positions.md), not a reason to stop once you've opened the form. Translate/match German questions to the "Default answers" list in $AGENT_FILE and keep going. Only write VERIFY if a specific field is genuinely ambiguous, never simply because the surrounding language is German -- you've already spent the time/compute to get this far.
PROMPT
)

  local job_tag="$WORKER_NUM/$TOTAL"
  JOB_TAG[$worker_id]="$job_tag"
  echo ""
  echo "=================================================================="
  echo "  JOB $job_tag   |   $pos_id   |   $role"
  echo "  Company: $section   |   ATS: $ats"
  echo "=================================================================="
  echo "[JOB $job_tag] [Worker $worker_id] Starting [browser: $worker_dir/browser_data]"
  echo "=== JOB $job_tag | $pos_id | $role | $section ===" > "$log_file"

  # Launch claude -p from the worker directory so it picks up the isolated .claude.json.
  # Wrapped in `timeout` so a hung worker (e.g. an unclosed browser keeping the process
  # alive) can never block this script from reaching the merge step -- it gets SIGTERM'd
  # after $WORKER_TIMEOUT seconds, then SIGKILL'd 30s later if it's still not gone.
  (cd "$worker_dir" && timeout --kill-after=30s "${WORKER_TIMEOUT}s" claude -p "$prompt" \
    --model "$MODEL" \
    --effort "$EFFORT" \
    --dangerously-skip-permissions \
    >> "$log_file" 2>&1 < /dev/null) &
  local pid=$!
  # Tab-delimited, NOT colon-delimited -- $url contains "://" plus possibly more
  # colons (ports etc.), which used to shift every field after it when this was
  # joined/split on ':' (e.g. a role landing in $wats, corrupting applied.md
  # section headers like "## ashby:Enpal" or "## other:BMW Group"). Tabs never
  # appear in these fields.
  PIDS+=("$pid"$'\t'"$worker_id"$'\t'"$lineno"$'\t'"$pos_id"$'\t'"$role"$'\t'"$url"$'\t'"$ats"$'\t'"$section")
  RUNNING=$((RUNNING + 1))
}

# Process positions with parallelism limit
#
# CRITICAL: reads from fd 3, not stdin (fd 0). This loop backgrounds `claude -p`
# workers (see launch_worker) while it is still iterating; if the loop's input
# were bound to stdin, a background child inheriting fd 0 could silently consume
# bytes out of $POSITIONS_TSV mid-loop (a classic `while read < file; do cmd & done`
# bug), corrupting later `read` calls -- this is what caused garbled/truncated
# rows (embedded newlines splitting a row in two, missing Apply links) in
# positions.md's Need Verification section. Keeping the file on fd 3 means only
# this loop's own `read -u 3` touches it; child processes' stdin is unaffected
# (and launch_worker also explicitly redirects the worker's stdin from /dev/null
# as a second layer of defense).
while IFS=$'\t' read -r -u 3 lineno pos_id role url ats section; do
  # Wait if we've hit the parallel limit
  while [[ $RUNNING -ge $PARALLEL ]]; do
    for i in "${!PIDS[@]}"; do
      IFS=$'	' read -r pid wid wlineno wposid wrole wurl wats wsection <<< "${PIDS[$i]}"
      if ! kill -0 "$pid" 2>/dev/null; then
        wait "$pid" && {
          report_finished "$wid" "worker exited OK"
          COMPLETED=$((COMPLETED + 1))
        } || {
          report_finished "$wid" "worker FAILED (exit code $?)"
          FAILED=$((FAILED + 1))
        }
        check_limit_hit "$LOG_DIR/worker_${wid}.log"
        # Record the result in applied.md / positions.md right away -- do not wait
        # for the rest of the batch, so this position can never be picked up again
        # by another run before it's marked done.
        if merge_result_file "$WORK_DIR/result_${wid}.md" "$wats" "$wsection" "$wurl" "$wrole" "$LOG_DIR/worker_${wid}.log"; then
          # Rename so the Final Safety-Net Merge Pass below doesn't re-merge this
          # same result a second time (that duplicate-merge is what produced the
          # "Uncategorized"-labeled duplicate Need Verification rows).
          mv -f "$WORK_DIR/result_${wid}.md" "$WORK_DIR/result_${wid}.md.done" 2>/dev/null || true
        fi
        RUNNING=$((RUNNING - 1))
        unset 'PIDS[i]'
      fi
    done
    # Compact the array
    PIDS=("${PIDS[@]}")
    sleep 2
  done

  if [[ "$LIMIT_HIT" == "true" ]]; then
    echo "Stopping dispatch of new positions (usage limit hit earlier). Remaining unprocessed positions stay in positions.md for the next run."
    break
  fi

  launch_worker "$lineno" "$pos_id" "$role" "$url" "$ats" "$section"
done 3< "$POSITIONS_TSV"

# Wait for remaining workers (bounded by --worker-timeout per worker, so this always
# terminates even if a browser/worker hangs -- guaranteeing we reach the merge step below)
echo ""
echo "All workers launched. Waiting for completion..."
TOTAL_WORKERS=0
for pid_info in "${PIDS[@]}"; do
  IFS=$'	' read -r pid wid wlineno wposid wrole wurl wats wsection <<< "$pid_info"
  wait "$pid" || true  # Don't care about exit code -- claude -p returns 1 even on success
  check_limit_hit "$LOG_DIR/worker_${wid}.log"
  if merge_result_file "$WORK_DIR/result_${wid}.md" "$wats" "$wsection" "$wurl" "$wrole" "$LOG_DIR/worker_${wid}.log"; then
    mv -f "$WORK_DIR/result_${wid}.md" "$WORK_DIR/result_${wid}.md.done" 2>/dev/null || true
  fi
  TOTAL_WORKERS=$((TOTAL_WORKERS + 1))
  report_finished "$wid" "done"
done

# ------------------------------------------------------------------
# Step 3: safety-net pass + cleanup
# ------------------------------------------------------------------
# Every worker's result was already merged into applied.md/positions.md the moment
# it finished (above), not batched until now -- this avoids the same position ever
# being picked up twice by an overlapping/rerun before results are recorded. This
# is just a catch-all in case any result file was somehow missed.
echo ""
echo "=== Final Safety-Net Merge Pass ==="
for result_file in "$WORK_DIR"/result_*.md; do
  merge_result_file "$result_file" "unknown" "Uncategorized" || true
done

# Archive processed result/log files instead of leaving them to accumulate --
# stale results from a prior run sitting alongside new ones is exactly what
# caused completed applications (Fraunhofer IIS, Sopra Steria) to go unmerged
# and undetected after an earlier interrupted run.
ARCHIVE_DIR="$WORK_DIR/archive/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ARCHIVE_DIR"
mv "$WORK_DIR"/result_*.md "$ARCHIVE_DIR/" 2>/dev/null || true
mv "$WORK_DIR"/result_*.md.done "$ARCHIVE_DIR/" 2>/dev/null || true
mv "$LOG_DIR"/worker_*.log "$ARCHIVE_DIR/" 2>/dev/null || true

# Clean up worker environments (browser data can be large)
echo ""
echo "Cleaning up worker browser profiles..."
rm -rf "$WORKERS_DIR"

# Keep the "to apply / needs verification / applied" counters in sync
if [[ "$FULLTIME" == "true" ]]; then
  "$SCRIPT_DIR/update-counters.sh" --fulltime
else
  "$SCRIPT_DIR/update-counters.sh"
fi

echo ""
echo "=== Summary ==="
echo "  Track: $TRACK_LABEL"
echo "  Workers launched: $TOTAL_WORKERS"
echo "  Applied: $APPLIED_COUNT"
echo "  Dead listings removed: $DEAD_COUNT"
echo "  Need verification: $VERIFY_COUNT"
echo "  Needs manual email: $EMAIL_COUNT"
echo "  No result file: $NO_RESULT"
echo ""
echo "Worker logs: $LOG_DIR/"
echo ""
echo "\"$APPLIED_FILE\" and \"$POSITIONS_FILE\" have been updated automatically."
