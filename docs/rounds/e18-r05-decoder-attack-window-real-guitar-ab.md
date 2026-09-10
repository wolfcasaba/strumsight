# E18-R05 — A dekóder onset-ablakának eltolása az attack-ról a sustain-re: fixture + property + valós gitáros A/B

- **Státusz:** PREPARED (előre megírva 2026-09-10, kód olvasva: `claude/optimistic-bohr-vpaxh4 @ 3521c210`) — **`hold`: a felhasználó VALÓS GITÁROS mérése a belépő feltétel (§0.0)**
- **Típus:** Chapter 18 (Komponálás és akkordok hangból) kísérő DSP-kör — **döntési paraméter, AGENTS.md §9 alatt**
- **Kör-azonosító:** `E18-R05`
- **Branch:** `<motor>/e18-r05-decoder-attack-window`
- **Brief szerzője:** Claude (Fable) · Implementáció: Codex vagy M3
- **Előre kiosztott ADR:** `ADR 0540` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset.
- **Előzmény:** [ADR 0539](../adr/0539-live-recognition-stability-stabilized-hero-and-onset-guard.md) D4 (a dekóder attack-ablaka NEM változott az E18-R01 javító körben), a kutatási jegyzet §4 protokollja: [`docs/research/chord-recognition-stability-and-engines-2026-09.md`](../research/chord-recognition-stability-and-engines-2026-09.md), a DSP-igazság: [`docs/rag/chunks/016-pitch-chord-sota.md`](../rag/chunks/016-pitch-chord-sota.md) „AS BUILT round 138" + az E18-R01 megjegyzés.

