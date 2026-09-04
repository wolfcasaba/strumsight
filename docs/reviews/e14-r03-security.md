# E14-R03 — Biztonsági / adatvédelmi review

Brief: `docs/rounds/e14-r03-model-activation-telemetry.md`
ADR: `docs/adr/0355-fail-visible-model-activation-telemetry.md`
Diff: `git diff a143e603..HEAD` (ág: `sonnet-impl/e14-r03-model-activation-telemetry`,
HEAD `9da47c0a`, 4 implementációs commit a pre-flight commit után)
Reviewer: Claude (Opus 5), biztonsági review · Dátum: 2026-09-04 · Kockázat: **high**
(AGENTS.md §15.1 — kötelező jelentés)

## Verdikt

**CLEAN**

CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0 · MINOR: 3 · NOTE: 4

Nem tárgyalható termékhatár (AGENTS.md §5) sérülését **nem mértem**. A kör nem
nyit hálózati kérést, nem kér engedélyt, nem ír tárba, nem érint secretet és nem
érint AI-providert; nyers audio és kamera-frame nem kerül új mezőbe. A három
MINOR mindegyike **latens** (ma nincs élő hívási út), de mindhárom egy-egy
*kimondott* ADR 0355-invariáns szerkezeti gyengeségére mutat, ezért a merge nem
tilos, de az E14-R04 bekötő kör előtt rendezendők.

---

## 0. Mit néztem végig (a scope mérése)

```
$ git -C /home/ubuntu/ss-sonnet-impl-e14-r03 diff --stat a143e603..HEAD
 docs/rounds/e14-r03-model-activation-telemetry.md  |  97 +++++
 lib/features/live/engine/dsp/live_pipeline.dart    |  84 ++++--
 lib/features/live/engine/ml/model_activation.dart  |  50 +++++
 lib/features/live/engine/ml/strum_crnn.dart        | 116 +++++++++-
 .../live/model/recognition_runtime_info.dart       | 151 +++++++++++++
 lib/features/live/providers/live_lab_provider.dart |  25 ++-
 lib/features/live/public.dart                      |   5 +
 test/features/live/model_activation_test.dart      | 202 ++++++++++++++++
 .../live/recognition_runtime_info_test.dart        | 130 +++++++++++
 9 files changed, 838 insertions(+), 22 deletions(-)
```

A 9 fájl **pontosan** a brief `allowed_paths` listája. Listán kívüli változás:
nincs. `pubspec.yaml` / `pubspec.lock` **nem** változott
(`git diff a143e603..HEAD -- pubspec.yaml pubspec.lock` → üres kimenet), tehát
**új dependency nincs**: a `package:crypto` már korábban is direkt függőség
(`pubspec.yaml:46 — crypto: ^3.0.7  # source SHA-256 provenance`). Új asset
nincs (a sérült fixture-ök futásidőben, `Directory.systemTemp` alatt jönnek
létre — §9 előírása teljesül).

`flutter test` / `flutter analyze` **nem futott** ebben a reviewban (az
orchestrátor kapuja már lefutott, a jelentett kimenet a kör §10-ében áll). Az
alábbi mérések grep + olvasás + **tiszta Dart próba** (`dart run`, a kör saját
forrásán) alapúak.

---

## 1. Kivétel-szöveg szivárgás (ADR 0355 §2/2. pont) — **TISZTA**

```
$ grep -n "catch" lib/features/live/model/recognition_runtime_info.dart \
    lib/features/live/engine/ml/model_activation.dart \
    lib/features/live/engine/ml/strum_crnn.dart \
    lib/features/live/engine/dsp/live_pipeline.dart \
    lib/features/live/providers/live_lab_provider.dart
lib/features/live/providers/live_lab_provider.dart:66:    } catch (_) {
lib/features/live/engine/ml/strum_crnn.dart:51:    } catch (_) {
lib/features/live/engine/ml/strum_crnn.dart:109:    } catch (_) {
```

Mind a három catch **`catch (_)`**, azaz a kivétel objektuma nevet sem kap —
`toString()`-je szintaktikailag nem is elérhető. A `live_lab_provider.dart:66`
ág a kör ELŐTT is ott volt (a diff nem érinti). A `strum_crnn.dart:43` az
`on PathNotFoundException` klóz, amely szintén nem köt változót.

