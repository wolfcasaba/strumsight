# E99-R05 (GOV-06b) — A valós-audio BPM-metrika javítása

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-09, `main @ dc201524` utáni
  friss `main`; a defekt a GOV-06 SAJÁT riportadataiból mérve)
- **Típus:** **governance-kör**, a GOV-06 (`E99-R04`) **mérési javítása**
- **Kör-azonosító:** `E99-R05`. Az `E99` a governance-körök fenntartott
  pszeudo-epic kódja (nem valódi epic). Emberi neve **GOV-06b**.
- **Branch:** `codex/e99-r05-gov-06b-bpm-metric-fix`
- **Előfeltétel:** GOV-06 (`E99-R04`) merge-elve (PR #207)
- **Brief szerzője:** Claude (Opus 5) · **Implementáció:** Codex (Terra)
- **Előre kiosztott ADR:** [`0212`](../adr/0212-bpm-baseline-metric-invalidation-and-independent-tempo-reference.md)
  — **MÁR MEGÍRVA az orchesztrátor által, a `docs/adr/` a TILOS zónában van.**
  Az ADR 0212 **felülírja** az [ADR 0199](../adr/0199-real-audio-dsp-baseline-measurement-contract.md)
  **Döntés 6**-ot; az ADR 0199 minden más döntése érvényben marad.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "tool/benchmarks/real_audio_dsp_baseline.dart",
  "test/tooling/real_audio_dsp_baseline_test.dart",
  "ml/chords/tempo_reference.py",
  "docs/eval/real-audio-dsp-baseline.md",
  "docs/rounds/e99-r05-gov-06b-bpm-metric-fix.md",
]
gate_tests = [
  "test/tooling",
  "test/features/analyze",
]
native_gate = false
```

> **Egy ÚJ fájl:** `ml/chords/tempo_reference.py`. Ez az EGYETLEN engedélyezett
> új fájl; minden más új fájl scope-sértés. A meglévő
> `ml/chords/eval_real_sessions.py` és `eval_guitarset.py` **érintetlen** —
> más kérdést válaszolnak.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A GOV-06 három számából **kettő érvényes, egy nem**. Ez a kör a harmadikat
javítja: a **45,067 BPM MAE** nem a DSP tempó-hibáját méri, hanem két
pengetés-sűrűség-becslés egyezetlenségét.

**Ez orchesztrátor-hiba, nem implementer-hiba.** A GOV-06 implementere pontosan
azt építette, amit az ADR 0199 Döntés 6 és a brief §5.6 előírt, és a
feltételezést a riportban ki is mondta. A mércében volt a hiba: **kimondott
feltételezés ≠ validált feltételezés.**

## 2. Jelenlegi állapot — a defekt mérve

### 2.1 Ami ÉRVÉNYES és nem változik

| Metrika | Érték |
|---|---|
| Akkord-pontosság | **67,069%** (7892/11767), baseline 18,832%, moll 83,333% (185/222) |
| Onset P/R/F1 @25 ms | 38,532% / 42,517% / 40,427% |
| Onset P/R/F1 @50 ms | 64,233% / 70,876% / **67,391%** |
| Onset P/R/F1 @100 ms | 81,208% / 89,607% / 85,201% |

Ezek a `.strums` eseményekre épülnek, ahol **az esemény MAGA a ground truth** —
nincs bennük metrikai-szint feltételezés. A kör hozzájuk nem nyúl (ADR 0212
Döntés 5).

### 2.2 A defekt — három mérés

Az ADR 0199 Döntés 6 a BPM ground-truth-ot `60 / medián pozitív ground-truth
IOI`-ként definiálta, **kimondva**, hogy ez egyenletes rácsot feltételez.
A feltételezés hamis.

**(1) A származtatott ground truth önmagában implauzibilis** — a 82 `.strums`
fájlból számolva:

| Statisztika | Származtatott BPM |
|---|---|
| medián | **161,5** |
| p25 / p75 | 103,4 / 198,8 |
| min / max | 49,7 / **369,1** |
| 200 BPM felett | **20 felvétel** |

Pengetett akusztikus gitárgyakorlás nem 369 BPM-en zajlik. A `.strums`
események **pengetések, nem ütemek** (7228 `D` + 4539 `U` — tipikus
nyolcad-alapú le-fel mintázat). A „ground truth" pengetés-sűrűséget mér.

**(2) A DSP ugyanazt a rossz metrikai szintet követi** — a riport
felvételenkénti `predictedBpm / groundTruthBpm` arányából:

| Statisztika | Arány |
|---|---|
| medián | **1,028** |
| p25 / p75 | 0,889 / 1,276 |
| min / max | 0,515 / 3,657 |

A medián ~1,0 → a 45,067 MAE nem tempó-hiba, hanem két sűrűség-becslés
szórása.

**(3) Metrikai-szint toleranciával sem menthető** (±4%, az 1/3, 1/2, 2/3, 1,
3/2, 2, 3 szorzókat elfogadva):

| Egyezés | Felvétel | Arány |
|---|---|---|
| szigorú (±4%) | 15/82 | **18,3%** |
| metrikai-szint toleráns (±4%) | 22/82 | **26,8%** |

### 2.3 Az eszköz a javításhoz

`~/audio-venv/bin/python` létezik, **librosa 0.11.0 + numpy 1.26.4** (mérve).
A repó bevett gyakorlata: `ml/chords/eval_real_sessions.py` már ma is
librosa-referenciát használ közelítő ground-truth-ként.

> ⚠ A `~/audio-venv` **nincs verziókövetve**, ahogy a korpusz sem. Ugyanaz a
> reprodukálhatósági korlát (ADR 0199 Döntés 8) — a riportnak ezt is ki kell
> mondania.

## 3. Scope

**Benne:**

1. `ml/chords/tempo_reference.py` (ÚJ) — librosa beat-tracker, ami
   felvételenként **független tempó-becslést** ad, és JSON-t ír (fájlnév →
   tempó BPM). Ez a referencia, amit a Dart harness beolvas.
2. `tool/benchmarks/real_audio_dsp_baseline.dart` — a BPM-szakasz átírása:
   három szám (ADR 0212 Döntés 3), integer-ezrelék tűréssel.
3. `test/tooling/real_audio_dsp_baseline_test.dart` — az ÚJ BPM-metrikák
   cellái (a meglévő akkord/onset cellák **érintetlenül**).
4. `docs/eval/real-audio-dsp-baseline.md` — a BPM-szakasz átírása: a 45,067
   **visszavont** értékként marad, a visszavonás okával; az új számok
   hozzáadva.
5. A brief §10 handoff.

**Kívül (ebben a körben TILOS):**

- **A `lib/` bármely fájlja.** A DSP bitre változatlan (ADR 0212 Döntés 6).
  A tempó-becslés javítása KÉSŐBBI kör, és csak érvényes mérce után.
- Az akkord- és onset-metrika logikájának bármilyen módosítása (Döntés 5).
- `ml/chords/eval_real_sessions.py`, `eval_guitarset.py` és minden más
  meglévő `ml/` fájl.
- A korpusz (`ml/data/`) bármilyen módosítása vagy git-be vétele.
- Küszöb vagy CI-kapu bevezetése (ADR 0199 Döntés 8 érvényben).
- `.github/`, `tools/`, `assets/`, `lib/l10n/`, `docs/adr/`.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `ml/chords/tempo_reference.py` | **ÚJ** — a független librosa tempó-referencia |
| `tool/benchmarks/real_audio_dsp_baseline.dart` | a BPM-szakasz átírása |
| `test/tooling/real_audio_dsp_baseline_test.dart` | az ÚJ BPM-cellák |
| `docs/eval/real-audio-dsp-baseline.md` | a riport BPM-szakasza |
| `docs/rounds/e99-r05-gov-06b-bpm-metric-fix.md` | §10 handoff |

**Tilos zóna:** `lib/` (MINDEN), `ml/` a fenti egy ÚJ fájlon kívül,
`ml/data/`, `tools/`, `tool/` a fenti egy fájlon kívül, `.github/`,
`assets/`, `docs/adr/`, minden más `docs/` fájl.

## 5. Kötött architekturális döntések

Forrás: [ADR 0212](../adr/0212-bpm-baseline-metric-invalidation-and-independent-tempo-reference.md).

### 5.1 A referencia NEM a `.strums` eseményekből származik

Ez volt az eredeti hiba. A tempó-referencia **független beat-tracker**
(librosa), a `.wav`-ból. A `.strums`-alapú szám megmarad, de **átcímkézve**
(§5.3).

### 5.2 A tűrés-összehasonlítás integer EZRELÉKBEN történik

**Nem stílus, hanem a mérce épsége** — ugyanaz a hibaosztály, amit a GOV-06
az onsetnél már integer mikroszekundummal oldott meg, és amit a
[`docs/LESSONS.md`](../LESSONS.md) **L13** rögzít.

Mérve: `abs(1.04 - 1.0) <= 0.04` → **`False`** (a tényleges különbség
`0.040000000000000036`). Lebegőpontosan a „pontosan a tűréshatáron" cella
nem érhető el.

Ezért: az arányt ezrelékre kerekített `int`-ként hasonlítsd
(`deviationPerMille = ((ratio - 1).abs() * 1000).round()`), a feltétel
`deviationPerMille <= tolerancePerMille`, alapértelmezett tűrés **40**.

### 5.3 Három szám, kipinnelt címkékkel

A BPM-szakasz **mindhármat** közli, és a harmadikat **kifejezetten NEM
tempóként**:

| # | Név a riportban | Referencia | Tűrés |
|---|---|---|---|
| 1 | szigorú tempó-egyezés | librosa beat-tracker | ±40 ezrelék |
| 2 | metrikai-szint toleráns tempó-egyezés | librosa, az 1/3, 1/2, 2/3, 1, 3/2, 2, 3 szorzókkal | ±40 ezrelék |
| 3 | **pengetés-sűrűség egyezés** (NEM tempó) | a régi `.strums`-alapú szám | a meglévő |

A 3. sort **tilos** „BPM-pontosságnak" vagy „tempó-hibának" nevezni. Az
elnevezés a lelet lényege.

### 5.4 A visszavont szám nem törlendő

A 45,067 BPM MAE **benne marad** a riportban, `visszavonva` megjelöléssel és
a visszavonás okával (§2.2 három mérése). A törlés elfedné, hogy egyszer
állítottuk.

### 5.5 A „nem mérhető" ÉRVÉNYES kimenet

Ha a librosa-referencia és a pengetés-sűrűség olyan mértékben mond ellent
egymásnak, hogy a tempó a korpuszon nem mérhető, a helyes riport-kimenet:
**„a BPM ezen a korpuszon nem mérhető, mert nincs validált tempó-annotáció"**,
a szükséges lépés megnevezésével (kézi tempó-annotáció egy részhalmazon).

Ez **nem kudarc**, és **tilos** helyette egy szebb, de megalapozatlan számot
közölni.

### 5.6 Nyitott döntések — előre rögzített feloldással (ADR 0138)

```yaml
open_decisions:
  - id: OD-01
    question: Hol fusson a librosa referencia, és mi legyen a kimenete?
    blocking: false
    resolution_policy: use_default
    default: >
      `~/audio-venv/bin/python ml/chords/tempo_reference.py ml/data/klangio
      --out <json>`; a kimenet felvétel-stem → tempó BPM leképezés JSON-ban.
      A Dart harness ezt a JSON-t olvassa be egy paraméterrel megadott
      útvonalról. Ha a JSON hiányzik, a harness a tempó-szakaszt
      "nem futott" jelöléssel hagyja ki — NEM esik vissza a régi,
      .strums-alapú számra tempóként.

  - id: OD-02
    question: Melyik librosa API adja a tempót?
    blocking: false
    resolution_policy: use_default
    default: >
      `librosa.beat.beat_track` (a repó `eval_real_sessions.py`-ja is
      librosa-alapú). A pontos hívást és a librosa verziót (0.11.0) a
      riport rögzítse, mert verziófüggő.

  - id: OD-03
    question: Mi legyen, ha a librosa egy felvételre nem ad tempót?
    blocking: false
    resolution_policy: use_default
    default: >
      A felvétel kimarad a tempó-aggregátumból, DE nevesítve felsorolandó a
      riportban, a darabszámmal. Néma kihagyás TILOS (ugyanaz a szabály,
      mint a GOV-06 OD-02-jében).

  - id: OD-04
    question: Mi legyen, ha a DSP a független referenciához mérve is gyenge?
    blocking: false
    resolution_policy: use_default
    default: >
      A riport KIMONDJA, kiemelten. Nem hangolod, nem szépíted (Döntés 6).
      Ez érvényes kimenet — pontosan ezért mérünk.
