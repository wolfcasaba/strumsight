# Mi van lefejlesztve és bekötetlenül — a felmérés, mérésekkel

**Mérés dátuma:** 2026-09-12 (E18-R18…R20). A lista nem vélemény: mindegyik sor
mögött egy parancs van, ami kiadható és megismételhető.

A célja, hogy a „kössünk be mindent" kérés ne induljon újra nulláról, és hogy a
**parkolt** dolgokat senki ne nézze elfelejtettnek.

## A módszer

```bash
# 1) Képernyő, amit semmi nem konstruál
for f in $(find lib/features -name "*_screen.dart"); do
  cls=$(grep -oE "class [A-Za-z0-9_]+Screen" "$f" | head -1 | sed 's/class //')
  [ -n "$cls" ] && [ "$(grep -rl "\b$cls\b" lib/ --include=*.dart | grep -v "^$f$" | wc -l)" = 0 ] \
    && echo "UNREFERENCED $cls  $f"
done

# 2) Provider, amit a saját fájlján kívül semmi nem olvas
#    (a tiszta jel: a saját fájljában is csak a deklaráció említi)
grep -rn "^final [a-zA-Z0-9_]*Provider = " lib/ --include=*.dart
```

## 1. Parkolt rollout-felületek — NEM elfelejtett munka

Ezeket nem szabad „bekötni": a kapuk szándékosak, és az indok a
`lib/app/config/feature_flags.dart`-ban van.

| Felület | Kapu | Állapot |
|---|---|---|
| Közösség (10 képernyő) | `STRUMSIGHT_COMMUNITY` + al-flagek | **BEKÖTVE** (E18-R19), backend él |
| Kihívás-lista képernyő | — | szerveroldali hiány, lásd lent |
| Elemzés-felvétel (3 képernyő) | `audioAnalysisV2Enabled` | **define NINCS**, `forEnvironment` fixen `false` |
| AI-tutor terv-előnézet | `aiTutorEnabled` | parkolt |
| Setlist-session | `songTrainerV2Enabled` | parkolt |

### Az elemzés-felvétel külön eset, és ezt érdemes tudni

Az `audioAnalysisV2Enabled` nem csak alapból hamis: **nincs hozzá dart-define**, a
`FeatureFlags.forEnvironment` fixen `false`-ra állítja, és az
`analysisRolloutStage` így **minden buildben `v1Default`**. A `/analyze` shell-fül
eközben a **V1** `AnalyzeScreen`-re megy, ami elérhető és működik. A három capture
képernyő tehát egy **párhuzamos V2 implementáció**, nem egy hiányzó út — felkapcsolni
rollout-döntés, ami egyszerre két elemzés-felületet eredményezne.

### Öt képernyő nem úticél, hanem komponens

Ez konstruktorból mérhető, nem megítélés kérdése:

| Képernyő | Amit KÉR |
|---|---|
| `AnalysisHomeScreen` | `recentAnalyses`, `onStartRecording`, `onImportFile` |
| `AnalysisRecordingScreen` | `recorder` (élő `AnalysisRecorder`), `onFinished`, `onCancel` |
| `AnalysisProcessingScreen` | `state` (élő `AnalysisState`), `onCancel` |
| `PracticePlanPreviewScreen` | `draft`, `validationContext` |
| `SetlistSessionScreen` | `setlist`, `mode`, `availability`, `performanceRunner` |

Route-ot adni nekik azt jelentené, hogy **kitaláljuk a recordert, a draftot és a
setlistet**. Ami hiányzik, nem az útvonal, hanem a folyam, ami összeállítja őket.

**Jó hír a folyamhoz:** az agy megvan. Az `AnalysisController` teljes állapotgép
(`acquiringInput` → `recording` → `validating` → `analyze` / `cancel`), a
`createMicCapture` szállított, a `file_selector` dependency, és az
`analysisRepositoryProvider`-t a bootstrap **valóban** felülírja
(`production_repository_overrides.dart`, az E18-R01 F5 javítása). Tehát a
capture-folyam egy **kompozíciós** kör, nem egy fejlesztési — amint a rollout-döntés
megvan.

Mérve és kimondva: az `analysisCacheProvider` override nélkül **dob**, és a bootstrap
nem írja felül — de **semmi nem olvassa**, tehát a dobás elérhetetlen. Nem defekt.

## 2. Szerveroldali hiány — ez nem kliens-munka

A futó példányon (`docs/operations/casaba-backend.md`) **nincs**:

- `GET /community/challenges` (lista)
- `GET /community/challenges/{id}` (részletek)
- `GET /community/challenges/{id}/me` (saját nevezés)

Ezért a `CommunityChallengesScreen` szándékosan nincs route-olva: mindig elhasalna.
Az `AppRoutes.communityChallenges` konstans megvan, hogy egysoros legyen, amint a
szerver megkapja ezt a hármat.

## 3. Amit a felmérés valódi hibaként talált

### `practiceSessionRecorderProvider` — egy őr, ami rossz alanyt nevezett meg

A provider a placeholder-metaadat kapu miatt `NoopPracticeSessionRecorder`-t ad, és a
`practice_history_recorder_test.dart` B2 cellája ezt **„a produkciós útnak, amit a
vezérlő minden befejezésnél bejár"** nevezte. **Mérve: nem az.** A providert semmi nem
olvassa; a `practiceSessionControllerProvider` családja **inline** építi a valódi
`PracticeHistoryRecorder`-t az `inputs.definition` tényleges mode/source/id
értékeivel. A gyakorlás tehát rögzül — de az őr egy halott ágat védett, miközben azt
hitte, az élest.

Ez rosszabb, mint a védelem hiánya: egy őr, ami rossz alanyt nevez meg, mindenkit
utána abban a hitben hagy, hogy az éles út le van fedve.

**Javítva:** a provider doksija és a cella kommentje kimondja, hogy ez nem a
produkciós út, és az éles utat
`test/features/practice/practice_recorder_live_path_test.dart` védi — két külön
mechanizmusra állítva: a **típusok** (`PracticeMode` / `PracticeSource` kódjai valódi
értékek, tehát a placeholder elérhetetlen rajtuk keresztül) és a **katalógus** (egy
szállított definíció sem viseli a placeholder id-t).

### A közösségi lánc nem volt végig állítva

A bekötött képernyők a `socialGraphRepositoryProvider`-t olvassák, ami három provideren
át, egy **null rövidzárral** a közepén dől el. Ha az `accountEnabled` hamis, a
`DisabledSocialGraphRepository` minden hívásra `ConfigurationFailure`-t ad — a
képernyők renderelnek, görgetnek, és **soha nem töltenek be semmit**. Pontosan az
L652 hibaosztály, csak csendesebben. **Javítva:**
`test/features/community/community_production_chain_test.dart` mindkét irányt
állítja.

## Amit legközelebb érdemes

1. **A szerver három kihívás-útvonala** → a kihívás-képernyő egysoros route.
2. **Rollout-döntés az elemzés V2-ről** → utána a capture-folyam kompozíciós kör.
3. A `listenAndRepeat` ritmus-mód — mért válasz már van rá (ADR 0546): az app nem
   játszhat hangot, amíg pontoz.
