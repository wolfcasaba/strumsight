# E18-R04 — Helyi hangfájl dekódolása: kutató- és döntéskör

- **Státusz:** PREPARED (előre megírva 2026-09-09, kód olvasva: `main @ 1ae9e55`) — **`hold`: döntéskör, a fejezet szállító köreit nem blokkolja, és őket sem várja meg**
- **Típus:** Chapter 18 (Komponálás és akkordok hangból), Kör 4 — **kutató/döntés (spike), production bekötés NÉLKÜL**
- **Kör-azonosító:** `E18-R04`
- **Branch:** `<motor>/e18-r04-local-audio-file-decoding`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0538` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset.
- **Fejezet-terv:** [`docs/plans/chapter-18-composer-and-chords-from-audio.md`](../plans/chapter-18-composer-and-chords-from-audio.md)

**Visszakeresett előzmény:** [ADR 0536](../adr/0536-chords-from-audio-source-boundary.md)
D2(b) (a támogatott fájl-forrás a felhasználó SAJÁT, helyi fájlja — a StrumSight
nem szerzi be), a `docs/research/epic-03-guitar-pro-feasibility.md` precedens
(feasibility-kör spike-kal, `docs/rounds/e03-r13-guitar-pro-feasibility.md`),
a `CLAUDE.md` mért build-igazsága: **EGY win32 major a fán**
(a `flutter_secure_storage` v10 pin oka), és
[L639](../LESSONS.md#l639) (a repo-szintű SPDX-mező NEM a tényleges licenc —
a grant szövegét kell elolvasni). A pre-flight futtassa a
`node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "audio dekóder platform csatorna licenc"`
parancsot, és frissítse a §2-t.

## 0.0 MIÉRT `hold`

A kör nem szállít production viselkedést, ezért nem sürgős; a `hold` azt jelzi,
hogy az orchestrátor akkor indítja, amikor a fejezet szállító sávja (R02/R03)
nem foglalja a fát. **Mi oldja fel:** orchestrátor-döntés — nincs kód-előfeltétele.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/research/chapter-18-local-audio-decoding.md",
  "docs/adr/0538-local-audio-decoding-choice.md",
  "tool/audio_decode_spike/pubspec.yaml",
  "tool/audio_decode_spike/bin/run_spike.dart",
  "tool/audio_decode_spike/lib/audio_decode_spike.dart",
  "tool/audio_decode_spike/test/audio_decode_spike_test.dart",
  "test/fixtures/audio_decode/README.md",
  "docs/rounds/e18-r04-local-audio-file-decoding.md",
]
native_gate = false
gate_tests = [
  "test/features/audio_analysis/data",
]
```

> A `gate_tests` csak `test/` alatti Dart útvonalat fogad, a kör diffjében
> viszont **nulla `lib/` sor** van. A választott cella a bemeneti-határ
> regressziója (`WavDecoderAdapter` + `AnalysisInputValidator`): ha a kör
> bármit elmozdítana a szállított dekóder-seamen, ez vált pirosra. A kör
> TÉNYLEGES mércéje a §6 döntési tábla és a spike saját tesztje — lásd §7.

## 0. Kör-jelzés és STOP-protokoll

Scope-ütközés esetén a kimenet a brief-REVÍZIÓ, nem a scope önkényes tágítása:
állítsd meg a kört (`stopped`), és írd le, melyik §-t kell módosítani.

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott futásnak számít.

## 1. Cél

**Mért döntés** arról, hogyan dekódoljunk MP3/M4A(AAC)/OGG fájlt az eszközön a
`FileAnalysisInput` útjához — ízlés helyett méret, licenc, karbantartottság és
kompatibilitás alapján. A kör kimenete **ADR 0538 + kutatási jegyzőkönyv +
futtatható spike**; production kód NEM születik.

## 2. Jelenlegi állapot — mért tények (`main @ 1ae9e55`)

- A V2 bemeneti határ egyetlen dekóder-seamje az `AudioDecoderGateway`
  (`lib/features/audio_analysis/data/input/audio_decoder_gateway.dart:6-8`):
  `AppResult<DecodedAudio> decode(FileAnalysisInput input)`.
