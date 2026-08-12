# E06-R17 — Review

Brief: `docs/rounds/e06-r17-monophonic-pitch-capability.md`
Diff: `2c08dc5b..2c02f031` (`codex/e06-r17-monophonic-pitch-capability`); implementer-only commit: `f5d5d613..2c02f031`
Reviewer: Claude (Opus 5, független review-ág) · Dátum: 2026-08-12
Verdikt: **CHANGES REQUESTED**

## Összegzés

BLOCKER: 0 · MAJOR: 3 · MINOR: 2 · NOTE: 2

A gate FORMAI oldala kifogástalan: 15/15 fájl az `allowed_paths`-on belül, a
teljes `tools/round-gate.sh test/features/audio_analysis test/property
test/core test/features/tuner` saját kézzel, izolált klónban, elölről
lefuttatva **teljesen zöld** (format, analyze, mind a 4 célzott teszt-útvonal,
architecture, secrets, l10n — ld. Gate-bizonyíték táblázat). A Tuner-paritás
bizonyítottan érintetlen fájllal áll.

A CONTENT oldalon három throwaway mutáció-próba (F1, F2, F3 alatt
dokumentálva, mind visszaállítva, a working tree jelenleg tisztán a
`2c02f031`-gyel azonos) azt mutatja, hogy a kör legkockázatosabb, KÉTSZERES
pre-flight-felülvizsgálaton átesett garanciája — a flag-kapu ELSŐSÉGE — a
SAJÁT dedikált tesztje által gyakorlatilag védtelen (a teszt egy másik,
véletlenül egybeeső feltétel miatt marad zöld akkor is, ha a flag-ellenőrzést
teljesen törlöm a forrásból), a kötelező NaN-mentesség property teszt nem a
valódi számítási láncot méri (egy `centsBetween`-be injektált NaN-bug mellett
zöld marad, miközben 9/11 fixture-teszt lefagy), és a „polifónia-kapu"
kritérium a brief által név szerint előírt négyhangos akkord-fixture helyett
egy kéthangú szekvenciális proxyval van lefedve. Egyik hiba SEM
produkciós-kód-defekt (a forráskód olvasása + a próbák is megerősítik: a
tényleges viselkedés a brief szerint helyes) — mindhárom **teszt-lefedettségi**
rés a kör legkritikusabb, névvel nevezett garanciáin.

**Fontos folyamat-megjegyzés (nem számít bele a BLOCKER/MAJOR/MINOR/NOTE
összesítésbe, mert nem kód-defekt):** a review indulásakor
(2026-08-12 12:2x UTC) az implementer `2c02f031` commitja **nem volt fent**
az `origin/codex/e06-r17-monophonic-pitch-capability`-n (sem a megosztott
`/home/ubuntu/music-theory` local branch-en) — csak egy különálló
implementer-klónban (`/home/ubuntu/ss-terra-e06-r17`, tiszta working tree,
`[ahead 1]`) létezett, `git push` nélkül. A review tartalmi részét emiatt
onnan (read-only fetch, SHA egyezés `2c02f0314c0dd0be3e8056abe5a210c9b5a5c439`
ellenőrizve) forrásoztam az izolált `/tmp/review-e06-r17` klónba. E jelentés
push-a (lásd alul) a `2c02f031`-et is felviszi `origin`-ra, mivel a helyi
branch-em erre épül — ez oldja fel a hiányt, de érdemes az orchestrátor
pipeline-jában megnézni, miért jelezte a #3 lépés („Verify scope audit +
commit implementer diff") kész-nek magát push nélkül.

