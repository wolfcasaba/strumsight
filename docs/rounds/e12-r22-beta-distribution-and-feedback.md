# E12-R22 — Beta distribution, tester enrollment és feedback

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 22
- **Kör-azonosító:** `E12-R22`
- **Branch:** `<motor>/e12-r22-beta-distribution-and-feedback`
- **Előfeltétel:** `E12-R06` és `E12-R17` merge-elve (release-notes generálás a manifestből; a consent-határ a data-inventoryból)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** ~~`ADR 0461`~~ → **`ADR 0486`** (a §0.0.A pre-flight revízió szerint: a
  foglaló `tools/round-slots.py reserve-adr --round E12-R22` 2026-09-01-én `0486`-ot adott; a queue
  batch-előjegyzése elavult). A megírt ADR:
  [`docs/adr/0486-beta-distribution-consent-and-redacted-diagnostics-bundle.md`](../adr/0486-beta-distribution-consent-and-redacted-diagnostics-bundle.md).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "beta distribution tester consent feedback diagnostics bundle redaction"` → a `halts/round-status-E08-R20` és `E09-R14` merge-elt körök (diagnosztikai és média-consent minták). A MÉRT precedens a fán a Lab-diagnosztika: opt-in, token mögött, méret-korlátos WAV-melléklettel.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/diagnostics/data/diagnostics_uploader.dart` MÉRT korlátait (`maxWavBytes = 5 * 1024 * 1024`, egyszeri POST diagnosztikai tokennel, decimálás a méret-korlát alá) és a `.github/workflows/lab-apk.yml` fejlécének figyelmeztetését (a Lab-token eldobható spam-gate, NEM felhasználói adatot védő titok).

## 0.0 Miért nincs ÚJ feedback-képernyő ebben a körben

