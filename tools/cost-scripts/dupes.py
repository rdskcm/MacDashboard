import json,os,glob,collections
ARCH=os.path.expanduser("~/Documents/ClaudeRetrospective/claude-sessions-cleanup-2026-07-25")
LIVE=os.path.expanduser("~/.claude/projects/-Users-rdskcm-Claude-Projects-Optimizing-Mac-Usage-and-Settings")
files=glob.glob(os.path.join(ARCH,"**","*.jsonl"),recursive=True)+glob.glob(os.path.join(LIVE,"**","*.jsonl"),recursive=True)
where=collections.defaultdict(set); n=0; tok=collections.Counter()
for f in files:
    base=ARCH if f.startswith(ARCH) else LIVE
    rel=os.path.relpath(f,base)
    for line in open(f,errors="replace"):
        line=line.strip()
        if not line: continue
        try: d=json.loads(line)
        except: continue
        if d.get("type")!="assistant": continue
        m=d.get("message") or {}; u=m.get("usage")
        if not u or not m.get("id"): continue
        n+=1; where[m["id"]].add(rel)
        tok["raw_cr"]+=u.get("cache_read_input_tokens",0); tok["raw_out"]+=u.get("output_tokens",0)
uniq=len(where)
dup={k:v for k,v in where.items() if len(v)>1}
print(f"всего assistant-записей с usage : {n:,}")
print(f"уникальных message.id           : {uniq:,}")
print(f"коэффициент дублирования        : {n/uniq:.2f}x")
print(f"id, встречающихся в >1 файле    : {len(dup):,} ({len(dup)/uniq*100:.0f}% уникальных)")
print(f"\nсырые суммы БЕЗ дедупликации: output {tok['raw_out']:,}  кэш-чтение {tok['raw_cr']:,}")
print(f"stats-cache (проект+прочее):  output 9,995,676   кэш-чтение 1,018,159,376")
print("\nПРИМЕРЫ дублей — в каких файлах встречается один и тот же message.id:")
for i,(k,v) in enumerate(sorted(dup.items(),key=lambda x:-len(x[1]))[:5]):
    print(f"  {k[:30]}  в {len(v)} файлах:")
    for p in sorted(v)[:6]: print(f"      {p}")
