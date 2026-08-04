# Epic 4 AI Tutor — kiinduló adat- és rollout-baseline

- **Rögzítve:** 2026-08-04
- **Forrásbaseline:** `main` @ `8d702324130d53b4a5b81c254652ca2107f9f524`
- **Kör:** E04-R01
- **Határ:** ez adatforrás-leltár és rögzített fixture-kimenet; nem vezet be
  tutor-context assemblert, route-ot, hálózati hívást vagy új coaching
  viselkedést.

## Osztályozási szabály

| Jelölés | Jelentés a leltárban |
| --- | --- |
| **Mért tény** | Egy konkrét gyakorlásból vagy elemzett klipből származó, strukturált mérési/scoring eredmény. |
| **Számított aggregátum** | A mért vagy tárolt elemekből determinisztikusan összesített érték. |
| **UI-only** | Megjelenítési, navigációs vagy felhasználói beállítás; önmagában nem játékosi evidence. |

## Jelenlegi adatforrások

| Forrás és publikus elérés | Adat | Osztály | Tutorba vihető alapegység | R01-korlát |
| --- | --- | --- | --- | --- |
| Practice — `features/practice/public.dart`, `PracticeSessionResult` | Sessionazonosító, időtartam, finish reason, `PracticeAttemptResult`, stabil tempó | **Mért tény** | Egy befejezett session strukturált eredménye és az utolsó/best attempt | Csak későbbi public adapter olvashatja; a session nem ad át mikrofonframe-et. |
| Practice — `PracticeMetrics` és `PracticeVerdict` | Completion/rhythm/direction/chord/overall metrikák, target- és combo-számok, score, timing offset/bias, célonkénti verdict | **Mért tény** | A rendelkezésre álló metrikák és verdictek, az `MetricInsufficientData`/`MetricNotApplicable` állapottal együtt | Hiányzó dimenzió nem egészíthető ki feltételezéssel. |
| Practice — `PracticeCoach` → `PracticeInsight` | Egy stabil insight code, opcionális secondary/recommendation code | **Számított aggregátum** | Determinisztikus coaching-kimenet, nem szabad szöveg | A rögzített fixture-kimenet lent található; ez nem új tutor-viselkedés. |
| Analyze — `features/analyze/public.dart`, `AnalyzeResult` | Időtartam, BPM, akkord-idővonal és strumok direction/confidence mezővel | **Mért tény** | Korlátozott, időbélyeges elemzési eredmény | A context-adapternek a célhoz szükséges részhalmazt kell kiválasztania. |
| Analyze — `downCount`, `upCount`, `chordSummary`, Lab ML/DSP agreement | Iránydarabszámok, akkordösszefoglaló, opcionális diagnosztikai egyezés | **Számított aggregátum** | Rövidített összegzés vagy explicit Lab-diagnosztika | A Lab-diagnosztika opcionális; nem változtatja meg az alap Analyze eredményt. |
| Progress — `features/progress/public.dart`, `PracticeEntry` | Lokálisan tárolt nap, forrás, másodperc, stroke, akkorddarabszám, opcionális direction accuracy | **Mért tény** | Dátumhoz és forráshoz kötött gyakorlási bejegyzés | A 0 vagy `null` érték is jelentéssel bír: ismeretlen/nem mért adatot nem szabad pontossággá alakítani. |
| Progress — `PracticeStats`, `DayTotal` | Összes session/idő/stroke, napok, forrásonkénti darabszám, átlag/best direction accuracy, heti sor | **Számított aggregátum** | Időablakos progress-summary | Az időablakot, a bemeneteket és a számítás verzióját a későbbi adapternek rögzítenie kell. |
| Streak — `features/streak/public.dart`, `StreakData` | Current/longest streak, last practice day, freezes, total days | **Számított aggregátum** | Helyi szokás-összegzés | Nem játékminőségi mérés; nem használható technikai állítás alapjaként. |
| Streak — `DailyChallenge` és badge/screen megjelenítés | Napi seedből generált pattern, név, glyph, megjelenített státusz | **UI-only** | Alapértelmezetten nincs tutor-contextben | A pattern nem bizonyítja, hogy a felhasználó eljátszotta. |
| Settings — capo, balkezes mód, A4, input/visual latency | Felhasználói hangszer- és eszközbeállítások; latency kalibrációs értékek | **UI-only** | Később csak explicit purpose esetén, például konfigurációs magyarázathoz | Nem játékteljesítmény-evidence; a latency külön eszközkalibráció, nem technikai játékdiagnózis. |
| Settings — Lab mode | Diagnosztikai felhasználói toggle | **UI-only** | Alapértelmezetten nincs tutor-contextben | Nem consent és nem cloud-AI engedély. |
| Song Trainer — `SongTrainerResult` | Practice session result, revisionált song event-referenciájú verdictek | **Mért tény** | Egy scored session eredménye és stabil song-koordinátája | Csak a későbbi Song result adapteren át használható. |
| Song Trainer — `SongMeasureTrainerResult`, `SongSectionTrainerResult` | Measure/section szerinti verdict-lista és average event score | **Számított aggregátum** | Problémás measure/section összegzés | Az átlag nem írhatja felül a hozzá tartozó evidence hiányát vagy bizonytalanságát. |
| App route-ok, screen state, lokalizált címkék és route-argumentek | Aktuális képernyő, szöveg, navigációs paraméterek | **UI-only** | Alapértelmezetten nincs tutor-contextben | R01 nem regisztrál AI Tutor route-ot. |

