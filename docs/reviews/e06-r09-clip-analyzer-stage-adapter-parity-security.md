# E06-R09 — Security / adatvédelmi / prompt-injection review

- **Kör:** E06-R09 — V1 `ClipAnalyzer` bekötése V2 stage-adapterként (parity)
- **Branch:** `codex/e06-r09-clip-analyzer-stage-adapter-parity`
- **Diff:** `git diff 71b158b3..HEAD` (izolált klón: `/tmp/security-review-e06-r09-retry`)
- **Reviewer:** Claude (dedikált security-reviewer, READ-ONLY — kód nem módosult)
- **Dátum:** 2026-08-12
- **Brief kockázat:** `risk = "high"` → kötelező dedikált security review
- **Verdikt:** **PASS** — 0 CRITICAL · 0 BLOCKER · 0 MAJOR · 0 MINOR · 5 NOTE (mind előre-mutató, az R22 wiring-körre)

> **Nincs BLOCKER/CRITICAL lelet.** A kör nem sért nem-tárgyalható termékhatárt
> (AGENTS.md §5), nem vezet be titok-szivárgást, consent-megkerülést,
> path-traversalt vagy RCE-t. A teljes `audio_analysis` V2 feature — beleértve
> ezt az adaptert — **még nincs bekötve** (nincs `lib/` fogyasztó), így minden
> megjegyzés a jövőbeli R22 wiring-körre irányuló hardening.

---

## 1. Vizsgált diff és módszer

`git diff --stat 71b158b3..HEAD` (csak a security-releváns felület):

| Fájl | Állapot |
|---|---|
| `lib/features/audio_analysis/engine/legacy/legacy_evidence.dart` | ÚJ (145 sor) |
| `lib/features/audio_analysis/engine/legacy/clip_analyzer_stage.dart` | ÚJ (111 sor) |
| `lib/features/audio_analysis/engine/analysis_provenance_builder.dart` | ÚJ (84 sor) |
| `lib/features/audio_analysis/public.dart` | +3 export |
| `tool/check_architecture.dart` | **VÁLTOZATLAN** (`git diff` üres) |
| 4 teszt (`test/features/audio_analysis/engine/*`, `test/property/*`, `test/tooling/*`) | ÚJ |
| `docs/adr/0226-*.md`, `docs/rounds/e06-r09-*.md` | ÚJ |

A V1 `ClipAnalyzer` (`lib/features/analyze/engine/clip_analyzer.dart`, 241 sor) és
a `runClipAnalysis` belépő (`lib/features/analyze/providers/analyze_providers.dart`)
ebben a körben **nem módosult** — a diff kizárólag `analyze/public.dart`-on át hívja őket.

**Reprodukálható alap-tények (mind lefuttatva a klónban):**
- `tool/check_architecture.dart` diffje **üres** → az allowlist bitre változatlan.
- `grep -rn` a hat új szimbólumra `lib/`-ben → **nincs production fogyasztó** a
  hat új fájlon kívül; `audio_analysis/public.dart`-ot **semmi nem importálja**
  `lib/`-ben → a feature teljesen unwired.
- `grep -nE 'print\(|log|Logger|toString|debugPrint|stderr|stdout|developer\.'`
  a három új `lib/` fájlon → **NONE**.
- Immutability copy-szemantika reprodukálva (`/tmp/imm_probe.dart`, `dart` futtatva):
  `List.unmodifiable` = másolat + írásra dob; `Uint8List.fromList` = másolat
  store-nál és getter-olvasásnál is.

---

## 2. A brief öt vizsgálati pontja — leletek bizonyítékkal

### 2.1 Fájl-olvasás / asset-kezelés — CRNN-súly bemeneti út → CLEAN (1 előre-mutató NOTE)

