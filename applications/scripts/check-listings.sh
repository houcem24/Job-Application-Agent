#!/usr/bin/env bash
#
# check-listings.sh -- Check job listing URLs and auto-remove dead ones
#
# Usage:
#   ./scripts/check-listings.sh [--max N] [--ats TYPE] [--dry-run] [--fulltime]
#
# Launches a `claude -p` worker that navigates to each URL, checks if it's alive,
# and automatically removes dead listings from positions.md.
#
#   --fulltime   Check the "full time applications/positions.md" track instead of
#                the default "working student applications/positions.md" track.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"

MAX=100
ATS_FILTER=""
DRY_RUN=false
FULLTIME=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --max) MAX="$2"; shift 2 ;;
    --ats) ATS_FILTER="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --fulltime) FULLTIME=true; shift ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

if [[ "$FULLTIME" == "true" ]]; then
  TRACK_DIR="$APP_DIR/full time applications"
  WORK_DIR="$SCRIPT_DIR/.work/fulltime"
else
  TRACK_DIR="$APP_DIR/working student applications"
  WORK_DIR="$SCRIPT_DIR/.work/working_student"
fi
POSITIONS_FILE="$TRACK_DIR/positions.md"

mkdir -p "$WORK_DIR"

# Extract URLs
URLS_FILE="$WORK_DIR/urls_to_check.txt"
python3 - "$POSITIONS_FILE" "$ATS_FILTER" "$MAX" <<'PYEOF' > "$URLS_FILE"
import re, sys

filepath, ats_filter, max_count = sys.argv[1], sys.argv[2], int(sys.argv[3])

with open(filepath) as f:
    lines = f.readlines()

count = 0
for line in lines:
    stripped = line.strip()
    if not stripped.startswith('|') or '---|' in stripped:
        continue
    url_match = re.search(r'\[(?:Apply|Search|LinkedIn|Sign up)\]\((https?://[^\s)]+)\)', line)
    if not url_match:
        continue
    url = url_match.group(1)

    if ats_filter:
        ats_map = {
            "workday": "myworkdayjobs.com",
            "greenhouse": "greenhouse.io",
            "ashby": "ashbyhq.com",
            "lever": "lever.co",
        }
        if ats_filter in ats_map and ats_map[ats_filter] not in url:
            continue

    print(url)
    count += 1
    if count >= max_count:
        break
PYEOF

TOTAL=$(wc -l < "$URLS_FILE" | tr -d ' ')
echo "=== Check Listings ==="
echo "Found $TOTAL URLs to check"
echo ""

if [[ "$TOTAL" -eq 0 ]]; then
  echo "No URLs to check. Exiting."
  exit 0
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY RUN] URLs that would be checked:"
  cat "$URLS_FILE"
  exit 0
fi

URLS=$(cat "$URLS_FILE" | tr '\n' ' ')

PROMPT=$(cat <<EOF
You are checking job listing URLs for dead/expired positions.

POSITIONS FILE: $POSITIONS_FILE

URLS TO CHECK:
$URLS

INSTRUCTIONS:
1. For each URL, use browser_navigate to visit it.
2. Check if the listing is dead. Dead indicators:
   - "Page not found", "404", "can't find that page"
   - "No longer accepting applications", "This job is closed"
   - "Custom Job Error", "We couldn't find this job"
   - Redirects to a completely different company or unrelated page
   - "410 Gone"
   - Deadline explicitly passed (e.g., "Applications closed March 22, 2026")
3. For EACH dead URL, remove its entire row from the positions file ($POSITIONS_FILE) using the Edit tool.
   - If removing a row leaves a section with only a table header and separator (no data rows), delete the entire section (header + table).
   - If a parent section also becomes empty, delete it too.
   - Update the Table of Contents if you delete a section.
4. After checking all URLs, print a summary:
   - How many were alive
   - How many were dead (and which ones you removed)
   - Any that were ambiguous

IMPORTANT: Actually edit the file to remove dead listings. Do NOT just report them -- remove them.
Do batch checking: navigate to each URL quickly, check the page title/content, move on. Don't spend more than 10 seconds per URL.
EOF
)

echo "Launching checker..."
echo ""
claude -p "$PROMPT"

echo ""
echo "=== Done ==="
echo "Dead listings have been removed from $POSITIONS_FILE."
