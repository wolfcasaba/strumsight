# E14-R06 — Accuracy Lab és engedélyezett adatgyűjtés

- **Státusz:** READY (pre-flight lefutott 2026-09-04, kód újramérve: `main @ 5dcff18e`;
  előre megírva 2026-08-20, `main @ b0979855`)
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

### 0.0.1 Pre-flight revíziók (2026-09-04, `main @ 5dcff18e`) — MÉRT állítások

Az alábbiak a MAI fán mértek, és **felülírják** a brief régebbi szövegének
minden ellentmondó részletét. Forrásuk az ADR
[`0358`](../adr/0358-consented-on-device-lab-capture-package.md) kontextus-szakasza.

**R1 — ADR-szám: `0358` marad.** A `tools/round-slots.py reserve-adr --round E14-R06`
a globális számlálóból `0504`-et adott (a lemezen a legnagyobb ADR `0503`), a
queue-sor és a brief viszont a Chapter 14 előre kiosztott blokkjából `0358`-at
rendel ehhez a körhöz (`E14-R07…R09` = `0359…0361`). A `0358` a lemezen
**szabad** (`docs/adr/0358-*` → nincs találat), az egyediség-őr
(`tools/tests/test_adr_numbering.py`) pedig kizárólag ütközést és névalakot mér,
folytonosságot nem — így a queue-koordináció a döntő. A `0504` foglalása
megmarad (nem használjuk), és a pre-flight a `0358`-ra is markert írt, hogy egy
párhuzamos kör se kaphassa meg.

**R2 — A feladatlista-tartományt futtatható validáció mérje (ADR 0358 D6).**
A §6/1 „14 → hiba / 15 → elfogadott / 21 → hiba” cellahármas **csak akkor
írható meg**, ha a 15–20 tartományt egy tetszőleges listát fogadó validáció
kényszeríti ki, nem egy `const` lista hossza. Elvárt alak (a név szabadon
választható, de a szemantika kötött):

```dart
// tetszőleges listára fut, tehát a 14/15/21 cella megírható:
LabTaskCatalog.validated(List<LabTask> tasks)   // tartományon kívül → típusos hiba
LabTaskCatalog.standard()                       // a szállított katalógus, maga is validált
```

A szállított katalógus lefedi a hat feladat-családot, és a hossza a
tartományban van.

**R3 — A 4. acceptance-pont mércéje ALLOWLIST + érték-oldali kanári, nem
tiltólista (ADR 0358 D2, forrás: [`docs/LESSONS.md`](../LESSONS.md) L260).**
Egy fix kulcskészletű DTO fölött a `forbiddenKeys.any(json.contains)` alakú
teszt **konstrukció szerint mindig zöld**. A kötelező cella ezért: a
szerializált JSON rekurzívan összegyűjtött kulcshalmaza **EGYENLŐ** a
dokumentált megengedett halmazzal. Emellé jön egy kanári-cella: a bemenetbe
tett egyedi minta (pl. eszköznévbe ágyazott token) a kimenetben **csak** azon
az egy mezőn jelenhet meg, ahová szánták.

**R4 — Nincs újrahasználható WAV-kódoló, a kör a sajátját írja (ADR 0358 D8).**
`lib/features/learn/audio/wav.dart` és `lib/features/analyze/engine/wav_decoder.dart`
LÉTEZIK, de egyik feature `public.dart`-ja sem exportálja
(`grep -rn "wav" lib/features/*/public.dart` → nulla), a cross-feature import
pedig csak barrelt célozhat (`tool/check_architecture.dart:774`). A PCM → WAV
bájtsorozat tehát a `lab_package_writer.dart`-ban, `dart:typed_data` fölött
készül. Idegen barrel bővítése tilos zóna → `stopped`.

**R5 — Nulla kimenő csatorna és nulla plugin-hívás (ADR 0358 D7).** A diff nem
használhat `share_plus`-t (a fán VAN: `pubspec.yaml:39`), Diót, `ApiClient`-et,
`HttpClient`-et, `package:http`-t és `path_provider`-t. Mért ok: ezek a minták
aktiválják a `tool/check_data_inventory.dart` egress-felderítését
(`:371-438`), ami `docs/privacy/data-inventory.yaml` bejegyzést követelne — az
pedig ennek a körnek a TILOS zónájában van. A writer a cél-könyvtárat
**`Directory` paraméterként** kapja, így a teszt ideiglenes könyvtárban mér.

