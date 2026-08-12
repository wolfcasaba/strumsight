# E06-R10 — Security / adatvédelmi / prompt-injection review

- **Kör:** E06-R10 — Event evidence modell és onset/strum timeline V2
- **Branch:** `codex/e06-r10-event-evidence-onset-strum-timeline`
- **Diff:** `git diff origin/main...codex/e06-r10-event-evidence-onset-strum-timeline` (izolált klón: `/tmp/review-e06-r10-security`)
- **Reviewer:** Claude (dedikált security-reviewer, READ-ONLY — production kód nem módosult, AGENTS.md §15.1)
- **Dátum:** 2026-08-12
- **Brief kockázat:** `risk = "high"` → kötelező dedikált security review (CLAUDE.md)
- **Verdikt:** **PASS** — 0 CRITICAL · 0 BLOCKER · 0 MAJOR · **1 MINOR** · 5 NOTE (a MINOR és mind az öt NOTE latens/előre-mutató, az R19/R22 bekötő körökre)

> **Nincs BLOCKER/CRITICAL lelet.** A kör nem sért nem-tárgyalható termékhatárt
> (AGENTS.md §5): nincs titok-szivárgás, consent-megkerülés, path-traversal,
> RCE, hálózati kérés, mikrofon-hozzáférés vagy nyers-audio kiszivárgás. A
> teljes `audio_analysis` V2 feature — beleértve az `EventTimelineBuilder`-t és
> az `EventId`-t — **még nincs bekötve** (`audioAnalysisV2Enabled = false`
> minden környezetben, nincs `lib/` fogyasztó). A brief által kiemelt fő aggály
> (memória/DoS nagyon hosszú klipeken, integer overflow a sample-index
> számításban) **reprodukálhatóan NEM áll fenn** — a részletet lásd §2.1.

---

## 1. Vizsgált diff és módszer

`git diff --stat origin/main...HEAD` (a security-releváns felület):

| Fájl | Állapot |
|---|---|
| `lib/features/audio_analysis/domain/analysis_event.dart` | **MÓDOSÍTVA** (+95, additív — csak `OnsetEvent`/`StrumEvent` bővül) |
| `lib/features/audio_analysis/domain/events/event_id.dart` | ÚJ (30 sor) |
| `lib/features/audio_analysis/engine/events/event_timeline_builder.dart` | ÚJ (261 sor) |
| `lib/features/audio_analysis/public.dart` | +2 export (`event_id.dart`, `event_timeline_builder.dart`) |
| `tool/check_architecture.dart` | **VÁLTOZATLAN** (`git diff` üres) |
| 4 teszt (`domain/analysis_event_test`, `domain/event_id_test`, `engine/event_timeline_builder_test`, `property/analysis_event_timeline_property_test`) | ÚJ |
| `docs/adr/0228-*.md`, `docs/rounds/e06-r10-*.md` | ÚJ |

A `preprocessed_audio.dart` (E06-R08), `legacy_evidence.dart` és
`analysis_provenance_builder.dart` (E06-R09) **nem módosult** ebben a körben — a
builder fogyasztja őket. Az `AnalysisEvent` bázisosztály és a testvér-típusok
(`ChordChangeEvent` stb.) egyetlen sora sem változott (§3/§4 tilos zóna
betartva).

**Reprodukálható alap-tények (mind lefuttatva a klónban):**

- `tool/` diffje **üres** → az architektúra-allowlist bitre változatlan.
- `audioAnalysisV2Enabled = false` (`feature_flags.dart:32,78`); **semmi nem
  importálja** az `audio_analysis/public.dart`-ot `lib/`-ben az `audio_analysis`
  fán kívül; `EventTimelineBuilder`/`EventId` egyetlen `lib/` fogyasztóval sem
  rendelkezik a definíciós fájlokon kívül (a `grep`-találatok `targetEventId`
  substringek a `practice`/`song_trainer` fában — más, pre-existing szimbólum).
  → a feature **teljesen unwired**. Az `analysis_recorder.dart`/
  `analysis_context.dart` (a `runId` forrása) szintén unwired.
- `grep -nE 'print\(|Logger|debugPrint|stderr|stdout|developer\.|log\(|toString'`
  a három érintett `lib/` fájlon → **NONE** (nincs napló-sink, nincs custom
  `toString`).
