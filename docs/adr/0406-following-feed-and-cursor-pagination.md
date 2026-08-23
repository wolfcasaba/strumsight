# ADR 0406 — Following feed és cursor pagination backend

- **Státusz:** Elfogadva (E09-R13 pre-flight, 2026-08-23)
- **Kör:** E09-R13 — Following feed és cursor pagination backend
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 13 (a 32 kör közül a tizenharmadik)
- **Kontext-ADR-ek:** [0398](0398-profile-privacy-audience-policy-and-access-control.md)
  (Kör 4 — `CommunityAccessPolicy.evaluate_content_access`, a kiértékelési
  sorrend forrása), [0401](0401-follow-and-follow-request-social-graph.md)
  (Kör 7 — `community_follows`, az aktív-él = elfogadott-follow minta),
  [0402](0402-block-mute-and-safety-relationships.md) (Kör 8 —
  `query_filters.is_blocked_pair` és a lista-szintű block-szűrő), [0405](0405-post-crud-and-audience-enforcement.md)
  (Kör 11 — `community_posts` tényleges oszlopai/indexei, `moderation_state`,
  `deleted_at`).
- **Sorszám-jegyzet:** a brief fejléce (és a pipeline-prompt) `0404`-et adott
  előre kiosztott ADR-ként, de a `0404` sorszámot MÁR a Kör 10 foglalta el
  (`docs/adr/0404-share-artifact-contracts.md`) — ez a brief 2026-08-22-i
  megírása és a kör 2026-08-23-i indítása közötti naptári avulás
  ([[L430]] mintája, lásd az ADR 0405 azonos jegyzetét). A foglaló
  (`tools/round-slots.py reserve-adr --round E09-R13`) friss számot adott:
  **`0406`**. A brief §0.0 D1 rögzíti a korrekciót.

## Kontextus

**Mért 2026-08-23-án, a pre-flightban (a brief §0.0-jában megismételve):**

