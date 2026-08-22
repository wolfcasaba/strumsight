# ADR 0400 — Profil-onboarding service-réteg és Community gate UI

**Státusz:** elfogadva (E09-R06 pre-flight, 2026-08-22)

## Kontextus

**Mért 2026-08-22-én, a pre-flightban (a brief §0.0-ja hordozza a teljes
tényellenőrzést).** Az E09-R06 batch-elt briefje (PR #405) `risk = "high"`-t
állít és azt írja, hogy ez a kör "az ELSŐ, ami ténylegesen HTTP-n keresztül
hívja" a Kör 3 (`ADR 0397`) handle-policy-t és a Kör 4 (`ADR 0398`)
access-policy-t — de az `allowed_paths` és a tilos zóna a `backend/**`-et
TELJES egészében kizárja. A kód tényleges állapota ennek ellentmond:

1. **Nincs backend endpoint, ami `community_profiles` sort létrehozna.**
   `backend/app/community/routers/profile.py` ma csak `GET /community/ping`
   és `GET /community/profiles/{public_id}` (olvasás `public_id`-n) —
   egyik sem ír. `backend/app/community/services/identity_service.py`
   `assign_handle`/`change_handle` egy MEGLÉVŐ `profile_id`-re `UPDATE`-el,
   nem `INSERT`-el. A teljes backend fában (`grep -rn "INSERT INTO
   community_profiles"`) nulla találat — `CommunityProfile(...)` konstruktor
   csak a tesztekben fordul elő, közvetlen ORM-hívással.
2. **Ez NEM hiányzó dokumentáció, hanem egy MÁR MERGE-ELT ADR explicit
   következménye, amit a batch-elt E09-R06 brief nem vitt tovább.**
   `docs/adr/0396-…md` „Következmények": *„A Kör 6 (onboarding, explicit
   profil-létrehozás) a `community_profiles` sor tényleges service-szintű
   létrehozását adja; ez a kör [Kör 2] csak a modellt, a migrációt és a
   modul-boundary olvasó/teszt útját."* — vagyis a Kör 6 (ez a kör) SAJÁT,
   már kijelölt feladata a service-szintű létrehozás, nem egy jövőbeli,
   még kiosztatlan körnek.
3. **A `main.py`-ba / `build_community_router`-be való éles bekötés
   VISZONT külön, ettől független, tudatosan halasztott feladat marad.**
   Ugyanaz az ADR 0396 „Következmények" bekezdés külön mondatban rögzíti:
   *„A `main.py`-ba való éles router-bekötés… egy JÖVŐBELI Epic 9 kör
   dolga."* Az E09-R04 review F1/N2 lelete (`docs/reviews/e09-r04-review.md`)
   ugyanezt a halasztást erősíti meg a `privacy.py` router kapcsán: a
   TOCTOU-rés ma kihasználhatatlan, mert *„a router NINCS bekötve az élő
   appba"*, és a leletet a *„bekötő kör"*-nek címzi — ami tehát egy
   HARMADIK, önálló, még sorra nem került kör (nincs ilyen tétel az Epic 9
   32 körös tervében, `docs/sdd/10-epic-09-community-platform.md`).
4. **A `CommunityProfileRepository` (Kör 5, domain, lezárt szerződés) MA
   NEM tartalmaz `create`/`update` metódust** — csak `fetchMyProfile`,
   `fetchById`, `fetchByHandle`, `searchProfiles`. A Kör 6 brief scope-ja
   (profil létrehozás/szerkesztés) enélkül nem implementálható a
   deklarált domain-interfészen keresztül.
5. **A Flutter domain-entitás (`CommunityProfile`, Kör 5) `bio`,
   `skillInterests`, `badges`, `avatarUrl` mezőket definiál, de a backend
   `community_profiles` táblán EGYIK sem létezik oszlopként** (csak `id`,
   `public_id`, `user_id`, `display_name`, `created_at`,
   `handle_display`, `handle_normalized`, `handle_changed_at`). Egy új
   migráció (ADR 0396/0398 mintája: `alembic/versions/e09_r06_0005_*`)
   ÚJ, önálló architekturális döntés lenne (oszloptípus, hossz-korlát,
   JSON vs. külön tábla a `skillInterests`-hez) — méretében összemérhető
   Kör 2–4 egy-egy önálló ADR-jével, és ez a kör nem az elsődleges célja.

Ez a döntés a fenti öt mért tényre ad választ: **mit told el ez a kör a
backend felé, mit NEM, és miért.**

## Döntés

### 1. A kör backend-scope-ja: KIZÁRÓLAG a Kör 6-nak ADR 0396-ban már
   kiosztott „service-szintű létrehozás" — nincs migráció, nincs
   router-mounting

`backend/**` a brief tilos zónájából **SZŰKEN, névvel** kikerül —
KIZÁRÓLAG az alábbi, ÚJ vagy bővített fájlokra:

```text
backend/app/community/services/profile_service.py   (ÚJ)
backend/app/community/schemas/profile.py             (BŐVÍTÉS)
backend/app/community/routers/profile.py              (BŐVÍTÉS)
backend/tests/community/conftest.py                    (BŐVÍTÉS — auth fixture)
backend/tests/community/test_profile_service.py        (ÚJ)
```

`backend/app/main.py`, `backend/app/community/__init__.py`
(`build_community_router` factory-hívó, `/health/ready` bekötés) és
BÁRMILYEN `alembic/versions/**` fájl **változatlanul tilos zóna marad** —
ezek a §2.3 szerint egy KÜLÖN, még ki nem osztott „router-mounting kör"
feladatai (ADR 0396 „Következmények", E09-R04 review F1/N2), nem ezé a
köré. Az implementer az EXISTING `identity_service.py`/`handle_policy.py`
függvényeket **importálja** (nem módosítja) — ezek a fájlok NEM kerülnek
az `allowed_paths`-ra.

### 2. `create_profile` — egyetlen tranzakció, három lépés, MEGLÉVŐ
   segédfüggvényekre építve

```python
# backend/app/community/services/profile_service.py (vázlat, nem szó szerinti kód)
def create_profile(
    db: Session,
    *,
    user_id: int,
    handle: str,          # raw, validate() normalizálja
    display_name: str,
    visibility: ProfileVisibility,
    audience_default: CommunityAudience,
    now: datetime,
) -> CommunityProfile:
    normalized = validate(handle)  # ValueError -> router 400 (handle_policy, importálva)
    profile = CommunityProfile(user_id=user_id, display_name=display_name.strip())
    db.add(profile)
    db.flush()  # profile.id kell az assign_handle-höz, commit még nem történik
    assign_handle(db, profile.id, handle.strip(), normalized)  # identity_service, importálva
    db.add(CommunityPrivacySettings(
        profile_id=profile.id,
        visibility=visibility.value,
        audience_default=audience_default.value,
        updated_at=now,
    ))
    commit_with_uniqueness_check(db)  # identity_service, importálva
    db.refresh(profile)
    return profile
```

A `user_id` unique constraint (`community_profiles.user_id`, ADR 0396 §1-
ben lefektetve) a **második** védelmi vonal a duplikált profil ellen — a
router réteg ELŐSZÖR egy olvasó `SELECT`-tel ad barátságos 409-et
(`ProfileAlreadyExists`), de a `commit_with_uniqueness_check` catch-ága a
végső, DB-szintű enforcement, ugyanúgy, ahogy az `assign_handle` teszi a
handle-ütközésnél (§6.1 mérce-mátrix "check-then-insert anti-pattern"
tilalma, ADR 0397 §5.1 precedens).

**Hibafordítás a routerben** (mind a meglévő `handles.py` mintáját
követve):

| Service-kivétel | HTTP |
|---|---|
| `ValueError` (`validate()`-ből) | 400 |
| `ProfileAlreadyExists` (router-szintű előzetes SELECT) | 409 `profile_exists` |
| `HandleAlreadyClaimed` (`commit_with_uniqueness_check`-ből) | 409 `handle_taken` |

### 3. `update_profile` — csak `display_name`, a SAJÁT profilra

```python
def update_profile(db: Session, profile: CommunityProfile, display_name: str) -> CommunityProfile:
    profile.display_name = display_name.strip()
    db.add(profile)
    db.commit()
    db.refresh(profile)
    return profile
```

A `visibility`/`audience_default` UTÓLAGOS módosítása a `privacy.py`
router (Kör 4) dolga marad — az a router MA nincs bekötve (§2.3 pont), ez
a kör ezen nem változtat. Az edit-képernyő tehát a display name-et (+
UI-only bio/interest — 4. pont) szerkeszti, a privacy-választást NEM
kínálja fel újra a létrehozás utáni edit flow-ban.

### 4. `bio`/`skillInterests`/`badges`/`avatarUrl`: UI-only ebben a
   körben, NEM kerülnek a create/update payloadba

A `edit_profile_screen.dart` MEGJELENÍTI és a helyi controller-state
ŐRZI ezeket a mezőket (az A3 "hálózati hiba nem veszti el a kitöltött
formadatot" ezekre a mezőkre IS vonatkozik), de a Dio-hívás **nem**
küldi őket — nincs hova írni a szerveren. Egy jövőbeli migráció-hozó kör
adja hozzá az oszlopokat és a payload-mezőket egyszerre (ADR 0398 §1
"enum-as-plain-string" precedensét követve, plain `String`/JSON oszlop,
nem `Enum`). A `CommunityProfile.copyWith` ÉS a Dio-DTO ezt a határt a
`toCreatePayload()`/`toUpdatePayload()` szűk metódusokban tartja, nem a
teljes entitás szerializálásával — így a jövőbeli bővítés egy fájlban
landol.

### 5. `CommunityProfileRepository` bővítése — bővítés indokolt esettel
   (Kör 5 tilos zóna kivétele)

```dart
// lib/features/community/domain/repositories/community_profile_repository.dart
Future<CommunityProfile> createProfile({
  required CommunityHandle handle,
  required String displayName,
  required ProfileVisibility visibility,
  required CommunityAudience audienceDefault,
});

Future<CommunityProfile> updateProfile({
  required String displayName,
});
```

Két új, domain-szintű (Dio-mentes) kivétel ugyanabban a fájlban:
`ProfileAlreadyExistsException`, `HandleTakenException` — a Dio impl
fordítja HTTP 409-ről ide, a controller ezekre ágazik (pl. handle-ütközés
→ inline mezőhiba, ne globális hibatoast).

### 6. `CurrentUser`/`DbSession` (`app.deps`) az ÚJ endpointokon, a
   MEGLÉVŐ endpointok bespoke `_session_factory`-ja érintetlen

A két ÚJ végpont (`POST`/`PUT /community/profiles/me`) a projekt már
bevett, megosztott auth-mintáját használja (`backend/app/routers/
settings.py` precedens: `CurrentUser`, `DbSession` az `app.deps`-ből),
NEM a router saját `request.app.state.session_factory` hídját — ez a két
mechanizmus egyenértékű a teszt-appban is, mert
`backend/tests/community/conftest.py::community_client_enabled` MÁR
felülírja `app.dependency_overrides[get_db]`-t (a `CurrentUser` lánc
ugyanerre a `get_db`-re épül). A MEGLÉVŐ `ping`/`read_profile` végpontok
VÁLTOZATLANOK maradnak — a bevezetés a két ÚJ végpontra szűken korlátozott,
nem egy retrofit az egész fájlon.

## Alternatívák

- **Ez a kör is `backend/**`-et teljesen kizárva marad, a Flutter réteg
  egy dokumentált-de-nemlétező kontraktra épül.** Elvetve: az ADR 0396
  „Következmények" MÁR kiosztotta ezt a felelősséget Kör 6-nak — egy
  ilyen halasztás egy MERGE-ELT ADR tartalmát írná felül hallgatólagosan,
  új, negyedik "onboarding endpoint" kört igényelne, ami az Epic 9 32
  körös tervében NINCS allokálva (kockázat: örökre elmarad).
- **A migráció (bio/skillInterests oszlopok) is ebben a körben.** Elvetve:
  önálló, Kör 2–4 méretű architekturális döntés (oszloptípus,
  hossz-korlát, JSON vs. tábla), amit egy MiniMax UI-kör pre-flightja nem
  tervezhet meg felelősen egy már amúgy is nagy scope mellé; a mezők
  UI-only kezelése (4. pont) a felhasználó felé semmit nem változtat MA
  (a mezők úgyis csak a helyi formban élnek egy backend nélkül is).
- **A `handles.py`/`privacy.py` routerek bekötése is ide kerül, hogy a
  teljes flow éles legyen.** Elvetve: ez pontosan az ADR 0396
  „Következmények" és az E09-R04 review F1/N2 által KIFEJEZETTEN egy
  külön körnek címzett feladat — az F1 TOCTOU-rés ÉS az authz-hiányosság
  EGYSZERRE oldandó meg a bekötéskor (N2), ami messze túlmutat egy
  profil-onboarding UI-kör felelősségén.

## Következmények

Az Epic 9 terv egy eddig sehol nem allokált tétellel bővül: egy jövőbeli
„router-mounting kör" kell, ami (a) bekötia `handles.py`/`privacy.py`
routereket `build_community_router`-be, (b) lezárja az E09-R04 F1 TOCTOU-
rést UPDATE-feltétellel vagy sor-zárolással, (c) authz-ot ad a
`privacy.py` végpontokra, és (d) a `main.py`/`/health/ready` élesítést
végzi. Ezt a `HANDOFF.md` §6 rögzíti záráskor, nyitott, EMBERI döntést
NEM igénylő tartozásként (mint az E09-R04 F1/F2 mintája).

A `bio`/`skillInterests`/`badges`/`avatarUrl` UI-only állapota egy
jövőbeli migráció-hozó kör előfeltétele — az a kör a `toCreatePayload()`/
`toUpdatePayload()` szűk metódusokat bővíti, nem az egész repository
implementációt.

## Hivatkozások

- ADR 0396 (Community backend modulhatár — „Következmények": Kör 6
  service-szintű létrehozás felelőssége)
- ADR 0397 (public identity/handle policy — `identity_service.py`,
  `handle_policy.py` újrafelhasznált függvényei)
- ADR 0398 (profil privacy/audience policy — `ProfileVisibility`,
  `CommunityAudience`, `server_default="followers"` sosem-public elv)
- ADR 0399 (Flutter Community domain — `CommunityProfileRepository`,
  `CommunityProfile`, bővítendő ezen a körön)
- `docs/reviews/e09-r04-review.md` F1/F2/N2 (router-mounting kör
  előfeltételei)
- `docs/sdd/10-epic-09-community-platform.md` Kör 6 szakasz (2495–2541.
  sor)
- `backend/app/routers/settings.py` (`CurrentUser`/`DbSession` minta)
