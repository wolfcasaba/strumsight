# StrumSight Software Design Document

## Chapter 14 — Recognition Accuracy & Useful UI Recovery

**Dokumentumverzió:** 1.0  
**Állapot:** Codex-fejlesztésre kész, valós eszközös kapukkal  
**Auditált csomag:** `strumsight-main (1).zip`  
**Audit dátuma:** 2026-08-09  
**Fókusz:** fel/le pengetés, akkordfelismerés, megbízható Live visszajelzés, valóban hasznos napi gyakorlási UI  
**Végrehajtási elv:** egy kör = egy branch/PR; a következő kör csak zöld kapu és review után indul

---

# 1. Vezetői döntés

A StrumSight kódbázisa technikailag jóval előrébb jár annál, amit a jelenlegi alkalmazás felülete megmutat. Sok feature, teszt, SDD, AI Tutor-, Practice-, Song Trainer- és Vision-alap már elkészült vagy részben elkészült. A termék legfontosabb ígérete azonban még nem elég erős:

> **A felhasználó nem bízhat stabilan abban, hogy a kijelzett akkord és a fel/le pengetési nyíl helyes.**

Ezért a következő fejlesztési szakaszban nem új feature-ök halmozása a helyes prioritás. Először a felismerési magot és a fő gyakorlási felületet kell rendbe tenni.

A Recovery Program négy alapelve:

1. **A „nem biztos” jobb, mint a magabiztosan rossz válasz.**
2. **Minden felismerési állítás legyen mérhető, kalibrált és visszakövethető.**
3. **Synthetic green nem jelent valós termékkészültséget.**
4. **A UI ne detektort mutasson, hanem következő hasznos lépést adjon a gitárosnak.**

A Gamification, Community, Offline AI és Vision felhasználói rolloutja addig maradjon másodlagos, amíg az itt rögzített Alpha/Beta felismerési kapuk nem teljesülnek.

---

# 2. Audit módszere és korlátai

A feltöltött ZIP teljes statikus kódauditja készült el. A csomagban körülbelül:

- **690 Dart forrásfájl**;
- **495 Dart tesztfájl**;
- 18 feature könyvtár;
- 12 repositoryban lévő SDD fejezet;
- Epic 1–5 completion reportok;
- valós-audio baseline és ML asset manifest található.

Az auditkörnyezetben **nem volt telepítve Flutter vagy Dart**, ezért ebben az ellenőrzésben nem futott `flutter analyze`, `flutter test` vagy APK build. A repositoryban dokumentált korábbi CI-gate eredményeket bizonyítékként figyelembe vettem, de azokat itt nem reprodukáltam. Ez a dokumentum ezért:

- kód- és architektúra-audit;
- meglévő mérési bizonyíték elemzése;
- kutatásalapú recovery terv;
- nem új, független build-verifikáció.

---

# 3. SDD és implementáció jelenlegi állapota

| Terület | Auditált állapot | Következtetés |
|---|---|---|
| Core Platform / Epic 1 | completion report és kiterjedt infrastruktúra jelen van | technikailag erős alap, valódi eszközös evidence továbbra is fontos |
| Practice Engine / Epic 2 | domain/application és production session wiring dokumentált | értékes feature, de a fő navigáció nem teszi központivá |
| Song Trainer / Epic 3 | completion report és széles implementáció jelen van, release blockerekkel | használható termékké csak stabil felismerési alap után érdemes tenni |
| AI Tutor / Epic 4 | completion evidence jelen van, feature flaggel kikapcsolva | nem sürgősebb a felismerési pontosságnál |
| Computer Vision / Epic 5 | technikai implementáció evidence; minden vision flag false; modellek deferred | jelenleg nem felhasználói feature |
| Audio Analysis / későbbi fejezetek | tervek és részimplementációk | ne tereljék el a fókuszt a Live magról |
| Chapter 13 UI/UX | **nincs benne a feltöltött repositoryban** | a Codex nem tudja hivatalos repo-specifikációként követni |

A legfontosabb termékprobléma nem az, hogy kevés kód készült. Az a probléma, hogy a fejlesztés szélessége megelőzte a fő felhasználói ígéret megbízhatóságát és láthatóságát.

---

# 4. Kritikus auditmegállapítások

## 4.1 A jelenlegi UI technikai feature-listát, nem gitáros munkafolyamatot mutat

A `lib/app/home_shell.dart` és `lib/app/routing/app_route.dart` jelenlegi fő navigációja:

```text
Live | Analyze | Learn | Library | Settings
```

A Chapter 13-ban tervezett task-orientált irány ezzel szemben:

```text
Today | Practice | Songs | Coach | Profile
```

A Practice V2 és Song Trainer V2 csak non-production környezetben aktív, az AI Tutor és minden Vision flag kikapcsolt. Emiatt a felhasználó a sok elkészült háttérmunka ellenére egy szűk detektoralkalmazást lát.

## 4.2 A Live UI látványosan felerősíti a felismerési hibát

A Live képernyő fő eleme jelenleg egy nagy chord-filmstrip:

- a legújabb akkord óriási hero kártya;
- korábbi akkordok balra zsugorodnak;
- shimmer, pulse, slide és glow animációk;
- nagy down/up nyíl;
- egyetlen confidence bar.

A `chord_timeline_provider.dart` minden megerősítetlen labelváltást új vizuális eseménnyé emel. Ha a recognizer C → G → C között téved, a UI ezt három magabiztos, látványos kártyaként mutathatja. Ez rontja a bizalmat.

A Live UI jelenleg nem mutatja egyértelműen:

- külön a chord és a direction bizonyosságát;
- a provisional/confirmed különbséget;
- a „nem biztos” állapotot;
- a jelminőség problémáját;
- hogy a CRNN vagy a fallback heuristic fut-e;
- mit tegyen a felhasználó a javításhoz.

## 4.3 A LiveFrame túl kevés információt visz a UI-nak

A `LiveFrame` nem tartalmaz:

- chord confidence-et;
- chord unknown/no-chord valószínűséget;
- direction down/up/no-strum raw valószínűségeket;
- calibrated decision margin-t;
- signal quality state-et;
- candidate/provisional/confirmed állapotot;
- reject reason-t;
- model/runtime azonosítót;
- verdict latencyt.

A `LivePipeline` rendelkezik `chordConfidence` getterrel, de azt nem teszi bele a frame-be. Emiatt a UI confidence barja lényegében csak a legutóbbi strum confidence-et reprezentálja, miközben a felhasználó könnyen az egész felismerés bizonyosságának hiheti.

## 4.4 A fel/le pengetés pontatlansága mérési bizonyítékkal is látszik

A jelenlegi iránypipeline:

```text
SuperFlux onset candidate
        ↓
~70 ms post-onset audio ablak
        ↓
3-class CRNN: down / up / no-strum
        ↓
no-strum gate
        ↓
kötelező down vagy up döntés
```

A `ml/live_3c_threshold.json` saját eval bizonyítéka:

- true-strum retention: **94,98%**;
- false-onset rejection: **92,97%**;
- direction accuracy a true strumokon: **80,68%**.

Ez azt jelenti, hogy a modell saját eval foldján is körülbelül minden ötödik elfogadott valódi pengetés iránya hibás. Ráadásul a no-strum gate után a kód mindig down vagy up döntést hoz; nincs külön irány-margin alapú abstention.

A valós telefonos baseline onset F1 értékei:

| Tűrés | F1 |
|---:|---:|
| 25 ms | 40,427% |
| 50 ms | 67,391% |
| 100 ms | 85,201% |

Tehát a probléma két részből áll:

1. a pengetési esemény időpontját sem találja mindig el pontosan;
2. az elfogadott esemény iránya sem elég megbízható.

További UX-probléma, hogy a hero nyíl az utolsó strum után akár két másodpercig sticky marad. A felhasználó így egy régi irányt is aktuális visszajelzésnek érzékelhet.

## 4.5 A Live akkordfelismerés nem a szállított Chord CRNN-t használja

A Live pipeline jelenlegi chord útja:

```text
16 384 mintás NNLS chroma (~370 ms @ 44.1 kHz)
        ↓
bass + treble chord dictionary
        ↓
Viterbi smoothing
        ↓
tonalness gate
        ↓
confidence EMA + Schmitt latch
```

A repositoryban van `assets/ml/chord_crnn.bin`, 25 kimenettel (`N.C.` + 24 maj/min), parity tesztekkel, de ez az Analyze/Lab útban van bekötve, nem a Live döntési útban.

A valós telefonos baseline:

- chord accuracy: **67,069%**;
- majority baseline: **18,832%**;
- minor subset: **83,333%**, de csak 222 esemény;
- corpus: 11 767 event, 98%-ban dúr.

Különösen gyenge recallok:

