# ADR 0401 — Follow és follow-request social graph

- **Státusz:** Elfogadva (E09-R07 pre-flight, 2026-08-22)
- **Kör:** E09-R07 — Follow és follow request social graph
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 7 (a 32 kör közül a hetedik)
- **Kontext-ADR-ek:** [0399](0399-flutter-community-domain-and-public-api.md)
  (Kör 5 — `SocialGraphRepository` domain-interfész, `CommunityPage`/
  `CursorPage`/`ContentId`/`PublicUserId` value objectek), [0398](0398-profile-privacy-audience-policy-and-access-control.md)
  (Kör 4 — `RelationshipContext`/`CommunityAccessPolicy`, `ProfileVisibility`),
  [0400](0400-profile-onboarding-service-and-community-gate-ui.md) (Kör 6 —
  `HttpCommunityProfileRepository` minta, `UnsupportedError` a még-nem-
  implementált interfész-metódusra).
- **Sorszám-jegyzet:** a `docs/execution/pipeline-queue.tsv` E09-R07 sora
  `0400`-at adott előre kiosztott ADR-ként, de ez a szám MÁR foglalt (a Kör 6
  ADR-je) — a `tools/round-slots.py reserve-adr --round E09-R07` friss számot
  adott (`0401`, Epic 9 batch-tartomány 0395–0419).

## Kontextus

**Mért 2026-08-22-én, a pre-flightban:**

1. `backend/app/community/policies/access_policy.py` `RelationshipContext`
   mezői (`viewer_is_owner`, `blocked`, `is_follower`, `is_club_member`) MA
   is szintetikus, hívó által összeállított paraméterek — ez a kör NEM tölti
   ki élő adattal (a `NINCS BENNE` lista kifejezetten kizárja a feed/post
   láthatóságot, Kör 13 dolga). A follow-service tehát nem a policy-t hívja,
   hanem önálló, a policy-től független táblákat és service-réteget épít; a
   `is_follower` mezőnév-egyezés (nem `following`/`isFollowing`) a JÖVŐBELI
   Kör 8/11/13 kötelezettsége, amikor a policy-t élő adattal hívják.
2. `lib/features/community/domain/repositories/social_graph_repository.dart`
   (Kör 5, ADR 0399) MÁR létező, lezárt domain-interfész: `SocialGraphRepository`
   — NEM egy még megírandó `RelationshipRepository`. A brief `allowed_paths`-a
   egy `relationship_repository_impl.dart` NEW fájlt sorol fel — ez az
   OSZTÁLY neve és fájlneve, az interfész, amit implementál, a MEGLÉVŐ
   `SocialGraphRepository`. Az interfész 11 metódust ad
   (`followingPage`, `followersPage`, `follow`, `unfollow`, `removeFollower`,
   `acceptFollowRequest`, `declineFollowRequest`, `block`, `unblock`, `mute`,
   `unmute`) — a `block`/`mute` négyes Kör 8 hatókör, de a Dart abstract
   interface class MIND a 11 metódus implementációját megköveteli
   fordításkor.
3. A domain-interfészben NINCS külön `cancelFollowRequest` metódus, és az
   SDD §21.3 API-listája sem sorol fel külön cancel endpointot — csak
   `DELETE /v1/community/profiles/{id}/follow` (unfollow) és
   `POST .../accept` / `POST .../decline`. A §10.1 lifecycle
   (`requested → accepted | declined | cancelled`) a "cancelled" állapotot a
   KÉRELMEZŐ saját döntéseként írja le — ez pontosan a meglévő `unfollow()`
   hívás szemantikája a kérelmező oldaláról nézve (én szüntetem meg a saját
   kimenő kapcsolatomat, függetlenül attól, hogy az még függőben van vagy már
   elfogadták). A domain-interfész emiatt NEM bővítendő (a `lib/features/
   community/domain/**` tilos zóna ezen a körön változatlanul nulla-diff
   marad).
4. `lib/core/network/api_client.dart` MA három JSON-metódust ad
   (`getJson`/`postJson`/`putJson`) és egy body-mentes `post()`-ot (void
   válasz, `headers` paraméterrel) — **nincs DELETE-metódus**. Az SDD §21.3
   két DELETE endpointot ír elő (`DELETE .../follow`, `DELETE .../
   followers/{id}`). Enélkül `unfollow()`/`removeFollower()` nem hívható HTTP
   szinten.
