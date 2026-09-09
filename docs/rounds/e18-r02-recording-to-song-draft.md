# E18-R02 — Felvételből dal-vázlat

- **Státusz:** PREPARED (előre megírva 2026-09-09, kód olvasva: `main @ 1ae9e55`) — **`hold`: az `E18-R01` szerkesztő-diffjére épül (a `SongBuilderScreen` ugyanazokat a sorokat mozgatja)**
- **Típus:** Chapter 18 (Komponálás és akkordok hangból), Kör 2
- **Kör-azonosító:** `E18-R02`
- **Branch:** `<motor>/e18-r02-recording-to-song-draft`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0537` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset.
- **Fejezet-terv:** [`docs/plans/chapter-18-composer-and-chords-from-audio.md`](../plans/chapter-18-composer-and-chords-from-audio.md)

**Visszakeresett előzmény:** [ADR 0284](../adr/0284-import-preview-is-not-a-commit.md) D1
(megerősítésig nincs tartós rekord), [ADR 0536](../adr/0536-chords-from-audio-source-boundary.md) D3
(a kimenet ELŐNÉZET, a gyenge szakasz gyengének látszik), [L606](../LESSONS.md#l606)
(üres forrás és zöld kapu megkülönböztethetetlen), [L637](../LESSONS.md#l637) (a
„küszöbön" cellát SZÁMOLNI kell). A pre-flight futtassa a
`node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "felvételből dal-vázlat kvantálás"`
parancsot, és frissítse a §2-t.

## 0.0 MIÉRT `hold`

Az `E18-R01` ([ADR 0535](../adr/0535-song-editor-chord-audition-and-progression-preview.md))
ugyanazt a `SongBuilderScreen`-t írja, amelynek ez a kör a konstruktorát és a
mentési ágát bővíti. **Mi oldja fel:** az `E18-R01` merge-e.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/songs/application/song_draft_from_analysis.dart",
  "lib/features/songs/screens/song_builder_screen.dart",
  "lib/features/songs/public.dart",
  "lib/features/analyze/screens/analyze_screen.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/songs/song_draft_from_analysis_test.dart",
  "test/features/analyze/analyze_to_song_draft_test.dart",
  "test/property/song_draft_quantisation_property_test.dart",
  "docs/adr/0537-recording-to-song-draft-quantisation.md",
  "docs/rounds/e18-r02-recording-to-song-draft.md",
]
native_gate = false
gate_tests = [
  "test/features/songs/",
  "test/features/analyze/",
  "test/property/song_draft_quantisation_property_test.dart",
  "test/l10n/arb_parity_test.dart",
]
```

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

A felvétel eredményéből **dal-vázlat** lesz: az `AnalyzeResult` akkord-idővonala
ütemekre kvantálva, ütemenkénti bizonyítékkal, és a vázlat a dalszerkesztőben
nyílik meg — **a felhasználó erősíti meg, addig semmi nem kerül tárba**. Ez az a
lépés, ami a felismerést a „nézd meg" állapotból a „legyen belőle az én dalom"
állapotba viszi, és ez adja az `E18-R03` hallgatás-módjának a kimeneti útját.

## 2. Jelenlegi állapot — mért tények (`main @ 1ae9e55`)

- Az `AnalyzeResult` (`lib/features/analyze/model/analyze_result.dart:113-166`)
  `chords` (`TimelineChord{label, startSec, endSec}`), `strums`, `bpm`,
  `beatsPerBar` mezőket hoz. **`TimelineChord`-on NINCS confidence**
  (`analyze_result.dart:17-43`) — konfidencia csak a V2 `ChordSegment`-en van
  (`lib/features/audio_analysis/domain/analysis_segment.dart:19-21,45-49`).
- Az eredményből ma **lecke** készül: `Lessons.fromAnalyze`
  (`lib/features/learn/model/lesson.dart:374-402`) — a `bpm <= 0` esetre
  `90.0`-t használ (`:375`), az ütemeket a `result.beatsPerBar`-ból számolja
  (`:392-394`). **Dal nem készül belőle.**
