# E01-R13 — Backend security és diagnosztikai elkülönítés

Státusz: PLANNING (pre-flight kész 2026-07-29, kód újraolvasva: `main` @ `5cfbfc7`)
SDD: docs/sdd/02-epic-01-core-platform.md § „Kör 13 — Backend security és diagnosztikai elkülönítés"
Branch: `codex/epic-01-round-13-backend-security`
Brief szerzője: Claude · Implementáció: Codex
**Előfeltétel: az R12 merge-ölve** — ✅ teljesült (PR #17, `d7cdca0`); a
route-regisztrációs flag a R12-es `create_app(settings)` mintára épül.

> ✅ **Pre-flight elvégezve (2026-07-29):** a §2 az R12 utáni `main` mért állapota;
> a kör felszívja az R12 review (docs/reviews/e01-r12-review.md) 3 MINOR
> follow-upját is (§3/§6).

## 1. Cél

A production account API és a fejlesztői Lab-infrastruktúra ma egyetlen appban,
feltétel nélkül él együtt: a diagnostics-upload és az APK-download route minden
környezetben regisztrálódik, a diag-token dev-defaulttal fut, az upload a teljes
payloadot memóriába olvassa, a bcrypt 72 bájtos korlátja pedig némán csonkol.
A kör kimenete: **flag-vezérelt Lab-route-regisztráció** (prodban alapból nincs),
**hardened token-kezelés**, **méretkorlátozott streaming upload atomikus írással**,
**byte-helyes jelszó-validáció** és a hozzájuk tartozó security-tesztek.

## 2. Jelenlegi állapot

Ténylegesen elolvasott kód (`backend/`, 2026-07-29, R12 UTÁNI `main` @ `5cfbfc7`):

- **`app/main.py`** (R12 átrendezte) — `create_app(settings: Settings | None)` a
  gyár; a `diagnostics` router (126–128. sor) és a `GET /download` (148–160. sor,
  a `create_app`-on belül inline definiált, `STRUMSIGHT_APK_PATH`-t közvetlenül
  `os.environ`-ból olvas) **feltétel nélkül, minden env-ben** regisztrálódik.
  A `_guard_prod(settings)` a dev-secretet, a wildcard-CORS-t és (R12 óta) a
  prod-SQLite-ot már tiltja — **ez kész**. Lifespan: dev-ben `create_all`,
  hibája `application.state.dev_schema_initialization_failed = True`-ba fut —
  **néma** (semmi nem olvassa, log sincs; R12 review MINOR-1, e kör dolga).
- **`app/config.py`** (R12) — `Settings` env-prefixszel (`STRUMSIGHT_`):
  env/secret_key/database_url/allow_sqlite_in_prod/cors_origins. Diagnostics
  flag, diag-token, diag-dir, max-bytes **nincs benne** — azok ma env-olvasások
  a routerben.
- **`app/routers/diagnostics.py`** —
  - token: `STRUMSIGHT_DIAG_TOKEN` env, default **`"strumsight-lab-dev"`**;
    összehasonlítás `!=`-vel (nem konstans idejű); a prod-guard a diag-tokenre
    **nem** terjed ki → prodban ma a dev-default token élne.
  - upload: `await request.body()` — a **teljes payload memóriába kerül**, a
    méret-ellenőrzés a beolvasás UTÁN fut (default limit 32 MB env-ből).
    Nincs streaming, nincs temp-fájl + atomikus rename; félbeszakadt kérésből
    nem marad temp, de túlméretes kérés memóriát eszik.
  - `_safe_id`: alfanumerikus+`-_` szűrés, 48 char cap, időbélyeg-prefix — path
    traversal ellen véd; **ütközés lehetséges** (azonos kliens-id ugyanabban a
    GMT-másodpercben felülír).
  - `index.jsonl` append hibája kezeletlen (dobna 500-at a sikeres session-írás után);
    adatkönyvtár env-ből (`STRUMSIGHT_DIAG_DIR`), fájljogosultság nem szűkített.
- **`app/security.py`** — `_to_bytes`: `password.encode("utf-8")[:72]` — **néma
  bájt-csonkolás**. A `UserCreate` `max_length=72` **karaktert** limitál, így egy
  többbájtos (pl. ékezetes/emoji) jelszó 72 karakter alatt is átlépheti a 72 bájtot
  → pont a §13.5-ben tiltott néma truncate történik.
- **`app/routers/auth.py`** — login: ismeretlen e-mail és rossz jelszó **azonos
  üzenetet** ad (§13.6 lényege kész); jelszó/token logolás nincs (nincs is logging).
  Rate limit: process-lokális `RateLimiter`, a korlátait a docstring dokumentálja;
  README-szintű üzemeltetési dokumentáció nincs.
- **Tesztek:** 44 passed a friss main-en. `test_hardening.py` fedi a
  prod-secret/CORS/SQLite guardot; diag-token rossz-token esete
  `test_diagnostics.py`-ban; streaming/traversal/72-byte esetek **nincsenek**.
  `test_prod_with_sqlite_without_explicit_permission_refuses_to_boot`
  (`test_hardening.py:103`) env-érzékeny: nincs
  `monkeypatch.delenv("STRUMSIGHT_ALLOW_SQLITE")`, exportált env mellett elhasal
  (R12 review MINOR-3).
- **R12 review follow-upok (mind e kör dolga):** MINOR-1 néma dev-`create_all`
  hiba (fent); MINOR-2 a `backend/README.md` nem mondja ki, hogy a nem stampelt
  dev DB readinesse tartósan `503 migration_mismatch`; MINOR-3 a fenti
  env-érzékeny teszt.

## 3. Scope

**Benne:**

- Route-regisztráció flag-vezérelten (`Settings`): `diagnostics_enabled` és
  `apk_download_enabled` — **prod env-ben default False**; a `create_app` csak
  akkor regisztrálja a diagnostics routert és a `/download`-ot, ha a flag igaz.
- Token-hardening: prod (vagy publikus Lab-deploy, azaz `diagnostics_enabled=true`
  + `env=prod`) esetén dev-default vagy üres token → **boot-hiba**; összehasonlítás
  `hmac.compare_digest`-tel; token soha nem kerül logba/válaszba.
- Streaming upload: `request.stream()` chunkolt olvasás, limit túllépésekor az
  olvasás megszakad (413), a payload nem gyűlik fel memóriában; írás temp-fájlba
  + siker esetén `os.replace` (atomikus); megszakadt feltöltés → temp törlése.
- Fájlrendszer: session-id ütközéskor egyedi suffix (nincs néma felülírás);
  adatkönyvtár a `Settings`-ből (env-kompatibilitás megtartva); fájlok 0o600;
  `index.jsonl` írási hibája kezelt (a session-fájl attól még megmarad, a válasz
  jelzi).
- Jelszó 72 **bájt** validáció: `UserCreate`-ben UTF-8 bájthossz-ellenőrzés
  (≤72 OK, >72 → 422); a néma csonkolás megszűnik az új regisztrációknál.
- Rate limiter korlátainak dokumentálása (README: single-process, multi-worker
  esetén nem megosztott, skálázásnál közös store kell).
- **R12 review MINOR follow-upok:** (1) a dev-`create_all` hibája a néma flag
  helyett `logging` warning-ot ad (lásd 5.7); (2) README-mondat a nem stampelt
  dev DB tartós `503 migration_mismatch` readinesséről; (3)
  `monkeypatch.delenv("STRUMSIGHT_ALLOW_SQLITE", raising=False)` a
  `test_prod_with_sqlite_without_explicit_permission_refuses_to_boot`-ba.
- A §„Kötelező tesztek" teljes listája (Lab-route hiánya prodban, hibás token,
  túl nagy payload, félbeszakadt upload, path traversal, 72/73 bájtos Unicode
  jelszó, azonos login-hiba, prod default-secret tiltás, wildcard-CORS tiltás —
  az utóbbi kettő már létező teszt, hivatkozni elég).