5. `backend/app/community/__init__.py::build_community_router()` MA
   KIZÁRÓLAG a `routers/profile.py` routerét adja vissza — a Kör 3
   (`handles.py`) és ez a kör (`social_graph.py`) routerei NEM ezen a
   csatornán mennek élesbe. A precedens (`backend/tests/community/
   test_handle_policy.py`) egy ÖNÁLLÓ, a saját routerét közvetlenül
   importáló, helyi `FastAPI()` + `TestClient` fixture-t épít — a
   `community_client_enabled` fixture-t NEM használja. A `social_graph.py`
   router tesztje ugyanezt a mintát követi; a `community/__init__.py`
   módosítása (router-mounting) EBBEN a körben nem szükséges és tilos zóna
   marad.
6. `backend/tests/community/conftest.py` MÁR ad egy `community_two_auth_headers`
   fixture-t (E09-R06, az A8 konkurencia-teszthez) — két önálló,
   `Authorization` fejléces userre. A profil-sorokat a MEGLÉVŐ
   `POST /community/profiles/me` endponton keresztül (a helyi teszt-app saját
   routerén, `routers/profile.py`) lehet létrehozni mindkét userhez — a
   `conftest.py` bővítése NEM szükséges ehhez a körhöz.
7. Az alembic-lánc feje MA `e09_r04_0004` (`e01_r12_0001 → e09_r02_0002 →
   e09_r03_0003 → e09_r04_0004`) — az E09-R05 (Flutter-only) és E09-R06
   (service-szintű, migráció nélküli) egyik sem bővítette a láncot.
8. Nincs `community_idempotency_records` tábla (az SDD §20.1 csak
   jövőbeli táblaként sorolja fel) — ez a kör nem vezet be külön
   idempotency-key-tárolást.

## Döntés

### 1. `lib/core/network/api_client.dart` SZŰK bővítése: egyetlen `delete()` metódus

```dart
// lib/core/network/api_client.dart — ÚJ metódus, a meglévő post() pontos tükre
Future<AppResult<void>> delete(
  String path, {
  Map<String, Object?> headers = const {},
  bool requiresAuthentication = true,
}) async {
  try {
    await _dio.request<Object?>(
      path,
      options: Options(
        method: 'DELETE',
        headers: headers,
        extra: {
          NetworkRequestMetadata.requiresAuthentication: requiresAuthentication,
        },
      ),
    );
    return const Success(null);
  } on DioException catch (error, stackTrace) {
    return Failure(mapNetworkFailure(error, stackTrace: stackTrace));
  } catch (error, stackTrace) {
    return Failure(UnknownFailure(cause: error, stackTrace: stackTrace));
  }
}
```

`lib/core/network/api_client.dart` ezért a brief `allowed_paths`-ára kerül,
KIZÁRÓLAG erre az egy, additív metódusra szűkítve — nulla módosítás a
meglévő négy metóduson. **NEM elfogadható gyengítés:** a `_requestJson`
JSON-dekódoló ág módosítása vagy a meglévő metódusok szignatúrájának
bővítése — a DELETE válasz testét ez a kör sosem dekódolja (204/void).

Az idempotency key transport-módja emiatt metódusonként eltér, hogy ez az
egy metódus elég legyen:

- `POST`/`PUT` mutáció (follow, accept, decline): a kulcs a JSON body
  `idempotency_key` mezője (a MEGLÉVŐ `postJson`/`putJson` `data` paramétere
  hordozza — nincs szükség header-bővítésre).
- `DELETE` mutáció (unfollow/cancel, follower-removal): a kulcs query-
  paraméterként megy (`?idempotency_key=...`), mert a `delete()` nem hordoz
  JSON body-t.

### 2. A domain-interfész NEM bővül; a block/mute négyes `UnsupportedError`-t dob

`relationship_repository_impl.dart` a MEGLÉVŐ `SocialGraphRepository`-t
implementálja (2. kontextus-pont). A `block`/`unblock`/`mute`/`unmute`
metódusok a Kör 6 precedensét követik szó szerint
(`HttpCommunityProfileRepository.fetchById`, ADR 0400):

```dart
@override
Future<void> block({required PublicUserId target, required String idempotencyKey}) =>
    throw UnsupportedError('SocialGraphRepository.block is not yet implemented');
```

**NEM elfogadható gyengítés:** a négy metódus csendes no-op implementációja
(sikeres `Future.value()` visszaadása) — az félrevezető sikert jelentene egy
funkcionalitásra, ami nem létezik (Kör 8).

### 3. „Cancel" a meglévő `unfollow()` hívás egyik ága, nem külön domain-metódus

