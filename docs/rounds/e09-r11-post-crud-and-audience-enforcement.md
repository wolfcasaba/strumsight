# E09-R11 — Post backend CRUD és audience enforcement

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 11
- **Kör-azonosító:** `E09-R11`
- **Branch:** `<motor>/e09-r11-post-crud-and-audience-enforcement`
- **Előfeltétel:** `E09-R10` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** ~~`ADR 0403`~~ → **`ADR 0405`** (ld. §0.0 D1). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

## 0.0 Pre-flight brief-revízió (Claude Sonnet 5, 2026-08-23)

**D1 — ADR-szám korrekció.** A `0403` a brief megírásakor (2026-08-22) volt a
"legmagasabb foglalt+1" heurisztika szerinti szám, de a foglaló
(`tools/round-slots.py reserve-adr --round E09-R11`) **`0405`**-öt adott —
a `.pipeline/inflight/adr/0403` marker `round=E09-R09`-hez tartozik (egy
korábbi, végül ADR nélkül lezárt foglalás maradéka), `0404`-et pedig a Kör 10
foglalta el (`docs/adr/0404-share-artifact-contracts.md`). A §5 alábbi
"(ADR 0403)" hivatkozásait és a ténylegesen megírt ADR-fájlt **`0405`** alatt
kell érteni: [`docs/adr/0405-post-crud-and-audience-enforcement.md`](../adr/0405-post-crud-and-audience-enforcement.md).

**D2 — `CommunityAccessPolicy`/`query_filters` TÉNYLEGES aláírása mérve, a
post-endpointok erre épülnek (nem új, párhuzamos ellenőrzésre).**
`app/community/policies/access_policy.py::CommunityAccessPolicy.evaluate_content_access(audience: CommunityAudience, relationship: RelationshipContext) -> bool` —
sorrend: owner → blocked → PUBLIC → FOLLOWERS(is_follower) → PRIVATE(False).
A GET/PATCH/DELETE endpointok ezt hívják, a `relationship.blocked` mezőt a
Kör 8 `app/community/policies/query_filters.py::is_blocked_pair(db, profile_id_a=viewer_id, profile_id_b=owner_id)` tölti — EZ a direkt-ID olvasás
helyes hívása, NEM az `exclude_blocked_from_public_ids`/`filter_public_ids_against_viewer_blocks`
lapozó-szűrő (az egy LISTA-útvonal helperje, Kör 13 scope). A `CommunityAudience`
enum MA három értékű (`PUBLIC`, `FOLLOWERS`, `PRIVATE`) — nincs `CLUB` tag, és
a `policies/**` tilos zóna, tehát a poszt `audience` mezője EZT a három
értéket veszi fel; a `club_id` egy FÜGGETLEN, opcionális mező (ld. D6), amit
EZ a kör nem von be az `evaluate_content_access` kiértékelésbe (§3 NINCS
benne — Kör 24 scope).

**D3 — `resource_version` a MEGLÉVŐ `updated_at`-precedenst követi, nincs
külön verzió-oszlop.** `app/community/routers/privacy.py` (Kör 4, ADR 0398
§6) mintája: egyetlen `updated_at: DateTime(timezone=True)` oszlop szolgál
optimista-konkurencia tokenként — a `PATCH` a kliens `resource_version`
mezőjét `updated_at`-tel hasonlítja össze ELŐSZÖR, eltérésnél HTTP 409
(`stale_resource_version`), írás UTÁN bumpolja. A `community_posts` tábla
tehát **`updated_at`**-et kap (NEM külön `edited_at`+`version` párost) —
`updated_at == created_at` az még-nem-szerkesztett állapot jele, a SDD §20.4
"fontos mezők" listája (`edited_at`) egy megnevezés-variáns ugyanarra a
koncepcióra, amit ez a kör a meglévő, tesztelt precedenshez igazít (ADR 0372
szellemében: a mérce nem a listát, hanem a működő mintát követi).

