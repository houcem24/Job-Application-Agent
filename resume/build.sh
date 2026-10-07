#!/usr/bin/env bash
# Compiles the CV and a link-free "clean" copy for ATS scanners that reject
# PDFs with active content, then refreshes the upload copies in
# applications/documents/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TEX_FILE="${1:-cv_4.tex}"
BASE="${TEX_FILE%.tex}"
DOCS_DIR="$SCRIPT_DIR/../applications/documents"

if [[ ! -f "$TEX_FILE" ]]; then
  echo "File not found: $TEX_FILE" >&2
  exit 1
fi

compile() {
  pdflatex -interaction=nonstopmode "$1" >/dev/null
  pdflatex -interaction=nonstopmode "$1" >/dev/null
}

echo "Building $BASE.pdf ..."
compile "$TEX_FILE"

# Clean variant: drop hyperref/hypersetup and unwrap \href{url}{text} -> text
CLEAN_TEX="${BASE}_clean.tex"
sed -E -e '/\\usepackage(\[[^]]*\])?\{hyperref\}/d' -e '/\\hypersetup/d' \
       -e 's/\\href\{[^}]*\}\{([^}]*)\}/\1/g' "$TEX_FILE" > "$CLEAN_TEX"
echo "Building ${BASE}_clean.pdf ..."
compile "$CLEAN_TEX"

rm -f ./*.aux ./*.log ./*.out "$CLEAN_TEX"

mkdir -p "$DOCS_DIR"
cp "$BASE.pdf" "$DOCS_DIR/resume.pdf"
cp "${BASE}_clean.pdf" "$DOCS_DIR/resume_clean.pdf"
rm -f "${BASE}_clean.pdf"
echo "Done: $BASE.pdf (upload copies refreshed in applications/documents/)"
