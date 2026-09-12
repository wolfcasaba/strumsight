# ADR 0570 — A két-tier routing JELE asset-specifikus: a szállított assetn a margó lapos, a letisztult tier mégis +0,192-t ér — de csak minden ütésre alkalmazva

- **Státusz:** elfogadva (mérés + egy **sötét** konstans indoklásának javítása; semmi nem
  kerül felkapcsolásra)
- **Dátum:** 2026-09-12
- **Kör:** E18-R43
- **Kapcsolódó:** ADR 0563 (a szabály, amit ez újramér), ADR 0556 D1/D3 (a nyíl és a
  revízió-költség), ADR 0566 D3 (a nyíl **ma nincs**), ADR 0569 (miért a szállított asset a
  mérvadó), ADR 0565 (a forward mért költsége), `docs/LESSONS.md` L672 §2, L685,
  `ml/probe_settled_tier_value.py`

## Kontextus

Az ADR 0569 kimondta, hogy a settled asset nem szállítható, és megnevezte a következő
lépést: **az ADR 0563 két-tier mérését a szállított assetn meg kell ismételni.** Ez az.

## Döntés

### D1 — A próba megnevezi az assetet, és a default EGZAKTAN reprodukálja az ADR 0563-at

`ml/probe_settled_tier_value.py` mostantól `--asset=PATH [--gate=X]`-szel bármely SSML
blobot mér (az ADR 0569 `read_ssml.py`-ján keresztül), és **kiírja, melyik assetet mérte**.
Argumentum nélkül a settled súlyokat és a saját osztály-feltételes kapuját használja —
és a kimenet szám szerint azonos az ADR 0563-ban rögzítettel:

```
  settled asset, 0,2929-es kapu   fast 0,5262   hibrid@0,30 0,5813   +0,0551
```

Ez a paraméterezés **regressziós ellenőrzése**: ha az átalakítás bármit elmozdított volna,
ez a sor nem egyezne.

### D2 — A szállított assetn a margó NEM jelzi, hogy a gyors hívás helyes-e

Ugyanaz a próba, ugyanaz a szelet, ugyanaz az 530 ütés,
`--asset=assets/ml/strum_crnn_live_3c.bin` a saját 0,85-es kapuján:

```
  fast margó    n     fast pontosság     settled asset (ADR 0563)
   0,0–0,2      32       0,2188               0,4000
   0,2–0,4      22       0,4545               0,4167
   0,4–0,6      35       0,2286               0,5455
   0,6–0,8      60       0,3000               0,5588
   0,8–1,0     381       0,3202               0,8500
```

A settled assetn **monoton** 0,40 → 0,85. A szállítotton **lapos és nem monoton**
(0,22 / 0,45 / 0,23 / 0,30 / 0,32). Vagyis az L672 §2 kritériuma — *a margó akkor
legitim routing-jel, ha tényleg jelzi a hibát* — a settled assetn **teljesül**, a
szállítotton **nem**.

*A routing-jel érvényessége tehát nem az ötlet tulajdonsága, hanem a modellé.*

### D3 — A letisztult tier a szállított assetn IS sokat ér, csak máshol

```
  szállított asset, 0,85-es kapu    macro    le-F1    fel-F1
  csak gyors (ez ships ma)          0,3340   0,4346   0,2333
  csak letisztult                   0,5259   0,7938   0,2581   (+0,1919)
```

És ahol a nyereség **van**:

```
  t=0,30   rövid margó        n= 44   gyors 0,3182 → letisztult 0,4091   (+0,0909)
  t=0,30   megfelelő margó    n=486   gyors 0,3107 → letisztult 0,6337   (+0,3230)
```

A nyereség tehát a **megfelelő** margójú ütéseken nagyobb — pont azokon, amiket az ADR 0563
szabálya **nem** küld a letisztult tierre. Ezért a `_settleBelowMargin = 0.30` a szállított
assetn a rendelkezésre álló **+0,1919-ből +0,0044-et** fog:

```
  hibrid@0,30  0,3384   (+0,0044)
  hibrid@0,90  0,3803   (+0,0464)
  csak letisztult 0,5259 (+0,1919)
```

**A szállított assethez tartozó szabály tehát nem „a rövid margójúakat letisztítani", hanem
„MINDEN ütést letisztítani".**

### D4 — És az UX-ellenvetés, ami ezt eddig kizárta, MA nem kötelez

