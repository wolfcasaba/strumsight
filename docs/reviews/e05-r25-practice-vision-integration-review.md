# E05-R25 — Review

Brief: `docs/rounds/e05-r25-practice-vision-integration.md`
ADR: [`docs/adr/0192-practice-vision-integration-contract.md`](../adr/0192-practice-vision-integration-contract.md)
Diff: `git diff origin/main...codex/e05-r25-practice-vision-integration`
Reviewer: Claude Sonnet 5 (orchestrator) · Dátum: 2026-08-08
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

Independent gate re-run in an isolated `/tmp` clone: **all 7 gate steps
green** (format, analyze, `test/features/practice` — 913 tests, `test/features/vision`
— 522 tests, architecture, secrets, l10n). Scope-audit: exact match against
the (corrected) `allowed_paths`, 13/13 files, zero out-of-scope changes.
Ran my own falsification probe against the audio-parity fixture (independent
of the implementer's own documented probe) — confirmed it turns RED on a
real regression.

**Process note (not a code finding):** the first dispatch correctly
`stopped` on a genuine gap — `docs/adr/0192-…md` (the orchestrator's own
pre-flight artifact) was missing from `allowed_paths`. Fixed via a
documented brief revision (§0.0/8) before resuming; the implementer's
already-completed work was verified unchanged and correct across the pause.
See `HANDOFF.md`/git log for the two-commit pre-flight history
(`b82259e`, `97c5928`) if reconstructing the timeline.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Audio-parity fixture (audio score/metrics/history entry bitre azonos vision ON/OFF) | ✅ | `test/features/practice/domain/practice_session_result_vision_test.dart:21-43` — JSON-projekciós összehasonlítás minden audio-mezőre + `PracticeSessionResultHistoryMapper.toHistoryEntry()` teljes egyenlőség. Reviewer-oldali falszifikáció: `scorePoints` 900→999 a vision-változaton → a teszt PIROSRA fordult (`Differ at offset 525`), majd visszaállítva. |
| 2 | Vision-állapot mátrix (`unavailable`/`degraded`/`good`, `VisionQualitySummary.overall`-ból) | ✅ | `lib/features/vision/domain/integration/vision_practice_contract.dart:105-113` (`visionPracticeQualityFor`) — pontosan a §0.0/4-ben előírt leképezés (`good→good`, `needsImprovement→degraded`, `notObservable`/`null→unavailable`). `test/features/practice/data/practice_vision_adapter_test.dart:9-33` mindhárom `VisionMetricState` értéken végigfut. |
| 3 | Capability-gate teszt a 3 pilotra (hiányzó capability → audio-only, nem letiltott) | ✅ | `practice_vision_adapter_test.dart:47-70` — mindhárom `VisionPracticeContracts.pilots` elemre `isPracticeAvailable=true` + `mode=audioOnly`, amikor `availableCapabilities` üres. |
| 4 | Visszamenőleges API-kompatibilitás (a/b/c, revideálva §0.0/1) | ✅ | (a) `flutter analyze lib/ test/ tool/` — „No issues found!" a teljes fán (mind a 12 meglévő `PracticeSessionResult(…)` hívóhelyet lefedve, a `vision` argumentum nélkül is fordulnak); (b) `practice_session_result_vision_test.dart:13-19` explicit `vision: null` egyenlőség+hash; (c) ugyanaz a fájl 21-43 sor (mapper-érintetlenség). |
| 5 | Architektúra-őr (`allowlist` nem bővült) | ✅ | Izolált klónban: `Architecture dependencies OK (12 allowlisted deviation(s))` — pontosan ugyanaz a 12, mint a `tool/check_architecture.dart` `architectureAllowlist` konstansában eleve szereplő 12 (mind DSP-vonatkozású, egyik sem e körből). `grep -rn "import.*features/vision" lib/features/practice/` — mind a 3 találat `vision/public.dart`-ra mutat, nincs mély import. |
| 6 | Lokalizációs paritás | ✅ | Izolált klónban: `L10n parity OK (en → hu, 1001 message(s))`. |
| 7 | Valódi-sértés próba (§10) | ✅ | Implementer saját próbája (§10, prózában dokumentálva) + reviewer-oldali független megismétlés (ld. #1 bizonyíték) — mindkettő piros → helyreállítás. |

## Scope-audit

```
git diff --stat origin/main...HEAD
```

13 fájl, mind a (javított) `allowed_paths` listán — 0 kívüli fájl:

- `docs/adr/0192-practice-vision-integration-contract.md` (ÚJ)
- `docs/rounds/e05-r25-practice-vision-integration.md`
- `lib/features/practice/data/vision/practice_vision_adapter.dart` (ÚJ)
- `lib/features/practice/domain/model/practice_session_result.dart`
- `lib/features/practice/presentation/widgets/practice_vision_dimension.dart` (ÚJ)
- `lib/features/practice/public.dart`
- `lib/features/vision/domain/integration/vision_practice_contract.dart` (ÚJ)
- `lib/features/vision/public.dart`
- `lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb`
- `test/features/practice/data/practice_vision_adapter_test.dart` (ÚJ)
- `test/features/practice/domain/practice_session_result_vision_test.dart` (ÚJ)
- `test/features/practice/presentation/practice_vision_dimension_test.dart` (ÚJ)

## Architektúra + termékhatárok (AGENTS.md §5/§6)

- **Cross-feature import fegyelem:** `practice` → `vision` kizárólag
  `vision/public.dart`-on át (3 találat, mind helyes cél) — ellenőrizve grep-pel
  ÉS a gépi architektúra-őrrel egyaránt.
- **`VisionPracticeContract` a vision oldalon él** (`lib/features/vision/domain/integration/`),
  a saját feature-én belüli (nem cross-feature) importokkal éri el a
  meglévő `FrettingCapability`/`PickingCapability`/`PostureCapability`
  enumokat és a `VisionQualitySummary`-t — nem cross-feature reláció, tehát
  nem esik a `public.dart`-szabály alá, helyesen.
- **Nincs raw media / landmark expozíció:** a `PracticeVisionAdapter` és a
  `PracticeVisionDimension` widget kizárólag a már aggregált
  `VisionSessionResult.qualitySummary.overall`-t olvassa; egyik új fájl sem
  importál semmit a `vision/domain/landmarks/` vagy `vision/domain/geometry/`
  alól. Ez folytatja az E05-R24 „raw-media-mentes" garanciát a Practice
  oldalra.
- **Erőforrás-lifecycle:** N/A — a `PracticeVisionAdapter` tiszta függvény,
  nincs `.acquire(`/lease/subscription (§0.0/7 mérése megerősítve az
  élő kódon).
- **Nincs hardcode-olt UI-szöveg a domainben/adapterben** — a widget minden
  megjelenő szövege `AppLocalizations`-ból jön; a domain/adapter réteg
  (`vision_practice_contract.dart`, `practice_vision_adapter.dart`) nem
  tartalmaz felhasználónak szóló string-literált.
- **`practice_result_screen.dart` érintetlen** (nincs a diffben) — a
  `PracticeVisionDimension` szándékosan nem bekötött, a widget saját
  doc-commentje ezt explicit rögzíti.

## Megállapítások

### N1 — NOTE — Egy ARB-kulcs jelenleg nem hívott UI-ból

- **Fájl:** `lib/l10n/app_en.arb:1357`, `lib/l10n/app_hu.arb` (megfelelő sor) —
  `practiceVisionDimensionUnavailable`
- **Megfigyelés:** a `PracticeVisionDimension` widget `unavailable` esetén
  `SizedBox.shrink()`-et ad vissza (helyesen, a brief §6 „nincs" előírása
  szerint) — ez a kulcs jelenleg nincs hívva egyetlen widget-kódból sem.
- **Hatás:** nincs — a l10n-paritás gate kulcsonként ellenőriz, nem
  hívottság szerint; nem build- vagy teszt-hiba.
- **Javasolt irány:** nem blokkoló; ha egy jövőbeli kör (pl. a summary-widget
  bekötése) mégsem használja fel, egy későbbi ARB-tisztítás törölheti.
- **Státusz:** OPEN (nem blokkol, follow-up).

## Gate-bizonyíték (saját kézzel, izolált `/tmp/review-e05-r25` klónban)

```
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/practice                                zöld
    test test/features/vision                                  zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
EXIT_CODE=0
```

`test test/features/practice`: `+913` (`All tests passed!`).
`test test/features/vision`: `+522 ~2` (`All tests passed!`).

## Dedikált security-review (risk = "high")

[`docs/reviews/e05-r25-practice-vision-integration-security.md`](e05-r25-practice-vision-integration-security.md)
— **PASS**, 0 CRITICAL/BLOCKER/MAJOR, 1 MINOR + 4 NOTE, saját izolált
`/tmp` klónban futtatott gate-tel és próbákkal, függetlenül az itteni
review-tól.

A security-review **MINOR-1** finomabb bizonyítékkal ugyanazt a
nem-tranzitív guard-korlátot írja le, amit ez a jelentés is (§ Architektúra)
és az ADR 0192 Döntés 3 is elismer, de eggyel tovább megy: a
`vision/public.dart` nemcsak UI-screeneket, hanem **nyers landmark/pose/
geometry/koordináta típusokat és landmark-provider osztályokat is**
re-exportál, és sem `check_architecture.dart`, sem `domain_purity_test.dart`
nem korlátozza, MELYIK szimbólumot importálja a practice oldal a barrelen
át — csak azt nézik, hogy az import célja `/public.dart`-ra végződik-e. **MA
nincs áthágás** (R25 egyetlen új/módosított fájlja sem hivatkozik nyers
típusra — grep-pel megerősítve mindkét review-ban), ezért ez **MINOR,
follow-up**, nem BLOCKER/MAJOR — de mivel R25 nyitja meg az ELSŐ
`practice → vision/public.dart` élt, és a következő kör (E05-R26, Song
Trainer vision-integráció) ugyanezt a barrelt fogja importálni, a javítás
(szimbólum-szintű negatív guard vagy a barrel domain-safe/raw-UI szétválasztása)
**az R26 pre-flightja előtt** esedékes — rögzítve `HANDOFF.md` §3-ban és
`docs/LESSONS.md`-ben a záró rituálék részeként, R26 pre-flight bemenetének.

## Végső verdikt

**APPROVED.** Mindkét független review (tartalmi + security) 0 nyitott
BLOCKER/MAJORT talált; a nyitott MINOR-ok (N1 itt, MINOR-1 + 4 NOTE a
security-review-ban) egyike sem érinti a §6 acceptance-et vagy a mai
viselkedést, mind dokumentált follow-up. CI: Full Gate
[31263769978](https://github.com/wolfcasaba/strumsight/actions/runs/31263769978)
**success** + Router CI (auto-triggered a `docs/rounds/**` útvonalon)
**success**, mindkettő a pontos merge-előtti tip `2a0d79a`-n. Mehet a
squash-merge.
