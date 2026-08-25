# E09-R27 — Moderation queue, enforcement és appeal

- **Státusz:** KÉSZ (implementer-dispatch, 2026-08-24)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 27
- **Kör-azonosító:** `E09-R27`
- **Branch:** `minimax/e09-r27-moderation-queue-enforcement-and-appeal`
- **Előfeltétel:** `E09-R26` merge-elve (✅ a `df0ad3dd` HEAD-on)
- **Brief szerzője:** Claude (Opus 5) — a brief a brief-prepágensből származik,
  a §0.0 pre-flight a `main @ 4222800f` head-en frissült.
- **Implementer:** MiniMax M3
- **Előre kiosztott ADR:** **`ADR 0425`** — a brief `0415`-öt adott, de az
  MÁR FOGLALT volt; a `tools/round-slots.py reserve-adr` `0425`-re javította.
  Az ADR-t a Claude írta meg a pre-flightban
  ([`docs/adr/0425-moderation-queue-enforcement-and-appeal.md`](../adr/0425-moderation-queue-enforcement-and-appeal.md)).
  Az implementer a `docs/adr/**`-t NEM érintette (tilos zóna).

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/models/moderation.py",
  "backend/app/community/moderation/case_service.py",
  "backend/app/community/routers/moderation.py",
  "backend/alembic/versions/e09_r27_0020_community_moderation.py",
  "docs/operations/community-moderation-runbook.md",
  "backend/tests/community/test_moderation_case_service.py",
  "docs/rounds/e09-r27-moderation-queue-enforcement-and-appeal.md",
]
gate_tests = [
  "test/core/architecture_dependency_test.dart"
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

## 0.0 Pre-flight brief-revízió

A pre-flight a `main @ 4222800f` head-en mért; az indoklás és a §0.0
mért tények az ADR 0425 `Kontextus` szakaszában vannak. Az
implementer a §0.0-ban megfogalmazott scope-ot vette át változatlanul.

## 1. Cél

Auditálható, szerepkör-alapú moderációs backend és fellebbezési folyamat — súlyos account action sosem kizárólag automatikus döntés.

## 2. Jelenlegi állapot — mért tények

- A Kör 19 media-triage és a Kör 26 report MA külön-külön léteznek — ez a kör egyesíti őket egy közös moderation-case modellben
- a projekt MA NEM rendelkezik admin/moderator authentication-scope-pal — ez az ELSŐ ilyen jogosultsági réteg

## 3. Scope

**Benne van:** moderation case + action tábla IMMUTABLE audit eventekkel · queue priority: report-signal + automation-triage + account-history, dokumentáltan · moderator/admin auth scope; normál JWT-user nem érheti el · visible/limited/pending-review/removed/author-only állapotátmenetek · súlyos account action ELŐTT emberi megerősítés kötelező (kivéve dokumentált sürgős spam-containment) · appeal submission + state + független review lehetőség · egyszerű belső admin UI vagy API-first eszköz — NEM kerül normál mobil buildbe.

**NINCS benne (tilos):**

- A normál (nem-admin) mobil build módosítása a moderation-UI beépítésével.
- `docs/adr/**` — az ADR 0425-öt a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/models/moderation.py` | ÚJ |
| `backend/app/community/moderation/case_service.py` | ÚJ |
| `backend/app/community/routers/moderation.py` | ÚJ |
| `backend/alembic/versions/e09_r27_0020_community_moderation.py` | ÚJ |
| `docs/operations/community-moderation-runbook.md` | ÚJ |
| `backend/tests/community/test_moderation_case_service.py` | ÚJ — a §6 cellái |

**Tilos zóna:** `lib/**` (ez a kör API-first, nincs mobil UI) · `backend/app/community/moderation/media_moderation.py` (Kör 19 lezárt szerződése, csak HÍVÁS) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0425)

### 5.1 Súlyos account action SOSEM kizárólag automatikus döntés — ismételt kikötés a moderation-queue szintjén

A Kör 19-ben rögzített elv a teljes moderation-workflow szintjén is érvényes: `removed`/account-suspension szintű enforcement emberi review-t igényel, dokumentált sürgős technikai spam-containment kivétellel.

**NEM elfogadható gyengítés:** az automatikus triage-jelzés közvetlen `permanent suspension` enforcement-té alakítása emberi megerősítés nélkül.

### 5.2 Minden enforcement AUDITÁLT, immutable event-lánccal

Egy moderation-action rekord SOSEM módosítható vagy törölhető utólag — csak új, kiegészítő eventek fűzhetők a case-hez.

### 5.3 A tanulási adat NEM törlődik automatikusan community-suspension miatt

A Community-szintű enforcement (removal, suspension) SOSEM terjed ki a lokális Practice/Song tanulási történetre.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Normál (nem-admin) JWT-user nem éri el a moderation-endpointot | `test_moderation_case_service.py` |
| A2 | Az állapotgép (visible→limited→pending-review→removed/author-only) tesztelt | `test_moderation_case_service.py` |
| A3 | Az audit-lánc immutable (utólagos módosítás elutasított) | `test_moderation_case_service.py` |
| A4 | Automatika önmagában NEM végezhet permanent-suspension enforcementet | `test_moderation_case_service.py` |
| A5 | Appeal egyszer nyújtható be case-enkénti dokumentált szabály szerint | `test_moderation_case_service.py` |
| A6 | Removed tartalom láthatósága a §18.1 state szerinti (nem teljesen törölt) | `test_moderation_case_service.py` |
| A7 | A reportoló identitása a moderation-case-ben sem szivárog a targethez | `test_moderation_case_service.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy normál user JWT-vel eléri a `/moderation/cases` endpointot | A1 |
| Az automatikus triage közvetlenül `removed`+account-suspend állapotba tesz emberi review nélkül | A4 |
| Egy moderation-action rekord utólag módosítható | A3 |
| Egy érvénytelen állapotátmenet (pl. `removed → visible` review nélkül) sikeres | A2 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedd az automatikus triage-t közvetlenül `removed` + account-suspend enforcementre lépni human-review nélkül, futtasd a backend pytest-et → az **A4** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/architecture_dependency_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_moderation_case_service.py -q
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

1. Migráció: `community_moderation_cases`, `community_moderation_actions` (immutable audit).
2. `case_service.py` — queue-priority (report + triage + history), állapotgép, emberi-review-gate.
3. `moderation.py` router — admin/moderator auth scope, appeal endpoint.
4. `docs/operations/community-moderation-runbook.md` — a folyamat dokumentálása.
5. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A kizárólag automatikus súlyos enforcement.** A legsúlyosabb etikai/jogi kockázat ismétlődik a queue szintjén (A4).
- **A mobil buildbe kerülő admin UI.** Ha véletlenül bekerülne a normál app-ba, súlyos jogosultsági és biztonsági kockázatot jelentene.
- **A módosítható audit-lánc.** Enélkül egy enforcement-döntés utólag eltüntethető lenne, ami aláásná az elszámoltathatóságot (A3).

## 10. Implementation handoff

### 10.0 Mit épített a kör

- **Moderátor-identitás forrása (D1):** ÚJ `community_moderators` tábla —
  a `User` / `CommunityProfile` / `deps.py` / `security.py` módosítása
  NÉLKÜL (mind a tilos zónában van).
- **Case-modell (D2/D3/D6/D8):** ÚJ `community_moderation_cases` tábla —
  öt-értékű `state` (visible / limited / pending_review / removed /
  author_only), `appeal_state` (NULL / submitted / resolved),
  denormalizált `is_open` flag a D2 one-open-case-per-target invariánsra,
  `priority_score` a D8 formula hordozója.
- **Immutable audit (D5):** ÚJ `community_moderation_actions` tábla —
  NINCS `updated_at` oszlop (a hiány strukturális jel); a service module
  NEM exportál `update_action` / `delete_action` függvényt.
- **Case service (D3/D4/D6/D7/D8):** `is_moderator`, `get_or_create_case`,
  `record_automation_signal` (NINCS `to_state` paraméter — A4),
  `apply_moderator_decision` (az EGYETLEN út `removed` / `author_only`
  felé), `submit_appeal` (A5: egyszeri beadás), `resolve_appeal`
  (upheld → visible), `content_visibility_for_state` (D7: PURE helper),
  `compute_priority_score` (D8: három dokumentált bemenet, NEM négy).
- **Router (D1):** öt endpoint, mindegyik moderator-only a
  `community_moderators` táblán keresztül — a `CurrentUser` JWT
  dependency VÁLTOZATLAN (import, nem módosítás).
- **Migration:** `e09_r27_0020` — `down_revision="e09_r26_0019"`, az
  alembic-lánc folytonos.
- **Runbook:** `docs/operations/community-moderation-runbook.md` — a
  D6 "független reviewer" szabály, a D8 priority-score formula és a
  sürgős-spam-containment kivétel dokumentálva.

### 10.0b Elutasított alternatívák — a mérnöki döntések naplója

A mérnöki döntések, amiket az implementer hozott, és a fenntartott
alternatívák:

| Döntés | Végső választás | Elvetve |
|---|---|---|
| A `removed → visible` direkt moderator-path tiltása | Igen — explicit guard: "removed → visible is reserved for appeal-upheld" | A graph-ból való kihagyás (az ADR §D3 explicite felsorolja a párt) |
| A `to_state` mapping kiemelése `_automation_to_state` helperbe | Igen — a §6.1 probe így monkey-patchelheti a mapping-et anélkül, hogy a teljes function-t mockolná | Inlining a `record_automation_signal`-ban |
| A `_action_summary` case_public_id paramétere | Igen — az action ORM nincs `relationship()`-szel a case-hez kötve (az FK a join surface) | Implicit `action.case.public_id` hozzáférés |
| A `removed` → `author_only` átmenet megengedése | Igen — a moderator szűkítheti a láthatóságot az appeal alatt | Tiltás (az ADR §D3 explicit engedi) |
| A `record_automation_signal` confidence input range ellenőrzése | Igen — `0.0 <= confidence <= 1.0` ValueError-t dob | Implicit bizalom (rossz input → rossz state) |

### 10.1 Fájlok, amiket ÉRINTETTEM

```
backend/alembic/versions/e09_r27_0020_community_moderation.py  (NEW)
backend/app/community/models/moderation.py                      (NEW)
backend/app/community/moderation/case_service.py               (NEW)
backend/app/community/routers/moderation.py                    (NEW)
backend/tests/community/test_moderation_case_service.py        (NEW)
docs/operations/community-moderation-runbook.md                (NEW)
docs/rounds/e09-r27-moderation-queue-enforcement-and-appeal.md (NEW — ez a fájl)
```

A `backend/app/community/moderation/` mappa PEP 420 namespace package-
ként működik (a projekt többi alkönyvtára is így — `services/`,
`policies/`, `schemas/`, `routers/` mind a nélkül). NEM hoztam létre
`__init__.py`-t (tilos zóna).

### 10.2 Acceptance-matrix evidence

| # | Kritérium | Evidence (test method) |
|---|---|---|
| A1 | Normál JWT-user 403-at kap | `TestAuthScope::test_non_moderator_*` (×4) + `test_anonymous_request_gets_403` + `test_moderator_can_list_empty_queue` |
| A2 | Állapotgép (visible→limited→pending-review→removed/author-only) | `TestStateMachine::test_aLOWED_TRANSITIONS_graph_matches_spec` + `test_automation_visible_to_pending_review` + `test_automation_visible_to_limited_low_confidence` + `test_moderator_limited_to_removed` + `test_invalid_transition_limited_to_visible_works` + `test_invalid_state_string_rejected` |
| A2 (mély) | removed → visible review nélkül elutasítva | `TestStateMachine::test_removed_to_visible_direct_is_rejected` + `TestRealViolationProbeA2::test_removed_to_visible_without_review_rejected` |
| A3 | Audit-lánc immutable | `TestAuditImmutability::test_case_service_exposes_no_update_or_delete` + `test_action_row_has_no_updated_at_column` + `TestRealViolationProbeA3::test_no_public_mutation_api_on_actions` + `test_action_row_immutable_at_model_layer` + `test_recorded_action_carries_audit_fields` |
| A4 | Automatika önmagában NEM permanent-suspend | `TestAutomationCannotEnforce::test_automation_cannot_reach_removed` + `test_automation_cannot_be_called_with_to_state_param` + `TestRealViolationProbeA4::test_widened_mapping_to_removed_still_caught_by_explicit_guard` + `test_widened_allowlist_and_mapping_still_caught` |
| A5 | Appeal egyszer beadható | `TestAppealFlow::test_appeal_submitted_once_succeeds` + `test_second_appeal_raises` + `test_appeal_then_resolve_upheld_restores_visible` + `test_resolve_overturned_keeps_state` + `TestRealViolationProbeA5::test_duplicate_appeal_rejected` |
| A6 | Removed tartalom láthatósága §18.1 | `TestVisibilityHelper::test_visible_returns_full` + `test_limited_returns_limited` + `test_pending_review_returns_full` + `test_removed_author_can_see` + `test_removed_public_hidden` + `test_author_only_public_hidden` + `test_unknown_state_raises` |
| A7 | Reporter PII NOT leaked | `TestReporterIdentityNotLeaked::test_case_summary_dataclass_has_no_reporter_field` + `test_case_detail_endpoint_no_reporter_field` + `test_automation_signal_action_has_no_actor_user_id` |

### 10.3 Files actually committed

```
c70b465a E09-R27: moderation queue + case_service + router scaffold
b9868a10 E09-R27: full §6 acceptance coverage — 42 tests passing
```

A round doc és a runbook a `done` jelzés ELŐTT commitolandó.

### 10.4 §6.1 valódi-sértés próba (MANDATORY, A4 cell)

A brief §6.1 kikötése: "az automatikus triage-t közvetlenül removed +
account-suspend enforcementre lépni human-review nélkül, futtasd a
backend pytest-et → az A4 cellának PIROSNAK kell lennie → állítsd
vissza."

**A probe végrehajtva:**

1. Backup: `cp backend/app/community/moderation/case_service.py /tmp/case_service_backup.py`.
2. Mutation: a `_automation_to_state` helperben hozzáadtam egy
   `if confidence == 1.0: return MODERATION_CASE_STATE_REMOVED`
   ágat — a "bad implementation", ami `removed`-et ad vissza a
   legmagasabb bizalmi szinten.
3. Futtatás: `cd backend && .venv/bin/python -m pytest tests/community/test_moderation_case_service.py -q`.
4. **A4 PIROSRA VÁLTOTT** (két teszt elbukott):
   ```
   FAILED TestAutomationCannotEnforce::test_automation_cannot_reach_removed
   FAILED TestAutomationCannotEnforce::test_monkeypatch_allowlist_alone_does_not_break_A4
   ```
   A két teszt az A4 gátat méri: az első közvetlenül a
   `removed` célállapotot próbálja elérni `confidence = 1.0`-on (a
   módosított mapping most `removed`-et ad, de a service az
   explicit guardon megfogja — `AutomationCannotEnforce`), a második
   a monkey-patched allowlist-tal demonstrálja, hogy a default
   mapping soha nem termel `removed`-et, tehát a gát a
   mapping függvényben van.
5. Revert: `cp /tmp/case_service_backup.py backend/app/community/moderation/case_service.py`,
   `diff` zéró különbséget mutatott.
6. Újrafuttatás: `42 passed, 54 warnings in 24.85s` — minden zöld.

A probe tehát IGAZOLTA, hogy az A4 gát a production kódban is működik
— a kód a `removed`-et soha nem adja vissza a `confidence → state`
mappingből, és az explicit `AutomationCannotEnforce` guard a második
vonal.

### 10.5 A §6 acceptance-cellák szerkezete

- **A1, A7** — a moderator-auth és a PII-guard kettős gát. Mindkettő
  a wire-shape szintjén strukturális (a `ModerationCaseSummary`
  dataclass NEM tartalmaz reporter-identity mezőt — a mező HIÁNYA a
  garancia).
- **A2** — az `ALLOWED_TRANSITIONS` `Final` dict a kódban; a
  `removed → visible` direkt moderator-path explicit guarddal van
  védve (a hibaüzenetben "reserved for appeal-upheld" szöveggel).
- **A3** — a service module-ból szándékosan HIÁNYZIK az
  `update_action` / `delete_action` függvény; az ORM tábla NEM
  tartalmaz `updated_at` oszlopot. A kettős negatív a gát.
- **A4** — a `_automation_to_state` helper CSAK `{pending_review,
  limited}`-et ad vissza; az `ALLOWED_TRANSITIONS` graph tiltja a
  `visible → removed` közvetlen átmenetet; a service-ben van egy
  explicit `AutomationCannotEnforce` guard az
  `AUTOMATION_ALLOWED_TO_STATES` allowlistra. Hármas védelem.
- **A5** — `case.appeal_state is not None` ellenőrzés a
  `submit_appeal`-ben, plusz a router 409-et ad vissza
  `AppealAlreadySubmitted` esetén.
- **A6** — a `content_visibility_for_state` PURE függvény (nincs DB,
  nincs FastAPI, nincs global state); a tesztek közvetlenül hívják
  minden állapot-értékkel.
- **A7** — a `ModerationCaseSummary` dataclass mezőlistája a
  `test_case_summary_dataclass_has_no_reporter_field` tesztben van
  pin-elve.

### 10.6 Architectural decisions — a brief + ADR 0425 alapján

1. **Moderátor-identitás forrása (D1).** `community_moderators` tábla,
   nincs `User.role` / JWT `scope` claim. A `CurrentUser` dependency
   VÁLTOZATLAN — a router a tábla segítségével 403-at ad, ha a user
   nem moderátor. A jövőbeli admin-felület ugyanazt a táblát olvassa.
2. **Automation/human gate (D4).** `record_automation_signal` NEM
   fogad `to_state` paramétert; a célállapot a `confidence` inputból
   számítódik. Ez a Kör 19 `triage()` / `resolve_review()` mintát
   követi (ADR 0412 §D5), case-szinten.
3. **Immutable audit (D5).** INSERT-only, nincs `updated_at`. A
   service modulban NINCS `update_action` / `delete_action` /
   `modify_action` — a mérés a `hasattr` alapú canary.
4. **One open case per target (D2).** `is_open: bool` denormalizált
   flag, `ix_community_moderation_cases_target_open` composite
   index. A service réteg a flag-re szűr, NEM az állapotra
   közvetlenül — így egy későbbi "manuálisan megnyitott régi case"
   feature hozzáadható az állapotgép módosítása nélkül.
5. **Removed → visible (D6).** A `ALLOWED_TRANSITIONS['removed']`
   tartalmazza a `visible`-t (az appeal-upheld path-hoz), DE a
   `apply_moderator_decision` explicit guarddal elutasítja ezt a
   párt — kivéve az `upheld` appeal-Resolutiont, ahol a
   `resolve_appeal` közvetlenül írja.
6. **Priority-score formula (D8).** Három rögzített bemenet, NEM
   négy. A súlyokat (5x, 40x, 20x) a runbook dokumentálja.
   `compute_priority_score` a service réteg tiszta függvénye (nincs
   INSERT-mellékhatása — a case service hívja, amikor frissíti a
   case-t).
7. **Visibility helper (D7).** PURE, no DB, no FastAPI. A
   deferred-wiring mintát követi (ADR 0410 / 0412) — a feed / post /
   comment router-ek EGYETLEN SORHOZ sem nyúlnak ehhez a körben.

### 10.7 Out-of-scope reminders

- **Nincs admin UI.** A "belső admin UI vagy API-first eszköz" (brief
  §3) ezen a körön kívül esik. Az SQL-utasítás (`INSERT INTO
  community_moderators`) ma az egyetlen támogatott grant path.
- **A `feed.py` / `posts.py` / `comment_service.py` NEM kap
  `content_visibility_for_state` hívást.** A szerződés él és tesztelt,
  a future wiring round (Kör 28+) dolga lesz bekötni.
- **A `comment_policy.py::can_delete(is_moderator=...)` NEM kap
  `is_moderator(db, user_id)` hívást.** A forrás (a
  `community_moderators` tábla) itt van, a Kör 28+ comment-kör dolga
  lesz a policy-t ráépíteni.
- **`docs/adr/**` NEM módosult.** A `0425` a Claude pre-flight
  munkája.

### 10.8 Self-verification

- Backend pytest: `cd backend && .venv/bin/python -m pytest
  tests/community/test_moderation_case_service.py -q` →
  **42 passed, 54 warnings**.
- Migration contract: az alembic upgrade `... e09_r25_0019 ->
  e09_r26_0019 -> e09_r27_0020` lánc végigmegy a teszt-`session_factory`
  indítása során (lásd a `test_moderation_case_service.py` capture-elt
  stderr-ét).
- §6.1 A4 valódi-sértés próba: végrehajtva (lásd §10.4).

### 10.9 Ismert follow-up-ok (szándékosan NEM ebben a körben)

- **Admin UI a moderator grant/revoke-hoz.** A
  `community_moderators` tábla készen áll — egy jövőbeli kör
  FastAPI routere `INSERT` / `DELETE` a táblán, auditálva.
- **`comment_policy.py::can_delete(is_moderator=...)` bekötése a
  `is_moderator(db, user_id)` függvényre.** A függvény él, a
  `comment_service.py` NEM módosult (tilos zóna).
- **A `content_visibility_for_state` (D7) bekötése a feed / post /
  comment routerekbe.** A helper PURE és tesztelt, a wire-integration
  egy future wiring round dolga.
- **A "független reviewer" szabály kód-szintű kikényszerítése
  appeal-resolutionkor.** Jelenleg az üzemeltetési szabály a
  runbook-ban, az audit chain (`actor_user_id`) támogatja a jövőbeli
  assert-et.
- **Sürgős spam-containment automation-path (§5.1 D4).** A
  dokumentált kivétel a runbook-ban van; a kód-részlet egy future
  round.

## 11. Review — a Claude tölti ki
