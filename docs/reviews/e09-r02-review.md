# E09-R02 — Review

Brief: `docs/rounds/e09-r02-backend-community-module-and-migration.md`
Diff: `fe8cee54..7e8bc1e5` on `minimax/e09-r02-backend-community-module-and-migration`
(implementer's own diff for the resumed §0.1 fix is `9be8e613..7e8bc1e5` — see
Scope-audit below for why the two bases differ)
Reviewer: Claude (Sonnet 5) · Dátum: 2026-08-22
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

## Kontextus

Ez a kör két munkaszakaszból áll:

1. **Első implementer-futás** (`05fa154d`, 2026-08-22 12:32): a Community
   modulhatár + első migráció létrehozása. A `test_migrations.py::test_downgrade_one_revision_removes_application_schema`
   teszt bukott, de a fájl akkor nem volt az `allowed_paths`-on — az
   implementer helyesen `blocked`-ot jelzett (H3 halt).
2. **Self-heal** (`a11608b8`, PR #409, már merge-elve `main`-re a session
   indulása előtt): a brief §0.1 revíziója felvette `backend/tests/test_migrations.py`-t
   az `allowed_paths`-ra, és pontos feloldást írt elő (a teszt két esetre
   bontása).
3. **Ez a session**: origin/main (a self-heal) merge-elve a kör-branchre
   (`9be8e613`), majd az implementer folytatta a §0.1 szerinti javítást
   (`7e8bc1e5`).

A review a TELJES branch-diffet nézte át tartalmilag (a Community modul +
migráció + a tesztfelbontás), a scope-audit viszont a self-heal saját,
korábban jóváhagyott munkáját (HANDOFF.md, LESSONS.md, a self-heal
regressziós tesztje) helyesen kizárja — az az a self-heal session saját
hatásköre volt, nem ennek a round-nak a diffje.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Nincs `create_all` alapú Community schema production-ben | ✅ | `community_readiness_failure()` (`backend/app/community/__init__.py:78-124`) csak migration-head + prod-Postgres gate; `test_community_readiness_failure_reports_create_all_disallowed` és a 3 másik readiness-teszt (`test_profile_schema.py:465-540`) |
| A2 | Nem szivárog belső user ID | ✅ | `CommunityProfileOut`/`CommunityPrivacySettingsOut` whitelist-only séma (`schemas/profile.py`), csak `public_id`/`display_name`/`created_at` ill. `public_id`/`updated_at`; `test_profile_out_schema_does_not_expose_internal_id`, `test_response_payload_does_not_contain_internal_id` |
| A3 | Önálló dependency boundary (factory override) | ✅ | `backend/tests/community/conftest.py` saját `FastAPI()`-t épít, NEM `app.main.create_app`-et hívja; `test_module_import_does_not_read_production_env` |
| A4 | Alembic upgrade üres DB-n sikeres | ✅ | `alembic upgrade head` — a gate `[9] backend pytest` cellája + `test_alembic_upgrade_head_applies_community_migration` |
| A5 | Community router hiányzik disabled módban | ✅ | `build_community_router()` `None`-t ad, ha `settings.community_enabled` hamis (`__init__.py:52-68`); `test_router_is_not_mounted_when_disabled` + `test_factory_returns_none_when_community_disabled` |
| A6 | Public UUID egyedi, nem szekvenciális | ✅ | `public_id: Uuid(as_uuid=True), default=uuid.uuid4`, DB-szintű unique index mindkét táblán; `test_public_id_is_uuid4_not_derived_from_internal_id`, `test_public_id_unique_constraint_at_db_level` |
| A7 | User–profile 1:1 constraint kikényszerítve | ✅ | `unique=True` a `user_id`-n (`models/profile.py:73`) + a migráció `unique=True` a `user_id` oszlopon; **valódi-sértés próba lásd lent** |

## Valódi-sértés próba (§6.1, KÖTELEZŐ)

Izolált `/tmp/review-e09-r02` klónban: a `(user_id)` `unique=True` eltávolítva
a `CommunityProfile` modellből (`backend/app/community/models/profile.py:70-75`),
`pytest tests/community -q` futtatva.

- **Eredmény:** `test_duplicate_profile_for_same_user_is_rejected_by_db`
  **PIROSRA vált** (`Failed: DID NOT RAISE <class 'sqlalchemy.exc.IntegrityError'>`) —
  a többi 16 teszt zöld marad, tehát a próba pontosan az A7 cellát fogja meg,
  nem szélesebb kört.
