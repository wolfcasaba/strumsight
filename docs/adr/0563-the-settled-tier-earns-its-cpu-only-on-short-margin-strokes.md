# ADR 0563 — A letisztult tier csak a RÖVID MARGÓJÚ ütéseken éri meg: a nyereség 84%-a a költség ötödéért

- **Státusz:** elfogadva (mérés + routing; a tier **marad sötét**, a felkapcsolás
  profile-build költségmérést kíván)
- **Dátum:** 2026-09-12
- **Kör:** E18-R40
- **Kapcsolódó:** ADR 0556 D3 (a gyors/letisztult megjelenítési szabály), ADR 0559 (a tier
  megépült és sötét), ADR 0562 (a fúzió megengedhetetlen — ez a kör az, ami **marad**),
  `ml/probe_settled_tier_value.py`, `docs/LESSONS.md` L679 és az **L672 §2 korrekciója**

## Kontextus

Az ADR 0562 bezárta a fúziót: a metrikus csatorna nem érhet a pontozó útra. A **kétszintű
döntés** viszont érintetlenül átélte, mert **tisztán akusztikus** — ugyanaz a modell, ugyanaz
az ablak, csak több hang érkezett meg (ADR 0552/0554). Nincs benne rács, nincs benne
megoldókulcs.

A mért terv az ADR 0556 D3, az egyetlen elrendezés, ami nem mér a tanuló ellen olyannal, amit
nem látott:

- **elég margó** a gyors hívásnál → a nyíl azt az irányt mutatja, és **a pontozó ugyanazt
  használja** (különben a nyíl hazudott);
- **rövid margó** → **irány-semleges** ütés-jel, és a pontozó a **letisztult** irányt
  használja, mert a tanulónak nem mutattunk állítást, amit megcáfolhatnánk.

## Mérés (`ml/probe_settled_tier_value.py`, tartalék GuitarSet: ismeretlen játékos ÉS dal, 530 ütés)

```
  tier                       macro   le-F1   fel-F1   semleges nyíl   2. forward
  csak gyors (ma szállít)   0,5262  0,7743  0,2780        0%             0%
  csak letisztult           0,5917  0,8481  0,3353      100%           100%
```

A „csak letisztult" **nem szállítható sor**: minden nyíl ~238 ms-ot várna, amit az ADR 0556 D1
a mért javítás-költség miatt elvet.

Az ADR 0556 D3 hibrid (gyors a margó felett, letisztult alatta):

```
  margó t    macro   semleges nyíl / 2. forward    vs gyors
    0,10    0,5389            6,4 %                +0,0127
    0,30    0,5813           19,8 %                +0,0551   <- választva
    0,50    0,5811           32,5 %                +0,0550
    0,70    0,6044           49,1 %                +0,0783
    0,90    0,5917           74,7 %                +0,0655
    1,01    0,5917          100,0 %                +0,0655   (= csak letisztult)
```

A `t = 0` a csak-gyors, a `t > 1` a csak-letisztult: **az alapvonal és a plafon ugyanazon
görbe pontjai**, nem külön kódutak.

**Hol van a nyereség:**

```
  t=0,30  rövid margó      n=105   gyors 0,3619 -> letisztult 0,6762   (+0,3143)
  t=0,30  elég margó       n=425   gyors 0,7059 -> letisztult 0,7459   (+0,0400)
  t=0,90  rövid margó      n=396   gyors 0,5480 -> letisztult 0,6742   (+0,1263)
  t=0,90  elég margó       n=134   gyors 0,9030 -> letisztult 0,9030   (+0,0000)
```

**És a margó tényleg mér megbízhatóságot** — ez az, ami a margóra való útválasztást
legitimálja:

```
  gyors margó   n     gyors pontosság
   0,0-0,2      70       0,4000
   0,2-0,4      72       0,4167
   0,4-0,6      66       0,5455
   0,6-0,8     102       0,5588
   0,8-1,0     220       0,8500
```

## Döntés

### D1 — A szállítandó munkapont `t = 0,30`

