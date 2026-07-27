import json, os, glob, collections, datetime

ROOT = os.path.expanduser("~/.claude/projects/-Users-rdskcm-Claude-Projects-Optimizing-Mac-Usage-and-Settings")
files = glob.glob(os.path.join(ROOT, "**", "*.jsonl"), recursive=True)

seen = set()
per_model = collections.defaultdict(lambda: collections.Counter())
per_day = collections.defaultdict(lambda: collections.Counter())
per_file = collections.defaultdict(lambda: collections.Counter())
reqs = collections.Counter()
mind, maxd = None, None

for f in files:
    rel = os.path.relpath(f, ROOT)
    with open(f) as fh:
        for line in fh:
            line=line.strip()
            if not line: continue
            try: d = json.loads(line)
            except: continue
            if d.get("type") != "assistant": continue
            msg = d.get("message") or {}
            u = msg.get("usage")
            if not u: continue
            key = (msg.get("id"), u.get("output_tokens"), u.get("cache_read_input_tokens"))
            if key in seen: continue
            seen.add(key)
            model = msg.get("model") or "unknown"
            ts = d.get("timestamp","")[:10]
            if ts:
                mind = ts if mind is None or ts<mind else mind
                maxd = ts if maxd is None or ts>maxd else maxd
            cc = u.get("cache_creation") or {}
            rec = collections.Counter({
                "in": u.get("input_tokens",0) or 0,
                "out": u.get("output_tokens",0) or 0,
                "cw5": cc.get("ephemeral_5m_input_tokens",0) or 0,
                "cw1h": cc.get("ephemeral_1h_input_tokens",0) or 0,
                "cw_total": u.get("cache_creation_input_tokens",0) or 0,
                "cr": u.get("cache_read_input_tokens",0) or 0,
                "n": 1,
            })
            per_model[model].update(rec)
            per_day[ts].update(rec)
            per_file[rel].update(rec)
            reqs[model]+=1

def fmt(n): return f"{n:,}"

print(f"date range: {mind} .. {maxd}   files={len(files)}  requests={sum(reqs.values())}")
print()
hdr = f"{'model':<22}{'reqs':>7}{'input':>12}{'output':>12}{'cw 5m':>14}{'cw 1h':>14}{'cache read':>15}"
print(hdr); print("-"*len(hdr))
tot = collections.Counter()
for m,c in sorted(per_model.items(), key=lambda x:-x[1]["cr"]):
    print(f"{m:<22}{c['n']:>7}{fmt(c['in']):>12}{fmt(c['out']):>12}{fmt(c['cw5']):>14}{fmt(c['cw1h']):>14}{fmt(c['cr']):>15}")
    tot.update(c)
print("-"*len(hdr))
print(f"{'TOTAL':<22}{tot['n']:>7}{fmt(tot['in']):>12}{fmt(tot['out']):>12}{fmt(tot['cw5']):>14}{fmt(tot['cw1h']):>14}{fmt(tot['cr']):>15}")
print()
print("grand total tokens (all kinds):", fmt(tot['in']+tot['out']+tot['cw_total']+tot['cr']))
print("non-cached (in+out, what /usage shows):", fmt(tot['in']+tot['out']))
print()
print("per day:")
for day in sorted(per_day):
    c=per_day[day]
    print(f"  {day}  reqs={c['n']:>4}  in={fmt(c['in']):>10} out={fmt(c['out']):>9} cw={fmt(c['cw_total']):>11} cr={fmt(c['cr']):>13}")
print()
print("per file:")
for f_,c in sorted(per_file.items(), key=lambda x:-x[1]['cr']):
    print(f"  {f_:<70} reqs={c['n']:>4} cr={fmt(c['cr']):>13} out={fmt(c['out']):>9}")
