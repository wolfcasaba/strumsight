# E99-R04 (GOV-06) — Valós-audio DSP baseline mérés

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-09, kód és korpusz olvasva:
  `main @ 66e545db`)
- **Típus:** **governance-kör** (nem SDD-fejezet) — a `HANDOFF.md` §6
  „Kötelező sorrend" **4. pontja**
- **Kör-azonosító:** `E99-R04`. Az `E99` a governance-körök fenntartott
  pszeudo-epic kódja (nem valódi epic) — a `tools/ai_router/brief.py:19`
  `(?i)(e\d{2}-r\d{2})` és a `tools/round-pipeline.sh:278`
  `^[A-Z][0-9]{2}-R[0-9]{2}$` mintája miatt a „GOV-06" alakú fájlnév kiesne a
  gépi kapukból. Emberi neve végig **GOV-06**.
- **Branch:** `codex/e99-r04-gov-06-real-audio-dsp-baseline`
- **Előfeltétel:** GOV-05c (`E99-R03`) merge-elve (`0e9d211c`)
- **Brief szerzője:** Claude (Opus 5) · **Implementáció:** Codex (Terra)
- **Előre kiosztott ADR:** [`0199`](../adr/0199-real-audio-dsp-baseline-measurement-contract.md)
  — **MÁR MEGÍRVA az orchesztrátor által, a `docs/adr/` a TILOS zónában van.**

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "tool/benchmarks/real_audio_dsp_baseline.dart",
  "test/tooling/real_audio_dsp_baseline_test.dart",
  "docs/eval/real-audio-dsp-baseline.md",
  "docs/rounds/e99-r04-gov-06-real-audio-dsp-baseline.md",
]
gate_tests = [
  "test/tooling",
  "test/features/analyze",
]
native_gate = false
```

> **Négy fájl, ebből három ÚJ** (`real_audio_dsp_baseline.dart`,
> `real_audio_dsp_baseline_test.dart`, `docs/eval/real-audio-dsp-baseline.md`
> — a `docs/eval/` könyvtár ma nem létezik, létrehozandó). Ezek **explicit
> engedélyezettek**; minden más új fájl scope-sértés.
>
> `native_gate = false`: a kör egyetlen natív bájtot sem érint, és nem
> változtat a szállított appon — a mérce a `full-gate.yml`.
>
> **A `gate_tests` az [L203](../LESSONS.md) szerint:** a harness a
> `ClipAnalyzer`-t és a wav-dekódert használja, ezért a
> `test/features/analyze` is bent van, nem csak a `test/tooling`.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Megmérni a **szállított** DSP pontosságát valódi gitárfelvételeken:
**akkord-pontosság, onset P/R/F1, BPM-hiba**.

**Miért most:** az Epic 6 harminc köre erre a DSP-re épít metrika-,
confidence- és insight-réteget. Ha az alap gyenge, azt most olcsó megtudni.

**Ez MÉRÉSI kör.** Nem hangol, nem tanít, nem javít. A DSP viselkedése
bitre változatlan marad (ADR 0199 Döntés 7).

## 2. Jelenlegi állapot (mérve 2026-08-09, `main @ 66e545db`)

### 2.1 A meglévő tudás

`HANDOFF.md` §3: a termék központi állítására **egyetlen** valós-audio szám
létezik — CRNN pengetés-irány 86,7% vs heurisztika 38,9% (r164 A/B).
**Akkord-pontosságra, onsetre és BPM-re valós felvételen nincs szám.**

`ml/chords/eval_real_sessions.py` első valós eredménye (2026-07-14, 7 session
/ 75 esemény): ML 36% vs DSP 56%, **librosa közelítő referenciával**. Ez a
szkript és az `ml/chords/eval_guitarset.py` **Python**, és a MODELLT méri —
nem a szállított Dart DSP-t. **Mindkettő a TILOS zónában van**, a kör nem
írja felül őket: más kérdést válaszolnak.

### 2.2 A korpusz — mérve

`ml/data/klangio/`: **82 `.wav`** telefonos gitárfelvétel + **82 `.strums`**
címkefájl + 2 `.csv` + `strums_list.txt`. Összesen **423 MB**.

A `.strums` soronként (mérve `recording_1001.strums`):

```
0.4511111111111114	D	C-major
1.6121088435374151	D	C-major
2.9124263038548754	D	C-major
```

`idő(mp) \t irány(D/U) \t akkord` — **összesen 11 767 esemény**.

**Címke-eloszlás (mind a 82 fájlon összesítve):**

| Címke | Esemény | Címke | Esemény |
|---|---|---|---|
| G-major | 2216 | B-major | 860 |
| C-major | 1982 | F#-major | 408 |
| D-major | 1804 | Bb-major | 284 |
| A-major | 1546 | C#-major | 138 |
| E-major | 1283 | **B-minor** | **124** |
| F-major | 1024 | **A-minor** | **98** |

**Csak 222 moll esemény a 11 767-ből (1,886%).** Irány: 7228 `D` / 4539 `U`
(a `D` aránya 61,426%).

**A többségi-osztály baseline: 2216/11767 = 18,832%.** Egy konstans
„G-major" jóslás ennyit érne el — minden aggregált akkord-számot EHHEZ kell
viszonyítani.

> ⚠ **A korpusz NINCS verziókövetve:** `git ls-files ml/data/klangio/` →
> **0 fájl**. Csak ezen a boxon létezik. Következmény: a CI nem tudja
> futtatni a mérést, tehát a kör kimenete elkötelezett riport, nem kapu
> (ADR 0199 Döntés 8). A verziókövetés **nevesített follow-up**, nem e kör
> hatóköre — de a riportnak ki kell mondania a korlátot.

### 2.3 A szállított DSP — offline futtatható

`lib/features/analyze/engine/clip_analyzer.dart:65`:

```dart
AnalyzeResult analyze(List<double> pcm, int sampleRate)
```

Szinkron, pure, determinisztikus. A 22–33. sori doc-comment szerint „Runs the
REAL Live DSP over a recorded PCM clip".

`AnalyzeResult` (`lib/features/analyze/model/analyze_result.dart`):
`bpm` (124. sor), `TimelineChord{label, startSec, endSec}` (17–26. sor),
`TimelineStrum{direction, timeSec, confidence}` (47–56. sor).

Wav-dekóder: `lib/features/analyze/engine/wav_decoder.dart`.
Precedens önálló Dart mérőeszközre: `tool/benchmarks/song_trainer_pitch_benchmark.dart`
(`void main(List<String> arguments)`, JSON-kimenet).

**A `docs/eval/` könyvtár ma NEM létezik** (`ls docs/eval/` → nincs ilyen).

## 3. Scope

**Benne:**

1. `tool/benchmarks/real_audio_dsp_baseline.dart` (ÚJ) — a harness:
   wav → PCM → **valódi `ClipAnalyzer`** → összevetés a `.strums`
   ground-truth-tal → riport.
2. `test/tooling/real_audio_dsp_baseline_test.dart` (ÚJ) — a harness
   **metrika-logikájának** unit-tesztje szintetikus, kézzel számolt
   bemeneteken (NEM a 423 MB korpuszon — a CI nem éri el).
3. `docs/eval/real-audio-dsp-baseline.md` (ÚJ) — a lefuttatott mérés
   riportja.
4. A brief §10 handoff.

**Kívül (ebben a körben TILOS):**

- **A `lib/` bármely fájlja.** A DSP viselkedése bitre változatlan (ADR 0199
  Döntés 7). Ha a harness futtatásához a szállított kódot kellene
  módosítani, az **lelet** → `stopped`, nem megkerülés.
- `ml/` bármely fájlja — a meglévő Python kiértékelők érintetlenek (§2.1).
- A korpusz (`ml/data/`) módosítása, mozgatása, git-be vétele, LFS-be
  tétele. A verziókövetés külön döntés.
- Küszöb, kapu vagy CI-integráció bevezetése (ADR 0199 Döntés 8).
- Bármilyen DSP-hangolás, modellcsere, paraméterállítás.
- `.github/`, `tools/`, `assets/`, `lib/l10n/`, `docs/adr/`.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `tool/benchmarks/real_audio_dsp_baseline.dart` | **ÚJ** — a harness |
| `test/tooling/real_audio_dsp_baseline_test.dart` | **ÚJ** — a metrika-logika unit-tesztje |
| `docs/eval/real-audio-dsp-baseline.md` | **ÚJ** (a könyvtárral együtt) — a riport |
| `docs/rounds/e99-r04-gov-06-real-audio-dsp-baseline.md` | §10 handoff |

**Tilos zóna:** `lib/` (MINDEN), `ml/` (MINDEN, a korpuszt is beleértve),
`tools/`, `tool/` a fenti egy ÚJ fájlon kívül, `.github/`, `assets/`,
`docs/adr/`, minden más `docs/` fájl.

## 5. Kötött architekturális döntések

Forrás: [ADR 0199](../adr/0199-real-audio-dsp-baseline-measurement-contract.md).

### 5.1 A valódi `ClipAnalyzer`-t hívd

Python-oldali újraimplementáció **nem elfogadható mérés**. A harness
importálja a `ClipAnalyzer`-t és a wav-dekódert a `lib/`-ből.

A `ClipAnalyzer` konstruktora több paramétert vesz (`chunkSize`,
`chromaMedianWindow`, `bassWeight`, `strumRefiner`). **A harness az
alapértelmezett konstrukciót használja** (`const ClipAnalyzer()`), mert a
kérdés az, amit a felhasználó kap. Ha a riport kedvéért paramétert
hangolnál, az a Döntés 7 megsértése.

### 5.2 Akkord-pontosság: ground-truth esemény-időpontokban mintavételezve

Minden `.strums` eseményre keresd meg, melyik jósolt `TimelineChord` fedi az
adott időpontot (`startSec <= t < endSec`), és annak `label`-jét hasonlítsd.

**Ha egy eseményt semelyik szegmens nem fed → HIBÁS találat**, nem kihagyott
minta. A „nincs predikció → ne számítson" könyvelés a mérce lazítása.

### 5.3 A címke-normalizálás kipinnelt

Ground-truth `<gyök>-major` / `<gyök>-minor` → (gyök, minőség). A jósolt
címke ugyanarra normalizálva.

- **Elfogadott:** enharmonikus gyök-azonosság (`Bb` ≡ `A#`, `C#` ≡ `Db`,
  `F#` ≡ `Gb`).
