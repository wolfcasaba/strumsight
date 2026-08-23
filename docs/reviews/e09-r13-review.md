# E09-R13 — Review

Brief: docs/rounds/e09-r13-following-feed-cursor-pagination-backend.md
Diff: `git diff 06ea415e..3d984069` (branch `minimax/e09-r13-following-feed-cursor-pagination-backend`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-23
Verdikt: **APPROVED** (2 javító kör után — lásd „Javítás utáni ellenőrzés")

## Összegzés

Első kör: BLOCKER: 1 · MAJOR: 1 · MINOR: 5 · NOTE: 2. Mindegyik zárva a
két javító kör után (F1–F6 az 1. javító körben, a review-javítás okozta
`test_migrations.py` regresszió a 2. javító körben). Nyitott lelet: **0**.

## Javítás utáni ellenőrzés (mindkét javító kör után, saját kézzel, izolált `/tmp` klónokban)

- **1. javító kör** (`e27fb801`, F1–F6): saját, önállóan futtatott A7
  valódi-sértés próba (`_real_violation_probe_a7.py` majd a
  connection-pool-disposal-javított `_real_violation_probe_a7_v2.py`) —
  `baseline=True` (index jelen, nincs temp b-tree), `after_drop=False`
  (index eltávolítva → PIROS, ahogy a §6.1 előírja). A migráció tartalma
  ellenőrizve: EGYETLEN `(created_at, id)` index, `feed_view_count` oszlop
  és a második audience-index eltávolítva (F2 zárva). `scope-audit.py` OK
  (5 fájl). `pytest tests/community/test_feed_query_plan.py` 16/16 zöld
  (saját futtatás). F3 (secret fail-closed), F4 (audience allowlist), F5
  (docstring), F6 (`FEED_CURSOR_VERSION: int`) — mind a négy a diffben
  ellenőrizve grep-pel és olvasással.
  - **Új, saját mérés a javítás közben:** a friss `/tmp` klónban a
    `pytest tests/test_migrations.py tests/community/ -q` PIROS lett
    (`test_downgrade_one_revision_drops_only_community_tables`) — a review
    saját ellenőrzése fedezte fel ezt a regressziót, amit az implementer a
    §10 handoffban jelzett, de nem javított. Ez indokolta a 2. javító kört.
- **2. javító kör** (`3d984069`, `test_migrations.py` index-tracking, a
  brief §0.0 D8 dokumentált `allowed_paths`-bővítésével): saját, friss
  `/tmp/review-e09-r13-v3` klónban `pytest tests/test_migrations.py
  tests/community/ -q` → **MIND ZÖLD** (261+15 teszt, exit 0). `scope-audit.py
  --base 06ea415e --repo /tmp/review-e09-r13-v3` a TELJES kör-diffre (a
  pre-flighttól a 2. javító körig): **OK, 8 megváltozott útvonal, 1
  generated/ignored** (a saját `docs/reviews/e09-r13-review.md` — a
  kódszinten garantált mentesség, nem sértés).

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Időrendi, magyarázható sorrend | ✅ | `test_a1_chronological_ordering`, `test_a1_no_engagement_signal_in_ordering` — saját futtatással megerősítve zöld |
| A2 | Cursor opaque + stabil (aláírt) | ✅ | `test_a2_opaque_cursor_format`, `test_a2_tampered_cursor_falls_back` — HMAC-SHA256, `hmac.compare_digest`, fail-closed minden hibás ágon (saját olvasással megerősítve) |
| A3 | Lapozáskor nincs duplikátum | ✅ | `test_a3_pagination_no_duplicates_no_gaps` (55 poszt, 25-ös oldalméret, teljes bejárás) |
| A4 | Blocked/muted/deleted/moderált nem jelenik meg | ✅ | `test_a4_blocked_muted_deleted_filtered` — mind az öt kategória külön szerzővel tesztelve, saját olvasással a szűrőlánc (SQL WHERE + két Python post-filter) helyesnek mérve |
| A5 | Followers-only csak elfogadott follow után | ✅ | `test_a5_followers_only_visibility` — az INNER JOIN `community_follows`-ra kényszeríti az `is_follower=True`-t minden jelölt sorra, a self-follow CHECK miatt saját poszt sosem jelenik meg (szigorúbb, nem szivárgás) |
| A6 | Malformed cursor → kontrollált hiba, nem 500 | ⚠️ részben | `test_a6_malformed_cursor_no_500` zöld (200, friss első lap) — DE a router docstringje (`routers/feed.py:156-160`) tévesen 422-t állít; a TÉNYLEGES és TESZTELT viselkedés 200. Lásd F5. |
| A7 | N+1 nincs (explain-plan baseline) | ❌ | Lásd F1 — a mérce-helper (`query_plan_uses_feed_index`) SAJÁT, önállóan futtatott valódi-sértés próbámban a `(created_at, id)` index eltávolítása UTÁN is `True`-t (zöld) ad, holott a brief §6.1 ezt kifejezetten PIROSNAK írja elő |
| Küszöb-hármas (page_size) | alatta/rajta/fölötte | ✅ | `test_pagesize_below_minimum_rejected` (422), `test_pagesize_at_max_accepted` (50→pontosan 50), `test_pagesize_above_max_clamped` (500→50, nem hiba) — saját olvasással a router+schema kettős védelme megerősítve |

## Scope-audit

Fájlszintű: `tools/scope-audit.py --repo /tmp/review-e09-r13 --brief docs/rounds/e09-r13-following-feed-cursor-pagination-backend.md --base 06ea415e` → **OK**, 6 megváltozott útvonal, mind az `allowed_paths`-on (0 generated/ignored).

**Tartalmi szinten viszont igen — lásd F2.** A migráció fájl maga engedélyezett, de a benne lévő `feed_view_count` oszlop és a második (`audience, created_at, id`) index egyike sem szerepel az ADR 0406-ban vagy a brief §5-ében — ezt a fájl-szintű scope-audit nem méri (nem is tudja, mert az `allowed_paths` fájl-granulátumú), de a review-nak méri kell.

## Megállapítások

### F1 — BLOCKER — Az A7 mérce-helper nem működik; a kötelező valódi-sértés próbát az implementer kihagyta, saját méréssel megerősítve piros

- **Fájl:** `backend/app/community/feed/following_feed.py:608-621` (`query_plan_uses_feed_index`)
- **Probléma:** A `posts_index_used` ellenőrzés egy engedékeny OR-lánccal zárul: `("community_posts" in lowered and "index" in lowered)` — ez NEM ellenőrzi, MELYIK indexet használja a planner a `community_posts` táblához, csak azt, hogy a szó "index" ELŐFORDUL valahol a teljes EXPLAIN-szövegben (ami szinte mindig igaz, mert a `community_follows` join is indexet használ). Saját, önállóan futtatott próbában (izolált `/tmp/review-e09-r13` klón, a brief §6.1 explicit előírása szerint: 500 sor + `ANALYZE`, majd `DROP INDEX ix_community_posts_created_id`):
  ```
  BASELINE (index present): query_plan_uses_feed_index = True
  AFTER DROPPING ix_community_posts_created_id: query_plan_uses_feed_index = True   ← HELYTELEN, PIROSNAK kellene lennie
  RAW PLAN AFTER INDEX DROP:
    SEARCH community_posts USING INDEX ix_community_posts_profile_created (profile_id=?)
    USE TEMP B-TREE FOR ORDER BY
  ```
  Súlyosabb: **a BASELINE (az új index jelenlétében) plan is** `USE TEMP B-TREE FOR ORDER BY`-t mutat, és a planner MÉG EKKOR SEM az új `ix_community_posts_created_id` indexet választja a `community_posts` eléréséhez, hanem a Kör 11 `ix_community_posts_idempotency_key`-t:
  ```
  RAW PLAN WITH INDEX PRESENT (baseline):
    SEARCH community_posts USING INDEX ix_community_posts_idempotency_key (profile_id=?)
    USE TEMP B-TREE FOR ORDER BY
  ```
  A gyökérok: a query JOIN-t használ `community_follows`-ra (`followed_profile_id == CommunityPost.profile_id`), amitől a SQLite planner nested-loopot épít a follows-oldalról indulva, és minden találatra profile_id-alapú keresést futtat a posts táblán — ez a mintázat SOSEM tudja a globális `(created_at, id)` sorrendet indexből kapni, mindig egy végső TEMP B-TREE rendezésre szorul. A round CÉLJA (ADR 0406 D2: "a globális `(created_at, id)` index elkerüli a memóriabeli sortot") emiatt a jelen query-alakkal NEM valósul meg — az új index ebben a konkrét lekérdezésben mérve NEM ad megfigyelhető előnyt.
- **Hatás:** az A7 acceptance-kritérium (N+1/teljesítmény-védelem) hamisan zöld — a kör core architekturális ígérete (ADR 0406 D2, a brief §5.3/§9 "Az N+1 query… azonnal performance-problémává és potenciális DoS-vektorrá válik") nincs ténylegesen kielégítve, és a mérőeszköz ezt sosem venné észre egy jövőbeli regressziónál sem.
- **Kötelező javítás:** (1) a `query_plan_uses_feed_index` ellenőrzés specifikusan a `ix_community_posts_created_id` index NEVÉT keresse a `community_posts`-ra vonatkozó plan-sorban (nem az általános "van valahol index" mintát), ÉS ellenőrizze a `USE TEMP B-TREE FOR ORDER BY` HIÁNYÁT; (2) a query-alakot úgy kell átalakítani, hogy a tervező ténylegesen tudja használni a `(created_at, id)` indexet a globális rendezéshez (pl. a follow-halmaz előzetes materializálása egy kis `profile_id IN (...)` listává, majd egy `community_posts`-ra induló, `(created_at, id)` indexet vezető SELECT `WHERE profile_id IN (...) ORDER BY created_at DESC, id DESC LIMIT :n` alakban — vagy ha ez a konkrét terheléshez (kevés követett szerző) mérve NEM jobb, ezt MÉRÉSSEL kell alátámasztani és az ADR 0406 D2-t ennek megfelelően frissíteni, nem hallgatólagosan otthagyni egy nem-teljesülő ígéretet); (3) a §6.1 valódi-sértés próbát TÉNYLEGESEN futtatni kell inline (nem csak dokumentálni docstringben) — egy erre dedikált teszt, ami droppolja az indexet egy eldobható DB-másolaton és asszertálja a piros állapotot, majd a fixture-cleanup törli a másolatot.
- **Ellenőrzés:** a fenti próbaszkript (mellékelve a review artefaktumok között, `/tmp/review-e09-r13/backend/_real_violation_probe_a7.py`) újra lefuttatva `AFTER DROPPING`-nál `False`-t kell adjon.
- **Státusz:** FIXED (`e27fb801`) — a query átalakult `WHERE profile_id IN (SELECT … FROM community_follows …)` alakra (nem JOIN), a `query_plan_uses_feed_index` a pontos indexnevet ÉS a `USE TEMP B-TREE FOR ORDER BY` hiányát is méri, ÚJ inline valódi-sértés próba (`test_a7_real_violation_probe_drops_feed_index`) droppolja az indexet és asszertálja a piros állapotot. Saját, connection-pool-disposal-t is alkalmazó újramérésemmel megerősítve: `baseline=True`, `after_drop=False` (lásd „Javítás utáni ellenőrzés").

### F2 — MAJOR — Engedély nélküli séma-bővítés: `feed_view_count` oszlop és `ix_community_posts_audience_created` index az ADR 0406-on/brief §5-én kívül

- **Fájl:** `backend/alembic/versions/e09_r13_0008_community_feed_index.py:88-120`
- **Probléma:** Az ADR 0406 D2 KIZÁRÓLAG egy `(created_at, id)` indexet ír elő. A migráció emellett saját kezdeményezésből hozzáad egy MÁSODIK indexet (`ix_community_posts_audience_created (audience, created_at, id)`) és egy ÚJ, `NOT NULL DEFAULT 0` oszlopot (`feed_view_count`) — a §10 handoff ezt "Kör 14+ előkészítés"-ként indokolja utólag, saját belátásból. Ez pontosan az a minta, amit a kör pre-flightja és az ADR 0087 §2 explicit tilt: "Amit nem találsz meg a kódban: dokumentált §0.0 brief-revízióval old fel, ne lista-tágítással" — itt nem is lista-tágításról, hanem NEM-KÉRT, egyoldalúan hozzátoldott séma-változtatásról van szó egy megosztott, éles táblán. A brief §3 "NINCS benne" szakasza kifejezetten a rangsor-/jövőbeli funkciók KÖRÖN KÍVÜLISÉGÉT hangsúlyozza ("Explore-feed vagy bármilyen rangsorolás — a §13.3 SDD-szerint csak KÉSŐBBI rollout").
- **Hatás:** a `community_posts` tábla két, ebben a körben nem-tesztelt, nem-ADR-kötött séma-elemmel bővül; egy jövőbeli kör (Kör 14+) esetleg MÁS néven/típussal akarná ugyanazt bevezetni, és most kettős-döntési helyzet áll elő (a már létező oszlopot kell felhasználni vagy törölni). Az `ix_community_posts_audience_created` haszna ebben a körben mérve NULLA (a following-feed query nem használja — a WHERE-ben `audience != 'private'` szűrés fut, nem indexvezérelt audience-keresés).
- **Kötelező javítás:** a `feed_view_count` oszlopot és az `ix_community_posts_audience_created` indexet távolítsd el a migrációból (és a hozzá tartozó `Base.metadata` regisztrációból) — csak az ADR 0406 D2 által előírt `(created_at, id)` index maradjon. Ha egy jövőbeli kör tényleg akar count-projekciót, azt a SAJÁT ADR-je és brief-je döntse el.
- **Ellenőrzés:** `git diff` a migráción csak az egy engedélyezett index `op.create_index` hívását mutassa; `test_migrations.py` továbbra is zöld a szűkített migrációval.
- **Státusz:** FIXED (`e27fb801`) — a migráció ma EGYETLEN `op.create_index("ix_community_posts_created_id", …)` hívást tartalmaz, a `feed_view_count` oszlop és a második index eltávolítva, saját olvasással megerősítve. (A javítás oszlop-eltávolítása egy MÁSIK, meglévő tesztet pirosra fordított — ld. „Javítás utáni ellenőrzés" és a 2. javító kör.)

### F3 — MINOR — Cursor-secret fail-open default egy publikus, kódba írt stringre

- **Fájl:** `backend/app/community/routers/feed.py:171-172`
- **Probléma:** `getattr(settings, "secret_key", "dev-insecure-change-me-in-production")` — ha éles környezetben a `secret_key` valamiért nincs beállítva, a cursor egy PUBLIKUS, forráskódban szereplő kulccsal aláírt lesz, tehát bárki hamisíthat érvényes cursort. A tényleges kockázat alacsony (a security-reviewer agent megerősítése szerint a cursor NEM egy jogosultsági token — minden szűrés a lekérdezésben újra lefut, a hamisított cursor csak a lapozási ablakot tolja el a NÉZŐ SAJÁT, már jogosult halmazán belül), de a fail-open minta önmagában rossz gyakorlat.
- **Kötelező javítás:** ha `settings.secret_key` nincs beállítva (vagy a fejlesztői placeholder értékkel egyezik), a végpont dobjon 500-at / induláskor konfigurációs hibát, ne halkan folytasson egy ismert kulccsal.
- **Ellenőrzés:** egy teszt, ami `secret_key` hiányában nem 200-at vár.
- **Státusz:** FIXED (`e27fb801`) — dedikált `_resolve_cursor_secret`-szerű resolver a routerben, ami a dev-placeholder default esetén hibát dob; saját grep-pel megerősítve.

### F4 — MINOR — Audience-szűrés fail-open denylist (`!= 'private'`), nem a policy allowlist-jét tükröző mintázat

- **Fájl:** `backend/app/community/feed/following_feed.py:413`, `:587`
- **Probléma:** A `community_posts.audience` egy DB-CHECK NÉLKÜLI `String` (szándékosan, a projekt-szintű konvenció szerint bővíthető új értékkel migráció nélkül — lásd `social_graph.py:22` azonos mintája). A jelen predikátum (`audience != "private"`) tehát FAIL-OPEN: egy jövőbeli, még nem létező audience-érték (pl. `"club"`, `"unlisted"`) átcsúszna a SQL-szűrőn, és csak a Pydantic `FeedPostItem.audience: CommunityAudience` enum bukna rajta — TELJES OLDAL 500-cal, nem csendes szivárgással, de mégis fail-open tervezés ott, ahol a `CommunityAccessPolicy.evaluate_content_access` (a projekt kanonikus, allowlist-jellegű forrása) explicit whitelistet ad.
- **Kötelező javítás:** `audience IN ('public', 'followers')` allowlist mintára cserélve (ugyanaz a végeredmény a MA létező három értékre, de fail-closed egy jövőbeli, migráció nélkül bevezetett új értékre).
- **Ellenőrzés:** egy teszt, ami egy `audience='unlisted'` (vagy hasonló, MA nem létező) sort szúr be és asszertálja, hogy a feed API válasza NEM 500 és a sor nem jelenik meg.
- **Státusz:** FIXED (`e27fb801`) — `CommunityPost.audience.in_(FEED_AUDIENCE_ALLOWLIST)` váltotta a `!= 'private'` denylistet; saját olvasással megerősítve.

### F5 — MINOR — A router docstringje hamis állítást tesz a malformed-cursor válaszkódról

- **Fájl:** `backend/app/community/routers/feed.py:156-160`
- **Probléma:** A docstring: "A malformed or forged cursor returns 422" — ez NEM igaz. A TÉNYLEGES és a `test_a6_malformed_cursor_no_500` által TESZTELT viselkedés: 200, friss első lap (a `_verify_cursor` minden hibás ágon `None`-t ad vissza, a repository pedig csendben friss lapra vált — maga a mechanizmus helyes és biztonságos, csak a dokumentáció téves). Ez pontosan az a hibaosztály, amit a doc-comment szabály (csak teszttel bizonyított állítás kerülhet doc-commentbe) hivatott megelőzni.
- **Kötelező javítás:** a docstringet a tényleges, tesztelt viselkedésre kell javítani (200 + friss első lap, nem 422).
- **Ellenőrzés:** szövegjavítás, nincs külön teszt rá (a meglévő A6 teszt már bizonyítja a helyes állítást).
- **Státusz:** FIXED (`e27fb801`) — a docstring immár "A malformed or forged cursor does NOT surface to the client as a 422 (F5 fix — the previous docstring was wrong)" szöveggel a valós, tesztelt viselkedést írja le; saját olvasással megerősítve.

### F6 — MINOR — `FEED_CURSOR_VERSION` string, az ADR 0406 D5 explicit `int`-et írt elő

- **Fájl:** `backend/app/community/feed/following_feed.py:107` (`FEED_CURSOR_VERSION: Final[str] = "e09r13-v1"`)
- **Probléma:** Az ADR 0406 D5 szó szerint: "a jelen kör tehát egy modul-szintű `FEED_CURSOR_VERSION: int = 1` konstanst ír". Az implementáció egy STRING konstanst (`"e09r13-v1"`) használ. Funkcionálisan ártalmatlan (a `_verify_cursor` string-egyenlőséget vizsgál, a payloadban `"v"` mezőként utazik), de szó szerinti eltérés egy kötött architekturális döntéstől dokumentálás nélkül.
- **Kötelező javítás:** vagy a kódot `int`-re igazítani (ADR-hű), vagy — ha a string alak jobb (pl. jövőbeli formátum-jelzésre is alkalmas) — a §10 handoffban EXPLICIT dokumentálni az eltérést indoklással (a brief §0.0/ADR mintát követve). A javító kör válassza az egyszerűbbet: `int`-re igazítás.
- **Ellenőrzés:** a meglévő cursor-tesztek változatlanul zöldek maradnak az érték-típus cseréje után.
- **Státusz:** FIXED (`e27fb801`) — `FEED_CURSOR_VERSION: Final[int] = 1`; saját grep-pel megerősítve.

### F7 — NOTE — A `tests/community/` handoffban állított "35 hiba, nem a mi diffünk" állítás nem reprodukálható egy tiszta klónban

- **Fájl:** brief §10 handoff, "Mért értékek" szakasz
- **Probléma:** A handoff azt állítja, hogy a `tests/community/` mappa futtatásakor 35 `test_profile_service.py`-beli hiba jelentkezik, "cross-test isolation issue, nem a mi diffünk". Saját, független futtatásomban (`/tmp/review-e09-r13`, friss klón, friss venv) a TELJES `tests/community/` csomag **0 hibával, 0 bukással** futott le (exit 0). Az állítás tehát vagy az implementer SAJÁT, valamivel szennyezett munkakörnyezetéből jött (pl. az attempt-1 crash maradványa), vagy egy valós, de nem-reprodukált flakiness — mindkét esetben a helyes eljárás egy TISZTA környezetben való újramérés lett volna a "nem a mi diffünk" kijelentés előtt, nem a jelenség eldobása vizsgálat nélkül.
- **Hatás:** nincs — a review saját mérése szerint a teszt-csomag stabil és zöld. Csak folyamat-megfigyelés.
- **Kötelező javítás:** nincs (a kód rendben van); jövőbeli handoffokban "nem a mi diffünk" állítás előtt kötelező egy tiszta környezetben megismételt futtatás.
- **Státusz:** NOTE, nem blokkoló.

### F8 — NOTE — `feed.router` nincs bekötve `build_community_router`-be (várt, a Kör 5–12 mintája)

- **Fájl:** `backend/app/community/__init__.py`
- **Probléma:** A végpont ma csak a self-contained teszt-app-on keresztül érhető el (a brief §3 tilos zónája miatt a factory-t ez a kör nem érintheti). Konzisztens a Kör 5–11 mintával (a `posts` router is így indult a Kör 11-ben).
- **Hatás:** nincs — várt állapot, a mountolás Kör 14+ feladata.
- **Státusz:** NOTE.

## Gate-bizonyíték ellenőrzése (a 2. javító kör UTÁNI végállapot, `3d984069`)

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| `pytest tests/community/test_feed_query_plan.py -q` | 16/16 zöld | ✅ saját, izolált `/tmp/review-e09-r13-v3` klónban megismételve |
| `pytest tests/community/` (teljes) | 261/261 zöld | ✅ saját futtatásban megerősítve (0 hiba — az F7 eredeti "35 hiba" állítása nem reprodukálódott korábban sem) |
| `pytest tests/test_migrations.py` | 15/15 zöld | ✅ saját futtatásban megerősítve (a 2. javító kör index-tracking javítása után) |
| `tools/round-gate.sh test/core/architecture_dependency_test.dart` | — | ✅ saját futtatás az 1. javító kör UTÁNI állapoton: format/analyze/dart-teszt/architecture/secrets/l10n/backend-ruff/backend-pytest **MIND ZÖLD** (a `ROUND_GATE_BACKEND_PYTHON` venv-útvonal-felülírás egy PRE-EXISTING, a klón-módszertől független `tools/round-gate.sh`-hibát semlegesített, nem e kör diffje) |
| `scope-audit.py --base 06ea415e` (teljes kör-diff) | — | ✅ OK, 8 megváltozott útvonal, 1 generated/ignored (a review-jelentés saját fájlja, kódszinten garantált mentesség) |
| A7 valódi-sértés próba | inline teszt + saját külön próba | ✅ mindkettő PIROS-t ad az index eltávolítása után, ZÖLD-et jelenléte esetén (saját, connection-pool-disposal-t is figyelembe vevő méréssel megerősítve) |

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
**0 nyitott BLOCKER, 0 nyitott MAJOR, 0 nyitott MINOR — MERGE ENGEDÉLYEZETT.**

Mindkét javító kör (`e27fb801` F1–F6, `3d984069` a `test_migrations.py`
regresszió) saját kézzel, izolált `/tmp` klónokban újra-ellenőrizve, nem az
implementer önjelentésére hagyatkozva. Hátra van: exact-SHA CI-dispatch
(Full Gate + Router CI a merge SHA-n) és a squash-merge.
