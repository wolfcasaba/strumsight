# E06-R11 — Security / adatvédelmi / prompt-injection review

- **Kör:** E06-R11 — Frame-szintű chord-evidence, verziózott szegmens-összeállítás, DSP↔ML decoder-provenance
- **Branch:** `codex/e06-r11-chord-evidence-segmentation-provenance`
- **Diff:** `git diff dd732c4f..0d350f7a` (izolált klón: `/tmp/review-e06-r11`; a `244846bc` review-doksi commitot figyelmen kívül hagyva, csak a KÓD)
- **Reviewer:** Claude (dedikált security-reviewer, READ-ONLY — production kód nem módosult)
- **Dátum:** 2026-08-12
- **Brief kockázat:** `risk = "high"` → kötelező dedikált security review (AGENTS.md router)
- **Verdikt:** **PASS with NOTEs** — 0 CRITICAL · 0 BLOCKER · 0 MAJOR · **1 MINOR** · 4 NOTE (mind latens/unwired, jövőbeli fogyasztó-körre)

> **Nincs BLOCKER/CRITICAL/MAJOR lelet.** A kör nem sért nem-tárgyalható
> termékhatárt (AGENTS.md §5): nincs hálózati hívás, nincs AI-/LLM-provider,
> nincs nyers-audio-kezelés, nincs mic-ownership, nincs perzisztencia-változás,
> nincs új dependency/asset/platform-permission, nincs log/print sink. A teljes
> `ChordSegmentAssembler` / `ChordLabelNormalizer` / `ChordFrameEvidence` felület
> és az `analysisExperimentalFusionEnabled` flag **bekötetlen** (egyetlen `lib/`
> fogyasztó sincs a definíciókon kívül). Minden lelet ezért latens, jövőbeli
> hardening — de az egyik (MINOR-1, assert-only validáció) release-ben bizonyítottan
> ledobódik, ezért kifejezetten megjelölöm.

---

## 1. Vizsgált diff és módszer

`git diff --stat dd732c4f..0d350f7a` (security-releváns felület):

| Fájl | Állapot |
|---|---|
| `lib/features/audio_analysis/domain/harmony/chord_frame_evidence.dart` | ÚJ (103 sor) |
| `lib/features/audio_analysis/engine/harmony/chord_segment_assembler.dart` | ÚJ (218 sor) |
| `lib/features/audio_analysis/engine/harmony/chord_label_normalizer.dart` | ÚJ (32 sor) |
| `lib/features/audio_analysis/engine/harmony/decoder_source.dart` | ÚJ (4 sor, re-export) |
| `lib/features/audio_analysis/domain/analysis_segment.dart` | MÓDOSÍTOTT (additív: `id`/`source`/`confidenceSource`/`modelManifestId` + 2 enum) |
| `lib/app/config/feature_flags.dart` | MÓDOSÍTOTT (additív: `analysisExperimentalFusionEnabled`, default false) |
| `lib/features/audio_analysis/public.dart` | +4 export |
| `lib/features/audio_analysis/data/analysis_document_codec.dart` | **VÁLTOZATLAN** (nincs a diffben) |
| `tool/check_architecture.dart`, `pubspec.yaml`, `assets/**`, `android/**`, `ios/**` | **VÁLTOZATLAN** (nincs a diffben) |
| 4 teszt (`engine/*`, `property/*`, `app/feature_flags_test.dart`) | ÚJ/bővített |

**Reprodukálható alap-tények (mind lefuttatva a klónban):**

