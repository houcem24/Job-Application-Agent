#!/usr/bin/env bash
#
# update-counters.sh -- Recompute and stamp live job-tracker counts.
#
# Counts:
#   - "to apply"        : rows in positions.md, excluding the "Need Verification", "Skipped",
#                          "Manual Application Required", and "Requires C1 German" sections
#   - "needs verification" : entries in the "Need Verification" section of positions.md
#   - "skipped"         : entries in the "Skipped" section of positions.md
#   - "requires manual application" : entries in the "Manual Application Required" section of positions.md
#   - "requires C1 German" : entries in the "Requires C1 German" section of positions.md (see
#                             JOB_APPLICATION_AGENT.md's Languages section -- these are never
#                             resolved by answering the screening question "Yes", only by an
#                             actual change in the candidate's German level)
#   - "needs manual email" : entries in the standalone needs_manual_email.md file
#   - "applied"         : rows in applied.md's per-company application tables
#     (the "Companies Searched -- No Relevant Roles Found" table is NOT counted --
#      those are non-applications)
#
# Writes a "> **Counts:** ..." line into positions.md (all seven counts) and a
# shorter one into needs_manual_email.md (its own count only), right after each
# file's intro blockquote. Re-run this any time a job moves between positions.md
# <-> applied.md <-> needs_manual_email.md (or in/out of Need Verification/Skipped/
# Manual Application Required/Requires C1 German) to keep the numbers live.
#
# Usage: ./scripts/update-counters.sh [--fulltime]
#
#   --fulltime   Recompute counters for the "full time applications/" track instead
#                of the default "working student applications/" track.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"

FULLTIME=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --fulltime) FULLTIME=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ "$FULLTIME" == "true" ]]; then
  TRACK_DIR="$APP_DIR/full time applications"
else
  TRACK_DIR="$APP_DIR/working student applications"
fi
POSITIONS_FILE="$TRACK_DIR/positions.md"
APPLIED_FILE="$TRACK_DIR/applied.md"
NEEDS_MANUAL_EMAIL_FILE="$TRACK_DIR/needs_manual_email.md"

read -r TO_APPLY NEEDS_VERIFICATION SKIPPED MANUAL_REQUIRED REQUIRES_C1_GERMAN NEEDS_MANUAL_EMAIL APPLIED <<< "$(python3 - "$POSITIONS_FILE" "$APPLIED_FILE" "$NEEDS_MANUAL_EMAIL_FILE" <<'PYEOF'
import re, sys, os

positions_file, applied_file, needs_manual_email_file = sys.argv[1], sys.argv[2], sys.argv[3]

# A markdown table separator row looks like "|---|---|---|" -- only pipes,
# dashes, colons (alignment markers), and whitespace. Checking for a bare
# "---" substring is not enough: a job URL slug can legitimately contain
# "---" (e.g. ".../Werkstudent-Agentic-AI---Multi-Agent-Systeme/..."),
# which would wrongly get treated as a separator and dropped from the count.
def is_separator_row(stripped_line):
    return bool(re.fullmatch(r'[|:\-\s]+', stripped_line))

# --- positions.md: count "to apply" vs "needs verification" rows ---
# "to apply" rows are still a markdown pipe-table (see JOB_APPLICATION_AGENT.md
# Task 1 rules), but "Need Verification" entries are NOT a table -- each is a
# blank-line-separated block starting with "- **#<id> -- <company> -- <role>**"
# (see move_to_need_verification() in batch-apply.sh), so it can hold a full
# Reason sentence readably instead of forcing everything onto one cramped line.
to_apply = 0
needs_verification = 0
skipped = 0
manual_required = 0
requires_c1_german = 0
needs_manual_email = 0
in_verification_section = False
in_skipped_section = False
in_manual_required_section = False
in_c1_german_section = False
verify_entry_re = re.compile(r'^-\s+\*\*#')

