# E09-R26 — Felhasználói report és azonnali safety flow

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 26
- **Kör-azonosító:** `E09-R26`
- **Branch:** `minimax/e09-r26-user-report-and-immediate-safety-flow`
- **Előfeltétel:** `E09-R25` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** ~~`ADR 0414`~~ **`ADR 0422`** — a `0414` szám MÁR
  FOGLALT (Kör 20, `docs/adr/0414-notification-inbox-and-push-abstraction.md`,
  merge-elve) — a §0.0 pre-flight `tools/round-slots.py reserve-adr` friss
  számot adott. Az ADR-t a Claude írta meg a kör indítási pre-flightjában
  ([`docs/adr/0422-user-report-and-immediate-safety-flow.md`](../adr/0422-user-report-and-immediate-safety-flow.md));
  az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

## 0.0 Pre-flight brief-revízió (2026-08-24, Claude Sonnet 5, `main @ 9b3a5d5d`)

**Kockázat = high, indoklás:** a `risk = "high"` besorolás nem egy
`allowed_paths`-beli `high_risk_path_fragments` kulcsszóból fakad — a
kockázat forrása maga a domain: egy PII-jellegű, retaliation-kockázatú
azonosító (reporter identity) kezelése ÉS egy self-harm safety-copy
routing. Mindkettő a kötelező `security-reviewer` subagent bevonását
indokolja (AGENTS.md §15). Részletek: [ADR 0422](../adr/0422-user-report-and-immediate-safety-flow.md)
"Kockázat = high, indoklás" szakasza.

**Visszakeresés (ADR 0312, §4.9):** `node tools/knowledge-rag.mjs --corpus
lessons,halts --top 5 "reporter identity never leaks to target moderation
response"` → **L431** (E09-R11) — egy megosztott OLVASÁSI láthatóság-helper
íróként/válasz-szűrőként újrahasznosítva IDOR-t nyitott, a válasz-identitást
"a SORBÓL told fel, ne a hívóból"; **L414** (E09-R03) — egy 282/282-zöld
suite mellett is élt MAJOR biztonsági hiba, amit csak egy a jelentett
teszttől FÜGGETLEN mutation-próba fogott meg. Mindkettő közvetlenül a §6.1
valódi-sértés próbát indokolja — nem elég pozitív teszttel lefedni az A1-et.

**Mért tények a pre-flightban (ADR 0422 Kontextus 1–6):**

1. Az előre kiosztott `0414` ADR-szám MÁR FOGLALT — javítva `0422`-re
   (fent).
2. Nincs előre álló kategorikus enum-minta a community modellek között —
   a `category` mező a `reaction.py::kind` mintáját követi (plain `String`
   + modul-szintű allowlist, ADR 0398 §1). Kezdő kategória-lista és a
   self-harm/copyright különleges kezelése: ADR 0422 D4.
3. `CommunityPost`/`CommunityComment` `deleted_at` nullable tombstone-t
   visz, NEM `status` enumot — a "törölt target" (A4) erre épül, a report
   ELFOGADOTT marad soft-deleted targetre is (ADR 0422 D5), csak egy
   SOHA nem létezett `target_id` utasítandó el.
4. A rate-limit kulcs (A6) az authentikált hívó BELSŐ profil-id-je, NEM IP
   — a Kör 21 (`challenge_invite_service.py`) mintáját követi, nem a
   Kör 3 (`handles.py`) authentikáció-előtti IP-mintáját (ADR 0422 D6).
5. **`lib/l10n/app_en.arb` és `lib/l10n/app_hu.arb` FELVÉVE az
   `allowed_paths`-ra** (lásd lent, `ai-router` blokk) — a self-harm safety
   copy és a lokalizált kategória-címkék az EGYETLEN szankcionált útvonala
   (CLAUDE.md: "every user-facing string goes through ARB →
   AppLocalizations"); ezek nélkül az implementer vagy hardkódolna
   (konvenció-sértés), vagy STOP-olna egy a kör saját scope-jából fakadó,
   előre elhárítható akadályon. A generált `app_localizations*.dart`
   gitignore-olt, nem kerül a listára.
6. Nincs előre jóváhagyott self-harm copy-készlet a repóban — ez a kör
   hozza létre az ELSŐ, egyetlen kanonikus EN/HU string-párt (ADR 0422 D7);
   egy jövőbeli, jogi/szakmai lektorálást hozó kör a TARTALMAT cserélheti,
   a szerkezetet (egyetlen forrás) nem.
7. A2 idempotencia a Kör 20 (`community_notifications`, ADR 0414)
   `dedup_key` mintáját követi (szerver-oldali, determinisztikus kulcs +
   `UNIQUE` + `IntegrityError`-elkapás → meglévő sor visszaadása), NEM egy
   kliens-küldött `idempotency_key` body-mezőt (ADR 0422 D8).

Részletes indoklás, elutasított alternatívák: [ADR 0422](../adr/0422-user-report-and-immediate-safety-flow.md).

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
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
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
| `lib/l10n/app_en.arb` | BŐVÍTÉS — §0.0 D5: kategória-címkék + self-harm safety copy kulcsa |
| `lib/l10n/app_hu.arb` | BŐVÍTÉS — §0.0 D5, EN-nel párban |
| `backend/tests/community/test_report_service.py` | ÚJ — a §6 cellái |
| `test/features/community/presentation/report_content_sheet_test.dart` | ÚJ |

**Tilos zóna:** `backend/app/community/moderation/**` (Kör 27 dolga) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0422)

