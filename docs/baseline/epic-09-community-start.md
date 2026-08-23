# Epic 9 — Community mért kiindulópont

- **Kör:** E09-R01 (Chapter 10, Kör 1)
- **Dátum:** 2026-08-22
- **Mért alap-commit:** jelen kör kiindulópontja `main @ db6293f4` (a
  brief-ben hivatkozott, a mérések `E08-R30` merge `a8ecb9f3` utániak)
- **Szerződés:** ADR 0395 (a Claude írja a §5 döntésekből)
- **Fenvegetés-nyilvántartó:** [`docs/security/community-threat-model.md`](../security/community-threat-model.md)
  (8 kötelező kategória)

> Ez a dokumentum NEM normatív — a Community adat-modell és a flag-
> készlet elsőbbségi forrása továbbra is a 0395 ADR és a threat model.
> A baseline kizárólag a Community Kör 2+ számára MÉRT, TÉNYLEGES
> induló állapot: meglévő feature-fák, feature-barrel határok, és az
> eddig elkészült backend route-ok listája — hogy a későbbi körök ne
> találgassanak, és a `lib/features/community/` csak a legkisebb
> szükséges felületet hozza létre.

> A mért számok `find … | wc -l` alapján vannak, és a §10
> `git show HEAD:lib/...` sort írják le. A kód és a táblázat eltérése
> esetén a kód a mérvadó.

## 0. Státusz a Kör 1-ben

- `lib/features/community/` **nem létezik** — ez az Epic 9 első köre
  és kizárólag a feature-flag családot, a threat modelt és ezt a
  baseline-t hozza létre. A tényleges feature-fa a Kör 2+ dolga.
- `lib/features/share/` már él — a Kör 10 share-artifact és a
  wrapped / strum card widgetek készen állnak (lásd §1.3).
- `lib/features/gamification/` a Epic 8 30 körében jött létre —
  a community-data-modell kiindulópontja (lásd §1.5).
- A backend `community_postgres_ready` readiness-placeholder
  (E09-R01 A5) jelenleg `False` — az SQLite dev-default miatt.

## 1. Érintett feature-fák és függőségi térkép

### 1.1 A mért induló állapot (file-számok)

A `find … -type f -name '*.dart' -not -path '*test*'` és a
`find test/features/<feature> -type f -name '*.dart'` kimenete:

| Feature | Forrás-fák | Teszt-fák |
|---|---|---|
| `lib/features/auth/` | 7 | 7 |
| `lib/features/share/` | 9 | 7 |
| `lib/features/progress/` | 8 | 5 |
| `lib/features/streak/` | 8 | 5 |
| `lib/features/learn/` | 24 | 34 |
| `lib/features/gamification/` | **73** (Epic 8 teljes feature) | (a teszt-fa külön mérése: 44) |
| `lib/features/community/` | **0** — ez a kör nem hozza létre | **0** — Kör 2+ |

A Community adat-modellje a Kör 2-ben jön létre, és kizárólag az
alábbi meglévő feature-ekre támaszkodik a barrel-public.dartikon át:

- `lib/features/share/public.dart` — a share-card widgetek és a
  `ShareService` (offline-first, audit-elhető artifact-pipeline).
- `lib/features/progress/public.dart` — a `PracticeEntry` és a
  `PracticeStats` típusok (a community posztokban hivatkozott
  evidence-elemek).
- `lib/features/gamification/public.dart` — a `RewardInboxItem`,
  `QuestProgress`, `AchievementProgress` típusok (a Kör 10+ feed
  funkciók kiindulópontja).
- `lib/features/auth/public.dart` — a jelenlegi account-layer
  publikus felülete.

### 1.2 Backend modulok (mért)

A `find backend/app -maxdepth 2 -type d` kimenete:

| Backend modul | Fájlok | Környezet |
|---|---|---|
| `backend/app/routers/auth.py` (67 sor, self-contained) | JWT + bcrypt + rate-limit | E01-R12 |
| `backend/app/routers/diagnostics.py` | lab diagnostics endpoint | E01-R13 |
| `backend/app/routers/settings.py` | user settings sync | E01-R12 |
| `backend/app/gamification/{schemas,service}.py` | ledger és receipt (E08-R28) | E08-R28 |
| `backend/app/tutor/*.py` (9 .py) | AI Tutor proxy (provider gateway + safety + redaction + stream) | E04 |
| `backend/app/` — új `community/` modul | **NEM LÉTEZIK** — Kör 2 dolga | E09-R02 |

