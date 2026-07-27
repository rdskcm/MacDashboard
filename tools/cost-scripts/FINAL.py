import json,os,glob,collections
PR={"claude-opus-4-8":(5,25),"claude-opus-5":(5,25),"claude-fable-5":(10,50),
    "claude-sonnet-5":(3,15),"claude-sonnet-4-6":(3,15),"claude-haiku-4-5-20251001":(1,5),"claude-haiku-4-5":(1,5)}
ARCH=os.path.expanduser("~/Documents/ClaudeRetrospective/claude-sessions-cleanup-2026-07-25")
LIVE=os.path.expanduser("~/.claude/projects/-Users-rdskcm-Claude-Projects-Optimizing-Mac-Usage-and-Settings")
files=glob.glob(os.path.join(ARCH,"**","*.jsonl"),recursive=True)+glob.glob(os.path.join(LIVE,"**","*.jsonl"),recursive=True)
best={}   # requestId -> final (max output) record
for f in files:
    is_sub="subagents" in f
    for line in open(f,errors="replace"):
        line=line.strip()
        if not line: continue
        try: d=json.loads(line)
        except: continue
        if d.get("type")!="assistant": continue
        m=d.get("message") or {}; u=m.get("usage"); mdl=m.get("model")
        if not u or mdl not in PR: continue
        rid=d.get("requestId")
        cur=best.get(rid)
        if cur is None or u.get("output_tokens",0)>cur[1].get("output_tokens",0):
            best[rid]=(mdl,u,d.get("timestamp","")[:10],is_sub)
tok=collections.Counter(); mc=collections.Counter(); mt=collections.defaultdict(collections.Counter)
day=collections.Counter(); dayn=collections.Counter(); sub=0.0
for rid,(mdl,u,dt,is_sub) in best.items():
    pin,po=PR[mdl]; cc=u.get("cache_creation") or {}
    c5=cc.get("ephemeral_5m_input_tokens",0); c1=cc.get("ephemeral_1h_input_tokens",0)
    if not(c5 or c1): c5=u.get("cache_creation_input_tokens",0)
    i,o,cr=u.get("input_tokens",0),u.get("output_tokens",0),u.get("cache_read_input_tokens",0)
    cost=i/1e6*pin+o/1e6*po+c1/1e6*pin*2+c5/1e6*pin*1.25+cr/1e6*pin*0.1
    tok.update({"in":i,"out":o,"cw":c5+c1,"cr":cr}); mc[mdl]+=cost
    mt[mdl].update({"out":o,"cr":cr,"cw":c5+c1,"n":1})
    if is_sub: sub+=cost
    day[dt]+=cost; dayn[dt]+=1
T=sum(mc.values()); G=sum(tok[k] for k in ("in","out","cw","cr")); vis=tok["in"]+tok["out"]
print(f"ОКОНЧАТЕЛЬНЫЙ РАСЧЁТ — {len(best):,} вызовов API, 45 сессий, весь проект\n")
print(f"{'тип токенов':<24}{'количество':>16}{'доля':>8}")
for lbl,k in (("Input (не из кэша)","in"),("Output","out"),("Запись в кэш","cw"),("Чтение из кэша","cr")):
    print(f"  {lbl:<22}{tok[k]:>16,}{tok[k]/G*100:>7.2f}%")
print(f"  {'ВСЕГО':<22}{G:>16,}")
print(f"\n  input+output (то, что показывает /usage): {vis:,} = {vis/G*100:.2f}%")
print(f"  кэш-чтение / output: {tok['cr']/tok['out']:.0f}x")
print(f"  средний контекст на вызов: {tok['cr']/len(best):,.0f} токенов\n")
print(f"{'модель':<12}{'вызовов':>9}{'output':>11}{'кэш-чтение':>14}{'$':>9}{'доля':>7}")
for m,c in mc.most_common():
    t=mt[m]
    print(f"{m.replace('claude-','').replace('-20251001',''):<12}{t['n']:>9,}{t['out']:>11,}{t['cr']:>14,}{c:>9.2f}{c/T*100:>6.1f}%")
print(f"{'ИТОГО':<12}{len(best):>9,}{tok['out']:>11,}{tok['cr']:>14,}{T:>9.2f}")
print(f"\n{'дата':<12}{'вызовов':>9}{'$':>9}")
for d0 in sorted(day): print(f"{d0:<12}{dayn[d0]:>9,}{day[d0]:>9.2f}")
b=sum(day[d] for d in day if "2026-07-12"<=d<="2026-07-20")
p=sum(day[d] for d in day if d>="2026-07-22")
print(f"\n12–20 июля (SwiftUI → публикация): ${b:,.2f}")
print(f"22–25 июля (публикации):           ${p:,.2f}")
print(f"ИТОГО ПРОЕКТ:                      ${T:,.2f}")
print(f"субагенты: ${sub:,.2f} ({sub/T*100:.0f}% счёта)")
print(f"средняя цена вызова: ${T/len(best):.3f}")
naive=sum(((u.get('input_tokens',0)+u.get('cache_read_input_tokens',0)+((u.get('cache_creation') or {}).get('ephemeral_5m_input_tokens',0)+(u.get('cache_creation') or {}).get('ephemeral_1h_input_tokens',0) or u.get('cache_creation_input_tokens',0)))/1e6*PR[m][0]+u.get('output_tokens',0)/1e6*PR[m][1]) for m,u,_,_ in best.values())
print(f"\nбез prompt caching было бы: ${naive:,.0f}  (экономия ${naive-T:,.0f}, {(1-T/naive)*100:.0f}%)")
