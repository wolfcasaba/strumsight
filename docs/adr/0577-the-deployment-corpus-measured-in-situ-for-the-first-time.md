# ADR 0577 — A telepítési korpusz IN SITU, először: irány-macro 0,9166, és a letisztult tier ott −0,3355-öt veszít

- **Státusz:** elfogadva (mérés; az ADR 0572 D1 orákulum-előjelét **in situ megerősíti**, és
  a „ne kapcsold fel a szállított assettel" utasítást orákulumról **in-situ** alapra teszi;
  semmi nem kerül felkapcsolásra)
- **Dátum:** 2026-09-13
- **Kör:** E18-R45
- **Kapcsolódó:** ADR 0576 (amiért ez egyáltalán megmérhető), ADR 0572 D1 (az orákulum
  −0,2455, amit ez megerősít), ADR 0571 D4 (az orákulum-műszer korlátja — itt **igazolva**),
  ADR 0573 (miért same-player szám ez), ADR 0549 (a kapu, amit ez először mér a telepítési
  korpuszon), ADR 0550, `test/tooling/klangio_threshold_sweep_test.dart`,
  `test/support/live_sweep_harness.dart`

## Kontextus

Az arc minden in-situ száma eddig **GuitarSeten** készült — stúdió mikrofon-tömb —, a
telepítési korpuszon (Klangio, telefon-mikrofon) pedig csak **orákulum**-ablakos számok
voltak, mert azt hittem, a korpusz nincs a gépen (ADR 0576: volt). Most mindkettő in situ
mérhető, **ugyanazzal a műszerrel**: a söprést hajtó gépezet a
`test/support/live_sweep_harness.dart`-ból jön, amit a GuitarSet-söprés is használ — és ami
a kiszervezés után a GuitarSet-táblát **bitre** ugyanúgy reprodukálta (ADR 0571 D2 minden
sora, jegyre).

## Döntés

### D1 — Mérve: 82 felvétel, 11767 annotált pengetés, a szállított úton

`assets/ml/strum_crnn_live_3c.bin`, 13142 SuperFlux onset, 18 pengetés frame-egybeolvadás
miatt kizárva és kiírva:

```
  kapu      margin   onsetP  onsetR  onsetF1   irány-macro   le      fel     megtartva
  0,850 *   on       0,7264  0,7021  0,7141    0,9166        0,9398  0,8934  11374
  0,650     on       0,7316  0,7008  0,7159    0,9174        0,9404  0,8945  11271
  0,439     on       0,7357  0,6994  0,7171    0,9177        0,9406  0,8947  11186
  nincs     on       0,6380  0,7078  0,6711    0,9144        0,9380  0,8908  13055
  (* amit a produkció ma tesz)
```

**Ez NEM generalizációs állítás.** A `split: all`, és a szállított asset ezeknek a
felvételeknek a ~80%-án **tanult** (ADR 0573 D1: a splitje felvétel-diszjunkt, nem
játékos-diszjunkt). A 0,9166 tehát **same-player, nagyrészt tanított** szám. Amit viszont
**megad**: mit tesz az app telepítési feltételű audión, azon az úton, amit futtat — onset
detektálás, streamelt ablak, kapu, margó —, nem annotált onsetre épített orákulum-ablakon.

### D2 — A letisztult tier a telepítési korpuszon IN SITU −0,3355

Ugyanazok a megtartott ütések, az irányt a **csonkítatlan** ablak dönti, a létezést továbbra
is a gyors hívás (ADR 0559 D2):

```
  kapu      irány-macro(gyors)   irány-macro(letisztult)   delta     le       fel
  0,850 *        0,9166                 0,5811            −0,3355   0,8193   0,3429
  0,439          0,9177                 0,5809            −0,3367   0,8196   0,3422
  nincs          0,9144                 0,5815            −0,3329   0,8187   0,3442
```

A **felütés** omlik össze: 0,8934 → 0,3429. És `settledMissing = 0` — a 60 másodperces
felvételeken minden onsetnek megépíthető volt a letisztult ablaka, szemben a GuitarSet
take-végi 1 kizárásával.

**Az ADR 0572 D1 orákulumon −0,2455-öt mért ugyanerre.** Ez in situ **−0,3355**: ugyanaz az
előjel, nagyobb magnitúdó. Tehát

- az **ADR 0571 D4 korlátja igazolva**: az orákulum-műszer a **delta előjelére** korroborált,
  a **szintjére** nem — itt 0,09-cel tévedett a magnitúdóban, a helyes irányban;