- **TILOS:** a minőség elhagyása; a jósolt bővített/sus/7 minőség
  „gyökre csonkolása" (pl. `Csus4` → `C-major`); részleges pontszám
  „közeli" akkordra; a ground-truth szótárának bővítése.

A ground-truth **12 címkéje a teljes megengedett céltér**; minden ezen kívüli
jósolt címke hibás találat.

### 5.4 Az onset-párosítás integer MIKROSZEKUNDUMBAN történik

**Ez nem stílus, hanem a mérce épsége.** Lebegőpontosan a „pontosan a
küszöbön" cella nem érhető el megbízhatóan — mérve:
`abs(1.050 - 1.000) == 0.050` → **`False`** (a tényleges különbség
`0.050000000000000044`). Ugyanez a hibaosztály állt a
[`docs/LESSONS.md`](../LESSONS.md) **L13** mögött.

Ezért: az időpontokat mikroszekundum `int`-re kerekítve hasonlítsd, és a
párosítás feltétele `deltaUs <= toleranceUs`.

Kétoldali, mohó párosítás: **egy ground-truth esemény legfeljebb egy jósolt
eseménnyel párosítható és fordítva.** Az újrafelhasználás inflálná a recallt.

### 5.5 Az aggregált szám önmagában nem kimenet

