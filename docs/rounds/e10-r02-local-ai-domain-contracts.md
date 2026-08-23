# E10-R02 — Local AI feature boundary és közös domain szerződések

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 2
- **Kör-azonosító:** `E10-R02`
- **Branch:** `<motor>/e10-r02-local-ai-domain-contracts`
- **Előfeltétel:** `E10-R01` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0420` — a szám FOGLALT (Epic 10 batch-tartomány 0420-tól, driftre számítva — lásd E10-R01 §0.0). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `tool/check_architecture.dart` TÉNYLEGES `_isSharedDomain()` és `_isForbiddenDomainDependency()` függvényét (384. sor környéke) — a bővítés a MEGLÉVŐ allowlist-mintát kövesse, ne írja át. Eltérésnél §0.0 brief-revízió.

## 0.0 Pre-flight kiegészítés — mért kódtények

**A `TutorContextSnapshot`-ot ez a kör NEM hozza létre** (a SDD §3.5/6.1 megfogalmazása félreérthető) — az MÁR LÉTEZIK Chapter 5 munkájaként (`lib/features/ai_tutor/application/context/tutor_context_snapshot.dart`). Ez a kör kizárólag a runtime-független `core/ai` és `features/offline_ai/domain` value objecteket hozza létre (SDD §7 közös szerződések: `LocalAiMode`, `LocalAiAvailability`, `LocalAiFailure`, `DeviceCapabilityProfile`, `ModelPackageDescriptor`, `LocalGenerationRuntime`, `GenerationEvent` stb.) — ezek ÚJAK, nincs ütközés a Chapter 5-tel.

**Az architektúra-guard bővítése konkrétan:**

```dart
// tool/check_architecture.dart, ~384. sor — MA:
bool _isSharedDomain(String sourcePath) =>
    sourcePath.startsWith('lib/core/music/') ||
    sourcePath.startsWith('lib/core/audio/codec/') ||
    sourcePath.startsWith('lib/features/practice/domain/');
