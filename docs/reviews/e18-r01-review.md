# E18-R01 — Review

Brief: `docs/rounds/e18-r01-song-editor-chord-audition.md` · ADR: [`0535`](../adr/0535-song-editor-chord-audition-and-progression-preview.md)
Branch: `claude/song-editor-chord-audio-tbkokz` · Base: `origin/main @ 1ae9e55`
HEAD a review pillanatában: `e3283bbcf9aa5b6cf0a0bc383a8db423ba5a7ec2`
(a produkciós + teszt diff utoljára `6a4a2be`-ben mozdult; a két legfelső commit már E18-R02/R03 tervdokumentum)
Diff: `git diff 1ae9e55...e3283bb`
Reviewer: Claude (Opus 5, review-ágens, READ-ONLY) · Dátum: 2026-09-09
**Verdikt: CHANGES REQUESTED** (1 BLOCKER, 2 MAJOR)

## Összegzés

BLOCKER: 1 · MAJOR: 2 · MINOR: 6 · NOTE: 5

A kör lényege jó: a Karplus–Strong rekurzió, a fogás→hangmagasság matematika, a
nyolcad-rácsos `previewSchedule`, az autodispose+`watch` életciklus és a
kétszerkesztős kontraktus mind helyes, és a mérhető részüket helyben
ellenőriztem. Két teszt viszont olyat állít, amit a kód mérhetően NEM ad
(F1: a nullátmenet-becslés 1158 Hz-et mér 220 helyett), és egy widget-teszt
függő `Timer`-rel ér véget (F2) — mindkettő a kör saját `gate_tests` cellája,
tehát a kapu ezekkel nem lehet zöld. A harmadik blokkoló szintű lelet
scope: a branch két további környi tervdokumentumot is visz (F3).

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | `midiNotes` C-fogás / néma húr / >24 bund | ✅ (eltéréssel) | `test/core/music/chord_voicing_test.dart:6-27`; a C-fogás `[48,52,55,60,64]` a `GuitarStrings.standard` (40/45/50/55/59/64) alapján kézzel újraszámolva helyes. A brief „nyitott E = `[40,45,50,55,59,64]`" cellája NINCS leállítva — helyette az E-dúr fogás `[0,2,2,1,0,0]` → `[40,47,52,56,59,64]` (lásd F6). |
| A2 | `strumOnsets` irány, le ≠ fel PCM | ✅ | `plucked_string_synth_test.dart:64-96`; `18 ms × 44100 / 1000 = 793,8 → 794` — a `[0,794,…,3970]` és a fordítottja pontosan a `strumOnsets` szerződése. |
| A3 | determinizmus, csúcs = `amp`·32767 ±2 %, 220 Hz ±4 %, RIFF/WAVE | ❌ | A pitch-cella mérhetően PIROS (F1). A többi része rendben: a csúcs konstrukcióból pontos (`gain = amp/peak`), a RIFF-offszetek a 44 bájtos `pcmToWav` fejlécből (`lib/core/audio/codec/wav_encoder.dart`) stimmelnek, `pcm.last == 0` a záró fade-ből következik. |
| A4 | `resolve('C')` fogás, 5 hang, 130,81 Hz; fallback; szemét → `none`, 0 hívás | ✅ (résrel) | `test/features/learn/chord_audition_test.dart:46-91`. A „nem találgatunk" azonban csak ISMERETLEN ALAPHANGRA igaz — ismeretlen minőség-utótagra a `ChordAudio` dúr-hármast tippel (F8). |
| A5 | LRU-korlát 24, találat frissíti a recency-t | ⚠️ félig | `chord_audition_test.dart:112-127` a korlátot méri; a recency-frissítést SEMMI nem méri (F7). |
| A6 | `previewSchedule` mátrix (6 cella) | ✅ | `test/features/songs/song_preview_player_test.dart:37-146`; a `timeSec = (bar*beatsPerBar + slot*0,5) * 60/bpm` képletből a 90 bpm-es 0 / 0,667 / 1,333 / 2,0 és a 120 bpm-es 0…1,25 sor kézzel ellenőrizve; a hosszú minta csonkul (`slot < pattern.length`), a rövid szünettel pótlódik. |
| A7 | `SongPreviewController` transport-szerződés | ⚠️ | A viselkedés a kódban helyes (stop idempotens, `dispose` után nincs notify), de az első cella függő időzítővel ér véget (F2). |
| A8 | Builder: add/tap/törlés/tiltott toggle/kiemelés/route-elhagyás | ✅ | `test/features/songs/song_builder_audition_test.dart`; a `watch`→`read` falszifikáció valóban megbuktatná a 153-185. sor autodispose-celláját. |
| A9 | V2: `Add chord` → 1 esemény + 1 pengetés; `Hear chord` → csak hang | ✅ | `test/features/song_trainer/presentation/song_editor_audition_test.dart:128-180`; ugyanaz az `enterText`+`tap` minta, ami a meglévő zöld `song_editor_screen_test.dart:65-67`-ben már bizonyított. |
| A10 | Aggregált ARB = generátor kimenete; architektúra tiszta | ✅ | **Helyben mérve:** a `tool/gen_l10n_segments.dart` merge-logikáját (alfabetikus rend, `@kulcs` a kulcs után, `@@locale` elöl, 2 szóközös JSON, záró `\n`) Pythonban újraimplementálva a lemezen lévő `lib/l10n/app_en.arb` és `app_hu.arb` **bájtra egyezik** (200 986 / 202 805 bájt, 0 hiba). Architektúra: a `song_trainer → learn/public.dart` és `songs → learn/public.dart` élek `public.dart`-ra mutatnak, tehát a `crossFeatureImportsMustUsePublicApi` szabály szerint nem is deviációk; `lib/core/music/chord_voicing.dart` framework-mentes (`_isSharedDomain` prefix). A `learn` feature-nek nincs `public/` fragmentuma, így a kézi barrel-szerkesztés nem tesz elavulttá generált barrelt. |

