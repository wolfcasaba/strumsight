# E14-R06 — Accuracy Lab és engedélyezett adatgyűjtés

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ b0979855`)
- **Típus:** Chapter 14 (Recognition Accuracy & Useful UI Recovery), Kör 6
- **Kör-azonosító:** `E14-R06`
- **Branch:** `<motor>/e14-r06-accuracy-lab-and-consented-capture`
- **Előfeltétel:** `E14-R01` merge-elve (release guard). Az `E14-R02…R05`-től
  FÜGGETLEN — a fájlhalmaz diszjunkt, párhuzamosítható.
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0358` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a
> `lib/features/analyze/engine/clip_recorder.dart`-ot (ez a MEGLÉVŐ felvevő, a
> kör NEM ír újat) és a `lib/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart`
> consent-mintáját. Ha az `E14-R02` közben merge-elt, igazítsd a manifest-mezőket
> a `evaluation/recognition/baseline_manifest.json` sémájához. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/accuracy_lab/domain/lab_task.dart",
  "lib/features/accuracy_lab/domain/lab_capture_package.dart",
  "lib/features/accuracy_lab/domain/lab_consent.dart",
  "lib/features/accuracy_lab/data/lab_package_writer.dart",
  "lib/features/accuracy_lab/public.dart",
  "test/features/accuracy_lab/lab_capture_package_test.dart",
  "test/features/accuracy_lab/lab_package_writer_test.dart",
  "test/features/accuracy_lab/lab_consent_test.dart",
  "docs/rounds/e14-r06-accuracy-lab-and-consented-capture.md",
]
gate_tests = [
  "test/features/accuracy_lab/lab_capture_package_test.dart",
  "test/features/accuracy_lab/lab_package_writer_test.dart",
  "test/features/accuracy_lab/lab_consent_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a kör mikrofon-felvételt csomagol, consent-kaput
és lokális törlést épít — a diff adatvédelmi felületet érint (`privacy`,
felhasználói nyers audio), ezért a security-review kötelező (`.ai/router.toml`
high-risk osztály).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Kötött scope-szűkítés a SDD-hez képest (drift, KÖTELEZŐ így)

A SDD Kör 06 „Accuracy Lab flow"-t ír 15–20 feladattal, azaz **felületet is**.
Ez a kör a flow **adat- és adatvédelmi magját** építi meg (feladatlista-domain,
csomagformátum, consent-kapu, író/törlő), **képernyő nélkül** — két mért ok:

1. A képernyő helye a Chapter 13 sávban van (`E13-R16…R35` a képernyők köre);
   két sáv ugyanarra a felületre írva fájl-ütközést adna, amit a slot-tervező
   (`tools/round-slots.py plan`) épp tiltani hivatott.
2. A gate a felületet csak widget-teszttel méri, a csomag-determinizmust és a
   consent-kaput viszont közvetlenül — a bizonyítható rész kerül ebbe a körbe.

A UI-bekötés külön kör (`E14-R06b`, brief később), és a jelen kör
acceptance-e NEM hivatkozhat rá.

## 1. Cél

Legyen a repóban egy **hálózat nélkül is végigfutó**, gépileg ellenőrizhető
mérési-csomag szerződés: a Lab feladatai (csend, zaj, egyes akkordok, lassú
down/up, váltott pengetés, gyors pattern) determinisztikus csomagot adnak
(WAV + eseménylista + eszköz-metadata + consent-verzió), amelyből a későbbi
körök (R07 annotáció, R08 harness) ground truthot építhetnek — anélkül, hogy
bármi elhagyná az eszközt a felhasználó kifejezett beleegyezése nélkül.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **ADR 0249 / E06-R29** (`evaluation/analysis/manifest_schema.json`): a repó
  már eldöntötte, hogy **nyers audio SOHA nem kerül a repóba** — a manifest
  csak paramétert és annotációt tartalmaz. Ez a kör ugyanezt a határt viszi
  tovább az eszközön keletkező csomagra.
- **E99-R07 / tutor privacy**: a `tutor_privacy_providers.dart` már bevezette
  a „nincs beleegyezés → nincs kimenő adat" mintát; ezt a kör újrahasznosítja,
  nem talál ki másikat.

## 2. Jelenlegi állapot — mért tények

- `lib/features/analyze/engine/clip_recorder.dart` — MEGLÉVŐ klip-felvevő; a
  kör NEM ír új felvevőt, csak a csomagot építi köré.
- `lib/features/accuracy_lab/` — **nem létezik**; ez a kör hozza létre.
- `evaluation/analysis/README.md` + `manifest_schema.json` — a „manifest igen,
  nyers audio nem" határ MÁR írott szabály (E06-R29).
- A `ml/corpus/` a tanító oldal korpusz-eszköze (`fetch.sh`,
  `make_voice_negatives.py`), nem az eszközön keletkező csomagé — a kettőt a
  brief szándékosan nem keveri.

## 3. Scope

**Benne:** feladat-domain (`LabTask`), csomag-modell (`LabCapturePackage`),
consent-modell és -kapu (`LabConsent`), determinisztikus író + törlő
(`LabPackageWriter`), checksum, séma-verzió.

**Nincs benne:** képernyő, navigáció, l10n-kulcs, export-hálózat, modellhívás,
DSP-paraméter, `ml/**`, bármilyen automatikus feltöltés.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/accuracy_lab/domain/lab_task.dart` | a 15–20 feladat típusos leírása |
| `lib/features/accuracy_lab/domain/lab_capture_package.dart` | csomag-modell + séma-verzió |
| `lib/features/accuracy_lab/domain/lab_consent.dart` | consent-állapot és -verzió |
| `lib/features/accuracy_lab/data/lab_package_writer.dart` | determinisztikus írás, checksum, törlés |
| `lib/features/accuracy_lab/public.dart` | additív barrel |
| `test/features/accuracy_lab/lab_capture_package_test.dart` | round-trip + determinizmus |
| `test/features/accuracy_lab/lab_package_writer_test.dart` | írás/törlés/hash |
| `test/features/accuracy_lab/lab_consent_test.dart` | consent-kapu mátrix |
| `docs/rounds/e14-r06-accuracy-lab-and-consented-capture.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten `lib/features/analyze/**`,
`lib/features/live/**`, `lib/l10n/**` és a generált l10n, `assets/**`, `ml/**`,
`docs/adr/**`, `docs/rag/chunks/**`, `.github/workflows/**`,
`tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0358)

### 5.1 Nincs export consent nélkül — a kapu típusban él

Az exportot végző hívás **csak** `LabConsent.granted`-et fogadjon el
paraméterként; a „nincs consent" ág ne futásidejű `if` legyen egy bool fölött,
hanem külön típus. **NEM elfogadható** gyengítés: nullable consent + `?? false`,
vagy „a hívó felelőssége" kommentár.

### 5.2 A csomag nem tartalmaz azonosítót

Tilos e-mail, account token, pontos hely, IMEI, hirdetési azonosító. Az
eszköz-metadata kizárólag: modellnév, OS-verzió, mintavételi frekvencia,
csatornaszám, app-verzió. **NEM elfogadható**: „hash-elve azért benne marad".

### 5.3 Determinizmus: ugyanaz a bemenet bitre ugyanaz a csomag

A JSON kulcsrendezése kanonikus, az időbélyeg a csomagba **bemenetként** érkezik
(nem `DateTime.now()` a writer belsejében) — különben a teszt nem mérhető.

### 5.4 A törlés tényleges

Törlés után sem a WAV, sem az annotáció, sem a manifest nem marad vissza; a
writer törlő ága a fájlrendszert méri, nem egy flaget állít.

### 5.5 Séma-verzió kötelező

`schemaVersion` a csomag gyökerében; ismeretlen verzió olvasásakor **típusos
hiba**, nem néma default (ADR 0054 mintája).

## 6. Acceptance criteria

1. `LabTask` felsorolja a SDD hat feladat-családját (csend, zaj, egyes akkord,
   lassú down/up, váltott pengetés, gyors pattern), és a lista hossza a
   **15–20** tartományban van: a teszt a hármas cellát méri — **14 → hiba**,
   **15 → elfogadott (inkluzív alsó határ)**, **21 → hiba**.
2. `LabCapturePackage` JSON round-trip veszteségmentes, és kétszer ugyanabból a
   bemenetből **bájtra azonos** kimenet.
3. Consent nélkül az export-hívás nem fordul (típushiba) — a teszt a
   `granted`/`revoked`/`unknown` hármas mátrixot méri.
4. A csomag semmilyen ágon nem tartalmazza a tiltott mezőneveket (teszt egy
   tiltólistával grepeli a szerializált JSON-t).
5. Törlés után a csomag könyvtára nem létezik, és a writer `missing` státuszt ad.
6. Ismeretlen `schemaVersion` olvasása típusos hibát ad, nem `null`-t.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A writer belsejében `DateTime.now()` | 2. pont bájtra-azonos cellája |
| A consent bool paraméter `?? false`-szal | 3. pont `unknown` cellája |
| Az eszköz-metadata beteszi a hirdetési azonosítót | 4. pont tiltólista-cellája |
| A törlés csak flaget állít | 5. pont könyvtár-létezés cellája |
| Ismeretlen séma-verzió → default | 6. pont típusos-hiba cellája |
| A feladatlista 14 elemű | 1. pont **14 → hiba** cellája |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/accuracy_lab
```

Külön processzben futó `format` → `analyze` → célzott teszt → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge
Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: a determinizmus-cella a kanonikus kulcsrendezés
ideiglenes kikapcsolásával **PIROS**, visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. `LabTask` + a feladatlista, teszttel.
2. `LabConsent` és a típusos kapu.
3. `LabCapturePackage` + séma-verzió + round-trip teszt.
4. `LabPackageWriter` (írás, checksum, törlés) + tesztek.
5. `public.dart` additív export.

## 9. Kockázatok

- **Fájlrendszer a tesztben:** a writer-teszt ideiglenes könyvtárat használjon,
  soha a valódi app-dokumentumkönyvtárat (a CI-n nincs).
- **Scope-csúszás a UI felé:** a §0.0 tiltja; felület-igény esetén `stopped`.
- **A `clip_recorder.dart` átírásának kísértése:** tilos zóna, a felvevő
  változatlan marad.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
