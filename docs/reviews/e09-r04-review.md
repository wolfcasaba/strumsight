# E09-R04 — Review

Brief: `docs/rounds/e09-r04-profile-privacy-and-audience-policy.md`
ADR: `docs/adr/0398-profile-privacy-audience-policy-and-access-control.md`
Diff: `git diff c13c7f72...802a6656` (base `main`, round branch
`minimax/e09-r04-profile-privacy-and-audience-policy`)
Reviewer: Claude Sonnet 5 (orchestrátor) + `security-reviewer` subagent
(risk="high") · Dátum: 2026-08-22
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 2 · NOTE: 3

A kör két menetben futott: az implementer (MiniMax M3) helyesen `blocked`-ot
jelzett, mert a §6 mind a hat acceptance-cellája zöld volt, de egy, a kör
hatókörén kívüli, MEGLÉVŐ CI-teszt (`test_migrations.py::
test_downgrade_one_revision_drops_only_community_tables`) determinisztikusan
elbukott egy OSZLOP-szintű migráción (az L411→L413 minta harmadik
láncszeme). Az orchesztrátor önjavítással (brief §0.1, `docs/LESSONS.md`
L415) feloldotta: az `allowed_paths` szűken bővült a teszt-fájllal, a teszt
séma-pillanatkép-alapúra generalizálva (mind tábla-, mind oszlop-szintű
migrációkat fed a jövőben), és az implementer egy második, javító körben
commitolta a fixet. A `docs/LESSONS.md` bővítés tévedésből bekerült a
round-branchbe is — ezt egy review-oldali javító commit (`802a6656`)
eltávolította (a LESSONS.md a post-merge záró rituálé dolga, nem a
round-branché); a scope-audit ezután tiszta.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | A szerver minden readnél policyt alkalmaz | ✅ | `test_a1_evaluate_profile_access_returns_an_enum_member` (18 eset), `test_a1_no_policy_less_path_in_source`, `test_content_evaluate_uses_same_order_as_profile_evaluate` — mind ZÖLD, saját futtatással megerősítve |
| A2 | Block mindig felülírja a follow/club-ot | ✅ | `test_a2_*` (3 teszt) + FÜGGETLEN mutation-próba (saját, a sorrend felcserélve PUBLIC-ág elé) → 3 teszt PIROS, visszaállítva ZÖLD |
| A3 | Private profil olvasása jogosultság nélkül csak `SUMMARY` | ✅ | `test_a3_*` (3 teszt), ZÖLD |
| A4 | Followers-only tartalom csak accepted follow után | ✅ | `test_a4_followers_content_hidden_from_pending_follow` + 2 másik, ZÖLD |
| A5 | Az alapértelmezett profil nem `public` | ✅ | `test_a5_*` (3 teszt) + FÜGGETLEN mutation-próba (ORM default → `"public"`) → `test_a5_orm_default_for_visibility_is_followers` PIROS, visszaállítva ZÖLD |
| A6 | Stale privacy update elutasítva | ✅ | `test_a6_*` (5 teszt) + FÜGGETLEN mutation-próba (stale-check kikapcsolva) → 2 teszt PIROS, visszaállítva ZÖLD |

Mind a hat cellát a `security-reviewer` subagent is önállóan, a jelentett
tesztkészlettől függetlenül verifikálta (lásd lent).

## Scope-audit

```
$ python3 tools/scope-audit.py --repo /tmp/review-e09-r04 \
    --brief docs/rounds/e09-r04-profile-privacy-and-audience-policy.md --base ee9079e7
Legacy scope audit OK (ee9079e72fe0..802a6656e114, 10 changed path(s), 0 generated/ignored)
```

Engedélyezett fájlokon kívüli változás: **nincs** (a `docs/LESSONS.md`
kilépés a `802a6656` javító commitban rendezve — ld. Összegzés).

## Megállapítások

### F1 — MINOR — Optimistic-concurrency ellenőrzés TOCTOU-rés párhuzamos írónál

- **Fájl:** `backend/app/community/routers/privacy.py:155-165`
  (`update_privacy_settings`)
- **Probléma:** a `resource_version`-ellenőrzés Python-szinten, memóriában
  történik (`if _as_utc(payload.resource_version) != _as_utc(settings_row.
  updated_at)`), majd a sor mezőit módosítva `db.flush()` — nincs feltételes
  `UPDATE ... WHERE updated_at = :expected` és nincs `SELECT ... FOR UPDATE`
  zárolás. PostgreSQL READ COMMITTED alatt két egyidejű, egyaránt friss
  `resource_version`-nel induló írás mindkettő sikeresen lezárulhat — a
  második felülírja az elsőt (lost update), a 409-garancia csak SZEKVENCIÁLIS
  hívásokra áll.
- **Hatás:** ma nem kihasználható — a router NINCS bekötve az élő appba
  (`build_community_router` csak `routers/profile`-t importál), tehát
  konkurens HTTP-hívó nem létezik. Ha egy jövőbeli kör bekötné a routert
  ANÉLKÜL, hogy ezt a rést zárná, a privacy-race élessé válna.
- **Kötelező javítás:** a bekötő kör (Kör 5+) a `UPDATE` feltételéhez adja
  hozzá az `updated_at = :expected_version` WHERE-ágat (vagy explicit
  sor-zárolást), és a 0 affected-row esetet fordítsa `StalePrivacyUpdateError`-ra.