**Visszakeresett előzmény:** a tünet („leütött C → egy keretre más akkord → vissza
C", MINDEN akkordnál, a felhasználó 2026-09-09-i jelentése) mechanizmusa a
kutatási jegyzet §2-ben mért: a `ViterbiChordDecoder` onset-boostja
(`_onsetBoostFrames = 2`, `_onsetBonusScale = 0.25`, ~186 ms a 93 ms-os
akkord-hopnál) PONTOSAN az attack-tranziensre esik, ahol a kromagram a
legzajosabb; a bónusz-csökkentés ott engedi át a kihívót. Az E18-R01 a
DÖNTÉSI rétegen orvosolt (stabilizált hős, 0,2 s onset-őr, kártya-lejárat),
a dekóder-konstans érintetlen maradt, mert DSP-igazság csak fixture +
property + valós gitáros mérés HÁRMASÁVAL mozdítható (AGENTS.md §9).

## 0.0 MIÉRT `hold` — és mi oldja fel

A kör NEM indítható a felhasználó boxán elvégzett **valós gitáros
alapmérés** nélkül (§7 „0. lépés"). Két kimenete lehet:

1. Az E18-R01 döntési-rétegű javításai után a tünet a Live-on **már nem
   látható** (`flipRate` ≈ 0 ismételt pengetésnél) → a kör **lezárul kód
   nélkül**: az ADR 0540 rögzíti a mért alapértéket és azt, hogy a
   dekóder-oldali eltolás NEM szükséges. Ez is teljes értékű kimenet.
2. A tünet a stabilizált hős MÖGÖTT (a nyers `frame.current`-ben, a
   diagnosztika-panelen) továbbra is mérhető → a kör a §5 szerint megy tovább.

**Mi oldja fel a `hold`-ot:** a §7 „0. lépés" mérési jegyzőkönyve a §10-ben
(nyers `flipRate` érték, akkordonként), az orchestrátor jóváhagyásával.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/live/engine/dsp/viterbi_chord_decoder.dart",
  "lib/features/live/engine/dsp/dsp_config.dart",
  "test/features/live/dsp/viterbi_decoder_test.dart",
  "test/property/viterbi_onset_window_property_test.dart",
  "test/fixtures/audio/live_repeated_strums/README.md",
  "test/fixtures/audio/live_repeated_strums/manifest.json",
  "docs/rag/chunks/016-pitch-chord-sota.md",
  "docs/adr/0540-decoder-onset-window-on-sustain.md",
  "docs/research/chord-recognition-stability-and-engines-2026-09.md",
  "docs/rounds/e18-r05-decoder-attack-window-real-guitar-ab.md",
]
native_gate = false
gate_tests = [
  "test/features/live/dsp",
  "test/property",
]
```

> A `native_gate = false` IGAZ: a kör tiszta Dart DSP-t érint, Android-build
> nélkül mérhető; a végső mérce (valós gitár a telefon mikrofonján) az APK-t
> a `build-apk.yml` artefaktumából kapja, amit az orchestrátor indít.

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

**Mért döntés** arról, hogy a Viterbi-dekóder onset-boost ablakát el kell-e
tolni az attack-tranziensről a korai sustain-re — és ha igen, az eltolt
ablak MÉRTEN kevesebb téves váltást ad ismételt pengetésnél, miközben a
valódi akkordváltás megerősítési késése nem romlik 450 ms fölé. A kimenet:
**ADR 0540 + fixture-alapú A/B + randomizált property + valós gitáros
jegyzőkönyv**; a konstans CSAK a hármas mérce zöldjével mozdul.

## 2. Jelenlegi állapot — mért tények (`3521c210`)

- `lib/features/live/engine/dsp/viterbi_chord_decoder.dart:66-73`:
  `_onsetBoostFrames = 2`, `_onsetBonusScale = 0.25`, `noteOnset()` →
  `_boostLeft = 2`; a `process()` a boost alatt `selfBonus * 0.25`-öt ad
  (`:88-90`), gated keret NEM fogyasztja (`:88`, r142 audit).
- `DspConfig.chordSelfTransitionBonus = 0.22` (`dsp_config.dart:39`),
  akkord-hop `nnlsHop = 4096` ≈ 93 ms (`:17`).
- A boostot a pipeline az onset-detektor `onsetJustFired` jelére indítja
  (`live_pipeline.dart:226`), ~12 ms detektálási késéssel — tehát az 1. és
  2. boostolt akkord-keret a 0–186 ms-os attack-sávra esik.
- A meglévő mérce: `test/features/live/dsp/viterbi_decoder_test.dart`
  „onset-aligned switch boost" csoport (`:123`): a marginális váltás
  gyorsabb onset után (`:133`), a boost lejár (`:148`), azonos akkordon az
  onset nem vált (`:194`). **Nincs** cella arra, hogy az attack-keret
  ZAJOS kromagramja (nem marginális, hanem tranziens-torzított) mit tesz.
- A döntési réteg (E18-R01, ADR 0539): `RecognitionStabilizer`
  `onsetTransientGuardSec = 0.2` (`recognition_stabilizer.dart:39,52`),
  `flipRate` getter (`:83`), `debugFramesProcessed` (`:88`).

## 3. Scope

**Benne van:** a fixture (ismételt pengetések WAV-ban, akkordonként) ·
a decoder A/B-je a fixture-ön (mai ablak vs. eltolt ablak) · randomizált
property az onset-ablakra · az ADR · a RAG-chunk frissítése ugyanabban a
commitban · a valós gitáros jegyzőkönyv a §10-ben.

**NINCS benne (ebben a körben TILOS):**

- A `RecognitionStabilizer`, a `ChordTimeline`, a `LiveScreen` — a döntési
  réteg az E18-R01-ben zárult; itt csak a dekóder mozdul.
- A `selfBonus` (0.22) vagy az NNLS/onset-detektor bármely paramétere —
  egy változó egyszerre, különben az A/B nem értelmezhető.
- A `LiveCrnnClassifier.calibrate` 0.87-es plafonja (külön kör: kalibráció
  valós adaton — a kutatási jegyzet §5).
- 64 kbps MP3 loopback fixture — a jelentés saját tanulsága: WAV, vagy semmi.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/live/engine/dsp/viterbi_chord_decoder.dart` | az ablak-alak (mely keretekre esik a bónusz-csökkentés) — CSAK a §6 zöldjével |
| `lib/features/live/engine/dsp/dsp_config.dart` | ha az ablak-alak konfigurálható konstanssá válik (D2) |
| `test/features/live/dsp/viterbi_decoder_test.dart` | az „onset-aligned switch boost" csoport új cellái (A1–A3) |
| `test/property/viterbi_onset_window_property_test.dart` | ÚJ — randomizált property (`PROPERTY_SEED`), A4 |
| `test/fixtures/audio/live_repeated_strums/README.md`, `manifest.json` | a fixture leírása és a mért címkék; a WAV-ok NEM commitolódnak (D4) |
| `docs/rag/chunks/016-pitch-chord-sota.md` | a DSP-igazság — ugyanabban a commitban, mint a konstans |
| `docs/adr/0540-decoder-onset-window-on-sustain.md` | a döntés (akkor is, ha „nem változtatunk") |
| `docs/research/chord-recognition-stability-and-engines-2026-09.md` | §4 mért eredményei |
| `docs/rounds/e18-r05-decoder-attack-window-real-guitar-ab.md` | státusz és §0.0-revízió |

**Tilos zóna:** `lib/features/live/engine/recognition_stabilizer.dart`,
`lib/features/live/providers/**`, `lib/features/live/widgets/**`,
`lib/features/live/screens/**`, `lib/features/live/engine/dsp/nnls_*`,
`*onset_detector*`, `lib/features/live/engine/ml/**`, `pubspec.yaml`.

> **ÚJ fájl létrehozása is scope-sértés, ha nincs a listán.** A kör két új
> fájlt kap (a property és a fixture-leírás); bármi más → `stopped`.

> **KÖTELEZŐ pre-flight:** `tools/gateguard-scan.py --brief docs/rounds/e18-r05-decoder-attack-window-real-guitar-ab.md`
> (0 = indítható). A lista nem tartalmaz védett útvonalat.

## 5. Kötött döntések (ADR 0540)

### D1 — Egy változó mozdul: az onset-boost ablak ALAKJA

A bónusz-csökkentés keretenkénti profilja változhat (pl. `[1.0, 0.25, 0.5]`
az onset utáni 1., 2., 3. akkord-keretre — az 1. keret TELJES bónusszal, a
2.–3. csökkentettel), a `selfBonus`, az NNLS és az onset-detektor NEM. Az
A/B két karja: **A = mai** (`[0.25, 0.25]`), **B = eltolt** (a kör által
mért legjobb profil a §6.1 rácsból).

### D2 — A profil konstansként él, nem futásidejű kapcsolóként

Nincs feature-flag, nincs beállítás: a Live egyetlen dekódert futtat. Ha B
nyer, a konstans változik és a RAG-chunk ugyanabban a commitban; ha A marad,
a kód nem változik, csak az ADR és a chunk kap mért „nem mozdul" bejegyzést.

### D3 — A mérce a SZÁRMAZTATOTT mennyiség: téves megerősített váltás / pengetés

Nem a dekóder nyers keret-címkéi számítanak, hanem az, amit a felhasználó
lát: ismételt pengetésnél a **megerősített** címke (a stabilizátor
kimenete) hányszor tér el az akkordtól pengetésenként (`flipRate`), és
valódi váltásnál az onsettől a megerősítésig eltelt idő. A property és a
fixture-cellák is EZT mérik, a nyers keret-flip csak diagnosztika.

### D4 — A WAV-ok nem kerülnek a repóba

A fixture leírása (`README.md`) és a mért címkék (`manifest.json`)
commitolódnak; a hangfájlok a futtató boxán élnek, az útvonalat env-ből
(`STRUMSIGHT_LIVE_FIXTURE_DIR`) kapja a teszt, és HIÁNYUKBAN a fixture-cellák
`skip`-pel jelzik magukat — de a property-cella szintetikus kromagrammal
mindig fut. Egy „skip" NEM zöld: a §10 handoff a fixture-cellák TÉNYLEGES
futásának kimenetét idézi.

### D5 — A valós gitár a végső mérce, a szintetikus zöld nem „kész"

A HORIZON-szabály (CLAUDE.md): a végső elfogadás a felhasználó valós
gitáros APK-tesztje a §7 „0." és „5." lépése szerint, a §10-ben
jegyzőkönyvezve.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Az eltolt ablak javít az ismételt pengetésen, de a valódi váltás késése 450 ms fölé nő — melyik nyer?
    blocking: true
    resolution_policy: use_default
    default: >-
      A (mai ablak) marad; az ADR a mért trade-offot rögzíti. A késés-küszöb
      a döntés ELŐTT rögzített (§6.1), utólag nem emelhető.
  - id: OD-02
    question: Több profil is zöld a rácson — melyiket válasszuk?
    blocking: false
    resolution_policy: use_default
    default: >-
      a legkisebb késésűt a zöldek közül; egyenlőségnél a maihoz legközelebbit
      (legkisebb változás).
  - id: OD-03
    question: A fixture nem reprodukálja a tünetet (0 téves váltás már A-val is)?
    blocking: true
    resolution_policy: use_default
    default: >-
      a fixture NEM elég a döntéshez; a kör a valós gitáros nyers flipRate-re
      támaszkodik (§7 „0." lépés). Ha az is 0 → §0.0 (1) kimenet, kód nélkül.
```

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Ismételt pengetés (ugyanaz az akkord 8×, 7 akkordra) → **0** téves megerősített váltás a B karral, és a szám NEM nagyobb, mint az A karral | `viterbi_decoder_test.dart` fixture-cellák, akkordonként |
| A2 | Valódi váltás (4 pár) megerősítési késése B-vel ≤ 450 ms, és legfeljebb +93 ms (egy akkord-keret) az A-hoz képest | `viterbi_decoder_test.dart` „real change" cellák; a 6.1 küszöb-hármas |
| A3 | Azonos akkordon az onset továbbra sem vált (a meglévő `:194` cella zöld marad) | meglévő cella |
| A4 | Randomizált property: tetszőleges seedre az attack-tranziens-torzított 1. keret (a helyes akkord kromagramja + zaj) NEM vált a B profillal, ha a 2.–3. keret a helyes akkord | `test/property/viterbi_onset_window_property_test.dart`, `PROPERTY_SEED` |
| A5 | A konstans-változás és a `016-pitch-chord-sota.md` frissítése EGY commitban van | `git log -1 --stat` |
| A6 | A valós gitáros jegyzőkönyv (7 akkord × 8 pengetés, 4 váltás) a §10-ben, nyers `flipRate`-tel A-ra és B-re | §10 |
| A7 | A `selfBonus`, az NNLS és az onset-detektor paraméterei bájtra változatlanok | `git diff --stat` (csak az engedélyezett fájlok) |

**NEM elfogadható gyengítés:**

- Az A1-et NEM elégíti ki a nyers keret-flip számolása a megerősített helyett
  (D3): a mérce a stabilizátor kimenete.
- Az A2 küszöbe (450 ms) a döntés ELŐTT rögzített; a mátrix „pontosan
  rajta" cellája nélkül a `<`/`<=` különbség mérhetetlen.
- Az A4-et NEM elégíti ki fix seedű cella: a property `PROPERTY_SEED`-et
  olvas, és CI-ban a `run_id` seeddel is fut.
- Az A6-ot NEM elégíti ki emulátoros loopback: a mérce a telefon
  mikrofonja + valós gitár.
- A fixture-cellák `skip`-je NEM zöld (D4).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A bónusz-csökkentés az 1. keretre is teljes (= a mai viselkedés B-ként eladva) | A4 property: a zajos 1. keret vált |
| Az ablak túl hosszú (bónusz-csökkentés 4+ keretre) | A2 „real change" nem romlik, de A1 ismételt pengetésnél a 4. keret zajára vált → piros |
| A boostot a gated keret fogyasztja (r142 regresszió) | a meglévő „gated frame keeps the boost" cella |
| A `selfBonus` csendes átállítása „hogy B nyerjen" | A7 diff-mérce + a `dsp_config` cellái |
| A késés-küszöb utólagos emelése | a 6.1 küszöb-hármas „pontosan rajta" cellája |
| A property fix seeddel | CI HARD lépés `PROPERTY_SEED=${{ github.run_id }}` |

**Küszöb-hármas a megerősítési késésre (A2), `python3 -c`-vel számolva a
93 ms-os hopból: 4 keret = 372 ms (alatta), 450 ms (pontosan rajta —
elfogadható `<=`), 5 keret = 465 ms (fölötte — piros).**

| Mért késés | Elvárt |
|---|---|
| 372 ms (4 keret) | ZÖLD |
| 450 ms | ZÖLD (`<=`) |
| 465 ms (5 keret) | PIROS |

### 7.1 Falszifikációs cella minden acceptance-ponthoz

| Acceptance | Őr | Valódi-sértés próba |
|---|---|---|
| A1 | fixture-cellák (7 akkord) | B profil → `[0.25, 0.25]` visszaállítása → legalább egy akkord piros (különben a fixture nem reprodukál: OD-03) |
| A2 | „real change" cellák + küszöb-hármas | ablak `[1.0, 1.0, 1.0]` (nincs boost) → késés 465 ms fölé → piros |
| A4 | property | a property zaj-amplitúdójának nullázása → vacuous: a cella KÖTELEZŐEN asszertálja, hogy a zajos keret ÖNMAGÁBAN (boost nélkül) váltana |
| A5 | `git log` | a chunk-frissítés külön commitban → review BLOCKER |
| A7 | `git diff --stat` | bármely tilos-zónás fájl a diffben → `stopped` |

## 7. Kötelező ellenőrzések

**0. lépés — a `hold` feloldása (a felhasználó boxán, kód előtt):** az
E18-R01 APK-jával (`strumsight-1.0.0-1-3521c21-development.apk`, build-apk
34431041159) valós gitárral: 7 akkord × 8 ismételt pengetés + 4 váltás, a
diagnosztika-panel nyers `flipRate` értékével akkordonként → §10.

```bash
tools/round-gate.sh test/features/live/dsp test/property
```

A gate a `format` → `analyze` → `test <minden útvonal külön>` →
`architecture` lépéseket KÜLÖN processzként futtatja. A fixture-cellák a
`STRUMSIGHT_LIVE_FIXTURE_DIR` env-vel futnak; a §10 az ezzel futtatott,
csonkítatlan kimenetet idézi.

A teljes suite + randomizált property-kapu + APK a CI-ban:

```bash
gh workflow run build-apk.yml --ref <kör-branch>
```

**5. lépés — a végső mérce:** a kör APK-jával ugyanaz a valós gitáros
protokoll, mint a 0. lépésben; A és B nyers `flipRate`-je egymás mellett a
§10-ben (D5).

## 8. Implementációs sorrend

1. §7 „0." lépés — valós gitáros alapmérés; `hold` feloldása vagy §0.0 (1) lezárás.
2. Fixture: WAV-ok felvétele a boxon, `README.md` + `manifest.json` (címkék, onset-idők).
3. A/B keret: a dekóder profil-paraméterezése (D1) TESZT-oldali injektálással; A és B fixture-cellák (A1–A3).
4. Property (A4) `PROPERTY_SEED`-del; a §7.1 vacuous-őr.
5. Rács a §6.1 szerint, OD-02 kiválasztás; konstans + RAG-chunk EGY commitban (A5).
6. ADR 0540 (akkor is, ha A marad).
7. `tools/round-gate.sh` csonkítatlan kimenettel; CI dispatch az orchestrátortól.
8. §7 „5." lépés — valós gitáros A/B, §10 jegyzőkönyv (A6).

## 9. Kockázatok

- **A fixture nem reprodukál.** A 64 kbps MP3 loopback tünet-forrás volt az
  emulátoros jelentésben; WAV-val a tünet gyengébb lehet → OD-03.
- **Kétirányú trade-off.** Az eltolt ablak késlelteti a valódi váltást;
  a 450 ms küszöb a termék-érzet határa (a kutatási jegyzet §4), nem
  alkudható utólag (OD-01).
- **Egy változó fegyelme.** A `selfBonus` és az onset-detektor csábító
  „kis" hangolása az A/B-t értelmezhetetlenné teszi (A7).
- **Szintetikus zöld.** A property és a fixture nem hallja a telefon
  mikrofonját; a HORIZON végső mérce a valós gitár (D5).
- **A CRNN-ág.** A `LiveCrnnClassifier` 0.87-es plafonja külön kérdés; ha a
  Live a CRNN-ágon fut, a Viterbi-ablak hatása kisebb — az ADR nevezze meg,
  melyik ágon mért a jegyzőkönyv.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