A backend `DELETE /community/profiles/{id}/follow` (vagy ezzel ekvivalens
service-hívás) a HÍVÓ (kérelmező) nézőpontjából állapot-elágaztat:

1. Ha van AKTÍV `community_follows` sor a (hívó → cél) párra → törli
   (valódi unfollow).
2. Egyébként, ha van `requested` állapotú `community_follow_requests` sor,
   ahol a hívó a kérelmező → `cancelled`-re állítja (cancel).
3. Egyébként idempotens no-op siker (nincs sem aktív follow, sem függő
   kérés — a hívó már "nem követi" állapotban van, ismételt hívás nem hiba).

A Flutter `relationship_repository_impl.dart` a `unfollow()` metódust
MINDKÉT (valódi unfollow ÉS saját kérés visszavonása) UI-eseményre ugyanazzal
a hívással szolgálja ki — a képernyő a `CommunityRelationshipToViewer`
(`pendingRequestOutgoing` vs. `youFollowThem`) állapotból tudja, melyik eset
áll fenn, de a repository-hívás azonos.

### 4. `community_follow_requests`: EGY sor pár élettartamára, állapot-újrahasznosítással

```python
# backend/app/community/models/social_graph.py
class CommunityFollowRequest(Base):
    __tablename__ = "community_follow_requests"

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"), primary_key=True
    )
    public_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), unique=True, index=True, default=uuid.uuid4, nullable=False
    )
    requester_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    target_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    status: Mapped[str] = mapped_column(String, nullable=False, default="requested")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow, nullable=False)
    responded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        UniqueConstraint("requester_profile_id", "target_profile_id"),
        CheckConstraint("requester_profile_id != target_profile_id"),
    )
```

**Miért EGY sor a pár teljes élettartamára (nem új INSERT minden
follow-kísérletnél):** egy sima `UNIQUE(requester_profile_id,
target_profile_id)` DB-portábilis SQLite/PostgreSQL között; egy `status`
szerinti parciális unique index (`WHERE status = 'requested'`) dialektus-
függő szintaxist igényelne (SQLAlchemy `sqlite_where=`/`postgresql_where=`
duplán karbantartva) — a plain unique + állapot-újrahasznosítás (egy
elutasított/visszavont kérés újra-követési kísérlet esetén `UPDATE ... SET
status = 'requested', responded_at = NULL`) ugyanazt az invariánst
(legfeljebb egy függő kérés párononként) egyszerűbben, egy indexen adja.
`status`, mint a projekt MEGLÉVŐ `visibility`/`audience_default` mintája
(ADR 0398 §1), plain `String` — az érvényesség a service-rétegen dől el, nem
DB `CHECK`-kel (az érték-készlet a jövőben bővülhet anélkül, hogy migráció
kellene).

**NEM elfogadható gyengítés:** a `UniqueConstraint` elhagyása és
alkalmazás-szintű "SELECT majd INSERT" ellenőrzés — ez pontosan az A2
race-ablak (két konkurens follow-kérés).

### 5. `community_follows`: a brief §5.1 szerint, self-follow CHECK mindkét táblán

```python
class CommunityFollow(Base):
    __tablename__ = "community_follows"

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"), primary_key=True
    )
    follower_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    followed_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow, nullable=False)

    __table_args__ = (
        UniqueConstraint("follower_profile_id", "followed_profile_id"),
        CheckConstraint("follower_profile_id != followed_profile_id"),
    )
```

A `CheckConstraint` a `community_follow_requests`-en (4. pont) a §5.1
invariáns kiterjesztése defenzív mélységként — a brief csak a
`community_follows`-on írja elő explicit, de ugyanabban a migrációs
fájlban, nulla extra scope-tal járó bővítés.

### 6. Idempotency: állapot-átmenet-idempotencia, NEM külön kulcs-tárolás

