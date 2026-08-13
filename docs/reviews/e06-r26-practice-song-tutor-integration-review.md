# E06-R26 — Review

Brief: `docs/rounds/e06-r26-practice-song-tutor-integration.md`
Diff: `git diff e510695a..e8faa8fd` (pre-flight commit → implementer commit)
Reviewer: Claude (Sonnet 5, pipeline orchestrator) · Dátum: 2026-08-13
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 0 · MAJOR: 4 · MINOR: 1 · NOTE: 1

A gate a saját, izolált `/tmp/review-e06-r26` klónomban függetlenül zöld
(format/analyze/`test/features/audio_analysis` 533/`test/tooling` 64/
`test/app` 73/architecture 12-entry/secrets/l10n — mind ZÖLD), a scope-audit
tiszta (12 megváltozott útvonal, mind az `allowed_paths`-on belül, 0
generated/ignored), és a `.codex-round-status` `gate_shape=VIOLATION` jelzése
**hamis pozitívnak bizonyult** — a naplóban az egyetlen találat a
`docs/LESSONS.md` L245 saját szövege volt (az implementer a kötelező
előolvasás részeként olvasta be a fájlt), nem egy ténylegesen csonkított/
láncolt gate-hívás; lásd alább. A kód formailag fegyelmezett és jól
strukturált — a talált problémák mind TARTALMI hiányok, amiket a zöld gate
nem fog meg (pontosan azért fut független review).

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Practice round-trip (darabszám/idő/típus/irány, targetVersion) | ✅ | `practice_analysis_adapter_test.dart:16-37` — 2 esemény, exact µs-idő, típus `[strum, chordChange]`, `direction.name=='down'`, `targetVersion=7` |
| 2 | Practice score nem duplikálódik | ✅ | `PracticeAnalysisEvidence` típusnak nincs `sessionScore`/`PracticeScore` mezője (zárt mezőlista); + forrás-szöveg teszt (`practice_analysis_adapter_test.dart:39-46`) |
| 3 | Retry-tempo küszöb hármas + alsó korlát (4. cella: clamp 60%-ra) | ❌ | **F1** — a clamp strukturálisan elérhetetlen, nincs teszt rá |
| 4 | Song capo/transzpozíció mátrix — hat cella, konkrét MIDI | ✅ | `song_analysis_adapter_test.dart:10-27`, mind a 6 cellát magam is újraszámoltam (`display=input+transpose`, `concert=display+capo`) — egyezik |
| 5 | Backing offset és sebesség — három cella | ✅ | `song_analysis_adapter_test.dart:29-42`; magam újraszámoltam: `250000+round(1000000/0.75)=1583333` — egyezik |
| 6 | Tutor-redakció (nincs PCM/waveform/fájlnév/deviceId, ≤50 event) | ✅ | `tutor_analysis_snapshot_test.dart` + **saját, független valódi-sértés próbám** (5. szakasz) |
| 7 | Tutor-immutabilitás (nincs visszaút) | ✅ | `events.add(...)` → `throwsUnsupportedError`; `TutorAnalysisSnapshot` egyetlen mezője sem hordoz `AnalysisDocument`-referenciát |
| 8 | Progress evidence egyszer (2. feldolgozás nem hoz újat) | ✅ | `progress_evidence_adapter_test.dart:5-13` — második `credit()` hívás `null` |
| 9 | Határ-őr (csak `public.dart` import, allowlist nem nőtt) | ✅ | `analysis_cross_feature_boundary_test.dart` — regex-scan `lib/features/audio_analysis/**`-re, 12 allowlist-bejegyzés számolva |
| 10 | Flag-kapu (mindkét flag OFF, adapter-providerek nem példányosulnak, hívásszámláló) | ❌ | **F2 + F4** — Progress-nek nincs providere/flag-je; Song providere van, de nincs hívásszámláló teszt |
| 11 | Más feature-ök érintetlenek | ✅ | `git diff --stat` / scope-audit: 12 fájl, mind `audio_analysis`/`feature_flags.dart`/`test/`/`docs/rounds/` alatt — nulla `practice\|song_trainer\|ai_tutor\|progress\|analyze` feature-fájl |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.**
`python3 tools/scope-audit.py --repo /tmp/review-e06-r26 --brief docs/rounds/e06-r26-practice-song-tutor-integration.md --base e510695a` →
`Legacy scope audit OK (e510695a..e8faa8fd, 12 changed path(s), 0 generated/ignored)`.
Mind a 12 megváltozott fájl szerepel a brief `allowed_paths` listáján; a
`tool/check_architecture.dart`-ot az implementer NEM módosította (nem volt
rá szükség — a 12-es allowlist változatlan maradt, ahogy a §9 kockázat
előre jelezte).

## Megállapítások