| Akkord | Recall |
|---|---:|
| C# major | 0,0% |
| D major | 41,7% |
| Bb major | 56,0% |
| F major | 58,1% |
| C major | 67,4% |

Ez nem általánosít minden felhasználóra, mert a corpus egyetlen, erősen egyoldalú disztribúció. Viszont elég ahhoz, hogy a felhasználói panaszt technikai szempontból megalapozottnak tekintsük.

## 4.6 A jelenlegi confidence nem elég a bizalomhoz

A kódban már szerepel manuális piecewise calibration, mert a nyers CRNN softmax túl magabiztosnak bizonyult. Ez jó felismerés, de a jelenlegi megoldás még nem ad teljes selective-prediction rendszert:

- nincs risk–coverage optimalizálás;
- nincs subgroup calibration;
- nincs külön OOD/unknown chord kezelés;
- a UI százalékot mutathat akkor is, amikor a modell korlátai fontosabbak lennének;
- a model confidence nem azonos a teljes end-to-end esemény helyességével.

---

# 5. Kutatási következtetések

## 5.1 A joint onset + direction + chord modell a legerősebb következő kutatási irány

A 2025-ös *Joint Transcription of Acoustic Guitar Strumming Directions and Chords* munka:

- 90 perc valós gitárfelvételt gyűjtött három gitárostól;
- telefon-, pickup- és kézmozgásadatot használt annotációhoz;
- 4 óra szintetikus strumming adatot generált;
- 28 strumming patternt, több tempót, pick/finger technikát és hangerőt használt;
- egy CRNN-ben közösen tanulta a down/up onset regressiont és a chord classificationt;
- ±6 félhang pitch augmentationt használt címketranszponálással;
- valós telefonos és szintetikus adat kombinációjával jelentősen javította a mikrofonos eredményt.

A legfontosabb termék-következtetés: **nem biztos, hogy a generic onset detector + külön direction classifier hosszú távon a legjobb architektúra**. A joint modell közvetlenül down és up onset görbéket tanul, így a direction nem csak egy későbbi címke egy esetleg hibás onseten.

## 5.2 A valós és szintetikus adat együtt értékes, de valódi holdout nélkül félrevezető

A kutatásban a szintetikus adat realism-augmentációt kapott: reverb, háttérzaj, EQ/filter, compression, distortion, fret noise, tapping/clapping és random SNR. A StrumSightnak is szüksége van ilyen adatra, de a release-döntés kizárólag nem látott játékos/eszköz/gitár spliten történhet.

## 5.3 Chordnál a kontextus, strukturált reprezentáció és class balancing fontos

A ChordFormer kutatás a convolution + long-range context kombinációját, strukturált chord reprezentációt és reweighted loss-t használ a ritka chord osztályok kezelésére. A StrumSight első célja továbbra is 24 maj/min + N.C./unknown lehet, de a C# és D típusú class collapse ellen balanced sampling és strukturált root/quality spike indokolt.

## 5.4 A confidence-t kalibrálni kell, és a modellnek szabad nemet mondania

A modern neurális modellek confidence értéke gyakran nem felel meg a valódi helyességi valószínűségnek. A temperature scaling egyszerű, jól ismert baseline. A selective classification kutatások szerint az abstention – a modell „nem tudom” válasza – közvetlenül használható a hibaarány csökkentésére, coverage árán.

A StrumSightnál a helyes cél:

```text
maximize coverage
subject to accepted prediction accuracy >= target
```

Nem az a cél, hogy minden strumra legyen nyíl.

## 5.5 SuperFlux maradjon baseline, ne legyen az egyetlen stratégia

A SuperFlux maximum filterrel csökkenti a vibrato okozta false onseteket, causal és valós időben használható. Ez értékes baseline és fallback. A gitár strumming saját zajai és irányosztályozása azonban külön feladat, ezért joint modellel és hard-negative corpusszal össze kell vetni.

## 5.6 A UI-nak adaptívnak és funkcióorientáltnak kell lennie

Flutter hivatalos irányelve alapján a rendelkezésre álló helyhez kell igazítani a navigációt: kis ablakban NavigationBar, nagyobb ablakban NavigationRail/supporting pane. A UI-t 200%-os text scalinggel, high contrasttal, TalkBackkel és legalább 48×48-as tap targettel kell ellenőrizni. Az állapotot nem szabad kizárólag színnel közölni.

---

# 6. Cél felismerési architektúra

```text
Microphone capture
    ↓
Audio route + runtime metadata
    ↓
Signal Quality Analyzer
    ↓
Shared causal audio frontend
    ├── Legacy SuperFlux + 3c CRNN          (baseline/fallback)
    ├── Candidate joint strum model         (shadow → primary)
    ├── Legacy NNLS/Viterbi chord path      (baseline/fallback)
    └── Candidate Chord CRNN / hybrid       (shadow → primary)
    ↓
Temporal Fusion + Recognition Stabilizer
    ↓
Confidence Calibration + Select/Reject Policy
    ↓
RecognitionFrame V2
    ↓
Free Play / Guided Practice / Accuracy Lab UI
```

## 6.1 Kötelező döntési állapotok

```text
candidate     — onset/chord jelölt, még nem mutatható biztosként
provisional   — rövid, vizuálisan visszafogott előjelzés
confirmed     — release gate szerint elfogadott
uncertain     — van evidence, de nem elég biztos
rejected      — no-strum, no-chord, quality vagy open-set miatt elutasítva
expired       — régi event, többé nem aktuális
```

## 6.2 Kötelező UI-szabály

A UI soha nem készíthet saját confidence logikát. Csak a domain által adott:

- decision;
- calibrated confidence;
- reject reason;
- signal quality;
- provisional/confirmed állapot

alapján renderelhet.

## 6.3 Free és Guided mód szétválasztása

**Free Play:** csak audio evidence. Expected chord prior tilos.  
**Guided Practice:** a cél ismert, de a prior nem írhatja felül a rossz audio evidence-t.  
**Accuracy Lab:** a felhasználó korrigálhat, az adat provenance-szel menthető.

---

# 7. Javasolt mérési és release kapuk

Az alábbiak **termékcélok**, nem garantált eredmények. A corpus bővülése után review-val módosíthatók, de nem szépíthetők utólag egy rossz release elfogadásához.

## 7.1 Minimum saját validation corpus

Beta előtt legalább:

- 8 külön gitáros;
- 6 külön telefonmodell;
- 4 gitár;
- pick és finger;
- quiet/medium/loud;
- legalább 4 szoba és több telefon–gitár távolság;
- 24 maj/min chord kiegyensúlyozott supporttal;
- hard-negative audio;
- player/device/guitar grouped holdout.

## 7.2 Strum Alpha kapu

| Metrika | Minimum |
|---|---:|
| Onset F1 @50 ms | 0,82 |
| End-to-end direction macro-F1 | 0,80 |
| Accepted direction accuracy | 0,90 |
| Coverage az accepted accuracy mellett | 0,70 |
| False visible arrow hard-negative audión | <= 2 / perc |
| Verdict latency p50 | <= 180 ms |
| Verdict latency p95 | <= 280 ms |

## 7.3 Strum Beta/GA cél

| Metrika | Beta cél |
|---|---:|
| Onset F1 @50 ms | >= 0,87 |
| Down F1 | >= 0,88 |
| Up F1 | >= 0,84 |
| Accepted direction accuracy | >= 0,93 |
| Coverage | >= 0,80 |
| False visible arrow hard-negative audión | <= 1 / perc |
| p95 verdict latency | <= 250 ms |
| Event finalization flip | <= 1% |

## 7.4 Chord Alpha kapu

| Metrika | Minimum |
|---|---:|
| Weighted accuracy | 0,80 |
| Macro-F1 | 0,70 |
| N.C./unknown F1 | 0,88 |
| Leggyengébb támogatott chord recall | 0,55 |
| Confirmed chord accepted accuracy | 0,88 |
| Chord transition p50 | <= 350 ms |
| False confident chord hard-negative audión | <= 2 / perc |

## 7.5 Chord Beta/GA cél

| Metrika | Beta cél |
|---|---:|
| Weighted accuracy | >= 0,86 |
| Macro-F1 | >= 0,78 |
| N.C./unknown F1 | >= 0,92 |
| Leggyengébb támogatott chord recall | >= 0,65 |
| Confirmed chord accepted accuracy | >= 0,92 |
| Chord transition p95 | <= 500 ms |
| False confident chord | <= 1 / perc |

## 7.6 UI kapuk

- új felhasználó legfeljebb 2 tapból gyakorlást indít;
- minden fontos állapot szín nélkül is érthető;
- 200% text scalingnél nincs overflow;
- minimum 48×48 tap target;
- Live landscape módban 1–2 méterről olvasható;
- bizonytalan felismerés nem bünteti automatikusan a tanulót;
- egy session végén mindig van legalább egy konkrét következő lépés;
- offline, account nélkül nulla hálózati kérés.