**Kívül (ebben a körben TILOS):**

- Redis / megosztott rate-limit store (dokumentálni kell, bevezetni nem).
- Alembic/schema változás (`models.py` érintetlen — nincs séma-igénye a körnek).
- A Flutter-oldali uploader (`lib/features/diagnostics/`) módosítása — a wire
  contract (POST /diagnostics, X-Diag-Token, gzip body) **változatlan marad**.
- Felhasználói auth a diagnosztikára (a token spam-gate marad, nem user-auth).
- CI workflow (Kör 15).

## 4. Engedélyezett fájlok

Csak az alábbi útvonalak módosíthatók. Bármi más → **MEGÁLLÁS és jelentés**.

| Útvonal | Miért |
|---|---|
| `backend/app/config.py` | diagnostics/apk-download flagek + diag-token/dir a Settings-be |
| `backend/app/main.py` | feltételes route-regisztráció + token boot-guard |
| `backend/app/routers/diagnostics.py` | streaming upload, atomikus írás, compare_digest, ütközéskezelés |
| `backend/app/schemas.py` | UserCreate 72-bájt validátor |
| `backend/app/security.py` | a néma `[:72]` csonkolás rendezése (lásd 5.5) |
| `backend/tests/test_diagnostics.py` | streaming/limit/traversal/ütközés tesztek |
| `backend/tests/test_hardening.py` | prod Lab-route-hiány + token-guard tesztek |
| `backend/tests/test_auth.py` | 72/73 bájt Unicode jelszó esetek |
| `backend/tests/test_migrations.py` | **csak** a MINOR-1 teszt (dev-`create_all` hiba → log, caplog-asszert) |
| `backend/README.md` | rate-limit üzemeltetési korlátok, Lab-deploy szabályok |
| `docs/rounds/e01-r13-backend-security-and-diagnostics.md` | **csak a 10. szekció** |

