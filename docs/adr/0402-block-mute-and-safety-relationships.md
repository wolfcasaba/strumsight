# ADR 0402 — Block, mute és safety kapcsolatkezelés

- **Státusz:** Elfogadva (E09-R08 pre-flight, 2026-08-22)
- **Kör:** E09-R08 — Block, mute és safety kapcsolatkezelés
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 8 (a 32 kör közül a nyolcadik)
- **Kontext-ADR-ek:** [0401](0401-follow-and-follow-request-social-graph.md)
  (Kör 7 — `follow_service.py`, `community_follows`/`community_follow_requests`
  séma, DELETE-query-param idempotency minta), [0398](0398-profile-privacy-audience-policy-and-access-control.md)
  (Kör 4 — `RelationshipContext`/`CommunityAccessPolicy`, block-first
  kiértékelési sorrend), [0399](0399-flutter-community-domain-and-public-api.md)
  (Kör 5 — `SocialGraphRepository` domain-interfész).
- **Sorszám-jegyzet:** a `docs/execution/pipeline-queue.tsv` E09-R08 sora
  `0401`-et adott előre kiosztott ADR-ként, de ez a szám MÁR foglalt (a Kör 7
  ADR-je) — a `tools/round-slots.py reserve-adr --round E09-R08` friss számot
  adott (`0402`, Epic 9 batch-tartomány 0395–0419).

## Kontextus

**Mért 2026-08-22-én, a pre-flightban (a brief §0.0-ja a teljes
tényellenőrzést hordozza):**

1. `backend/app/community/services/follow_service.py::unfollow()` (381–386.
   sor) a `community_follow_requests` sort **UPDATE**-eli (`status =
   "cancelled"`), sosem `DELETE`-eli. A modell docstringje
   (`models/social_graph.py` 10–15. sor) ezt explicit szerződésként rögzíti:
   "the row is recycled (UPDATE) ... so the pair always carries exactly one
   row". A brief eredeti "block törli a pending requestet" megfogalmazása
   ezzel a MÉRT mintával ütközött volna (két, egymásnak ellentmondó
   perzisztencia-stratégia ugyanazon a táblán, kör-határon át).
2. `grep -rln "challenge_invite\|ChallengeInvite" backend/app/community/` → 0
   találat. A `community_challenges`/invite séma a **Kör 21**-ben landol
   (`docs/rounds/e09-r21-challenge-and-invite-lifecycle.md`). A brief
   "pending challenge invite törlése" cellája ebben a körben elérhetetlen
   cél-státusz volt.
3. `grep -rln "CommunityAccessPolicy\|RelationshipContext"
   backend/app/community/routers/` → 0 találat — a Kör 4
   `CommunityAccessPolicy` MA egyetlen routert sem ér el élőben.
   `profile.py::read_profile` és `privacy.py::get_privacy` **authentikáció
   nélküli** lookup endpointok (nincs `CurrentUser` paraméterük), tehát
   nincs viewer-identitásuk, amihez a block-reláció köthető lenne.
   `social_graph.py::get_followers`/`get_following` viszont MÁR
   authentikált (`current_user: CurrentUser`, a Kör 7 review F2 javítása), és
   a saját docstringjük szó szerint ezt a kört ("Kör 8") nevezi meg a
   szűrő-bekötés helyeként.
4. `grep -rln "club" backend/app/community/` → csak `access_policy.py`
   docstring-hivatkozás. A klub-domain a `docs/sdd/10-epic-09-community-platform.md`
   Kör 24-ben épül meg — nincs élő club-endpoint, ami ellen az A6
   "közös klubban placeholder" kritérium mérhető lenne.
5. `lib/features/community/data/repositories/relationship_repository_impl.dart`
   (13–22. sor, Kör 7 shipped kód) explicit dokumentálja: *"The 4 block/mute
   methods ... are Kör 8 scope; this round throws `UnsupportedError` for
   each"*. Ez a fájl az eredeti brief `allowed_paths`-ában NEM szerepelt — a
   kör a saját elődje által kijelölt munkát nem tudta volna elvégezni anélkül,
   hogy hozzáférjen.
6. A `SocialGraphRepository` (Kör 5, ADR 0399) 11 metódusa között nincs
   "a hívó saját blocked/muted listája" — csak `followingPage`/
   `followersPage`, amik a follow-gráfról szólnak. Az SDD UI-61
   (`docs/sdd/13-chapter-13-ui-ux-design-system.md` 107. sor) explicit
   lista-UI-t ír elő ("Blocked users / Muted threads").
7. `lib/features/community/application/controllers/relationship_controller.dart`
   MA nem ismer block/mute műveletet, és az `application/controllers/**`
   nem volt az eredeti `allowed_paths`-on.

## Döntés

### D1 — A block-tranzakció pontos alakja: DELETE az élen, UPDATE a requesten

`block_service.py` egy DB-tranzakcióban:

