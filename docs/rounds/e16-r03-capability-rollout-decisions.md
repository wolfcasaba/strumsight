# E16-R03 — Capability rollout-döntések: mi legyen BE alapból

- **Státusz:** PREPARED (előre megírva 2026-09-02, kód olvasva: `main @ 11d0d2bb`)
- **Típus:** Chapter 16 (Kompozíció és rollout), Kör 3
- **Kör-azonosító:** `E16-R03`
- **Branch:** `<motor>/e16-r03-capability-rollout-decisions`
- **Előfeltétel:** `E16-R02` merge-elve (a bekötési hiányok lezárva — rollout csak működő capabilityre adható)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`ADR 0492`](../adr/0492-capability-rollout-decision-evidence-and-nonprod-boundary.md) — MEGÍRVA a pre-flightban; a szám mérten szabad volt (lemez, ágak, foglalási markerek), `O_EXCL` markerrel rögzítve.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "rollout boundary availability flag shipping decision entry point"` → **[ADR 0197](../adr/0197-song-trainer-shipping-rollout-boundary.md)** („a rollout-határ áthelyezése és a belépési pont mint a rollout része") és **[ADR 0065](../adr/0065-practice-engine-v2-parallel-rollout.md)**. A repó MÉRT mintája: a rollout nem puszta flag-billentés, hanem belépési pont + bizonyíték.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/app/config/feature_flags.dart` `forEnvironment` ágát, és listázd a MÉRT alapértelmezéseket. **A pre-flight ezt elvégezte — az eredmény a §0.0.1, és három ponton MEGCÁFOLTA ennek a bekezdésnek az eredeti szövegét.**

## 0.0.1 Pre-flight brief-revízió (Claude/Sonnet 5 orchestrátor, 2026-09-03, `main @ d7014b9d`)

A mérés a `tool/release/verify_ga_scope.py` SAJÁT, fail-closed
`forEnvironment`-olvasójával futott (`_extract_for_environment_field_assignments`),
nem szemre. Normatív forrás: [ADR 0492](../adr/0492-capability-rollout-decision-evidence-and-nonprod-boundary.md).

**Visszakeresett előzmény (ADR 0312, `knowledge-rag`):**
[L534](../LESSONS.md#l534) (flag-alapértelmezés flip → 53 bukás 19 fájlban, az
E15-R02 H3-ja), [ADR 0220](../adr/0220-audio-analysis-v2-parallel-rollout-boundary.md)
(a kilenc Epic 6 flag OFF, a `feature_flags.dart` tilos zóna, hacsak a brief nem
sorolja fel), [ADR 0491](../adr/0491-practice-generator-entry-point-and-rollout.md) D2,
[ADR 0197](../adr/0197-song-trainer-shipping-rollout-boundary.md),
[ADR 0065](../adr/0065-practice-engine-v2-parallel-rollout.md).

### R1 — A §2 „mért tények" listája három ponton TÉVES volt (javítva)

| Állítás a briefben | MÉRT valóság |
|---|---|
| `practiceGeneratorEnabled` KI minden környezetben | **`nonProd`** — E15-R07 óta (ADR 0491 D2). Nem a kör dönt róla; már BE. |
| „vision **10** flag" | **11** vision flag |
| „`audioAnalysisV2Enabled` + **9** további analysis flag" | **9** analysis flag ÖSSZESEN (`audioAnalysisV2Enabled` + 8) |

**A mérés teljes kimenete (40 mező):**

- **`nonProd` (8):** `diagnosticsEnabled`, `labModeAvailable`,
  `practiceEngineV2Enabled`, `migratedLearnEnabled`,
  `practiceDetailedHistoryEnabled`, `songTrainerV2Enabled`,
  `practiceGeneratorEnabled`, `adaptiveShellEnabled`
- **`false` minden környezetben (26):** tutor 2 (`aiTutorEnabled`,
  `aiTutorCloudEnabled`) + `plannerAssistEnabled` + vision 11 + analysis 9 +
  recognition 3 (`recognitionRecoveryEnabled`, `recognitionShadowModeEnabled`,
  `newLiveStageEnabled`)
- **`const bool.fromEnvironment(...)` (5):** a community flagek
- **hívó-adta átmenő érték (1):** `accountEnabled`

A §2 alábbi szövege ennek megfelelően javítva.

### R2 — A `feature_flags.dart` `forEnvironment` törzse NÉGY gépileg felismert alakot enged (ADR 0492 D3)

