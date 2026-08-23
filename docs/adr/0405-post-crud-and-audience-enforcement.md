# ADR 0405 — Post backend CRUD és audience enforcement

- **Státusz:** Elfogadva (E09-R11 pre-flight, 2026-08-23)
- **Kör:** E09-R11 — Post backend CRUD és audience enforcement
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 11 (a 32 kör közül a tizenegyedik)
- **Kontext-ADR-ek:** [0398](0398-profile-privacy-audience-policy-and-access-control.md)
  (Kör 4 — `CommunityAccessPolicy`, a kiértékelési sorrend és a `NONE`/
  `SUMMARY`/`FULL` szint-hármas precedense), [0401](0401-follow-and-follow-request-social-graph.md)
  (Kör 7 — a PÁR-egyediségre épülő idempotencia-minta, amivel ez az ADR
  szándékosan szakít), [0402](0402-block-mute-and-safety-relationships.md)
  (Kör 8 — `query_filters.is_blocked_pair`, a direkt-ID block-ellenőrzés
  forrása), [0404](0404-share-artifact-contracts.md) (Kör 10 — az artifact-
  szerződés, amit ez a kör fogyaszt, nem redefiniál).
- **Sorszám-jegyzet:** a brief fejléce `0403`-at adott előre kiosztott
  ADR-ként, de a `tools/round-slots.py reserve-adr --round E09-R11` friss
  számot adott (`0405`) — a `.pipeline/inflight/adr/0403` marker egy korábbi,
  `E09-R09`-hez tartozó, végül ADR nélkül lezárt foglalás maradéka, `0404`-et
  pedig a Kör 10 foglalta el. A brief §0.0 D1 rögzíti a korrekciót.

## Kontextus

**Mért 2026-08-23-án, a pre-flightban (ez a szakasz a teljes
tényellenőrzést hordozza — a brief §0.0-jában is megismételve):**

1. `app/community/policies/access_policy.py::CommunityAccessPolicy.evaluate_content_access(audience, relationship) -> bool`
   MA létezik, teljes kiértékelési sorrenddel: `viewer_is_owner` → `blocked`
   → `PUBLIC` → `FOLLOWERS(is_follower)` → `PRIVATE`. A `CommunityAudience`
   enum három tagú (`PUBLIC`, `FOLLOWERS`, `PRIVATE`) — nincs `CLUB` tag, és
   a `policies/**` ebben a körben tilos zóna (csak HÍVÁS), tehát a poszt
   `audience` mezője ezt a három értéket veszi fel.
2. `app/community/policies/query_filters.py::is_blocked_pair(db, *, profile_id_a, profile_id_b) -> bool`
   a direkt-pár block-predikátum — ez a helyes hívás egyetlen poszt
   olvasásához, NEM a lapozó `exclude_blocked_from_public_ids`/
   `filter_public_ids_against_viewer_blocks` (azok LISTA-útvonal helperek,
   Kör 13 feed-scope).
3. `app/community/routers/privacy.py` (Kör 4) az optimista-konkurencia
   mintát egyetlen `updated_at` oszloppal oldja meg (nincs külön `version`/
   `etag` oszlop); a `PATCH` a kliens `resource_version`-jét `updated_at`-tel
   hasonlítja össze, eltérésnél 409-et ad.
4. `app/community/services/follow_service.py`/`block_service.py`
   "idempotens" create-je NEM perzisztálja a kliens `idempotency_key`-t — a
   follow/block PÁR természetes egyedisége (UNIQUE constraint) adja az
   idempotenciát. Egy posztnak nincs ilyen természetes egyedisége.
5. `grep -rn "bleach\|markdown" requirements.txt requirements-dev.txt` → 0
   találat — nincs HTML-sanitizáló vagy markdown-parser függőség telepítve.
6. `grep -rln "class CommunityClub" app/` → 0 találat; `app/config.py`-ban
   csak egy `community_clubs_enabled` feature-flag van — a `community_clubs`
   tábla nem létezik.