---

# 8. Kötelező fejlesztési sorrend

```text
R01–R09   Mérési és bizonyítási alap
R10–R14   Azonnali truthfulness és UX hotfix
R15–R24   Strum onset + direction recovery
R25–R33   Chord recognition recovery
R34–R39   Hasznos, adaptív termék-UI
R40–R42   Valós gitáros field validation és rollout
```

**Tilos** R17-től modellcserét productionbe vinni R08–R09 grouped evaluation nélkül.  
**Tilos** a teljes UI-redesignot úgy kiadni, hogy a bizonytalan event továbbra is biztos nyílként/akkordként jelenik meg.  
**Tilos** a Visiont az audio pontatlanság gyors elfedésére bekapcsolni; előbb önálló audio baseline szükséges.

---

# 9. Codex általános utasítás minden körhöz

```text
1. Olvasd el: AGENTS.md, HANDOFF.md, Chapter 14, az adott kör evidence fájljait.
2. Kizárólag az adott kört implementáld; a következőbe ne kezdj bele.
3. Először reprodukáld vagy teszttel rögzítsd a problémát.
4. Ne hangolj thresholdot egyetlen játékosra vagy ugyanarra a test setre.
5. Ne módosíts shipping DSP/ML konstansokat mért A/B report és ADR nélkül.
6. Ne jeleníts meg confidence-et kalibrálatlan valószínűségként.
7. Minden új modellhez model card, manifest, checksum és rollback szükséges.
8. Futtasd külön a format, analyze, unit, property, architecture és releváns evaluation kapukat.
9. A Flutter/Dart vagy corpus hiánya esetén ne állíts sikeres verifikációt.
10. Frissítsd a HANDOFF.md fájlt pontos parancsokkal, eredményekkel és nyitott kockázatokkal.
```

---

# 10. Fejlesztési körök


## Kör 01 — Recovery kickoff, scope freeze and release guard

### Cél

Állítsd le ideiglenesen az új, felhasználó előtt megjelenő feature-ök bővítését. A cél az, hogy a felismerés és a napi gyakorlási alapfolyamat mérhetően megbízható legyen, mielőtt Gamification, Community, Offline AI vagy Vision rollout történik.

### Kötelező feladatok

- Hozz létre `docs/sdd/14-recognition-ui-recovery.md` és `docs/adr/0213-recognition-recovery-program.md` fájlokat.
- Adj hozzá `recognitionRecoveryEnabled`, `recognitionShadowModeEnabled` és `newLiveStageEnabled` feature flageket, productionben alapértelmezetten kikapcsolva.
- Dokumentáld, hogy a legacy DSP továbbra is baseline, és kizárólag mért eredmény után cserélhető.
- A release workflow blokkolja az új recognition modell aktiválását hiányzó evaluation report esetén.

### Elfogadási feltételek

- Nincs felhasználói viselkedésváltozás.
- A CI ellenőrzi az evaluation report és model manifest kapcsolatát.
- A scope freeze és a feloldási feltételek ADR-ben szerepelnek.

### Javasolt branch

```text
codex/recovery-r01-kickoff
```

### Javasolt commit

```text
chore(recognition): establish recovery program and release guards
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 02 — Reprodukálható jelenlegi baseline és evidence index

### Cél

A jelenlegi mérési eredményeket egyetlen, géppel olvasható és emberileg áttekinthető baseline-csomagba kell rendezni. A 82 felvételes mérés értékes, de a korpusz nincs verziókövetve, és nem tartalmaz teljes end-to-end irány-metrikát.

### Kötelező feladatok

- Készíts `evaluation/recognition/baseline_manifest.json` fájlt a corpus hash, modellhash, app commit, konfiguráció és mérési parancs rögzítésével.
- Készíts `docs/eval/recognition-baseline-index.md` oldalt.
- Válaszd külön az onset-, direction-, chord-, no-chord-, latency- és calibration-metrikákat.
- Jelöld visszavontnak a nem validált BPM-állításokat minden összefoglalóban.

### Elfogadási feltételek

- Ugyanaz a bemenet bitre azonos reportot ad.
- A baseline report nem állít többet, mint amit a corpus bizonyít.
- Minden számhoz tartozik forrásfájl és mérési parancs.

### Javasolt branch

```text
codex/recovery-r02-baseline
```

### Javasolt commit

```text
docs(eval): create reproducible recognition baseline index
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 03 — Model activation telemetry és fail-visible működés

### Cél

A Live pipeline jelenleg csendben visszaeshet a heurisztikus irányosztályozóra, ha a CRNN súlyok nem tölthetők be. Ez diagnosztikailag veszélyes: a fejlesztő és a tesztelő nem tudja biztosan, melyik modell fut.

### Kötelező feladatok

- Vezess be `RecognitionRuntimeInfo` modellt: strum model id/version/hash, chord engine id, fallback reason, sample rate, frontend version.
- A modellbetöltési hiba legyen strukturált log és Lab állapot, ne üres `catch`.
- Productionben a felhasználó ne kapjon technikai hibaszöveget, de a runtime info kerüljön minden lokális accuracy exportba.
- Adj model activation integrációs tesztet a valós assetekkel.

### Elfogadási feltételek

- Teszt bizonyítja, hogy a 3-class CRNN valóban aktív.
- Hibás assetnél explicit `fallback` állapot és stabil hibakód jelenik meg.
- Nincs token, audio vagy személyes adat a logban.

### Javasolt branch

```text
codex/recovery-r03-runtime-info
```

### Javasolt commit

```text
fix(ml): make recognition model activation observable
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 04 — RecognitionFrame V2 domain contract

### Cél

A jelenlegi `LiveFrame` csak egy akkordot, egy sticky strumot és egyetlen – valójában strum – confidence értéket visz a UI-ba. A UI ezért nem tud különbséget tenni biztos, bizonytalan, ideiglenes vagy elutasított felismerés között.

### Kötelező feladatok

- Hozz létre Flutter-független modelleket: `RecognitionDecision`, `RecognitionRejectReason`, `SignalQualitySnapshot`, `ChordPrediction`, `StrumPrediction`, `RecognitionRuntimeInfo`.
- A döntési állapotok: `candidate`, `provisional`, `confirmed`, `uncertain`, `rejected`, `expired`.
- A strum modell tartalmazza: onset time, verdict time, pDown, pUp, pNoStrum, calibrated confidence, direction margin, model id.
- A chord modell tartalmazza: label, root, quality, noChord/unknown probability, calibrated confidence, stability frames, source engine.
- Készíts kompatibilitási adaptert a régi `LiveFrame` hívókhoz.

### Elfogadási feltételek

- A domain contract nem importál Fluttert vagy Riverpodot.
- JSON round-trip és backward compatibility tesztek zöldek.
- A UI külön látja a chord- és direction-confidence értéket.

### Javasolt branch

```text
codex/recovery-r04-contract
```

### Javasolt commit

```text
refactor(recognition): introduce versioned recognition frame contracts
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 05 — Signal quality analyzer

### Cél

A felismerés pontosságát erősen befolyásolja a telefon elhelyezése, clipping, túl halk jel, zaj és beszéd. A jelenlegi UI csak egy input levelt mutat, de nem mondja meg, miért nem megbízható a mérés.

### Kötelező feladatok

- Implementálj streaming quality feature-öket: RMS, peak, clipping ratio, estimated noise floor, crest factor, tonalness, SNR proxy, silence ratio.
- Állapotok: `good`, `tooQuiet`, `tooLoud`, `clipping`, `tooNoisy`, `speechLike`, `unstable`, `unknown`.
- A quality analyzer ne osztályozzon betegséget vagy személyt; kizárólag audióminőséget.
- Adj szintetikus és valós fixture teszteket.

### Elfogadási feltételek

- A quality állapot stabil, hiszterézises, nem villog frame-enként.
- Clipping és silence fixture 100%-ban megfelelő állapotot ad.
- A feature nem növeli 5%-nál jobban a mért DSP CPU-időt.

### Javasolt branch

```text
codex/recovery-r05-signal-quality
```

### Javasolt commit

