# Chapter 17 — Teljes bekötés (Full wiring)

- **Nyitva:** 2026-09-05, a felhasználó jelzésére („nem látszik a teljes fejlesztés és
  funkció még az appban" → „csináljuk meg úgy hogy minden be legyen kapcsolva és
  minden működjön amit a 328 kör alatt fejlesztve lett").
- **Mért alap:** `main @ b17e08ef`, `dart run tool/check_screen_reachability.dart`.
- **Terv szerzője:** Claude (Opus 5), orchesztrátor.

## 1. A mért probléma

A `tool/check_screen_reachability.dart` mérése a fenti SHA-n:

```
Measured screens: 96. Reachable: 73. Unreachable: 23. Flag-gated: 27.
```

A `build-apk.yml` által szállított `development` APK-ra levetítve (a
`FeatureFlags.forEnvironment` értékeivel):

| kategória | db | ok |
|---|---|---|
| élő a szállított APK-ban | **61** | — |
| routolt, de KI a dev buildben | **12** | `forEnvironment` MINDEN környezetben `false`-ra köti (AI Tutor 5, Vision 3, Analysis V2 4) |
| **sehonnan nem hivatkozott (halott)** | **23** | nincs route ÉS nincs imperatív hívás |

### 1.1 A 12 flag-kapuzott képernyő — MEGOLDVA build-oldalon

A `preview/full-ui-showcase-e14` ág (`30e3cc1b`) a `STRUMSIGHT_PREVIEW_ALL`
define-nal 18 rollout-kaput kapcsol be egyszerre; a `lab-apk.yml` ebből
telepíthető APK-t épít (release `preview-full-e14`). **Ez build-előnézet, NEM
rollout-döntés** — az ág a `main`-re nem megy vissza. A production rollout
külön, ADR-hez kötött döntés (Chapter 12 Kör 28, Epic 6/7 release-blokkolók).

### 1.2 A 23 halott képernyő — EZ a fejezet tárgya

| feature | db | mért akadály |
|---|---|---|
| `community` | **13** | 7 domain-repository interfészből csak **3** impl létezik (`challenge`, `profile`, `relationship`); a `feed`, `post`, `club`, `notification` impl HIÁNYZIK. **0 Riverpod-provider** a feature-ben, és **11 `throw UnimplementedError`** override-seam várja a production bekötést. |
| `practice_generator` | 4 | `practice_generator_providers.dart:88` és `:151` — két `UnimplementedError` seam (exercise-candidate resolver, generation-plan-input builder). A 6 képernyőből 2 (`PlanSetup`, `TodayPlan`) MÁR routolt. |
| `audio_analysis` (capture) | 3 | Az Analysis **V2** felvevő-ága. A `data/capture/analysis_recorder.dart` létezik, kompozíció nincs. A legacy `AnalyzeScreen` felvevő útja MŰKÖDIK — ez párhuzamos V2 ág, nem törött alapfunkció. |
| `ai_tutor` | 1 | `PracticePlanPreviewScreen` — injektált `PracticePlanDraft`-ot vár, nincs előállító. |
| `onboarding` | 1 | `FirstWinStageScreen` — a `onboardingFirstWinConfidenceProvider` LÉTEZIK, csak a belépés hiányzik. |
| `song_trainer` | 1 | `SetlistSessionScreen` — a `SetlistSessionController` LÉTEZIK, kompozíció nincs. |

**Fontos, mért kikötés:** a 23 halott képernyő NEM törött alapfunkció. A
termék gerince (Live, Analyze, Practice, Songs, Learn, Library, Progress,
Profile, Tuner, Metronome, Gamification) routolt és az `E16-R05` full-app
bejárás szerint valós adatot vagy explicit állapotot állít. A 23 a
BEFEJEZETLEN peremvidék, amit a Community (13) ural.

## 2. A fejezet körei

**A sorrend kötött:** a kompozíciós gyorsnyereségek (R01–R04) mennek előre,
mert a domain/application rétegük MÁR kész — csak provider + route hiányzik.
A Community sáv (R07–R13) a legnagyobb, és **külső függősége van**: a
`backend/` FastAPI szolgáltatásnak futnia kell, és a telefonnak elérnie
(a Lab-mód cloudflared-alagútjának mintájára).

| Kör | Tárgy | Csoport |
|---|---|---|
| `E17-R01` | Onboarding First-Win állomás bekötése | A — kompozíció |
| `E17-R02` | Analysis V2 felvevő-ág bekötése (3 képernyő) | A — kompozíció |
| `E17-R03` | Song Trainer setlist-session bekötése | A — kompozíció |
| `E17-R04` | AI Tutor gyakorlóterv-előnézet bekötése | A — kompozíció |
| `E17-R05` | A Practice Generator két `UnimplementedError` seamje | B — seam |
| `E17-R06` | A Practice Generator 4 maradék képernyőjének bekötése | B — kompozíció |
| `E17-R07` | Community HTTP-alap: kliens, hiba-taxonómia, auth-fejléc | C — adatréteg |
| `E17-R08` | `CommunityFeedRepository` impl + feed-cache production override | C — adatréteg |
| `E17-R09` | `CommunityPostRepository` impl (poszt, komment, könyvjelző) | C — adatréteg |
| `E17-R10` | `CommunityClubRepository` impl (klub-lista, -részlet, tagkezelés) | C — adatréteg |
| `E17-R11` | `NotificationRepository` + `SocialGraphRepository` impl | C — adatréteg |
| `E17-R12` | Community route-ok, gate-képernyő és shell-belépés | C — kompozíció |
| `E17-R13` | Backend `community_enabled` bekapcsolás + e2e füstteszt | C — backend |
| `E17-R14` | Zárókör: 96/96 elérhetőség, teljes-app bejárás, APK-evidencia | záró |

## 3. A fejezet befejezési mércéje

`dart run tool/check_screen_reachability.dart` a záró körön:
**`Unreachable: 0`** — és ez a szám a kör `gate_tests`-ében őrzött cella,
nem egy doksi-mondat.

A `E17-R14` a `docs/release/full-app-verification.md` mintájára MÉRT
bejárást ad, és APK-evidenciát a `build-apk.yml` zöld futásából.

## 4. Amit a fejezet SZÁNDÉKOSAN nem tesz

- **Nem hoz rollout-döntést.** A 26 hardkódolt `false` flag production
  bekapcsolása külön, ADR-hez kötött döntés — ez a fejezet a KÉPERNYŐK
  elérhetőségét oldja meg, nem a kapuk termékdöntését.
- **Nem nyúl a felismerési útvonalhoz.** A `recognitionRecoveryEnabled` /
  `recognitionShadowModeEnabled` / `newLiveStageEnabled` az ADR 0271
  aktiválási szerződése alatt marad; azt a Chapter 14 viszi.
- **Nem épít új képernyőt.** Minden kör MÁR LÉTEZŐ képernyőt köt be.
