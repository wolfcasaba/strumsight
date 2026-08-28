# E12-R04 — Environment és channel konfiguráció lezárása

- **Státusz:** READY (pre-flight lefutott 2026-08-28, kód újramérve: `main @ 4cb32eb0`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 4
- **Kör-azonosító:** `E12-R04`
- **Branch:** `sonnet-impl/e12-r04-environment-and-channel-isolation`
- **Előfeltétel:** `E12-R01` merge-elve (a baseline rögzíti a jelenlegi környezet-mátrixot)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`ADR 0445`](../adr/0445-environment-value-set-and-staging-isolation.md) — a pre-flightban MEGÍRVA, ez a kör normatív forrása.

**Visszakeresett előzmény (ADR 0312 §4.9, pre-flight 2026-08-28):**

- `--corpus lessons,halts,adr "environment matrix staging production fail-closed backend settings validation"` → **[ADR 0060](../adr/0060-alembic-schema-source-and-injected-engine-lifecycle.md)** (Alembic mint egyetlen production séma-forrás; a `test_prod_with_real_config_boots` MÁR explicit SQLite-engedéllyel boot-ol — ezt a cellát a kör nem írhatja át) és **[L274](../LESSONS.md#l274)** (a kompozíciós bizonyítás ≠ a tényleges production wiring).
- `--corpus lessons,halts "closed enum value set literal validation breaking existing tests forbidden zone backend config"` → **[L195](../LESSONS.md#l195)** (egy additív enum-érték „production-semlegessége" nem elég a DEKLARÁLÓ típusból — a FOGYASZTÓ oldalt is végig kell követni) és **[E99-R16/H3](../../.pipeline/)** (a javítás tilos zónába esne → halt). Mindkettő KÖZVETLENÜL erre a körre illik: a `settings.env` fogyasztói (`main.py`, `community/__init__.py`) a tilos zónában vannak, ezért a `prod` literált NEM nevezhetjük át — lásd §0.0 R1.
- Teljes korpusz: `"backend/app/config.py Settings env prod staging secret_key diag_token app_config.dart resolve fail-closed"` → a `test/app/app_config_test.dart` fejléce (E01-R03 kötelező konfigurációs cellái) és az `app_config.dart` `resolve()` — a kör regresszió-őrei.
- **[ADR 0061](../adr/0061-lab-route-isolation-and-hardened-diagnostics.md)** (Lab-route-ok REGISZTRÁCIÓ-szintű elkülönítése) és **[ADR 0060](../adr/0060-alembic-schema-source-and-injected-engine-lifecycle.md)** a kör HATÁRAI — egyiket sem írja át.

## 0.0 Pre-flight brief-revízió (2026-08-28, orchestrátor, ADR 0087 §2)

A brief PREPARED változatának négy mért állítása megdőlt vagy pontatlan volt. A
revíziók a kör saját, még nem merge-elt artefaktumát érintik, tehát az
orchestrátor hatáskörében vannak. Az engedélyezett-fájllista **változatlan**
(nem tágult).

### R1 — A production-jelölő `prod`, NEM `production`

**Mit mértem.**

```
backend/app/config.py:112              resolved.get("env", "dev") != "prod"
backend/app/main.py:39                 if settings.env != "prod":     (_guard_prod)
backend/app/main.py:114                if settings.env != "prod":     (lifespan create_all)
backend/app/community/__init__.py:93   getattr(settings, "env", "dev") == "prod"
```

és ~20 meglévő teszt (`backend/tests/test_hardening.py`, `test_migrations.py`,
`tests/tutor/test_tutor_proxy.py`, `tests/community/test_profile_schema.py`)
`Settings(env="prod")`-ot példányosít.

**Miért revízió.** A PREPARED brief §3 a `dev | lab | staging | production`
zárt értékkészletet írta elő. A `production` kanonikussá tétele két
lehetőséget hagyna: (a) a `main.py` és `community/__init__.py` átírása — ez a
kör **tilos zónája**, azaz H3; (b) a fenti tesztek eltörése — ez **A7**-sértés.

**A revízió.** A kanonikus értékkészlet **`dev | lab | staging | prod`**, és a
kliens enum-nevei (`development`, `production`) **aliasok**, amiket a `Settings`
példányosításkor normalizál (ADR 0445 D1–D2). Az SDD Ch12 Kör 4
„egységesítsd az értékeket" feladatát az alias-normalizálás teljesíti, nem az
átnevezés.

### R2 — Az A2/A3 production-őr MÁR LÉTEZIK, és a tilos zónában él

**Mit mértem.** `backend/app/main.py:36-69` `_guard_prod(settings)`, amit a
`create_app()` hív: `env == "prod"` mellett elutasítja a dev `secret_key`-t, a
wildcard CORS-t, a dev/üres `diag_token`-t bekapcsolt diagnostics mellett, az
escape-hatch nélküli SQLite-ot és a dev tutor-kulcsot. A cellák léteznek:
`backend/tests/test_hardening.py::TestProdBootGuards`.

**Miért revízió.** A PREPARED brief A2/A3-a („`env=production` + repóbeli dev
`secret_key` → indulási hiba") **ma is teljesül** — új munka nélkül. Ha az
implementer ugyanezt a `Settings` példányosításába emelné, **eltörné** a
`test_prod_with_dev_secret_refuses_to_boot` és
`test_prod_enabled_diagnostics_refuses_insecure_token` cellákat, amelyek
SZÁNDÉKOSAN példányosítanak `Settings(env="prod", …)`-ot dev-titokkal, és a
hibát a `create_app` hívásán várják (A7-sértés, ráadásul a `test_hardening.py`
nincs az engedélyezett listán).

**A revízió.** A2/A3 **regressziós cella** lett: a meglévő `_guard_prod`
szerződését a `create_app`-on keresztül méri, a `Settings`-validációt NEM
mozgatja. Az ÚJ, példányosítás-idejű őr **kizárólag a stagingre** vonatkozik
(A4), ahol ma semmilyen őr nincs (ADR 0445 D4).

### R3 — A `backend/tests/test_settings.py` a `/settings` VÉGPONT profilja, nem a `Settings` teszt

**Mit mértem.** A fájl 8 cellája a `/settings` HTTP-végpontot méri
(`theme_mode`, `locale`, `confidence_threshold`, `tuning_a4`, auth-gate,
per-user izoláció) — egyetlen `Settings(...)` példányosítás sincs benne.

**Miért revízió.** A brief az A1–A4 bizonyítékát ebbe a fájlba tette. A fájl
**az engedélyezett listán van**, tehát a lista tágítása nélkül használható — de
a cellák elhelyezését meg kell kötni, különben a fájl célja elmosódik.

**A revízió.** Az új cellák egy **külön, névvel elkülönített osztályba**
kerülnek (`class TestEnvironmentValueSet`, `class TestStagingIsolation`), a
fájl modul-docstringje pedig kiegészül azzal, hogy a modul MOST KÉT dolgot mér:
a `/settings` végpont profilját ÉS a `Settings.env` értékkészletét. A meglévő 8
cella egyike sem módosulhat. A `backend/tests/test_hardening.py` **nem
szerkeszthető** (nincs a listán) — az A2/A3 regressziós cella az új osztályban,
`create_app`-on keresztül mér.

### R4 — Az A5-kiegészítés feltételes megfogalmazása feltétlenre szigorítva

**Mit mértem.** `test/app/app_config_test.dart` egyetlen cellája sem használ
`staging` részláncot tartalmazó hostot (a hostok: `api.strumsight.example`,
`secret-host.example`, `localhost`, `127.0.0.1`, `10.0.2.2`), tehát az új
tiltás nem tör el meglévő cellát.

**Miért revízió.** A PREPARED brief §3 szövege — „production build nem mutathat
staging-jelölésű endpointra, **ha az egyben Lab-token használatát is jelentené**"
— konjunkcióval gyengítette a szabályt: egy staging endpointra mutató
production build production-tokennel átment volna. Az SDD Ch12 Kör 4 előírása
(„production nem olvashat Lab tokent VAGY endpointot") diszjunktív.

**A revízió.** A tiltás **feltétlen**: productionben, ha bármely hálózatot
használó flag be van kapcsolva, a host (kisbetűsítve) nem tartalmazhatja a
`staging` részláncot (ADR 0445 D5). A meglévő loopback-tiltás MELLÉ kerül, nem
helyette.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/app/config/app_config.dart",
  "lib/app/config/app_environment.dart",
  "backend/app/config.py",
  "backend/tests/test_settings.py",
  "test/app/app_config_test.dart",
  "docs/release/environment-matrix.md",
  "docs/rounds/e12-r04-environment-and-channel-isolation.md",
]
gate_tests = [
  "test/app/app_config_test.dart",
  "test/app/config/feature_flags_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a diff a hitelesítési és titok-határon dolgozik
(`diag_token`, `secret_key`, production endpoint-tiltás) — egy elrontott
fail-closed ág production buildben Lab-titkot engedne be. A `security-reviewer`
ügynök futtatása a review-ban KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a munkához az `AppEnvironment` enum bővítése, a
`lib/app/routing/**`, a `backend/app/main.py`, a
`backend/app/community/__init__.py` vagy a `backend/tests/test_hardening.py`
érintése kellene, a kimenet a `stopped` jelzés és brief-revízió kérése — a
lista csendes tágítása TILOS ([L478](../LESSONS.md#l478)).

## 1. Cél

A Development, Lab, Staging és Production adat- és titok-elkülönítésének
lezárása úgy, hogy a production ág fail-closed marad, a backend
környezet-értékkészlete zárt lesz (ismeretlen érték ⇒ indulási hiba), a
kliens enum-nevei aliasként elfogadottak, és a staging kizárólag backend-oldali
deployment-cél.

## 2. Jelenlegi állapot — mért tények (`main @ 4cb32eb0`, 2026-08-28)

- `lib/app/config/app_environment.dart`: az enum **három** értéke
  `development`, `lab`, `production`; `tryParse` üres/hiányzó → `development`,
  ismeretlen → **null** (nem coerce-öl defaultra) → kontrollált bootstrap-hiba.
- `lib/app/config/app_config.dart` `resolve()` MÁR fail-closed productionben:
  nem-HTTPS URL, loopback host (`localhost`, `127.0.0.1`, `10.0.2.2`), üres vagy
  DEV diagnostics-token bekapcsolt diagnostics mellett, és elérhető Lab-mód mind
  `ConfigurationException`-t ad (`app_config.dart:128-168`). A `resolve()`
  MINDEN sértett szabályt összegyűjt, nem az elsőnél dob.
- `backend/app/config.py`: `Settings` `env_prefix="STRUMSIGHT_"`,
  **`env: str = "dev"` — szabad string, semmilyen validáció**; `secret_key`
  dev-alapértelmezés `"dev-insecure-change-me-in-production"`;
  `diag_token: str = "strumsight-lab-dev"` — ugyanaz a dev-token, amit a kliens
  `AppConfig.devDiagnosticsToken`-je ismer; `allow_sqlite_in_prod` flag
  (`validation_alias="STRUMSIGHT_ALLOW_SQLITE"`); a
  `_default_lab_flags_for_environment` `mode="before"` validátor a Lab-flageket
  `env != "prod"` esetén kapcsolja be.
- **A production titok-őr `backend/app/main.py:36-69` `_guard_prod`-ban él**, a
  `create_app()` hívja — ez a kör **tilos zónája** (§0.0 R2).
- **A production-jelölő literál `"prod"`** — a `main.py`, a
  `community/__init__.py` és a `config.py:112` egyaránt erre az egyenlőségre
  épül (§0.0 R1).
- **Staging MA nincs** sem kliens-, sem backend-oldalon: az `env` string
  „staging" értéke ma semmit nem kapcsol, sőt a `!= "prod"` ág miatt
  **bekapcsolná** a Lab-route-okat.
- `backend/tests/test_settings.py` a `/settings` VÉGPONT profilja (§0.0 R3);
  a `Settings` hardening-cellái `backend/tests/test_hardening.py::TestProdBootGuards`
  alatt vannak — **az a fájl nincs az engedélyezett listán**.
- `test/app/app_config_test.dart` és `test/app/config/feature_flags_test.dart`
  léteznek — ezek a kör regresszió-őrei; **átírásuk a zöldért TILOS** (elbukó
  meglévő teszt ⇒ megállás és jelentés).
- `docs/release/` létezik (`blockers.md`, `program-baseline.md`,
  `release-history-audit.md`); `environment-matrix.md` **még nincs**.

## 3. Scope

**Benne van:**

- `backend/app/config.py`: a `Settings.env` zárt értékkészletre szigorítása
  (`dev | lab | staging | prod`), a kliens-alias normalizálásával
  (`development`→`dev`, `production`→`prod`, üres/hiányzó→`dev`,
  `trim().lower()`), ismeretlen érték → **`ValidationError`** (ADR 0445 D1–D2).
- `backend/app/config.py`: **staging** példányosítás-idejű fail-closed
  validáció (dev `secret_key` tiltva; dev/üres `diag_token` tiltva bekapcsolt
  diagnostics mellett; wildcard CORS tiltva; SQLite csak
  `allow_sqlite_in_prod` mellett) + a Lab-flagek alapértelmezése stagingen a
  productionnel azonosan **kikapcsolt** (ADR 0445 D4).
- `backend/tests/test_settings.py`: az A1–A4 cellák külön osztályokban
  (§0.0 R3).
- `lib/app/config/app_config.dart`: productionben a staging-jelölésű host
  **feltétlen** tiltása, a meglévő loopback-tiltás MELLETT (ADR 0445 D5).
- `lib/app/config/app_environment.dart`: dokumentációs pontosítás — a staging
  NEM kliens-környezet, a backend `STRUMSIGHT_ENV` értékkészlete és az
  alias-leképezés kimondva.
- `test/app/app_config_test.dart`: az A5 cellák BŐVÍTÉSE.
- `docs/release/environment-matrix.md`: ÚJ — a négy környezet mátrixa.

**NINCS benne (tilos):**

- **Az `AppEnvironment` enum bővítése** — a staging a §5.1 szerint
  backend-oldali (STOP-eset, ha mégis kellene).
- **`backend/app/main.py`** (`_guard_prod`, lifespan, router-regisztráció) és
  **`backend/app/community/__init__.py`** — a `prod` literál fogyasztói.
- **`backend/tests/test_hardening.py`** és minden más backend teszt.
- `lib/app/routing/**` és a Lab-route regisztráció (ADR 0061 hatálya).
- Bármely meglévő teszt gyengítése, `skip`-je vagy törlése.
- `docs/adr/**` — az ADR 0445 a pre-flightban MÁR megíródott.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/app/config/app_config.dart` | a staging-host tiltás hozzáadása a fail-closed ágakhoz |
| `lib/app/config/app_environment.dart` | dokumentációs pontosítás (a staging NEM kliens-környezet + alias-tábla) |
| `backend/app/config.py` | zárt `env` értékkészlet + alias-normalizálás + staging-őr |
| `backend/tests/test_settings.py` | az A1–A4 cellák (ÚJ osztályokban, meglévő cella nem módosul) |
| `test/app/app_config_test.dart` | az A5 cellák (BŐVÍTÉS, meglévő cella nem törölhető) |
| `docs/release/environment-matrix.md` | ÚJ — a négy környezet mátrixa |
| `docs/rounds/e12-r04-environment-and-channel-isolation.md` | §10 implementation handoff |

**Tilos zóna:** `backend/app/main.py` · `backend/app/community/**` ·
`backend/tests/test_hardening.py` · minden egyéb `backend/tests/**` ·
`backend/alembic/**` · `lib/app/routing/**` · `lib/features/**` ·
`.github/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések ([ADR 0445](../adr/0445-environment-value-set-and-staging-isolation.md))

### 5.1 A staging BACKEND-környezet, nem negyedik kliens-flavor (ADR 0445 D3)

A kliens a stagingot ugyanazzal a `lab` (vagy `development`) buildtel éri el,
más `STRUMSIGHT_API_URL` mellett. **NEM elfogadható gyengítés:** egy negyedik
`AppEnvironment` érték bevezetése „a teljesség kedvéért" — az enum minden
hívóhelyét (bootstrap, `FeatureFlags.forEnvironment`, Lab-route regisztráció,
diagnostics) érinti, és a Kör 4 scope-ján kívüli regressziós felületet nyit.

### 5.2 Az ismeretlen környezet-érték HIBA, nem default (ADR 0445 D1)

A backend `env` ismeretlen értéke példányosítási hibát ad, pontosan úgy, ahogy
a kliens `AppEnvironment.tryParse` null-t ad. **NEM elfogadható gyengítés:**
`getattr(..., "dev")`, `or "dev"` vagy `try/except → "dev"` jellegű csendes
visszaesés — egy elgépelt `STRUMSIGHT_ENV=prod uction` így dev-titkokkal
indítana production deployt.

### 5.3 A kanonikus production-jelölő `prod`; a kliens enum-nevei ALIASOK (ADR 0445 D2)

`development`→`dev`, `production`→`prod`, üres/hiányzó→`dev`, `trim().lower()`
után. **NEM elfogadható gyengítés:** a `prod` literál átnevezése
`production`-re — a fogyasztói (`main.py`, `community/__init__.py`) a tilos
zónában vannak, és ~20 meglévő teszt `Settings(env="prod")`-ot példányosít
(§0.0 R1). **Az sem elfogadható**, ha az alias-leképezés kimarad: akkor a
`production` érték ismeretlenné, azaz indulási hibává válna, és az SDD Kör 4
„egységesítés" feladata teljesítetlen maradna.

### 5.4 A staging őre a `Settings` PÉLDÁNYOSÍTÁSÁN ül, a productioné marad a boot-őrben (ADR 0445 D4)

A production őr (`main.py::_guard_prod`) **változatlan** — tilos zóna, és a
meglévő cellák a `create_app` hívásán várják a hibát. Az új, példányosítás-idejű
őr **kizárólag a stagingre** vonatkozik. **NEM elfogadható gyengítés:** a
staging ág a production ág aliasa (`env in ("prod","staging")`) — az egyrészt
tilos zóna, másrészt elveszítené a titok-elkülönítést.

### 5.5 A production titok-tiltás fail-closed, ismert-rossz-érték listával

A staging-őr elutasítja a repóban SZEREPLŐ dev-alapértelmezéseket
(`dev-insecure-change-me-in-production`, `strumsight-lab-dev`). **NEM
elfogadható gyengítés:** csak „üres-e" ellenőrzés — a mért valóság az, hogy a
dev értékek nem üresek, hanem konkrét, publikus stringek. A listát a
`Settings.model_fields[...].default` értékéből kell olvasni (ahogy a
`main.py:29-31` teszi), nem újra beírt string-literálból.

### 5.6 A production kliens-build nem mutathat staging-jelölésű endpointra (ADR 0445 D5)

Productionben, ha bármely hálózatot használó flag be van kapcsolva, a host
kisbetűsített alakja nem tartalmazhatja a `staging` részláncot. **NEM
elfogadható gyengítés:** a tiltás feltételhez kötése (pl. „csak ha Lab-token is
használatban van"), vagy a meglévő loopback-tiltás HELYETT való bevezetése.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Ismeretlen `STRUMSIGHT_ENV` (pl. `"prod uction"`, `"qa"`) a `Settings` példányosítását `ValidationError`-ral megállítja — nem esik vissza `dev`-re | `backend/tests/test_settings.py::TestEnvironmentValueSet` |
| A1b | `""`, `"  "` és a hiányzó érték → `dev`; `"development"`/`"DEV"` → `dev`; `"production"`/`"PROD "` → `prod`; `"lab"` → `lab`; `"staging"` → `staging` | `backend/tests/test_settings.py::TestEnvironmentValueSet` |
| A2 | `env="prod"` + repóbeli dev `secret_key` → a `create_app()` `RuntimeError`-t dob (a MEGLÉVŐ `_guard_prod` szerződése regresszió-mentes) | `backend/tests/test_settings.py::TestEnvironmentValueSet` |
| A3 | `env="production"` (alias) ugyanazt a production őrt kapja, mint `env="prod"`: dev `diag_token` + `diagnostics_enabled=True` → `create_app()` `RuntimeError` | `backend/tests/test_settings.py::TestEnvironmentValueSet` |
| A4 | `env="staging"`: dev `secret_key`, dev `diag_token` (bekapcsolt diagnostics mellett), wildcard CORS és escape-hatch nélküli SQLite MIND `ValidationError` a `Settings(...)` példányosításakor; valós titkokkal viszont példányosul, és a Lab-flagek alapértelmezése `False` | `backend/tests/test_settings.py::TestStagingIsolation` |
| A5 | A kliens meglévő production fail-closed cellái VÁLTOZATLANUL zöldek (HTTPS, loopback-host, dev-token, Lab-mód), ÉS production + `https://staging.strumsight.app` → `ConfigurationException`, míg ugyanez a host `lab`/`development` környezetben elfogadott | `test/app/app_config_test.dart` |
| A6 | `docs/release/environment-matrix.md` mind a négy környezetre megadja: hol él (kliens/backend/mindkettő), milyen `STRUMSIGHT_ENV` érték + elfogadott aliasok, milyen titok, milyen endpoint, milyen adatbázis, milyen Lab-flag alapértelmezés | a dokumentum táblázata |
| A7 | Egyetlen meglévő teszt sem lett törölve, `skip`-elve vagy gyengítve; a tilos zóna egyetlen fájlja sem változott | `git diff --stat` + a §7 gate + a gépi scope-audit |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA | Melyik őr méri |
|---|---|---|
| Az `env` validáció ismeretlen értékre `dev`-re esik vissza | **A1** | unit-cella (`pytest.raises(ValidationError)`) |
| Az alias-normalizálás kimarad (`production` ismeretlennek számít) | **A1b** és **A3** | unit-cella (`Settings(env="production").env == "prod"`) |
| Az alias-normalizálás kisbetűsítés/trim nélkül készül | **A1b** (`"PROD "`) | unit-cella |
| A staging-őr csak az ÜRES titkot fogja, a repóbeli dev-értéket nem | **A4** | unit-cella (`Settings(env="staging", secret_key=<dev default>)`) |
| A staging ág a production ág aliasa lesz (a titok-elkülönítés elvész) | **A4** (a Lab-flag alapértelmezés és a példányosítás-idejű hiba cellája) | unit-cella |
| A staging-őr a productionre is elsül (a `Settings(env="prod", secret_key=<dev>)` már példányosításkor dobna) | **A2** — a cella a `create_app`-on várja a hibát, nem a konstruktoron; és `backend/tests/test_hardening.py` (nem módosítható) | unit-cella + a meglévő hardening-cellák |
| A kliens `resolve()` átrendezése közben kiesik a loopback- vagy a dev-token-tiltás | **A5** | a MEGLÉVŐ E01-R03 cellák |
| A staging-host tiltás feltételhez kötve (csak Lab-token mellett) készül | **A5** (production + staging host + valós production token) | unit-cella |
| A staging-host tiltás a NEM-production környezetekre is elsül | **A5** (`lab` + staging host ⇒ elfogadott) | unit-cella |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):**

1. Állítsd a staging titok-ellenőrzést „csak üres string tiltott"-ra →
   `cd backend && python -m pytest tests/test_settings.py -q` → az **A4**
   cellának PIROSNAK kell lennie → állítsd vissza.
2. Töröld a kliens staging-host tiltását → `flutter test test/app/app_config_test.dart`
   → az **A5** új cellájának PIROSNAK kell lennie → állítsd vissza.

Mindkét próba KIMENETÉT (a bukó cella neve + a hibaüzenet első sora) írd be a
§10-be — a „visszaállítottam" önmagában nem bizonyíték.

## 7. Kötelező ellenőrzések

Dart sáv — a mérce artefaktum, csővezeték és `tail` NÉLKÜL:

```bash
tools/round-gate.sh test/app/app_config_test.dart test/app/config/feature_flags_test.dart
```

Backend sáv (külön processzként):

```bash
cd backend && python -m pytest tests/test_settings.py tests/test_hardening.py -q
```

A `test_hardening.py` azért fut le, mert a `Settings` szerződése alatta van —
**nem szerkesztheted**, csak zölden kell tartanod (A7).

## 8. Implementációs sorrend

A brief §8 a TERVED — nincs külön task-lista.

1. `backend/app/config.py` — zárt `env` értékkészlet + alias-normalizálás
   (`field_validator`/`mode="before"`), a meglévő
   `_default_lab_flags_for_environment` viselkedésének megőrzésével dev/lab/prod-ra.
2. `backend/app/config.py` — staging példányosítás-idejű őr + Lab-flag
   alapértelmezés stagingen `False`.
3. `backend/tests/test_settings.py` — az A1–A4 cellák ÚJ osztályokban, a
   modul-docstring kiegészítésével.
4. `lib/app/config/app_config.dart` — a staging-host tiltás a meglévő
   loopback-blokk MELLÉ.
5. `lib/app/config/app_environment.dart` — doc-comment pontosítás (a staging NEM
   kliens-környezet + alias-tábla). **Doc-commentben csak tesztben bizonyított
   állítás szerepelhet.**
6. `test/app/app_config_test.dart` — az A5 cellák bővítése.
7. `docs/release/environment-matrix.md`.
8. A valódi-sértés próbák a §10-be.

## 9. Kockázatok

- **A csendes visszaesés.** A `dev` defaultra esés a legveszélyesebb
  hibaosztály: production deploy dev-titokkal (A1).
- **Az enum-bővítés csábítása.** Egy negyedik `AppEnvironment` érték a kör
  scope-ját sokszorosára tágítaná (§5.1, STOP-eset).
- **A `prod` literál átnevezésének csábítása.** A fogyasztói a tilos zónában
  vannak (§0.0 R1) — az átnevezés H3 vagy A7.
- **A staging-őr túlnyúlása a productionre.** Ha a példányosítás-idejű őr a
  `prod` értékre is elsül, a `test_hardening.py` MEGLÉVŐ cellái elbuknak — az
  A7-sértés, nem „szigorítás" (§5.4).
- **A meglévő fail-closed ágak regressziója.** A `resolve()` átrendezése
  észrevétlenül ejthet egy ágat (A5, A7).

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** Claude Sonnet 5 (`sonnet-impl`), 2026-08-28.

### 10.1 Mit implementáltam

- `backend/app/config.py`: a `_default_lab_flags_for_environment`
  `mode="before"` model-validator átnevezve
  `_normalize_environment_and_default_lab_flags`-re, kiegészítve a zárt
  `dev | lab | staging | prod` értékkészlet-kényszerrel és a
  `development`→`dev` / `production`→`prod` alias-normalizálással
  (`trim().lower()` után; hiányzó/üres → `dev`; ismeretlen → `ValueError`,
  amit pydantic `ValidationError`-rá csomagol). A Lab-flagek
  (`diagnostics_enabled`, `apk_download_enabled`) alapértelmezése ugyanitt
  bővült: `False`, ha `env in ("prod", "staging")`.
- `backend/app/config.py`: új `_guard_staging` `mode="after"` model-validator
  — kizárólag `env == "staging"` esetén fut, a dev `secret_key`, a wildcard
  CORS, a bekapcsolt diagnosztika melletti dev/üres `diag_token` és az
  escape-hatch nélküli SQLite ellen, ugyanazokat a dev-alapértelmezéseket
  olvasva a `Settings.model_fields[...].default`-ból, mint a `main.py`
  meglévő `_guard_prod`-ja. A production ág (`main.py::_guard_prod`,
  `create_app()`) **nem módosult** — tilos zóna.
- `backend/tests/test_settings.py`: modul-docstring kiegészítve; két új
  osztály — `TestEnvironmentValueSet` (A1, A1b, A2 regresszió, A3) és
  `TestStagingIsolation` (A4) —, a meglévő 8 cella változatlan.
- `lib/app/config/app_config.dart`: a production fail-closed ág a meglévő
  loopback-tiltás MELLÉ egy feltétlen staging-host tiltást kapott
  (`uri.host.toLowerCase().contains('staging')`), plusz a `resolve()`
  doc-comment pontosítása.
- `lib/app/config/app_environment.dart`: doc-comment kiegészítve — a staging
  NEM ennek az enumnak az értéke, a backend `STRUMSIGHT_ENV` alias-táblája
  kimondva.
- `test/app/app_config_test.dart`: egy új cella a production csoportban
  (staging-host feltétlen tiltás) + egy új csoport, ami igazolja, hogy
  ugyanaz a host `lab`/`development` alatt elfogadott.
- `docs/release/environment-matrix.md`: új dokumentum, a négy környezet
  mátrixa fájl+sor és teszt-hivatkozásokkal.

### 10.2 Kötelező ellenőrzések — kimenet

- `tools/round-gate.sh test/app/app_config_test.dart
  test/app/config/feature_flags_test.dart` → **MINDEN GATE ZÖLD** (format,
  analyze, mindkét dart teszt-útvonal külön, architecture, secrets, l10n,
  backend ruff format, backend ruff check, backend pytest — a gate maga is
  lefuttatta a teljes backend suite-ot).
- `cd backend && python3 -m pytest tests/test_settings.py
  tests/test_hardening.py -q` → **44 passed** (a `test_hardening.py`
  egyetlen sora sem módosult, mindegyik zöld maradt — A7).
- `cd backend && python3 -m pytest -q` (teljes backend suite, saját
  ellenőrzésként a kötelező gate-en felül) → **all green** (csak
  `DeprecationWarning`-ok, hiba nélkül).

### 10.3 Valódi-sértés próbák (§6.1)

**1. próba — a staging titok-ellenőrzés „csak üres string tiltott"-ra
gyengítve** (`backend/app/config.py::_guard_staging`, a `secret_key ==
dev_secret` sort ideiglenesen `not self.secret_key.strip()`-re cserélve):

```
$ cd backend && python3 -m pytest tests/test_settings.py -q
......................F....                                              [100%]
FAILED tests/test_settings.py::TestStagingIsolation::test_dev_secret_key_refuses_to_instantiate
Failed: DID NOT RAISE <class 'pydantic_core._pydantic_core.ValidationError'>
```

Az **A4** cella (`TestStagingIsolation::test_dev_secret_key_refuses_to_instantiate`)
pirosra váltott, ahogy a mérce-mátrix előírja. Visszaállítva
(`self.secret_key == dev_secret`), utána `pytest tests/test_settings.py
tests/test_hardening.py -q` → **44 passed** (zöld).

**2. próba — a kliens staging-host tiltása törölve**
(`lib/app/config/app_config.dart`-ból a `uri.host.toLowerCase().contains('staging')`
ág ideiglenesen eltávolítva):

```
$ flutter test test/app/app_config_test.dart
00:00 +6 -1: production configuration rejects a staging-labelled host unconditionally (ADR 0445 D5) [E]
  expected ConfigurationException
  package:matcher                       fail
  test/app/app_config_test.dart 39:3    _problemsOf
  test/app/app_config_test.dart 114:24  main.<fn>.<fn>
...
Some tests failed.
```

Az új **A5** cella (`rejects a staging-labelled host unconditionally (ADR
0445 D5)`) pirosra váltott. Visszaállítva, utána `flutter test
test/app/app_config_test.dart` → **21 tests, All tests passed!** (zöld).

### 10.4 Scope

`git status --short` a munka végén pontosan az engedélyezett fájllista
almazmazát mutatja: `backend/app/config.py`,
`backend/tests/test_settings.py`, `lib/app/config/app_config.dart`,
`lib/app/config/app_environment.dart`, `test/app/app_config_test.dart`
(módosítva) + `docs/release/environment-matrix.md` (új) + ez a fájl (§10). A
tilos zóna egyetlen fájlja sem érintett.

### 10.5 Javító kör (review B1–B4) — a leletek lezárása

A javító kör implementer-futása a `sonnet-impl` motor **3600 s abszolút
időkorlátjába** futott bele (`status=timeout`, `scope_audit=ok`,
`scope_audit_changed=3`), a kód-munka azonban ekkorra elkészült és a
munkapéldányban commitolatlanul állt. Az orchestrátor a scope-auditált diffet
ellenőrizte, a mérce-próbákat **maga futtatta le** (lásd alább), és a `8e832a21`
commitban rögzítette. Ez nem gyengíti a mércét: minden alábbi szám a
munkapéldányban ténylegesen futtatott parancs kimenete, és ugyanez a HEAD megy
végig a teljes CI-kapun.

**A javítás tartalma:** `hide_input_in_errors=True` a `Settings.model_config`-ban
(B1), `not self.secret_key.strip() or …` a `_guard_staging` első ágában (B2),
`tutor_api_key`-sor az `environment-matrix.md`-ben (B3), a validátor korábbi
nevének kimondása doc-commentben (B4). Új gépi őrök: a
`TestSecretsNeverLeakIntoErrors` osztály három cellája és a
`TestStagingIsolation::test_empty_or_blank_secret_key_refuses_to_instantiate`
két paraméterezett cellája.

**B1 valódi-sértés próba** (`hide_input_in_errors=True` sor ideiglenesen
eltávolítva):

```
$ cd backend && python -m pytest tests/test_settings.py -q -p no:randomly
FAILED tests/test_settings.py::TestSecretsNeverLeakIntoErrors::test_unknown_env_error_does_not_leak_secret_key
FAILED tests/test_settings.py::TestSecretsNeverLeakIntoErrors::test_unknown_env_error_does_not_leak_database_url
FAILED tests/test_settings.py::TestSecretsNeverLeakIntoErrors::test_staging_guard_error_does_not_leak_database_url
```

Mindhárom új cella pirosra váltott → a sor visszaállítva.

**B2 valódi-sértés próba** (a `not self.secret_key.strip() or` rész
ideiglenesen visszavéve a puszta egyenlőség-vizsgálatra):

```
$ cd backend && python -m pytest tests/test_settings.py -q -p no:randomly
FAILED tests/test_settings.py::TestStagingIsolation::test_empty_or_blank_secret_key_refuses_to_instantiate[]
FAILED tests/test_settings.py::TestStagingIsolation::test_empty_or_blank_secret_key_refuses_to_instantiate[   ]
```

Mindkét paraméterezett cella pirosra váltott → a `.strip()`-es ág visszaállítva.

**A B1 eredeti boot-log reprodukciója a javítás UTÁN** (ugyanaz a parancs, ami a
review-ban a DB-jelszót kiszivárogtatta):

```
$ cd backend && env -i PATH=/usr/bin:/bin HOME=/home/ubuntu \
    STRUMSIGHT_ENV="Prod-uction" \
    STRUMSIGHT_SECRET_KEY="9f3c1a7be24d05f8a1b6c0d3e7f2a894" \
    STRUMSIGHT_DATABASE_URL="postgresql+psycopg://app:Pg-Pa55w0rd@db.internal/ss" \
    python -c "from app.config import Settings; Settings()"

1 validation error for Settings
  Value error, STRUMSIGHT_ENV='Prod-uction' is not a recognized environment
  (expected one of ['dev', 'lab', 'prod', 'staging'], or the aliases
  development/production). [type=value_error]
LEAK secret_fragment: False | LEAK db_password: False
```

**Ruff-kapuk a javítás után** (a `backend-ci.yml` ugyanezt futtatja):

```
$ cd backend && python -m ruff check app tests
All checks passed!
$ cd backend && python -m ruff format --check app tests
131 files already formatted
```

## 11. Review — a Claude tölti ki

Lásd: [`docs/reviews/e12-r04-review.md`](../reviews/e12-r04-review.md).
