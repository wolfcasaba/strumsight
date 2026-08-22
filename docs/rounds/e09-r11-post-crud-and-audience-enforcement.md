# E09-R11 — Post backend CRUD és audience enforcement

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 11
- **Kör-azonosító:** `E09-R11`
- **Branch:** `<motor>/e09-r11-post-crud-and-audience-enforcement`
- **Előfeltétel:** `E09-R10` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0403` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 4 `CommunityAccessPolicy` és a Kör 8 `query_filters.py` TÉNYLEGES aláírását — a post-endpointok ezekre épülnek, nem új, párhuzamos audience-ellenőrzést vezetnek be. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/models/post.py",
  "backend/app/community/schemas/post.py",
  "backend/app/community/services/post_service.py",
  "backend/app/community/routers/posts.py",
  "backend/alembic/versions/e09_r11_0007_community_post.py",
  "backend/tests/community/test_post_service.py",
  "docs/rounds/e09-r11-post-crud-and-audience-enforcement.md",
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

Biztonságos poszt létrehozás, olvasás, szerkesztés és törlés — idempotens create, szerveroldali author, audience/block-ellenőrzött read, soft delete.

## 2. Jelenlegi állapot — mért tények

- A Kör 10 artifact-szerződés MA létezik, de poszthoz még nem kapcsolódik
- A Kör 4 audience-policy és a Kör 8 block-szűrő MA készen áll — ez a kör az első valódi "tartalom" endpoint, ami mindkettőt egyszerre használja

## 3. Scope

**Benne van:** post tábla public ID, audience, opcionális club ID, artifact, moderation state · create/get/patch/delete endpoint Pydantic validációval · create: idempotency key + szerveroldali author ID · body-limit, markdown subset, mention-limit, artifact-schema validáció · get/patch/delete: audience, block, owner, moderation policy ellenőrzés · soft delete + cache invalidation event · resource version/ETag a lost-update ellen.

**NINCS benne (tilos):**

- Feed/lista endpoint — Kör 13.
- Komment/reakció — Kör 15/16.
- Klub-audience TÉNYLEGES tagság-ellenőrzése — Kör 24 (itt csak a mező létezik).
- `docs/adr/**` — az ADR 0403-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/models/post.py` | ÚJ |
| `backend/app/community/schemas/post.py` | ÚJ |
| `backend/app/community/services/post_service.py` | ÚJ |
| `backend/app/community/routers/posts.py` | ÚJ |
| `backend/alembic/versions/e09_r11_0007_community_post.py` | ÚJ |
| `backend/tests/community/test_post_service.py` | ÚJ — a §6 cellái |

**Tilos zóna:** `lib/**` (ez a kör tisztán backend) · `backend/app/community/policies/**` (csak HÍVÁS) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0403)

### 5.1 A post-author SZERVEROLDALI authból származik, sosem a kérés testéből

A create endpoint az authentikált JWT subjectből olvassa az author-t; a kérés body-jában szereplő bármilyen author-mező figyelmen kívül marad.

**NEM elfogadható gyengítés:** egy `author_id` mező elfogadása a request body-ból "mert a kliens úgyis tudja, ki ő" — ez triviális identitás-hamisítás.

### 5.2 A create idempotens — retry NEM duplikál posztot

Ugyanaz az idempotency key ugyanazt a poszt-ID-t adja vissza, függetlenül attól, hányszor küldi újra a kliens.

### 5.3 A törölt poszt NEM tér vissza normál endpointból

Soft delete után a `GET /posts/{id}` 404-et (vagy policy szerinti elrejtést) ad — a poszt tartalma nem szivárog ki az ID ismeretében sem.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Forged author a kérésben figyelmen kívül marad, a szerver saját authját használja | `test_post_service.py` |
| A2 | Ugyanaz a create retry nem duplikál posztot | `test_post_service.py` — idempotency teszt |
| A3 | Audience-mátrix minden kombinációra helyes (owner/follower/blocked/public) | `test_post_service.py` |
| A4 | Blocked user nem olvashatja a posztot közvetlen ID-vel sem | `test_post_service.py` |
| A5 | Stale edit (elavult resource version) elutasítva | `test_post_service.py` |
| A6 | Soft delete után a poszt nem tér vissza normál endpointból | `test_post_service.py` |
| A7 | HTML/script tartalom a body-ban elutasítva | `test_post_service.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A create endpoint elfogadja a body `author_id` mezőjét | A1 |
| Az idempotency key nincs ellenőrizve, minden hívás új rekordot hoz létre | A2 |
| A blocked user közvetlen ID-vel mégis olvashatja a posztot | A4 |
| A patch nem ellenőrzi a resource verziót, felülírja a köztes módosítást | A5 |
| A törölt poszt `GET`-je 200-at ad a tartalommal | A6 |
| A body validáció csak kliensoldali, a szerver `<script>`-et is elfogad | A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki az idempotency-key ellenőrzést a `post_service.py`-ból, futtasd kétszer ugyanazt a create-hívást → az **A2** cellának PIROSNAK kell lennie (két külön poszt jön létre) → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/architecture_dependency_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_post_service.py -q
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

1. Migráció: `community_posts` tábla (public_id, profile_id, audience, club_id nullable, body, artifact_*, moderation_state, resource_version).
2. `post_service.py` — create (idempotency + szerveroldali author), get/patch/delete (policy-ellenőrzött).
3. `posts.py` router — Pydantic validáció, body/mention/markdown-limit.
4. Soft delete + cache-invalidation event kibocsátás.
5. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A kliens-adta author elfogadása.** A legsúlyosabb lehetséges hiba ebben a körben — bárki bárki nevében posztolhatna (A1).
- **Az idempotency-key figyelmen kívül hagyása.** Egy hálózati retry nyilvánosan duplikált posztot eredményezne (A2).
- **A soft-delete szivárgása.** Egy elfelejtett `WHERE deleted_at IS NULL` feltétel a törölt tartalmat élve tartaná (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
