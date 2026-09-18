# Environment mátrix — StrumSight

**Kör:** `E12-R04` (Environment és channel konfiguráció lezárása).
**Normatív forrás:** [ADR 0445](../adr/0445-environment-value-set-and-staging-isolation.md).
Minden állítás alakja `<állítás> — <fájl>:<sor>` vagy a hivatkozott teszt
neve; a gépi kényszer és az operatív (nem gépileg ellenőrzött) szabály
külön van jelölve.

## 1. A négy környezet

| | **Development** | **Lab** | **Staging** | **Production** |
|---|---|---|---|---|
| **Hol él** | kliens (build) | kliens (build) | **kizárólag backend** (deployment-cél, nincs saját kliens flavor — ADR 0445 D3) | kliens (build) + backend |
| **Kliens `AppEnvironment`** | `development` — `lib/app/config/app_environment.dart:30-33` | `lab` — `app_environment.dart:35-37` | *nincs* (a staginget egy `development`/`lab` build éri el más `STRUMSIGHT_API_URL`-lel — `app_environment.dart:14-18`) | `production` — `app_environment.dart:39-40` |
| **Backend `STRUMSIGHT_ENV`** | `dev` | `lab` | `staging` | `prod` |
| **Elfogadott aliasok** | `development` (üres/hiányzó is `dev`-re normalizál) — `backend/app/config.py:21,124-134` | *(nincs alias)* | *(nincs alias)* | `production` — `backend/app/config.py:21,127` |
| **Ismeretlen érték** | — | — | — | minden környezetben: `ValidationError` a `Settings(...)` példányosításkor, NEM csendes `dev` — `backend/app/config.py:128-133`, bizonyítja: `backend/tests/test_settings.py::TestEnvironmentValueSet::test_unknown_value_refuses_to_instantiate` |
| **Titok (secret_key)** | repóbeli dev-alapértelmezés megengedett — `backend/app/config.py:42` | ua., mint dev | **tiltott a repóbeli dev-alapértelmezés**, példányosítás-idejű `ValidationError` — `backend/app/config.py:151-155`, bizonyítja: `test_settings.py::TestStagingIsolation::test_dev_secret_key_refuses_to_instantiate` | **tiltott**, boot-idejű `RuntimeError` a `create_app()`-ban (`main.py:36-45`, kör tilos zónája — nem módosult), bizonyítja: `backend/tests/test_hardening.py::TestProdBootGuards::test_prod_with_dev_secret_refuses_to_boot` |
| **Diagnosztikai token (`diag_token`)** | repóbeli dev-alapértelmezés megengedett | ua. | bekapcsolt diagnosztika mellett **tiltott a dev-alapértelmezés / üres érték**, példányosítás-idejű `ValidationError` — `backend/app/config.py:161-167` | ua., de boot-idejű `RuntimeError` — `main.py:51-57` |
| **CORS** | `*` megengedett — `backend/app/config.py:57` | ua. | **`*` tiltott**, példányosítás-idejű `ValidationError` — `backend/app/config.py:156-160` | **`*` tiltott**, boot-idejű `RuntimeError` — `main.py:46-50` |
| **Adatbázis** | SQLite alapértelmezett, engedély nélkül — `backend/app/config.py:48` | ua. | SQLite csak explicit `STRUMSIGHT_ALLOW_SQLITE=true` mellett, példányosítás-idejű `ValidationError` egyébként — `backend/app/config.py:168-172` | ua., de boot-idejű `RuntimeError` — `main.py:58-62` |
| **Kliens endpoint-tiltás** | nincs | nincs | *(a staging maga a tiltott endpoint-jelölés — lásd alább)* | HTTP, loopback (`localhost`/`127.0.0.1`/`10.0.2.2`) ÉS `staging` részláncot tartalmazó host **feltétlenül** tiltott — `lib/app/config/app_config.dart:139-159`, bizonyítja: `test/app/app_config_test.dart` „rejects a staging-labelled host unconditionally” + „rejects loopback/development hosts” |
| **Lab-flagek alapértelmezése** (`diagnostics_enabled`, `apk_download_enabled`) | `True` (bekapcsolva) — `backend/app/config.py:137-139` | `True` | **`False`** (a productionnel azonosan kikapcsolt) — `backend/app/config.py:137`, bizonyítja: `test_settings.py::TestStagingIsolation::test_real_secrets_instantiate_cleanly_with_lab_flags_off_by_default` | `False` — ua. sor, bizonyítja: `backend/tests/test_hardening.py::TestProdBootGuards::test_lab_routes_default_on_in_dev_and_off_in_prod` |
| **Production titok-őr helye** | n/a | n/a | *(saját, alább)* | `main.py::_guard_prod`, a `create_app()` hívja, **boot-idejű** hiba (nem `Settings` példányosítás-idejű) — `main.py:36-69,103-105` |
| **Staging titok-őr helye** | n/a | n/a | `Settings._guard_staging` (`mode="after"` validator), **példányosítás-idejű** hiba — `backend/app/config.py:142-173` | n/a |
| **Tutor provider-kulcs (`tutor_api_key`)** | repóbeli dev-alapértelmezés megengedett | ua. | **NEM ellenőrzött** — a staging-őr (4 ellenőrzés, ADR 0445 D4 taxatív listája) szándékosan nem fedi a `tutor_api_key`-t; egy `tutor_enabled=true` staging deploy a repóbeli `dev-tutor-key` értékkel is elindul. Az egységesítés az **E12-R07** kör hatásköre (review B3, E12-R04) | ellenőrzött — bekapcsolt `tutor_enabled` mellett a dev/üres `tutor_api_key` boot-idejű `RuntimeError` — `main.py:63-69` |

