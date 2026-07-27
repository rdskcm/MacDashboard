import json, os, glob, collections
ROOT=os.path.expanduser("~/.claude/projects/-Users-rdskcm-Claude-Projects-Optimizing-Mac-Usage-and-Settings")
PRICE={"claude-opus-4-8":(5,25),"claude-opus-5":(5,25),"claude-sonnet-5":(2,10)}
seen=set(); agg=collections.defaultdict(lambda: collections.Counter())
for f in glob.glob(os.path.join(ROOT,"**","*.jsonl"),recursive=True):
    for line in open(f):
        line=line.strip()
        if not line: continue
        try: d=json.loads(line)
        except: continue
        if d.get("type")!="assistant": continue
        m=d.get("message") or {}; u=m.get("usage")
        if not u: continue
        k=(m.get("id"),u.get("output_tokens"),u.get("cache_read_input_tokens"))
        if k in seen: continue
        seen.add(k)
        day=d.get("timestamp","")[:10]
        if day < "2026-07-22": continue   # >= Jul 22 only (Jul<=20 already in stats-cache)
        cc=u.get("cache_creation") or {}
        agg[m.get("model")].update({"in":u.get("input_tokens",0),"out":u.get("output_tokens",0),
            "cw5":cc.get("ephemeral_5m_input_tokens",0),"cw1h":cc.get("ephemeral_1h_input_tokens",0),
            "cr":u.get("cache_read_input_tokens",0),"n":1})
T=0; tk=collections.Counter()
print(f"{'model':<20}{'reqs':>6}{'output':>10}{'cache wr':>12}{'cache rd':>14}{'cost $':>10}")
print('-'*72)
for mdl,c in sorted(agg.items(),key=lambda x:-x[1]["cr"]):
    if mdl not in PRICE: continue
    pin,pout=PRICE[mdl]
    cost=c["in"]/1e6*pin + c["out"]/1e6*pout + c["cw1h"]/1e6*pin*2 + c["cw5"]/1e6*pin*1.25 + c["cr"]/1e6*pin*0.1
    T+=cost; tk.update(c)
    print(f"{mdl.replace('claude-',''):<20}{c['n']:>6}{c['out']:>10,}{c['cw5']+c['cw1h']:>12,}{c['cr']:>14,}{cost:>10.2f}")
print('-'*72)
print(f"{'TAIL (Jul 22-25)':<20}{tk['n']:>6}{tk['out']:>10,}{tk['cw5']+tk['cw1h']:>12,}{tk['cr']:>14,}{T:>10.2f}")
print(f"\ntail tokens total: {tk['in']+tk['out']+tk['cw5']+tk['cw1h']+tk['cr']:,}")
print(f"1h share of cache writes in tail: {tk['cw1h']/(tk['cw5']+tk['cw1h'])*100:.0f}%")
