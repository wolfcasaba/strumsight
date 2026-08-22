# E09-R07 — Biztonsági / adatvédelmi review

- **Kör:** E09-R07 — "Follow és follow request social graph" (Epic 9, Kör 7)
- **Branch / HEAD:** `minimax/e09-r07-follow-and-follow-request-graph` @ `1d4d6341`
- **Diff-bázis:** `git diff 556cd269..1d4d6341` (11 fájl, +4105/-3)
- **Kockázat:** high (konkurencia-érzékeny DB-invariánsok + privacy-adjacens kapcsolattípus)
- **Reviewer:** security-reviewer (READ-ONLY, AGENTS.md §15.1 — nincs prod-szerkesztés)
- **Verdikt:** **PASS** — nincs CRITICAL/BLOCKER. 1 latent MAJOR (a router jelenleg NEM mountolt → nem shippable), 2 MINOR, néhány NOTE.

A social-graph HTTP-router jelenleg **nincs bekötve a production app-ba** — ez a
tény a legtöbb hálózat-elérhető kockázatot latenssé (nem shippable) fokozza le.
Bizonyíték: `build_community_router()` (`backend/app/community/__init__.py`) csak
a `.routers.profile.router`-t adja vissza; `grep -rn "social_graph" backend/app/`
egyetlen `include_router`-t sem talál, csak a `follow_service` importját. A router
egyetlen fogyasztója a teszt-conftest.

---

## Ellenőrzött pontok és bizonyíték

### 1. Self-follow / duplikált-follow race-védelem — DB-szinten MEGVAN (A1/A2)
`backend/alembic/versions/e09_r07_0005_community_follow.py`:
- `community_follows`: `UNIQUE(follower_profile_id, followed_profile_id)` (91–95. sor) **ÉS** `CHECK(follower_profile_id != followed_profile_id)` (96–99. sor).
- `community_follow_requests`: `UNIQUE(requester_profile_id, target_profile_id)` (166–170. sor) **ÉS** `CHECK(requester_profile_id != target_profile_id)` (171–174. sor).

A védelem nem csak app-szintű `if`: a `follow()` (`follow_service.py:185–193`)
elkapja az `IntegrityError`-t, rollbackel és újraolvas — a race-t a DB unique
constraint zárja, az app csak fordít. **Megfelel.**

### 2. `community_follow_requests` egy-sor-per-pár, UPDATE-tel újrahasznosítva
`follow_service.py:197–212`: private célnál `_existing_request` SELECT → ha van és
`status=="requested"` visszatér; egyébként `status="requested"`, `responded_at=None`
és `flush()` (UPDATE), **nem** új INSERT. Új pár esetén INSERT + `IntegrityError`→
re-read (220–227). A race-window INSERT-et a pár-unique constraint zárja.
**Megfelel az ADR 0401 §4-nek.**

### 3. IDOR / jogosultság — a cselekvő profil MINDIG a JWT-ből
`backend/app/community/routers/social_graph.py`, minden mutáló végpont a
`_caller_profile_public_id(db, current_user.id)`-t adja át cselekvőként, sosem
kliens-adta id-t:
- `post_follow` (129. sor): `follower_public_id` = hívó.
- `post_accept_follow_request` (178.) / `post_decline_follow_request` (226.):
  `target_public_id` = hívó, és a service (`accept_follow_request:254–258`,
  `decline_follow_request:331–332`) elutasítja, ha
  `request.target_profile_id != target.id` → **más kérését nem lehet elfogadni/elutasítani**.
- `delete_follow` (273.): `follower_public_id` = hívó.
- `delete_follower` (315–323.): explicit `caller_public_id != public_id` → **403**;
  `owner_public_id` = path, ami kötelezően = hívó → **más követőjét nem lehet eltávolítani**.

A mutáló felület IDOR-védelme zárt. **Megfelel.**

### 4. Idempotencia — szerveroldali kulcstárolás NINCS, állapotgép-idempotencia van
Az `idempotency_key` átveendő, de sehol nem perzisztálódik (grep: nincs tábla/oszlop).
A retry-k a terminális állapotba konvergálnak:
- `follow` retry: meglévő él/kérés visszaadva hiba nélkül (178–179, 200–204).
- `accept` retry `accepted` állapoton: él megírva ha hiányzik, egyébként no-op (260–280).
- `decline` retry `declined`-on: no-op (333–334); `accepted`-on **elutasít** (335–340) —
  ez helyes: egy elfogadott kérést nem lehet utólag decline-nal visszavonni (§6.1 IDOR-regresszió elkerülése).
