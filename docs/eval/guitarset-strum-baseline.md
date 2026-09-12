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
