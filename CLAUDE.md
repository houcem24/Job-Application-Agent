# CLAUDE.md

Agent orientation for this repository: an AI-driven job search and application pipeline built on Claude Code and the
Playwright MCP. It finds working-student and junior data/AI/ML roles in Germany, tracks them in Markdown, and fills
out application forms automatically.

## Where Things Are

| What | Where |
|------|-------|
| Candidate details, credentials, standing answers | `profile/candidate.md` (gitignored; template: `candidate.example.md`) |
| CV source (single source of truth for profile content) | `resume/cv_4.tex` |
| Agent rules: search methods, apply workflow, ATS playbook | `applications/JOB_APPLICATION_AGENT.md` |
| Copy-paste prompts and script usage | `applications/USAGE.md` |
| Trackers | `applications/working student applications/`, `applications/full time applications/` |
| Upload copies of documents | `applications/documents/` |

## Common Tasks

- **Update the CV:** edit `resume/cv_4.tex`, then run `resume/build.sh` (Git Bash on Windows). It builds `cv_4.pdf`
  plus a hyperlink-free copy and refreshes `applications/documents/resume.pdf` and `resume_clean.pdf`.
- **Search / apply / triage:** follow `applications/USAGE.md`.
- **Batch apply:** `applications/scripts/batch-apply.sh --parallel N` (add `--fulltime` for the full-time track).

## Rules for Agents

- Read `profile/candidate.md` before filling any form. Never invent a candidate detail; ask instead.
- Never misrepresent a checkable qualification (language level, degree, experience, residence).
- Never submit an application through linkedin.com itself; resolve to the employer's own ATS.
- Record each application in `applied.md` immediately after submitting, and check `applied.md` before applying.
- Upload documents straight from `applications/documents/`; never copy them elsewhere.
- Never commit `profile/candidate.md`, `applications/documents/`, reports, or generated cover letters.

## Environment Notes

- Shell scripts are bash and need Git Bash on Windows.
- LaTeX: `pdflatex` (MiKTeX on Windows, TeX Live elsewhere).
- Python 3 is used by `update-counters.sh`, `check-listings.sh`, and the LinkedIn search helpers (`requests`).
- Paths contain spaces (`working student applications/`); always quote them.