- Pure-Dart probe (`/tmp/r10probe/probe.dart`, a három import-mentes domain
  fájl standalone futtatva) reprodukálta a §2 [A]–[E] viselkedéseit.

---

## 2. Leletek bizonyítékkal

### 2.1 PCM-puffer, attack/RMS ablakok, memória/DoS, integer overflow → CLEAN (a brief fő aggálya reprodukálhatóan NEM áll fenn)

A builder az `originalSamples` **immutable** pufferen (`preprocessed_audio.dart:16`,
`List.unmodifiable`) számol attack-peaket és RMS-t. A vizsgálat eredménye:

- **Fix méretű ablakok, NEM klip-hosszúsággal skálázódnak.** Az attack-ablak
  `[t, t+20 ms]`, az RMS-ablak `[t−5 ms, t+45 ms]` — névvel ellátott
  `Duration`-konstansok (`event_timeline_builder.dart:47-50`). 48 kHz-en ez
  **960**, illetve **2400** minta; 44,1 kHz-en 882/2205 minta — a klip
  hosszától **függetlenül**. A `_absolutePeak` (`:208-215`) és `_rms`
  (`:217-227`) loopja pontosan ezt a fix ablakot járja be eseményenként. Egy
  10 perces és egy 10 órás klip **azonos** per-esemény költséget ad.
- **Nincs PCM-másolat.** A builder indexeléssel olvas az immutable pufferből,
  nem duplikálja azt; az extra memória a kimeneti event-listán túl O(1). A
  teljes munka O(strums × fix_ablak) + O(strums·log strums) rendezés
  (`:66`) — a `strums` szám a V1 analizátor fizikai strum-szeparációval
  korlátozott kimenete, nem támadó által, klip-hossztól függetlenül
  növelhető mennyiség.
- **Index-out-of-range kizárva (bizonyítva).** `_sampleIndexFor` és
  `_boundedSampleIndex` minden indexet `math.min(..., length-1)`-gyel klampol
  (`:166-172`, `:205-206`), és a `durationToSampleIndex` monoton nem csökkenő,
  így a `[start, end]` loop-tartomány mindig `start ≤ end`, mindkettő
  `[0, length-1]`-ben. Az üres puffer ág korábban visszatér zero-dinamikával
  (`:192`), így a loop csak nem-üres pufferen fut.
- **Integer overflow — nincs realisztikus trigger.** A `durationToSampleIndex`
  (`preprocessed_audio.dart:66`, **pre-existing E06-R08, nem ez a diff**)
  képlete `((micros+1)*sampleRate−1) ~/ 1e6`. A probe megerősítette: a túlcsordulási
  határ 48 kHz-en ~9,08e18 ≈ **~6 év folyamatos audio**; a builder ennek legfeljebb
  `clip + 45 ms`-ot ad át. 64-bites mobil célon (a release-APK gate platformja)
  nincs valós kockázat.

**Bizonyíték (probe [D]):** `durationToSampleIndex(0)=0`, `(10s)=480000`,
`(6év micros+1)*48000 = 9082368000000048000` (> 0, azaz int64-en belül).

*Következtetés:* a brief által megnevezett memória/DoS/overflow felület
**reprodukálhatóan nem sebezhető** — a fix ablakok + puffer-újrafelhasználás
kifejezetten DoS-rezisztens tervezés (kontraszt az E06-R09-ben megjelölt
`Float64List(product(dims))` OOM-mintával).

### 2.2 Fail-closed viselkedés határeset-bemeneten (üres/negatív/NaN) → CLEAN (1 előre-mutató NOTE)

- **Üres `strums` lista** → üres `events` + üres `suppressedEvents`, nem dob
  (fedve: `event_timeline_builder_test.dart:214-217`). ✔ fail-safe.
- **Üres `originalSamples`** → `_dynamicsAt` zero-dinamikát ad (`:192`), az
  esemény `sampleIndex=0`-val épül. Nem dob, nem szivárog — degenerált, de
  kontrollált. (Teszt nem fedi; lásd NOTE-1.)
