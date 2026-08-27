# E12-R17 — Privacy data inventory és consent enforcement

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 17
- **Kör-azonosító:** `E12-R17`
- **Branch:** `<motor>/e12-r17-privacy-data-inventory-and-consent-enforcement`
- **Előfeltétel:** `E13-R35` merge-elve (a Consent Center FELÜLETE ott készül el — ez a kör a mögötte lévő adat-leltárt és kényszerítést méri)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0457` — a szám FOGLALT (Chapter 12 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "privacy data inventory consent enforcement revoke export deletion"` → **[ADR 0247](../adr/0247-analysis-export-share-and-delete-contract.md)** (export/share/delete szerződés) és **[ADR 0132](../adr/0132-ai-tutor-privacy-and-consent.md)** (Tutor privacy & consent). A leltár ezekre a MÉRT szerződésekre épül; új consent-fogalmat nem vezet be.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg a MEGLÉVŐ consent-hordozókat (`lib/features/ai_tutor/domain/models/tutor_consent.dart`, `lib/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart`, `lib/features/settings/screens/vision_privacy_screen.dart`, `lib/features/diagnostics/data/diagnostics_uploader.dart`) és nézd meg, mit hozott az E13-R35 Consent Center köre. A leltárnak a MÉRT állapotot kell tükröznie.

## 0.0 A felület NEM ennek a körnek a dolga

