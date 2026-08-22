# E09-R07 — Follow és follow request social graph

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 7
- **Kör-azonosító:** `E09-R07`
- **Branch:** `<motor>/e09-r07-follow-and-follow-request-graph`
- **Előfeltétel:** `E09-R06` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** ~~`ADR 0400`~~ → **`ADR 0401`** (0400-at az E09-R06
  már felhasználta — l. §0.0 1. pont). Az ADR-t a Claude írta meg a kör
  indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

**Kockázat = high, indoklás:** a kör konkurencia-érzékeny adatbázis-
invariánsokat vezet be (self-follow és duplikált-follow race-védelem, A1/A2)
és egy privacy-adjacens kapcsolattípust (a follow-státusz a Kör 8/11/13
láthatósági policy jövőbeli bemenete lesz, ADR 0398 §2 "A visszavonás
feltétele") — egyik `allowed_paths` fájlnév sem tartalmazza szó szerint a
router `high_risk_path_fragments` listájának egyik tagját sem, de a
kockázat forrása a TARTALOM (race-biztos írás + a jövőbeli policy bemenete),
nem a fájlnév.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 4 `CommunityAccessPolicy` TÉNYLEGES relationship-paraméter alakját — a follow-service ebbe a szerződésbe kell illeszkedjen, nem egy párhuzamos, önálló relationship-fogalmat vezet be. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/models/social_graph.py",
  "backend/app/community/services/follow_service.py",
  "backend/app/community/routers/social_graph.py",
  "backend/alembic/versions/e09_r07_0005_community_follow.py",
  "lib/features/community/application/controllers/relationship_controller.dart",
  "lib/features/community/data/repositories/relationship_repository_impl.dart",
  "lib/features/community/presentation/screens/followers_screen.dart",
  "lib/core/network/api_client.dart",
  "backend/tests/community/test_follow_service.py",
  "test/features/community/application/relationship_controller_test.dart",
  "docs/rounds/e09-r07-follow-and-follow-request-graph.md",
]
gate_tests = [
  "test/features/community/application/relationship_controller_test.dart"
]
native_gate = false
```

**`lib/core/network/api_client.dart` SZŰKEN, egy okkal kerül az
`allowed_paths`-ra:** az implementer KIZÁRÓLAG egy ÚJ, additív `delete()`
metódust adhat hozzá (a meglévő `post()` pontos tükre, csak `method:
'DELETE'`-lel) — l. §0.0 4. pont + ADR 0401 §1. A meglévő négy metódus
(`getJson`/`postJson`/`putJson`/`post`) egyetlen sora sem módosulhat. Bármi
más ezen a fájlon: `stopped`.

## 0.0 Pre-flight brief-revízió (Claude, 2026-08-22, ADR 0401)

A brief eredeti, előre megírt változata öt ponton avult / hiányos volt a
2026-08-22-i tényellenőrzés szerint — a teljes indoklás és a kódrészletek
[ADR 0401](../adr/0401-follow-and-follow-request-social-graph.md)-ben:

1. **ADR-szám csere `0400` → `0401`** — a `0400` az E09-R06 saját ADR-je
   (HANDOFF E09-R06 bejegyzés), a queue-fájl `0400` értéke elavult feltevés
   volt.
2. **A domain-interfész NEM `RelationshipRepository`, hanem a MEGLÉVŐ
   `SocialGraphRepository`** (`lib/features/community/domain/repositories/
   social_graph_repository.dart`, Kör 5/ADR 0399, lezárt, tilos zóna). A
   `relationship_repository_impl.dart` (fájlnév marad) ezt az 11-metódusos
   interfészt implementálja; a `block`/`unblock`/`mute`/`unmute` négyes
   `UnsupportedError`-t dob (Kör 6/ADR 0400 precedens szerint) — ez NEM
   scope-bővítés, a Dart abstract interface class megköveteli mind a 11
   metódus jelenlétét fordításkor.
3. **Nincs külön "cancel" domain-metódus és endpoint** — a §3 scope "cancel"
   sora a MEGLÉVŐ `unfollow()` hívás egyik ága (a kérelmező saját függő
   kérését szünteti meg). A domain (`lib/features/community/domain/**`)
   emiatt NULLA diffet kap ebben a körben — a brief §4 tilos zóna
   "bővítés indokolt esettel" kitétele NEM aktiválódik.
4. **`lib/core/network/api_client.dart` nincs DELETE-metódussal** — a Kör 5
   Dart interfész `unfollow()`/`removeFollower()` HTTP-hívásához szükséges
   egy `delete()` metódus (a meglévő `post()` pontos tükre). Az idempotency
   key ezért metódusonként eltérő csatornán utazik: POST/PUT body-mezőként
   (`idempotency_key`), DELETE query-paraméterként (`?idempotency_key=`) —
   NINCS header-bővítés a meglévő metódusokon.
5. **`backend/app/community/__init__.py::build_community_router()` NEM
   bővül** — a Kör 3 (`handles.py`) precedens szerint a `social_graph.py`
   router tesztje önálló, helyi `FastAPI()`/`TestClient` fixture-t épít
   (`test_handle_policy.py` mintája), nem a `community_client_enabled`
   fixture-t. `backend/tests/community/conftest.py` bővítése SEM szükséges —
   a MEGLÉVŐ `community_two_auth_headers` fixture + a MEGLÉVŐ
   `POST /community/profiles/me` endpoint elég két teszt-profil
   létrehozásához.
6. **Migráció-lánc:** `down_revision = "e09_r04_0004"` (a MÉRT jelenlegi
   alembic-fej — E09-R05 Flutter-only, E09-R06 migráció nélküli volt, egyik
   sem bővítette a láncot).
7. **`community_follow_requests` egyedi-pár invariáns:** EGY sor a pár
   teljes élettartamára (plain `UNIQUE`, állapot-újrahasznosítás
   `UPDATE`-tel), NEM parciális/`status`-szűrt unique index — DB-portábilis
   SQLite/PostgreSQL között, l. ADR 0401 §4.
8. **Idempotency ebben a körben állapot-átmenet-idempotencia** — nincs
   `community_idempotency_records` tábla (SDD §20.1 jövőbeli tétel), a
   retry-biztonságot a service-réteg a természetes állapotgépből adja
   (l. ADR 0401 §6), nem külön kulcs-tárolásból.

**Visszakeresés (ADR 0312, §4.9):** `node tools/knowledge-rag.mjs --corpus
lessons,halts,adr --top 5 "follow social graph community request lifecycle
idempotent"` → a döntő találat `adr/0398` (`RelationshipContext` §"A
visszavonás feltétele": "Felülvizsgálandó, ha a Kör 7/8 mérten azt találja,
hogy a `RelationshipContext` mezőkészlete... bővítést igényel" — ez a kör
MÉRTEN azt találta, hogy NEM igényel bővítést, l. §0.0 1. pont) és `adr/0397`
(identity_service `commit_with_uniqueness_check` minta, amit a
`follow_service.py` a saját, azonos szerkezetű `IntegrityError`→domain-
kivétel fordításnál követ). `--corpus lessons,halts --top 5 "self-follow
database constraint race concurrent unique index"` → nincs pontosan
egyező korábbi halt/lecke erre a konkrét race-mintára (a legközelebbi
találatok más körök `merged` jelzései, tartalmilag nem relevánsak) —
**nincs releváns előzmény** lelet ezen az ágon, az ADR 0397/0398
minta-precedens fedezi a kockázatot.

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

Idempotens, privacy-kompatibilis követési rendszer: public profilnál azonnali follow, private profilnál explicit accept/decline lifecycle.

## 2. Jelenlegi állapot — mért tények

- A Kör 4 policy-mátrixa MA egy `RelationshipContext` paramétert fogad, de a tényleges follow-tábla és -szolgáltatás még nem létezik — ez a kör hozza létre
- `ProfileVisibility.private` (Kör 4) MA a request-alapú follow előfeltétele

## 3. Scope

**Benne van:** `community_follows` és `community_follow_requests` migráció egyedi constrainttel · public profilnál azonnali follow, private profilnál request lifecycle · accept, decline, cancel, unfollow, follower-removal · idempotency key minden mutációhoz · follower/following cursor pagination endpoint · kliens: optimistic follow CSAK public profilnál; private requestnél pending state.

**NINCS benne (tilos):**

- Block/mute — Kör 8.
- Feed vagy post látás a follow alapján — Kör 13.
- `docs/adr/**` — az ADR 0400-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/models/social_graph.py` | ÚJ — follow + follow_request tábla |
| `backend/app/community/services/follow_service.py` | ÚJ — lifecycle + idempotency |
| `backend/app/community/routers/social_graph.py` | ÚJ — endpointok |
| `backend/alembic/versions/e09_r07_0005_community_follow.py` | ÚJ |
| `lib/features/community/application/controllers/relationship_controller.dart` | ÚJ |
| `lib/features/community/data/repositories/relationship_repository_impl.dart` | ÚJ |
| `lib/features/community/presentation/screens/followers_screen.dart` | ÚJ |
| `backend/tests/community/test_follow_service.py` | ÚJ — a §6 cellái |
| `test/features/community/application/relationship_controller_test.dart` | ÚJ |

**Tilos zóna:** `lib/features/community/domain/**` (csak olvasás, bővítés indokolt esettel) · `backend/app/community/policies/access_policy.py` (Kör 4 lezárt szerződése) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0401)

### 5.1 A follow-mutáció idempotens és adatbázis-szinten védett self-follow ellen

`CHECK (follower_profile_id != followed_profile_id)` és `UNIQUE (follower_profile_id, followed_profile_id)` — a védelem NEM alkalmazás-szintű `if` ág, mert azt egy race megkerülheti.

**NEM elfogadható gyengítés:** egy service-szintű `if follower == followed: raise` ellenőrzés adatbázis-constraint nélkül — versenyhelyzetben duplikált vagy self-follow rekord keletkezhet.

### 5.2 Private profilnál a follow REQUEST-alapú, explicit elfogadással

`requested → accepted | declined | cancelled` — a kliens optimistic UI-ja CSAK a public úton engedett; private profilnál a UI `pending` állapotot mutat, amíg a szerver nem erősít vissza.

### 5.3 A follower eltávolítása NEM igényel blockot

A profil tulajdonosa eltávolíthat egy követőt anélkül, hogy blockolná — ez két külön, egymástól független művelet.

### 5.4 A migráció a MÉRT jelenlegi fejre láncol

`backend/alembic/versions/e09_r07_0005_community_follow.py`:
`down_revision = "e09_r04_0004"` (l. §0.0 6. pont). A `community_follows` ÉS
`community_follow_requests` táblák EGY migrációs fájlban jönnek létre;
mindkettőn `CHECK (... != ...)` self-reláció-tiltás (§0.0 / ADR 0401 §4–5).

### 5.5 `relationship_repository_impl.dart` a MEGLÉVŐ `SocialGraphRepository`-t implementálja

Nem egy új interfészt — l. §0.0 2. pont. A `block`/`unblock`/`mute`/`unmute`
`UnsupportedError`-t dob (Kör 6/ADR 0400 precedens). „Cancel" a meglévő
`unfollow()` egyik ága, nincs külön domain-metódus (§0.0 3. pont). A
`lib/core/network/api_client.dart` egyetlen ÚJ `delete()` metódust kap
(§0.0 4. pont, ADR 0401 §1) — semmi mást ezen a fájlon.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Self-follow tiltott adatbázis-szinten | `test_follow_service.py` |
| A2 | Duplikált follow retry vagy versenyhelyzet mellett sem keletkezik | `test_follow_service.py` — concurrent teszt |
| A3 | Private profil accept/decline/cancel lifecycle helyes | `test_follow_service.py` |
| A4 | Follower removal nem igényel blockot | `test_follow_service.py` |
| A5 | Cursor pagination stabil, nincs duplikált oldal | `test_follow_service.py` |
| A6 | Optimistic follow rollback hálózati hiba esetén (Flutter) | `relationship_controller_test.dart` |
| A7 | Public profilnál a follow azonnali, private profilnál pending | `relationship_controller_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A self-follow csak service-szinten ellenőrzött, DB-constraint nélkül | A1 |
| Két konkurens follow-kérés mindkettő sikeres rekordot hoz létre | A2 |
| Private profilnál a follow azonnal `accepted`-ként kerül be | A3 |
| A follower-removal blockot is létrehoz | A4 |
| Public profilnál a UI `pending` állapotot mutat a tényleges azonnali siker helyett | A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a `(follower_profile_id, followed_profile_id)` unique constraintet, futtasd a backend pytest-et konkurens kérésekkel → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/application/relationship_controller_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_follow_service.py -q
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

1. Migráció: `community_follows` (unique + check constraint), `community_follow_requests`.
2. `follow_service.py` — public azonnali / private request lifecycle, idempotency key.
3. `social_graph.py` router — follow, accept, decline, cancel, unfollow, follower-removal, cursor pagination.
4. `relationship_controller.dart` — optimistic (public) / pending (private) állapotgép.
5. `followers_screen.dart` — lista cursor paginationnel.
6. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **Az alkalmazás-szintű self-follow/duplikáció-ellenőrzés.** Ez a legkritikusabb invariáns — csak DB-constraint biztosítja versenyben (A1/A2).
- **A private-follow azonnali elfogadása.** Ha a request-lifecycle kihagyható, a privát profil védelme illúzió (A3).
- **A follower-removal és a block összemosása.** A termék két külön eszközt kínál különböző súlyossággal (A4).

## 10. Implementation handoff — az implementer tölti ki

### Javító kör 1 (E09-R07 fix1) — 2026-08-22

A javító kör 1 a `docs/reviews/e09-r07-review.md` mind az öt leletét (1
BLOCKER, 2 MAJOR, 1 MINOR, 1 NOTE) lezárja, ugyanazzal a motorral
(`minimax`), a `minimax/e09-r07-follow-and-follow-request-graph`
branch-en.

#### Mit készített

* **F1 (BLOCKER, megoldva):** a `test_swap_unique_constraint_breaks_a2`
  párhuzamossági teszt determinisztikussá téve egy teszt-oldali
  monkey-patch-csel, ami a `follow_service._existing_follow` függvényt
  cseréli le egy Barrier-vel szinkronizált verzióra. A `writer()`
  szintű Barrier nem volt elég (a service 3 SELECT-et futtat, mielőtt
  INSERT-elne; az első szál végigment az egész existence-check →
  INSERT → commit úton, mire a második egyáltalán a saját
  existence-check-jéhez ért — ezért a második `_existing_follow`
  már megtalálta az első sorát és short-circuit-ölt). A Barrier a
  `_existing_follow` belsejébe téve mindkét szálat ugyanannál a
  SQL-döntési pontnál tartja, így mindkettő INSERT-el, és UNIQUE
  constraint hiányában mindkét INSERT sikeres → 2 sor a táblában
  (a §6.1 valódi-sértés cella determinisztikusan piros).
* **F2 (MAJOR, megoldva):** a `get_followers` és `get_following`
  endpointok felvettek egy `current_user: CurrentUser` paramétert — a
  router minden más mutáló végpontjával konzisztensen. A láthatósági
  szűrés (Kör 8/13) továbbra is kimaradt, de a hitelesítés a router
  saját invariánsa. Két új teszt (403-as `Authorization`-nélküli
  elutasítás — a FastAPI `HTTPBearer(auto_error=True)` "no bearer
  at all" kódja, a `test_auth.py::142` precedens szerint) + egy
  200-as happy-path (auth-val) a `test_follow_service.py`-ban.
* **F3 (MAJOR, megoldva):** a `relationship_repository_impl.dart`
  `unfollow()` és `removeFollower()` metódusai a `DELETE` URL-be
  fűzik az `?idempotency_key=${Uri.encodeQueryComponent(key)}` query
  paramétert — a backend `social_graph.py::delete_follow[er]`
  KÖVETELTE (`min_length=1`, nincs alapérték). Három új teszt a
  `relationship_controller_test.dart`-ban (`_ScriptedAdapter`-rel
  rögzített `RequestOptions`) a ténylegesen küldött URL-t asszertálja,
  nem csak a visszaadott `AppResult`-ot.
* **F4 (MINOR, megoldva):** a `post_follow` router végpont most
  elkapja a `FollowAlreadyExists` service-exceptiont és
  `{"status": "following", ...}` sikeres válasszal tér vissza
  (`db.rollback()` után) — a service által dokumentált ritka race
  kimenetel nem nyers 500 + `str(IntegrityError)`, hanem idempotens
  siker. Új teszt monkeypatch-csel szimulálja a `follow` service
  kivételét és ellenőrzi a 200-as választ.
* **F5 (NOTE, megoldva):** ez a §10 — a javító kör 1 handoffja.

A teljes javító kör 1 diff: 5 commit a branch-en, minden lelet
konkrétan azonosítható commit message-ben.

#### F1 döntés — `_existing_follow`-ba injektált Barrier (a preferencia)

A review két utat kínált: (a) Barrier-rel determinisztikussá tenni a
tesztet, vagy (b) kivenni a suite-ból és egyszeri manuális próbaként
dokumentálni. Az (a) utat választottam, de a service_follow belsejébe
kellett a Barrier, nem a writer()-be — az utóbbi nem tudja garantálni,
hogy a két szál a létezés-ellenőrzés pillanatában együtt legyen, mert
a service_follow előtte 3 SELECT-et futtat (follower, target,
existence_check). A megoldás: a teszt monkey-patch-csel kicseréli
`follow_service._existing_follow`-t egy Barrier-szinkronizált verzióra,
amiben mindkét szál a `barrier.wait()`-nél várakozik, MINDKETTŐ
meghívja az eredeti függvényt (mindkettő `None`-t lát, mert a Barrier
PONT az SQL-döntés előtt tartja őket), MINDKETTŐ továbblép az INSERT-re.
UNIQUE constraint nélkül mindkét INSERT sikeres, count == 2
determinisztikusan.

15 egymást követő futtatásból 15/15 zöld (l. lent).

#### §6.1 valódi-sértés próba — ténylegesen elvégzett proof

A brief §6.1 kötelező valódi-sértés próbája a `(follower_profile_id,
followed_profile_id)` unique constraint eltávolításával demonstrálja,
hogy KONKURENS hívás esetén az A2 cella pirosra vált. A teszt a
`test_swap_unique_constraint_breaks_a2` — Barrier-rel a futása
determinisztikus.

Az implementer a javító körben a következőt futtatta:

```bash
cd backend
# 1) A unique constraint ELTÁVOLÍTÁSA (a teszt maga csinálja, tmp_path-on):
#    A CREATE TABLE community_follows már NEM tartalmazza a
#    ``UNIQUE (follower_profile_id, followed_profile_id)`` constraintet.
# 2) A teszt indítása — a Barrier biztosítja, hogy a két szál
#    egyszerre lépjen a service_follow() hívásba:
python3 -m pytest tests/community/test_follow_service.py::test_swap_unique_constraint_breaks_a2 -q
# 3) Elvárt: count == 2 (két sor a community_follows táblában).
```

Eredmény a javító kör 1 előtt (a review mérte): 10 futtatásból 7
PIROS (`count == 1`, nem 2). Eredmény a javító kör 1 után (Barrier-rel,
saját mérés a §6.1 mintát követve): **15 futtatásból 15 ZÖLD**, a
két szál minden esetben átjut az existence-check → INSERT ablakon,
mindkét `INSERT` sikeres (mert nincs UNIQUE), `count == 2`.

```bash
$ cd /home/ubuntu/ss-mm-e09-r07/backend
$ for i in $(seq 1 15); do
    python3 -m pytest tests/community/test_follow_service.py::test_swap_unique_constraint_breaks_a2 \
      2>&1 | grep -E "passed|failed" | tail -1
  done
1 passed, 4 warnings in 0.77s
1 passed, 4 warnings in 0.75s
1 passed, 4 warnings in 0.74s
1 passed, 4 warnings in 0.75s
1 passed, 4 warnings in 0.74s
1 passed, 4 warnings in 0.75s
1 passed, 4 warnings in 0.74s
1 passed, 4 warnings in 0.74s
1 passed, 4 warnings in 0.73s
1 passed, 4 warnings in 0.75s
1 passed, 4 warnings in 0.75s
1 passed, 4 warnings in 0.75s
1 passed, 4 warnings in 0.74s
1 passed, 4 warnings in 0.74s
1 passed, 4 warnings in 0.76s
# 15/15 green — timing consistent ~0.74s
```

(Azonos service layer re-read-et a teszt kódja `FollowAlreadyExists`
kivételként is elfogadja — ezen az ágon a `count` bizonyítja a
constraint nélküli állapotot, nem a kivétel típusa.)

#### Diff statisztika

A javító kör 1 kizárólag az `allowed_paths` listáján lévő fájlokat
érinti (a `docs/reviews/e09-r07-security-review.md` reviewer-artifact,
ami a review-commit során jött létre, a `git add -A` egyszer
besöpörte — a javító kör 1 végén külön `git rm`-elve lett, így az
implementer commit nem nyúlt hozzá):

```
 backend/app/community/routers/social_graph.py    | F2 (current_user a
                                                   GET endpointokon) +
                                                   F4 (FollowAlreadyExists)
 backend/tests/community/test_follow_service.py   | F1 (Barrier) + F2
                                                   (3 új teszt) + F4
                                                   (1 új teszt)
 lib/features/community/data/repositories/
   relationship_repository_impl.dart              | F3 (idempotency_key
                                                   query param a DELETE URL-be)
 test/features/community/application/
   relationship_controller_test.dart              | F3 (3 új URL-assert
                                                   teszt scripted adapterrel)
 docs/rounds/e09-r07-follow-and-follow-request-
   graph.md                                       | F5 (ez a §10)
```

## 11. Review — a Claude tölti ki
