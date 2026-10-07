"""Phase 1: LinkedIn guest search API, past 2 days, Germany. Saves cards to cards.json incrementally."""
import json, re, sys, time, random, html, os
from concurrent.futures import ThreadPoolExecutor, as_completed
import requests

OUT = os.path.join(os.path.dirname(__file__), "cards.json")
TPR = "r172800"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"

TERMS = [
 "junior data analyst","junior data scientist","junior data engineer","junior machine learning engineer",
 "junior ai engineer","junior ml engineer","junior bi analyst","junior business intelligence",
 "junior data consultant","junior analytics engineer","junior data specialist","junior power bi",
 "graduate data","graduate ai","graduate machine learning","trainee data","trainee analytics","trainee ki",
 "entry level data","berufseinsteiger data","absolvent data","junior datenanalyst","junior data management",
 "junior generative ai","junior llm","junior ki","ki engineer","ai engineer","machine learning engineer",
 "data scientist","data analyst","data engineer","analytics engineer","bi developer","business intelligence analyst",
 "datenanalyst","data science","generative ai engineer","llm engineer","mlops engineer","computer vision engineer",
 "nlp engineer","ai developer","ki entwickler","data consultant","reporting analyst","power bi developer",
 "data visualization","data quality analyst","master data","data governance","ai consultant","ki berater",
 "data platform engineer","databricks","snowflake","quantitative analyst","risk modelling","marketing analyst",
 "product analyst","pricing analyst","supply chain analyst","people analytics","finance data analyst",
 "junior consultant data","junior consultant ai","junior software engineer ai","forward deployed engineer",
 "ai solutions engineer","applied scientist","research engineer machine learning","data steward",
 "junior data","junior analyst","junior ai","associate data scientist","associate data engineer",
 "werkstudent data",  # filtered out later; kept off to save time
]
TERMS = [t for t in TERMS if not t.startswith("werkstudent")]

THROTTLED = [0]
QUERY_BUDGET = 150  # seconds per query before moving on
def fetch(url, tries=4):
    for i in range(tries):
        try:
            r = requests.get(url, headers={"User-Agent": UA, "Accept-Language": "en-US,en;q=0.9"}, timeout=(5, 15))
            if r.status_code == 200:
                return r.text
            if r.status_code in (429, 999, 503):
                THROTTLED[0] += 1
                time.sleep(min(3 + i * 3, 10) + random.random() * 2)
                continue
            if r.status_code == 400:
                return ""
            time.sleep(2)
        except requests.RequestException:
            time.sleep(2 + i)
    return None

CARD_RE = re.compile(r'<li>(.*?)</li>', re.S)
def parse(htmltext):
    out = []
    for block in CARD_RE.findall(htmltext):
        m = re.search(r'urn:li:jobPosting:(\d+)', block) or re.search(r'/jobs/view/[^"]*?-(\d+)\?', block)
        if not m:
            continue
        jid = m.group(1)
        def g(p):
            mm = re.search(p, block, re.S)
            return html.unescape(re.sub(r'<[^>]+>', '', mm.group(1))).strip() if mm else ""
        out.append({
            "id": jid,
            "title": g(r'class="base-search-card__title"[^>]*>(.*?)</h3>'),
            "company": g(r'class="base-search-card__subtitle"[^>]*>(.*?)</h4>'),
            "location": g(r'class="job-search-card__location"[^>]*>(.*?)</span>'),
            "date": (re.search(r'datetime="([^"]+)"', block) or [None, ""])[1],
        })
    return out

def run_query(term, extra=""):
    found = {}
    from urllib.parse import quote
    misses = 0
    t0 = time.time()
    for start in range(0, 250, 10):
        if time.time() - t0 > QUERY_BUDGET:
            print(f"  budget hit: {term}{extra} at start={start}", flush=True); break
        url = (f"https://www.linkedin.com/jobs-guest/jobs/api/seeMoreJobPostings/search?keywords={quote(term)}"
               f"&location=Germany&geoId=101282230&f_TPR={TPR}{extra}&start={start}")
        t = fetch(url)
        if t is None:
            misses += 1
            if misses >= 2: break
            continue
        cards = parse(t)
        if not cards:
            break
        new = 0
        for c in cards:
            if c["id"] not in found:
                found[c["id"]] = c; new += 1
        if new == 0:
            break
        time.sleep(0.4 + random.random() * 0.4)
    return term + extra, found

def main():
    allc = {}
    if os.path.exists(OUT):
        allc = json.load(open(OUT, encoding="utf-8"))
    jobs = [(t, "") for t in TERMS] + [(t, "&f_E=1%2C2") for t in TERMS[:45]]
    donef = os.path.join(os.path.dirname(__file__), "done_queries.txt")
    doneq = set(open(donef, encoding="utf-8").read().splitlines()) if os.path.exists(donef) else set()
    jobs = [j for j in jobs if (j[0] + j[1]) not in doneq]
    done = 0
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = [ex.submit(run_query, t, e) for t, e in jobs]
        for f in as_completed(futs):
            try:
                q, found = f.result()
            except Exception as e:
                print("ERR", e, flush=True); continue
            for k, v in found.items():
                v.setdefault("queries", [])
                if k in allc:
                    allc[k]["queries"] = list(set(allc[k].get("queries", []) + [q]))
                else:
                    v["queries"] = [q]; allc[k] = v
            done += 1
            open(os.path.join(os.path.dirname(__file__), "done_queries.txt"), "a", encoding="utf-8").write(q + chr(10))
            print(f"[{done}/{len(jobs)}] {q}: {len(found)} -> total {len(allc)} | throttled so far: {THROTTLED[0]}", flush=True)
            json.dump(allc, open(OUT, "w", encoding="utf-8"), ensure_ascii=False)
    print("DONE", len(allc))

if __name__ == "__main__":
    main()
