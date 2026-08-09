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

- [x] **A1 — A `lib/` alatt nulla változás.**
  `git diff --name-only origin/main...HEAD | grep '^lib/'` **üres**.

- [x] **A2 — A tűrés-cellahármas integer ezrelékben**, `python3 -c`-vel
  kiszámolva (§5.2):

  | `deviationPerMille` | `<= 40` | Elvárt |
  |---|---|---|
  | **39** | `True` | **egyezik** |
  | **40** | `True` | **egyezik** (ez az egyetlen cella, ami a `<` és a `<=` közti különbséget méri) |
  | **41** | `False` | **NEM egyezik** |

  Mind a három kötelező.

- [x] **A3 — A metrikai-szint tolerancia mátrixa.** Ground-truth tempó 100
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

- [x] **A4 — A pengetés-sűrűség szám NEM tempóként szerepel** (§5.3).
  Gépi mérce: a riport BPM-szakaszában a `.strums`-alapú számhoz tartozó
  címke tartalmazza a „pengetés-sűrűség" kifejezést, és NEM tartalmazza a
  „tempó-hiba" / „BPM-pontosság" megnevezést.

- [x] **A5 — A 45,067 visszavontként benne marad** (§5.4), a visszavonás
  okával — nem törölve, nem csendben lecserélve.

- [x] **A6 — Nincs csendes visszaesés.** Ha a tempó-referencia JSON hiányzik,
  a harness a tempó-szakaszt „nem futott"-ként jelöli, és **nem** használja
  helyette a `.strums`-alapú számot tempóként (OD-01). Teszt-cella: hiányzó
  referencia → a kimenet tempó-szekciója `notRun`, nem szám.

- [x] **A7 — Az akkord- és onset-számok bitre változatlanok.** Az újrafuttatás
  ugyanazt adja: akkord 7892/11767 = 67,069%, moll 185/222, onset F1
  40,427% / 67,391% / 85,201%. Eltérés → **lelet** (nem determinisztikus
  mérés), jelentendő.

- [x] **A8 — A riport kimondja a reprodukálhatósági korlátot** a
  `~/audio-venv`-re is (nincs verziókövetve), a librosa verziójával (0.11.0)
  és a futtatott paranccsal együtt.

- [x] **A9 — A kimaradt felvételek nevesítve** (OD-03), darabszámmal.

