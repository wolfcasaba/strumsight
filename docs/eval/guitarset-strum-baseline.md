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

---

# A mérce, ami eddig hiányzott — és a kétszintű döntés mért nyeresége (E18-R29)

```bash
GUITARSET_DIR=/path/to/guitarset python ml/experiment_cross_corpus.py
GUITARSET_DIR=/path/to/guitarset python ml/probe_direction_budget.py
```

## Előbb a mérce: a szállított irány-kimenet a TÖBBSÉGI ALAPVONAL ALATT van

```
  többségi alapvonal („mindig lefelé")
    GuitarSet teszt (n=530,  81% lefelé):  le 0,8935  fel 0,0000  macro 0,4468
    Klangio  teszt (n=3721, 62% lefelé):  le 0,7673  fel 0,0000  macro 0,3836

  SZÁLLÍTOTT 3 osztályos CRNN, végponttól végpontig, GuitarSeten:  macro 0,3876
```

Három kör beszélt „javulásról" anélkül, hogy ez a sor le lett volna írva. A repó máshol
használja ezt a fegyelmet — a GOV-06 az akkord-pontosságot „67,069% a 18,832%-os többségi
alapvonal fölött" formában rögzítette —, az irány-mérésekből kimaradt.

**És egy metrika-csapda.** Egy orákulum, ami semmit nem tud az ütésről, csak azt, **melyik
felvételből** jött, és a take-ek felütés-aránya szerint rangsorol: **AUC 0,7386.**

> Ezen a korpuszon a **0,74 alatti AUC semmilyen irány-diszkriminációt nem bizonyít.**
> A **macro-F1** az olvasandó metrika.

Ez visszamenőleg érvénytelenít néhány AUC-ot a fenti szakaszokból (a szállított log-mel
0,6523-a és a 16 sávos 0,7484-e a nulla-információs szint körül vagy alatta van); a
macro-F1 számok érvényesek.

**Mellékhatásként megbukott a saját magyarázatom.** Az onset előtti jelet (AUC 0,7128)
„váltakozás-tippnek" nevezte a fenti szakasz. De az egymást követő ütések a GuitarSeten
**61,4%-ban ugyanolyan irányúak** (Klangión 45,4%) — **nincs erős váltakozás.** A valódi
mechanizmus rosszabb: **128 ms terem, gitár és akkord azonosítja a take-et**, és a take
osztály-aránya elvégzi a többit. A döntés (ne számítsuk be az onset előtti kontextust)
**változatlan, és jobban megalapozott.** A `D DU UDU`-ra hivatkozó érv viszont pontatlan
volt: az 60%-ban váltakozik, vagyis **többet**, mint a korpusz; a valódi érv az, hogy a
kontextus-prior **a korpusz repertoárjára** jellemző.

## A grid: három tanítókészlet × két határidő

A két határidő-blokk között **csak a levágás** változik. A szállított 15 frame **már
238 ms-ot elér** az onset után (a 70 ms-os levágás 168 ms-ot dob el belőle), tehát a
tensor-alak mindkét blokkban `(15, 128)`, a háló, a mag és a csoport szerinti korai
leállítás ugyanaz. **Nulla architektúra-költség.**