## 1/b. Kliens build-oldali alapértelmezések (WP-G, 2026-09-06)

A teszter-APK-t a **védett** `.github/workflows/build-apk.yml` állítja elő, és
az EGYETLEN define-t ad át: `--dart-define=STRUMSIGHT_ENV=development`. A
korábbi Lab APK (`lab_build.json`, `lab-apk.yml`) — amely a teljes define-listát
hordozta — kivezetve; a `lab_build.json` a repóban marad, de már csak a
korábbi lab-build dokumentációja. Ezért a fejlesztői build teszt-konfigurációja
**kódban** él: `FeatureFlags.forShippedBuild` + `AppConfig.apiBaseUrlFor`,
amelyeket a `AppBootstrap.run` hív.

A „define" oszlop-érték azt jelenti: pontosan az, amit a build átadott;
define hiányában `false` (URL esetén `http://10.0.2.2:8000`). **Egy
explicit define MINDEN környezetben nyer** — a fejlesztői alapértelmezés
kizárólag a define HIÁNYÁRA vonatkozik, és ezt a különbséget a kód
`bool.hasEnvironment`-tel méri (a `bool.fromEnvironment` a hiányzó define-t és
az explicit `false`-t azonosan olvassa).

| Feloldott érték | **Development** | **Lab** | **Production** |
|---|---|---|---|
| `apiBaseUrl` (`STRUMSIGHT_API_URL`) | **`https://casaba.app/strumsight`** (élő backend) — `lib/app/config/app_config.dart` `liveApiBaseUrl` / `apiBaseUrlFor` | `http://10.0.2.2:8000` (változatlan) | define; nélküle `http://10.0.2.2:8000`, amit a fail-closed validáció HTTP + loopback címen elutasít (változatlan) |
| `accountEnabled` (`STRUMSIGHT_ACCOUNT`) | **`true`** | define | define |
| `previewAll` overlay (`STRUMSIGHT_PREVIEW_ALL`) | **`true`** → AI Tutor (lokális), Planner Assist, 10 Vision, 9 Analysis V2 (`audioAnalysisV2Enabled` is), recognition recovery, új Live stage | define | **soha nem alkalmazódik** (`forEnvironment` production-ág, változatlan) |
| `communityEnabled` / `…Writes` / `…Leaderboard` / `…Clubs` | **`true`** | define | define (ADR 0395 kill switch, változatlan) |
| `communityMediaEnabled` | define (**`false`**) — nyitott R-SEC-01 / R-PRIV-01 | define | define |
| `aiTutorCloudEnabled`, `visionLabCaptureEnabled`, `recognitionShadowModeEnabled` | `false` (a preview overlay szándékosan nem nyitja) | ua. | `false` |
| `diagnosticsToken` | dev-alapértelmezés (a diagnosztikai alagút kivezetve) | ua. | fail-closed (változatlan) |

