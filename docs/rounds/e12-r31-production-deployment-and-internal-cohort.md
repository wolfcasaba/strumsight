# E12-R31 — Production deployment és internal production cohort

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 31
- **Kör-azonosító:** `E12-R31`
- **Branch:** `<motor>/e12-r31-production-deployment-and-internal-cohort`
- **Előfeltétel:** `E12-R30` merge-elve (feature freeze + zöld teljes regresszió)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör ellenőrzőlistát, füst-cellákat és döntési csomag-sablont szállít.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "production deployment internal cohort smoke signing fingerprint readiness"` → a `halts/round-status-E08-R15` és `E14-R01` merge-elt körök; release-domain előzmény nincs. A signing-oldali szerződés az ADR 0062 + a Kör 7 terméke.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd, hogy a Kör 7 fingerprint-mezője TÉNYLEGESEN bekerül-e a provenance manifestbe (a Kör 6/7 futásainak artefaktumában), és hogy a Kör 8 `/readyz` readiness-gate-je él-e. A füst-cellák EZEKRE hivatkoznak.

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

- A production kliens-konfiguráció fail-closed (`app_config.dart:131–168`), a Lab-mód production artefaktumban tiltott.
- A backend readiness (`/readyz`, Kör 8) a migrációs fejre mér; a staging deploy-lépések a `docs/operations/backend-deploy.md`-ben.
- A production signing fail-closed (`release-apk.yml` + `build.gradle.kts`, Kör 7), a fingerprint a provenance manifestben.
- Élő production backend MA nincs — a füst-csomag ezért URL-paraméteres, és lokálisan a staging profilra futtatható.
- `docs/release/rollout-packet-template.md` **nincs**.

## 3. Scope

**Benne van:** `tool/release/production_smoke.py` (paraméteres cél-URL; auth, readiness, sync, community-olvasás, modell-manifest elérés; Lab-route JELENLÉTÉNEK tiltása; a fingerprint egyezésének ellenőrzése a manifesttel) · `backend/tests/test_production_smoke_contract.py` (a füst-csomag által hívott végpontok szerződésének cellái, lokálisan) · `test/tooling/production_readiness_test.dart` (a kliens production profil ellenőrzései: nincs Lab-endpoint, nincs dev token) · `docs/release/internal-production-checklist.md` (gépi és EMBERI pontok szétválasztva) · `docs/release/rollout-packet-template.md` (mit tartalmaz egy rollout-döntés: build, flag-profil, mérések, rollback-cél, döntéshozó).

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
| A2 | Lab-route elérhetősége a célon → nem-nulla kilépés | `test_production_smoke_contract.py` |
| A3 | A kliens production profil nem tartalmaz dev tokent és dev hostot | `production_readiness_test.dart` (a MEGLÉVŐ `app_config_test` cellái mellett) |
| A4 | A fingerprint eltérése a manifesttől → nem-nulla kilépés | `production_readiness_test.dart` |
| A5 | Az ellenőrzőlista minden pontja meg van jelölve gépi vagy EMBERI címkével | a dokumentum + a teszt cellája |
| A6 | A rollout-csomag sablonja tartalmazza a rollback-célt és a döntéshozót | a sablon |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A füst-csomag beégetett hitelesítéssel dolgozik | A1 |
| A Lab-route ellenőrzés kimarad | A2 |
| A fingerprint-ellenőrzés csak létezést néz, egyezést nem | A4 |
| Az ellenőrzőlista minden pontot automatikusnak jelöl | A5 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** a teszt-fixture-ben tedd elérhetővé a Lab-route-ot a production célon, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

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