* `community_follows` — mindkét irányú aktív él (blocker→target ÉS
  target→blocker) `DELETE`. A szimmetrikus törlés szándékos: a block egy
  kapcsolatot szüntet meg, nem egy irányt — egy megmaradt ellenkező irányú
  follow-él értelmetlen, megtévesztő maradék lenne, még akkor is, ha az
  `access_policy.py` block-first sorrendje amúgy elfedné a tartalmát.
* `community_follow_requests` — bármely `requested` állapotú sor a párra
  (bármelyik irányból) `UPDATE status = "blocked"`, `responded_at = most`.
  ÚJ terminális érték, nem a meglévők (`declined`/`cancelled`) egyike —
  a jövőbeli UI-nak külön kell tudnia megkülönböztetni "a másik fél
  elutasított" és "blokkoltalak" között. A mezőn nincs DB `CHECK`
  (`models/social_graph.py` 136–137. sor: "the value-set can grow without a
  migration"), tehát az új érték bevezetése nem igényel sémaváltozást.
* Challenge-invite sor **nem** érintett — nincs ilyen tábla (D3).

Ha bármelyik lépés hibázik, EGYIK sem íródik be (egy tranzakció).

**NEM elfogadható gyengítés:** két külön hívás (előbb zárd le a
follow-t/requestet, majd hozd létre a blockot) — egy hiba a kettő között
inkonzisztens, biztonsági rést hagyó köztes állapotot eredményezne.

### D2 — Élő block-szűrés csak a MA authentikált endpointokra

Ez a kör `get_followers`/`get_following`-ba (`social_graph.py`) köti be a
block-szűrést, `access_policy.py::evaluate_profile_access` block-first
sorrendjét követve:

1. Ha a hívó és a `public_id` tulajdonosa között block áll fenn (bármelyik
   irányból) → `403`, a lap helyett.
2. Egyébként minden, a hívóval block-kapcsolatban álló profil kimarad a
   visszaadott lapból.

`profile.py::read_profile`, `privacy.py::get_privacy` és a `handles.py` két
GET-je **authentikáció nélküliek maradnak** — nincs viewer-identitásuk,
amihez a block köthető lenne, és az authentikáció hozzáadása egy külön,
ebben a körben nem budgetezett architektúra-döntés lenne (érintené a
Flutter oldal hívási láncát is: ma egyik kliens sem küld JWT-t ezekre a
hívásokra). A regressziós teszt ezt a négy endpointot NÉVEN nevezi meg és
dokumentált, indokolt kihagyásként jelöli — ez tartja meg az A5
előre-mutató szellemét (egy jövőbeli, `CurrentUser`-t kapó endpoint
kötelezően bekötendő a közös szűrőre) anélkül, hogy hamis biztonságérzetet
keltene egy nem létező ellenőrzésről.

### D3 — Nincs challenge-invite törlés ebben a körben

A tábla nem létezik (Kör 21 dolga). `block_service.py` tranzakciója
KIZÁRÓLAG `community_follows`/`community_follow_requests` sorokat érinti
(D1). A tranzakciós függvény belső lépései kapcsolattípusonként
nevesítettek, hogy a Kör 21 brief-je bővíthesse, amikor a challenge-invite
tábla létrejön — ez a kör csak ezt a horgot hagyja, stub tábla vagy hívás
nélkül.

### D4 — A6 pure-helper kontraktus, nem élő club-endpoint teszt

`query_filters.py` egy önálló, DB-hátterű, tiszta block-ellenőrző
segédfüggvényt ad (a pontos nevet az implementer választja), amit egy
jövőbeli klub-funkció (Kör 24) fog hívni a placeholder-megjelenítéshez. Az
A6 bizonyítéka ennek a segédfüggvénynek a unit-tesztje egy blokkolt párra —
nem egy élő club-endpoint elleni integrációs teszt (nincs ilyen endpoint).

### D5 — Szűk kivétel a domain tilos zónán: két új listázó metódus

`lib/features/community/domain/repositories/social_graph_repository.dart`
két új metódussal bővül: `blockedProfilesPage`/`mutedProfilesPage` (a hívó
saját blocked/muted listája, ugyanaz az aláírás-minta, mint
`followingPage`/`followersPage`, cél-userId paraméter nélkül). A meglévő 11
metódus szignatúrája NEM módosulhat — ez a `flutter analyze`
breaking-change-védelme is: minden meglévő hívó változatlanul fordítható
marad. A `lib/features/community/domain/**` tilos zóna minden más fájlra
változatlan.

### D6 — A screen saját, képernyő-kolokált Riverpod state-et visz

`relationship_controller.dart` MA nem ismeri a block/mute műveleteket, és az
`application/controllers/**` nincs az `allowed_paths`-on.
`safety_relationships_screen.dart` a `socialGraphRepositoryProvider`-t
(a Kör 7 óta élő, ebben a körben bővülő `relationship_repository_impl.dart`)
közvetlenül fogyasztja egy a saját fájljában definiált, lapozott
blocked/muted state-et tartó Riverpod notifieren keresztül — ugyanaz a
`_placeholderProfile` + `fetchById`-összefésülés minta, mint a Kör 7
`followingPage`/`followersPage` már dokumentált kontraktusa. Nincs új
`application/controllers/` fájl ebben a körben.

### Backend HTTP-felület (a routing-konvenció rögzítése)

`routers/safety.py` (ÚJ):

* `POST /community/profiles/{public_id}/block` (body: `idempotency_key`)
* `DELETE /community/profiles/{public_id}/block?idempotency_key=...` (unblock)
* `POST /community/profiles/{public_id}/mute` (body: `idempotency_key`)
* `DELETE /community/profiles/{public_id}/mute?idempotency_key=...` (unmute)
* `GET /community/blocked?cursor=&limit=` — a hívó saját blocked listája
* `GET /community/muted?cursor=&limit=` — a hívó saját muted listája

Mind az ADR 0401 §1 DELETE-query-param mintáját követi (a Dart
`api_client.dart::delete()` nem visz body-t — ADR 0401 Következmények,
`lib/core/network/api_client.dart` már ad `delete()`-et, nem igényel
bővítést). A lista-endpointok ugyanazt a `{"public_ids": [...],
"next_cursor": ...}` alakot adják, mint `get_followers`/`get_following`.
Mind a hat endpoint authentikált (`CurrentUser`).

## Elutasított alternatívák

- **A `community_follow_requests` sor `DELETE`-elése blokkoláskor.**
  Elvetve: ellentmond a Kör 7 MÁR lezárt, MÉRT UPDATE-újrahasznosítási
  szerződésének (1. kontextus-pont) — két, egymásnak ellentmondó
  perzisztencia-stratégia ugyanazon a táblán, kör-határon át, jövőbeli
  olvasóknak (pl. "kérelem-történet" UI) megmagyarázhatatlan inkonzisztenciát
  hagyna.
- **Authentikáció hozzáadása `read_profile`/`get_privacy`-hez ebben a
  körben, hogy az A2/A5 minden read endpointra kiterjedjen.** Elvetve:
  külön, önmagában is review-t igénylő architektúra-változás (két, MA
  authentikáció nélkül szállított, élesben használt endpoint viselkedését
  módosítaná), ami messze túlnő a brief eredeti fájllistáján és a kör
  "high risk" besorolásának indoklásán túli, ÚJ kockázati felületet nyitna.
  A D2 helyette a MA authentikált felületre szűkíti az élő védelmet, és
  a hiányt NÉVEN nevezve, nem hallgatva hagyja a regressziós tesztben.
- **Stub `community_challenge_invites` tábla létrehozása ebben a körben,
  hogy a brief szó szerinti "invite törlése" megfogalmazása teljesíthető
  legyen.** Elvetve: a Kör 21 brief-je saját sémát fog tervezni a valódi
  challenge-domainhez; egy előre gyártott, feltételezéseken alapuló stub
  tábla vagy újraírásra szorulna (kettős migráció), vagy hallgatólagosan
  rossz sémát rögzítene precedensként.
- **A `blockedProfilesPage`/`mutedProfilesPage` metódusok kihagyása és a
  screen "csak művelet-gombok, lista nélkül" szűkítése.** Elvetve: az SDD
  UI-61 és a brief saját "Blocked/Muted users beállítási képernyő"
  megfogalmazása explicit listát vár; egy lista nélküli screen nem
  teljesítené a kör saját scope-ját, csak a betű szerinti fájllistát.

## Következmények

- A `community_follow_requests.status` érték-készlete egy ÚJ, negyedik
  terminális értékkel bővül (`blocked`, a meglévő `requested`/`accepted`/
  `declined`/`cancelled` mellett) — ezt egy jövőbeli UI meg tudja
  különböztetni "elutasítva" és "blokkolva" között.
- `SocialGraphRepository` mostantól 13 metódust ad (a Kör 5 11 + a D5 2 új
  lista-metódusa) — a meglévő 11 szignatúrája stabil marad, jövőbeli
  bővítés csak additív lehet, ugyanezzel a mintával.
- A `test_block_query_regression.py` explicit, dokumentált kihagyás-listát
  visz a 4 authentikáció nélküli endpointra — egy jövőbeli kör, amely
  ezekhez `CurrentUser`-t ad, ezzel a listával méri, hogy a block-szűrés
  bekötése nem maradt el.
- `query_filters.py` pure block-helperje a Kör 24 klub-integráció kötelező
  belépési pontja lesz — a Kör 24 brief-jének ezt kell hívnia, nem saját
  block-lekérdezést írnia.

## A visszavonás feltétele

Felülvizsgálandó, ha egy jövőbeli kör (Kör 9/13 feed-search, vagy egy
dedikált auth-bővítő kör) `read_profile`/`get_privacy`-hez authentikációt
ad — ekkor a D2 hatóköre bővül, és a `test_block_query_regression.py`
kihagyás-listája szűkül. Szintén felülvizsgálandó, ha a Kör 21
challenge-invite implementációja azt találja, hogy a block-tranzakciónak
NEM elég a §"D3 horog" — ekkor a Kör 21 brief-je dönti el, hogy
`block_service.py`-t bővíti-e, vagy önálló, a challenge-service saját
block-listenerét építi.