- **Unwired:** `grep -rn "ChordSegmentAssembler|\.fuse(|ChordLabelNormalizer|ChordFrameEvidence|analysisExperimentalFusionEnabled" lib/` → a definíciókon és a `feature_flags.dart` self-referencián kívül **nincs production fogyasztó**. (A `tutor_orchestrator.dart:260` `contextAssembler.assemble` egy MÁSIK, AI-tutor context-assembler — nem a `ChordSegmentAssembler`.)
- **Nincs sink:** `grep "print(|debugPrint|log(|Logger|dio|Dio|http|Http|openai|anthropic|provider|File(|Socket|Process"` a négy új harmony fájlban → **NONE**. A módosított domain-fájlokon **nincs** `toJson/toMap/toString/jsonEncode` → az érték-objektumoknak csak az alapértelmezett `Object.toString`-je van (típusnév).
- **Nincs perzisztencia-sink:** a `_chordSegmentToJson` (`analysis_document_codec.dart:371-377`, **változatlan**) kizárólag `startUs/endUs/confidence/label`-t szerializál — az új `id/source/confidenceSource/modelManifestId` mezők **NEM** kerülnek a perzisztált dokumentumba. (ADR 0229 6. pont: „a top-k frame evidence nem kerül automatikusan a perzisztált dokumentumba; a codec változatlan”.)
- **Pure-Dart probe** (`/tmp/e06r11_probe/`, `dart` futtatva a valós R11 kódon `file://` importtal): a lenti 2.1–2.6 leletek reprodukálva, `--enable-asserts` és `--no-enable-asserts` mellett is.

---

## 2. A brief nyolc vizsgálati pontja — leletek bizonyítékkal

### 2.1 Input-validáció / DoS-felület (brief #1) → nagyrészt CLEAN, 1 latens NOTE

**A fő evidence-út fail-closed, valódi `throw`-val (release-safe).** A
`ChordFrameEvidence._validateProbability` (`chord_frame_evidence.dart:98-102`)
`!value.isFinite || value < 0 || value > 1` ágon **`ArgumentError`-t dob** — a
NaN-t és az ∞-t is elutasítja (a range-only check tipikus NaN-fail-open hibáját
**bezárja**). A `_` konstruktor (`:31-47`) negatív `time`-ra, üres `topLabel`-re
és a `derived`-invariáns sértésére szintén valódi `throw`. Az assembler
`assemble` (`chord_segment_assembler.dart:31-43`) és `_validateFrames` (`:99-113`)
negatív `clipDuration`/policy-időre, klip-en-túli és nem-monoton frame-időre
valódi `throw`. **Probe-bizonyíték** (`--no-enable-asserts` mellett is dob):

```
NaN topConfidence   -> ArgumentError: must be in [0, 1]
infinity tonalness  -> ArgumentError: must be in [0, 1]
confidence 1.5 (>1) -> ArgumentError: must be in [0, 1]
negative time       -> ArgumentError (time)
frame.time > clip   -> ArgumentError: outside clip
```

**Nincs végtelen ciklus.** A `_mergeShortSegments` `while` (`:122-136`) minden
iterációban vagy növeli az indexet, vagy `removeAt`-tal csökkenti a hosszt →
terminál; a `segments.length == 1` és `index > 0` guardok az index-0 ágat
`length >= 2`-re szűkítik (nincs out-of-bounds).

**NOTE-1 (latens, O(S²) merge — csak opt-in policy + jövőbeli hívó esetén):** a
`_mergeShortSegments` `removeAt`-ot hív egy ciklusban (`:129`,`:133`) → **O(S²)**
a szegmensszámban. Probe (valós kód):

```
N=5000  no-merge=30ms  opt-in-merge=91ms
N=10000 no-merge=18ms  opt-in-merge=445ms
N=20000 no-merge=24ms  opt-in-merge=962ms
N=40000 no-merge=44ms  opt-in-merge=13135ms   ← ~13 mp
```

*Failure scenario:* egy jövőbeli hívó (a) ~40k+ frame-et ad, amiből minden
szomszédos frame más címke (⇒ frame-enként egy szegmens), ÉS (b) pozitív
`minimumSegment`/`mergeTransientSegments` policyt választ → ~13 mp CPU-blokk egy
klipen (event-loop stall). *Miért csak NOTE:* az **alapértelmezett** policy
`minimumSegment = Duration.zero` → a `mergeThreshold > Duration.zero` guard
(`:76`) a teljes merge-ágat **kihagyja** (a `no-merge` oszlop O(N), lapos). A
feature **unwired**, és a property-teszt is az alap policyt hívja
(`analysis_chord_segment_property_test.dart:40-43`) → a kvadratikus ág
**teszteletlen**. *Irány:* a merge-t egyetlen bejáráson épített új listával
(nem `removeAt`-tal) kell megvalósítani. **Gate-feltétel:** ha egy jövőbeli kör
ezt untrusted/hosszú importált audióra köti be pozitív merge-policyval,
**MAJOR-ra átsorolandó** és javítandó a bekötés előtt.