## Scope-audit

`python3 tools/scope-audit.py --repo /home/user/strumsight --brief docs/rounds/e18-r01-song-editor-chord-audition.md --base 1ae9e55` → **FAILED**, 29 út.

| Kategória | Utak |
|---|---|
| Engedélyezett és megváltozott | mind a 23 `allowed_paths` bejegyzés (17 `lib/` + `test/`, 3 docs) — 1:1 fedés, hiány nélkül |
| **Scope-on kívül, COMMITOLVA** | `docs/adr/0536-chords-from-audio-source-boundary.md`, `docs/plans/chapter-18-composer-and-chords-from-audio.md`, `docs/rounds/e18-r02-recording-to-song-draft.md`, `docs/rounds/e18-r03-listen-mode-external-source.md` |
| Scope-on kívül, még csak munkafában | `docs/execution/pipeline-queue.tsv` (**protected path**), `docs/rounds/e18-r04-local-audio-file-decoding.md` (untracked), az R02/R03 briefek további módosításai |

Tilos zóna (`lib/core/audio/{capture,dsp,lifecycle,pitch}/`, `lib/features/chords/`,
`lib/features/live/`, `tools/round-gate.sh`, `.github/workflows/`): **érintetlen** ✅.

## Megállapítások

### F1 — BLOCKER — A pitch-teszt mérhetően piros: a nullátmenet-becslés 1158 Hz, nem 220 Hz

- **Fájl:** `test/core/audio/plucked_string_synth_test.dart:41` (a becslő: `:9-15`)
- **Probléma:** a `_estimatedHz` a 0,2–1,0 s-os farokra nullátmenet-számlálást
  végez, és `closeTo(220, 8,8)`-at vár. A `PluckedStringSynth.pluck`
  aritmetikáját (fix `0x5EED` LCG, `period = round(44100/220) = 200`,
  `y[n] = 0,5·(y[n−N]+y[n−N−1])·decay`) bájthű Pythonban újrajátszva a
  teszt által számolt érték **1158,125 Hz**. Ok: a hurokszűrő
  csillapítása a k-adik felharmonikusra `cos(πk/N)` — k=3-ra ez 0,99889/periódus,
  vagyis a fehérzajos gerjesztés alsó felharmonikusai gyakorlatilag nem halnak
  el; 0,2 s-os ablakokban mérve a becslés 3280 → 1407 → 1097 → 660 Hz, és
  **2,5 s után is 660 Hz-en (3. felharmonikus) áll be** — SOSEM 220 közelében.