**R6 — A `public.dart` KÉZZEL írott, generátor nem előfeltétel.** A generált
barrel-frissesség őre (`tool/check_architecture.dart:798`) csak azokra a
feature-ökre fut, amelyeknek van `lib/features/<f>/public/` fragment-könyvtára
(`tool/gen_public_barrel.dart:182-199`). Az `accuracy_lab` **nem** hoz létre
ilyet — ne is hozzon, mert az a barrel-generátor futtatását tenné
előfeltétellé.

**R7 — A consent-mintát ÚJRAHASZNOSÍTJUK, nem importáljuk.** A
`tutor_privacy_providers.dart` + `domain/models/tutor_consent.dart`
tengelyenkénti grant/revoke másoló metódusai a követett minta (ADR 0132), de az
ai_tutor barrelje nem exportálja a consent modellt, tehát az import
architektúra-sértés lenne. A `LabConsent` önálló, a kör saját fájljában.

**R8 — A §7 gate-parancs tételesen tükrözi a `gate_tests` listát**
(brief-lint **S12** lelet, `.pipeline/brief-lint-E14-R06.md`). Javítva a §7-ben.

**R9 — Determinizmus-eszközök a fán: `crypto: ^3.0.7` deklarált**
(`pubspec.yaml:46`), tehát a checksumhoz nincs szükség új függőségre — és nem
is vehető fel, a `pubspec.yaml` tilos zóna. Az időbélyeg **bemenet**, a
kulcsrendezés kanonikus (ADR 0358 D3).