- **Ellenőrzés:** egy jövőbeli, két egyidejű írót szimuláló teszt (két
  session ugyanarra a sorra, azonos kezdő `resource_version`-nel) — ez a kör
  scope-ján kívül esik (a router hívó nélküli), ezért NEM ennek a körnek a
  javítandója.
- **Státusz:** OPEN (dokumentálva, nem ennek a körnek a hatásköre — a
  bekötő kör brief §0.0-jába kerüljön be előfeltételként).

### F2 — MINOR — `_get_or_create_settings_row` docstring nem egyezik a viselkedéssel

- **Fájl:** `backend/app/community/routers/privacy.py:104-133`
- **Probléma:** a docstring ("...creating one with default visibility/
  audience if it doesn't exist yet") get-or-create szemantikát ígér, de a
  függvény törzse hiányzó sor esetén `HTTPException(404)`-et dob (nincs
  `INSERT`). A tényleges viselkedés helyes és a projekt "nincs
  get-or-create" precedensét követi (ADR 0395/0396) — csak a docstring
  félrevezető.
- **Hatás:** alacsony — egy jövőbeli olvasó (implementer vagy reviewer) a
  docstringre hagyatkozva téves feltevéssel építkezhetne.
- **Kötelező javítás:** a docstring cseréje a tényleges viselkedésre
  ("raises 404 if the row doesn't exist yet — no get-or-create, matching
  ADR 0395/0396").
- **Ellenőrzés:** nincs teszt-igény, tisztán doc-fix.
- **Státusz:** OPEN, halasztva — nem blokkol; a következő, `routers/
  privacy.py`-t érintő kör (a bekötő Kör 5+, F1-gyel együtt) javítsa. Egy
  harmadik implementer-kör dispatch-elése egyetlen docstring-sorért nem
  arányos a MINOR súlyossággal.

### N1 — NOTE — Enum-bypass fail-closed, DB-oldali CHECK nélkül is

A `community_privacy_settings.visibility`/`.audience_default` egy
korlátlan `String` oszlop (ADR 0398 §1 szándékos döntése), DB-szintű
`CHECK` nélkül. A `security-reviewer` próbája megerősítette: egy érvénytelen
DB-string a Python `is` azonosság-összehasonlítás miatt a policy egyik `is
ProfileVisibility.PUBLIC` ágát sem üti el, tehát fail-closed (`SUMMARY`/
`False`) — nem disclosure, legfeljebb egy jövőbeli `PrivacySettingsOut`
szerializáció dobna 500-at egy korrupt soron (availability, nem
biztonsági rés). Nem igényel javítást.

### N2 — NOTE — A router hívó nélküli, auth nélkül — biztonságosan halasztva

`routers/privacy.py` MA nincs bekötve (`build_community_router` nem
importálja), és a `public_id` `uuid4` — nem enumerálható. A hiányzó
caller-identitás ellenőrzés tehát ma nem kihasználható; a bekötő körnek
EGYSZERRE kell megoldania az authz-t ÉS az F1 concurrency-rést.

### N3 — NOTE — `docs/security/community-access-matrix.md` cellánként egyezik a kóddal

Kereszt-ellenőrizve a `access_policy.py` tényleges elágazásaival — nincs
eltérés a dokumentált és a tényleges mátrix között.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (saját, izolált `/tmp/review-e09-r04` klónban, csővezeték nélkül) |
| analyze | zöld | ✅ |
| test test/core/architecture_dependency_test.dart | zöld | ✅ |
| architecture | zöld | ✅ |
| secrets | zöld | ✅ |
| l10n | zöld | ✅ |
| backend ruff format | zöld | ✅ |
| backend ruff check | zöld | ✅ |
| backend pytest (321 teszt, TELJES suite) | zöld | ✅ (saját futtatás, `802a6656` HEAD-en) |
| backend `test_access_policy.py` (39 teszt) | zöld | ✅ + 3 FÜGGETLEN mutation-próba mindegyike a várt módon PIROS majd ZÖLD |
| CI (teljes suite + property + APK) | — | dispatch a review UTÁN, merge előtt (ld. lent) |

**Folyamati megjegyzés (nem BLOCKER, mert a végleges kimenet tiszta):** az
első implementer-futás a `round-gate.sh`-t háromszor `| tail` mögé kötve
futtatta (tiltott alak), a javító kör pedig a `round-gate.sh`-t magát
csővezeték nélkül futtatta, de egy belső "round-auditor" al-lépés a
`pytest`-kimenetet még mindig `| grep`/`| head`/`| tail` mögé kötötte
diagnosztikai célból. Az AUTORITATÍV bizonyítékot (a teljes, csonkítatlan
"321/321, 100%" kimenetet) mindkét esetben saját, független, izolált
klónban futtatott paranccsal kereszt-ellenőriztem — a mért eredmény
(minden gate zöld) megerősítve, függetlenül a jelentés formai fegyelmétől.

## Merge-döntés

ADR 0052: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → **merge
engedélyezett**. Az F1/F2 MINOR leletek nem blokkolnak — mindkettőt a
bekötő kör (Kör 5+) előfeltételeként dokumentáljuk (HANDOFF/RTM), nem
igényelnek harmadik javító kört ebben a rundában.