- [x] **A10 — A gate zöld**, a §7 szerinti egyetlen artefaktum-hívással.

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
- **Futtatott parancsok + tényleges, csonkítatlan kimenet:**
  - `~/audio-venv/bin/python ml/chords/tempo_reference.py ml/data/klangio --out /tmp/tempo_reference.json`

  ```text
  librosa version: 0.11.0
  tempo references written: 82/82 -> /tmp/tempo_reference.json
  recordings without tempo (0): []
  ```

  - `~/flutter/bin/flutter test --dart-define=REAL_AUDIO_DSP_BASELINE_CORPUS=ml/data/klangio --dart-define=REAL_AUDIO_DSP_TEMPO_REFERENCE=/tmp/tempo_reference.json tool/benchmarks/real_audio_dsp_baseline.dart`

  ```text
  Resolving dependencies...
  Downloading packages...
    _fe_analyzer_shared 99.0.0 (105.0.0 available)
    analyzer 12.1.0 (14.1.0 available)
    camera 0.11.4 (0.12.0+2 available)
    camera_android_camerax 0.6.30 (0.7.4+4 available)
    camera_avfoundation 0.9.23+2 (0.10.2 available)
    camera_web 0.3.5+4 (0.3.5+5 available)
    dio 5.10.0 (5.11.0 available)
    dio_web_adapter 2.2.0 (2.2.1 available)
    flutter_local_notifications 22.0.1 (22.2.0 available)
    flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
    flutter_riverpod 3.3.2 (3.4.2 available)
    flutter_secure_storage 10.3.1 (11.0.0 available)
    flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
    flutter_secure_storage_linux 3.0.1 (3.0.2 available)
    flutter_secure_storage_platform_interface 2.0.1 (2.0.3 available)
    go_router 17.3.0 (17.4.0 available)
    hooks 2.0.2 (2.1.0 available)
    intl 0.20.2 (0.20.3 available)
    jni 1.0.0 (1.0.3 available)
    jni_flutter 1.0.1 (1.0.2 available)
    matcher 0.12.19 (0.12.20 available)
    meta 1.18.0 (1.19.0 available)
    objective_c 9.4.1 (9.5.0 available)
    package_config 2.2.0 (3.0.0 available)
    package_info_plus 10.2.0 (10.2.1 available)
    permission_handler 12.0.3 (13.0.0 available)
    permission_handler_android 13.0.1 (14.0.0 available)
    permission_handler_apple 9.4.10 (9.5.0 available)
    permission_handler_html 0.1.3+5 (0.1.4+1 available)
    permission_handler_platform_interface 4.3.0 (4.4.0 available)
    permission_handler_windows 0.2.1 (0.2.2 available)
    record_use 0.6.0 (1.0.0 available)
    riverpod 3.3.2 (3.4.2 available)
    share_plus 13.2.0 (13.3.0 available)
    share_plus_platform_interface 7.1.0 (7.2.0 available)
    shared_preferences_android 2.4.26 (2.4.27 available)
    synchronized 3.4.1 (3.4.1+1 available)
    test 1.31.0 (1.31.2 available)
    test_api 0.7.11 (0.7.13 available)
    test_core 0.6.17 (0.6.19 available)
    uuid 4.5.3 (4.6.0 available)
    vector_math 2.2.0 (2.4.2 available)
    wakelock_plus 1.6.1 (1.7.0 available)
    wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
    win32 6.3.0 (6.4.0 available)
    xml 6.6.1 (7.0.1 available)
  Got dependencies!
  46 packages have newer versions incompatible with dependency constraints.
  Try `flutter pub outdated` for more information.
  00:00 +0: loading /home/ubuntu/ss-terra-e99-r05/tool/benchmarks/real_audio_dsp_baseline.dart
  Shell: [1/82] recording_1001_phone.wav
  Shell: [2/82] recording_1002_phone.wav
  Shell: [3/82] recording_1003_phone.wav
  Shell: [4/82] recording_1004_phone.wav
  Shell: [5/82] recording_1005_phone.wav
  Shell: [6/82] recording_1006_phone.wav
  Shell: [7/82] recording_1007_phone.wav
  Shell: [8/82] recording_1008_phone.wav
  Shell: [9/82] recording_1009_phone.wav
  Shell: [10/82] recording_1010_phone.wav
  Shell: [11/82] recording_1011_phone.wav
  Shell: [12/82] recording_1012_phone.wav
  Shell: [13/82] recording_1013_phone.wav
  Shell: [14/82] recording_1014_phone.wav
  Shell: [15/82] recording_1015_phone.wav
  Shell: [16/82] recording_1016_phone.wav
  Shell: [17/82] recording_1017_phone.wav
  Shell: [18/82] recording_1018_phone.wav
  Shell: [19/82] recording_1019_phone.wav
  Shell: [20/82] recording_1020_phone.wav
  Shell: [21/82] recording_1021_phone.wav
  Shell: [22/82] recording_1023_phone.wav
  Shell: [23/82] recording_1024_phone.wav
  Shell: [24/82] recording_1025_phone.wav
  Shell: [25/82] recording_1026_phone.wav
  Shell: [26/82] recording_1027_phone.wav
  Shell: [27/82] recording_1028_phone.wav
  Shell: [28/82] recording_2001_phone.wav
  Shell: [29/82] recording_2002_phone.wav
  Shell: [30/82] recording_2003_phone.wav
  Shell: [31/82] recording_2004_phone.wav
  Shell: [32/82] recording_2005_phone.wav
  Shell: [33/82] recording_2006_phone.wav
  Shell: [34/82] recording_2007_phone.wav
  Shell: [35/82] recording_2008_phone.wav
  Shell: [36/82] recording_2009_phone.wav
  Shell: [37/82] recording_2010_phone.wav
  Shell: [38/82] recording_2011_phone.wav
  Shell: [39/82] recording_2012_phone.wav
  Shell: [40/82] recording_2013_phone.wav
  Shell: [41/82] recording_2014_phone.wav
  Shell: [42/82] recording_2015_phone.wav
  Shell: [43/82] recording_2016_phone.wav
  Shell: [44/82] recording_2017_phone.wav
  Shell: [45/82] recording_2018_phone.wav
  Shell: [46/82] recording_2019_phone.wav
  Shell: [47/82] recording_2020_phone.wav
  Shell: [48/82] recording_2021_phone.wav
  Shell: [49/82] recording_2022_phone.wav
  Shell: [50/82] recording_2023_phone.wav
  Shell: [51/82] recording_2024_phone.wav
  Shell: [52/82] recording_2025_phone.wav
  Shell: [53/82] recording_2026_phone.wav
  Shell: [54/82] recording_2027_phone.wav
  Shell: [55/82] recording_2028_phone.wav
  Shell: [56/82] recording_4001_phone.wav
  Shell: [57/82] recording_4002_phone.wav
  Shell: [58/82] recording_4003_phone.wav
  Shell: [59/82] recording_4004_phone.wav
  Shell: [60/82] recording_4005_phone.wav
  Shell: [61/82] recording_4006_phone.wav
  Shell: [62/82] recording_4007_phone.wav
  Shell: [63/82] recording_4008_phone.wav
  Shell: [64/82] recording_4009_phone.wav
  Shell: [65/82] recording_4010_phone.wav
  Shell: [66/82] recording_4011_phone.wav
  Shell: [67/82] recording_4012_phone.wav
  Shell: [68/82] recording_4013_phone.wav
  Shell: [69/82] recording_4014_phone.wav
  Shell: [70/82] recording_4015_phone.wav
  Shell: [71/82] recording_4016_phone.wav
  Shell: [72/82] recording_4017_phone.wav
  Shell: [73/82] recording_4018_phone.wav
  Shell: [74/82] recording_4019_phone.wav
  Shell: [75/82] recording_4020_phone.wav
  Shell: [76/82] recording_4021_phone.wav
  Shell: [77/82] recording_4022_phone.wav
  Shell: [78/82] recording_4023_phone.wav
  Shell: [79/82] recording_4024_phone.wav
  Shell: [80/82] recording_4025_phone.wav
  Shell: [81/82] recording_4027_phone.wav
  Shell: [82/82] recording_4028_phone.wav
  Shell: {
  Shell:   "corpus": {
  Shell:     "path": "ml/data/klangio",
  Shell:     "wavCount": 82,
  Shell:     "strumsCount": 82,
  Shell:     "eventCount": 11767,
  Shell:     "sha256": "4880faceab27217640701f1b93db477606d5fb3aa2c4434574040b6590315827",
  Shell:     "versionControlled": false
  Shell:   },
  Shell:   "processedRecordings": 82,
  Shell:   "skippedRecordings": [],
  Shell:   "chords": {
  Shell:     "correct": 7892,
  Shell:     "total": 11767,
  Shell:     "accuracy": 0.6706892156029575,
  Shell:     "majorityClassBaseline": {
  Shell:       "label": "G-major",
  Shell:       "correct": 2216,
  Shell:       "total": 11767,
  Shell:       "accuracy": 0.1883232769609926
  Shell:     },
  Shell:     "minorSubset": {
  Shell:       "correct": 185,
  Shell:       "total": 222,
  Shell:       "accuracy": 0.8333333333333334
  Shell:     },
  Shell:     "perLabel": {
  Shell:       "A-major": {
  Shell:         "support": 1546,
  Shell:         "precision": 0.8832288401253918,
  Shell:         "recall": 0.7289780077619664
  Shell:       },
  Shell:       "A-minor": {
  Shell:         "support": 98,
  Shell:         "precision": 0.6722689075630253,
  Shell:         "recall": 0.8163265306122449
  Shell:       },
  Shell:       "B-major": {
  Shell:         "support": 860,
  Shell:         "precision": 0.9394703656998739,
  Shell:         "recall": 0.8662790697674418
  Shell:       },
  Shell:       "B-minor": {
  Shell:         "support": 124,
  Shell:         "precision": 0.8823529411764706,
  Shell:         "recall": 0.8467741935483871
  Shell:       },
  Shell:       "Bb-major": {
  Shell:         "support": 284,
  Shell:         "precision": 0.9520958083832335,
  Shell:         "recall": 0.5598591549295775
  Shell:       },
  Shell:       "C#-major": {
  Shell:         "support": 138,
  Shell:         "precision": 0.0,
  Shell:         "recall": 0.0
  Shell:       },
  Shell:       "C-major": {
  Shell:         "support": 1982,
  Shell:         "precision": 0.8497772119669,
  Shell:         "recall": 0.6735620585267407
  Shell:       },
  Shell:       "D-major": {
  Shell:         "support": 1804,
  Shell:         "precision": 0.8984468339307049,
  Shell:         "recall": 0.41685144124168516
  Shell:       },
  Shell:       "E-major": {
  Shell:         "support": 1283,
  Shell:         "precision": 0.8276119402985075,
  Shell:         "recall": 0.8643803585346843
  Shell:       },
  Shell:       "F#-major": {
  Shell:         "support": 408,
  Shell:         "precision": 0.9525222551928784,
  Shell:         "recall": 0.7867647058823529
  Shell:       },
  Shell:       "F-major": {
  Shell:         "support": 1024,
  Shell:         "precision": 0.7767624020887729,
  Shell:         "recall": 0.5810546875
  Shell:       },
  Shell:       "G-major": {
  Shell:         "support": 2216,
  Shell:         "precision": 0.88712422007941,
  Shell:         "recall": 0.7057761732851986
  Shell:       }
  Shell:     }
  Shell:   },
  Shell:   "onsets": {
  Shell:     "25000": {
  Shell:       "matched": 5003,
  Shell:       "falsePositives": 7981,
  Shell:       "falseNegatives": 6764,
  Shell:       "precision": 0.3853203943314849,
  Shell:       "recall": 0.4251720914421688,
  Shell:       "f1": 0.4042664942830592
  Shell:     },
  Shell:     "50000": {
  Shell:       "matched": 8340,
  Shell:       "falsePositives": 4644,
  Shell:       "falseNegatives": 3427,
  Shell:       "precision": 0.6423290203327172,
  Shell:       "recall": 0.7087617914506671,
  Shell:       "f1": 0.6739121651650438
  Shell:     },
  Shell:     "100000": {
  Shell:       "matched": 10544,
  Shell:       "falsePositives": 2440,
  Shell:       "falseNegatives": 1223,
  Shell:       "precision": 0.8120764017252002,
  Shell:       "recall": 0.8960652672728818,
  Shell:       "f1": 0.8520059795563816
  Shell:     }
  Shell:   },
  Shell:   "bpm": {
  Shell:     "status": "measured",
  Shell:     "referenceMethod": "librosa.beat.beat_track",
  Shell:     "tolerancePerMille": 40,
  Shell:     "strictTempoMatch": {
  Shell:       "matched": 11,
  Shell:       "eligible": 82
  Shell:     },
  Shell:     "metricLevelTempoMatch": {
  Shell:       "matched": 32,
  Shell:       "eligible": 82,
  Shell:       "ratios": [
  Shell:         0.3333333333333333,
  Shell:         0.5,
  Shell:         0.6666666666666666,
  Shell:         1.0,
  Shell:         1.5,
  Shell:         2.0,
  Shell:         3.0
  Shell:       ]
  Shell:     },
  Shell:     "missingReferenceRecordings": [],
  Shell:     "records": [
  Shell:       {
  Shell:         "recording": "recording_1001",
  Shell:         "referenceBpm": 49.69200721153846,
  Shell:         "predictedBpm": 82.68749999999977,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1002",
  Shell:         "referenceBpm": 99.38401442307692,
  Shell:         "predictedBpm": 101.3327205882361,
  Shell:         "strictMatch": true,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1003",
  Shell:         "referenceBpm": 95.703125,
  Shell:         "predictedBpm": 100.34890776699055,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1004",
  Shell:         "referenceBpm": 143.5546875,
  Shell:         "predictedBpm": 141.58818493150648,
  Shell:         "strictMatch": true,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1005",
  Shell:         "referenceBpm": 97.50884433962264,
  Shell:         "predictedBpm": 102.3360148514853,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1006",
  Shell:         "referenceBpm": 99.38401442307692,
  Shell:         "predictedBpm": 191.4062499999999,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1007",
  Shell:         "referenceBpm": 79.50721153846153,
  Shell:         "predictedBpm": 161.49902343749977,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1008",
  Shell:         "referenceBpm": 132.51201923076923,
  Shell:         "predictedBpm": 300.0,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1009",
  Shell:         "referenceBpm": 101.33272058823529,
  Shell:         "predictedBpm": 102.3360148514853,
  Shell:         "strictMatch": true,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1010",
  Shell:         "referenceBpm": 161.4990234375,
  Shell:         "predictedBpm": 161.49902343749977,
  Shell:         "strictMatch": true,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1011",
  Shell:         "referenceBpm": 161.4990234375,
  Shell:         "predictedBpm": 164.06250000000122,
  Shell:         "strictMatch": true,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1012",
  Shell:         "referenceBpm": 99.38401442307692,
  Shell:         "predictedBpm": 107.66601562499916,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1013",
  Shell:         "referenceBpm": 50.666360294117645,
  Shell:         "predictedBpm": 95.70312499999994,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1014",
  Shell:         "referenceBpm": 80.74951171875,
  Shell:         "predictedBpm": 154.2677238805972,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1015",
  Shell:         "referenceBpm": 101.33272058823529,
  Shell:         "predictedBpm": 187.92613636363643,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1016",
  Shell:         "referenceBpm": 50.17445388349515,
  Shell:         "predictedBpm": 99.38401442307723,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1017",
  Shell:         "referenceBpm": 101.33272058823529,
  Shell:         "predictedBpm": 184.57031250000227,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1018",
  Shell:         "referenceBpm": 80.74951171875,
  Shell:         "predictedBpm": 151.99908088235324,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1019",
  Shell:         "referenceBpm": 101.33272058823529,
  Shell:         "predictedBpm": 172.26562499999912,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1020",
  Shell:         "referenceBpm": 80.74951171875,
  Shell:         "predictedBpm": 118.8038793103448,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1021",
  Shell:         "referenceBpm": 99.38401442307692,
  Shell:         "predictedBpm": 198.76802884615327,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1023",
  Shell:         "referenceBpm": 95.703125,
  Shell:         "predictedBpm": 97.50884433962247,
  Shell:         "strictMatch": true,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1024",
  Shell:         "referenceBpm": 161.4990234375,
  Shell:         "predictedBpm": 161.49902343749977,
  Shell:         "strictMatch": true,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1025",
  Shell:         "referenceBpm": 99.38401442307692,
  Shell:         "predictedBpm": 161.49902343749977,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1026",
  Shell:         "referenceBpm": 103.359375,
  Shell:         "predictedBpm": 102.3360148514853,
  Shell:         "strictMatch": true,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1027",
  Shell:         "referenceBpm": 132.51201923076923,
  Shell:         "predictedBpm": 219.91356382978523,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_1028",
  Shell:         "referenceBpm": 101.33272058823529,
  Shell:         "predictedBpm": 198.76802884615563,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2001",
  Shell:         "referenceBpm": 99.38401442307692,
  Shell:         "predictedBpm": 107.66601562500054,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2002",
  Shell:         "referenceBpm": 101.33272058823529,
  Shell:         "predictedBpm": 118.8038793103448,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2003",
  Shell:         "referenceBpm": 50.17445388349515,
  Shell:         "predictedBpm": 164.06250000000003,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2004",
  Shell:         "referenceBpm": 101.33272058823529,
  Shell:         "predictedBpm": 106.55605670103219,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2005",
  Shell:         "referenceBpm": 101.33272058823529,
  Shell:         "predictedBpm": 191.4062499999999,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2006",
  Shell:         "referenceBpm": 79.50721153846153,
  Shell:         "predictedBpm": 271.99835526316434,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2007",
  Shell:         "referenceBpm": 79.50721153846153,
  Shell:         "predictedBpm": 184.57031250000227,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2008",
  Shell:         "referenceBpm": 99.38401442307692,
  Shell:         "predictedBpm": 215.33203125000108,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2009",
  Shell:         "referenceBpm": 101.33272058823529,
  Shell:         "predictedBpm": 202.66544117647464,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2010",
  Shell:         "referenceBpm": 161.4990234375,
  Shell:         "predictedBpm": 166.70866935483818,
  Shell:         "strictMatch": true,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2011",
  Shell:         "referenceBpm": 101.33272058823529,
  Shell:         "predictedBpm": 184.57031250000227,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2012",
  Shell:         "referenceBpm": 99.38401442307692,
  Shell:         "predictedBpm": 202.66544117646978,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2013",
  Shell:         "referenceBpm": 79.50721153846153,
  Shell:         "predictedBpm": 161.49902343750287,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2014",
  Shell:         "referenceBpm": 99.38401442307692,
  Shell:         "predictedBpm": 300.0,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2015",
  Shell:         "referenceBpm": 82.03125,
  Shell:         "predictedBpm": 178.20581896551593,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2016",
  Shell:         "referenceBpm": 101.33272058823529,
  Shell:         "predictedBpm": 191.4062499999999,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2017",
  Shell:         "referenceBpm": 101.33272058823529,
  Shell:         "predictedBpm": 229.68750000000037,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2018",
  Shell:         "referenceBpm": 101.33272058823529,
  Shell:         "predictedBpm": 198.76802884615327,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2019",
  Shell:         "referenceBpm": 109.95678191489361,
  Shell:         "predictedBpm": 169.44159836065674,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2020",
  Shell:         "referenceBpm": 80.74951171875,
  Shell:         "predictedBpm": 159.014423076923,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2021",
  Shell:         "referenceBpm": 79.50721153846153,
  Shell:         "predictedBpm": 258.3984375000066,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2022",
  Shell:         "referenceBpm": 99.38401442307692,
  Shell:         "predictedBpm": 187.92613636363643,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2023",
  Shell:         "referenceBpm": 78.30255681818181,
  Shell:         "predictedBpm": 159.014423076923,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2024",
  Shell:         "referenceBpm": 99.38401442307692,
  Shell:         "predictedBpm": 191.4062499999999,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2025",
  Shell:         "referenceBpm": 79.50721153846153,
  Shell:         "predictedBpm": 172.26562499999997,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2026",
  Shell:         "referenceBpm": 79.50721153846153,
  Shell:         "predictedBpm": 149.796195652173,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2027",
  Shell:         "referenceBpm": 99.38401442307692,
  Shell:         "predictedBpm": 219.91356382978523,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_2028",
  Shell:         "referenceBpm": 198.76802884615384,
  Shell:         "predictedBpm": 210.93749999999864,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4001",
  Shell:         "referenceBpm": 82.03125,
  Shell:         "predictedBpm": 295.312500000001,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4002",
  Shell:         "referenceBpm": 80.74951171875,
  Shell:         "predictedBpm": 86.13281249999999,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4003",
  Shell:         "referenceBpm": 151.99908088235293,
  Shell:         "predictedBpm": 154.2677238805972,
  Shell:         "strictMatch": true,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4004",
  Shell:         "referenceBpm": 147.65625,
  Shell:         "predictedBpm": 149.796195652173,
  Shell:         "strictMatch": true,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4005",
  Shell:         "referenceBpm": 139.6748310810811,
  Shell:         "predictedBpm": 252.0960365853687,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4006",
  Shell:         "referenceBpm": 79.50721153846153,
  Shell:         "predictedBpm": 265.0240384615385,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4007",
  Shell:         "referenceBpm": 105.46875,
  Shell:         "predictedBpm": 161.49902343749977,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4008",
  Shell:         "referenceBpm": 101.33272058823529,
  Shell:         "predictedBpm": 161.49902343749977,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4009",
  Shell:         "referenceBpm": 107.666015625,
  Shell:         "predictedBpm": 287.1093750000014,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4010",
  Shell:         "referenceBpm": 161.4990234375,
  Shell:         "predictedBpm": 172.26562499999912,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4011",
  Shell:         "referenceBpm": 132.51201923076923,
  Shell:         "predictedBpm": 215.33203125000108,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4012",
  Shell:         "referenceBpm": 80.74951171875,
  Shell:         "predictedBpm": 181.3322368421057,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4013",
  Shell:         "referenceBpm": 99.38401442307692,
  Shell:         "predictedBpm": 172.26562499999912,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4014",
  Shell:         "referenceBpm": 161.4990234375,
  Shell:         "predictedBpm": 175.185381355932,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4015",
  Shell:         "referenceBpm": 79.50721153846153,
  Shell:         "predictedBpm": 202.66544117647038,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4016",
  Shell:         "referenceBpm": 101.33272058823529,
  Shell:         "predictedBpm": 191.40625000000205,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4017",
  Shell:         "referenceBpm": 80.74951171875,
  Shell:         "predictedBpm": 154.26772388059578,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4018",
  Shell:         "referenceBpm": 99.38401442307692,
  Shell:         "predictedBpm": 123.04687499999972,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4019",
  Shell:         "referenceBpm": 99.38401442307692,
  Shell:         "predictedBpm": 108.79934210526294,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4020",
  Shell:         "referenceBpm": 79.50721153846153,
  Shell:         "predictedBpm": 178.2058189655178,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4021",
  Shell:         "referenceBpm": 99.38401442307692,
  Shell:         "predictedBpm": 219.9135638297881,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4022",
  Shell:         "referenceBpm": 132.51201923076923,
  Shell:         "predictedBpm": 206.7187500000002,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4023",
  Shell:         "referenceBpm": 99.38401442307692,
  Shell:         "predictedBpm": 206.71874999999892,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4024",
  Shell:         "referenceBpm": 99.38401442307692,
  Shell:         "predictedBpm": 191.4062499999977,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4025",
  Shell:         "referenceBpm": 82.03125,
  Shell:         "predictedBpm": 169.44159836065504,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4027",
  Shell:         "referenceBpm": 101.33272058823529,
  Shell:         "predictedBpm": 184.57031249999974,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": false
  Shell:       },
  Shell:       {
  Shell:         "recording": "recording_4028",
  Shell:         "referenceBpm": 101.33272058823529,
  Shell:         "predictedBpm": 151.99908088235324,
  Shell:         "strictMatch": false,
  Shell:         "metricLevelMatch": true
  Shell:       }
  Shell:     ],
  Shell:     "strumDensityAgreement": {
  Shell:       "method": "60 / median positive .strums inter-onset interval",
  Shell:       "recordings": 82,
  Shell:       "meanAbsoluteDifferenceBpm": 45.06716069579421,
  Shell:       "records": [
  Shell:         {
  Shell:           "recording": "recording_1001",
  Shell:           "strumDensityBpm": 49.692033621629946,
  Shell:           "predictedBpm": 82.68749999999977,
  Shell:           "absoluteDifferenceBpm": 32.99546637836983
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1002",
  Shell:           "strumDensityBpm": 99.38398493338788,
  Shell:           "predictedBpm": 101.3327205882361,
  Shell:           "absoluteDifferenceBpm": 1.948735654848221
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1003",
  Shell:           "strumDensityBpm": 95.70309073131517,
  Shell:           "predictedBpm": 100.34890776699055,
  Shell:           "absoluteDifferenceBpm": 4.645817035675378
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1004",
  Shell:           "strumDensityBpm": 129.19924461508316,
  Shell:           "predictedBpm": 141.58818493150648,
  Shell:           "absoluteDifferenceBpm": 12.388940316423316
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1005",
  Shell:           "strumDensityBpm": 184.5699520118125,
  Shell:           "predictedBpm": 102.3360148514853,
  Shell:           "absoluteDifferenceBpm": 82.23393716032719
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1006",
  Shell:           "strumDensityBpm": 258.39904564619144,
  Shell:           "predictedBpm": 191.4062499999999,
  Shell:           "absoluteDifferenceBpm": 66.99279564619155
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1007",
  Shell:           "strumDensityBpm": 258.39904564619144,
  Shell:           "predictedBpm": 161.49902343749977,
  Shell:           "absoluteDifferenceBpm": 96.90002220869167
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1008",
  Shell:           "strumDensityBpm": 369.139904023625,
  Shell:           "predictedBpm": 300.0,
  Shell:           "absoluteDifferenceBpm": 69.13990402362498
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1009",
  Shell:           "strumDensityBpm": 198.76764062810574,
  Shell:           "predictedBpm": 102.3360148514853,
  Shell:           "absoluteDifferenceBpm": 96.43162577662044
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1010",
  Shell:           "strumDensityBpm": 172.2652885443583,
  Shell:           "predictedBpm": 161.49902343749977,
  Shell:           "absoluteDifferenceBpm": 10.766265106858526
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1011",
  Shell:           "strumDensityBpm": 215.33199707866257,
  Shell:           "predictedBpm": 164.06250000000122,
  Shell:           "absoluteDifferenceBpm": 51.269497078661345
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1012",
  Shell:           "strumDensityBpm": 198.7682991065365,
  Shell:           "predictedBpm": 107.66601562499916,
  Shell:           "absoluteDifferenceBpm": 91.10228348153733
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1013",
  Shell:           "strumDensityBpm": 95.70309073131517,
  Shell:           "predictedBpm": 95.70312499999994,
  Shell:           "absoluteDifferenceBpm": 0.00003426868477163225
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1014",
  Shell:           "strumDensityBpm": 151.99916907120908,
  Shell:           "predictedBpm": 154.2677238805972,
  Shell:           "absoluteDifferenceBpm": 2.268554809388121
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1015",
  Shell:           "strumDensityBpm": 184.57051978134547,
  Shell:           "predictedBpm": 187.92613636363643,
  Shell:           "absoluteDifferenceBpm": 3.3556165822909634
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1016",
  Shell:           "strumDensityBpm": 52.20171613141782,
  Shell:           "predictedBpm": 99.38401442307723,
  Shell:           "absoluteDifferenceBpm": 47.182298291659414
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1017",
  Shell:           "strumDensityBpm": 184.57051978134547,
  Shell:           "predictedBpm": 184.57031250000227,
  Shell:           "absoluteDifferenceBpm": 0.00020728134319369929
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1018",
  Shell:           "strumDensityBpm": 161.49870801033592,
  Shell:           "predictedBpm": 151.99908088235324,
  Shell:           "absoluteDifferenceBpm": 9.499627127982677
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1019",
  Shell:           "strumDensityBpm": 103.35935117889953,
  Shell:           "predictedBpm": 172.26562499999912,
  Shell:           "absoluteDifferenceBpm": 68.90627382109959
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1020",
  Shell:           "strumDensityBpm": 151.99878400972793,
  Shell:           "predictedBpm": 118.8038793103448,
  Shell:           "absoluteDifferenceBpm": 33.19490469938313
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1021",
  Shell:           "strumDensityBpm": 258.3984892301663,
  Shell:           "predictedBpm": 198.76802884615327,
  Shell:           "absoluteDifferenceBpm": 59.63046038401305
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1023",
  Shell:           "strumDensityBpm": 123.04676084529024,
  Shell:           "predictedBpm": 97.50884433962247,
  Shell:           "absoluteDifferenceBpm": 25.537916505667766
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1024",
  Shell:           "strumDensityBpm": 172.26553583912695,
  Shell:           "predictedBpm": 161.49902343749977,
  Shell:           "absoluteDifferenceBpm": 10.766512401627182
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1025",
  Shell:           "strumDensityBpm": 198.7682991065365,
  Shell:           "predictedBpm": 161.49902343749977,
  Shell:           "absoluteDifferenceBpm": 37.269275669036716
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1026",
  Shell:           "strumDensityBpm": 52.7343647003194,
  Shell:           "predictedBpm": 102.3360148514853,
  Shell:           "absoluteDifferenceBpm": 49.601650151165906
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1027",
  Shell:           "strumDensityBpm": 322.99741602067184,
  Shell:           "predictedBpm": 219.91356382978523,
  Shell:           "absoluteDifferenceBpm": 103.0838521908866
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_1028",
  Shell:           "strumDensityBpm": 215.33238347826398,
  Shell:           "predictedBpm": 198.76802884615563,
  Shell:           "absoluteDifferenceBpm": 16.564354632108348
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2001",
  Shell:           "strumDensityBpm": 99.38398493338788,
  Shell:           "predictedBpm": 107.66601562500054,
  Shell:           "absoluteDifferenceBpm": 8.282030691612661
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2002",
  Shell:           "strumDensityBpm": 99.38398493338788,
  Shell:           "predictedBpm": 118.8038793103448,
  Shell:           "absoluteDifferenceBpm": 19.41989437695692
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2003",
  Shell:           "strumDensityBpm": 161.49914270871744,
  Shell:           "predictedBpm": 164.06250000000003,
  Shell:           "absoluteDifferenceBpm": 2.5633572912825855
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2004",
  Shell:           "strumDensityBpm": 95.70309073131517,
  Shell:           "predictedBpm": 106.55605670103219,
  Shell:           "absoluteDifferenceBpm": 10.852965969717019
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2005",
  Shell:           "strumDensityBpm": 184.57051978134547,
  Shell:           "predictedBpm": 191.4062499999999,
  Shell:           "absoluteDifferenceBpm": 6.835730218654419
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2006",
  Shell:           "strumDensityBpm": 206.71870235779906,
  Shell:           "predictedBpm": 271.99835526316434,
  Shell:           "absoluteDifferenceBpm": 65.27965290536528
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2007",
  Shell:           "strumDensityBpm": 258.3979328165375,
  Shell:           "predictedBpm": 184.57031250000227,
  Shell:           "absoluteDifferenceBpm": 73.82762031653522
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2008",
  Shell:           "strumDensityBpm": 322.9991548188782,
  Shell:           "predictedBpm": 215.33203125000108,
  Shell:           "absoluteDifferenceBpm": 107.66712356887712
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2009",
  Shell:           "strumDensityBpm": 198.76764062810574,
  Shell:           "predictedBpm": 202.66544117647464,
  Shell:           "absoluteDifferenceBpm": 3.897800548368906
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2010",
  Shell:           "strumDensityBpm": 172.2657831346056,
  Shell:           "predictedBpm": 166.70866935483818,
  Shell:           "absoluteDifferenceBpm": 5.557113779767434
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2011",
  Shell:           "strumDensityBpm": 135.99906613974585,
  Shell:           "predictedBpm": 184.57031250000227,
  Shell:           "absoluteDifferenceBpm": 48.571246360256424
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2012",
  Shell:           "strumDensityBpm": 198.7682991065365,
  Shell:           "predictedBpm": 202.66544117646978,
  Shell:           "absoluteDifferenceBpm": 3.8971420699332953
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2013",
  Shell:           "strumDensityBpm": 151.99916907120908,
  Shell:           "predictedBpm": 161.49902343750287,
  Shell:           "absoluteDifferenceBpm": 9.499854366293789
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2014",
  Shell:           "strumDensityBpm": 95.70309073131517,
  Shell:           "predictedBpm": 300.0,
  Shell:           "absoluteDifferenceBpm": 204.29690926868483
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2015",
  Shell:           "strumDensityBpm": 156.60501214341366,
  Shell:           "predictedBpm": 178.20581896551593,
  Shell:           "absoluteDifferenceBpm": 21.60080682210227
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2016",
  Shell:           "strumDensityBpm": 103.35935117889953,
  Shell:           "predictedBpm": 191.4062499999999,
  Shell:           "absoluteDifferenceBpm": 88.04689882110036
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2017",
  Shell:           "strumDensityBpm": 95.70316705705584,
  Shell:           "predictedBpm": 229.68750000000037,
  Shell:           "absoluteDifferenceBpm": 133.98433294294455
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2018",
  Shell:           "strumDensityBpm": 198.76796986677576,
  Shell:           "predictedBpm": 198.76802884615327,
  Shell:           "absoluteDifferenceBpm": 0.00005897937751342397
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2019",
  Shell:           "strumDensityBpm": 50.17446078134179,
  Shell:           "predictedBpm": 169.44159836065674,
  Shell:           "absoluteDifferenceBpm": 119.26713757931495
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2020",
  Shell:           "strumDensityBpm": 151.99916907120908,
  Shell:           "predictedBpm": 159.014423076923,
  Shell:           "absoluteDifferenceBpm": 7.015254005713928
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2021",
  Shell:           "strumDensityBpm": 234.9072116513977,
  Shell:           "predictedBpm": 258.3984375000066,
  Shell:           "absoluteDifferenceBpm": 23.491225848608906
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2022",
  Shell:           "strumDensityBpm": 184.57051978134547,
  Shell:           "predictedBpm": 187.92613636363643,
  Shell:           "absoluteDifferenceBpm": 3.3556165822909634
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2023",
  Shell:           "strumDensityBpm": 191.40618146263034,
  Shell:           "predictedBpm": 159.014423076923,
  Shell:           "absoluteDifferenceBpm": 32.391758385707334
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2024",
  Shell:           "strumDensityBpm": 103.35935117889953,
  Shell:           "predictedBpm": 191.4062499999999,
  Shell:           "absoluteDifferenceBpm": 88.04689882110036
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2025",
  Shell:           "strumDensityBpm": 161.49892535923416,
  Shell:           "predictedBpm": 172.26562499999997,
  Shell:           "absoluteDifferenceBpm": 10.766699640765808
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2026",
  Shell:           "strumDensityBpm": 80.74946267961708,
  Shell:           "predictedBpm": 149.796195652173,
  Shell:           "absoluteDifferenceBpm": 69.04673297255592
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2027",
  Shell:           "strumDensityBpm": 322.99741602067184,
  Shell:           "predictedBpm": 219.91356382978523,
  Shell:           "absoluteDifferenceBpm": 103.0838521908866
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_2028",
  Shell:           "strumDensityBpm": 215.33238347826398,
  Shell:           "predictedBpm": 210.93749999999864,
  Shell:           "absoluteDifferenceBpm": 4.394883478265342
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4001",
  Shell:           "strumDensityBpm": 80.74946267961708,
  Shell:           "predictedBpm": 295.312500000001,
  Shell:           "absoluteDifferenceBpm": 214.56303732038396
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4002",
  Shell:           "strumDensityBpm": 80.74946267961708,
  Shell:           "predictedBpm": 86.13281249999999,
  Shell:           "absoluteDifferenceBpm": 5.383349820382904
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4003",
  Shell:           "strumDensityBpm": 135.99922027113712,
  Shell:           "predictedBpm": 154.2677238805972,
  Shell:           "absoluteDifferenceBpm": 18.268503609460083
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4004",
  Shell:           "strumDensityBpm": 117.45383574864096,
  Shell:           "predictedBpm": 149.796195652173,
  Shell:           "absoluteDifferenceBpm": 32.34235990353204
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4005",
  Shell:           "strumDensityBpm": 258.3979328165375,
  Shell:           "predictedBpm": 252.0960365853687,
  Shell:           "absoluteDifferenceBpm": 6.301896231168797
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4006",
  Shell:           "strumDensityBpm": 206.71870235779906,
  Shell:           "predictedBpm": 265.0240384615385,
  Shell:           "absoluteDifferenceBpm": 58.30533610373945
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4007",
  Shell:           "strumDensityBpm": 258.3979328165375,
  Shell:           "predictedBpm": 161.49902343749977,
  Shell:           "absoluteDifferenceBpm": 96.89890937903772
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4008",
  Shell:           "strumDensityBpm": 172.26553583912695,
  Shell:           "predictedBpm": 161.49902343749977,
  Shell:           "absoluteDifferenceBpm": 10.766512401627182
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4009",
  Shell:           "strumDensityBpm": 322.99741602067184,
  Shell:           "predictedBpm": 287.1093750000014,
  Shell:           "absoluteDifferenceBpm": 35.888041020670414
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4010",
  Shell:           "strumDensityBpm": 172.2657831346056,
  Shell:           "predictedBpm": 172.26562499999912,
  Shell:           "absoluteDifferenceBpm": 0.0001581346064938316
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4011",
  Shell:           "strumDensityBpm": 271.99844054227424,
  Shell:           "predictedBpm": 215.33203125000108,
  Shell:           "absoluteDifferenceBpm": 56.66640929227316
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4012",
  Shell:           "strumDensityBpm": 161.49914270871744,
  Shell:           "predictedBpm": 181.3322368421057,
  Shell:           "absoluteDifferenceBpm": 19.833094133388244
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4013",
  Shell:           "strumDensityBpm": 184.57023589614232,
  Shell:           "predictedBpm": 172.26562499999912,
  Shell:           "absoluteDifferenceBpm": 12.304610896143203
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4014",
  Shell:           "strumDensityBpm": 151.99916907120908,
  Shell:           "predictedBpm": 175.185381355932,
  Shell:           "absoluteDifferenceBpm": 23.186212284722927
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4015",
  Shell:           "strumDensityBpm": 151.99897654022462,
  Shell:           "predictedBpm": 202.66544117647038,
  Shell:           "absoluteDifferenceBpm": 50.66646463624576
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4016",
  Shell:           "strumDensityBpm": 107.66599853933128,
  Shell:           "predictedBpm": 191.40625000000205,
  Shell:           "absoluteDifferenceBpm": 83.74025146067076
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4017",
  Shell:           "strumDensityBpm": 143.55475058558375,
  Shell:           "predictedBpm": 154.26772388059578,
  Shell:           "absoluteDifferenceBpm": 10.712973295012034
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4018",
  Shell:           "strumDensityBpm": 99.38398493338788,
  Shell:           "predictedBpm": 123.04687499999972,
  Shell:           "absoluteDifferenceBpm": 23.662890066611837
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4019",
  Shell:           "strumDensityBpm": 52.7343647003194,
  Shell:           "predictedBpm": 108.79934210526294,
  Shell:           "absoluteDifferenceBpm": 56.06497740494354
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4020",
  Shell:           "strumDensityBpm": 139.67488342967022,
  Shell:           "predictedBpm": 178.2058189655178,
  Shell:           "absoluteDifferenceBpm": 38.53093553584759
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4021",
  Shell:           "strumDensityBpm": 132.51205307549432,
  Shell:           "predictedBpm": 219.9135638297881,
  Shell:           "absoluteDifferenceBpm": 87.40151075429378
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4022",
  Shell:           "strumDensityBpm": 369.139904023625,
  Shell:           "predictedBpm": 206.7187500000002,
  Shell:           "absoluteDifferenceBpm": 162.42115402362478
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4023",
  Shell:           "strumDensityBpm": 271.99844054227424,
  Shell:           "predictedBpm": 206.71874999999892,
  Shell:           "absoluteDifferenceBpm": 65.27969054227532
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4024",
  Shell:           "strumDensityBpm": 103.35935117889953,
  Shell:           "predictedBpm": 191.4062499999977,
  Shell:           "absoluteDifferenceBpm": 88.04689882109817
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4025",
  Shell:           "strumDensityBpm": 161.49914270871744,
  Shell:           "predictedBpm": 169.44159836065504,
  Shell:           "absoluteDifferenceBpm": 7.942455651937593
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4027",
  Shell:           "strumDensityBpm": 161.49892535923416,
  Shell:           "predictedBpm": 184.57031249999974,
  Shell:           "absoluteDifferenceBpm": 23.07138714076558
  Shell:         },
  Shell:         {
  Shell:           "recording": "recording_4028",
  Shell:           "strumDensityBpm": 103.35935117889953,
  Shell:           "predictedBpm": 151.99908088235324,
  Shell:           "absoluteDifferenceBpm": 48.63972970345371
  Shell:         }
  Shell:       ]
  Shell:     }
  Shell:   }
  Shell: }
  No tests ran.
  No tests were found.
  ```

  - Tételes aggregátum-ellenőrzés: `"strictTempoMatch": {"matched": 11, "eligible": 82}` és `"metricLevelTempoMatch": {"matched": 32, "eligible": 82}`; a beillesztett `bpm.records` tömb 82 felvételt tartalmaz.
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