- A fordított irány MÁR él: `Song.toAnalyzeResult`
  (`lib/features/songs/model/song.dart:70-95`) ütemenként egy `TimelineChord`-ot
  gyárt — ez a kvantálás **inverze**, és a kör mércéje használhatja.
- Az Analyze eredmény-sávjában ma négy művelet van (megosztás, „gyakorold ezt",
  mentés, új felvétel): `lib/features/analyze/screens/analyze_screen.dart:331-393`.
- **A csapda:** a `SongBuilderScreen._save()`
  (`lib/features/songs/screens/song_builder_screen.dart:132-146`)
  `existing != null` ágon `SongsController.update`-et hív, az pedig ismeretlen
  id-re **némán no-op** (`lib/features/songs/providers/songs_provider.dart:52-53`).
- **A második csapda:** a `Song.fromJson` üres akkordcímkét ELUTASÍT
  (`requireStringList`, `lib/core/foundation/json_validation.dart:186-204`), tehát
  „üres ütem" nem perzisztálható.
- A `songs/public.dart` ma CSAK a modellt exportálja (`:9`); a `learn/public.dart:9`
  viszont MÁR exportál képernyőt — ez a kereszt-feature belépés szállított mintája.
- A `lib/l10n/app_{en,hu}.arb` **generált** aggregátum (`tool/gen_l10n_segments.dart`);
  az új kulcsok FORRÁSA a `lib/l10n/base/app_{en,hu}.arb`.

## 3. Scope

**Benne van:**

- Tiszta (Flutter-mentes, óra- és id-mentes) vázlatépítő függvény:
  `AnalyzeResult` → `SongDraft`.
- Ütem-kvantálás: ütemhossz a `bpm`/`beatsPerBar`-ból, ütemenként a legnagyobb
  átfedésű akkordcímke, és a **lefedettség** mint bizonyíték.
- A `SongBuilderScreen` vázlat-bemenete (prefill), ami a mentést **`add()`**-re
  köti, nem `update()`-re.
