# ADR 0535 — A dalszerkesztő akkord-meghallgatása és a menet-előnézet (komponálás füllel)

**Státusz:** elfogadva (2026-09-09, E18-R01 — Chapter 18 „Komponálás és akkordok hangból", Kör 1)

**Kör:** `E18-R01` · **Brief:** [`docs/rounds/e18-r01-song-editor-chord-audition.md`](../rounds/e18-r01-song-editor-chord-audition.md)

Kapcsolódik: [ADR 0284](0284-import-preview-is-not-a-commit.md) (az előnézet nem
commit), [ADR 0056](0056-exclusive-microphone-session.md) (egy mikrofon-tulajdonos),
RAG chunk [014](../rag/chunks/014-play-along-learn.md) (Learn jam-mode pad),
[ADR 0536](0536-chords-from-audio-source-boundary.md) (a fejezet másik fele:
akkordok hangból, a YouTube-határ).

## Kontextus

A felhasználó kérése (2026-09-09): *„a hangok lenyomásakor az az akkord hang
hallható, amit benyomott a felhasználó, tehát hallja is, milyen hangot nyomott
meg; lehet komponálni is így, mielőtt gitárral játszaná."*

Mérve (`main @ 1ae9e55`):

| Hely | Mai viselkedés |
|---|---|
| `lib/features/songs/screens/song_builder_screen.dart:160-185` | a menet-chipek (`InputChip`) CSAK törölhetők; az „Add a chord" `ActionChip`-ek némán bővítik a listát |
| `lib/features/song_trainer/presentation/widgets/song_event_editor.dart:56-71` | a V2 szerkesztő akkordmezője + „Add chord" — hang nincs |
| `lib/features/learn/audio/chord_audio.dart` | `ChordAudio.frequencies(label)` → C3 körüli **hármashangzat**, `padWav` → lágy szinusz-pad; `Backing` app-szintű, jam-módra (chunk 014) |
| `lib/features/chords/chord_shape.dart` | 34 fogás, húronkénti bund-számokkal (`-1` néma, `0` üres) — a diagram, amit a felhasználó LÁT |
| `lib/features/chords/screens/chord_library_screen.dart:36` | az akkordkönyvtár tap-to-hear a pad-ot játssza (kerek 90) |
| `lib/features/tuner/providers/reference_tone_provider.dart` | a route-hoz kötött, autodispose lejátszó mintája (E13-R19 A5: nem szólhat tovább a képernyő elhagyása után) |

A logikai hiány: a szerkesztő két különböző dolgot mutat és játszana. A diagram
egy KONKRÉT fogást ábrázol (C: x-3-2-0-1-0 → C3 E3 G3 C4 E4, öt húr), a pad
viszont egy absztrakt hármashangzatot (C3 E3 G3) szinuszból. Komponáláshoz az
kell, amit a gitár fog adni.

## Döntések

### D1 — A meghallgatás a FOGÁST játssza, pengetett húrokkal; a pad csak tartalék

`SynthChordAudition.resolve(label)` sorrendje:

1. `ChordShapes.forLabel(label)` → `ChordVoicing.frequencies(frets)` (minden
   megszólaló húr, mély→magas, `AuditionSource.fingering`);
2. nincs diagram → `ChordAudio.frequencies(label)` (akkordhangok C3 körül,
   `AuditionSource.chordTones`);
3. nem értelmezhető címke → `AuditionSource.none`, **nem szól semmi** (nem
   találgatunk).

A szintézis Karplus–Strong pengetett húr (`lib/core/audio/synth/plucked_string_synth.dart`):
zajlöket egy `sr/f` hosszú késleltető hurokban, kéttagú átlagoló szűrővel —
fényes attack, sötétedő lecsengés, azaz gitárszerű. A gerjesztés
**fix-seedes LCG**, sosem `Random`: azonos kérés → bájtra azonos PCM
(cache-kulcs, teszt, golden). A pengetés húronként `18 ms`-os eltolással
söpör: **le-pengetés mély→magas, fel-pengetés magas→mély** — ez a
`PluckedStringSynth.strumOnsets` egység-tesztelt szerződése, és ugyanaz a
↓/↑ jelentés, amit az app a detektorban használ.

*Miért nem a meglévő `Backing.playChord`:* a pad szándékosan „ül a játékos
alatt" jam-módban; a komponáló viszont azt akarja hallani, amit majd fogni fog.
A két használat különböző hang, különböző életciklus — nem egy osztály két
kapcsolója.

### D2 — Egy lejátszó képernyőnként, a route-hoz kötve; `watch`, nem `read`

`chordAuditionProvider` = `Provider.autoDispose<ChordAudition>`, a képernyő
`build`-jében **watch**-olva. Így a route elhagyása elengedi az utolsó
listenert, Riverpod lebontja a lejátszót, és semmi nem cseng tovább a
következő képernyőn (a tuner referencia-hang A5 szerződése). Tap-callbackből
`ref.read` egy autodispose providerre létrehozná és azonnal el is dobná —
ezért TILOS. Az `AudioPlayer` lustán, az első pengetéskor jön létre (a
konstruktora platform-csatornát érint; teszt/golden nem érheti el).

Mikrofon-lease NINCS: a meghallgatás kizárólag lejátszás, az
`AudioSessionCoordinator`-t nem érinti (ADR 0056 határa érintetlen).

### D3 — A menet-előnézet TISZTA ütemezés + egy időzítő-lánc

`previewSchedule(chords, pattern, bpm, beatsPerBar)` tiszta függvény: nyolcad-
rács, `null` = szünet, egy akkord ütemenként; a nem illeszkedő mintát a
`Song.fromJson` módján illeszti (csonkol / szünettel pótol), sosem folyik át
a következő ütembe. `SongPreviewController` (`ChangeNotifier`) csak az
órát birtokolja: `Timer`-lánc a következő pengetésig, `currentBar` a
megszólaló ütemhez (a chip kiemeléséhez), `stop()` idempotens, `dispose()`
elhallgattat. **Bármely szerkezeti szerkesztés (akkord, minta, metrum, tempó)
leállítja a futó előnézetet** — elavult ütemterv helyett csend.

Az előnézet NEM lecke-futás: nincs pontozás, nincs streak, nincs mikrofon.
A „játszd el gitárral" út továbbra is a `LearnScreen` (chunk 014).

### D4 — Mindkét szerkesztő ugyanazt a kontraktust fogyasztja

A legacy `SongBuilderScreen` (chip-tap = hallás; add-chip = hozzáad ÉS hall;
`Preview` transport) és a V2 `SongEditorScreen` (`onAddChord` hallat; külön
„Hear chord" gomb a mezőhöz) egyaránt a `learn/public.dart` felületén
exportált `ChordAudition`-t használja. A `song_trainer` → `learn` él ÚJ, a
meglévő szabály szerint kizárólag `public.dart`-ra mutat.

### D5 — Az akkordkönyvtár tap-to-hear NEM változik ebben a körben

A `chord_library_screen.dart:36` marad a `Backing.playChord`-on. Átállítása a
fogás-hangra következetes lenne, de más képernyő, más teszt-lefedés — külön
kör (follow-up a fejezet-tervben), nem „mellékes" refaktor (AGENTS §4).

## Következmények

- Új: `lib/core/audio/synth/plucked_string_synth.dart`,
  `lib/core/music/chord_voicing.dart` (core, tiszta Dart),
  `lib/features/learn/audio/chord_audition.dart`,
  `lib/features/learn/providers/chord_audition_provider.dart`,
  `lib/features/songs/application/song_preview_player.dart`.
- Öt ARB-kulcs (`songChordHear`, `songPreviewPlay`, `songPreviewStop`,
  `songPreviewHint`, `songEditorHearChord`) a FORRÁS szegmensben, az
  aggregátum generálva (ADR 0307 §4).
- Memória: legfeljebb 24 gyorsítótárazott pengetés × ~140 KB (1,6 s @ 44,1 kHz)
  — a `Backing` korlátjának mintája.
- Nem változik: detektor-DSP, `ChordAudio`/`Backing`, a Learn jam-mód, a
  mikrofon-tulajdonlás.

## Elvetett alternatívák

- **Pad átkapcsolása fogásra a `Backing`-ben.** A jam-mód hangját is
  megváltoztatná, és az app-szintű életciklus miatt a képernyő elhagyása után
  is szólna.
- **MIDI/SoundFont lejátszó plugin.** Több MB asset, licence-kérdés, plusz
  plugin a win32-major-fegyelem mellé — a tiszta Dart szintézis 0 assettel
  adja a gitárszerű hangot.
- **Előnézet = `LearnScreen` jam-módban.** A komponáló nem akar leckét
  indítani (count-in, highway, mikrofon-kérés) egy akkordcsere meghallgatásához.
