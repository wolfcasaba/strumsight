# E06-R05 — Biztonsági / privacy review (dedikált)

Brief: `docs/rounds/e06-r05-input-abstraction-and-safe-import.md`
Diff: `git diff a7507a58 7b5a4e1c` (a `7b5a4e1c` fej a `ss-terra-e06-r05`
worktree-ben ül, origin-ra még nem pusholva — a review ezt a commitot fetchelte
egy izolált `/tmp` klónba, minden próbát ott futtatva; a megosztott worktree-t
csak olvasásra érintette).
Reviewer: Claude (security-reviewer, READ-ONLY) · Dátum: 2026-08-11
Verdikt: **CHANGES REQUIRED (FAIL)** — 0 CRITICAL, 0 BLOCKER, **1 MAJOR**, 2 NOTE

A MAJOR **nem termékhatár-sértés** (nincs titok-szivárgás, consent-megkerülés,
RCE/path-traversal, crash vagy rejtett hálózat). A crash-safety, a fájlnév-
privacy, a hálózat/FS-tisztaság és a `FailureCode` additivitás mind bizonyítottan
rendben. Az egyetlen merge-blokkoló lelet a §5.6 kötött döntés (importált úton
NaN/Inf **elutasítás, nem sanitization**) egy reprodukálható megkerülése, amit a
kör teljes tesztkészlete (a 15 gateway-teszt, az 5 validator-teszt és az
500-esetes fuzz) nem fed.

## Összegzés

CRITICAL: 0 · BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 2

## Scope-audit

A diff pontosan a brief `allowed_paths` listáján marad (10 kód/teszt + a brief
doc). A `lib/features/audio_analysis/public.dart` (+1 sor,
`export 'domain/analysis_input.dart';`) a listán szerepel; a barrel csak a domain
input-contractot exportálja, a `data/input/**` adapter-belsőt (pl.
`WavDecoderAdapter`) **nem**. `git diff --stat` **nem** tartalmazza a fagyasztott
`lib/core/audio/codec/wav_decoder.dart`-ot. Listán kívüli változás: **nincs**.

## A dedikált review öt fókuszpontja — bizonyítékkal