```

## 6. Acceptance criteria

- [ ] **A1 — A `lib/` alatt nulla változás.**
  `git diff --name-only origin/main...HEAD | grep '^lib/'` **üres**.

- [ ] **A2 — A tűrés-cellahármas integer ezrelékben**, `python3 -c`-vel
  kiszámolva (§5.2):

  | `deviationPerMille` | `<= 40` | Elvárt |
  |---|---|---|
  | **39** | `True` | **egyezik** |
  | **40** | `True` | **egyezik** (ez az egyetlen cella, ami a `<` és a `<=` közti különbséget méri) |
  | **41** | `False` | **NEM egyezik** |

  Mind a három kötelező.

- [ ] **A3 — A metrikai-szint tolerancia mátrixa.** Ground-truth tempó 100
  BPM mellett, ±40 ezrelék tűréssel:

  | Jósolt BPM | Szigorú | Metrikai-szint toleráns |
  |---|---|---|
  | 100 | **egyezik** | egyezik |
  | 200 (2×) | **NEM** | **egyezik** |
  | 50 (1/2×) | **NEM** | **egyezik** |
  | 150 (3/2×) | **NEM** | **egyezik** |
  | 137 | **NEM** | **NEM** |

  Az utolsó sor az, ami a „minden szorzót elfogadó" hibás implementációt
  pirosra váltja.

- [ ] **A4 — A pengetés-sűrűség szám NEM tempóként szerepel** (§5.3).
  Gépi mérce: a riport BPM-szakaszában a `.strums`-alapú számhoz tartozó
  címke tartalmazza a „pengetés-sűrűség" kifejezést, és NEM tartalmazza a
  „tempó-hiba" / „BPM-pontosság" megnevezést.

- [ ] **A5 — A 45,067 visszavontként benne marad** (§5.4), a visszavonás
  okával — nem törölve, nem csendben lecserélve.

- [ ] **A6 — Nincs csendes visszaesés.** Ha a tempó-referencia JSON hiányzik,
  a harness a tempó-szakaszt „nem futott"-ként jelöli, és **nem** használja
  helyette a `.strums`-alapú számot tempóként (OD-01). Teszt-cella: hiányzó
  referencia → a kimenet tempó-szekciója `notRun`, nem szám.

- [ ] **A7 — Az akkord- és onset-számok bitre változatlanok.** Az újrafuttatás
  ugyanazt adja: akkord 7892/11767 = 67,069%, moll 185/222, onset F1
  40,427% / 67,391% / 85,201%. Eltérés → **lelet** (nem determinisztikus
  mérés), jelentendő.

- [ ] **A8 — A riport kimondja a reprodukálhatósági korlátot** a
  `~/audio-venv`-re is (nincs verziókövetve), a librosa verziójával (0.11.0)
  és a futtatott paranccsal együtt.

- [ ] **A9 — A kimaradt felvételek nevesítve** (OD-03), darabszámmal.

- [ ] **A10 — A gate zöld**, a §7 szerinti egyetlen artefaktum-hívással.

> **Miért nincs több küszöb-hármas:** a kör egyetlen numerikus tűrése az
> arány-tolerancia, és arra az A2 megadja a teljes alatta/rajta/fölötte
> hármast. A többi acceptance logikai.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Lebegőpontos arány-összehasonlítás integer ezrelék helyett | **A2 középső cella** (`40`) |
| Szigorú `<` a `<=` helyett | **A2 középső cella** |
| A metrikai-szint tolerancia minden szorzót elfogad | **A3 utolsó sora** (137 BPM) |
| A tolerancia csak 1× és 2× szorzót ismer | **A3** 1/2× és 3/2× sora |
| A `.strums`-alapú szám tempóként címkézve marad | **A4** |
| A 45,067 törölve vagy csendben lecserélve | **A5** |
| Hiányzó referencia esetén visszaesés a régi számra | **A6** |
| Az akkord/onset logika „menet közben" módosul | **A7** |

**Valódi-sértés próba (kötelező, §10-ben dokumentálandó):** írd át
ideiglenesen a tűrés-feltételt `<=`-ról `<`-ra → az **A2 középső cellájának
PIROSNAK kell lennie** → állítsd vissza, és idézd a nyers kimenetet.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling test/features/analyze
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05).

**A tényleges mérés két lépés**, és a kimenetük a riport:

```bash
~/audio-venv/bin/python ml/chords/tempo_reference.py ml/data/klangio --out /tmp/tempo_reference.json
~/flutter/bin/flutter test --dart-define=REAL_AUDIO_DSP_BASELINE_CORPUS=ml/data/klangio --dart-define=REAL_AUDIO_DSP_TEMPO_REFERENCE=/tmp/tempo_reference.json tool/benchmarks/real_audio_dsp_baseline.dart
```

> A második parancs alakját a GOV-06 handoffja mérte ki: a brief eredetileg
> `dart run`-t írt elő, de a valós `ClipAnalyzer` tranzitívan `dart:ui`-t
> importál, ami a sima Dart VM-ben nem elérhető — a Flutter-tesztrunner
> ugyanazt a változatlan publikus `ClipAnalyzer`-t futtatja. **Ez a mért,
> működő alak**, ne térj vissza a `dart run`-hoz.

## 8. Implementációs sorrend

1. **RED először:** a `test/tooling/...` ÚJ BPM-cellái — A2 hármas, A3
   ötsoros mátrix, A6 hiányzó-referencia cella. Szintetikus, kézzel számolt
   bemeneteken.
2. `ml/chords/tempo_reference.py` — a librosa referencia + JSON-kimenet.
3. A harness BPM-szakaszának átírása, amíg a tesztek zöldek.
4. Gate futtatása.
5. A két mérési parancs lefuttatása (§7).
6. A riport BPM-szakaszának átírása a TÉNYLEGES számokkal (A4, A5, A8, A9).
   Ne írj bele számot, amit nem futtattál.
7. A §6.1 valódi-sértés próba + visszaállítás.
8. Záró gate + §10 handoff + `done`.

## 9. Kockázatok

1. **A librosa-referencia is közelítő** — nem kézi annotáció. A riport ezt
   mondja ki; ne állítsd abszolút igazságnak.
2. **Lehet, hogy a helyes kimenet a „nem mérhető"** (§5.5). Előre elfogadva.
3. **A `~/audio-venv` nincs verziókövetve** — ugyanaz a reprodukálhatósági
   korlát, mint a korpusznál (A8).
4. **A tempó-becslés javítása NEM e kör dolga** — előbb kell érvényes mérce.

## 10. Implementation handoff — a Codex tölti ki

- **Módosított fájlok:** `ml/chords/tempo_reference.py` librosa 0.11.0
  `beat_track`-referenciát és stem→BPM JSON-kimenetet ad; a benchmark integer
  ezrelékes, inkluzív szigorú és metrikai-szint egyezést számol, hiányzó JSON-nál
  `notRun`-t ad, a régi összevetést pengetés-sűrűségként tartja meg; a teszt A2,
  A3 és A6 szintetikus cellákat ad; a riport a mért értékekkel frissült.
- **Futtatott parancsok:**
  - `~/audio-venv/bin/python ml/chords/tempo_reference.py ml/data/klangio --out /tmp/tempo_reference.json`
    → `librosa version: 0.11.0`; `tempo references written: 82/82 ->
    /tmp/tempo_reference.json`; `recordings without tempo (0): []`.
  - `~/flutter/bin/flutter test --dart-define=REAL_AUDIO_DSP_BASELINE_CORPUS=ml/data/klangio --dart-define=REAL_AUDIO_DSP_TEMPO_REFERENCE=/tmp/tempo_reference.json tool/benchmarks/real_audio_dsp_baseline.dart`
    → 82/82 feldolgozva, 0 kihagyott; szigorú egyezés 11/82, metrikai-szint
    egyezés 32/82, pengetés-sűrűség átlagos abszolút különbség
    45.06716069579421 BPM. A teljes JSON-kimenet a riport mérési szakaszának
    forrása volt.
- **§6.1 valódi-sértés próba:** a `<=` ideiglenes `<`-re cserélése után a
  célzott teszt PIROS: `Expected: <true> Actual: <false> predicted=104.0`,
  `test/tooling/real_audio_dsp_baseline_test.dart 92:9`; a többi 7 teszt lefutott,
  majd a `<=` visszaállítása után a célzott teszt `00:00 +8: All tests passed!`.
- **A1 bizonyíték:** `git diff --name-only origin/main...HEAD | grep '^lib/'`
  kimenete üres volt; a kör nem módosít `lib/` fájlt.
- **A7 bizonyíték:** újrafuttatva változatlan: akkord 7892/11767 =
  67.069%, moll 185/222 = 83.333%; onset F1: 40.427% / 67.391% / 85.201%.
- **OD-03:** librosa minden felvételre adott tempót; kimaradt: 0, lista `[]`.
- **OD-04:** a mért szigorú egyezés 13.415%, metrikai-szint egyezés 39.024%;
  nincs validált, kézi tempó-annotáció, ezért a BPM ezen a korpuszon nem
  mérhető. DSP-hangolás nem történt.
- **Eltérés / nem futtatott ellenőrzés:** az audio-venvben nincs `ruff`, ezért a
  Python-fájl ruff-formázása nem futott; csomagtelepítés scope-on kívüli volt.
  A Dart-format, analyze és célzott tesztek a gate-ben futnak. Follow-up: kézi
  tempó-annotáció reprezentatív részhalmazon, majd külön DSP-javítási kör, ha
  érvényes mérce ezt indokolja.

> Szám, amit nem futtattál, hazugság.

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e99-r05-gov-06b-bpm-metric-fix-review.md`