- **Hatás:** a kör saját `gate_tests` cellája piros → a §7 kapu és a CI
  `full-gate` nem lehet zöld; az A3 „220 ±4 %" állítás a jelentésben hamis zöld
  lenne.
- **Fontos:** a SZINTÉZIS jó — ugyanezen a jelen a normalizált autokorreláció a
  0,5–0,7 s ablakban `r(lag 200) = 0,997`, `r(lag 201) = 0,997`,
  `r(lag 150) = −0,02`, tehát a húr valóban 220 Hz-en (200,5 minta periódussal)
  cseng. Nem az implementációt kell átírni.
- **Kötelező javítás:** cseréld a becslőt a hangmagasságot ténylegesen mérő
  eljárásra — pl. „a normalizált autokorreláció a `round(sr/220)` lagon > 0,9,
  és egy nem-harmonikus lagon (150) < 0,3" —, VAGY a nullátmenet-számlálást egy
  aluláteresztett/érvényesített jelre alkalmazd. Küszöb-lazítás (a ±4 % ±500 %-ra
  tágítása) NEM elfogadható javítás.
- **Ellenőrzés:** `flutter test test/core/audio/plucked_string_synth_test.dart`
  a user boxán / CI-ban. A leletem SDK nélkül is reprodukálható:
  ugyanaz a ciklus Pythonban (`pluck(220, 1.0)` → a teszt saját `_estimatedHz`
  képlete → 1158,125).
- **Státusz:** OPEN

### F2 — MAJOR — A transport-teszt első cellája függő `Timer`-rel ér véget

- **Fájl:** `test/features/songs/song_preview_player_test.dart:150-167`
- **Probléma:** a `start(...)` a `_step`-ben azonnal ütemez egy `Timer`-t a
  következő pengetésre (667 ms), a teszttörzs viszont a három `expect` után
  véget ér; a takarítás csak `addTearDown(controller.dispose)`, ami a
  package:test tear-down fázisában, a flutter_test invariáns-ellenőrzése UTÁN
  fut. A repó saját, mért leckéje szerint (`docs/handoff-archive.md:5655`,
  102. kör) a függő időzítő „fails other tests' end-of-test invariants" —
  vagyis „A Timer is still pending even after the widget tree was disposed."
- **Hatás:** valószínűsíthetően piros cella (A7 első fele), és ha a tear-down
  sorrend mégis megmenti, akkor is szivárgó időzítőt hagy a következő tesztre.
- **Kötelező javítás:** a törzs végén explicit `controller.stop();` (vagy
  `controller.dispose()`), az `addTearDown` mellett is.
- **Ellenőrzés:** `flutter test test/features/songs/song_preview_player_test.dart`
  — a többi négy cella már ma is lezárja az időzítőláncot (stop / dispose /
  végigjátszás / üres menet), ez az egyetlen kivétel.
- **Státusz:** OPEN

### F3 — MAJOR — A branch két további kör tervdokumentumát is viszi (scope)

- **Fájl:** `docs/adr/0536-…md`, `docs/plans/chapter-18-…md`,
  `docs/rounds/e18-r02-…md`, `docs/rounds/e18-r03-…md` (commit `7dc3dae`, `e3283bb`);
  munkafában ezen felül `docs/execution/pipeline-queue.tsv` (protected) és egy
  untracked `e18-r04` brief.
- **Probléma:** az `ai-router.allowed_paths` 23 útja közül egyik sem ezek; a
  review-szabály szerint minden listán kívüli változás automatikusan legalább
  MAJOR, és a brief §0 STOP-protokollja kifejezetten azt írja, hogy
  scope-ütközéskor a kimenet a brief-REVÍZIÓ, nem a scope tágítása.
