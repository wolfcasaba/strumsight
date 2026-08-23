# ADR 0407 — Kommentek, reply és mention

- **Státusz:** Elfogadva (E09-R16 pre-flight, 2026-08-23)
- **Kör:** E09-R16 — Kommentek, reply és mention
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 16 (a 32 kör közül a tizenhatodik)
- **Kontext-ADR-ek:** [0405](0405-post-crud-and-audience-enforcement.md)
  (Kör 11 — `post_service.py`/`post.py` séma, `updated_at`-mint-resource_version
  minta, `PostNotFound`/`StalePostUpdateError` kivétel-alak, HTML-elutasítás +
  mention-limit regex a `schemas/post.py`-ban), [0402](0402-block-mute-and-safety-relationships.md)
  (Kör 8 — `query_filters.py::is_blocked_pair`, csak-hívás tilos zóna),
  [0398](0398-profile-privacy-audience-policy-and-access-control.md) (Kör 4 —
  `CommunityAccessPolicy`/`RelationshipContext`, block-first kiértékelési
  sorrend), [0399](0399-flutter-community-domain-and-public-api.md) (Kör 5 —
  `CommunityPostRepository` a `comments`/`createComment`/`updateComment`/
  `deleteComment` négyessel, MÁR él).
- **Sorszám-jegyzet:** a pipeline-prompt E09-R16-hoz `0405`-öt adott előre
  kiosztott ADR-ként, de ez a szám MÁR foglalt (Kör 11, post-crud). A
  `tools/round-slots.py reserve-adr --round E09-R16` friss számot adott
  (`0407`, Epic 9 batch-tartomány 0395–0419; `0406` a Kör 13 following-feed).
- **Visszakeresés (ADR 0312, pre-flight §4.9):** `node
  tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "komment reply
  mention block privacy validáció mélység-korlát"` → ADR 0402 (block-first
  sorrend, `query_filters.py` csak-hívás), ADR 0398 (`CommunityAccessPolicy`
  kontraktus-stabilitás). `--corpus lessons,halts --top 5 "resource_version
  edit conflict optimistic concurrency temp ID atomikus csere"` → nincs
  E09-R16-specifikus előzmény-lecke a resource_version mintára (az ADR 0405
  kontextus-ADR fedi ezt a mérési utat, nem a lessons-korpusz); L421
  (threading race-próba szinkronizációja) releváns, ha az A4/A6 valódi-sértés
  próbája konkurenciát szimulálna — ebben a körben a próbák szinkron
  hívásokkal futnak, tehát L421 mintája nem alkalmazandó közvetlenül.

## Kontextus

**Mért 2026-08-23-én, a pre-flightban (ez a §0.0 a teljes tényellenőrzést hordozza):**

1. `backend/app/community/schemas/post.py` (E09-R11, ADR 0405) MÁR tartalmaz
   egy `_reject_html_tags` (28–98. sor, `<[a-zA-Z/!]` regex, REJECT-only, nincs
   sanitizáló könyvtár a repóban) és egy `_enforce_mention_limit` (98–104. sor,
   `@[a-zA-Z0-9_]{1,64}` handle-minta, `MENTION_MAX_COUNT = 20`) validátort —
   mindkettő **privát** (`_`-prefixű), nincs az `__all__`-ban (223–228. sor:
   csak `CreatePostRequest`/`MENTION_MAX_COUNT`/`PatchPostRequest`/`PostOut`).
   A `schemas/post.py` NINCS ezen kör `allowed_paths`-án.
2. `backend/app/community/models/profile.py` és `backend/app/models.py::User`
   grep-elve (`Mapped[`, `role`, `moderator`, `is_staff`, `is_admin`,
   `superuser`) → **egyik osztályon sincs role/moderator/admin mező**. A
   `docs/sdd/10-epic-09-community-platform.md` "moderator" említései (1188,
   1709, 3392, 3443, 3539. sor) mind a Kör 24 (club) vagy a Kör 26/27
   (Moderation-QUEUE, ez a brief §3 explicit kizárja) hatáskörébe tartoznak —
   nincs ÉLŐ moderator-fogalom, amihez a comment-delete policy kötné magát.
3. `backend/app/community/services/identity_service.py::lookup_active_profile_id(db,
   normalized) -> int | None` (294. sor) a Kör 3 handle→profil feloldás — ez a
   mention-validáció bemenete a "létező profil" ághoz.
4. `backend/app/community/policies/query_filters.py::is_blocked_pair(db, *,
   profile_id_a, profile_id_b) -> bool` (44. sor) a Kör 8 block-predikátum —
   ez a tilos zóna egyetlen engedélyezett hívási pontja (csak import, a fájl
   NEM módosítható).
