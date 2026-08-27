# E12-R04 — Environment és channel konfiguráció lezárása

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 4
- **Kör-azonosító:** `E12-R04`
- **Branch:** `<motor>/e12-r04-environment-and-channel-isolation`
- **Előfeltétel:** `E12-R01` merge-elve (a baseline rögzíti a jelenlegi környezet-mátrixot)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0445` — a szám FOGLALT (Chapter 12 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "environment matrix production lab staging fail-closed config isolation"` → **[ADR 0061](../adr/0061-lab-route-isolation-and-hardened-diagnostics.md)** (a Lab-route-ok REGISZTRÁCIÓ-szintű elkülönítése — production buildben a route létre sem jön) és **[ADR 0060](../adr/0060-alembic-schema-source-and-injected-engine-lifecycle.md)** (Alembic mint egyetlen production séma-forrás). A kör mindkettő HATÁRÁN dolgozik, és egyiket sem írhatja át.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/app/config/app_config.dart` `resolve()` fail-closed ágait (a megíráskor: production ⇒ HTTPS kötelező, dev-host tiltott, dev diagnostics-token tiltott, Lab-mód tiltott) és a `backend/app/config.py` `Settings` mezőit (`env_prefix="STRUMSIGHT_"`, `env: str = "dev"`, `allow_sqlite_in_prod`). A §2 minden állítását újra kell mérni.

## 0.0 Négy környezet — de HOL

A SDD Kör 4 négy környezetet kér (Development, Lab, Staging, Production). A fán az `AppEnvironment` enum **három** értéket ismer (`development`, `lab`, `production`), a backend `Settings.env` pedig szabad string (`"dev"` alapértelmezés). A staging egy DEPLOYMENT-cél, nem egy negyedik kliens-build-flavor: a §5.1 ezt köti meg. Ha a pre-flight azt méri, hogy egy negyedik enum-érték mégis elkerülhetetlen, az brief-revízió (a blast radius az `AppEnvironment` MINDEN hívóhelye), nem az implementer önálló döntése.

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

**Kockázat = high, indoklás:** a diff a hitelesítési és titok-határon dolgozik (`diag_token`, `secret_key`, production endpoint-tiltás) — egy elrontott fail-closed ág production buildben Lab-titkot engedne be. A `security-reviewer` ügynök futtatása a review-ban KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a munkához az `AppEnvironment` enum bővítése vagy a `lib/app/routing/**` érintése kellene, a kimenet a `stopped` jelzés és brief-revízió kérése — a lista csendes tágítása TILOS ([L478](../LESSONS.md#l478)).

## 1. Cél

A Development, Lab, Staging és Production adat- és titok-elkülönítésének lezárása úgy, hogy a production ág fail-closed marad, és a staging kizárólag backend-oldali deployment-cél.

## 2. Jelenlegi állapot — mért tények

- `lib/app/config/app_environment.dart`: az enum **három** értéke `development`, `lab`, `production`; ismeretlen `STRUMSIGHT_ENV` érték → `tryParse` **null** (nem coerce-öl defaultra) → kontrollált bootstrap-hiba.
- `lib/app/config/app_config.dart` `resolve()` MÁR fail-closed productionben: nem-HTTPS URL, dev-host (`10.0.2.2`), hiányzó vagy DEV diagnostics-token és elérhető Lab-mód mind `ConfigurationException`-t ad (`app_config.dart:131–168`).
- `backend/app/config.py`: `Settings` `env_prefix="STRUMSIGHT_"`, `env: str = "dev"` (szabad string, nincs enum), `secret_key` DEV-alapértelmezéssel, `allow_sqlite_in_prod` flag, `diag_token: str = "strumsight-lab-dev"` — ugyanaz a dev-token, amit a kliens `AppConfig.devDiagnosticsToken`-je ismer.
- **Staging MA nincs** sem kliens-, sem backend-oldalon: az `env` string „staging" értéke ma semmit nem kapcsol.
- `test/app/app_config_test.dart` és `test/app/config/feature_flags_test.dart` léteznek — ezek a kör regresszió-őrei; **átírásuk a zöldért TILOS** (elbukó meglévő teszt ⇒ megállás és jelentés).

## 3. Scope

**Benne van:** a backend `Settings.env` szigorítása zárt értékkészletre (`dev` | `lab` | `staging` | `production`), ismeretlen érték → indulási hiba (fail-closed) · production backend: dev `secret_key` és dev `diag_token` TILTVA, `allow_sqlite_in_prod` false mellett SQLite tiltva · staging: production-szerű validáció, de külön adatbázis/media-cél, és kimondottan tiltott production-titok · kliens: a `resolve()` fail-closed ágainak KIEGÉSZÍTÉSE azzal, hogy production build nem mutathat staging-jelölésű endpointra, ha az egyben Lab-token használatát is jelentené · `docs/release/environment-matrix.md` (a négy környezet mátrixa: melyik oldalon él, milyen titok, milyen endpoint, milyen adatbázis).

**NINCS benne (tilos):**

- **Az `AppEnvironment` enum bővítése** — a staging a §5.1 szerint backend-oldali (STOP-eset, ha mégis kellene).
- `lib/app/routing/**` és a Lab-route regisztráció (ADR 0061 hatálya).
- Bármely meglévő teszt gyengítése, `skip`-je vagy törlése.
- `docs/adr/**` — az ADR 0445-öt a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/app/config/app_config.dart` | a fail-closed ágak kiegészítése |
| `lib/app/config/app_environment.dart` | dokumentációs pontosítás (a staging NEM kliens-környezet) |
| `backend/app/config.py` | zárt `env` értékkészlet + production titok-tiltás |
| `backend/tests/test_settings.py` | a backend-oldali §6 cellái |
| `test/app/app_config_test.dart` | a kliens-oldali §6 cellái (BŐVÍTÉS, meglévő cella nem törölhető) |
| `docs/release/environment-matrix.md` | ÚJ — a négy környezet mátrixa |

**Tilos zóna:** `lib/app/routing/**` · `lib/features/**` · `backend/app/` egyéb moduljai · `backend/alembic/**` · `.github/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0445)

### 5.1 A staging BACKEND-környezet, nem negyedik kliens-flavor

A kliens a stagingot ugyanazzal a `lab` (vagy `development`) buildtel éri el, más `STRUMSIGHT_API_URL` mellett. **NEM elfogadható gyengítés:** egy negyedik `AppEnvironment` érték bevezetése „a teljesség kedvéért" — az enum minden hívóhelyét (bootstrap, flag-feloldás, Lab-route regisztráció, diagnostics) érinti, és a Kör 4 scope-ján kívüli regressziós felületet nyit.

### 5.2 Az ismeretlen környezet-érték HIBA, nem default

A backend `env` ismeretlen értéke indulási hibát ad, pontosan úgy, ahogy a kliens `AppEnvironment.tryParse` null-t ad. **NEM elfogadható gyengítés:** `getattr(..., "dev")` jellegű csendes visszaesés — egy elgépelt `STRUMSIGHT_ENV=prod` így dev-titkokkal indítana production deployt.

### 5.3 A production titok-tiltás fail-closed, ismert-rossz-érték listával

A production ág elutasítja a repóban SZEREPLŐ dev-alapértelmezéseket (`dev-insecure-change-me-in-production`, `strumsight-lab-dev`). **NEM elfogadható gyengítés:** csak „üres-e" ellenőrzés — a mért valóság az, hogy a dev értékek nem üresek, hanem konkrét, publikus stringek.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Ismeretlen `STRUMSIGHT_ENV` a backend indulását megállítja (nem esik vissza `dev`-re) | `backend/tests/test_settings.py` |
| A2 | `env=production` + repóbeli dev `secret_key` → indulási hiba | `backend/tests/test_settings.py` |
| A3 | `env=production` + `diag_token == "strumsight-lab-dev"` → indulási hiba | `backend/tests/test_settings.py` |
| A4 | `env=staging` production-szerű validációt kap, de a production-titkok használata tiltott | `backend/tests/test_settings.py` |
| A5 | A kliens meglévő production fail-closed cellái VÁLTOZATLANUL zöldek (HTTPS, dev-host, dev-token, Lab-mód) | `test/app/app_config_test.dart` |
| A6 | `docs/release/environment-matrix.md` mind a négy környezetre megadja: hol él, milyen titok, milyen endpoint, milyen adatbázis | a dokumentum táblázata |
| A7 | Egyetlen meglévő teszt sem lett törölve, `skip`-elve vagy gyengítve | `git diff` a teszt-fájlokon + a §7 gate |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az `env` validáció ismeretlen értékre `dev`-re esik vissza | A1 |
| A production-ellenőrzés csak az ÜRES titkot fogja, a repóbeli dev-értéket nem | A2 és A3 |
| A staging ág egyszerűen a production ág aliasa lesz (a titok-elkülönítés elvész) | A4 |
| A kliens `resolve()` átrendezése közben kiesik a dev-host tiltás | A5 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** állítsd a backend production ág titok-ellenőrzését „csak üres string tiltott"-ra, futtasd a backend teszteket → az **A2** és **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app/app_config_test.dart test/app/config/feature_flags_test.dart
```

Backend sáv (a gate Python-ága, külön processzként):

```bash
cd backend && python -m pytest tests/test_settings.py -q
```

## 8. Implementációs sorrend

1. `backend/app/config.py` — zárt `env` értékkészlet + fail-closed production/staging validáció.
2. `backend/tests/test_settings.py` — az A1–A4 cellák.
3. `lib/app/config/app_config.dart` — a kliens-oldali kiegészítés (staging endpoint + Lab-token kombináció).
4. `test/app/app_config_test.dart` — az A5 cella BŐVÍTÉSE.
5. `docs/release/environment-matrix.md`.
6. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **A csendes visszaesés.** A `dev` defaultra esés a legveszélyesebb hibaosztály: production deploy dev-titokkal (A1).
- **Az enum-bővítés csábítása.** Egy negyedik `AppEnvironment` érték a kör scope-ját sokszorosára tágítaná (§5.1, STOP-eset).
- **A meglévő fail-closed ágak regressziója.** A `resolve()` átrendezése észrevétlenül ejthet egy ágat (A5, A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