- **Hatás:** az E18-R01 merge egy még nem review-zott, más körökre vonatkozó
  döntéshalmazt (ADR 0536 + három brief) is beemelne `main`-be; a
  `pipeline-queue.tsv` protected path módosítása ráadásul a párhuzamos
  kör-ütemezés konfliktus-felülete.
- **Kötelező javítás:** válaszd le a `7dc3dae` és `e3283bb` commitokat külön
  branch/PR-re (a tervezési kör saját nyoma), VAGY írj brief-revíziót, amely az
  `allowed_paths`-t explicit indoklással kiterjeszti — a `pipeline-queue.tsv`-t
  a merge-rituálé, nem a kör diffje írja.
- **Ellenőrzés:** `python3 tools/scope-audit.py --repo … --base 1ae9e55` → OK.
- **Státusz:** OPEN

### F4 — MINOR — Az új DSP-hez nincs randomizált property-teszt

- **Fájl:** `test/property/` (hiányzó cella), `lib/core/audio/synth/plucked_string_synth.dart`
- **Probléma:** a `CLAUDE.md` HORIZON-szabálya kimondja: „New DSP behaviour ⇒ add
  a randomized property, not only fixed fixtures." A kör új szintézist ad, de
  csak fix fixtúrákat. A `test/property/` nincs az `allowed_paths`-on, tehát ezt
  a brief mulasztotta el (nem az implementáció).
- **Javasolt javítás:** brief-revízióval egy property-cella `PROPERTY_SEED`
  alapján, 80–1300 Hz közti véletlen frekvenciákra: `pcm.last == 0`,
  `peak == amp·32767 ±2 %`, kétszeri hívás bájtazonos, és az F1-ben javasolt
  autokorrelációs pitch-invariáns.
- **Státusz:** OPEN (follow-up is elfogadható)

### F5 — MINOR — A brief §10 „Implementation handoff" üres, CI-link nincs

- **Fájl:** `docs/rounds/e18-r01-song-editor-chord-audition.md:191-193`
- **Probléma:** a DoD gate-bizonyíték pontja (`docs/execution/09-review-report.md` §7)
  a CI-run linkjét kéri; a remote konténerben a kapu nem futtatható, ezért a
  CI-run az EGYETLEN bizonyíték — és az még nincs bejegyezve.
- **Javítás:** a `full-gate.yml` run URL-je + eredménye a §10-be, merge előtt.
- **Státusz:** OPEN

### F6 — MINOR — A1 acceptance-drift: a „nyitott E" cella helyett más eset került tesztbe

- **Fájl:** `test/core/music/chord_voicing_test.dart:13-19` vs. brief §6 A1
- **Probléma:** a brief `nyitott E = [40,45,50,55,59,64]` (hat üres húr) cellát ír
  elő; a teszt az E-dúr FOGÁST (`[0,2,2,1,0,0]` → `[40,47,52,56,59,64]`) méri.
  A csere tartalmilag jobb (valódi fogás, nem hat üres húr), de a brief cellája
  így nem teljesült szó szerint — a mérce és a teszt szétcsúszása pontosan az,
  amit az acceptance-tábla meg akar előzni.
- **Javítás:** vagy vedd fel a hat üres húr celláját is (egy sor), vagy javítsd a
  brief A1 szövegét az implementált cellára, indoklással.
- **Státusz:** OPEN

### F7 — MINOR — Az LRU recency-frissítése nincs mérve (A5 fele)

- **Fájl:** `lib/features/learn/audio/chord_audition.dart:143-150`,
  `test/features/learn/chord_audition_test.dart:112-127`
- **Probléma:** a `_cache.remove(key) ?? …` + újrabeszúrás mintája helyes, de a
  teszt csak a 24-es korlátot méri; ha valaki a `remove`-ot elhagyja (azaz a
  cache FIFO-vá válik), MINDEN teszt zöld marad. A `Backing` erre már bevezette
  a `debugCacheKeys` mérőfelületet (`chord_audio.dart:114-117`, 115. kör).
- **Javítás:** ugyanaz a `@visibleForTesting List<String> get debugCacheKeys`, és
  egy cella: A, B, …, majd A újrapengetése után A NEM eshet ki elsőként.