- **Negatív `legacy.time`** → `_sampleIndexFor` → `durationToSampleIndex`
  `if (duration.isNegative) throw` (`preprocessed_audio.dart:63-65`).
  **Fail-CLOSED** (elutasít dobással), de **elkapatlan** `ArgumentError`, ami
  kibukik a `build()`-ből. Reprodukálva (probe [D]:
  `durationToSampleIndex(-1ms) -> THROW ArgumentError`).
- **NaN/tartományon kívüli `legacy.confidence`** → a builder
  `_normalizedConfidence` (`:181-184`) `if (!value.isFinite) return 0`, majd
  `clamp(0,1)` — **fail-closed 0-ra**, NEM a nyers confidence. (Részletes
  jelentőség §2.3.)

**NOTE-1 (előre-mutató, R22):** a `LegacyStrumEvidence` (`legacy_evidence.dart:83-93`)
**nem** validálja `time ≥ 0`-t, és a `LegacyEvidence.durationFromSeconds`
(`:142-144`) negatív `timeSec`-ből negatív `Duration`-t képez. A mai V1
strum-idők nem-negatívak (frame-pozíció), így a shipping bemenet biztonságos,
DE a builder feltételezi ezt védekezés nélkül. *Failure scenario:* R22 egy
jövőbeli, negatív időt megengedő forrásból táplálja a buildert → elkapatlan
`ArgumentError` a `build()`-ből → hívó összeomlása. *Irány:* R22 a `build()`-et
`try/catch`-be zárja, VAGY a `LegacyStrumEvidence`/`AnalyzeResult` validáljon
`time ≥ 0`-t. (Fail-closed, tehát nem sebezhető-output; robusztussági NOTE.)

### 2.3 NaN / confidence-kezelés → az új mezők a R02-rést BEZÁRJÁK; a bázis-rés változatlan, de árnyékolva (1 NOTE)

Ez a kör az E06-R02 „NaN-fail-open a `< lo || > hi` idiómán" tanulságra
**helyesen reagál** az ÚJ mezőkön:

- `_validateUnitInterval` (`analysis_event.dart:114-118`) és
  `_validateNonNegativeFinite` (`:120-124`) az `!value.isFinite` idiómát
  használja → **elutasítja a NaN-t ÉS a `+Infinity`-t**. Reprodukálva (probe
  [A]): `attackStrength=NaN`, `localRms=NaN`, `directionConfidence=NaN`,
  `attackStrength=+Inf` mind **THROW ArgumentError**.
- A builder `_absolutePeak`/`_rms` eleve kihagyja a nem-finite mintákat
  (`:212`, `:222`), így NaN attack/RMS nem is keletkezik — a validáció
  defense-in-depth.
- A builder `_normalizedConfidence` (`:181-184`) az `isFinite`-őrt a `clamp`
  **elé** teszi. Ez lényeges: a probe megerősítette, hogy Dartban
  `double.nan.clamp(0,1) == 1.0` — ha a builder csak `clamp`-elt volna,
  **NaN → 1,0 (maximális, hamis confidence)** lett volna. Az `isFinite`-előőr
  miatt **NaN → 0** (fail-closed). ✔ §5.5/ADR 0179 tiszteletben tartva.

**NOTE-2 (pre-existing E06-R02, nem ez a kör regressziója):** a bázis
`AnalysisEvent.confidence` ellenőrzése (`analysis_event.dart:11`,
`if (confidence < 0 || confidence > 1)`) **változatlan**, és **NaN-re
fail-open** — reprodukálva (probe [B]: `OnsetEvent(confidence: NaN)` →
**NO THROW**). Ezt a builder árnyékolja (mindig előre-normalizál), így a mai
körben nem kihasználható. *Failure scenario:* egy JÖVŐBELI, NEM builder-alapú
producer (pl. a codec decode-ja, amikor egyszer deszerializálja ezeket az
eseményeket) nyers NaN confidence-szel konstruál → hamis „nem gyenge"
confidence a downstream `if (confidence < threshold)` ágban (`NaN < t` false →
nem szűr). *Irány:* a bázis check javítása `!confidence.isFinite ||`-ra (az
in-diff testvérek mintája) — az E06-R02 review már MINOR-ként jelölte; itt csak
megerősítem, hogy R10 nem javította és nem is rontotta.

### 2.4 Event ID determinizmus és info-szivárgás → CLEAN (1 előre-mutató NOTE)

