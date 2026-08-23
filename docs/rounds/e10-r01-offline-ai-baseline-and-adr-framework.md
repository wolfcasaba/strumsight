# E10-R01 — Offline AI baseline, source review, ADR-keret és feature flag család

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 1
- **Kör-azonosító:** `E10-R01`
- **Branch:** `<motor>/e10-r01-offline-ai-baseline-and-adr-framework`
- **Előfeltétel:** Epic 9 (Community Platform) utolsó köre merge-elve, vagy a queue-ban Epic 10 az aktuális sáv
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — ez a kör dokumentumot és feature flaget ad, nem köt új architekturális döntést. A jövőbeli runtime/modell-döntések ADR-jei a Kör 7/26/29-nél kerülnek kiosztásra.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/app/config/feature_flags.dart` és `lib/features/ai_tutor/` TÉNYLEGES állapotát — a §0.0 alább már tartalmazza a 2026-08-22-i mérést, de ha driftelt, §0.0 brief-revízió, NEM csendes lista-tágítás.

## 0.0 Pre-flight — mért tények és a SDD-tervezet driftje (Claude Sonnet 5, 2026-08-22)

**A `docs/sdd/11-epic-10-offline-ai.md` több helyen ELAVULT feltevést tartalmaz a 2026-07-28-i írás óta — ezt a brief-sorozat mindenütt korrigálja, itt az első és legfontosabb hely:**

1. **A SDD Kör 1 saját fájllistája `docs/adr/0010-local-ai-runtime-template.md`-t javasol.** A projekt ADR-sorszámozása MA 0406-nál tart (monoton, 0050 óta folyamatos) — a 0010/0011 tartomány STALE, egy korai tervezői vázlat maradványa. **Ez a kör NEM foglal le konkrét ADR-számot** (nincs kötött döntése), de minden KÉSŐBBI Epic 10 kör a `tools/round-slots.py reserve-adr`-rel kér számot a saját pre-flightjában — a batch-írás idején (2026-08-22) a legmagasabb foglalt szám 0419 (Epic 9 tartomány), az Epic 10 batch ezért a 0420-tól induló sávot IRÁNYOZZA ELŐ minden egyes brief fejlécében, **driftre számítva** (ugyanaz a minta, mint minden korábbi batch-nél, pl. Epic 9 0395-0419).
2. **A SDD §3.3 "TutorContextSnapshot"-ot Epic 10 feladataként sorolja fel — ez TÉVES.** A `TutorContextSnapshot` MÁR LÉTEZIK: `lib/features/ai_tutor/application/context/tutor_context_snapshot.dart` (211 sor), a `ContextProvenance`, `TutorContextField`, `TutorContextFieldKey` osztályokkal együtt, Chapter 5 kész munkája. Epic 10 ezt **fogyasztja**, nem hozza létre.
3. **A "Chapter 5 confirmation coordinator" nem létezik ilyen néven.** A tényleges mechanizmus `ActionConfirmationService` (`lib/features/ai_tutor/application/orchestration/action_confirmation_service.dart`), `propose→preview→confirm` folyamattal, `clientActionId` idempotenciával — [ADR 0133](../adr/0133-ai-tutor-tool-confirmation.md), [ADR 0139](../adr/0139-ai-tutor-action-proposal-confirmation.md), [ADR 0287](../adr/0287-no-automatic-tool-execution-in-the-tutor.md). Minden későbbi Epic 10 brief, ami tool-confirmationt említ, erre a szolgáltatásra hivatkozik.
4. **A "claim provenance" nem `ClaimProvenance` osztály.** A tényleges pár `TutorClaimValidator`/`TutorClaim`/`TutorSourceRef` (`lib/features/ai_tutor/domain/services/tutor_claim_validator.dart`, `lib/features/ai_tutor/domain/models/tutor_source_ref.dart`) — [ADR 0135](../adr/0135-tutor-knowledge-governance.md), [ADR 0136](../adr/0136-tutor-knowledge-retrieval.md).
5. **A `TutorModelGateway` MA is létező, stabil interfész**, NEM ez a kör hozza létre: `lib/features/ai_tutor/data/model_gateway/tutor_model_gateway.dart` — `start(TutorModelRequest) → Future<AppResult<Stream<TutorModelEvent>>>`, `cancel()`, `health()`, [ADR 0131](../adr/0131-ai-tutor-provider-boundary.md). A produkciós DI-ben ma egy **placeholder stub** van bekötve: `LocalTutorModelGatewayStub` (`local_tutor_model_gateway_stub.dart:21`), ami MINDIG `AppResult.failure(UnknownFailure(code: 'tutor.model_gateway.unavailable'))`-t ad, bekötve a `tutor_providers.dart:350` sorban. **Ez a stub a Kör 23 tényleges cserélendő célpontja** — a Kör 1 csak dokumentálja ezt a tényt, nem nyúl a fájlhoz.
6. **A `lib/core/security/` könyvtár NEM létezik.** A Kör 8 aláírás-ellenőrző kódja teljesen új infrastruktúra lesz.
7. **A `tool/check_architecture.dart` `_isSharedDomain()` allowlistje (384. sor) MA három útvonalat tartalmaz** (`lib/core/music/`, `lib/core/audio/codec/`, `lib/features/practice/domain/`) — a `lib/core/ai/` és a `lib/features/offline_ai/domain/` NINCS rajta. A Kör 2 bővíti ezt (SDD 2.6).
8. **A `lib/app/config/feature_flags.dart`-ban két minta él egymás mellett**: dart-define-vezérelt (pl. `communityEnabled: const bool.fromEnvironment('STRUMSIGHT_COMMUNITY')`) és konstruktor-default-only (pl. `aiTutorEnabled` — nincs dart-define, mindig `false` a `forEnvironment`-ben, amíg be nem drótozzák). A Kör 1 a Community-mintát követi (dart-define, kill-switch), mert az Offline AI éles eszközterhelést és letöltést von maga után, ugyanaz a kockázati osztály, mint a Community.

**Visszakeresett előzmény (ADR 0312, §4.9):**
`node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "feature flag production default kill switch offline model download"` → **ADR 0395** (E09-R01, Community flag család, dart-define minta) — ugyanaz a mechanizmus, amit ez a kör is követ. `node tools/knowledge-rag.mjs --corpus lessons,halts --top 5 "architecture guard shared domain allowlist flutter import"` → **L407** (E08-R27: az allowlist-alapú domain-guard csak azt a fájlt védi, amit valaki felvett rá — kötelező kézi grep minden ÚJ domain-fájl importjára, ne csak a gépi gate-re hagyatkozz). Ez a lecke minden Epic 10 Dart-domain körnek (2, 3, 16, 17 stb.) szól.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "docs/sdd/epic-10-baseline.md",
  "docs/sdd/epic-10-source-review.md",
  "docs/sdd/epic-10-risk-register.md",
  "lib/app/config/feature_flags.dart",
  "test/app/config/feature_flags_test.dart",
  "docs/rounds/e10-r01-offline-ai-baseline-and-adr-framework.md",
]
gate_tests = [
  "test/app/config/feature_flags_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** egyik `allowed_paths` sem egyezik szó szerint a router `high_risk_path_fragments` listájával, de a kimenet egy production on/off kapu (`localAiFeatureEnabled` + hét alkapcsoló) egy 32 körös, natív kódot, modellletöltést és eszközterhelést hozó epic számára — rossz alapértéke a teljes epic hátralévő részét élesítené egy nem auditált, letöltés- és erőforrás-igényes felületen. A kockázati profil megegyezik a `high_risk_path_fragments` szándékával.

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

Dokumentáld a repository tényleges állapotát, a Chapter 5 MEGLÉVŐ szerződéseit (ne feltételezz újakat) és a runtime-jelöltek hivatalos forrásokból vett képességeit; vezesd be a nyolc kötelező Offline AI feature flaget production-off alapértékkel. **Alkalmazáskód-változtatás a domain/UI rétegben NINCS.**

## 2. Jelenlegi állapot — mért tények

- `lib/features/offline_ai/` és `lib/core/ai/` **nem létezik** — ez az Epic 10 első köre.
- A `TutorModelGateway`, `TutorContextSnapshot`, `TutorToolRegistry`, `ActionConfirmationService`, `TutorClaimValidator`/`TutorSourceRef`, `TutorConversation`/`TutorMessage`, és MÁR MEGLÉVŐ `local_tutor_conversation_repository.dart` + `local_tutor_memory_repository.dart` a Chapter 5 (ai_tutor feature) kész, stabil munkája — lásd §0.0 pontos fájlutakkal.
- `lib/app/config/feature_flags.dart` MA 30+ named-parameter flaget hordoz; a Community család (E09-R01) mutatja a dart-define + production-off mintát.
- `backend/app/config.py` `Settings.tutor_enabled` mintája (`bool = False`, `STRUMSIGHT_` env-prefix) — az Offline AI backend (Kör 30) ugyanezt követi majd, de EZ a kör Flutter-oldali, a backendhez nem nyúl.

## 3. Scope

**Benne van:** `docs/sdd/epic-10-baseline.md` (Flutter/Dart/AGP/Kotlin/NDK/minSdk/targetSdk állapot) · `docs/sdd/epic-10-source-review.md` (LiteRT-LM, ExecuTorch, llama.cpp, ONNX Runtime GenAI hivatalos forrásokból) · `docs/sdd/epic-10-risk-register.md` (OOM, thermal, licenc, tampering, injection, tool misuse, quality regression, download failure) · a nyolc `localAi*` feature flag production-off alapértékkel.

**NINCS benne (tilos):**

- Bármilyen `lib/core/ai/**` vagy `lib/features/offline_ai/**` fájl — ez Kör 2-től kezdődik.
- Végleges runtime- vagy modellválasztás — ez Kör 6/7 dolga, valós mérés nélkül tilos.
- A meglévő `aiTutorEnabled`/Chapter 5 flagek módosítása.
- `docs/adr/**`, `tools/**`, `.github/**`, `android/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/sdd/epic-10-baseline.md` | ÚJ — a tényleges repo-állapot |
| `docs/sdd/epic-10-source-review.md` | ÚJ — a runtime-jelöltek elsődleges forrásból |
| `docs/sdd/epic-10-risk-register.md` | ÚJ — a nyolc kockázati kategória |
| `lib/app/config/feature_flags.dart` | ÚJ Offline AI flagek hozzáadása (bővítés) |
| `test/app/config/feature_flags_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/core/ai/**` · `lib/features/offline_ai/**` · `lib/features/ai_tutor/**` (a Chapter 5 kódhoz NEM nyúl) · `docs/adr/**` · `docs/sdd/11-epic-10-offline-ai.md` (a forrás-SDD-t nem módosítja) · `tools/**` · `.github/**` · `android/**`

## 5. Kötött architekturális döntések

### 5.1 Nincs ÚJ kötött döntés — a flag-mechanizmus a Community-mintát követi

**NEM elfogadható gyengítés:** bármelyik `localAi*` flag production defaultja `true`, vagy a nyolcból bármelyik dart-define nélkül, konstruktor-default `true`-val kerül be "egyszerűség kedvéért" — ez pontosan az a hibaosztály, amit az E09-R01 §6.1 A1/A2 cellája már megfogott a Community flag-családnál.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Mind a nyolc `localAi*` flag production-ben explicit engedély nélkül `false` | `feature_flags_test.dart` |
| A2 | Mind a nyolc flag development/lab környezetben elérhető | `feature_flags_test.dart` |
| A3 | A baseline dokumentum a TÉNYLEGES `pubspec.yaml`/`android/`/`ios/` állapotra épül, nem feltételezésre | review — dokumentum-audit |
| A4 | A source review a négy runtime-jelöltet elsődleges (hivatalos) forrásból dokumentálja, licenccel | review — dokumentum-audit |
| A5 | A risk register mind a nyolc SDD-kötelező kategóriát lefedi (OOM, thermal, licenc, tampering, injection, tool misuse, quality regression, download failure) | review — dokumentum-audit |
| A6 | Nincs meglévő flag módosítva | `tools/round-gate.sh` — teljes cél-terület zöld |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `localAiFeatureEnabled` production defaultja `true` | A1 |
| Csak a fő flag kap production-off védelmet, a hét alkapcsoló nem | A2 |
| A risk register kihagyja a tool misuse vagy a download failure kategóriát | A5 |
| A flag hozzáadás egy meglévő flag nevét vagy alapértékét módosítja | A6 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd `localAiFeatureEnabled` production defaultját `true`-ra, futtasd a gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart
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

1. `docs/sdd/epic-10-baseline.md` — tényleges toolchain-állapot.
2. `docs/sdd/epic-10-source-review.md` — a négy runtime-jelölt táblázata.
3. `docs/sdd/epic-10-risk-register.md` — nyolc kockázati kategória.
4. A nyolc `localAi*` flag hozzáadása `feature_flags.dart`-hoz (dart-define, Community-minta).
5. A production-default teszt.
6. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A flag alapértelmezésének elrontása.** Egyetlen rossz `true` élesítené a letöltési/erőforrás-felületet auditálatlanul (A1/A2).
- **A source review marketinganyagra hagyatkozása.** A SDD kifejezetten tiltja, hogy egyetlen flagship-teszt vagy hivatalos dokumentáció-hiány végleges döntést szüljön — a review csak a MAI hivatalos állapotot rögzíti, nem dönt.
- **A risk register felszínessége.** Egy ki nem mondott kockázat (pl. tool misuse) a Kör 20+ tájékán derülne ki drágán.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