| kar | határidő | GuitarSet le/fel/**macro** | „fel" mond/valóság | Klangio le/fel/**macro** | „fel" mond/valóság |
|---|---|---|---|---|---|
| *alapvonal* | — | 0,8935 / 0,0000 / *0,4468* | — | 0,7673 / 0,0000 / *0,3836* | — |
| A csak Klangio | 70 ms | 0,3856 / 0,3248 / **0,3552** | 0,76 / 0,19 | 0,3426 / 0,4734 / **0,4080** | 0,73 / 0,38 |
| A csak Klangio | 238 ms | 0,3352 / 0,3477 / **0,3415** | 0,82 / 0,19 | 0,6442 / 0,5984 / **0,6213** | 0,56 / 0,38 |
| B Klangio+GuitarSet | 70 ms | 0,5835 / 0,4199 / **0,5017** | 0,64 / 0,19 | 0,6169 / 0,5788 / **0,5979** | 0,58 / 0,38 |
| **B Klangio+GuitarSet** | **238 ms** | 0,8284 / 0,4609 / **0,6446** | 0,29 / 0,19 | 0,6488 / 0,6154 / **0,6321** | 0,58 / 0,38 |
| C csak GuitarSet | 70 ms | 0,8772 / 0,1364 / **0,5068** | **0,06** / 0,19 | 0,7649 / 0,0014 / **0,3832** | **0,00** / 0,38 |
| C csak GuitarSet | 238 ms | 0,8625 / 0,4402 / **0,6514** | 0,20 / 0,19 | 0,7496 / 0,3554 / **0,5525** | 0,18 / 0,38 |

### A két emelő nem helyettesíti egymást

- **Plusz hang egyedül** (A kar): a *saját* doménben nagyot hoz — Klangio 0,4080 →
  **0,6213** (+0,2133) —, de **átvinni nem tud**: GuitarSet 0,3552 → 0,3415, vagyis
  **semmi**, és mindkettő az alapvonal **alatt**.
- **Második korpusz egyedül** (B @ 70 ms): átvisz (+0,1465 a GuitarSeten), de a
  hang-költségvetést asztalon hagyja.
- **Együtt** (B @ 238 ms): **0,6446 / 0,6321**, mindkettő jóval az alapvonala fölött.

*A „több hang" javítja a modellt azon, amit már ismer; a „több korpusz" teszi átvihetővé.*

### A kontroll-kar megint dolgozott

`C @ 238 ms` a GuitarSeten **0,6514**, hajszálnyival B felett — de a Klangión **0,5525** B
0,6321-ével szemben, és 70 ms-nál **teljesen összeomlik** („fel"-nek mond 0,00). A Klangio
tehát **nem holt súly**, és a választás B. Megint: **macro-F1 egyedül C-t hozta volna ki
győztesnek** 70 ms-nál.

### Az Alpha kapu nincs meg, és nem kerekítjük fel

Ch14 §7.2: **0,80**. A választott konfiguráció **0,6446**. A lineáris padló 238 ms-on
0,7326, tehát a CRNN **0,088**-cal van alatta — **ugyanannyival, mint 70 ms-nál** (0,5017
vs 0,5885). Vagyis a plusz hangot **ugyanolyan hatékonysággal** váltja pontosságra: a
nyereség valódi képesség, nem műtermék, de a maradék rés is ugyanott van.

## Ami ebből következik

A kétszintű döntés (ADR 0551 D4) **megérte** és megépül: ideiglenes válasz 70 ms-nál az
élő nyílhoz, letisztult ~250 ms-nál a **ritmus-pontozáshoz**, aminek nincs latencia-igénye
— és ahol a hamis válasz fáj (ADR 0549 D2). Bekötő kör, AGENTS.md §9 alatt, a 3 osztályos
asset újratanításával; a jelenlegi kísérletek szándékosan **2 osztályosak**, mert a
no-strum fej külön képesség saját kalibrált kapuval, és összekeverve nem lehetne megmondani,
melyik változás mozdította melyik számot.

---

# A maradék rés szétszedve: ADAT, nem modell és nem jellemző (E18-R30)

```bash
GUITARSET_DIR=/path/to/guitarset python ml/probe_direction_representation.py
```

A „0,088-as rés" két különböző dolgot kevert össze: a 0,7326-os padló **16 geometriai
amplitúdó-sávon** volt mérve, a CRNN 0,6446-ja **128 log-melen**. Külön mérve:

## 1. A modell-oldal: nincs rés

238 ms-on, ugyanazon az osztáson, **a CRNN saját bemenetén**:

| | le | fel | macro | 95% CI |
|---|---|---|---|---|
| lineáris padló, **szállított 128 log-mel** | 0,8692 | 0,4510 | **0,6601** | [0,6088, 0,7108] |
| 32 sávra poolozva | 0,8717 | 0,5046 | 0,6882 | [0,6386, 0,7357] |
| 16 sávra poolozva | 0,9035 | 0,5251 | 0,7143 | [0,6617, 0,7624] |
| 8 sávra poolozva | 0,9062 | 0,5257 | 0,7160 | [0,6656, 0,7666] |
| **betanított CRNN** | 0,8284 | 0,4609 | **0,6446** | — |

**0,0155 a rés** — a hibahatáron jóval belül. A CRNN **eléri a saját bemenetének lineáris
plafonját.** Több epoch, paraméter vagy regularizáció nincs hova dolgozzon; a zsugorítás
pedig összeomlaszt (ADR 0551 D5). **A modell-oldal lezárva.**

## 2. A „szélesebb sáv jobb" NEM replikált — és ez majdnem egy kört vett meg

A fenti táblázat monoton (128 → 8: 0,6601 → 0,7160), és jó magyarázata is volt. **18 jelölt
fold** (minden játékos sorra kiemelve × a darab-osztás három rotációja, mindig mindkét
tengelyen diszjunktul; 14 használható):

```
  szállított 128 log-mel     0,6715 ± 0,0828   [0,5552, 0,7845]
  32 sávra poolozva          0,7090 ± 0,0802
  16 sávra poolozva          0,6731 ± 0,0897
   8 sávra poolozva          0,6931 ± 0,1063
  16 geometriai amplitúdó    0,7270 ± 0,0821   [0,5993, 0,8648]   (13 fold)
```

**Nem monoton** (16 sáv rosszabb, mint 32), és minden érték benne van minden másik
szórásában. Az egy osztáson látott rendezettség **műtermék** volt — és ha nem
keresztvalidálom, `ml/features.py` + `crnn_frontend.dart` cserét javasoltam volna az r134-es
paritás-fegyelem alatt, **nulla nyereségért.**

## 3. A reprezentáció PLAFON, nem padló

Gradient boosting ugyanazokon a foldokon, ugyanazokon a jellemzőkön:

```
  szállított 128 log-mel, boosted     0,6492 ± 0,1277   (lineáris: 0,6715)
  16 sávra poolozva, boosted          0,6490 ± 0,1142   (lineáris: 0,6731)
  16 geometriai amplitúdó, boosted    0,6822 ± 0,1193   (lineáris: 0,7270)
```

**Minden reprezentáción rosszabb.** Egy erősebb olvasó **kevesebbet** nyer ki — túlilleszkedik.
Nincs kiaknázatlan nemlineáris szerkezet: a **~0,73 plafon.**

## 4. A geometriai reprezentáció előnye NEM bizonyított

Párosítva (ugyanazok a foldok, ugyanazok a söprések), 13 fold:

```
  fold              log-mel   geometriai    diff
  00 × Funk1         0,6754     0,6115     −0,0639
  00 × Funk2         0,6144     0,5993     −0,0151
  00 × Funk3         0,6298     0,6387     +0,0089
  01 × Funk1         0,7806     0,7727     −0,0079
  01 × Funk2         0,7845     0,8512     +0,0667
  01 × Funk3         0,7843     0,7388     −0,0455
  02 × Funk3         0,5904     0,7491     +0,1587
  03 × Funk3         0,5843     0,6887     +0,1044
  04 × Funk1         0,7383     0,8194     +0,0811
  04 × Funk2         0,5855     0,6758     +0,0903
  04 × Funk3         0,6828     0,7324     +0,0495
  05 × Funk2         0,6189     0,7088     +0,0899
  05 × Funk3         0,5552     0,8648     +0,3096

  átlag +0,0636   sd 0,0981   SE 0,0272
  95% CI (normális)  [+0,0103, +0,1170]   ← nullát KIZÁR
  előjel-teszt       p = 0,2668           ← NEM utasít el
```

A két teszt **ellentmond**, és ez az eredmény. A CI-t a **farok viszi**: egy fold +0,3096,
miközben **4 fold negatív**. Vagyis a **normalitás-feltevés** a hibás, nem az
eloszlásfüggetlen teszt. Ez nem elég a szállított jellemző-kinyerő és a Dart-párja
átírásához.

## Ami ebből következik

| | macro-F1 |
|---|---|
| többségi alapvonal | 0,4468 |
| szállított 3 osztályos CRNN (ma, végponttól) | 0,3876 |
| **betanított CRNN, Klangio+GuitarSet, 238 ms** | **0,6446** |
| a reprezentáció **plafonja** a foldokon | ~0,73 |
| Ch14 §7.2 **Alpha kapu** | **0,80** |

**A maradék rés ADAT.** Nem finomítás: a modell a plafonján van, a jellemzők plafonja 0,73,
és erősebb modell rosszabb. A korpusz-diverzitás viszont az **egyetlen** emelő, ami eddig
mérhetően **átvitt** (ADR 0552 D2). Ma **kilenc gitáros** van összesen (Klangio 3 +
GuitarSet 6).

Ezért a következő **mérési** lépés gyűjtés, nem modellezés: (1) a user saját telefonos
felvétele — pontos címkék, célhardver, nincs licenc-kérdés, és egyszerre lezárja az L660
nyitott tételét; (2) további iránycímkés vagy hexafonikus korpuszok.

## 5. És az egy-osztásos mérés ÉHEZTETI a tanítást: a 0,6446 alsó korlát

Megvizsgáltam, hogy a GuitarSet **keresztezett** kombinációi (1471 söprés a 3056-ból)
hozzáadhatók-e a tanításhoz. **Nem:**

```
  keresztezett söprés összesen        1471
    amelyik JÁTÉKOST oszt a teszttel   886
    amelyik DARABOT  oszt a teszttel   585
    amelyik EGYIKET SEM                  0
```

Tehát a „használható, ha a teszt-fold diszjunkt" megfogalmazás igaz, de **üres** — nincs
ilyen söprés. Viszont kiderült valami fontosabb: az egy-osztásos terv egyszerre **három
játékost és nyolc darabot** tart vissza, a 18-fold CV pedig csak **egy játékost és egy
darabcsoportot**:

```
  18-fold CV tanító-méret:  min 1296   median 1635   max 2100
  az egy osztás:                                     1055
```

Vagyis a **0,6446** azt írja le, amit a konfiguráció **1055 söprésből** tud — nem a
képességét. A tartalék-teljesítményt ezért **foldok fölött** kell jelenteni, nem egy
osztáson; a szállítható modell a teljes készleten tanul, a becslés a CV-ből jön.

A következő **építési** lépés változatlanul az ADR 0552 kétszintű bekötése (+0,1429 mérve,
architektúra-költség nélkül).

---

# Egy asset vagy kettő? — és az előző kör nyereség-száma két változást kevert (E18-R31)

```bash
GUITARSET_DIR=/path/to/guitarset python ml/experiment_deadline_augmentation.py
```

Az ADR 0552 „nulla architektúra-költség" megfogalmazása a **bemenetre** igaz (a 15 frame már
238 ms-ot elér, a tensor `(15, 128)` marad), a **súlyokra nem**: a két szint két különböző
levágáson tanított modell volt. Naivan tehát két asset, két `tryLoad`, két paritás-fixtúra,
és hívás-helyenkénti modellválasztás a Dart-oldalon. Harmadik lehetőség: **egy** modell,
ami **mindkét** levágáson tanul.

Három kar, mindegyik **mindkét** határidőn pontozva, mindkét tartalék korpuszon, a repó saját
`honest_eval.STD_SEEDS = [42, 1, 2]` magjaival:

| kar | GuitarSet @70 ms | GuitarSet @238 ms | Klangio @70 ms | Klangio @238 ms |
|---|---|---|---|---|
| *alapvonal* | *0,4468* | *0,4468* | *0,3836* | *0,3836* |
| A tanítva @70 ms | 0,4690 ±0,0603 | **0,4269 ±0,0063** ↓ | 0,4879 ±0,0854 | 0,5205 ±0,0248 |
| B tanítva @238 ms | 0,5865 ±0,0358 | **0,6954 ±0,0362** | **0,4795 ±0,0924** | 0,6593 ±0,0193 |
| **C tanítva MINDKETTŐN** | **0,5934 ±0,0127** | 0,6659 ±0,0172 | **0,5828 ±0,0385** | **0,6675 ±0,0195** |

„Fel"-nek mond / valóság a két kritikus cellában: **B @70 ms Klangión 0,08 / 0,38** (fel-F1
0,1912), **A @238 ms GuitarSeten 0,53 / 0,19**.

## 1. Mindkét kereszt-cella összeomlik, és három magon stabilan

- **A letisztult fej a nyílnál** (B @ 70 ms): a Klangión **0,08**-at mond felütésnek a valódi
  0,38 mellett — gyakorlatilag megszűnik felütést jelezni, **pont a nyíl helyén**.
- **A mai fej a pontozásnál** (A @ 238 ms): GuitarSeten **0,4269 ± 0,0063**, a **többségi
  alapvonal alatt**, és a szórás **parányi** — tehát tulajdonság, nem ingadozás. A mai modell
  a plusz hangtól **rosszabb** lesz, mert sosem tanulta meg használni.

Egy magon mindkettő elmagyarázható lett volna rossz inicializálásként.

## 2. C nyeri a 70 ms-os szintet — a saját specialistáját is megverve

GuitarSet 0,5934 vs A 0,4690; Klangio 0,5828 vs A 0,4879. És **C szórása a legkisebb**
(±0,0127 / ±0,0385 az A ±0,0603 / ±0,0854-éhez képest). A határidő-augmentáció tehát
**regularizál**, nem kompromisszum.

A 238 ms-os szinten B és C **döntetlen**: GuitarSet 0,6954 vs 0,6659 a ±0,036-os szóráson
belül, Klangión C a jobb. C @238 GuitarSeten a kalibráció is pontos: „fel"-nek mond
**0,19** a valódi 0,19 mellett.

→ **Egy asset megy mindkét szintre** (ADR 0554 D1): egy `.bin`, egy paritás-fixtúra, egy
`tryLoad`, és a két szint két **hívási idő**, nem két modell.

## 3. A „+0,1429" két változást kevert össze

Az ADR 0552 a nyereséget A @ 70 ms (0,5017) → B @ 238 ms (0,6446) úton számolta — vagyis
**egyszerre** mozdította a szintet és a tanítást. Ugyanazon a súlykészleten, azon, amit
szállítanánk:

```
  GuitarSet:  C @70 ms 0,5934  →  C @238 ms 0,6659   =  +0,0725
  Klangio:    C @70 ms 0,5828  →  C @238 ms 0,6675   =  +0,0847
```

**+0,07–0,08, nem +0,14.** A szórás ±0,017–0,020, tehát a nyereség valódi — de a korábbi
szám nem az volt, aminek látszott.

## 4. És az egy-magos számok MINDKÉT irányban tévedtek

```
  A @70 ms,  GuitarSet:  0,5017 (egy mag)  →  0,4690 ± 0,0603    optimista volt
  B @238 ms, GuitarSet:  0,6446 (egy mag)  →  0,6954 ± 0,0362    pesszimista volt
```

Nem „egy mag optimista" tehát, hanem **az irány sem kiszámítható** — nem lehet fejben
korrigálni, és nem lehet konzervatív becslésnek nevezni. A repónak **volt** erre konvenciója
(`honest_eval.STD_SEEDS`), és az előző kör nem használta.

## Ami ebből a sorrendre következik

**Asset előbb, sín utána** (ADR 0554 D3). A mai assettel a „letisztult" hívás a többségi
alapvonal alatt van, tehát a Dart-sín korai bekötése a **ritmus-pontozást rontaná el** — épp
azon az úton, ahol a hamis válasz levonás vagy hamis kredit (ADR 0549 D2). Egy sín, aminek a
mögötte lévő modellje rosszabb, **nem semleges infrastruktúra, hanem regresszió**.

---

# A kétszintű 3 osztályos asset, és a kapu, ami a felütéseket hallgattatta el (E18-R32)

```bash
GUITARSET_DIR=/path/to/guitarset python ml/train_live_3c_settled.py
```

Két korpusz (Klangio + GuitarSet), **mindkét levágáson** tanítva (ADR 0554 D1), 3 osztály,
saját kapu-kalibrációval. A szállított `strum_crnn_live_3c.bin` **nem változik** — az új
súlyok `strum_crnn_live_3c_settled.bin`-ben, a fixtúra
`crnn_live_3c_settled_parity.json`-ban.

## A kapu: az osztály-vak szabály a felütéseket vágta

```
  szint    korpusz     elnyomva: LE     FEL     arány    P(no-strum) medián LE / FEL
   70 ms   Klangio        0,165      0,209     1,27×      0,0051 / 0,0098
   70 ms   GuitarSet      0,138      0,225     1,63×      0,0046 / 0,0241
  238 ms   Klangio        0,114      0,154     1,35×      0,0014 / 0,0038
  238 ms   GuitarSet      0,035      0,098    2,80×      0,0003 / 0,0019

  osztályonkénti illesztett küszöb:   le 0,041166     fel 0,292900     (7×)
```

A `reggae-skank` lecke szinte csak felütés — egy azt gyakorló tanuló az ütéseinek
**tizedét** a motor csendje miatt veszítené el, levonásként. Ez az ADR 0549 D2 hazugsága,
osztály szerint elfordítva.

```
  kapu               küszöb      megtart  elutasít
  class_blind        0,124528     0,950    0,974     (ADR 0549 szabálya)
  class_conditional  0,292900     0,971    0,960     (szállított, ADR 0555)
```

| kapu | szint | korpusz | macro | fel-F1 | fel-pont. | fel-recall | elnyomva-fel |
|---|---|---|---|---|---|---|---|
| class_blind | 70 ms | Klangio | 0,4922 | 0,5137 | 0,4343 | 0,6285 | 0,209 |
| **class_conditional** | 70 ms | Klangio | **0,5055** | 0,5357 | 0,4371 | **0,6918** | **0,137** |
| class_blind | 70 ms | GuitarSet | 0,5117 | 0,2600 | 0,2653 | 0,2549 | 0,225 |
| **class_conditional** | 70 ms | GuitarSet | **0,5262** | 0,2780 | 0,2562 | **0,3039** | **0,127** |
| class_blind | 238 ms | Klangio | 0,6267 | 0,5754 | 0,5516 | 0,6014 | 0,154 |
| **class_conditional** | 238 ms | Klangio | **0,6363** | 0,5899 | 0,5472 | **0,6399** | **0,110** |
| class_blind | 238 ms | GuitarSet | 0,6000 | 0,3409 | 0,4054 | 0,2941 | 0,098 |
| **class_conditional** | 238 ms | GuitarSet | **0,6061** | 0,3516 | 0,4000 | **0,3137** | **0,078** |

**Mind a négy cellában jobb**, 1,4 pont hamis-onset elutasításért.

### Ez nem új ötlet, és ez a fontos

- Az osztály-vak szabály **tankönyvi Chow (1970)**; a `t = (C_r − C_c)/(C_e − C_c)`
  formulában **nincs osztály-index**, mert szimmetrikus költségeket tesz fel. A mért eltérés
  ennek **dokumentált** bukása.
- A javítás neve **Mondrian / címke-feltételes konformális predikció** (Vovk és mások 2003;
  Vovk–Gammerman–Shafer 2005) → **egzakt véges mintás osztályonkénti garancia**.
- Barber és mások (2021): folytonos feltételre lehetetlen, **véges partícióra elérhető** — a
  három osztály véges partíció.
- **Fumera–Roli–Giacinto (2000)** már bizonyította, hogy az osztályonkénti küszöbök
  **Pareto-dominálják** az egy-küszöbűt.

### A kötelező ellenőrzés, amit az irodalom írt elő

Jones és mások (NeurIPS 2020) és Cresswell és mások (ICLR 2025): a **megtartás**
kiegyenlítése nem egyenlíti ki a **megtartott halmaz** hibaarányát, és ronthat is. Megmérve:
a felütés megtartott **pontossága** −0,005…+0,003 (mozdulatlan), a **recall** +0,020…+0,063.
A visszaütés **nem történik meg**, de kicsiben látható — a nyereség a recallon van.

### Ami NYITVA marad

A megtartási kvantilis **eleve rossz keret**, ha a hamis csend és a hamis pozitív költsége
különbözik; akkor a küszöböt **költség-arányból** kell levezetni (Tortorella; Pietraszek
2005; Charoenphakdee és mások 2021). Az ADR 0549 D2 **megnevezte** mindkét költséget
prózában, aztán kvantilist választott. Külön kör (ADR 0555 D4), és a riportot érdemes
**precision/recall reject curve**-re váltani (Fischer & Wollstadt 2023).

## A 3 osztályos ár, és ami nem javult

```
  2 osztályos arm C (kapu nélkül):  GuitarSet 0,5934 @70 / 0,6659 @238 · Klangio 0,5828 / 0,6675
  3 osztályos + kapu (szállítható):  GuitarSet 0,5262 / 0,6061        · Klangio 0,5055 / 0,6363
```

A no-strum képesség mért ára tehát **0,03–0,07 macro** — az elnyomás 7,8–13,7%-a a valódi
ütéseknek, és ezeket hibának számolom, mert egy elnyomott ütés olyan ütés, amit a pontozó
**sosem lát**.

**És az őszinte szám:** a GuitarSeten a megtartott felütések **pontossága 0,40**, a
**recallja 0,31** — vagyis az ismeretlen játékosok felütéseinek kb. **harmadát** találja meg,
és amikor „fel"-t mond, 40%-ban igaza van. A lefelé ütés ezzel szemben 0,857 / 0,865. Ez az
ADR 0553 adat-diagnózisát erősíti: **a rés adat, nem modell és nem jellemző.**

## Az adat-irány, amit a kutatás talált

**Guitar-TECHS** ([Zenodo 14963133](https://zenodo.org/records/14963133),
[arXiv:2501.03720](https://arxiv.org/abs/2501.03720)) — **CC-BY-4.0**, 5h12m, **három profi
gitáros**, akik nem azonosak a meglévőkkel, **explicit alternáló akkord-pengetés** („a
legalsó fekvéstől indulva"), és **húronkénti MIDI** Fishman Triple Play pickupból, amiből az
irány **ugyanúgy levezethető, mint a GuitarSetnél**. Ez **9 → 12 játékos.** Az irányt nem a
szerzők címkézték: mi vezetnénk le, ugyanazzal a módszerrel.

Amit a keresés **kizárt**:

| készlet | ok |
|---|---|
| `KLANGIO-GST-MM-T` | az ISMIR-2022 előd-készlet, **ugyanazok a játékosok** |
| arXiv 2508.07973 | **maga a GST-MM-2025 papír**, nem külön korpusz |
| IDMT-SMT-Guitar | **CC BY-NC-ND** — a no-derivatives kizárja a tanítást |
| EGDB | **egy** gitáros; a kiadott audio mono DI, a hexafonikus csatornák megléte nem megerősített |
| EG-IPT | **egy** gitáros, csak izolált egyes hangok |
| GAPS | licenc-ellentmondás (Zenodo CC-BY vs. a projekt saját, nem továbbadható licence), klasszikus szólórepertoár |
| François Leduc | hozzáférés kérésre, egy gitáros |
| GIHME | a repó **üres placeholder** |
| Zenodo 6470236 (36 gitáros, EMG+mocap) | CC-BY és a legnagyobb játékos-készlet, de **a pengetés nem megerősített**, nincs hexafonikus csatorna |