A Community backend-modul a Kör 2-ben jön létre, és a meglévő
route-okkal azonos szinten csatlakozik (FastAPI router, app
factory-n át).

### 1.3 Share artifact-ok (a Kör 10 alapja, már most kész)

A `lib/features/share/widgets/` jelenleg két widget-et hordoz:

- `strum_card.dart` — heti strumming recap kártya
- `wrapped_card.dart` — hosszabb időszakot átfogó kártya

A `ShareService` (a `share_service.dart`-ban) a `share_plus` csomagra
épül, és az ADR 0247 szerinti öntörlő tempfile-szerződést használja.
A Kör 10 share-artifact a Community posztokhoz a meglévő widget-eket
és service-t fogja használni — a Community surface area ehhez a
kész infrastruktúrához csatlakozik.

### 1.4 Account layer (a Community bejelentkezés alapja)

Az `accountEnabled` feature-flag-gel védett account layer a
`lib/features/auth/` és a `backend/app/routers/auth.py` párosán
nyugszik. A Community körének alap-feltétele, hogy ez a layer
production-ready legyen, de a Community flag-ek production defaultja
`False` addig is, amíg az account layer audit-ját a Kör 2+ el nem
végzi. A meglévő `AuthenticationService`, `UserRepository` és a
`/auth/register` / `/auth/login` endpointok a Kör 4-től használhatók.

### 1.5 Gamification ledger (a Community reward-ok alapja)

A Epic 8 során jött létre a `lib/features/gamification/` feature,
és a `backend/app/gamification/{schemas,service}.py` modul a
szerver-oldali összesítést végzi. A Community Kör 18+ a reward-okat
ezen a ledger-en keresztül fogja olvasni — a
`docs/sdd/epic-08-completion-report.md` §3.2-ben rögzített
számszerű feltételek betartásával.

## 2. Feature-barrel határok (cross-feature import-szerződés)

Az AGENTS.md §6 kimondja: feature-ek kizárólag a `public.dart`
barrel-en vagy közös core modulkon át érintkezhetnek. A Community
feature-fa a Kör 2-ben a fenti barrel-eken át csatlakozik:

| Community import | Forrás (barrel) | Megjegyzés |
|---|---|---|
| User azonosító + auth state | `lib/features/auth/public.dart` | `accountEnabled` flag-gel védett |
| Share-artifact (Kör 10+) | `lib/features/share/public.dart` | `ShareService`, `ShareContent` |
| Practice-entry evidencia | `lib/features/progress/public.dart` | `PracticeEntry`, `PracticeStats` |
| Reward-inbox (Kör 18+) | `lib/features/gamification/public.dart` | `RewardInboxItem`, `QuestProgress` |
| API hívások | `lib/core/api/api_config.dart` | `dio` instance, JWT bearer header |

A Kör 2+ tilos importálni:

- `lib/features/<other>/internal/**` — kizárólag a public.dart-n
  át;
- `backend/app/tutor/**` — külön threat model és safety-layer;
- `lib/features/share/widgets/strum_card.dart` közvetlenül — csak a
  `lib/features/share/public.dart` barrel-en át.

## 3. Production kill switch hatálya és viselkedése

A Community flag család a meglévő `accountEnabled` (router-szintű
kapu) és `tutorEnabled` (backend-szintű kapu) mintáját követi,
azzal a különbséggel, hogy a Community **NEM env-aware** — a
`diagnostics_enabled` / `apk_download_enabled` mintától eltérően,
amelyek dev-ben `True` és production-ben `False` alapértelmezetté
válnak a `_default_lab_flags_for_environment` validator alatt.

A Community minden flag-jének production defaultja `False`, és ez
a default **soha** nem változik a build-environment alapján. A
production élesítés kizárólag:

- Flutter: `flutter build apk --dart-define=STRUMSIGHT_COMMUNITY=true`
  (és esetleg az alábbi 4 alkapcsoló),
- Backend: `STRUMSIGHT_COMMUNITY_ENABLED=true` env-var (és a 4
  alkapcsoló).

A két oldal kapcsolójának egyszerre kell állnia — félig kikapcsolt
állapot a feature-flag családon belül a `communityWritesEnabled` /
`communityMediaEnabled` / stb. alkapcsolók szándékos, independent
viselkedése, nem kódbeli hiba.

## 4. A kill switch és a §6 acceptance kölcsönhatása

