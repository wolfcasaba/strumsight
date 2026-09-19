# E09-R25 — Review

Brief: docs/rounds/e09-r25-club-feed-pinned-post-and-challenge.md
Diff: `git diff main...minimax/e09-r25-club-feed-pinned-post-and-challenge`
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-24
Verdikt: **APPROVED** (javító kör 1 + javító kör 2 után; a risk="high" miatt
kötelező `security-reviewer` agent második, független ellenőrzést is végzett
javító kör 1 után — lásd F2/F3 alább)

## Összegzés

BLOCKER: 0 · MAJOR: 0 (3 talált, mindhárom javítva) · MINOR: 1 · NOTE: 2

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Nem-tag nem éri el a klub feedjét vagy tartalmát | ✅ | `test_a1_non_member_cannot_list_club_feed` + valódi-sértés próba `test_a1_real_violation_probe_drop_membership_check` (a membership-guard kikapcsolásával az outsider kap egy oldalt → PIROS → visszaállítva) |
| A2 | Klub elhagyása után a cache-ből azonnal eltűnik a csak-club tartalom | ✅ | `club_detail_screen.dart:305-326` (`_leave` négy `ref.invalidate(...)` hívása: `clubDetailProvider`, `clubFeedProvider`, `clubPinnedProvider`, `clubChallengesProvider`) + widget teszt `club_detail_screen_test.dart:252` (lásd F4 MINOR — a teszt csak a `clubDetailProvider` újraépülését méri közvetlenül, a forráskód viszont mind a négyet invalidálja) |
| A3 | Pin-jogosultság csak a klub owner/moderator-jáé | ✅ | `test_a3_member_cannot_pin_post`, `test_a3_other_club_moderator_cannot_pin_here` (cross-club guard), `test_a3_owner_can_pin_post`, `test_a3_moderator_of_same_club_can_pin_post`, `test_a3_member_cannot_end_club_challenge`, `test_a3_owner_can_end_club_challenge` |
| A4 | Pin-limit érvényesül (konfigurációból) | ✅ | `test_a4_pin_limit_enforced` + valódi-sértés próba `test_a4_real_violation_probe_drop_pin_limit` (limit monkeypatch 10 000-re → mind a `MAX_CLUB_PINNED_POSTS+2` poszt bekerül → PIROS → visszaállítva) |
| A5 | Club-challenge eligibility a tagságot ellenőrzi | ✅ | `test_a5_non_member_cannot_create_club_challenge` + `test_a5_member_creates_club_challenge_with_public_id_str` (a `club_id` oszlop a `public_id` string-alakját tárolja, NEM a belső bigint id-t — külön assertálva) |
| A6 | Block érvényesül klubon belül is (Kör 8/24 szűrő újrahasznosítva) | ✅ | `test_a6_block_drops_author_from_pinned_list`, `test_a6_block_drops_author_from_club_challenges` |
| A7 | Klub-feed pagination stabil, nincs duplikált post | ✅ | `test_a7_club_feed_pagination_is_stable` (két oldal, diszjunkt post-id halmazok, unió = az összes poszt) |

## Scope-audit

`tools/scope-audit.py --repo /home/ubuntu/ss-mm-e09-r25 --brief docs/rounds/e09-r25-club-feed-pinned-post-and-challenge.md --base 0d198eff`
→ `Legacy scope audit OK (0d198effd48b..c919f0818476, 7 changed path(s), 0 generated/ignored)`.
A `base` a §0.0 pre-flight brief-revízió commitja (a kör tényleges induló
HEAD-je), NEM a Kör 24 merge-commitja — a brief-revízió maga a §2 szerinti
orchestrátor-hatáskör, nem implementer-munka. Mind a 7 megváltozott útvonal
az (időközben bővített) `allowed_paths`-on belül van, a §0.0d javító
addendum utáni migrációs fájllal együtt.

## Megállapítások

### F1 — MAJOR (a review során talált, javító kör 1-ben ZÁRVA) — hiányzó éles alembic migráció a pinned-post táblához

- **Fájl:** `backend/app/community/services/club_content_service.py` (eredeti állapot, `2b3e62ae`)
- **Probléma:** a `community_club_pinned_posts` junction tábla egy PRIVÁT
  `MetaData`-n élt (`_pinned_metadata`), kifejezetten azért, hogy a
  `test_upgrade_head_matches_current_orm_schema` migráció-drift-őr ne vegye
  észre. Nem volt hozzá alembic migráció.
- **Hatás:** egy éles `alembic upgrade head` UTÁN a tábla nem jönne létre —
  a `pin_post`/`unpin_post`/`list_club_pinned` (A3/A4) "no such table"
  hibával bukna élesben, miközben a teszt-fixture (`Base.metadata.create_all`
  a privát metadatán) zölden mutatta a gate-et. A brief §3 scope-ja explicit
  tartalmazza a pin-perzisztenciát — nem elhagyható "következő kör" korlát.