**Tilos zóna:** minden más — kiemelten `backend/alembic/**` és
`backend/app/database.py` (R12 eredménye), `backend/app/models.py`,
`lib/**`, `test/**`, `tool/**`, `.github/**`, `docs/**` (a fenti fájl §10-én
kívül), `HANDOFF.md`, ADR-ek.

## 5. Kötött architekturális döntések

Előre kiosztott ADR-szám: **`0061`** — az ADR-t Claude írja.

1. **A wire contract nem változik.** A Flutter-kliens (X-Diag-Token header, gzip
   body, 201 + `{status, session, bytes}`) módosítás nélkül működik tovább a
   Lab-env backenddel. Minden hardening a szerver oldalán történik.
2. **Regisztráció-szintű elkülönítés, nem 403.** Prodban a Lab route-ok **nem
   léteznek** (404), nem „tiltottak" — a felület el sem készül. Ezt teszt
   bizonyítja (`env=prod` app → `/diagnostics` és `/download` 404/405).
3. **Fail-closed token.** `diagnostics_enabled=true` + `env=prod` esetén a
   dev-default/üres token boot-hiba (a meglévő `_guard_prod` mintájára, ugyanoda);
   dev-ben a mai default marad (zero-setup boot nem törhet).
4. **Streaming limit a beolvasás KÖZBEN.** A limit túllépésekor a stream-olvasás
   megáll és 413 megy vissza; tilos a teljes body felolvasása a döntés előtt.
   A temp fájl a végleges névre `os.replace`-szel kerül; hibaágon a temp törlődik.
5. **Jelszó-csonkolás: regisztrációnál tilos, verifikációnál kompat.** A
   `UserCreate` 422-t ad >72 UTF-8 bájtra (néma csonkolás megszűnik). A
   `verify_password` bájt-levágása **megmarad** — a korábban (csonkolt jelszóval)
   regisztrált userek beléphetnek; ez dokumentálandó a security.py kommentjében.
   A login-schema szándékosan nem kap hossz-limitet.
6. **Rate limiter marad process-lokális.** Egyetlen uvicorn-process a célkörnyezet;
   a korlát dokumentáció, nem új infrastruktúra.
7. **MINOR-1 feloldása: log, nem readiness-átalakítás.** A lifespan dev-`create_all`
   hibaágán a néma `dev_schema_initialization_failed` flag megszűnik, helyette
   modul-szintű `logging.getLogger(__name__).exception(...)` (stderr-re jut).
   A readiness ok-kódjai NEM változnak (az a R12 tesztelt kontraktusa); teszt
   caplog-gal asszertálja a logot. A meglévő R12-tesztek átírása tilos —
   elbukó meglévő teszt = megállás és jelentés.

## 6. Acceptance criteria

- [ ] `env=prod` + default flagek: `/diagnostics`, `/diagnostics/health` és
      `/download` **nem regisztrált** (404) — teszt bizonyítja; dev-ben mind él.
- [ ] Prod + `diagnostics_enabled=true` + dev-default token → boot-hiba (teszt).
- [ ] Token-összehasonlítás `hmac.compare_digest`; a token nem szerepel se
      logban, se hibaválaszban (grep a diffben + teszt a 401 body-ra).
- [ ] Limit feletti upload: 413 úgy, hogy a szerver nem olvasta végig a bodyt
      (teszt: limitnél nagyobb streamelt kérés; memória-assert helyett a
      megszakítás ténye — pl. olvasott-bájt számláló seam — ellenőrzött).