with open(positions_file, encoding="utf-8") as f:
    for line in f:
        header_match = re.match(r'^#{1,4}\s+(.+)', line)
        if header_match:
            title = header_match.group(1).lower()
            in_verification_section = "need verification" in title
            in_skipped_section = title.strip() == "skipped"
            in_manual_required_section = "manual application required" in title
            in_c1_german_section = "requires c1 german" in title
            continue
        stripped = line.strip()
        if in_verification_section:
            if verify_entry_re.match(stripped):
                needs_verification += 1
            continue
        if in_skipped_section:
            if verify_entry_re.match(stripped):
                skipped += 1
            continue
        if in_manual_required_section:
            if verify_entry_re.match(stripped):
                manual_required += 1
            continue
        if in_c1_german_section:
            if verify_entry_re.match(stripped):
                requires_c1_german += 1
            continue
        if not stripped.startswith('|') or is_separator_row(stripped):
            continue
        cols = [c.strip() for c in stripped.split('|')[1:-1]]
        # Data rows are bare-numeric IDs (working-student track, e.g. "42") or
        # FT-prefixed IDs (full-time track, e.g. "FT4") or the LinkedIn-scraper
        # "L<n>" convention. Anything else (e.g. "#" in the header row) is skipped.
        if not cols or not re.fullmatch(r'(FT|L)?\d+', cols[0]):
            continue  # header row (e.g. "# | Role | ...") or malformed row
        to_apply += 1

# --- needs_manual_email.md: count entries in the standalone file ---
# Same blank-line-separated block format as Need Verification, just in its own
# file instead of a section within positions.md.
if os.path.isfile(needs_manual_email_file):
    with open(needs_manual_email_file, encoding="utf-8") as f:
        for line in f:
            if verify_entry_re.match(line.strip()):
                needs_manual_email += 1

# --- applied.md: count rows in per-company application tables ---
# Every "## Company" section's table is an application table EXCEPT the
# "Companies Searched -- No Relevant Roles Found" section, which tracks
# companies with no suitable openings (not actual applications).
applied = 0
in_no_roles_section = False
header_row_re = re.compile(r'^\|\s*role\s*\|', re.IGNORECASE)

with open(applied_file, encoding="utf-8") as f:
    for line in f:
        header_match = re.match(r'^#{1,4}\s+(.+)', line)
        if header_match:
            title = header_match.group(1).lower()
            in_no_roles_section = "no relevant roles" in title or "companies searched" in title
            continue
        stripped = line.strip()
        if not stripped.startswith('|') or is_separator_row(stripped):
            continue
        if header_row_re.match(stripped):
            continue  # table header row (e.g. "| Role | Date Applied | ... |")
        if in_no_roles_section:
            continue
        applied += 1

print(f"{to_apply} {needs_verification} {skipped} {manual_required} {requires_c1_german} {needs_manual_email} {applied}")
PYEOF
)"

COUNTER_LINE="> **Counts:** ${TO_APPLY} to apply &middot; ${NEEDS_VERIFICATION} needs verification &middot; ${SKIPPED} skipped &middot; ${MANUAL_REQUIRED} requires manual application &middot; ${REQUIRES_C1_GERMAN} requires C1 German &middot; ${NEEDS_MANUAL_EMAIL} needs manual email &middot; ${APPLIED} applied"
EMAIL_COUNTER_LINE="> **Counts:** ${NEEDS_MANUAL_EMAIL} needs manual email"

stamp_counter() {
  local file="$1"
  python3 - "$file" "$COUNTER_LINE" <<'PYEOF'
import sys

filepath, counter_line = sys.argv[1], sys.argv[2]
with open(filepath, encoding="utf-8") as f:
    lines = f.readlines()

out = []
inserted = False
skip_next_blank_dup = False
i = 0
while i < len(lines):
    line = lines[i]
    # Replace an existing counter line in place
    if line.startswith("> **Counts:**"):
        out.append(counter_line + "\n")
        inserted = True
        i += 1
        continue
    out.append(line)
    # Insert right after the first blockquote intro line, if not already inserted
    if not inserted and line.strip().startswith(">") and not line.startswith("> **Counts:**"):
        # Only insert once, right after this first blockquote line
        if i + 1 >= len(lines) or not lines[i + 1].strip().startswith(">"):
            out.append(">\n")
            out.append(counter_line + "\n")
            inserted = True
    i += 1

with open(filepath, "w", encoding="utf-8") as f:
    f.writelines(out)
PYEOF
}

stamp_counter "$POSITIONS_FILE"

if [[ -f "$NEEDS_MANUAL_EMAIL_FILE" ]]; then
  COUNTER_LINE="$EMAIL_COUNTER_LINE" stamp_counter "$NEEDS_MANUAL_EMAIL_FILE"
fi

echo "Counts updated: ${TO_APPLY} to apply | ${NEEDS_VERIFICATION} needs verification | ${SKIPPED} skipped | ${MANUAL_REQUIRED} requires manual application | ${REQUIRES_C1_GERMAN} requires C1 German | ${NEEDS_MANUAL_EMAIL} needs manual email | ${APPLIED} applied"