7. `grep -rln "outbox\|cache_invalidat\|CacheInvalidat" app/` → 0 találat —
   nincs élő outbox/cache-invalidation infrastruktúra a backendben.
8. Az `alembic/versions/` legutóbbi feje `e09_r08_0006` (`down_revision`
   lánc) — a következő migráció `e09_r11_0007`, `down_revision =
   "e09_r08_0006"`.

## Döntés

### D1 — Az audience-kiértékelés a MEGLÉVŐ `CommunityAccessPolicy.evaluate_content_access`-en megy, nincs párhuzamos logika

A GET/PATCH/DELETE végpontok a Kör 4 policy-t hívják a Kör 8
`is_blocked_pair`-ből épített `RelationshipContext`-tel. A `club_id` mező
független, opcionális oszlop — EBBEN a körben nem vesz részt a
kiértékelésben (Kör 24 scope).

### D2 — `resource_version` = a poszt `updated_at` oszlopa, nincs külön verzió-oszlop

A `privacy.py` (Kör 4) mintáját követve a `community_posts.updated_at` a
konkurencia-token ÉS az "szerkesztve volt-e" jel egyszerre
(`updated_at == created_at` ⇒ még nem szerkesztett). A PATCH a kliens
`resource_version`-jét `updated_at`-tel veti össze ÍRÁS ELŐTT; eltérésnél
409 `stale_resource_version`.

### D3 — Az idempotencia-kulcs a `community_posts` táblán perzisztálódik, nem egy megosztott táblán

`idempotency_key: String`, `UNIQUE(profile_id, idempotency_key)`. A create
`INSERT`-je `IntegrityError`-ra újraolvassa a meglévő sort és annak
`public_id`-ját adja vissza — ugyanaz a race-mintázat, mint
`follow_service.py::follow`. A SDD által javasolt megosztott
`community_idempotency_records` ("user + operation + key") tábla ÚJ
modell-fájlt igényelne, ami nincs ennek a körnek az `allowed_paths`-ában —
bevezetése egy jövőbeli, MÁSODIK idempotencia-fogyasztó endpoint körének
feladata.

### D4 — HTML/script tartalom REJECT-only validátorral szűrve, nincs sanitizáló függőség

A body-validátor `re.search(r"<[a-zA-Z/!]", body)` mintára utasít el
(nyitó/záró tag vagy kommentnyitás-szerű szekvencia) — nincs tényleges
markdown-rendereles vagy HTML-tisztítás, csak bemenet-elutasítás.

### D5 — `club_id` FOREIGN KEY nélküli nullable oszlop

A `community_clubs` tábla nem létezik (Kör 24 hozza létre). A `club_id`
BigInteger, nullable, FK-constraint NÉLKÜL — Kör 24 adja hozzá a
constraintot egy külön migrációban, amikor a céltábla létrejön.

### D6 — Egységes 404 minden "a néző nem férhet hozzá" ágra

Nincs ilyen ID, blocked, audience-kizárás, `deleted_at IS NOT NULL`,
`moderation_state != "visible"` — MIND 404, sosem 403. A poszt létezése
maga érzékeny infó (SDD §28.6 IDOR / report-identity-leak biztonsági
teszt-tétel); egy 403 elárulná, hogy a poszt létezik, csak a néző nem
láthatja. Ez szándékosan ELTÉR a Kör 8 `social_graph.py`
follower-lista 403-mintájától, mert ott a profil létezése már ismert (a
néző odanavigált a profilra) — más felszín, más döntés.

### D7 — `moderation_state` kétértékű mező (`"visible"`/`"removed"`), alapérték `"visible"`, aktív moderáció-endpoint nélkül

A tényleges moderáció-workflow Kör 27/28 scope. Ez a kör csak a mezőt és a
D6 egységes-404 kezelést adja — új moderáció-endpoint nélkül.

### D8 — Artifact-schema validáció a Kör 10 `parse_share_artifact`-ot hívja, nem definiál új uniót