- Az EGYETLEN szállított implementáció a `WavDecoderAdapter`
  (`lib/features/audio_analysis/data/input/wav_decoder_adapter.dart:16-26`) —
  RIFF-fejlécet ellenőriz, majd a legacy `WavDecoder`-t hívja. **MP3/M4A/OGG
  ma nem dekódolható.**
- A bemeneti korlátok verziózottak: `InputLimits.maxFileBytes = 64 MiB`,
  `maxDuration = 10 perc`, `minSampleRate = 8000`, `maxSampleRate = 192000`,
  `maxChannels = 2` (`data/input/input_limits.dart:9-15`).
- A PCM-oldali belépő létezik és tesztelt, de UI-ból ma elérhetetlen:
  `AnalyzeController.analyzeImported`
  (`lib/features/analyze/providers/analyze_providers.dart:195-203`),
  `test/features/analyze/analyze_import_test.dart:28`.
- A fájlválasztás platform-portja megvan: `FilePickerAdapter` /
  `PlatformFilePickerAdapter` a `file_selector: ^1.1.0`-ra
  (`lib/features/song_trainer/data/importers/file_picker_adapter.dart:9-40`,
  `pubspec.yaml:46`) — **kotta-kiterjesztésekre** szűrve (`:20-27`).
- A `pubspec.yaml` ma NEM tartalmaz audio-dekóder csomagot; az `audioplayers`
  lejátszó, nem dekóder (`pubspec.yaml:29`).

## 3. Scope

**Benne van:** a lehetőségek MÉRT összehasonlítása · egy futtatható spike, ami a
választott (és legalább egy elvetett) úton ténylegesen dekódol egy helyi fájlt
PCM-re · a döntés ADR-be írása · a bekötés VÁZLATA (melyik seam, milyen
failure-kódok, milyen korlátok).

**NINCS benne (ebben a körben TILOS):**

- Bármilyen `lib/` módosítás — nincs production bekötés, nincs új adapter a fában.
- `pubspec.yaml` módosítás (a spike SAJÁT, különálló pubspecet visz a
  `tool/audio_decode_spike/` alatt — a fő fa függőségi gráfja nem mozdul).
- `android/` vagy `ios/` natív forrás módosítása.
- Szerzői joggal védett hangfájl commitolása fixture-ként.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `docs/research/chapter-18-local-audio-decoding.md` | a jegyzőkönyv: opciók × kritériumok, mért cellákkal |
| `docs/adr/0538-local-audio-decoding-choice.md` | a döntés |
| `tool/audio_decode_spike/**` (4 fájl) | különálló Dart csomag; a fő fa pubspecje érintetlen |
| `test/fixtures/audio_decode/README.md` | mit kell a HELYI (nem commitolt) próbafájlnak tartalmaznia |
| `docs/rounds/e18-r04-local-audio-file-decoding.md` | a brief saját státusz- és §0.0-revíziója |

**Tilos zóna:** `lib/**`, `pubspec.yaml`, `pubspec.lock`, `android/**`, `ios/**`.

## 5. Kötött döntések (a kör MENETÉRE, ADR 0538)

### D1 — Legalább három opció, azonos kritériumokkal

1. **Android `MediaCodec` + `MediaExtractor` platform-csatornán** (saját, vékony
   plugin a `lib/core/audio/` port mögé);
2. **létező pub.dev csomag** (a kör keresi meg a jelölteket, nem a brief nevezi meg);
3. **`ffmpeg_kit_flutter` vagy utódja**.

Kevesebb opcióval a döntés nem összehasonlítás, hanem racionalizálás.

### D2 — A kritériumok kötöttek, és MINDEN cella mért vagy kimondottan mérhetetlen