- **Determinisztikus, nincs entrópia-szivárgás:** `EventId._build`
  (`event_id.dart:19-29`) tisztán `'$runId:$type:$sampleIndex'`; `type`
  rögzített literál (`'onset'`/`'strum'`), **nem** `hashCode`/`Random`/globális
  számláló (§5 #3 betartva). A `sampleIndex` csak temporális pozíció (nem
  audio-tartalom, az `event.time` már úgyis hordozza) — nincs többlet-szivárgás.
- **Fail-closed a rossz bemeneten:** üres/whitespace `runId` → `throw`
  (`:24`); negatív `sampleIndex` → `throw` (`:25-27`). Reprodukálva (probe [E]).
- **A `runId` mai forrása biztonságos gépi token:** `analysis_recorder.dart:209-211`
  → `'recording-${micros}-${count}'` (időbélyeg + számláló), nincs benne
  untrusted adat, `:` vagy vezérlőkarakter.

**NOTE-3 (előre-mutató, R22):** a `runId` **verbatim, karakterkészlet-korlát
nélkül** interpolálódik az ID-be (`:28`). Reprodukálva (probe [E]): egy `:`-t
tartalmazó `runId` → `a:b:c:onset:9` (kétértelmű, ha egy jövőbeli kör `:` mentén
parse-olja az ID-t); egy újsort tartalmazó `runId` → `run\nINJECT:strum:1`
(verbatim). *Failure scenario:* ha R22 a `runId`-t untrusted forrásból
(importált fájlnév, felhasználói szöveg) származtatja EGY egyedi
`_runIdGenerator`-on át, ÉS az ID-t később logolják vagy `:`-mentén parse-olják
→ log-injekció / display-spoofing / parse-kétértelműség. *Irány:* R22-ben a
`runId` maradjon gépi token, VAGY az `EventId` tiltsa a `:`/vezérlőkaraktert.
Ma latens (a `runId` gépi token, unwired).

### 2.5 `confidenceSource` false-confidence őr → 1 MINOR (latens §5 #5 mag)

