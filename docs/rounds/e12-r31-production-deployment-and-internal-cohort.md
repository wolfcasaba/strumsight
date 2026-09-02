# E12-R31 — Production deployment és internal production cohort

- **Státusz:** ACTIVE — pre-flight elvégezve 2026-09-02, **§0.0.1 brief-revízióval** (P1–P7: két MÉRTEN hamis premissza javítva). Eredetileg előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 31
- **Kör-azonosító:** `E12-R31`
- **Branch:** `<motor>/e12-r31-production-deployment-and-internal-cohort`
- **Előfeltétel:** `E12-R30` merge-elve (feature freeze + zöld teljes regresszió)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör ellenőrzőlistát, füst-cellákat és döntési csomag-sablont szállít.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "production deployment internal cohort smoke signing fingerprint readiness"` → a `halts/round-status-E08-R15` és `E14-R01` merge-elt körök; release-domain előzmény nincs. A signing-oldali szerződés az ADR 0062 + a Kör 7 terméke.

> ✅ **Pre-flight ELVÉGEZVE (2026-09-02).** A két előírt mérés MEGTÖRTÉNT, és
> **mindkettő megcáfolta a brief állítását**: a fingerprint NEM kerül a
> provenance manifestbe (sidecar + proposal), és `/readyz` NEM létezik
> (a readiness `GET /health/ready`). A javítások a **§0.0.1** szakaszban —
> az implementer a §0.0.1-et tekintse a §2/§3/§6 fölé rendeltnek.

## 0.0 EMBERI KAPU

A production backend deploy és az app belső cohortra telepítése **user-művelet** (infrastruktúra-hozzáférés, titkok, store/telepítés). Az implementer terméke: a füst-teszt csomag, ami a deploy UTÁN futtatható és gépileg dönt, valamint a rollout-döntési csomag sablonja. A kör NEM deployol.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "docs/release/internal-production-checklist.md",
  "docs/release/rollout-packet-template.md",
  "tool/release/production_smoke.py",
  "backend/tests/test_production_smoke_contract.py",
  "test/tooling/production_readiness_test.dart",
  "docs/rounds/e12-r31-production-deployment-and-internal-cohort.md",
]
gate_tests = [
  "test/tooling/production_readiness_test.dart",
  "test/app/app_config_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a füst-csomag production endpointokkal és titkokkal dolgozik; egy hibás alapértelmezés (pl. Lab-endpoint a production profilban) valódi adatvédelmi és üzemeltetési hibát okozna. A `security-reviewer` futtatása a review-ban KÖTELEZŐ.

## 0.0.1 Pre-flight brief-revízió (orchestrátor, Claude, 2026-09-02)

A brief 2026-08-27-én készült `main @ 9ca4a0dc`-re. A kötelező pre-flight
(prompt §1: „a táblát mértem, nem a tényleges utat") **két állítást MÉRTEN
megcáfolt**, továbbá négy ponton az útvonalak/mezőnevek kiméréssel
pontosíthatók. A revízió a mércét NEM lazítja és az engedélyezett-fájllistát
NEM tágítja — csak a hamis premisszákat cseréli mért tényre.

**Visszakeresés (ADR 0312, szűkítve → teljes):** `lessons,halts,adr` ágon
`halts/round-status-E12-R27`, `halts/round-status-E12-R29`, `adr/0449`,
`adr/0486` (a release-manifest a füst-eszközök EGYETLEN igazságforrása),
`lessons/L34` (a secret-scan a megőrzött configra is terjed ki),
`lessons/L220` (jelöletlen fixture-literál → secrets-lelet). Teljes korpuszon
a `sdd/12-release-roadmap-final-integration.md#77` (**§26.1 Rollout decision
packet**) — az A6 sablonjának mért forrása.

### P1 — `/readyz` NEM létezik; a readiness a `GET /health/ready` *(a §2 állítása HAMIS)*