| Kritérium | Hogyan mérjük |
|---|---|
| release APK méret-delta | `flutter build apk --release` előtte/utána, a CI artefaktumból |
| licenc | a csomag SAJÁT `LICENSE` fájlja + a natív függőségek grantja — a repo-szintű SPDX-mező NEM elég ([L639](../LESSONS.md#l639)) |
| karbantartottság | utolsó kiadás dátuma, nyitott issue-k, ARCHIVÁLT-e a repo |
| kompatibilitás | Flutter 3.44 / Dart `^3.12.2`, AGP, `minSdk`; és **win32 major** — a fán CSAK EGY lehet (`CLAUDE.md`) |
| formátum-lefedettség | MP3, M4A/AAC, OGG/Vorbis, FLAC |
| platform-lefedettség | Android (kötelező), iOS (kívánatos), teszt-host (asztali `flutter test`) |
| a seamhez illeszkedés | `AppResult<DecodedAudio>`, szinkron vagy async, isolate-barát-e |

**A „mérhetetlen" cella is eredmény** — de KI KELL mondani, hogy miért az, nem
üresen hagyni.

### D3 — A spike VALÓDI fájlt dekódol, nem API-t szemlél

A `tool/audio_decode_spike/bin/run_spike.dart` egy megadott helyi fájlt olvas be,
és kiírja: minta-szám, mintavételi frekvencia, csatornaszám, futásidő, csúcs-
memória becslés. Egy „a dokumentáció szerint támogatja" mondat nem mérés.

### D4 — Szerzői joggal védett hangfájl NEM kerül a repóba

A próbafájlt a futtató adja meg útvonalként; a repóban csak a `README.md` áll,
ami leírja, milyen fájl kell (hossz, formátum, mintavételi frekvencia). Ez a
`AGENTS.md` §5 „nem commitolunk nagy datasetet / idegen tartalmat" szabálya és
az [ADR 0536](../adr/0536-chords-from-audio-source-boundary.md) D1 következménye
egyszerre.

### D5 — A kör NEM köt be semmit

Az ADR a bekötést a KÖVETKEZŐ körre írja elő (seam, failure-kódok, korlátok,
teszt-terv szintjén). Egy „amíg itt vagyok, be is kötöm" lépés a döntést és a
szállítást egy nem review-zható diffbe vonná.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Mi legyen, ha EGYIK opció sem fér bele az APK méret-korlátba?
    blocking: true
    resolution_policy: use_default
    default: >-
      az ADR kimondja, hogy a fájl-út WAV-on marad, és a hallgatás-mód
      (E18-R03) az elsődleges út — a „nincs jó opció" is döntés, nem halasztás.
  - id: OD-02
    question: A saját platform-csatornás megoldás hova kerülne a fában?
    blocking: false
    resolution_policy: use_default
    default: >-
      `lib/core/audio/codec/` port mögé, a `WavDecoderAdapter` mintájára —
      de ez a KÖVETKEZŐ kör dolga (D5), az ADR csak megnevezi.
  - id: OD-03
    question: iOS-támogatás hiánya kizáró ok-e?
    blocking: true
    resolution_policy: use_default
    default: >-
      NEM. A termék Android-first (`AGENTS.md` §1); az iOS-hiányt az ADR
      kockázatként rögzíti, nem elutasításként.
```

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A jegyzőkönyv MIND a három opcióra (D1) MINDEN kritériumot (D2) kitölt — mért értékkel vagy kimondott „nem mérhető + miért" cellával | `docs/research/chapter-18-local-audio-decoding.md` táblája |
| A2 | Minden licenc-cella a csomag SAJÁT grantjából idéz, nem a repo SPDX-mezőjéből | idézet + forrás-URL cellánként |
| A3 | A spike LEGALÁBB egy valódi helyi fájlt dekódol, és kiírja a minta-számot / frekvenciát / csatornaszámot | a `run_spike.dart` TÉNYLEGES kimenete a §10-ben |
| A4 | A méret-döntés a 6.1 küszöb-mátrix szerint dől el | az ADR döntési szakasza |
| A5 | A fő fa függőségi gráfja VÁLTOZATLAN: a diff nem érinti a `pubspec.yaml`/`pubspec.lock` fájlt, és a win32 major nem mozdul | `git diff --stat` + a §7 gate |
| A6 | Az ADR megnevezi a KÖVETKEZŐ kör bekötési seamjét, a failure-kódokat és a korlátokat | ADR 0538 |
| A7 | A repóba NEM kerül hangfájl | `git diff --stat` (nulla bináris) |

**NEM elfogadható gyengítés:**

- Az A1-et NEM elégíti ki két opció összehasonlítása („a harmadik nyilvánvalóan
  rossz") — a kizárás is MÉRT cella.
- Az A3-at NEM elégíti ki a dokumentáció idézése: a mérce a futtatott kimenet.
- Az A5-öt NEM elégíti ki „csak ideiglenesen vettem fel a csomagot": a fő
  pubspec ebben a körben nem módosulhat.
- Az A4-et NEM elégíti ki a küszöb utólagos megemelése azért, hogy a kedvenc
  opció beférjen — a küszöb a döntés ELŐTT rögzített.

### 6.1 Küszöb-mátrix — release APK méret-delta (költségvetés: **8,0 MB**)

| Mért delta | Elvárt besorolás | Mit mér |
|---|---|---|
| `7,9 MB` | ELFOGADHATÓ | szigorúan a küszöb **alatt** |
| `8,0 MB` | ELFOGADHATÓ (`<=`) | pontosan **rajta** — ez az egyetlen cella, ami a `<` és a `<=` közt különbséget tesz |
| `8,1 MB` | ELUTASÍTVA (kivétel: mért indoklás) | szigorúan a küszöb **fölött** |

### 6.2 Falszifikáció — a reviewer eldobható próbája (docs-only kör)

A kör nem szállít futtatható őrt, ezért a falszifikáció a reviewer próbája:
**melyik mondat/oszlop törlése teszi az adott acceptance-cellát bizonyíthatatlanná.**

| Acceptance | Ha ezt kivesszük, PIROS (bizonyíthatatlan) lesz |
|---|---|
| A1 | bármelyik opció-sor vagy kritérium-oszlop törlése |
| A2 | a licenc-cellák forrás-URL-jei |
| A3 | a `run_spike.dart` TÉNYLEGES kimenete a §10-ben (a „lefuttattam" mondat nem mérce) |
| A4 | a 6.1 mátrix „pontosan rajta" sora |
| A5 | a `git diff --stat` a handoffból |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis/data
```

A gate a `format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtatja. A spike saját csomagja külön fut:

```bash
dart test tool/audio_decode_spike
```

Az APK méret-mérés a CI-ban készül (a boxon nincs Android SDK — `CLAUDE.md`):

```bash
gh workflow run build-apk.yml --ref <kör-branch>
```

## 8. Implementációs sorrend

1. A §2 mért tényeinek ÚJRAMÉRÉSE.
2. Opció-lista és jelöltek összegyűjtése (D1), a kritérium-tábla váza (D2).
3. Licenc- és karbantartottság-cellák, forrás-URL-lel (A2).
4. A spike megírása és VALÓDI fájlon futtatása (D3, A3).
5. Méret-mérés a CI-ban, a 6.1 mátrix kitöltése.
6. ADR 0538: döntés + a következő kör bekötési vázlata (D5, A6).
7. `tools/round-gate.sh` csonkítatlan kimenettel.

## 9. Kockázatok

- **A licenc-csapda.** Egy LGPL/GPL natív bináris statikus linkelése a zárt
  APK-ban jogi kötelezettséget hoz; a repo-szintű SPDX-mező félrevezet
  ([L639](../LESSONS.md#l639)).
- **A halott csomag.** Az audio-dekóder csomagok karbantartása gyakran megszűnik
  (az `ffmpeg_kit` vonalról KÜLÖN ellenőrizd, él-e még a kiadási ága) — egy
  archivált függőség a következő AGP/Flutter-ugrásnál blokkoló.
- **A win32-ütközés.** Egy plugin, ami win32 ^5-öt húz be, a `flutter test`
  host-fordítását töri el a fán (`CLAUDE.md` mért igazsága) — ezt a kör a
  bekötés ELŐTT méri, nem utána.
- **A méret.** Egy teljes ffmpeg-build több tíz MB; a felhasználó egy offline
  gitáralkalmazást tölt le, nem médiakonvertert.
- **A scope-szivárgás.** A „már úgyis itt van" bekötés (D5 sérelme) a döntést
  és a szállítást egy diffbe vonná, és a review nem tudná szétválasztani.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