### 2.2 ReDoS a normalizer regexében (brief #2) → CLEAN (nem lelet)

A `ChordLabelNormalizer.normalize` regexe `^([A-G](?:#|b)?)(.*)$`
(`chord_label_normalizer.dart:18`). **Nincs beágyazott/kétértelmű kvantor**
(`[A-G]` fix 1 kar; `(?:#|b)?` korlátos; `(.*)` egyetlen mohó, `$`-hoz kötött) →
lineáris illesztés, katasztrofális backtracking kizárva. **Probe-bizonyíték**
(2 millió karakteres adverzariális bemenetek):

```
14 ms  match=true   [A + 2,000,000 '#']
12 ms  match=true   [A + 2,000,000 'b']
 0 ms  match=false  [nem-chord prefix + 2,000,000 'x']
12 ms  match=true   [alternáló '#b' × 1,000,000]
 0 ms  match=false  [belső-newline + 1,000,000 '#']
```

Minden eset ≤14 ms 2M karakteren → **nincs ReDoS**. (Megjegyzés: belső `\n`-t
tartalmazó címke nem illeszkedik → `trimmed` visszaadva változatlanul — lásd
NOTE-2.)

### 2.3 `decoder_source.dart` re-export + kettős export (brief #3) → CLEAN (nem lelet)

A `public.dart` a `DecoderSource`-ot két úton exportálja: közvetlenül a
`domain/analysis_segment.dart`-on (`:23`) és a `engine/harmony/decoder_source.dart`
re-exporton (`:34`, `export '../../domain/analysis_segment.dart' show DecoderSource`).
Mivel **ugyanaz az egyetlen deklaráció** kerül ki mindkét úton (nem két külön
azonos nevű típus), a Dart export-szabályok szerint ez **nem ütközés** — fordul,
és a fogyasztó ugyanazt az enumot kapja. **Nincs valódi kockázat**, csak
redundancia (a round gate-jének fordítania kellett hozzá). Az indoklás legit: a
provenance domain-érték, hogy a domain-szegmens ne függjön az engine-től.

### 2.4 `modelManifestId` log/serialize szivárgás (brief #4) → CLEAN

- **Nincs szerializáló sink ebben a körben:** a codec változatlan és csak
  `start/end/confidence/label`-t ment (2.1 fenti bizonyíték). A `modelManifestId`
  (`String?`, `chord_frame_evidence.dart:96`, `analysis_segment.dart:49`)
  **nem** kerül perzisztálásba, logba vagy `toString`-be.
- **Nem titok-jellegű:** a repóban a `modelManifestId` szándékolt érték-mintája
  `'strum_crnn.bin@SSML-v1'` (`analysis_provenance_builder.dart:56`) — model-fájl
  + verziócímke, **nem secret/token**. A típus-szerződés maga opak stringet
  tárol; egy jövőbeli hívónak sem nyit titok-utat, mert nincs olvasó sink.
- **Privacy-pozitívum:** a `topK` (top-k jelölt-valószínűségek) **soha nem
  perzisztálódik** (ADR 0229 3./6. pont) és az assembler sem olvassa
  (`toChordSegment` a `topConfidence`-t használja, nem a `topK`-t) → nincs
  „több ezer frame top-k adata a dokumentumban”.

### 2.5 Feature-flag boundary (brief #5) → CLEAN (fail-closed)

