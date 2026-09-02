# E16-R03 — Capability rollout-döntések: mi legyen BE alapból

- **Státusz:** PREPARED (előre megírva 2026-09-02, kód olvasva: `main @ 11d0d2bb`)
- **Típus:** Chapter 16 (Kompozíció és rollout), Kör 3
- **Kör-azonosító:** `E16-R03`
- **Branch:** `<motor>/e16-r03-capability-rollout-decisions`
- **Előfeltétel:** `E16-R02` merge-elve (a bekötési hiányok lezárva — rollout csak működő capabilityre adható)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0492` — a szám FOGLALT (Chapter 16 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "rollout boundary availability flag shipping decision entry point"` → **[ADR 0197](../adr/0197-song-trainer-shipping-rollout-boundary.md)** („a rollout-határ áthelyezése és a belépési pont mint a rollout része") és **[ADR 0065](../adr/0065-practice-engine-v2-parallel-rollout.md)**. A repó MÉRT mintája: a rollout nem puszta flag-billentés, hanem belépési pont + bizonyíték.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/app/config/feature_flags.dart` `forEnvironment` ágát, és listázd a MÉRT alapértelmezéseket. A megíráskor `nonProd`: diagnostics, labMode, practiceEngineV2, migratedLearn, practiceDetailedHistory, songTrainerV2, adaptiveShell — MINDEN más `false` (vision 10 flag, analysis 10 flag, tutor 2, generator 2, recognition 3), a community öt flagje pedig dart-define-ból.

## 0.0 A kör tárgya: MÉRT készenlét, nem lelkesedés

A cél nem az, hogy „kapcsoljunk be mindent", hanem hogy capabilityenként MÉRT kritérium alapján dőljön el: BE (alapértelmezés), PREVIEW (flag mögött marad, de nevesített feltétellel), vagy KI (nevesített blokkolóval). A kritérium capabilityenként: (a) a felülete migrált és elérhető (E15), (b) a kompozíciós rétege valós adatot ad (E16-R01/R02), (c) a saját mérce-sávja zöld, (d) nem igényel olyan külső erőforrást (backend, API-kulcs, modell), ami a felhasználónál nincs.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/app/config/feature_flags.dart",
  "test/app/config/feature_flags_test.dart",
  "test/app/feature_flags_test.dart",
  "test/e2e/first_practice_offline_test.dart",
  "docs/release/capability-rollout.md",
  "docs/rounds/e16-r03-capability-rollout-decisions.md",
]
gate_tests = [
  "test/app/config/feature_flags_test.dart",
  "test/app/feature_flags_test.dart",
  "test/e2e/first_practice_offline_test.dart",
  "test/ui/ui_inventory_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a flag-alapértelmezés dönti el, mit lát és mit indít el a felhasználó (kamera, hálózat, modell-betöltés) — egy elhamarkodott `true` erőforrás-igényes vagy hibás ágat tenne alapértelmezetté. A `security-reviewer` futtatása KÖTELEZŐ (a hálózatot vagy kamerát nyitó flagek miatt).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha egy capability bekapcsolása a `lib/features/**` javítását igényelné, a kimenet a `stopped` jelzés — a rollout-kör nem javít terméket, hanem dönt és dokumentál.

## 1. Cél

Minden capability kapjon MÉRT, indokolt rollout-besorolást, és a nem-production alapértelmezések ezt tükrözzék — hogy egy sima buildben az legyen elérhető, ami bizonyítottan működik.

## 2. Jelenlegi állapot — mért tények

- `forEnvironment` `nonProd` értékkel: `diagnosticsEnabled`, `labModeAvailable`, `practiceEngineV2Enabled`, `migratedLearnEnabled`, `practiceDetailedHistoryEnabled`, `songTrainerV2Enabled`, `adaptiveShellEnabled`.
- **KI (`false`) minden környezetben:** `aiTutorEnabled`, `aiTutorCloudEnabled`, `practiceGeneratorEnabled`, `plannerAssistEnabled`, **10** `vision*` flag, `audioAnalysisV2Enabled` + **9** további `analysis*` flag, `recognitionRecoveryEnabled`, `recognitionShadowModeEnabled`, `newLiveStageEnabled`.
- **Dart-define-ból:** az öt `community*` flag.
- A capability-k állapota a sáv-mérésekből: a Vision (Epic 5) és az Audio Analysis 2.0 (Epic 6) implementációja kész, de a SDD-index szerint az Epic 6 „rollout stays at shadow, release blockers remain"; a Tutor (Epic 4) backendet igényel; a Generator (Epic 7) lokális; a Community backend-felcsatolása az `E15-R12`.
- `test/e2e/first_practice_offline_test.dart` a core offline út őre — a rollout nem ronthatja el.

## 3. Scope

**Benne van:** `docs/release/capability-rollout.md` — capabilityenként a NÉGY kritérium mért kiértékelése, a döntés (BE / PREVIEW / KI) és az indoklás, blokkoló esetén NEVESÍTVE (melyik kör oldja fel) · a `feature_flags.dart` `forEnvironment` ágának módosítása KIZÁRÓLAG a „BE" besorolású capabilitykre · a két flag-teszt kiegészítése az új alapértelmezésekkel (cella capabilityenként, mindhárom környezetre) · a core offline e2e újrafuttatása bizonyítékként.

**NINCS benne (tilos):**

- Production alapértelmezés megváltoztatása (a GA-scope a Chapter 12 Kör 28 dolga).
- `lib/features/**` bármely módosítása.
- Olyan capability bekapcsolása, aminek a mérce-sávja nem zöld, vagy külső erőforrást igényel (backend, API-kulcs) — az PREVIEW marad.
- `docs/adr/**` — az ADR 0492-t a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/app/config/feature_flags.dart` | a „BE" besorolású capabilityk alapértelmezése |
| `test/app/config/feature_flags_test.dart` · `test/app/feature_flags_test.dart` | capabilityenkénti cellák |
| `test/e2e/first_practice_offline_test.dart` | a core út bizonyítéka az új alapértelmezésekkel |
| `docs/release/capability-rollout.md` | ÚJ — a döntési tábla |

**Tilos zóna:** `lib/features/**` · `lib/app/routing/**` · `backend/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0492)

### 5.1 A bekapcsolás BIZONYÍTÉKHOZ kötött

Egy capability csak akkor lesz alapértelmezetten BE, ha mind a négy kritérium teljesül, és ez a táblában hivatkozással szerepel. **NEM elfogadható gyengítés:** „elkészült, tehát menjen" — az Epic 6 saját zárójelentése például nyitott release-blokkolót rögzít.

### 5.2 A külső erőforrást igénylő capability PREVIEW marad

Backendet, API-kulcsot vagy letöltendő modellt igénylő ág nem lehet alapértelmezés, amíg az erőforrás nincs a felhasználónál. **NEM elfogadható gyengítés:** bekapcsolás „úgyis hibaállapotot mutat" indoklással — az hibás alapélményt ad.

### 5.3 A core offline út sérthetetlen

A rollout után is végigjárható marad hálózat nélkül. **NEM elfogadható gyengítés:** a core út feltételessé tétele bármelyik új capabilityre.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | MINDEN capability pontosan egy besorolást kap, mind a négy kritérium mért kiértékelésével | `docs/release/capability-rollout.md` + a flag-tesztek fedettség-cellája |
| A2 | Minden „BE" capabilityhez tartozik cella mindhárom környezetre (development, lab, production) | `feature_flags_test.dart` |
| A3 | Külső erőforrást igénylő capability NEM lett alapértelmezés | `feature_flags_test.dart` (nevesített cella a tutor-cloud és a community ágra) |
| A4 | A production alapértelmezés VÁLTOZATLAN | `feature_flags_test.dart` production-cellái |
| A5 | A core offline e2e út zöld az ÚJ alapértelmezésekkel | `first_practice_offline_test.dart` |
| A6 | Minden „KI"/„PREVIEW" besorolás nevesíti a feloldó kört | a döntési tábla |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy capability bekapcsol, de a production ág is megváltozik | A4 |
| A tutor-cloud vagy a community alapértelmezetten BE lesz | A3 |
| Egy új alapértelmezés elrontja a core offline utat | A5 |
| A tábla „később" bejegyzést tartalmaz feloldó kör nélkül | A6 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** kapcsold be az `aiTutorCloudEnabled`-t `nonProd`-ra, futtasd a §7 gate-et → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart test/app/feature_flags_test.dart test/e2e/first_practice_offline_test.dart test/ui/ui_inventory_test.dart
```

## 8. Implementációs sorrend

1. A négy kritérium kiértékelése capabilityenként (mérés, nem vélemény).
2. `docs/release/capability-rollout.md` — a döntési tábla.
3. `feature_flags.dart` — kizárólag a „BE" besorolásúak.
4. A két flag-teszt cellái + a core offline e2e.
5. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Túlkapcsolás.** Egy nem kész capability alapértelmezetté tétele rontja az első élményt (A1, A3).
- **Erőforrás-igény.** A kamera/modell-betöltés gyenge eszközön az indulást lassítja — a tábla ezt kritériumként méri.
- **Production szivárgás.** A `nonProd` és a production ág összekeverése (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
