# E09-R13 — Following feed és cursor pagination backend

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 13
- **Kör-azonosító:** `E09-R13`
- **Branch:** `<motor>/e09-r13-following-feed-cursor-pagination-backend`
- **Előfeltétel:** `E09-R12` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** ~~`ADR 0404`~~ → **`ADR 0406`** (ld. §0.0 D1). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 11 `community_posts` TÉNYLEGES oszlopait és indexeit — a feed-query ezekre épül, és a `created_at, id` összetett indexnek léteznie kell a stabil rendezéshez. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

## 0.0 Pre-flight brief-revízió (Claude Sonnet 5, 2026-08-23)

**D1 — ADR-szám korrekció.** A `0404` a brief megírásakor (2026-08-22) volt a
"legmagasabb foglalt+1" heurisztika szerinti szám, de az a sorszám azóta a
Kör 10-hez tartozik (`docs/adr/0404-share-artifact-contracts.md`) — naptári
avulás, ugyanaz a mintázat, mint az ADR 0405 saját sorszám-jegyzete
([[L430]]). A foglaló (`tools/round-slots.py reserve-adr --round E09-R13`)
friss számot adott: **`0406`**. A §5 fejléc "(ADR 0404)" hivatkozását és a
ténylegesen megírt ADR-fájlt **`0406`** alatt kell érteni:
[`docs/adr/0406-following-feed-and-cursor-pagination.md`](../adr/0406-following-feed-and-cursor-pagination.md).

**Kockázat = high, indoklás (S7 zárása):** a `risk = "high"` jogos annak
ellenére, hogy egyik `allowed_paths` elem sem tartalmazza szó szerint a
router high-risk-fragmenslistát (`auth, authorization, camera, credential,
crypto, encryption, migration, payment, privacy, secret, share, upload,
vision`) — ez a kör az ELSŐ, ami egy queryben kombinálja az audience-,
follow-, block-, mute- és moderation-szűrést EGY listázó (sok sort visszaadó)
végponton. Egy hibás szűrési sorrend vagy egy kimaradt predikátum nem egy
poszt szivárgását okozná (mint a Kör 11 GET-jénél), hanem SOK, a nézőre nem
tartozó poszt tömeges, egyetlen kérésben történő kiszivárgását (blokkolt/némított/
followers-only tartalom a feedben) — ez a klasszikus "listázó végpont ugyanaz
a hiba, nagyobb blast radius" minta. A cursor aláíratlansága vagy
manipulálhatósága (A2) pedig a lapozási határ megkerülését tenné lehetővé,
ami a fenti szűrők megkerülésének egy MÁSODIK, független útja lenne.

**Visszakeresés (S8, ADR 0312 §4.9-sorrend szerint):**
- `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "following feed cursor pagination backend query"` →
  legjobb releváns találat: **ADR 0405** (Kör 11, `bm25#3 emb#2`) "A
  visszavonás feltétele" szakasza — a D6 egységes-404 minta és a D3/D9
  körön-belüli megoldások jövőbeli felülvizsgálati feltétele kifejezetten
  "Kör 13 (feed)"-et nevezi meg precedensként; ez a kör viszont NEM egy
  közvetlen ID-s olvasás (nincs D6-típusú 404-kérdés, a feed egy szűrt
  LISTA, ahol a nem-látható sorok egyszerűen hiányoznak a lapról, nem
  hibáznak).
- `node tools/knowledge-rag.mjs --corpus lessons,halts --top 5 "N+1 query cursor pagination opaque signed timeout page_size"` →
  **L349** (`emb#2`): egy lapozó `do-while` a kezdő `cursor == null` állapotot
  összemoshatja a "lapozás elakadt" hibajellel — a jelen kör ELLENŐRZŐ,
  szerver-oldali tesztje (`test_feed_query_plan.py`) erre a klienskódra nem
  vonatkozik közvetlenül (a §6 cellák szerver-oldali válasz-alakot mérnek),
  de a §6 A2/A6 cellák tesztjeinek explicit kell kezelniük az ELSŐ hívás
  (`cursor=None`) esetét külön az "érvénytelen cursor" esettől, nehogy a
  szerver-oldali válasz-kontraktus ugyanabba a hibaosztályba essen, amit
  L349 a kliens oldalán mért.
- Nincs több, ezen a két szűkített lekérdezésen kívül releváns találat; a
  teljes korpuszos kiegészítő lekérdezés (`"following feed cursor pagination
  backend community_posts follows blocks"`) a `docs/sdd/10-...`, a
  `docs/plans/gpt/124-...` és a `lib/features/community/domain/
  repositories/feed_repository.dart` (Kör 5, ADR 0399 §1 — a Flutter-oldali
  KONTRAKTUS, amit ez a backend kör majd Kör 14-ben szolgál ki) találatokat
  hozta — mindhármat a Kontextus 1–5. pontjai (lásd ADR 0406) már lefedik.

