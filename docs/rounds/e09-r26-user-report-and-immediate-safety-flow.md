# E09-R26 — Felhasználói report és azonnali safety flow

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 26
- **Kör-azonosító:** `E09-R26`
- **Branch:** `<motor>/e09-r26-user-report-and-immediate-safety-flow`
- **Előfeltétel:** `E09-R25` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0414` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 8 `safety_relationships_screen.dart` TÉNYLEGES widget-struktúráját — a report bottom sheet ugyanabból a képernyő-családból nyílik, konzisztens biztonsági UX-szel. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/models/report.py",
  "backend/app/community/services/report_service.py",
  "backend/app/community/routers/reports.py",
  "backend/alembic/versions/e09_r26_0019_community_report.py",
  "lib/features/community/presentation/dialogs/report_content_sheet.dart",
  "backend/tests/community/test_report_service.py",
  "test/features/community/presentation/report_content_sheet_test.dart",
  "docs/rounds/e09-r26-user-report-and-immediate-safety-flow.md",
]
gate_tests = [
  "test/features/community/presentation/report_content_sheet_test.dart"
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

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Könnyen elérhető report, hide, mute és block folyamat minden releváns tartalomnál — a reportoló személye SOSEM szivárog a targethez.

## 2. Jelenlegi állapot — mért tények

- A Kör 8 block/mute MA készen áll — ez a kör a report-workflow ELSŐ darabja, ami majd a Kör 27 moderation-queue-ba táplál

## 3. Scope

**Benne van:** report tábla: target type/ID, category, opcionális detail, reporter, dedup mező · report endpoint úgy, hogy a reporter személye NEM kerül a target response-aiba · Flutter report bottom sheet lokalizált kategóriával és safety shortcutokkal · report után AZONNALI hide/mute/block lehetőség · ugyanazon target/category ismételt submit idempotens vagy kontrolláltan összevont · copyright/privacy kategóriához minimalizált extra metadata mező · self-harm concern kategóriánál CSAK jóváhagyott safety copy és routing.

**NINCS benne (tilos):**

- A moderation-queue TÉNYLEGES feldolgozása — Kör 27.
- `docs/adr/**` — az ADR 0414-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/models/report.py` | ÚJ |
| `backend/app/community/services/report_service.py` | ÚJ |
| `backend/app/community/routers/reports.py` | ÚJ |
| `backend/alembic/versions/e09_r26_0019_community_report.py` | ÚJ |
| `lib/features/community/presentation/dialogs/report_content_sheet.dart` | ÚJ |
| `backend/tests/community/test_report_service.py` | ÚJ — a §6 cellái |
| `test/features/community/presentation/report_content_sheet_test.dart` | ÚJ |

**Tilos zóna:** `backend/app/community/moderation/**` (Kör 27 dolga) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0414)

### 5.1 A reportoló SZEMÉLYE SOSEM szivárog a target-hez

A target semmilyen response-ban (poszt, moderation-jelzés, notification) nem kap információt arról, KI jelentette — ez a safety-mechanizmus alapja.

**NEM elfogadható gyengítés:** egy "átláthatósági" funkció, ami megmutatja a target-nek, hogy hányan és kik jelentették — ez retaliation-kockázatot nyitna, és elrettentene a jelentéstől.

### 5.2 A report után a felhasználónak NEM KELL tovább látnia a tartalmat

A report-flow végén azonnali hide/mute/block opciót kínál — a user döntése nélkül a UI nem kényszeríti vissza a tartalom megtekintésére.

### 5.3 Self-harm kategória KIZÁRÓLAG jóváhagyott safety copy-t és routingot használ

Ez a kategória nem kap egyedi, ad-hoc szöveget — a lokalizált, jogilag/szakmailag jóváhagyott copy-készletből dolgozik.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A target response semmilyen módon nem tartalmazza a reportoló azonosítóját | `test_report_service.py` |
| A2 | Duplikált report ugyanarra a target/category párra idempotens | `test_report_service.py` |
| A3 | Report után a user azonnal blockolhat/mute-olhat/elrejtheti a tartalmat | `report_content_sheet_test.dart` |
| A4 | Törölt target-re irányuló report kontrolláltan kezelt | `test_report_service.py` |
| A5 | Érvénytelen kategória elutasított | `test_report_service.py` |
| A6 | Rate limit érvényesül a report-endpointon | `test_report_service.py` |
| A7 | A report bottom sheet elérhető screen readerrel (accessibility focus) | `report_content_sheet_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A target moderation-jelzésében szerepel a reportoló ID-je | A1 |
| Minden ismételt submit új report-rekordot hoz létre | A2 |
| A report-flow nem ajánl fel azonnali hide/block opciót | A3 |
| Egy ismeretlen kategória-string átmegy a validáción | A5 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** add hozzá a `reporter_id`-t a moderation-jelzés Pydantic sémájához, futtasd a backend pytest-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/presentation/report_content_sheet_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_report_service.py -q
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. Migráció: `community_reports` (target_type, target_id, category, reporter_id [SOSEM exponálva], dedup_key).
2. `report_service.py` — idempotens submit, reporter-identity elkülönítés a response-tól.
3. `reports.py` router — rate limit, kategória-validáció.
4. `report_content_sheet.dart` — lokalizált kategóriák, azonnali safety-shortcutok, self-harm jóváhagyott copy.
5. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A reportoló-identitás szivárgása.** Ez retaliation-kockázatot nyitna és elrettentene a jelentéstől — a kör legsúlyosabb kockázata (A1).
- **A kényszerű tartalom-megtekintés.** Ha a flow nem kínál azonnali elrejtést, a user tovább szenvedne a jelentett tartalomtól (A3).
- **Az ad-hoc self-harm szöveg.** Egy nem jóváhagyott üzenet jogi és biztonsági kockázatot hordoz.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