```text
feat(audio): add actionable live signal quality analysis
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 06 — Lokális Accuracy Lab és engedélyezett adatgyűjtés

### Cél

A modelljavításhoz saját, a tényleges céltelefonokat és felhasználói környezetet reprezentáló adatok szükségesek. A felvétel alapértelmezetten maradjon helyi, export csak kifejezett beleegyezéssel történjen.

### Kötelező feladatok

- Készíts Accuracy Lab flow-t 15–20 rövid feladattal: csend, zaj, egyes akkordok, lassú down/up, váltott pengetés, gyors pattern.
- Ments lokálisan WAV + esemény + device metadata + consent schema version csomagot.
- Ne ments e-mailt, account tokent vagy pontos helyet.
- Export előtt mutasd a csomag tartalmát és kérj megerősítést.
- Készíts corpus manifest sémát és checksumot.

### Elfogadási feltételek

- Internet nélkül teljesen végigfut.
- Consent nélkül nincs export.
- Törlés után a lokális audio és annotáció nem marad vissza.
- Export determinisztikus és ellenőrizhető hash-sel rendelkezik.

### Javasolt branch

```text
codex/recovery-r06-accuracy-lab
```

### Javasolt commit

```text
feat(diagnostics): add privacy-first recognition accuracy lab
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 07 — Annotációs eszköz onset, irány és akkord címkézéshez

### Cél

A jelenlegi corpus bővítéséhez gyors, ember által ellenőrzött annotáció szükséges. A kutatásban is manuálisan validálták a fél-automatikus onset- és direction-címkéket; puszta automatikus címke nem lehet ground truth.

### Kötelező feladatok

- Készíts lokális web/desktop annotátort waveformmal és spectrogrammal.
- Támogasd az onset húzását, down/up/unknown címkét, chord labelt, no-chordot és annotátori megjegyzést.
- Legyen keyboard shortcut, undo/redo, autosave és inter-annotator export.
- Tárolj annotation schema versiont és provenance-t.

### Elfogadási feltételek

- 5 perces felvétel annotálható adatvesztés nélkül.
- Két annotátor eltérése reportolható.
- Invalid vagy átfedő eseményekre validator jelez.
- A tool nem módosítja a nyers WAV-ot.

### Javasolt branch

```text
codex/recovery-r07-annotation-tool
```

### Javasolt commit

```text
feat(evaluation): add human-validated guitar annotation tool
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 08 — Csoportosított evaluation harness és leakage-védelem

### Cél

Random clip split túl optimista lehet, ha ugyanaz a játékos, telefon vagy gitár több splitben szerepel. A termék számára a nem látott játékosra és eszközre való általánosítás a fontos.

### Kötelező feladatok

- Implementálj split-stratégiákat: leave-one-player-out, leave-one-device-out, leave-one-guitar-out, room holdout.
- Metrikák: onset P/R/F1 25/50/100 ms, down/up class F1, any-strum F1, accepted accuracy, coverage, false visible event/min, latency p50/p95, ECE, Brier.
- Chord: weighted accuracy, macro-F1, per-label precision/recall, no-chord F1, unknown false-accept, transition latency.
- A report tartalmazzon confidence–risk–coverage görbét.

### Elfogadási feltételek

- Split leakage detector hibázik, ha ugyanaz a group több splitben van.
- A metrikák fixture-ön kézzel ellenőrzött értéket adnak.
- A CI kis fixture corpuson fut; a teljes corpus manuális workflow.

### Javasolt branch

```text
codex/recovery-r08-eval-harness
```

### Javasolt commit

```text
feat(evaluation): add grouped recognition metrics and leakage guards
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 09 — Baseline dashboard és döntési kapu

### Cél

Az eredményeket ne egyetlen accuracy százalék fedje el. A release-döntésnek külön kell látnia a gyenge akkordokat, up/down eltérést, zajos helyzetet és az abstention árát.

### Kötelező feladatok

- Generálj HTML/Markdown/JSON reportot ugyanabból a mérésből.
- Mutasd a per-player, per-device, per-guitar, per-room és per-technique bontást.
- Külön jelenjen meg: confident wrong, uncertain correct, rejected event.
- Hozz létre `recognition_release_gate.json` fájlt verziózott küszöbökkel.

### Elfogadási feltételek

- A gate fail-closed: hiányzó metrika = FAIL.
- A reportból visszakövethető minden mérés modellre és corpusra.
- A teljes baseline felülírásához review és indoklás szükséges.

### Javasolt branch

```text
codex/recovery-r09-dashboard
```

### Javasolt commit

```text
feat(evaluation): add recognition quality dashboard and gates
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 10 — Azonnali direction abstention hotfix

### Cél

A 3-class modell eval foldján a true-strum direction accuracy csak körülbelül 80,7%. A jelenlegi döntés a no-strum gate után mindig down vagy up irányt választ, még akkor is, ha a két irány valószínűsége közel van. A felhasználó számára a „nem biztos” jobb, mint egy magabiztosan rossz nyíl.

### Kötelező feladatok

- Adj minimum direction margin és minimum calibrated confidence kaput.
- A küszöböt ne kézzel találd ki: held-out calibration seten optimalizáld a kívánt conditional accuracy/coverage célra.
- `uncertain` esetén ne jelenjen meg down/up nyíl; jelenjen meg semleges strum pulse vagy `?` állapot.
- A régi user confidence setting ne írja felül a safety minimumot.

### Elfogadási feltételek

- Accepted direction accuracy eléri az Alpha kaput a calibration seten.
- A report közli a coverage csökkenést.
- Ugyanarra az eventre a UI legfeljebb egyszer ad végleges irányt.
- Bizonytalan event nem számít hibás down/up találatnak a gyakorlási score-ban.

### Javasolt branch

```text
codex/recovery-r10-direction-abstain
```

### Javasolt commit

```text
fix(strum): abstain on ambiguous direction predictions
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 11 — Chord uncertainty, no-chord és külön confidence a UI-ban

### Cél

A pipeline rendelkezik chord confidence getterrel, de a `LiveFrame` nem továbbítja. A UI ezért csak a strum confidence-et mutatja, ami könnyen chord confidence-nek tűnhet.

### Kötelező feladatok

- Továbbítsd a raw, EMA és calibrated chord confidence értékeket a RecognitionFrame-ben.
- Válaszd külön a `noChord`, `unknownChord` és `lowSignal` állapotot.
- A UI ne mutasson chord labelt, ha a döntés `uncertain` vagy `rejected`.
- A confidence százalék alapértelmezetten ne legyen látható; inkább „Biztos / Ellenőrzés / Nem biztos” szöveg + ikon.

### Elfogadási feltételek

- Chord és strum confidence soha nem keveredik.
- Beszéd/noise fixture nem mutat biztos akkordot.
- A semantics label tartalmazza az uncertainty állapotot.
- A régi Live hívók kompatibilitási adapteren működnek.

### Javasolt branch

```text
codex/recovery-r11-chord-uncertainty
```

### Javasolt commit

```text
fix(live): expose chord uncertainty without false precision
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 12 — Provisional → confirmed temporal state machine

### Cél

A chord history minden labelváltást vizuális kártyává emel. Zajos felismerésnél ez a hibát látványos „timeline churnné” alakítja. A felhasználói felületen csak stabil, megerősített változás jelenjen meg.

### Kötelező feladatok

- Implementálj `RecognitionStabilizer` állapotgépet külön Free és Guided profilokkal.
- Chord: provisional jelölt, megerősítés minimum N frame vagy onset-aligned evidence után; confirmed állapotból csak erős transition evidence váltson.
- Strum: candidate onset → accepted/rejected/uncertain; event immutábilis legyen.
- Mérd a confirmation latency és flip rate értékeket.

### Elfogadási feltételek

- Ugyanaz az event nem változik downról upra véglegesítés után.
- Stable held chord nem generál új timeline cardot.
- Chord flip rate a baseline corpuson mérhetően csökken.
- A latency nem lépi túl az adott release gate-et.

### Javasolt branch

```text
codex/recovery-r12-stabilizer
```

### Javasolt commit

```text
feat(recognition): add provisional and confirmed event stabilizer
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 13 — Live UI truthfulness hotfix

### Cél

A teljes redesign előtt is szükséges egy használhatóbb Live felület: a history filmstrip ne legyen fő tartalom, az állapot legyen nyugodt, és az app mondja meg, mit tegyen a felhasználó.

### Kötelező feladatok

- A fő nézetben egyetlen stabil chord card és egyetlen legutóbbi strum event legyen.
- A history kerüljön lenyitható panelbe; shimmer és folyamatos hero animáció alapértelmezetten ki.
- Felül jelenjen meg a signal quality és mic/model állapot.
- Alsó CTA: `Indítás/Szünet/Befejezés`; Tuner és Metronome másodlagos.
- `uncertain` esetén szöveges ok: túl halk, zajos, bizonytalan irány, ismeretlen akkord.

### Elfogadási feltételek

- A képernyő 2 méterről olvasható compact landscape módban.
- 200% text scale mellett nincs overflow.
- A Live screen nem mutat egyszerre több egymással versengő fő üzenetet.
- Golden, semantics és widget tesztek készülnek.

### Javasolt branch

```text
codex/recovery-r13-live-hotfix
```

### Javasolt commit