5. `backend/app/community/policies/access_policy.py::CommunityAccessPolicy
   .evaluate_profile_access(visibility, RelationshipContext) ->
   ProfileAccessLevel` (Kör 4) a "block-first" sorrendet MÁR kikényszeríti:
   `blocked=True` ÉS `visibility=PUBLIC` együtt is `SUMMARY`-t ad, sosem
   `FULL`-t (114–135. sor környéke). Ez azt jelenti, hogy egy mention-ellenőrzés
   számára **elég egyetlen `evaluate_profile_access(...) == FULL` teszt**, ha a
   `RelationshipContext.blocked` mezőt a valódi `is_blocked_pair` eredménye
   tölti ki — nem kell két külön (blokk + láthatóság) branch-et írni, mert a
   policy már összegzi őket.
6. `backend/app/community/models/post.py` MODERATION_STATE_VISIBLE/REMOVED
   (két érték, 108–109. sor) + `updated_at` mint resource_version (176–184.
   sor, "There is NO separate `version` column") — ez a MÁR lezárt Kör 11
   döntés, amit a Dart `ModerationState` öt-állapotú enumja (`moderation_
   state.dart`, "No live backend enum mirrors `ModerationState` yet") explicit
   NEM tükröz.
7. `backend/app/community/services/block_service.py::list_blocked`
   (273–330. sor környéke) egy base64-kódolt, **nem HMAC-aláírt** `(created_at,
   row_id)` cursor-t használ egyetlen felhasználó saját listájára — szemben a
   Kör 13 `following_feed.py` HMAC-SHA256-aláírt cursorjával (ami a
   `feed_version`-bump-kompatibilitást és a globális, sok-poszt feed
   tamper-védelmét szolgálja). A komment-lista egyetlen poszt alá tartozó,
   kisebb kockázati felület — a `block_service` mintája arányosabb precedens.
8. `lib/features/community/domain/repositories/post_repository.dart` (Kör 5,
   ADR 0399, tilos zóna) MÁR definiálja a négyest: `comments()`,
   `createComment()`, `updateComment()` (68–95. sor) — **`updateComment`
   NEM kap `resourceVersion` paramétert**, szemben a posztok `updatePost`-jával
   (ami igen). A `domain/**` tilos zóna miatt ez a szignatúra ebben a körben
   NEM bővíthető.
9. Sem `backend/app/community/routers/comments.py`, sem
   `backend/app/community/schemas/comment.py` NINCS az `allowed_paths`-on — a
   brief §3 "endpoint" szava ellenére ez a kör (a Kör 14/15 precedensét
   követve, HANDOFF E09-R15 pre-flight §0.0 D2) **service-réteg-only**: a
   `comment_service.py` funkciói közvetlenül hívhatók (backend pytest), HTTP
   router bekötése egy KÉSŐBBI kör dolga.

## Döntés

### D1 — resource_version = a sor `updated_at`-je, nincs külön `version` oszlop

`comment.py` a Kör 11 `post.py` mintáját követi: `updated_at` (DateTime,
`onupdate=_utcnow`) a resource_version token. Az A4 edit-conflict a kliens
`resource_version` és a sor aktuális `updated_at`-je közti egyenlőtlenségen
dől el (`StaleCommentUpdateError`, a `StalePostUpdateError` alakja). **NEM
elfogadható gyengítés:** külön `version: int` oszlop bevezetése — ez a MÁR
kétszer (Kör 4 privacy-row, Kör 11 post) lezárt konvenciótól való eltérés
lenne indoklás nélkül.

### D2 — Moderator jogosultság: explicit, hívó-adta `is_moderator: bool`, NEM DB-mező

Mivel sem a `User`, sem a `CommunityProfile` modellen nincs role/admin/staff
mező (2. kontextus-pont), a `comment_policy.py` a Kör 4 `RelationshipContext`
mintáját követi: egy tiszta, DB-mentes függvény —

```python
def can_delete(
    *, actor_profile_id: int,
    comment_author_profile_id: int,
    post_owner_profile_id: int,
    is_moderator: bool = False,
) -> bool
```

`is_moderator` a HÍVÓ dönti el (nem a policy olvassa ki egy nem-létező
oszlopból). A `comment_service.py` a MA élő (nem-létező admin-felület nélküli)
hívási útvonalon mindig `is_moderator=False`-t ad át — a Moderation-QUEUE
admin-auth (aki `True`-t adna) a brief §3 explicit kizárása szerint Kör 26/27
dolga. Az **A5 mérce a policy-függvényt közvetlenül hívja** `is_moderator=True`
paraméterrel, ugyanúgy, ahogy a `CommunityAccessPolicy` tesztjei a
`RelationshipContext`-et pinnelik DB nélkül — ez valódi, mérhető bemenet, nem
egy soha-elő nem forduló branch. **NEM elfogadható gyengítés:** egy `is_
moderator` mező hozzáadása a `CommunityProfile`-hoz vagy egy ÚJ `moderators`
tábla ebben a körben — ez a `models/profile.py`/domain tilos zónát sértené és
messze túlnőne a brief fájllistáján; a jövőbeli admin-auth kör dönti el a
valódi forrást (DB-mező, külön tábla, vagy JWT-claim), a policy-függvény
szignatúrája már ma kompatibilis bármelyikkel.

