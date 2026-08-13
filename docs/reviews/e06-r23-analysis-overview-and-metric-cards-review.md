# E06-R23 — Review

Brief: `docs/rounds/e06-r23-analysis-overview-and-metric-cards.md`
Diff: `origin/main...sonnet-impl/e06-r23-analysis-overview-and-metric-cards`
Reviewer: Codex / gpt-5.6-terra · Dátum: 2026-08-13
Verdikt: APPROVED (a kötelező security review eredményére váró merge-döntéssel)

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

Az F1/F2 javító kör után a friss izolált review-gate és scope-audit zöld. A
kötelező külön security review még a merge előtt fut.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Öt metric-card állapot, unavailable okkal és tanáccsal | ✅ | `metric_card_test.dart`; mind az öt state lefutott a review-gate-ben. |
| 2 | Négy dokumentum-mátrix overflow nélkül | ✅ | `analysis_overview_screen_test.dart` négy dokumentum-cellája. |
| 3 | 320/600 px × 1.0/2.0 overflow-mátrix | ✅ | Mind a négy cella tesztelt; a 320/1.0 valódi overflow-t talált és a `MetricCard` `Wrap` javítása után zöld. |
| 4 | En+hu paritás, nyers kulcs nélkül | ⚠️ | Mindkét locale főcíme tesztelt, de nincs teljes megjelenített-kulcs ellenőrzés. |
| 5 | Nem color-only semantics | ✅ | Valódi-sértés próba: a `MetricCard` külső `Semantics.label` törlésére `flutter test test/features/audio_analysis/presentation/metric_card_test.dart` piros (2 elvárt semantics finder hibával), majd visszaállítva. |
| 6 | Nincs engine-import / UI confidence-küszöb | ✅ | `analysis_overview_screen_test.dart` forrásőrei; review-gate zöld. |
| 7 | Maximum-policy: pontosan 4, maradék a Részletek mögött | ✅ | A 9 insightos teszt 4 overview és 5 detail insightot mér. |
| 8 | Flag-gate route nélkül nem oldható fel | ✅ | Valódi `routerProvider`/`findMatch` teszt: flag-off nem old, flag-on+extra old, V1 `/analyze` változatlan. |
| 9 | Letiltott akció magyarázattal | ✅ | `InsightCard` disabled `Tooltip`-pel; widget- és forrásvizsgálat. |
| 10 | Metric semantics név+érték+megbízhatóság | ✅ | `MetricCard` külső semantics label, valódi-sértés próba. |
| 11 | V1 érintetlen | ✅ | Scope diffben nincs `lib/features/analyze/**`. |

## Scope-audit

`python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e06-r23 --brief docs/rounds/e06-r23-analysis-overview-and-metric-cards.md --base 86c8181adc3923f96a19ee7088e11504aa653065` → `Legacy scope audit OK` (18 path, 0 tiltott/generált). Az H3 self-heal által dokumentált `labels_adapter.dart` és regressziós teszt az aktuális brief explicit listáján szerepel.

## Megállapítások

### F1 — MAJOR — Az insight maximum-policy nem teljesíti a „pontosan 4 + Részletek” contractot

- **Fájl:** `lib/features/audio_analysis/presentation/controllers/overview_view_model.dart:234-270`, `lib/features/audio_analysis/presentation/analysis_overview_screen.dart:63-70,104-118`, `test/features/audio_analysis/presentation/analysis_overview_screen_test.dart:364-397`
- **Probléma:** A view model legfeljebb három kindből próbál slotokat készíteni; nem garantál négy insightot. A harmadik slot az első recommendation utáni *bármelyik* insightot veszi, ezért a kind-címkéje eltérhet a tényleges insightétól. A "Részletek" és az appbar action `OverviewMetricCard` listát navigál a metric-detail screenre, így a rejtett insightok nem jelennek meg sehol. A teszt ezt csak `lessThanOrEqualTo(4)`-gyel engedi át, noha a brief pontosan négyet és a maradék elérhetőségét írja elő.
- **Hatás:** Egy 9 insightos dokumentum 2-4 kártyát mutathat, a többi coaching információ elveszik; egyes insightok rossz kategóriacímkét kapnak.
- **Kötelező javítás:** A dokumentum sorrendjét/az R20 maximum-policyt hűen fogyasztó, determinisztikus négy slotot hozz létre; minden slot a saját `kind`-ját használja. Adj külön, read-only insight-details megjelenítést vagy a meglévő Részletek útvonalon egy olyan payloadot/képernyőt, amely a fennmaradó insightokat ténylegesen megjeleníti. A 9 insightos teszt `hasLength(4)`-et és a Részletek után a fennmaradó 5 insight láthatóságát mérje.
- **Ellenőrzés:** bővített `analysis_overview_screen_test.dart` és/vagy `overview_view_model_test.dart`, továbbá `tools/round-gate.sh test/features/audio_analysis test/app`.
- **Státusz:** FIXED (`45a13c0`), friss izolált gate-en ellenőrizve (`94e6758`).

### F2 — MAJOR — A kötelező route- és overflow-őrcellák hiányoznak

- **Fájl:** `test/features/audio_analysis/presentation/analysis_overview_screen_test.dart:255-340`, `lib/app/routing/app_router.dart:243-276`
- **Probléma:** A brief négy szélesség/text-scale kombinációt követel, de a tesztből két kombináció hiányzik. A flag-gated route implementálva van, de nincs teszt, amely `audioAnalysisV2Enabled == false` mellett igazolja, hogy `/analysis/overview` valóban nem oldható fel és a V1 route-ok változatlanok.
- **Hatás:** A jelenlegi zöld suite nem fogja meg a kiszélesített betűméret miatti overflow-t a két hiányzó cellában, illetve egy jövőbeli route-regisztrációs regressziót.
- **Kötelező javítás:** Egészítsd ki a 320/1.0 és 600/2.0 overflow-cellákkal. A meglévő, engedélyezett presentation tesztből vagy egy már meglévő router-tesztben mérd, hogy flag-off mellett nincs V2 route, flag-on + érvényes `AnalysisDocument` extrával megnyílik, és a V1 `/analyze` route változatlan marad.
- **Ellenőrzés:** célzott widget/router teszt, majd a kötelező gate.
- **Státusz:** FIXED (`45a13c0`), friss izolált gate-en ellenőrizve (`94e6758`).

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrizve |
|---|---|
| `tools/round-gate.sh test/features/audio_analysis test/app` | ✅ friss izolált `/tmp/review-e06-r23-fix` klónban a `94e6758` HEAD-en: format, analyze, 465 audio-analysis + 69 app teszt, architecture, secrets és l10n zöld. |
| Scope audit | ✅ kézi Python audit zöld. |
| Valódi-sértés próba | ✅ a MetricCard semantics label ideiglenes törlésére célzott teszt piros, majd a változás visszaállítva. |
| CI (teljes suite + property + APK) | ⏳ még nincs final exact-SHA dispatch; merge előtt kötelező. |

## Merge-döntés

F1 és F2 lezárt; a normál review APPROVED. Az ADR 0052 szerinti merge-hez az
exact-SHA teljes CI/property/APK és a kötelező security review zöld eredménye szükséges.