## Rögzített deterministic coaching fixture-snapshot

Ez a blokk **rögzített bemenet → kimenet snapshot**, nem a `PracticeCoach`
szabályainak viselkedésleírása. Forrása a meglévő
`test/features/practice/domain/practice_coach_test.dart` `biasLate` fixture-je
és a production `PracticeCoach`/`PracticeInsight` típusa (ADR 0084).

```yaml
fixture: practice_coach_bias_late_v1
input:
  practiceSessionResult:
    id: session-1
    activeDuration: 30s
    pausedDuration: 0s
    finishReason: userFinished
    highestStableTempoBpm: 90
    coachingSummary: []
    finalAttempt:
      index: 0
      tempoBpm: 90
      outcome: passed
      metrics:
        completion: 0.70
        rhythm: 0.60
        direction: 0.85
        chord: 0.85
        overall: 0.75
        totalTargets: 16
        resolvedTargets: 14
        maxCombo: 8
        scorePoints: 800
        meanAbsoluteOffset: 20ms
        timingBias: 0ms
  practiceSessionContext:
    strumCount: 30
    pairedEventCount: 20
    timingBias: 30ms
    lateShare: 0.80
    earlyShare: null
    slowestChordPair: null
output:
  code: practice.insight.bias_late
  secondaryCode: null
  recommendationKind: null
```

## Adatvédelmi határ

**Nyers audio nem része a tutor contextnek.** Sem PCM/frame, sem WAV/klip,
sem abból visszaállítható payload nem léphet át a későbbi
`TutorContextSnapshot` vagy tutor-request határon. A fenti leltárban csak a
helyben már előállított, strukturált mérési eredmények és azok determinisztikus
aggregátumai jelölhetők adapter-bemenetnek. A cloud consentet, a storage
consentet és az evaluation consentet az ADR 0132 szerint külön kell kezelni.

## Rollout és rollback

### R01 állapot

- `aiTutorEnabled` és `aiTutorCloudEnabled` minden környezetben default OFF.
- Nincs AI Tutor route, UI, gateway vagy hálózati wiring.
- `FeatureFlags.usesNetwork` változatlan; a cloud flag jelenleg nem kapcsol be
  URL-validációt vagy transportot.
- A kijelentkezett/offline 0-request út változatlanul a
  `offline_network_guard_test.dart` felelőssége.

### Következő rollout-lépcsők

1. **Internal deterministic:** későbbi, explicit build-konfigurációban csak
   `aiTutorEnabled` kapcsolható be; cloud flag OFF marad. A PracticeCoach
   fallback és a public-adapter evidence csak lokálisan használható.
2. **Lab / opt-in beta:** csak consent-, redaction-, context-inspection- és
   deletion-flow után indulhat. A cloud flag továbbra is külön kapu.
3. **Korlátozott production:** csak az R14 backend proxy, usage guard,
   observability és az Epic 4 safety/evaluation gate-ek után. A kliens nem
   hívhat közvetlen model-provider SDK-t.
4. **Széles rollout:** csak a teljes suite, property gate, APK és a valós
   offline/network-loss evidence után növelhető.

### Rollback elv

1. Cloud incidensnél először az `aiTutorCloudEnabled` értékét kell OFF-ra
   állítani a kiadási konfigurációban; a lokális deterministic út ettől
   független marad.
2. Feature- vagy safety incidensnél az `aiTutorEnabled` is OFF-ra állítandó,
   így az AI Tutor route és integráció a későbbi wiringben nem lehet elérhető.
3. Ha a hiba a release artefaktumban nem kapcsolható vissza biztonságosan,
   vissza kell térni az előző, mindkét flaggel OFF kiadásra. R01-ben nincs
   remote kill switch vagy futásidős rollout-mechanizmus.
4. A rollback nem törölhet csendben user-adatot; a későbbi memory és consent
   törlés/retention folyamatot külön, ellenőrizhető műveletként kell kezelni.

## Toolchain és teszt-baseline

- Flutter `3.44.2` stable és Dart `^3.12.2` a
  `docs/development/00-environment-setup.md` és `pubspec.yaml` szerint.
- Az alkalmazás két forráslokalizációt követ: `lib/l10n/app_en.arb` és
  `lib/l10n/app_hu.arb`; a generált `app_localizations*.dart` checkout után
  előkészítést igényel.
- A backend meglévő tesztterületei: auth, diagnostics, hardening, migrations
  és settings (`backend/tests/`). R01 nem módosít backend fájlt.
- A teljes Flutter suite, a property gate, a backend suite és az APK
  bizonyítéka CI-feladat; R01 lokális záró ellenőrzése kizárólag a kijelölt
  `tools/round-gate.sh` hívás.