A `tool/release/verify_ga_scope.py` fail-closed parsere pontosan ezeket ismeri:
`nonProd` · `true` · `false` · `const bool.fromEnvironment(...)` · a mező saját
nevével azonos átmenő érték. **Bármi más — `environment == AppEnvironment.lab`,
`nonProd && x`, ternáris — `VerifyError`**, ami a
`test/tooling/ga_scope_test.dart`-ot pirosra viszi. Az a fájl a kör
`allowed_paths`-án KÍVÜL van → **H3 egy egyébként helyes döntésből**. Ha egy
rollout-döntés nem fejezhető ki ezzel a négy alakkal, az a döntés **PREVIEW**, és
a feloldó kör a táblába kerül — a parser alakját NEM tágítjuk.

### R3 — Flip ELŐTT hatósugár-mérés, különben STOP (ADR 0492 D4, L534)

Az `appConfigProvider` alapértéke MAGA a
`FeatureFlags.forEnvironment(AppEnvironment.development, …)`, ezért egy
`false → nonProd` flip minden, a valódi `StrumSightApp`-ot pumpáló widget-teszt
konfigurációját elmozdítja. Mérve (L534, E15-R02): **egyetlen sor → 53 bukás 19
fájlban**, a kör H3-mal állt meg implementer-dispatch NÉLKÜL. 24 tesztfájl
hivatkozik közvetlenül a `forEnvironment`-re, a valódi hatósugár ennél nagyobb.

**Kötelező eljárás minden tervezett flipre, a flip véglegesítése ELŐTT:**

1. futtasd a §7 gate-et a flippel, majd flip NÉLKÜL — a KÜLÖNBSÉG az oksági hatás;
2. ha a különbség kizárólag a `gate_tests` fájljait érinti → mehet, igazítsd őket
   az ÚJ viselkedéshez;
3. ha bármely, az `allowed_paths`-on kívüli fájlt pirosra visz → **`stopped`
   jelzés** a mért fájllistával. **TILOS** a lista tágítása és TILOS az
   `appConfigProvider`-override-dal elrejtett alapértelmezés (ADR 0467 D9).

Egy „nulla flip" kimenet — ha egyetlen capability sem teljesíti mind a négy
kritériumot — **érvényes és elfogadott** eredmény: a kör terméke ilyenkor a
döntési tábla, és a `feature_flags.dart` változatlan marad.

### R4 — A `docs/release/` NÉV-ütközések feloldása (ADR 0492 D2)

A `docs/release/` MA két, hasonló nevű, MÁS tárgyú dokumentumot hordoz:

