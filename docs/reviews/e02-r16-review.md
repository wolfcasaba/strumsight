# Review — E02-R16 (Rhythm-only + Free Practice)

- **Branch:** `codex/e02-r16-rhythm-and-free-practice`
- **Implementer commit:** `2031855` (motor: **MiniMax M3**)
- **Reviewer:** Claude (Opus 4.8), read-only, izolált `/tmp/review-e02r16` klón (origin @ `2031855`)
- **ADR:** [0082](../adr/0082-free-practice-honest-summary.md)
- **Verdict:** ✅ **APPROVED** — nincs nyitott BLOCKER/MAJOR/MINOR; 1 NOTE.

## 1. Gate — reviewer-oldali újrafuttatás

A záró gate-et magam futtattam a friss klónban:

```
tools/round-gate.sh test/features/practice/ test/property/free_practice_property_test.dart test/core/l10n_parity_test.dart
```

- **Első futás:** `analyze PIROS (1)` — `AppLocalizations` / `app_localizations.dart`
  hiányzik. Ez a **generált l10n**, ami `.gitignore`-olt (CLAUDE.md); friss
  klónban `flutter gen-l10n` előtt nem létezik. **NEM kód-hiba.** `flutter
  gen-l10n` után `flutter analyze lib/ test/ tool/` → **„No issues found!"**.
- **Második futás** (l10n generálva): **MINDEN GATE ZÖLD** — format · analyze ·
  test `test/features/practice/` · test property · test `l10n_parity` ·
  architecture. (A teljes suite + property + APK a CI-ban, ADR 0053.)

## 2. Scope-audit

`git diff --name-only bbec16a..2031855` — kizárólag a brief §4 engedélyezett
fájljai: a két új domain-modell/-service, az eligibility, a két mód-nézet, a
session-screen becsatolás (11 sor), a két ARB, öt teszt, és a brief §10.
**`lib/features/streak|progress|learn` és `practice/application`: 0 sor.**
Nincs listán kívüli fájl. ✔

## 3. Acceptance criteria — tételes bizonyíték

| Pont | Verdikt | Bizonyíték (reviewer-mérés) |
|---|---|---|
| **A1** | ✅ | `practice_direction_scorer.dart:119-121` `applicableCount==0 → MetricNotApplicable` (NEM 0); `practice_chord_scorer.dart:90` chord `NotApplicable`. `rhythm_only_view_test.dart` 5 cella (direction-less/bearing, Available, NotApplicable, InsufficientData). |
| **A2** | ✅ | **Valódi-sértés próba (§11 mandátum):** a `practice_score_aggregator.dart` overall null-ágát ideiglenesen `MetricAvailable(0)`-ra rontva a pre-existing `practice_score_aggregator_test.dart:167` „free practice has no overall score" **PIROS lett** (`Expected MetricNotApplicable, Actual MetricAvailable`); visszaállítva zöld. A `freePracticeOpen` üres súlyok → `availableWeightTotal==0` → `overall MetricNotApplicable`, `outcome notScored` (aggr:76-81, teszt:175-179). |
| **A3** | ✅ | `free_practice_summarizer.dart:88-105` down/up + arány; `summarizer_test.dart:18` 10 strum (7/3)→70/30; `:61` 0 strum → `FreePracticeDirectionRatioInsufficientData` (NEM 0%). `StrumDirection` mérve: csak `{down, up}` → `else up++` helyes. |
| **A4** | ✅ | MAD-alap, `_minimumStrumCountForStability=4` (summarizer:143-171); tesztek 3→Insufficient, 4→0, 12 egyenletes→0, 12+1500ms gap → medián NEM rándul (deviations medián=0). Python-ellenőrzés a §10-ben egyezik. |
| **A5** | ✅ | `_chordTimeline` (summarizer:110-131) utolsó szegmens `ceiling=activeDuration`-ig; `FreePracticeChordSegment.label` **`String?`**, null=explicit „nincs akkord" (`free_practice_summary.dart:36`); UI `practiceFreePracticeChordNone` „No chord". |
| **A6** | ✅ | `PracticeSessionEligibility.isEligible` **`||`**, mindhárom `>=` (elig:62-65); `eligibility_test.dart` 9 küszöb-cella (19999/20000/20001 ms, 3/4/5, 7/8/9). |
| **A7** | ✅ | **Szöveg-audit mindkét ARB-ben:** a Free Practice/Rhythm blokkban NINCS „accuracy/pass/score/pontosság". `practiceFreePracticePercent` **kizárólag** a le/fel arányra (`free_practice_view.dart:181,189` `downRatio/upRatio*100`) — ez ADR 0082 §2 szerint engedélyezett TÉNY, nem score. InsufficientData → „Not enough data yet"/„Még nincs elég adat"; 0 jel → `_NoSignalCard` „No strums heard yet". |
| **A8** | ✅ | View-tesztek `takeException()==null` 320×568 és 915×412; `Semantics(container,label)` a Card-on; `l10n_parity_test` zöld. |
| **A9** | ✅ | `free_practice_property_test.dart` (SEED 42→CI run_id): 4 invariáns × 80 trial; soha-nem-dob, `down+up==strumCount`, monoton predikátum, timeline≤active — mind zöld. |
| **A10** | ✅ | `domain_purity_test` + architecture gate zöld (0 új deviation); diff a §4 listán belül; streak/progress/learn 0 sor. |

## 4. Próbatesztek (eldobható, dokumentálva)

1. **A2 valódi-sértés** (fent, §3 A2) — a guard bizonyítottan piros→zöld.
2. **`gen-l10n` után analyze** — „No issues found!" — igazolja, hogy a gate-1
   PIROS pusztán a friss-klón l10n-artefaktum, nem kódhiba.
3. **`StrumDirection` enum mérve** (`{down, up}`) — az `else up++` ág nem
   nyel el harmadik értéket; `down+up==strumCount` konstrukció szerint tart.

## 5. NOTE (nem blokkol)

- **N1 — property-teszt bemenet-scope.** A `_randomInput`
  (`free_practice_property_test.dart:207,190,201`) **rendezi** a megfigyeléseket
  és az `at`-okat `activeDuration`-on belülre szorítja. Ez a summarizer
  dokumentált előfeltétele (observations `at` szerint növekvő, gateway-enforced;
  `free_practice_summarizer.dart:26-28`), tehát legitim. Következmény: a
  **timeline-≤-active** invariáns szerződés-sértő (rendezetlen / aktív időn túli)
  bemenetre elvben megsérthető a negatív-klipp miatt — a valós úton nem
  fordulhat elő. Ártalmatlan; **R17+ hardening-javaslat:** a `_chordTimeline`
  defenzív rendezése vagy egy `assert(isSorted)`. Nem a kör hatóköre.

## 6. Architektúra / termékhatárok

Domain pure (nincs clock/IO/random/detektor a summarizerben és a predikátumban);
core↛feature nem sérül; a nézetek csak `AppLocalizations`-t és a domain-modellt
látják; nincs audio/hálózat/mic/secret érintés. ✔

## Összegzés

A kör pontosan az ADR 0082 „ne állítsunk többet, mint amit mérünk" elvét
valósítja meg: a „nincs adat" mindenütt `NotApplicable`/`InsufficientData`
(soha nem 0), a Free Practice `overall` bizonyítottan `MetricNotApplicable`, és
a UI sehol nem közöl score/accuracy/pass állítást. **APPROVED** — mehet a
zöld-kapus merge.
