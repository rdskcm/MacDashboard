import json,os,glob,collections,datetime
PR={"claude-opus-4-8":(5,25),"claude-opus-5":(5,25),"claude-fable-5":(10,50),
    "claude-sonnet-5":(3,15),"claude-sonnet-4-6":(3,15),"claude-haiku-4-5-20251001":(1,5),
    "claude-haiku-4-5":(1,5),"claude-mythos-5":(10,50)}
ARCH=os.path.expanduser("~/Documents/ClaudeRetrospective/claude-sessions-cleanup-2026-07-25")
LIVE=os.path.expanduser("~/.claude/projects/-Users-rdskcm-Claude-Projects-Optimizing-Mac-Usage-and-Settings")
files=glob.glob(os.path.join(ARCH,"**","*.jsonl"),recursive=True)+glob.glob(os.path.join(LIVE,"**","*.jsonl"),recursive=True)

seen=set(); S=collections.defaultdict(lambda: {"c":0.0,"n":0,"out":0,"cr":0,"cw":0,"t0":None,"t1":None,
                                               "mdl":collections.Counter(),"sub":0})
day=collections.defaultdict(float); mdlc=collections.Counter(); mdltok=collections.defaultdict(collections.Counter)
unknown=collections.Counter()
for f in files:
    p=os.path.relpath(f,ARCH if f.startswith(ARCH) else LIVE)
    sid=p.split("/")[0].replace(".jsonl","")          # subagent files roll into parent session
    is_sub="subagents" in p
    for line in open(f,errors="replace"):
        line=line.strip()
        if not line: continue
        try: d=json.loads(line)
        except: continue
        if d.get("type")!="assistant": continue
        m=d.get("message") or {}; u=m.get("usage"); mdl=m.get("model")
        if not u: continue
        if mdl not in PR:
            unknown[mdl]+=1; continue
        k=(m.get("id"),u.get("output_tokens"),u.get("cache_read_input_tokens"))
        if k in seen: continue
        seen.add(k)
        pin,pout=PR[mdl]; cc=u.get("cache_creation") or {}
        c5=cc.get("ephemeral_5m_input_tokens",0) or 0
        c1=cc.get("ephemeral_1h_input_tokens",0) or 0
        if not (c5 or c1): c5=u.get("cache_creation_input_tokens",0) or 0   # fallback
        cr=u.get("cache_read_input_tokens",0) or 0
        cost=(u.get("input_tokens",0)/1e6*pin + u.get("output_tokens",0)/1e6*pout
              + c1/1e6*pin*2 + c5/1e6*pin*1.25 + cr/1e6*pin*0.1)
        ts=d.get("timestamp","")
        s=S[sid]; s["c"]+=cost; s["n"]+=1; s["out"]+=u.get("output_tokens",0); s["cr"]+=cr; s["cw"]+=c5+c1
        s["mdl"][mdl]+=cost
        if is_sub: s["sub"]+=cost
        if ts:
            if s["t0"] is None or ts<s["t0"]: s["t0"]=ts
            if s["t1"] is None or ts>s["t1"]: s["t1"]=ts
            day[ts[:10]]+=cost
        mdlc[mdl]+=cost
        mdltok[mdl].update({"out":u.get("output_tokens",0),"cr":cr,"cw":c5+c1})
if unknown: print("НЕИЗВЕСТНЫЕ МОДЕЛИ (пропущены):",dict(unknown),"\n")
T=sum(s["c"] for s in S.values())
print(f"ТОЧНЫЙ РАСЧЁТ ПО ТРАНСКРИПТАМ  —  {len(S)} сессий, {sum(s['n'] for s in S.values()):,} запросов\n")
print("ТОП-15 САМЫХ ДОРОГИХ СЕССИЙ")
h=f"{'начата':<17}{'длит.':>8}{'запр.':>7}{'кэш-чтение':>13}{'субаг.$':>9}{'$':>8}"
print(h); print("-"*len(h))
for sid,s in sorted(S.items(),key=lambda x:-x[1]["c"])[:15]:
    t0=datetime.datetime.fromisoformat(s["t0"].replace("Z","+00:00")).astimezone()
    t1=datetime.datetime.fromisoformat(s["t1"].replace("Z","+00:00")).astimezone()
    dur=(t1-t0); hh=int(dur.total_seconds()//3600); mm=int(dur.total_seconds()%3600//60)
    top=s["mdl"].most_common(1)[0][0].replace("claude-","").replace("-20251001","")
    print(f"{t0.strftime('%d.%m %H:%M'):<17}{f'{hh}ч{mm:02d}м':>8}{s['n']:>7}{s['cr']:>13,}{s['sub']:>9.2f}{s['c']:>8.2f}  {top}")
print("-"*len(h))
print(f"\nПО ДНЯМ")
for d0 in sorted(day): print(f"  {d0}  ${day[d0]:>8.2f}")
print(f"\nПО МОДЕЛЯМ")
for m,c in mdlc.most_common():
    t=mdltok[m]
    print(f"  {m.replace('claude-','').replace('-20251001',''):<12} out={t['out']:>10,} кэш-чт={t['cr']:>13,}  ${c:>8.2f}  {c/T*100:>5.1f}%")
print(f"\nИТОГО ПО ПРОЕКТУ (точно, без экстраполяции): ${T:,.2f}")
sub=sum(s["sub"] for s in S.values())
print(f"из них субагенты: ${sub:,.2f} ({sub/T*100:.0f}%)")