`ClipAnalyzerStage.run` (`clip_analyzer_stage.dart:30-37`) az
`input.strumRefinerWeights` (`Uint8List?`) értéket **változtatás nélkül** adja
tovább a `runClipAnalysis((samples, sampleRate, weights, false, null))` belépőnek.

- **Nincs új, ellenőrizetlen untrusted forrás.** A `LegacyClipAnalyzerInput`-ot és
  a stage-et **egyetlen production kód sem hozza létre** (grep: csak a definíciók
  + tesztek). A `strumRefinerWeights` egyetlen production betöltője a bundle-elt,
  megbízható `assets/ml/strum_crnn.bin` (`analyze_providers.dart:85`, `rootBundle`).
- **Crash-safe a V1 oldalon (változatlan kód):** `runClipAnalysis`
  (`analyze_providers.dart:46-52`) a `CrnnStrumNet.parse`-ot `try { } catch (_)`
  ágba zárja → bármely rossz bájtsorozat (`FormatException`/`RangeError`) →
  `crnn = null` → heurisztikus címkék, **sosem bukik el egy analyze**. Az adapter
  tehát nem vezet be új összeomlási/parse-felületet: a V1 fail-safe fallbackra támaszkodik.
- **Az adapter maga nem ad méret/formátum-validációt**, de erre a körben nincs is
  szükség (unwired + a parse crash-safe + a szándékolt forrás a bundle-elt asset).

**NOTE-1 (előre-mutató, R22 wiring):** `CrnnStrumNet.parse`
(`crnn_strum_net.dart:64-66`, **változatlan**) a fejléc `dims` mezőiből számolt
`n = product(dims)` méretű `Float64List(n)`-t allokál. Adversariális (nem bundle-elt)
súlyokból ez elvi OOM-ot okozhat. A shipping útvonal ezt `compute()` izolátumban
futtatja (`analyze_providers.dart:114`), de az **adapter szinkron** hívja a
`runClipAnalysis`-t (`clip_analyzer_stage.dart:31`) — így ha egy jövőbeli kör
nem-bundle-elt forrásból ad súlyt, az izolátum-konténment eltűnik.
*Failure scenario:* R22 a `strumRefinerWeights`-et felhasználó-importált fájlból
tölti be → craftelt `dims` → 2 GB allokáció a hívó izolátumon → app-crash.
*Irány:* R22-ben CSAK a bundle-elt asset kerüljön ide, VAGY méret/formátum
pre-validáció + izolátum/timeout, ha nem-bundle-elt forrás valaha bevezetésre kerül.
Nem lelet ez ellen a kör ellen (unwired + V1 érintetlen + szándékolt forrás = bundle).

### 2.2 Memória / immutability → CLOSED (1 teszt-hézag NOTE)

Minden visszaadott gyűjtemény immutable, defenzív másolattal; **nem szökik ki
mutable referencia**:

- `samples`: `List<double>.unmodifiable(samples)` (`legacy_evidence.dart:18`) —
  másolat (a hívó eredeti listájának utólagos mutációja nem szivárog be) és írásra dob.
- `_strumRefinerWeights`: defenzív másolat **store-nál** (`Uint8List.fromList`,
  `:19-21`) **és getter-olvasásnál** (`:40-42`). A getter minden hívásra új
  másolatot ad → a hívó nem tud belenyúlni a belső állapotba.
- `chords`/`strums` (`:104-105`), `LegacyClipAnalyzerCall.modelManifestIds`
  (`:53`), `LegacyAnalyzerProvenance.modelManifestIds`
  (`analysis_provenance_builder.dart:15`): mind `List.unmodifiable`.
- Elem-típusok (`LegacyChordEvidence`, `LegacyStrumEvidence`) `final class` + `const`
  konstruktor + csupa `final` mező (`String`/`Duration`/`StrumDirection`/`double`) → immutable.

Bizonyíték: `/tmp/imm_probe.dart` reprodukálta a copy-szemantikát; a
`clip_analyzer_stage_test.dart:39-52` már ma is állítja, hogy `chords.add(...)`
és `modelManifestIds.add(...)` `UnsupportedError`-t dob.

