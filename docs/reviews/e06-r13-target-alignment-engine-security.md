# E06-R13 — Target Alignment Engine — Security / Privacy / Prompt-Injection Review

**Reviewer:** security-reviewer (READ-ONLY) · Dátum: 2026-08-12
**Branch:** `codex/e06-r13-target-alignment-engine` @ `2ae80542` (impl) / `c7cd64a0` (pre-flight)
**Base:** `ce4b6b24` · **Router risk:** `high` (a review kötelező, AGENTS.md §15.1)

## Verdikt: PASS — 0 CRITICAL, 0 BLOCKER, 0 MAJOR

Nincs merge-tiltó lelet. Nincs bizonyított titok-szivárgás, consent-megkerülés,
RCE/path-traversal, és egyetlen AGENTS.md §5 termékhatár sem sérül. Két
**MINOR** (mindkettő latens, mindkettő *kötelezően javítandó a
fogyasztó-bekötő kör előtt*: R14–R16 vagy R26), néhány NOTE és két
pozitívum. A kör tisztán domain+engine kód, teljesen bekötetlen (nincs külső
fogyasztó a mai `main`-en).

## Összegzés

Az `EventAligner` egy monoton, determinisztikus, sávos DP. A
bemenet-validáció erős, a memóriakorlát (`O(min(n,m))`) **bizonyítottan
tartja magát**, és a kör ténylegesen bezárja az E06-R02 NaN-fail-open rést a
saját határán. A két residuális kockázat: (1) a sáv *időablakból* származik,
nem konstansból, ezért időben-klaszterezett bemenet teljes szélességűre
nyitja → a *dokumentált* `O(n·m)` idő korlátlan `n,m` mellett latens DoS; (2)
az `AlignmentResult.confidence` a párosított események átlagos
confidence-e, a missed/extra arányt figyelmen kívül hagyva → §5/ADR 0179
hamis-confidence mag. Mindkettő latens (bekötetlen), egyik in-round
acceptance-cellát sem buktat.

## Acceptance-kritérium relevancia (biztonsági nézőpont)

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| DoS-korlát | Sáv/allokáció mérete korlátozott? | ⚠️ részben | Memória `O(min)` **igen** (`scoreStateCount = min`, mérve); idő `O(n·m)` klaszterezett bemenetre → F1 |
| Bemenet-validáció | NaN/∞/negatív/degenerált crash-biztos? | ✅ | `beatDuration≤0`, NaN-confidence, rendezetlen, negatív idő → mind `ArgumentError`, reprodukálva |
| Nincs I/O/secret/hálózat | Tiszta domain/engine? | ✅ | grep: 0 db `dart:io`/flutter/dio/http/print/log/File/toJson a 6 új prod fájlban |
| Domain purity (§6) | Nincs Flutter/Riverpod/storage a domain-ben? | ✅ | csak relatív domain-importok |
| §5 gyenge confidence | Nem állít biztosat? | ⚠️ | `confidence=mean(matched)` túlállít → F2 |
| §5.1 prompt-injection | Nincs külső utasítás-tartalom? | ✅ (N/A) | nincs AI/tool/KB felület; brief+ADR verziózott commit |

## Megállapítások

### F1 — MINOR — Az időből-származó sáv klaszterezett bemenetnél teljes szélességűre nyílik → latens DoS (nincs bemeneti méretkorlát)

- **Fájl:sor:** `lib/features/audio_analysis/engine/alignment/event_aligner.dart:42–50`
  (a sáv `_lowerBound`/`_upperBound`-ból, `width = endExclusive - first`,
  `candidatePairCount += width`); `tolerance_policy.dart:16–32` (a tolerancia
  `[40ms,150ms]`-ra clampelt — **időben** korlátos, **eseményszámban nem**).
  Nincs hosszkorlát `align()`-ban, sem `analysis_target.dart:38`-on
  (`expectedEvents`).
- **Failure scenario:** Bemenet = N megfigyelt + N elvárt esemény, mind
  **egyetlen toleranciaablakon belül** (pl. mind `time=0`). Ekkor minden sor
  `[rowTime−tol, rowTime+tol]` ablaka az ÖSSZES oszlopot tartalmazza →
  `maxBandWidth = N`, `candidatePairCount = n·m`, futásidő `O(n·m·log)`.
  Reprodukálva (különálló, nem commitolt Dart-próba): sparse bemenet (mint az
  acceptance-fixture, 100ms-enként) n=2000 → band **3**, 34ms; klaszterezett
  bemenet (mind `time=0`) n=1000/2000/4000/8000 → band **= n**,
  `candidatePairCount` **= n²**, idő **94 / 304 / 1284 / 4819 ms** (tiszta
  kvadratikus görbe) → extrapolálva n=100 000-re ~12+ perc (ANR/DoS-szintű).
