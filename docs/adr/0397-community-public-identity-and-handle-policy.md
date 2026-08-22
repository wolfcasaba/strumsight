# ADR 0397 — Community public identity: injektálható UUID-generátor, normalizált handle-egyediség, cooldown+redirect history

- **Státusz:** Elfogadva (E09-R03 pre-flight, 2026-08-22)
- **Kör:** E09-R03 — Public identity és handle policy
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 3 (a 32 kör közül a harmadik)
- **Kontext-ADR-ek:** [0396](0396-community-backend-module-boundary-and-first-migration.md)
  (Kör 2 — `community_profiles.public_id` séma, whitelist-only Pydantic válasz,
  `Uuid(as_uuid=True)` dialektus-portábilis típus), [0395](0395-community-baseline-feature-flags-and-threat-model-scope.md)
  (Kör 1 — `community_enabled` flag-ek, threat-model scope).
- **Sorszám-jegyzet:** a szám a `tools/round-slots.py reserve-adr --round
  E09-R03` foglalótól jött (Epic 9 batch-tartomány 0395–0419), és a
  `docs/execution/pipeline-queue.tsv`-ben előre dokumentált `0397` értékkel
  egyezik.

## Kontextus

**Mért 2026-08-22-én, a pre-flightban (lásd a brief §0.0-ját is):**

1. `backend/app/community/models/profile.py` (E09-R02) ma `id`
   (BigInteger/Integer-variant PK) + `public_id` (`Uuid(as_uuid=True),
   unique=True, index=True, default=uuid.uuid4, nullable=False`) +
   `user_id` + `display_name` + `created_at` — **nincs `handle` mező és
   nincs `policies/`/`services/` alkönyvtár** a Community fában.
2. `backend/app/ratelimit.py` egy MEGLÉVŐ, stdlib-only, in-memory sliding-
   window `RateLimiter` (round 120, `backend/app/routers/auth.py` már
   használja `login_limiter`/`register_limiter` mintával). Ez a kör
   ÚJRAHASZNÁLJA ezt az osztályt az availability endpointhoz — nem ír saját
   rate-limit mechanizmust.
3. `backend/alembic/versions/e09_r02_0002_community_profile.py` az EGYETLEN
   Community migráció (`revision = "e09_r02_0002"`, `down_revision =
   "e01_r12_0001"`). Az ÚJ migráció ennek a láncnak a folytatása.
4. Az SDD (`docs/sdd/10-epic-09-community-platform.md`, Kör 3) nem ad
   numerikus cooldown/redirect-ablak értéket — ezek ennek az ADR-nek a
   döntései.
5. A brief `allowed_paths`-a NEM tartalmazza a `backend/app/community/
   routers/profile.py`-t (a Kör 2 profil-GET route-ját). A handle→profil
   redirect-felbontás tehát KIZÁRÓLAG az ÚJ `handles.py`-ban élhet, nem a
   meglévő profil-endpointban.

## Döntés

### 1. Handle-oszlopok a `community_profiles` táblán (nem külön tábla)

```python
handle_display: Mapped[str | None] = mapped_column(String(24), nullable=True)
handle_normalized: Mapped[str | None] = mapped_column(String(24), nullable=True)
handle_changed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
```

- `handle_display`: a user által beírt, EREDETI (nem case-folded) alak —
  ez jelenik meg a UI-ban.
- `handle_normalized`: a §2 normalizáló függvény kimenete — ezen fut az
  egyediség.
- Unique **index** `handle_normalized`-en (`ix_community_profiles_handle_normalized`,
  `unique=True`). Több `NULL` egyszerre megengedett (SQL unique-index
  szemantika — a NULL sosem egyenlő NULL-lal, sem SQLite-on, sem
  PostgreSQL-en), tehát a Kör 6 előtti, még handle nélküli profilok nem
  ütköznek egymással.
- **Miért `community_profiles`-on, nem külön táblán:** a brief tilos zónája
  kifejezetten "a handle-oszlop hozzáadásán kívül" fogalmaz — ez a handle
  MAGA a `profile.py`-on élő oszlop(ok), nem egy 1:1 kapcsolt tábla. A külön
  `handle_history` tábla (§4) más dolog: a MÚLTBELI, felszabadított handle-ök
  auditja, nem az aktuális.

### 2. Normalizálás: NFKC + Unicode casefold, `handle_policy.py`