**NOTE-2 (teszt-hézag, nem kód-hiba):** a `Uint8List` getter defenzív másolata
(`:40-42`) HELYES, de nincs rá közvetlen assert (egy teszt sem mutálja a
visszaadott `strumRefinerWeights`-et és ellenőrzi a belső állapotot). A kód
korrekt; csak a regressziós lefedettség hiányzik.

### 2.3 Adatszivárgás / naplózás → CLEAN

- **Nincs log/print/logger/toString sink** a három új fájlban (grep: NONE). Nincs
  custom `toString` → az alapértelmezett `Object.toString` csak a típusnevet adja.
- **`fallbackReason` mindig `null` vagy a fix, névvel ellátott konstans**
  `'candidate-matches-heuristic-baseline'` (`analysis_provenance_builder.dart:64-65`);
  egyetlen értékadási helye `clip_analyzer_stage.dart:75-77`. **Sosem** tartalmaz
  nyers kivétel-szöveget vagy audio-adatot — a fallback-detektálás nem is
  catch-ből, hanem a candidate↔baseline strum-lista összevetéséből származik
  (`clip_analyzer_stage.dart:74`, `_sameStrumLabelsAndConfidence`).
- **Kivétel-szövegek csak konfig-skalárokat tartalmaznak**, nem audiót/súlyt:
  `ArgumentError.value(sampleRate, ...)` (`legacy_evidence.dart:23`, int),
  `ArgumentError.value(bassWeight, ...)` (`analysis_provenance_builder.dart:20`,
  a fix 0.35 konstans). PCM vagy súly-bájt sehol nem kerül üzenetbe.
- `modelManifestId = 'strum_crnn.bin@SSML-v1'` szándékolt verzió-címke, nem titok.

### 2.4 Cross-feature import-határ → CLEAN (1 barrel-szélesség NOTE)

- **`tool/check_architecture.dart` bitre változatlan** (`git diff` üres); az
  allowlist pontosan **12 bejegyzés**, mind pre-existing `analyze → live/engine/*`.
- Az új kód **kizárólag** `features/analyze/public.dart`-ot importál cross-feature
  határként (`clip_analyzer_stage.dart:2`, `legacy_evidence.dart:4`) + a
  megengedett core `core/music/strum.dart`-ot (`legacy_evidence.dart:3`). **Nincs**
  közvetlen `lib/features/live/**` vagy `assets/ml/**` import.
- Új gépi őr: `architecture_allowlist_guard_test.dart:7` pinneli `length <= 12`.

**NOTE-3 (előre-mutató, latent):** az `analyze/public.dart` re-exportálja az
`analyze_providers.dart`-ot (Riverpod- és `rootBundle`-kötött modul), így az
`audio_analysis/engine` réteg mostantól tranzitívan Flutter/Riverpod ellen
fordul a barrelen át — ugyanaz a "public barrel többet exportál a szűk
kontraktusnál" minta, mint a korábbi vision-barrel eseteknél. A kör SAJÁT kódja
csak a tiszta `runClipAnalysis` függvényt + az `AnalyzeResult`/`TimelineStrum`
value-típusokat használja, tehát **framework-szimbólum nem lép be a domain-logikába**.
Egy JÖVŐBELI `audio_analysis` domain-fájl viszont ugyanezen a barrelen át
véletlenül framework-típust húzhatna be. Latent, a barrel szélessége az `analyze`
feature terve — nem ennek a körnek a hibája.

### 2.5 Prompt-injection / dev-rendszer önvédelem (AGENTS.md §5.1, ADR 0138) → CLEAN

