# Chapter 18 — Komponálás és akkordok hangból

- **Nyitva:** 2026-09-09, a felhasználó két kérésére:
  1. *„a hangok lenyomásakor az az akkord hang hallható, amit benyomott a
     felhasználó, tehát hallja is, milyen hangot nyomott meg; lehet komponálni
     is így, mielőtt gitárral játszaná"*;
  2. *„lehessen dalokat importálni az internetről, pl. YouTube-ról, és abból a
     zenéből kiolvasni az akkordokat — a Yousician így csinálja."*
- **Mért alap:** `main @ 1ae9e55` (a Chapter 17 R01 merge-e utáni állapot).
- **Terv szerzője:** Claude (Opus 5), orchesztrátor.
- **ADR-sáv:** `0535`–`0538`.

## 1. A két kérés egy fejezet

A két kérés ugyanannak a hiánynak a két oldala: **a dal ma csak úgy kerül a
StrumSightba, ha a felhasználó betűzi be**. Az egyik oldal a füllel való
komponálás (hallom, amit írok), a másik a meglévő zenéből való kiolvasás
(hallom, amit valaki más játszik).

### 1.1 A második kérés premisszája mérve téves

A Yousician **nem** olvas ki akkordot YouTube-ról: kiadóktól licencelt dalokhoz
ELŐRE elkészített chartokat szállít (a saját támogatása mondja ki, hogy a
hiányzó dal oka licenc, nem technika). Ami a kérés magját tényleg megadja, az a
Chord ai-féle **hallgatás-mód**: a telefon mikrofonja hallja a körülötte szóló
zenét (YouTube, Spotify, rádió), és az akkordok az **eszközön** futó modellből
jelennek meg. A Chordify ugyanezt szerveroldalon, YouTube-linkből csinálja — ez
az út a YouTube ToS-ébe és a saját SDD-nkbe (`docs/sdd/04-epic-03-song-trainer.md:256-268`)
ütközik.

A fejezet forrás-határát ezért külön ADR rögzíti:
[**ADR 0536** — Akkordok hangból: a forrás-határ (YouTube nélkül)](../adr/0536-chords-from-audio-source-boundary.md).

## 2. Mért jelenlegi állapot (`main @ 1ae9e55`)

| Amit a felhasználó akar | Ami MA van | Fájl (olvasva) |
|---|---|---|
| hallja, amit ír | az `E18-R01` szállítja (pengetett fogás + menet-előnézet) | [ADR 0535](../adr/0535-song-editor-chord-audition-and-progression-preview.md) |
| akkordok hangból | **megvan a motor**: chroma + Viterbi dekóder → `TimelineChord` szakaszok | `lib/features/analyze/engine/clip_analyzer.dart:198-225` |
| … importált hangból is | `AnalyzeController.analyzeImported(pcm, sampleRate)` létezik és tesztelt, de a `lib/` fában **NULLA hívója van** | `lib/features/analyze/providers/analyze_providers.dart:195-203`; `test/features/analyze/analyze_import_test.dart:28` |
| a felismerésből DAL legyen | az idővonalból ma **lecke** lesz, dal nem | `lib/features/learn/model/lesson.dart:374-402` (`Lessons.fromAnalyze`) |
| … és fordítva | dalból mesterséges `AnalyzeResult` MÁR készül (share-út) | `lib/features/songs/model/song.dart:70-95` (`Song.toAnalyzeResult`) |
| a gyenge szakasz gyengének látsszon | a legacy `TimelineChord` **nem hordoz konfidenciát**; a V2 `ChordSegment` igen | `lib/features/analyze/model/analyze_result.dart:17-43` vs. `lib/features/audio_analysis/domain/analysis_segment.dart:19-21,45-49` |
| saját hangfájl elemzése | a V2 dekóder-seam **csak WAV**-ot ismer | `lib/features/audio_analysis/data/input/wav_decoder_adapter.dart:16-26`, `data/input/audio_decoder_gateway.dart:6-8` |
| korlátos felvétel | a `ClipRecorder` puffere **korlátlanul nő** (ADR 0217 is ezt mérte) | `lib/features/analyze/engine/clip_recorder.dart:11-24` |
| egy mikrofon-tulajdonos | kizárólagos lease, második ownernek `audioSessionBusy` | `lib/core/audio/lifecycle/audio_session_coordinator.dart:34-55` |

### 2.1 Két mért csapda, amit a fejezet köreinek KI KELL kerülnie