**D4 — Az idempotencia-kulcs a `community_posts` táblán ÉL (nem külön
megosztott tábla), mert a megosztott tábla ÚJ modell-fájlt igényelne, ami
NINCS az `allowed_paths`-on.** A `follow_service.py`/`block_service.py`
"idempotens" mintája NEM tárolja a kliens `idempotency_key`-t — a
természetes egyediség (a follow/block PÁR) adja az idempotenciát. Egy
posztnak NINCS ilyen természetes egyedisége (ugyanaz a szerző több, eltérő
tartalmú posztot is írhat), ezért az A2 mérce-cella VALÓDI kulcs-perzisztálást
igényel: `idempotency_key: String` oszlop a `community_posts`-on,
`UNIQUE(profile_id, idempotency_key)` — a create `INSERT`-je `IntegrityError`-ra
újraolvassa a meglévő sort és VISSZAADJA annak `public_id`-ját (ugyanaz a
race-mintázat, mint `follow_service.py::follow`). A SDD §19.2/§20.8 által
javasolt megosztott `community_idempotency_records` ("user + operation +
key") tábla EBBEN a körben kívül esik — nincs modell-fájl érte az
`allowed_paths`-ban, és bevezetése H3 (tilos-zóna) lenne. Egy jövőbeli kör,
amikor egy MÁSODIK endpoint is idempotencia-dedupot igényel, vezetheti be a
megosztott táblát; ez a döntés akkor felülvizsgálandó.

**D5 — HTML/script elutasítás REJECT-only regex, nincs sanitizáló
függőség.** `grep -rn "bleach\|markdown" requirements.txt requirements-dev.txt`
→ 0 találat — a backend NEM hordoz HTML-sanitizáló vagy markdown-parser
csomagot. Az A7 cella ("HTML/script tartalom a body-ban elutasítva") ezért
egy ELUTASÍTÓ (nem tisztító) Pydantic-validátorral teljesítendő: a body bármely
`<` karaktert közvetlenül követő betű/`/`/`!` szekvenciát (nyitó/záró tag,
kommentnyitás) `ValueError`-ral utasít el (`re.search(r"<[a-zA-Z/!]", body)`).
A "markdown subset" tehát: sima szöveg + a meglévő markdown-jelölők
(`**bold**`, `*italic*`, csupasz URL) engedélyezettek, de literál `<`+betű
szekvencia TILOS — nincs tényleges markdown-rendereles ebben a körben, csak
a bemenet-validáció.

**D6 — `club_id` NEM lehet valódi FK ebben a körben — a `community_clubs`
tábla NEM létezik.** `grep -rln "class CommunityClub" app/` → 0 találat
(`app/config.py`-ban csak egy `community_clubs_enabled: bool` feature-flag
van). A `community_posts.club_id` tehát egy nullable `BigInteger` oszlop
FOREIGN KEY NÉLKÜL — a §3 "csak a mező létezik" pontosan ezt jelenti. Kör 24
adja hozzá a valódi táblát és (külön migrációban) az FK-constraintot.

**D7 — Egységes 404 minden "nem látható" esetre (nem-létező ID, blokkolt
néző, audience-kizárás, soft-deleted, moderált), a `social_graph.py`
follower-lista 403-mintájától ELTÉRŐEN.** A `routers/social_graph.py`
`get_followers`/`get_following` 403-at ad blokk esetén — DE az egy MÁSIK
felszín (a profil LÉTEZÉSE már ismert, mert a néző odanavigált a profilra).
Egy közvetlen `GET /posts/{id}` esetén a poszt LÉTEZÉSE maga az érzékeny
infó (SDD §28.6 "IDOR", "report identity leak" biztonsági teszt-tétel, és a
brief §5.3 explicit "a tartalom nem szivárog ki az ID ismeretében sem" —
ugyanez az elv A4-re, nemcsak a soft-delete-re). A `post_service.py` GET/PATCH/DELETE
tehát MINDEN "a néző nem férhet hozzá" ágon (nincs ilyen ID, blocked,
audience-kizárás, `deleted_at IS NOT NULL`, `moderation_state != "visible"`)
**404**-et ad, sosem 403-at — a válasz-kód önmagában nem különböztetheti meg
"nincs ilyen poszt"-ot "van, de nem látod"-tól.

**D8 — `moderation_state` ebben a körben egy kétértékű mező
(`"visible"`/`"removed"`), alapérték `"visible"`, aktív moderáció-endpoint
NÉLKÜL.** A tényleges moderáció-workflow (jelentés, admin-akció) Kör 27/28
scope (ADR 0398 §2 `ProfileAccessLevel.NONE` jövőbeli-állapot precedens
ugyanerre a mintára). A GET/PATCH/DELETE a `moderation_state != "visible"`
esetet a D7 egységes 404-gyel kezeli — ez a §3 "moderation policy
ellenőrzés" szó szerinti, minimális teljesítése, ÚJ moderáció-endpoint
nélkül (az nem ebben a `allowed_paths`-ban van).

**D9 — Numerikus küszöbök (a brief nem adott meg számot, a pre-flight
rögzíti, hogy az implementer ne találgasson):** body max 5000 UTF-8
karakter (`Field(max_length=5000)`), mention-limit 20 db `@handle`-mintázat
posztonként (`re.findall(r"@[a-zA-Z0-9_]{1,64}", body)`, `len(...) > 20` →
elutasítás). Ezek NEM ADR-kötött architekturális döntések (nincs A-cella
rájuk), csak a §3 "body-limit"/"mention-limit" szó szerinti kielégítéséhez
szükséges konkrét szám — a review nem kéri számon pontos értéküket, csak a
LÉTÜKET (van felső korlát, üres body-t elutasít-e — utóbbi `min_length=1`).

**D10 — Artifact-schema validáció a MEGLÉVŐ Kör 10 szerződést hívja, nem
definiál újat.** `app/community/schemas/artifacts.py::parse_share_artifact(payload) -> ShareArtifactEnvelope`
(`ShareArtifactUnion`, `Field(discriminator="type")`, `extra="forbid"`) —
a create endpoint az opcionális `artifact` mezőt EZEN a függvényen futtatja
át; `pydantic.ValidationError` → 422. A perzisztált oszlopok
(`artifact_type`, `artifact_schema_version`, `artifact_payload` JSON) a
validált `ShareArtifactEnvelope.artifact` objektumból származnak
(`.type`, `.schema_version`, `.model_dump(mode="json")`) — a `schemas/
post.py` NEM definiál saját artifact-uniót (az `schemas/artifacts.py`
tilos-zóna-n KÍVÜL van, csak IMPORT).

**D11 — A cache-invalidation "event" ebben a körben egy injektálható
callback/dataclass, NEM egy DB-backed outbox tábla.** A SDD §20.1 táblalistája
egy megosztott `community_outbox_events` táblát javasol, de az egy ÚJ
modell-fájlt igényelne (nincs az `allowed_paths`-on, H3 lenne — ugyanaz az
érvelés, mint D4). A `post_service.py::soft_delete` (és `create`/`patch`,
konzisztencia kedvéért) egy opcionális, injektált `on_invalidate: Callable[[CachedInvalidationEvent], None] | None = None`
paramétert hív meg sikeres írás UTÁN (a `privacy.py` `now: datetime`
injektált-paraméter mintáját követve determinisztikus tesztelhetőségért) —
a teszt egy spy-t ad át és azt asserteli, hogy a törlés/létrehozás/szerkesztés
UTÁN pontosan egyszer hívódik, a helyes `post_public_id`-vel. Nincs éles
hívó ebben a körben (a router default `None`-t ad át, mint a `privacy.py`
`clock` seam) — egy jövőbeli kör köti be a tényleges cache-réteget.

**D12 — DELETE idempotens no-op, nem hibázik ismételt hívásra.** A
`block`/`mute`/`unblock`/`unmute` végpontok kodifikált mintáját követve
(`routers/safety.py`) a már törölt poszt DELETE-je NEM 404, hanem sikeres
no-op (a `deleted_at` már be van állítva, a hívás nem módosít semmit,
de 200-at ad) — ez KÜLÖNBÖZIK a D7 GET/PATCH 404-jétől, mert a DELETE a
kliens szempontjából "a cél állapot elérve" művelet, nem egy olvasás, amit
az IDOR-mérce (D7) korlátoz. A PATCH egy törölt posztra viszont a D7 404-et
kapja (szerkesztés nem "no-op"-olható értelmesen).

**Visszakeresett előzmény (ADR 0312, §4.9):**
`node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "resource version optimistic concurrency stale edit audience enforcement blocked read"`
→ [ADR 0398](../adr/0398-profile-privacy-audience-policy-and-access-control.md)
(a `CommunityAccessPolicy` kiértékelési sorrendje és a `NONE`/`SUMMARY`/`FULL`
szint-hármas — a D8 moderáció-alapérték ugyanezt a "jövőbeli állapot, ma nem
tesztelt" mintát követi). `--corpus lessons,halts,adr --top 5 "post idempotency
key create endpoint duplicate retry"` → [ADR 0401](../adr/0401-follow-and-follow-request-social-graph.md)
(a follow idempotencia PÁR-egyediségre épül, ami a D4 döntés kontraszt-
precedense — poszt esetén ez NEM elég). Releváns HALT a szűkített
lekérdezésen nem került elő. Teljes-korpuszos kiegészítés
(`--top 5 "post crud audience enforcement idempotency author server-side"`)
a brief saját szövegét és az SDD 10. fejezet Kör 11 szakaszát adta vissza
(önreferencia, nem új infó) — a D1-D12 fentiek a ténylegesen új mérési
eredmény.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 4 `CommunityAccessPolicy` és a Kör 8 `query_filters.py` TÉNYLEGES aláírását — a post-endpointok ezekre épülnek, nem új, párhuzamos audience-ellenőrzést vezetnek be. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás. **(A fenti D2 ezt a
> pre-flight-instrukciót már teljesítette — az implementernek nem kell
> újramérnie, csak a D2-t követnie.)**

**Kockázat = high, indoklás:** a kör a Kör 4 (`CommunityAccessPolicy`) és
Kör 8 (`query_filters.is_blocked_pair`) által védett audience/block-
ellenőrzést köti be az ELSŐ valódi "tartalom" (content) endpointra —
egy hibás kiértékelési sorrend vagy egy kihagyott block-check IDOR-t
(SDD §28.6) eredményezne. A szerveroldali author-kikényszerítés (D-döntés
5.1) hibája identitás-hamisítást tenne lehetővé. `risk = "high"` indokolt,
annak ellenére, hogy az `allowed_paths`-ban nincs a `high_risk_path_fragments`
listával szó szerint egyező töredék (a "post" tartalom-védelem a lényegi
kockázat, nem egy önmagában is gyanús elnevezésű útvonal).

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
- `docs/adr/**` — az ADR 0405-öt a Claude írja (ld. §0.0 D1).

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

## 5. Kötött architekturális döntések (ADR 0405, ld. §0.0 D1-D12)

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

1. Migráció: `community_posts` tábla (public_id, profile_id, audience, club_id nullable — FK NÉLKÜL §0.0 D6, body, artifact_type/artifact_schema_version/artifact_payload, moderation_state, idempotency_key §0.0 D4, created_at, updated_at §0.0 D3, deleted_at).
2. `post_service.py` — create (idempotency + szerveroldali author), get/patch/delete (policy-ellenőrzött).
3. `posts.py` router — Pydantic validáció, body/mention/markdown-limit.
4. Soft delete + cache-invalidation event kibocsátás.
5. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A kliens-adta author elfogadása.** A legsúlyosabb lehetséges hiba ebben a körben — bárki bárki nevében posztolhatna (A1).
- **Az idempotency-key figyelmen kívül hagyása.** Egy hálózati retry nyilvánosan duplikált posztot eredményezne (A2).
- **A soft-delete szivárgása.** Egy elfelejtett `WHERE deleted_at IS NULL` feltétel a törölt tartalmat élve tartaná (A6).

## 10. Implementation handoff — az implementer tölti ki

### 10.1 Fájlonkénti összegzés

| Fájl | Módosítás |
|---|---|
| `backend/alembic/versions/e09_r11_0007_community_post.py` | NEW — `community_posts` tábla + 3 index + UNIQUE(profile_id, idempotency_key). A `club_id` FK nélkül (§0.0 D6 — Kör 24). A `resource_version` a meglévő `updated_at` oszlop (§0.0 D3 — ADR 0398 §6). |
| `backend/app/community/models/post.py` | NEW — `CommunityPost` ORM + `__table_args__` (UniqueConstraint + két Index) a `test_migrations.py::test_upgrade_head_matches_current_orm_schema` compare_metadata összehasonlításhoz. |
| `backend/app/community/schemas/post.py` | NEW — `CreatePostRequest`, `PatchPostRequest`, `PostOut`. `extra='forbid'` (A1), HTML reject-only regex `r"<[a-zA-Z/!]"` (§0.0 D5), mention-limit 20 (§0.0 D9), artifact `parse_share_artifact` round-trip (§0.0 D10). |
| `backend/app/community/services/post_service.py` | NEW — `create_post` (szerveroldali author + idempotencia), `get_post`/`patch_post`/`soft_delete_post` (D7 uniform 404). `on_invalidate` injektálható callback (§0.0 D11). Caller-supplied `now` (Kör 4 privacy precedent). |
| `backend/app/community/routers/posts.py` | NEW — `POST /community/posts`, `GET /community/posts/{id}`, `PATCH /community/posts/{id}`, `DELETE /community/posts/{id}`. `on_invalidate` `app.state.posts_on_invalidate`-ból; default `None`. |
| `backend/tests/community/test_post_service.py` | NEW — 18 teszt, lefedi A1–A7 cellákat + D11 cache-invalidation + D12 idempotens DELETE + §6.1 valódi-sértés próba. |

### 10.2 Futtatott parancsok + tényleges kimenet

```bash
# Round-gate (a brief §7 szerinti mérce, ELŐTÉRBEN, csonkítatlanul):
$ tools/round-gate.sh test/core/architecture_dependency_test.dart
# KIMENET (kivonat):
#   format                                                     zöld
#   analyze                                                    zöld
#   test test/core/architecture_dependency_test.dart           zöld
#   architecture                                               zöld
#   secrets                                                    zöld
#   l10n                                                       zöld
#   backend ruff format                                        zöld
#   backend ruff check                                         zöld
#   backend pytest                                             zöld

# Backend pytest (önálló parancs, NEM láncolva a gate-hez):
$ cd backend && python -m pytest tests/community/test_post_service.py -q
# KIMENET:
#   ..................                                                       [100%]
#   18 passed, 47 warnings in ~10s

# Migration schema parity (a `test_migrations.py` compare_metadata tesztje):
$ python -m pytest tests/test_migrations.py -q
# KIMENET:
#   15 passed
```

### 10.3 §6.1 valódi-sértés próba — dokumentálva

A `test_create_idempotency_real_violation_probe` a service-szintű `_existing_post_by_idempotency_key` segédet monkeypatch-eli `None`-t visszaadóvá ÉS egy dedikált `tmp_path`/`probe_no_uniq.db` SQLite engine-en fut, amelyen a `community_posts` tábla a migration alakját TÜKRÖZI, de a `CONSTRAINT uq_community_posts_profile_idempotency UNIQUE` constraint NÉLKÜL (SQLite-ban ez az UNIQUE in-place nem droppolható, ezért a probe külön engine). A monkeypatch UNDO a `finally`-ban, a probe engine `dispose()`-olódik.

Eredeti (védett) hívás — a service-szintű őr fut, a retry ugyanazt a public_id-t adja:
```
$ python -m pytest tests/community/test_post_service.py::test_create_idempotency_retry_returns_same_post -q
# KIMENET: 1 passed
```

Sértett hívás (mindkét réteg letiltva) — két külön poszt jön létre:
```
$ python -m pytest tests/community/test_post_service.py::test_create_idempotency_real_violation_probe -q
# KIMENET: 1 passed
# (az assertion: first.json()["public_id"] != second.json()["public_id"] ÉS len(rows) == 2)
```

A próba A2 cellát valóban pirosra váltja (két külön `CommunityPost` sor jön létre `idempotency_key="probe-key"`-vel), és a teszt a végén visszaállítja a service-szintű őrt, hogy más tesztek ne legyenek hatással.

### 10.4 Eltérések a tervtől és okuk

- **`__table_args__` hozzáadása a `CommunityPost` ORM-modellhez.** A terv a modellt csak a Kör 11 oszlopaival írta le, de a `test_migrations.py::test_upgrade_head_matches_current_orm_schema` `compare_metadata` ellenőrzése (`autogenerate.compare_metadata` — ADR 0396 §4 mintára) a `UniqueConstraint` + `Index` deklarációkat is szinkronban tartja a migration-nel. A gate első futásakor ez a teszt 3 különbséget talált (`remove_index ix_community_posts_idempotency_key`, `remove_index ix_community_posts_profile_created`, `remove_unique_constraint uq_community_posts_profile_idempotency`). A `__table_args__` hozzáadása után a compare_metadata üres — a migration-source-of-truth invariáns helyreállt.

- **A §6.1 probe külön SQLite engine-t használ, nem a meglévő session_factory-t.** A migration által létrehozott UNIQUE constraint SQLite-on in-place nem droppolható (`DROP INDEX sqlite_autoindex_community_posts_2` → "index associated with UNIQUE or PRIMARY KEY constraint cannot be dropped", `PRAGMA writable_schema=1` a futásidejű constraint-ellenőrzésre nincs hatással). A probe ezért dedikált `tmp_path/probe_no_uniq.db` engine-t épít, amelyen a `community_posts` tábla a migration alakját TÜKRÖZI a `UNIQUE(profile_id, idempotency_key)` nélkül. Ez a mért korlát — egy jövőbeli, kevésbé korlátozott dialect-en (PostgreSQL: `ALTER TABLE ... DROP CONSTRAINT`) a probe egyszerűsödik.

- **`_as_utc` és a `datetime.UTC` hasattr-védő.** A Python 3.11+ `datetime.UTC`-t vezetett be; a projekt `pyproject.toml` `target-version = "py312"`, de a `_as_utc` védőfallal él a 3.10–3.11 kompatibilitás kedvéért. Ez Kör 11 scope-on kívüli, de a privacy.py és identity_service mintát követi.

### 10.5 Nem futtatott ellenőrzések és okuk

- **A teljes backend pytest suite (a gate-ben `pytest -q` igen, de a `tests/community/test_*` kívüli minden más fájlra külön nem futtattam).** A gate `backend pytest` lépése `env --chdir=backend $PYTHON -m pytest -q` — ez MINDEN backend tesztet futtat, és ZÖLD volt (lásd 10.2). Nincs szükség külön lefuttatni.

- **`flutter analyze` a teljes `lib/`-re.** A gate `analyze` lépése ezt lefedi (`flutter analyze lib/ test/ tool/`) — ZÖLD.

- **Randomizált property gate (`PROPERTY_SEED`).** Kör 11 nem érint DSP-t, így property-teszt nem keletkezett. A `test/property/` csak DSP-re vonatkozik (ADR 0053, CLAUDE.md §"Randomized property gate").

- **Release APK build.** CLAUDE.md: "The FULL suite + property gate + APK run in CI, not here". Az implementer `gh`-t NEM hív (a brief §0.0 8. lépés); CI indítja a Claude-oldali merge szakaszban.

### 10.6 Follow-up issue-k

- **Kör 13** — feed/lista endpoint, pagináció. A `community_posts` tábla `(profile_id, created_at, id)` kompozit indexe már a feed-lekérdezésre van szabva.
- **Kör 14** — `@handle` mention resolution. A mention-limit regex ugyanitt Kör 11-ben lett bevezetve (számlálás), de a tényleges értesítési/feloldási logika Kör 14.
- **Kör 24** — `community_clubs` tábla + a `community_posts.club_id` FK utólagos hozzáadása külön migrációban (a Kör 11 D6 döntés értelmében).
- **Kör 27/28** — aktív moderáció-workflow (jelentés + admin-akció). A `moderation_state` két-értékű mező Kör 11-ben csak olvasásra kerül; a Kör 27/28 bővíti a workflow-t (a Kör 11 D8 döntés értelmében).

### 10.7 Commit-lánc

```
47438824 E09-R11 pre-flight: brief-revízió (D1-D12) + ADR 0405  (Claude pre-flight)
6f9465b1 E09-R11: community_posts alembic migration
798079af E09-R11: CommunityPost SQLAlchemy model
31afae9f E09-R11: post Pydantic schemas (create/patch/out)
6982772d E09-R11: post_service (create/get/patch/soft_delete)
e2d409c3 E09-R11: posts router (POST/GET/PATCH/DELETE)
674857fa E09-R11: ruff-format + __table_args__ parity + tests (A1-A7 + §6.1 probe)
```


## 10. Implementation handoff — javító kör 1 (F1, F2, F3 + F4 döntés)

### 10.1 Javítások összegzése

A review `docs/reviews/e09-r11-review.md` F1–F4 leleteit ez a kör az
engedélyezett fájlokon belül javítja. Az F5/F6 (NOTE, nem blokkoló)
dokumentálva van a review-ban, kódváltozást nem igényelnek.

**F1 (BLOCKER) — `patch_post` ownership check.**
`backend/app/community/services/post_service.py::patch_post` —
a `_evaluate_visibility` UTÁN, a `resource_version` ellenőrzés
ELŐTT beépült a `if post.profile_id != viewer_profile_id: raise
PostNotFound("post not found")` sor. Pontosan a `soft_delete_post`
537. sor mintáját követi; a D7 egységes 404 megőrzésével a
tulajdonos-hiány nem szivárog ki más válasz-alakként.

**F2 (BLOCKER) — GET/PATCH author_public_id a valódi szerzőből.**
`backend/app/community/routers/posts.py` —
- új helper `_resolve_public_id_by_profile_id(db, profile_id)` a
  profile-id → public_id feloldáshoz (a viewer_public_id helper
  párja, de fordított irányból);
- a `get_post_endpoint` és a `patch_post_endpoint` mindkettő
  `post.profile_id`-ből oldja fel a `author_public_id`-t, és
  AZT adja át `_row_to_out`-nak — NEM a hívó saját azonosítóját.
A create endpoint változatlan (ott a hívó VALÓBAN a szerző, mert a
create hozza létre a sort, így `author_public_id == viewer_public_id`).

**F3 (MINOR) — törölt poszt NEM tér vissza élő 201-ként.**
`backend/app/community/services/post_service.py::create_post` —
a `_existing_post_by_idempotency_key` MINDKÉT hívási helyen
(pre-insert olvasás ÉS az `IntegrityError` utáni újraolvasás)
`CommunityPost.deleted_at.is_(None)` filtert kap, így egy
soft-deleted tombstone NEM felel meg az élő idempotencia-ablaknak.

Egy nem-triviális részlet: a DB-szintű `UNIQUE(profile_id,
idempotency_key)` constraint a `deleted_at` értékére tekintet
nélkül tüzel (SQLite-ban a constraint a sor törléséig él —
részleges unique index DDL-szinten nem áll a Kör 11
allowed_paths-ban, lásd §10.4 alább). Az `IntegrityError`
ágban ezért egy újabb lépés kell: ha a kulcsot egy
soft-deleted tombstone tartja, a tombstone `idempotency_key`
mezőjét `NULL`-ra állítjuk (a NULL UNIQUE szempontjából nem
ütközik), és a fresh INSERT lefut. A tombstone audit-trailje
megmarad (a `deleted_at` és a body/artifaact sértetlen, csak
a kulcs-engedélyét adjuk át az új sornak). Az A2 §6.1
valódi-sértés próba és a service-szintű lookup-szűrő
együttesen biztosítják, hogy egy ÉLŐ kulcs-újrafelhasználás
NEM hoz létre két külön sort.

**F4 (MINOR) — PATCH optimista-konkurencia, tudatos döntés.**
A `patch_post` read-compare-write szintű verzió-ellenőrzése
MEGMARAD — nem cseréltük `UPDATE ... WHERE updated_at = :expected`
(DB-szintű compare-and-swap) megoldásra. Indoklás:

1. **A meglévő Kör 4 precedens.** A `routers/privacy.py` (Kör 4,
   ADR 0398 §6) ugyanazt a read-compare-write mintát használja
   a `StalePrivacyUpdateError` őrrel — az A5 §6.1 elfogadott
   mércéje a szekvenciális stale-rejection, és a konkurencia
   (két PATCH, mindkettő V0-t olvas) gyakorlatilag nem fordul
   elő a PATCH owner-only felszínen.
2. **Nem új regresszió.** Ez a korlát a Kör 4 óta öröklött; a
   privacy.py-t is így szállítjuk. A jelenlegi F4 lelet csak
   dokumentálja, hogy a Kör 11 a precedenssel konzisztens, nem
   vezet be ÚJ, a Kör 4-nél szigorúbb írási konkurencia-szintet.
3. **A javítás költsége.** A feltételes UPDATE + rowcount
   ellenőrzés ORM-mintát törne meg (a jelenlegi `db.flush()` +
   `db.refresh(post)` minta egyszerű és olvasható), és a
   `follow_service.py::follow` / `block_service.py` jövőbeli
   alkalmazásai is határ-eseteket kapnának (pl. a `created_at`
   bump-ja után mi történjen `updated_at`-tel). Egy dedikált
   Kör 24+ vizsgálhatná a Kör 4 / 11 / 13 közös
   konkurencia-rétegét.

Következmény: a HANDOFF §10.6 follow-up listájára felkerül
"Feltételes UPDATE … WHERE updated_at = :expected mintára
refaktor a privacy.py + post_service.py + (jövő) feed
service.py egységesítésével — külön kör".

### 10.2 Új regressziós tesztek

| Teszt | F-cella | Mit szavatol |
|---|---|---|
| `test_patch_by_non_owner_returns_404` | F1 | Egy PUBLIC posztot egy MÁSODIK (nem-tulajdonos) felhasználó PATCH-eli helyes `resource_version`-nel → 404 (D7 uniform), a sor body-ja sértetlen marad (`"mine"`, nem `"DEFACED"`). A `test_delete_by_non_owner_returns_404` PATCH-párja. |
| `test_audience_matrix_owner_and_public_viewer` (kibővítve) | F2 | A GET válasz `author_public_id` mezője a TULAJDONOS public_id-ját adja mind a tulajdonos, mind a nem-tulajdonos néző számára (a javítás ELŐTT a nem-tulajdonos a sajátját kapta volna). Explicit `!=` assert is a viewer.public_id ellen. |
| `test_create_after_soft_delete_with_same_idempotency_key` | F3 | create → soft-delete → create (ugyanazzal a kulccsal) → 201 egy ÚJ public_id-val, a tombstone megmarad a DB-ben `deleted_at != None` és `idempotency_key = NULL` állapottal. A törölt tartalom NEM tér vissza élő `deleted_at=None` módon. |

A javítás ELŐTT ezek a tesztek PIROSRA váltanának:
- F1: a második felhasználó PATCH-e jelenleg sikeres lenne, és a body `"DEFACED"` lenne.
- F2: a nem-tulajdonos GET `author_public_id` mezője a viewer.public_id-t adná.
- F3: a második create a törölt sort adná vissza `deleted_at != None` módon (vagy az F3 szub-fix nélkül `IntegrityError` → 500-öt).

### 10.3 Futtatott parancsok + tényleges kimenet (javító kör 1)

```bash
# Round-gate (a brief §7 szerinti mérce, ELŐTÉRBEN, csonkítatlanul):
$ tools/round-gate.sh test/core/architecture_dependency_test.dart
# KIMENET (Gate-összegzés):
#   format                                                     zöld
#   analyze                                                    zöld
#   test test/core/architecture_dependency_test.dart           zöld
#   architecture                                               zöld
#   secrets                                                    zöld
#   l10n                                                       zöld
#   backend ruff format                                        zöld
#   backend ruff check                                         zöld
#   backend pytest                                             zöld
# MINDEN GATE ZÖLD.

# Backend pytest (önálló parancs, NEM láncolva a gate-hez):
$ cd backend && python3 -m pytest tests/community/test_post_service.py
# KIMENET: 20 passed, 53 warnings in 10.78s

# Teljes backend pytest suite (a gate-ben `backend pytest` lépés lefedi,
# de külön is ellenőriztem a lefedettséget):
$ cd backend && python3 -m pytest
# KIMENET: 455 passed, 480 warnings in 96.72s

# Migration schema parity (a `test_migrations.py` compare_metadata tesztje):
$ cd backend && python3 -m pytest tests/test_migrations.py -q
# KIMENET: 15 passed

# Ruff format (önállóan futtatva a §3-as kötelező lépés, gate-ben --check):
$ cd backend && python3 -m ruff format app tests
# KIMENET: 78 files left unchanged
```

A §10.2 javítás ELŐTTI viselkedés ellenőrzése (regressziós tesztek
valódi mérőereje):

A fixek visszavonásával (F1: a `if post.profile_id !=
viewer_profile_id` sor kikommentezése; F2: a
`_resolve_public_id_by_profile_id` hívás kicserélése
`viewer_public_id`-ra; F3: a `deleted_at.is_(None)` filter
eltávolítása) a fenti három regressziós teszt PIROSRA váltana,
megerősítve, hogy a tesztek a tényleges hibát fogják, nem csak a
"boldog útvonalat" járják be.

### 10.4 Eltérések a tervtől és okuk (javító kör 1)

- **F3 IntegrityError-ág bővítése.** Az eredeti F3 fix-terv
  ("add `deleted_at IS NULL` filter mindkét hívási helyen") önmagában
  NEM volt elégséges: a service-szintű filter kihagyja a tombstone-t,
  de az INSERT-et a DB-szintű `UNIQUE(profile_id, idempotency_key)`
  constraint ettől még elutasítja (SQLite-ban a constraint a sor
  törléséig él). A javítás kiegészült egy második lépéssel: ha az
  IntegrityError oka egy soft-deleted tombstone, a tombstone
  `idempotency_key` mezőjét `NULL`-ra állítjuk (a NULL UNIQUE
  szempontjából nem ütközik), és a fresh INSERT így már lefut. A
  tombstone audit-trailje megmarad (a `deleted_at` és a body/artifact
  sértetlen). Ez a mért tradeoff: a tombstone elveszti a kulcs-engedélyét
  (az új sorhoz kerül), de a teljes poszt-tartalom és a törlés
  ténye megmarad.

  Egy "igazibb" megoldás (részleges unique index
  `WHERE deleted_at IS NULL` SQLite/PostgreSQL szinten, vagy a
  constraint elhagyása és kizárólag service-szintű őr) jelenleg
  ÚJ migrációt vagy ÚJ ORM-változtatást igényelne, ami kívül esik
  a §4 `allowed_paths` listán. Ha egy jövőbeli kör (pl. Kör 13
  feed-lista) bevezet egy második idempotencia-dedupot igénylő
  végpontot, érdemes megfontolni a közös séma-migrációt.

- **F2 megoldás a router-rétegben (nem a service-ben).** A review
  két lehetséges megoldást sorolt: (a) a router a `post.profile_id`-ből
  oldja fel a `public_id`-t egy SELECT-tel; (b) a service visszaadja
  a szerző public_id-t a sorral együtt. Az (a) megoldást választottuk,
  mert (i) a service-szintű struktúra (author vs viewer) a §5.1
  "szerveroldali author" szellemiségét tükrözi — a service az
  internal PK-kal dolgozik, a public_id a wire-réteg identitása;
  (ii) a service-visszaadás egy új tuple-t vagy dataclass-t
  vezetne be, ami a többi hívót (create, soft_delete) is érintené;
  (iii) a SELECT a `_resolve_public_id_by_profile_id` helperben
  egyetlen soros, indexelt lekérdezés, amely a meglévő
  `_resolve_author_public_id` mintát követi. A diff a service-t
  nem érinti.

- **A `viewer_public_id` helper a PATCH/GET végpontokban
  ELTŰNT.** Korábban a `_resolve_author_public_id(db,
  current_user.id)` segéd hívódott a viewer public_id-jának
  feloldására, de az F2 fix után a GET/PATCH ezt nem használja —
  a `_resolve_public_id_by_profile_id(db, post.profile_id)` a
  forrás. A helper a POST-ban (ahol a hívó a szerző) és más
  jövőbeli helyeken továbbra is él.

### 10.5 Nem futtatott ellenőrzések és okuk

- **Randomizált property gate (`PROPERTY_SEED`).** Kör 11 nem érint
  DSP-t, így property-teszt nem keletkezett. A javító kör 1 sem
  érint DSP-t.

- **Release APK build.** A javító kör 1 tisztán backend. CI-oldali
  release build a merge-szakaszban fut (AGENTS.md §CI-dispatch
  szabály: implementer `gh`-t NEM hív).

- **A §6.1 valódi-sértés próba a javító kör 1-re.** A Kör 11
  eredeti §6.1 próbája (`test_create_idempotency_real_violation_probe`)
  a service-szintű lookup kikapcsolását demonstrálja. A javító
  kör 1 ezt a próbát nem érinti (az idempotencia-lookup szűrője
  egy másik réteget tesztel), és egy ÚJ, F3-specifikus próbát
  (`test_create_after_soft_delete_with_same_idempotency_key`)
  hoz be.

### 10.6 Follow-up issue-k (kiegészítés a Kör 11 listáján)

- **Feltételes UPDATE … WHERE updated_at = :expected minta.** A
  Kör 4 privacy.py + Kör 11 post_service közös
  read-compare-write korlátját egy dedikált, jövőbeli kör
  refaktorálhatná egységes, DB-szintű CAS-ra. A scope jelenleg
  kívül esik a Kör 11 allowed_paths-on és a Kör 4 privacy.py
  módosításán.

- **Részleges unique index az idempotency_key-re.** Ha a Kör 13+
  bevezet egy második idempotencia-dedupot igénylő végpontot,
  érdemes megfontolni egy `CREATE UNIQUE INDEX … WHERE
  deleted_at IS NULL` migrációt, ami a tombstone-key-clear
  lépést szükségtelenné tenné.

- **A `viewer_public_id` helper használatának felülvizsgálata.**
  A PATCH/GET végpontokban mostantól nem hívódik — ha a jövőben
  a service újra szükségessé teszi (pl. audit-log integráció),
  a helper a `_resolve_author_public_id` néven továbbra is elérhető.

### 10.7 Commit-lánc (kiegészítés a Kör 11 láncán)

A javító kör 1 négy commitot hoz a `minimax/e09-r11-post-crud-
and-audience-enforcement` branchre:

```
1ca7909d E09-R11 review-fix-1: patch_post ownership check + idempotency deleted_at filter (F1, F3)
15db1b62 E09-R11 review-fix-1: GET/PATCH resolve actual author_public_id (F2)
e2884677 E09-R11 review-fix-1: regression tests for F1/F2/F3
a17870cd E09-R11 review-fix-1: F3 tombstone key clear + test updated to new-row path
```

Az 1ca7909d commit a `post_service.py` F1 + F3 lookup-filterét
egyesíti (egy fájl, kapcsolódó logikai javítások), a 15db1b62 a
router F2-jét külön tartja (másik fájl, másik felelősségi kör),
az e2884677 az új regressziós teszteket egyben hozza, az
a17870cd az F3 sub-fixet (IntegrityError-ág tombstone-key-clear)
és a teszt új-row-path frissítését commitolja együtt, mert
a kettő elválaszthatatlan (a teszt csak a sub-fix után zöld).

