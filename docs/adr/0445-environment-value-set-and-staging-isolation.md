# ADR 0445 — Zárt environment-értékkészlet, kliens-alias normalizálás és a staging mint backend-környezet

- **Státusz:** Elfogadva (E12-R04 pre-flight, 2026-08-28)
- **Kör:** `E12-R04` — Environment és channel konfiguráció lezárása
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Epic / fejezet:** [Chapter 12 — Release Roadmap, Sprint Planning & Final
  Integration](../sdd/12-release-roadmap-final-integration.md) Kör 4
- **Az ADR-t az orchestrátor (Claude Opus 5) írta a pre-flightban**, a
  [`docs/rounds/e12-r04-environment-and-channel-isolation.md`](../rounds/e12-r04-environment-and-channel-isolation.md)
  brief §5 kötött döntéseinek normatív forrásaként.

## Kontextus — a MÉRT állapot

A pre-flight mérése (`main @ 4cb32eb0`, 2026-08-28):

```
lib/app/config/app_environment.dart : enum {development, lab, production}
                                       tryParse: üres → development, ismeretlen → null
lib/app/config/app_config.dart      : resolve() productionben fail-closed
                                       (HTTPS, loopback-tiltás, dev diag-token, Lab-mód)
backend/app/config.py               : env: str = "dev"   ← SZABAD STRING, nincs enum
backend/app/main.py:36-69           : _guard_prod(settings) — a production titok-,
                                       CORS-, SQLite- és tutor-kulcs-tiltás MÁR ITT ÉL
backend/app/main.py:39,114          : if settings.env != "prod"
backend/app/community/__init__.py:93: getattr(settings, "env", "dev") == "prod"
backend/app/config.py:112           : resolved.get("env", "dev") != "prod"
```

A backend production-jelölője tehát a mért valóságban **`prod`**, nem
`production`, és ez a literál a kör **tilos zónájában** (`backend/app/main.py`,
`backend/app/community/__init__.py`) is ott van, valamint ~20 meglévő teszt
(`backend/tests/test_hardening.py`, `test_migrations.py`,
`tests/tutor/test_tutor_proxy.py`, `tests/community/test_profile_schema.py`)
`Settings(env="prod")`-ot példányosít.

A mért hibaosztály, amit ez az ADR zár: **a szabad string csendes elfogadása**.
Ma egy elgépelt `STRUMSIGHT_ENV=prod uction`, `STRUMSIGHT_ENV=production` vagy
`STRUMSIGHT_ENV=PROD` érték hiba nélkül elindítja a backendet, és mivel minden
production-kapu `== "prod"` egyenlőségre épül, a deploy **dev-titokkal,
wildcard CORS-szal és bekapcsolt Lab-route-okkal** szolgálna ki forgalmat. Ez
nem elméleti: a kliens oldalon ugyanezt a hibaosztályt az
`AppEnvironment.tryParse` null-ja MÁR lezárja (E01-R03) — a backend oldal maradt
nyitva.

## Döntés

### D1 — A backend `env` zárt értékkészlet, kanonikus értékei `dev | lab | staging | prod`

A `Settings.env` mezője a fenti négy kanonikus értéken kívül semmit nem fogad
el. Az ismeretlen érték **példányosítási hiba** (pydantic `ValidationError`),
nem visszaesés `dev`-re.

A kanonikus production-jelölő **`prod` marad**, mert a mért egyenlőség-vizsgálat
(`main.py`, `community/__init__.py`) a kör tilos zónájában él, és az átnevezés
vagy a tilos zónát nyitná meg (H3), vagy ~20 meglévő tesztet törne el
(A7-sértés). Az „egységesítést" a D2 alias-szabálya adja, nem az átnevezés.

### D2 — A kliens enum-nevei ALIASOK, amiket a backend normalizál

A `Settings.env` a példányosításkor `trim().lower()` után normalizál, a
kliens [`AppEnvironment.tryParse`](../../lib/app/config/app_environment.dart)
szemantikájával azonos módon:

| Bemenet | Kanonikus érték |
|---|---|
| hiányzó / üres / csupa whitespace | `dev` |
| `dev`, `development` | `dev` |
| `lab` | `lab` |
| `staging` | `staging` |
| `prod`, `production` | `prod` |
| bármi más | **`ValidationError`** |

Ez teljesíti az SDD Ch12 Kör 4 „Egységesítsd az AppConfig és backend Settings
environment értékeit" feladatát: a `STRUMSIGHT_ENV=production` — a kliens
enum-neve — a backendben is helyesen production, ANÉLKÜL hogy a `== "prod"`
hívóhelyekhez hozzá kellene nyúlni.