- **Státusz:** OPEN

### F8 — MINOR — Ismeretlen minőség-utótag dúr-hármasként szólal meg

- **Fájl:** `lib/features/learn/audio/chord_audition.dart:129-131` →
  `lib/features/learn/audio/chord_audio.dart:60` (`_quality[…] ?? const [0,4,7]`)
- **Probléma:** a D1 3. lépése szerint „nem értelmezhető címke → csend, nem
  találgatunk", de a fallback csak az ALAPHANGOT validálja: `Cdim`, `C5`, `Cm6`,
  `Cwhatever` mind C-dúr hármashangzatként szól. A V2 szerkesztő akkordmezője
  szabad szöveg, tehát ez felhasználóhoz eljutó, hallhatóan HAMIS visszajelzés a
  komponáláshoz. Az ADR D1 betűjét a kód követi (a fallback a `ChordAudio`-ra
  delegál), ezért nem BLOCKER — de a döntés szándékával ellentétes.
- **Javítás (a scope-on belül, `chord_audition.dart`-ban):** a `chordTones`-ágat
  csak ismert minőség-utótagra engedd (a `ChordAudio._quality` kulcsai),
  egyébként `AuditionSource.none`; plusz egy cella: `resolve('Cdim').source ==
  none`. Ha ez késői döntés, akkor a follow-up az ADR 0535 D1 pontosításával
  induljon.
- **Státusz:** OPEN

### F9 — MINOR — A preview-controller az ELSŐ build audition-példányához kötődik

- **Fájl:** `lib/features/songs/screens/song_builder_screen.dart:47-50, 84-85, 160-163`
- **Probléma:** `_preview ??= SongPreviewController(audition)` — ha a
  `chordAuditionProvider` valaha újraépül (invalidálás, override-csere,
  autodispose-újralétrehozás), a controller a RÉGI, már disposolt auditiont
  tartja, és az előnézet néma no-op lenne (a `catch (_)` elnyeli).
  Ma nincs ilyen újraépítési út (a provider függőségmentes), tehát nem hiba,
  csak törékeny kötés.
- **Javítás:** ha a `build`-ben kapott `audition` nem azonos a controlleréval,
  dobd el és építsd újra a controllert (`if (!identical(...)) { _preview?.dispose(); _preview = null; }`).
- **Státusz:** OPEN

## NOTE-ok

- **N1 — Szintézis a UI szálon.** Egy akkord ≈ 1,6 s × 44 100 Hz; a
  `strumPcm` belső iterációi: húronként `n − onset` (6 húr ≈ 411 000 iteráció,
  iterációnként ~6 lebegőpontos művelet) + 3 teljes végigfutás
  (fade/csúcs/kvantálás, ≈ 212 000) ≈ **0,6 M művelet és 141 KB allokáció
  pengetésenként**. AOT Dartban egy középkategóriás telefonon ez nagyságrendileg
  3–6 ms — egy 16,7 ms-os frame alatt, és a 24-es LRU miatt (címke, irány)
  páronként EGYSZER fizetjük meg. Izolátra vinni most nem indokolt; ha valaha
  jankot mérünk, az a legelső koppintás lesz gyenge eszközön. (Becslés
  művelet-számlálásból, nem eszközön mért érték.)
- **N2 — `catch (_)` blokkok.** `chord_audition.dart:75-78, 84-87, 93-96`: mind
  kommentált, „best-effort" indoklással, a `Backing._play` (`chord_audio.dart:141-144`)
  és a `RealReferenceTonePlayer` (`reference_tone_provider.dart:40-52`)
  precedensével azonos — az AGENTS §10 „üres catch" tilalmát NEM sértik, és a
  lenyelt hiba nem backend-írás, hanem lejátszás. Ugyanakkor eszközön egy
  audioplayers-hiba teljesen néma marad; egy `assert`/`debugPrint` debug módban
  olcsó javulás lenne.