- Belépési pont az Analyze eredmény-sávjában („Legyen ebből dal").
- Az új felhasználói szövegek ARB-forrásban + a generált aggregátum frissítése.

**NINCS benne (ebben a körben TILOS):**

- Bármilyen DSP-paraméter, dekóder vagy `clip_analyzer` módosítás (`AGENTS.md` §9).
- A `SongDocument` V2 út (`song_trainer`) — ez a kör a **legacy `Song`** vázlatot
  szállítja; a V2 leképezés külön kör.
- Mikrofon, felvétel, hangforrás bármely érintése (az az `E18-R03`).
- Új képernyő a fába (a leltár- és elérhetőség-őrök mozdulnának).
- A `TimelineChord` bővítése konfidencia-mezővel.

## 4. Engedélyezett fájlok

Csak az `ai-router` blokk listája módosítható. Bármi más → MEGÁLLÁS és jelentés.

| Útvonal | Miért |
|---|---|
| `lib/features/songs/application/song_draft_from_analysis.dart` | ÚJ: a tiszta vázlatépítő + `SongDraft`/`DraftBar` típusok |
| `lib/features/songs/screens/song_builder_screen.dart` | vázlat-prefill és a `add()`-re kötött mentés |
| `lib/features/songs/public.dart` | additív export: a szerkesztő képernyő + a vázlat-típus |
| `lib/features/analyze/screens/analyze_screen.dart` | a belépési pont az eredmény-sávban |
| `lib/l10n/base/app_{en,hu}.arb` | az ÚJ kulcsok forrás-szegmense |
| `lib/l10n/app_{en,hu}.arb` | a `tool/gen_l10n_segments.dart` által GENERÁLT aggregátum — kézzel ne írd, regeneráld |
| `test/...` (3 fájl) | a kör saját mércéi |
| `docs/adr/0537-...` | a §5 döntéseinek rögzítése |

**Tilos zóna:** `lib/features/analyze/engine/**`, `lib/features/audio_analysis/**`,
`lib/core/audio/**`, `lib/features/song_trainer/**`, `lib/app/routing/**`.

## 5. Kötött architekturális döntések (ADR 0537)

### D1 — A vázlatépítő TISZTA függvény

Nincs benne `BuildContext`, `Ref`, óra, `Random`, id-generálás vagy I/O:
`SongDraft songDraftFromAnalysis(AnalyzeResult result, {required String name})`.
Az id-t a `SongsController.add` adja — a vázlatnak nincs identitása, mert nem
létező rekord ([ADR 0284](../adr/0284-import-preview-is-not-a-commit.md) D1).

### D2 — A kvantálás szerződése (kötött, sorrendben)

1. `bpm = result.bpm > 0 ? result.bpm : 90.0` — **ugyanaz a tartalék**, amit a
   `Lessons.fromAnalyze` használ (`lesson.dart:375`); két különböző tartalék két
   különböző dalt adna ugyanabból a felvételből.
2. `beatsPerBar = result.beatsPerBar`; `barSec = beatsPerBar * 60 / bpm`.
3. Origó: `t0 = chords.first.startSec` (üres idővonalra a vázlat ÜRES, lásd 5.4).
4. `barCount = min(maxSongBars, max(1, ceil((chords.last.endSec - t0) / barSec)))`
   — a `maxSongBars = 512` a `song.dart:10` szállított korlátja.
5. Ütemenként a győztes címke a **legnagyobb összes átfedés** az ütem-ablakkal;
   döntetlennél a KORÁBBAN kezdődő szakasz nyer (determinizmus).
6. `coverage = győztes átfedés / barSec` ∈ [0, 1].
7. **Átfedés nélküli ütem az ELŐZŐ ütem címkéjét tartja meg** (`coverage = 0`),
   mert üres címke nem perzisztálható (`json_validation.dart:186-204`), és mert
   a `clip_analyzer` maga is „sustain"-eli a no-chord kereteket
   (`clip_analyzer.dart:204-207`). Ha még nincs előző, az ELSŐ later címke jön.

### D3 — A bizonyíték neve LEFEDETTSÉG, nem konfidencia

A `DraftBar` mezője `coverage` + `source: DraftBarEvidenceSource.timelineCoverage`,
és a felhasználói szöveg sem mondja rá, hogy „konfidencia". A legacy
idővonalon **nincs** modell-konfidencia (§2), és egy származtatott arányt
konfidenciának nevezni pontosan az `AGENTS.md` §5 „gyenge confidence nem
jelenhet meg biztos állításként" tiltása ([ADR 0536](../adr/0536-chords-from-audio-source-boundary.md) D3).

`uncertain = coverage < 0.5` — a küszöbön lévő ütem MÉG biztos.

### D4 — A ritmus nem találgatás

A minta a `beatsPerBar * 2` nyolcad-slotból áll. Egy slot akkor foglalt, ha az
ütemek **SZIGORÚ többségében** volt rajta strum (`count > barCount / 2`,
egész-összehasonlítás — nincs lebegőpontos küszöb); az irány a slot gyakoribb
iránya, döntetlennél a slot LEGKORÁBBI strumjának iránya. **Ha az eredményben
nincs strum, a vázlat minta-listája ÜRES**, és a szerkesztő a saját
alapértelmezését tartja meg — a vázlat nem talál ki ritmust.

### D5 — A vázlat ÚJ dalként mentődik

A `SongBuilderScreen` a vázlatot **külön** paraméterként kapja (nem `existing`-ként),
és a mentés ezen az ágon `SongsController.add(...)`. Az `existing`-ág változatlan.
*Mért ok:* az `update()` ismeretlen id-re némán nem csinál semmit
(`songs_provider.dart:52-53`) — a felhasználó megnyomná a mentést, és a dala
elveszne.

### D6 — Kereszt-feature belépés a `public.dart`-on

Az `analyze_screen.dart` a `songs/public.dart`-ot importálja, nem a képernyő
fájlját (`AGENTS.md` §6) — a `learn/public.dart:9` szállított mintája szerint.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Hova kerüljön a vázlatépítő — a songs vagy az analyze feature alá?
    blocking: true
    resolution_policy: use_default
    default: >-
      songs/application/ — a songs MÁR függ az analyze public contractjától
      (song.dart:4 importálja az analyze/public.dart-ot), fordítva nem; a
      fordított irány új kereszt-feature függést teremtene.
  - id: OD-03
    question: Mi történjen, ha a felismert idővonal 512 ütemnél hosszabb?
    blocking: true
    resolution_policy: use_default
    default: >-
      csonkítás a maxSongBars korlátra (song.dart:10), és a szerkesztő
      LÁTHATÓAN jelzi a csonkítást — néma levágás nem elfogadható.
  - id: OD-04
    question: A gyenge ütem jelölése blokkolja-e a mentést?
    blocking: true
    resolution_policy: use_default
    default: >-
      NEM. A jelölés tájékoztat, nem tilt (ADR 0284 D3: figyelmeztetés ≠
      blokkoló hiba); a felhasználó javíthat és menthet.
```

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | `songDraftFromAnalysis` tiszta: ugyanarra a bemenetre kétszer futtatva BÁJTAZONOS vázlat, és a függvény nem érint órát/id-t/I/O-t | unit-teszt (kétszeri hívás egyenlősége) + a fájl importlistája |
| A2 | Az ütemszám a D2/4 képlete szerinti, `bpm × beatsPerBar` mátrixon | property-teszt (lásd 6.2) |
| A3 | Minden ütem címkéje NEM ÜRES, ha az idővonalon van legalább egy akkord (sustain-szabály, D2/7) | unit + property |
| A4 | `coverage ∈ [0,1]`, és `uncertain = coverage < 0.5` — a küszöbön lévő ütem BIZTOS | küszöb-mátrix (6.1) |
| A5 | A vázlat → `Song` → `toJson` → `fromJson` körút a címkéket, mintát, `bpm`-et és `beatsPerBar`-t megőrzi | unit-teszt |
| A6 | A vázlat megnyitása UTÁN, megerősítés ELŐTT a `SongsRepository` tartalma VÁLTOZATLAN | widget-teszt valós `ProviderContainer`-rel |
| A7 | A megerősítés `add()`-del ment: a mentés után a dal a listában VAN (nem néma no-op) | widget-teszt a `songsControllerProvider` állapotán |
| A8 | Strum nélküli eredményből a vázlat minta-listája ÜRES, és a szerkesztő alapértelmezése marad | unit + widget-teszt |
| A9 | Az Analyze eredmény-sáv új művelete üres eredményen INAKTÍV (nincs vázlat a semmiből) | widget-teszt |

**NEM elfogadható gyengítés:**

- Az A4 küszöbét NEM szabad `<=`-re cserélni „hogy a határeset is figyelmeztessen":
  a `<` és a `<=` közti különbséget pontosan a „rajta" cella méri.
- Az A6-ot NEM elégíti ki az, hogy a mentés után törlünk („ideiglenes rekord"):
  a mérce az, hogy megerősítés előtt **egyáltalán nem keletkezik** rekord.
- Az A3-at NEM elégíti ki üres címke szűrése a megjelenítéskor: a VÁZLAT
  adatában sem lehet üres címke, különben a mentés `JsonRecordException`-nel bukik.
- Az A2-t NEM elégíti ki egyetlen `bpm`/`beatsPerBar` eset — a fixture default
  csendesen kiválaszthat egy pontot, ahol a hibás és a helyes kvantálás
  megkülönböztethetetlen.

### 6.1 Küszöb-mátrix — a származtatott `coverage`-re (`bpm = 120`, `beatsPerBar = 4` ⇒ `barSec = 2.0`)

`python3 -c` -vel számolva (nem fejben — [L637](../LESSONS.md#l637)):

| Átfedés az ütemben | Származtatott `coverage` | Elvárt `uncertain` | Mit mér |
|---|---|---|---|
| `0.9 s` | `0.45` | **true** | szigorúan a küszöb ALATT |
| `1.0 s` | `0.5` | **false** | pontosan a küszöbÖN — ez az egyetlen cella, ami a `<` és `<=` közt különbséget tesz |
| `1.1 s` | `0.55` | **false** | szigorúan a küszöb FÖLÖTT |

### 6.2 Mérce-mátrix — melyik hibás implementációt fogja PIROSRA

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `uncertain = coverage <= 0.5` | a 6.1 „pontosan a küszöbön" sora |
| Az ütemhossz `60/bpm` (beat) lesz `beatsPerBar * 60/bpm` helyett | A2 property-cella, a `beatsPerBar = 3` oszlop |
| A győztes címke az ütem KEZDETÉN szóló akkord (nem a legnagyobb átfedésű) | A2/A4 unit-cella: két akkord egy ütemben, 0,4 s + 1,6 s bontásban |
| Az átfedés nélküli ütem üres címkét kap | A3 + A5 (a `fromJson` `JsonRecordException`-t dob) |
| A vázlat `existing`-ként megy a szerkesztőnek (`update()`-ág) | A7 — a mentés után a lista ÜRES marad |
| A vázlat mentése a megnyitáskor történik | A6 |
| A minta „lazán többségi" (`>=` fél ütem) | A8 melletti unit-cella: 2 ütem, 1 strum a sloton → a slot marad ÜRES |

### 6.3 Property-mátrix (`test/property/song_draft_quantisation_property_test.dart`)

`PROPERTY_SEED` (hiányában 42) · `bpm ∈ {60, 90, 120, 180}` × `beatsPerBar ∈ {3, 4}`
× véletlen idővonalak (1–40 akkordszakasz). Invariánsok: determinizmus,
`coverage ∈ [0,1]`, nem üres címke, `barCount` a képlet szerint, és
`Song.toAnalyzeResult`-tal visszavezetve az ÜTEMHATÁROK egybeesnek.

### 6.4 Falszifikációs próba (KÖTELEZŐ, a §10-ben dokumentálva)

Cseréld a D5 mentési ágát `update()`-re, futtasd a gate-et → az **A7 cella
PIROS** → állítsd vissza. Ez bizonyítja, hogy a néma mentés-vesztést a kör
tényleg méri, nem csak leírja.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/songs/ test/features/analyze/ test/property/song_draft_quantisation_property_test.dart test/l10n/arb_parity_test.dart
```

A gate a `format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtatja (a box mért OOM-csapdája miatt a lánc
tilos). A teljes suite + a friss seedű property gate a CI-ban fut
([ADR 0053](../adr/0053-ci-full-test-suite.md)) — azt az orchestrátor indítja.

Az ARB-változás után a generált aggregátum frissítése kötelező:

```bash
dart run tool/gen_l10n_segments.dart
```

## 8. Implementációs sorrend

1. A §2 mért tényeinek ÚJRAMÉRÉSE (az `E18-R01` diffje alatta mozdult).
2. `song_draft_from_analysis.dart` — típusok + tiszta függvény, TESZTTEL ELŐSZÖR.
3. A küszöb- és property-mátrix cellái (6.1, 6.3).
4. `SongBuilderScreen` vázlat-ág (D5) + `songs/public.dart` export.
5. Az Analyze eredmény-sáv művelete + ARB-kulcsok + aggregátum-regenerálás.
6. A §6.4 falszifikációs próba lefuttatása és dokumentálása.
7. `tools/round-gate.sh` csonkítatlan kimenettel.
8. ADR 0537 megírása a §5 döntéseiből.

## 9. Kockázatok

- **A néma mentés-vesztés** (D5) — a legvalószínűbb hiba: a `existing`
  paraméter kézre esik, és a kör zölden szállítana egy nem mentő gombot.
- **A konfidencia-illúzió** — ha a felület „konfidenciát" ír, a felhasználó
  modell-bizonyosságnak hiszi a lefedettséget (D3).
- **A ritmus kitalálása** — egy „legalább valami minta" tartalék hamis
  ritmust ad a dalnak; a D4 üres mintája a becsületes válasz.
- **Az l10n forrás-csapda** — a generált `app_*.arb` kézi szerkesztése a
  `--check` módban elavul ([L646](../LESSONS.md#l646)); a forrás a `base/`.
- **A csonkítás** — 512 ütem fölött a néma levágás adatvesztésnek látszik (OD-03).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