- `analysisExperimentalFusionEnabled` **default `false`** a konstruktorban
  (`feature_flags.dart:36`) ÉS **`forEnvironment` minden környezetben `false`-ra
  állítja** (`:83`, feltétel nélkül — nem `nonProd`-hoz kötött) → prod, staging,
  dev, lab mind OFF.
- **Nincs dart-define override:** `grep "fromEnvironment|hasEnvironment|
  Platform.environment"` a `feature_flags.dart`-ban → csak doc-komment-találatok,
  **nincs** `bool.fromEnvironment` a fusion-flaghez. Kényszerített bekapcsolás
  nem lehetséges (ADR 0220 „nincs dart-define a force-enable-hez”).
- **`fuse()` fail-closed:** `required bool enabled`, és `!enabled` ágon a
  **változatlan `dsp` objektumot adja vissza** — a probe `identical(offResult,
  dsp) == true`-t mért → bájtra parity, valódi no-op. `usesNetwork`
  (`:172`) változatlan (csak account/diagnostics).
- **Gépi őr bővítve:** `feature_flags_test.dart` mind az öt audio-flag OFF-ját
  állítja minden környezetben (`toString` contains `...FusionEnabled: false`) +
  equality-flip teszt.

### 2.6 Determinisztikus ID + label-injekció (brief #6) → latens NOTE

**NOTE-2 (előre-mutató, latens — nincs mai fogyasztó):** a `_defaultId`
(`analysis_segment.dart:51-52`) a címkét **szanitálás nélkül** interpolálja az
ID-be: `'chord-${startUs}-${endUs}-$label'`. A normalizer a nem-chord stringeket
**változatlanul** visszaadja (a regex nem illeszt → `return trimmed`,
`chord_label_normalizer.dart:19`). Probe (valós kód):

```
direct ctor id        = chord-0-1000000-../../../../etc/passwd
normalize('../../etc')= '../../etc'   (változatlanul átfolyik)
assembler id          = chord-0-1000000-'; DROP TABLE segments;--
```

*Failure scenario:* egy jövőbeli hívó a `ChordSegment.id`-t **fájlnévként /
DB-kulcsként / log-sorként** használja, és egy jövőbeli ML-decoder vagy import-út
tetszőleges (attacker-influenced) stringet ad `label`-ként → path-traversal
(`../../etc/passwd`) vagy injekció-alakú kulcs. *Miért csak NOTE:* **ma egyetlen
hívó sem** használja az `id`-t útként/kulcsként/logként (grep), és a `derived`
címke a V1 fix vokabulárumából jön. A normalizer nem-chord pass-through ága
**teszteletlen** (`chord_label_normalizer_test.dart` csak érvényes chordokat
fed). *Irány:* a `label`-komponenst szanitálni/hash-elni az ID-ben, VAGY
dokumentálni, hogy `id` NEM biztonságos útként/kulcsként — mielőtt bármely
storage/FS-fogyasztó bekötné.

### 2.7 Prompt-injection / AI-provider felület (brief #7) → CLEAN (megerősítve)

A kör **NEM** hív semmilyen LLM/AI-providert. A négy új harmony fájl és a
`feature_flags.dart` importja tisztán relatív, pure-Dart (`dart:core`
`Duration`/`ArgumentError`/`RegExp`) — `grep "openai|anthropic|dio|http|provider"`
→ **NONE**. Nincs külső tartalom, ami promptba kerülhetne; nincs tool-calling,
memória- vagy policy-módosítás. A brief/ADR scope-SZŰKÍTŐ (flag default-false,
V1-parity), nincs rejtett jövőbeli-agent-célzó direktíva.

### 2.8 Termékhatárok (brief #8, AGENTS.md §5) → CLEAN

- **Nyers audio / kamera-frame:** a kód kizárólag már-dekódolt chord-evidence-et
  (címke, confidence, `Duration`) dolgoz fel — **nincs PCM/audio-minta/frame**.
- **Mic-ownership / capture:** nincs recorder/capture-változás a diffben.
- **Secret logban/commitban:** nincs log/print sink; nincs titok-jellegű literál
  az új fájlokban; a `modelManifestId` verziócímke, nem secret (2.4). Nincs új
  fájl, ami kulcsot tartalmazna.