A riport **kötelezően** tartalmazza: osztályonkénti bontást mind a 12
címkére (támogatás, precision, recall), a **18,832%-os többségi-osztály
baseline**-t, és a **222 eseményes moll-részhalmaz** külön számát.
Ezek nélkül a riport nem fogadható el.

### 5.6 A BPM származtatott, és annak is kell látszania

Nincs BPM-metaadat a korpuszban. A ground-truth BPM a ground-truth
onsetek inter-onset intervallumaiból származtatandó, **kimondott
feltételezéssel**, hogy a pengetések egyenletes rácson ülnek.

A riport felvételenként közölje a rács-szabályosság mérőszámát (az IOI-k
szórása a mediánhoz viszonyítva). Szabálytalan rácsú felvétel kizárható a
BPM-aggregátumból — **de a kizárás tényét, darabszámát és kritériumát a
riportnak ki kell írnia.** Néma szűrés = a mérce lazítása.

### 5.7 Nyitott döntések — előre rögzített feloldással (ADR 0138)

```yaml
open_decisions:
  - id: OD-01
    question: Milyen onset-tűréshatárokon közöljük a P/R/F1-et?
    blocking: false
    resolution_policy: use_default
    default: >
      Három ponton: 25 ms (szigorú), 50 ms (MIR-szokvány), 100 ms
      (megengedő) — mikroszekundumban 25000 / 50000 / 100000. Mindhárom
      bekerül a riportba; EGYETLEN, kényelmesen választott pont nem
      elfogadható.

  - id: OD-02
    question: Mi történjen, ha egy .wav nem dekódolható vagy a ClipAnalyzer dob?
    blocking: false
    resolution_policy: use_default
    default: >
      A felvétel kimarad az aggregátumból, DE a riport nevesítve felsorolja
      (fájlnév + hibaüzenet) és közli a kimaradtak darabszámát. Néma
      kihagyás TILOS. Ha 82-ből több mint 8 (10%) hasal el, az önmagában
      lelet → jelentsd a §10-ben.

  - id: OD-03
    question: A `.csv` fájlokat (2 db) használjuk-e?
    blocking: false
    resolution_policy: use_default
    default: >
      NEM. A mérés a 82 `.strums` címkefájlra épül; a két `.csv` tartalma
      (szenzor-idősor) nem ground-truth ehhez a kérdéshez.

  - id: OD-04
    question: Mi legyen, ha a szállított DSP a baseline ALATT teljesít?
    blocking: false
    resolution_policy: use_default
    default: >
      A riport ezt KIMONDJA, kiemelten, és a §10 handoff is. Nem javítod,
      nem hangolod, nem szépíted (Döntés 7). Egy baseline alatti eredmény a
      kör ÉRVÉNYES kimenete — pontosan azért mérünk az Epic 6 előtt.

  - id: OD-05
    question: A harness unit-tesztje a valódi korpuszt használja?
    blocking: true
    resolution_policy: use_default
    default: >
      NEM, semmilyen formában. A CI nem éri el a 423 MB-ot (§2.2), tehát a
      korpuszra hivatkozó teszt a CI-ban elhasalna vagy némán kihagyódna.
      A teszt szintetikus, kézzel számolt bemeneteken méri a
      METRIKA-LOGIKÁT (párosítás, normalizálás, baseline-számítás).
```