- és a „**ne kapcsold fel a letisztult tiert a szállított assettel**" utasítás mostantól
  **in-situ, telepítési korpuszú** számon áll, nem orákulumon. Ez a legerősebb formája, amit
  eddig kapott.

### D3 — Az onset-megtartás 0,70 egy ISMERT szám újramérése, nem regresszió — és a kapu nem a felelős

Az onsetR 0,7021 első látásra ellentmond a `superflux_onset_detector.dart`-ban álló
„real recall **89,6%**"-nak. Nem mond ellent; **más mennyiség**:

```
  89,6 %   a NYERS SuperFlux detektor, ±0,12 s egyeztetési ablakkal, a 2013-as eval foldon
  0,7021   a TELJES pipeline által publikált ütések, ±50 ms (onsetToleranceMsPrimary),
           mind a 11767 annotált pengetésen
```

Kétszer szigorúbb tolerancia és egy későbbi fázis. És a ~70% **dokumentált**: a
`test/tools/onset_recall_probe_test.dart` első sora r164 óta ezt kérdezi — *„WHY does the
live analyzer match only **73 %** of labeled strums on real takes"*. A mostani 0,7021 ezt
**reprodukálja**, 2,4-szer szigorúbb toleranciával.

És egy dolgot ki is zár: **nem a kapu veszíti el őket.** A kapu teljes felengedése az
onset-megtartást 0,7021 → 0,7078-ra viszi, **+0,006**. A hiányzó ~30% tehát a kapu előtt
veszik el, nem ott.

### D4 — A kapu a telepítési korpuszon, in situ, először: +0,088 precizitás −0,006 megtartásért

```
  kapu      onsetP   onsetR
  nincs     0,6380   0,7078
  0,850     0,7264   0,7021      +0,0884 P  /  −0,0057 R
```

Ez az ADR 0549 fantom-elnyomása, **a telepítési korpuszon, végponttól végpontig**, először
megmérve. A csere kedvező, és a kapu-ladder monoton: szigorúbb kapu → jobb precizitás,
elhanyagolható megtartás-veszteség.

### D5 — És most először áll egymás mellett két IN-SITU korpusz, egy műszerrel

```
  szállított asset, 0,850-es kapu, margin on, IN SITU, ugyanaz a szerelvény
  korpusz                              irány-macro   le       fel
  Klangio   (telefon, ~80%-át tanulta)    0,9166    0,9398   0,8934
  GuitarSet (stúdió, sosem látta)         0,3872    0,5736   0,2007
```

A két szám különbsége **korpusz + tanítási kitettség** együtt, és szétválasztani ezen a két
sejten nem lehet (ADR 0573 D6). De a **felütés** kontrasztja — 0,8934 vs 0,2007 — ugyanaz a
lelet, amit az ADR 0572 D5 orákulumon írt fel: a modell **tud** felütést a saját korpuszán,
amit nem tud, az **átvinni**. Most in situ, mindkét oldalon.

## Következmények

- A telepítési korpusz in-situ söprése megvan és megismételhető:
  `flutter test test/tooling/klangio_threshold_sweep_test.dart`, `KLANGIO_SPLIT=guitarist4`
  és `STRUM_3C_ASSET=…` kapcsolókkal.
- Egy jövőbeli asset-jelölt mostantól **mindkét** korpuszon in situ mérhető, **egy**
  műszerrel — ez az, amit az ADR 0569 D4 kért és amit mérhetetlenül fogalmazott meg.
- A `settledTier` marad **false**.

## Amit NEM állítunk

- **A 0,9166 nem új-játékos szám**, és nem is lehet az: a szállított asset splitje nem tud
  ilyet előállítani (ADR 0573 D1). Aki ezt a számot „az app pontossága" gyanánt idézi,
  same-player számot idéz.
- **Nincs on-device szám.** Host futás, 28 perc wall-time 82 percnyi audióra.
- **A hiányzó ~30% onsetet nem lokalizáltuk.** A kapu kizárva (D3); a detektor refraktorja,
  a gyors pengetés flux-padlója, a label-stílus és a publikálási logika nyitva van. Az
  `onset_recall_probe_test.dart` pont ezeket a hipotéziseket sorolja fel r164 óta.
- **Nem mértük a késés-eloszlást** ezen a korpuszon. A GuitarSet-söprésben van ilyen oszlop,
  a Klangio-söprésben szándékosan nincs — egy oszlop, amit senki nem olvas, már került
  ebbe az arcba egyszer (ADR 0568). Amint egy kérdés kéri, portolható.
- **Egy asset.** A settled asset in-situ Klangio száma ebben a körben nincs megmérve.