A SDD Kör 22 `lib/features/feedback/` felületet is kér. A felületek tulajdonosa a Chapter 13 sáv, és a `test/ui/ui_inventory_test.dart` EGZAKT képernyőszámot pinnel — egy új képernyő itt a Full Gate-et mozdítaná el, miközben a design-rendszer szerinti kivitelezés nem ennek a körnek a kompetenciája. A kör ezért a **csatornát és a csomagot** szállítja (redaktált diagnosztikai bundle, consent-szöveg, terjesztési eljárás, release-notes generálás), a felhasználói felület pedig NEVESÍTETT hiányként megy tovább a Chapter 13 pótkörébe.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "docs/beta/enrollment.md",
  "docs/beta/tester-consent.md",
  "docs/beta/feedback-triage.md",
  "tool/release/generate_beta_notes.py",
  "tool/release/build_diagnostics_bundle.py",
  "test/tooling/beta_release_notes_test.dart",
  "backend/tests/test_diagnostics_redaction.py",
  "docs/rounds/e12-r22-beta-distribution-and-feedback.md",
]
gate_tests = [
  "test/tooling/beta_release_notes_test.dart",
  "test/tooling/diagnostics_storage_separation_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a kör a felhasználói diagnosztikai adat útját érinti (bundle-tartalom, redakció, melléklet-consent) — egy hiányos redakció token vagy e-mail kiszivárgását jelentené. A `security-reviewer` futtatása a review-ban KÖTELEZŐ.

## 0.0.A Pre-flight revízió — MÉRT tények (Claude, 2026-09-01, `main @ 1f09d56c`)

A brief 2026-08-27-én készült (`main @ 9ca4a0dc`). Az indítás előtti mérés a következőket
erősítette meg / írta felül. **Ami itt áll, az erősebb a brief korábbi szövegénél.**

### R1 — Az ADR száma `0486`, nem `0461`

`tools/round-slots.py reserve-adr --round E12-R22` → **`0486`**. A lemezen a legmagasabb szám
`0485` (E12-R21), és `0461`-es fájl nem létezik. Ugyanaz a minta, mint az E12-R21-nél
(előjegyzés `0460`, tényleges `0485`). A §5 kötött döntései tehát az
[ADR 0486](../adr/0486-beta-distribution-consent-and-redacted-diagnostics-bundle.md)
D1–D7 pontjai. **Az ADR-t a Claude MEGÍRTA a pre-flightban — az implementer nem nyúl a
`docs/adr/**`-hoz.**

### R2 — Mért állandók és kulcsok, amiket az implementer NEM talál ki

| Mért érték | Forrás |
|---|---|
| `maxWavBytes = 5 * 1024 * 1024` = **5 242 880** bájt, a határ INKLUZÍV | `lib/features/diagnostics/data/diagnostics_uploader.dart:40` |
| A backend a feltöltést **verbatim bájtként** tárolja, nem transzformál | `backend/app/routers/diagnostics.py` (fejléc + `_unique_session_path`) |
| Release-manifest kulcsok (a béta-jegyzet BEMENETE): `schemaVersion`, `app.{version,buildNumber,shortSha,channel}`, `modelPackage.{schemaVersion,manifestSha256,modelCount}`, `knowledgePackage.{schemaVersion,manifestSha256,documentCount}`, `artifacts[].{name,path,sha256}` | `tool/generate_release_manifest.dart:206-272` |
| Commitolt release-manifest JSON **nincs** — futásidőben áll elő, tehát a teszt FIXTURE manifestet ír `Directory.systemTemp`-be | `git ls-files` |
| `leaves_device: true` mezőt tartó útvonalak: `account_api` (6 mező), `diagnostics_upload` (3), `share_export` (3). A `tutor_stream` és `community_media` mezői `false`-ok; az öt `rides:` sor mező nélküli | `docs/privacy/data-inventory.yaml` |

### R3 — Szállított minták, amiket követni KELL (ne írj újat)

- **Dart tooling-teszt Python eszközre:** `test/tooling/ai_release_report_test.dart` és
  `release_manifest_test.dart` `python3`-ra shell-el, fixture-fát `Directory.systemTemp`-be ír, és
  `tearDown`-ban bont. A `python3` az EGYETLEN külső bináris, amit a
  `test/tooling/beta_release_notes_test.dart` meghívhat; `skip:` ág SEHOL nincs benne.
- **Backend pytest a `tool/release/*.py`-ra:** `backend/tests/test_security_release.py`
  `importlib.util.spec_from_file_location` + `sys.modules[spec.name] = module` mintával tölti be a
  modult (a `from __future__ import annotations` miatt a regisztráció a `exec_module` ELŐTT
  kötelező). A `backend/tests/test_diagnostics_redaction.py` ezt a mintát használja.
- **Leltár-parszolás:** `test/tooling/beta_release_notes_test.dart` a szállított
  `tool/check_data_inventory.dart` `DataInventory.parseFile`-ját IMPORTÁLJA
  (`import '../../tool/check_data_inventory.dart';`, ahogy `data_inventory_test.dart` teszi) —
  második YAML-parszert írni tilos (ADR 0486 D6).
- **Fixture-fa nincs commitolva:** a `test/fixtures/**` NEM engedélyezett útvonal, tehát minden
  fixture futásidőben, temp-könyvtárban keletkezik.

### R4 — A `beta_release_notes_test.dart` a kör EGYETLEN Dart teszt-fájlja

A név a Kör 6-os elnevezést örökli, de a fájl MINDKÉT Python eszköz celláit hordozza
(`build_diagnostics_bundle.py` ÉS `generate_beta_notes.py`), plusz a §6 A6 dokumentum-celláját. Ez
nem tévedés: az engedélyezett-fájllista egyetlen új Dart teszt-fájlt ad, és a lista **szűkíthető,
nem tágítható**.

### R5 — A `--consent-*` kapcsolók pontos szerződése (ADR 0486 D1)

Az A4 cella nem „valamilyen" consent-ellenőrzést mér, hanem ezt a négy bemenet/kimenet párt:

| Bemenet | Elvárt |
|---|---|
| se `--consent-diagnostics`, se `--consent-raw-audio` | exit ≠ 0, **kimeneti fájl nem jön létre** |
| csak `--consent-diagnostics` | exit 0, csomag hang NÉLKÜL |
| csak `--consent-raw-audio` | exit ≠ 0 (a hang-consent önmagában nem jogosít) |
| `--consent-diagnostics --consent-raw-audio` | exit 0, csomag a hang-melléklettel |

### R6 — Az A6 kereszt-ellenőrzés pontos alakja (ADR 0486 D6)

A `docs/beta/tester-consent.md` egy gépi blokkot tart:

```text
<!-- data-inventory-crosscheck:begin -->
| route | field |
|---|---|
| diagnostics_upload | ml_dsp_comparison_events (tSec, mlChord, dspChord, agree, mlConf, dspConf, strumDir, bpm, inputLevel) |
…
<!-- data-inventory-crosscheck:end -->
```

A `field` cella a leltár `name:` értékének **szó szerinti** másolata. A teszt KÉTIRÁNYBAN mér:
minden `leaves_device: true` mezőhöz kell dokumentum-sor (hiány → piros), és minden dokumentum-sor
mögött kell leltár-mező (kitalált sor → piros). A blokk a leltár HÁROM ilyen útvonalát fedi le
(`account_api`, `diagnostics_upload`, `share_export`), nem csak a diagnosztikait — a tesztelő a
teljes app-ot használja.

### R7 — Redakció: négy osztály, rekurzívan (ADR 0486 D2)

token · e-mail · abszolút fájl-útvonal · eszköz-azonosító (`deviceId`, `device_id`, `androidId`,
`installId`, `udid`). Az e-mail BÁRMELY sztringértékben, nem csak `email` nevű kulcsban. A
`device_metadata` platform-sztringje (`appVersion`, `device`) **marad** — a leltár szerint a
build-korreláció a célja. Helyettesítő: állandó `[REDACTED:token|email|path|device-id]`, só és hash
nélkül (a determinizmus ezen áll).

### R8 — Amit ez a kör NEM előlegez meg

Az [E12-R25](e12-r25-release-candidate-assembly.md) RC-workflow-ja (`beta-release.yml`) és az
[E12-R27](e12-r27-closed-beta-launch-and-monitoring.md) cohort-profilja
(`docs/beta/cohort-profiles.yaml`, `tool/release/verify_beta_profile.py`) **más körök tulajdona** —
sem fájlt, sem sémát ne hozz létre hozzájuk. A `docs/beta/enrollment.md` a cohort-fogalmat
PRÓZÁBAN írja le, gépi profil-fájl nélkül.

### R9 — Visszakeresés (ADR 0312)

`node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "beta distribution tester consent
feedback diagnostics bundle redaction"` → `halts/E08-R20`, `E09-R14` (rétegzett consent és
diagnosztikai minták, mindkettő merge-elt). `--corpus lessons,halts --top 5 "redaction masking
secret leak python generator deterministic byte-identical output"` → **[L394](../LESSONS.md#l394)**
(friss klónban a generált l10n első gate-je átmenetileg stale lehet — a változatlan-HEAD ismétlés
diagnosztikai bizonyíték, nem product-fix; a `tools/prepare-flutter-generated.sh` a klón után
KÖTELEZŐ) és [L92](../LESSONS.md#l92) (determinisztikus generátor-precondition). Teljes korpuszon a
saját brief és az SDD Ch12 „Fő érintett fájlok" blokkja jött vissza — új korlát nem került elő.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a munkához ÚJ képernyő (`lib/features/**`) kellene, a kimenet a `stopped` jelzés — a §0.0 szerint az a Chapter 13 sáv dolga.

## 1. Cél

Kontrollált béta-terjesztés, tájékozott tesztelői hozzájárulás és redaktált, reprodukálható visszajelzés-csomag — nyers hang kizárólag külön, explicit hozzájárulással.

## 2. Jelenlegi állapot — mért tények

- `lib/features/diagnostics/`: `diagnostics_uploader.dart` (opt-in, `maxWavBytes = 5 MiB`, egyszeri POST diagnosztikai tokennel), `diagnostics_providers.dart`, `diagnostics_panel.dart`.
- `backend/app/routers/diagnostics.py` + `backend/tests/test_diagnostics.py` **létezik**; `test/tooling/diagnostics_storage_separation_test.dart` a kliens-oldali elkülönítés őre.
- `.github/workflows/lab-apk.yml` (41 sor) MÁR épít Lab-buildet `lab_build.json`-ból; `beta-release.yml` **nincs**.
- `docs/beta/` **nem létezik**; release-notes generátor **nincs** (a Kör 6 release-manifestje viszont a bemenete lesz).
- `test/ui/ui_inventory_test.dart` egzakt képernyőszámot pinnel — ez a kör NEM mozdítja el.

## 3. Scope

**Benne van:** `docs/beta/enrollment.md` (csatorna, cohort, beléptetés, visszavonás, verzió-kényszerítés) · `docs/beta/tester-consent.md` (MIT gyűjtünk, MIT nem, hogyan vonható vissza — a Kör 17 data-inventory alapján) · `docs/beta/feedback-triage.md` (kategóriák, súlyosság, válaszidő) · `tool/release/generate_beta_notes.py` (a Kör 6 release-manifestjéből determinisztikus béta-jegyzet) · `tool/release/build_diagnostics_bundle.py` (redaktált csomag: token, e-mail, útvonal, eszköz-azonosító maszkolva; a NYERS hang KÜLÖN melléklet, alapból KIHAGYVA; méret-korlát a MÉRT 5 MiB-hez igazítva) · `test/tooling/beta_release_notes_test.dart` · `backend/tests/test_diagnostics_redaction.py`.

**NINCS benne (tilos):**

- ÚJ képernyő vagy `lib/**` módosítás.
- ÚJ CI-workflow (`beta-release.yml`) — a Kör 25 RC-workflow-jával együtt jön.
- Valódi tesztelői adat vagy valódi token a fixture-ökben.
- `docs/adr/**` — az ADR **0486**-ot a Claude MÁR megírta a pre-flightban (§0.0.A R1).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/beta/enrollment.md` | ÚJ — terjesztés és beléptetés |
| `docs/beta/tester-consent.md` | ÚJ — tájékoztató és hozzájárulás |
| `docs/beta/feedback-triage.md` | ÚJ — triage-eljárás |
| `tool/release/generate_beta_notes.py` | ÚJ — béta-jegyzet a manifestből |
| `tool/release/build_diagnostics_bundle.py` | ÚJ — redaktált csomag |
| `test/tooling/beta_release_notes_test.dart` | a kliens-oldali §6 cellák |
| `backend/tests/test_diagnostics_redaction.py` | a backend-oldali §6 cellák |

**Tilos zóna:** `lib/**` · `.github/**` · `lab_build.json` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0486 — a teljes szöveg a D1–D7 pontokban)

### 5.1 A nyers hang KÜLÖN, kikapcsolt alapértelmezésű melléklet

A bundle alapból metaadatot és feature-értékeket visz, hangot nem. **NEM elfogadható gyengítés:** „úgyis opt-in az egész Lab mód, tehát a hang is mehet" — a MÉRT precedens (ADR 0132/0247 mintája) a rétegzett hozzájárulás.

### 5.2 A redakció a csomag ÖSSZEÁLLÍTÁSAKOR történik, nem a szerveren

Titok nem kerül a csomagba, tehát a szerverre sem. **NEM elfogadható gyengítés:** szerver-oldali „majd ott maszkoljuk" ág.

### 5.3 A béta-jegyzet determinisztikus és a manifesthez kötött

**NEM elfogadható gyengítés:** kézzel szerkesztett jegyzet build-azonosító nélkül.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A bundle alapértelmezésben NEM tartalmaz nyers hangot | `beta_release_notes_test.dart` |
| A2 | Token, e-mail és fájl-útvonal maszkolva kerül a bundle-be | `beta_release_notes_test.dart` + `test_diagnostics_redaction.py` |
| A3 | Méret-korlát fölötti melléklet elutasított (nem csendben csonkolt) | `beta_release_notes_test.dart` |
| A4 | A §0.0.A R5 NÉGY consent-bemenete pontosan a táblázat szerinti kimenetet adja; hozzájárulás nélkül kimeneti fájl SEM keletkezik | `beta_release_notes_test.dart` |
| A5 | A béta-jegyzet kétszeri generálása bájtazonos, tartalmazza az `app.version` + `app.buildNumber` + `app.shortSha` hármast és a `app.channel`-t; hiányzó kötelező manifest-kulcsra nem-nulla kilépés | `beta_release_notes_test.dart` |
| A6 | A `tester-consent.md` gépi blokkja KÉTIRÁNYBAN egyezik a Kör 17 data-inventory `leaves_device: true` mezőivel (§0.0.A R6) | `beta_release_notes_test.dart` dokumentum-cellája |
| A8 | A csomag JSON-ja kanonikus (minden szinten rendezett kulcsok, egyetlen záró `\n`), és két futás bájtazonos | `beta_release_notes_test.dart` |
| A7 | A meglévő `diagnostics_storage_separation_test.dart` VÁLTOZATLANUL zöld | a §7 gate |

**Küszöb-cellahármas a melléklet-méretre** (a MÉRT `maxWavBytes = 5 242 880` bájt, a határ INKLUZÍV — a pontosan ekkora melléklet MÉG elfogadott): a küszöb **alatt** (5 242 879 bájt) → elfogadva; **pontosan rajta** (5 242 880) → elfogadva; a küszöb **fölött** (5 242 881) → ELUTASÍTVA, hibával, nem csonkolással.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A hang alapból bekerül a csomagba | A1 |
| A redakció csak a tokenre fut, az e-mailre nem | A2 |
| A túl nagy melléklet csendben csonkolódik | a küszöb-cellahármas „fölött" cellája |
| A consent-ellenőrzés figyelmeztet, de folytatja a csomagolást | A4 |
| A jegyzet generálási időbélyeget tartalmaz | A5 |
| A redakció csak a legfelső szinten fut, a beágyazott event nyers marad | A2 (rekurzív cella) |
| Csak `--consent-raw-audio` mellett is összeáll a csomag | A4 harmadik sora |
| A csomag kulcsai a bejárási sorrendben kerülnek a JSON-ba | A8 |
| A dokumentum-blokk a leltárban nem létező mezőnevet sorol fel | A6 fordított iránya |
| A jegyzet hiányzó `app.shortSha` mellett üres mezővel folytatja | A5 fail-closed cellája |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** kapcsold be a hang-mellékletet alapértelmezetté, futtasd a §7 gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/beta_release_notes_test.dart test/tooling/diagnostics_storage_separation_test.dart
```

Backend sáv (külön processzként):

```bash
cd backend && python -m pytest tests/test_diagnostics_redaction.py tests/test_diagnostics.py -q
```

## 8. Implementációs sorrend

1. `tool/release/build_diagnostics_bundle.py` — a redakcióval és a rétegzett consenttel.
2. `test/tooling/beta_release_notes_test.dart` — a küszöb-cellahármassal.
3. `backend/tests/test_diagnostics_redaction.py`.
4. `tool/release/generate_beta_notes.py`.
5. A három `docs/beta/` dokumentum + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Titok a csomagban.** A legsúlyosabb: token vagy e-mail kikerülése (A2).
- **Csendes csonkolás.** A méret-túllépés elrejtése hibás diagnosztikát okoz (küszöb-cella).
- **Felület-hiány elfelejtése.** A feedback-képernyő NEVESÍTETT hiány marad — a §0.0 kimondja, hogy a Chapter 13 pótkörébe tartozik.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
