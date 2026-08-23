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

## 11. Review — a Claude tölti ki