**D2 — A `community_posts` TÉNYLEGES oszlopai és indexei mérve (ADR 0406
Kontextus 1.).** A `moderation_state` kétértékű (`"visible"`/`"removed"`),
a `deleted_at` a soft-delete tombstone, az `audience` a három
`CommunityAudience`-értéket veszi fel — mindhárom PONTOSAN a brief §3/§6
feltételezése szerint. Az EGYETLEN eltérés: a Kör 11 `ix_community_posts_
profile_created (profile_id, created_at, id)` indexe NEM a feed
kereszt-profilos rendezését szolgálja — az `allowed_paths`-on lévő ÚJ
migráció egy `profile_id`-t NEM vezető `(created_at, id)` indexet ad hozzá
(ADR 0406 D2).

**D3 — "Elfogadott follow" = a `community_follows` aktív-él LÉTEZÉSE, nincs
külön státusz-mező a szűréshez.** Mérve (ADR 0406 Kontextus 2., a §1 "1.
Elérhetetlen cél-státusz" pre-flight-szabály szerint): a
`CommunityFollow` modellnek nincs `status` oszlopa; a
`CommunityFollowRequest.status = "accepted"` átmenet a
`follow_service.py::accept_follow_request` service-ben EGYÜTT jár egy ÚJ
`CommunityFollow` sor `INSERT`-jével. A feed-query tehát a
`community_follows` táblát olvassa a viewer `follower_profile_id`-jára,
nem a request-táblát és nem egy "accepted" enumot keres.

**D4 — Erőforrás-tulajdonlás ellenőrzés: nincs a körben lease/lock/handle/
subscription jellegű erőforrás, a §1 "2." pre-flight-szabály N/A.** A kör
kizárólag egy read-only DB-query végpontot ad (session-factory + kérésenkénti
`db.close()`, a meglévő routerek mintája) — nincs réteg, ami egy hosszú
életű erőforrást (lease, lock, subscription) szerezne meg és adna tovább egy
másiknak, tehát a `grep -rn "\.acquire(" lib/` ellenőrzés erre a körre nem
alkalmazható (tisztán backend, `lib/**` a tilos zónában van).

**D5 — A cursor a MEGLÉVŐ HMAC-aláírt-token mintát követi
(`profile_search_repository.py::_sign_cursor`/`_verify_cursor`), nem
definiál új sémát.** Ld. ADR 0406 D4 — a kulcs `settings.secret_key`
(ugyanaz, mint a `search.py` cursor-jánál), a wire-alak
`<base64url(json)>.<base64url(hmac)>`. A payload a sort-key hármast hordozza
(`created_at`, `id`, `feed_version`) — a "feed-verzió" egy STATIKUS,
kódba égetett `FEED_CURSOR_VERSION` konstans ebben a körben (ADR 0406 D5),
nem egy perzisztált számláló.

**D6 — A mute-szűrés egy ÚJ, EGYIRÁNYÚ helperrel megy, a Kör 8 SZIMMETRIKUS
block-lista-mintája nem másolható 1:1.** Ld. ADR 0406 D3 — a
`community_mutes` táblának nincs lista-szintű helperje (csak egy privát,
egy-párra dolgozó `_existing_mute` a `block_service.py`-ban); a mute
aszimmetrikus (a muter iránya számít), tehát a feed-query saját, a
`muter_profile_id = viewer` predikátumra épülő halmazt épít, és NEM hívja a
Kör 8 szimmetrikus `list_block_pairs_for_viewer`-jét erre a célra (a block-
szűréshez viszont AZT kell hívnia — a két szűrő egymás mellett, külön
predikátumként fut).

**D7 — A "query timeout védelem" a kikényszerített MAXIMUM oldalmérettel
valósul meg, nincs SQL-szintű `statement_timeout` a backendben.** Mérve
(ADR 0406 Kontextus 5., D6): a `social_graph.py` lapozó végpontjainak
precedensét (`_FOLLOW_LIST_MAX_LIMIT = 200`) követve a §6.1 küszöb-hármas
konkrét alapérték/maximum száma NEM ADR-kötött — az implementer választja és
a §10-ben dokumentálja (ugyanaz a precedens, mint az ADR 0405 D9 "numerikus
küszöbök" pontja).

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/feed/following_feed.py",
  "backend/app/community/schemas/feed.py",
  "backend/app/community/routers/feed.py",
  "backend/alembic/versions/e09_r13_0008_community_feed_index.py",
  "backend/tests/community/test_feed_query_plan.py",
  "docs/rounds/e09-r13-following-feed-cursor-pagination-backend.md",
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

Időrendi, determinisztikus és privacy-safe következő feed — nincs engagement-maximalizáló fekete-doboz rangsorolás, csak audience/follow/block-szűrt, cursor-lapozott, stabil sorrend.

## 2. Jelenlegi állapot — mért tények

- A Kör 7 follow-gráf, a Kör 8 block-szűrő és a Kör 11 post-tábla MA külön-külön léteznek — ez a kör az első, ami mindhármat egy queryben kombinálja
- nincs még feed-specifikus index — ez a kör adja hozzá

## 3. Scope

**Benne van:** following feed query: audience, accepted follow, block, mute, moderation, deletion szűréssel · stabil sort: `created_at DESC, id DESC` · signed, opaque cursor feed-verzióval · maximum page size + query timeout védelem · N+1 elkerülése batched profile/count projekcióval · explain-plan baseline.

**NINCS benne (tilos):**

- Feed UI/cache — Kör 14.
- Explore-feed vagy bármilyen rangsorolás — a §13.3 SDD-szerint csak KÉSŐBBI rollout.
- `docs/adr/**` — az ADR 0404-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/feed/following_feed.py` | ÚJ |
| `backend/app/community/schemas/feed.py` | ÚJ |
| `backend/app/community/routers/feed.py` | ÚJ |
| `backend/alembic/versions/e09_r13_0008_community_feed_index.py` | ÚJ — összetett index |
| `backend/tests/community/test_feed_query_plan.py` | ÚJ — a §6 cellái |

**Tilos zóna:** `lib/**` (tisztán backend kör) · `backend/app/community/models/post.py` (csak olvasás) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0406, ld. §0.0 D1)

### 5.1 A feed IDŐRENDI — nincs engagement-alapú fekete-doboz rangsor

A rendezés kizárólag `created_at DESC, id DESC` — semmilyen engagement-jel (reakció-szám, komment-szám) nem befolyásolja a sorrendet.

**NEM elfogadható gyengítés:** egy "okosabb" rangsor bevezetése reakciószám vagy friss aktivitás alapján "jobb UX-ért" — ez pontosan a §13.2 tiltott engagement-maximalizáló mintája, és a Kör 32 elfogadási kritériuma bukna rajta.

### 5.2 A cursor OPAQUE — a kliens nem értelmezi, csak visszaadja

A cursor jelezve tartalmazza a sort key-t, a stabil post-ID-t és a feed-verziót — aláírt vagy más módon integritás-védett, hogy a kliens ne tudja manipulálni.

### 5.3 A query védett N+1 ellen és van timeout/page-size korlátja

A profil- és count-adatok batch-projekcióval jönnek egyetlen queryben, nem post-onkénti külön lekérdezéssel.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A feed időrendi és magyarázható (nincs rejtett rangsor) | `test_feed_query_plan.py` |
| A2 | A cursor kliens számára opaque és stabil | `test_feed_query_plan.py` |
| A3 | Lapozáskor nincs duplikált post normál esetben | `test_feed_query_plan.py` — no-duplicate-pages |
| A4 | Blocked/muted/deleted post nem jelenik meg | `test_feed_query_plan.py` |
| A5 | Followers-only tartalom csak elfogadott follow után látszik a feedben | `test_feed_query_plan.py` |
| A6 | Malformed cursor kontrolláltan hibát ad, nem 500-at | `test_feed_query_plan.py` |
| A7 | N+1 query nincs (explain-plan baseline) | `test_feed_query_plan.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A rendezés a reakciószámot is figyelembe veszi | A1 |
| A cursor egy nyers, kliens által dekódolható JSON | A2 |
| Egy módosuló feed közben átfedő oldalt ad vissza | A3 |
| A blocked user posztja mégis megjelenik a feedben | A4 |
| A followers-only poszt egy nem-követő feedjében is látszik | A5 |
| Egy sérült cursor 500-as hibát dob stack trace-szel | A6 |
| A profil-adatok posztonkénti külön SELECT-tel jönnek | A7 |

**A küszöb három kötelező cellája** (az oldal-méret (`page_size`, alapértelmezett és kliens által kért maximum)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `page_size = 0` | elutasítva — `ValidationError`, minimum 1 |
| **rajta** (a küszöbön) | `page_size` pontosan a konfigurált maximumon (pl. 50) | elfogadva, a válasz pontosan ennyi elemet ad |
| a küszöb **fölött** | `page_size` a maximum fölött (pl. 500) | a szerver a MAXIMUMRA korlátozza, nem 500-as hibát ad és nem fogadja el nyersen |

A hármas tömören: **alatt** → elutasít · **rajta** → elfogad, pontos méret · **fölött** → korlátoz a maximumra (fail-safe, nem hiba).

A határ a maximum záró határ, a korlátozás védi a query-timeoutot.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a `created_at, id` összetett indexet a migrációból, futtasd az explain-plan tesztet nagy adathalmazon → az **A7** N+1/teljesítmény-cellának PIROSNAK kell lennie (sequential scan) → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/architecture_dependency_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_feed_query_plan.py -q
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

1. Migráció: `(profile_id, created_at, id)` és `(audience, created_at)` összetett index.
2. `following_feed.py` — a query (follow + audience + block + mute + moderation + deletion szűrés).
3. Opaque, aláírt cursor a sort-key + post-ID + feed-verzió köré.
4. `feed.py` router — page-size korlát, timeout védelem.
5. Az explain-plan baseline teszt.
6. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A rejtett rangsor kísértése.** "Csak egy kicsit okosabb sorrend" — és a feed elveszti a magyarázhatóságát (A1).
- **A cursor manipulálhatósága.** Egy aláírás nélküli cursor lehetővé tenné a lapozási határok megkerülését (A2).
- **Az N+1 query.** Nagy following-listánál ez azonnal performance-problémává és potenciális DoS-vektorrá válik (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