| Létező fájl | Tárgya | Gépi őre |
|---|---|---|
| `ga-scope.md` | GA/**production** besorolás, zárt `ga\|preview\|disabled\|postponed` készlet 16 flag-kulcsra (ADR 0489) | `tool/release/verify_ga_scope.py` + `test/tooling/ga_scope_test.dart` |
| `rollout-decision.md` | staged **százalékos** rollout-csomag, megfigyelési ablakok (E12-R32) | `tool/release/verify_rollout_decision.py` + `test/tooling/rollout_decision_test.dart` |

A kör ÚJ `capability-rollout.md`-ja a **nem-production (development/lab)
alapértelmezésekről** dönt. A fejlécének ki kell mondania mindkét elhatárolást, és
a dokumentum a **production alapértelmezésről saját állítást nem tesz** — arra a
`ga-scope.md`-re hivatkozik (különben két igazságforrás keletkezne ugyanarra a
mezőre).

### R5 — A `gate_tests` lista BŐVÜLT (szigorítás, nem tágítás)

Három, a körön KÍVÜL élő őr került a `gate_tests`-be, mert a kör diffje pirosra
viheti őket, és a célzott kapunak mérnie kell ezt (S14/L593 hibaosztály):

| Őr | Mit mér | Melyik ADR 0492-döntést |
|---|---|---|
| `test/tooling/ga_scope_test.dart` | a `forEnvironment` parse-olhatósága + a `ga-scope.md` `production_default` oszlopa | D3, D8 |
| `test/app/analysis_rollout_flags_test.dart` | az Epic 6 flagek rollout-állapota (ADR 0220) | D1, D5 |
| `test/app/app_config_test.dart` | az `appConfigProvider` alapértéke — a L534 csatolás premisszája | D4 |

Ezek `gate_tests`-ben vannak, de az `allowed_paths`-ban **NINCSENEK**: zöldnek
kell maradniuk **módosítás nélkül**. Ha valamelyik csak a fájl átírásával lenne
zöld, az a §0 STOP-protokoll esete.

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
  "test/tooling/ga_scope_test.dart",
  "test/app/analysis_rollout_flags_test.dart",
  "test/app/app_config_test.dart",
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

- `forEnvironment` `nonProd` értékkel (**8**, MÉRVE — §0.0.1 R1): `diagnosticsEnabled`, `labModeAvailable`, `practiceEngineV2Enabled`, `migratedLearnEnabled`, `practiceDetailedHistoryEnabled`, `songTrainerV2Enabled`, **`practiceGeneratorEnabled`** (ADR 0491 D2 óta — a brief eredeti szövege tévesen KI-ként sorolta), `adaptiveShellEnabled`.
- **KI (`false`) minden környezetben (26, MÉRVE):** `aiTutorEnabled`, `aiTutorCloudEnabled`, `plannerAssistEnabled`, **11** `vision*` flag, **9** `analysis*` flag (`audioAnalysisV2Enabled` + 8), `recognitionRecoveryEnabled`, `recognitionShadowModeEnabled`, `newLiveStageEnabled`.
- **Dart-define-ból:** az öt `community*` flag.
- A capability-k állapota a sáv-mérésekből: a Vision (Epic 5) és az Audio Analysis 2.0 (Epic 6) implementációja kész, de a SDD-index szerint az Epic 6 „rollout stays at shadow, release blockers remain"; a Tutor (Epic 4) backendet igényel; a Generator (Epic 7) lokális; a Community backend-felcsatolása az `E15-R12`.
- `test/e2e/first_practice_offline_test.dart` a core offline út őre — a rollout nem ronthatja el.

## 3. Scope

**Benne van:** `docs/release/capability-rollout.md` — capabilityenként a NÉGY kritérium mért kiértékelése, a döntés (BE / PREVIEW / KI) és az indoklás, blokkoló esetén NEVESÍTVE (melyik kör oldja fel) · a `feature_flags.dart` `forEnvironment` ágának módosítása KIZÁRÓLAG a „BE" besorolású capabilitykre · a két flag-teszt kiegészítése az új alapértelmezésekkel (cella capabilityenként, mindhárom környezetre) · a core offline e2e újrafuttatása bizonyítékként.

**A „nulla flip" ÉRVÉNYES kimenet** (§0.0.1 R3): ha a négy kritérium mért
kiértékelése szerint egyetlen capability sem minősül „BE"-nek, a
`feature_flags.dart` VÁLTOZATLAN marad, és a kör terméke a döntési tábla + a
besorolásokat pinnelő cellák. Ez nem hiányos kör — a §5.1 szerint épp ez a mérce.

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

## 5. Kötött architekturális döntések ([ADR 0492](../adr/0492-capability-rollout-decision-evidence-and-nonprod-boundary.md))

> Az ADR a pre-flightban MEGÍRVA. A lenti §5.1–§5.3 az ADR **D1 · D5 · D6**
> döntése; a **D2** (két dokumentum, két hatókör), a **D3** (négy gépi alak),
> a **D4** (flip előtti hatósugár-mérés) és a **D8** (production változatlan) a
> §0.0.1 R2–R5 pontjaiban él, és ugyanúgy KÖTELEZŐ.

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
| A7 | A `capability-rollout.md` a NEM-production döntés: a fejléce elhatárolja magát a `ga-scope.md`-től és a `rollout-decision.md`-től, és production alapértelmezésről saját állítást nem tesz (ADR 0492 D2) | `feature_flags_test.dart` cella, amely a dokumentumot FÁJLKÉNT olvassa (a `rollout_decision_test.dart` mintája) |
| A8 | A `forEnvironment` törzse a négy gépileg felismert alak egyikét tartja minden mezőre (ADR 0492 D3) | `test/tooling/ga_scope_test.dart` — módosítás NÉLKÜL zöld |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy capability bekapcsol, de a production ág is megváltozik | A4 |
| A tutor-cloud vagy a community alapértelmezetten BE lesz | A3 |
| Egy új alapértelmezés elrontja a core offline utat | A5 |
| A tábla „később" bejegyzést tartalmaz feloldó kör nélkül | A6 |
| A tábla saját production-alapértelmezést állít (második igazságforrás a `ga-scope.md` mellett) | A7 |
| A `forEnvironment` egy mezője ternáriust vagy `environment == …` alakot kap | A8 (`ga_scope_test.dart` → `VerifyError`) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** kapcsold be az `aiTutorCloudEnabled`-t `nonProd`-ra, futtasd a §7 gate-et → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart test/app/feature_flags_test.dart test/e2e/first_practice_offline_test.dart test/ui/ui_inventory_test.dart test/tooling/ga_scope_test.dart test/app/analysis_rollout_flags_test.dart test/app/app_config_test.dart
```

A lista a `gate_tests` blokkot tükrözi (§0.0.1 R5). Az utolsó három őr a körön
KÍVÜL él: zöldnek kell maradniuk **módosítás nélkül**.

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