### F1 — MAJOR — A retry-tempo 60%-os alsó korlátja (`clamp`) strukturálisan elérhetetlen; a brief kötelező "negyedik cellája" bizonyítatlan

- **Fájl:** `lib/features/audio_analysis/application/adapters/practice_analysis_adapter.dart:148-164`
- **Probléma:** `recommendedRetryTempo` egy 4-ágú `switch`-csel számolja a `reduction`-t, aminek maximuma **fixen `strongReduction = 0.15`** (a `_` alapértelmezett ág is ezt adja, FÜGGETLENÜL attól, mekkora a bemenő `timingErrorSeverity`). Emiatt `targetTempo * (1 - reduction) >= targetTempo * 0.85` **minden** bemenetre — a `.clamp(targetTempo * 0.60, double.infinity)` alsó korlátja SOHA nem tud aktiválódni, mert `0.85 * targetTempo` sosem esik `0.60 * targetTempo` alá semmilyen véges pozitív `targetTempo`-ra. A brief §6 explicit negyedik cellát kér: "egy negyedik cella, ahol a számított tempó a target 60%-a alá esne → a javaslat pontosan 60% (clamp)" — ez a cella a jelenlegi kód mellett **nem konstruálható**, és a `practice_analysis_adapter_test.dart`-ban valóban nincs is ilyen teszt (a legszélsőségesebb eset, `timingErrorSeverity: 1`, `50 * 0.85 = 42.5`-öt ad, ami messze `50 * 0.6 = 30` fölött van — a clamp nem aktiválódik ott sem).
- **Hatás:** a mérce-mátrix (§6.1) "A retry-tempo 60% alá megy → a clamp-cella" sora véd egy olyan regresszió ellen, amit a jelenlegi implementáció sosem tudna produkálni ÉS sosem tudna helyesen kezelni sem — ha egy jövőbeli kör mégis szükségesnek látná a 60%-os padlót ténylegesen elérni (pl. összetettebb/súlyosabb timing-hiba jelzésnél), a clamp kód MA nem bizonyítottan helyes, csak véletlenül sosem fut le.
- **Kötelező javítás:** VAGY (a) a severity→reduction lépcsőt bővíteni úgy, hogy létezzen olyan bemenet, ami >40%-os redukciót adna a clamp előtt (pl. egy explicit "ismételt sikertelen kísérlet" súlyozás vagy egy szélesebb küszöb-sáv), VAGY (b) ha a termékdöntés az, hogy 15% a valódi maximum redukció és a 60%-os padló csak egy védőháló egy jövőbeli bővítéshez, akkor ezt dokumentálja a brief §0.0-jában egy revízióval, és a `recommendedRetryTempo`-t (vagy egy dedikált, közvetlenül tesztelhető metódust) tegye tesztelhetővé egy szimulált/nyers redukciós értékkel, hogy a clamp MAGA bizonyítottan helyes legyen, függetlenül a severity→reduction lépcsőtől.
- **Ellenőrzés:** egy negyedik teszt-cella, ami ténylegesen `< targetTempo * 0.6` eredményt várna a clamp ELŐTT, és `== targetTempo * 0.6`-ot a clamp UTÁN.
- **Státusz:** OPEN

### F2 — MAJOR — `ProgressEvidenceAdapter`-nek nincs flag-kapuzott providere; egyik új flag sem tudja kikapcsolni

- **Fájl:** `lib/features/audio_analysis/application/adapters/progress_evidence_adapter.dart` (teljes fájl)
- **Probléma:** a másik három adapter (`PracticeAnalysisAdapter`, `SongAnalysisAdapter`, `TutorAnalysisSnapshotAdapter`) mindegyike kapott egy `*Factory` interfészt + `*FactoryProvider`-t + egy flag-ellenőrző `*Provider`-t (`if (!ref.watch(appConfigProvider).flags.analysis…Enabled) return null;`). A `ProgressEvidenceAdapter`-nek **egyike sincs** — nincs `flutter_riverpod` import, nincs `app_config.dart` import, nincs flag-ellenőrzés SEHOL a fájlban. A `feature_flags.dart` diff mindkét új flag doc-commentje is csak Practice/Song-ot és Tutor-t nevesíti ("Whether Analysis evidence adapters for Practice and Song may instantiate" / "Whether the redacted Analysis-to-Tutor adapter may instantiate") — a Progress-adapter EGYIK flag alá sincs besorolva, sem dokumentumban, sem kódban.
- **Hatás:** a brief §5 Döntés 7 ("Mindkét új flag default OFF, és flag OFF esetén az adapter NEM példányosul") és a §6 "Flag-kapu" acceptance criterion NEM teljesül a négy adapter egyikére. Jelenleg ez ártalmatlan, mert semmi nem hívja a `credit()`-et (nincs bekötés az `analysis_controller.dart`-ba — az nincs is az `allowed_paths`-on), de a védelmi réteg maga hiányzik: ha egy jövőbeli kör vaktában bekötné, nincs flag, ami megállítaná.
- **Kötelező javítás:** adj a `ProgressEvidenceAdapter`-hez ugyanazt a factory+flag-provider mintát, mint a másik háromnak, és rendeld egyértelműen az egyik (vagy egy új, de az ADR 0176/0132 hatáskörén belüli) flaghez — a `analysisPracticeIntegrationEnabled` tűnik a logikusabb választásnak, mivel a Progress evidence az elemzés→gyakorlás-visszacsatolás láncba tartozik.
- **Ellenőrzés:** egy `_CountingProgressFactory`-alapú teszt, ami bizonyítja, hogy flag OFF mellett a factory `create()`-je nulla hívást kap, ugyanúgy, ahogy a Practice/Tutor teszt (`practice_analysis_adapter_test.dart:101-121`) teszi.
- **Státusz:** OPEN