## 6. Acceptance criteria

- [ ] **A1 — A harness a valódi `ClipAnalyzer`-t futtatja**, alapértelmezett
  konstrukcióval, és a `lib/` alatt egyetlen fájl sem módosul.
  Gépi mérce: `git diff --name-only origin/main...HEAD | grep '^lib/'`
  **üres**.

- [ ] **A2 — Onset-párosítás: alatta / rajta / fölötte cellahármas**, integer
  mikroszekundumban, 50 ms-os (50000 µs) tűréshatárnál. A cellákat
  `python3 -c`-vel számoltam ki (§5.4):

  | `deltaUs` | `deltaUs <= 50000` | Elvárt párosítás |
  |---|---|---|
  | **49999** | `True` | **párosít** |
  | **50000** | `True` | **párosít** (ez az egyetlen cella, ami a `<` és a `<=` közti különbséget méri) |
  | **50001** | `False` | **NEM párosít** |

  Mind a három cella kötelező. A középső elhagyása azt jelenti, hogy a
  szigorú `<` implementáció megkülönböztethetetlen a helyes `<=`-tól.

- [ ] **A3 — Nincs újrafelhasználás a párosításban.** Teszt-cella: két
  ground-truth esemény a tűréshatáron belül EGYETLEN jósolt eseményhez —
  az eredmény **1 találat és 1 hiányzás**, nem 2 találat. (Ez a cella
  fogja meg a recall-inflációt.)

- [ ] **A4 — Fedetlen esemény = hibás találat** (§5.2). Teszt-cella: egy
  ground-truth esemény olyan időpontban, amit semelyik jósolt szegmens nem
  fed → az akkord-pontosság nevezőjében BENNE van, számlálójában nincs.