A hibaok minden ágon a zárt `FallbackReason` enumból jön
(`recognition_runtime_info.dart:6-27`, 5 érték), és a szerializáció az enum
`name`-jét írja ki (`:113 'fallbackReason': fallbackReason?.name`) — nem indexet,
nem szöveget. `assert`-üzenet nem tartalmaz kivétel-adatot
(`model_activation.dart:16-19, 28-31`: fix, angol, adatmentes sztringek).

**Bizonyíték a méréshez, nem csak az állításhoz:** a redakciós kanári
(`test/features/live/model_activation_test.dart:179-201`) **megöli** azt a
mutációt, amely a `PathNotFoundException` szövegét tenné a fallback-infóba: a
kivétel `toString()`-je tartalmazza a `strumsight_canary_<n>` szegmenst, amit a
:194-197 sorok tiltanak. Ez a cella tehát *működőképes* a fallback ágra. A
korlátját lásd **S2**.

## 2. Fájlrendszer-út szivárgás az ÉRTÉK-oldalon (L260) — **részben mérve, lásd S1/S2**

Az EGYETLEN mező, amely útból származó értéket kaphat, a `strumModelId`, és
csak az **aktivált** ágon:

- `strum_crnn.dart:63` — `modelId: path.split('/').last`
- `strum_crnn.dart:122` — `strumModelId: modelId`

Minden **fallback** ág (`:44-58`, `:97-103`, `:110-116`, `live_pipeline.dart:35-39`)
kivétel nélkül a `RecognitionRuntimeInfo.fallback(...)` gyártófüggvényen megy
keresztül, amely a `strumModelId`-t **konstans `'none'`-ra**, a hasht üres
sztringre, a verziót 0-ra köti (`recognition_runtime_info.dart:36-49`). Az
út-származék tehát a fallback ágon **szerkezetileg** kizárt — ez helyes.

A live út (a production egyetlen élő útja) a `modelId`-t **konstansként** adja:
`live_pipeline.dart:43 modelId: 'live-crnn'`. Út oda sem kerül.

Ami marad: az aktivált, fájl-alapú ág (`activate(path)`) elválasztó-függő
alapnév-vágása (**S1**) és az, hogy erre az ágra nincs kanári (**S2**).

**„Van-e ilyen hívási út ma?" — nincs.** Mérve:

```
$ grep -rn "tryLoad\|\.activate(" --include=*.dart lib/ | grep -i crnn
lib/features/live/engine/ml/live_crnn_classifier.dart:128:  static LiveCrnnStrumClassifier? tryLoad(
lib/features/live/engine/ml/strum_crnn.dart:138:  static StrumCrnn? tryLoad(String path) => activate(path).model;
```

`lib/` alatt **egyetlen hívó sincs** sem a `StrumCrnn.activate`-re, sem a
`StrumCrnn.tryLoad`-ra, sem a `LiveCrnnStrumClassifier.tryLoad`-ra — kizárólag
tesztek és `test/tools/*` próbák hívják őket, mind **fix, relatív**
`assets/ml/...` úttal (`test/property/crnn_ab_property_test.dart:38,116`,
`test/tools/*`). A `path` ma tehát megbízható; felhasználó, import, deep-link,
backend vagy diagnosztika nem táplálja.

## 3. `strumModelSha256` mint ujjlenyomat — **TISZTA**

A hash a ténylegesen betöltött bájtokból számolódik (`strum_crnn.dart:124`), és
a bájtok forrása a production úton **kizárólag bundle-elt asset**:

`real_strum_engine.dart:186-204` — `_liveCrnnWeights()` a `rootBundle`-ből
tölti a `assets/ml/strum_crnn_live_3c.bin`, majd `assets/ml/strum_crnn_live.bin`
assetet, egyszer app-futásonként cache-elve; ezt adja át a `_DspInit`
`crnnWeights` mezője az izolátumnak, onnan a `LivePipeline` factory-ja
(`live_pipeline.dart:66-83`) az `activateBytes`-nak.

Következmény: a hash egy adott buildre **konstans**, minden telepítésen azonos →
eszköz- vagy felhasználó-azonosítóként **nem** viselkedhet. Felhasználói
audióból, mikrofonpufferből vagy importált fájlból képzett hash-ra vezető utat
nem találtam (a `recentPcm()` puffer sehol nem éri el az `activateBytes`-t —
`grep -rn "activateBytes" lib/` → 2 találat: a definíció és a
`live_pipeline.dart:42` hívás a súly-bájtokkal).