- **N3 — Lejátszás-sorosítás.** A `play()` `await stop()` után indít, miközben a
  preview `unawaited`-del percenként ~180 strokeot tüzel; két egymásba futó hívás
  sorrendje elvileg `A.stop → B.stop → A.play → B.play` is lehet. A `Backing`
  ezért nem `await`-el, hanem `.ignore()`-ol. Gyakorlati kockázat kicsi
  (nyolcad = 333 ms @90), de eszközön érdemes figyelni.
- **N4 — Rebuild-szkópolás.** A `ListenableBuilder` helyesen szűkíti az
  újrarajzolást a chip-`Wrap`-re és a transport-sorra; egy ütemváltás így is
  újraépíti az összes chipet (N ≤ menet hossza) — elfogadható.
- **N5 — Golden/overflow.** A builder egy új sort (Preview + hint szöveg) kapott;
  a `e15_r13` textscale-mátrix és a `screen_size_guard` a `gate_tests`-en van,
  de itt nem futtatható — a CI mondja meg. A V2 `IconButton` `Wrap`-ben ül,
  ott túlcsordulás nem várható.

## Ami rendben van (nem dicséret, hanem ellenőrzött tények)

- **Karplus–Strong.** A gyűrűpuffer valóban a `y[n] = 0,5·(y[n−N]+y[n−N−1])·decay`
  rekurziót valósítja meg: az `i`-edik iterációban olvasott cella az `i−N`-edik
  iterációban íródott, `prev` pedig az `i−N−1`-edik kimenet — a `prev = cur`
  léptetés és a `(idx+1) % period` indexelés együtt pontosan ezt adja. A `decay`
  így PERIÓDUSONKÉNT hat (0,996^220 ≈ 0,41 egy másodperc alatt 220 Hz-en),
  vagyis a docstring „~1,5 s tail" állítása reális.
- **Pengetés-irány.** `(downstroke ? i : count-1-i) * step` — le: mély húr
  indul elsőnek, fel: magas; a detektor ↓/↑ jelentésével egyezik.
- **Normalizálás és fade.** `gain = amp/peak` (nulla csúcsra 0, nincs osztás
  nullával), a záró 30 ms-os fade szorzója `(n−1−i)/release`, ami az utolsó
  mintán PONTOSAN 0 — a `pcm.last == 0` állítás konstrukcióból igaz, és mivel a
  csúcskeresés a fade UTÁN fut, a normalizálást sem rontja el.
- **Riverpod 3.** `Provider.autoDispose` + `ref.onDispose` (a
  `referenceTonePlayerProvider` mintája), `ref.watch` a `build`-ből MINDKÉT
  szerkesztőben (`song_builder_screen.dart:160`, `song_editor_screen.dart:270`),
  callbackből sehol nincs `ref.read` az auditionre; `StateProvider` nincs;
  mikrofon-lease nincs (`AudioSessionCoordinator` érintetlen, ADR 0056 határa áll).
- **Életciklus.** Route-elhagyás: `State.dispose` → `_preview.dispose()` (timer
  cancel + `audition.stop()`), majd az utolsó listener elvesztésével a provider
  is lebontja az auditiont; `stop()` idempotens (`!_playing && _currentBar == null`
  → korai return), `dispose()` után `stop()` nem notify-ol (`if (!_disposed)`),
  a `_step` a `_disposed || !_playing` őrrel indul. Minden szerkezeti edit
  (`_edit`) leállítja a futó előnézetet — a D3 „elavult ütemterv helyett csend".
- **Ütemezés vége.** A záró `Timer(_delay(totalSec − schedule.last.timeSec), stop)`
  nem off-by-one: a `timeSec` maximuma `(chords.length−1)·beatsPerBar + beatsPerBar − 0,5`
  ütés, tehát mindig `totalSec` alatt van, a `_delay` pedig 0-ra vág.
- **i18n.** Öt kulcs mindkét lokálban, a FORRÁS `lib/l10n/base/`-ben, az
  aggregátum bájtra a generátoré (helyben újraszámolva); a `songChordHear`
  placeholder-metaadata mindkét nyelven ott van.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | — (két `style(E18-R01)` commit) | ⚪ nem futtatható itt |