### F3 — MAJOR — `SongAnalysisAdapter` akkord-transzponáló ága (displayChord) teljesen tesztelet­len — az OD-01 saját "teljes teszteléssel" kikötése sérül

- **Fájl:** `lib/features/audio_analysis/application/adapters/song_analysis_adapter.dart:125-138`; teszt: `test/features/audio_analysis/application/song_analysis_adapter_test.dart` (csak `displayMidi`-t tesztel, `displayChord`-ot sosem)
- **Probléma:** a brief §5.1 OD-01 explicit előírja: "Ebben a körben az adapter a snapshotból → AnalysisTarget irányt szállítja, **teljes teszteléssel**." A `SongReferenceEvent.displayChord` ágat (transzponálás `Chord(...).transposed(...)`-tal, kétszer egymás után: transposition majd capo) **egyetlen teszt sem hívja meg** — a fixture (`_snapshot()`, sor 45-66) mindig `displayMidi`-t ad, `displayChord`-ot sosem. A saját kézi újraszámolásom szerint a képlet (`display = Chord(displayChord).transposed(transposition)`, `concert = Chord(display).transposed(capo)`) matematikailag konzisztens a MIDI-ággal és a meglévő `Chord.transposed` dokumentált szemantikájával (`core/music/chord.dart:13-16`) — tehát NEM találtam benne konkrét hibát —, de ez a kód olvasásából, nem tesztből derül ki, ami pont az, amit a review-protokoll (és az OD-01 saját szövege) kizár.
- **Emellett egy valódi aszimmetria:** a `display` (transzponált, de capo előtti) akkord-értéket a kód kiszámolja, majd **eldobja** — az `expectedChords`-ba csak a `concert` kerül, és a `SongAnalysisTarget`-nek nincs olyan mezője (a MIDI-ág `pitches: List<SongPitchContext>`-jének megfelelője), ami ezt megőrizné. A brief §5 Döntés 6 "a megjelenítés display pitch-ben marad **külön mezőben**" — ez a MIDI-ágra bizonyítottan igaz (`SongPitchContext`), az akkord-ágra nem.
- **Hatás:** egy jövőbeli Song-oldali kör, ami akkord-alapú dalokat köt be, tesztelet­len kódra és egy hiányzó display-akkord mezőre építene.
- **Kötelező javítás:** írj legalább egy, a MIDI-mátrixhoz hasonló cellasort a `displayChord` ágra (pl. C-dúr / kereszt-módosítós gyök / bemol-módosítós gyök × transzpozíció/capo kombináció), és dönts (dokumentáltan) arról, hogy a transzponált display-akkord értékét megőrzi-e egy `SongAnalysisTarget`-mező, vagy expliciten indokolja a §10, miért elég a hívónak a nyers `event.displayChord`.
- **Ellenőrzés:** az új teszt zöld, és lefedi legalább a hat MIDI-cellával szimmetrikus akkord-esetet.
- **Státusz:** OPEN

### F4 — MAJOR — `songAnalysisAdapterProvider` flag-kapuja helyes, de nincs hívásszámláló teszt rá

- **Fájl:** `lib/features/audio_analysis/application/adapters/song_analysis_adapter.dart:196-201`; a meglévő hívásszámláló teszt (`practice_analysis_adapter_test.dart:101-121`) csak `_CountingPracticeFactory`-t és `_CountingTutorFactory`-t használ, Song-ot nem.
- **Probléma:** kód-olvasással a `songAnalysisAdapterProvider` helyesen `analysisPracticeIntegrationEnabled`-re kapuz — de a brief §6 "Flag-kapu... hívásszámláló" kritériuma egyik meglévő tesztben sincs a Song providerre végrehajtva.
- **Hatás:** alacsonyabb kockázatú, mint F2 (a mechanizmus létezik és helyesnek tűnik), de a review-elv szerint ("a zöld gate nem bizonyíték... a review MÉR") egy bizonyítatlan viselkedés nem tekinthető ellenőrzöttnek.
- **Kötelező javítás:** bővítsd az `OFF integration flags do not instantiate…` tesztet (vagy adj hozzá egy párját a `song_analysis_adapter_test.dart`-ba) egy `_CountingSongFactory`-val.
- **Státusz:** OPEN