A Consent Center és a privacy-felület a Chapter 13 sáv terméke (E13-R35). Ez a kör a felület MÖGÖTTI igazságot méri: (a) minden adatmezőnek van-e célja, retentionje és jogalapja, (b) a consent visszavonása AZONNAL leállítja-e az adott adatáramlást. Új képernyőt tehát NEM hoz létre — a `test/ui/ui_inventory_test.dart` egzakt képernyőszáma nem mozdulhat.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "docs/privacy/data-inventory.yaml",
  "docs/privacy/consent-enforcement.md",
  "tool/check_data_inventory.dart",
  "test/privacy/consent_enforcement_test.dart",
  "test/tooling/data_inventory_test.dart",
  "docs/rounds/e12-r17-privacy-data-inventory-and-consent-enforcement.md",
]
gate_tests = [
  "test/privacy/consent_enforcement_test.dart",
  "test/tooling/data_inventory_test.dart",
  "test/ui/ui_inventory_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a kör tárgya közvetlenül adatvédelmi határ (consent, retention, hálózatra kerülő adat) — egy hibás cella hamis biztonságérzetet adna arról, hogy egy visszavont hozzájárulás tényleg leállította az adatküldést. A `security-reviewer` futtatása a review-ban KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha egy cella MÉRT szivárgást talál (visszavont consent mellett is megy adat), a kimenet a `stopped` jelzés és jelentés — a `lib/**` javítása ebben a körben TILOS, mert a javítás önálló, review-zott kört érdemel.

## 1. Cél

Géppel olvasható adat-leltár minden feature-höz, és MÉRT bizonyíték arra, hogy a hozzájárulás visszavonása azonnal érvényre jut.

## 2. Jelenlegi állapot — mért tények

- `docs/privacy/` MA **egy** dokumentumot tartalmaz (`practice-planning-data.md`) — teljes leltár nincs.
- Consent-hordozók a fán: `tutor_consent.dart` (AI Tutor), `tutor_privacy_providers.dart`, `vision_privacy_screen.dart` (Vision), `diagnostics_uploader.dart` (Lab-diagnosztika), és a Community privacy-mezői (`e09_r04_0004_community_privacy_fields.py` migráció).
- `test/privacy/` **nem létezik**; `tool/check_data_inventory.dart` **nem létezik** (a `tool/ci/` fa a MÉRCE védett zónája — ADR 0321/0372, `protect_factory_files.py` `PROTECTED_GLOBS` —, ezért az ÚJ ellenőrző a `tool/` gyökérbe kerül, a `tool/check_architecture.dart` mintájára).
- `test/ui/ui_inventory_test.dart` egzakt képernyőszámot pinnel (`hasLength(94)` a megíráskor) — ez a kör NEM mozdíthatja el.
- `AppConfig.usesNetwork => accountEnabled || diagnosticsEnabled` — a hálózat-használat MA két flagből következik; a leltárnak ezt is le kell írnia.

## 3. Scope

**Benne van:** `docs/privacy/data-inventory.yaml` — feature-enként MINDEN tárolt/továbbított adatmező: cél, jogalap, retention, tárolási hely (eszköz/backend), consent-kapcsoló, „elhagyja-e az eszközt" · `tool/check_data_inventory.dart` (hiányzó mező vagy a fán MÉRT, leltárban nem szereplő adatküldő út → nem-nulla kilépés) · `test/privacy/consent_enforcement_test.dart` (a consent visszavonása után az adott út NEM küld: tutor, diagnostics, community — mindegyik a MAGA MÉRT kapcsolójával) · `docs/privacy/consent-enforcement.md`.

**NINCS benne (tilos):**

- ÚJ képernyő vagy bármely `lib/**` módosítás.
- Új consent-fogalom vagy -kapcsoló bevezetése.
- Backend séma-változás.
- `docs/adr/**` — az ADR 0457-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/privacy/data-inventory.yaml` | ÚJ — a leltár |
| `docs/privacy/consent-enforcement.md` | ÚJ — a kényszerítési szabályok |
| `tool/check_data_inventory.dart` | ÚJ — a leltár teljesség-ellenőrzése |
| `test/privacy/consent_enforcement_test.dart` | a §6 kényszerítési cellái |
| `test/tooling/data_inventory_test.dart` | a leltár séma-cellái |

**Tilos zóna:** `lib/**` · `backend/**` · `test/ui/goldens/**` · `docs/adr/**` · `.github/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0457)

### 5.1 A leltár teljességét a KÓD méri, nem a szerző

A checker a fán megkeresi az adatküldő utakat (HTTP-kliens hívóhelyek, uploader-ek), és mindegyikhez leltár-bejegyzést követel. **NEM elfogadható gyengítés:** kézzel írt lista gépi teljesség-ellenőrzés nélkül — az első új végpont után hazudna.

### 5.2 A visszavonás AZONNAL hat, nem a következő indításkor

**NEM elfogadható gyengítés:** „a következő app-indításkor lép életbe" viselkedés elfogadása — a mért felhasználói elvárás és az ADR 0132 is azonnali hatályt ír.

### 5.3 Nincs csendes cloud-fallback

Ha egy helyi út nem elérhető, a rendszer NEM esik vissza felhő-hívásra hozzájárulás nélkül. **NEM elfogadható gyengítés:** „degradált mód" néven bevezetett hálózati ág.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A leltár MINDEN mezője hordoz célt, jogalapot, retentiont és tárolási helyet | `data_inventory_test.dart` |
| A2 | A fán MÉRT minden adatküldő úthoz tartozik leltár-bejegyzés | `data_inventory_test.dart` (fa-bejárás) |
| A3 | Tutor-consent visszavonása után a tutor-út NEM küld adatot | `consent_enforcement_test.dart` |
| A4 | Diagnostics-consent visszavonása után az uploader NEM küld | `consent_enforcement_test.dart` |
| A5 | Community-consent visszavonása után a közösségi írás-út NEM küld | `consent_enforcement_test.dart` |
| A6 | A visszavonás AZONNAL hat (ugyanabban a session-ben, újraindítás nélkül) | `consent_enforcement_test.dart` |
| A7 | A képernyő-leltár száma VÁLTOZATLAN (a kör nem hoz új képernyőt) | `test/ui/ui_inventory_test.dart` a §7 gate-ben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A checker a leltárból indul, nem a fából (új végpont láthatatlan) | A2 |
| A teszt a visszavonást app-újraindítás után méri | A6 |
| A teszt csak EGY csatornát tilt, a többi nyitva marad ([L453](../LESSONS.md#l453)) | A3–A5 valamelyike |
| A kör „mellékesen" új privacy-képernyőt hoz létre | A7 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** a teszt-fake-ben állítsd a diagnostics-consentet úgy, hogy a visszavonás csak a következő indításkor érvényesüljön, futtasd a §7 gate-et → az **A4** és **A6** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/privacy/consent_enforcement_test.dart test/tooling/data_inventory_test.dart test/ui/ui_inventory_test.dart
```

A leltár-ellenőrző közvetlen futtatása (kimenet a §10-be):

```bash
dart run tool/check_data_inventory.dart
```

## 8. Implementációs sorrend

1. A MÉRÉS: adatküldő utak kigyűjtése a `lib/**` fából.
2. `docs/privacy/data-inventory.yaml`.
3. `tool/check_data_inventory.dart` (fa ↔ leltár összevetés).
4. `test/privacy/consent_enforcement_test.dart` — az A3–A6 cellák.
5. `test/tooling/data_inventory_test.dart`.
6. `docs/privacy/consent-enforcement.md` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Hamis biztonság.** Egy csatorna-specifikus mock zöldre viszi a cellát, miközben másik úton megy adat ([L453](../LESSONS.md#l453)).
- **A leltár elavulása.** Kézi lista mellett az első új végpont után hamis (A2).
- **Termékhiba felfedezése.** Ha egy út visszavonás után is küld, az `stopped` jelzés — a javítás önálló kör.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
