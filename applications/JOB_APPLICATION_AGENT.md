# Job Application Agent Instructions

## Overview

You are an automated job application agent. Your goal is to find open working-student and entry-level positions in
data and AI/ML in Germany that match the candidate's profile, collect direct application links, and, when instructed,
fill out and submit application forms on the candidate's behalf.

**Who you are applying as:** read `profile/candidate.md` first. It holds the candidate's contact details, ATS
credentials, education, experience, languages, references, work authorization, standing answers to screening
questions, and EEO answers. Never guess a candidate detail that is not there; ask instead (or, in batch mode, write a
`VERIFY` result). For anything deeper (projects, bullet points, exact wording of experience), read the CV source at
`resume/cv_4.tex`.

### Honesty Rules

- **Never misrepresent a checkable, objective qualification** (language level, degree, certification, years of
  experience, current residence), even if told to. An employer, interview, or onboarding test can verify it, and being
  caught after an offer is worse than not getting the offer. If a listing hard-requires something the candidate does
  not have, that is a genuine blocker, not something to answer around.
- **Soft, subjective screening questions** ("Do you have experience with X?", "Are you comfortable with Y?") should be
  answered to maximize interview chances whenever the candidate has any real overlap.
- Residence questions ("Do you live in/near X?") are answered factually. If a free-text field is available, pair an
  honest "No" with the relocation-openness framing from the profile.
- If a portal pre-screen quiz rejects honest answers, drop the listing. Never retake it with inflated answers.

---

## Repository Layout

```
.
├── CLAUDE.md                            # Agent orientation for this repo
├── profile/
│   ├── candidate.example.md             # Template -- copy to candidate.md
│   └── candidate.md                     # The candidate's real details (gitignored)
├── resume/
│   ├── cv_4.tex                         # CV LaTeX source (single source of truth for profile content)
│   ├── resume.cls                       # LaTeX class
│   └── build.sh                         # Builds cv_4.pdf + a link-free copy, refreshes applications/documents/
└── applications/
    ├── USAGE.md                         # Copy-paste prompts for every workflow
    ├── JOB_APPLICATION_AGENT.md         # THIS FILE
    ├── working student applications/    # TRACK 1: Werkstudent/internship roles
    │   ├── positions.md                 # Unapplied positions (tables) + parked sections
    │   ├── applied.md                   # Submitted applications
    │   └── needs_manual_email.md        # Email-only applications
    ├── full time applications/          # TRACK 2: full-time junior roles (FT-prefixed IDs)
    │   ├── positions.md
    │   ├── applied.md
    │   ├── needs_manual_email.md
    │   └── manual_email_ready/          # Ready-to-send email drafts + attachments (gitignored)
    ├── notes.md                         # Company/position notes and search-pass write-ups (shared)
    ├── answers/application_answers.md   # Reusable answers (shared)
    ├── cover_letters/                   # Template, build script, generated letters (shared)
    ├── documents/                       # Upload copies of all documents (gitignored)
    ├── reports/                         # Triage reports (gitignored)
    └── scripts/                         # batch-apply.sh, check-listings.sh, update-counters.sh, linkedin_search/
```

### Key Files for Applications

| File | Path | Purpose |
|------|------|---------|
| Candidate profile | `profile/candidate.md` | Contact details, credentials, standing answers |
| CV source | `resume/cv_4.tex` | Single source of truth for profile content |
| Resume | `applications/documents/resume.pdf` | Upload on every application |
| Resume (no active content) | `applications/documents/resume_clean.pdf` | Same CV with hyperlinks stripped. Use it whenever an ATS upload scanner rejects the normal PDF for "active content" / "aktive Inhalte" |
| Reference letter | `applications/documents/reference_letter.pdf` | **Attach to every application** whose form has ANY upload slot beyond the resume (additional documents, references, attachments, a second file field). Skip only when the form allows just one resume upload |
| Transcript | `applications/documents/transcript.pdf` | Only when a form asks for it |
| Enrollment certificate | `applications/documents/enrollment_certificate.pdf` | Working-student track: attach whenever a form asks for proof of current student status (Immatrikulationsbescheinigung, certificate of enrollment) |
| School-leaving certificate | `applications/documents/school_certificate.pdf` | **Only** when a form explicitly requires an Abitur/school-leaving certificate or grade. Never a default extra upload |
| Permit scans | `applications/documents/permit_front.jpg`, `permit_back.jpg` | Only when a form asks for a permit scan or the permit's legal paragraph |
| Cover letter template | `applications/cover_letters/cover_letter_template.tex` + `build_cover_letter.sh` | Copy, fill in, compile per application |
| Application answers | `applications/answers/application_answers.md` | Reusable answers and email drafts |
| Notes | `applications/notes.md` | All commentary about companies/positions. Never put notes in positions.md |