**Megfelel az ADR 0401 §6-nak.** (Egy dupla-`accept` verseny esetén a vesztes író
belső `rollback`-je visszagörgeti a saját `status='accepted'` írását is, de a győztes
már perzisztálta — a terminális állapot helyes; lásd NOTE-2.)

### 6. Block/mute stubok — `UnsupportedError`, nem csendes no-op
`relationship_repository_impl.dart`:
- `HttpSocialGraphRepository.block/unblock/mute/unmute` (251–285. sor): mind
  `throw UnsupportedError(...)` — nem `Future.value()`. Ez pontosan a §2
  "NEM-ELFOGADHATÓ GYENGÍTÉS" elkerülése (a csendes siker félrevezető lenne egy
  nem létező funkcióra).
- `DisabledSocialGraphRepository` (100–121.): `throw _disabled.error` (ConfigurationFailure).
**Megfelel.**

### 7. SQL injection / raw SQL — csak paraméterezett
Egyetlen raw SQL a diffben: `_caller_profile_public_id`
(`social_graph.py:429–434`): `text("SELECT public_id FROM community_profiles WHERE
user_id = :uid", {"uid": user_id})` — kötött paraméter, nincs string-interpoláció.
A `follow_service.py`-ban nincs `text(...)` (grep megerősítve). **Megfelel.**

### 8. A2 valódi-sértés próba — valódi, nem fake
`backend/tests/community/test_follow_service.py:390–519`
(`test_swap_unique_constraint_breaks_a2`): friss SQLite-ot alembic-el head-re visz,
majd DROP + CREATE TABLE **a pár-unique nélkül** (csak `UNIQUE(public_id)` + `CHECK`
marad, 426–438. sor), két thread konkurensen `service_follow`-t hív, és
`assert count == 2` (512.) — bizonyítva, hogy a production unique constraint a
tényleges védelem. Ez nem triviális assert; a hibamódot ténylegesen előállítja.
A `test_a2_concurrent_follow_writes_produce_one_row` (323–374.) a pozitív oldal
(`count == 1`). **Valódi regressziós őr.**

---

## Leletek

### MAJOR (latent — jelenleg NEM shippable, a router nincs mountolva)
**M1 — A follower/following lista-végpontok hitelesítetlenek és láthatóság-kapu nélküliek.**
`backend/app/community/routers/social_graph.py:352–413` (`get_followers`,
`get_following`): egyik GET végpontnak **nincs `current_user: CurrentUser`
paramétere** (szemben a hat mutáló végponttal), és nincs semmilyen
visibility-gating. Failure scenario: ha egy jövőbeli kör bekötné ezt a routert a
`build_community_router()`-be **anélkül**, hogy előbb auth + láthatóság-kaput
adna hozzá, akkor bárki (hitelesítés nélkül) lekérdezhetné egy tetszőleges — akár
`private` — profil teljes követő/követett listáját a `public_id` ismeretében
(`GET /community/profiles/{public_id}/followers`). Ez az AGENTS.md §5.4
(community funkció nem ronthatja az adatvédelmet) és a kör privacy-adjacens
céljának megsértése lenne.
- **Sértett szabály:** §5 termékhatár (privacy) — jövőbeli.
- **Miért csak latent:** `build_community_router()` (`community/__init__.py`)
  csak a `profile.router`-t adja vissza; a social_graph router sehol nincs
  `include_router`-rel bekötve (`grep -rn social_graph backend/app/`). Így a
  végpont production-ban **nem elérhető**. A brief §3 a láthatóság-kaput
  explicit a Kör 8/13-ra halasztja.
- **Javaslat iránya:** a router bekötése ELŐTT (Kör 8/13) kötelező (a) `CurrentUser`
  a két GET végpontra, (b) a Kör 4 `CommunityAccessPolicy` szerinti láthatóság-kapu
  a lista-olvasásra. Erős garancia lenne egy fail-closed teszt, amely azt bizonyítja,
  hogy a router NEM mountolható auth+gating nélkül. Ezt a review-t a mount-körben
  MEG KELL ismételni.