| # | Fókusz | Eredmény | Bizonyíték |
|---|---|---|---|
| 1 | Byte-szintű WAV-parser crash-safety adverzariális inputon | **PASS** | 12 kézzel gyártott malformed/oversized/DoS eset → mind **typed `Failure`**, 0 kezeletlen kivétel, 0 hang (lásd „Adverzariális próba-napló") |
| 2 | Fájlnév-privacy end-to-end | **PASS** | `SourceDisplayName.value` **soha** nem olvasódik `lib/`-ben (`grep`); `toString()`-ek redaktáltak; 0 logger/print/analytics az új fájlokban; redakciós teszt: `analysis_input_validator_test.dart:146-157` |
| 3 | Nincs rejtett hálózat/FS-írás | **PASS** | `grep -E "File\(|Directory\(|writeAs|dio|http|Socket|Process|path_provider"` az 5 új lib-fájlon → 0 találat (a „File" csak a `FileAnalysisInput` osztálynév); a fájlnévből **semmilyen** FS-path nem épül → §28.2 valóban scope-on kívül |
| 4 | `FailureCode` additivitás | **PASS** | `app_failure.dart` diff = **12 új** `static const String`, csak `+` sorok; egyetlen meglévő konstans sincs átnevezve/törölve/érték-változtatva (String-const class, nem enum → nincs átsorszámozási kockázat) |
| 5 | NaN/Infinity split (import=reject, mic=sanitize) | **RÉSZBEN — MAJOR** | single-chunk import NaN/±Inf → `audioNonFiniteSample` (probe 13,14); mic PCM → sanitize+warn (`validator` teszt 110-144). **DE** multi-`data`-chunk float32 NaN → **Success** (probe 15) — lásd F1 |

## Megállapítások

### F1 — MAJOR — Multi-`data`-chunk float32 megkerüli az importált „NaN=reject" határt

- **Fájl:** `lib/features/audio_analysis/data/input/wav_decoder_adapter.dart:171-187`
  (`_inspect` az ELSŐ `data` chunkon `return`-öl) együtthatva a fagyasztott
  `lib/core/audio/codec/wav_decoder.dart:41-55,95` dekóderrel (az UTOLSÓ `data`
  chunkot dekódolja és a float32-t `.clamp(-1.0, 1.0)`-gal vágja).
- **Probléma:** Az importált út nem-véges-elutasítása KIZÁRÓLAG `_inspect`
  float32-scanjében él (`:171-186`), ami a **legelső** `data` chunk után
  `return Success`-t ad (`:187`), a többit meg sem nézi. A fagyasztott legacy
  dekóder viszont az **utolsó** `data` chunkot dekódolja, és a `.clamp(-1,1)` a
  nem-véges float32-t véges értékké alakítja (mérve: `NaN.clamp(-1,1)=1.0`,
  `+Inf→1.0`, `−Inf→−1.0`). Így a `validator.validate()` (`:65-87`) már
  redaktált-véges mintát lát → az import-reject ág (`:83-87`) **soha nem sül el**
  ezen az úton. Egy támadó két `data` chunkkal (első véges, második NaN-os)
  becsempész egy nem-véges float32 mintát, ami teljes kitérésű 1.0 spike-ként
  landol a pipeline-ban.
- **Reprodukció (izolált klón, `dart` futás):** probe 15 — `fmt `(format 3,
  1 ch) + `data`(13000× véges float32) + `data`(NaN + 13000× véges) →
  **`Success`** 13003 mintával, mind „véges" (a NaN 1.0-ra vágva). A single-
  chunk megfelelője (probe 13) helyesen `Failure(audio.non_finite_sample)`.
- **Sértett szabály:** brief §5.6 („NaN/Infinity minta: **elutasítás (nem
  sanitization)** az importált úton") + a §6.1 mérce-mátrix „importált NaN
  Failure-cella". A megadott indok szó szerint az, amit ez a lelet megvalósít:
  „silently sanitizing untrusted imported data could mask a corrupted or
  adversarially crafted file".
- **Miért nem fogja meg egyik teszt sem:** a gateway-teszt (`:96-172`) nem
  injektál NaN-t és nem használ több `data` chunkot; a validator-teszt csak
  `validate(PcmAnalysisInput)` szinten tesztel közvetlen PCM-mel (`:90-108`), a
  fájl-pipeline-t nem; a fuzz (`analysis_input_fuzz_property_test.dart`) csak
  `RIFF`/`WAVE`-et bélyegez, `fmt `/`data` id-t soha → érvényes multi-chunk WAV-ot
  nem tud előállítani, és a Success-ág finiteness-assertje (`:44`) amúgy is
  **átmenne**, mert a kimenet a vágás után véges.
- **Hatás:** integritás — adverzariális/korrupt importált fájl átcsúszik az
  input-integritás kapun, a korrupció elrejtve; a downstream DSP hamis
  teljes-kitérésű tranzienst kaphat. Nem privacy/secret/RCE, a konkrét kimenet
  jóindulatú (egy vágott minta), ezért MAJOR és nem BLOCKER.
- **Kötelező javítás iránya (a fagyasztott dekóder érintése nélkül):** az
  `_inspect` ne álljon meg az első `data` chunkon — vagy utasítsa el a >1 `data`
  chunkot tartalmazó fájlt (a valid WAV-nak pontosan egy van), vagy a
  finiteness-scant az UTOLSÓ (ténylegesen dekódolt) `data` chunkon végezze, hogy
  ugyanazokat a bájtokat validálja, amiket a legacy dekóder felhasznál.
  Post-decode ellenőrzés önmagában NEM elég: a `.clamp` már megette a NaN-t.
- **Ellenőrzés:** a fenti probe 15 mátrix-cellája (multi-`data` float32 NaN →
  `Failure(audio.non_finite_sample)`) legyen zöld; a single-chunk cella maradjon
  zöld.
- **Státusz:** OPEN

### F2 — NOTE — `_inspect` teljes fejléc-bejárása a gateway try/catch-en KÍVÜL fut

- **Fájl:** `lib/features/audio_analysis/data/input/wav_decoder_adapter.dart:33`
  (`_inspect` hívás) vs. a `try` `:39`; a nyers float32-scan `:177`.
- **Probléma:** Minden `ByteData` olvasás és a float32-scan a `_inspect`-ben
  (`:83-206`) a `try` (`:39-80`) ELŐTT fut. A gateway „mindig `AppResult`"
  szerződése így teljes egészében a `_inspect` belső bounds-aritmetikáján áll
  (`:103` `chunkSize > bytes.length - body`). **A jelenlegi kód bizonyítottan
  biztonságos** (mind a 12 crash-próba typed `Failure`-t adott).
- **Bizonyíték, hogy a `:103` guard teherhordó (mutáció-próba az izolált klónban,
  visszaállítva):** a guardot `if (false && …)`-re állítva egy valid `fmt `+
  túl-deklarált `data` float32 fájl **kezeletlen `IndexError`-t** dobott, ami a
  `_inspect:177` → `decodeInput:33` kereten át kiszökött a gateway-ből (a try
  nem fogta) — majd `git checkout` visszaállítás. A kiszökő érték egy
  **bájt-index RangeError**, NEM audio/fájlnév → nincs privacy-hatás.
- **Hatás:** jelenleg nincs; jövőbeli fragility — a bounds-aritmetika bármely
  gyengülése a „mindig `AppResult`" szerződést kezeletlen kivétellel töri.
- **Javasolt irány (nem blokkoló):** a `_inspect` hívás vonása a `try`-ba (a
  `RangeError`→`audioChunkSizeOutOfBounds` map már létezik `:62`), hogy a
  fail-closed strukturális legyen, ne csak aritmetikai.
- **Státusz:** OPEN (hardening)

### F3 — NOTE — A float32 finiteness-scan a legacy olvasást megduplázza (perf, korlátozott)

- **Fájl:** `lib/features/audio_analysis/data/input/wav_decoder_adapter.dart:172-186`.
- **Probléma:** float32 import esetén `_inspect` végigolvassa a `data` chunk
  minden mintáját finiteness-ért, majd a legacy dekóder MÉGEGYSZER végigolvassa
  őket. A `maxFileBytes = 64 MiB` kapu (`:28`) korlátozza, így ~2× pass ≤64 MiB-en
  — **nem DoS** (mérve: 32 MiB junk-walk 211 ms). Informatív, nem biztonsági.
- **Státusz:** OPEN (informational)

## Amit bizonyítottan tisztának találtam (üres-lelet-bizonyíték)

- **Crash-safety:** modulo-by-zero csali (`channels=0, blockAlign=0`) →
  `audio.unsupported_channel_count` (a `validatePcmMetadata:41` elutasítja a
  `channels<=0`-t egy nem-halasztott kóddal, mielőtt `header` beállna, így a
  `:163` `chunkSize % blockAlign` sosem fut `blockAlign==0`-val); `0xFFFFFFFF`
  chunk-méret → `chunk_size_out_of_bounds`; `sampleRate=0xFFFFFFFF` →
  `invalid_sample_rate`; nem-blokk-igazított `data` → `truncated_chunk`;
  32 MiB × 4.19M nulla-méretű chunk → 211 ms typed `Failure` (a ciklus min. +8
  bájtot lép, forward progress garantált). Overflow-safe forma (`size >
  bytes.length - body`) jelen van `:103`.
- **Fájlnév-privacy (ADR 0217, §5.4):** `SourceDisplayName.toString()` =
  `'SourceDisplayName(redacted: true)'`; a három input `toString()` a redaktált
  alakot interpolálja; a `.value` a teljes `lib/`-ben SEHOL nem olvasódik; a
  `sourceDisplayName` csak objektumként továbbadva (`validator:102`,
  `adapter:53`); `AudioFailure.cause` csak decoder-eredetű `RangeError`/
  `ArgumentError`, sosem a fájlnév.
- **Hálózat/FS:** 0 `File(`/`Directory(`/`writeAs`/`dio`/`http`/`Socket`/
  `Process`/`path_provider` az új lib-fájlokban; nincs fájlnévből épített path.
- **`FailureCode` additivitás:** 12 új konstans, csak `+`, semmi átnevezés/
  törlés/érték-változtatás.
- **Mic-sanitize split:** PCM-mikrofon úton NaN→0.0 + `warning`
  (`validator:83-112`, teszt `:110-144`), a többi minta bitre változatlan.

## Adverzariális próba-napló (izolált klón, `dart --packages=<klón>/.dart_tool`)

```
NaN.clamp(-1,1)=1.0  +Inf.clamp=1.0  -Inf.clamp=-1.0
01 valid 16-bit mono                         -> Success
02 channels=0 blockAlign=0 (mod-by-zero csali)-> Failure(audio.unsupported_channel_count)
03 channels=0 blockAlign=2                    -> Failure(audio.unsupported_channel_count)
04 nonsense blockAlign/byteRate               -> Failure(audio.truncated_chunk)
05 sampleRate=0xFFFFFFFF                       -> Failure(audio.invalid_sample_rate)
06 data declaredSize=0xFFFFFFFF               -> Failure(audio.chunk_size_out_of_bounds)
07 JUNK declaredSize=0xFFFFFFFF               -> Failure(audio.chunk_size_out_of_bounds)
08 data size=3 (non-aligned)                  -> Failure(audio.truncated_chunk)
09 truncated fmt (size 10)                    -> Failure(audio.truncated_chunk)
10 only RIFF/WAVE                             -> Failure(audio.truncated_chunk)
11 not-RIFF                                   -> Failure(audio.invalid_riff)
12 DoS 32MiB / 4.19M size=0 JUNK chunks       -> Failure(audio.truncated_chunk)  (211ms)
13 imported float32 single-chunk NaN          -> Failure(audio.non_finite_sample)
14 imported float32 single-chunk +Inf         -> Failure(audio.non_finite_sample)
15 imported float32 MULTI-data finite->NaN    -> Success   <-- F1 (elvárt: Failure)
16 microphone float32 single-chunk NaN        -> Failure(audio.non_finite_sample)
mutation: :103 guard -> `if(false && …)` => UNCAUGHT IndexError @ _inspect:177 -> decodeInput:33 (F2), majd git checkout restore
```

## Merge-döntés

0 CRITICAL, 0 BLOCKER, **1 MAJOR (OPEN)**. Az ADR 0052 / a review-report §
szerint a MAJOR merge-blokkoló, és a brief §11 „nulla OPEN BLOCKER/MAJOR" bárja
is ezt írja elő → **CHANGES REQUIRED**, amíg az F1 (§5.6 megkerülés) meg nem
oldódik vagy a csapat expliciten nem waiverezi a §5.6-ot a multi-`data`-chunk
esetre. A crash-safety, privacy, hálózat/FS és additivitás nem igényel változást.