- **Offline alapélmény:** nincs hálózat; a flag OFF → az offline V1 út bájtra
  változatlan.
- **Gyenge confidence mint biztos állítás (§5.5):** ADR 0229 kimondottan tiltja a
  kész címkéből kitalált top-k/no-chord valószínűséget és a „kitalált 1.0”
  confidence-t (evidence nélkül 0.0). Ez §5.5-**pozitívum** — kivéve a MINOR-1
  latens magot lent.

---

## 3. MINOR lelet — FIXED

**Státusz: FIXED (`f3f34b2f`, javító kör #1).** A `const` konstruktor mindkét
`assert`-je valódi `if (...) throw ArgumentError(...)`-ra cserélve (a `const`
kulcsszó eltávolítva — Dart nyelvi korlát: const konstruktor teste nem
tartalmazhat futásidejű elágazást; a `ChordLabelCandidate(` sehol máshol nem
volt `const` kontextusban hívva, tehát ez nem tör hívót). Regressziós teszt
(`chord label candidates reject invalid values with ArgumentError`, 3 eset:
üres label, NaN confidence, 1.1 confidence) hozzáadva — `--enable-asserts`
NÉLKÜL is bizonyítottan dob, mert már nem assert-védett. Independent
re-verify: `flutter test test/features/audio_analysis/engine/
chord_segment_assembler_test.dart` → 13/13 zöld (12 eredeti + 1 új), izolált
`/tmp/review-e06-r11` klónban, `f3f34b2f`-en.

### MINOR-1 — `ChordLabelCandidate` validációja assert-only → release-ben ledobódik (latens false-confidence mag, §5.5)

**Fájl:sor:** `chord_frame_evidence.dart:8-13` (assertek a 9. és 10. soron).

A `ChordLabelCandidate` const konstruktora `assert(label != '')` és
`assert(confidence >= 0 && confidence <= 1)` — **kizárólag assert**, nincs
valódi `throw`. A release APK az asserteket **ledobja**, így éles buildben a
degenerált jelölt átmegy. **Probe-bizonyíték** (ugyanaz a valós kód, két mód):

```
--enable-asserts   (teszt):   NaN confidence -> _AssertionError (line 10)
--no-enable-asserts (release): NaN confidence -> NO-THROW
                               empty label    -> NO-THROW
                               confidence 9.0  -> NO-THROW
```

Ez éles kontraszt a **testvér** `ChordFrameEvidence`-szel, amely valódi
`throw`-t használ (`_validateProbability`, `:98-102`) és release-ben is dob.

*Failure scenario:* egy jövőbeli kör (R18/R29, Lab ML-decoder) `complete`
evidence-t gyárt `topK` jelöltekkel egy release buildben, és egy UI a jelölt
`confidence`-ét megjeleníti („2. legvalószínűbb: X%”). Egy `NaN`/`9.0`/üres-címke
jelölt **átmegy a validáción**, és a `NaN`/tartományon-kívüli érték biztos
állításként jelenhet meg → **§5.5-sértés** (gyenge/érvénytelen confidence mint
biztos). *Sértett szabály:* AGENTS.md §5 #5 (assert-strip a value-class
validációban — a korábbi körökben visszatérő minta).

*Miért MINOR és nem MAJOR/BLOCKER — latens:* ma **nincs fogyasztó**: (a) a `topK`
jelöltek `confidence`-ét **senki nem olvassa** (az assembler a `topConfidence`-t
használja); (b) a `topK` **soha nem perzisztálódik** (2.4); (c) az egyetlen út,
amit R11 gyárt (`derived`), **üres `topK`-t** kényszerít (`:39-46`, valódi
throw). Így éles hatás ma nincs — de a mag ott van, és a teszt (assertekkel fut)
strukturálisan **nem foghatja** a release-viselkedést.