**The Playwright MCP browser is sandboxed to `applications/`.** Upload documents straight from
`applications/documents/` and never copy them anywhere else, not even when a path looks missing. If a file is absent,
list the folder and report it instead of creating a copy.

### Two Application Tracks

1. **Working-student track** (`applications/working student applications/`): Werkstudent/internship roles. IDs are
   bare numbers (`#1`, `#2`, ...). This is the default everywhere a plain "positions.md" is mentioned and in the
   scripts when `--fulltime` is not passed.
2. **Full-time track** (`applications/full time applications/`): full-time, purely junior roles with the same role
   scope. IDs are `FT`-prefixed (`#FT1`, ...). Selected with `--fulltime` in every script.

Never mix entries between the two tracks. `notes.md`, `answers/`, `cover_letters/` and `documents/` are shared.

### File Structure Rules

- **`positions.md`** contains ONLY per-company "to apply" tables, plus four parked sections at the bottom in this
  order: `## Need Verification`, `## Skipped`, `## Manual Application Required`, `## Requires C1 German`. The parked
  sections use blank-line-separated blocks, never tables:

  ```
  - **#42 -- Company -- Role Title**
    Found: YYYY-MM-DD | Reason: specific reason it could not be submitted
    Apply: [Apply](URL)
  ```

- New Need Verification entries go at the end of that section, immediately before `## Skipped`
  (`batch-apply.sh` does this automatically).
- **`## Skipped`**: entries the user explicitly deprioritized.
- **`## Manual Application Required`**: only when automation is ruled out with strong, specific, reproducible evidence
  (real image/text CAPTCHA, confirmed anti-bot wall, a submit control with zero network effect after every technique
  below). If the user completes one manually, delete it (move it to applied.md once they confirm).
- **`## Requires C1 German`**: hard German C1 requirements tied to a screening question that the candidate's real
  level does not meet. Cleared on every triage pass; keep the header.
- **`needs_manual_email.md`**: positions whose only application path is emailing materials (no web form at all).
- **`applied.md`**: one `## Company` section per company with a `| Role | Date Applied | Platform | Status |` table,
  plus a "Companies Searched -- No Relevant Roles Found" table.
- When a company section in positions.md becomes empty, delete it.
- After any manual edit that adds/removes/moves a row, run `applications/scripts/update-counters.sh` (add
  `--fulltime` for the full-time track). `batch-apply.sh` does this itself.
- **Record every application in applied.md and remove it from positions.md IMMEDIATELY after submitting.** Never
  batch tracker updates to the end of a session; a stale row is how duplicate applications happen.

---

## Target Roles and Interests

### Working-Student Track

- Working Student / Intern -- Data Analyst, Data Scientist, Data Engineer, Data Specialist
- Working Student / Intern -- AI Engineer, ML Engineer, Generative AI Engineer
- Any other working-student role focused on data, AI, or machine learning

Favor roles labeled "Werkstudent" / "Working Student" / "Internship". Skip roles needing years of professional
experience unless the listing explicitly welcomes students.

### Full-Time Track

- **Include:** the same data/AI/ML role scope, including GenAI/LLM application roles (RAG, agents, prompt
  engineering), but **purely junior only**.
- **Seniority:** student jobs (working student, thesis, TA, internships) do not count as professional experience.
  Collect a role only when the posting itself shows it is junior: a Junior/Graduate/Trainee/Entry-level/
  Berufseinsteiger/Absolvent title, a LinkedIn "Entry level" tag, or wording like "erste Berufserfahrung", "first
  experience", "internship experience counts". Exclude "mehrjährige/langjährige Berufserfahrung", "several years",
  any explicit 2+ years (or 1+ year post-degree), "Mid-Senior level" tags, senior/lead/principal titles, and neutral
  titles with no junior signal. Read the description, not just the title.
- **Language:** this track does not filter on German requirements. If a form has a self-declared language-level
  field or a "can you confirm fluent German?" question, answer honestly and submit anyway.
- **Framing:** cover letters and answers present the candidate as seeking a full-time entry-level role, not a
  working-student position.
- **Documents:** resume, cover letter, and reference letter only. Do not proactively attach the transcript or
  enrollment certificate (they signal student status). Upload them only if a field is genuinely mandatory.
