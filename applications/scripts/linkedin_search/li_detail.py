"""Phase 2: filter cards, fetch details for candidates, classify by junior rule. Writes details.json + review.txt."""
import json, re, os, time, random, html, glob, unicodedata
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.parse import unquote
import requests

HERE = os.path.dirname(__file__)
FT = os.environ.get("FT_TRACK_DIR", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "full time applications"))
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"

def norm(s):
    s = unicodedata.normalize("NFKD", s.lower())
    s = re.sub(r"\((m|w|d|f|x|all|gn|mwd|m/w/d|w/m/d|m/f/d|f/m/d|d/m/w|all genders?)[^)]*\)", " ", s)
    return re.sub(r"[^a-z0-9]+", " ", s).strip()

# known listings in the full-time track
known_ids, known_text = set(), ""
for f in glob.glob(os.path.join(FT, "*.md")):
    t = open(f, encoding="utf-8").read()
    known_ids |= set(re.findall(r"jobs/view/(?:[^/\s)]*-)?(\d{9,11})", t))
    known_text += "\n" + norm(t)

cards = json.load(open(os.path.join(HERE, "cards.json"), encoding="utf-8"))

KW = re.compile(r"data|daten|analyt|\bai\b|\bki\b|k\.i\.|machine learning|\bml\b|mlops|llm|genai|generative|intelligence|\bbi\b|power bi|scien|statist|quant|reporting|nlp|computer vision|deep learning|künstliche|kuenstliche|artificial|databricks|snowflake|tableau|controlling analyst|insight", re.I)
BAD_TITLE = re.compile(r"senior|\bsr\.?\b|lead|principal|head of|\bhead\b|staff|director|direktor|leiter|leitung|teamlead|architect|architekt|werkstudent|working student|praktik|intern\b|internship|thesis|abschlussarbeit|masterarbeit|bachelorarbeit|studentische|student|ausbildung|azubi|duales studium|dual student|phd|doktorand|postdoc|professor|minijob|aushilfe|freelance|freiberuf|expert\b|experte|manager(?!.*junior)|vp\b|chief|consultant.*senior|mid-level|mid level|\bmid\b|erfahren", re.I)
SPAM_CO = re.compile(r"alignerr|rex\.zone|randstad|michael page|hapeko|vesterling|instaffo|ai futures|ka resources|haystack|jobgether|talentspring|workwise|innodata|ai training|outlier|dataannotation|mercor|crossing hurdles|turing|braintrust|toptal|hays|gulp|amadeus fire|robert half|wallis|stellenwerk|joblift|jobot|pertemps|experteer|personal ?total|adecco|manpower|orizon|dis ag|akkodis|brunel|ferchau|bertrandt", re.I)
JUNIOR_T = re.compile(r"junior|\bjr\b|graduate|trainee|entry|einsteiger|absolvent|young professional|career start|berufsstart|associate|traineeship|nachwuchs|einstieg", re.I)

cands = []
for c in cards.values():
    if c["id"] in known_ids: continue
    t = c["title"]
    if not KW.search(t): continue
    if BAD_TITLE.search(t) and not re.search(r"junior|trainee|graduate", t, re.I): continue
    if SPAM_CO.search(c["company"]): continue
    if norm(c["company"]) and norm(t) and (norm(t) in known_text and norm(c["company"]).split()[0] in known_text):
        c["maybe_dup"] = True
    cands.append(c)
print("cards", len(cards), "candidates", len(cands))

def fetch(url, tries=4):
    for i in range(tries):
        try:
            r = requests.get(url, headers={"User-Agent": UA, "Accept-Language": "en-US,en;q=0.9"}, timeout=(5, 15))
            if r.status_code == 200: return r.text
            if r.status_code in (429, 999, 503): time.sleep(min(3 + i * 3, 10) + random.random() * 2); continue
            if r.status_code in (400, 404, 410): return ""
            time.sleep(2)
        except requests.RequestException:
            time.sleep(2 + i)
    return None

def detail(c):
    t = fetch(f"https://www.linkedin.com/jobs-guest/jobs/api/jobPosting/{c['id']}")
    if t is None: c["err"] = "fetch"; return c
    m = re.search(r'show-more-less-html__markup[^>]*>(.*?)</div>', t, re.S)
    desc = html.unescape(re.sub(r"<[^>]+>", " ", m.group(1))) if m else ""
    c["desc"] = re.sub(r"\s+", " ", desc).strip()
    crit = re.findall(r'description__job-criteria-subheader[^>]*>\s*(.*?)\s*</h3>\s*<span[^>]*>\s*(.*?)\s*</span>', t, re.S)
    c["criteria"] = {html.unescape(a.strip()): html.unescape(b.strip()) for a, b in crit}
    a = re.search(r'id="applyUrl"[^>]*>\s*<!--"(.*?)"-->', t, re.S)
    if a:
        u = html.unescape(a.group(1)); mm = re.search(r"[?&]url=([^&]+)", u)
        c["apply"] = unquote(mm.group(1)) if mm else u
    c["closed"] = "No longer accepting applications" in t
    return c