## 4. Fájlolvasás / untrusted bemenet — **ma megbízható; lásd N3**

`StrumCrnn.activate(String path)` → `File(path).readAsBytesSync()`
(`strum_crnn.dart:42`) az egyetlen új fájlolvasás. Hívási lánc a 2. pont
grepje szerint: **`lib/` alól nulla**, csak teszt/tool. `dart:io` import a
fájlban a kör előtt is megvolt (a diff nem adott hozzá `dart:io`-t).

Path traversal / zip / szimbolikus link: a kör nem csomagol ki semmit, nem
kezel felhasználói archívumot, nem épít utat felhasználói sztringből.

## 5. `LiveLabState.runtimeInfo` és a diagnosztika-feltöltés — **nem kerül a payloadba (mérve)**

Mérés:

```
$ grep -rn "runtimeInfo" lib/features/diagnostics/
(nincs találat)
$ grep -n "toJson" lib/features/diagnostics/model/diagnostics_session.dart
50, 72, 103
```

- A feltöltött hasznos teher `DiagnosticsSession.toJson()`
  (`diagnostics_uploader.dart:57 jsonEncode(session.toJson())`), amelynek
  kulcskészlete **fix és zárt**: `sessionId`, `appVersion`, `device`,
  `startedAt`, `surface`, `events`, `audioClips`
  (`diagnostics_session.dart:103-111`). `runtimeInfo` nincs benne, és a
  `DiagnosticsSession` nem is ismeri a típust.
- A feltöltést indító hívás `live_lab_provider.dart:76-80`:
  `upload(result, pcm, sr, surface: 'live')` — a `state.runtimeInfo`-t **nem
  olvassa**. A kör ezt a metódust nem is módosította (a diff csak a
  `LiveLabState` mezőt és a `reportRuntimeInfo` belépőt adta hozzá).
- A feltöltés consent-kapuzott marad: `diagnostics_uploader.dart:52-54` —
  `if (!consentGranted || apiClient == null) return failed;`. Ezt a kör nem
  érinti.

Tehát a `runtimeInfo` ebben a körben **semmilyen kimenő hasznos teherbe nem
kerülhet**. (A Lab meglévő, opt-in audio-feltöltése a kör előtti állapot, nem e
kör lelete.)

Kiegészítés: a `live_lab_panel.dart` sem olvassa (`grep -n runtimeInfo
lib/features/live/widgets/live_lab_panel.dart` → nincs találat), tehát production
UI-ra technikai hibakód sem kerül (ADR 0355 §5.3 teljesül).

## 6. Prompt-injection / hálózat / engedély / tár / secret — **N/A (grep-bizonyíték)**

```
$ grep -nE "dio|Dio|http|package:flutter/services|SecureStorage|SharedPreferences|KeyValueStore|MethodChannel|print\(|debugPrint|developer\.log|stderr|stdout" \
    lib/features/live/model/recognition_runtime_info.dart \
    lib/features/live/engine/ml/model_activation.dart \
    lib/features/live/engine/ml/strum_crnn.dart \
    lib/features/live/engine/dsp/live_pipeline.dart \
    lib/features/live/public.dart
(egyetlen kód-találat sincs; a `live_lab_provider.dart` találatai kommentek,
 illetve a kör előtti import-készlet)
```

- **AI-provider / prompt / tool-calling:** a diff egyetlen sora sem érint
  provider-adaptert, promptot, tudásbázis-chunkot vagy tool-allowlistet. Az új
  `RecognitionRuntimeInfo` egyetlen sztring-mezője sem kerül LLM-promptba (nincs
  fogyasztója az `ai_tutor` alatt: `grep -rn "RecognitionRuntimeInfo"
  lib/features/ai_tutor/` → nincs találat).
- **Hálózat:** nincs új `Dio`/HTTP hívás. Kijelentkezett, diagnostics-off
  állapotban a kör nem indít kérést (a 5. pont mérése szerint a runtimeInfo
  semmilyen kimenő útra nem lép).
- **Engedély:** nincs új platform permission; a mikrofon-tulajdonlás
  (`real_strum_engine`) érintetlen.