*Javasolt javítás iránya:* a két `assert`-et cseréld valódi
`throw ArgumentError`-ra (a `ChordFrameEvidence._validateProbability` mintájára),
vagy validáld a `topK` elemeit a `_` konstruktorban `throw`-val — hogy a release
build is elutasítsa a NaN/tartományon-kívüli/üres jelöltet, mielőtt bármely
fogyasztó bekötné.

---

## 4. További megjegyzés

**NOTE-3 (pre-existing kontextus, nem R11-lelet):** a bázis `AnalysisSegment`
confidence-ellenőrzése `confidence < 0 || confidence > 1` (range-only, `isFinite`
nélkül) — a diff szerint **változatlan** (nem R11). R11 termelői viszont csak
**véges** confidence-t állítanak elő (`toChordSegment` a véges `topConfidence`
frame-súlyozott átlaga; `_fuseSegment` két `[0,1]` érték szorzata) → R11 **nem
vezet be** NaN-confidence utat a `ChordSegment`-be. Említve teljesség kedvéért; a
bázis range-only check higiéniája a codec-boundary (R21) körben nézendő.

**NOTE-4 (korrektség-átfedés, nem security):** a `_chordSegmentToJson` (változatlan
codec) az új provenance-mezőket (`source/confidenceSource/modelManifestId`)
**eldobja** encode-nál → round-trip-veszteséges. Security szempontból ez a
**biztonságosabb** (kevesebb perzisztált adat), és megfelel az ADR 0229 6.
pontnak — de a korrektség-reviewer nézze meg, hogy a provenance-veszteség szándékolt-e
a jelen körben (R21 storage-szerződés feladata).

---

## 5. Megállapítások összegzés

| Súlyosság | Db | Tételek |
|---|---|---|
| CRITICAL | 0 | — |
| BLOCKER | 0 | — |
| MAJOR | 0 | — |
| MINOR | 1 | `ChordLabelCandidate` assert-only validáció (release-strip, latens false-confidence mag, §5.5) |
| NOTE | 4 | O(S²) merge opt-in policyban (13 mp@40k, teszteletlen); `_defaultId` label→id szanitálatlan interpoláció; bázis confidence range-only (pre-existing); codec provenance-veszteség (korrektség-átfedés) |

**Titkok:** az új `lib/` fájlokban nincs kulcs/token/jelszó-szerű literál; a
`modelManifestId` szándékolt verziócímke (`strum_crnn.bin@SSML-v1`), nem secret;
nincs új fixture valós kulccsal. A gépi őr (`tool/ci/check_secrets.dart`) külön
fut a round gate-jében; szemantikailag ebben a diffben nincs titok-felület.

**Nem-leletek (bizonyítékkal zárva):** ReDoS (regex lineáris, ≤14 ms@2M kar);
NaN/∞/tartomány/negatív-idő a fő evidence-úton (valódi throw, release-safe);
flag default-off minden környezetben + nincs dart-define override; `fuse(off)`
bájtra parity (`identical`); nincs hálózat/provider/LLM/audio/mic/log sink; nincs
perzisztencia-változás (codec változatlan); nincs új dependency/asset/permission;
teljesen unwired.

---

## 6. Verdikt

**PASS with NOTEs a security scope-ban.** Nincs nyitott CRITICAL/BLOCKER/MAJOR
lelet, így a `risk = "high"` merge-kapu **security-oldalról nem blokkolt**. Az
egyetlen MINOR (assert-only `ChordLabelCandidate`) és a négy NOTE kivétel nélkül
**latens/unwired** — egyik sem érhető el ma futásidőben (a feature bekötetlen, a
flag OFF minden környezetben, a merge-ág és a label-pass-through teszteletlen és
hívó nélküli). A javasolt hardening a jövőbeli fogyasztó-körre (R18/R21/R29)
irányul; kifejezetten követendő az MINOR-1 (assert→throw), a NOTE-1 (O(S²) merge,
MAJOR-ra átsorolandó ha untrusted hosszú audióra kötik) és a NOTE-2 (label→id
szanitáció, mielőtt bármely FS/DB-fogyasztó bekötné).