YEARS = re.compile(r"(?<![\d.])([2-9]|1[0-9])\s*(?:\+|-\s*\d+|bis\s*\d+|–\s*\d+)?\s*(?:\+\s*)?(?:years?|yrs|jahre?n?)\b", re.I)
MIN1 = re.compile(r"(at least|minimum of|mindestens|min\.)\s*(one|1|ein(em|er)?)\s*(year|jahr)", re.I)
MULTI = re.compile(r"mehrjährig|mehrjaehrig|langjährig|mehrere jahre|several years|multiple years|many years|extensive experience|fundierte(n)? berufserfahrung|einschlägige(n)? berufserfahrung|proven track record|years of experience|jahre(n)? berufserfahrung|considerable experience|significant experience|substantial experience|umfangreiche (berufs)?erfahrung", re.I)
JUNIOR_D = re.compile(r"erste(n)? (praktische(n)? |berufliche(n)? )?(berufs)?erfahrung|first (professional |practical |work )?experience|berufseinsteiger|berufseinstieg|career starter|entry.level|graduate|absolvent|internships?.{0,40}(count|welcome|enough|sufficient)|werkstudent.{0,60}(erfahrung|experience)|working student.{0,60}experience|young professional|recent(ly)? graduat|frisch|no experience required|keine berufserfahrung", re.I)

def classify(c):
    d = c.get("desc", ""); cr = c.get("criteria", {})
    lvl = cr.get("Seniority level", ""); emp = cr.get("Employment type", "")
    reasons = []
    if c.get("closed"): reasons.append("closed")
    if emp and emp not in ("Full-time",): reasons.append("emp:" + emp)
    if lvl in ("Director", "Executive"): reasons.append("lvl:" + lvl)
    ym = [m.group(0) for m in YEARS.finditer(d)]
    yr_hits = []
    for m in YEARS.finditer(d):
        ctx = d[max(0, m.start()-60): m.end()+60].lower()
        if re.search(r"experience|erfahrung|berufs", ctx) and not re.search(r"we are|wir sind|seit|since|founded|gegründet|years old|jahre alt|unternehmen|company|history|tradition|befristet|contract|vertrag|programm|program|rotation|month|monat|trainee", ctx):
            yr_hits.append(ctx)
    if yr_hits: reasons.append("years")
    if MULTI.search(d): reasons.append("multi:" + MULTI.search(d).group(0))
    if MIN1.search(d) and re.search(r"post.?degree|nach (dem|ihrem|deinem) studium|after (your )?(graduation|degree)", d, re.I): reasons.append("1yr-post")
    jsig = bool(JUNIOR_T.search(c["title"])) or lvl in ("Entry level", "Internship") or bool(JUNIOR_D.search(d))
    if lvl == "Mid-Senior level" and not JUNIOR_D.search(d) and not re.search(r"junior|trainee|graduate", c["title"], re.I): reasons.append("midsenior")
    if not jsig: reasons.append("nojunior")
    c["reasons"] = reasons; c["yr_ctx"] = yr_hits[:3]
    c["jsig"] = jsig
    return c

if __name__ == "__main__":
    out = os.path.join(HERE, "details.json")
    det = json.load(open(out, encoding="utf-8")) if os.path.exists(out) else {}
    todo = [c for c in cands if c["id"] not in det or det[c["id"]].get("err")]
    print("to fetch", len(todo), flush=True)
    n = 0
    with ThreadPoolExecutor(max_workers=6) as ex:
        for f in as_completed([ex.submit(detail, c) for c in todo]):
            c = f.result(); det[c["id"]] = c; n += 1
            if n % 25 == 0:
                print("fetched", n, flush=True); json.dump(det, open(out, "w", encoding="utf-8"), ensure_ascii=False)
    for c in det.values(): classify(c)
    json.dump(det, open(out, "w", encoding="utf-8"), ensure_ascii=False)
    from collections import Counter
    cnt = Counter()
    for c in det.values():
        for r in c["reasons"]: cnt[r.split(":")[0]] += 1
    print(cnt)
    keep = [c for c in det.values() if not c["reasons"]]
    print("pass", len(keep), "errors", sum(1 for c in det.values() if c.get("err")))
