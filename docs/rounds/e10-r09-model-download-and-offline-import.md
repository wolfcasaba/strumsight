# E10-R09 — Model download, pause, resume és offline import

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 9
- **Kör-azonosító:** `E10-R09`
- **Branch:** `<motor>/e10-r09-model-download-and-offline-import`
- **Előfeltétel:** `E10-R08` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0424` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/core/network/` MEGLÉVŐ `DioFactory`/`ApiClient` mintáját (E01-R08) — a resumable download ugyanazt a Dio-alapot használja, nem önálló HTTP klienst épít. Eltérésnél §0.0 brief-revízió.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "idempotent crash-safe quarantine atomic activation"` → **E08-R04** (bounded persistent activity outbox, crash-safe quarantine, idempotent drain, bm25#1 emb#1) — a "staging + sidecar state + quarantine" minta ebben a körben ugyanezt az elvet alkalmazza modellcsomag-letöltésre.

## 0.0 Hardver/scope-korlát — miért PENDING

Ez a kör NEM tölt le VALÓDI, több GB-os modellt sem fejlesztés, sem teszt közben — a "Kötelező tesztek" mind egy FAKE/mock HTTP repository-t és egy kis (néhány KB-os) fixture-fájlt használnak, az `AGENTS.md` §10 "determinisztikus... network fake" szabálya szerint. A resumable download LOGIKÁJA (Range/ETag, pause/resume state, staging fájl) teljesen független attól, hogy a végleges runtime melyik lett (Kör 6/7 `hold`) — a manifest formátum (Kör 8) a bemenete, nem a runtime.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/offline_ai/data/model_download_repository.dart",
  "lib/features/offline_ai/application/model_download_controller.dart",
  "lib/features/offline_ai/data/offline_package_importer.dart",
  "test/features/offline_ai/model_download/",
  "docs/rounds/e10-r09-model-download-and-offline-import.md",
]
gate_tests = [
  "test/features/offline_ai/model_download/",
]
native_gate = false
```

**Kockázat = high, indoklás:** a `share`/`upload` kategóriával rokon: a letöltés HÁLÓZATI kérést indít, és az offline import egy `file-picker`-en át fogad KÜLSŐ bemenetet — mindkettő a router `high_risk_path_fragments` szándékával egyező kockázat, még ha a fájlnevek szó szerint nem is egyeznek.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

## 1. Cél

A nagy modellcsomag letöltése legyen megbízható, felhasználó által kontrollált és megszakítás után folytatható; a signed offline import kizárólag a Kör 8 verifierén átment csomagot fogadja el.

## 2. Jelenlegi állapot — mért tények

- `lib/core/network/` MA `DioFactory`-t ad (egyetlen Dio-forrás, guard-teszttel védve) — ez a kör ezt HASZNÁLJA, nem épít párhuzamos HTTP klienst.
- A Kör 8 (E10-R08) `signed_manifest_verifier.dart`-ja a bemenete az importernek — a letöltött/importált fájl előbb STAGINGBE kerül, a verifier fut, csak utána mehet tovább (a Kör 10 aktiválja).
- `lib/features/offline_ai/data/` **nem létezik** — ez az első data-réteg fájl a feature-ben.

## 3. Scope

**Benne van:** resumable download repository Range/ETag támogatással (ha a distribution szolgáltatás támogatja) · staging fájl + sidecar download state · pause/resume/cancel/retry/network-change kezelés · szerveroldali ETag/version-változás detektálása (régi partial nem folytatható vakon) · Wi-Fi-only és charging-preferred policy · production offline file-picker import, KIZÁRÓLAG signed package-re · staging-first import (nincs közvetlen external-path→runtime load).

**NINCS benne (tilos):**

- Valódi, több GB-os modell tényleges letöltése bármilyen tesztben.
- Az aktiválás logikája — ez Kör 10 dolga.
- `docs/adr/**` — az ADR 0424-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/offline_ai/data/model_download_repository.dart` | ÚJ — resumable download |
| `lib/features/offline_ai/application/model_download_controller.dart` | ÚJ — pause/resume/cancel orchestráció |
| `lib/features/offline_ai/data/offline_package_importer.dart` | ÚJ — signed-only file-picker import |
| `test/features/offline_ai/model_download/` | a §6 cellái |

**Tilos zóna:** `lib/core/network/**` (csak HASZNÁLJA, nem módosítja a `DioFactory`-t) · `lib/core/security/**` (csak importálja a Kör 8 verifierét) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0424)

### 5.1 A letöltés SOHA nem indul automatikusan

Egyetlen kódút sem indíthat modellletöltést app-indításkor, feature-flag bekapcsoláskor vagy háttérben — kizárólag explicit felhasználói gomb-lenyomás.

**NEM elfogadható gyengítés:** egy "előtöltés Wi-Fi-n, ha úgyis van hely" háttérfolyamat, akár jó szándékú UX-optimalizálásként is — ez a SDD §5.2 "helyi-first, nem helyi-only kényszer" elvének sértése.

### 5.2 Import csak staging-en és verifikáción át, sosem közvetlen runtime-load

Az offline import a kiválasztott fájlt ELŐSZÖR a staging könyvtárba másolja, majd a Kör 8 verifierét futtatja rajta — a runtime SOHA nem kap közvetlen external path-ot.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Resume pontosan a megszakítás bájtjától folytatja (nincs duplikáció, nincs kihagyás) | `model_download_repository_test.dart` |
| A2 | Szerveroldali ETag-változás esetén a régi partial eldobásra kerül, nem folytatódik vakon | `model_download_repository_test.dart` |
| A3 | Cancel után nincs aktiválható félig letöltött csomag | `model_download_controller_test.dart` |
| A4 | Hálózatvesztés közben a state konzisztens marad (nincs korrupt sidecar) | `model_download_controller_test.dart` |
| A5 | Aláíratlan/hamisított csomag importja elutasított | `offline_package_importer_test.dart` |
| A6 | Aláírt csomag importja staging-en és verifikáción át fut, nem közvetlenül | `offline_package_importer_test.dart` |
| A7 | Elégtelen tárhely a letöltés/import ELŐTT kiderül, nem közben omlik össze | `model_download_controller_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A resume a fájl elejétől kezd újra ETag-ellenőrzés nélkül | A1 vagy A2 (a duplikáció vagy a stale-adat aszerint, melyik teszt-eset fut) |
| A cancel nem törli a staging fájlt | A3 |
| Az importer közvetlenül a felhasználó által választott path-ot adja át a runtime-nak | A6 |
| Az aláíratlan csomag "csak figyelmeztetést" kap, de importálódik | A5 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** kapcsold ki az ETag-összehasonlítást a resume logikában, szimulálj szerveroldali fájlváltást → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/offline_ai/model_download
```

A gate artefaktum a mérce — lásd a §12 általános AGENTS.md-idézetet a korábbi köröknél; csonkítás/pipe tilos, CI-dispatch/PR/merge Claude-oldal.

## 8. Implementációs sorrend

1. `model_download_repository.dart` — Range/ETag, staging fájl, sidecar state.
2. `model_download_controller.dart` — pause/resume/cancel/retry, Wi-Fi/charging policy.
3. `offline_package_importer.dart` — file-picker → staging → Kör 8 verifier.
4. A tárhely-előellenőrzés.
5. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A csendes automatikus letöltés.** A legfontosabb termékhatár-sértés lehetősége (5.1).
- **A resume korrumpált partial-lal folytatása.** Adatvesztést vagy aktiválhatatlan csomagot eredményezne (A1/A2).
- **A direkt external-path import.** Megkerülné a Kör 8 teljes verifikációs láncát (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