```python
import unicodedata

def normalize_handle(raw: str) -> str:
    """Canonical uniqueness key: NFKC compatibility-fold, then Unicode
    casefold (stronger than .lower() — handles ß, İ, full-width forms).
    This is what the A1 Unicode-collision property test exercises directly."""
    return unicodedata.normalize("NFKC", raw).casefold()
```

Validáció (`validate_handle_format`, `ValueError`/Pydantic
`ValidationError`-t dob):

- Hossz a NORMALIZÁLT alakon mérve, `[3, 24]` zárt intervallum (§6.1
  küszöb-hármas — `"ab"` elutasít, `"abc"` és a 24 karakteres elfogad,
  `"a"*25` elutasít).
- Minden karakter a normalizált alakban Unicode alfanumerikus
  (`ch.isalnum()`) vagy `_`; whitespace, control karakter, vagy üres
  normalizált eredmény → elutasítás.
- A validáció a NORMALIZÁLT string hosszán/karakterein fut, NEM a nyers
  inputén — egy hosszú, de NFKC-vel rövidebbre eső Unicode input (pl.
  ligatúrák) ne kerülje meg a felső határt, és fordítva.

**NEM elfogadható gyengítés:** a normalizálás csak a Pydantic-validátorban
fut, az adatbázis-oszlop pedig a nyers `handle_display`-re indexel — ez
pontosan a §6.1 valódi-sértés próba tárgya (A1-et pirosra váltja).

### 3. Reserved/blocked katalógus — Python-konstans, nem tábla

```python
RESERVED_HANDLES: frozenset[str] = frozenset({
    "admin", "administrator", "root", "system", "support", "help",
    "api", "www", "null", "undefined", "moderator", "mod", "staff",
    "official", "strumsight", "security", "billing", "legal", "about",
    "settings", "me", "profile",
})
```

Az ellenőrzés a NORMALIZÁLT handle-t hasonlítja a katalógus elemeihez (a
katalógus elemei már eleve normalizált-alakúak, tehát nincs futásidejű
NFKC/casefold rájuk). Bővíthető kód-módosítással (Python `frozenset`, nem DB
tábla) — ez SZÁNDÉKOS: nincs admin-UI vagy migráció-igény egy szó
hozzáadásához, és a `RESERVED_HANDLES` egy elnevezett, egy helyen
importálható konstans, amit a teszt (A4) közvetlenül importál, nem
duplikálja.

### 4. `handle_history.py` — a FELSZABADÍTOTT handle audit-táblája

```python
class CommunityHandleHistory(Base):
    __tablename__ = "community_handle_history"

    id: Mapped[int] = mapped_column(_bigint, primary_key=True)
    profile_id: Mapped[int] = mapped_column(
        _bigint, ForeignKey("community_profiles.id", ondelete="CASCADE"), nullable=False, index=True,
    )
    old_handle_display: Mapped[str] = mapped_column(String(24), nullable=False)
    old_handle_normalized: Mapped[str] = mapped_column(String(24), nullable=False, index=True)
    released_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    redirect_expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
```

Nincs `unique` a `old_handle_normalized`-en — ugyanaz a handle többször is
felszabadulhat/history-be kerülhet idővel (különböző profilok, különböző
időpontokban), az egyediséget csak az AKTUÁLIS `community_profiles.
handle_normalized` kényszeríti ki (§1).

### 5. `identity_service.py` — injektálható UUID-generátor + handle-orchestráció

```python
UuidFactory = Callable[[], uuid.UUID]
DEFAULT_UUID_FACTORY: UuidFactory = uuid.uuid4

class IdentityService:
    def __init__(self, uuid_factory: UuidFactory = DEFAULT_UUID_FACTORY) -> None:
        self._uuid_factory = uuid_factory

    def new_public_id(self) -> uuid.UUID:
        """The single, testable definition of 'how Community mints a new
        public identifier' — production always uses uuid4 (cryptographically
        unpredictable, never sequential). Tests inject a deterministic
        factory to assert call-count/uniqueness without depending on
        SQLAlchemy column-default internals."""
        return self._uuid_factory()
```

**Hatókör ebben a körben:** ez a komponens ÚJ és önállóan tesztelt (A2), de
— az R02-ben már élő `community_profiles.public_id` SQLAlchemy
`default=uuid.uuid4` oszlop-defaultját ez a kör NEM cseréli le
`IdentityService`-hívásra (a `profile.py` tilos zónája csak a handle-oszlop
hozzáadását engedi, a `public_id` mechanizmusa nem ennek a körnek a dolga).
`IdentityService.new_public_id()` MA hívó nélküli, tesztelt komponens — a
mintát az ADR 0396 §4 (`community_readiness_failure`, "MA nincs élő hívója")
precedens indokolja: a jövőbeli Community-felületek (pl. egy jövőbeli
csoport/klub publikus ID-je) ezt hívják majd, nem szórt `uuid.uuid4()`
hívásokat. A2 tesztje közvetlenül az `IdentityService`-t hívja (két
egymást követő `new_public_id()` NEM sorozatos, NEM `id`-ből származtatott).