- **Fontos árnyalat:** a **memóriakorlát `O(min(n,m))` TARTJA magát**
  (`scoreStateCount = min`, a `pending` lista ≤ min) — mérve. Az idő
  `O(n·m)` pedig **dokumentált** (ADR 0231 D6 / brief §5.6: „`O(n·m)` idő,
  `O(min(n,m))` memória"). Ez tehát **NEM** „dokumentálatlan `O(n²)`/`O(n³)`
  allokáció" — a klaszterezett eset pontosan a dokumentált `O(n·m)`
  idő-legrosszabb-esetet éri el (Fenwick log-faktorral). A valódi rés:
  **nincs `n,m` felső korlát**, és a sáv-optimalizáció (amit a *jelenlegi
  egyetlen* skálateszt neve — „large **sparse** alignment stays within the
  time-derived band", `event_aligner_test.dart:225`,
  `expect(maximumCandidateBandWidth <= 3)` — sugalmaz) klaszterezett
  bemenetnél megbukik. **Egyetlen teszt sem fed nagy, időben-klaszterezett
  bemenetet.**
- **Sértett szabály:** brief §5.6 / ADR 0231 D6 „korlátos, dokumentált
  komplexitás" — betűjében teljesül (memória `O(min)`, idő `O(n·m)`), de a
  sáv-korlátosság ígérete csak sparse bemenetre igaz; defense-in-depth kérdés
  a jövőbeli *importált (nem bizalmas forrású) target*-ekre nézve (ADR 0231
  „importált dal-fájlok/gyakorlat-targetek").
- **Miért MINOR és nem MAJOR:** bekötetlen (nincs jelenlegi untrusted feed),
  a komplexitás dokumentált, a memóriakorlát tartja magát, és **egyetlen
  in-round acceptance-cella sem bukik** (a §6 perf-cella klaszterezett
  n=2000-re is 304ms < 10s).
- **Javítás iránya (kötelező a bekötő/importált-target kör — R14/R26 — előtt):**
  fail-closed bemeneti méretkorlát (`observed.length`/`expected.length`/
  `AnalysisTarget.expectedEvents.length` felső határ → dobás), VAGY kemény
  sávszélesség-korlát (a jelöltek számának per-sor felső határa a
  toleranciából *és* egy konstans plafonból). Emellett egy acceptance-cella
  nagy **klaszterezett** bemenetre, ami a sparse-cella mellett méri a
  band-width-et.
- **Státusz:** OPEN, nem blokkoló — follow-up a fogyasztó-bekötő kör (R14–R16
  timing-metrikák vagy R26 Practice/Song adapter) pre-flightjának.

### F2 — MINOR — `AlignmentResult.confidence` túlállítja az illesztés minőségét

- **Fájl:sor:** `event_aligner.dart:119–125` — `confidence = matches.isEmpty
  ? 0.0 : (Σ match.observed.confidence) / matches.length`.
- **Failure scenario:** 1 megfigyelt (confidence 0.98) esemény vs. 1000
  szétszórt elvárt esemény → csak `e0` illeszkedik, 999 missed.
  Reprodukálva: `matches=1, missed=999, RESULT.confidence = 0.98` (98%) egy
  0.1%-ban teljes illesztésre. A `confidence` a párosított események
  *észlelési* confidence-ének átlaga — az illesztés **teljességét/minőségét**
  (missed/extra arány) teljesen figyelmen kívül hagyja.
- **Enyhítő tény:** a `totalCost` (999.0) és a `missedExpected` (999 elem)
  **őszinte** — egy gondos fogyasztó látja a rossz illesztést. De a
  `confidence` mező önmagában olvasva („98% biztos") félrevezet. Egyetlen
  teszt sem fedi a „kevés-match-sok-missed-de-magas-confidence" esetet (a
  tesztek csak confidence=1 tökéletes, confidence=0 üres, és a
  cost-szorzó cellákat fedik: `event_aligner_test.dart:29,169,173`).
- **Sértett szabály:** AGENTS.md §5 — „gyenge confidence nem jelenhet meg
  biztos állításként".
- **Javítás iránya (kötelező, amikor egy metrika/UI olvassa — R14–R16):** vagy
  nevezd/dokumentáld át egyértelműen („párosított-esemény észlelési
  confidence, NEM az illesztés teljessége"), vagy fűzz be egy
  coverage-faktort (`matches / (matches + missed)`).
- **Státusz:** OPEN, nem blokkoló — follow-up ugyanoda, mint F1.

### F3 — NOTE — A méretkorlát-hiány a `AnalysisTarget` snapshoton keresztül is terjed

- `analysis_target.dart:38–45` — `expectedEvents` nem kap hosszkorlátot (bár
  rendezettség- és `notes∈[0,127]`/`chords` validált). Amikor egy jövőbeli
  fogyasztó `target.expectedEvents`-et ad az `aligner.align(expected:)`-nek,
  az F1 DoS ezen a csatornán is él (importált target N klaszterezett
  eseménnyel). Ugyanaz a fail-closed méretkorlát fedi.

### F4 — NOTE (pozitívum) — A kör bezárja az E06-R02 NaN-fail-open rést a határán

- `event_aligner.dart:180–182` — `_validateOrderedObserved`
  `!event.confidence.isFinite` ellenőrzést használ (NaN observed confidence
  → `ArgumentError`, reprodukálva), szemben az `AnalysisEvent` konstruktor
  `< 0 || > 1` idiómájával, ami NaN-t átenged. `alignment_result.dart:65,68`
  és `:17` a kimeneteket `!isFinite`-tal validálja. Ez a helyes, in-diff
  minta.

### F5 — NOTE (pozitívum) — Degenerált numerikus bemenet crash-biztos, nincs osztás-nullával

- `tolerance_policy.dart:17–19` — `beatDuration ≤ 0` → `ArgumentError`
  (reprodukálva `0` és `−1µs`-ra). A tolerancia `[40ms,150ms]`-ra clampelt,
  így `_matchCost` `timingCost = timingDistance / tolerance.inMicroseconds`
  osztója ≥ 40000 > 0 — nincs osztás nullával. Extrém `beatDuration` (µs
  vagy évek) is a clamp miatt korlátos sávot ad. Üres observed/expected →
  tiszta üres eredmény (nincs crash).

## Ellenőrzött, tiszta felületek (üres-lelet bizonyíték)

- **Nincs hálózat/audio/secret/I/O:** grep a 6 új prod fájlon
  (`domain/target/*`, `engine/alignment/*`) — **0 találat**
  `dart:io|dart:ffi|package:flutter|dio|http|HttpClient|Socket|MethodChannel|
  Platform\.|SharedPreferences|KeyValueStore|SecureStore|print|debugPrint|
  developer\.log|stderr|stdout|File(|Directory(|toJson|toMap|serialize|
  jsonEncode|Random(`-re. (A `dart:io` csak a *teszt*-fájlban,
  `Platform.environment['PROPERTY_SEED']`-hez — rendben.)
- **Domain purity:** `domain/target/` fájlok kizárólag relatív
  domain-importokat használnak. Nincs Flutter/Riverpod/storage. Az
  `engine/alignment/` fájlok domain+`tolerance_policy` importok, nincs
  framework.
- **Titkok:** nincs új kulcs/token; a teszt-fixture-ök szintetikus
  események (`'o0'`, `'e0'` id-k) — nincs secret material.
- **Prompt-injection a fejlesztőrendszerre (§5.1):** N/A — ebben a körben
  nincs AI-provider, tool-calling, sem tudásbázis-visszakeresés. A brief és
  ADR 0231 verziózott, commitolt tartalom; nincs benne letöltött/generált,
  utasításként értelmezhető szöveg. A brief §9 „ADR 0203" hivatkozás egy
  önként dokumentált, nem létező placeholder (ADR 0231 „Kontextus" szakasza
  kifejezetten kimondja) — nem injection-vektor, csak dokumentált eltérés
  (AGENTS.md §2).
- **Immutabilitás:** `AnalysisTarget` (`:42–45`) és `AlignmentResult`
  (`:62–64`) `List.unmodifiable`-lel védenek; az `EventAligner` nem mutálja
  a bemenetet (indexekkel dolgozik, új listákat épít).

## Merge-döntés

**PASS.** 0 CRITICAL / 0 BLOCKER / 0 MAJOR → nincs merge-tiltó biztonsági
lelet (a merge-bar egyébként változatlan: exact-SHA zöld CI, §4-en belüli
diff). A két MINOR nem blokkol, de **mindkettőt kötelezően fel kell oldani,
mielőtt bármely fogyasztó (metrika R14–R16, Practice/Song adapter R26, vagy
importált target) bekötné az `EventAligner`-t** — F1 fail-closed
méretkorlátot/sávplafont, F2 a `confidence` mező átértelmezését vagy
coverage-faktorát igényli. Ez a jelentés a fogyasztó-bekötő kör szerzőjének
szól figyelmeztetésként (l. HANDOFF.md E06-R13 záró bekezdés).