**MINOR-1 — `analysis_event.dart:103-112`, `:126-130` (§5 #5, ADR 0179):**
az `EventConfidenceSources.isKnown` (`:108-111`) allowlistje **tartalmazza a
`'calibrated'`-et**, és a `_validateConfidenceSource` (`:126-130`) csak az
*ismertséget* ellenőrzi, a *kalibráltság igazságát* nem. A konstruktor tehát
elfogad egy `confidenceSource: 'calibrated'`-nek jelölt eseményt tetszőleges
nyers `confidence`-szel — reprodukálva (probe [C]:
`OnsetEvent(confidenceSource: calibrated)` → **NO THROW**; csak az ismeretlen
`'totally-made-up'` dob).

- **Miért nem MAJOR, és miért PASS:** a kör SAJÁT buildere ezt **bizonyíthatóan
  nem** produkálja — a `confidenceSource` switch (`event_timeline_builder.dart:127-131`)
  a 3-értékű `StrumRefinerSource` enumon (`none`/`heuristic`/`crnn`,
  `legacy_evidence.dart:46`) **kimerítő**, és sosem képez `calibrated`-et. Az
  őr-teszt (`analysis_event_timeline_property_test.dart:56-72`,
  `event_timeline_builder_test.dart:38-39`) a **builder KIMENETÉT** méri
  (`isNot(calibrated)`), nem a típus-szintű elutasítást — így a
  konstruktor-permisszivitás **jelenleg tesztelten kívül van**, és egyetlen
  in-round acceptance cellát sem ver pirosra.
- **Failure scenario (R19):** amikor az R19 bekötit a kalibrációt, egy hiba,
  ami nyers confidence-t `'calibrated'`-ként címkéz, **nem akad fenn** a
  típus-rendszeren → gyenge/kalibrálatlan érték „kalibrált biztos állításként"
  jelenne meg (§5 #5 sértés). *Irány:* R19-ben a `'calibrated'` címkét
  KIZÁRÓLAG a tényleges kalibrációs stage állíthassa be (invariáns-teszt a
  producer oldalán), mert a value-típus ezt nem tudja kikényszeríteni.

Osztályozás: **MINOR** (latens, reprodukálható false-confidence mag; nem
határsértés, mert a kör kimenete tiszta és nincs éles fogyasztó).

### 2.6 Adatszivárgás / naplózás / titkok → CLEAN

- **Nincs log/print/Logger/toString sink** a három érintett fájlban (grep NONE).
  Nincs custom `toString` → az alapértelmezett csak a típusnevet adja.
- **A `fallbackReason` nem szivárogtat:** a builder a
  `provenance.fallbackReason`-t adja tovább (`event_timeline_builder.dart:142,155`),
  ami az E06-R09 szerint mindig `null` vagy a fix konstans
  `'candidate-matches-heuristic-baseline'` — sosem nyers kivétel-szöveg vagy
  audio. A `_validateFallbackReason` (`:132-136`) csak üres stringre dob (a
  hibaüzenet a whitespace-értéket tartalmazza, nem érzékeny adatot).
- **Kivétel-üzenetek csak skalárt/enum-stringet hordoznak:** `runId` (gépi
  token), `sampleIndex`/confidence (számok), `confidenceSource` (enum-string),
  `onsetEventId` (a determinisztikus ID). **Nyers PCM-mintaérték SEHOL nem
  kerül üzenetbe, ID-be vagy mezőbe.**
- **Nyers audio (§5 #1/#3):** az `attackStrength`/`localRms` **aggregált
  DSP-skalárok** (egyetlen peak, ill. RMS eseményenként), nem nyers audio (=
  a PCM-folyam/felvétel) — ugyanaz a mérce, mint az E06-R07 signal-quality
  metrikáknál. Ráadásul semmi nem hagyja el az eszközt (unwired, nincs
  hálózat, a codec ebben a körben nem is szerializálja őket — OD-03). Nincs
  §5 sértés.
- **Titkok:** a három fájl string-literáljai `'onset'`/`'strum'`/`'heuristic'`/
  `'crnn'`/`'calibrated'` + doc-comment — nincs kulcs/token/jelszó. A
  fixture-ök (`Duration`/`double` konstansok) valóban fake-ek, nem valós
  értékek. A `check_secrets` kapu az implementer gate-jén zöld volt (brief §10).

### 2.7 Hálózat / mikrofon / consent / cross-feature import → CLEAN

- **Nincs `Dio`/HTTP, nincs mikrofon-hozzáférés, nincs új platform-permission.**
  A builder egy már-elkészült `PreprocessedAudio` puffert fogyaszt; nem nyit
  mikrofont, nem hív hálózatot. Nincs consent-kapu szükséglete, mert semmi nem
  hagyja el az eszközt. Az offline alapélmény érintetlen (§5 #2/#4).
- **Cross-feature import fegyelem:** a builder importjai `dart:math` +
  `core/music/strum.dart` (megengedett core) + kizárólag `audio_analysis`-on
  belüli relatív importok. **Nincs** közvetlen `features/analyze/**` vagy
  `features/live/**` import. Az architektúra-allowlist (`tool/check_architecture.dart`)
  **bitre változatlan** (`git diff` üres).

**NOTE-4 (előre-mutató, latens — az E06-R09 NOTE-3 folytatása):** a
`public.dart` mostantól re-exportálja a buildert, ami tranzitívan a
`legacy_evidence.dart` → `analyze/public.dart` (Riverpod/`rootBundle`) láncon át
Flutter ellen fordul. A builder SAJÁT kódja csak tiszta value-típusokat és a
`core/music` enumot használja, tehát **framework-szimbólum nem lép be a
domain-logikába**; latens rés egy JÖVŐBELI, ugyanezen a barrelen keresztül
véletlenül framework-típust behúzó domain-fájlra. A barrel szélessége az
`analyze` feature terve, nem ennek a körnek a hibája.

### 2.8 Prompt-injection / AI-provider / dev-rendszer önvédelem → N/A + docs scope-szűkítő

- **Az AI-provider/prompt-injection felület N/A ebben a körben:** nincs
  felhő-provider, nincs prompt, nincs tool-calling, nincs tudásbázis-chunk,
  nincs felhasználói üzenet vagy provider-válasz. Tisztán DSP/domain kód. Külső
  tartalom (dal-fájl, MusicXML/MIDI, provider-válasz) nem folyik promptba.
- **Docs önvédelem (AGENTS.md §5.1, ADR 0138):** az ADR 0228 és a round-brief
  **scope-SZŰKÍTŐ**: STOP-protokoll, tiltott zóna felsorolás (`brief:248-249`),
  „additív/hátrafelé kompatibilis" kényszer (§5 pont 7), „a self-heal
  jogosultság kizárólag a HALT-olt körre szól". **Nincs** rejtett instrukció
  vagy jövőbeli-agent-célzó scope-tágító direktíva. A §6.1 „Valódi-sértés
  próba" (dedup ideiglenes kiszedése → RED → visszaállítás) legitim
  teszt-minőségi önellenőrzés, nem injection.

---

## 3. Megállapítások összegzés

| Súlyosság | Db | Tételek |
|---|---|---|
| CRITICAL | 0 | — |
| BLOCKER | 0 | — |
| MAJOR | 0 | — |
| MINOR | 1 | **MINOR-1:** a konstruktor elfogadja a `confidenceSource:'calibrated'`-et kalibráltság-bizonyíték nélkül (latens §5 #5 mag, R19) — `analysis_event.dart:103-112,126-130` |
| NOTE | 5 | N1: negatív/érvénytelen `legacy.time` → elkapatlan throw (fail-closed, R22); N2: bázis `confidence` NaN-fail-open (pre-existing E06-R02, builder árnyékolja); N3: `EventId` `runId` verbatim, nincs `:`/vezérlő-karakter őr (R22); N4: barrel Flutter-tranzitivitás (latens); N5: `durationToSampleIndex` overflow-headroom (~6 év@48kHz, pre-existing E06-R08, nincs valós trigger) |

---

## 4. Verdikt

**PASS a security scope-ban.** Nincs nyitott CRITICAL/BLOCKER/MAJOR lelet. A
kör nem sért nem-tárgyalható termékhatárt: nincs hálózat, mikrofon, consent-kapu
vagy nyers-audio kiszivárgás; a titok-, napló- és cross-feature-import felület
tiszta; az architektúra-allowlist változatlan.

A brief által kiemelt fő aggály (memória/DoS nagyon hosszú klipeken, integer
overflow a sample-index számításban) **reprodukálhatóan nem áll fenn** — a fix
méretű attack/RMS ablakok, a PCM-puffer újrafelhasználása (nincs másolat), a
klampolt indexhatárok és a ~6 éves overflow-headroom kifejezetten
DoS-rezisztens. A NaN-kezelés az ÚJ mezőkön az `isFinite`-idiómával **bezárja**
az E06-R02 rést, a builder confidence-normalizálása pedig helyesen
`NaN → 0`-t ad (nem a `clamp`-buktató `NaN → 1`-et).

Az egyetlen MINOR (`confidenceSource:'calibrated'` konstruktor-permisszivitás)
és mind az öt NOTE **latens/előre-mutató** — a teljes `audio_analysis` V2
feature unwired (`audioAnalysisV2Enabled = false`, nincs `lib/` fogyasztó). A
merge security-oldalról **nem blokkolt**. Az R19 (kalibráció) briefjében a
**MINOR-1** (a `'calibrated'` címkét kizárólag a kalibrációs stage állíthatja),
az R22 (wiring) briefjében az **N1** (negatív-idő pre-validáció/try-catch) és
**N3** (`runId` karakterkészlet) kifejezetten követendő.

---

**Releváns fájlok (abszolút útvonalak, az izolált klónban):**
- `/tmp/review-e06-r10-security/lib/features/audio_analysis/engine/events/event_timeline_builder.dart`
- `/tmp/review-e06-r10-security/lib/features/audio_analysis/domain/events/event_id.dart`
- `/tmp/review-e06-r10-security/lib/features/audio_analysis/domain/analysis_event.dart`
- `/tmp/review-e06-r10-security/lib/features/audio_analysis/domain/preprocessed_audio.dart` (pre-existing, fogyasztott)
- `/tmp/review-e06-r10-security/lib/features/audio_analysis/engine/legacy/legacy_evidence.dart` (pre-existing, fogyasztott)
- Probe: `/tmp/r10probe/probe.dart` (a [A]–[E] reprodukciók)