### D3 — A mention-validáció a MEGLÉVŐ három hívást komponálja, egyetlen `FULL` teszttel

```python
profile_id = lookup_active_profile_id(db, normalized_handle)          # Kör 3
if profile_id is None:
    # nincs ilyen kereshető profil → mention eldobva
blocked = is_blocked_pair(db, profile_id_a=author_id, profile_id_b=profile_id)  # Kör 8
ctx = relationship_context_from_block_flag(blocked=blocked, viewer_is_owner=(profile_id == author_id))
level = CommunityAccessPolicy().evaluate_profile_access(target.visibility, ctx)
valid = level == ProfileAccessLevel.FULL
```

Egyetlen `== FULL` teszt elég (5. kontextus-pont: a policy már block-first
sorrendű), tehát **nem** kell külön "blocked" early-return ág — az duplikálná
a policy már meglévő döntését és divergálhatna tőle egy jövőbeli policy-
változtatáskor. **NEM elfogadható gyengítés:** egy regex-alapú
handle-kereső/linkelő, ami nem hívja a fenti hármat (a brief §5.1 explicit
tiltja).

A `schemas/post.py` privát `_reject_html_tags`/`_enforce_mention_limit`
függvényeit **NEM** importálja a `comment_service.py` (privát, `__all__`-on
kívüli szimbólumok idegen modulból — fragilis, és a `schemas/post.py` nincs az
`allowed_paths`-on, tehát egy jövőbeli refaktor ott némán eltörné ezt a kört).
A comment body HTML-elutasítása és mention-limitje **saját, a komment-modul
belsejében élő** függvény, UGYANAZZAL a mintával (`<[a-zA-Z/!]` REJECT regex,
`@[a-zA-Z0-9_]{1,64}` handle-minta) — a duplikáció szándékos, a modulhatár
tiszteletben tartásáért.

### D4 — Mélység: explicit `depth: int` oszlop, max 1, elutasítás létrehozáskor

`community_comments.depth` (Integer, NOT NULL) — top-level komment `depth=0`,
egyetlen szintű reply `depth=1` (a szülő `depth`-je + 1). Létrehozáskor, ha a
szülő `depth >= 1` (azaz az új sor `depth`-je `>= 2` lenne), a service
`ValidationError`-t dob, sor nem jön létre. **NEM elfogadható gyengítés:**
rekurzív DB-lekérdezés a mélység kiszámítására minden create-nél — az
explicit oszlop egy sima szülő-lookuppal (egyetlen SELECT) helyettesíti.

### D5 — moderation_state: a Kör 11 két-értékű string mintája, NEM az öt-állapotú Dart enum

`community_comments.moderation_state` (String, default `"visible"`) —
`MODERATION_STATE_VISIBLE`/`MODERATION_STATE_REMOVED` a `comment.py`-ban
újra definiálva (nem importálva a `post.py`-ból, mert az nincs az
`allowed_paths`-on) ugyanazzal a két értékkel. A Dart `ModerationState` öt
állapota (`limited`/`pendingReview`/`authorOnly`) ebben a körben sem kap élő
backend-tükröt — ugyanaz a dokumentált rés, amit a `moderation_state.dart`
saját docstringje már rögzít (6. kontextus-pont).

### D6 — Cursor pagination: a `block_service.list_blocked` mintája, NEM a feed HMAC-cursorja

A komment-lista `(created_at, id)` base64-kódolt, **nem aláírt** cursort kap —
egyetlen poszt alá tartozó lista, arányos a Kör 8 `list_blocked` mintájával
(7. kontextus-pont). **NEM elfogadható gyengítés:** a Kör 13 HMAC-aláírt,
`feed_version`-es cursor-gépezet átvétele — az egy sokkal nagyobb, globális
lista tamper-felületét védi, amit ez a kör nem örököl.

### D7 — Ez a kör service-réteg-only, HTTP router NÉLKÜL (Kör 14/15 precedens)