```text
refactor(ui): make Live feedback stable and truthful
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 14 — Automatikus Audio Setup és Accuracy Check wizard

### Cél

A felhasználó ne kezdjen vakon egy rossz telefonpozícióval. Egy rövid setup felméri a zajt, hangerőt, latencyt és az első néhány ismert akkordot/pengetést.

### Kötelező feladatok

- 30–60 másodperces flow: csendmérés, egy erős down, egy up, E/Am/G/C ellenőrzés, telefonpozíció javaslat.
- Ne „kalibráld rá” a modellt a rossz címkékre; csak input gain/latency/quality beállítást és személyes confidence profilt adj.
- Ments device+audio-route specifikus profilt.
- Profil elavul, ha mic route/sample rate érdemben változik.

### Elfogadási feltételek

- A wizard megszakítható és újraindítható.
- Rossz jelminőségnél nem enged hamis sikerállapotot.
- A profile migráció és törlés tesztelt.
- A user kap konkrét, egyértelmű telefonelhelyezési tanácsot.

### Javasolt branch

```text
codex/recovery-r14-calibration-wizard
```

### Javasolt commit

```text
feat(onboarding): add guitar audio setup and accuracy check
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 15 — Hard-negative corpus

### Cél

A false onsetek és phantom chordok jelentős része nem valódi pengetés: beszéd, taps, asztalkoppanás, pengető-kattintás, húrzaj, fret squeak, metronóm, háttérzene, tévé, ventilátor és telefonmozgatás.

### Kötelező feladatok

- Készíts taxonómiát és célzott capture listát.
- Legalább 60 perc negatív anyag több telefonról és szobából.
- Annotáld, hogy az esemény `no-strum`, `no-chord` vagy mindkettő.
- A release report tartalmazzon false visible arrow/chord per minute metrikát.

### Elfogadási feltételek

- Nincs random clip leakage a train/eval között.
- A negatív corpusban legalább 10 fő kategória szerepel.
- A UI false-visible-event metrika reprodukálható.
- A data licence/consent manifest teljes.

### Javasolt branch

```text
codex/recovery-r15-hard-negatives
```

### Javasolt commit

```text
test(data): build hard-negative recognition corpus
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 16 — Canonical SuperFlux A/B benchmark

### Cél

A SuperFlux jó valós idejű baseline és vibrato ellen hasznos, de általános onset detector; nem gitárirány-modell. A jelenlegi 64 mel-band és egyedi threshold konfigurációt össze kell vetni a publikált/canonical változatokkal, nem pusztán tovább hangolni egy korpuszon.

### Kötelező feladatok

- Implementálj konfigurálható benchmark adaptert: current, canonical 24 bands/octave, complex-domain és egyszerű spectral flux baseline.
- Minden változat ugyanazon grouped corpuson fusson.
- Ne változtasd production konstansokat addig, amíg nincs report.
- Mérd CPU-t és latencyt is.

### Elfogadási feltételek

- A/B report per subgroup elkészül.
- A kiválasztott baseline Pareto-optimális accuracy/latency szempontból.
- Synthetic regresszió és hard-negative teszt egyaránt zöld.
- Az eredmény ADR-ben rögzített.

### Javasolt branch

```text
codex/recovery-r16-onset-ab
```

### Javasolt commit

```text
experiment(dsp): benchmark onset detectors on real guitar audio
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 17 — Klangio ISMIR 2025 referencia reprodukció és licence audit

### Cél

A publikált joint modell közvetlenül onsetet, down/up irányt és akkordot tanul, valós telefonos és szintetikus adatokkal. Először reprodukálni kell a hivatalos checkpoint eredményét, majd mérni a StrumSight corpuson.

### Kötelező feladatok

- Pineld külön research környezetben a hivatalos repository commitját.
- Ellenőrizd külön a kód, checkpoint és dataset licencét; csak audit után kerüljön artifact a termékbe.
- Futtasd a checkpointot a publikált fixture-ön és a StrumSight held-out corpuson.
- Dokumentáld input, output, latency, memory és licence eredményt.

### Elfogadási feltételek

- Reprodukciós notebook/script egyetlen paranccsal fut.
- A hivatalos eredményt nem keverjük a StrumSight saját mérésével.
- Licence blocker esetén nincs termékbe másolás.
- Készül go/no-go ADR.

### Javasolt branch

```text
codex/recovery-r17-reference-model
```

### Javasolt commit

```text
research(ml): evaluate joint guitar strumming reference model
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 18 — Streaming joint onset + direction prototype

### Cél

A jelenlegi kétlépcsős rendszerben az onset detector hibája továbbterjed a direction classifierre. A joint regression head közvetlenül külön down és up onset görbét adhat, és természetesen támogatja az abstentiont.

### Kötelező feladatok

- Készíts offline Python prototípust 16 kHz log-mel frontenden.
- Output: down onset regression, up onset regression, no-event confidence; opcionális chord head.
- Csak causal vagy kontrollált lookahead architektúra kerüljön mobil jelöltként értékelésre.
- Hasonlítsd össze a legacy two-stage pipeline-nal.

### Elfogadási feltételek

- End-to-end down/up F1 és latency report elkészül.
- A model input/output sémája verziózott.
- Nincs training/eval player leakage.
- Go/no-go minimum Alpha kapuhoz kötött.

### Javasolt branch

```text
codex/recovery-r18-joint-prototype
```

### Javasolt commit

```text
experiment(ml): prototype joint streaming strum transcription
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 19 — Adataugmentáció és kiegyensúlyozott training recipe

### Cél

A publikált eredmények alapján a szintetikus+valós kombináció, a ±6 félhang pitch shift és a valós zaj/reverb/handling augmentáció javíthatja az általánosítást. Az augmentációt azonban ablationnel kell bizonyítani.

### Kötelező feladatok

- Augmentációk: pitch shift címketranszponálással, room IR, gain, EQ, compression, device response, SNR, traffic/living-room noise, fret/pick/tap burst.
- Kiegyensúlyozd down/up/no-strum és chord label mintákat.
- Minden augmentáció legyen seedelt, manifestelt és kikapcsolható.
- Készíts ablation reportot.

### Elfogadási feltételek

- Nincs címke-eltolódás pitch shift vagy latency augmentáció során.
- A minor és ritka chord osztályok támogatása dokumentált.
- Legalább egy unseen-player és unseen-device split javul.
- Rosszabbodó subgroup esetén nincs automatikus elfogadás.

### Javasolt branch

```text
codex/recovery-r19-augmentation
```

### Javasolt commit

```text
feat(ml): add reproducible guitar-specific augmentation pipeline
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 20 — Strum modell tanítás grouped holdouttal

### Cél

A kiválasztott joint vagy továbbfejlesztett modell tényleges train runja csak lezárt adat- és split-sémával indulhat.

### Kötelező feladatok

- Train/validation/test groupok külön játékos/eszköz/gitár szerint.
- Mentett checkpoint mellett: config, seed, dependency lock, git SHA, dataset hash, metrics.
- Early stopping fő metrika: end-to-end macro F1; secondary: conditional accuracy/coverage.
- Készíts model cardot ismert gyengeségekkel.

### Elfogadási feltételek

- A train run teljesen reprodukálható.
- Nincs test-set threshold tuning.
- Per-group metrikák és confidence diagramok elérhetők.
- A modell nem kerül app assetbe gate nélkül.

### Javasolt branch

```text
codex/recovery-r20-strum-train
```

### Javasolt commit

```text
train(ml): produce grouped-holdout strum model candidate
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 21 — Strum confidence calibration és selective prediction

### Cél

A softmax confidence önmagában nem megbízható. A cél nem a lehető legtöbb nyíl, hanem a kontrollált hibaarány egy elfogadható coverage mellett.

### Kötelező feladatok

- Hasonlítsd össze temperature scaling, isotonic/Platt és logit-margin confidence estimatorokat.
- Optimalizálj risk–coverage görbén: legalább 92% accepted accuracy cél, majd coverage maximalizálás.
- Kalibráció külön validation seten; test csak egyszer.
- A threshold profile modellverzióhoz kötött.

### Elfogadási feltételek

- ECE és Brier javul vagy dokumentáltan nem romlik.
- Accepted accuracy/coverage gate teljesül minden kötelező subgroupban.
- OOD/hard-negative adaton az abstention nő.
- A UI-nak továbbított confidence valóban kalibrált.

### Javasolt branch

```text
codex/recovery-r21-strum-calibration
```

### Javasolt commit

