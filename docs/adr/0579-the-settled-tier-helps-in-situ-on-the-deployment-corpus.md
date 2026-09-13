# ADR 0579 — A letisztult tier IN SITU a telepítési korpuszon +0,1236-ot ér, ha az asset mindkét levágáson tanult — és az orákulum-műszer pontossága most három ponton jellemezve

- **Státusz:** elfogadva (mérés; a két-tier ügy **hiányzó in-situ lábát** megadja a telepítési
  korpuszon, és az ADR 0571 D4 korlátját **pontosítja**; semmi nem kerül felkapcsolásra)
- **Dátum:** 2026-09-13
- **Kör:** E18-R46
- **Kapcsolódó:** ADR 0577 (az in-situ műszer), ADR 0572 D2 (az orákulum +0,1299, amit ez
  megerősít), ADR 0571 D4 (a korlát, amit ez pontosít), ADR 0574 (a f7..14 lábnyom),
  ADR 0573 D1 (miért nem asset-rangsor ez), ADR 0566 (az elnyomás mint pontozói vakság),
  `test/tooling/klangio_threshold_sweep_test.dart`

## Kontextus

Az ADR 0571 a letisztult tier in-situ értékét **GuitarSeten** mérte (+0,1679), az ADR 0572 a
telepítési korpuszon csak **orákulum**-ablakon (+0,1299 a settled asseten, −0,2455 a
szállítotton). Az ADR 0577 óta a telepítési korpusz in situ is mérhető. Ez a kör mindkét
assetet végigfuttatja **ugyanazon a foldon, ugyanazzal a műszerrel, ugyanazokon a kapukon**.

A fold a **4-es gitáros** mind a 27 felvétele (3721 annotált pengetés, 4430 SuperFlux onset,
9 pengetés frame-egybeolvadás miatt kizárva és kiírva). Ez a settled assetre
**játékos-diszjunkt**; a szállítottra **nem** (22/27-ét tanulta — ADR 0573 D1).

## Döntés

### D1 — Egy belső ellenőrzés, ami a többit olvashatóvá teszi

A `nincs kapu / margin off` sor **bitre ugyanaz** a két assetre:

```
  asset        onsetP   onsetR   megtartva
  szállított   0,6582   0,7837      4430
  settled      0,6582   0,7837      4430
```

Az onset-út tehát **asset-független** (SuperFlux, nem a CRNN), és minden további különbség
**utána** keletkezik. Ez nem dekoráció: ha ez a sor eltérne, a két asset tábláit nem lehetne
egymás ellen olvasni.

### D2 — A HIÁNYZÓ LÁB: a letisztult tier a telepítési korpuszon in situ +0,1236

A settled asset (ADR 0554, mindkét levágáson tanult), a **saját** 0,2929-es kapuján, a saját
tiszta foldján:

```
  tier                irány-macro    le       fel
  csak gyors            0,5389     0,4873   0,5905
  csak letisztult       0,6625     0,6847   0,6402     (+0,1236)
```

**Mindkét irány javul** — a le +0,1974-tel, a fel +0,0497-tel —, és `settledMissing = 0`: a
60 másodperces felvételeken minden onsetnek megépíthető a csonkítatlan ablaka.

Ez az, amit az ADR 0571 D5 és az ADR 0572 a két-tier döntés **valódi-audió** lábaként
hiányolt, és amit eddig csak orákulum-ablakon lehetett állítani — **most a telepítési
korpuszon, in situ, az app útján.**

### D3 — Ugyanaz a fold, ugyanaz a műszer, a SZÁLLÍTOTT asseten: −0,3628

```
  szállított asset, 0,850-es kapu      irány-macro    le       fel
  csak gyors                             0,9373     0,9522   0,9224
  csak letisztult                        0,5745     0,8058   0,3432     (−0,3628)
```

Ugyanaz a korpusz, ugyanaz a fold, ugyanaz a szerelvény, **ellentétes előjel** — és a
különbség az, hogy az asset tanult-e a csonkítatlan ablakon. Ez az ADR 0572 D3 állítása, most
**in situ a telepítési korpuszon**, és az ADR 0574 lokalizálta is, hogy hol: a f7..14 sávban,
a csonkítás teljes lábnyomában.

### D4 — Az orákulum-műszer pontossága most HÁROM ponton jellemezve