```

Bővítsd `lib/core/ai/` és `lib/features/offline_ai/domain/` ággal — mindkettő az `_isForbiddenDomainDependency()` (389. sor környéke) ALÁ esik ezután, ami tiltja a `package:flutter*`, `package:flutter_riverpod`/`riverpod`, `package:dio`, `package:shared_preferences` és `lib/l10n*` importot. **A `lib/core/` → `lib/features/` irány MA IS tiltott** (332. sor: a general core→features ban) — ez azt jelenti, hogy a `lib/core/ai/` interfészek (pl. `LocalGenerationRuntime`) NEM importálhatnak semmit `lib/features/offline_ai/`-ből; a FÜGGŐSÉG iránya mindig `features/offline_ai` → `core/ai`, soha fordítva.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts --top 5 "architecture guard allowlist new domain path shared"` → **L407** (E08-R27) — a gépi allowlist-gate csak azt védi, amit felvettek rá; a pre-flight/review kézzel grep-elje minden ÚJ domain-fájl importlistáját (`grep -n "^import" <fájl>`), ne csak a gate zöldjére hagyatkozzon.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/core/ai/local_ai_mode.dart",
  "lib/core/ai/local_ai_availability.dart",
  "lib/core/ai/local_ai_failure.dart",
  "lib/core/ai/generation_id.dart",
  "lib/core/ai/generation_request.dart",
  "lib/core/ai/generation_event.dart",
  "lib/core/ai/generation_metrics.dart",
  "lib/core/ai/runtime_capabilities.dart",
  "lib/core/ai/loaded_model_handle.dart",
  "lib/core/ai/runtime_health.dart",
  "lib/core/ai/local_generation_runtime.dart",
  "lib/core/ai/model_registry.dart",
  "lib/core/ai/model_package_manager.dart",
  "lib/core/ai/model_package_descriptor.dart",
  "lib/core/ai/device_capability_profiler.dart",
  "lib/core/ai/local_ai_resource_coordinator.dart",
  "lib/core/ai/public.dart",
  "lib/features/offline_ai/domain/session_id.dart",
  "lib/features/offline_ai/domain/model_package_id.dart",
  "lib/features/offline_ai/domain/model_version.dart",
  "lib/features/offline_ai/public.dart",
  "tool/check_architecture.dart",
  "test/core/ai/",
  "test/tooling/architecture_dependency_offline_ai_test.dart",
  "docs/rounds/e10-r02-local-ai-domain-contracts.md",
]
gate_tests = [
  "test/tooling/architecture_dependency_offline_ai_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Runtime- és platformfüggetlen Flutter domain boundary a helyi AI-hoz — pure Dart, immutable, önállóan tesztelt, a Chapter 5 meglévő kódjától ÉS a natív SDK-któl teljesen elszigetelve.

## 2. Jelenlegi állapot — mért tények

- `lib/core/ai/` és `lib/features/offline_ai/` **nem létezik** — ez a kör hozza létre.
- A Kör 1 (E10-R01) létrehozta a nyolc `localAi*` feature flaget — ez a kör nem nyúl hozzájuk, csak a mögöttes domaint építi.
- A `tool/check_architecture.dart` `_isSharedDomain()` allowlistje MA három útvonalat véd — lásd §0.0.
- A `lib/features/ai_tutor/` MÁR rendelkezik `TutorModelGateway`, `TutorContextSnapshot`, `TutorToolRegistry` szerződésekkel — ez a kör ÚJ, párhuzamos domaint épít MELLÉJÜK (nem helyettük), amit egy KÉSŐBBI kör (Kör 23) köt majd össze a gateway interfészen keresztül.

## 3. Scope

**Benne van:** `LocalAiMode`, `LocalAiAvailability`, `LocalAiFailure` (18 kategória a SDD §7.7 szerint), `GenerationId`, `SessionId`, `ModelPackageId`, `ModelVersion` value objectek · `GenerationRequest`, `GenerationEvent` (sealed hierarchia), `GenerationMetrics`, `RuntimeCapabilities`, `LoadedModelHandle`, `RuntimeHealth` modellek · `LocalGenerationRuntime`, `ModelRegistry`, `ModelPackageManager`, `DeviceCapabilityProfiler`, `LocalAiResourceCoordinator` interfészek (csak szerződés, implementáció NÉLKÜL) · az architektúra-guard bővítése.

**NINCS benne (tilos):**

- Bármilyen interfész IMPLEMENTÁCIÓJA (repository, service, natív adapter) — ez a Kör 8+ dolga.
- `TutorContextSnapshot`, `TutorModelGateway` vagy bármely Chapter 5 fájl módosítása.
- `docs/adr/**` — az ADR 0420-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/core/ai/*.dart` | ÚJ — a runtime-független value objectek és interfészek (lásd az `ai-router` blokk teljes listáját) |
| `lib/features/offline_ai/domain/*.dart` | ÚJ — a néhány feature-szintű azonosító típus |
| `lib/features/offline_ai/public.dart` | ÚJ — export-only barrel |
| `tool/check_architecture.dart` | a `_isSharedDomain()` bővítése két új útvonallal |
| `test/core/ai/` | a §6 cellái |
| `test/tooling/architecture_dependency_offline_ai_test.dart` | ÚJ — a bővített guard regressziós próbája |

**Tilos zóna:** `lib/features/ai_tutor/**` · `lib/features/offline_ai/application/**`, `data/**`, `presentation/**` (ez a kör csak `domain/`-t hoz létre) · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `android/**`

## 5. Kötött architekturális döntések (ADR 0420)

### 5.1 A local-AI domain teljesen model-agnostic és runtime-agnostic

`lib/core/ai/` és `lib/features/offline_ai/domain/` egyetlen fájlja sem importálhat `package:flutter/*`, Riverpod-ot, Dio-t, Android-specifikus típust vagy runtime SDK-t (LiteRT-LM, ExecuTorch, llama.cpp, ONNX). Ezek a típusok kizárólag az infrastructure/platform rétegben (Kör 7+) jelenhetnek meg.

**NEM elfogadható gyengítés:** egy "ideiglenes" `dart:io`-alapú fájlelérés vagy egy runtime-specifikus enum-érték (pl. `RuntimeFamily.liteRtLm`) beégetése a domainbe "amíg a bake-off el nem dönti" — a domain a runtime-VÁLASZTÁSTÓL függetlenül kell hogy stabil maradjon; a runtime nevét egy STRING/opak azonosító hordozza, nem egy zárt enum, ami a bake-off előtt már elköteleződik.

### 5.2 Minden persisted enum wire stringet használ, ismeretlen érték kontrollált

A `LocalAiMode`, `LocalAiAvailability` és a többi enum szerializációja explicit `name`/`values.byName` mintát követ; ismeretlen wire-string a `LocalAiMode`-nál biztonságos `deterministicOnly`-ra esik vissza (SDD §7.1), az `Availability`-nél explicit `FormatException`-t dob (nincs biztonságos "alapértelmezett" elérhetőségi állapot).

**NEM elfogadható gyengítés:** egy `catch (_) { return values.first; }` minta bármelyik enumnál — ez csendben rossz állapotot mutatna a felhasználónak.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Minden value object immutable és `==`/`hashCode` konzisztens | `test/core/ai/` |
| A2 | JSON round-trip minden persisted típusra bájtra egyező | `test/core/ai/` |
| A3 | Ismeretlen `LocalAiMode` wire-string → `deterministicOnly` | `test/core/ai/local_ai_mode_test.dart` |
| A4 | Ismeretlen `LocalAiAvailability` wire-string → explicit hiba, NEM csendes fallback | `test/core/ai/local_ai_availability_test.dart` |
| A5 | `lib/core/ai/` és `lib/features/offline_ai/domain/` egyetlen fájlja sem importál Flutter/Riverpod/Dio/Android típust | `test/tooling/architecture_dependency_offline_ai_test.dart` |
| A6 | Más feature csak a `public.dart` barrelen át érheti el a típusokat | `test/tooling/architecture_dependency_offline_ai_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy value object mutable mezőt kap | A1 |
| A JSON encode/decode veszít egy mezőt | A2 |
| A `LocalAiMode.fromWire` ismeretlen értékre dobna ahelyett, hogy `deterministicOnly`-t adna | A3 |
| A `LocalAiAvailability.fromWire` ismeretlen értékre csendben egy default értéket adna | A4 |
| Egy domain-fájl `import 'package:flutter/material.dart'`-ot tartalmaz (akár `show`-val) | A5 |
| Egy másik feature közvetlenül `lib/core/ai/local_ai_mode.dart`-ot importálja a `public.dart` helyett | A6 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** adj hozzá egy `import 'package:flutter/material.dart' show Color;` sort valamelyik `lib/core/ai/` fájlhoz, futtasd a gate architecture-lépését → az **A5** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/architecture_dependency_offline_ai_test.dart test/core/ai
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. A 18 `LocalAiFailure` kategória + `LocalAiMode`/`LocalAiAvailability` enumok wire-string kódolással.
2. `GenerationId`, `SessionId`, `ModelPackageId`, `ModelVersion` azonosító value objectek.
3. `GenerationRequest`, `GenerationEvent` (sealed), `GenerationMetrics`, `RuntimeCapabilities`, `LoadedModelHandle`, `RuntimeHealth`.
4. `LocalGenerationRuntime`, `ModelRegistry`, `ModelPackageManager`, `DeviceCapabilityProfiler`, `LocalAiResourceCoordinator` — TISZTA interfészek, `implements`/`extends` nélkül.
5. `public.dart` barrel mindkét helyen.
6. `tool/check_architecture.dart` bővítése + a regressziós teszt.
7. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A domain korai elköteleződése egy runtime mellett.** Egy zárt enum vagy egy runtime-specifikus mező visszamenőleg törné a Kör 6/7 bake-off eredményét (A1, 5.1).
- **A guard-bővítés túl tág lenne.** Ha a `_isSharedDomain()` mintaillesztés véletlenül lefedne egy `lib/features/offline_ai/application/`-beli fájlt is, az illegitim módon engedne Flutter-függést oda, ahol a rétegnek épp Flutter-t KELLENE használnia — a mintaillesztést pontosan `lib/features/offline_ai/domain/`-ra kell szűkíteni, nem `lib/features/offline_ai/`-ra.
- **A wire-string enum-kezelés inkonzisztenciája.** Ha az `Availability` is csendben fallback-elne, egy jövőbeli migrációs hiba észrevétlen maradna (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