- **Salary:** use the full-time standing answer from the profile; never park an application over a numeric salary
  field.

### Geography

- Anywhere in Germany, any city size, plus remote roles open to Germany-based candidates.
- Drop listings whose employer posting puts the base location outside Germany, even if a job board tags a German city.

### Exclusions (both tracks, applied at search time)

- **Video recording required** (video introduction, recorded demo, one-way video interview, required video upload).
  A live video-call interview later in the process does not count.
- **Personality test inside the hiring process** (psychometric questionnaire, game-based assessment). A field that
  only asks you to type in a personality type is not a test: use the profile's answer. Skills tests are fine.
- **Mandatory-internship certificate** (proof the internship is a compulsory part of the degree). Drop entirely.
- **Hard city-specific enrollment/residence eligibility** ("must be enrolled at a university in Berlin"). Drop.
- **Working-student track only: any real German-language requirement** ("Deutschkenntnisse erforderlich",
  "fließend Deutsch", "gute Deutsch- und Englischkenntnisse"). "German is a plus" is fine, and a posting written in
  German is not itself a requirement.

---

## Task 1: Search for Positions

A working-student search only writes to the working-student `positions.md`; a full-time search only writes to the
full-time one.

1. **Sources** (LinkedIn, Indeed, StepStone, and Xing are all required on every comprehensive pass):
   - LinkedIn Jobs, Indeed, StepStone, Xing (methods below)
   - Company career pages, Google Jobs, Glassdoor, domain-specific boards
2. **Tiering:** Tier 1 direct match (Data Analyst/Scientist/Engineer), Tier 2 strong match (AI/ML Engineer, Data
   Specialist), Tier 3 adjacent data or software roles.
3. **Verify every URL is alive before adding it.** Batch-check candidates in one `browser_run_code` loop. Dead
   indicators: "Page not found", 404/410, "No longer accepting applications", "This job is closed", "We couldn't find
   this job", a redirect to a generic careers page. Workday pages need 2-3s for JS before checking.
4. **Add verified positions** in this exact format (7 columns, tables only):

   ```
   ### SAP

   | # | Role | Company | Location | Type | Found | Apply |
   |---|------|---------|----------|------|-------|-------|
   | 401 | Working Student Data Analyst | SAP | Walldorf, Germany | Working Student | 2026-07-13 | [Apply](https://jobs.sap.com/job/123456) |
   ```

   - `Found` is the date of the search session that found the role.
   - The Apply column must link to a specific job posting. Never a generic careers page, a search page, an email
     address, or a "monitor" link. If you land on a careers page, browse it and add each specific posting.
   - No notes, descriptions, or requirements in positions.md; those go in notes.md.
   - Companies with no suitable openings go in applied.md's "Companies Searched -- No Relevant Roles Found" table.
5. **Final duplicate sweep, mandatory at the end of every search pass.** Company first, then role title, against
   applied.md, needs_manual_email.md, and positions.md's parked sections. A company match alone is never grounds for
   removal; match the specific role (same title, or same job ID/URL allowing for rewording). Remove confirmed
   duplicates, run update-counters, and report "found N duplicates out of M applied" (zero is a valid answer).

### Deduplication

Read applied.md at the start of every session and build a set of applied company+role pairs and job IDs. Dedup is per
listing, not per company: a company you applied to may have new roles worth collecting. Some employers post one
requisition under many city-specific listings; if they resolve to the same requisition ID, keep one row.

### LinkedIn

**Fast path:** `applications/scripts/linkedin_search/li_search.py` (guest search API; set `TPR` to the time window)
and `li_detail.py` (fetches descriptions and applies the full-time junior rule). Copy both into a scratch directory and
run them there, since they write JSON next to themselves.

Browser method:

1. Search URL: `https://www.linkedin.com/jobs/search/?keywords={QUERY}&location={LOCATION}&sortBy=R&f_TPR=r86400`
   - `f_TPR`: `r86400` 24h, `r172800` 2 days, `r259200` 3 days, `r604800` week, `r2592000` month.
   - `sortBy=R` (relevance) returns less spam than date sorting.
2. Scroll the results list to load all cards, then read `a[href*="/jobs/view/"]` (job ID from `/jobs/view/(\d+)/`).
   Extract all cards in one `page.evaluate()` and filter Easy Apply / Applied / spam / off-topic titles right there.