`IdentityService` a handle-változtatás orchestrátora is:

```python
HANDLE_CHANGE_COOLDOWN = timedelta(days=14)
HANDLE_REDIRECT_WINDOW = timedelta(days=7)

class HandleCooldownError(Exception): ...
class HandleTakenError(Exception): ...
class HandleReservedError(Exception): ...

def change_handle(
    self, db: Session, profile: CommunityProfile, raw_handle: str, *, now: datetime,
) -> CommunityProfile:
    normalized = handle_policy.normalize_handle(raw_handle)
    handle_policy.validate_handle_format(normalized)
    if normalized in handle_policy.RESERVED_HANDLES:
        raise HandleReservedError(normalized)
    if profile.handle_changed_at is not None and now - profile.handle_changed_at < HANDLE_CHANGE_COOLDOWN:
        raise HandleCooldownError(profile.handle_changed_at + HANDLE_CHANGE_COOLDOWN)
    if profile.handle_normalized is not None:
        db.add(CommunityHandleHistory(
            profile_id=profile.id,
            old_handle_display=profile.handle_display,
            old_handle_normalized=profile.handle_normalized,
            released_at=now,
            redirect_expires_at=now + HANDLE_REDIRECT_WINDOW,
        ))
    profile.handle_display = raw_handle
    profile.handle_normalized = normalized
    profile.handle_changed_at = now
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HandleTakenError(normalized) from None
    return profile
```

Az `IntegrityError`-re épülő `try/except commit` — NEM egy előzetes
"nézd meg, foglalt-e" SELECT — ez az A5 (concurrent-claim) megbízható
védelme: a DB unique index dönt, az alkalmazás csak a kivételt fordítja
409-re (§5.1, a brief kifejezett tiltása az app-szintű race-hajlamos
mintára).

### 6. `handles.py` router — availability + resolve, mindkettő rate-limitelt

```python
handle_availability_limiter = RateLimiter(max_attempts=30, window_seconds=60)

@router.get("/handles/{handle}/availability")
def check_availability(handle: str, request: Request, db: Session = Depends(_session_factory)) -> dict:
    _throttle(handle_availability_limiter, request)  # 429 ha kimerült
    normalized = handle_policy.normalize_handle(handle)
    if not handle_policy.is_valid_format(normalized):
        return {"available": False}
    if normalized in handle_policy.RESERVED_HANDLES:
        return {"available": False}
    taken = db.query(CommunityProfile).filter_by(handle_normalized=normalized).one_or_none()
    return {"available": taken is None}

@router.get("/handles/{handle}/resolve")
def resolve_handle(handle: str, db: Session = Depends(_session_factory)) -> dict:
    normalized = handle_policy.normalize_handle(handle)
    profile = db.query(CommunityProfile).filter_by(handle_normalized=normalized).one_or_none()
    if profile is not None:
        return {"public_id": str(profile.public_id), "redirected": False}
    now = datetime.now(timezone.utc)
    history = (
        db.query(CommunityHandleHistory)
        .filter_by(old_handle_normalized=normalized)
        .filter(CommunityHandleHistory.redirect_expires_at > now)
        .order_by(CommunityHandleHistory.released_at.desc())
        .first()
    )
    if history is not None:
        current = db.get(CommunityProfile, history.profile_id)
        if current is not None:
            return {"public_id": str(current.public_id), "redirected": True}
    raise HTTPException(status_code=404, detail="handle not found")
```

- **Csak EGY handle hívásonként** (path param) — nincs batch/lista body.
  Ez az A3 explicit tiltása egy "kényelmi" enumerációs csatornára.
- Az `availability` válasz KIZÁRÓLAG `{"available": bool}` — nem különbözteti
  meg "foglalt" vs. "reserved" vs. "érvénytelen formátum" okot, hogy egy
  támadó ne tudja a reserved-listát vagy a formátum-szabályokat az
  availability endpointon át feltérképezni finomabban, mint amit a §2/§3
  önmagában amúgy is nyilvános (a validációs szabály maga nem titok, csak a
  KONKRÉT elutasítás oka per-hívás ne szivárogjon differenciáltan).