- **Kötelező javítás:** ÚJ migráció (`e09_r25_0019_community_club_pinned_posts.py`,
  `down_revision = e09_r24_0018`) + a `Table` deklaráció költöztetése
  `Base.metadata`-ra.
- **Ellenőrzés:** `backend/tests/test_migrations.py::test_upgrade_head_matches_current_orm_schema`
  — a javítás ELŐTT ezt nem futtattam (a §7 gate_tests nem tartalmazta), a
  javítás UTÁN függetlenül lefuttattam izolált klónban: **15/15 zöld**.
- **Státusz:** **FIXED** (`c919f081`, §0.0d javító addendum +
  javító kör 1). Lásd a §0.0 pre-flight revízió (`0d198eff`) is már
  előre dokumentálta a `club_id` dual-typing kockázatot (ADR 0420 D1/D2
  hivatkozással) — a junction-tábla migráció hiánya egy ATTÓL FÜGGETLEN,
  az implementáció során felmerült új gap volt, amit a review fogott meg.

### F2 — MAJOR (security-reviewer talált, javító kör 2-ben ZÁRVA) — hibás, félrevezető `CLUB_PIN_AUTHORIZED_ROLES` re-export

- **Fájl:** `backend/app/community/feed/club_feed.py:611` (eredeti állapot, `c919f081`)
- **Probléma:** egy MÁSODIK, azonos nevű, de HIBÁS értékű
  `CLUB_PIN_AUTHORIZED_ROLES` konstans élt itt (`= CLUB_ROLE_ALLOWLIST` =
  `{owner, moderator, member}`, TARTALMAZTA a sima tagot), egy doksi-
  kommenttel, ami explicit ARRA biztatott egy jövőbeli router-implementert,
  hogy EZT importálja a pin-jogosultság ellenőrzésére. A HELYES halmaz
  (`{owner, moderator}`) `club_content_service.py`-ban élt ugyanezen a
  néven, és a `pin_post`/`unpin_post` már azt használta helyesen.
- **Hatás:** jelenleg holt kód (0 importáló, `grep` igazolta), de egy
  booby trap — egy jövőbeli router-kör a docstring alapján valószínűleg a
  ROSSZ konstanst kötötte volna be, ami egy sima klub-tagnak pin-jogot
  adott volna (§5.2 sértés).
- **Kötelező javítás:** a hibás re-export + doksi-blokk törlése.
- **Ellenőrzés:** független `security-reviewer` agent találta (2. review-
  kör, javító kör 1 UTÁN), én magam `grep`-pel megerősítettem a hibás
  értéket és a 0 importálót a javítás előtt, majd a diffet a javítás után.
- **Státusz:** **FIXED** (`938faa9f`, javító kör 2).

### F3 — MAJOR (security-reviewer talált, javító kör 2-ben ZÁRVA) — `end_club_challenge` megsérthette a `ck_community_challenges_window_positive` CHECK-et

- **Fájl:** `backend/app/community/services/club_content_service.py`,
  `end_club_challenge` (eredeti állapot, `c919f081`)
- **Probléma:** a függvény nyers `challenge.ends_at = now`-t írt, a "már
  véget ért" guard viszont csak `ends_at <= now`-nál lőtt. Egy JÖVŐBELI
  `starts_at`-tal létrehozott, MÉG EL NEM INDULT challenge azonnali
  lezárása `ends_at = now < starts_at`-ot írt volna, ami a modell
  `CheckConstraint("ends_at > starts_at")`-ját sérti.
- **Hatás:** reprodukálható `IntegrityError` → 500 egy legitim owner/
  moderator saját hívásán (nem külső támadási felület, de valódi,
  determinisztikus bukás — a security-reviewer eredetileg MINOR-nak
  minősítette, ÉN MAJOR-ra emeltem, mert a hiba MOST, a service-függvény
  közvetlen hívásával reprodukálható, nem csak egy jövőbeli router-kör
  problémája).
- **Kötelező javítás:** domain-kivétel (`ClubChallengeNotYetStarted`)
  bevezetése a `now < starts_at` ágra, `ends_at = now` írás helyett.
- **Ellenőrzés:** ÚJ teszt
  `test_a3_owner_end_not_yet_started_club_challenge_raises` — jövőbeli
  `starts_at` + azonnali `end_club_challenge` hívás → asszertálja a
  `ClubChallengeNotYetStarted`-ot, NEM 500-at.
- **Státusz:** **FIXED** (`938faa9f`, javító kör 2).

### F4 — MINOR — az A2 widget teszt túlígéri a saját lefedettségét

- **Fájl:** `test/features/community/presentation/clubs/club_detail_screen_test.dart:252-341`
- **Probléma:** a teszt docstringje és neve azt állítja, hogy a `leave`
  hívás a `clubFeedProvider`/`clubPinnedProvider`/`clubChallengesProvider`
  invalidációját méri, de a tényleges assertion csak a `clubDetailProvider`
  újraépülését számolja (`detailRevisions`); a három screen-local providerre
  nincs önálló, célzott assertion (pl. egy hasonló revízió-számláló).