Az ADR 0556 D1 a „mindent letisztítani" utat a **revízió-költségre** hivatkozva vetette el
(Du, CHI 2023), a D3 pedig azért, mert minden nyíl **irány-semleges** lenne. Mérve ADR 0566
D3-ban: **egyetlen szállított felület sem rajzol ÉSZLELT irányt.** A `RhythmLane` a notált
rácsot, a `practice_highway` és a `practice_feedback` a **várt** irányt; az egyetlen észlelt
irányt mutató felület a megosztó kártya, az ADR 0556 élő nyila pedig **sötét**.

Tehát a „100% irány-semleges nyíl" ára ma **nulla**, mert nincs nyíl, amit semlegesíteni
kellene. A pontozó pedig a kísérlet **végén** értékel (`_gradeAttempt`), ahol egy 238 ms-os
irány-késés nem számít.

**Egy él-eset kimondva, nem elhallgatva:** a kísérlet **utolsó** ütése. Ha a letisztult
verdikt a kísérlet lezárása után érkezne, az az ütés bizonyíték nélkül maradna — a bekötés
dolga lesz a lezárást a legutolsó onset letisztult pillanatáig (onset + 238 ms) kivárni.

**A költség viszont nem nulla, és levezetett, nem újonnan mért:** minden ütésre egy második
forward. Az ADR 0565 mérése szerint a ritkásított forward a gyors tiert 200 bpm
tizenhatodon 22,2%, 80 bpm nyolcadon 4,4% magra teszi — tehát „mindent letisztítani"
**kétszerezi**: ~44% és ~8,8%. (Az ADR 0563 19,8%-os routingja ennél jóval kevesebbet
költött, de a fentiek szerint majdnem semmit nem vásárolt.)

### D5 — Ezért ebben a körben sem kapcsolunk fel semmit

Két hiányzó dolog miatt:

1. **Nincs in-situ szám a letisztult tierre.** A `guitarset_threshold_sweep_test.dart` egy
   onsetre **egy** osztályozást rögzít, a 70 ms-osat; a letisztult pillanat in-situ
   méréséhez a recordernek egy második, csonkítatlan ablakos hívást is rögzítenie kell. A
   D3 számai **orákulum**-ablakokon készültek.
2. **A pontozó irány-forrásának megváltoztatása DSP-változás**, tehát az AGENTS.md §9 négy
   lábát kívánja, és a D4 él-esete (az utolsó ütés lezárása) külön teszt-felületet.

Amit a kör **ad**: a `_settleBelowMargin` doc-kommentje mostantól **megnevezi az assetet**,
amin a tábla készült, és hordozza a szállított asset ellen-tábláját is — tehát a következő
olvasó nem veszi át egy asset-specifikus indoklást általánosnak.

## Következmények

- Az ADR 0563 döntése **érvényes a settled assetre** és **nem érvényes a szállítottra**. A
  `settledTier` felkapcsolása innentől két dolog közül választ: vagy egy asset, amin a margó
  jelez (és ami az ADR 0569 kritériumát is teljesíti), vagy a „mindent letisztítani" szabály
  a maga kétszeres CPU-jával.
- Az ADR 0556 D3 routing-szabálya (rövid margó → semleges nyíl + letisztult irány a
  pontozónak) **a settled asset** tulajdonságára épült. Ha az nem szállít, a szabály
  újragondolásra vár.

## Amit NEM állítunk

- **Orákulum-ablakok, nem in situ.** A D3 számai a Python úton, annotált onsetre épített
  ablakokból jönnek; a szállított út fast-tier in-situ macrója az ADR 0567 szerint 0,3872
  (hasonló nagyságrend, más műszer), a letisztult tier in-situ értéke **nincs megmérve**.
- **Nem magyarázzuk meg**, miért jobb a szállított asset a **csonkítatlan** ablakon, amit
  sosem látott (`train_live_3c.py` csak `live70`-et tölt). Kézenfekvő sejtés volna „több
  hang = több információ", de ez sejtés, és az L681 szabálya szerint nem írjuk mechanizmusnak.
- **n=530, egy szelet**, szórás-becslés nélkül; a 0,2–0,4-es margó-sáv n=22, tehát a
  nem-monotonitás egyetlen sora önmagában zajos — a **laposság** az állítás, nem a
  sorrend.
- **A fel-F1 a szállított assetn a letisztult tierrel is csak 0,2581.** Az ADR 0553
  adat-diagnózisa áll: ez a tier nem adat-pótlás.