- `resolve` a redirect-mechanizmus (A6) konkrét, tesztelhető felülete —
  `routers/profile.py` (nincs az `allowed_paths`-on) érintése nélkül.

### 7. E-mail-eredetű handle regresszió (A7)

`handle_policy.py` és `identity_service.py` egyik függvénye sem fogad el
`email` paramétert, és egyik sem importálja/olvassa `User.email`-t. A
regressziós teszt strukturálisan ellenőrzi (nem csak viselkedésileg): pl. a
két modul forráskódjában nincs `email` token, ÉS egy explicit teszteset
bizonyítja, hogy `change_handle` aláírása kizárólag `raw_handle: str`-t
fogad (nincs opcionális e-mail-alapú fallback ág).

**NEM elfogadható gyengítés:** egy "ha a user nem ad handle-t, generáljunk
egyet az e-mail helyi részéből" kényelmi ág — ezt a §3 kifejezetten tiltja.

## Elutasított alternatívák

- **Alkalmazás-szintű "SELECT majd INSERT" egyediség-ellenőrzés
  tranzakcióban, DB unique constraint nélkül.** Elvetve: pontosan az a
  race-hajlamos minta, amit a projekt már megmért (`tools/round-slots.py`
  `O_CREAT|O_EXCL` ADR-foglalás precedense) — a `try/except IntegrityError`
  minta az egyetlen megbízható védelem konkurens kérésekre (A5).
- **Batch-availability endpoint** (N handle egy hívásban). Elvetve: a brief
  §5.3 kifejezetten tiltja — enumerációs csatornává válna a rate limitet
  megkerülve (A3).
- **`profile.py` `public_id` oszlop-defaultjának lecserélése
  `IdentityService`-hívásra ebben a körben.** Elvetve: a `profile.py` tilos
  zónája csak a handle-oszlop hozzáadását engedi; a `public_id` mechanizmus
  módosítása egy MEGLÉVŐ, R02-ben már elfogadott döntés (ADR 0396 §1)
  visszamenőleges bővítése lenne, ami H1-közeli kockázat egy önjavító
  eszkalációban — a `IdentityService` inkább a JÖVŐBELI publikus
  azonosítók egységes forrása.
- **Külön `community_handles` 1:1 tábla a `community_profiles`-tól,
  handle-oszlopok helyett.** Elvetve: a brief tilos zónájának szó szerinti
  olvasata ("a handle-oszlop hozzáadásán kívül") a `profile.py`-on élő
  oszlop(oka)t ír elő, nem egy új 1:1 táblát; az egyediség és a cooldown is
  egyszerűbb egyetlen táblán, join nélkül.
- **A reserved-lista adatbázis-tábla, admin API-val.** Elvetve: a §3 scope
  "konfigurálható katalógus"-t kér, nem admin-CRUD-ot; a Python `frozenset`
  verziózott, code-review-zott, és a jövőbeli admin-felület (ha kell) egy
  külön kör dolga.

## Következmények

- A `handle_history` tábla és a `resolve` endpoint révén A6 (cooldown +
  rövid redirect) a `handles.py`-on belül, `routers/profile.py` érintése
  nélkül mérhető — egy jövőbeli kör dolga a `resolve`/redirect tényleges
  bekötése a publikus profil-megjelenítő útvonalba.
- `IdentityService.new_public_id()` MA hívó nélküli, tesztelt komponens
  (az ADR 0396 §4 precedensét követve) — a `profile.py` `public_id`
  mechanizmusának egységesítése egy jövőbeli, dedikált kör dolga, ha
  egyáltalán szükségessé válik.
- A `HANDLE_CHANGE_COOLDOWN` (14 nap) és `HANDLE_REDIRECT_WINDOW` (7 nap)
  konstansok ennek az ADR-nek a döntései — egy jövőbeli kör módosíthatja
  ADR-frissítéssel, ha a terméktulajdonos más értéket kér.

## A visszavonás feltétele

Felülvizsgálandó, ha egy jövőbeli kör mérten azt találja, hogy a
`resolve`/redirect logikának a `handles.py`-on belüli elhelyezése
gyakorlati problémát okoz (pl. duplikált lookup-logika a `routers/
profile.py` tényleges bekötésekor) — ekkor a konszolidáció egy dedikált,
jövőbeli kör `allowed_paths`-ára tartozik, nem ennek a körnek a
visszamenőleges bővítése.