A `lib/app/config/feature_flags.dart` 31 + 5 = 36 flaget hordoz a
Kör 1 végén. A Community öt flag a factory-ban (`forEnvironment`)
közvetlenül `bool.fromEnvironment`-nel olvassa a dart-defines-t,
`defaultValue` nélkül — így a flag hiánya = `False`, MINDEN
környezetben. Ez az alapértelmezett viselkedés a §6 A1 / A2
cellákat védi.

A `backend/app/config.py` a `_default_lab_flags_for_environment`
validator alá NEM teszi a Community flag-eket — a Community NEM
env-aware, mert a dev-safe default itt a `False`, nem a `True`.
Ez a §6 A1 / A5 cellákat védi a backend oldalon.

A `community_postgres_ready` property csak-olvasható readiness-
placeholder, amely `False`, ha a `database_url` `sqlite:///...`,
és `True`, ha `postgresql+psycopg://...` (vagy hasonló PG-flavor).
A teljes readiness-ellenőrzés a Kör 2 dolga (DB-szintű kapcsolat-
ellenőrzés + szerep-konfiguráció), de ez a narrow placeholder már
a Kör 1-ben jelzi a deployment-oldali döntést.

## 5. Meglévő teszt-guardok, amiket a Community NEM törhet el

A `tools/round-gate.sh test/...` mérce a meglévő teszt-útvonalak
mindegyikét zöldben tartja. A Community flag-ek és a threat model
dokumentum NEM érint(het)i:

- `test/app/config/feature_flags_test.dart` — a meglévő flag-ek
  értékszemantikáját és factory-viselkedését védi (a Kör 1
  kiterjesztette az új Community csoporttal).
- `test/app/config/app_config_test.dart` — a configuration-
  resolution logikát védi (a Community NEM hív `usesNetwork`-
  bővítést, mert a flag-ek értelmezése kizárólag a feature-en
  belül történik).
- `test/features/gamification/...` — a Kör 8 Epic 8 lezáró
  jelentésben foglalt dual-write soak feltételeit védi.
- `backend/tests/test_auth.py`, `test_diagnostics.py`,
  `test_migrations.py`, `test_settings.py`,
  `test_gamification_ledger.py`, `test_hardening.py`,
  `test_tutor/` — a backend oldali meglévő mérce.

## 6. A Kör 2-től elvárt munka (referencia)

Ez a Kör 1 kizárólag a feature-flag családot, a threat modelt és
ezt a baseline-t hozza létre. A Kör 2-től a későbbi körök
elvárt munkája:

1. **Kör 2:** `backend/app/community/{models,schemas,service}.py`
   és `backend/app/routers/community.py` (posts, comments,
   follows). A `community_postgres_ready` property True-ra vált,
   amennyiben a deployment PG-re váltott.
2. **Kör 3:** A `lib/features/community/domain/` (post, comment,
   follow entity-k).
3. **Kör 4:** A `lib/features/community/data/` (a repository-
   provider minta).
4. **Kör 5:** A `lib/features/community/application/` (provider-ek).
5. **Kör 6-10:** A felszíni UI-k (compose, feed, share-artifact).
6. **Kör 11-20:** A klub / leaderboard / challenge / moderation
   sub-feature-ek.

A pontos Kör-2 brief a Chapter 10 queue-ban a main-be merge-elt
E09-R01 alapján íródik; ez a baseline csak az induló mért
állapotot rögzíti.

## 7. Kapcsolódó dokumentumok

- `docs/rounds/e09-r01-community-baseline-and-feature-flags.md` —
  a Kör 1 briefje (a fenti lista a §2 + §5-ből származik).
- `docs/security/community-threat-model.md` — a 8 kategória, a
  védelmi intézkedések és a feature-flag-kapuk.
- ADR 0395 — a Community flag-család definíciója.
- ADR 0220 — Epic 6 audio-analysis-v2 kill switch (precedens).
- ADR 0247 — self-deleting share tempfile (Kör 10 alap).
- `docs/sdd/epic-08-completion-report.md` — megelőző epic záró
  jelentése, a Community adat-modell kiindulópontja.

---

> **A baseline frissítése:** amint a Kör 2+ új feature-fát hoz
> létre, ez a dokumentum kiegészül az `lib/features/community/`
> sorral és a `backend/app/community/` sorral. A meglévő sorok a
> mérőszámokkal együtt NEM változnak — csak bővülnek.
