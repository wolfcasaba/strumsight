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

## 11. Review — a Claude tölti ki