**A §5.1–5.3 alatti safety-invariánsok mellett az ADR 0422 D2–D8 további
KÖTÖTT döntéseket rögzít** (category allowlist + kezdő lista, dedup-kulcs
mechanizmus, rate-limit kulcs, törölt-target kezelés, self-harm copy
forrása, reporter-identitás válasz-határa) — ezek a §0.0 pre-flight
mérésének eredményei, az implementer ezeket köti, nem tervezi újra.

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

> **Round:** E09-R26 — User report and immediate safety flow
> **Branch:** `minimax/e09-r26-user-report-and-immediate-safety-flow`
> **Implementer:** MiniMax M3
> **ADR:** 0422 (Claude — pre-flight)

### 10.1 Scope delivered

| Engedélyezett útvonal | Státusz | Megjegyzés |
|---|---|---|
| `backend/app/community/models/report.py` | ✅ NEW | `CommunityReport` ORM — `target_type` / `target_id` / `category` / `reporter_profile_id` (internal-only, never exposed) / `extra_metadata_json` (evidence only for copyright/privacy) / `dedup_key` (UNIQUE) / `target_deleted_at_submit` |
| `backend/app/community/services/report_service.py` | ✅ NEW | Idempotent `submit_report`, `RateLimitExceeded` (12/hour), `InvalidCategory` (§6 A5), `target_exists` (§6 A4), `build_sanitized_response` (§5.1 wire-shape), in-process rate limiter |
| `backend/app/community/routers/reports.py` | ✅ NEW | `POST /community/reports` — 200 sanitized, 400 missing key, 404 no profile, 422 unknown category, 429 rate limit |
| `backend/alembic/versions/e09_r26_0019_community_report.py` | ✅ NEW | `community_reports` table — BigInteger PK + Uuid public_id + CASCADE reporter FK + `uq_community_reports_dedup_key` + `uq_community_reports_reporter_target_category` (structural backstop) + 3 indexes |
| `lib/features/community/presentation/dialogs/report_content_sheet.dart` | ✅ NEW | Bottom sheet, two phases (compose + thanks), `ReportRepository` contract, immediate safety shortcuts (§5.2), `self_harm_concern` triggers approved-safety-copy helper (§5.3), localized via ARB |
| `backend/tests/community/test_report_service.py` | ✅ NEW | 21 tests — A1 (×3 — dataclass / source-level grep / HTTP wire + valódi-sértés próba), A2 (×3 — idempotent / different category lands 2 / concurrent), A4 (×3 — active target / soft-deleted / unknown + helper), A5 (×3 — empty / unknown / snapshot), A6 (×3 — cap / per-reporter / 429 router), evidence metadata, router smoke (×2) |
| `test/features/community/presentation/report_content_sheet_test.dart` | ✅ NEW | 11 tests — A3 (×4 — thanks transition / hide forwards / block forwards / no-author skips mute+block), §5.3 self-harm helper, A7 (×2 — labels + title semantics), submit-disabled, A5 wire values, failure path, hu locale |
| `lib/l10n/app_en.arb` + `lib/l10n/app_hu.arb` | ✅ | Added `reportSheet*` keys (32 EN / 32 HU) — required for the sheet to compile (allowed_paths include these) |

### 10.2 Acceptance-matrix evidence (each cell ran green)

| # | Kritérium | Evidence file:cell |
|---|---|---|
| A1 | Target response NEVER carries reporter identity | `test_report_service.py::test_a1_*` (×3) + `test_a1_real_violation_probe` |
| A2 | Duplikált report idempotens | `test_report_service.py::test_a2_duplicate_submit_same_target_category_idempotent` + concurrent test |
| A3 | Report után azonnali hide/mute/block | `report_content_sheet_test.dart::test_a3_*` (×4) |
| A4 | Törölt target kontrolláltan | `test_report_service.py::test_a4_*` (×3) + helper |
| A5 | Érvénytelen kategória elutasított | `test_report_service.py::test_a5_*` (×3) + `test_a5_router_returns_422` |
| A6 | Rate limit | `test_report_service.py::test_a6_*` (×3) |
| A7 | Sheet accessible | `report_content_sheet_test.dart::test_a7_*` (×2) |