| analyze | — | ⚪ nem futtatható itt |
| célzott tesztek | a brief §7 listája | ❌ F1 mérhetően piros, F2 valószínűsíthetően piros |
| architecture | tiszta | ✅ a szabályok kézi kiolvasásával (`tool/check_architecture.dart`) |
| l10n aggregátum | friss | ✅ helyben újragenerálva, bájtazonos |
| scope-audit | — | ❌ `tools/scope-audit.py` FAILED (F3) |
| CI (`full-gate.yml`) | — | ⏳ fut, a §10-be linkelendő |

## Mit nem tudtam mérni

- **`flutter analyze` és `flutter test` NEM futott.** Ezen a boxon nincs
  Flutter/Dart SDK (`docs/execution/remote-container-environment.md`; a `dart`
  MCP-szerver is `ENOENT`-tel esett el), a letöltést a proxy 403-mal tiltja.
  Minden teszt-lelet (F1, F2) OLVASÁSBÓL és a kód aritmetikájának független
  (Python) újrajátszásából származik, nem `flutter test` kimenetből —
  a végső bizonyíték a CI `full-gate.yml` futása a `e3283bb` HEAD-en.
- **Nem mértem:** a golden-mátrix és a `screen_size_guard` viselkedését az új
  builder-sorral; a widget-tesztek tényleges zöldjét (Flutter 3.44 finder- és
  invariáns-viselkedés: `BackButton`, `FilledButton.tonalIcon` mint
  `FilledButton`-altípus, `InputChip` törlés-ikon, autodispose-időzítés
  `pumpAndSettle` után — mindegyikre van repóbeli precedens, de futtatás nélkül
  ez érv, nem mérés); a szintézis valós eszközön mért idejét (N1 becslés
  művelet-számlálásból); és a hangzás minőségét, ami úgyis csak a felhasználó
  valódi gitáros APK-tesztjén dől el.

## Merge-döntés

ADR 0052 szerint minden kapu zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
Jelenleg **1 BLOCKER (F1) + 2 MAJOR (F2, F3) nyitott**, ezért a merge tilos.
Javító kör után elég a `test/core/audio/plucked_string_synth_test.dart`, a
`test/features/songs/song_preview_player_test.dart` és a scope újraellenőrzése,
plusz a CI-run linkje a brief §10-be.

## Javító kör #1 — az implementáló session válasza (2026-09-09, HEAD a §10-ben)

| Lelet | Státusz | Mi történt |
|---|---|---|
| F1 BLOCKER | **FIXED** | a becslő autokorrelációs lag-keresés (100–400 minta, oktávhiba nem maszkolható), `sr/lag` ±4 % — küszöb NEM lazult (`plucked_string_synth_test.dart`) |
| F2 MAJOR | **FIXED** | explicit `controller.stop()` a törzs végén (`song_preview_player_test.dart`) |
| F3 MAJOR | **RESOLVED — brief-revízió** (§0.0.1 R1): a tervdokumentumok a user explicit kérésének kimenetei; `allowed_paths` bővítve, queue-sor `hold` |
| F4 MINOR | OPEN → follow-up (E18-R02 brief, §0.0.1 R6) |
| F5 MINOR | **FIXED** a §10-ben (CI-run link) |
| F6 MINOR | **FIXED** — hat-üres-húr cella felvéve, brief A1 pontosítva |
| F7 MINOR | **FIXED** — `debugCacheKeys` + recency-cella |
| F8 MINOR | **FIXED** — `ChordAudio.hasKnownQuality` kapu, `Cdim/C5/Cm6/Cwhatever → none` cella; ADR 0535 D1 pontosítva |
| F9 MINOR | **FIXED** — `_previewFor` identity-ellenőrzés, újrakötés |
| — | **ÚJ (CI-lelet)** | a V2 „Hear chord" gomb elhalasztva: az `e13_r24_song_editor_*` pixel-golden a hajtás felett tartalmazza a gombsort, a remote konténer goldent nem tud regenerálni (§0.0.1 R2); az `onAddChord` → hallás út marad |

A javítások független újra-ellenőrzése (ADR 0055) a user boxán vagy egy
következő review-sessionben esedékes; a CI-run az egyetlen gépi bizonyíték.