A brief §3 "endpoint" megfogalmazása ellenére sem `routers/comments.py`, sem
`schemas/comment.py` nincs az `allowed_paths`-on (9. kontextus-pont). A
`comment_service.py` négy funkciója (create/edit/delete/list) közvetlenül
hívható és tesztelhető (`test_comment_service.py`), a Flutter
`comments_screen.dart`/`comment_controller.dart` a MÁR élő
`CommunityPostRepository.comments`/`createComment`/`updateComment`/
`deleteComment` kontraktus ellen fejleszt, valós HTTP-bekötés NÉLKÜL — ugyanaz
a minta, mint a Kör 14 `feed_controller` és a Kör 15 `ReactionController`. A
`updateComment` Dart-oldali hívása nem visz `resourceVersion`-t (8.
kontextus-pont, a domain tilos zóna miatt ez ebben a körben nem bővíthető) —
az A4 (edit-conflict) mérce ezért KIZÁRÓLAG a backend `test_comment_service.py`
felelőssége, a `comments_screen_test.dart` csak az A6 (temp ID atomikus csere)
UI-oldalát méri.

## Elutasított alternatívák

- **Külön `version: int` oszlop a resource_version-höz.** Elvetve: eltér a
  kétszer lezárt `updated_at`-mint-verzió konvenciótól (D1).
- **`is_moderator` mint DB-mező vagy új tábla.** Elvetve: a `models/profile.py`
  tilos zónát sértené, és egy admin-auth architektúra-döntést előlegezne meg,
  ami nem ennek a körnek a hatásköre (D2).
- **Külön "blocked" early-return ág a mention-validációban a `CommunityAccessPolicy`
  `FULL`-tesztje mellett.** Elvetve: duplikálná a policy már meglévő
  block-first döntését, divergencia-kockázatot nyitva egy jövőbeli
  policy-változtatáskor (D3).
- **Rekurzív SQL a komment-mélység kiszámítására.** Elvetve: az explicit
  `depth`-oszlop egyetlen szülő-lookuppal olcsóbb és a §6.1 valódi-sértés
  próbája (a mélység-ellenőrzés kivétele) is egyszerűbben célozható rajta (D4).
- **A `schemas/post.py` privát HTML/mention-validátorainak importálása.**
  Elvetve: `__all__`-on kívüli szimbólum idegen, nem-allowed-path modulból —
  fragilis csatolás egy fájlhoz, amit ez a kör nem érinthet (D3).
- **HMAC-aláírt cursor a komment-listához, a Kör 13 feed mintáját követve.**
  Elvetve: aránytalan védelem egy poszt-alá-skálázott listához; a Kör 8
  `list_blocked` egyszerűbb mintája arányos (D6).
- **HTTP router/schema hozzáadása ebben a körben, mert a brief §3 szövege
  "endpoint"-et mond.** Elvetve: az `allowed_paths` MÉRT ténye (9.
  kontextus-pont) és a Kör 14/15 precedens szerint ez a kör service-réteg-only
  — a router egy későbbi kör hatásköre (D7).

## Következmények

- `comment_policy.py::can_delete` szignatúrája (`is_moderator: bool`) a Kör
  26/27 admin-auth kör belépési pontja: az a kör dönti el a valódi forrást
  (DB-mező, tábla, JWT-claim), ennek a policy-nak a szignatúráján nem kell
  változtatnia.
- A HTML/mention body-validáció duplikált (`schemas/post.py` és
  `comment_service.py` külön másolatban tartja ugyanazt a két regexet) — egy
  jövőbeli refaktor-kör kiemelheti közösbe, ha mindkét modul stabil allowed-
  path-listát kap egyszerre.
- Nincs élő `GET/POST/.../comments` HTTP-végpont ez után a kör után sem — egy
  jövőbeli kör dolga a `comment_service.py` HTTP-bekötése (D7), a `PostOut`/
  `FeedPostItem` wire-projekcióhoz hasonlóan (E09-R15 pre-flight §0.0 D2
  precedens).
- A `updateComment` domain-kontraktus `resourceVersion` nélkül marad — ha egy
  jövőbeli kör a Dart oldalon is optimista edit-conflict UI-t akar, a
  `post_repository.dart` bővítése (additív, a meglévő szignatúrák
  változatlanul) külön kör dolga.

## A visszavonás feltétele

Felülvizsgálandó, ha a Kör 26/27 admin-auth egy konkrét moderator-forrást ad
(D2) — ekkor a `comment_service.py` hívási helyét kell bővíteni
`is_moderator=<valódi forrás>`-ra, a policy-függvény szignatúrája
változatlan marad. Szintén felülvizsgálandó, ha egy jövőbeli kör HTTP-t köt a
`comment_service.py` elé (D7) — ekkor a `schemas/comment.py`/`routers/
comments.py` pár megkapja a saját `allowed_paths`-sorát, és eldönthető, hogy a
D3 duplikált validátorai kiemelhetők-e egy közös modulba.
