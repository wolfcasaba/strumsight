# E10-R07 — Runtime ADR és production plugin skeleton

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`) — **`hold`: az E10-R06 valódi bake-off eredményétől függ, natív Android build**
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 7
- **Kör-azonosító:** `E10-R07`
- **Branch:** `<motor>/e10-r07-runtime-adr-and-plugin-skeleton`
- **Előfeltétel:** `E10-R06` (bake-off) VALÓS eredménnyel lezárva
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0422` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva). Ez az EGYETLEN Epic 10 ADR, aminek a TARTALMA emberi/mérési inputot igényel — a szám lefoglalható előre, de a döntés csak a Kör 6 valós adata után írható meg.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "native platform adapter fake runtime version handshake"` → nincs releváns előzmény (a találatok más domain hibaosztályai) — ez a kör a projekt ELSŐ ilyen jellegű infrastruktúrája, a §5/§9 saját tervezésére támaszkodik.

## 0.0 MIÉRT `hold`

Ez a kör két, EGYMÁSTÓL FÜGGETLEN okból nem indítható a batch-prep pillanatában:

1. **Adatfüggőség:** az ADR döntése ("melyik runtime nyert") a Kör 6 VALÓS bake-off eredményéből következik — amíg az `hold`-on van, ennek a körnek nincs bemenete, és egy implementer csak találgatna vagy a SDD §16.1 marketingállítás-tilalmát sértené.
2. **Natív build:** a `android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/` alatti Kotlin plugin/facade réteg buildeléséhez és a fake runtime end-to-end tesztjéhez natív Android toolchain kell — ugyanaz a korlát, mint a Kör 6-nál (§0.0 ott).

**Mi oldja fel:** a Kör 6 lezárása VALÓS adattal, ÉS emberi/CI-oldali megerősítés, hogy natív Android build+teszt elérhető ehhez a munkapéldányhoz.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/adr/0422-local-ai-runtime-selection.md",
  "android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/LocalAiPlugin.kt",
  "android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/RuntimeCapabilities.kt",
  "android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/runtime/RuntimeAdapter.kt",
  "android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/runtime/SelectedRuntimeAdapter.kt",
  "android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/runtime/FakeRuntimeAdapter.kt",
  "lib/platform/local_ai/local_ai_platform.dart",
  "lib/platform/local_ai/local_ai_platform_impl.dart",
  "test/platform/local_ai/",
  "docs/rounds/e10-r07-runtime-adr-and-plugin-skeleton.md",
]
gate_tests = [
  "test/platform/local_ai/",
]
native_gate = true
```

## 0.1 Az ADR-t maga a Claude írja — ez a kör KIVÉTEL a szokásos szabály alól

A brief-sablon normál szabálya szerint az implementer sosem érinti a `docs/adr/`-t. **Ez a kör kivétel:** mivel az ADR TARTALMA a Kör 6 mért eredményétől függ (nem a Claude előre-tervezett architekturális döntésétől), az orchesztrátor a Kör 6 review-jának lezárása UTÁN, ÚJ pre-flightben írja meg az ADR 0422 végleges szövegét a mért adatokból — ugyanúgy, ahogy minden más Epic 10 ADR-t, csak az input a szokásosnál később áll rendelkezésre. Az implementer TOVÁBBRA sem ír `docs/adr/`-t.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

## 1. Cél

A bake-off alapján rögzíteni a production runtime-ot, és létrehozni a stabil Android/Flutter platform-adaptert FAKE runtime támogatással, hogy a Kör 8+ már ne várjon a valódi natív integrációra.

## 2. Jelenlegi állapot — mért tények

- `lib/platform/` **nem létezik** — ez lesz az első platform-boundary fájl.
- `android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/` **nem létezik**.
- A Kör 6 bake-off eredménye (`docs/benchmarks/local-ai-runtime-bakeoff.md`, `local_ai/benchmark/results/`) az elsődleges bemenet.

## 3. Scope

