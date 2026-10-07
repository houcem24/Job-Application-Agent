#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
  cat <<EOF
Usage: ./build_cover_letter.sh <Company_Role.tex> [--plain]

Compiles a filled-in cover letter .tex file (copied from cover_letter_template.tex)
to a PDF of the same basename, in this directory.

--plain   Strip hyperlink/active-content annotations (no hyperref, contact info
          as plain text). Use when a form's upload scanner rejects/silently fails
          on the normal PDF (some ATS platforms flag embedded link actions as
          "active content").
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

TEX_FILE="$1"
PLAIN_FLAG="${2:-}"
if [[ -n "$PLAIN_FLAG" && "$PLAIN_FLAG" != "--plain" ]]; then
  usage
  exit 1
fi

if [[ ! -f "$TEX_FILE" ]]; then
  echo "File not found: $TEX_FILE" >&2
  exit 1
fi

BASE="${TEX_FILE%.tex}"

if [[ "$PLAIN_FLAG" == "--plain" ]]; then
  touch "$BASE.plain"
  echo "Building cover letter (plain, no active content): $BASE.pdf"
else
  echo "Building cover letter: $BASE.pdf"
fi

pdflatex -interaction=nonstopmode "$TEX_FILE"
rm -f "$BASE.aux" "$BASE.log" "$BASE.out" "$BASE.plain"
echo "Done: $BASE.pdf"