### F5 — MINOR — A Practice-oldali teszt a `practice` feature belső domain-fájlját importálja a `public.dart` helyett

- **Fájl:** `test/features/audio_analysis/application/practice_analysis_adapter_test.dart:10`
- **Probléma:** `import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';` — közvetlen import a Practice belsejébe, hogy a teszt kézzel felépíthessen egy `CompiledPracticeTarget`-et. A határ-őr (`analysis_cross_feature_boundary_test.dart`) ezt NEM kapja el, mert csak a `lib/features/audio_analysis/**`-t szkenneli, a `test/`-et nem — tehát ez formálisan nem sérti a mért kontraktust, de a szándékot igen: a `practice/public.dart` már exportálja a `compilePracticeTarget()` publikus factory-függvényt (`practice/public.dart:82-83`), amivel a teszt egy VALÓDI, a compiler invariánsait (pl. rendezett `expectedChordSegments`) ténylegesen kielégítő fixture-t kapna, kézzel-gyártott (esetleg a valós invariánsokat nem tükröző) helyett.
- **Kötelező javítás (opcionális, nem blokkoló):** fontolják meg a fixture-t a publikus `compilePracticeTarget()`-en át építeni.
- **Státusz:** OPEN (follow-up, nem blokkolja a merge-et)

### F6 — NOTE — Felesleges enum-kerülőút a `direction` átvitelénél

- **Fájl:** `lib/features/audio_analysis/application/adapters/practice_analysis_adapter.dart:81-84`
- **Megfigyelés:** `direction: event.direction == null ? null : StrumDirection.values.byName(event.direction!.name)` — mivel `event.direction` már a **core**-megosztott `StrumDirection` (nem practice-belső) típus (ugyanaz, amit az `ExpectedEvent.direction` vár), a `.name`→`.byName()` oda-vissza konverzió felesleges; `direction: event.direction` közvetlenül is működne. Ártalmatlan, csak olvashatósági megjegyzés.
- **Státusz:** OPEN (nem blokkoló)

## Valódi-sértés próba (saját, független)

Az implementer §10-ben dokumentált próbáját **függetlenül megismételtem** az
izolált `/tmp/review-e06-r26` klónban: a `TutorAnalysisSnapshot.toJson()`-ba
ideiglenesen visszaírtam egy `'fileName': 'REVIEW_PROBE_VIOLATION.wav'`
bejegyzést → `flutter test
test/features/audio_analysis/application/tutor_analysis_snapshot_test.dart`
**PIROSRA váltott** (`Expected: not contains '"fileName"'`) → a sort
eltávolítottam → a teszt **újra zöld** (`git diff --stat` a klónban üres,
nincs maradék módosítás). A redakciós guard valódi tartalmi sértést fog meg,
nem csak formálisat.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer) | Ellenőrizve (saját, izolált `/tmp/review-e06-r26`) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld | ✅ zöld |
| test `test/features/audio_analysis` | 533 | ✅ zöld (533) |
| test `test/tooling` | 64 | ✅ zöld (64) |
| test `test/app` | 73 | ✅ zöld (73) |
| architecture | zöld, 12 allowlist | ✅ zöld, "12 allowlisted deviation(s)" |
| secrets | — | ✅ zöld (2436 fájl, 0 lelet) |
| l10n | — | ✅ zöld (1263 üzenet) |
| `gate_shape=VIOLATION` jelzés | — | ❌ **hamis pozitív** — az egyetlen regex-találat `docs/LESSONS.md` L245 saját szövege volt (a naplóban az implementer a kötelező lecke-előolvasás során olvasta be a fájlt), nem egy csonkított `round-gate.sh`-hívás. Négy tényleges gate-futás a naplóban mind csonkítás/láncolás nélküli. |
| CI (teljes suite + property + APK) | — | Még nem futott — a merge előtti kötelező lépés, a javító kör után |

## Merge-döntés

**Merge TILOS amíg nyitva van BLOCKER/MAJOR** (ADR 0052) — jelenleg 4 nyitott
MAJOR (F1-F4). Javasolt út: **javító kör ugyanazzal a motorral (Terra)**,
findings-lista F1-F4 (F5/F6 opcionális). A javító kör után a gate-et és a
négy célzott próbát (retry-tempo 4. cella, Progress hívásszámláló, Song
hívásszámláló, Song akkord-mátrix) újra saját, izolált klónban futtatom,
majd a jelentést frissítem.
