# E09-R13 — Following feed és cursor pagination backend

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 13
- **Kör-azonosító:** `E09-R13`
- **Branch:** `<motor>/e09-r13-following-feed-cursor-pagination-backend`
- **Előfeltétel:** `E09-R12` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0404` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 11 `community_posts` TÉNYLEGES oszlopait és indexeit — a feed-query ezekre épül, és a `created_at, id` összetett indexnek léteznie kell a stabil rendezéshez. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

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

## 5. Kötött architekturális döntések (ADR 0404)

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