Az ADR 0226 és a round-brief **scope-SZŰKÍTŐ**, nem tágító: STOP-protokoll
(`brief:43-50`), tiltott zóna felsorolás (`brief:144-145`), "allowlist csak
szűkülhet" (`brief:37-41,157`), "V1 bitre változatlan" (`brief:149`). **Nincs**
rejtett instrukció, jövőbeli-agent-célzó direktíva vagy scope-tágító nyelvezet.
A `brief:258` "Valódi-sértés próba" legitim teszt-minőségi önellenőrzés (ideiglenes
törlés → RED → visszaállítás), nem injection.

---

## 3. További megjegyzések (a security-remit határán)

**NOTE-4 (előre-mutató, false-confidence higiénia):** a `strumRefinerSource =
heuristic` egy **inferált** címke (candidate == baseline,
`clip_analyzer_stage.dart:74`), nem közvetlenül bizonyított parse-hiba. Az ADR
0226 ezt kimondottan dokumentálja mérési korlátként + visszavonási feltétellel. A
címke ŐSZINTÉN elnevezett (`candidate-matches-heuristic-baseline`, nem "a modell
elbukott"), unwired és nem user-facing → **nem sérti a §5 #5 szabályt** (gyenge
confidence ≠ biztos állítás). *R22 irány:* ha a provenance user-facing lesz, a
`heuristic` NE jelenjen meg "az AI-modell hibázott" biztos állításként.

**NOTE-5 (előre-mutató, DoS-amplifikáció):** ha `weights != null`, a
`runClipAnalysis` **kétszer** fut ugyanazon a PCM-en (`clip_analyzer_stage.dart:31`
+ `:67`) — ez az ADR 0226 dokumentált mérési technikája (candidate vs. baseline),
de 2× DSP-költség. A cancellation-token a két futás ELŐTT és UTÁN ellenőrződik
(`:29`, `:39`), de a DSP-futások KÖZBEN nem → hosszú klip nem szakítható meg
menet közben. *R22 irány:* izolátum + timeout, mielőtt (potenciálisan hosszú,
untrusted) klipre bekötik.

---

## 4. Megállapítások összegzés

| Súlyosság | Db | Tételek |
|---|---|---|
| CRITICAL | 0 | — |
| BLOCKER | 0 | — |
| MAJOR | 0 | — |
| MINOR | 0 | — |
| NOTE | 5 | súly-forrás pre-validáció (R22); Uint8List-copy teszt-hézag; barrel Flutter-tranzitivitás; `heuristic` inferált címke user-facing higiénia; dupla-DSP cancellation-granularitás |

**Titkok:** a klón teljes gate-jén az implementer `check_secrets` futása 0 findinget
adott (`brief:336`, `2214 file(s), 0 finding(s)`); szemantikailag a "garbage
weights" fixture `Uint8List(16)` (16 nulla bájt) — **valóban fake**, nem valós
kulcs; a `crnn` teszt-ág a bundle-elt `assets/ml/strum_crnn.bin`-t olvassa
(megbízható, már repóban lévő model-asset, nem titok). Az új `lib/` fájlokban
nincs kulcs/token/jelszó-szerű literál (az egyetlen grep-találat a
`cancellationToken` substring — nem titok).

---

## 5. Verdikt

**PASS a security scope-ban.** Nincs nyitott CRITICAL/BLOCKER/MAJOR/MINOR lelet.
Az öt NOTE kivétel nélkül a jövőbeli **R22 wiring-körre** irányuló hardening —
egyik sem blokkoló, mert a teljes `audio_analysis` V2 feature (és ez az adapter)
jelenleg **unwired**, a V1 DSP/CRNN-kód bitre változatlan, az immutability
zárt (reprodukálva), a fallback-provenance nem szivárogtat, és az architektúra-
allowlist nem nőtt. A merge security-oldalról nem blokkolt; az R22 briefjében a
NOTE-1 (súly-forrás pre-validáció / izolátum) és NOTE-5 (cancellation-granularitás)
kifejezetten követendő.