- **Tár / secret:** nincs írás sem `SecureStore`-ba, sem preferenciába; nincs új
  token, kulcs vagy jelszó. A tesztfixture hash
  (`recognition_runtime_info_test.dart:14-15`) egy 62 karakteres, nyilvánvalóan
  szintetikus hex-minta, nem valódi kulcs.
- **Offline alapélmény (§5/4):** a fallback VISELKEDÉSE bitre azonos maradt — a
  `classifier: crnnActivation.model` (`live_pipeline.dart:108`) ugyanazt a
  `null → heurisztika` szemantikát adja, mint a korábbi `_tryLiveCrnn`. A kör
  §10-ének falszifikációs próbája (a `model` → `model!` mutáció 4 fallback-cellát
  pirosra vitt) ezt méri; ezt a próbát **nem futtattam újra** (lásd „Amit nem
  mértem").

## 7. `assert`-alapú invariánsok release-ben — **S3**

Lásd az S3 leletet: mérve, van biztonsági (telemetria-hitelességi) következménye,
de ma latens.

---

## Megállapítások

### S1 / **MINOR** — az alapnév-vágás elválasztó-függő: Windows-úton a TELJES út (benne a felhasználónévvel) a `strumModelId`-be kerül

**Hely:** `lib/features/live/engine/ml/strum_crnn.dart:63` —
`modelId: path.split('/').last`, onnan `:122 strumModelId: modelId`, majd
`recognition_runtime_info.dart:105-127` (`toJson`) és `:119-128` (`toString`).

**Sértett szabály:** ADR 0355 §5.4 + „Amit ez a döntés TILT" 5. pont
(„a `RecognitionRuntimeInfo` bővítése … abszolút úttal”), valamint a mező saját
dokumentációja: *„The activated model's asset FILENAME only — no directory,
never a full path"* (`recognition_runtime_info.dart:82-83`). Az invariáns
**állítás**, nem szerkezeti igazság.

**Mérés (tiszta Dart, a kör forrásából kimásolt kifejezés):**

```
$ dart --enable-asserts run <scratch>/probe/main.dart
modelId(32 ch) = "strum_crnn_live_3c.bin"
modelId(35 ch) = "m.bin"
modelId(57 ch) = "C:\Users\Kovacs Csaba\AppData\Local\Temp\strumsight\m.bin"
```

**Failure scenario:** egy Windows dev/CI hoston (a repó `flutter_secure_storage`
v10 / win32 pinje szerint a host-compile Windowsra is számít) bármely hívó, aki
abszolút úttal aktivál — pl. egy jövőbeli `activate(File(...).path)` egy
`Directory.systemTemp` alatti súlyfájlra —, `strumModelId`-ként a teljes utat
kapja, benne a Windows-felhasználónévvel. Ez az érték a `toString()`-en és a
`toJson()`-on át bármely jövőbeli exportba/diagnosztikába bekerül. POSIX-on a
vágás helyes (a fenti próba 2. sora).

**Miért csak MINOR:** ma nincs `lib/` alatti hívó (2. pont grepje), a production
live út konstans `'live-crnn'` id-t használ, és a tesztek relatív POSIX-utat
adnak — tehát ma **nem reprodukálható éles szivárgás**, csak a stabilan kimondott
invariáns szerkezeti gyengesége.

**Javasolt irány:** az alapnév-vágás legyen elválasztó-független (mindkét
szeparátor kezelése, vagy `package:path` `basename`), és a `RecognitionRuntimeInfo`
konstruktora utasítsa vissza (valódi `throw`, nem `assert`) azt a
`strumModelId`-t, amely elválasztó-karaktert tartalmaz — így az invariáns
szerkezetivé válik.

### S2 / **MINOR** — az acceptance 4. pont kanárija csak azt az ágat méri, amely konstrukció szerint `'none'`

**Hely:** `test/features/live/model_activation_test.dart:179-201` (a kanári-cella)
vs. `lib/features/live/engine/ml/strum_crnn.dart:39-50` (a mért ág) és `:61-63`
(a NEM mért ág).

**Sértett szabály:** a kör R4 revíziója és ADR 0355 §6 („a redakciót kanári-próba
méri … a szerializált **érték** ezt a szegmenst nem tartalmazza"), valamint
`docs/LESSONS.md` L260.

**Failure scenario / szerkezeti bizonyíték:** a kanári hívása
`StrumCrnn.activate(missingPath)` egy **nem létező** fájlra
(`model_activation_test.dart:186-188`). Ez a hívás a `strum_crnn.dart:43`
`on PathNotFoundException` ágon **visszatér a 44-50. sorban**, tehát a
`:61-65` `activateBytes(..., modelId: path.split('/').last, ...)` hívás — az
EGYETLEN hely, ahol útból származó érték keletkezik — **soha nem fut le a kanári
alatt**. Az állítás `expect(result.info.strumModelId, 'none')` (:199) így
konstrukció szerint igaz: a `RecognitionRuntimeInfo.fallback` hardkódolja
(`recognition_runtime_info.dart:43`).

Igazságos ellenpont (mérve): az alapnév-vágás **nincs teljesen fedetlenül** —
`model_activation_test.dart:24,33` egy könyvtárat is tartalmazó relatív útból
(`assets/ml/strum_crnn_live_3c.bin`) a csupasz fájlnevet várja, tehát a
`modelId: path` mutációt ez a cella pirosra viszi. Ami hiányzik: **kanári az
aktivált ágon** — egyedi útszegmenssel rendelkező, ténylegesen betölthető
fájlból, a `toString()`/`toJson()` értékei ellen.

**Javasolt irány:** a kanári-cella másolja az igazi asset bájtjait egy
`strumsight_canary_<n>` temp-könyvtárba, aktiváljon **onnan**, és mérje, hogy sem
a `toString()`, sem a `toJson()` értékei nem tartalmazzák a temp-gyökeret és a
kanári szegmenst. Ez a cella S1-et is elkapná (Windows hoston pirosan).

### S3 / **MINOR** — a `ModelActivation` konzisztencia-invariánsai release buildben eltűnnek, és „aktivált" telemetriát engednek fallback mellett

**Hely:** `lib/features/live/engine/ml/model_activation.dart:16-19` és `:28-31`
(két `assert`), hatásuk: `:49 bool get isActivated => model != null`.

**Sértett szabály:** AGENTS.md §5/5. (gyenge/hiányzó bizonyosság nem jelenhet meg
biztos állításként), ADR 0271 §1 (`UNKNOWN > CONFIDENTLY WRONG`), és ADR 0355
alapcélja (a mérés hitele).

**Mérés (a kör két új fájljának valódi kódja, csak a `package:meta` import
levágva; `dart run` mindkét assert-módban):**

```
--- asserts ON (a tesztek módja) ---
activated(...) THREW: _AssertionError
fallback(...) THREW: _AssertionError

--- asserts OFF (release APK módja) ---
activated(model, fallbackInfo) CONSTRUCTED: isActivated=true reason=parseFailed
fallback(assetMissing, parseFailedInfo) CONSTRUCTED: reason=parseFailed
```

**Failure scenario:** release buildben egy `ModelActivation.activated(model,
info)` hívás olyan info-val, amelyen `fallbackReason != null`, csendben létrejön:
`isActivated == true`, miközben a telemetria fallbacket jelent — az E14-R06…R09
kiértékelő körök pontosan ezt a párost olvasnák. A második sor még élesebb:
`fallback(assetMissing, …)` a **kért kódtól eltérő** (`parseFailed`) kódot
jelenti, mert az info-t nem a `reason`-ből építi. A tesztek ezt szerkezetileg nem
foghatják meg (assert ON → dobás), az APK-gate pedig assert OFF-fal fut.

**Miért MINOR és nem MAJOR:** ma mind a hat konstrukciós hely a `strum_crnn.dart`
/ `live_pipeline.dart` belsejében van, és mindegyik konzisztens párt ad; a típus
nincs a `public.dart` barrelben
(`grep -n export lib/features/live/public.dart` → a `model_activation.dart` nem
szerepel), tehát featureön kívülről ma nem építhető inkonzisztens példány.

**Javasolt irány:** az inkonzisztens állapot legyen **reprezentálhatatlan** —
a `fallback` gyártófüggvény a `reason`-ből ÉPÍTSE az infót (ne fogadjon el
külön infót), az `activated` pedig valódi `ArgumentError`-t dobjon (release-ben
is), vagy az `isActivated` a `info.fallbackReason == null`-ból származzon, hogy a
két forrás ne csúszhasson szét.

### N1 / NOTE — a live út `modelId`-ja nem különbözteti meg a két live assetet

`live_pipeline.dart:43` a konstans `'live-crnn'`-t adja, miközben a
`real_strum_engine.dart:193-194` két assetet próbál sorban
(`strum_crnn_live_3c.bin`, majd `strum_crnn_live.bin`, eltérő osztályszámmal).
A `strumModelSha256` megkülönbözteti őket, a `strumModelId` nem. A kör ezt
kimondottan az E14-R04-re halasztja (R3), és a kód kommentje is jelzi — ezért
NOTE. Kockázat, ha nyitva marad: egy `strumModelId`-re kulcsolt accuracy-export a
2 osztályos assettel mért eredményt a 3 osztályosnak tulajdonítaná (§5/5.
hamis-bizonyosság mag).

### N2 / NOTE — `RecognitionRuntimeInfo.fromJson` `Error`-t dob, nem `Exception`-t

`recognition_runtime_info.dart:51-64`: `json['strumModelId'] as String`
(`TypeError`), `json['strumModelVersion'] as int` (`TypeError`),
`FallbackReason.values.byName(...)` (`ArgumentError`). Mindkettő `Error`
leszármazott, tehát egy `on Exception catch` őrből **kiszökik**. Ma nincs hívója
(`grep -rn "RecognitionRuntimeInfo.fromJson" lib/` → nincs találat), de a típus
már a `public.dart` barrelben van, és a `fromJson` a természetes belépő, ha az
E14-R04 vagy az accuracy-export lemezről / izolátum-üzenetből dekódol. Irány:
fail-closed dekódolás (`JsonRecordException`-alapú `require*` segédek, ismeretlen
enum-névre zárt visszaesés), mielőtt az első hívó megjelenik.

### N3 / NOTE — `CrnnStrumNet.parse` fejlécből vezérelt allokációja továbbra sincs korlátozva (előzmény, nem e kör hozadéka)

`crnn_strum_net.dart:56-70`: a `count`, `nameLen`, `ndim`, `dims[]` mind a fájlból
olvasott `u32`, és `final data = Float64List(n)` az `n = dims` szorzatból foglal —
a bájthossz ellenőrzése előtt. Egy preparált súlyfájl (`dims=[0xFFFFFFFF]`)
gigabájtos allokációt kérne. **Ma nem elérhető untrusted bemenettel:** a bájtok
forrása kizárólag bundle-elt asset (3. pont), fájl-alapú hívó pedig `lib/` alatt
nincs (2. pont). A kör új fejléc-előellenőrzése (`strum_crnn.dart:90-104`) a
magicet és a verziót zárja, méretkorlátot nem ad. Az a kör, amely valaha
letöltött / oldalról betöltött modellt aktivál, ezt a határt köteles lezárni
(ADR 0292 integritás-szerződése az elsődleges védelem).

### N4 / NOTE — a hash egyszeri költsége mérve, nem a per-frame úton

`assets/ml/strum_crnn_live_3c.bin` = 1 456 887 bájt (`ls -l`). A
`crypto.sha256.convert(bytes)` (`strum_crnn.dart:124`) **pipeline-onként egyszer**
fut, a `factory LivePipeline` konstruktorban (`live_pipeline.dart:66-83`), a
**DSP-izolátumban** (`real_strum_engine.dart:216-222` `_dspEntry`), nem az
UI-szálon és nem a `addChunk` úton. A §9 „nem kerülhet a per-frame útvonalra"
kockázat szerkezetileg zárva: a `runtimeInfo` getter
(`live_pipeline.dart:305`) egy előre kiszámolt mezőt ad vissza.

---

## Amit NEM mértem (kimondva)

1. **A gate újrafuttatását** (`tools/round-gate.sh`, `flutter test`,
   `flutter analyze`) — a feladat kifejezetten tiltotta; a §10-ben közölt
   kimenetet nem verifikáltam.
2. **A §10 falszifikációs próbáját** (a `model!` mutáció) nem játszottam újra;
   a fallback-viselkedés változatlanságát a diff olvasásából
   (`classifier: crnnActivation.model`, azonos null-szemantika) állapítottam meg.
3. **Windows hoston nem futtattam** semmit — az S1 bizonyítéka a
   `path.split('/').last` kifejezés Linuxon reprodukált kimenete Windows alakú
   bemenetre, nem valódi Windows futás.
4. **A CI-run** (`build-apk.yml`) állapotát nem néztem — az orchestrátor hatásköre.
