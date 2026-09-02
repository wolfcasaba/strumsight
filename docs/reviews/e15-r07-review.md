# E15-R07 — kör-review (ADR 0055)

- **Reviewer:** Claude (Opus 5, orchestrátor-székből, read-only)
- **Dátum:** 2026-09-02
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Ág:** `sonnet-impl/e15-r07-practice-generator-migration`
- **Review-alap:** `1ff15285` (pre-flight) → `9179f00f` (F1 implementáció)
- **Brief:** `docs/rounds/e15-r07-practice-generator-migration.md` (§0.0.C revízióval)
- **ADR:** `docs/adr/0491-practice-generator-entry-point-and-rollout.md`

## 1. Scope-audit

A wrapper gépi auditja: `scope_audit=ok`, `scope_audit_base=1ff15285`,
`scope_audit_changed=14`. Saját ellenőrzés (`git diff --name-only`): mind a 14
fájl az `allowed_paths` listán van. A munkafa a jelzéskor tiszta
(`git status --short` üres; a jelzésbeli `dirty_files=1` maga a jelzésfájl volt
a kiírás pillanatában — utólag ellenőrizve, nem elfedett munka).

**Kiemelten ellenőrizve — a merge-elt őr által védett tilalmak:**

- `lib/features/practice_generator/presentation/providers/practice_generator_providers.dart`
  és `.../data/local/local_practice_evidence_repository.dart` **NEM** szerepel a
  diffben (csak `import`-ként olvasva) — a
  `tools/tests/test_e15_r07_composition_prerequisite.py` mind a 10 cellája zöld.
- A `practice_generator` `application/`, `domain/`, `data/` rétege érintetlen —
  a STOP-protokoll betartva.

## 2. Acceptance — leletenkénti mérés

| # | Kritérium | Verdikt | Bizonyíték (a reviewer FÜGGETLEN mérése) |
|---|---|---|---|
| A1′ | 2 képernyő `unreachable` → `reachable`, a másik 4 változatlan | ✅ | `dart run tool/check_screen_reachability.dart`: `PlanSetupScreen` → `app_router.dart:377` (`practiceGeneratorEnabled`), `TodayPlanScreen` → `:385` (`practiceGeneratorEnabled`); `PlanPreview`/`PlanPrivacy`/`Weekly`/`PlanChangeReview` mind `—` (unreachable). Összesítő: `Reachable: 70` (68-ról), `Flag-gated: 27` (25-ről) |
| A1″ | a 3–6. képernyőre NINCS route; a bekötöttek FELÉPÜLNEK | ✅ | `grep -nE "PlanPreviewScreen\|PlanPrivacyScreen\|WeeklyPlanScreen\|PlanChangeReviewScreen" lib/app/routing/app_router.dart` → nincs találat. A két ON-cella `expect(tester.takeException(), isNull)` + `findsOneWidget` |
| A2 | a route-ok a flag MÖGÖTT vannak (ON/OFF cellapár) | ✅ | `app_router.dart`: `if (practiceGeneratorEnabled) ...[ GoRoute … ]`, a `practiceEnabled` blokktól függetlenül. `app_router_test.dart`: 2 ON-cella + 1 OFF-cella |
| A3 | `nonProd` ON, `production` OFF, default OFF | ✅ | `feature_flags.dart:88` `practiceGeneratorEnabled: nonProd`. Mind a HÁROM pinnelő cella megvan és mér: default `isFalse`, production `isFalse`, nonProd `isTrue` |
| A4 | a belépési pontról a flow megnyitható | ✅ | `practice_hub_screen.dart` `_PlanBuilderCard` → `context.go(AppRoutes.practiceGeneratorSetup)`, flag-kapuzva; `practice_hub_screen_test.dart` új cellái |
| A4′ | a fél lépés ŐSZINTE | ✅ | a kártya `l10n.planSetupTitle` = „Build your practice plan" / „Gyakorlási terv összeállítása" (cselekvés, NEM kész terv) + `planSetupGoalTitle` = „What would you like to work on?" / „Min szeretnél dolgozni?". Nincs bevezetett `onComplete` callback, nincs „generálás elindult" visszajelzés |
| A5 | a registry `killSwitchPath`-ja az ÚJ igazságot írja | ✅ | `feature_flag_registry.dart:149-154`: a régi „hardcoded to `false` in every environment" szöveg helyett a `nonProd` határ + a kill switch tényleges módja; `adr: '0491'` |
| A6 | `ui_inventory` `hasLength(96)` VÁLTOZATLAN | ✅ | `Measured screens: 96`; a kör nem hozott létre és nem törölt képernyőt |
| A7/A12 | F2 migráltság + dokumentumok | ✅ | mind a 6 képernyő `MIGRATED` (újramérve); `migration-status.md` és `retirement-plan.md` frissítve |
| A11 | nincs beégetett felhasználói szöveg | ✅ | a belépési pont MINDEN szövege ARB-kulcsból; a két kulcs `en` ÉS `hu` alatt is létezik (`app_en.arb:2640,2665`, `app_hu.arb:2601,2626`) |

