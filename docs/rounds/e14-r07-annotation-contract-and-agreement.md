# E14-R07 — Annotációs szerződés, validator és annotátor-egyetértés

- **Státusz:** READY (pre-flight lefutott 2026-09-04, kód újramérve: `main @ 1feecc11`;
  előre megírva 2026-08-20, `main @ b0979855`)
- **Típus:** Chapter 14 (Recognition Accuracy & Useful UI Recovery), Kör 7
- **Kör-azonosító:** `E14-R07`
- **Branch:** `<motor>/e14-r07-annotation-contract-and-agreement`
- **Előfeltétel:** `E14-R06` merge-elve (a csomagformátum, amit annotálunk).
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0359` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a
> `evaluation/analysis/manifest_schema.json`-t és a
> `lib/features/audio_analysis/data/evaluation/evaluation_manifest_parser.dart`-t
> — ez a kör UGYANAZT a mintát viszi tovább a felismerési oldalra, nem újat
> talál ki. Ellenőrizd az `E14-R06` `LabCapturePackage` mezőneveit is.
> Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "evaluation/recognition/annotation_schema.json",
  "evaluation/recognition/fixtures/annotation_pair.json",
  "lib/features/live/domain/evaluation/recognition_annotation.dart",
  "lib/features/live/data/evaluation/recognition_annotation_parser.dart",
  "tool/recognition_annotate.dart",
  "test/features/live/evaluation/recognition_annotation_test.dart",
  "docs/eval/recognition-annotation.md",
  "docs/rounds/e14-r07-annotation-contract-and-agreement.md",
]
gate_tests = [
  "test/features/live/evaluation/recognition_annotation_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Kötött scope-szűkítés a SDD-hez képest (drift, KÖTELEZŐ így)

A SDD Kör 07 grafikus annotátort ír (waveform, spectrogram, húzható onset,
undo/redo). Ez a kör a **szerződést, a validatort és az egyetértés-mérést**
építi meg CLI-ként; a grafikus szerkesztő NINCS benne. Mért ok: a repónak
nincs desktop/web futtatási célja, és a gate egy GUI-t nem tud vezetni —
a bizonyítható rész (séma, átfedés-validáció, provenance, két-annotátoros
riport) viszont közvetlenül mérhető. A szerkesztő külön kör (`E14-R07b`),
és a jelen kör acceptance-e nem hivatkozhat rá.

### 0.0.1 Pre-flight revíziók (2026-09-04, `main @ 1feecc11`) — MÉRT állítások

Az alábbiak a MAI fán mértek, és **felülírják** a brief régebbi szövegének minden
ellentmondó részletét. Forrásuk az ADR
[`0359`](../adr/0359-recognition-annotation-contract-and-agreement.md)
kontextus-szakasza.

**R1 — ADR-szám: `0359` marad.** A `tools/round-slots.py reserve-adr --round E14-R07`
a globális számlálóból `0506`-ot adott (a lemezen a legnagyobb ADR `0503`), a
Chapter 14 előre kiosztott blokkja viszont `0359`-et rendel ehhez a körhöz
(`E14-R06…R09` = `0358…0361`). A `0359` a lemezen **szabad**
(`ls docs/adr | grep ^0359` → nincs találat), és a foglaló marker-könyvtárában sem
szerepelt; egyedül ez a brief hivatkozik rá. A `0506` foglalása megmarad (nem
használjuk), és a pre-flight a `0359`-re is markert írt, hogy egy párhuzamos kör
se kaphassa meg. Ugyanez a mérés az `E14-R06`-ban (`0358` vs `0504`).

**R2 — `evaluation/recognition/` MÁR LÉTEZIK.** A §2 „az `E14-R02` hozza létre"
mondata teljesült: a könyvtárban ma `README.md`, `baseline_manifest.json` és
`baseline_manifest_schema.json` van (ADR 0354). A kör az új `fixtures/`
alkönyvtárat hozza létre, a meglévő három fájlhoz **nem nyúl** (tilos zóna).

**R3 — A minta a `EvaluationManifestParser`, a FÜGGÉS tilos (ADR 0359 D6).**
Másolandó alak (`lib/features/audio_analysis/data/evaluation/evaluation_manifest_parser.dart`):
egy hiba-`enum` (`…ErrorKind`) + egy `…ParseException(kind, message, {path})`
típus, szigorú ismeretlen-kulcs ellenőrzés, és `parseJsonString` + `parse(Map)`
páros. A `live` oldalon ez SAJÁT típusnevekkel készül: az `audio_analysis`
kódjának importja kereszt-feature függés lenne (`tool/check_architecture.dart:774`
— csak `public.dart` barrel célozható). Idegen barrel bővítése → `stopped`.

**R4 — A `live` barrel nem válik elavulttá, tehát nem kell hozzányúlni.** A
generált barrel-ellenőrzés (`tool/check_architecture.dart:798`) csak azokra a
feature-ökre fut, amelyeknek van `lib/features/<f>/public/` fragment-könyvtára
(`tool/gen_public_barrel.dart:37-45`); a `lib/features/live/public/` **nem
létezik**, a `public.dart` kézzel írott. Új `domain/`/`data/` fájl tehát nem teszi
elavulttá. Az új típusok **nem** kerülnek a barrelbe (nem publikus szerződés) —
a `lib/features/live/public.dart` a tilos zónában marad.

**R5 — A `tool/` CLI és a teszt közvetlen útvonalon importálhat.** Az
architektúra-őr csak a `lib/`-et járja be (`tool/check_architecture.dart:136`),
ezért a `tool/recognition_annotate.dart` ugyanúgy importálhatja az új parsert
közvetlenül, ahogy a `tool/audio_analysis_evaluate.dart` teszi ma
(`import 'package:strumsight/features/audio_analysis/data/evaluation/…'`). A CLI
alakja is onnan másolandó: fixture-default útvonal, `--manifest`/`--help`
kapcsoló, determinisztikus JSON a `stdout`-ra, hiba a `stderr`-re nem nulla
kilépési kóddal.

**R6 — A fixture NEM a `test/fixtures/` nyilvántartás alá tartozik.** A
`tool/check_fixture_manifest.dart:10` a `test/fixtures/manifest.json` ellenében
méri a `test/fixtures/` fát; az `evaluation/recognition/fixtures/annotation_pair.json`
azon kívül van, tehát sem bejegyzést nem kap, sem hiányzó bejegyzésként nem bukik
el. Ne írj hozzá manifest-bejegyzést (az a tilos zóna).

**R7 — Nulla hálózati minta a `lib/`-ben.** A `tool/check_data_inventory.dart:431`
a `lib/` fából deríti fel az egress-útvonalakat, és találat esetén
`docs/privacy/data-inventory.yaml` bejegyzést követelne — az tilos zóna. A parser
és a modell ezért `dart:io`-mentes, tiszta érték-kód; a fájlbeolvasás kizárólag a
`tool/` CLI-ben történik.

**R8 — Irány-címke: a `core` enumja legális, az `audio_analysis`-é nem.** A fán
`lib/core/music/strum.dart:5` → `enum StrumDirection { down, up }`, és
`lib/features/audio_analysis/domain/analysis_event.dart:55` →
`enum StrumDirection { down, up, unknown }`. A `core` importja feature → core
irány, tehát legális; az `audio_analysis`-beli közvetlen import architektúra-sértés.
Ha az annotációnak a `down|up`-nál többre van szüksége, a kör SAJÁT enumot
deklarál az új `domain/` fájlban — idegen feature enumját nem importálja.

**R9 — Nincs S5-típusnév-ütközés.** `RecognitionAnnotation`, `AnnotationEvent`,
`AnnotationProvenance`, `Provenance`, `AgreementReport` egyike sem létezik ma a
`lib/`/`tool/` fában.

**R10 — A `dart format` és a `flutter analyze` a `tool/`-ra is fut**
(`.github/actions/flutter-gates/action.yml:13,17`: `dart format … lib test tool`,
`flutter analyze lib/ test/ tool/`), tehát a CLI formázása és lint-tisztasága a
kapu része, nem opció.

## 1. Cél

Az annotáció legyen **verziózott, validált és visszakövethető**: egy onset-,
irány- és akkord-annotációs séma, hozzá parser és `tool/`-CLI, amely elutasítja
az érvénytelen/átfedő eseményeket, és két annotátor eltéréséről gépi riportot ad.
Automatikus címke önmagában NEM ground truth — a séma ezt a provenance mezővel
teszi mérhetővé.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **ADR 0249 / E06-R29:** `EvaluationManifestParser` + `manifest_schema.json` —
  típusos hibák (`InvalidSchemaVersion`), CI-fixture, külső valós korpusz. Ez a
  kör ugyanezt a hármast építi a felismerési annotációra.
- **E14-R01 release guard:** a „nem validált állítás visszavonva" szabály — az
  annotációnál ez a `provenance: auto|human|reviewed` mező.

## 2. Jelenlegi állapot — mért tények

- `evaluation/recognition/` — az `E14-R02` hozza létre (baseline manifest); az
  annotációs séma ide kerül, mellé.
- `lib/features/live/domain/`, `lib/features/live/data/` — **nem léteznek**; ez
  a kör hozza létre őket, az `audio_analysis` mintájára.
- `tool/audio_analysis_evaluate.dart` — a CLI-forma mintája (fixture-default,
  `--manifest` kapcsoló, determinisztikus JSON a stdout-ra).

## 3. Scope

**Benne:** annotációs séma (JSON Schema), Flutter-független modell + parser,
átfedés/érvényesség validáció, provenance, két-annotátoros egyetértés-riport,
CLI, CI-fixture, rövid doksi.

**Nincs benne:** GUI, hangfájl-írás/módosítás, modellhívás, DSP, `ml/**`,
korpusz-adat a repóban.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `evaluation/recognition/annotation_schema.json` | a séma maga |
| `evaluation/recognition/fixtures/annotation_pair.json` | két annotátoros CI-fixture |
| `lib/features/live/domain/evaluation/recognition_annotation.dart` | Flutter-független modell |
| `lib/features/live/data/evaluation/recognition_annotation_parser.dart` | típusos parser + validáció |
| `tool/recognition_annotate.dart` | validate + agreement CLI |
| `test/features/live/evaluation/recognition_annotation_test.dart` | séma, validáció, egyetértés |
| `docs/eval/recognition-annotation.md` | használat, provenance-szabály |
| `docs/rounds/e14-r07-annotation-contract-and-agreement.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten `lib/features/live/engine/**`,
`evaluation/analysis/**`, `assets/**`, `ml/**`, `docs/adr/**`,
`docs/rag/chunks/**`, `.github/workflows/**`, `tools/round-gate.sh`. Új
kereszt-feature import felvétele a `tool/check_architecture.dart` listájába
TILOS — ha kellene, `stopped`.

## 5. Kötött architekturális döntések (ADR 0359)

### 5.1 A nyers hang érintetlen

A CLI és a parser CSAK annotációt olvas/ír; WAV-ot soha nem módosít, nem is
nyit írásra. **NEM elfogadható**: „normalizáljuk a WAV-ot a konzisztenciáért".

### 5.2 Provenance kötelező, és nem default `human`

Minden esemény `provenance` mezője kötelező, felvehető értékei
`auto | human | reviewed`; hiányzó mező **típusos hiba**. Az automatikus címke
sosem lép elő `human`-ná parser-oldalon.

### 5.3 Átfedés és érvénytelenség: hiba, nem javítás

Két, ugyanarra a sávra eső, átfedő esemény esetén a parser hibát ad, **nem**
old fel csendben (nem vág, nem összevon). A hiba tartalmazza a két esemény
indexét.

### 5.4 Egyetértés: mért szám, nem becslés

A riport párosított eseményekre onset-toleranciával számol egyetértést, és
külön adja az irány- és akkord-címke egyezését. A tolerancia paraméter, nem
beégetett konstans.

### 5.5 Determinisztikus kimenet

Ugyanaz a bemenet bitre ugyanazt a riportot adja (kanonikus kulcsrend, nincs
`DateTime.now()` a riport belsejében).

## 6. Acceptance criteria

1. A séma-verzió eltérése típusos hibát ad (nem `null`, nem default).
2. Átfedő eseménypár elutasítva, a hibaüzenet mindkét indexet tartalmazza.
3. Hiányzó `provenance` → típusos hiba; `auto` érték nem konvertálódik.
4. A CLI a fixture-ön determinisztikus JSON riportot ad: kétszeri futás bájtra
   azonos.
5. Az egyetértés-riport a fixture-re kézzel ellenőrzött értéket ad: a két
   annotátor 10 eseményéből 8 párosítható 50 ms-on belül, ebből 7 egyezik
   irányban → `directionAgreement = 0.875`.
6. Az onset-tolerancia (50 ms) határa **inkluzív**, és mind a három cellát
   mérni kell: a küszöb **alatt** (49 ms eltérés) → párosít; **rajta**
   (pontosan 50 ms) → párosít, mert a határ az elfogadó oldalhoz tartozik;
   **fölött** (51 ms) → nem párosít.

> **A számok kiszámolva (S3, `python3 -c`, 2026-09-04):**
> `7/8 = 0.875` (irány-egyetértés a párosított eseményekre),
> `8/10 = 0.8` (párosítási arány — ez NEM az egyetértés, a kettő nem
> keverhető), `49 <= 50 → True`, `50 <= 50 → True`, `51 <= 50 → False`
> (az inkluzív határ három cellája).

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A parser az átfedést csendben összevonja | 2. pont index-cellája |
| Hiányzó provenance → `human` default | 3. pont típusos-hiba cellája |
| A riportba bekerül a futás időbélyege | 4. pont bájtra-azonos cellája |
| A párosítás exkluzív határt használ (`<`) | 6. pont **50 ms** cellája |
| Az egyetértés az összes eseményre oszt, nem a párosítottakra | 5. pont `0.875` cellája |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live/evaluation/recognition_annotation_test.dart
```

> **S12-revízió (brief-lint, 2026-09-04):** a korábbi parancs a
> `test/features/live/evaluation` KÖNYVTÁRAT adta át, a `gate_tests` viszont a
> `test/features/live/evaluation/recognition_annotation_test.dart` FÁJLT sorolja
> fel. A metaadatot a scope-audit és a CI-terv olvassa, a kaput viszont a
> parancssor futtatja — a kettő szétcsúszása néma. A fenti parancs mostantól
> tükrözi a `gate_tests` listát.

Külön processzben futó `format` → `analyze` → célzott teszt → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge
Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: a párosítás határának `<=` → `<` cserével a 6. pont
**50 ms** cellája **PIROS**, visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. Séma + fixture.
2. Modell + parser (séma-verzió, provenance, átfedés).
3. Egyetértés-számítás.
4. CLI a meglévő `tool/audio_analysis_evaluate.dart` alakja szerint.
5. Doksi.

## 9. Kockázatok

- **A GUI-igény visszaszivárgása:** a §0.0 tiltja; felület-kérés → `stopped`.
- **Fixture-túlillesztés:** a fixture-nek tartalmaznia kell nem párosítható
  eseményt is, különben a párosító hibás implementációja is zöld marad.
- **Kereszt-feature import:** az `audio_analysis` evaluation kódját NEM
  importáljuk; a minta másolható, a függés nem.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
