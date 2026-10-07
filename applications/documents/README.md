# Documents

Upload copies used during applications. The Playwright MCP browser is sandboxed to `applications/`, so every file
it uploads must live here. Upload straight from this folder; never copy documents elsewhere.

Everything in this folder except this README is gitignored.

| File | What it is | When it is attached |
|------|------------|---------------------|
| `resume.pdf` | Compiled CV (`resume/build.sh` writes it here) | Every application |
| `resume_clean.pdf` | Same CV without hyperlinks (also built by `resume/build.sh`) | When an ATS rejects the normal PDF for "active content" |
| `reference_letter.pdf` | Reference letter from a previous employer | Every form with any upload slot beyond the resume |
| `transcript.pdf` | University transcript of records | Only when a form asks for it |
| `enrollment_certificate.pdf` | Proof of enrollment (Immatrikulationsbescheinigung) | Working-student forms asking for proof of student status |
| `school_certificate.pdf` | School-leaving certificate (Abitur or equivalent) | Only when a form explicitly requires it |
| `permit_front.jpg`, `permit_back.jpg` | Residence/work permit scans | Only when a form asks for a permit scan |

Only `resume.pdf` is required to get started; add the rest as you have them.
