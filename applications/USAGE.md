# Usage Guide

Copy-paste prompts and commands for every workflow. Run the prompts in Claude Code from the `applications/` folder
(the `@` file references are relative to it).

There are **two independent tracks** (see `JOB_APPLICATION_AGENT.md`, "Two Application Tracks"):

- **Working-student track** -- `working student applications/` -- Werkstudent/internship roles, IDs `1, 2, ...`
- **Full-time track** -- `full time applications/` -- purely junior full-time roles, IDs `FT1, FT2, ...`, no German
  filter. Selected with `--fulltime` in every script.

## Table of Contents

- [1. Search for Positions](#1-search-for-positions)
- [2. Need Verification Triage](#2-need-verification-triage)
- [3. Apply -- Single Session (Interactive)](#3-apply----single-session-interactive)
- [4. Batch Apply -- Parallel Workers](#4-batch-apply----parallel-workers)
- [5. Maintenance Scripts](#5-maintenance-scripts)

---

## 1. Search for Positions

Pick a window (`today`, `last 2 days`, `last 3 days`, `last week`, `last 3 weeks`, `last month`) and a track. The
LinkedIn `f_TPR` values for each window are listed in `JOB_APPLICATION_AGENT.md` (Task 1, LinkedIn). A one-off window
change applies to that run only.

### 1A. Working-student track

```
Search for working student positions in Germany that suit my profile (data analyst, data scientist, data engineer,
data specialist, AI engineer, ML engineer, or similar). Only look for positions posted in the LAST 3 DAYS -- use each
board's date filter and skip anything older. Be very comprehensive: LinkedIn, Indeed, StepStone, and Xing are all
required, plus company career pages. Look at all kinds of companies (consulting, fintech, enterprise, startups,
corporates, media). Skip roles that need years of professional experience I don't have. Also re-check companies in
applied.md for new roles -- only the exact same listing must never be added twice. Add findings to
`working student applications/positions.md` in the exact format, and stamp each row's Found date. Use multiple agents
if needed. Follow JOB_APPLICATION_AGENT.md strictly, including all exclusion rules.

Finish with the mandatory final duplicate sweep (Task 1, step 5) and report how many duplicates were found out of the
current applied.md total. Update the "Last search pass" line and write a short search write-up in notes.md.
@"working student applications/positions.md" @"working student applications/applied.md"
@"working student applications/needs_manual_email.md" @notes.md @JOB_APPLICATION_AGENT.md @../profile/candidate.md
```

### 1B. Full-time track

```
Search for full-time positions in Germany that suit my profile: Data Analyst, Data Scientist, Data Engineer, Data
Specialist, AI/ML/Generative AI Engineer, Data Analytics/Visualization, or similar. Purely junior roles only -- apply
the Seniority rule in JOB_APPLICATION_AGENT.md ("Full-Time Track") and read each posting's description before adding
it. Do NOT filter on German requirements for this track. Only look for positions posted in the LAST 2 DAYS. LinkedIn,
Indeed, StepStone, and Xing are all required (the fast path in scripts/linkedin_search/ is fine for LinkedIn). Add
findings to `full time applications/positions.md` with FT-prefixed IDs continuing from the highest existing one. Also
re-check companies in the full-time applied.md for new roles.

Finish with the mandatory final duplicate sweep scoped to the full-time track and report the result. Update the "Last
search pass" line and write a short search write-up in notes.md.
@"full time applications/positions.md" @"full time applications/applied.md"
@"full time applications/needs_manual_email.md" @notes.md @JOB_APPLICATION_AGENT.md @../profile/candidate.md
```

---

## 2. Need Verification Triage

Run periodically to clear the parked sections. Run each track as a separate pass and never move entries between tracks.
Replace `TRACK` with `working student applications` or `full time applications`.

```
Go through EVERY entry in the "Need Verification" AND "Skipped" sections of `TRACK/positions.md`. For each one:
- Re-check that the listing is still live (listing page or a cross-post); drop dead ones.
- Read my `# comment` under the entry if present ("skip" = leave it in Skipped but still check whether it is now
  resolvable; anything else = an instruction to act on). `applied` after the Apply link = I completed it manually
  (move it to applied.md with today's date); `expired` = drop it.
- Re-check it against every rule in JOB_APPLICATION_AGENT.md. If the blocker is a durable pattern we have no rule for
  yet, add the rule so batch workers stop getting stuck on it.
- Then requeue it into its company's to-apply table with a fresh Found date if a rule resolves the blocker; move it to
  needs_manual_email.md if it is email-only; move it to applied.md if the blocker proves a prior application
  (duplicate-profile error); drop it if it is disqualifying; or move it to "Manual Application Required" only with
  strong, specific, reproducible evidence that no automated attempt can succeed. Infrastructure failures (worker
  crashed, session limit, MCP timeout) are always requeued.
For the full-time track, also drop entries that fail the junior-only rule or turn out to be internships, and requeue
anything sitting in "Requires C1 German" (no German filter on that track). For the working-student track, empty the
"Requires C1 German" section but keep its header.
Remove stray duplicates, run `scripts/update-counters.sh` (with --fulltime for the full-time track), and write a
plain-English report to `reports/application_problems_<YYYY-MM-DD>.txt`: a short intro, one "PROBLEM #N" section per
blocker pattern (count, cause in plain words, what was done, affected roles), "WHAT I CHANGED", and "BOTTOM LINE"
with before/after counts. Give a short summary in chat too. Finally tidy applications/: loose cover letters go into
cover_letters/, LaTeX leftovers are deleted, and .playwright-mcp/ logs are cleared.
@"TRACK/positions.md" @"TRACK/needs_manual_email.md" @"TRACK/applied.md" @JOB_APPLICATION_AGENT.md
```

---

## 3. Apply -- Single Session (Interactive)

Use this when you are at the computer and can answer questions as they come up:

```
@JOB_APPLICATION_AGENT.md @../profile/candidate.md Let's apply to the positions in
`working student applications/positions.md` from top to bottom. For each one, check applied.md first, then fill out
the application form. If you hit a question you cannot answer from the profile, stop and ask me. Record each
application in applied.md immediately after submitting. Always review every field before submitting. Open-ended
answers: concise, specific, never verbose or flattering; read the CV for context. If something goes wrong or I give
you a new instruction, update JOB_APPLICATION_AGENT.md so it does not happen again.
@../resume/cv_4.tex @"working student applications/positions.md" @"working student applications/applied.md"
```

---

## 4. Batch Apply -- Parallel Workers

Launches several `claude -p` workers in parallel, each applying to one position in its own isolated Playwright
browser. Results are merged into the tracker files as each worker finishes.

```bash
cd applications

./scripts/batch-apply.sh --dry-run                     # preview the queue
./scripts/batch-apply.sh --max 10 --parallel 3         # 10 positions, 3 at a time
./scripts/batch-apply.sh --ats greenhouse --parallel 4 # only one ATS
./scripts/batch-apply.sh --parallel 3 --headless       # no visible browser windows
./scripts/batch-apply.sh --max 5 --parallel 2 --fulltime
```

| Option | Default | Meaning |
|--------|---------|---------|
| `--parallel N` | 3 | Workers running at once |
| `--max M` | all | Maximum positions to process |
| `--ats TYPE` | all | `workday`, `greenhouse`, `ashby`, `lever`, `other` |
| `--model MODEL` | sonnet | `haiku`, `sonnet`, `opus` |
| `--effort LEVEL` | medium | `low`, `medium`, `high`, `max` |
| `--headless` | off | Hide browser windows |
| `--worker-timeout SEC` | 900 | Kill a hung worker after this long |
| `--fulltime` | off | Use the full-time track |
| `--dry-run` | off | Show the queue without launching workers |

If Claude's usage limit is hit mid-run, no new workers start, running ones finish, and completed results are still
merged.

### Recommended parallelism

| ATS | `--parallel` | Notes |
|-----|--------------|-------|
| Greenhouse | 4 | Fastest, single-page forms |
| Ashby / Lever | 3-4 | Fast, simple forms |
| Workday | 2 | Multi-step, one account per company tenant |
| Other / custom | 1-2 | Varies widely |

Model choice: `haiku` for simple single-page forms, `sonnet` for most forms, `opus` for complex multi-step flows.

---

## 5. Maintenance Scripts

```bash
./scripts/check-listings.sh                 # remove dead listings from positions.md
./scripts/check-listings.sh --dry-run       # report only
./scripts/check-listings.sh --ats workday   # one ATS only
./scripts/update-counters.sh                # refresh the Counts line
./scripts/update-counters.sh --fulltime
../resume/build.sh                          # rebuild the CV and refresh documents/resume*.pdf
```
