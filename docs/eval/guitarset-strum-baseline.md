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
