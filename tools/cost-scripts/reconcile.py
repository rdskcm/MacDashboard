import json,os,glob,collections
ARCH=os.path.expanduser("~/Documents/ClaudeRetrospective/claude-sessions-cleanup-2026-07-25")
LIVE=os.path.expanduser("~/.claude/projects/-Users-rdskcm-Claude-Projects-Optimizing-Mac-Usage-and-Settings")
files=glob.glob(os.path.join(ARCH,"**","*.jsonl"),recursive=True)+glob.glob(os.path.join(LIVE,"**","*.jsonl"),recursive=True)
print(f"файлов .jsonl прочитано: {len(files)}")
seen=set(); vis=collections.defaultdict(collections.Counter)
for f in files:
    for line in open(f,errors="replace"):
        line=line.strip()
        if not line: continue
        try: d=json.loads(line)
        except: continue
        if d.get("type")!="assistant": continue
        m=d.get("message") or {}; u=m.get("usage"); mdl=m.get("model")
        if not u or not mdl or mdl=="<synthetic>": continue
        k=(m.get("id"),u.get("output_tokens"),u.get("cache_read_input_tokens"))
        if k in seen: continue
        seen.add(k)
        mdl="claude-haiku-4-5-20251001" if mdl.startswith("claude-haiku") else mdl
        vis[d.get("timestamp","")[:10]][mdl]+=u.get("input_tokens",0)+u.get("output_tokens",0)
S=json.load(open(os.path.expanduser("~/.claude/stats-cache.json")))
A=lambda k:"claude-haiku-4-5-20251001" if k.startswith("claude-haiku") else k
print(f"\n{'дата':<12}{'stats-cache':>14}{'архив':>12}{'покрытие':>10}")
print("-"*48)
ts=ta=0
for e in S["dailyModelTokens"]:
    d0=e["date"]; sc=sum(e["tokensByModel"].values()); ar=sum(vis[d0].values())
    ts+=sc; ta+=ar
    print(f"{d0:<12}{sc:>14,}{ar:>12,}{(ar/sc*100 if sc else 0):>9.0f}%")
print("-"*48)
print(f"{'ИТОГО':<12}{ts:>14,}{ta:>12,}{ta/ts*100:>9.0f}%")
extra=sum(sum(v.values()) for d,v in vis.items() if d>"2026-07-21")
print(f"\nв архиве сверх периода stats-cache (22-25.07): {extra:,}")