- [ ] **A5 — A címke-normalizálás mátrixa.** Kötelező cellák:

  | Ground-truth | Jósolt | Elvárt |
  |---|---|---|
  | `C-major` | `C` | találat |
  | `Bb-major` | `A#` | **találat** (enharmonikus, §5.3) |
  | `A-minor` | `Am` | találat |
  | `C-major` | `Cm` | **hibás** (minőség nem hagyható el) |
  | `C-major` | `Csus4` | **hibás** (nem csonkolható gyökre) |
  | `A-minor` | `A` | **hibás** |

  A negyedik–hatodik cella az, ami a lazított normalizálást pirosra váltja.

- [ ] **A6 — A baseline-számítás mért értéke.** A harness a
  többségi-osztály baseline-t a ground-truth eloszlásából számolja, nem
  hard-kódolja. Teszt-cella szintetikus eloszláson kézzel számolt
  eredménnyel. A valódi korpuszon ennek **18,832%**-ot kell adnia
  (2216/11767) — ezt a riport tartalmazza.

- [ ] **A7 — A riport kötelező elemei megvannak** (§5.5, §5.6):
  osztályonkénti bontás mind a 12 címkére; a többségi-osztály baseline; a
  222 eseményes moll-részhalmaz külön száma; onset P/R/F1 mind a **három**
  tűréshatáron (OD-01); BPM-hiba a származtatottság kimondásával és a
  kizárt felvételek darabszámával (§5.6); a kimaradt/hibás felvételek
  nevesített listája (OD-02).

- [ ] **A8 — A riport reprodukálhatósági blokkja.** Tartalmazza a futtatott
  parancsot, a korpusz fájl-darabszámát (82 wav / 82 strums), az
  eseményszámot (11 767), a korpusz checksumját, és **kimondja**, hogy a
  korpusz nincs verziókövetve, ezért a mérés a boxon kívül ma nem
  reprodukálható (ADR 0199 Döntés 8).

- [ ] **A9 — Nincs küszöb, nincs kapu.** A harness nem ad nem-nulla
  kilépési kódot „rossz" eredményre, és a kör nem köt CI-lépést a
  számokhoz. Gépi mérce: a `.github/` alatt nulla változás (tilos zóna).

- [ ] **A10 — A unit-teszt nem hivatkozik a korpuszra** (OD-05). Gépi
  mérce: `grep -c "ml/data" test/tooling/real_audio_dsp_baseline_test.dart`
  → **0**.

- [ ] **A11 — A gate zöld**, a §7 szerinti egyetlen artefaktum-hívással.

> **Miért nincs több küszöb-hármas:** a kör egyetlen numerikus küszöbe az
> onset-tűréshatár, és arra az A2 megadja a teljes alatta/rajta/fölötte
> hármast. A többi acceptance logikai (fájl érintettsége, riport-elem
> megléte, párosítási viselkedés).

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A harness Python-reimplementációt hív a `ClipAnalyzer` helyett | **A1** (a review olvassa a diffet) + a riport nem hivatkozhat `ClipAnalyzer`-re |
| Lebegőpontos összehasonlítás integer µs helyett | **A2 középső cella** (`deltaUs == 50000`) |
| Szigorú `<` a `<=` helyett | **A2 középső cella** |
| A párosítás újrafelhasználja a jósolt eseményt | **A3** |
| A fedetlen esemény kimarad a nevezőből | **A4** |
| Lazított címke-normalizálás (minőség elhagyása / gyökre csonkolás) | **A5** 4–6. cella |
| A baseline hard-kódolva | **A6** (a szintetikus eloszlás más értéket ad) |
| Aggregált szám bontás/baseline nélkül | **A7** (reviewer eldobható próbája: a riport szekcióinak grepelése) |
| A hibás felvételek néma kihagyása | **A7** + OD-02 |
| A BPM-kizárás néma | **A7** (§5.6) |
| A unit-teszt a 423 MB korpuszt olvassa | **A10** |
| Küszöb/kapu bevezetése | **A9** |

