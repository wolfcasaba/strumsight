# E06-R05 — Review

Brief: docs/rounds/e06-r05-input-abstraction-and-safe-import.md
Diff: `git diff a7507a58...7b5a4e1c`
Reviewer: Claude (independent review subagent) · Dátum: 2026-08-11
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 2 · NOTE: 3

Gépi scope-audit: 11/11 changed file ∈ allowed_paths, zero extras. Saját,
izolált `/tmp` klónban újrafuttatott gate (format/analyze/4 célzott
teszt-útvonal/architecture/secrets/l10n) mind ZÖLD. Három saját
valódi-sértés mutáció lefuttatva (kettő a vártnak megfelelően pirosra
fordult, egy — a chunk-size overflow-formula csere — Dartban nem
diszkriminál, lásd F6). A `RangeError`/`ArgumentError` catch-ágak
instrumentált méréssel **soha nem tüzeltek** a kör saját suite-jén és 10
különböző fuzz-seeden (5000 eset) — defenzív, jelenleg holt kód. Eközben
egy **kézzel célzott** (nem fuzz-) próba egy valódi, reprodukálható rést
talált: egy második, `_inspect` által soha meg nem vizsgált `data` chunk
NaN/Inf float32 mintát tud átcsempészni az importált útra `Success`-ként —
ez a brief §6 NaN-mátrix kritériumának explicit ígéretét sérti egy olyan
bemenetre, amit sem a fuzz, sem az egységtesztek nem fednek le (F1,
MAJOR). A javítás a kör saját, engedélyezett `wav_decoder_adapter.dart`
fájlján belül elvégezhető, az érintetlen core dekódert nem érinti — nem
váltja ki a brief §9 STOP-klauzuláját.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Formátum-mátrix — 7 cella (16-bit mono/stereo, float32 mono/stereo → Success; 8-bit/24-bit → `unsupportedBitDepth`, ADPCM → `unsupportedFormat`) | ✅ | `audio_decoder_gateway_test.dart:20-93`; saját futtatás: `flutter test test/features/audio_analysis/data/audio_decoder_gateway_test.dart` → 15/15 zöld |
| 2 | Malformed-mátrix — 6 cella (non-RIFF, non-WAVE, csonkolt fmt, csonkolt data, data>hátralévő bájtok, `0xFFFFFFFF`) | ✅ | `audio_decoder_gateway_test.dart:96-172` (+1 bónusz cella: stereo incomplete frame); mind `invalidRiff`/`truncatedChunk`/`chunkSizeOutOfBounds`-ra fut, crash nélkül — saját Mutation-B próba alatt is (lásd lent) |
| 3 | Fájlméret-küszöb hármas: 67 108 863/864/865 | ✅ | `analysis_input_validator_test.dart:12-22`, python3-kommenttel egyező pontos értékek; saját **Mutation-A** (a check ideiglenes eltávolítása) → pontosan a `67108865` cella ment pirosra (`Expected Failure<void>, Actual Success<void>` a `file-size limit is inclusive at 64 MiB` teszten), majd visszaállítva → zöld |
| 4 | Hossz-küszöb hármas: 11 999/12 000/12 001 és 28 799 999/28 800 000/28 800 001 | ✅ | `analysis_input_validator_test.dart:24-52`, python3-kommenttel egyező pontos értékek; saját **Mutation-C** (`sampleCount < minSamples` → `<=`) → pontosan a 12 000-mintás cella (+ 2 másik, ugyanazt a rögzítést újrahasználó teszt) ment pirosra, majd visszaállítva → zöld |
| 5 | NaN-mátrix: importált → 3× `nonFiniteSample` Failure; mikrofon → 3× Success+warning+0.0, többi minta változatlan | ✅ (a leírt teszt szerint) — **de lásd F1** | `analysis_input_validator_test.dart:54-144` mind zöld. A tesztek `validator.validate()`-et hívják közvetlenül, a WAV-bájt-elemző réteget megkerülve — F1 egy, a teljes import-csővezetéken (adapter+legacy dekóder) át reprodukálható rést mutat, amit ez a kritérium — ahogy írva van — nem fed le |
| 6 | Fuzz property: `PROPERTY_SEED` ≥500 eset, ≤64 KiB/eset, csak véges Success-PCM | ✅ | `analysis_input_fuzz_property_test.dart` — saját futtatás izoláltan és a teljes `test/property` alatt (`-r expanded`, `+72: All tests passed!`, a fuzz teszt a +16. helyen); saját 10-seedes sweep (1,2,3,42,60605,999999,123456789,7,8675309,271828 × 500 = 5000 eset) — 0 hiba, 0 catch-tüzelés. Seed-konvenció eltérés: F2 |
| 7 | Fájlnév-redakció: `toString()` sosem nyers, 0 logger-hívás | ✅ | `analysis_input.dart:17` (`SourceDisplayName.toString()` fix string, sosem interpolálja `.value`-t) + `analysis_input_validator_test.dart:146-157`; saját `grep -rniE "logger\|print(\|debugPrint\|log(" lib/features/audio_analysis/domain/analysis_input.dart lib/features/audio_analysis/data/input/*.dart` → 0 találat (csak egy doc-comment említi a szót) |
| 8 | Core dekóder bitre változatlan | ✅ | `git diff a7507a58...7b5a4e1c -- lib/core/audio/codec/wav_decoder.dart` → üres; `git diff a7507a58...7b5a4e1c -- test/features/analyze/wav_decoder_test.dart` → üres; `flutter test test/features/analyze` a gate-ben zöld (64/64) |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs**. `git diff --stat
a7507a58...7b5a4e1c` 11 fájlt mutat, mind a brief `ai-router.allowed_paths`
listáján (10 kód/teszt fájl + a brief maga). `app_failure.dart` diffje
kizárólag additív: 12 új `static const String` sor, a hunk (`@@ -37,6
+37,20 @@`) minden módosított sora `+`; egyetlen meglévő konstans sem
törölt/átnevezett. `AnalysisInputSource` enum kizárólag a meglévő
`domain/analysis_mode.dart`-ban létezik (`grep -rn "enum
AnalysisInputSource"` → 1 találat); az új `domain/analysis_input.dart` csak
importálja, nem deklarálja újra. `public.dart` diffje egyetlen új export
sor (`domain/analysis_input.dart`). Import-irány: `core/foundation/app_failure.dart`
0 importtal (nem függ feature-től); az új `data/input/*.dart` fájlok
`core/`-ból és a saját feature `domain/`-jából importálnak, sosem
fordítva; `domain/analysis_input.dart` csak `dart:typed_data` + sibling
domain fájlokat importál. `tool/check_architecture.dart` (a checker maga)
diffje üres, és az allowlistben nincs az új fájlokra hivatkozó bejegyzés —
a gate „12 allowlisted deviation(s)" üzenete meglévő, e körtől független
tételekből jön.

