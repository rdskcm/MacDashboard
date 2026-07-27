def calc(i,o,cr,cw,pin,pout,ttl1h):
    return i/1e6*pin + o/1e6*pout + cr/1e6*pin*0.1 + cw/1e6*pin*(2.0 if ttl1h else 1.25)

print("СЕССИЯ 12 ИЮЛЯ  (официально Total cost $25.62)")
s1=[("fable-5",653,82_200,4_700_000,480_400,18.39,10,50,True),
    ("sonnet-5",60_400,188_300,8_800_000,402_400,7.15,3,15,False),
    ("haiku-4-5",50,2_400,86_300,39_900,0.0705,1,5,False)]
print("СЕССИЯ 17 ИЮЛЯ  (официально Total cost $34.02)")
s2=[("fable-5",2_400,115_200,18_300_000,244_100,28.94,10,50,True),
    ("sonnet-5",4_400,79_600,5_100_000,282_300,3.77,3,15,False),
    ("opus-4-8",116_600,28_900,0,0,1.31,5,25,False)]
for label,ss,official in (("12 июля",s1,25.62),("17 июля",s2,34.02)):
    print(f"\n=== {label} ===")
    print(f"{'модель':<11}{'расчёт $':>10}{'офиц. $':>10}{'ошибка':>9}")
    T=0
    for n,i,o,cr,cw,off,pin,pout,t in ss:
        c=calc(i,o,cr,cw,pin,pout,t); T+=c
        print(f"{n:<11}{c:>10.4f}{off:>10.4f}{abs(c-off)/off*100:>8.1f}%")
    print(f"{'ИТОГО':<11}{T:>10.2f}{official:>10.2f}{abs(T-official)/official*100:>8.1f}%")
