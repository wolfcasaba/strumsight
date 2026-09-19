# ADR 0571 — A letisztult tier IN SITU +0,168 macrót ér a szállított assetn, és a nyereség teljes egésze a LEFELÉ ütés

- **Státusz:** elfogadva **mint GuitarSet-mérés**; az ebből olvasható **ajánlás**
  („mindent letisztítani" a szállított assettel) az **ADR 0572-ben megdőlt**: Klangion — a
  telepítési korpuszon — ugyanez **−0,2455**. A D3 felütés-állítása szintén ott **javítva**.
  Semmi nem kerül felkapcsolásra.
- **Dátum:** 2026-09-12
- **Kör:** E18-R43
- **Kapcsolódó:** ADR 0570 (az orákulum-ablakos előrejelzés, amit ez ellenőriz), ADR 0559 D2
  (a létezést a gyors tier dönti), ADR 0566 D3 (nincs nyíl, tehát nincs UX-ár), ADR 0565 (a
  forward költsége), ADR 0553 (a felütés adat-diagnózisa), ADR 0569 (miért a szállított asset
  a mérvadó), `test/tooling/guitarset_threshold_sweep_test.dart`

## Kontextus

Az ADR 0570 orákulum-ablakokon mérte, hogy a szállított assetn a letisztult tier **+0,1919**
macrót ér, ha **minden** ütésre alkalmazzuk — és kimondta, hogy ez **nem** in-situ szám: a
söprés egy onsetre **egy** osztályozást rögzített, a 70 ms-osat.

Ez a kör rögzíti a másodikat.

## Döntés

### D1 — Hogyan: a repó SAJÁT paritás-horgonya, onsetenként egy szeletre

A söprés recordere mostantól az **onset-frame**et is rögzíti minden híváshoz, és a pass után
minden megtartott onsetre kiszámolja a **csonkítatlan** ablakot a
`LiveCrnnFrontend.referenceWindow`-val — azzal a függvénnyel, amit a repó már pinel a
streamelt `windowAt`-hoz, tehát ez a dokumentált **referencia**, nem egy második
implementáció.

Két részlet teszi helyessé, nem körülbelül helyessé:

1. **Szelet, nem a felvétel.** A frontend ringje **egy másodperc**
   (`Float64List(sampleRate)`), tehát egy 30 másodperces take beadásakor csak az utolsó
   másodperc lenne címezhető, és minden korábbi onset **nullákat** olvasna. A szelet az
   onset-frame előtt 0,1 s-tól utána 0,6 s-ig tart — bőven az ablak saját terjedelmén túl,
   bőven a ringen belül.
2. **Frame-kezdet szemantika.** A `referenceWindow` maga adja hozzá az r144 attack-offsetet,
   tehát amit kér, az az onset **FRAME** kezdete — itt a szelethez képest kifejezve. A
   közzétett időből visszaszámolni **kétszer** alkalmazná a korrekciót.

A létezést továbbra is a **gyors** hívás dönti (ADR 0559 D2: a kapu a live határidő döntése,
és a letisztult tier nem revideálja) — így a mérés azt izolálja, amit a **második forward**
vásárol.

### D2 — Mérve, in situ, a szállított assetn: +0,1679 macro

12 held-out fájl (ismeretlen játékos ÉS darab), 1772 SuperFlux onset, a szállított
0,850-es kapu `margin on` — pontosan amit a produkció tesz:

```
  irány-F1              gyors     letisztult    változás
  macro                 0,3872      0,5551       +0,1679
  LE                    0,5736      0,9032       +0,3296
  FEL                   0,2007      0,2069       +0,0062
```

```
  kapu     dirMacro(gyors)  dirMacro(letisztult)  delta
  0,439        0,3753            0,5670          +0,1917
  0,650        0,3811            0,5599          +0,1788
  0,850 *      0,3872            0,5551          +0,1679
  nincs        0,4213            0,5380          +0,1168
```

Az 1772 onsetből **1**-nek nem volt megépíthető a letisztult ablaka (a take vége) — kizárva
és **kiírva**.

### D3 — A nyereség TELJES egésze a lefelé ütés, és ezt ki kell mondani

**LE 0,5736 → 0,9032. FEL 0,2007 → 0,2069.** A második forward a lefelé ütést
gyakorlatilag megoldja ezen a korpuszon, és a felütéshez **nem ad semmit**.

Ez az ADR 0553 adat-diagnózisát **megerősíti, nem váltja**: a felütés hiánya nem
ablak-hossz-kérdés.

> **JAVÍTVA (ADR 0572 D5).** Az eredeti mondat itt így folytatódott: „a felütéshez **adat**
> kell". Ez GuitarSet-alapú volt, és általánosként **téves**. Ugyanez a szállított asset a
> **Klangion** a felütést **0,7579**-cel hozza (gyors tier), GuitarSeten 0,2007-tel. A modell
> tehát **tud** felütést a saját korpuszán; amit nem tud, az **átvinni** — ez az **ADR 0550**
> diagnózisa (kereszt-korpusz transzfer), nem az ADR 0553-é.

Terméki következmény: egy `reggae-skank`-szerű, felütés-domináns lecke ebből **semmit** nem
kap. Egy lefelé-domináns kezdő lecke viszont majdnem mindent.

### D4 — A két műszer egyetért a DELTÁN, és nem a szintben

```
                      gyors    letisztult   delta
  orákulum (Python)   0,3340     0,5259     +0,1919
  in situ  (Dart)     0,3872     0,5551     +0,1679
```

A **szintek** 0,05-tel eltérnek (más ablak-építő, más onset-időpontok, más kapu-alkalmazás),
a **delta** 0,024-en belül egyezik. Ez az arc első olyan esete, ahol egy orákulum-ablakos
szám in-situ ellenőrzést kapott — és az eredmény egy **használható korlát**: az
orákulum-műszer **delta-kérdésekre** korroborált, **szint-kérdésekre** nem. Egy jövőbeli kör
ezért nyugodtan szűrhet orákulum-ablakon (gyors, nem kell korpusz-audió), de egy szállítási
állítás szintjét in situ kell megmérni.

### D5 — Semmi nem kerül felkapcsolásra ebben a körben

A pontozó irány-forrásának megváltoztatása **szállított viselkedés**, tehát az AGENTS.md §9
négy lábát kívánja. Ez a kör a **valódi-audió** lábat adja. Ami hátravan:

- **fixtúra + property**: a „letisztult irány minden ütésre" útra;
- **az él-eset**, amit az ADR 0570 D4 megnevezett: a kísérlet **utolsó** ütése — a lezárást az
  utolsó onset + 238 ms-ig ki kell várni, különben az az ütés bizonyíték nélkül marad (ez a
  mérésben „missing 1"-ként meg is jelent, a take végén);
- **a CPU**: levezetve az ADR 0565-ből, minden ütésre egy második forward a gyors tier
  **kétszerese** — ~44% egy magból 200 bpm tizenhatodon, ~8,8% 80 bpm nyolcadon.

És a `settledTier` ma is **false**; a `_settleBelowMargin` margó-routingja az ADR 0570 szerint
a szállított assetn **nem** a helyes szabály.

## Következmények

- A „mindent letisztítani" szabály mellett most **in-situ** szám áll, nem extrapoláció.
- Az irány-macro 0,5551 továbbra is a Chapter 14 §7.2 Alpha kapu (**0,80**) **alatt** van, és
  a rés most már majdnem teljesen a **felütés** (0,21).
- A söprés-eszköz egy futásból adja a gyors és a letisztult oszlopot is, tehát egy jövőbeli
  asset ugyanazzal a szerelvénnyel hasonlítható.

## Amit NEM állítunk

- **Nincs on-device szám.** 12 GuitarSet-fájl, host futás.
- **Nincs Klangio-oldal IN SITU** (~~a korpusz nincs a gépen — ADR 0569~~ — **a korpusz a
  gépen van, ADR 0576; az elnapolás alaptalan volt**). A +0,1679 a
  GuitarSetre vonatkozik. ~~a telepítési korpuszon a letisztult tier hatása nincs
  megmérve~~ — **az ADR 0572 orákulum-ablakon megmérte, és ott −0,2455**, tehát a fenti
  szám nem általánosítható a telepítési feltételre.
- **Nem magyarázzuk meg**, miért javít a csonkítatlan ablak ennyit a LE és semennyit a FEL
  osztályon. Kézenfekvő sejtés van rá, de sejtés (L681).
- **A down-F1 0,9032 nem hasonlítható** az arXiv 2508.07973 mikrofonos 0,8551-éhez: más
  korpusz, más protokoll. A 0,5736 → 0,9032 a **mi** held-out mérésünkön belüli változás.
- **n=12 fájl, egy szelet**, szórás-becslés nélkül.