- Módosítás visszaállítva, `pytest tests/community -q` → 17/17 zöld, `git diff`
  üres.

## Scope-audit

`tools/scope-audit.py --repo /tmp/review-e09-r02 --brief docs/rounds/e09-r02-backend-community-module-and-migration.md --base 9be8e6138876d353791029d95137046cb9426ed6`
(a self-heal beépítése UTÁNI HEAD, azaz ennek a folytató munkamenetnek a
tényleges induló állapota):

```
Legacy scope audit OK (9be8e613..7e8bc1e5, 2 changed path(s), 0 generated/ignored)
```

Változott fájlok: `backend/tests/test_migrations.py`,
`docs/rounds/e09-r02-backend-community-module-and-migration.md` (§10 handoff
frissítés) — mindkettő a §0.1 által kiterjesztett `allowed_paths`-on.

Megjegyzés: a `fe8cee54` (pre-flight) bázissal futtatott audit 3 további
"violation"-t is jelez (`HANDOFF.md`, `docs/LESSONS.md`,
`tools/tests/test_e09_r02_migration_downgrade_test_scope.py`) — ezek a MÁR
MERGE-ELT self-heal (PR #409, a saját, korábbi review-jával lezárva) saját
kör-brief-en kívüli, de a self-heal tágabb hatáskörében jogos módosításai, nem
ennek a review-nak a tárgya. A teljes `fe8cee54..7e8bc1e5` diff tartalmilag
átnézve (lásd lent), de a scope-ítélet a `9be8e613` bázison alapul.

## Gate-bizonyíték ellenőrzése

Önállóan futtatva izolált klónban (`/tmp/review-e09-r02`, GitHub origin-ről
klónozva a kör-branch HEAD-jén, `7e8bc1e5`):

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (saját futtatás) |
| analyze | zöld | ✅ (saját futtatás) |
| test test/core/architecture_dependency_test.dart | zöld | ✅ (saját futtatás) |
| architecture | zöld | ✅ (saját futtatás) |
| secrets | zöld | ✅ (saját futtatás) |
| l10n | zöld | ✅ (saját futtatás) |
| backend ruff format | zöld | ✅ (saját futtatás) |
| backend ruff check | zöld | ✅ (saját futtatás) |
| backend pytest (74 teszt, benne 17 community + 15 migrations) | zöld | ✅ (saját futtatás) |
| CI (teljes suite + property + APK) | — | dispatch a review UTÁN, merge előtt (ez a jelentés írásakor még nem futott) |

Az implementer saját, korábbi gate-állítása (a folytató munkamenet logjában)
is untruncated, külön parancsként futott — ellenőrizve a stream-json logban,
nem csak bemondásra elfogadva.

## Megállapítások

Nincs BLOCKER, MAJOR vagy MINOR lelet.

### N1 — NOTE — orchestrátor-oldali eljárási megjegyzés, nem kód-lelet

A folytató dispatch során az orchestrátor saját, ideiglenes prompt-fájlját
(`.pipeline-continue-E09-R02.md`) tévedésből a megosztott munkapéldány
git-fájába írta, ami a `mm-round.sh` beépített scope-audit lépésén egy hamis
`VIOLATION`-t (`status=stopped`) okozott. Az orchestrátor a fájlt eltávolította,
a scope-audit-ot kézzel, tisztán újrafuttatta (`OK`), és a `.codex-round-status`-t
javította a valós állapotra. Nem érinti a review verdiktjét — kód-oldali hiba
nem történt, csak az orchestrátor saját munkakönyvtár-higiéniája volt hibás.
Nem igényel javító kört.

## Merge-döntés

Minden helyi gate zöld (saját kézzel, izolált klónban ellenőrizve), az
acceptance mátrix mind a 7 sora bizonyítékkal teljesül, a valódi-sértés próba
a próbán szándékosan bekövetkezett hibát mérte, a scope-audit tiszta. Nincs
nyitott BLOCKER/MAJOR. **A merge feltétele még hátravan: exact-SHA CI-run
zöld a kör-branchen** (ADR 0052/0086 §2) — ezt a review UTÁN dispatch-eli az
orchestrátor, és csak azután squash-merge-el.