`schemas/post.py` importálja `schemas/artifacts.py::parse_share_artifact`
(`ShareArtifactEnvelope`/`ShareArtifactUnion`) — a perzisztált
`artifact_type`/`artifact_schema_version`/`artifact_payload` oszlopok a
validált objektumból származnak. Nincs második artifact-diszkriminátor a
backendben.

### D9 — A cache-invalidation "event" egy injektált callback, nem egy DB-backed outbox tábla

`on_invalidate: Callable[[...], None] | None = None` paraméter a
service-függvényeken (a `privacy.py` `now`/`clock` injektált-paraméter
mintáját követve) — determinisztikusan tesztelhető, éles hívó nélkül. A
SDD javasolta megosztott `community_outbox_events` tábla ÚJ modell-fájlt
igényelne (ugyanaz az `allowed_paths`-érvelés, mint D3) — egy jövőbeli kör
köti be a tényleges cache-réteget.

### D10 — DELETE idempotens no-op, PATCH a törölt posztra 404-et ad

A `safety.py` block/mute mintáját követve a DELETE egy már törölt posztra
sikeres no-op (200), NEM 404 — a DELETE "cél állapot elérve" művelet, nem
olvasás, tehát a D6 IDOR-mérce nem vonatkozik rá. A PATCH viszont a D6
404-et kapja (szerkesztés nem "no-op"-olható értelmesen).

## Elutasított alternatívák

- **Megosztott `community_idempotency_records` / `community_outbox_events`
  tábla bevezetése ebben a körben.** Elvetve: mindkettő új modell-fájlt
  igényelne, ami nincs az `allowed_paths`-ban (H3 lenne). A SDD §19.2/§20.1
  ezt a szélesebb infrastruktúrát egy jövőbeli, több endpointot kiszolgáló
  kör dolgának hagyja.
- **403 blocked/audience-kizárt olvasásra (a `social_graph.py` mintáját
  másolva).** Elvetve: egyetlen poszt közvetlen ID-s olvasásánál a 403 saját
  magában elárulná a poszt létezését egy nem-jogosult néző számára — ez az
  SDD §28.6 IDOR-tétel pontos ellenpéldája.
- **Külön `version`/`etag` integer oszlop a `community_posts`-on.** Elvetve:
  a `privacy.py` (Kör 4) `updated_at`-alapú mintája már tesztelt és működik;
  egy második, redundáns oszlop indokolatlan komplexitás.
- **`bleach` vagy hasonló sanitizáló csomag hozzáadása.** Elvetve: nincs a
  `requirements.txt`-ben, és egy új függőség felvétele ennek a körnek nem
  tárgya (az `allowed_paths` nem tartalmaz `requirements*.txt`-et) — egy
  REJECT-only regex-validátor a brief A7 cellájához elégséges.

## Következmények

- A `community_posts` tábla `idempotency_key` és `club_id` oszlopai a Kör
  11 saját, körön-belüli megoldásai — egy jövőbeli megosztott idempotencia-
  tábla vagy a Kör 24 klub-tagság-integráció bevezetésekor mindkettő
  felülvizsgálandó (a `club_id` FK-constraintot kap, az `idempotency_key`
  esetleg átköltözik egy megosztott táblára, ha egy MÁSODIK endpoint is
  igényli).
- A D6 egységes-404 minta a jövőbeli Kör 13 (feed) és Kör 15/16 (komment/
  reakció) végpontoknak is precedens — azok is közvetlen ID-s
  tartalom-olvasások, ugyanazzal az IDOR-kockázattal.
- A D9 injektált-callback minta a `privacy.py` "seam most, wire later"
  precedensét ismétli — egy jövőbeli kör a router-mount + tényleges
  cache-réteg bekötésekor él vele.

## A visszavonás feltétele

Felülvizsgálandó, ha egy második Community endpoint (Kör 13+ feed, Kör
15/16 komment/reakció) is idempotencia-dedupot vagy cache-invalidation
eventet igényel — ekkor a D3/D9 "körön belüli" megoldásai helyett a SDD
§19.2/§20.1 megosztott táblái indokolttá válnak, saját migrációs körrel.