A nyereség **84%-a** (+0,0551 a +0,0655-ből) a költség **ötödéért** (19,8% vs 100%). A
magasabb sorok **nem** kerülnek választásra: 0,3 fölött a görbe ezen a minta-méreten
önmagától pár ütésen belül van — a `t = 0,70` sor még a csak-letisztultat is meghaladja, amit
530 ütésen egy fel-F1 **nem tud alátámasztani** —, és minden lépés **CPU-t és irány-semleges
nyilakat** is fizet.

### D2 — A költség-kalkulus megváltozik az ADR 0559-hez képest: nem duplázás, hanem +20%

Az ADR 0559 D3 úgy fogalmazott, hogy a tier bekapcsolása „**ütésenként** egy második
forwardot" jelent. Ez az R36-os implementációra igaz volt, ami **minden** bejelentett ütést
sorba állított. Routinggal ez **19,8%**, mert egy magabiztos gyors hívás nem kér letisztultat
— és mérve nem is érdemes: a 0,8–1,0 margó-sávban a gyors pontosság **0,8500**.

Az analyzer ezért csak akkor sorba állít, ha a gyors verdikt margója `< 0,30`, **vagy** ha a
gyors hívás **nem nevezett irányt** (akkor nincs nyíl-állítás, amit egy későbbi verdikt
megcáfolhatna, és a pontozónak különben semmije nem lenne).

### D3 — A tier MARAD SÖTÉT, amíg a költség nincs profile-buildben megmérve

A `settledTier = false` default **nem változik**. Ami változott: a felkapcsolás **ára**
lényegesen kisebb, és a **haszna** mért (+0,0551 macro tartalék korpuszon). A felkapcsolás
feltétele továbbra is a **profile-build** költségszám — a JIT-es teszt-harnesz ~29 ms-os
forwardja nem on-device szám és nem átvihető (ADR 0559).

### D4 — És ez KORRIGÁLJA az L672 §2 magyarázatát

Az L672 §2-ben ezt írtam a fúziós körről: *„A margó 70 ms-on **nem mér megbízhatóságot**,
tehát a rá épített óvatosság nem óvatosság, hanem zaj."* **Ez téves.** Mérve a margó
monoton: 0,40 → 0,85.

A valódi ok, amiért a teljes fúzió akkor megverte a döntetlen-törőt: a teljes fúzió
`lam = 0,99`-nél **gyakorlatilag a rácsra cserélte az akusztikus hívást mindenhol**, és egy
**96%-ban inga-követő** korpusz ezt jutalmazza. A döntetlen-törő csak a rövid margójú
ütéseken támaszkodott a rácsra, tehát **kevesebbet nyert ebből** — vagyis az összehasonlítás
a margó megbízhatóságáról **semmit nem mondott**.

Ez **erősíti az ADR 0562-t**: a „jobb" fúziós sor azért volt jobb, mert **többet csalt**.

## Következmények

- A `StrumAnalyzer` útválasztása mért konstans (`_settleBelowMargin = 0.30`), a táblával a
  doksijában.
- Három új teszt pinneli: magabiztos gyors verdikt → **a második forward ki sem megy**;
  **null irányú** gyors verdikt → mindig settle-el; **valószínűség nélküli** osztályozó → soha.
- A sötét-default őrtesztje most **rövid margós** verdiktet használ, hogy a zöld állítás azt
  bizonyítsa, hogy **a flag** állította meg, nem az útválasztás.

## Amit NEM állítunk

- **Nincs on-device költségszám.** A +20% *relatív* szám; az absztrakt ár profile-buildből jön.
- A 0,5813 **egy korpusz egy tartalék felosztása**, 530 ütés. A `t` megválasztása ezen a
  mintán 0,3 és 0,7 között **nem megkülönböztethető**, ezért a **költség** döntött, nem a macro.
- A hibrid a **nyíl** oldalon 19,8% **irány-semleges** jelet jelent. Hogy ez a tanulónak
  elfogadható-e, az **termék-kérdés, nem mérési** — és az ADR 0556 D5 szerint saját tanulókon,
  megtartásra kell megmérni.