```text
feat(ml): calibrate strum confidence and risk coverage
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 22 — Mobil distillation, quantization és performance gate

### Cél

A kutatási modell akkor használható, ha ARM telefonon valós időben, stabil memóriával és elfogadható akkumulátor-terheléssel fut.

### Kötelező feladatok

- Készíts student jelölteket és quantization A/B-t.
- Mérj legalább low/mid/high tier Android készüléken: p50/p95 inference, memory peak, CPU, thermal throttling.
- Ellenőrizd a float referencia és mobil inference parityt.
- A modell load/unload lifecycle legyen biztonságos.

### Elfogadási feltételek

- p95 verdict latency megfelel a release gate-nek.
- 10 perces session alatt nincs növekvő memória.
- Quantization accuracy regresszió a megengedett határon belül.
- Low tieren szükség esetén legacy fallback, explicit runtime info mellett.

### Javasolt branch

```text
codex/recovery-r22-mobile-model
```

### Javasolt commit

```text
perf(ml): distill and benchmark mobile strum model
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 23 — Strum shadow mode az alkalmazásban

### Cél

Az új modell először ne vezérelje a felhasználói UI-t. Fusson shadow módban, és lokálisan hasonlítsa össze a legacy és candidate predikciókat.

### Kötelező feladatok

- Egyetlen shared frontend, amennyiben lehetséges; ne duplázd indokolatlanul az FFT/mel költséget.
- Shadow output csak lokális metrics bufferbe kerül.
- Exportban szerepel latency, disagreement, accepted/rejected és quality state.
- Nem változik a user score vagy UI.

### Elfogadási feltételek

- Shadow mode feature flag mögött van.
- Off állapotban nulla extra inference.
- 10 perces A/B session nem szivárog memóriát.
- Disagreement report reprodukálható.

### Javasolt branch

```text
codex/recovery-r23-strum-shadow
```

### Javasolt commit

```text
feat(recognition): deploy candidate strum model in shadow mode
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 24 — Strum release gate és kontrollált rollout

### Cél

A candidate csak akkor válhat elsődlegessé, ha valós eszközös és grouped corpus kapukat teljesít, nem pusztán egy átlagos accuracy számot.

### Kötelező feladatok

- Alpha: belső tesztelők; Beta: opt-in; Production: fokozatos százalék.
- Rollback kapcsoló modellasset új app release nélkül, amennyiben a platformmodell ezt biztonságosan támogatja; különben gyors app rollback terv.
- Monitorozható kizárólag aggregált, consentelt quality metric.
- Záró model card és known limitations.

### Elfogadási feltételek

- Minden kötelező release gate PASS.
- Nincs kritikus subgroup regresszió.
- Rollback gyakorlat sikeres.
- A legacy modell legalább egy release-ig elérhető fallback.

### Javasolt branch

```text
codex/recovery-r24-strum-release
```

### Javasolt commit

```text
release(recognition): gate and roll out validated strum model
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 25 — Kiegyensúlyozott chord corpus

### Cél

A jelenlegi 82 felvételes corpus 98%-ban dúr, és a C# major recall 0%, D major 41,7%. A chord fejlesztéshez balanced, több voicingot és no-chord/unknown példát tartalmazó corpus szükséges.

### Kötelező feladatok

- Minimum 24 maj/min osztály + N.C. + unknown/open-set.
- Chordonként több nyitott/barre/alternatív voicing, capo és több gitár.
- Pick/finger, halk/erős, különböző távolság és szoba.
- Ne használj automatikus chord címkét emberi ellenőrzés nélkül ground truthként.

### Elfogadási feltételek

- Minden támogatott chord eléri a minimum supportot.
- A split groupolt játékos/eszköz/gitár szerint.
- A corpus manifest tartalmazza a voicingot és capo-t.
- No-chord és hard-negative arány dokumentált.

### Javasolt branch

```text
codex/recovery-r25-chord-corpus
```

### Javasolt commit

```text
test(data): build balanced mobile chord recognition corpus
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 26 — A meglévő Chord CRNN élő shadow bekötése

### Cél

A repository már szállít `chord_crnn.bin` modellt, de ez csak Analyze/Lab úton fut; a Live pipeline továbbra is NNLS + dictionary + Viterbi. Először mérni kell a meglévő CRNN-t ugyanazon élő inputon.

### Kötelező feladatok

- Töltsd be a chord assetet az audio isolate-ba ugyanazzal a manifest-integritással.
- Implementálj streaming window adaptert és shadow outputot.
- Mérd a live NNLS, CRNN és ground truth egyezést időben illesztve.
- Ne jelenítsd meg a CRNN outputot a felhasználónak ebben a körben.

### Elfogadási feltételek

- Asset parity teszt mellett élő wiring teszt is van.
- Shadow mode off esetén nincs extra költség.
- A chord CRNN latency/memory report elkészül.
- Hibás asset fail-visible runtime info-t ad.

### Javasolt branch

```text
codex/recovery-r26-chord-shadow
```

### Javasolt commit

```text
feat(chord): wire shipped chord CRNN into live shadow evaluation
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 27 — NNLS vs CRNN vs hybrid összehasonlítás

### Cél

Nem feltételezzük, hogy a neurális modell minden környezetben jobb. A legacy path magyarázható és olcsó; a CRNN több kontextust használhat. A döntést per-label és per-condition mérés alapján kell meghozni.

### Kötelező feladatok

- Három rendszer ugyanazon corpuson: legacy, CRNN, hybrid.
- Hybrid jelöltek: consensus, confidence-weighted, onset-aligned switch, quality-aware fallback.
- Mérd chord accuracy, macro-F1, N.C. F1, transition latency, flip rate, CPU/memory.
- Készíts failure cluster elemzést.

### Elfogadási feltételek

- A választott rendszer nem csak weighted accuracyban, hanem macro-F1-ben is javul.
- C# / D / F / Bb gyenge osztályok külön reportban.
- A hybrid logika determinisztikus és unit tesztelt.
- Döntés ADR-ben.

### Javasolt branch

```text
codex/recovery-r27-chord-ab
```

### Javasolt commit

```text
experiment(chord): compare legacy neural and hybrid recognition
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 28 — Hybrid chord stabilizer és onset-aligned transition

### Cél

A felhasználónak gyors, de nem ugráló chord kijelzés kell. A stabilizer használhat onsetet a váltási pillanat jelzésére, de a chord label megerősítéséhez több evidence szükséges.

### Kötelező feladatok

- Külön `FreeChordProfile` és `GuidedChordProfile`.
- Provisional chord gyorsan megjelenhet halvány/semleges állapotban; confirmed csak threshold után.
- Ring-out hold és release quality-aware legyen.
- Ne tartson végtelenül régi chordot valódi csendben.

### Elfogadási feltételek

- Transition latency és false flip egyszerre szerepel a gate-ben.
- Silence esetén a chord a megadott határon belül törlődik.
- Sustained chord nem villog.
- State machine property tesztek készülnek.

### Javasolt branch

```text
codex/recovery-r28-chord-stabilizer
```

### Javasolt commit

```text
feat(chord): add quality-aware hybrid temporal stabilizer
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 29 — Strukturált root + quality chord modell és class balancing spike

### Cél

A merev 24-class softmax ritka osztályoknál gyenge lehet, és később nehezen bővíthető. Kutatási spike-ként vizsgáld a root, quality és no-chord külön fejeket, reweighted/focal loss-szal.

### Kötelező feladatok

- Baseline: 25-class model; candidate: 12 root + quality + N.C./unknown.
- Reweighted loss, balanced sampling és confusion-aware augmentation.
- Kontextusmodell csak akkor, ha mobil latency és causal működés elfogadható.
- A nagyobb chord vocabulary ebben a körben nem kötelező production feature.

### Elfogadási feltételek

- Per-class recall javul, különösen a gyenge osztályokon.
- Nincs súlyos weighted accuracy regresszió.
- Mobile feasibility report elkészül.
- Go/no-go döntés, nem automatikus rewrite.

### Javasolt branch

```text
codex/recovery-r29-structured-chord
```

### Javasolt commit

```text
research(chord): evaluate structured and class-balanced chord model
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 30 — Expected chord prior szigorú izolációja

### Cél

Guided gyakorlatban hasznos az elvárt chord ismerete, de Free Play módban ez hamis „találatot” okozhat. A mérésnek és a UI-nak egyértelműen jelölnie kell, mikor használt priort.

### Kötelező feladatok

- `RecognitionMode.free` alatt expected chord API legyen hatástalan és tesztben őrzött.
- Guided módban a prior csak transition tie-breaker vagy explicit scorer input; ne írja felül az audio evidence-t.
- Report külön `audioOnly` és `guidedPrior` metrikával.
- UI jelezze: „gyakorlási célhoz viszonyítva”, ne állítsa független felismerésnek.

### Elfogadási feltételek

- Free mode parity teszt bitre azonos prior nélkül/rossz priorral.
- Guided wrong-chord esetet nem javítja automatikusan helyesre.
- Minden export rögzíti a mode-ot.
- Nincs evaluation leakage.

### Javasolt branch

```text
codex/recovery-r30-guided-prior
```

### Javasolt commit

```text
fix(chord): isolate guided priors from free recognition
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 31 — Quality-aware preprocessing és device adaptation