1. **A néma mentés-vesztés.** A `SongBuilderScreen._save()`
   (`lib/features/songs/screens/song_builder_screen.dart:132-146`) `existing != null`
   esetén `SongsController.update`-et hív, az pedig ismeretlen id-re **némán
   nem csinál semmit** (`lib/features/songs/providers/songs_provider.dart:52-53`).
   Egy szintetikus vázlatot tehát TILOS `existing`-ként átadni: a felhasználó
   megnyomná a mentést, és semmi nem történne. (Ugyanaz a hibaosztály, amit a
   `CLAUDE.md` „cloud writes swallowed by try/catch" pontja és az
   [L606](../LESSONS.md#l606) mér: az üres/eldobott írás és a zöld kapu
   megkülönböztethetetlen.)
2. **A nem létező konfidencia.** Aki a legacy idővonalra „per-akkord
   konfidenciát" ír a briefbe, olyan mezőre hivatkozik, ami nincs
   (`analyze_result.dart:17-43`). A vázlat ütemenkénti bizonyítéka ezért
   **származtatott lefedettség**, és a felületen is annak nevezendő
   ([ADR 0536](../adr/0536-chords-from-audio-source-boundary.md) D3).

## 3. A fejezet körei

**A sorrend kötött:** minden kör az előző kimenetére épül, és mindegyik ugyanazt
a szabályt viszi tovább — *az előnézet nem véglegesítés*.

| Kör | Tárgy | ADR | Függ |
|---|---|---|---|
| `E18-R01` | **A dalszerkesztő akkord-meghallgatása és menet-előnézete** (komponálás füllel) — pengetett fogás a diagramból, transzport a teljes menetre | [`0535`](../adr/0535-song-editor-chord-audition-and-progression-preview.md) | — |
| `E18-R02` | **Felvételből dal-vázlat**: `AnalyzeResult` → ütemekre kvantált `Song`-vázlat, ütemenkénti lefedettséggel, a szerkesztőben megerősítésre | `0537` | R01 |
| `E18-R03` | **Hallgatás-mód külső forrásból**: a mikrofon hallja a szóló dalt (YouTube a telefonon, másik eszköz, rádió), korlátos klip, eszközön futó elemzés → R02 vázlat-útja; a link CSAK metaadat | [`0536`](../adr/0536-chords-from-audio-source-boundary.md) | R02 |
| `E18-R04` | **Helyi hangfájl dekódolása** (MP3/M4A/OGG) — kutató- és döntéskör a `FileAnalysisInput` dekóder-seamjéhez, spike-kal, production bekötés NÉLKÜL | `0538` | — (a döntése az R03 után köthető be) |

Az `E18-R01` ebben a sessionben szállított; a többi kör a
`docs/execution/pipeline-queue.tsv`-ben `hold`, a fenti függésekkel.

### 3.1 Mit ad a felhasználónak a lánc vége

A felhasználó lejátssza a dalt (bárhonnan), a StrumSight hallgatja, és a
felismert menet **szerkeszthető vázlatként** nyílik meg: a biztos ütemek
készen, a bizonytalanok megjelölve. Onnantól minden meglévő út él rá —
lecke (`Lessons.fromAnalyze`), gyakorlás, setlist, megosztás.

## 4. Kockázatok

- **A hallgatás-mód fizikai határa.** Hangszórón át, szobazajjal a felismerés
  gyengébb, mint közvetlen gitárjelnél. Ha a felület ezt elhallgatja, a
  §5 „gyenge confidence nem jelenhet meg biztos állításként" sérül.
  *Kezelés:* a vázlat ütemenkénti jelölése + a hallgatás-mód saját, őszinte
  másolatszövege; a pontosságot nem a gitár-út számaival hirdetjük.
- **A jogi határ csendes elmosódása.** Egy „csak közkincs dalra" kapcsoló, egy
  szerveroldali „csak a hangsáv" segéd, egy külső könyvtár tranzitív
  letöltő-függősége mind ugyanoda vezet. *Kezelés:* [ADR 0536](../adr/0536-chords-from-audio-source-boundary.md) D1
  kivétel nélküli, és a `test/app/offline_network_guard_test.dart` méri.
- **A vázlat véglegesítéssé válik.** A megerősítés előtti mentés kényelmesebb
  állapotkezelés — és pontosan az [ADR 0284](../adr/0284-import-preview-is-not-a-commit.md)
  által mért hibaosztály. *Kezelés:* minden kör acceptance-cellája méri, hogy a
  tár a megerősítésig VÁLTOZATLAN.
- **A mikrofon-ütközés.** A hallgatás-mód ugyanazt a mikrofont kéri, amit a
  Live/Tuner. *Kezelés:* kizárólagos lease, ŐSZINTE „foglalt" hiba — nem lopás
  ([ADR 0056](../adr/0056-exclusive-microphone-session.md)).
- **A dekóder-függőség súlya.** Egy ffmpeg-osztályú csomag megsokszorozhatja az
  APK méretét és licenc-kötelezettséget hoz. *Kezelés:* az `E18-R04` MÉRT
  döntés, nem ízlés — méret, licenc, karbantartottság, Flutter 3.44 / Dart 3.12
  kompatibilitás.

## 5. Amit a fejezet SZÁNDÉKOSAN nem tesz

- **Nem tölt le hangot semmilyen szolgáltatásból** — se kliensen, se a
  `backend/`-en (ADR 0536 D1, SDD §4.2).
- **Nem épít licencelt dalkatalógust** (Yousician-modell) — ez nem technikai
  kör.
- **Nem generál teljes tabulatúrát vagy húronkénti kottát** hangból (SDD §4.2).
- **Nem nyúl a felismerő DSP hangolásához.** A `clip_analyzer` / `ml_chord_decoder`
  paraméterei változatlanok (`AGENTS.md` §9); a fejezet az idővonal
  FELHASZNÁLÁSÁRÓL szól, nem az előállításáról.
- **Nem hoz rollout-döntést** a `songTrainerV2Enabled` és társai kapuiról.
- **Nem tesz új képernyőt a fába**, ha egy meglévő módja is elég: az új
  képernyő elmozdítja a `test/ui/ui_inventory_test.dart` egzakt leltárszámát és
  a `check_screen_reachability` mérését, ezért csak indokolt esetben, a
  megfelelő őrökkel együtt.
