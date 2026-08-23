# E10-R30 — Backend manifest, CDN és release channel

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 30
- **Kör-azonosító:** `E10-R30`
- **Branch:** `<motor>/e10-r30-backend-manifest-and-release-channel`
- **Előfeltétel:** `E10-R08` merge-elve (a csomagformátumtól függ; a Kör 29 valós exportjától FÜGGETLEN, lásd §0.0)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0442` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "backend manifest CDN release channel revocation staged rollout"` → nincs releváns előzmény (a találatok más domain hibaosztályai) — ez a kör a projekt ELSŐ ilyen jellegű infrastruktúrája, a §5/§9 saját tervezésére támaszkodik.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `backend/app/config.py` `Settings.tutor_enabled` TÉNYLEGES mintáját (`bool = False`, `STRUMSIGHT_` env-prefix, `env_prefix="STRUMSIGHT_"`) — az Offline AI backend beállítás EZT a mintát követi, nem a Community dart-define-t (az backend-oldali, nem Flutter). Eltérésnél §0.0 brief-revízió.

## 0.0 Pre-flight kiegészítés — miért PENDING, függetlenül a Kör 29-től

A SDD Kör 30 sorrendben a Kör 29 UTÁN áll, de a backend manifest/metadata VÉGPONT önmagában NEM igényel valódi bináris modell-fájlt — placeholder `package_id`/`version`/`sha256` metaadattal is teljesen tesztelhető és éles-minőségű kódot eredményez. A tényleges bináris feltöltése (CDN-re) egy KÉSŐBBI, a Kör 29 valós exportjától függő, emberi/operátori lépés, ami NEM ennek a kódnak a helyessége.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/routers/local_ai.py",
  "backend/app/schemas/local_ai.py",
  "backend/app/config.py",
  "backend/tests/test_local_ai_manifest.py",
  "docs/deployment/local-ai-distribution.md",
  "docs/rounds/e10-r30-backend-manifest-and-release-channel.md",
]
gate_tests = [
  "test/app/config/feature_flags_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** egyik `allowed_paths` sem egyezik szó szerint a `high_risk_path_fragments` listával, de a `migration`/`privacy` kategóriával rokon: a végpont ÚJ backend Alembic-modellt vezethet be (ha szükséges), és a manifest-kérés privacy-korlátai (nincs device fingerprint, nincs prompt) kritikus adatvédelmi határ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

## 1. Cél

A modell- és knowledge-package terjesztése legyen skálázható, aláírt és staged-rollout-ot támogató, promptadat és device fingerprint nélkül.

## 2. Jelenlegi állapot — mért tények

- `backend/app/routers/local_ai.py` **nem létezik** — ez lesz az első Offline AI backend router.
- `backend/app/config.py` `Settings.tutor_enabled` mintája (`bool = False`, `STRUMSIGHT_` prefix) — ez a kör ugyanezt a mintát követi az Offline AI flagekhez (`local_ai_distribution_enabled` stb.), NEM a Flutter dart-define mintát.
- A projekt MA egyetlen Alembic migrációt tart (`e01_r12_0001_initial_account_schema.py`) — ez a kör CSAK akkor ad újat, ha a statikus signed manifest MEGOLDÁS nem elegendő (SDD 30.2: "statikus signed manifest előnyben").

## 3. Scope

**Benne van:** FastAPI channel-manifest endpointok (`GET /v1/local-ai/channels/{channel}/manifest`, `GET /v1/local-ai/packages/{package_id}/{version}/metadata`, `GET /v1/local-ai/knowledge/{language}/manifest`) · statikus signed manifest ELŐNYBEN Alembic-modell helyett, hacsak a dinamikus release-metaadat ezt ténylegesen nem indokolja · object storage/CDN URL + ETag/Range támogatás · stable/beta/lab channel policy · package revocation, minimum app version, privacy-safe staged-rollout seed · kliens-oldali signature-ellenőrzés HTTPS mellett IS kötelező · endpoint contract + cache-header tesztek · nincs exact device fingerprint vagy prompt a logban.

**NINCS benne (tilos):**

- Valódi bináris modell feltöltése CDN-re — ez egy KÉSŐBBI operátori lépés.
- `docs/adr/**` — az ADR 0442-t a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/routers/local_ai.py` | ÚJ — a manifest/metadata végpontok |
| `backend/app/schemas/local_ai.py` | ÚJ — a Pydantic sémák |
| `backend/app/config.py` | ÚJ Offline AI backend flagek (bővítés, `tutor_enabled` mintájára) |
| `backend/tests/test_local_ai_manifest.py` | a §6 cellái |
| `docs/deployment/local-ai-distribution.md` | ÚJ — a disztribúciós architektúra |

**Tilos zóna:** `backend/app/` egyéb moduljai (auth, tutor, community) · `backend/alembic/**` (csak akkor, ha a §3 indokolja — alapból tiltott) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0442)

### 5.1 A manifest-kérés SOSEM tartalmazhat promptot, conversation-ID-t, learner-profilt vagy exact device fingerprintet

**NEM elfogadható gyengítés:** egy "jobb tier-ajánlás" ürüggyel bevezetett részletes hardver-paraméter a kérésben — a tier-választás a KLIENSEN, lokálisan történik a manifest deklarált követelményei alapján (SDD §18.3).

### 5.2 A kliens a signature-t HTTPS mellett IS lokálisan ellenőrzi

A HTTPS transport-biztonság NEM helyettesíti az end-to-end csomag-aláírás-ellenőrzést (Kör 8) — egy kompromittált vagy hibásan konfigurált CDN-endpoint sem tudna hamis csomagot becsempészni.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A manifest-endpoint válasza megfelel a deklarált sémának | `test_local_ai_manifest.py` |
| A2 | ETag/Range header helyesen kezelt | `test_local_ai_manifest.py` |
| A3 | Visszavont (revoked) csomag metaadata explicit jelzi ezt, a kliens nem aktiválná | `test_local_ai_manifest.py` |
| A4 | Minimum app-version alatti kliens kérése kontrolláltan elutasított/jelzett | `test_local_ai_manifest.py` |
| A5 | Csatorna-hozzáférés (stable/beta/lab) helyesen szűrt | `test_local_ai_manifest.py` |
| A6 | A kérés/válasz NEM tartalmaz promptot, conversation-ID-t vagy exact device fingerprintet | `test_local_ai_manifest.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A manifest séma elfogad egy `device_fingerprint` mezőt a kérésben | A6 |
| A revoked csomag ugyanúgy szerepel, mint az aktív | A3 |
| A beta-csatorna metaadat lab-kliensnek is elérhető szűrés nélkül | A5 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** adj hozzá egy `device_fingerprint` mezőt a kérés-sémához, futtasd a tesztet → az **A6** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
cd backend && python -m pytest tests/test_local_ai_manifest.py -q
```

A `gate_tests` regresszió-őre (Kör 1 óta stabil feature-flag teszt) a `tools/round-gate.sh`-on át bizonyítja, hogy a backend munka nem érintett véletlenül Flutter-oldali kódot:

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart
```

## 8. Implementációs sorrend

1. `backend/app/schemas/local_ai.py` — a Pydantic sémák.
2. `backend/app/config.py` — Offline AI backend flagek.
3. `backend/app/routers/local_ai.py` — a három végpont.
4. Channel/revocation/min-version policy.
5. `docs/deployment/local-ai-distribution.md`.
6. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A device fingerprinting csendes bevezetése.** A legfontosabb privacy-invariáns (5.1, A6).
- **A revocation figyelmen kívül hagyása.** Egy visszavont, esetleg biztonsági hibás csomag továbbra is terjedne (A3).
- **A statikus-vs-dinamikus manifest túltervezése.** Egy felesleges Alembic-modell a §30.2 SDD-ajánlás ("statikus előnyben") ellenére indokolatlan komplexitást vinne be.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