**Valódi-sértés próba (kötelező, §10-ben dokumentálandó):** írd át
ideiglenesen a párosítás feltételét `deltaUs <= toleranceUs`-ról
`deltaUs < toleranceUs`-ra → az **A2 középső cellájának PIROSNAK kell
lennie** → állítsd vissza, és idézd a nyers kimenetet. Ha zöld marad, a
mérce nem mér → `stopped`.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling test/features/analyze
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (`docs/LESSONS.md` L09); a `flutter analyze`
és `flutter test` kézi láncolása OOM-ot ad ezen a gépen (L05).

**A tényleges mérés futtatása külön lépés**, és a kimenete a riport:

```bash
~/flutter/bin/dart run tool/benchmarks/real_audio_dsp_baseline.dart ml/data/klangio
```

Ennek a parancsnak a **TÉNYLEGES, csonkítatlan** kimenete (vagy a
generált riport) kerül a `docs/eval/real-audio-dsp-baseline.md`-be és a §10
handoffba. 82 felvétel elemzése eltarthat — ez várható, nem hiba.

## 8. Implementációs sorrend

1. **RED először:** `test/tooling/real_audio_dsp_baseline_test.dart` — az A2
   cellahármas, az A3 újrafelhasználás-cella, az A4 fedetlen-cella, az A5
   hatcellás normalizálási mátrix, az A6 baseline-cella. Szintetikus,
   kézzel számolt bemeneteken (OD-05).
2. A harness metrika-logikája, amíg a tesztek zöldek.
3. A wav-dekódolás + `ClipAnalyzer` bekötése.
4. Gate futtatása.
5. A tényleges mérés lefuttatása a 82 felvételen (§7).
6. `docs/eval/real-audio-dsp-baseline.md` megírása a TÉNYLEGES számokkal
   (A7, A8). Ne írj bele számot, amit nem futtattál.
7. A §6.1 valódi-sértés próba + visszaállítás.
8. Záró gate + §10 handoff + `done`.

## 9. Kockázatok

1. **A mérés a boxon kívül nem reprodukálható** (korpusz nincs a gitben).
   Kimondott korlát, nem elhallgatott (A8); a verziókövetés follow-up.
2. **A korpusz 98%-ban dúr** és egyetlen forrásból (telefon) származik. A
   számok erre a disztribúcióra érvényesek — a riportnak ezt is ki kell
   mondania.
3. **A BPM-metrika származtatott** (§5.6), tehát gyengébb bizonyíték.
4. **A ground-truth maga is zajos lehet** (telefonos felvétel, gépi címkézés
   nyomai). A riport ne állítsa abszolút igazságnak; a relatív bontás
   (melyik akkordon gyenge) robusztusabb következtetés, mint az abszolút szám.
5. **Az eredmény kellemetlen lehet.** Ez nem kockázat, hanem a kör célja —
   OD-04.

## 10. Implementation handoff — a Codex tölti ki

- `test/tooling/real_audio_dsp_baseline_test.dart`: szintetikus contract-teszt
  az inclusive 49 999 / 50 000 / 50 001 µs onset-cellákra, a predikció
  újrafelhasználásának tiltására, fedetlen chord-eseményre, a hatcellás
  címke-normalizálásra és a származtatott többségi baseline-ra. A teszt nem
  hivatkozik a korpuszra.
- `tool/benchmarks/real_audio_dsp_baseline.dart`: WAV → valódi, változatlan
  `const ClipAnalyzer()` → chord/onset/BPM metrika. Integer µs-párosítást,
  enharmonikus, de minőséget megőrző normalizálást, korpusz-SHA-256-ot és
  felvételenkénti IOI-szabályosságot ad ki. A jelentés a korpusz eredeti
  12 címkéjét őrzi meg (például `Bb-major`), az enharmonikus forma csak belső
  összevetés.
- `docs/eval/real-audio-dsp-baseline.md`: elkötelezett baseline-riport, benne
  a teljes, csonkítatlan 82-fájlos futási kimenet.

### Futtatott parancsok és tényleges eredmények

1. RED: `~/flutter/bin/flutter test test/tooling/real_audio_dsp_baseline_test.dart`
   a harness létrehozása előtt: compilation failure, hiányzó
   `tool/benchmarks/real_audio_dsp_baseline.dart` és metrika API-k. Ez a
   várt RED állapot volt.