**R10 — Párhuzamos kör fut (`E14-R03`, PR #566).** A fájlhalmazok diszjunktak
(`lib/features/live/**` vs. `lib/features/accuracy_lab/**`), de a záró
rituálék és a merge a merge-záron át mennek (prompt §4.1). Az `E14-R03`
ágához, PR-jéhez és munkapéldányához hozzányúlni tilos.

**R11 — A `LabTask` típusnév szabad.** `grep -rn "class Lab…" lib/ test/` →
nulla találat a `LabTask`, `LabConsent`, `LabCapturePackage`,
`LabPackageWriter` nevekre: nincs S5-ütközés a fán.

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

**Pre-flight visszakeresés (2026-09-04, `node tools/knowledge-rag.mjs`, előbb
szűkítve `--corpus lessons,halts,adr`, utána teljes korpuszon):**

- [`lessons/L260`](../LESSONS.md) — a kulcsnév-tiltólistás redakciós teszt
  konstrukció szerint vakon zöld marad; a szivárgás az ÉRTÉK-oldalon van.
  Ez alakította a §6/4 acceptance-pontot (allowlist + kanári, §0.0/R3).
- [`adr/0178`](../adr/0178-vision-privacy-by-default.md) — kimondja, hogy „a Lab
  capture consent-flow, redakció és tárolási határidő külön kör felelőssége”;
  ez a kör az az adat-magra nézve.
- [`adr/0249`](../adr/0249-analysis-evaluation-dataset-governance.md) — nyers
  felvétel nem kerül a repóba, a determinisztikus artefaktum bájtazonos.
- [`lessons/L161`](../LESSONS.md) — egy helyesen unit-tesztelt helper hazudhat:
  a bizonyíték a tényleges hívási lánc. A consent-kapu cellái ezért a
  csomagot kiadó ÚTON mérnek, nem egy izolált predikátumon.

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
4. A csomag kulcskészlete ZÁRT: a szerializált JSON rekurzívan összegyűjtött
   kulcshalmaza **egyenlő** a dokumentált megengedett halmazzal (allowlist-cella),
   és egy érték-oldali kanári-cella igazolja, hogy a bemenetbe tett egyedi minta
   csak a saját mezőjében jelenik meg (§0.0/R3, L260 — a puszta tiltólista-teszt
   konstrukció szerint vakon zöld).
5. Törlés után a csomag könyvtára nem létezik, és a writer `missing` státuszt ad.
6. Ismeretlen `schemaVersion` olvasása típusos hibát ad, nem `null`-t.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A writer belsejében `DateTime.now()` | 2. pont bájtra-azonos cellája |
| A consent bool paraméter `?? false`-szal | 3. pont `unknown` cellája |
| Az eszköz-metadata beteszi a hirdetési azonosítót | 4. pont **allowlist**-cellája (a kulcshalmaz-egyenlőség sérül) |
| A metadata egy megengedett mező ÉRTÉKÉBE szivárogtat azonosítót | 4. pont kanári-cellája |
| A feladatlista-tartomány `const` lista hosszában él, nem validációban | 1. pont 21-elemű cellája (nem megírható → hiányzó mérce) |
| A törlés csak flaget állít | 5. pont könyvtár-létezés cellája |
| Ismeretlen séma-verzió → default | 6. pont típusos-hiba cellája |
| A feladatlista 14 elemű | 1. pont **14 → hiba** cellája |

## 7. Kötelező ellenőrzések

```
tools/round-gate.sh test/features/accuracy_lab/lab_capture_package_test.dart test/features/accuracy_lab/lab_package_writer_test.dart test/features/accuracy_lab/lab_consent_test.dart test/features/accuracy_lab
```

(A parancs tételesen tükrözi a `gate_tests` listát — brief-lint **S12**,
§0.0/R8. A `test/features/accuracy_lab` záró útvonal a könyvtár egészét is
megméri, ha a kör további tesztfájlt tenne bele.)

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

**Implementer motor:** `sonnet-impl` (Claude Sonnet 5). **Státusz:** kész, a
kör gate-je zöld.

### 10.1 Mit épített a kör

- `lib/features/accuracy_lab/domain/lab_task.dart` — `LabTaskFamily` (6 tag),
  `LabTask`, `LabTaskRangeException`, `LabTaskCatalog.validated(List<LabTask>)`
  (futtatható 15–20 tartomány-ellenőrzés tetszőleges listára) +
  `LabTaskCatalog.standard()` (16 elem, mind a hat család lefedve).
- `lib/features/accuracy_lab/domain/lab_consent.dart` — `sealed LabConsent`,
  `LabConsentGranted`/`LabConsentRevoked`/`LabConsentUnknown`.
- `lib/features/accuracy_lab/domain/lab_capture_package.dart` —
  `LabDeviceMetadata`, `LabCaptureEvent`, `LabCapturePackage` (`toJson`/
  `fromJson`, `schemaVersion` const = 1, `LabCapturePackageSchemaVersionException`),
  `canonicalJsonEncode` (rekurzív kulcsrendezés).
- `lib/features/accuracy_lab/data/lab_package_writer.dart` — `LabPackageWriter`
  (`write`/`status`/`delete`), saját `dart:typed_data` PCM→WAV kódoló (ADR
  0358 D8), `package:crypto` SHA-256 checksum a manifestben. A `write` hívás
  `consent` paramétere `LabConsentGranted` típusú — a gate a típusban él (D1).
- `lib/features/accuracy_lab/public.dart` — kézzel írott, additív barrel.

### 10.2 Gate — a tényleges kimenet

```
tools/round-gate.sh test/features/accuracy_lab/lab_capture_package_test.dart test/features/accuracy_lab/lab_package_writer_test.dart test/features/accuracy_lab/lab_consent_test.dart test/features/accuracy_lab
```

```
    → [1] format: ZÖLD
    → [2] analyze: ZÖLD          (Analyzing 3 items... No issues found!)
    → [3] test lab_capture_package_test.dart: ZÖLD   (+10 tests)
    → [4] test lab_package_writer_test.dart: ZÖLD    (+6 tests)
    → [5] test lab_consent_test.dart: ZÖLD           (+3 tests)
    → [6] test test/features/accuracy_lab: ZÖLD      (+19 tests, egyben)
    → [7] architecture: ZÖLD     (12 allowlistelt deviáció, változatlan)
    → [8] secrets: ZÖLD          (4315 fájl, 0 lelet)
    → [9] l10n: ZÖLD

MINDEN GATE ZÖLD.
```

### 10.3 Falszifikációs bizonyíték (§7.1)

**Determinizmus-cella (D3).** `lab_capture_package.dart`,
`_writeCanonical`-ban a `..sort()` ideiglenes eltávolítása (a kulcsrendezés
kikapcsolása) után:

```
$ flutter test test/features/accuracy_lab/lab_capture_package_test.dart \
    --plain-name "canonical encoding is independent of source key order"
...
00:00 +0 -1: ... canonical encoding is independent of source key order [E]
  Expected: '{"schemaVersion":1,"packageId":"pkg-001",...}'
    Actual: '{"events":[...],"device":{"appVersion":...},...,"schemaVersion":1}'
     Which: is different.
Some tests failed.
```

→ **PIROS.** A `..sort()` visszaállítása után a teljes gate (fenti 10.2)
újra zöld — a `git diff` a visszaállított fájlra üres (bájtra az eredeti).

**Allowlist-cella (D2, L260).** `lab_capture_package.dart`,
`LabDeviceMetadata.toJson()`-ba ideiglenesen felvéve egy
`'advertisingId': 'temp-falsification-probe'` bejegyzés:

```
$ flutter test test/features/accuracy_lab/lab_capture_package_test.dart \
    --plain-name "serialized keyset equals the documented allowlist"
...
00:00 +0 -1: ... serialized keyset equals the documented allowlist [E]
  Expected: Set:[schemaVersion, packageId, ..., endSeconds]   (15 kulcs)
    Actual: Set:[..., advertisingId, ...]                     (16 kulcs)
     Which: larger than expected
Some tests failed.
```

→ **PIROS.** A sor eltávolítása után a teljes gate újra zöld — a `git diff`
a visszaállított fájlra üres.

### 10.4 Scope

A diff kizárólag a brief `allowed_paths` listáján szereplő 9 fájlt érinti (5
production + 3 teszt + ez a dokumentum). Nem nyúlt a `pubspec.yaml`-hoz, a
`clip_recorder.dart`-hoz, idegen feature barreljéhez, sem hálózati/plugin
csatornát nyitó csomaghoz (`share_plus`, `Dio`, `http`, `path_provider`) —
ezeket egyik fájl sem importálja.

### 10.5 Javító kör (fix1) — a review 2 MAJOR + 2 MINOR leletének zárása

**MAJOR-1 — path traversal (`lab_package_writer.dart:52` körül).**
`lib/features/accuracy_lab/data/lab_package_writer.dart:12-26` új, exportált
`labPackageIdPattern` (`^[A-Za-z0-9_-]+$`) és `LabPackageIdException`; a
`locate()` (`:76-78`, korábban `:48-52`) a `packageId`-t e minta ellen
ellenőrzi, MIELŐTT bármi `Directory`/`File` objektumot épít belőle, és
sértésnél a típusos kivételt dobja. A `write`/`status`/`delete` mindhárom a
`locate()`-en keresztül fut, tehát a védelem mindhármukra átöröklődik — nem
csak egy belépési pontot fed.

Új cella (`test/features/accuracy_lab/lab_package_writer_test.dart`, `„LabPackageWriter — packageId path-traversal rejection (MAJOR-1)"` csoport,
7 teszt): `".."`, üres id, `"a/b"` mind a `locate`/`status`/`delete`-en,
plusz egy `write`-próba, ami egy VALÓDI testvérkönyvtárat hoz létre
(`Directory.systemTemp.createTempSync`) és `packageId: '../$victimName'`
mellett hívja a `write`-ot — a teszt igazolja, hogy a testvérkönyvtár és a
benne lévő fájl a hívás után is érintetlen marad.

*Régi kódon piros — mért próba:* a fix előtti `lib/` állapotra (a
mostani commit `HEAD`-je, azaz a review által vizsgált kód) visszaállítva a
teljes `lab_package_writer_test.dart` és `lab_capture_package_test.dart` NEM
fordul (a két fájl az új `LabPackageIdException`/`LabTaskDuplicateIdException`
típusokra hivatkozik, amik a régi `lib/`-ben nem léteznek):

```
test/features/accuracy_lab/lab_package_writer_test.dart:161:21: Error:
  'LabPackageIdException' isn't a type.
test/features/accuracy_lab/lab_capture_package_test.dart:42:23: Error:
  'LabTaskDuplicateIdException' isn't a type.
00:00 +0 -2: Some tests failed.
```

Ez önmagában PIROS bizonyíték: a régi implementáció ténylegesen hiányzik a
védelem. A fix visszaállítása után (a jelen commit `lib/` állapota) a 10.2
gate teljes egésze zöld — l. alant.

**MAJOR-2 — a `write()` sosem olvasta a `consent` paramétert
(`lab_package_writer.dart:89-93` körül).** A manifest összeállítása
(jelenlegi `:113-121`) most a `'consentVersion': consent.consentVersion`
kulccsal FELÜLÍRJA a `package.toJson()`-ből örökölt mezőt — a `consent` (a
ténylegesen megadott grant) az egyetlen forrás, a hívó által összerakott
`package.consentVersion` a manifestben már nem jelenhet meg eltérő értékkel.

Új cella (`lab_package_writer_test.dart`, „the manifest consentVersion
reflects the actual consent grant, even when package.consentVersion
disagrees"): `consent = LabConsentGranted(consentVersion: 'consent-v2-2026')`,
`package.consentVersion = 'v1-stale'` → `manifest['consentVersion']` ==
`'consent-v2-2026'`.

*Régi kódon piros — mért próba* (a fix előtti `lab_package_writer.dart`-ra
visszaállítva, de a teszt-fájlból csak ezt az egy cellát futtatva, mivel a
traversal-csoport a fenti típushiány miatt a fájlt egyben nem fordítja):

```
LabPackageWriter — write/checksum/delete (ADR 0358 D3/D4) the manifest
consentVersion reflects the actual consent grant, even when
package.consentVersion disagrees [E]
  Expected: 'consent-v2-2026'
    Actual: 'v1-stale'
Some tests failed.
```

A fix visszaállítása után a cella zöld (l. 10.2 gate).

**MINOR-1 — path-szerű `packageId` a kimenetben.** A MAJOR-1 validációja
lezárja: mivel a `packageId` most `labPackageIdPattern`-nek megfelel (nincs
`/`, `\`, `.`), a manifestbe és az annotációba írt `packageId` mező (D2 zárt
kulcskészlet oldaláról) soha nem hordozhat útvonal-darabot — a
`lab_capture_package_test.dart` „closed keyset” csoportja (10.2 gate, +9/+10.
teszt) változatlanul zöld marad, tehát a kulcshalmaz nem bővült.

**MINOR-2 — doc-comment `unique within its catalog` teszttel nem
bizonyítva.** `lib/features/accuracy_lab/domain/lab_task.dart` — új
`LabTaskDuplicateIdException` + a `LabTaskCatalog.validated()` (`:57-68`)
most egy `Set<String>`-tel figyeli az ismétlődő id-t és dob, mielőtt a
listát visszaadná; a doc-comment állítása (`:19`, „Stable identifier, unique
within its catalog") ezzel valódi kényszerré vált.

Új cella (`lab_capture_package_test.dart`, „a duplicate task id within an
otherwise valid-length list is rejected"): 15 elemű lista, ahol az utolsó
elem id-je megegyezik az első eleméével → `LabTaskDuplicateIdException`.

*Régi kódon piros:* l. a MAJOR-1 alatt idézett compile-hiba — ugyanaz a fájl
(`lab_capture_package_test.dart`) nem fordul a régi `lib/` ellen, mert a
`LabTaskDuplicateIdException` típus nem létezik.

**A teljes gate a fix után (10.2-vel megegyező parancs, újrafuttatva):**

```
    → [1] format: ZÖLD
    → [2] analyze: ZÖLD          (Analyzing 3 items... No issues found!)
    → [3] test lab_capture_package_test.dart: ZÖLD   (+11 tests, +1 az eredetihez képest)
    → [4] test lab_package_writer_test.dart: ZÖLD    (+14 tests, +8 az eredetihez képest)
    → [5] test lab_consent_test.dart: ZÖLD           (+3 tests, változatlan)
    → [6] test test/features/accuracy_lab: ZÖLD      (+28 tests, egyben)
    → [7] architecture: ZÖLD     (12 allowlistelt deviáció, változatlan)
    → [8] secrets: ZÖLD          (4317 fájl, 0 lelet)
    → [9] l10n: ZÖLD

MINDEN GATE ZÖLD.
```

A javító kör nem lazított és nem törölt egy korábbi cellát sem — mind a 19
eredeti teszt és a 9 új (7 traversal + 1 consent-provenance + 1 duplicate-id)
zöld.

## 11. Review — a Claude tölti ki