**Benne van:** döntési ADR súlyozott kritériumokkal és raw benchmark linkekkel · primary runtime + fallback stratégia · Kotlin plugin/facade réteg, `RuntimeAdapter` mögé rejtett SDK · típusos platform message schema (command API ≠ event stream) · determinisztikus FAKE natív runtime a Flutter integrációs tesztekhez · version handshake Flutter és native között · iOS jövőbeli adapter közös contract-jegyzete.

**NINCS benne (tilos):**

- A teljes natív modell-lifecycle (load/unload/session) — ez Kör 13 dolga.
- Bármilyen VALÓS runtime SDK dependency-jét a `pubspec.yaml`/`build.gradle`-be, amíg az ADR nincs elfogadva.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

**Tilos zóna:** `lib/core/ai/**` (a Kör 2 interfészeit csak IMPLEMENTÁLJA, nem módosítja) · `lib/features/offline_ai/**` · `docs/sdd/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0422)

### 5.1 A Flutter domain SOSEM lát runtime SDK-t

A választott runtime SDK (pl. LiteRT-LM) kizárólag a Kotlin `SelectedRuntimeAdapter` mögött jelenhet meg; a Flutter oldal a Kör 2 `LocalGenerationRuntime` interfészét látja, típusos platform message schemán át.

**NEM elfogadható gyengítés:** egy "gyors" runtime-specifikus konstans vagy hibakód átszivárgása a Flutter oldalra "amíg nincs jobb absztrakció".

### 5.2 A FAKE runtime determinisztikus és CI-ben elérhető

A `FakeRuntimeAdapter` a valós streaming/cancel/session-reset kontraktust adja vissza, de kitalált, előre rögzített tokenekkel — SOHA nem tölt be valódi modellt.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A Flutter domain nem importál runtime SDK-t vagy Android osztályt | `test/tooling/architecture_dependency_offline_ai_test.dart` (Kör 2 bővítve) |
| A2 | A fake runtime teljes end-to-end streamet ad determinisztikusan | `test/platform/local_ai/fake_runtime_test.dart` |
| A3 | A version handshake hibája kontrollált, azonosítható hibát ad | `test/platform/local_ai/version_handshake_test.dart` |
| A4 | Ismeretlen natív hiba kontrollált `LocalAiFailure`-ra map-elt | `test/platform/local_ai/error_mapping_test.dart` |
| A5 | A runtime döntés ADR-ben, súlyozott kritériumokkal és raw linkkel visszakövethető | review — ADR-audit |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy Flutter fájl importál egy `package:litert_lm`-szerű típust | A1 |
| A fake runtime nem-determinisztikus (random token sorrend) | A2 |
| A version mismatch csendben "sikeresként" viselkedik | A3 |
| Egy ismeretlen natív hibakód `UnknownLocalAiFailure` helyett crash-el | A4 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állíts be egy verzió-mismatchet a handshake-ben, futtasd a tesztet → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/platform/local_ai
```

A `native_gate = true`, mert `android/` fájlt érint — a CI-terv (`tools/round-ci-plan.py`) ezért `build-apk.yml`-t fog választani, nem `full-gate.yml`-t.

## 8. Implementációs sorrend

1. ADR 0422 megírása a Kör 6 mért adataiból (Claude, pre-flight).
2. Kotlin `RuntimeAdapter` interfész + `FakeRuntimeAdapter`.
3. `LocalAiPlugin.kt` — MethodChannel/EventChannel facade.
4. `lib/platform/local_ai/` — Flutter oldali adapter, típusos üzenetekkel.
5. Version handshake mindkét oldalon.
6. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A runtime SDK szivárgása a Flutter oldalra.** A legfontosabb architekturális invariáns (A1).
- **A fake runtime hűtlensége a valós kontrakthoz.** Ha a fake túl egyszerű, a Kör 14+ integrációs tesztjei hamis biztonságot adnának.
- **A natív build törékenysége ezen a boxon.** Ha a CI natív build-je bármilyen okból nem megbízható, a `native_gate` dispatch előtt emberi megerősítés szükséges.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