- **Hatás:** a forráskód (`club_detail_screen.dart:323-326`) TÉNYLEG mind a
  négy providert invalidálja — ellenőriztem közvetlen olvasással — tehát ez
  NEM funkcionális hiba, csak a teszt lefedettségi állítása pontatlan a
  saját dokumentációjához képest.
- **Kötelező javítás:** nem blokkoló; egy jövőbeli kör bővítheti a tesztet
  külön revízió-számlálóval a három screen-local providerre.
- **Ellenőrzés:** —
- **Státusz:** OPEN (follow-up, nem blokkolja a merge-et).

### N1 — NOTE — screen-local providerek produkcióban `UnimplementedError`-t dobnak

A `clubFeedProvider`/`clubPinnedProvider`/`clubChallengesProvider` szándékosan
unwired (§0.0 #3 — Kör 24 `communityClubRepositoryProvider` precedens).
Ez a §0.0 pre-flight revízióban dokumentált, tudatos döntés — a valódi
backend-bekötés egy jövőbeli kör feladata.

### N2 — NOTE — `CLUB_PIN_AUTHORIZED_ROLES` inline definíció a permission-mátrix helyett

A `club_content_service.py` a pin/end-challenge jogosultságot INLINE
definiálja (`club_permissions.py` nincs az `allowed_paths`-on) — az F2
javítás után ez már az EGYETLEN (helyes) definíció a kódbázisban. Egy
jövőbeli kör formalizálhatja `ClubAction.PIN_POST`/`ClubAction.END_CHALLENGE`
akciókként a mátrixban — a §10.6 handoff ezt már jelzi.

### N3 — NOTE — a challenge-write útvonalak (create/end) nem egységes 404-et adnak létezés-vs-tagság között

A security-reviewer mérte: `list_club_feed`/`list_club_pinned`/
`list_club_challenges` (olvasás) egységesen `ClubNotVisible`/
`ClubChallengeNotVisible`-t ad klub-hiányra ÉS nem-tagságra (a repo D7
"egységes 404" konvenciója). A `create_club_challenge`/`end_club_challenge`
(írás) viszont KÜLÖN kivételt ad létezés-hiányra
(`ClubChallengeNotVisible`) és nem-tagságra (`ClubChallengeActorNotMember`)
— egy jövőbeli router, ha ezeket 404/403-ra képezi le, egy létezés-oracle-t
nyitna privát klubokra. Jelenleg NINCS router egyik service-függvényhez
sem (0 HTTP-felület a diffben), tehát ez ma nem élő sérülékenység — egy
jövőbeli router-kör feladata az egységes leképezés, a §10 handoff-ban
rögzítve.

## Gate-bizonyíték ellenőrzése

Mind SAJÁT kézzel, izolált `/tmp/` klónokban, a közös munkapéldánytól
függetlenül — KÉTSZER: javító kör 1 UTÁN (`c919f081`, `/tmp/review-e09-r25`)
és javító kör 2 UTÁN (`938faa9f`, `/tmp/review-e09-r25-2`, friss klón).

| Gate | Állított eredmény | Ellenőrizve (c919f081) | Ellenőrizve (938faa9f, végleges) |
|---|---|---|---|
| `tools/round-gate.sh test/features/community/presentation/clubs/club_detail_screen_test.dart` (9 lépés) | zöld | ✅ 9/9 | ✅ 9/9 (háttérben futtatva, lásd alább) |
| `cd backend && python -m pytest tests/community/test_club_content_service.py -q` | 17/17 | ✅ 15/15 (F2/F3 előtt) | ✅ **17/17** (2 új teszt: F1 real-violation refresh + F3 regresszió) |
| `cd backend && python -m pytest tests/test_migrations.py -q` (F1 javítás ellenőrzése) | 15/15 | ✅ 15/15 | ✅ 15/15 |
| Scope-audit (`--base 0d198eff`) | OK | ✅ 0 violation, 0 generated/ignored | ✅ 0 violation, 1 generated/ignored (a saját review-jelentés, kód szerint mentesítve) |
| CI (teljes suite + property + APK / Router CI) | — | — | ⏳ dispatch a review UTÁN, a merge előtt igazolva |

## Merge-döntés

ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
Mind a HÁROM MAJOR-lelet (F1 hiányzó migráció, F2 hibás re-export, F3
window-CHECK bukás) zárva, mindkét javító kör után a gate-eket SAJÁT kézzel,
friss izolált klónban újrafuttattam — a jelen állapot (`938faa9f`) teljesíti
a LOKÁLIS zöld kaput. A CI-dispatch (`build-apk.yml`/`full-gate.yml` a §3.0
terv szerint + `router-ci.yml`, ha releváns) a merge előfeltétele,
exact-SHA-n igazolva.