## Megállapítások

### F1 — MAJOR — Második, nem validált `data` chunk NaN/Inf mintát csempész át az importált útra `Success`-ként

- **Fájl:** `lib/features/audio_analysis/data/input/wav_decoder_adapter.dart:154-188` (`_inspect`, a `'data'` ágon **azonnal visszatér** az ELSŐ talált `data` chunk alapján) ↔ `lib/core/audio/codec/wav_decoder.dart:41-53` (a `decode()` ciklusa **folytatja** a bájt-tartomány pásztázását, és bármelyik `'data'`-taggel jelölt chunk felülírja a `pcm` változót — az UTOLSÓ `data` chunk PCM-je nyer) ↔ `lib/core/audio/codec/wav_decoder.dart:95` (`out[i] = (acc / channels).clamp(-1.0, 1.0);`)
- **Probléma:** `_inspect()` a NaN/Inf-ellenőrzést (float32 esetén) és a méret/blockAlign-konzisztenciát **kizárólag az első `data` chunkon** végzi el, majd `Success`-t ad vissza. A változatlan legacy dekóder viszont a FÁJL VÉGÉIG pásztáz, és ha egy MÁSODIK `data` chunk is szerepel a bájtsorban, annak PCM-je íródik a végeredménybe (felülírva az elsőt) — ezt a második chunkot `_inspect` sosem látta. Ha ez a második chunk NaN/±Inf float32 mintát tartalmaz, a legacy dekóder saját `.clamp(-1.0, 1.0)` hívása **csendben** 1.0-ra/±1.0-ra konvertálja (Dart `num.clamp` `compareTo`-szemantikája: NaN „nagyobbnak" számít a felső határnál). Az `AnalysisInputValidator.validate()` NaN-vizsgálata csak EZUTÁN fut, a már „kimosott", véges mintán — így ott sem akad fenn semmi.
- **Hatás:** a brief §6 NaN-mátrix kritériuma explicit ígéretet tesz: „importált úton NaN/+Inf/−Inf → `nonFiniteSample` Failure". Ez a bemenet-alak (2 `data` chunk, valid RIFF/WAVE/fmt) ezt megkerüli: `Success<PcmAnalysisInput>` jön vissza egy csendben 1.0-ra torzított mintával — hibás, de észrevétlen elemzési bemenet. A kör saját 500-esetes véletlen-bájt fuzzja ezt gyakorlatilag sosem konstruálja meg (egy jólformált, két-`data`-chunkos RIFF valószínűsége tiszta véletlen bájtokból elhanyagolható), és egyetlen egységteszt sem fedi (az `analysis_input_validator_test.dart` NaN-tesztjei közvetlenül `validator.validate()`-et hívják, megkerülve a WAV-bájt-réteget).
- **Kötelező javítás:** `_inspect()`-nek vagy (a) el kell utasítania minden WAV-ot, amiben egynél több `'data'` chunk van, vagy (b) a legacy dekóderrel azonos „utolsó `data` chunk számít" szemantikával kell pásztáznia/NaN-ellenőriznie — MINDKETTŐ a kör saját, engedélyezett `wav_decoder_adapter.dart`-ján belül elvégezhető, az érintetlen core dekódert nem kell módosítani, tehát ez **nem** váltja ki a brief §9 STOP-klauzuláját (az a core dekóder algoritmusának megváltoztatására vonatkozik).
- **Ellenőrzés:** saját eldobható próba (`test/_probe_double_data_test.dart`, megírva → lefuttatva → törölve, sosem commitolva) egy fmt(format=3, 32-bit float, mono, 48 kHz) + data-chunk-1 (12 000×0.25, tiszta) + data-chunk-2 (12 000 minta, első=`double.nan`) WAV-ot épített. `WavDecoderAdapter().decodeInput(...)` → `Success<PcmAnalysisInput>(sampleCount: 12000, allFinite: true, first: 1.0)`. Külön, izolált `dart run` szkripttel megerősítve a gyökérok: `double.nan.clamp(-1.0, 1.0) = 1.0 isFinite=true`; `double.infinity.clamp(-1.0,1.0)=1.0`; `double.negativeInfinity.clamp(-1.0,1.0)=-1.0`. A hiba kizárólag a float32 (format 3) útra korlátozódik — a 16-bit PCM ág egész aritmetikát használ, nem tud NaN/Inf-et termelni.
- **Státusz:** OPEN

### F2 — MINOR — A fuzz-teszt eltér a repó `PROPERTY_SEED` konvenciójától

- **Fájl:** `test/property/analysis_input_fuzz_property_test.dart:17`
- **Probléma:** `int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 60605` — a `test/property/` alatti mind a 22 MÁSIK fájl `?? 42`-re esik vissza (grep-gel ellenőrizve az összesen 23 fájlból), összhangban a CLAUDE.md HORIZON-konvenciójával („absent → seed 42, deterministic dev loop"). Ez a fájl indoklás/komment nélkül `60605`-öt használ, és — a másik 22 fájltól eltérően — sosem írja ki `print('PROPERTY_SEED=$seed')`-et, ami egy helyi (nem CI) fuzz-hiba reprodukálásához kellene.
- **Hatás:** kozmetikai/konzisztencia — a teszt helyesen működik, a CI a saját `PROPERTY_SEED=${{ github.run_id }}`-jével felülírja mindenképp. Egy jövőbeli karbantartó viszont a log-ból nem tudná megállapítani, melyik seed futott egy helyi hibánál.
- **Kötelező javítás:** fallback `?? 42`-re, plusz egy `print('PROPERTY_SEED=$seed');` sor a másik 22 fájl mintájára.
- **Ellenőrzés:** `grep -n "PROPERTY_SEED" test/property/*.dart` — mind a 22 másik fájl `?? 42`, ez az egy `?? 60605`.
- **Státusz:** OPEN

### F3 — MINOR — A mikrofon-NaN „többi minta változatlan" teszt nem bizonyítja teljeskörűen a triviálistól eltérő esetet

- **Fájl:** `test/features/audio_analysis/data/analysis_input_validator_test.dart:110-144`, `_samplesWith` helper: 165-173
- **Probléma:** a tömb `List<double>.filled(12000, 0.0)` alapú, mindössze 3 nem-alapértelmezett elemmel (`prefix`, hossz 3). A `.skip(3).every((sample) => sample == 0.0)` állítás triviálisan igaz attól függetlenül, hogy a sanitizer helyesen van-e implementálva, mert ezek a minták a sanitizálás ELŐTT is már 0.0 voltak — egy olyan hiba, ami MÁS (nem-NaN) mintákat is lenulláz, ezzel a tömb-alakkal nem bukna el. A `.take(3)` ellenőrzés (0.25/0.0/-0.5) 2 nem-nulla pozíciót érdemben fed — ez részleges, nem teljes rés. (Kód-olvasással megerősítve — `analysis_input_validator.dart:89-94` — hogy a tényleges sanitizáló ciklus kizárólag a nem-véges indexeket módosítja, tehát az implementáció helyes; ez egy teszt-szigor észrevétel, nem élő hiba.)
- **Hatás:** alacsony — az implementáció (kód-olvasással) helyes, csak a teszt nem bizonyítja azt egy változatosabb tömbön.
- **Kötelező javítás:** egy minden indexen egyedi, nem-nulla értékű fixture, hogy a „változatlan" állítás ne triviálisan teljesüljön.
- **Státusz:** OPEN

### F4 — NOTE — `practiceSession`/`songSession` NaN-kezelés: a brief nem tér ki rá explicit

- **Fájl:** `lib/features/audio_analysis/data/input/analysis_input_validator.dart:83` (`if (input.source != AnalysisInputSource.microphone)`)
- **Megfigyelés:** a brief §5 6. pontja és a §6 NaN-mátrix kizárólag az importált-vs-mikrofon bináris felosztást tárgyalja/teszteli. Az implementáció `validate()`-je minden, `microphone`-tól ELTÉRŐ `AnalysisInputSource` értéket — tehát nemcsak `importedFile`-t, hanem a meglévő `practiceSession` és `songSession` értékeket is — „NaN-on elutasít" módon kezel. Ez egy védhető, konzervatív alapértelmezés (elutasítás, hacsak nem bizonyítottan mikrofon-eredetű) egy enumhoz, aminek a switch/if-ágát valahogy exhaustívvá kellett tenni — de a brief-ben nyitva hagyott, fel nem oldott kérdés marad, hogy ez-e a szándékolt viselkedés.
- **Hatás:** nincs élő hiba; dokumentációs/spec-rés egy jövőbeli kör/brief számára tudatos eldöntésre.
- **Státusz:** OPEN (spec-rés, nem kódhiba)

### F5 — NOTE — A záró commit (`7b5a4e1c`) a review időpontjában még nem volt push-olva origin-re

- **Fájl:** n/a (repó-állapot, nem kód)
- **Megfigyelés:** a kör-tények szerint Head = `7b5a4e1c`, de `git ls-remote
  https://github.com/wolfcasaba/strumsight.git
  codex/e06-r05-input-abstraction-and-safe-import` a review idején csak
  `9b1c7ebf`-et adta vissza (a pre-flight commit); `7b5a4e1c` kizárólag az
  implementer helyi fájában (`/home/ubuntu/ss-terra-e06-r05`) létezett
  („ahead of origin by 1 commit"). A review-eljárás 1. lépése sima
  `git clone`-t ír elő GitHub-ról — ez a commit hiánya miatt nem hozta
  volna be a tényleges fejet. Megoldás: helyi-transzport `git fetch
  /home/ubuntu/ss-terra-e06-r05 codex/e06-r05-input-abstraction-and-safe-import`
  az izolált `/tmp` klónba (a forrás fát nem módosítja, csak olvas belőle),
  majd `git checkout FETCH_HEAD` — a `7b5a4e1c` SHA innentől megerősítve
  egyezik a kör-tények Head-jével.
- **Hatás:** merge-blokkoló, amíg az orchestrátor nem push-olja a branch-et —
  de ez folyamat-kérdés, nem kódhiba.
- **Státusz:** OPEN (orchestrátor teendő: push)

### F6 — NOTE — A chunk-size overflow-formula csere (§5a) Dartban nem diszkriminál

- **Fájl:** `lib/features/audio_analysis/data/input/wav_decoder_adapter.dart:103`
- **Megfigyelés:** a brief §6.1 mérce-mátrixa szerint a `chunkSize > bytes.length - body` → `body + chunkSize > bytes.length` csere a `0xFFFFFFFF` overflow-cellát pirosra kellene fordítsa. Saját **Mutation-B** próba (alkalmazva → `audio_decoder_gateway_test.dart` + `analysis_input_fuzz_property_test.dart` lefuttatva → mind a 16 teszt ZÖLD maradt → visszaállítva) ezt NEM erősítette meg. Gyökérok: Dart egészei nem csordulnak túl 32 bitnél — `body + 0xFFFFFFFF` (~4,3 milliárd) kényelmesen belefér Dart natív int tartományába, így a mérce-mátrix által modellezett wraparound-hiba-osztály (fix szélességű egészes nyelvekből) WAV-realisztikus nagyságrendeken (`maxFileBytes` = 64 MiB ≪ 2^53) nem reprodukálódik Dartban.
- **Hatás:** nincs — az implementáció továbbra is helyesen a brief által előírt biztonságosabb (kivonás-előbb) formulát követi; ez csak azt jelzi, hogy ez a konkrét mérce-mátrix-sor Dartban nem empirikusan diszkriminatív.
- **Státusz:** informatív, nincs teendő

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | ZÖLD | ✅ — `dart format --output=none --set-exit-if-changed lib test tool` → „Formatted 1263 files (0 changed) in 4.71 seconds." |
| analyze | ZÖLD (implementer egy `.gitignore`-olt, hiányzó `app_localizations.dart` miatti újrafutást jelzett) | ✅ — saját futtatásban a hiba nem jelentkezett újra (a `flutter pub get` build-hookjai generálták); „No issues found! (ran in 18.2s)" |
| test test/features/audio_analysis | ZÖLD (implementer: 15+5 célzott teszt) | ✅ — 55/55 teszt zöld ebben a mappában összesen (a gateway 15 + validator 5 + a mappa többi, e körtől független tesztje); `flutter test test/features/audio_analysis` → „All tests passed!" |
| test test/property | ZÖLD (implementer: 1 seedelt fuzz, 500 eset) | ✅ — `flutter test test/property` → „+72: All tests passed!"; a compact reporter nem írta ki külön a fuzz-fájl nevét (konkurrens-futás megjelenítési sajátosság) — `-r expanded` újrafuttatással függetlenül megerősítve, hogy a fuzz teszt ott fut és zöld (+16. pozíció) |
| test test/core | (a brief gate_tests listáján, implementer nem részletezte) | ✅ — 31/31 zöld |
| test test/features/analyze | ZÖLD (implementer: V1 érintetlen) | ✅ — 64/64 zöld, ezen belül a változatlan `wav_decoder_test.dart` |
| architecture | ZÖLD | ✅ — „Architecture dependencies OK (12 allowlisted deviation(s))." — a 12 tétel egyike sem hivatkozik az új fájlokra |
| secrets | (bónusz gate-lépés) | ✅ — „Secret scan OK (2180 file(s) scanned, 0 finding(s))." |
| l10n | (bónusz gate-lépés) | ✅ — „L10n parity OK (en → hu, 1019 message(s))." |

## Merge-döntés

**CHANGES REQUIRED.** A kör formális fegyelme erős — a gate hazugság
nélkül zöld, a scope-audit tiszta, 7 a 8 acceptance-kritériumból szó
szerint és bizonyítottan teljesül, a `FailureCode`-bővítés valóban
additív, a core dekóder és tesztje bitre érintetlen, és a `RangeError`/
`ArgumentError` catch-ágak — instrumentált méréssel, a kör saját suite-jén
és egy 5000-esetes saját fuzz-sweepen — sosem tüzeltek, tehát nem a brief
§9 STOP-klauzulája alá eső, rejtve tartott core-parser-hiba.

Azonban egy **kézzel célzott** (nem a fuzz által automatikusan talált)
próba egy valódi, reprodukálható rést mutatott (F1, MAJOR): egy második,
`_inspect` által sosem vizsgált `data` chunk NaN/Inf float32 mintát tud
`Success`-ként átcsempészni az importált útra, közvetlenül megsértve a
brief §6 NaN-mátrix ígéretét egy olyan bemenetre, amit sem a kör fuzz-, sem
egységtesztjei nem fednek le. A javítás behatárolt és a kör saját,
engedélyezett fájlján (`wav_decoder_adapter.dart`) belül elvégezhető — nem
igényel új kört vagy a core dekóder módosítását —, de amíg nyitott, a
`AGENTS.md`/`ADR 0055` merge-mércéje („nulla OPEN BLOCKER/MAJOR") szerint
ez a kör nem mergelhető változatlanul.

**Kötelező a merge előtt:** F1 javítása (a `_inspect` utasítsa el a
többszörös `data` chunkot, VAGY pásztázza/NaN-ellenőrizze ugyanazt az
„utolsó `data` chunk számít" tartományt, mint a legacy dekóder) + egy új
regressziós teszt erre a konkrét bemenet-alakra. F2 és F3 (MINOR) ajánlott,
de nem blokkoló; F4 dokumentálható a brief-ben egy jövőbeli körre; F5-öt az
orchestrátornak kell rendeznie (push origin-re) a CI-dispatch előtt; F6
tisztán informatív, nincs teendő.