## Acceptance criteria (brief §6)

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Frekvencia-mátrix (7 cella, A4+6 húr, ±2 cent, exact MIDI) | ✅ | `pitch_frame_extractor_test.dart` 7 parametrizált teszt (E2..A4), mind zöld a saját gate-futásban |
| 2 | Cent-offset küszöb hármas (+9.99/+10.00/+10.01, inkluzív +10.00) | ✅ | `pitch_metrics_test.dart:30-46` „intonation threshold is inclusive at +10.00 cents" — explicit 3-cellás tábla, zöld |
| 3 | Voiced-arány küszöb hármas (0.349/0.350/0.351, inkluzív 0.350) | ⚠️ RÉSZBEN | `pitch_capability_gate_test.dart:23-37` ténylegesen **69/70/71 / 200** (=0.345/0.350/0.355) frame-konstrukciót használ, nem a brief szó szerinti 0.349/0.350/0.351-jét, és a szubsztitúció OKÁT nem dokumentálja kommentben, holott a brief ezt kifejezetten kéri („a pontos konstrukciót a teszt dokumentálja"). Az inkluzivitás magának a 0.350-nek FUNKCIONÁLISAN helyesen bizonyított — ld. F5 (MINOR) |
| 4 | Polifónia-kapu: 4-hangos akkord → `unavailable`, hívásszámláló==0, chord/ritmus külön fut | ⚠️ RÉSZBEN | A KAPU LOGIKÁJA bizonyítottan védett (F3 mutáció-próba: a spread-ellenőrzés kikapcsolása 2 tesztet pirosra fog), DE a fixture 2 frekvenciás szekvenciális blokk, nem névvel nevezett 4-hangos akkord a valódi extractoron át — ld. F3 (MAJOR). A „chord/ritmus külön fut" felét a megosztott `test/features/audio_analysis` könyvtár zöld állapota (320 teszt, benne a pre-existing chord/rhythm/dynamics tesztek, EGYIK fájl sem érintett a diffben) közvetetten igazolja |
| 5 | Csend és zaj: mindkettő `unavailable`, dokumentáltan melyik ok | ⚠️ RÉSZBEN | Zaj: ✅ direkt teszt (`pitch_frame_extractor_test.dart:38-62`, gate-szintű `unavailable` + reason-halmaz). Csend: a kör saját tesztje (`silence yields only unvoiced frames`, 29-36. sor) csak az EXTRACTOR kimenetét nézi, a KAPUT sosem hívja — saját, eldobható próbateszttel megerősítve, hogy a helyes viselkedés (`unavailable`/`insufficientEvents`) valóban fennáll, de a kör SAJÁT suite-ja ezt nem bizonyítja — ld. F4 (MINOR) |
| 6 | Vibrato ±30 cent, 5 Hz → EGY szegmens, stabilityCents≈30±5 | ✅ | `pitch_frame_extractor_test.dart:64-69`, zöld |
| 7 | Hangváltás A4→C5 → KÉT szegmens, határ ±40 ms | ✅ | `pitch_frame_extractor_test.dart:71-83`, zöld |
| 8 | Tuner-paritás: tesztfája átírás nélkül zöld, diff nem érint `lib/core/audio/**`/`lib/features/tuner/**` | ✅ | `git diff --stat` mindkét útvonalra üres (implementer-commit ÉS teljes kör-diff); `test test/features/tuner`: 42/42 zöld, saját gate-futásban |
| 9 | Flag-kapu: `analysisPitchEnabled=false` ELSŐKÉNT, OD-01 (a)-(d) előtt, `notApplicable`, hívásszámláló==0 | ⚠️ RÉSZBEN | A PRODUKCIÓS KÓD helyesen elsőként ellenőrzi (`pitch_capability_gate.dart:57-65`, kommenttel is jelölve). A DEDIKÁLT teszt (`pitch_capability_gate_test.dart:6-21`) ezt viszont NEM tudja bizonyítani — ld. F1 (MAJOR), 2 önálló mutáció-próbával igazolva |
| 10 | NaN-mentesség property: véletlen bemenetre minden Hz/cents véges, confidence [0,1] | ❌ | `analysis_pitch_property_test.dart` fut és zöld, DE nem hívja a kör egyetlen számítási függvényét sem (`PitchFrameExtractor`, `MonophonicPitchSegmentBuilder`, `PitchCapabilityGate`, `buildPitchMetrics`) — csak már eleve véges, kézzel írt véletlen értékekkel konstruál value objecteket. Mutáció-próbával igazolva — ld. F2 (MAJOR) |

## Scope-audit

```
git diff --stat f5d5d613..2c02f031   →  15 files changed, 1157 insertions(+), 1 deletion(-)
```

Mind a 15 fájl szerepel a brief `allowed_paths` listáján (1:1 egyezés, sem
hiány, sem többlet). Tilos zóna (`lib/core/audio/**`, `lib/features/tuner/**`,
`lib/features/analyze/**`, `lib/features/live/**`) — **nulla** érintett fájl,
mind az implementer-commitra, mind a teljes kör-diffre (`2c08dc5b..2c02f031`)
ellenőrizve.

## Megállapítások

### F1 — MAJOR — A flag-kapu dedikált tesztje nem bizonyítja a saját nevében szereplő tulajdonságot

- **Fájl:** `test/features/audio_analysis/engine/pitch_capability_gate_test.dart:6-21`
- **Probléma:** A `'flag OFF short-circuits before every OD-01 check and metric
  callback'` teszt `hasMonophonicTarget: false`-t ÉS `analysisPitchEnabled:
  false`-t is beállítja egyszerre. Mivel `hasMonophonicTarget: false` ÖNMAGÁBAN
  is `notApplicable`-t ad (OD-01 (a) ág, `pitch_capability_gate.dart:66-74`),
  a teszt attól függetlenül zöld marad, hogy a flag-ellenőrzés ELSŐKÉNT fut-e,
  UTOLJÁRA fut-e, vagy akár teljesen HIÁNYZIK-e a forrásból.
- **Mutáció-próba (elvégezve, visszaállítva):**
  1. A flag-ellenőrzést a metódus VÉGÉRE helyeztem (az `available` return elé,
     tehát minden OD-01 (b)-(d) feltétel UTÁN, de még `onAvailable()` hívása
     előtt). Eredmény: `pitch_capability_gate_test.dart` mind a 4 tesztje
     ZÖLD marad — a dedikált teszt nem veszi észre az átrendezést, mert egyik
     inputja sem olyan kombináció (flag=false + valós target + egyébként
     mindent teljesítő frame-ek), ahol a sorrend megfigyelhető különbséget
     okozna.
  2. A flag-ellenőrzést TELJESEN semlegesítettem (`if (!analysisPitchEnabled
     && false)`). Eredmény: a dedikált gate-teszt TOVÁBBRA IS zöld (a
     `hasMonophonicTarget: false` konfundálás miatt); egyedül a
     `pitch_metrics_test.dart` „disabled or polyphonic capability…" tesztje
     bukik (`status` `available`-re vált `notApplicable` helyett) — ez a
     teszt VÉLETLENÜL fedi le a tulajdonságot (valós `target`, tiszta
     440 Hz-es frame-ek), noha nem elsődlegesen erre lett tervezve.
  - Mindkét mutáció visszaállítva (`cp` a mentett eredetiből,
    `git diff --stat` üres); a teljes pitch-tesztkör utána zöld.
- **Hatás:** Egy jövőbeli, jóhiszemű refaktor (pl. a feltételek olvashatósági
  átrendezése) csendben megszegheti az ADR 0235 Döntés 5 legfontosabb,
  KÉTSZERES pre-flight-körön átment garanciáját, és a NEVE SZERINT pontosan
  erre írt teszt ezt nem venné észre — csak egy másik fájl egy másik tesztje,
  amely nem dokumentálja, hogy ezt a szerepet is betölti.
- **Kötelező javítás:** a dedikált teszt fixture-jét szét kell választani: egy
  eset `analysisPitchEnabled: false, hasMonophonicTarget: true` VALÓS,
  egyébként mindent teljesítő frame-készlettel (ahogy a
  `pitch_metrics_test.dart`-beli `_frames()` teszi), hogy a flag-ellenőrzés
  önmagában, konfundálás nélkül bizonyítható legyen.
- **Ellenőrzés:** az új/módosított teszt a fenti mindkét mutációra (relokáció
  ÉS teljes törlés) pirosra váltson.
- **Státusz:** OPEN

### F2 — MAJOR — A „NaN-mentesség" property teszt nem hívja a kör egyetlen számítási függvényét sem

- **Fájl:** `test/property/analysis_pitch_property_test.dart:12-39`
- **Probléma:** A teszt közvetlenül konstruál `PitchFrame` és
  `MonophonicPitchSegment` value objecteket, MINDEN mezőt már eleve véges,
  `random.nextDouble()`-alapú kifejezésekkel töltve fel (pl.
  `centsOffset: random.nextDouble() * 100 - 50`). Sosem hívja a
  `PitchFrameExtractor.extract`, `MonophonicPitchSegmentBuilder.build`,
  `PitchCapabilityGate.evaluate`, sem a `buildPitchMetrics`/`buildGatedPitchMetrics`
  függvényeket — vagyis a kör tényleges, `math.log`/medián/percentilis/
  dropout-arány számítású kódját SOHA nem futtatja. Az `.isFinite` állítások
  gyakorlatilag azt bizonyítják, hogy a `PitchFrame`/`MonophonicPitchSegment`
  konstruktorok saját maguk validálnak — ami már a fix `pitch_frame.dart`/
  `monophonic_pitch_segment.dart` konstruktor-tesztjeiből is következik.
- **Mutáció-próba (elvégezve, visszaállítva):** a
  `monophonic_pitch_segment_builder.dart`-beli megosztott `centsBetween()`
  függvényt (amelyet a szegmens-építő, a kapu spread-számítása ÉS a metrika-
  motor hibaszámítása is használ) feltétel nélkül `double.nan`-re
  cseréltem.
  - `flutter test test/property/analysis_pitch_property_test.dart` → **ZÖLD**
    marad („All tests passed!") — a property teszt nem veszi észre.
  - `flutter test test/features/audio_analysis/engine/pitch_frame_extractor_test.dart`
    → **9/11 teszt PIROS**, `Invalid argument(s): Pitch segment cents values
    must be finite.` kivétellel (a `MonophonicPitchSegment` konstruktor maga
    dobja) — a hiba valódi és súlyos, csak nem a property teszt kapja el.
  - Visszaállítva (`cp` a mentett eredetiből, `git diff --stat` üres); utána
    a `test/features/audio_analysis/engine` könyvtár és a property teszt
    EGYÜTT futtatva 235/235 zöld.
- **Hatás:** a brief §6 utolsó, név szerint „NaN-mentesség property"-ként
  hivatkozott kritériuma formailag teljesül (a teszt létezik, fut,
  `PROPERTY_SEED` konvenciót követ), de VALÓS regresszió-védelmet nem ad a
  kör legkockázatosabb aritmetikájára (log/median/percentilis/osztás). A
  HORIZON-konvenció („New DSP behaviour ⇒ add a randomized property, not only
  fixed fixtures", CLAUDE.md) szellemével ez nem egyeztethető össze.
- **Kötelező javítás:** a property teszt véletlen, de érvényes tartományból
  vett FREKVENCIA-MINTÁKAT (vagy legalább véletlen `PitchFrame`-listákat)
  vezessen át ténylegesen a `MonophonicPitchSegmentBuilder.build` és/vagy a
  `buildPitchMetrics` függvényeken, és az EREDMÉNY mezőin ellenőrizze a
  végesség/tartomány-invariánsokat — ne a bemeneti value objectek saját
  validációját tesztelje vissza.
- **Ellenőrzés:** a fenti `centsBetween → double.nan` mutáció a javított
  property teszt mellett pirosra váltson.
- **Státusz:** OPEN

### F3 — MAJOR — A polifónia-kapu fixture-je nem a brief által név szerint előírt négyhangos akkord

- **Fájlok:** `test/features/audio_analysis/engine/pitch_capability_gate_test.dart:39-54`,
  `test/features/audio_analysis/engine/pitch_metrics_test.dart:67-88`
- **Probléma:** a brief §6 („Polifónia-kapu") és §6.1 mérce-mátrixa szó
  szerint „négyhangos akkord-fixture"-t ír elő. A tényleges tesztek egy
  **kéthangú, szekvenciális** frame-listát adnak a kapunak közvetlenül
  (`110 Hz × 20 frame` majd `440 Hz × 20 frame` konkatenálva) — sem valódi
  4-hangos akkord waveform nincs, sem a `PitchFrameExtractor`/valódi YIN nem
  fut rajta; a teszt csak a kapu SPREAD-küszöbének (>100 cent) elszigetelt
  logikáját méri.
- **Mutáció-próba (elvégezve, visszaállítva — a task 6(b) pontja szerint):** a
  spread-ellenőrzést semlegesítettem (`if (false && spread > maximumPitchSpreadCents)`).
  Eredmény: **2 teszt vált pirosra** —
  `pitch_capability_gate_test.dart`: „polyphonic proxy blocks metrics before
  the callback" (`unavailable` helyett `available`) és
  `pitch_metrics_test.dart`: „disabled or polyphonic capability…"
  (`reason` `polyphonicInput` helyett `null`). Ez megerősíti: a KAPU LOGIKÁJA
  ténylegesen védett, csak a FIXTURE TÍPUSA tér el az előírttól.
  Visszaállítva, `git diff --stat` üres, utána zöld.
- **Hatás:** a §5.4 architekturális döntés („Polifonikus bemenetre nincs
  hamis note score") a kör LEGMAGASABB tétjű garanciája. Egy valódi 4-hangos
  akkord a tényleges YIN-detektoron átfuttatva NEM feltétlenül produkál
  ugyanolyan nagy, tiszta spread-et, mint egy kézzel írt kéthangú blokk-lista
  (pitch-detektorok polifonikus bemeneten gyakran instabilan, de nem
  feltétlenül SZÉLES szórással viselkednek — pl. egy erős felharmonikuson
  „megülhetnek"). Ez a kör explicit kockázata (OD-01: „a V1 NEM végez
  polifónia-detektálást", proxy-alapú), és a brief pont ezért nevezte meg a
  konkrét fixture-típust — ezt a tesztkör jelenleg nem méri.
- **Kötelező javítás:** legalább egy teszt szintetizáljon 4, egyidejűleg
  összekevert szinusz-hullámot (pl. egy dúr akkord alaphangjai) valódi audio-
  mintaként, futtassa át a valódi `PitchFrameExtractor`-en, és bizonyítsa a
  `unavailable`/`polyphonicInput` kimenetet + hívásszámláló==0-t azon a
  láncon.
- **Ellenőrzés:** az új teszt bukjon, ha a spread-küszöb (vagy az azt
  helyettesítő valódi polifónia-jelző) hiányzik/hibás.
- **Státusz:** OPEN

### F4 — MINOR — A csend-fixture a kapu-szintű kimenetet nem bizonyítja

- **Fájl:** `test/features/audio_analysis/engine/pitch_frame_extractor_test.dart:29-36`
- **Probléma:** a „silence yields only unvoiced frames" teszt csak a
  `PitchFrameExtractor` kimenetét ellenőrzi (minden frame unvoiced), a
  `PitchCapabilityGate`-et sosem hívja. A brief §6 „Csend és zaj" pontja
  viszont a KAPU `unavailable`+dokumentált-ok kimenetét kéri, ahogy a zaj-
  esetnél helyesen meg is történik (60. sor körül, ugyanebben a fájlban).
- **Saját, eldobható próbateszt (elvégezve, visszaállítva):** ideiglenesen
  hozzáadtam egy tesztet, amely a csend-frame-eket ténylegesen átvezeti a
  `PitchCapabilityGate.evaluate`-en. Eredmény: **zöld**,
  `status=unavailable`, `reason=insufficientEvents` — a mögöttes VISELKEDÉS
  helyes (a `voiced.isEmpty` ág, `pitch_capability_gate.dart:84-90`, ezt a
  forráskód olvasásából is megerősíthetően garantálja). A próbatesztet
  eltávolítottam, `git diff --stat` üres.
- **Hatás:** funkcionális hiba NINCS (a próba ezt igazolja), de a kör SAJÁT
  suite-ja nem bizonyítja a brief által név szerint kért kapu-szintű
  kimenetet csendre — csak a zajra.
- **Kötelező javítás:** a meglévő „silence…" tesztet egészítse ki (vagy egy
  új teszt) a `PitchCapabilityGate.evaluate` hívásával és a
  `status`/`reason` explicit ellenőrzésével, ugyanabban a mintában, mint a
  zaj-teszt.
- **Ellenőrzés:** az új assertion bukjon, ha a `voiced.isEmpty` ág eltávolodik
  az `insufficientEvents`-től.
- **Státusz:** OPEN

### F5 — MINOR — A voiced-arány küszöb-hármas dokumentálatlanul tér el a brief szó szerinti celláitól

- **Fájl:** `test/features/audio_analysis/engine/pitch_capability_gate_test.dart:23-37`
- **Probléma:** a brief §6 explicit 0.349/0.350/0.351 cellákat kér
  (`200 frame` mellett ez 69.8/70.0/70.2 — tört frame-szám, tehát szó szerint
  konstruálhatatlan). A teszt emiatt (érthető okból) 69/70/71-et használ
  (0.345/0.350/0.355), DE a brief explicit kéri: „a pontos konstrukciót a
  teszt dokumentálja" — ez a dokumentáció (komment, miért 69/70/71 és nem pl.
  egy más totál-frame-szám, ami közelebb esne a névleges 0.349/0.351-hez)
  HIÁNYZIK a tesztfájlból.
- **Hatás:** a viselkedés funkcionálisan helyes (a pontosan 0.350
  inkluzivitása bizonyított), csak a nyomon-követhetőség hiányos —
  egy jövőbeli olvasó nem tudja megkülönböztetni „szándékos, dokumentált
  közelítés" és „elgépelt/hibás küszöb-cella" között.
- **Kötelező javítás:** egysoros komment a fixture fölé, ami rögzíti: miért
  69/70/71 és nem a névleges 0.349/0.350/0.351 (a tört frame-szám okát és a
  választott közelítés indoklását).
- **Ellenőrzés:** dokumentáció-jellegű, nincs teszt-következménye.
- **Státusz:** OPEN

### F6 — NOTE — A §10 handoff nem dokumentálja a mérce-mátrix saját maga kérte valódi-sértés próbát

- **Fájl:** `docs/rounds/e06-r17-monophonic-pitch-capability.md` §10
- **Probléma:** a brief §6.1 mérce-mátrixának utolsó sora explicit kéri:
  „Valódi-sértés próba (§10): a polifónia-kapu ideiglenes kiszedése → a
  négyhangos akkord unavailable cella PIROS → visszaállítás." A §10 handoff,
  ahogy az implementer kitöltötte, ezt nem említi (sem az elvégzését, sem az
  eredményét).
- **Hatás:** nem tudható a jelentésből, hogy az implementer elvégezte-e ezt
  önállóan; a review oldalán most pótlólag megtörtént (F3 alatt
  dokumentálva), de ez a REVIEWER munkája volt, nem az implementeré, ahogy a
  mérce-mátrix eredetileg szánta.
- **Kötelező javítás:** nem blokkoló; jövőbeli körökben a §10 kitöltésekor a
  mérce-mátrix saját-próba sorait explicit pipálja/dokumentálja az
  implementer.
- **Státusz:** OPEN (follow-up jellegű, nem blokkol)

### F7 — NOTE — ARB-beszúrás egy másik kulcs kulcs/metaadat párja közé ékelődik

- **Fájlok:** `lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb`
- **Probléma:** a 7 új `pitchMetric*` kulcs a `"aiTutorEvidenceMetric"` érték-
  sora ÉS a saját `"@aiTutorEvidenceMetric"` metaadat-sora KÖZÉ van beszúrva,
  nem egy logikailag összefüggő helyre (pl. a fájl végére, vagy egy meglévő
  pitch/tuner-blokk mellé). Funkcionális hatása nincs (egyik új kulcsnak sincs
  placeholdere, az l10n parity gate zöld), csak olvashatósági/diff-tisztasági
  nit.
- **Státusz:** OPEN (kozmetikai, nem blokkol)

## Gate-bizonyíték

Mind a négy célzott teszt-útvonal + a gate script beépített lépései, saját
kézzel, **elölről**, izolált `/tmp/review-e06-r17` klónban (a `2c02f031`-gyel
tartalmilag azonos, SHA-ellenőrzött forrásfa), `--result-json` strukturált
kimenettel:

| Gate | Állított eredmény (implementer §10) | Saját, független futtatás |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld | ✅ zöld (0 issue) |
| test test/features/audio_analysis | zöld | ✅ zöld — **320/320** teszt |
| test test/property | zöld | ✅ zöld — **86/86** teszt, `PROPERTY_SEED=42` |
| test test/core | zöld | ✅ zöld — **401/401** teszt |
| test test/features/tuner | zöld | ✅ zöld — **42/42** teszt, érintetlen fájlokkal |
| architecture | zöld | ✅ zöld — 12 előzetes (más körökből származó) allowlisted deviation, ÚJ eltérés nincs |
| secrets | (nem hivatkozott) | ✅ zöld — 2308 fájl, 0 találat |
| l10n parity | (nem hivatkozott) | ✅ zöld — en→hu, 1051 üzenet |

Strukturált eredmény (`ROUND_GATE_RESULT_FILE`):
`{"command_exit_code": 0, "error_hash": null, "exit_code": 0, "failed_step":
null, "outcome": "pass", "schema_version": 1}`

Az implementer §10 „célzott flutter test (20 teszt)" állítása pontos: a 4 új
pitch-tesztfájl összesen 4+11+4+1=20 tesztet regisztrál.

A 4513 ms-os (30 s-os A4 klip) mért futásidő a brief §9 saját kockázat-
bejegyzése szerint **előre jóváhagyott, nem-blokkoló** follow-up (E06-R29) —
nem defekt, a brief kifejezetten ezt írja elő 3 s fölötti mérésre.

## Mutáció-próbák — összefoglaló (mind eldobva, visszaállítva)

| # | Cél | Módszer | Eredmény |
|---|---|---|---|
| 1a | Flag-kapu sorrend (relokáció) | flag-check az `available` elé mozgatva | Mind a 4 dedikált teszt ZÖLD marad → konfundált fixture |
| 1b | Flag-kapu (teljes törlés) | `if (!analysisPitchEnabled && false)` | Csak `pitch_metrics_test.dart` 1 tesztje PIROS; a dedikált fájl végig zöld |
| 2 | Polifónia call-counter | spread-ellenőrzés `if (false && …)` | 2 teszt PIROS (gate + metrics fájl) — a kapu-logika védett |
| 3 | NaN-mentesség property valódisága | `centsBetween()` → feltétel nélkül `double.nan` | Property teszt ZÖLD marad; 9/11 fixture-teszt PIROS (`ArgumentError`) |
| 4 | Csend → kapu (megerősítés, nem sértés) | ideiglenes teszt hozzáadva, a gate-et hívva | ZÖLD, `unavailable`/`insufficientEvents` — viselkedés helyes, csak lefedetlen |

Minden módosítás visszaállítva mentett eredetiből; a végső `git status
--short` és `git diff --stat` (a terra-implementer `2c02f031` commitjához
képest is) üres — a review nem hagyott produkciós-kód változást.

## Merge-döntés

**CHANGES REQUESTED.** A gate teljesen zöld és a scope-audit tiszta, de az
ADR 0052 zöld-kapu ÖNMAGÁBAN nem elég: 3 nyitott MAJOR áll fenn (F1-F3),
mindegyik „hiányzó teszt a viselkedésváltozásra/garanciára" kategóriában — a
kör legkritikusabb, névvel nevezett, részben kétszeres pre-flight-kört is
kapott garanciáin (flag-kapu sorrend, NaN-mentesség, polifónia-fixture
hűsége). A produkciós kód ELLENŐRIZVE helyesen viselkedik mindhárom esetben
(a mutáció-próbák ezt is igazolják ott, ahol releváns) — a hiány kizárólag a
REGRESSZIÓVÉDELEM oldalán van. Javasolt javító kör: F1+F2+F3 (MAJOR) teszt-
kiegészítés, F4+F5 (MINOR) opcionálisan ugyanabban a körben, F6+F7 (NOTE)
nem blokkol.

Emellett — folyamat-oldalon, nem review-tartalom — a `2c02f031` push-
hiányosságát ez a review commit oldja fel (ld. Összegzés); érdemes az
orchestrátor pipeline #3 lépését (push-megerősítés) megerősíteni, hogy ez ne
ismétlődjön.