### MINOR
**m1 — `FollowAlreadyExists` a `post_follow`-ban nincs elkapva → 500 + potenciális constraint-név a hibában.**
`social_graph.py:126–139`: a `post_follow` csak `ValueError`-t és
`SelfFollowNotAllowed`-t kezel. A `follow()` viszont dobhat
`FollowAlreadyExists(str(exc))`-t (`follow_service.py:193`, `227`), amelynek üzenete
a nyers `IntegrityError` stringje (SQL + constraint-név). Failure scenario: egy
valódi race, ahol a `flush()` `IntegrityError`-t dob, de a re-read semmit nem talál
(pl. időzítési ablak) → a kivétel kezeletlenül propagál 500-ként; ha az app valaha
`debug=True`-val futna, a válasz kiszivárogtatná a constraint-nevet/SQL-t.
Production-ban (debug off) a FastAPI generikus "Internal Server Error"-t ad, így
valódi szivárgás nincs — de a helyes viselkedés 200 (idempotens siker) vagy 409 lenne.
- **Sértett szabály:** robustness / §5.3 (belső adat hibaüzenetben) — csak debug-on aktív.
- **Javaslat:** kapd el a `FollowAlreadyExists`-t is (mint a mutáló végpontok
  szimmetrikus párja), fordítsd 200/409-re, ne engedd a nyers `str(exc)`-t a válaszba.

**m2 — A Dart `delete()` nem továbbítja a kötelező `idempotency_key` query-paramétert.**
`lib/core/network/api_client.dart` (új `delete()`, +33 sor) nem fogad
query-paramétert, és `relationship_repository_impl.dart:197–199, 212–215`
(`unfollow`, `removeFollower`) `?idempotency_key=...` nélkül hív. A backend
`delete_follow`/`delete_follower` viszont `idempotency_key: str = Query(..., min_length=1)`
kötelezőt vár (`social_graph.py:257, 303`) → 422. Ez elsődlegesen **funkcionális**
(a unfollow/remove ma nem működne bekötve), a correctness-review hatásköre; itt
csak azért jelzem, mert az idempotencia-kulcs a mutáció-szerződés része. Biztonsági
hatás nincs (nem elérhető végpont). Ugyanígy a `followingPage`/`followersPage`
építi a `params`-t (limit/cursor), de nem adja át a `getJson`-nak (145–151, 163–169) — funkcionális, nem biztonsági.

### NOTE
- **N1 — Privacy-fallback fail-safe.** `_is_private` (`follow_service.py:99–114`)
  hiányzó privacy-sornál `True`-t (private) ad vissza — biztonságos alapértelmezés
  (ADR 0398 §5). Helyes irány.
- **N2 — Dupla-`accept` verseny.** `accept_follow_request` (`follow_service.py:282–306`):
  a vesztes konkurens író belső `db.rollback()`-je visszagörgeti a saját
  `status='accepted'` írását, majd mégis `accepted`-et jelent vissza; a győztes
  viszont már perzisztálta az `accepted`-et és az élt. A terminális DB-állapot
  helyes (unique él-constraint + re-read), a jelentett státusz konzisztens a
  végállapottal. Nincs teendő, csak dokumentálva.
- **N3 — Placeholder profil a lista-dekódolásban.** `_placeholderProfile`
  (`relationship_repository_impl.dart:365–388`) `visibility: followers` és
  `relationship: notRelated` fix értékeket ad a public_id-only oldalakhoz. Ez
  strukturális seam (a teljes profil a `fetchById` follow-up), nem
  false-confidence adat egy detektorból; a hívó a kanonikus úton feltölti.
- **N4 — Nincs log/analytics/titok-sink az új fájlokban.** `grep` a
  `follow_service.py` / `social_graph.py` / `social_graph.py (models)` fölött:
  nincs `logging`/`logger`/`print`; a controllerben sincs sink. Hibaüzenetek
  csak benign domain-szövegek (`str(exc)` domain-kivételen). Nincs
  token/audio/kamera-adat a diffben. `SecureStore` vs `KeyValueStore` nem
  érintett (a JWT a meglévő `flutter_secure_storage`-ban marad, e kör nem nyúl hozzá).

---

## Amit végignéztem és nem találtam problémát
- Titkok / kulcsok új fájlokban: nincs (diff átnézve; nincs credential-literál).
- Új dependency: nincs (a diff nem érint `pubspec`/`requirements`-et).
- Path traversal / zip / import: e kör nem csomagol ki külső tartalmat — nem érintett.
- Prompt injection / AI-provider: e kör nem érint AI-providert vagy promptot — nem érintett.
- Consent-kapu / nyers audio-kamera határ: e kör nem érint capture-t — nem érintett.
- Cursor: az opaque base64(JSON) kurzor dekódolása fail-safe (`_decode_cursor`
  `follow_service.py:440–448` minden hibát `None`-ra fog, nincs
  deszerializációs RCE; `int(payload["id"])` + `fromisoformat`).