### Cél

A telefonmikrofonok frekvenciamenete, AGC-je és zajszintje eltér. A cél nem egyedi modell minden telefonra, hanem robusztus normalizálás és explicit degradált állapot.

### Kötelező feladatok

- Vizsgáld: loudness normalization, DC removal, high-pass, device response augmentation, AGC detection, optional noise suppression.
- Minden preprocessing A/B mérve; ne tegyen tönkre attack információt.
- Device profile csak technikai audio route adatot tároljon.
- Degraded quality esetén növeld az abstentiont, ne a confidence-et.

### Elfogadási feltételek

- Legalább 5 telefonon mért report.
- Nincs onset latency regresszió a gate felett.
- Clipping/noise esetén a UI megfelelő állapotot mutat.
- A preprocessing teljesen kikapcsolható rollbackhez.

### Javasolt branch

```text
codex/recovery-r31-device-adaptation
```

### Javasolt commit

```text
experiment(audio): add measured device-robust preprocessing
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 32 — Chord calibration, unknown/open-set és selective prediction

### Cél

A chord modellnek képesnek kell lennie arra, hogy ne kényszerítsen egy sus7/add9/rosszul lefogott vagy idegen hangot a legközelebbi maj/min osztályba.

### Kötelező feladatok

- Kalibráld chord confidence-et validation seten.
- Vezess be unknown/open-set döntést energy, entropy, margin vagy külön head alapján; A/B mérés kötelező.
- Optimalizálj per-class minimum recall és accepted accuracy mellett.
- A UI különböztesse meg `N.C.` és `Ismeretlen akkord` állapotot.

### Elfogadási feltételek

- Hard-negative és unsupported chord false accept a gate alatt.
- Accepted chord accuracy és coverage reportolt.
- A weakest supported chord recall eléri a minimumot.
- Confidence reliability diagram elkészül.

### Javasolt branch

```text
codex/recovery-r32-chord-calibration
```

### Javasolt commit

```text
feat(chord): calibrate confidence and reject unsupported chords
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 33 — Chord release gate és rollout

### Cél

Az új chord path csak valós telefonos corpuson, per-label kapukkal és rollback tervvel aktiválható.

### Kötelező feladatok

- Shadow → internal alpha → opt-in beta → gradual production.
- Külön threshold profile free/guided mode-ra.
- Legacy path legalább egy release-ig megmarad.
- Model card tartalmazza a támogatott chord vocabularyt és korlátokat.

### Elfogadási feltételek

- Weighted és macro gate PASS.
- N.C./unknown gate PASS.
- A gyenge osztályok minimum recall kapuja PASS.
- Rollback gyakorlat és device matrix kész.

### Javasolt branch

```text
codex/recovery-r33-chord-release
```

### Javasolt commit

```text
release(chord): gate and roll out validated chord recognition
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 34 — Chapter 13 design system repositoryba emelése

### Cél

A részletes UI/UX Chapter 13 nincs benne a feltöltött repositoryban, ezért a Codex nem tudja következetesen végrehajtani. Először a dokumentumot és a tokenalapot kell commitolni.

### Kötelező feladatok

- Add hozzá `docs/sdd/13-ui-ux-design-system-screen-specification.md` fájlt.
- Hozd létre a design tokeneket: color, typography, spacing, radius, motion, breakpoints.
- Készíts accessibility token auditot és theme goldeneket.
- Ne migráld egyszerre az összes képernyőt.

### Elfogadási feltételek

- Chapter 13 szerepel az SDD indexben és traceability matrixban.
- Dark, light, high-contrast theme smoke/golden zöld.
- Nincs feature viselkedésváltozás.
- Tokenek hardcoded UI értékei új kódban tiltottak.

### Javasolt branch

```text
codex/recovery-r34-ui-foundation
```

### Javasolt commit

```text
docs(ui): add Chapter 13 and design-system foundations
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 35 — Új adaptív app shell

### Cél

A jelenlegi top-level nav `Live / Analyze / Learn / Library / Settings`; ez a technikai feature-listát tükrözi, nem a gitáros napi célját. Az új shell: `Today / Practice / Songs / Coach / Profile`.

### Kötelező feladatok

- Közös destination model NavigationBar/NavigationRail számára.
- <600 logical px: NavigationBar; >=600: NavigationRail vagy supporting pane.
- A régi route-ok deep linkként továbbra is működjenek.
- Coach csak akkor jelenjen meg aktívan, ha elérhető; ne legyen no-op gomb.

### Elfogadási feltételek

- Compact, landscape, tablet és foldable widget tesztek.
- Route redirect loop nincs.
- 200% text scale és TalkBack semantics tesztelt.
- Live mic lifecycle shellváltáskor változatlanul biztonságos.

### Javasolt branch

```text
codex/recovery-r35-app-shell
```

### Javasolt commit

```text
refactor(navigation): introduce task-oriented adaptive app shell
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 36 — Today és „10 perces hasznos gyakorlás” flow

### Cél

Az app nyitóképernyője ne egy detektor legyen, hanem mondja meg, mit érdemes ma csinálni. A már meglévő Practice Engine legyen látható és elérhető.

### Kötelező feladatok

- Today: egy fő CTA, napi terv, folytatás, setup warning, legutóbbi actionable insight.
- Default 10 perces flow: hangolás → ritmus/akkord gyakorlat → rövid eredmény.
- Offline működés; AI hiányában determinisztikus ajánlás.
- Ne mutass üres Community/Gamification kártyákat.

### Elfogadási feltételek

- Új user 2 tapon belül gyakorlást indít.
- Minden CTA működik; no-op tiltott.
- Offline network guard zöld.
- Empty/loading/error/degraded state minden kártyához definiált.

### Javasolt branch

```text
codex/recovery-r36-today-flow
```

### Javasolt commit

```text
feat(today): expose a useful ten-minute guitar practice flow
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 37 — Live Stage V2 teljes képernyő

### Cél

A végleges Live képernyőnek egy gitáros számára azonnal használhatónak kell lennie, nem látványos diagnosztikai filmstripnek.

### Kötelező feladatok

- Módok: Free Play, Guided Pattern, Accuracy Check.
- Központ: confirmed chord; mellette expected target csak Guided módban.
- Strum event: down/up/uncertain + timing; 1–1 rövid feedback.
- Signal quality card, mic status, explicit model/fallback csak Labban.
- History opcionális bottom sheet; nincs alapértelmezett shimmer/glow halmozás.
- Landscape stage layout 2 méteres olvashatósággal.

### Elfogadási feltételek

- False confident state UI teszttel tiltott.
- Direction és chord uncertainty külön szemantikával.
- Tap target >=48x48, kontraszt és color-not-only teszt zöld.
- 10 perces real-device sessionben nincs overflow, jank vagy mic leak.

### Javasolt branch

```text
codex/recovery-r37-live-stage-v2
```

### Javasolt commit

```text
feat(live): build task-focused Live Stage V2
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 38 — Guided practice target + correction loop

### Cél

A felismerés önmagában kevés; a felhasználónak tudnia kell, mit játsszon, mi sikerült, és mit ismételjen. A meglévő Practice Engine és Song Trainer a hasznos termék alapja.

### Kötelező feladatok

- Guided sessionben mutasd a következő chord/pattern célt és a beat gridet.
- Eredmény: egy fő probléma, egy konkrét javító gyakorlat, „Ismételd a gyenge részt”.
- Uncertain recognition ne büntesse a tanulót automatikusan.
- Session result rögzítse a recognition coverage-et és quality-t a score mellett.

### Elfogadási feltételek

- A user egy tapból újrapróbálhatja a hibás szakaszt.
- A score nem nő/csökken pusztán a modell bizonytalansága miatt.
- Result action minden esetben működő route-ra mutat.
- Practice/Song/Live integrációs teszt zöld.

### Javasolt branch

```text
codex/recovery-r38-correction-loop
```

### Javasolt commit

```text
feat(practice): connect recognition to an actionable correction loop
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 39 — Adaptive, accessibility és outdoor usability audit

### Cél

A gitáros gyakran állványon, távolabbról, napsütésben vagy landscape módban használja a telefont. A UI-t valós használati helyzetekre kell tesztelni.

### Kötelező feladatok

- Compact 360 px, 412 px, landscape, tablet, foldable, 200% text scale.
- TalkBack, high contrast, grayscale/color-vision test.
- Minimum 48x48 touch target és 4.5:1 normál szövegkontraszt.
- Reduced motion: beat pulse és feedback animation csökkentése.
- Valódi kinti fény és 1–2 méteres olvasási checklist.

