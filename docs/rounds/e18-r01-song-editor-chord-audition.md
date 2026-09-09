# E18-R01 — A dalszerkesztő akkord-meghallgatása és menet-előnézet (komponálás füllel)

- **Státusz:** IN REVIEW (implementálva 2026-09-09, remote Claude-session, kód olvasva: `main @ 1ae9e55`) — **kivétel az ADR 0055 szereposztás alól:** a user explicit utasítására („tervezd meg és fejlesszük át") a tervező session maga implementált; a review + CI-kapu változatlan (ADR 0052).
- **Típus:** Chapter 18 (Komponálás és akkordok hangból), Kör 1
- **Kör-azonosító:** `E18-R01`
- **Branch:** `claude/song-editor-chord-audio-tbkokz`
- **Brief szerzője:** Claude (Fable 5.1) · **Implementáció:** ugyanez a session (tesztek: Sonnet-ágens, review: Opus-ágens — user-döntés 2026-09-09, token-takarékosság)
- **Előre kiosztott ADR:** [`0535`](../adr/0535-song-editor-chord-audition-and-progression-preview.md) — megírva.
- **Fejezet-terv:** [`docs/plans/chapter-18-composer-and-chords-from-audio.md`](../plans/chapter-18-composer-and-chords-from-audio.md)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "dalszerkesztő akkord meghallgatás hang lejátszás előnézet"` → a saját ADR 0535-ön túl az [ADR 0274](../adr/0274-motion-driven-by-the-audio-clock.md) (a ritmus-animációt az audio óra hajtja, nem független időzítő) releváns: az előnézet ütem-kiemelése NEM külön időzítőről fut, hanem ugyanabból az eseményláncból, amelyik a pengetést indítja — egyetlen óra, drift nélkül. Releváns lecke nincs.

## 0.0 Pre-flight mérés (S11 / S15)

- **S11 — a kör NEM cserél le képernyőt.** A `SongBuilderScreen` és a `SongEditorScreen` típusa, route-ja és belépési pontja változatlan; a diff a képernyők BELSEJÉT bővíti (chip-callback, egy új sor, egy ikon-gomb). A briefen kívül élő pin-tesztek (`test/app/routing/app_router_test.dart`, `test/features/songs/import/editor_draft_test.dart`, `test/ui/goldens/e13_r24_screens_golden_test.dart`, `test/ui/goldens/e15_r13_full_variant_matrix_test.dart`, `test/core/screen_size_guard_test.dart`, `test/features/songs/song_tap_tempo_test.dart`) a `gate_tests`-en futnak, az `allowed_paths`-on NINCSENEK: ha bármelyik pirosra vált, az a kör lelete, nem a cella hibája.
- **S15 — a §2 a `main @ 1ae9e55` ÁLLAPOTÁT méri, az implementáció ELŐTT.** A lint által jelzett 14 módosult / 3 új fájl e kör saját diffje (ugyanebben a sessionben), nem időközben merge-elt idegen szerződés; a kör egyetlen döntési helye az ADR 0535.

### 0.0.1 Revíziók a review után (2026-09-09, `docs/reviews/e18-r01-review.md`)

- **R1 — scope-bővítés a TERVDOKUMENTUMOKRA (review F3).** A user ugyanebben a sessionben, explicit utasítással kérte a fejezet MÁSIK felének megtervezését is („szeretném, hogy lehessen internetről is dalokat behívni… nézz utána"). Az ADR 0536, a `chapter-18` fejezet-terv, az E18-R02…R04 briefek és a queue-soraik ezért ennek a branchnek a részei — tervezői kimenet, nem produkciós kód; a `lib/`/`test/` scope változatlan. Az `allowed_paths` fenti bővítése ezt mondja ki; a `pipeline-queue.tsv` sora `hold`, a pipeline nem dispatch-eli.
- **R2 — a V2 szerkesztő KÜLÖN „Hear chord" gombja elhalasztva (pixel-golden).** A `test/ui/goldens/e13_r24_screens_golden_test.dart` a `SongEditorScreen`-t 412×915-ön pixelre méri (`e13_r24_song_editor_compact*.png`), és a `SongEventEditor` gombsora a hajtás FELETT van; egy új gomb a goldent mozdítja, amit CSAK a user boxa tud újragenerálni (`flutter test --update-goldens`), a remote konténer nem. A V2-ben ezért a kör CSAK az `onAddChord` → hallás utat szállítja (ez pixelt nem mozdít); a „hallgasd meg újra" gomb az E18-R02 (a user boxán futó kör) tétele, golden-frissítéssel. **A9 cella ennek megfelelően:** `Add chord` → `strummed == ['Dm']` és PONTOSAN egy esemény a chord trackben.
- **R3 — A1 pontosítva (review F6):** a „nyitott E" cella a hat üres húr (`[0,0,0,0,0,0]` → `[40,45,50,55,59,64]`) ÉS az E-dúr fogás (`[0,2,2,1,0,0]` → `[40,47,52,56,59,64]`) — mindkettő mérve.
- **R4 — A4 szigorítva (review F8):** ismert alaphang + ISMERETLEN minőség-utótag (`Cdim`, `C5`, `Cm6`) → `none`, csend — a `ChordAudio.hasKnownQuality` additív statikus a `chord_audio.dart`-ban (allowed_paths bővítve ezzel az egy fájllal; a jam-pad viselkedése változatlan).
- **R5 — A5 kiegészítve (review F7):** a HIT frissíti a recency-t (`debugCacheKeys`), a FIFO-degradáció mérve piros.
- **R7 — CI-lelet, 2. futás (`a846e0c`, [34364726569](https://github.com/wolfcasaba/strumsight/actions/runs/34364726569)): 10270 zöld, 2 piros.** A CI-log 5000 soros plafonja mögött; a mért állapot alapján a `test/features/songs/song_flow_test.dart` két cellája, amelyek a builder akkord-chipjeit NYOMJÁK: a chip-tap mostantól a `chordAuditionProvider` szállított gyárát, azaz a VALÓDI `audioplayers` lejátszót éri el — egy widget-tesztben plugin nélkül. A repó egyetlen valódi-lejátszós precedense (`recorder_hardening_test.dart:50`) sima `test()`, nem `testWidgets()`, ezért ott a függő időzítő/plugin-hiba nem bukik. A javítás: a `song_flow_test` `_app()` helperje ugyanazt a fake-injektálást kapja, amit a chord-library, a tuner és a reel tesztje használ (`chordAuditionProvider.overrideWithValue`); a cellák állításai NEM változnak (nem gyengítés, ugyanaz a mérce, csend a hangszórón). A fájl felvéve az `allowed_paths`-ra.
- **R8 — CI-lelet, bisect-tel lokalizálva (a log 5000 soros plafonja mögött, 7 eldobható `claude/e18-diag-*` ágon mérve):** (a) **A7 valódi termékhibát fogott:** a `SongPreviewController` a menet végét KÉTSZER várta ki — az utolsó pengetés utáni időzítő már a teljes hosszig várt, majd a záró lépés még egyszer hozzáadta az utolsó ütem kicsengését, így a transport egy ütemmel tovább mutatott „szól"-t (a cella 5,7 s-nál `isPlaying == true`-t mért a 5,333 s-os menet végén). Javítás: a záró lépés azonnal `stop()`. (b) **ARB-metaadat-paritás:** a `@songChordHear` hu-metaadatából hiányzott a `description`, ez volt a fa EGYETLEN en/hu metaadat-eltérése — a `main + core/learn/songs-application` variáns zöld, minden ARB-t vivő variáns pontosan eggyel piros. Javítás: azonos metaadat mindkét forrás-szegmensben. A hét eldobható ág (`claude/e18-r01-diag`, `claude/e18-diag-{a1,a2,a3,b1,b2,b3}`) törlése a proxy-n át nem ment (`remote end hung up`) — a user boxáról törlendők, tartalmuk soha nem merge-elendő.
- **R6 — F4 (randomizált property-cella az új szintézisre) follow-up:** a `test/property/` nincs a kör listáján; az E18-R02 briefje veszi fel (`docs/plans/chapter-18-…md` follow-up tábla).

> ⚠ **A remote konténerben nincs Flutter SDK** ([`docs/execution/remote-container-environment.md`](../execution/remote-container-environment.md)): a §7 gate itt NEM futtatható. A kör bizonyítéka a CI (`full-gate.yml` + `router-ci.yml`) a push-olt HEAD-en, a §10-ben linkelve. Lokális gate a user boxán a merge előtt KÖTELEZŐ.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/core/audio/synth/plucked_string_synth.dart",
  "lib/core/music/chord_voicing.dart",
  "lib/core/music/music.dart",
  "lib/features/learn/audio/chord_audio.dart",
  "lib/features/learn/audio/chord_audition.dart",
  "lib/features/learn/providers/chord_audition_provider.dart",
  "lib/features/learn/public.dart",
  "lib/features/songs/application/song_preview_player.dart",
  "lib/features/songs/screens/song_builder_screen.dart",
  "lib/features/song_trainer/presentation/widgets/song_event_editor.dart",
  "lib/features/song_trainer/presentation/screens/song_editor_screen.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/core/audio/plucked_string_synth_test.dart",
  "test/core/music/chord_voicing_test.dart",
  "test/features/learn/chord_audition_test.dart",
  "test/features/songs/song_preview_player_test.dart",
  "test/features/songs/song_builder_audition_test.dart",
  "test/features/song_trainer/presentation/song_editor_audition_test.dart",
  "test/features/songs/song_flow_test.dart",
  "docs/adr/0535-song-editor-chord-audition-and-progression-preview.md",
  "docs/rounds/e18-r01-song-editor-chord-audition.md",
  "docs/rag/chunks/014-play-along-learn.md",
  "docs/reviews/e18-r01-review.md",
  "docs/adr/0536-chords-from-audio-source-boundary.md",
  "docs/plans/chapter-18-composer-and-chords-from-audio.md",
  "docs/rounds/e18-r02-recording-to-song-draft.md",
  "docs/rounds/e18-r03-listen-mode-external-source.md",
  "docs/rounds/e18-r04-local-audio-file-decoding.md",
  "docs/execution/pipeline-queue.tsv",
  "HANDOFF.md",
]
native_gate = false
gate_tests = [
  "test/core/audio/plucked_string_synth_test.dart",
  "test/core/music/chord_voicing_test.dart",
  "test/features/learn/",
  "test/features/songs/",
  "test/features/song_trainer/presentation/",
  "test/features/chords/",
  "test/features/tuner/",
  "test/core/architecture_dependency_test.dart",
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
  "test/ui/goldens/e13_r24_screens_golden_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/features/songs/import/editor_draft_test.dart",
  "test/tooling/placeholder_wiring_test.dart",
]
```

## 0. Kör-jelzés és STOP-protokoll

Scope-ütközés esetén a kimenet a brief-REVÍZIÓ, nem a scope önkényes tágítása.

## 1. Cél

A dalszerkesztőben minden megnyomott akkord **hallható** — nem egy absztrakt
hármashangzat, hanem a diagramon mutatott FOGÁS, lepengetve —, és a teljes
menet a szerzett ↓/↑ mintával, tempóban **előre meghallgatható**, hogy a
dal a gitár kézbevétele ELŐTT megkomponálható legyen.

## 2. Jelenlegi állapot — mért tények (`main @ 1ae9e55`)

- `song_builder_screen.dart:160-185`: a menet `InputChip`-jei csak
  `onDeleted`-et kapnak; az „Add a chord" `ActionChip`-ek `setState(() =>
  _chords.add(label))` — hang nélkül.
- `song_event_editor.dart:56-71` (V2): szöveges akkordmező + `Add chord`;
  hang nélkül. A `SongEditorScreen` `onAddChord`-ja
  (`song_editor_screen.dart:352`) a controllerbe ír, mást nem.
- `chord_audio.dart:49-63`: `ChordAudio.frequencies` C3 körüli akkordhangok
  (3–4 hang); `padWav` szinusz-pad; `Backing` app-szintű `Provider` (nem
  autodispose), jam-módra.
- `chord_shape.dart:30-80`: 34 fogás húronkénti bund-számmal — a hangzó
  hangmagasság (nyitott húr MIDI + bund) SEHOL nem származik belőle.
- `reference_tone_provider.dart:55-62`: a route-hoz kötött, autodispose
  lejátszó mintája (`watch` a `build`-ből; A5).
- Keresztfeature-gráf: `learn → chords/public.dart` és `chords →
  learn/public.dart` MÁR kölcsönös; `song_trainer` ma csak
  `settings/public.dart`-ot importál.

## 3. Scope

**Benne:**
- pengetett-húr szintézis (`core/audio/synth`), fogás → hangmagasság
  (`core/music/chord_voicing.dart`);
- `ChordAudition` kontraktus + `SynthChordAudition` + autodispose provider a
  `learn` feature-ben, `public.dart`-on exportálva;
- a legacy `SongBuilderScreen`: chip-tap = hallás, add-chip = hozzáad + hall,
  `Preview` transport a menet-előnézethez, a szóló ütem chip-kiemelése;
- a V2 `SongEditorScreen`: `onAddChord` hallat (a külön „Hear chord" gomb:
  §0.0.1 R2);
- három ARB-kulcs (`songChordHear`, `songPreviewPlay`, `songPreviewStop`;
  en/hu) a FORRÁS szegmensben + generált aggregátum.

**Kívül (ebben a körben TILOS):**
- az akkordkönyvtár tap-to-hear átállítása (ADR 0535 D5);
- `ChordAudio`/`Backing`/Learn jam-mód módosítása;
- detektor-DSP, mikrofon-lease, `lib/core/audio/{capture,dsp,lifecycle,pitch}`;
- hangból akkord-beolvasás (E18-R02…R04, ADR 0536).

## 4. Engedélyezett fájlok

Lásd az `ai-router` blokkot. **Tilos zóna:** `lib/core/audio/{capture,dsp,lifecycle,pitch}/`,
`lib/features/chords/`, `lib/features/live/`, `tools/round-gate.sh`, `.github/workflows/`.

## 5. Kötött architekturális döntések (ADR 0535)

D1 fogás-hang pengetve, pad tartalék, ismeretlen címke = csend · D2 route-hoz
kötött lejátszó, `watch` a `build`-ből, lusta `AudioPlayer`, mikrofon-lease
nélkül · D3 tiszta `previewSchedule` + időzítő-lánc, szerkesztés = stop ·
D4 mindkét szerkesztő ugyanazt a kontraktust fogyasztja · D5 könyvtár marad.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Milyen kamarahangon szóljon a meghallgatás (a tuner A4-beállítása, vagy fix 440)?
    blocking: false
    resolution_policy: use_default
    default: fix 440 Hz — a beállítás átvezetése follow-up (a settings-függés új keresztfeature-él lenne)
  - id: OD-02
    question: Loopoljon-e az előnézet a menet végén?
    blocking: false
    resolution_policy: use_default
    default: nem — egyszer végigjátszik, az utolsó ütem kicseng, majd stop; a loop a Learn/Practice dolga
```

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | `ChordVoicing.midiNotes([-1,3,2,0,1,0])` = `[48,52,55,60,64]`; hat üres húr = `[40,45,50,55,59,64]`; E-dúr fogás `[0,2,2,1,0,0]` = `[40,47,52,56,59,64]`; néma húr kimarad, 24 feletti bund néma | `test/core/music/chord_voicing_test.dart` |
| A2 | `strumOnsets` le-pengetésre szigorúan növekvő (0, 794, …), fel-pengetésre szigorúan csökkenő; le ≠ fel PCM ugyanarra a hangkészletre | `test/core/audio/plucked_string_synth_test.dart` |
| A3 | A szintézis determinisztikus (két hívás bájtra azonos), a csúcs = `amp`·32767 ±2 %, a 220 Hz-es húr AUTOKORRELÁCIÓS periódus-becslése 220 ±4 % (100–400 mintás lag-ablak, oktávhiba nem maszkolható; a nullátmenet-számlálás MÉRTEN 1158 Hz-et adott — review F1), az utolsó minta 0; érvényes RIFF/WAVE | ugyanott |
| A4 | `resolve('C')` → `fingering`, 5 hang, legmélyebb 130,81 Hz; diagram nélküli, de értelmezhető címke (`Ebm`) → `chordTones`; szemét (`Zz9`, ``) ÉS ismert alaphang ismeretlen utótaggal (`Cdim`, `C5`, `Cm6`) → `none` és **semmi nem szól** (a lejátszóhoz 0 hívás). **NEM elfogadható gyengítés:** ismeretlen címkére/utótagra dúr-hármas találgatása. | `test/features/learn/chord_audition_test.dart` |
| A5 | LRU-korlát: 24-nél több különböző (címke, irány) után `cacheSize == 24`; találat frissíti a recency-t (`debugCacheKeys` sorrend: a HIT után az elem a legújabb — FIFO-degradáció piros) | ugyanott |
| A6 | `previewSchedule` mátrix: {4/4 default minta @90} × {3/4 hatréses @120} × {bpm 0} × {üres menet} × {túl hosszú minta} × {túl rövid minta} — a származtatott `timeSec` cellák: 0 / 0,6667 / 1,3333 / 2,0 / 2,6667 ill. 0 / 0,25 / … / 1,25 / 1,5; a hosszú minta farka NEM folyik a következő ütembe | `test/features/songs/song_preview_player_test.dart` |
| A7 | `SongPreviewController`: start → azonnal pengeti az első akkordot, `currentBar == 0`; 2,7 s után `currentBar == 1` és a 2. akkord szólt; a menet végén `isPlaying == false`, `currentBar == null`, `stop` a lejátszón; `stop()` közben megszakít (több pengetés nincs); `dispose()` elhallgattat és nem notify-ol | ugyanott (widget-teszt, `tester.pump(Duration)`) |
| A8 | Builder: add-chip `C` → chip + `strummed == ['C']`; chip-tap → újra szól, a menet nem változik; törlés → nincs hang; a `song-preview-toggle` üres menetnél tiltott; előnézet közben a szóló ütem chipje `selected`; a route elhagyása → a lejátszó `dispose` | `test/features/songs/song_builder_audition_test.dart` |
| A9 | V2: `Add chord` → `strummed == ['Dm']` és PONTOSAN egy esemény a chord trackben (a külön „Hear chord" gomb: §0.0.1 R2, E18-R02) | `test/features/song_trainer/presentation/song_editor_audition_test.dart` |
| A10 | Az aggregált ARB-ok a generátorral bájtra egyeznek; az architektúra-teszt tiszta (új él csak `public.dart`-ra) | CI `check_l10n`, `test/core/architecture_dependency_test.dart` |

### 6.1 Falszifikációs próba

- A2: cseréld fel a `strumOnsets` irány-ágát → az A2 cellának PIROSNAK kell
  lennie.
- A4: engedd át az ismeretlen címkét dúr-hármasként → az A4 „0 hívás" cella
  piros.
- A8: cseréld a `watch`-ot `read`-re a builder `build`-jében → a „route
  elhagyása → dispose" cella viselkedése változik (a tuner A5 mintája).

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/audio/plucked_string_synth_test.dart test/core/music/chord_voicing_test.dart test/features/learn/ test/features/songs/ test/features/song_trainer/presentation/ test/features/chords/ test/features/tuner/ test/core/architecture_dependency_test.dart test/ui/goldens/e15_r13_full_variant_matrix_test.dart test/core/screen_size_guard_test.dart
```

## 8. Implementációs sorrend

1. core: szintézis + voicing (tiszta, tesztelve). 2. learn: kontraktus +
provider + export. 3. songs: ütemező + controller. 4. a két szerkesztő
bekötése. 5. ARB forrás + generált aggregátum. 6. tesztek (A1–A9).
7. CI-dispatch a HEAD-en; lokális gate a user boxán.

## 9. Kockázatok

- **Platform-csatorna tesztben.** Az `AudioPlayer` csak az első pengetéskor
  jön létre; a widget-tesztek a providert felülírják.
- **Elavult előnézet.** Szerkesztés közben futó előnézet rossz dalt játszana —
  ezért minden szerkezeti edit `stop()`.
- **Golden-mátrix.** A builder új sort kap (Preview) — az `e15_r13` mátrix
  strukturális (nincs `matchesGoldenFile`), de a textscale-cellák túlcsordulást
  mérhetnek; a CI mondja meg.

## 10. Implementation handoff

_(a session tölti ki a CI-eredménnyel)_

## 11. Review

_(Opus review-ágens jelentése: `docs/reviews/e18-r01-review.md`)_
