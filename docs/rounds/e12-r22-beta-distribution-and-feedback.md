# E12-R22 — Beta distribution, tester enrollment és feedback

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 22
- **Kör-azonosító:** `E12-R22`
- **Branch:** `<motor>/e12-r22-beta-distribution-and-feedback`
- **Előfeltétel:** `E12-R06` és `E12-R17` merge-elve (release-notes generálás a manifestből; a consent-határ a data-inventoryból)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0461` — a szám FOGLALT (Chapter 12 batch-tartomány).

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
- `docs/adr/**` — az ADR 0461-et a Claude írja.

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

## 5. Kötött architekturális döntések (ADR 0461)

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
| A4 | Hozzájárulás nélkül a bundle-építés nem-nulla kóddal áll le | `beta_release_notes_test.dart` |
| A5 | A béta-jegyzet kétszeri generálása bájtazonos, és tartalmazza a build-azonosítót | `beta_release_notes_test.dart` |
| A6 | A `tester-consent.md` mezőről mezőre megegyezik a Kör 17 data-inventoryjával | `beta_release_notes_test.dart` dokumentum-cellája |
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