### Elfogadási feltételek

- Flutter accessibility guideline tesztek zöldek.
- Minden kritikus állapot szín nélkül is érthető.
- Nincs orientation lock.
- Field checklist legalább 3 telefonon teljesítve.

### Javasolt branch

```text
codex/recovery-r39-accessibility
```

### Javasolt commit

```text
test(ui): validate adaptive accessible stage usability
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 40 — Belső Alpha field study

### Cél

A laboreredmény nem elég. Különböző tudásszintű gitárosokkal kell mérni, hogy a felismerés és a UI valóban segít-e.

### Kötelező feladatok

- Legalább 8 tesztelő: kezdő, középhaladó, haladó; több telefon és gitár.
- Feladatok: setup, free play, guided pattern, chord changes, noisy room.
- Gyűjts: task completion, correction usefulness, false confident event, perceived trust, crash/jank.
- Audio export csak külön consenttel; egyébként csak helyi aggregált report.

### Elfogadási feltételek

- Minden blocker kategorizált és issue-ra bontott.
- False-confident hiba P0/P1.
- A user megérti az `uncertain` állapotot.
- Go/no-go review dokumentált.

### Javasolt branch

```text
codex/recovery-r40-alpha-study
```

### Javasolt commit

```text
test(product): run real-guitar internal alpha study
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 41 — Opt-in Beta, telemetry és privacy gate

### Cél

A Beta csak kifejezett opt-in legyen, világos privacy leírással. A terméknek offline-firstnek kell maradnia.

### Kötelező feladatok

- Feature flag és local opt-in.
- Alapértelmezetten nincs nyers audio upload.
- Consentelt aggregált telemetry: model version, quality bucket, accepted/rejected count, latency, user correction flag.
- Data retention, export és deletion flow.

### Elfogadási feltételek

- Logged-out/offline állapot 0 hálózati kérés.
- Opt-out azonnal leállít minden telemetriát.
- Privacy review és threat model PASS.
- Beta rollback egy kapcsolóval végrehajtható.

### Javasolt branch

```text
codex/recovery-r41-beta
```

### Javasolt commit

```text
release(beta): launch privacy-preserving recognition beta
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


## Kör 42 — Recovery program lezárása és production gate

### Cél

A Recovery akkor kész, ha nemcsak sok kód készült, hanem a felismerés és a fő user flow eléri a meghatározott kapukat valós eszközökön.

### Kötelező feladatok

- Frissítsd a README, HANDOFF, SDD index, traceability matrix, model cards, risk register és release runbook fájlokat.
- Töröld vagy archiváld a megtévesztő régi UI screenshotokat.
- Dokumentáld a megmaradt korlátokat és támogatott chord vocabularyt.
- Production rollout 1% → 5% → 20% → 50% → 100%, stop conditionökkel.

### Elfogadási feltételek

- Minden release gate PASS és bizonyítékkal linkelt.
- Rollback próba sikeres.
- Nincs nyitott P0/P1 recognition vagy mic lifecycle hiba.
- A projekt következő feature Epicje csak emberi jóváhagyással indul.

### Javasolt branch

```text
codex/recovery-r42-close
```

### Javasolt commit

```text
docs(recovery): close recognition and useful UI recovery program
```

### Körzáró evidencia

A PR leírásában szerepeljen:

- megváltoztatott publikus szerződések;
- futtatott parancsok és teljes kimenetük;
- mért baseline és új eredmény;
- corpus/split/model hash;
- ismert regresszió vagy elhalasztott tétel;
- rollback mód;
- reviewer által ellenőrizendő valós-eszközös lépés.


---

# 11. Elsőként végrehajtandó 12 kör

A legjobb első blokk:

```text
R01  Recovery program és feature freeze
R02  Reprodukálható baseline
R03  Model activation telemetry
R04  RecognitionFrame V2
R05  Signal quality
R06  Accuracy Lab capture
R07  Annotation tool
R08  Grouped evaluation
R09  Dashboard + release gate
R10  Direction abstention
R11  Chord uncertainty
R12  Provisional/confirmed stabilizer
```

R13 Live truthfulness hotfix ezután már a helyes domain contractra épülhet.

---

# 12. Tiltott gyorsjavítások

1. **Thresholdok vak átírása** egyetlen telefon vagy néhány kézi próba alapján.
2. **Synthetic-only siker** production evidence-ként.
3. **Nagyobb confidence szám** pontosságjavítás helyett.
4. **Minden event kötelező down/up címkézése.**
5. **Expected chord prior Free Play módban.**
6. **A Chord CRNN azonnali primary bekapcsolása shadow mérés nélkül.**
7. **Vision bekapcsolása az audio baseline elfedésére.**
8. **Új design animációk** a recognition truthfulness megoldása előtt.
9. **A tesztset használata threshold tuningra.**
10. **A corpus és model provenance elhagyása.**

---

# 13. Végső Definition of Done

A Chapter 14 csak akkor zárható le, ha:

## Felismerés

- [ ] Van verziózott, grouped saját validation corpus.
- [ ] Van end-to-end onset + direction + chord report.
- [ ] A direction modell tud abstainelni.
- [ ] A chord modell tud N.C./unknown állapotot.
- [ ] Confidence kalibrált és reliability reporttal igazolt.
- [ ] A Live UI csak confirmed predictiont mutat biztosként.
- [ ] A signal quality állapot actionable.
- [ ] Shadow A/B és rollback működik.
- [ ] Alpha/Beta release gate valós telefonon teljesült.

## UI és termék

- [ ] Chapter 13 a repositoryban van.
- [ ] Az app shell Today / Practice / Songs / Coach / Profile struktúrát használ.
- [ ] A Practice Engine látható és elsődleges flow.
- [ ] A Live filmstrip nem a fő felület.
- [ ] Uncertain állapot szöveggel, ikonnal és szemantikával jelenik meg.
- [ ] A felhasználó session végén konkrét javító lépést kap.
- [ ] Compact, landscape, tablet, 200% text, high contrast és TalkBack audit zöld.
- [ ] Offline módban nincs hálózati request.

## Release és governance

- [ ] Model manifest, checksum, model card és licence audit teljes.
- [ ] Corpus consent/licence/provenance teljes.
- [ ] A gate fail-closed.
- [ ] Rollback tesztelt.
- [ ] Nincs nyitott P0/P1 recognition vagy mic lifecycle hiba.
- [ ] README, HANDOFF, SDD index és traceability friss.

---

# 14. Kutatási források

1. Murgul, Schimper, Heizmann: **Joint Transcription of Acoustic Guitar Strumming Directions and Chords**, ISMIR 2025.  
   https://arxiv.org/abs/2508.07973
2. Hivatalos kód, checkpoint és dataset repository:  
   https://github.com/Klangio/guitar-strumming-transcription
3. Akram et al.: **ChordFormer: A Conformer-Based Architecture for Large-Vocabulary Audio Chord Recognition**, 2025.  
   https://arxiv.org/abs/2502.11840
4. Böck & Widmer: **Maximum Filter Vibrato Suppression for Onset Detection**, DAFx 2013.  
   https://www.dafx.de/paper-archive/details/0oee-99Z88WL7pSo749gcA
5. Guo et al.: **On Calibration of Modern Neural Networks**, ICML 2017.  
   https://proceedings.mlr.press/v70/guo17a.html
6. Cattelan & Silva: **How to Fix a Broken Confidence Estimator**, UAI 2024.  
   https://proceedings.mlr.press/v244/cattelan24a.html
7. Mao, Mohri, Zhong: **Predictor-Rejector Multi-Class Abstention**, ALT 2024.  
   https://proceedings.mlr.press/v237/mao24a.html
8. GuitarSet dataset, real guitar audio + rich annotation.  
   https://zenodo.org/records/3371780
9. GAPS: diverse real guitar audio across 200+ performers.  
   https://arxiv.org/abs/2408.08653
10. Flutter official adaptive UI guidance.  
    https://docs.flutter.dev/ui/adaptive-responsive/general
11. Flutter official accessibility guidance.  
    https://docs.flutter.dev/ui/accessibility
12. WCAG use of color and contrast.  
    https://www.w3.org/WAI/WCAG22/Understanding/use-of-color

---

# 15. Záró termékállítás

A helyes irány nem az, hogy a StrumSight még több menüpontot kapjon. A helyes irány:

> **Először legyen egy olyan Live és Practice élmény, amely inkább hallgat, mint hazudik; pontosan jelzi a bizonytalanságot; megmondja, hogyan javítsd a jelet; és minden mérésből egy konkrét következő gyakorlást készít.**

Ha ez a mag megbízható, akkor az AI Tutor, Song Trainer, Vision, Gamification és Community valóban értéket tud rá építeni.
