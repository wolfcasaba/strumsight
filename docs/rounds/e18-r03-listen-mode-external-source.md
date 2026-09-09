# E18-R03 — Hallgatás-mód külső forrásból

- **Státusz:** PREPARED (előre megírva 2026-09-09, kód olvasva: `main @ 1ae9e55`) — **`hold`: az `E18-R02` vázlat-útjára épül**
- **Típus:** Chapter 18 (Komponálás és akkordok hangból), Kör 3
- **Kör-azonosító:** `E18-R03`
- **Branch:** `<motor>/e18-r03-listen-mode-external-source`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** **nincs új** — a kört a MÁR MEGÍRT [ADR 0536](../adr/0536-chords-from-audio-source-boundary.md) köti (a `docs/adr/` ezért TILOS zóna ebben a körben).
- **Fejezet-terv:** [`docs/plans/chapter-18-composer-and-chords-from-audio.md`](../plans/chapter-18-composer-and-chords-from-audio.md)

**Visszakeresett előzmény:** [ADR 0536](../adr/0536-chords-from-audio-source-boundary.md)
(D1 hangletöltés SOHA, D2 a három engedett forrás, D4 retention),
[ADR 0056](../adr/0056-exclusive-microphone-session.md) (egy mikrofon-tulajdonos,
foglaltság → őszinte hiba), [ADR 0217](../adr/0217-analysis-raw-audio-retention.md)
(`keepOriginal = false`; ez az ADR MÉRTE, hogy a `ClipRecorder` puffere korlátlan),
[L606](../LESSONS.md#l606) (a zöld kapu és az üres forrás megkülönböztethetetlen).
A pre-flight futtassa a
`node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "mikrofon hallgatás mód külső hangforrás"`
parancsot, és frissítse a §2-t.

## 0.0 MIÉRT `hold`

A kör kimenete az `E18-R02` `songDraftFromAnalysis` útja: a hallgatás-mód nem kap
saját mentési ágat. **Mi oldja fel:** az `E18-R02` merge-e.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/analyze/engine/clip_recorder.dart",
  "lib/features/analyze/providers/analyze_providers.dart",
  "lib/features/analyze/screens/analyze_screen.dart",
  "lib/features/songs/application/song_draft_from_analysis.dart",
  "lib/features/songs/model/song.dart",
  "lib/features/songs/screens/song_builder_screen.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/analyze/listen_mode_test.dart",
  "test/features/songs/song_source_url_test.dart",
  "test/property/listen_clip_bound_property_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/features/analyze/mic_error_parity_test.dart",
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/songs/song_builder_audition_test.dart",
  "test/features/songs/song_tap_tempo_test.dart",
  "docs/rounds/e18-r03-listen-mode-external-source.md",
]
native_gate = false
gate_tests = [
  "test/features/analyze/",
  "test/features/songs/",
  "test/core/audio/",
  "test/app/offline_network_guard_test.dart",
  "test/property/listen_clip_bound_property_test.dart",
  "test/l10n/arb_parity_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
  "test/core/screen_size_guard_test.dart",
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

A felhasználó lejátssza a dalt — YouTube-videóként a saját telefonján, másik
készülékről, rádióból —, a StrumSight pedig **hallgatja a mikrofonnal**, és a
felismert akkordokból az `E18-R02` vázlat-útján dal-piszkozat lesz. A YouTube-
link csak **metaadatként** tárolható, hogy a felhasználó visszataláljon rá.
Ez az a kör, ami a felhasználó eredeti kérését („importálás YouTube-ról")
teljesíti — **letöltés nélkül**, az [ADR 0536](../adr/0536-chords-from-audio-source-boundary.md)
határai között.

## 2. Jelenlegi állapot — mért tények (`main @ 1ae9e55`)

- A felvevő út kész és kizárólagos: `ClipRecorder`
  (`lib/features/analyze/engine/clip_recorder.dart:11-57`) a
  `MicCapture`-ön keresztül `AudioOwner.analyzeRecorder` lease-t tart
  (`lib/features/analyze/providers/analyze_providers.dart:135`); második
  ownernek a koordinátor `audioSessionBusy` hibát ad, **nem lop mikrofont**
  (`lib/core/audio/lifecycle/audio_session_coordinator.dart:38-50`).
- A `MicStart` háromértékű (`ok | denied | failed`,
  `clip_recorder.dart:7`), és a képernyő a `micDenied` / `micError` fázisra
  külön, kimondott hiba-állapotot renderel
  (`lib/features/analyze/screens/analyze_screen.dart:178-232`).
- **A puffer korlátlan:** `final List<double> _buffer = []`
  (`clip_recorder.dart:15`), felső hossz nélkül — ezt már az
  [ADR 0217](../adr/0217-analysis-raw-audio-retention.md) is mérte.
  A V2 oldalon VAN korlát (`InputLimits.maxDuration = 10 perc`,
  `lib/features/audio_analysis/data/input/input_limits.dart:12`), de az a
  másik felvevő (`AnalysisRecorder`) ága.
- Az elemzés a felvétel forrásától FÜGGETLEN: `AnalyzeController._analyze`
  ugyanaz a farok a mikrofonos és az importált útra
  (`analyze_providers.dart:181-203`).
- A `Song` modellben **nincs link/forrás mező**
  (`lib/features/songs/model/song.dart:17-40`), a `toJson`/`fromJson` hat
  kulcsot ismer (`:109-142`).
- A hálózati csend őrzött: `test/app/offline_network_guard_test.dart` —
  kijelentkezve, diagnostics-off nincs kimenő kérés.

## 3. Scope

**Benne van:** a hangforrás megválasztása az Analyze képernyőn (a saját gitár /
a körülöttem szóló dal) · a hallgatás-klip felső korlátja és az automatikus
lezárás · a kimondott „nem töltünk le és nem töltünk fel semmit" szöveg · az
opcionális forrás-link tárolása és megjelenítése a dal-vázlatban ·
a vázlat forrás-megjelölése (`mikrofon / hallgatás`).

**NINCS benne (ebben a körben TILOS):**

- Bármilyen hálózati hívás, letöltés, link-lekérés vagy beágyazott lejátszó.
- Új `AudioOwner` enum-érték vagy `lib/core/audio/**` módosítás.
- DSP-, dekóder- vagy modell-paraméter érintése (`AGENTS.md` §9).
- Új képernyő vagy új route.
- Valós idejű (streamelő) akkordkijelzés — ez a kör KLIPET vesz fel és elemez.

## 4. Engedélyezett fájlok

Csak az `ai-router` blokk listája módosítható. Bármi más → MEGÁLLÁS és jelentés.

| Útvonal | Miért |
|---|---|
| `lib/features/analyze/engine/clip_recorder.dart` | a felső mintakorlát + automatikus lezárás |
| `lib/features/analyze/providers/analyze_providers.dart` | a forrás-mód állapota és a korlát bekötése |
| `lib/features/analyze/screens/analyze_screen.dart` | forrásválasztó, őszinte szöveg, link-mező |
| `lib/features/songs/application/song_draft_from_analysis.dart` | a vázlat forrás + link mezője (az `E18-R02` hozza létre) |
| `lib/features/songs/model/song.dart` | opcionális `sourceUrl` + a sanitizáló |
| `lib/features/songs/screens/song_builder_screen.dart` | a link megjelenítése/szerkesztése a vázlaton |
| `lib/l10n/base/app_{en,hu}.arb` + `lib/l10n/app_{en,hu}.arb` | az ÚJ kulcsok forrása, majd a GENERÁLT aggregátum |
| `test/...` | a kör saját mércéi (3 új fájl) + a pin-őrök (lásd alább) |

**A pin-őrök jogosultsága (S11):** a listán szereplő, a briefen KÍVÜL élő
pin-tesztek (`test/app/navigation/**`, `test/app/offline_network_guard_test.dart`,
`test/ui/goldens/e15_r13_full_variant_matrix_test.dart`,
`test/core/screen_size_guard_test.dart`,
`test/features/analyze/mic_error_parity_test.dart`,
`test/features/songs/song_builder_audition_test.dart`,
`test/features/songs/song_tap_tempo_test.dart`) azért vannak az `allowed_paths`-ban
ÉS a `gate_tests`-ben, mert a forrásválasztó és a link-mező a két képernyő
RENDERELT tartalmát mozdítja. A jogosultság PONTOSAN ennyi: a megváltozott render
leképezése a pinnelő cellában. **Cella törlése, `skip`-je vagy gyengítése TILOS.**

**Tilos zóna:** `lib/core/**`, `lib/features/audio_analysis/**`,
`lib/features/analyze/engine/clip_analyzer.dart`, `docs/adr/**`, `pubspec.yaml`.

## 5. Kötött architekturális döntések ([ADR 0536](../adr/0536-chords-from-audio-source-boundary.md))

### D1 — Semmit nem töltünk le és nem töltünk fel

A link **nem** hang-forrás: nincs `Dio`, `HttpClient`, `url_launcher`, webview
vagy bármilyen lekérés. A kör diffje NULLA hálózati hívást tartalmaz, és ezt a
`test/app/offline_network_guard_test.dart` méri (ADR 0536 D1).

### D2 — A hallgatás-mód az Analyze képernyő MÓDJA, nem új képernyő

Ugyanaz a felvevő, ugyanaz az elemző, ugyanaz az eredmény-sáv; a különbség a
forrás szemantikája és a szöveg. Új képernyő elmozdítaná a
`test/ui/ui_inventory_test.dart` egzakt leltárszámát és a
`check_screen_reachability` mérését — egy MÓD ugyanazt az élményt adja
mérce-mozgatás nélkül.

### D3 — Egy mikrofon-tulajdonos, őszinte foglaltság

A hallgatás-mód ugyanazt az `AudioOwner.analyzeRecorder` lease-t kéri
(`analyze_providers.dart:135`) — **nincs új enum-érték**, nincs `lib/core/audio`
módosítás. Ha a Live vagy a Tuner tartja a mikrofont, a felhasználó KIMONDOTT
„foglalt" hibát lát a meglévő `micError` ágon; a mikrofon elvétele tilos
([ADR 0056](../adr/0056-exclusive-microphone-session.md)).

### D4 — A klip KORLÁTOS, és a korlát elérése LEZÁR, nem csonkít

A `ClipRecorder` opcionális `maxSamples` felső korlátot kap. A hallgatás-mód
alapértéke **90 másodperc** (`sampleRate * 90` minta). A korlát elérésekor a
felvétel **magától leáll és elemez** — a többlet nem kerül némán a szemétbe, és
a puffer soha nem lép a korlát fölé. A gitár-mód alapértelmezése változatlan
(korlát nélkül) — ez a kör nem szűkíti a meglévő utat.

> A 90 s termékdöntés, nem DSP-hangolás: elég egy dal versszakára + refrénjére,
> és a memóriában tartott PCM így 44,1 kHz-en is a néhány MB-os sávban marad
> ([ADR 0217](../adr/0217-analysis-raw-audio-retention.md) retention-elve).

### D5 — A kimenet az `E18-R02` vázlat-útja

A hallgatás-mód eredménye ugyanaz az `AnalyzeResult`, és ugyanazon a
„Legyen ebből dal" műveleten megy tovább. **Nincs második mentési út** — egy
külön ág megkerülné a megerősítés-szabályt
([ADR 0284](../adr/0284-import-preview-is-not-a-commit.md) D1).

### D6 — A link METAADAT, fehérlistával

`Song.sourceUrl` opcionális (`String?`), JSON-kulcs `src`, hiányzó kulcs → `null`
(visszafelé kompatibilis). Elfogadott: `http` és `https` séma, **legfeljebb 2048
karakter**. Minden más (`javascript:`, `file:`, séma nélküli, túl hosszú) →
`null`, és a mentés ettől **nem bukik el** (a link kényelmi adat, nem a dal
lényege). A link soha nem kerül logba.

### D7 — A felület KIMONDJA, mi történik

A hallgatás-mód szövege explicit: a StrumSight a mikrofonnal hallgatja, ami
szól; **nem tölt le és nem tölt fel semmit**, a felismerés az eszközön fut. Ez
nem marketing-mondat, hanem a §5 termékhatár látható alakja.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: A forrásválasztó legyen-e perzisztens beállítás?
    blocking: false
    resolution_policy: use_default
    default: >-
      NEM. A mód a képernyő állapota, alapértelmezése a gitár-mód; egy
      elfelejtett „hallgatás" állapot csendben más felvevő-viselkedést adna.
  - id: OD-02
    question: Mi történjen, ha a felhasználó a korlát előtt állítja le?
    blocking: true
    resolution_policy: use_default
    default: >-
      a meglévő `stopAndAnalyze` út fut változatlanul; a korlát csak FELSŐ
      határ, nem minimum.
  - id: OD-03
    question: Hol jelenjen meg a link-mező?
    blocking: true
    resolution_policy: use_default
    default: >-
      a dal-vázlat szerkesztőjében (ott van a megerősítés), NEM a felvételi
      képernyőn — a felvétel közbeni gépelés elvonja a figyelmet és a mikrofon
      él közben.
  - id: OD-04
    question: Foglalt mikrofon esetén próbálkozzunk-e újra automatikusan?
    blocking: true
    resolution_policy: use_default
    default: >-
      NEM. Kimondott hiba + kézi újrapróbálás (a meglévő `micError` ág);
      az automatikus retry a másik owner alól venné el a mikrofont.
```

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A kör diffje NULLA hálózati hívást és NULLA letöltő függőséget visz be; az offline-őr zöld | `test/app/offline_network_guard_test.dart` + a diff olvasása |
| A2 | A hallgatás-klip mintaszáma SOHA nem lépi túl a korlátot, és a korlát elérésekor a felvétel MAGÁTÓL leáll | küszöb-mátrix (6.1) + property (6.3) |
| A3 | A gitár-mód felvétele változatlan: korlát nélkül fut, a meglévő tesztek zöldek | `test/features/analyze/` regresszió |
| A4 | Foglalt mikrofonnál a hallgatás-mód KIMONDOTT hibát ad, és a másik owner lease-e ÉL marad | teszt valós `AudioSessionCoordinator`-ral |
| A5 | A `sourceUrl` sanitizáló csak `http`/`https` sémát és ≤ 2048 karaktert fogad; minden más `null` | küszöb-mátrix (6.2) |
| A6 | `Song` JSON körút: `src` nélküli RÉGI rekord továbbra is beolvasható, `sourceUrl == null` | unit-teszt régi fixture-rel |
| A7 | A hallgatás-módból származó vázlat ugyanazon a megerősítési úton megy; megerősítés előtt a tár VÁLTOZATLAN | widget-teszt |
| A8 | A hallgatás-mód szövege kimondja, hogy nincs letöltés/feltöltés, és mindkét locale-ban létezik | `test/l10n/arb_parity_test.dart` + widget-teszt |

**NEM elfogadható gyengítés:**

- Az A2-t NEM elégíti ki a puffer utólagos levágása: a mérce az, hogy a
  felvétel **leáll**, és a puffer hossza pontosan a korlát — a „felveszünk
  többet, aztán eldobjuk" ág épp a retention-elvet (ADR 0217) sérti.
- Az A4-et NEM elégíti ki a mikrofon átvétele „mert a felhasználó ezt kérte":
  a foglaltság ŐSZINTE hiba, nem megkerülendő akadály.
- Az A5-öt NEM elégíti ki a `startsWith('http')` ellenőrzés: a séma-fehérlista
  parse-olt URI-n mérendő (`Uri.tryParse` + `scheme`), különben a
  `httpx://…` vagy a `http:javascript:` alak átcsúszik.
- Az A1-et NEM elégíti ki „a hívás csak flag mögött fut": ebben a körben
  hálózati kód egyáltalán nem születik.

### 6.1 Küszöb-mátrix — a hallgatás-klip felső korlátja (`sampleRate = 44100`, cap = 90 s)

`python3 -c`-vel számolva: `44100 * 90 = 3969000` minta.

| Felajánlott mintaszám | Másodperc | Elvárt viselkedés | Mit mér |
|---|---|---|---|
| `3968999` | `89,99997732…` | fut tovább, `isRecording == true` | szigorúan a küszöb **alatt** |
| `3969000` | `90,0` | a felvétel LEÁLL, a puffer hossza **pontosan** `3969000` | pontosan **rajta** — ez az egyetlen cella, ami a `>=` és a `>` közt különbséget tesz |
| `3969001` | `90,00002267…` | a felvétel LEÁLL, a puffer hossza **`3969000`**, nem `3969001` | szigorúan a küszöb **fölött** (a túlcsordult minta nem kerül a pufferbe) |

### 6.2 Küszöb-mátrix — a link hossza (cap = 2048 karakter)

| URL hossza | Elvárt `sourceUrl` | Mit mér |
|---|---|---|
| `2047` | az URL | szigorúan a küszöb **alatt** |
| `2048` | az URL | pontosan **rajta** (`<=`) |
| `2049` | `null` | szigorúan a küszöb **fölött** |

Séma-cellák: `https://…` → elfogadva · `http://…` → elfogadva ·
`javascript:alert(1)` → `null` · `file:///etc/passwd` → `null` ·
`youtube.com/watch?v=x` (séma nélkül) → `null`.

### 6.3 Mérce-mátrix — melyik hibás implementációt fogja PIROSRA

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A korlát-ellenőrzés `>` és nem `>=` | 6.1 „pontosan rajta" sora |
| A korlát elérésekor a felvétel FUT tovább, csak nem gyűjt | A2 (`isRecording` cella) |
| A túlcsorduló chunk EGÉSZBEN bekerül | 6.1 harmadik sora (puffer-hossz) |
| A korlát a gitár-módra is életbe lép | A3 regresszió |
| `startsWith('http')` séma-ellenőrzés | 6.2 `http:javascript:` cellája |
| A hallgatás-mód saját mentési utat kap | A7 |
| A foglalt mikrofon átvétele | A4 |

### 6.4 Property-mátrix (`test/property/listen_clip_bound_property_test.dart`)

`PROPERTY_SEED` (hiányában 42) · `sampleRate ∈ {8000, 16000, 44100, 48000}` ×
véletlen chunk-méretek (1–8192) × véletlen chunk-számok. Invariáns: a puffer
hossza SOHA nem nagyobb a korlátnál, a korlát elérése után `isRecording == false`,
és a felvétel eredménye determinisztikus ugyanarra a chunk-sorozatra.

### 6.5 Falszifikációs próba (KÖTELEZŐ, a §10-ben dokumentálva)

Cseréld a korlát-ellenőrzést `>=`-ról `>`-ra, futtasd a gate-et → a 6.1
„pontosan rajta" cella **PIROS** → állítsd vissza. Másodikként: vedd ki a
séma-fehérlistát → a 6.2 `javascript:` cellája **PIROS** → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/analyze/ test/features/songs/ test/core/audio/ test/app/offline_network_guard_test.dart test/property/listen_clip_bound_property_test.dart test/l10n/arb_parity_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/ui/goldens/e15_r13_full_variant_matrix_test.dart test/core/screen_size_guard_test.dart
```

A gate a `format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtatja. Az ARB-változás után:

```bash
dart run tool/gen_l10n_segments.dart
```

## 8. Implementációs sorrend

1. A §2 mért tényeinek ÚJRAMÉRÉSE (az `E18-R02` diffje alatta mozdult).
2. `ClipRecorder` felső korlát + automatikus lezárás, TESZTTEL ELŐSZÖR (6.1, 6.4).
3. A forrás-mód állapota a controllerben, a korlát bekötése a hallgatás-módra.
4. `Song.sourceUrl` + sanitizáló (6.2) + JSON-körút (A6).
5. Az Analyze képernyő forrásválasztója és a kimondott szöveg (D7) + ARB.
6. A vázlat forrás/link mezője és a szerkesztő megjelenítése (OD-03).
7. A §6.5 falszifikációs próbák lefuttatása és dokumentálása.
8. `tools/round-gate.sh` csonkítatlan kimenettel.

## 9. Kockázatok

- **A jogi határ csendes átlépése.** Egy „nyisd meg a linket" gomb, egy
  beágyazott lejátszó, egy „csak a hangsáv" segéd mind az ADR 0536 D1-be
  ütközik. A kör diffjében hálózati kód nem születhet (A1).
- **A hangszóró-visszacsatolás.** Ha a StrumSight is szólna (metronóm,
  akkord-meghallgatás), a mikrofon a saját hangját is hallaná. A hallgatás-mód
  alatt a saját hangkimenetnek némának kell lennie — ha ez a kör nem tudja
  garantálni a listán belül, `stopped` és brief-revízió.
- **A hamis pontosság-ígéret.** Hangszórón át a felismerés gyengébb; a
  hallgatás-mód szövege nem sugallhat gitár-szintű pontosságot (ADR 0536 D3).
- **A memória.** Korlát nélkül egy elfelejtett hallgatás-felvétel percekig nő
  (`clip_recorder.dart:15`) — ezt a D4 zárja le.
- **A mikrofon-ütközés.** A Live/Tuner lease-e alatt a hallgatás-mód nem
  indulhat, és a hibának LÁTSZANIA kell (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