Nincs `community_idempotency_records` tábla ebben a körben (8. kontextus-
pont). A kliens által küldött `idempotency_key` a §1 szerint utazik a
kérésben (API-szerződés-kompatibilitás, SDD §21.1 "header VAGY body
field"), de a backend NEM perzisztálja kulcsonként — a service-réteg a
TERMÉSZETES állapot-idempotenciára épít:

- `follow()` retry ugyanarra a párra: ha már van aktív `community_follows`
  sor VAGY `requested` állapotú kérés → siker (nem hiba), nincs új sor.
- `accept`/`decline` retry: ha a sor MÁR a célállapotban van → siker
  (nem hiba, nem 409).
- `unfollow`/`cancel` retry: a 3. pont §3. ága már idempotens no-op-ot ad.

**NEM elfogadható gyengítés:** egy retry-t 409/500-cal elutasítani, mert a
sor már a kért célállapotban van — ez a kliens optimistic UI-ját
(brief §5.2) törné el egy hálózati retry esetén.

### 7. Cursor pagination: `(created_at, id)` összetett rendezés, opaque cursor

A follower/following lista `ORDER BY created_at DESC, id DESC` — az `id`
tie-breaker azonos-időbélyegű (ugyanazon tranzakción belüli, teszt-
determinisztikus) sorok esetén zárja ki a duplikált vagy kihagyott oldalt
(A5). Nincs backend-oldali cursor-pagination precedens ma a Community
modulban (6. kontextus-pont) — ez a kör az első; az opaque cursor a
`(created_at, id)` párt kódolja (a pontos szerializációt az implementer
választja, a Flutter oldal a `CursorPage`/`CommunityPage<T>` meglévő,
tartalom-agnosztikus value objecteken keresztül fogyasztja, ADR 0399).

### 8. Migráció-lánc: `down_revision = "e09_r04_0004"`

A `backend/alembic/versions/e09_r07_0005_community_follow.py`
`down_revision`-je a MÉRT jelenlegi fej (7. kontextus-pont) — nem az
`e09_r03_0003` (a queue-fájl korábbi, elavult feltevése).

## Elutasított alternatívák

- **Külön `cancelFollowRequest` domain-metódus hozzáadása a
  `SocialGraphRepository`-hoz.** Elvetve: sem az interfész (Kör 5, lezárt
  szerződés), sem az SDD API-lista nem különíti el a cancel-t az
  unfollow-tól; egy új metódus a `lib/features/community/domain/**` tilos
  zóna megbontása lenne olyan funkcionalitásért, amit a meglévő `unfollow()`
  már lefed (3. döntési pont).
- **Parciális unique index (`WHERE status = 'requested'`) a
  `community_follow_requests`-en, hogy több lezárt kérés is élhessen
  párononként.** Elvetve: dialektus-függő szintaxis (SQLite `sqlite_where=`
  vs. PostgreSQL `postgresql_where=`) duplikált karbantartással, amikor az
  állapot-újrahasznosítás (4. döntési pont) DB-portábilisan ugyanazt az
  invariánst adja.
- **`community/__init__.py::build_community_router()` bővítése, hogy a
  `social_graph.py` routerét is visszaadja.** Elvetve: a Kör 3
  (`handles.py`) router SOSEM ment ezen a csatornán élesbe — a mért
  precedens (`test_handle_policy.py` önálló `FastAPI()` fixture-e) ezt a
  kört is ugyanerre az útra tereli, `__init__.py` nulla-diff marad.
- **Header-alapú idempotency-key transport minden metódusra (a `postJson`/
  `putJson` szignatúra `headers` paraméterrel bővítve).** Elvetve: a
  body-mező (POST/PUT) + query-paraméter (DELETE) kombináció az
  `api_client.dart` bővítését egyetlen additív metódusra (`delete()`) szűkíti
  — a cél a MINIMÁLIS collateral diff egy megosztott core fájlon.

## Következmények

- `lib/core/network/api_client.dart` mostantól öt metódust ad
  (`getJson`/`postJson`/`putJson`/`post`/`delete`) — minden jövőbeli
  Community-kör (Kör 8+ block/mute, Kör 11+ post/comment delete) ezt a
  `delete()`-et használja saját DELETE-hívásaihoz, nem vezet be párhuzamos
  megoldást.
- A `community_follow_requests.status` érték-készlete
  (`requested`/`accepted`/`declined`/`cancelled`) mostantól stabil,
  service-szinten validált szerződés — bővítése (nem a meglévő értékek
  átnevezése) egy jövőbeli kör dolga, ADR-hivatkozással.
- A `SocialGraphRepository.block`/`unblock`/`mute`/`unmute`
  `UnsupportedError`-ja Kör 8 explicit előfeltétele: az a kör ezt a négy
  metódust váltja valódi implementációra, nem új metódust ad hozzá.

## A visszavonás feltétele

Felülvizsgálandó, ha a Kör 8 mérten azt találja, hogy a block-művelet
(SDD §10.5 "follow kapcsolatok törlődnek") a `community_follows`/
`community_follow_requests` táblák közvetlen írását igényli a
`follow_service.py`-n kívülről — ekkor a Kör 8 brief dönti el, hogy egy
megosztott service-függvényt exportál-e a `follow_service.py`-ból (bővítés,
nem újraírás) vagy saját tranzakciót nyit ugyanazokon a táblákon.