Mérve: `grep -rn "readyz" backend/` → **0 találat**. A Kör 8 (E12-R08) a §0.0
R1-ben kifejezetten ELVETETTE az új útvonalat, és az
[ADR 0449](../adr/0449-staging-readiness-traffic-gate-and-recovery.md) 143. sora
ezt döntésként rögzíti („Új `/readyz` végpont. **Elutasítva**"). A tényleges
readiness `backend/app/main.py:234` — `GET /health/ready`, ami nem-készen
`503 {"status": "not_ready", "reason": …}`, készen `200 {"status": "ready"}`.
**Ahol a brief `/readyz`-t mond, ott `GET /health/ready` értendő.**

Kapcsolódó mért részlet, amit a füst-csomagnak kezelnie KELL: az ADR 0449 D1
forgalmi kapuja (`_traffic_gate`, `main.py:115–131`) `env ∈ {staging, prod}`
alatt **minden üzleti végpontot** `503 not_ready`-vé tesz, amíg a migrációs fej
el nem tér. Ez tehát NEM az üzleti végpont hibája — a füst-csomag a `503` +
`{"status": "not_ready"}` választ **külön kimeneti okként** jelentse, ne
általános hibaként. A `/health`, `/health/live`, `/health/ready` a kapun kívül
van (D2), ezért mindig elérhető.

### P2 — A fingerprint NINCS a release manifestben; sidecar JSON hordozza, és a workflow-lépés PROPOSAL *(a §2 állítása HAMIS)*

Kettős mérés:

1. `grep -n "fingerprint\|provenance\|manifest" .github/workflows/release-apk.yml`
   → **0 találat**. Sem a Kör 6 provenance-lépései, sem a Kör 7
   fingerprint-lépése nincs alkalmazva: mindkettő *proposal fragment*
   (`docs/release/workflows/release-apk-provenance.proposal.md`,
   `…/release-apk-fingerprint.proposal.md`), mert a `.github/workflows/**` a
   mérce védett zónája (ADR 0321 `PROTECTED_GLOBS`). Az alkalmazás merge UTÁNI
   orchestrátori/emberi lépés.
2. `tool/generate_release_manifest.dart:247–268` — a manifest kulcsai
   `schemaVersion`, `app{version,buildNumber,shortSha,channel}`,
   `modelPackage`, `knowledgePackage`, `artifacts[]`. **Nincs benne
   certificate/signing mező**, és az
   [ADR 0448](../adr/0448-production-signing-policy-and-secret-hardening.md) D4
   ezt SZÁNDÉKOS döntésként rögzíti: a fingerprint **sidecar** fájlba megy.

A sidecar mért alakja (a proposal 108–112. sora) pontosan két kulcs:

```json
{ "keyAlias": "<alias>", "sha256Fingerprint": "<AA:BB:…>" }
```

**Az A4 újraalapozása:** a füst-csomag NEM a release manifesttel veti össze a
fingerprintet (ott nincs ilyen mező), hanem a **`dist/signing-certificate.json`
sidecarral**, a VÁRT értéket paraméterből kapva:

```
--signing-certificate <útvonal> --expected-fingerprint <SHA-256>
```

Egyezés → 0; eltérés, hiányzó `sha256Fingerprint` kulcs, vagy nem-parszolható
sidecar → **nem-nulla kilépés**. A „csak létezést néz, egyezést nem"
gyengítést az A4 cellája továbbra is pirosra váltja. A manifest-kötés
(`--artifact dist/signing-certificate.json`) dokumentált follow-up, NEM ennek a
körnek a scope-ja.

### P3 — A „Lab-route" mért hármasa (az A2 legacy referenciája)

Az [ADR 0061](../adr/0061-lab-route-isolation-and-hardened-diagnostics.md) D2
szerint prodban a Lab-felület nem „tiltott", hanem **nem létezik** (404), a
`diagnostics_enabled` / `apk_download_enabled` `Settings`-flagek vezérlik
(`main.py:185`, `main.py:244`). A már shippelt legacy referencia
`backend/tests/test_hardening.py::TestProdHardening::test_prod_defaults_do_not_register_lab_routes:98–113`,
és a mért hármas pontosan:

| Próba | Elvárt prodban |
|---|---|
| `POST /diagnostics` | `404` |
| `GET /diagnostics/health` | `404` |
| `GET /download` | `404` |

**A2 pontosítva:** ha a célon a fenti három bármelyike **nem** `404`, a
füst-csomag nem-nulla kilépéssel áll meg. A `test_hardening.py`-t átírni
TILOS (tilos zóna) — az új szerződés-teszt vele EGYETÉRTVE, önálló cellákban
mér.

**Valódi-sértés próba (a §6.1-ben előírt) mért fixture-e:** a szomszédos
`test_prod_lab_routes_can_be_enabled_from_environment:115–123` mutatja, hogyan
kapcsolható be a Lab-felület (`STRUMSIGHT_DIAGNOSTICS_ENABLED=true`,
`STRUMSIGHT_APK_DOWNLOAD_ENABLED=true`, `STRUMSIGHT_DIAG_TOKEN=…`). A próbában
EZT a felállást állítsd elő a szerződés-teszt saját fixture-jében → az A2
cellának PIROSNAK kell lennie → állítsd vissza.

### P4 — A modell-manifest BUNDLED ASSET, nem HTTP-végpont

Mérve: `grep -rn "model_manifest" backend/app` → **0 találat**; a fájl
`assets/ml/model_manifest.json`, integritását a már futó
`test/tooling/ml_asset_manifest_test.dart` őrzi. A §3 „modell-manifest elérés"
pontja ezért **nem** hálózati próba: a füst-csomag a *lokálisan átadott
artefaktum-fa* meglétét és parszolhatóságát ellenőrzi
(`--asset-root <útvonal>`, default a repógyökér), HTTP-hívás nélkül.
Hálózati modell-manifest-fetch implementálása **scope-sértés** lenne.

### P5 — A füst-csomag által hívott végpontok MÉRT útvonalai

| Cél | Mért útvonal | Forrás |
|---|---|---|
| readiness | `GET /health/ready` | `main.py:234` |
| auth (bejelentkezés) | `POST /auth/login` | `routers/auth.py:51` |
| auth (token-ellenőrzés) | `GET /auth/me` | `routers/auth.py:65` |
| settings-sync olvasás | `GET /settings` | `routers/settings.py:23` |
| community-olvasás | `GET /community/feed` | `community/routers/feed.py:173` |

Kitalált útvonal használata (pl. `/api/v1/…`) az A1/A2 cellák sértése.

### P6 — Az A6 sablonja az SDD §26.1 gépi tükre

A `docs/sdd/12-release-roadmap-final-integration.md` §26.1 („Rollout decision
packet") **kilenc** kötelező elemet sorol: build és commit · active flags ·
migration version · model version · known issues · dashboard snapshot ·
support readiness · rollback target · döntéshozó. Az A6 minimuma
(rollback-cél + döntéshozó) marad a mérce, de a sablon **mind a kilencet**
tartalmazza, és a `production_readiness_test.dart` cellája mind a kilenc
szakasz jelenlétét méri — így a sablon nem sodródhat el az SDD-től.

### P7 — Nincs ADR, és ez a revízió sem indokol újat

A §5 szándéka változatlan: a kör három kötött szabályt szállít, nem új
architekturális döntést. A P1–P6 kizárólag **hamis premisszát cserél mért
tényre** a kör saját, még nem merge-elt briefjében (prompt §2, első
felsorolás), ezért ADR-t nem igényel, és a `docs/adr/**` tilos zóna marad.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha egy ellenőrzőlista-pont csak élő production hozzáféréssel dönthető el, azt a lista EMBERI lépésként jelölje — az implementer nem szimulálhat production futást.

## 1. Cél

A production környezet és a belső cohort validálása gépileg futtatható füst-csomaggal és auditálható rollout-döntési csomaggal — publikus felhasználó nélkül.

## 2. Jelenlegi állapot — mért tények

- A production kliens-konfiguráció fail-closed (`lib/app/config/app_config.dart`, `resolve()`), a Lab-mód production artefaktumban tiltott, és a HTTPS / loopback-host / `staging`-host / dev-diag-token tiltások is ott élnek.
- A backend readiness (**`GET /health/ready`**, Kör 8 — `/readyz` NEM létezik, §0.0.1 P1) a migrációs fejre mér; a staging deploy-lépések a `docs/operations/backend-deploy.md`-ben.
- A production signing fail-closed (Kör 7), a fingerprint azonban a **`dist/signing-certificate.json` sidecarban** él, NEM a release manifestben, és a workflow-lépés egyelőre **proposal** (§0.0.1 P2).
- Élő production backend MA nincs — a füst-csomag ezért URL-paraméteres, és lokálisan a staging profilra futtatható.
- `docs/release/rollout-packet-template.md` **nincs**.

## 3. Scope

**Benne van:** `tool/release/production_smoke.py` (paraméteres cél-URL; readiness `GET /health/ready`, auth `POST /auth/login` + `GET /auth/me`, sync `GET /settings`, community-olvasás `GET /community/feed` — a MÉRT útvonalak a §0.0.1 P5-ben; a modell-manifest **lokális artefaktum**-ellenőrzés, nem HTTP-fetch, §0.0.1 P4; a Lab-route hármas JELENLÉTÉNEK tiltása, §0.0.1 P3; a fingerprint egyezésének ellenőrzése a **sidecar** `signing-certificate.json`-nal, §0.0.1 P2) · `backend/tests/test_production_smoke_contract.py` (a füst-csomag által hívott végpontok szerződésének cellái, lokálisan) · `test/tooling/production_readiness_test.dart` (a kliens production profil ellenőrzései: nincs Lab-endpoint, nincs dev token) · `docs/release/internal-production-checklist.md` (gépi és EMBERI pontok szétválasztva) · `docs/release/rollout-packet-template.md` (mit tartalmaz egy rollout-döntés: build, flag-profil, mérések, rollback-cél, döntéshozó).

**NINCS benne (tilos):**

- Tényleges deploy, titok-kiosztás vagy telepítés.
- `lib/**`, `backend/app/**`, `.github/**` módosítás.
- Production titok bármilyen formában a repóban.
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `tool/release/production_smoke.py` | ÚJ — a füst-csomag |
| `backend/tests/test_production_smoke_contract.py` | a végpont-szerződés cellái |
| `test/tooling/production_readiness_test.dart` | a kliens-profil cellái |
| `docs/release/internal-production-checklist.md` | ÚJ — ellenőrzőlista (gépi/emberi bontásban) |
| `docs/release/rollout-packet-template.md` | ÚJ — döntési csomag sablon |

**Tilos zóna:** `lib/**` · `backend/app/**` · `.github/**` · `android/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések

Nincs ADR. Három kötelező szabály:

### 5.1 A füst-csomag SOSEM tartalmaz titkot

A hitelesítés paraméterből/környezetből jön, és a kimenet maszkolt. **NEM elfogadható gyengítés:** „teszt-jelszó" beégetése.

### 5.2 A Lab-útvonal JELENLÉTE production célon HIBA

A füst-csomag pozitívan ellenőrzi, hogy a Lab-route NEM elérhető (ADR 0061). **NEM elfogadható gyengítés:** csak a kliens-oldali tiltásra hagyatkozás.

### 5.3 Az ellenőrzőlista megkülönbözteti a gépi és az emberi pontot

**NEM elfogadható gyengítés:** minden pont „automatikus"-ként jelölése, amikor a fele emberi hozzáférést igényel.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A füst-csomag paraméteres célon fut, titok nélkül, maszkolt kimenettel | `production_readiness_test.dart` + a §7 lokális futás |
| A2 | A `POST /diagnostics`, `GET /diagnostics/health`, `GET /download` hármas bármelyikének 404-től eltérő válasza a célon → nem-nulla kilépés (§0.0.1 P3) | `test_production_smoke_contract.py` |
| A3 | A kliens production profil nem tartalmaz dev tokent és dev hostot | `production_readiness_test.dart` (a MEGLÉVŐ `app_config_test` cellái mellett) |
| A4 | A fingerprint eltérése a **sidecar** `signing-certificate.json`-tól (vagy hiányzó `sha256Fingerprint` kulcs) → nem-nulla kilépés (§0.0.1 P2) | `production_readiness_test.dart` |
| A5 | Az ellenőrzőlista minden pontja meg van jelölve gépi vagy EMBERI címkével | a dokumentum + a teszt cellája |
| A6 | A rollout-csomag sablonja tartalmazza az SDD §26.1 mind a **kilenc** elemét, köztük a rollback-célt és a döntéshozót (§0.0.1 P6) | a sablon + a teszt cellája |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A füst-csomag beégetett hitelesítéssel dolgozik | A1 |
| A Lab-route ellenőrzés kimarad, vagy csak a három útvonal EGYIKÉT nézi | A2 |
| A fingerprint-ellenőrzés csak létezést néz, egyezést nem | A4 |
| A fingerprint-ellenőrzés hiányzó `sha256Fingerprint` kulcsnál 0-val lép ki (fail-OPEN) | A4 |
| Az ellenőrzőlista minden pontot automatikusnak jelöl | A5 |
| A rollout-sablon az SDD §26.1 kilenc eleméből kevesebbet tartalmaz | A6 |
| A füst-csomag a modell-manifestet HTTP-n kéri le | A1 (scope-sértés, §0.0.1 P4) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** a
`test_production_smoke_contract.py` SAJÁT fixture-jében kapcsold be a
Lab-felületet a §0.0.1 P3-ban mért módon
(`STRUMSIGHT_DIAGNOSTICS_ENABLED=true`, `STRUMSIGHT_APK_DOWNLOAD_ENABLED=true`,
`STRUMSIGHT_DIAG_TOKEN=<nem-dev érték>`), futtasd a §7 backend sávot → az
**A2** cellának PIROSNAK kell lennie → állítsd vissza. A
`backend/tests/test_hardening.py` átírása TILOS (tilos zóna).

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/production_readiness_test.dart test/app/app_config_test.dart
```

Backend sáv (külön processzként):

```bash
cd backend && python -m pytest tests/test_production_smoke_contract.py -q
```

## 8. Implementációs sorrend

1. `tool/release/production_smoke.py` (paraméteres, titok nélkül).
2. `backend/tests/test_production_smoke_contract.py`.
3. `test/tooling/production_readiness_test.dart`.
4. `docs/release/internal-production-checklist.md` (gépi/emberi bontás).
5. `docs/release/rollout-packet-template.md` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Titok a repóban.** A füst-csomag a legvalószínűbb hely, ahol egy „ideiglenes" jelszó megragad (A1).
- **Lab-szivárgás productionben.** ADR 0061 közvetlen sértése (A2).
- **Emberi lépés eltakarása.** Egy „minden automatikus" lista hamis készenlétet mutat (A5).

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** Claude Sonnet 5 (`sonnet-impl`), 2026-09-02.

### 10.1 Mit épített

- **`tool/release/production_smoke.py`** (ÚJ) — paraméteres, titok nélküli
  füst-csomag. Nyolc független ellenőrzés fut minden hívásban (egy bukása
  nem hagyja ki a többit): `readiness` (`GET /health/ready`, §0.0.1 P1),
  `auth_login`/`auth_me` (`POST /auth/login` + `GET /auth/me`), `settings`
  (`GET /settings`), `community_feed` (`GET /community/feed` — 200 VAGY 404
  egyaránt „elérhető és helyesen kapuzott", mert a mai fán a Community
  router NINCS bekötve `main.py`-ba, tehát mindig 404-et ad, ld. 10.4),
  `lab_routes_absent` (a P3 hármas mind 404, §0.0.1 P3), `fingerprint` (a
  sidecar `dist/signing-certificate.json` `sha256Fingerprint` kulcsa
  egyezik `--expected-fingerprint`-tel, fail-closed a hiányzó kulcsra is,
  §0.0.1 P2), `model_manifest` (`--asset-root`/`assets/ml/model_manifest.json`
  létezik és parszolható, LOKÁLIS ellenőrzés, nincs HTTP-hívás, §0.0.1 P4).
  A jelszó KIZÁRÓLAG a `--password-env`-ben megnevezett környezeti
  változóból jön (nincs `--password` CLI-kapcsoló); a kimenet minden sora
  `[PASS]`/`[FAIL] <check>: <részlet>` alakú, és sosem tartalmazza a
  jelszót/tokent. Egy `GET /health/ready` 503 `{"status":"not_ready",...}`
  válasza (ADR 0449 D1 forgalmi kapu) az üzleti végpontok ellenőrzésén
  KÜLÖN kimeneti okként jelenik meg (`"traffic gate active (not_ready): …"`),
  nem általános `"unexpected status 503"`-ként. Standard library only
  (`urllib.request`), a `tool/release/verify_signing_policy.py` precedense
  szerint. Kilépési kód: 0 minden cella zöld, 1 legalább egy cella piros, 2
  használati hiba (pl. hiányzó `--password-env` érték).
- **`backend/tests/test_production_smoke_contract.py`** (ÚJ) — a füst-eszköz
  `run_checks()`/egyedi `check_*` függvényeit hívja közvetlenül, egy valódi
  `fastapi.testclient.TestClient`-tel egy migrált, prod-profilú
  `create_app()` app körül (nincs hálózat). 12 cella: a teljes A1 lefutás
  egy frissen migrált prod appon (mind a nyolc check zöld), a readiness/
  forgalmi-kapu külön-kimeneti-ok próba, az A2 alapértelmezett-404 próba, a
  §6.1/§7 KÖTELEZŐ valódi-sértés próba (ld. 10.3), és a fingerprint/model-
  manifest offline cellák (egyezés, eltérés, hiányzó kulcs, hiányzó/érvénytelen
  fájl).
- **`test/tooling/production_readiness_test.dart`** (ÚJ) — 16 cella öt
  csoportban: A1 (nincs `--password` kapcsoló a forrásban; hiányzó env-var
  → nem-nulla kilépés hálózati kísérlet nélkül; egy megkülönböztető jelszó
  SOSEM jelenik meg sem a stdoutban, sem a stderrben), A3 (a kliens
  `AppConfig.resolve` production + dev host + dev token esetén MINDKÉT okra
  dob — kiegészítve, nem duplikálva a meglévő `app_config_test.dart`-ot),
  A4 (a füst-eszköz CLI-jén keresztül: egyező sidecar → PASS, eltérő →
  FAIL „mismatch"-sel, hiányzó `sha256Fingerprint` kulcs → FAIL ÉS nem-nulla
  kilépés — explicit próba a fail-OPEN regresszió ellen, §6.1 mátrix —,
  parszolhatatlan JSON → FAIL), A5 (a checklist minden sora `**[GÉPI]**`
  vagy `**[EMBERI]**` címkét visel — számlálásos + két mutáció-próba), A6
  (a rollout-sablon mind a kilenc §26.1 fejlécet tartalmazza a mért
  sorrendben, a Rollback target és a Döntéshozó szakasz nem üres).
- **`docs/release/internal-production-checklist.md`** (ÚJ) — 16 sor,
  mindegyik `**[GÉPI]**`/`**[EMBERI]**` címkével, négy szakaszban (deploy
  előtt, deploy utáni automatikus füst-teszt, deploy utáni emberi döntési
  pontok, piros füst-teszt esetén a teendő).
- **`docs/release/rollout-packet-template.md`** (ÚJ) — az SDD §26.1 mind a
  kilenc eleme saját `## N. <cím>` szakaszként, helykitöltő tartalommal.

### 10.2 A §6 két gate-sávjának TÉNYLEGES kimenete

**Backend sáv** (`cd backend && python -m pytest
tests/test_production_smoke_contract.py -q`, `/home/ubuntu/music-theory/
backend/.venv/bin/python` — a boxon nincs `backend/.venv`, ld. 10.5):

```
............                                                             [100%]
```

12/12 zöld. `ruff format --check backend/app backend/tests` és `ruff check
backend/app backend/tests` is zöld (mindkettő lefutott a commit előtt, a
záró-sorrend §3 pontja szerint).

**Kliens sáv** (`tools/round-gate.sh test/tooling/production_readiness_test.dart
test/app/app_config_test.dart`): a teljes gate (format → analyze → mindkét
teszt-útvonal külön → architecture → secrets → l10n → backend ruff × 2 →
backend pytest teljes suite) **ZÖLD** — a `flutter test
test/tooling/production_readiness_test.dart` önmagában 16/16, a
`test/app/app_config_test.dart` a meglévő cellákkal érintetlen (a kör nem
módosította).

### 10.3 A §7 valódi-sértés próba MÉRT eredménye

`test_production_smoke_contract.py::test_real_breach_probe_lab_surface_enabled_turns_the_check_red`
egy migrált, prod-profilú appon `STRUMSIGHT_DIAGNOSTICS_ENABLED=true`,
`STRUMSIGHT_APK_DOWNLOAD_ENABLED=true`, `STRUMSIGHT_DIAG_TOKEN=a-real-deploy-
diagnostics-token` mellett futtatja a `check_lab_routes_absent`-et — a
`backend/tests/test_hardening.py::test_prod_lab_routes_can_be_enabled_from_environment`
mért felállását ismételve, azt a fájlt NEM módosítva.

**MÉRT kimenet (piros cella: `lab_routes_absent`):**

```
OK= False
DETAIL= POST /diagnostics: expected 404, got 401; GET /diagnostics/health: expected 404, got 200
```

`POST /diagnostics` 401-et ad (nincs `X-Diag-Token` fejléc a próbahívásban —
`routers/diagnostics.py:126-134`), `GET /diagnostics/health` 200-at (az a
végpont tervezetten hitelesítés nélküli — `routers/diagnostics.py:111-116`).
`GET /download` a próbában továbbra is 404 marad (nincs `STRUMSIGHT_APK_PATH`
staged fájl — `main.py`'s `download_apk()` handler), de ez nem menti meg a
cellát: az aggregált `check_lab_routes_absent` BÁRMELYIK nem-404 választ
elégségesnek tekinti a bukáshoz, így az A2 cella a mérce-mátrix szerint
PIROS. A próba után a környezeti változók (`monkeypatch`) automatikusan
visszaállnak — nincs maradó állapot.

### 10.4 Mért eltérés a §0.0.1 P5-től, amit dokumentálni kell

A P5 tábla a `GET /community/feed`-et a mai fán definiált végpontként
nevezi meg (`community/routers/feed.py:173`), de a `backend/app/community/
__init__.py:50-59` docstringje szerint ennek a routernek a `create_app()`-ba
kötése **egy jövőbeli kör** feladata — a mai `backend/app/main.py` a
Community routert EGYÁLTALÁN NEM regisztrálja. Emiatt `GET /community/feed`
a mai fán MINDIG 404-et ad, függetlenül a `community_enabled` flagtől. A
füst-eszköz `community_feed` cellája ezt tudottan kezeli: 200 ÉS 404 is
elfogadott, így a cella ma és a Community router bekötése UTÁN is helyesen
validál, kód-módosítás nélkül — de ez a kör NEM köti be a Community routert
(tiltott zóna, `backend/app/main.py`). **A javító kör (MINOR-2, §10.7)
pontosította a 404-ág szövegét**: a `"reachable and correctly gated"` állítás
egy nem-bekötött routerről tévesen sugallt elérhetőség-mérést — a mostani
szöveg (`"404 — either not registered on this deploy, or registered and
correctly gated…"`) kimondja, hogy egy státuszkódból a két eset nem
megkülönböztethető.

### 10.5 Mért eltérés a briefben feltételezett paranccsortól

A brief §6 backend-parancsa `python -m pytest`-et ír; ezen a boxon
`python` NINCS a PATH-on (csak `python3`), és a munkapéldányban nincs
`backend/.venv`. A `tools/round-gate.sh` maga is a megosztott
`$HOME/music-theory/backend/.venv/bin/python`-t keresi és találja meg
(`resolve_backend_python()`), és a záró gate ezt sikeresen használta — az
implementáció maga NEM tartalmaz ilyen feltételezést (a smoke-eszköz és a
kontraktus-teszt egyaránt sima `python3`/a hívó interpretere alatt fut).

### 10.6 Amit ez a kör NEM csinált (scope-on kívül, brief §3)

Nincs tényleges deploy, titok-kiosztás vagy telepítés. A fingerprint- és
provenance-workflow lépések továbbra is *proposal* állapotban vannak
(`docs/release/workflows/*.proposal.md`) — alkalmazásuk `.github/workflows/**`-t
érintené, ami tiltott zóna. A `docs/adr/**` érintetlen (nincs új ADR, §0.0.1
P7).

### 10.7 Javító kör (`docs/reviews/e12-r31-review.md`, CHANGES REQUESTED) — MÉRT bizonyíték

Az implementer ugyanaz (`sonnet-impl`), ugyanezen az ágon. A négy KÖTELEZŐ
lelet (MAJOR-1, MAJOR-2, MAJOR-3, MINOR-3) és mindhárom OLCSÓ MINOR (MINOR-1,
MINOR-2, MINOR-4) javítva.

**MAJOR-1 — `/download` fail-open javítva, MÉRT RED→GREEN.** A
`_LAB_ROUTES`-hoz egy `("POST", "/download")` rossz-metódus próba került
(`production_smoke.py`): egy valóban hiányzó route minden metódusra 404-et
ad, de egy regisztrált-de-nincs-staged-APK route (`apk_download_enabled=True`,
nincs `STRUMSIGHT_APK_PATH`) a GET-en 404-et, POST-on viszont 405-öt —
ezt a `check_lab_routes_absent` most FAIL-ként kezeli. Új, IZOLÁLT
contract-cella (`test_apk_download_enabled_alone_turns_the_check_red`) —
KIZÁRÓLAG `apk_download_enabled=True`-t kapcsol be, a `diagnostics_enabled`
prod-alapértéken (False) marad, tehát a `/diagnostics` lábak NEM
pirosíthatják a cellát (explicit `assert "/diagnostics" not in result.detail`).
Kézzel mérve a javítás előtti kóddal (a `("POST", "/download")` bejegyzés
ideiglenesen kivéve): a cella **PIROS** (`AssertionError: assert True is
False`); visszaállítva: **13/13 ZÖLD**
(`backend/tests/test_production_smoke_contract.py`).

**MAJOR-2 — a szivárgás-cella most ténylegesen a sikeres bejelentkezési ágat
futtatja, MÉRT mutáció-kill RED→GREEN.** A `test/tooling/
production_readiness_test.dart`-ban egy ÚJ, önálló csoport
(`MAJOR-2 (review E12-R31) …`) egy lokális stub-backendet indít, és a
füst-eszközt VALÓDI sikeres `POST /auth/login`-nal futtatja ellene (a
korábbi elérhetetlen-portos cella ezt sosem érte el). **Mért környezeti
korlát**, amiért a stub NEM `dart:io HttpServer.bind` (a review javaslata
szerinti közvetlen alak): ezen a boxon egy a Dart tesztfolyamatban közvetlenül
kötött socket **nem érhető el** a `_run` által indított `python3`
alfolyamatból — direkt próbával mérve (`curl`/`python3` gyermekfolyamat 5s
timeout-tal fut le egy szülő-Dart-folyamat saját maga kötötte porton, a
Bash-sandbox kikapcsolásával is), miközben KÉT, egyaránt alfolyamatként
indított `python3` (szerver + kliens, egymás testvérei) simán eléri egymást.
A stub ezért egy `python3 -c <script>` alfolyamat (`_startStubServer`
`Process.start`-tal), amit a `_run`-nal indított füst-eszköz testvér-
alfolyamatként ér el. **Mutáció-kill próba (a §10-ben előírt önellenőrzés,
ténylegesen elvégezve):** a `check_auth` sikerágába (`production_smoke.py`,
a `login_result = CheckResult("auth_login", True, "ok")` sor után) ideiglenesen
beszúrt `print(f"[DEBUG] logged in as {email} with {password} -> {token}")`
mellett az ÚJ cella futtatva **PIROS** lett:

```
Expected: not contains 'sentinel-password-must-never-leak-9f3c'
  Actual: '[DEBUG] logged in as smoke@strumsight.app with
           sentinel-password-must-never-leak-9f3c ->
           sentinel-bearer-token-must-never-leak-7a1d\n' …
```

— mind a jelszó-, mind a token-sentinel megjelent (a `print` a valóságban
mindkettőt kiírta volna). A `print` eltávolítása után a cella **ZÖLD**
(`flutter test test/tooling/production_readiness_test.dart --plain-name
"ACTUALLY logs in"` → `+1: All tests passed!`). A cella emellett explicit
szondázza, hogy a sikerág TÉNYLEG lefutott (`[PASS] auth_login:` /
`[PASS] auth_me:` a kimenetben) — enélkül a sentinel-hiány üres állítás
lenne. A régi elérhetetlen-portos cella megmaradt, de átnevezve arra, amit
ténylegesen mér (offline sanity, nem a sikeres bejelentkezés próbája).

**MAJOR-3 — `https` kikényszerítés, fail-closed exit 2, MÉRT.** `main()`-ben
egy `_https_scheme_error()` séma-ellenőrzés fut a jelszó-env-ellenőrzés UTÁN,
de MINDEN hálózati hívás ELŐTT: nem-`https` séma (és nincs
`--allow-insecure-http`) → `exit 2`, strukturált stderr-üzenettel, `run_checks`
SOSEM hívódik meg (nincs se helyi, se hálózati próba). Új `--allow-insecure-
http` kapcsoló lokális/staging futtatáshoz. Három ÚJ Dart-cella
(`MAJOR-3 …` csoport) mind ZÖLD: sima `http://` → exit 2 + `"https"` a
stderr-ben + üres stdout (egyetlen check-sor sem íródott ki); `--allow-
insecure-http` mellett a kilépés `isNot(2)` (a hálózati hiba miatt 1-re vált,
nem 2-re — bizonyítva, hogy túljutott a séma-kapun); `https://` cél
opt-out nélkül is túljut a séma-kapun. A meglévő `_unreachableBaseUrl`-t
használó cellák (A1, A4) mind kaptak `--allow-insecure-http`-t, különben a
séma-kapu MINDEGYIKÜKET usage-errorra váltaná még a próba előtt — ez a NOTE-1-et
is lezárja (a séma nélküli `--base-url` mostantól strukturált exit 2, nem
csupasz `ValueError`-traceback). A checklist §2 sora mostantól `https://
<production-hosztnév>`-t ír elő, és explicit figyelmezteti, hogy
`--allow-insecure-http` production célon SOSEM használandó.

**MINOR-3 — a docstring most a MÉRT tulajdonságot állítja.** A „prints one
masked PASS/FAIL line" mondat lecserélve: a valós, tesztelt tulajdonság,
hogy egy hitelesített végpont BODY-ja sosem kerül kiírásra (csak
státuszkód/`reason`/`status`), és hogy a `--base-url`-nek `https`-nek kell
lennie.

**MINOR-1 (olcsó, elvégezve) — redirect-védelem.** `_NoRedirectHandler`
(`urllib.request.HTTPRedirectHandler` alosztály, `redirect_request` `None`-t
ad vissza) + `urllib.request.build_opener` — egy 3xx válasz mostantól saját
státuszkódként bukik (`"unexpected status 3xx"`), nem követi az `urllib` a
redirectet más hostra az `Authorization` fejléc/jelszó-body megtartásával.

**MINOR-2 (olcsó, elvégezve) — `community_feed` szöveg pontosítva.** A 404-ág
mostantól kimondja, hogy egy státuszkódból nem dönthető el „nincs bekötve" vs
„bekötve és helyesen kapuzott ehhez a fiókhoz” — nem állítja többé, hogy
„reachable”. A 200-ág változatlanul „reachable and correctly gated (status
200)”.

**MINOR-4 (olcsó, elvégezve) — a fájl-szintű secret-marker eltávolítva.** A
három érintett literál (`_SMOKE_PASSWORD`, két `secret_key=`/`diag_token=`
fixture) `fake-` prefixet kapott; a `strumsight:allow-secret-file` sor
törölve. Mérve: `dart run tool/ci/check_secrets.dart` a marker nélkül is
**0 finding** (4176 fájl), és a backend-suite (13/13) és a `ruff format`/
`ruff check` (mindkettő zöld, a formázó 1 fájlt újraformázott a hosszú
`assert`-sor miatt) is változatlanul zöld.

**A §7 két gate-sávjának TÉNYLEGES kimenete (javító kör után):**

Backend sáv (`cd backend && python -m pytest
tests/test_production_smoke_contract.py -q`, `/home/ubuntu/music-theory/
backend/.venv/bin/python`):

```
.............                                                            [100%]
```

13/13 zöld (a MAJOR-1 izolációs cellával eggyel több, mint a §10.2-ben mért
12). `ruff format --check backend/app backend/tests` és `ruff check
backend/app backend/tests` is zöld.

Kliens sáv (`tools/round-gate.sh test/tooling/production_readiness_test.dart
test/app/app_config_test.dart`): `format` ZÖLD, `analyze` ZÖLD ("No issues
found!"), `test test/tooling/production_readiness_test.dart` **20/20 ZÖLD**
(a §10.2-ben mért 16 helyett — a MAJOR-2 stub-cella és a MAJOR-3 három
cellája új), `test test/app/app_config_test.dart` 21/21 ZÖLD (érintetlen),
`architecture` ZÖLD, `secrets` ZÖLD (0 finding, a MINOR-4 marker-eltávolítás
után is), `l10n` ZÖLD, `backend ruff format`/`ruff check` ZÖLD, **`backend
pytest` (a TELJES backend suite, mert a kör backendet is érint) ZÖLD**.

Az utolsó lépés első futása egy izolált leletet adott: `tests/community/
test_follow_service.py::test_swap_unique_constraint_breaks_a2` PIROS lett —
egy szál-verseny (`threading.Barrier`) időzítés-érzékeny regressziós teszt a
Community follow service-ben, amit ez a kör NEM érint (utoljára `1cc49e41`
E09-R07-ben módosítva, a jelen diff nem nyúl hozzá). A round-gate.sh HÁTTÉRBEN
futott, miközben PÁRHUZAMOSAN több `flutter test`-et is futtattam ellenőrzés
gyanánt (MAJOR-2/MAJOR-3 cellák, majd a mutáció-kill próba) — ez a CPU-
terhelés torzította a két szál ütemezését, és a teszt által vártan
egyidejűleg futó INSERT-ek NEM versenyeztek a szinkron ponton. Elszigetelten
lefuttatva (`pytest tests/community/test_follow_service.py::
test_swap_unique_constraint_breaks_a2 -q`) **ZÖLD** — megerősítve, hogy nem
regresszió. A `round-gate.sh`-t ezután MÉG EGYSZER, párhuzamos terhelés
nélkül lefuttatva mind a 10 lépés **ZÖLD** (`backend pytest` is), ez a
végleges, mérvadó futás.

## 11. Review — a Claude tölti ki
