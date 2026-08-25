# E09-R27 review — Moderation queue, enforcement és appeal

- **Kör:** E09-R27
- **Branch:** `minimax/e09-r27-moderation-queue-enforcement-and-appeal`
- **Implementer:** MiniMax M3 (a `0d40791d`-ig bezárólag)
- **Orchesztrátor/reviewer:** Claude (Opus 5), **remote Claude Code session**
- **1. körös reviewelt HEAD:** `aedb72b7` (implementer HEAD `0d40791d`
  + §0.3 upstream-sync merge `origin/main` `a88da88f` + a `fix1`
  brief-visszaállítás)
- **ADR:** [0425](../adr/0425-moderation-queue-enforcement-and-appeal.md)
- **Végső döntés:** lásd §9

> ⚠ **Ez a review NEM a szokásos boxon készült.** A kör sávja
> 2026-08-24 20:20-kor megállt (az implementer befejezte a kört, de PR
> nem született és a Router CI piros maradt), és a folytatás egy **remote
> Claude Code konténerben** történt, ahol **nincs Flutter/Dart SDK, nincs
> `gh` CLI, és nincs implementer-motor** (sem MiniMax, sem Codex). Ennek
> két következménye van, mindkettő itt rögzítve:
>
> 1. A `tools/round-gate.sh` **lokálisan nem futtatható** (nincs `flutter`
>    binárás). A Dart-oldali mérce ezért **kizárólag a CI Full Gate**
>    (`full-gate.yml`), az exact head SHA-n — a §2 hivatkozza. A kör
>    diffje **egyetlen Dart fájlt sem érint**, tehát a Dart-oldal
>    regressziómentessége a Full Gate zöldjén múlik, nem lokális mérésen.
> 2. A javító kört (§5.3) **nem az implementer-motor vitte**, hanem a
>    reviewer — mert a motor-oldal ebben a környezetben nem elérhető. Ezt
>    a `sdd-round-driver` skill explicit megengedi („a production kódot a
>    körben NEM te írod — kivétel: explicit user-utasítás, **vagy a
>    motor-oldal nem elérhető** — jelentésben rögzítve"). A user a
>    session elején explicit a kör landolását kérte.

## 1. Jelzés + handoff

Jelzésfájl (`.codex-round-status`) ebben a környezetben **nem érhető el** —
a munkapéldány a megállt boxon maradt. A kör állapotát ezért a **git- és
CI-tényekből** mértem:

| Tény | Mérés |
|---|---|
| 5 implementer-commit (`4549ba3` … `0d40791`) | `git log origin/main..0d40791d` |
| Backend CI ZÖLD a `0d40791d`-en | run [32772982007](https://github.com/wolfcasaba/strumsight/actions/runs/32772982007) |
| **Router CI PIROS a `0d40791d`-en** | run [32772982102](https://github.com/wolfcasaba/strumsight/actions/runs/32772982102) |
| PR: **nincs** | `list_pull_requests state=open` → `[]` |

A §10 handoff kitöltött (10.1–10.9), és a §6.1 kötelező valódi-sértés
próbát dokumentálja — a §5.1-ben ezt **függetlenül újrafuttattam**.

## 2. Gate

**A piros Router CI gyökéroka — F0, javítva a `fix1`-ben.** Három cella
állt pirosan, mindhárom UGYANARRA a leletre mutatva:

```
B4 (base): a brief nem hivatkozza a gate artefaktumot (tools/round-gate.sh)
```

Az implementer a §10 handoff kitöltése helyett **felülírta a teljes
kör-briefet**: a §0 (kör-jelzés/STOP), §3 (scope), §4 (engedélyezett
fájlok), §5 (kötött döntések), §6 (acceptance + mérce-mátrix), **§7
(kötelező ellenőrzések — benne a gate-sor)**, §8 és §9 eltűnt, az §1/§2
helyére a saját beszámolója került. A B4 ennek a **mérhető nyoma**: nem a
lint szigorodott, hanem a kör terve tűnt el a repóból.

A `fix1` doc-only javítás: a §0 és §1–§9 az `origin/main` briefjéből
visszaállítva (ADR-szám a mért `0425`-re), az implementer beszámolója a
handoff alá került (§10.0 / §10.0b), a doc végén lógó `ai-router` blokk a
sablon szerinti helyre, a fejléc alá.

Mért, lokálisan (a Python-oldal itt futtatható):

```
python3 tools/brief-lint.py --open --level base   → nincs lelet (exit 0)
python3 -m pytest tools/tests/test_pipeline_throughput.py \
        tools/tests/test_knowledge_rag.py \
        tools/tests/test_empty_queue_is_not_a_failure.py -q
  → 73 passed, 2 skipped, 56 subtests passed
python3 -m pytest tools/tests -k "brief or queue or pipeline" -q
  → 256 passed, 495 deselected, 219 subtests passed
backend: ruff check → All checks passed
backend: ruff format --check → 132 files already formatted
```

A Dart-oldali gate CI-ben — a run-azonosítók a §9-ben, az exact merge
SHA-n.

## 3. Scope-audit

```
python3 tools/scope-audit.py --repo . \
  --brief docs/rounds/e09-r27-moderation-queue-enforcement-and-appeal.md \
  --base origin/main
→ 8 changed path(s)
→ path outside allowed scope: docs/adr/0425-moderation-queue-enforcement-and-appeal.md
```

**Ez NEM H3.** Az ADR-t a brief §4 explicit az orchesztrátorra bízza
(`docs/adr/**` az implementer TILOS zónája), és a fájl mérve a
**pre-flight commitban** (`4549ba3`, „E09-R27 pre-flight — ADR 0425 +
brief-revízió") érkezett, nem implementer-commitban:

```
git log --oneline --diff-filter=A -- docs/adr/0425-*.md → 4549ba3
```

A maradék 7 útvonal mind a brief §4 listáján van. **Lista-tágítás nincs.**

## 4. Acceptance criteria — tételesen

| # | Kritérium | Állapot | Mérés |
|---|---|---|---|
| A1 | Nem-moderátor JWT-user nem éri el az endpointot | ✅ | `TestAuthScope` ×5, + saját mutation (§5.2) |
| A2 | Állapotgép tesztelt, `removed → visible` review nélkül tiltott | ✅ | `TestStateMachine` ×6 + `TestRealViolationProbeA2` |
| A3 | Audit-lánc immutable | ✅ | `TestAuditImmutability` ×3 + `ProbeA3` ×2, + saját mutation (§5.2) |
| A4 | Automatika önmagában nem enforce-olhat | ✅ | `TestAutomationCannotEnforce` ×3 + `ProbeA4` ×2, + saját mutation (§5.1) |
| A5 | Appeal egyszer nyújtható be | ⚠ → ✅ | `TestAppealFlow` ×4; **a cella vak volt arra, hogy KI költi el** — F1, javítva (§5.3) |
| A6 | Removed tartalom láthatósága state szerinti | ✅ | `TestVisibilityHelper` ×7 |
| A7 | A reportoló identitása nem szivárog | ✅ | `TestReporterIdentityNotLeaked` ×3 |

## 5. Próbateszt / mutation-eredmények

A reviewer **nem fogadta el bemondásra** a §10.4-et: minden próbát izolált
másolaton (`…/scratchpad/probe/backend`), a **production forráson végzett
valódi mutációval** futtattam újra — nem a teszt saját monkeypatchével.

### 5.1 §6.1 kötelező valódi-sértés próba — függetlenül megismételve

Három védelmi vonalat EGYSZERRE nyitottam ki a production kódban
(`case_service.py`), pontosan azt a hibás implementációt előállítva, amit
a brief §6.1 leír („az automatikus triage közvetlenül `removed` +
account-suspend állapotba tesz emberi review nélkül"):

1. `_automation_to_state`: `confidence >= 0.8` → `removed`
2. `AUTOMATION_ALLOWED_TO_STATES` kibővítve `removed`-dal
3. `ALLOWED_TRANSITIONS[visible]` kibővítve `removed`-dal

Eredmény — **5 cella PIROS**:

```
FAILED TestStateMachine::test_automation_visible_to_pending_review
FAILED TestAutomationCannotEnforce::test_automation_cannot_reach_removed
FAILED TestAutomationCannotEnforce::test_monkeypatch_allowlist_alone_does_not_break_A4
FAILED TestRealViolationProbeA4::test_widened_mapping_to_removed_still_caught_by_explicit_guard
FAILED TestRealViolationProbeA4::test_widened_allowlist_and_mapping_still_caught
```

A mutáció visszaállítva; a próbakönyvtár törölve. **A4 valódi mérce.**

### 5.2 További reviewer-mutációk (a §10-en túl)

| Mutáció | Várt cella | Eredmény |
|---|---|---|
| `_require_moderator` auth-gátja törölve a routerben | A1 | **PIROS** — `test_non_moderator_gets_403_on_list`, `…_on_detail` |
| publikus `update_action(...)` hozzáadva a `case_service`-hez | A3 | **PIROS** — `test_case_service_exposes_no_update_or_delete`, `ProbeA3::test_no_public_mutation_api_on_actions` |

Megjegyzés: az auth-gát törlése után a `…_on_decision` cella **zölden
maradt** — helyesen: az `apply_moderator_decision` a **service-rétegben
is** ellenőrzi a moderátor-identitást (védelem mélységben). Ez nem lelet.

### 5.3 Leletek

#### F1 — MAJOR (javítva) — bárki elköltheti a szerző EGYETLEN appealjét

`POST /community/moderation/cases/{id}/appeals` **bármely hitelesített
felhasználót** elfogadott (a router docstringje szó szerint: „Any
authenticated user can submit an appeal"), miközben az A5 szerint
case-enként **pontosan egy** appeal adható be. A kettő együtt abúzus-út:
egy idegen beadja először az appealt egy tetszőleges tartalomra, és a
szerző saját beadása ezután `AppealAlreadySubmitted`-be fut — a
jogorvoslata elveszett. A modul már tartalmazta a szerző feloldásához
szükséges `_target_author_profile_id` helpert; az appeal-úton egyszerűen
nem hívta.

**Javítás:** `submit_appeal` a beadót a target szerzőjéhez köti
(`_is_target_author`, a `users.id → community_profiles.id` 1:1 feloldáson
át), moderátori beadás továbbra is megengedett; minden más
`NotTargetAuthor` → a router **403**. A feloldhatatlan `target_type`
(pl. még be nem drótozott `media`) **fail-closed**: nem lesz megkerülő út.

#### F2 — MAJOR (javítva) — az audit-lánc moderátornak hazudta a szerzőt

Az appeal-beadás audit sora `actor_type = "human_moderator"`-t írt akkor
is, amikor a beadó — a router saját docstringje szerint — közönséges
felhasználó volt. A D5 immutable audit-lánc **egyetlen haszna az, hogy
igazat mond**; egy utólagos auditban ez a sor azt állítaná, hogy egy
moderátor lépett, holott nem.

**Javítás:** új `ACTOR_TYPE_CONTENT_AUTHOR = "content_author"`. A szerző
saját appealje `content_author`, a moderátor nevében beadott appeal marad
`human_moderator`. (Az `actor_type` `String(16)` — a 14 karakteres érték
elfér, migráció nem kell.)

#### F3 — MINOR (javítva) — bizonyítatlan doc-állítás egy versenyhelyzetről

A `get_or_create_case` docstringje azt állította, hogy egy párhuzamos
hívás „az `ix_community_moderation_cases_target_open` indexen keresztül"
veszti/nyeri a versenyt. Az index viszont mérve **`unique=False`** — nem
arbitrál semmit. Az ADR 0425 §D2 kifejezetten megengedi a service-rétegű
mechanizmust (az implementer ezt választotta), tehát az **invariáns
választása rendben van** — a hamis állítás volt a lelet
(AGENTS.md: doc-commentben csak bizonyított állítás).

**Javítás:** a docstring most az igazat mondja — service-rétegű
read-then-insert, az index csak olcsó lookup, a több-írós backend
versenyablaka nyitva marad (SQLite-on ma nem elérhető), a lezárása
partial unique indexszel egy follow-up.

#### F4 — MINOR (javítva) — nem létező kivétel-nevek a modul-docstringben

A modul-docstring `NotAModeratorError` / `AppealAlreadySubmittedError`
neveket említett; a tényleges osztályok `NotAModerator` /
`AppealAlreadySubmitted`.

### 5.4 Follow-up (NEM ebben a körben)

- **N1** — partial unique index a `(target_type, target_id)` párra
  `is_open = 1` mellett, a D2 invariáns több-írós backendre zárásához.
- **N2** — a moderation router **sehol nincs bekötve**: a
  `build_community_router` ma is csak a `profile` routert szereli fel,
  a 13 community routerből 12 (a Kör 26 `reports` is) kívül marad. Ez
  **epic-szintű, korábbról öröklött** hiány (ADR 0395 Következmények 3.
  pont), és a `backend/app/community/__init__.py` a kör tilos zónájában
  van — nem E09-R27 regresszió.

## 6. Security review (risk=high)

A kör `risk = "high"` (auth-scope, moderáció, felhasználói adat), ezért a
biztonsági szempont kötelező. Mérve:

- **Jogosultság:** minden moderation-endpoint a `community_moderators`
  táblán megy át (`_require_moderator` → 403), és a súlyos állapotok
  (`removed` / `author_only`) felé az **egyetlen** út az
  `apply_moderator_decision`, ami a service-rétegben **újra** ellenőrzi a
  moderátor-identitást. A `CurrentUser` JWT-dependency változatlan
  (import, nem módosítás) — a kör nem nyúlt a `deps.py` / `security.py`
  fájlhoz.
- **Automatika-gát (§5.1 ADR-invariáns):** háromrétegű, és mind a három
  réteg kilyukasztása után is PIROS a mérce (§5.1).
- **Retaliation-határ (A7):** a `ModerationCaseSummary` `frozen`
  dataclass, reporter-mező nélkül; az action-sorok `actor_user_id`-ja az
  ELJÁRÓ, nem a bejelentő. A Kör 26 `CommunityReport` join sehol nincs a
  válasz-úton.
- **Talált gyengeség:** F1 (idegen elköltheti a szerző appealjét) —
  **javítva**, saját teszt-cellákkal (`TestAppealAuthorGuard`, 6 cella,
  köztük a fail-closed és a router-403 él).
- A `_target_author_profile_id` és a `_report_signal` csak számol /
  azonosítót old fel; PII nem kerül válaszba.

**Eredmény: PASS** — F1 lezárása után 0 nyitott biztonsági lelet.

## 7. Architektúra + termékhatárok

- `lib/**` **érintetlen** — a kör API-first, ahogy a brief §3 előírja; a
  normál mobil build egyetlen bájttal sem nő.
- Alembic-lánc folytonos és egyfejű: `e09_r27_0020` ←
  `e09_r26_0019`.
- `community_moderation_actions`: **nincs `updated_at` oszlop** — a
  hiány strukturális jel, és a mérce (`test_action_row_has_no_updated_at_column`)
  erre a hiányra fogad.
- PEP 420 namespace package a `moderation/` alatt — a projekt többi
  alkönyvtárának mintája (`services/`, `policies/`, `routers/`).

## 8. Összegzés

| Súly | Darab | Állapot |
|---|---|---|
| BLOCKER | 0 | — |
| MAJOR | 2 (F1, F2) | **javítva a javító körben** |
| MINOR | 3 (F0, F3, F4) | **javítva** |
| NOTE / follow-up | 2 (N1, N2) | nyitva, dokumentálva |

A kör érdemi része **erős**: a §5.1 automatika-gát háromrétegű és
függetlenül mérve is bitel, az A3 immutabilitás strukturális (nem
konvenció), az A7 pedig `frozen` dataclass-szal van kikényszerítve. A két
MAJOR mindkettője **ugyanazon a vak folton** ült: az A5 cella az appeal
**darabszámát** mérte, a **beadó személyét** nem — se a jogosultságát, se
az audit-sorban rögzített szerepét.

## 9. Végső döntés

**APPROVED** — a javító kör (`fix2`) F1–F4-et lezárta, 0 nyitott lelet.

- Végleges HEAD: lásd a PR-t és a §9 CI-táblát a HANDOFF-ban.
- A merge-kapu változatlan (ADR 0052): Full Gate + Router CI + Backend CI
  `success` az **exact** head SHA-n.
