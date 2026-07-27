import json,os,glob,collections,datetime,re
PR={"claude-opus-4-8":(5,25),"claude-opus-5":(5,25),"claude-fable-5":(10,50),
    "claude-sonnet-5":(3,15),"claude-sonnet-4-6":(3,15),"claude-haiku-4-5-20251001":(1,5),"claude-haiku-4-5":(1,5)}
ARCH=os.path.expanduser("~/Documents/ClaudeRetrospective/claude-sessions-cleanup-2026-07-25")
LIVE=os.path.expanduser("~/.claude/projects/-Users-rdskcm-Claude-Projects-Optimizing-Mac-Usage-and-Settings")
files=glob.glob(os.path.join(ARCH,"**","*.jsonl"),recursive=True)+glob.glob(os.path.join(LIVE,"**","*.jsonl"),recursive=True)
best={}
for f in files:
    base=ARCH if f.startswith(ARCH) else LIVE
    sid=os.path.relpath(f,base).split("/")[0].replace(".jsonl","")
    for line in open(f,errors="replace"):
        line=line.strip()
        if not line: continue
        try: d=json.loads(line)
        except: continue
        if d.get("type")!="assistant": continue
        m=d.get("message") or {}; u=m.get("usage"); mdl=m.get("model")
        if not u or mdl not in PR: continue
        rid=d.get("requestId"); cur=best.get(rid)
        if cur is None or u.get("output_tokens",0)>cur[1].get("output_tokens",0):
            best[rid]=(mdl,u,d.get("timestamp",""),sid)
S=collections.defaultdict(lambda:{"c":0.0,"n":0,"t0":None,"t1":None,"m":collections.Counter()})
for rid,(mdl,u,ts,sid) in best.items():
    pin,po=PR[mdl]; cc=u.get("cache_creation") or {}
    c5=cc.get("ephemeral_5m_input_tokens",0); c1=cc.get("ephemeral_1h_input_tokens",0)
    if not(c5 or c1): c5=u.get("cache_creation_input_tokens",0)
    cost=(u.get("input_tokens",0)/1e6*pin+u.get("output_tokens",0)/1e6*po
          +c1/1e6*pin*2+c5/1e6*pin*1.25+u.get("cache_read_input_tokens",0)/1e6*pin*0.1)
    s=S[sid]; s["c"]+=cost; s["n"]+=1; s["m"][mdl]+=cost
    if ts:
        if s["t0"] is None or ts<s["t0"]: s["t0"]=ts
        if s["t1"] is None or ts>s["t1"]: s["t1"]=ts
# names from INDEX.md
names={}
idx=os.path.expanduser("~/Documents/ClaudeRetrospective/INDEX.md")
T=sum(s["c"] for s in S.values())
print(f"45 сессий, ${T:,.2f}, средняя ${T/len(S):.2f}\n")
print(f"{'начата (местное)':<18}{'длительность':>13}{'вызовов':>9}{'$':>9}  ведущая модель")
print("-"*66)
for sid,s in sorted(S.items(),key=lambda x:-x[1]["c"])[:12]:
    t0=datetime.datetime.fromisoformat(s["t0"].replace("Z","+00:00")).astimezone()
    t1=datetime.datetime.fromisoformat(s["t1"].replace("Z","+00:00")).astimezone()
    sec=(t1-t0).total_seconds()
    print(f"{t0.strftime('%d.%m %H:%M'):<18}{f'{int(sec//3600)}ч {int(sec%3600//60):02d}м':>13}{s['n']:>9,}{s['c']:>9.2f}  {s['m'].most_common(1)[0][0].replace('claude-','')}")
print("-"*66)
near=[(abs(s['c']-25.62),sid,s,25.62) for sid,s in S.items()]+[(abs(s['c']-34.02),sid,s,34.02) for sid,s in S.items()]
print("\nБлижайшие к официальным экранам:")
for tgt in (25.62,34.02):
    d,sid,s,_=min([x for x in near if x[3]==tgt])
    t0=datetime.datetime.fromisoformat(s["t0"].replace("Z","+00:00")).astimezone()
    print(f"  экран ${tgt}: сессия {sid[:8]} от {t0.strftime('%d.%m %H:%M')} — ${s['c']:.2f} (расхождение ${d:.2f})")
