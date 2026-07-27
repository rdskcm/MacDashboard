# Reproduce the official per-model costs from the Jul 12 /usage screenshot
obs = [  # model, input, output, cache_read, cache_write, official $
 ("fable-5",  653,    82_200,  4_700_000, 480_400, 18.39,  10, 50),
 ("sonnet-5", 60_400, 188_300, 8_800_000, 402_400,  7.15,   3, 15),
 ("haiku-4-5",50,      2_400,     86_300,  39_900,  0.0705, 1,  5),
]
print("Проверка формулы на официальных числах Claude Code (сессия 12 июля)\n")
print(f"{'модель':<11}{'TTL 5m $':>10}{'TTL 1h $':>10}{'официально':>12}{'совпало':>10}")
print("-"*53)
tot5=tot1=totof=0
for name,i,o,cr,cw,off,pin,pout in obs:
    base = i/1e6*pin + o/1e6*pout + cr/1e6*pin*0.1
    c5 = base + cw/1e6*pin*1.25
    c1 = base + cw/1e6*pin*2.0
    pick = "5m" if abs(c5-off)<abs(c1-off) else "1h"
    err = min(abs(c5-off),abs(c1-off))/off*100
    print(f"{name:<11}{c5:>10.4f}{c1:>10.4f}{off:>12.4f}{pick+f' ({err:.1f}%)':>10}")
    tot5+=c5; tot1+=c1; totof+=off
print("-"*53)
print(f"{'сумма':<11}{tot5:>10.2f}{tot1:>10.2f}{totof:>12.2f}")
print(f"\nОфициальный Total cost на скрине: $25.62   |   сумма по моделям: ${totof:.2f}")
print("\nВывод: цены Sonnet 5 — штатные $3/$15 (не вводные $2/$10).")
print("TTL кэш-записи: Fable — часовой, Sonnet и Haiku — пятиминутный.")