1. `app/community/models/post.py::CommunityPost` MA létező oszlopai:
   `id`, `public_id`, `profile_id` (FK, CASCADE), `audience` (plain
   `String`), `club_id` (nullable, FK NÉLKÜL), `body`, `artifact_*`,
   `moderation_state` (`"visible"`/`"removed"`, default `"visible"`),
   `idempotency_key`, `created_at`, `updated_at`, `deleted_at`. A
   `e09_r11_0007` migráció EGYETLEN, a feed-query szempontjából releváns
   indexet hoz létre: `ix_community_posts_profile_created (profile_id,
   created_at, id)` — ez a per-szerző olvasási útvonalat szolgálja
   (`WHERE profile_id = :x ORDER BY created_at DESC, id DESC`), NEM a
   feed több-szerzős (`profile_id IN (...)`) kereszt-partíciós rendezését.
   A brief bevezető pre-flight-figyelmeztetése ("a `created_at, id`
   összetett indexnek léteznie kell") tehát egy ÚJ, `profile_id`-t NEM
   vezető indexre utal — ez a kör migrációja adja hozzá, nem
   újrahasznosítás.
2. `app/community/models/social_graph.py::CommunityFollow`-nak NINCS
   `status` oszlopa — egy aktív follow-él LÉTEZÉSE maga az "elfogadott"
   állapot (`UNIQUE(follower_profile_id, followed_profile_id)`). A
   `CommunityFollowRequest.status` (`requested`/`accepted`/`declined`/
   `cancelled`) egy KÜLÖN táblán él, és `follow_service.py::accept_follow_request`
   (231. sor) a request-sor `UPDATE`-je MELLETT egy ÚJ `CommunityFollow`
   sort is `INSERT`-el (271–297. sor) — a "követett profilok posztjai"
   (SDD §13.2) tehát pontosan a `community_follows.followed_profile_id =
   viewer` predikátummal olvasható, nincs külön "accepted" enum-érték,
   amit szűrni kellene.
3. `app/community/policies/query_filters.py::is_blocked_pair` egyetlen
   PÁRra dolgozik; a LISTA-szintű block-szűrőt
   `filter_public_ids_against_viewer_blocks`/`list_block_pairs_for_viewer`
   adja — ez utóbbi egy SZIMMETRIKUS predikátumot materializál (bármelyik
   irány blokkolja, a pár láthatatlan). A `community_mutes` táblának
   (`app/community/models/safety_relationships.py::CommunityMute`)
   NINCS hasonló lista-szintű helperje — a `block_service.py` csak egy
   privát, egy-párra dolgozó `_existing_mute`-ot definiál. A mute
   ASZIMMETRIKUS (a docstring: "no signal is sent to the muted party") —
   a Kör 8 szimmetrikus block-halmaz-mintája NEM másolható 1:1, mert a
   mute csak a `muter`-irányban zár ki.
4. `app/community/repositories/profile_search_repository.py` MÁR
   tartalmaz egy működő, aláírt-cursor implementációt: `_sign_cursor`/
   `_verify_cursor`, base64url-kódolt `<json>.<hmac-sha256-prefix>` pár,
   kulcsa `settings.secret_key` (`app/config.py:31`, a JWT-réteg is ezt
   használja). A `routers/search.py` a kulcsot
   `getattr(settings, "secret_key", "dev-insecure-change-me-in-production")`
   mintával adja át — ugyanez a fallback-minta.
5. `grep -rn "timeout" app/community/ app/*.py` → nincs SQL-szintű
   statement-timeout infrastruktúra a backendben (a `tutor_timeout_seconds`
   egy másik, nem DB-kapcsolódó időzítő). A meglévő lapozó végpontok
   (`social_graph.py::get_followers`/`get_following`) a "timeout-védelmet"
   KIZÁRÓLAG a kikényszerített maximum oldalmérettel oldják meg
   (`_FOLLOW_LIST_MAX_LIMIT = 200`), nincs külön DB-driver-szintű
   `statement_timeout` beállítás.

## Döntés

### D1 — A feed a `community_follows` aktív-él LÉTEZÉSÉT olvassa "elfogadott follow"-ként, nincs külön "accepted" predikátum

A követési lista `SELECT followed_profile_id FROM community_follows WHERE
follower_profile_id = :viewer` — ez MÁR csak elfogadott (aktív) éleket ad
vissza, mert a `CommunityFollowRequest.status="accepted"` átmenet a Kör 7
service-ben egy ÚJ `CommunityFollow` sort ír, a pending request-sor önmagában
sosem jelenik meg itt. A feed-query tehát nem a request-táblát olvassa.

### D2 — A `(created_at, id)` globális összetett index ÚJ, nem a Kör 11 `(profile_id, created_at, id)` indexének újrafelhasználása

A migráció (`e09_r13_0008_community_feed_index.py`) egy `profile_id`-t NEM
vezető `(created_at, id)` indexet ad hozzá — ez teszi lehetővé, hogy a
több-szerzős (`profile_id IN (...)`) lekérdezés a rendezést az indexből
kapja (elkerülve a memóriabeli sortot), a `profile_id` szűrést pedig a
sorpost-filterként alkalmazza. A Kör 11 `ix_community_posts_profile_created`
változatlanul megmarad — az a per-szerző (profil-oldal) olvasási útvonal
mércéje, ezt a kör nem érinti (a modell-fájl csak OLVASÁSRA engedélyezett).

### D3 — A mute-szűrés egy ÚJ, ASZIMMETRIKUS halmaz-helperrel megy, nem a Kör 8 szimmetrikus block-mintájával

A block-lista-helper (`list_block_pairs_for_viewer`) szimmetrikus
predikátumot épít, mert a block mindkét irányban láthatatlanná tesz. A mute
csak a `muter`-irányban zár ki (a `muted` fél posztjai eltűnnek a `muter`
feedjéből, de a `muter` posztjai NEM tűnnek el a `muted` feedjéből) — ez a
kör tehát egy saját, `SELECT muted_profile_id FROM community_mutes WHERE
muter_profile_id = :viewer` alakú, EGYIRÁNYÚ halmazt épít, és NEM hívja
(vagy másolja) a Kör 8 szimmetrikus helperét erre a célra. A block-szűrés
(szimmetrikus, `is_blocked_pair`/lista-helper) és a mute-szűrés (egyirányú,
ÚJ helper) a feed-queryben EGYÜTT, de KÜLÖN predikátumként szerepel.

### D4 — A cursor a MEGLÉVŐ HMAC-SHA256 aláírt-token mintát követi, nem definiál új sémát

A `profile_search_repository.py::_sign_cursor`/`_verify_cursor` pár
(base64url `<json>.<hmac>`, kulcs `settings.secret_key`) a repó EGYETLEN
működő, tesztelt aláírt-cursor implementációja. A feed cursorja ugyanezt a
szerkezetet követi, a payloadja a sort-key hármas: `{"c": created_at_iso,
"id": post_id, "v": feed_version}` — a `"v"` mező a §5.2 "feed-verzió" kötött
döntés realizációja (egy monoton növekvő verziószám, ami a payloadban utazik,
de a jelen körben NEM kap külön perzisztált forrást — ld. D5). Egy MÁSODIK,
párhuzamos aláírás-implementáció bevezetése pontosan az az architekturális
drift, amit az ADR 0402 §D2 (a block-predikátum egyetlen forrása) általánosan
tilt — ugyanaz az elv a cursor-aláírásra is vonatkozik.

### D5 — A "feed-verzió" egy STATIKUS, kódba égetett konstans ebben a körben, nem egy perzisztált számláló

A §5.2 "feed-verzió" a cursor payloadjában utazó mező, aminek a célja, hogy
egy jövőbeli, a sorrendezési SZEMANTIKÁT megváltoztató kör (pl. amikor a
rangsor-algoritmus tényleg megváltozik — ld. §13.3 SDD "csak KÉSŐBBI rollout")
érvényteleníthesse a régi cursorokat. Nincs `community_feed_versions` tábla,
és egy ilyen tábla bevezetése ÚJ modell-fájlt igényelne, ami NINCS az
`allowed_paths`-on (H3 lenne). A jelen kör tehát egy modul-szintű
`FEED_CURSOR_VERSION: int = 1` konstanst ír a `following_feed.py`-ba; a
cursor-ellenőrzés a beágyazott verziót az AKTUÁLIS konstanshoz hasonlítja, és
eltérésnél a §6 A6 "kontrollált hiba" ágát futtatja (nem 500-at). Egy
jövőbeli kör, amikor a rendezési szemantika ténylegesen változik, bumpolja a
konstanst — ez a döntés akkor felülvizsgálandó.

### D6 — A "query timeout védelem" a kikényszerített MAXIMUM oldalmérettel valósul meg, nincs SQL-szintű `statement_timeout`

A backend NEM hordoz DB-driver-szintű statement-timeout konfigurációt (mért
tény, Kontextus 5.). A `social_graph.py` lapozó végpontjainak precedensét
követve a §6.1 küszöb-hármas (`page_size = 0` elutasítva, a konfigurált
maximumon elfogadva, a maximum fölött a maximumra korlátozva) ADJA a
"timeout-védelmet" — a nagy oldalméret elleni egyetlen védelem a
kikényszerített felső korlát, nem egy külön DB-szintű időzítő. A pontos
alapérték/maximum számpár (a §6.1 küszöb-hármas konkrét száma) NEM ADR-kötött
architekturális döntés — az implementer választja és a §10-ben dokumentálja
(ugyanaz a precedens, mint az ADR 0405 D9 "numerikus küszöbök" pontja).

## Elutasított alternatívák

- **A Kör 8 szimmetrikus block-lista-helper újrafelhasználása a mute-szűrésre
  is.** Elvetve: a mute aszimmetrikus (D3) — egy szimmetrikus helper
  hívása a mutált fél posztjait a mutáló feedjéből ÉS a mutáló posztjait a
  mutált fél feedjéből is kiszűrné, ami a §5.2 "mute csak a muted felet
  rejti a muter elől" invariánst sértené.
- **Egy második, a `profile_search_repository.py`-tól független
  cursor-aláírás implementáció.** Elvetve (D4): a repó egyetlen aláírt-cursor
  mintáját kell követni, nem egy párhuzamos HMAC-implementációt bevezetni —
  ugyanaz az elv, mint a Kör 8 `is_blocked_pair` "egyetlen forrás" mintája.
- **`community_feed_versions` tábla a feed-verzió perzisztálására.** Elvetve
  (D5): új modell-fájlt igényelne, ami nincs az `allowed_paths`-on — H3
  lenne. A statikus konstans a jelen kör scope-jában elégséges (nincs élő
  rangsor-változtatás, ami invalidációt igényelne).
- **A Kör 11 `ix_community_posts_profile_created` index kiterjesztése a
  feed-query kiszolgálására, külön `(created_at, id)` index nélkül.**
  Elvetve: `profile_id`-t vezető index nem segíti hatékonyan a
  `profile_id IN (sok érték)` + globális `created_at DESC` rendezést — a
  §6.1 A7 valódi-sértés próba (az index eltávolítása → sequential scan)
  pontosan ezt a különálló indexet méri.

## Következmények

- A `community_posts` táblán további index él a Kör 11 indexe MELLETT — egy
  jövőbeli írás-terhelés-mérés indokolhatja az egyik összevonását vagy
  lecserélését, de ez a kör mindkettőt megtartja (a Kör 11 index a
  profil-oldal olvasási útvonal mércéje marad).
- A `FEED_CURSOR_VERSION` statikus konstans azt jelenti, hogy egy jövőbeli
  rangsor-szemantika-váltás kör felelőssége a bumpolás — ha ezt elfelejtik,
  a régi cursorok csendben ÉRVÉNYESEK maradnak egy megváltozott
  szemantikájú feed felett. Ez dokumentált kockázat, nem ennek a körnek a
  hatásköre feloldani.
- A mute-szűrés ÚJ, egyirányú helperje precedens egy jövőbeli kör (pl. Kör
  14 feed UI/cache, vagy egy második feed-típus) számára — azoknak EZT az
  egyirányú mintát kell követniük mute-ra, NEM a block szimmetrikus
  mintáját.

## A visszavonás feltétele

Felülvizsgálandó, ha (a) egy jövőbeli kör tényleges rangsor-algoritmust vezet
be (SDD §13.3 "későbbi rollout") — ekkor a D5 statikus verzió-konstans
helyett egy perzisztált, invalidálható feed-verzió-forrás válik indokolttá;
vagy (b) egy MÁSODIK lapozó endpoint is aszimmetrikus mute-szűrést igényel —
ekkor a D3 helper egy megosztott `query_filters.py`-beli függvénnyé
emelhető (jelenleg egy hívó nem indokolja az emelést).