- [ ] Félbeszakadt upload után nincs árva temp-fájl a data-dirben (teszt).
- [ ] Path-traversal kísérlet (`../`, abszolút path, URL-encoded) a data-dir-en
      kívül SOHA nem ír (teszt); session-id ütközésnél mindkét feltöltés megmarad.
- [ ] 72 bájtos Unicode jelszó regisztrál és belép; 73 bájtos (de ≤72 karakteres)
      jelszó 422-t kap (teszt mindkettőre).
- [ ] Ismeretlen e-mail és rossz jelszó login-válasza bájtra azonos (meglévő
      viselkedés — regressziós assert).
- [ ] MINOR-1: dev-`create_all` hiba → `logging` warning/exception a néma flag
      helyett; caplog-teszt bizonyítja; readiness ok-kódok változatlanok.
- [ ] MINOR-2: README kimondja, hogy a nem stampelt dev DB readinesse tartósan
      `503 migration_mismatch`, és mi a teendő (`alembic stamp head`).
- [ ] MINOR-3: a prod-SQLite tiltó teszt `delenv`-vel env-független; a suite
      exportált `STRUMSIGHT_ALLOW_SQLITE=true` mellett is zöld (bizonyíték:
      egy futás `STRUMSIGHT_ALLOW_SQLITE=true` env-vel).
- [ ] Mind a meglévő backend-teszt zöld (baseline: 44 passed); `git diff --stat
      main...` csak a §4 tábláját tartalmazza.

## 7. Kötelező ellenőrzések

Külön parancsokként (`AGENTS.md` §12):

```bash
cd backend
.venv/bin/python -m pytest -q
```

(Ezen a boxon nincs `python` a PATH-on — minden backend-parancs
`.venv/bin/python -m …`. A MINOR-3 bizonyítékhoz egy második, külön futás:
`STRUMSIGHT_ALLOW_SQLITE=true .venv/bin/python -m pytest -q`.)

Flutter-diff üres; a zöld gate-hez Claude dispatch-eli a `build-apk.yml`-t a
kör-branchre (ADR 0052) — a Codex ne hívjon `gh`-t.

## 8. Implementációs sorrend

1. `Settings`: flagek + diag-token/dir átemelése env-kompatibilisen.
2. `create_app`: feltételes regisztráció + token boot-guard; prod-route-hiány tesztek.
3. `diagnostics.py`: `compare_digest`, streaming olvasás limittel, temp+`os.replace`,
   ütközés-suffix, index-hiba kezelés, 0o600 — tesztekkel lépésenként.
4. `schemas.py` 72-bájt validátor + `security.py` komment/rendezés; auth-tesztek.
5. README (rate-limit + Lab-deploy szabályok) → §10 kitöltése.

## 9. Kockázatok

- **A box élő Lab-pipeline-ja.** A boxon futó uvicorn + cloudflared tunnel a
  meglévő dev-env viselkedésre épül (dev-token, mindig-regisztrált route-ok).
  A kör NEM változtathatja meg a **dev** default viselkedést (zero-setup boot,
  route-ok élnek) — különben a felhasználó Lab-APK-ja némán 404-et kapna.
- **Starlette stream-szemantika.** A `request.stream()` csak egyszer fogyasztható,
  és a kliens-megszakítás `ClientDisconnect`-et dob — a temp-takarítás `finally`-be
  való. Tesztben a TestClient nem tud valódi félbeszakítást — a megszakítást a
  stream-fogyasztó seam-jén (kivétel-injektálással) kell tesztelni, nem hálózaton.
- **Bájt- vs karakterhossz.** A pydantic `max_length` karakterben mér — a
  bájt-validátor NE cserélje le a meglévő 8-karakteres minimumot és a 72-es
  karakter-capet, hanem egészítse ki (a hibaüzenet különböztesse meg a két esetet).
- **R12-függés.** ✅ Feloldva a pre-flightban: az R12 a vártak szerint
  `create_app(settings)`-t adott; a `/download` a `create_app`-on belül inline
  route (nem külön router) — a feltételes regisztráció ezt is fedi.

## 10. Implementation handoff — a Codex tölti ki

- Fájlonkénti összefoglaló.
- Futtatott parancsok + TÉNYLEGES kimenet.
- Eltérések a tervtől és okuk.
- Nem futtatott ellenőrzések és okuk.
- Follow-up issue-k.

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e01-r13-review.md`
