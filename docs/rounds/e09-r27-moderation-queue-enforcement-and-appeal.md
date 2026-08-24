# E09-R27 — Moderation queue, enforcement és appeal

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 27
- **Kör-azonosító:** `E09-R27`
- **Branch:** `<motor>/e09-r27-moderation-queue-enforcement-and-appeal`
- **Előfeltétel:** `E09-R26` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** ~~`ADR 0415`~~ **`ADR 0425`** — a `0415` szám MÁR
  FOGLALT (`docs/adr/0415-community-challenge-invite-lifecycle.md`,
  merge-elve) — a §0.0 pre-flight `tools/round-slots.py reserve-adr` friss
  számot adott. Az ADR-t a Claude írta meg a kör indítási pre-flightjában
  ([`docs/adr/0425-moderation-queue-enforcement-and-appeal.md`](../adr/0425-moderation-queue-enforcement-and-appeal.md));
  az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 19 `media_moderation.py` és a Kör 26 `report_service.py` TÉNYLEGES kimeneti alakját — a queue ezekből táplálkozik, nem újradefiniálja a triage-jelzéseket. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

## 0.0 Pre-flight brief-revízió (2026-08-24, Claude Sonnet 5, `main @ 4222800f`)

**Kockázat = high, indoklás:** a `risk = "high"` besorolás nem egy
`allowed_paths`-beli `high_risk_path_fragments` kulcsszóból fakad (a
brief-lint S7 ezt jelezte) — a kockázat forrása maga a domain: ez a kör
vezeti be az ELSŐ site-wide admin/moderator jogosultsági réteget, és egy
visszavonhatatlan account-enforcement audit-láncot épít. Mindkettő a
kötelező `security-reviewer` subagent bevonását indokolja (AGENTS.md §15).
Részletek: [ADR 0425](../adr/0425-moderation-queue-enforcement-and-appeal.md)
"Kockázat = high, indoklás" szakasza.

**Visszakeresett előzmény (ADR 0312, §4.9):** `node tools/knowledge-rag.mjs --corpus
lessons,halts,adr --top 5 "moderation queue enforcement appeal admin
scope"` → **ADR 0407 §D2** (bm25#2 emb#13, döntő találat — lásd lent).
`node tools/knowledge-rag.mjs --corpus lessons,halts --top 5 "immutable
audit event chain admin authorization scope new"` → nincs közvetlenül ide
vágó lecke a `community_moderation_actions` append-only mintára; a
legközelebbi analóg a Kör 19 `media_moderation.py` audit-oszlop mintája,
ami ADR-szinten (0412 §D5) már dokumentált.

**Mért tények a pre-flightban (ADR 0425 Kontextus 1–9):**

1. Az előre kiosztott `0415` ADR-szám MÁR FOGLALT — javítva `0425`-re
   (fent).
2. `grep -rn "role\|moderator\|is_staff\|is_admin" backend/app/models.py
   backend/app/community/models/profile.py` → **0 találat** — sem a
   `User`, sem a `CommunityProfile` modellen nincs admin/moderator mező.
   Az ADR 0407 §D2 (`comment_policy.py::can_delete(is_moderator=...)`)
   ezt EXPLICIT a "Kör 26/27 admin-auth kör" döntésére bízta — **ez a
   kör az**. A valódi forrás: ÚJ `community_moderators` tábla
   (`backend/app/community/models/moderation.py`, engedélyezett fájl),
   `User`/`CommunityProfile`/`deps.py`/`security.py` módosítása NÉLKÜL
   (ADR 0425 D1 — mindegyik a tilos zónában van).
3. A Kör 19 `media_moderation.py::triage()`/`resolve_review()`
   szétválasztása (ADR 0412 §D5) élő precedens: az automatika sosem írhat
   közvetlenül súlyos végállapotot. Ez a kör ugyanezt a mintát a
   case-állapotgépre és az account-enforcementre vetíti
   (`record_automation_signal` vs. `apply_moderator_decision`, ADR 0425
   D4) — a §6.1 kötelező valódi-sértés próba pontos alanya.
4. `docs/sdd/10-epic-09-community-platform.md` §18.1 az öt-értékű
   `ModerationState` Dart enum forrása
   (`visible/limited/pendingReview/removed/authorOnly`) — Python oldalon
   snake_case string-értékek, plain-`String` + modul-szintű allowlist
   (ADR 0398 §1 minta, ADR 0425 D3).
5. Az alembic-lánc feje `e09_r26_0019` — az új migráció
   `down_revision="e09_r26_0019"`, `revision="e09_r27_0020"` (a fájlnév
   már ezt viseli).
6. A `community_reports` `(target_type, target_id, created_at, id)`
   composite index (Kör 26) kifejezetten erre a queue-ra épült
   (`report.py:52-54`) — a `reporter_profile_id` retaliation-határa (ADR
   0422 D2) öröklődik: SOHA nem kerülhet target-néző/moderator-néző
   válasz-sémába (ADR 0425 D7/D8).
7. A queue-priority három bemeneti jele (report-signal, automation-triage,
   account-history) rögzített, a súlyozás az implementer mérnöki döntése
   — egyik acceptance cella sem méri a priority-t számszerűen, tehát nincs
   hozzá cellahármas-kötelezettség (ADR 0425 D8).
8. A `content_visibility_for_state` (A6) tiszta függvény, ezt a kör NEM
   köti be a `feed.py`/`posts.py` route-okba (egyik sincs az
   `allowed_paths`-on) — ugyanaz a deferred-wiring minta, mint a Kör 19
   triage-seam vagy a Kör 18 `object_store.py` port (ADR 0425 D7).

Részletes indoklás, elutasított alternatívák: [ADR 0425](../adr/0425-moderation-queue-enforcement-and-appeal.md).

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

## 1. Cél

Auditálható, szerepkör-alapú moderációs backend és fellebbezési folyamat — súlyos account action sosem kizárólag automatikus döntés.

## 2. Jelenlegi állapot — mért tények

- A Kör 19 media-triage és a Kör 26 report MA külön-külön léteznek — ez a kör egyesíti őket egy közös moderation-case modellben
- a projekt MA NEM rendelkezik admin/moderator authentication-scope-pal — ez az ELSŐ ilyen jogosultsági réteg

## 3. Scope

**Benne van:** moderation case + action tábla IMMUTABLE audit eventekkel · queue priority: report-signal + automation-triage + account-history, dokumentáltan · moderator/admin auth scope; normál JWT-user nem érheti el · visible/limited/pending-review/removed/author-only állapotátmenetek · súlyos account action ELŐTT emberi megerősítés kötelező (kivéve dokumentált sürgős spam-containment) · appeal submission + state + független review lehetőség · egyszerű belső admin UI vagy API-first eszköz — NEM kerül normál mobil buildbe.

**NINCS benne (tilos):**

- A normál (nem-admin) mobil build módosítása a moderation-UI beépítésével.
- `docs/adr/**` — az ADR 0415-öt a Claude írja.

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

## 5. Kötött architekturális döntések (ADR 0415)

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

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