**Emulátoros fejlesztő:** a loopback címet explicit define-nal kell kérni —
`flutter run --dart-define=STRUMSIGHT_API_URL=http://10.0.2.2:8000`.

**Kill switch a fejlesztői buildben:** a „hagyd el a define-t" mondat ott már
nem érvényes; egy felület kikapcsolása explicit `=false` define
(pl. `--dart-define=STRUMSIGHT_COMMUNITY=false`). Lab és production
változatlan. Bizonyítja: `test/app/config/feature_flags_test.dart`
„WP-G — FeatureFlags.forShippedBuild" csoport (development teljes
teszt-konfiguráció · lab és production bájtazonos a WP-G előtti feloldással ·
explicit define nyer), `test/app/app_config_test.dart` „WP-G —
apiBaseUrlFor", `test/app/app_bootstrap_test.dart` „WP-G — the shipped
development build".

## 2. A staging és a production őr tudatos aszimmetriája

A production titok-tiltás a `create_app()` hívásakor (boot-idejű), a staging
titok-tiltás a `Settings(...)` konstruktorban (példányosítás-idejű) fut le —
ez NEM hiba, hanem az ADR 0445 D4 tudatos döntése: a production őr a kör
tilos zónájában (`backend/app/main.py`) él, és onnan a ~20 meglévő,
`Settings(env="prod", …)`-ot boot-hiba-várakozással példányosító teszt miatt
nem mozdítható e kör scope-jában. Az egységesítés (a `_guard_prod` áthozása a
`Settings`-be) az **E12-R07** kör dolga.

A két őr **lefedettségben** is eltér, nem csak időzítésben: a staging-őr négy
ellenőrzést végez (ADR 0445 D4 taxatív listája — secret_key, CORS, diag_token,
SQLite), a production-őr öt ellenőrzést (ugyanaz a négy + a tutor
provider-kulcs — lásd az 1. táblázat „Tutor provider-kulcs" sorát). Ez NEM
hiányosság a staging-őrben — a kódnak az ADR-listát kell követnie, nem
bővítenie —, csak azt jelenti, hogy a staging-őr NEM olvasható a
production-őr szigorúbb vagy azonos szintű megfelelőjeként. Az egyesítés
(vagy a tutor-kulcs staging-re bővítése) az **E12-R07** kör dolga.

## 3. Operatív szabály — NEM gépi kényszer

A staging és a production **titkainak és adatbázisának különböznie kell**
egymástól (pl. a staging `secret_key`-je ne legyen azonos a production
`secret_key`-jével). Ezt a backend nem tudja megállapítani egy kapott
titokból — nincs módja eldönteni, hogy egy adott string "a production
titka"-e. Ez deployment-fegyelem kérdése, nem `Settings`-validáció.

## 4. Gyors összefoglaló — melyik build melyik `STRUMSIGHT_ENV`-hez tartozhat

```
flutter build apk --dart-define=STRUMSIGHT_ENV=development
  → a teszter-APK (build-apk.yml): élő backend, fiók BE, preview-all BE,
    Community (média nélkül) BE — lásd az 1/b. szakaszt.

flutter build apk --dart-define=STRUMSIGHT_ENV=development --dart-define=STRUMSIGHT_API_URL=https://staging-backend.example
  → kliens: development build; backend: staging deployment. Elfogadott (staging nem kliens-környezet).

flutter build apk --dart-define=STRUMSIGHT_ENV=production --dart-define=STRUMSIGHT_API_URL=https://staging-backend.example
  → ConfigurationException: "production must not point at a staging-labelled host" (app_config.dart:154-157).

STRUMSIGHT_ENV=staging uvicorn app.main:app
  → Settings(env="staging", secret_key=<dev default>) → ValidationError a folyamat indulásakor,
    MIELŐTT bármilyen kérést kiszolgálna.
```