```
  eset                                             orákulum   in situ   |eltérés|
  settled asset, Klangio g4 (in-distribution)       +0,1299   +0,1236    0,0063
  szállított asset, GuitarSet held-out (ADR 0571)   +0,1919   +0,1679    0,0240
  szállított asset, Klangio, csonkítatlan (OOD)     −0,2455   −0,3355    0,0900
```

Az ADR 0571 D4 azt írta fel, hogy az orákulum-műszer **delta-kérdésekre** korroborált,
szintekre nem. Ez **áll**, és most pontosítható:

> **a delta akkor pontos (0,006–0,024), ha a bemenet az asset számára eloszláson BELÜL van;
> ha eloszláson kívül, csak az ELŐJEL marad.**

Ami konzisztens azzal, amit „eloszláson kívül" jelent: a magnitúdó ott nem jósolható.

A **szintek** a vártnál közelebb vannak, de szisztematikusan elválnak: a settled asset
gyors szintje orákulumon 0,5055, in situ **0,5389** (+0,033), a letisztult 0,6354 vs
**0,6625** (+0,027). In situ **magasabb** — kézenfekvő olvasat, hogy a detektor a könnyebb
onseteket találja meg, tehát az egyeztetett részhalmaz kedvezőbb —, de ezt **nem mértük**, és
nem is állítjuk (L681).

### D5 — Amit ez a két tábla NEM mond: nem asset-rangsor

A szállított 0,9373 és a settled 0,5250 ugyanezen a foldon **nem** összevetés: a szállított
asset a fold 3721 pengetéséből 2897-et (78%) a tanítókészletében tartott. Az in-situ műszer
ezt a szennyezett párt **reprodukálja** a Python orákulum 0,9490 / 0,5055-éhez képest
(0,9373 / 0,5250) — ami a **műszert** hitelesíti, nem a rangsort. Az ADR 0573 D6 táblája áll.

### D6 — És egy ár, amit a csere fizetne: a settled asset kapuja sokkal többet hallgattat el

```
  kapu         szállított onsetR   settled onsetR      szállított megtartva / settled
  0,850            0,7718             0,7157                 3950 / 3534
  0,293            0,7665             0,6533                 3835 / 3009
  0,124            0,7632             0,6095                 3783 / 2737
```

A settled asset irány-macrója **javul** a szorosabb kapun (0,5250 → 0,5550), de az
onset-megtartása **összeomlik** (0,7157 → 0,6095). Az ADR 0566 szerint egy elnyomott pengetés
olyan ütés, amit a ritmus-pontozó **soha nem lát** — a tanuló a motor hallgatásáért kap
levonást. Tehát a settled asset szorosabb kapun mért jobb iránya **fedezettel van
megvásárolva**, és egy szállítási döntésnek ezt a cserét együtt kell mérlegelnie, nem a
macrót egyedül.

Ez a szám egyúttal az ADR 0569 D2 orákulum-megfigyelését (a settled 0,824-et tart meg a
szállított 0,964-e ellen) **in situ megerősíti**.

## Következmények

- A két-tier döntés **valódi-audió** lába (AGENTS.md §9) most megvan **a telepítési
  korpuszon**, egy mindkét levágáson tanult assetre. Ami hátravan: **fixtúra + property**, az
  **utolsó-ütés** él-eset (ADR 0570 D4), a **CPU** (ADR 0565), és mindenekelőtt egy asset, ami
  **szállítható** — az asset-kérdés az ADR 0578 szerint nyitott.
- A söprés mostantól `KLANGIO_EXTRA_GATES`-szel bármely jelölt **saját** kapuján is mér, és a
  kanonikus sorok megmaradnak, tehát a közös-kapus összevetés nem veszik el.

## Amit NEM állítunk

- **Nincs on-device szám.** Host futás.
- **Egy fold, egy korpusz, egy gitáros.** A 4-es gitáros a repó saját r172 LOGO mérése
  szerint a **legnehezebb** a háromból (ADR 0573 D2), tehát ez a fold a settled assetre
  pesszimista.
- **Nem asset-rangsor** (D5).
- **A letisztult tier CPU-ja itt nincs mérve**: a söprés offline építi a második ablakot, nem
  a live határidőn.
- **A szint-eltérés okát nem mértük** (D4).