## 3. A mért néma-bukások elleni három ellenőrzés (L21)

1. **A `done` jelzés `dirty_files` mezője** — kivizsgálva (lásd §1), nem elfedett munka.
2. **A CI `headSha` ↔ lokális HEAD** — `9179f00f286cdc1bae315c04af107a98475d4e7c`
   mindkét oldalon (§5).
3. **A commit megtörtént** — `9179f00f`, 14 fájl, a munkafa tiszta.

## 4. A LEGFONTOSABB lelet-vizsgálat: nem vákuum-zöld-e az A1″? (L583)

Az `E15-R14` mért bukása ([L583](../LESSONS.md#l583)) pont az volt, hogy a
„minden függőség felépül" cella a **saját override-jaitól** lett zöld. Ezért
külön megmértem, hogy az `app_router_test.dart` `_pumpRouter` harness-e
felülírja-e a generátor providereit:

**NEM.** A harness override-listája (`app_router_test.dart:95-125`) kizárólag
infrastruktúrát fak-ol (`preferenceOverrides()`, `fakeAudioOverrides()`,
`strumEngineProvider`, `onboardingSeenProvider`, `accountEnabledProvider`,
`tokenStoreProvider`, `authRepositoryProvider`, `songRepositoryProvider`,
`songAssetRepositoryProvider`, `appConfigProvider`) — a
`planSetupControllerProvider` és a `todayPlanControllerProvider`
**a VALÓDI kompozíciós gyökérből (ADR 0482) oldódik fel**. A cella tehát
ténylegesen azt bizonyítja, amit állít: a két route felépül az igazi
providerekből, `UnimplementedError` nélkül. **A L583 leckéje helyesen alkalmazva.**

## 5. Cella-integritás (§5.5 — a jogosultság PONTOSAN a belépési pont)

- Bevezetett `skip` / `@Skip` / `markTestSkipped`: **0**
  (`git diff … test/ | grep -E "^\+.*(skip:|@Skip|markTestSkipped)"` → üres).
- Hozzáadott cellák: **10**. „Törölt" cella: **1** — és az nem törlés, hanem
  ugyanannak a cellának a szerződés-frissítése (`factory keeps both flags off
  in non-production` → `factory turns practiceGeneratorEnabled on but keeps
  plannerAssistEnabled off (ADR 0491)`), az A3 által megkövetelt alakban. A
  cella továbbra is MÉR (mindkét flaget állítja).
- A hub típusát pinnelő őrök (`screen_size_guard`, `practice_a11y_audit`,
  `practice_hub_screen`, `practice_routing`, `release_flow_text_scale`,
  `test/app/navigation/**`) egyike sem gyengült; a hub képernyő típusa nem
  cserélődött le — a diff egy flag-kapuzott kártyát VESZ FEL rá.

## 6. Elismerés — a kör egy valódi mérési csapdát dokumentált

Az implementer §10-ben rögzítette, hogy a `practiceGeneratorEnabled` melletti
doc-comment eredetileg tartalmazta a két képernyő class-nevét, és a
`tool/check_screen_reachability.dart` ezt guard NÉLKÜLI deklaratív
referenciaként mérte → a `isFlagGated` hamisan `false`-ra váltott. A comment
átírása után a mérés `Flag-gated: 27`-re javult. Ez pontosan az a fajta
mérés-a-mérőeszközről lelet, amit a kör-jegyzőkönyvnek meg kell őriznie —
lásd a záró LESSONS-bejegyzést.

## 7. Nyitott lelet

**Nincs.** BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1 (§8).

### 8. NOTE — nem a kör hibája, a következő körnek szól

A flow **fél lépés marad**: a Setup-varázsló vége nem generál, a 6-ból 4
képernyő `unreachable`. Ez az ADR 0491 D3/D5 szerinti, tudatosan vállalt és
dokumentált állapot, nem hiányosság — a feloldása a két seam
(`exerciseCandidateResolverProvider`, `generationPlanInputBuilderProvider`)
konkrét implementációja + `main.dart` boot-override, ami önálló kör.

## VÉGSŐ DÖNTÉS: **APPROVED**

A zöld kapu további feltétele a CI exact-SHA zöldje (`full-gate.yml` +
`router-ci.yml` a merge SHA-n) — lásd §5 és a merge-lépés.
