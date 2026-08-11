# E06-R05 — Review

Brief: `docs/rounds/e06-r05-input-abstraction-and-safe-import.md`
Diff: `git diff e7bf483f..44300b21` (pre-flight commit → implementer HEAD), equivalently `git diff main...codex/e06-r05-input-abstraction-and-safe-import`
Reviewer: Claude (Sonnet 5, orchestrator) · Dátum: 2026-08-11
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 2

Implementer: Terra (Codex), 1 forduló, `continuations=0`, `gate_shape=ok`,
`scope_audit=ok` (11/11 changed paths inside `allowed_paths`). A brief kapott
egy pre-flight §0.0 revíziót (R1 ADR-szám, R2 `AnalysisInputSource`
újrahasználat, R3 két hiányzó `FailureCode` név) — mindhármat az implementer
helyesen követte, lásd F és a lenti bizonyítékok.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Formátum-mátrix, hét cella (4 success + unsupportedBitDepth×2 + unsupportedFormat×1) | ✅ | `test/.../audio_decoder_gateway_test.dart:12-69`; saját gate-futás: `test test/features/audio_analysis` ZÖLD, 45/45 |
| 2 | Malformed-mátrix, hat cella | ✅ | `audio_decoder_gateway_test.dart:72-119` — non-RIFF, non-WAVE, truncated fmt→`truncatedChunk`, truncated data→`chunkSizeOutOfBounds`, oversized declared data→`chunkSizeOutOfBounds`, `0xFFFFFFFF`→`chunkSizeOutOfBounds`; kézzel nyomonkövetve `wav_decoder_adapter.dart:92-121` ellen, mind reprodukálódik |
| 3 | Fájlméret-küszöb hármas (inkluzív) | ✅ | `audio_decoder_gateway_test.dart:121-138`: `maxFileBytes−1`/`maxFileBytes` Success, `+1` → `fileTooLarge`; a három bájtszám `python3 -c`-vel újramérve egyezik (67 108 863/864/865) |
| 4 | Hossz-küszöb hatos (min+max, inkluzív) | ✅ | `analysis_input_validator_test.dart:21-57`: 11999/12000/12001 és 28799999/28800000/28800001, névvel is (`clipTooShort`/`clipTooLong`) — **saját mutáció-próba** (lásd lent) megerősíti, hogy a cella valódi |
| 5 | NaN-mátrix, importált (3) + mikrofonos (3) | ✅ | `analysis_input_validator_test.dart:59-101`: NaN/+Inf/−Inf mindkét úton külön esetként; a mikrofonos teszt explicit ellenőrzi, hogy a SZOMSZÉDOS minták (`index 0`, `index 2`) bitre változatlanok maradnak, nem csak hogy "valami" 0 lett |
| 6 | Fuzz property, ≥500, `PROPERTY_SEED`, részben RIFF-fejléces | ✅ | `test/property/analysis_input_fuzz_property_test.dart` — 500 eset, `Platform.environment['PROPERTY_SEED']` seed (alap 42), minden második eset RIFF/WAVE-taggelt, `≤64 KiB/eset` (kockázat §9 betartva); saját gate-futás: ZÖLD |
| 7 | Fájlnév-redakció + gateway nulla logger-hívása | ✅ | `analysis_input.dart:15-23` `SourceDisplayName.toString()` sosem adja ki `value`-t (`redacted` mezője `const`-ban mindig `true`); `audio_decoder_gateway.dart` doc-comment + konstruktor **struktúrálisan** nem fogad loggert — ez erősebb bizonyíték, mint egy futásidejű "0 hívás" assert, mert logger-referencia hiányában hívás sem lehetséges. Teszt: `audio_decoder_gateway_test.dart:140-153` |
| 8 | Core dekóder bitre változatlan | ✅ | `git diff --stat e7bf483f..HEAD -- lib/core/audio/codec/ test/features/analyze/` → üres; saját gate-futás: `test test/features/analyze` ZÖLD, 65/65 (a régi `wav_decoder_test.dart` öt esete köztük, átírás nélkül) |
| 9 | Bounds-safety az összeadás ELŐTT (`size > bytes.length - body`) | ✅ | `wav_decoder_adapter.dart:96` szó szerint ezt a formát használja, nem a tiltott `body + size > bytes.length` alakot; a `0xFFFFFFFF`-cella (fenti #2) ezt ténylegesen gyakorolja |
| 10 | Kilenc additív `FailureCode`, meglévő érték érintetlen | ✅ | `git diff -- lib/core/foundation/app_failure.dart`: kilenc új `static const String` sor beszúrva a `audio` blokkba, egyetlen meglévő sor sem módosult |
| 11 | `AnalysisInputSource` újrahasználva, nem újradefiniálva (§0.0 R2) | ✅ | `analysis_input.dart:3` `import 'analysis_mode.dart';`, nincs második `enum AnalysisInputSource` sehol a diffben; `public.dart` egyetlen exportot ad rá (a régit) — nincs ambiguous-export |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.** `scope_audit=ok`,
`scope_audit_changed=11` a jelzésfájlban; kézzel megismételve:
`git diff --stat e7bf483f..44300b21` pontosan a brief `allowed_paths`
tizenegy bejegyzését adja (10 explicit fájl + a brief maga, amit a
`## 10. Implementation handoff` kitöltése módosított) — egyik sem esik a
tiltott zónába (`lib/core/audio/codec/**`, `lib/features/analyze/**`,
`lib/features/live/**`, `pubspec.yaml`).

## Megállapítások

### F1 — NOTE — `dirty_files=1` a jelzésben egy meglévő wrapper-hiba, nem az implementer munkája

- **Fájl:** `tools/codex-signal.sh:73`
- **Probléma:** a `dirty_files` számítás (`git status --porcelain | wc -l`)
  MAGÁT az éppen író `.codex-round-status.tmp.$$` ideiglenes fájlt is
  számolja, mert az a `{ ... } > "$temporary"` átirányítás miatt már létezik
  a lemezen, amikor a `git status` lefut — és a `.gitignore:66` csak a
  `.codex-round-status` pontos nevet fedi, a `.tmp.<pid>` változatot nem.
  Ez A JELZÉS ÖNMAGÁBAN mindig +1-et mutat egy egyébként tiszta fán.
- **Hatás:** a `done` jelzés `dirty_files=1`-et mutatott, holott a
  munkapéldány ténylegesen tiszta volt (`git status --short` közvetlenül
  ellenőrizve: 0 sor; a három commit — `57127bd6`/`c56d064f`/`44300b21` — a
  jelzés előtt 13 másodperccel lezárva).
- **Kötelező javítás:** NEM ebben a körben — a `tools/` védett mérce-infra
  (AGENTS.md §15.1, `protect_factory_files.py`), ennek a körnek nincs
  jogosultsága hozzá. Follow-up: a `.gitignore` mintát `.codex-round-status*`-ra
  bővíteni, vagy a számítást a `.tmp.$$` fájl explicit kizárásával futtatni
  (ugyanaz a minta, mint a wrapper saját `verify_claim()`-jében már megvan:
  `':(exclude).codex-round-status'`).
- **Ellenőrzés:** a jövőbeli javítás után egy tiszta fán `dirty_files=0`
  legyen.
- **Státusz:** OPEN (follow-up, nem ennek a körnek a hatásköre) — dokumentálva
  `docs/LESSONS.md`-ben a záráskor.

### F2 — NOTE — a max-duration cellának nem volt neve a batch-brief eredeti szövegében

- **Fájl:** `docs/rounds/e06-r05-input-abstraction-and-safe-import.md` §0.0 R3
- **Megfigyelés:** a pre-flight (orchesztrátor) észlelte, hogy a batch-brief
  §5 pont 1 hét kódot sorolt fel, de a §6 acceptance nyolcadikat (`clipTooShort`)
  is névvel követelt, és a maximum-ági kilencediknek egyáltalán nem volt neve.
  A revízió hozzáadta a `clipTooLong` nevet — az implementer ezt hűen követte
  (lásd Acceptance #4, #10). Csak dokumentáció célból rögzítve: nem az
  implementer hibája volt, hanem a 2026-08-07-i batch-brief hiányossága, amit
  a pre-flight zárt le a kód érintése előtt.
- **Státusz:** informatív, nem igényel akciót.

## Saját valódi-sértés próba (a review önálló mérése, nem az implementer állítása)

`analysis_input_validator.dart` `_metadataFailure`-jében a felső hossz-küszöb
`sampleCount * Duration.microsecondsPerSecond > sampleRate *
InputLimits.maxDuration.inMicroseconds` feltételét ideiglenesen `>=`-re
rontva (izolált `/tmp/review-e06-r05` klónban, NEM az implementer
munkapéldányában):

```
$ flutter test test/features/audio_analysis/data/analysis_input_validator_test.dart
00:00 +0 -1: accepts inclusive duration boundaries [E]
  Expected: <Instance of 'Success<ValidatedAnalysisInput>'>
    Actual: Failure<ValidatedAnalysisInput>:<Failure(audio.clip_too_long)>
```

A pontosan `28 800 000` mintás cella — a brief §6.1 saját
mérce-mátrix-sorának megfelelően — ténylegesen PIROSRA vált. Visszaállítás
után mind a négy teszt (4/4) újra zöld. A guard valódi, nem csak
névlegesen tesztelt.

## Gate-bizonyíték ellenőrzése

Mind az implementer TELJES `.codex-round-status`/handoff-állítását, mind a
saját, FÜGGETLEN `/tmp/review-e06-r05` klónbeli újrafuttatást az alábbi
táblázat veti össze:

| Gate | Állított eredmény (implementer) | Saját újrafuttatás (reviewer, izolált `/tmp` klón) |
|---|---|---|
| format | zöld | ✅ ZÖLD — `dart format --set-exit-if-changed`, 1263 fájl, 0 változott |
| analyze | (a round-gate.sh részeként zöld) | ✅ ZÖLD — `flutter analyze lib/ test/ tool/`, 0 lelet |
| test test/features/audio_analysis | 20 teszt zöld (a kör saját fájljai) | ✅ ZÖLD — a TELJES alkönyvtár, 45/45 (a kör 9 saját tesztje + a meglévő 36 regresszió-mentes) |
| test test/property | (a round-gate.sh részeként zöld) | ✅ ZÖLD — 72/72, benne az 500-esetes fuzz |
| test test/core | (a round-gate.sh részeként zöld) | ✅ ZÖLD — 401/401 |
| test test/features/analyze | 5 teszt zöld (wav_decoder_test.dart) | ✅ ZÖLD — a TELJES alkönyvtár, 65/65 |
| architecture | (a round-gate.sh részeként zöld) | ✅ ZÖLD |
| secrets | — | ✅ ZÖLD |
| l10n | — | ✅ ZÖLD |
| CI (teljes suite + property + APK) | — | dispatch folyamatban (`full-gate.yml`, natív diff nincs) — run-link a merge előtt kerül a jelentésbe |

## Merge-döntés

ADR 0052 szerint: minden gate zöld (saját, független újrafuttatással
megerősítve) ÉS nincs nyitott BLOCKER/MAJOR → **merge mehet**, a
`full-gate.yml` CI-run zöld exact-SHA visszaigazolása után (dispatch alatt,
lásd fent). Dedikált biztonsági review (risk=high, AGENTS.md §15.1) külön
napolva: `docs/reviews/e06-r05-input-abstraction-and-safe-import-security.md`.
