# ADR 0535 — Tömörített hang → PCM: platform-dekóder csatornán, nem FFI-vel

**Státusz:** elfogadva (2026-09-17, K2 kör — „Tömörített hang → PCM dekóder")

Kapcsolódik: `lib/core/audio/codec/wav_decoder.dart` (a MÉRT kiindulópont),
`lib/features/audio_analysis/data/input/wav_decoder_adapter.dart` (stabil
hibakód-stílus), `lib/features/audio_analysis/data/input/input_limits.dart`
(`maxDuration` 10 perc, `maxFileBytes` 64 MiB).

## Kontextus

Az „importálj saját hangot" út ma **kizárólag WAV-ot** tud. Ez nem feltételezés,
hanem a forrásban kimondott korlát:

```
$ sed -n '14,16p' lib/core/audio/codec/wav_decoder.dart
/// instead of decoding garbage. Compressed formats (MP3/M4A/OGG) are NOT WAV
/// and need a platform decoder — deliberately out of scope here.
```

A felhasználó telefonján viszont MP3 / M4A / AAC / OGG / FLAC van, és egy MP4-be
csomagolt felvételnek is a hangsávja érdekes. WAV-ra konvertálást kérni tőle a
funkció halála. A kérdés tehát nem *hogy* dekódoljunk, hanem *mivel*.

## Döntés

### 1. Platform-csatorna, nem FFI/minimp3

Az `android.media.MediaExtractor` + `MediaCodec` **hardveres, a rendszerbe épített**
dekódert ad, minden konténerre amit a telefon amúgy is lejátszik — egyetlen
sorral több natív függőség nélkül. A vizsgált alternatíva egy minimp3 (vagy
dr_libs) FFI-mag lett volna:

| | platform-csatorna | minimp3/FFI |
|---|---|---|
| formátumok | amit a készülék tud (MP3, AAC, M4A, OGG, FLAC, WAV, MP4-hangsáv) | MP3 (+ külön lib formátumonként) |
| natív build | nincs (a repo **NEM** tart C++ magot) | CMake + NDK + ABI-nként bináris |
| APK-méret | 0 | minden lib a csomagban |
| gyorsítás | HW-dekóder | CPU |
| ár | Androidon kívül nincs implementáció | platformfüggetlen |

A repo ma FFI/C++ mag NÉLKÜL épül, és a DSP tiszta Dart + `fftea`. Egy natív mag
bevezetése ennek a körnek a hatókörén kívüli, visszafordíthatatlan döntés lenne.
A csatorna viszont eldobható: ha később mégis kell FFI, a
`AudioDecoderPlatformBridge` mögé kerül, a hívók változatlanul.

### 2. MP4-ből kizárólag az audio-sáv

A `firstAudioTrack` **az első olyan sávot** választja, aminek a MIME-je
`"audio/"`-val kezdődik; ha ilyen nincs, `no_audio_track`. Egy MP4 első sávja
tipikusan nem a hang — a naiv „0. sáv" választás vagy `decoder_failed`-et adna,
vagy (rosszabb) értelmetlen bájtokat olvasnánk float32 PCM-nek. Ez utóbbi NÉMA
hiba: a Dart-oldali szerződés-cellák zöldek maradnának, mert azok a csatornát
mockolják. Ezért a szűrőt **forrás-őr** méri:
`tools/tests/test_k2_audio_decoder_track_filter.py`.

### 3. Mono float32, a hívónál eldönthető mintavétellel

A dekóder minden forráscsatornát egyetlen float-ra átlagol framenként — a DSP
(`ClipAnalyzer`, CQT, chroma) amúgy is mono bemenetet kap. A `targetSampleRate`
**opcionális**: hiánya esetén a dekóder saját kimeneti rátája marad meg,
újramintavételezés nélkül; megadva lineáris interpolációval újramintavételezünk.
A drága, jóminőségű resample a DSP dolga, nem a beolvasásé.

A drót-formátum `Uint8List` little-endian float32, nem `Float64List`: 4 bájt
framenként 8 helyett — 10 perc 48 kHz-en 110 MiB helyett 55 MiB. A Dart oldal
little-endian hoston nulla-másolásos `Float32List.view`-t ad, egyébként
mintánként olvas, így az eredmény mindkét esetben helyes.

### 4. Nincs WAV-gyorsítótár a lejátszáshoz

A dekódolt PCM az ELEMZÉS bemenete. A lejátszás az **eredeti bájtokból** megy
(a meglévő lejátszó-út), mert egy dekódolt WAV-másolat megduplázná a tárhelyet,
és két igazságforrást csinálna egy fájlból.

### 5. Kapuk a Dart oldalon, a natív hívás ELŐTT

`PlatformAudioDecoder` sorrendben mér: platform → fájl létezik → fájlméret ≤
`maxFileBytes` → `probe()` → hossz ≤ `maxDuration`. Egy 3 GB-os film sosem jut el
a `MediaCodec`-ig. A limitek a core-ban (`AudioDecoderLimits`) duplikálva vannak,
mert az `InputLimits` a `audio_analysis` feature-ben él, a
`tool/check_architecture.dart` `coreMustNotImportFeatures` szabálya pedig tiltja
az importot. A duplikáció nem bizalmi kérdés: egy cella elhasal, ha a kettő
elcsúszik.

### 6. iOS: ebben a körben nincs implementáció

A Dart oldal nem-Androidon `audio.unsupported_platform`-mal tér vissza, és a
csatornát **meg sem szólítja**. Ugyanez a kód akkor is, ha a natív oldal nincs
regisztrálva (`MissingPluginException`) — így egy hiányzó regisztráció nem
`decoder_failed`-nek álcázza magát. Az iOS-út (`AVAssetReader`) külön kör.

### 7. Nincs manifest-engedély

A path a Storage Access Frameworkből jön, ami fájlonként ad hozzáférést az
appnak. Sem `READ_EXTERNAL_STORAGE`, sem `READ_MEDIA_AUDIO` nem kell, és
szándékosan nem is kérünk.

## Hibakód-térkép

| csatorna (`PlatformException.code`) | `FailureCode` |
|---|---|
| `no_audio_track` | `audio.no_audio_track` |
| `unsupported_container` | `audio.unsupported_container` |
| `decoder_failed` | `audio.decoder_failed` |
| `file_not_found` | `audio.file_not_found` |
| `too_long` | `audio.clip_too_long` (a MEGLÉVŐ kód) |
| `unsupported_platform` | `audio.unsupported_platform` |
| bármi ismeretlen | `audio.decoder_failed` |

## Következmények

- **Jó:** minden formátum, amit a készülék lejátszik; nulla APK-növekmény; a WAV-út
  érintetlen.
- **Ár:** Androidon kívül nincs dekódolás; a Kotlin csak CI-ban fordul, tehát a
  fordítási hibaosztály a `build-apk.yml`-ig nem derül ki.
- **A végső elfogadás** továbbra is egy valódi APK-futás valódi zenei fájlon — a
  host-oldali cellák a szerződést mérik, nem a dekódolást.