**NEM elfogadható gyengítés:** `getattr(..., "dev")`, `or "dev"` vagy
`try/except: env = "dev"` jellegű csendes visszaesés; és nem elfogadható a
normalizálás elhagyása sem (akkor a `production` érték ismeretlenné, azaz
indulási hibává válna — ami fail-closed ugyan, de a D2 célját nem teljesíti).

### D3 — A staging BACKEND-környezet, nem negyedik kliens-flavor

Az `AppEnvironment` enum **nem bővül**. A kliens a stagingot ugyanazzal a `lab`
(vagy `development`) buildtel éri el, más `STRUMSIGHT_API_URL` mellett — az
enum minden hívóhelye (bootstrap, `FeatureFlags.forEnvironment`, Lab-route
regisztráció [ADR 0061](0061-lab-route-isolation-and-hardened-diagnostics.md),
diagnostics) érintetlen marad.

### D4 — A staging fail-closed őre a `Settings` PÉLDÁNYOSÍTÁSÁN ül, a productioné marad a boot-őrben

A production titok-tiltás mért helye `main.py::_guard_prod`, ami a kör tilos
zónája — oda **nem nyúlunk**, és a meglévő szerződést (a hiba a `create_app`
hívásakor keletkezik, nem a `Settings(...)` példányosításkor) nem írjuk át. Az
E12-R04 a `Settings`-be **kizárólag a stagingre** vezet be példányosítás-idejű
fail-closed validációt, mert stagingre ma SEMMILYEN őr nincs:

- `secret_key` nem lehet a repóbeli dev-alapértelmezés;
- `diag_token` nem lehet a repóbeli dev-alapértelmezés, ha `diagnostics_enabled`;
- `cors_origins` nem tartalmazhat `*`-ot;
- SQLite `database_url` csak explicit `allow_sqlite_in_prod` mellett;
- a Lab-flagek (`diagnostics_enabled`, `apk_download_enabled`) alapértelmezése
  stagingen — a productionnel azonosan — **kikapcsolt**.

**A tudatosan vállalt aszimmetria:** production → boot-idejű őr, staging →
példányosítás-idejű őr. Ennek egységesítése (a `_guard_prod` átemelése a
`Settings`-be) az E12-R07 (production signing & secret hardening) dolga, ahol
`backend/app/main.py` és `backend/tests/test_hardening.py` is scope-ban lehet.
Az E12-R04-ben az egységesítés H3 (tilos zóna) és A7 (meglévő teszt gyengítése)
lenne egyszerre.

**NEM elfogadható gyengítés:** a staging ág a production ág puszta aliasa
(`env in ("prod", "staging")` a `_guard_prod`-ban) — az egyrészt tilos zóna,
másrészt elveszítené a D5 titok-elkülönítést.

### D5 — A production kliens-build nem mutathat staging-jelölésű endpointra

Az `AppConfig.resolve()` productionben — a meglévő loopback-tiltással azonos
alakban, azzal EGYÜTT, nem helyette — elutasítja azt az `apiBaseUrl`-t, amelynek
**hostja (kisbetűsítve) tartalmazza a `staging` részláncot**. Ez az SDD Ch12
Kör 4 „production nem olvashat Lab tokent vagy endpointot" előírásának a
mérhető alakja endpoint-oldalon (a token-oldalt a meglévő
`devDiagnosticsToken`-tiltás fedi).

A szabály szándékosan **részlánc-alapú, nem címke-alapú**: a `staging.`,
`api-staging.`, `strumsight-staging.` és `.staging.` alakokat egyaránt fogja. A
false-positive kockázatot (egy legitim production host, amelynek nevében
szerepel a `staging` szó) tudatosan vállaljuk — fail-closed irányba téved, és
`--dart-define` átírással feloldható.

**NEM elfogadható gyengítés:** a tiltás feltételhez kötése (pl. „csak akkor, ha
egyben Lab-token is használatban van") — a brief eredeti megfogalmazása ilyen
konjunkciót tartalmazott, a §0.0 revízió ezt feltétlenre szigorította.

## Következmények

- Egy `STRUMSIGHT_ENV` elgépelés a backend **indulását** állítja meg, nem
  dev-titkokkal induló production deployt ad.
- A `production` és `development` értékek a backendben is használhatók — a
  kliens és a szerver környezet-szótára egységes.
- A stagingnek van saját, gépi őre; ami **nem** gépi, hanem operatív szabály (a
  staging titkai és adatbázisa különbözzenek a productiontől), az a
  [`docs/release/environment-matrix.md`](../release/environment-matrix.md)
  mátrixában kimondva él — egy backend nem tudja megállapítani, hogy egy kapott
  titok „a production titka"-e.
- A `_guard_prod` és a `Settings`-validáció kettőssége nyitott technikai adósság
  → E12-R07.
- Az `AppEnvironment` enum három értéke változatlan; az ADR 0061 Lab-route
  izolációja érintetlen.