2. A contract-teszt implementáció után: `00:00 +5: All tests passed!`.
3. `tools/round-gate.sh --result-json /tmp/e99-r04-final-round-gate.json test/tooling test/features/analyze`:
   format zöld, analyze zöld, `test/tooling` 52 zöld teszt,
   `test/features/analyze` és architecture-guard zöld. A gépi artefaktum:
   `{"command_exit_code": 0, "exit_code": 0, "failed_step": null, "outcome": "pass"}`.
4. Az előírt `~/flutter/bin/dart run tool/benchmarks/real_audio_dsp_baseline.dart ml/data/klangio`
   a sima Dart VM-en piros lett: `Dart library 'dart:ui' is not available on
   this platform.` A `ClipAnalyzer` tranzitívan Fluttert importál; production
   fájl módosítása nélkül a valódi API Flutter-tesztrunnerben futott:
   `~/flutter/bin/flutter test --dart-define=REAL_AUDIO_DSP_BASELINE_CORPUS=ml/data/klangio tool/benchmarks/real_audio_dsp_baseline.dart`.
   A teljes, csonkítatlan kimenet a
   [`docs/eval/real-audio-dsp-baseline.md`](../eval/real-audio-dsp-baseline.md)
   dokumentumban van.

### Valódi-sértés próba (§6.1)

Az onset-feltételt ideiglenesen `deltaUs <= toleranceUs`-ról
`deltaUs < toleranceUs`-ra rontottam. A nyers célteszt-kimenet releváns sora:

```
Expected: <1>
  Actual: <0>
deltaUs=50000
```

Ugyanez a futás az újrafelhasználás-cellát is pirosra váltotta, mert az a
teszt szintén a pontos küszöbértéket használja. A `<=` visszaállítása után a
teljes contract-teszt nyers lezárása: `00:00 +5: All tests passed!`.

### Mért eredmény és bizonyíték

- 82 / 82 felvétel feldolgozva, kihagyott vagy hibás felvétel: **0**.
- Korpusz: 82 WAV / 82 `.strums` / 11 767 esemény;
  SHA-256 `4880faceab27217640701f1b93db477606d5fb3aa2c4434574040b6590315827`.
- Akkord: 7 892 / 11 767 = **67,069%**; többségi baseline: G-major,
  2 216 / 11 767 = **18,832%**; moll-részhalmaz: 185 / 222 = **83,333%**.
- Onset P/R/F1 25 / 50 / 100 ms-nál rendre: 38,532 / 42,517 / **40,427%**;
  64,233 / 70,876 / **67,391%**; 81,208 / 89,607 / **85,201%**.
- Származtatott BPM-MAE: **45,067 BPM**. Nincs automatikus
  rács-szabálytalanság miatti kizárás (0); a felvételenkénti IOI-mérőszám a
  riport teljes nyers kimenetében szerepel.
- A1: `git diff --name-only origin/main...HEAD` tényleges kimenete nem
  tartalmaz `lib/` utat; a kör nem módosította a szállított DSP-t.
- Scope-audit: `scope_audit=ok`, base `dc201524`, 4 módosított útvonal,
  0 generated/ignored útvonal.

### Eltérés, nem futtatott ellenőrzések és follow-up

- Eltérés: a briefben adott sima `dart run` parancs nem futtat Fluttert
  igénylő `ClipAnalyzer`-t. A Flutter-tesztrunneres alternatíva ugyanazt a
  változatlan osztályt hívta; a korlát a riportban is dokumentált.
- A korpusz nincs verziókövetve, így a mérés nem CI-kapu és a boxon kívül nem
  reprodukálható. Follow-up: verziózott, licencelt corpus-provenance megoldás
  (LFS vagy külön adat-repozitórium), majd CI-ben reprodukálható baseline.
- Teljes Flutter-suite, property-gate és CI-workflow nem futott lokálisan:
  ezek az orchestrátor merge-előtti CI-felelősségei. Android APK-t a lokális
  kör szándékosan nem épített.

> Minden viselkedési állításhoz add meg a tesztet, ami bizonyítja. Állítás
> teszt nélkül = bemondás. **Szám, amit nem futtattál, hazugság.**

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e99-r04-gov-06-real-audio-dsp-baseline-review.md`