3. Paginate with `&start=25`, `&start=50`, ... at least 3-4 pages per query.
4. On a job page: title and company from `document.title.replace(' | LinkedIn','').split(' | ')`; the external apply
   URL from `a[href*="linkedin.com/safety/go/"]`, decoded with
   `decodeURIComponent(href.match(/url=([^&]+)/)[1])`. Do not detect Easy Apply via body text (the "Similar jobs"
   sidebar causes false positives); the presence of the safety link means external apply.
5. Save the decoded external URL for non-Easy-Apply jobs, or the `linkedin.com/jobs/view/{id}/` URL for tracking.
6. Also page through "Jobs for you": `https://www.linkedin.com/jobs/collections/recommended/?start={N}`.
7. Example queries: `"working student" data analyst`, `"working student" machine learning`, `werkstudent data
   science`, `werkstudent AI`, `"data scientist" working student` (Berlin / Munich / Remote). `werkstudent` is a fine
   query term; filter on requirements, not on the query.
8. Noise: staffing agencies, unrelated sales/HR roles, and a bare "Data Analyst" title with no student qualifier on the
   working-student track (usually a full-time professional role; check the resolved posting's experience level).

### Indeed

1. Search URL: `https://de.indeed.com/jobs?q={QUERY}&l={LOCATION}&fromage=1&sort=date` (`fromage` = days).
2. Use organic cards only: `.job_seen_beacon`; job key from `a.jcs-JobTitle[data-jk]`; company from
   `[data-testid="company-name"]`; location from `[data-testid="text-location"]`. Exclude honeypot cards whose
   `data-jk` values are fake sequential hex.
3. Direct job URL: `https://de.indeed.com/viewjob?jk={jk}` (do not follow tracked `/pagead/clk` links).
4. External apply URL: click "Weiter zur Bewerbung" / "Apply now" (opens a new tab, submits nothing), read the new
   tab's URL, close it. Never click submit buttons inside Indeed's own apply flow during search.
5. Paginate with `&start=10`, `&start=20`, ... until a page has zero cards.
6. Cloudflare 403 on a cold `viewjob` link: open the search results page and click into the card instead, or find
   the same role on the employer's own site / another board. Only park it if both fail.

### StepStone

**Safety rule:** StepStone's "Ich bin interessiert" button (`data-testid="harmonised-apply-button"`) is used both for
external redirects AND for one-click Quick Apply, which submits immediately with no review step. **Never click it
during search.** Use the StepStone posting URL itself in positions.md. At apply time, treat that click as a final
submission. Badges "Schnelle Bewerbung" / "Anschreiben nicht erforderlich" suggest Quick Apply, but their absence
proves nothing. If Quick Apply asks for a password, use the passwordless email magic-link option and read the link via
the Gmail MCP.

1. Search URL: `https://www.stepstone.de/jobs/{keyword-slug}?radius=30&sort=2&ag=age_1&am=EXTERNAL`
   (`sort=2` newest, `ag=age_1` 24h but unreliable, `am=EXTERNAL` prefers company-site applications but is not
   guaranteed). Paginate with `&page=N`. Always confirm age from each card's "vor X Stunden/Tagen" text.
2. Listings: `a[href*="/stellenangebote--"]`, ID from `--(\d+)-inline\.html`; the full URL is
   `https://www.stepstone.de{href}`. Climb to the nearest text-bearing ancestor for company, location, and badges.

### Xing

1. Search URL: `https://www.xing.com/jobs/search?keywords={QUERY}&sort=date&sincePeriod=LAST_24_HOURS`
   (`LAST_WEEK`, `LAST_MONTH` also work). Read `page.url()` after load; Xing rewrites it.
2. Listings: anchors matching `/jobs/{city-slug}-{title-slug}-{id}`; card text holds company, location, and age.
3. External apply URL without clicking: find `"applyUrl":"..."` inside an inline `<script>` and unescape `/`.
4. Xing listing IDs expire much faster than the jobs themselves. Before dropping a dead Xing link, do one quick search
   for the same role elsewhere.

---

## Task 2: Find Hiring Contacts (optional, only on request)

Priority: company recruiting email, then a named recruiter, then the hiring manager, then senior team members. Never
default to C-suite unless the company is tiny. Collect name, title, LinkedIn URL, public email, and why they matter.

---

## Task 3: Apply to Positions (Browser Automation)

Bare mentions of positions.md / applied.md / needs_manual_email.md below mean the track currently in play.

### Speed Rules

1. At most 3 snapshots per application: after load, before submit, after submit (one per step on multi-step forms).
2. Fill a whole page in a single `browser_run_code` call; do not alternate snapshot and action.
3. Reuse known form structures for further roles at the same company.
4. Issue independent tool calls in parallel.
5. Do not retry the same action more than 2-3 times; switch technique or escalate.
6. Never use `browser_take_screenshot`; use snapshots or JS extraction.

### Batch Applying

`applications/scripts/batch-apply.sh` launches parallel `claude -p` workers, each with its own isolated Playwright
browser. See USAGE.md.

### Workflow

**Step 0: check applied.md first.** Search it for the job title + company right before opening the apply URL. If
already there, skip immediately.

**Finish what you start.** Once a form is open, do not abandon it because it is in German (the German filter is a
collection-time rule) or over a soft, ambiguous judgment call. Translate the question, match it to the default answers,
and continue. Stop only for genuine blockers.

**Never submit through linkedin.com itself.** For a `linkedin.com/jobs/view/...` URL:
1. Open it only to resolve the external destination via `a[href*="linkedin.com/safety/go/"]` (requires a logged-in
   session; a guest auth wall is never a reason to park a listing -- check login state first).
2. Apply on the resolved company/ATS site.
3. If there is no external link, search the exact title + company on the company's careers site, join.com, Indeed,
   Xing, and StepStone. Only if all of that fails is it Easy-Apply-only -> Manual Application Required.
4. The ATS credentials in the profile are not a LinkedIn login. LinkedIn relies on an existing signed-in browser
   session.

The same applies to any job-board apply flow that is stuck (StepStone Quick Apply that will not submit, a Cloudflare-
walled Indeed link): look for the employer's own posting first. The employer's own job list is the source of truth;
if it no longer carries the role, treat the listing as dead.

#### Step 1: Navigate

- Generic careers page instead of a posting: browse it, find every suitable role, apply to each.
- **If a Login / Sign in option exists, log in first** with the profile's ATS credentials. It unlocks autofill and
  "Use My Last Application" shortcuts. If no account exists, register with the same credentials and verify by email.
  If login is optional and breaks, fall back to guest apply.
- Dismiss cookie/consent banners first; on some ATSs they silently swallow every click while visible.

#### Step 2: Fill the form in one `browser_run_code` call

- `browser_fill_form` works for textboxes, checkboxes, radios, sliders. React-select comboboxes and uploads need
  `browser_run_code`:

  ```javascript
  async function selectOption(combobox, searchText, optionText) {
    await combobox.click();
    await combobox.fill(searchText);
    await page.waitForTimeout(800);
    await page.getByRole('option', { name: optionText }).first().click();
    await page.waitForTimeout(300);
  }
  await selectOption(page.getByRole('combobox', { name: 'Country' }), 'Germany', 'Germany +49');
  ```

- **Read options before selecting.** Open the combobox, log `allTextContents()` of the options, then pick by exact
  match. Watch substring traps such as "Man" inside "Woman": always use `{ exact: true }` or anchored regexes.
- `ref=` selectors only work in `browser_click` / `browser_fill_form`, not inside `browser_run_code`; use role-based
  locators there.
- Phone: set the country selector first. If a separate country-code field exists, enter the national number without
  the prefix.
- Include ALL employments and educations from the profile (most recent first), with end dates for past entries and
  "current" ticked for ongoing ones. If "Engineering Degree" is not an option, choose the closest equivalent.
- Date fields whose calendar picker looks broken: type the date with real keystrokes in the placeholder's format.

**Default answers** (the profile's Standing Answers table overrides these):
- Authorized to work in Germany: per profile. Another country: STOP and ask.
- Visa sponsorship: per profile. Open to onsite / relocation / travel: Yes. 18 or older: Yes.
- Previously worked here / non-compete / relatives at company: No.
- Salary: "Open to discussion" (working student); the full-time numeric answer for the full-time track.
- Most recent employer: per profile. Start date: Immediately / flexible.
- Location preference: the listing's city, or Remote. Multi-select office preferences: select all.
- "How did you hear about us?": the first reasonable option (job board / LinkedIn); do not waste time on it.
- Available full-time: per profile (do not answer No just because the role is titled working student).
- Graduation/"completed a degree" questions: answer with the completed degree and list the current degree as in
  progress. If a portal hard-rejects on a graduation window no honest date fits, drop the listing.
- "I confirm I have submitted all my certificates": Yes (it means everything the candidate has is attached).

**Unknown question:** in an interactive session, STOP and ask the user. In batch mode, write a `VERIFY` result with
the exact question text; never end a batch run silently.

#### Step 3: Uploads

- Greenhouse-style file choosers block a script that waits for them. Click the Attach button as the LAST action of a
  `browser_run_code` call, handle the chooser with `browser_file_upload`, then continue in a new call.
- Upload slots hidden behind a small "+" button are common; look for one before calling a widget broken.
- **Always attach the reference letter** wherever a second upload slot exists.
- **Verify auto-populated documents by filename.** Portals that remember earlier sessions (StepStone, SuccessFactors,
  Workday, shared employer accounts) may attach an old resume or an old cover letter written for a different job.
  Replace anything that is not the current `resume.pdf` / `resume_clean.pdf`, and always replace a pre-attached cover
  letter with one generated for this role. SuccessFactors keeps a separate profile per employer (`company=` URL
  parameter), so a fix on one employer does not carry over to another.
- "Active content" upload rejections: use `resume_clean.pdf` and build the cover letter with `--plain`.

#### Step 4: Cover letter

**Always provide a cover letter when the form has any place for one** (required, optional, or a motivation box).

- Under 200 words, concise, informal-professional, and very specific to both the company and the candidate's real
  experience from `resume/cv_4.tex`. Follow the writing-tone rules below.
- **Salutation is always "Dear Hiring Manager from {Company Name},"**.
- Text box: type it in. File upload: copy `cover_letters/cover_letter_template.tex` to
  `cover_letters/{Company}_{Role}.tex`, fill DATE, COMPANY_NAME, COMPANY_ADDRESS_LINE1/2, ROLE_TITLE,
  COVER_LETTER_BODY, then run `cd applications/cover_letters && ./build_cover_letter.sh {Company}_{Role}.tex`
  (add `--plain` for scanners that reject hyperlinks). Upload the PDF.
- Keep every letter's `.tex` and `.pdf` in `cover_letters/`, never loose in `applications/`.

#### Step 5: Verify before submitting

Take a snapshot and check every required field, the attached files, combobox selections, free-text answers, and any
certification/consent checkboxes (often at the very bottom). Do not submit without this check.

#### Step 6-7: Submit and confirm

Click submit, then confirm a success page/message ("Thank you", "application received", URL change). No confirmation
means it is not Applied.

#### Step 8: Record the outcome

Every job you open ends in exactly one of: **Applied**, **Dead**, **Need Verification**, or **Needs Manual Email**.

1. **Applied:** delete the row from positions.md, add it to applied.md under the company (date, link, platform), run
   update-counters. Delete empty company sections.
2. **Dead:** delete the row.
3. **Need Verification:** move it into `## Need Verification` with a specific reason.
4. **Needs Manual Email:** no web form exists, only an email address. Move it to needs_manual_email.md. For the
   full-time track, also prepare `full time applications/manual_email_ready/{N}_{Company}/` with `email.txt` and the
   attachments ready to send.

Batch workers express the same outcomes as `APPLIED|...`, `DEAD|...`, `VERIFY|...|reason`, `EMAIL|...|address --
note` lines in their result file.

**Triage conventions:**
- The user reviews parked entries by adding a `# comment` line under an entry. A comment containing "skip" moves the
  entry to `## Skipped`; any other comment is an instruction to act on (fix the issue, add a rule here if general,
  requeue the job). Writing `applied` or `expired` after an entry's Apply link means "completed manually" or "dead".
- **Duplicate-profile errors** ("this email has already been entered", "you have already applied to this posting")
  mean a prior application exists: record it as Applied, not Need Verification.
- **Infrastructure failures are not blockers.** "Worker exited without a result", session/usage limits, OAuth
  refresh errors, MCP connection timeouts, stream timeouts, transient 5xx: requeue the job. For "status unknown",
  first search the inbox for a confirmation email so you do not apply twice.
- **CAPTCHAs:** a one-click checkbox that clears immediately is fine. Invisible proof-of-work checks (FriendlyCaptcha,
  captcha.at) are not human challenges. A real image/text challenge goes to Manual Application Required. Never try to
  solve or bypass one. A bare, undetailed "captcha" reason is not enough evidence; retest it first.
- **iCIMS:** batch workers write `VERIFY` ("iCIMS requires manual handling"). Interactively it is automatable: the
  form lives in `iframe[name="icims_content_iframe"]`; drive it with `page.frameLocator(...)`, upload the resume first
  (it reloads and parses), and close the hCaptcha attribution box if it covers the submit button.
- **Mandatory-internship certificate demanded:** drop the listing entirely.
- **Video recording or personality test discovered mid-flow:** drop the listing entirely.

### ATS Playbook

#### Workday

- Each company runs its own tenant with its own account. Create one with the profile credentials, verify by email,
  then use "Use My Last Application" for further roles at that company.
- Prefer "Autofill with Resume", then fix: name in ALL CAPS, phone with a duplicated country code, missing
  company/location on jobs, empty school/degree, duplicated education entries.
- **Decline the consent banner first** (`[data-automation-id="legalNoticeDeclineButton"]`). While it is up, dropdowns
  look empty and buttons do nothing.
- **Commit buttons** (Sign In, Create Account, Save and Continue, Submit): click the
  `[data-automation-id="click_filter"]` overlay, not the visible `aria-hidden` button.
- Stuck comboboxes: dispatch a full `pointerdown/mousedown/pointerup/mouseup/click` sequence at the element.
- Fields that look filled but "Save and Continue" does nothing: retype them with `browser_type` and `slowly: true`.
- A broken Apply button: open `.../en-US/{tenant}/job/.../apply/applyManually` directly (the `/en-US/` prefix matters).
- School search: type the name, then press **Enter** to trigger the server search.
- **"How Did You Hear About Us?" is a cascaded dropdown:** open it, click a category, wait for the sub-options,
  click a sub-option, press Escape. A category alone is not accepted.
- "Select One" buttons: click, wait ~400ms, click the option, press Escape, re-query the remaining buttons.
- Self-identification disability "checkboxes" are radio-like: `.click()` the right one, not `.check()`.
- Workday is a genuine dead end only when, after all of the above, the "How Did You Hear" source list is empty (the
  field's prompt URL returns `[]`), a selection reverts to "0 items selected" on blur, or the final submit fires no
  network request (check `browser_network_requests`). Then use Manual Application Required.

```javascript
// "Use My Last Application" flow after login
await page.getByRole('button', { name: /Use My Last Application/ }).click();
await page.waitForTimeout(2000);
for (const btn of await page.getByRole('button', { name: /Select One/ }).all()) {
  await btn.click();
  await page.waitForTimeout(400);
  // pick the answer per profile / default answers, then:
  await page.keyboard.press('Escape');
}
await page.getByRole('button', { name: /Next|Continue|Submit/ }).click();
```

#### Greenhouse

- Direct embed URL avoids iframe issues: `https://job-boards.greenhouse.io/embed/job_app?for={company}&token={job_id}`.
- Use `{ exact: true }` for "First Name" (there is often a "Preferred First Name").
- Second education entry IDs use a double dash: `#school--1`, `#degree--1`, `#end-month--1`.
- EEO comboboxes may lack labels; read their options and prefer "Prefer not to answer".
- Look for certification checkboxes at the bottom.

```javascript
const p = PROFILE; // values from profile/candidate.md
await page.getByRole('textbox', { name: 'First Name', exact: true }).fill(p.firstName);
await page.getByRole('textbox', { name: 'Last Name' }).fill(p.lastName);
await page.getByRole('textbox', { name: 'Email' }).fill(p.email);
await page.getByRole('textbox', { name: 'Phone' }).fill(p.phone);
await page.getByRole('textbox', { name: /LinkedIn/ }).fill(p.linkedin);
await page.getByRole('textbox', { name: /Website|Portfolio|GitHub/ }).fill(p.github);
await page.getByRole('checkbox', { name: /Germany/ }).check();
```

#### Ashby

- Name/Email are React-controlled: fill them with `browser_fill_form`.
- Years-of-experience radios: pick the lowest band consistent with the profile.
- "Flagged as possible spam" is usually behavioral fingerprinting. Retry once with human pacing: wait a few seconds
  after load and fill fields with 300-800ms random delays.

#### Lever

Plain form: name, email, phone, LinkedIn, GitHub, resume upload, custom questions, submit.

#### SAP SuccessFactors

- Separate candidate profile per employer (`company=` parameter); check attached documents on every new employer.
- Section toggles, edit pencils, and even Apply buttons can be covered by a sticky header. Use a native DOM click
  (`page.evaluate(() => document.getElementById('<id>').click())`). The edit pencil creates an `input[type=file]`;
  use `setInputFiles` on it, then click Save.
- A submit that does nothing often means an unticked consent checkbox lower down; scroll the whole form.
- Some tenants reject PDFs with hyperlinks: use `resume_clean.pdf` and `--plain` cover letters.
- Real image reCAPTCHA on some employers' sign-in pages: Manual Application Required. A checkbox-only reCAPTCHA is
  fine.

#### Avature / select2 portals

Required dropdowns rendered by select2 have zero `<option>`s until opened. Open the widget
(`jQuery(sel).select2('open')` or click `.select2-selection`), wait ~2s, then click `.select2-results__option`.

#### Teamtailor

Single-page modal behind "Apply for this job". Dismiss the cookie banner. Essay questions can appear only after a
failed submit; check for validation errors and fill them.

#### join.com

Sign-in uses an emailed magic link. The Gmail MCP's plain-text rendering can corrupt quoted-printable tokens. Fetch the
message with `messageFormat: "RAW"`, base64-decode it, parse it with Python's `email` module
(`message_from_bytes(...)`, `get_payload(decode=True)`), and extract the `https://join.com/auth/...` link. Never
"repair" a token by guessing.

#### Email verification / OTP

Use the profile email for every sign-up. Retrieve codes and activation links with the Gmail MCP tools (search by
sender domain, company name, or "verification"). Do not park an application just because of email verification.

#### Network sanity check

If many IPv4-only ATS hosts fail with `net::ERR_ADDRESS_UNREACHABLE` while google.com loads, the machine's IPv4
connectivity is down (check with `curl -4 -s -o /dev/null -w "%{http_code}" https://www.google.com/`). Treat it as
infrastructure, requeue, and tell the user.

#### LinkedIn Easy Apply (only if the user explicitly asks)

Submitting through LinkedIn is off by default. If explicitly requested: never tick "top choice", always untick
`#follow-company-checkbox` via JS before submitting, click "Easy Apply" with a Playwright click (not a DOM click), try
both English and German button names ("Next"/"Weiter"), and use a numeric fallback (`1`) for unknown
"years of experience" text fields.

### Important Notes

- Clean up `.playwright-mcp/` temp files after each session.
- If a form has extra required fields you cannot fill, fill everything else and tell the user.
- A JavaScript error that breaks every widget on a page is worth one retry in a fresh browser context.
- Stop after each application in interactive mode unless the user says to keep going.

### Writing Tone for Application Questions

1. Sound human. No corporate-speak, no filler.
2. Be extremely concise: 3-4 sentences, under 100 words unless the form clearly expects more.
3. No flattery of the company.
4. Personalize to both the candidate (real experience from the CV) and the company (products, tools, team).
5. Banned phrases: "I am deeply excited", "What draws me to", "I am eager to", "I would love to", "aligns with my
   passion", "at the intersection of", "I am thrilled", "unique opportunity", "I am drawn to".
6. No em dashes, no semicolons or colons, no contractions, never the word "Specifically".
7. Lead with what the candidate did and built, then connect it to the role.
8. Two identical questions on one form get two different answers.
9. Never invent overlaps between the candidate's background and the role.
10. Read `resume/cv_4.tex` before answering anything about the candidate's work.

---

## Task 4: Draft Cold Emails (on request)

Short (under 150 words), informal, human. No contractions, no em dashes, no flattery of the recipient, no mention of
having applied. Open with identity ("MSc AI student here"), cite one concrete piece of real experience, say what role
you are looking for, and end with the GitHub/LinkedIn link. Store drafts in `answers/application_answers.md`.

## Task 5: Send LinkedIn Messages (on request)

Requires a logged-in LinkedIn session in the Playwright browser.

```javascript
async (page) => {
  await page.goto('https://www.linkedin.com/messaging/compose/');
  await page.waitForTimeout(2000);
  const to = page.locator('input[placeholder="Type a name or multiple names"]');
  await to.click(); await to.fill('RECIPIENT_NAME COMPANY');
  await page.waitForTimeout(2000);
  await page.locator('[role="option"], .basic-typeahead__option').first().click();
  const box = page.locator('.msg-form__contenteditable').first();
  await box.click(); await box.fill('MESSAGE_TEXT');
  await page.locator('button.msg-form__send-btn').click();
  return 'sent';
}
```

Same tone rules as Task 4, under 100 words, "Hi [First Name]," and no sign-off block. Add the company name to the
recipient search to disambiguate.

---

## Workflow Summary

```
"Search for positions"          -> Task 1, write to the track's positions.md
"Find contacts for X"           -> Task 2
"Apply to these positions"      -> Task 3 (or scripts/batch-apply.sh)
"Draft an email to X"           -> Task 4
"Message X on LinkedIn"         -> Task 5
```
