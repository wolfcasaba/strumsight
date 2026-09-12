# GuitarSet baseline: az ELSŐ mért irány-szám (E18-R23, 2026-09-12)

Korpusz: [GuitarSet](https://zenodo.org/records/3371780), **CC-BY 4.0**, `audio_mono-mic`
+ `annotation`. **A felvételek nincsenek commitolva** — csak ez a mérés. Újrafuttatás:

```bash
GUITARSET_DIR=/path/to/guitarset flutter test \
  test/tooling/guitarset_strum_probe_test.dart
```

## Miért ez az első

A `docs/rounds/e14-r18-joint-streaming-prototype.md` kimondja: az értékelő korpusz
`.strums` fájljaiban **nincs irány ground truth**, ezért a szállított osztályozó
end-to-end irány-pontossága `not-measured` volt, és csak felső korlát létezett rá
(0,6739 — a saját onset-F1-je, mert `TP_direction ⊆ TP_onset`).

A GuitarSet ezt kézi címkézés nélkül zárja le: **hexafonikus pickupról** vették fel, így
az annotáció **húronkénti** hangkezdetet tartalmaz. Amilyen sorrendben a pengető a
húrokat éri, **az maga az irány** — nem helyettes mutató, hanem a dolog definíciója.

## A mérőeszköz validálása (ELŐBB, mint a motoré)

- **A `data_source` 0 valóban az alsó E**: annotált hangmagasságai MIDI 40-től (E2)
  indulnak, és 5-ig monoton emelkednek (64 = e4). A leképezést a hangmagasságokból
  olvastam ki, nem a dokumentációból vettem.
- **A mi osztályozónk ugyanazt a konvenciót használja**: `gap = highRise - lowRise`,
  pozitív = mély előbb = lefelé. Címke és előrejelzés ugyanarról beszél.
- Söprés-terjedés **medián 16–20 ms, p90 34–41 ms**; az összekapcsolási küszöb 45 ms.
- Az irány-címkék száma **stabil** 25–60 ms között (Rock 2360/845 → 2406/866), tehát a
  címke nem a küszöb műterméke.
- **Csak Rock és Funk comping.** A Bossa Nova **több „fel"-et** adott mint „le"-t
  (646/1073), az SS 5467-ből **3028 egyhangú** eseményt — mindkettő ujjal pengetett
  kíséret, ahol az „irány" nem tulajdonsága a játéknak.

## Az eredmény

72 fájl, 8089 annotált esemény, ebből **3035 tiszta söprés** (≥3 húr, sorrendben,
≥5 ms terjedés) és 1859 irány nélküli (egyhangú vagy döntetlen).

| | SZÁLLÍTOTT: CRNN 3 osztályos | visszaesés: heurisztika |
|---|---|---|
| onset precision | **0,914** | 0,703 |
| onset recall (minden esemény) | 0,428 | **0,891** |
| onset F1 | 0,583 | **0,786** |
| **valódi pengetések megtalálva** | 1807 / 3035 = **0,595** | 2896 / 3035 = **0,954** |
| irány F1 *le* | **0,562** | 0,203 |
| irány F1 *fel* | 0,277 | 0,387 |
| **irány macro-F1** | **0,4195** | 0,2953 |

### Amit ez mond

**1. Két külön igazság, és ez a legfontosabb.** A heurisztika a jobb **detektor**
(valódi pengetésekre 0,954 recall), a CRNN a jobb **irány-döntő** (macro 0,42 vs 0,30).
A szállított CRNN precíziója kiváló (0,914) — a tanult „nem-pengetés" elutasítás
dolgozik —, **de a valódi pengetések 40%-át is eldobja**. Ez nem a nem-pengetések
kiszűrése: a „csak pengetések" oszlop pont ezt a konfundot veszi ki.

**2. A heurisztika iránya majdnem invertált.** `up` FP 1863 = `down` FN 1863: a
ground truth 73% lefelé, a heurisztika 86%-ban felfelé mond. Ezért a `down` F1 0,203.
Ez nem „pontatlan", ez rossz irányba szisztematikus — és eddig **senki nem tudta**,
mert nem volt mihez mérni.

**3. Mindkettő messze a saját kapunk alatt.** Chapter 14 §7.2 Alpha: onset F1 ≥ 0,82,
irány macro-F1 ≥ 0,80. A szállított út **0,583 / 0,4195**.

**4. Konzisztencia-ellenőrzés, ami a szerelvényt hitelesíti.** Az
[arXiv 2508.07973](https://arxiv.org/html/2508.07973) SuperFlux alapvonala **0,7436**;
a mi heurisztika-águnk onset F1-je **0,786**. Más korpusz, de ugyanaz a detektor-család
— a két szám egymás mellett van, ami független jel arra, hogy a mérésem nem romlott el.
Ugyanez a cikk mikrofonon **any 92,75 / le 85,51 / fel 79,02**-t közöl, vagyis messze
felettünk.

## A következő lépés, amit ez a mérés megnevez

**Ötvözés a saját két komponensünk között, nem a cikkel.** Mivel
`TP_direction ⊆ TP_onset`, a CRNN iránya ma csak arra az **59,5%**-ra van alkalmazva,
amit ő maga detektál. Ha a heurisztika **95,4%**-os detektálásaira mondana irányt —
vagyis a CRNN `suppressed` jelzését NEM detektor-vétóként, hanem csak bizonytalanság-
jelzésként használnánk —, az irány-recall nagyot emelkedhet anélkül, hogy bármit
tanítanánk.

Ez egy **kompozíciós** kísérlet, nem modell-fejlesztés, és ez a legköltséghatékonyabb
következő mérés. Csak utána érdemes a cikk közös onset+irány+akkord CRNN-jéről
beszélni — és arra **nincs adatunk**: az ő készletük nincs publikálva, a GuitarSet
iránycímkéje pedig levezetett, amit tanításhoz előbb zaj-szempontból minősíteni kell.


---

# A küszöb-söprés: az ötvözés NYER, és nem a cikkel (E18-R24)

Újrafuttatás:

```bash
GUITARSET_DIR=/path/to/guitarset flutter test \
  test/tooling/guitarset_threshold_sweep_test.dart
```

## Korrekció a fenti alapvonalhoz: NEM egy kapu van, hanem kettő

A fenti szakasz a megtartás-veszteséget az elnyomó kapura írta. **Pontatlan volt.** A
szállított CRNN-úton két kapu áll egymás mögött:

1. `LiveCrnnStrumClassifier.noStrumThreshold` (0,43877) — a tanult „nem-pengetés"
   elutasítás, az osztályozón belül;
2. egy **margó-kapu** a `live_pipeline.dart`-ban: a `_strumSeq` csak akkor lép, ha
   `_isDirectionConfirmed(event)`, ami a `StrumPrediction.decision`-re hárít — és egy
   **valószínűség nélküli** eseményre (a heurisztika) **feltétel nélkül igazat** ad.

Ezért a heurisztika-ág **egyik kapuval sem** találkozik, a CRNN-ág **mindkettővel**. A
második kaput egy összefűzés-hossz állítás bukása találta meg (173 osztályozás → 172
kibocsátott pengetés), nem kódolvasás.

## Az eredmény

72 fájl, **10286 SuperFlux onset** (12 kizárva képkocka-egybeolvadás miatt).

| suppress | margó | megtartva | onset P | onset F1 | pengetés-recall | irány *le* | irány *fel* | **irány macro** |
|---|---|---|---|---|---|---|---|---|
| **0,439\*** | on | 3789 | 0,913 | 0,5828 | 0,596 | 0,5615 | 0,2769 | **0,4192** |
| 0,439 | off | 3824 | 0,913 | 0,5864 | 0,602 | 0,5628 | 0,2762 | 0,4195 |
| 0,650 | on | 4015 | 0,906 | 0,6013 | 0,620 | 0,5635 | 0,2835 | 0,4235 |
| 0,650 | off | 4052 | 0,906 | 0,6051 | 0,627 | 0,5648 | 0,2825 | 0,4237 |
| **0,850** | on | 4279 | 0,899 | 0,6223 | 0,649 | 0,5689 | 0,2934 | **0,4311** |
| 0,850 | off | 4318 | 0,899 | 0,6259 | 0,656 | 0,5700 | 0,2924 | 0,4312 |
| **none** | on | 10106 | 0,701 | 0,7792 | 0,941 | 0,5809 | 0,3196 | **0,4502** |
| **none** | off | 10286 | 0,701 | 0,7847 | **0,955** | 0,5809 | 0,3204 | **0,4506** |

`*` = amit a produkció ma tesz. A söprés a szállított kapun **pontosan reprodukálja** a
fenti, független alapvonalat (0,5828 / 0,596 / 0,4192 vs 0,5828 / 0,595 / 0,4195) — ez
hitelesíti a szerelvényt, nem az eredményt.

### 1. A margó-kapu nem a lényeg

`on` → `off` mindenhol **±0,0003** az irány macro-F1-en. Nem ez a mozgató, és nem
érdemes hozzányúlni.

### 2. Az elnyomó kapu a mozgató, és **minden** oszlopon rosszul áll erre az anyagra

0,439 → `none`: onset F1 **0,5828 → 0,7847**, pengetés-recall **0,596 → 0,955**, és az
irány macro-F1 **0,4192 → 0,4506**. A **pontosság** az egyetlen, ami fizet: 0,913 →
0,701.

Ez megoldja a fenti szakasz „két külön igazság" dilemmáját: nem két detektorról volt
szó. Az onsetek **mindig ugyanazok** (SuperFlux); a CRNN iránya pedig **jobb lesz**, ha
minden onsetre alkalmazzuk, nem csak arra az 59,6%-ra, amit ő maga megtart.

| | pengetés-recall | irány macro-F1 |
|---|---|---|
| szállított (CRNN + elnyomás) | 0,596 | 0,4192 |
| heurisztika (elnyomás nélkül) | 0,954 | 0,2953 |
| **CRNN irány, elnyomás nélkül** | **0,955** | **0,4506** |

A javasolt összetétel tehát **mindkét mai ágat dominálja** recallon és irányon is.

### 3. De a javaslat nem „vegyük ki a kaput"

A pontosság 0,701 azt jelenti, hogy a jelentett pengetések ~30%-a nem párosul annotált
eseménnyel. Tanulónak mutatott nyílnál ez **nem ingyenes**: a tananyag ritmus-pontozásában
egy hamis pengetés olyan slotot kreditál, amit a tanuló nem játszott — és a hiányzó
pengetés meg levonás. Mindkettő hazugság, csak ellentétes előjellel.

Ezért a mért, **biztonságos** lépés a **0,850**: minden oszlopon jobb a mainál
(onset F1 0,6223 vs 0,5828, recall 0,649 vs 0,596, irány 0,4311 vs 0,4192), és
**1,4 pont pontosságot** fizet érte. Ez a küszöb-érték egy szám a `ml/live_3c_threshold.json`-ban
— a döntés rollout-döntés, nem kód-kérdés.

### 4. Amit ez a cikkről mond

Semmit nem kellett tanítani, és az irány **0,4192 → 0,4506**-ra nőtt. Az
[arXiv 2508.07973](https://arxiv.org/html/2508.07973) mikrofonos számai (any 92,75 /
le 85,51 / fel 79,02) **így is messze felettünk** vannak. Tehát a kompozíció javít, de
nem zárja a rést — a cikk megközelítése továbbra is jobb, és továbbra is **adat nélkül**
vagyunk hozzá.


---

# A döntés és az ELLENŐRZÉSE: a kapu 0,85-re állítva (E18-R25, ADR 0549)

`noStrumThreshold` **0,4387717843055725 → 0,85**. Az illesztett érték
`fittedNoStrumThreshold` néven megmarad a provenienciájával; az eltérés szándékos és
őrteszttel pinelve (`live_crnn_3class_test.dart`).

**Ellenőrizve a független alapvonal-próbával, nem feltételezve:**

| | söprés jósolta | szállított úton mérve | előtte |
|---|---|---|---|
| onset precision | 0,899 | **0,900** | 0,913 |
| onset F1 | 0,6223 | **0,6224** | 0,5828 |
| pengetés-recall | 0,649 | **0,649** | 0,596 |
| irány macro-F1 | 0,4311 | **0,4313** | 0,4192 |

Két egymástól független szerelvény kerekítésen belül egyezik. És a **heurisztika-ág
változatlan** (0,786 / 0,954 / 0,2953) — vagyis a változás pontosan azt érintette, amit
érintenie kellett, és semmi mást.

**Amit ez nem ad meg.** Az irány 0,4313 továbbra is messze a Chapter 14 §7.2 Alpha kapu
alatt (0,80), és messze az arXiv 2508.07973 mikrofonos számai alatt. Ez a döntés
**javít, nem megoldás**.


---

# NEGATÍV eredmény: a le/fel döntési határ elmozgatása nem javít, csak a priort illeszti (E18-R26)

```bash
GUITARSET_DIR=/path/to/guitarset flutter test \
  test/tooling/guitarset_direction_boundary_test.dart
```

## A kérdés

A szállított úton (ADR 0549 után) az irány-hibák **egyetlen** torzításból jönnek:

```
down: TP 696  FP 135  FN 919   →  valódi le: 1615,  jelentett le:  831
up  : TP 219  FP 919  FN 135   →  valódi fel:  354, jelentett fel: 1138
```

A ground truth **82% lefelé**, a modell **58%-ban felfelé** mond: **919 valódi lefelé
ütést nevez felfelének.** A döntés pedig sima argmax — `final up = pUp > pDown`, vagyis
a határ fixen **0,5** egy kétosztályos, normalizált valószínűségen. Semmi nem illesztette;
ez az, amit az argmax jelent.

Kézenfekvő lenne eltolni. **De ugyanaz a csapda, amit az ADR 0549 épp leírt:** ha azért
tolom, mert ez a korpusz 82% lefelé, akkor korpusz-priorra illesztek — és a
felütés-domináns mintákon (a saját `reggae-skank` leckénk szinte csak felütés) rontanék.

Ezért **játékos szerinti osztás**: hangolás 00/01/02-n, kiértékelés 03/04/05-ön, se
előadó-, se felvétel-átfedés.

## A mérés

```
  tune játékosok 00/01/02: 72% le (907 eset)
  test játékosok 03/04/05: 90% le (1084 eset)

  P(up)>   tuneLe    tuneFel  tuneMacro | testLe    testFel  testMacro
  0,30     0,4980    0,3942     0,4461  |  0,5522   0,1870     0,3696
  0,40     0,5323    0,3965     0,4644  |  0,5692   0,1888     0,3790
  0,50*    0,5498    0,3896     0,4697  |  0,5848   0,1905     0,3876
  0,60     0,5661    0,3802     0,4731  |  0,6011   0,1877     0,3944
  0,70     0,5717    0,3683     0,4700  |  0,6230   0,1890     0,4060
  0,80     0,5877    0,3559     0,4718  |  0,6482   0,1838     0,4160
  0,90     0,6143    0,3383     0,4763  |  0,6837   0,1848     0,4343
  (* = a mai argmax)

  TUNE-on választva: P(up) > 0,90  (tune macro 0,4763)
  tartalék TESTen: macro 0,4343  vs  0,3876 a mai 0,50-nél  (n=1084)
```

## Amit ez mond, és miért NEM javítás

A tartalék halmazon a macro-F1 0,3876 → **0,4343** nő. Ez elsőre nyereségnek látszik. Nem
az, és három jel mondja meg:

**1. A hangoló görbe LAPOS.** 0,4697 (0,50) → 0,4763 (0,90): a teljes söprésen **+0,0066**.
A „legjobb" 0,90 hajszállal veri a 0,60-at (0,4731) és a 0,80-at (0,4718). Ez zaj-szint,
nem jel. *Egy lapos hangoló görbe azt jelenti, hogy nincs mit hangolni.*

**2. A tartalék görbe a PRIORT követi.** A test halmaz **90% lefelé** a tune 72%-ával
szemben. Minél inkább „lefelé" felé tolom a határt, annál jobb azon a felén, ahol több a
lefelé. Ez a definíció szerint prior-illesztés.

**3. A felütés F1 MEGSEM MOZDUL.** Tartalékon 0,1905 → 0,1848 a teljes söprésen, miközben
a lefelé F1 0,5848 → 0,6837-re nő. Tehát a nyereség **teljes egészében** abból jön, hogy
több dolgot nevez lefelének egy túlnyomóan lefelé korpuszon. Semmit nem tanult a
felütésekről.

**A diagnózis tehát nem a határ, hanem a modell.** Minden határnál a felütés F1 ≈ 0,19 a
tartalék játékosokon. A modell erre az anyagra **gyakorlatilag nem tudja azonosítani a
felütéseket**. Ez képesség-hiány, nem küszöb-hiba, és nem lehet egy skalárral elintézni.

**Mellék-fenntartás, ami önmagában is fontos:** a két fél **priorja nagyon eltér** (72% vs
90%), tehát a GuitarSet két fele nem felcserélhető. Ez a mérést nem rontja el — sőt, ez
az, ami a prior-illesztést *láthatóvá* tette —, de azt jelenti, hogy ezen a korpuszon
minden „átlagos" irány-szám erősen függ attól, kit válogatunk bele.

## Ami ebből következik

A küszöb-típusú (ingyenes) javítások **kimerültek**: az elnyomó kapu hozott valódit
(ADR 0549), a döntési határ nem hoz. Innen vagy **jobb modell** kell — amihez
iránycímkés tanítóadat, és az a blokkoló —, vagy **más jelforrás**.

---

# A defekt NEM az adat és NEM a felbontás: a modell nem nyeri ki azt, amit már megkap (E18-R27)

```bash
GUITARSET_DIR=/path/to/guitarset python ml/probe_direction_headroom.py
```

## Először is: a fenti szakasz záró állítása TÉVES, és itt visszavonom

A fenti „Ami ebből következik" azt mondta, hogy jobb modellhez *„iránycímkés tanítóadat
kell, és az a blokkoló"*. **Ez nem igaz, és a repó maga mondja meg, miért.**

A szállított 3 osztályos élő modell a **Klangio GST-MM-2025** készleten tanult
(`ml/klangio.py`, `ml/honest_eval.py:34`): ez **az arXiv 2508.07973 saját, publikus
adatkészlete**, Apache-2.0, 82 felvétel, `recording_<id>.strums` fájlokban
`time_s \t D|U \t akkord` címkékkel, és **telefon-mikrofonos** felvétellel — vagyis
pontosan a mi telepítési körülményünk. Iránycímkés, valódi tanítóadatunk tehát **van és
mindig is volt**; a modell ezen tanult.

Ez a javítás nem kozmetikai: a blokkolót rossz helyre tette, és emiatt a következő lépés
is rossz helyre mutatott.

## A kérdés, amit ez a kör feltett

Az ADR 0549 az elnyomó kaput állította (hozott valódit), az utána jövő kör a döntési
határt (nem hozott, csak a priort illesztette — L664). **Mindkettő egy skalárt hangolt.**
A most feltett kérdés más:

> Benne van-e az irány-információ abban, amit a modell **már most megkap** — és csak nem
> nyeri ki?

A mérőeszköz szándékosan a lehető legtompább: **sima logisztikus regresszió** 240
jellemzőn, amiket **a modell saját transzformációs geometriájával** veszek
(`ml/features.py`: N_FFT 2048 @ 16 kHz = **128 ms ablak**, HOP 160 = 10 ms, 15 frame).
Egy lineáris modell sokkal gyengébb egy CRNN-nél, tehát amit elér, az **alsó korlát** a
kinyerhetőre, nem felső.

Ground truth ugyanaz, mint a szállított út mérésénél: a hexafonikus pickup húronkénti
hangkezdetei, ugyanazzal a csoportosítással és `isClean` szűrővel, mint a
`guitarset_direction_boundary_test.dart` — így a számok **összevethetők**, nem csak
hasonlóak.

## 1. Az irány benne van — és a nagy időfelbontás ROSSZABB

Egyetlen változó mozog: a transzformáció felbontása. **Mindkét ág 240 jellemző**, ugyanaz
az osztályozó, ugyanazok a címkék.

| osztás | ág | le | fel | **macro** | AUC | train/test |
|---|---|---|---|---|---|---|
| **A** játékos-diszjunkt (darabok közösek) | `lo` = a modell geometriája | 0,9386 | 0,6355 | **0,7871** | 0,9225 | 1629/1409 |
| | `hi` = 5,8 ms ablak, 3,7 ms hop | 0,8631 | 0,4404 | 0,6518 | 0,7997 | |
| **B** darab-diszjunkt (játékosok közösek) | `lo` | 0,8902 | 0,7655 | **0,8279** | 0,9248 | 1928/1110 |
| | `hi` | 0,8219 | 0,6423 | 0,7321 | 0,8273 | |
| **C** MINDKETTŐ diszjunkt | `lo` | 0,9152 | 0,6294 | **0,7723** | 0,8928 | 1048/529 |
| | `hi` | 0,8335 | 0,4534 | 0,6435 | 0,7900 | |
| | **szállított CRNN** | **0,5848** | **0,1905** | **0,3876** | — | |

Két dolgot mond:

**(a) A hipotézisem megbukott.** Azzal indultam, hogy a 128 ms-os elemző ablak a baj:
a tiszta söprések medián hossza **22,2 ms**, a húrok közti késés **~8 ms**, és 40,7%-uk
**két 10 ms-os frame alatt** lezajlik — tehát „a söprés sorrendje elmosódik". A
kontrollált kísérlet ezt **megbuktatta**: a nagy felbontás *minden* osztáson rosszabb
(C-n 0,6435 vs 0,7723). Az irány tehát **nem elsősorban a söprés sorrendjéből** olvasható
ki a mikrofonon, hanem a **spektrális egyensúlyból** — amit a hosszabb ablak mér
stabilabban. (A söprés-statisztikák maradnak: igazak, csak nem azt jelentik, amit
hittem.)

**(b) A szállított modell nem nyeri ki azt, amit megkap.** Egy lineáris olvasó a modell
*saját* bemenetéből, **ismeretlen játékoson ÉS ismeretlen darabon**, macro **0,7723**-at
és fel-F1 **0,6294**-et ér el, szemben a szállított **0,3876 / 0,1905**-tel. A fel-F1
**háromszorosa**.

## 2. A kontrollok, mind a C osztáson

Négy egymást követő kör a mérőeszközön bukott el (L660–L664), úgyhogy minden szám
kontrollal jön:

```
  véletlenített címkék, 7 mag:  AUC 0,4096..0,5905  (átlag 0,4865)   [valódi: 0,8928]

  húrszám 3:  180 le /  60 fel   találat 0,8333
  húrszám 4:  189 le /  36 fel   találat 0,8800
  húrszám 5:   50 le /   5 fel   találat 0,9273
  húrszám 6:    8 le /   1 fel   találat 0,7778
  húrszám, ahol MINDKÉT osztályból >=20 van [3, 4]:
              le 0,9105  fel 0,6298  macro 0,7702  (n=465)
  húrszám MINT EGYETLEN jellemző:  AUC 0,4058
```

- **A 0,5776-os egymagú kontroll félrevezetett volna.** Egy mag nem kontroll: hét maggal
  a null-sáv 0,41–0,59, tehát az első húzás a sáv felső szélén volt, nem szivárgás.
- **Nem húrszámot mér.** A húrszám önmagában **AUC 0,4058** (rosszabb a véletlennél), és
  a 3–4 húros, mindkét osztályból jól képviselt részhalmazon a macro **változatlan**
  (0,7702 vs 0,7723). A comping felütései gyakran kevesebb húrt érnek — ezt külön ki
  kellett zárni, mert különben az „irány" csak a húrszám proxyja lett volna.
- **A darab-osztás nem luxus.** A GuitarSet **minden játékosa ugyanazt a 12 Rock/Funk
  darabot** játssza, tehát a játékos-diszjunkt osztás a harmóniamenetet **közösen
  hagyja**, és az osztályozó megjegyezhetné, hogy „ebben a darabban, ezen a ponton, ez
  egy le". Ezért van A, B és C — és a találat **mindhármon megáll**.

## 3. Mérés vagy tippelés? — és ez új megkötést szül

Egy 128 ms-os, az onset környékére centrált ablak **minden** frame-jében ott van az
attack, tehát frame-index szerinti ablációval **nem lehet** szétválasztani a „ezt az
ütést mérem" és a „az előzőből tippelek" eseteket. Ezért két ág van úgy kivágva, hogy az
egyik csak onset **előtti**, a másik csak onset **utáni** minta legyen:

| ág | le | fel | macro | AUC |
|---|---|---|---|---|
| `pre` — szigorúan az onset ELŐTT | 0,6984 | 0,4274 | 0,5629 | **0,7128** |
| `post` — szigorúan az onseten/utána | 0,8744 | 0,4545 | **0,6645** | 0,7507 |
| `both` | 0,8544 | 0,4872 | 0,6708 | 0,7703 |

**Az onset előtti hang egyedül AUC 0,7128-cal jelzi az irányt.** Ez nem mérés, hanem
**váltakozás-tipp**: a comping le-fel-le-fel, tehát aki tudja, mi volt az előző ütés,
az ingyen tippel. A mi mintáink viszont **nem váltakoznak** — a `D DU UDU`-ban két le
van egymás után, a `reggae-skank` szinte csak felütés —, tehát ez a tipp **nálunk
hazugság lenne**.

Ezért a szigorúan onset utáni szám az **őszinte**: macro **0,6645**, fel-F1 0,4545,
AUC 0,7507. Még így is **messze** a szállított 0,1905 fel-F1 felett.

## Amit ez a kör megállapít

1. **Nem az adat a blokkoló.** Valódi, iránycímkés, telefon-mikrofonos tanítóadatunk van
   (Klangio), és a modell azon tanult.
2. **Nem a bemenet felbontása a baj.** Mérve: a nagy felbontás rosszabb.
3. **Nem is a küszöb vagy a döntési határ.** Azok kimerültek (ADR 0549, L664).
4. **A GuitarSet levezetett iránycímkéi taníthatók.** Az ezeken illesztett modell
   ismeretlen játékosra **és** ismeretlen darabra általánosít (AUC 0,8928), miközben a
   véletlenített kontroll 0,41–0,59. Ez volt az a nyitott kérdés, hogy „a levezetett
   címke zaját tanítás előtt minősíteni kell" — **minősítve van.**
5. **A defekt átvitel (generalizáció):** a modell egy korpuszon tanult, és egy másikon
   nem viszi át — pontosan az ADR 0549 betegsége, de már **az egész modell szintjén, nem
   egy skaláron.**
6. **Új megkötés a pontozásra:** az irány-fejet **szigorúan onset utáni ablakon** kell
   értékelni, különben a szám részben váltakozás-tipp.

---

# JAVÍTÁS: a fenti 0,7723 ABLAK-IGAZÍTÁSI hibából jött — és a valódi korlát a 70 ms (E18-R28)

```bash
GUITARSET_DIR=/path/to/guitarset python ml/probe_direction_budget.py
GUITARSET_DIR=/path/to/guitarset python ml/experiment_cross_corpus.py
```

## Mit rontottam el

A fenti szakasz azt állította, hogy egy lineáris olvasó **a modell saját bemenetéből**
macro **0,7723**-at ér el. **Nem a modell bemenetéből.** A
`probe_direction_headroom.centred_starts` minden ablakot a frame-re **centrál**:

```
start = onset − PRE_FRAMES·HOP − N_FFT//2          →  onset − 94 ms
```

a szállított modellt tápláló `experiment_deadline.window_truncated` viszont a frame-nél
**kezdi**, és a határidő utáni farkat kinullázza:

```
start = (center − PRE_FRAMES)·HOP                 →  onset − 30 ms
seg[onset + 70 ms :] = 0
```

**64 ms extra felvezetés, és a 70 ms utáni hang.** És a hiba pont ott fájt a legjobban,
ahol a legkevésbé kellett volna: **ugyanez a szakasz** mérte ki, hogy a szigorúan onset
**előtti** hang AUC **0,7128**-cal jelzi az irányt a comping váltakozásából, és mondta ki,
hogy ez **tipp, nem mérés**, amit nálunk nem szabad beszámítani. A főszámom tehát azzal a
jellel pontozott, amit a saját szomszédos döntésem megtiltott.

Ugyanazok a címkék, ugyanaz az osztás, a **modell valódi** igazításán:

| | le | fel | macro | AUC |
|---|---|---|---|---|
| szállított log-mel 128, 70 ms levágás — **a CRNN bemenete** | 0,7857 | 0,3913 | **0,5885** | 0,6523 |
| 16 geometriai sáv, 70 ms levágás | 0,8817 | 0,3457 | 0,6137 | 0,7484 |
| betanított CRNN (Klangio+GuitarSet), 70 ms | 0,5835 | 0,4199 | **0,5017** | — |
| *~~próba-igazítás, levágás nélkül~~* | *~~0,9152~~* | *~~0,6294~~* | *~~0,7723~~* | *~~0,8928~~* |

A rés tehát **0,087**, nem 0,39. *A CRNN nem a domináns defekt* — a „nem nyeri ki, ami a
bemenetében van" állítás ennyiben túlzó volt.

## A valódi korlát: a 70 ms-os élő határidő

Ugyanaz a reprezentáció, ugyanaz a geometria, csak az onset után megtartott hang hossza
mozog. Két frame-szám, hogy a frame-**darabszám** ne legyen összekeverhető a hang
**hosszával**:

```
  frame  megtartott hang        le      fel    macro     AUC
    15    40 ms              0,8746  0,3584  0,6165  0,7479
    15    70 ms (SZÁLLÍTOTT) 0,8817  0,3457  0,6137  0,7484
    15   100 ms              0,8894  0,3506  0,6200  0,7501
    15   150 ms              0,8911  0,3356  0,6133  0,7826
    15   250 ms              0,9186  0,5466  0,7326  0,8369
    15   minden (238 ms)     0,9186  0,5466  0,7326  0,8369
    28    70 ms              0,8817  0,3457  0,6137  0,7485
    28   250 ms              0,9142  0,5217  0,7179  0,8279
    28   minden (368 ms)     0,9129  0,5185  0,7157  0,8228
```

**150 és 250 ms között ugrás: +0,12 macro, és a fel-F1 megduplázódik (0,3356 → 0,5466).**
Több **frame** nem hoz semmit (28 frame rosszabb, mint 15); több **hang** hoz.

Vagyis **az irány nem attack-tranziens jellemző, hanem a lecsengés jellemzője**: melyik
húrok zengenek tovább, és a pengető útja hogyan formálja őket. Ez utólag megmagyarázza
azt is, amit a korábbi szakasz mért, de nem értett: a nagy időfelbontás **azért** rosszabb
(nincs sorrend-jel, amit felbontani kéne), és a 128 ms-os ablak **azért** nem volt baj.

A termékre nézve ebből az következik, hogy a 70 ms-ot **nem kell mindenhol** fizetni: az
élő **nyílnak** kell azonnal megjelennie, a **ritmus-pontozásnak** nincs latencia-igénye.
A javítás alakja ezért **kétszintű irány-döntés** — ideiglenes válasz 70 ms-nál a nyílhoz,
letisztult ~250 ms-nál a pontozáshoz (ADR 0551 D4).

## Ami VÁLTOZATLANUL áll: a korpusz-diverzitás valódi emelő

Az igazítási hiba ezt **nem érinti** — az `ml/experiment_cross_corpus.py` végig a
szállított `window_truncated` geometriát használja. A szállított architektúra, három kar,
mindegyik mindkét tartalék korpuszon:

| kar | GuitarSet macro | Klangio macro | „fel"-nek mond / valóság |
|---|---|---|---|
| A csak Klangio | 0,3552 | 0,4080 | 0,76/0,19 · 0,73/0,38 |
| **B Klangio + GuitarSet** | **0,5017** | **0,5979** | 0,64/0,19 · 0,58/0,38 |
| C csak GuitarSet | 0,5068 | 0,3832 | 0,06/0,19 · **0,00**/0,38 |

**B mindkét korpuszon javít**, az *eredeti* doménben is (0,4080 → 0,5979). Hat új játékos
a három mellé valódi nyereség, és ezzel a GuitarSet levezetett címkéi már nem csak
lineáris illesztéssel, hanem a szállított architektúrával is **taníthatónak** bizonyultak.

**C egy csapda, amit a kontroll-kar kapott el.** A macro-ja (0,5068) *megveri* B-t — de a
Klangión **0,00**-t mond felütésnek: összeomlott a „mindig lefelé" válaszra, és a macro-ja
csak azért magas, mert a GuitarSet-teszt 81% lefelé. **Macro-F1 egyedül a rosszabb modellt
hozta volna ki győztesnek.** Ezért: minden irány-eredmény mellé **ki kell írni a jósolt
osztály-arányt a valódi mellé**. Ugyanaz a prior-illesztés, mint az L664-ben, új helyen —
és ezúttal egy olyan helyen, ahol a győztes kiválasztását rontotta volna el.

## Két hipotézis, ami megbukott

- **Kapacitás.** „364 ezer paraméter 106 effektív csoportra (82 Klangio-felvétel + 24
  GuitarSet-take), tehát túlilleszkedés." Mérve: a 10 ezer paraméteres és a 4 ezer
  paraméteres változat **összeomlott** — mindent „fel"-nek mond, le-F1 **0,0000**. A
  zsugorítás nem javít, hanem megszünteti.
- **Hangerő-invariancia.** „Egy erős lefelé ütés hangosabb, tehát globális normalizálás
  mellett a modell a hangerőre ülhet." Mérve: az ablakonkénti energia-normalizálás a
  CRNN-nek **rontott** (0,5017 → 0,4065) és a lineáris olvasónak is (0,5885 → 0,5763).