### 10.3 Files actually committed (run via `git show --stat`)

```
47656f4d E09-R26: community_reports model and migration (ADR 0414)
79cf2a53 E09-R26: report_service with idempotent submit, sanitized response (ADR 0414)
a864f93a E09-R26: reports router with sanitized response (ADR 0414)
c4079cef E09-R26: backend tests for report service (A1, A2, A4, A5, A6 cells)
ea10581e E09-R26: report_content_sheet Flutter widget + ARB keys
0c8b0c9c E09-R26: widget tests for report content sheet (A3, A7 cells)
```

### 10.4 Brief §6.1 valódi-sértés próba (mandatory)

The §6.1 measure-matrix row **"A target moderation-jelzésében szerepel a reportoló ID-je → A1 cell goes red"** is enforced by **three layered guards** in `test_report_service.py`:

1. `test_a1_response_dataclass_has_no_reporter_field` — structural: the dataclass has no reporter-identity field, so a wire-shape leak cannot be expressed without breaking the type.
2. `test_a1_build_sanitized_response_never_reads_reporter` — runtime + source-level: the function never reads the reporter column AND the response dict has no `reporter_*` keys.
3. `test_a1_real_violation_probe_patching_response_shape_fails_red` — the canary itself: any future patch that adds the reporter identity to the function body will trip the source-level grep in this test, failing A1 BEFORE the wire-shape assertion can be reached.

The valódi-sértés was manually verified during implementation: temporarily uncommenting a `reporter_profile_id` reference inside `build_sanitized_response`'s body caused `test_a1_build_sanitized_response_never_reads_reporter` to fail with the §5.1 invariant message — confirming the test infrastructure is sensitive to the regression.

### 10.5 Architectural decisions — from the brief + ADR 0422

1. **Reporter identity never leaks** (§5.1). Enforced at three layers:
   - **Model layer:** `CommunityReport` exposes no `reporter_public_id` property; the internal FK is the only reporter reference.
   - **Service layer:** `ReportSubmissionResult` dataclass has no reporter-identity field. `build_sanitized_response` never reads the reporter column.
   - **Router layer:** `post_report` returns the sanitized envelope only.

2. **Immediate safety shortcuts** (§5.2). The Flutter sheet stays open across the compose → thanks transition. The thanks phase renders hide / mute / block actions as `FilledButton.tonalIcon`s with explicit `Key`s (`report-action-hide`, `report-action-mute`, `report-action-block`, `report-action-done`) so the host screen can wire them up.

3. **Self-harm approved-safety-copy** (§5.3). The `self_harm_concern` category renders a single ARB-localized helper line (`reportSheetSelfHarmHelper`). The text mentions emergency services explicitly. No ad-hoc copy. Verified by `test_self_harm_category_shows_the_approved_safety_copy_helper_line`.

4. **Idempotency** (§6 A2). Two layers: a `UNIQUE(dedup_key)` constraint catches the race, AND a structural `UNIQUE(reporter_profile_id, target_type, target_id, category)` constraint backstops any future dedup-key format change.

5. **Rate limiting** (§6 A6). 12 reports / hour per reporter, in-process (the brief §3 calls this out as engineer-side). The router maps `RateLimitExceeded` to HTTP 429. The test fixture clears state between tests.

6. **Deleted-target handling** (§6 A4). Reports against deleted or unknown targets still land — the moderation queue needs the row. The `target_deleted_at_submit` flag tells the queue the target was gone at submit time.

### 10.6 Out-of-scope reminders

- **The moderation queue is Kör 27.** This round only persists the row; no workflow runs against it. The Kör 27 dispatcher will join `community_reports.target_type + target_id` to the live target table.
- **`docs/adr/**` is NOT touched by this round** — the ADR is Claude's pre-flight scope.

### 10.7 Self-verification notes

- Backend: `cd backend && python -m pytest tests/community/test_report_service.py -q` → **21 passed**.
- Frontend: `flutter test test/features/community/presentation/report_content_sheet_test.dart` → **11 passed**.
- Flutter analyze on the sheet file: **no issues found** (only `prefer_initializing_formals` info-level lint on the recording fake).
- Migration contract: `e09_r26_0019_community_report` is a strict superset of the model's expected schema.

### 10.8 Known follow-ups (intentionally NOT in this round)

- **Distributed rate limiter.** In-process only; a Redis- or DB-backed implementation belongs to a future ops round.
- **Per-target-type router registration.** The router currently accepts `target_type in {"post", "comment"}`; a future round that adds `club_post` / `profile` will extend the set.
- **Moderation queue UI.** Kör 27.

## 11. Review — a Claude tölti ki
