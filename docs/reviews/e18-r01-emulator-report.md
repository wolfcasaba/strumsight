# E18-R01 — Emulátoros tesztjelentés (A + B rész)

> **Terv:** [`docs/rounds/e18-r01-emulator-test-plan.md`](../rounds/e18-r01-emulator-test-plan.md)
> **Ág:** `claude/song-editor-chord-audio-tbkokz` · **HEAD a méréskor:** `70c21acd`
> **Dátum:** 2026-09-09 · **Gazdagép:** a felhasználó Windows-laptopja (NEM az Oracle VM)
> **Szabály (ADR 0055):** ami bukik, az JELENTVE van, nem javítva. A javítás a
> következő kör dolga.

## Emulátor- és gazdagép-profil

| Tétel | Érték |
|---|---|
| Emulátor AVD | `Pixel_3a_API_34_extension_level_7_x86_64` |
| Eszköz | `emulator-5554` — "sdk gphone64 x86 64", android-x64 |
| Android | 14 (API 34) |
| platform-tools | `adb` 1.0.41 (35.0.2-12147458) |
| Host OS | Microsoft Windows 11 Home 25H2, build 10.0.26200.9278 |
| Flutter | 3.44.2 stable, revízió `c9a6c48423` |
| Dart | 3.12.2 |
| Engine | `04efd7c093d4e9281d5526ebcad6ecc60ba8badf` (rev 77e2e94772) |
| Locale | en-GB |
| Hangkimenet | emulátor → a laptop hangszórója |
| Hangbemenet | Extended controls → Microphone → "Virtual microphone uses host audio input" |
| Hangforrás (§7) | valódi gitár a laptop mikrofonjánál |

## §0 — Előkészítés: eltérések a tervtől (KÖRNYEZETI, nem termékhiba)

A terv §0-ja `/home/ubuntu/music-theory`-t és egy meglévő Flutter SDK-t
feltételez. Ezen a gazdagépen ez NEM állt fenn; a mért eltérések:

| # | Lelet | Hatás | Amit tettem |
|---|---|---|---|
| S1 | Nem volt Flutter SDK a gépen (sem Windowson, sem a WSL Ubuntu-ban). Az Android SDK, az `adb` és egy Pixel 3a API 34 AVD viszont megvolt. | A terv egyetlen lépése sem futtatható (a §1 kapu, a §15 parancsok és a `flutter run` mind SDK-t igényel). Az `apk-dist` ág legfrissebb APK-ja build 181 — az E18-R01 változásokat NEM tartalmazza, tehát nem helyettesíti. | A felhasználó jóváhagyásával telepítve: Flutter 3.44.2 (`C:\src\flutter`) — pontosan a CI által pinnelt verzió (`.github/workflows/*`: `flutter-version: '3.44.2'`), így a mérés összevethető a CI-jal. |
| S2 | A repó útvonala ékezetes: `C:\Users\kcsab\Saved Games\gitár trainer\strumsight`. | A `flutter analyze` mindig összeomlik: `FormatException: Unexpected end of input`, majd `analysis server exited with code 255`. A csonkolt JSON pontosan a workspace-URI listánál szakad meg (`...ner/strumsight/lib/"}],"capabilities":…`) — az LSP `Content-Length` bájtban számol, az olvasó karakterben, és az `á` miatt a kettő eltér. Junction (`mklink /J`) nem segít: a Flutter visszaoldja a valódi útra. | Ékezetmentes `git worktree`: `C:\src\ss-e18`, ugyanazon az ágon. Onnan a `flutter analyze lib/` → "No issues found", exit 0. Minden további mérés innen történt. |
| S3 | CRLF checkout: `core.autocrlf=true` (globális), a repóban nincs `.gitattributes`. | A `test/features/learn/legacy_scorer_baseline_test.dart` "replay matches the frozen JSON byte for byte" cellája bukott: a `File('test/fixtures/practice/legacy_scorer_baseline.json').readAsStringSync()` `\r\n`-t adott vissza, a generált oldal `\n`-t. Linuxos CI-n LF van, ott zöld. | A saját munkapéldányomat (`C:\src\ss-e18`) LF-re állítottam (`extensions.worktreeConfig` + `core.autocrlf=false`, `core.eol=lf`, majd teljes újra-checkout). A felhasználó fő munkapéldánya érintetlen. Az LF-es fa bájtra egyezik a linuxos CI-checkouttal. A cella ezután zöld → a diagnózis megerősítve. |
| S4 | A terv §8 `com.strumsight.app` csomagnevet ír. | A valódi `applicationId` `com.wolfcasaba.strumsight` (`android/app/build.gradle.kts`). | A helyeset használtam. A tervet érdemes javítani. |
| S5 | `flutter doctor`: hiányzó `cmdline-tools`, "Android license status unknown"; Visual Studio C++ komponensek hiánya. | Nem blokkolt: a licenc-hash fájlok megvannak (`$SDK/licenses/`), platform 34/35 és build-tools 35.0.1 telepítve. A VS-tétel irreleváns (nem Windows-desktopra építünk). | Nincs teendő; feljegyezve. |
| S6 | A `dart format` CRLF melletti viselkedése. | Nem kockázat: `Formatted 2326 files (0 changed)` — a `dart_style` megőrzi a fájl sorvégét. | — |

`flutter pub get` → `Got dependencies!` (exit 0).

## §1 — Automata kapu (`tools/round-gate.sh`)

Futtatás az ékezetmentes munkapéldányból, a terv §1 pontos argumentumlistájával.
A script a lépéseket külön processzekben futtatja; `flutter analyze && flutter test`
láncolás sehol nem történt.

A kapu az első pirosnál kilép (`exit 10`), ezért a maradék lépéseket
egyenként, külön `flutter test` hívásokkal mértem le, hogy a jelentés teljes
legyen — ez jelölve van a "mérés" oszlopban.

| # | Lépés | Eredmény | Darab | Mérés |
|---|---|---|---|---|
| 1 | `format` | PASS | 2326 fájl, 0 változott | kapu |
| 2 | `analyze` | PASS | "No issues found!" | kapu (csak ékezetmentes útról, S2) |
| 3 | `test test/core/audio/plucked_string_synth_test.dart` | PASS | +12 | kapu |
| 4 | `test test/core/music/chord_voicing_test.dart` | PASS | +7 | kapu |
| 5 | `test test/features/learn/` | PASS | +230 ~1 | kapu (S3/LF után; előtte 1 piros) |
| 6 | `test test/features/songs/` | **FAIL** | +132 −1 | kapu — itt állt meg (`GATE_EXIT=10`) → F1 |
| 7 | `test test/features/song_trainer/presentation/` | PASS | +55 | egyenként |
| 8 | `test test/features/chords/` | PASS | +29 | egyenként |
| 9 | `test test/features/tuner/` | PASS | +62 | egyenként |
| 10 | `test test/core/architecture_dependency_test.dart` | **FAIL** | +52 −1 | egyenként → F2 |
| 11 | `test test/ui/goldens/e15_r13_full_variant_matrix_test.dart` | PASS | +1179 | egyenként |
| 12 | `test test/ui/goldens/e13_r24_screens_golden_test.dart` | **FAIL** | −6 | egyenként → F3 |
| 13 | `test test/core/screen_size_guard_test.dart` | PASS | +45 | egyenként |
| 14 | `test test/app/routing/app_router_test.dart` | PASS | +25 | egyenként |
| 15 | `test test/features/songs/import/editor_draft_test.dart` | PASS | +5 | egyenként |
| 16 | `test test/tooling/placeholder_wiring_test.dart` | PASS | +12 | egyenként |
| 17 | `architecture` (`tool/check_architecture.dart`) | PASS | exit 0 | egyenként |
| 18 | `secrets` (`tool/ci/check_secrets.dart`) | PASS | exit 0 | egyenként |
| 19 | `l10n` (`tool/ci/check_l10n_parity.dart`) | PASS | exit 0 | egyenként |

A backend sáv nem futott: a kör nem ért a `backend/`-hez
(`git diff --name-only $(git merge-base HEAD origin/main) HEAD -- backend` → 0 fájl).

### F1 — `test/features/songs/import/import_flow_test.dart` (FAIL)

Cella: "A2: cancelling a confirmed import cleans the opened workspace"

```
Expected: empty
  Actual: [
            _Directory:Directory: 'C:\Users\kcsab\AppData\Local\Temp\e13r24-a2-ffbc9572\import-1'
          ]
A2: a cancelled import must not leave a temp file behind
test\features\songs\import\import_flow_test.dart 88:7  main.<fn>
```

Elvárt: `controller.cancel()` után a `tempRoot` üres.
Tapasztalt: az `import-1` munkakönyvtár ottmarad.
Értékelés: a HEAD kódja a CI-n zöld volt (10 272 teszt), ezért ez nagy
valószínűséggel Windows-specifikus (nyitott fájlkezelő melletti
`Directory.delete` szemantika, illetve a törlés időzítése), de a mérésből ez
NEM bizonyított — ezért FAIL marad. Nem javítottam.

### F2 — `test/core/architecture_dependency_test.dart` (FAIL)

Cella: "community is reachable only through public.dart (E09-R05) — everywhere
under lib/ imports community only via public.dart"

```
Expected: empty
  Actual: [
            'lib\features\community\application\use_cases\import_share_artifact.dart
             -> package:strumsight/features/community/domain/entities/share_artifact.dart'
          ]
```

Értékelés: a jelentett útvonal backslash-es. A vétkesnek jelölt fájl a
`features/community/`-n BELÜL van, és a saját domain-entitását importálja —
amit a szabály megenged. A teszt "a fájl a modulon belül van-e" ellenőrzése
előre-perjeles útra illeszt, ezért Windowson hamis pozitív. Gazdagép-műtermék,
nem architektúra-sértés. Nem javítottam.

### F3 — `test/ui/goldens/e13_r24_screens_golden_test.dart` (FAIL)

Hat pixel-golden tér el:

| Golden | Eltérés |
|---|---|
| `e13_r24_song_import_compact.png` | 2,32 % — 8758 px |
| `e13_r24_song_import_preview_compact.png` | 1,17 % — 4400 px |
| `e13_r24_song_editor_compact.png` | 0,76 % — 2868 px |
| `e13_r24_song_import_compact_scale2.png` | 0,69 % — 2589 px |
| `e13_r24_song_import_preview_compact_scale2.png` | 0,67 % — 2533 px |
| `e13_r24_song_editor_compact_scale2.png` | 0,75 % — 2824 px |

Értékelés: a goldenek a linuxos CI-n készültek; a Windows-os
betűraszterizálás eltér. Egybevág a HANDOFF-fal, amely szerint az
`e13_r24_song_editor_*` goldeneket "csak a user boxa tudja regenerálni".
Gazdagép-műtermék. Nem javítottam, a goldeneket NEM regeneráltam.

### Falszifikációs próbák (brief §6.1) — mindhárom megfelelt

| # | Mutáció | Elvárt piros cella | Eredmény |
|---|---|---|---|
| P1 | `plucked_string_synth.dart` → `strumOnsets`: `downstroke ? i : count-1-i` felcserélve | irány-cellák | PASS — pirosra váltott: "a down-stroke sweeps low → high, strictly increasing from 0" ÉS "an up-stroke sweeps high → low, strictly decreasing from 5*step" (exit 1) |
| P2 | `chord_audition.dart` → a `hasKnownQuality` kapu kikommentezve | "UNKNOWN quality is silence" | PASS — pirosra váltott: "a known root with an UNKNOWN quality is silence, not a major" (exit 1) |
| P3 | `song_preview_player.dart` → záró `stop()` helyett `Timer(_delay(totalSec - schedule.last.timeSec), stop)` | "stops on its own" | PASS — pirosra váltott: "the bar advances and the next chord sounds, then playback ends and stops on its own" (exit 1) |

Mindhárom mutáció `git checkout -- <fájl>`-lal visszaállítva; a mérés végén a
követett fájlok változatlanok (`git status --porcelain` követett sorok: 0).

## §2 — Kézi teszt: a legacy dalszerkesztő (Songs → New song)

### Hogyan mértem

A `flutter run` ezen a gazdagépen NEM tud a VM service protokollhoz
csatlakozni (S7 lent), ezért az appot `adb`-vel indítottam, és a konzol az
`adb logcat` volt — ugyanaz a kimenet, amit a terv §15 is használ.

A cellákat két forrásból mértem:

- **Objektív**: az Android akadálymentességi fa (`uiautomator dump`) adja a
  vezérlők `content-desc`-jét, `selected` állapotát és pontos koordinátáit; a
  hangot az `adb logcat` audio-eseményei (`requestAudioFocus` /
  `abandonAudioFocus` / `AudioTrack: stop(N) called with N frames delivered`)
  mérik ezredmásodperces időbélyeggel. Egy pengetés = 70 560 minta @44,1 kHz =
  **1,600 s** (a `strumPcm` `seconds: 1.6` alapértéke).
- **Fül**: a hangzás JELLEGE (gitárszerű-e, fogásonként eltér-e, megfordul-e a
  söprés iránya) — ezt a felhasználó ítéli meg; lásd a „Hallgatási cellák"
  szakaszt.

| # | Cella | Eredmény | Mért bizonyíték |
|---|---|---|---|
| E1 | Indítás, konzol | **PASS (megjegyzéssel)** | Nincs `MissingPluginException`, nincs `RenderFlex overflowed`, nincs kezeletlen kivétel. `Displayed … MainActivity: +6s205ms`, „Fully drawn". **Megjegyzés:** indításkor van egy KEZELT hiba a konzolon: `[error] tutor.knowledge_index.load_failed {code=tutorKnowledge.indexLoad.assetReadFailure}` (`AssetKnowledgeRepository.loadIndex` → `main.dart:32`). Az app ettől nem áll meg. |
| E2 | `C` chip koppintás | **PASS (gépi fele)** | Koppintás → `requestAudioFocus USAGE_MEDIA/CONTENT_TYPE_MUSIC` +0,2 s → `AudioTrack: stop() 70560 frames` = 1,600 s → `abandonAudioFocus`. A `C` chip megjelent a menetben, a ▶ aktívvá vált. A hangzás JELLEGE: hallgatási cella. |
| E3 | menet-chip CÍMKE koppintás | **PASS** | Koppintás 22:49:55.034 → hangfókusz +0,235 s → 70 560 minta. A menet utána változatlanul `C` + `E` (2 chip, nem duplázódott, nem törlődött). |
| E4 | menet-chip `×` | **PASS** | A `C` chip eltűnt (menet: csak `E`), és a rákövetkező 3 s-ban **NULLA** audio-esemény — törléskor nem szól semmi. |
| E5 | `E`, `Am`, `G`, `F#m` egymás után | **PASS (gépi fele)** | Minden hozzáadás külön audio-eseményt adott (3 chip → 3 `AudioTrack: stop`). Hogy fogásonként ELTÉR-e: hallgatási cella. |
| E6 | 8–10 gyors koppintás | **PASS** | 12 koppintás eszközoldali ciklusból, ~0,06 s-onként (szigorúbb a kért 0,2 s-nál): 19 `abandonAudioFocus` a sorozat alatt — minden új pengetés levágta az előzőt —, majd csak az utolsó csengett ki (1,45 s). **0** kivétel, **0** ANR, az app folyamata végig élt. |
| E7 | `C G Am F`, default minta, 90 BPM, ▶ | **PASS** | Pontosan **16 pengetés** (4 ütem × 4 ütés). Első 22:54:10.704, utolsó 22:54:20.835 → 15 köz / 10,131 s = **0,675 s/ütés** (elvárt 60/90 = 0,667 s, +1,3 %), drift nélkül. A vezérlő `content-desc`-je ▶-ról **„Stop preview"**-ra váltott. Lejátszás közben pontosan EGY ütem chipje `selected=true`. |
| E8 | végigfutás, magától leáll | **PASS** | Első pengetés 22:54:10.704 → a vezérlő záró `abandonAudioFocus`-a 22:54:21.34 = **10,636 s**. Elvárt `totalSec` = 4×4×60/90 = **10,667 s** (−0,3 %). A P3-mutáció dupla-várakozó változata ~11,30 s-ot adna → **nincs plusz ütem-várakozás**. Utána a vezérlő „Preview", és egyetlen chip sem kiemelt. |
| E9 | ▶, 2 ütem után ■ | **PASS** | 5 pengetés után a ■: az utolsó `abandonAudioFocus` a gombnyomás pillanatában, majd **4 s-ig egyetlen további hangesemény sem**. Vezérlő „Preview", 0 kiemelt chip. |
| E10 | ▶ közben mintaváltás | **PASS** | A preset-koppintás pillanatában 8/16 pengetésnél járt; utána **6 s-ig 0 további pengetés** — az elavult ütemterv nem játszódott le. A vezérlő „Preview"-ra állt, és a ▶ újraindítható: az újraindítás után 3 s alatt 9 pengetés (≈0,33 s-onként) az `Eighths` preset szerint. |
| E11 | `Eighths` preset + ▶ | **PASS (gépi fele)** | A pengetési sűrűség ~0,67 s-ról **~0,33 s-ra** duplázódott — a nyolcados rács életbe lépett. Hogy a fel-pengetésnél MEGFORDUL-e a söprés iránya: hallgatási cella. |
| E12 | ▶ közben back | **FAIL (kis mértékű, de mért)** | Elvárt: AZONNALI csend. Mért: `KEYCODE_BACK` 23:05:43.163 → **még egy pengetés 23:05:43.559-kor (+396 ms)** → a hangfókusz elengedése 23:05:43.855 (+692 ms). Ezután 6 s-ig csend. Két független futásban egybevágó: a másik (`Eighths` mintánál) 2 pluszpengetést adott (≈0,67 s). Valószínű ok: az előnézet a route-átmenet ideje alatt még fut (a provider autodispose-a a route tényleges eltávolításakor tüzel). Nem javítottam. **Az E12 második fele PASS**: visszalépve a szerkesztőbe a chip-koppintás újra szól. |
| E13 | üres menet → ▶ | **PASS** | Üres menetnél a ▶ szürke/tiltott; az első chip hozzáadása után narancs/aktív lett. |
| E14 | legnagyobb betű- és kijelzőméret | **PASS** | `font_scale=1.3`, `wm density 544` (alap 440). A fejlécsor „CHORD PROGRESSION" két sorba tördel, a ▶ [483–619] és a „Suggest" [619–1012] elfér az 1080 px-en. **0** `RenderFlex`/`overflowed` a konzolon, nincs sárga-fekete csík. *Megfigyelés (nem bukás):* a lebegő `Save` gomb rátakar a chip-rács jobb alsó sarkára — ez alap-sűrűségnél is így van. |
| E15 | mentés → Learn, jam-pad hangja | *(hallgatási cella, lásd lent)* | |

### §2 hallgatási cellák (a felhasználó fülével mérendők)

Ezek gépi bizonyítéka megvan (szól-e hang, milyen hosszan, milyen ütemben);
ami hiányzik, az a hangzás JELLEGE:

- **E2** — a `C` gitárszerű, lepengetett dúr-e (mély→magas söprés, ~1,5 s kicsengés).
- **E5** — `E` / `Am` / `G` / `F#m` füllel ELTÉR-e (E = 6 húr, F#m = barré, magasabb).
- **E11** — az `Eighths` preset fel-pengetésénél megfordul-e a söprés iránya (magas→mély).
- **E15** — a mentett dal Learn-futásában a jam-pad LÁGY SZINUSZ marad-e (nem a pengetett hang).

## §7 — Mikrofon-bekötés

*(mérés alatt)*

## §14 — Hordozó képernyők: részleges leletek

| # | Képernyő | Eredmény | Mért |
|---|---|---|---|
| H1 | Today hub | **PASS** | Új felhasználónak „Let's get started" + „Start your first practice" CTA, „0 Day streak", „0 of 10 min today", „View progress". |
| H2 | Practice area hub → Setup → Session → Result | **FAIL** | Két különböző út, két különböző eredmény — részletek lent (B3). |

### B3 — §14/H2: a V2 practice-session mikrofon-hibája néma üres képernyőre visz

**Két út, két eredmény:**

1. **Practice hub → „Browse by goal → Chords"** → a „Practice setup" képernyőn
   **„Practice unavailable — This practice isn't available."** A cél-alapú
   belépő tehát nem vezet futtatható sessionhöz.
2. **Today → „Start your first practice" → Practice hub → „Start recommended
   practice"** → a setup ÉL: „Quarter downstrokes", tempó 70, 4/4, Metronome /
   Accent on count 1 / Show chord hint kapcsolók, `Scoring profile:
   legacyLearnParity`, „Start practice". A mikrofon-engedélykérés helyesen
   megjelenik („Allow StrumSight to record audio?" — While using the app /
   Only this time / Don't allow); „While using the app" után a session
   képernyő Start/Exit gombokkal jön.

**A hiba.** A „Start" után a felvétel MEGBUKIK, és az app szó nélkül az üres
eredmény-képernyőre navigál:

```
[debug] audio.session.acquired {owner=live}
[debug] audio.session.released {owner=live}
[info]  practice_observation_capture_started
[warning] practice_observation_stream_failed {code=audio.capture_failed} error=<AudioFailure>
[warning] practice_session_observation_stream_failed {code=audio.capture_failed} error=<AudioFailure>
[info]  practice_observation_capture_stopped
```

A képernyőn ekkor: **„Practice result — No result to show. Finish a practice
session to see the breakdown."**

**Értékelés.** A `audio.capture_failed` kiváltó oka ezen a gazdagépen
NAGY VALÓSZÍNŰSÉGGEL környezeti: az emulátor virtuális mikrofonja nem volt
bekötve (§7/1, „Virtual microphone uses host audio input"), így nincs mit
megnyitni. A *termék* oldali lelet viszont a HIBAÚT: a felhasználó nem kap
kimondott hibát arról, hogy a mikrofon nem nyílt meg — az üres eredmény-képernyő
azt sugallja, hogy ő nem fejezett be egy sessiont, holott a felvétel bukott el.
Ez az `AGENTS.md` §5 „a hiba legyen KIMONDVA" elvárásával feszül.
Nem javítottam. A §7/1 bekapcsolása után a cella ÚJRAMÉRENDŐ, hogy elváljon a
környezeti ok a hibaút-lelettől.

### B4 — a Practice hub MINDEGYIK „Quick tool"-járól a rendszer-back KILÉPTETI az appot

Reprodukálható, mind a négy gyors-eszközre. A minta minden esetben:
app indítás → `Practice hub` tab → az eszköz csempéje → rendszer `KEYCODE_BACK`.

| Quick tool | Megnyílt (képernyő) | Back után | App előtérben? |
|---|---|---|---|
| Metronome | `Metronome` | Android indítóképernyő | **nem** (`dumpsys window` 0 találat) |
| Chord library | `Chord library` | Android indítóképernyő | **nem** |
| Tuner | `Tuner` | Android indítóképernyő | **nem** |
| Live | `LISTENING` | Android indítóképernyő | **nem** |

**Elvárt:** a back a Practice hubra visz vissza.
**Tapasztalt:** az app háttérbe kerül / bezárul.

Kiegészítő megfigyelés: amíg a Metronome képernyőn állunk, a `Practice hub`
alsó tab-ra koppintás sem navigál vissza (a képernyő marad) — vagyis ezek a
képernyők a shellben gyök-szintű útvonalként viselkednek, nem a hubra
push-olt route-ként. Nem javítottam.

## Környezeti leletek a mérés közben (folytatás)

| # | Lelet | Hatás |
|---|---|---|
| S7 | `flutter run -d emulator-5554` **nem tud a VM service protokollhoz csatlakozni**: `Error connecting to the service protocol: … HttpException: Connection closed before full header was received … /ws`. `--no-dds` sem segít; három futásból három. Az APK viszont megépül és települ, és az app elindul. | Nincs hot reload / DevTools. A konzolt `adb logcat` adta — ugyanaz a kimenet, amit a terv §15 is használ. A §2 mérését nem korlátozta. |
| S8 | Az első telepítéskor: `INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package com.wolfcasaba.strumsight signatures do not match newer version` — az emulátoron egy korábbi, más aláírású build volt. A Flutter eltávolította és újratelepítette. | Mellékhatásként FRISS telepítés lett, ezért az onboarding lefutott (ez a §8-nak kedvez). |
| S9 | Az emulátor folyamata a §2 E12 mérése közben **magától összeomlott** (`adb devices` üres, `qemu-system-x86_64` eltűnt). | Újraindítás után az AVD pillanatképből állt vissza, az app telepítve maradt. Az E12 mérése megismételve. A jelenség egyszer fordult elő. |
| S10 | A `AndroidManifest.xml`-ben nincs deep-link intent-filter (csak MAIN/LAUNCHER). | A V2 Song Trainer szerkesztő (`/song-trainer/editor/new`) `adb`-vel nem nyitható közvetlenül; csak a UI-n át (Learn lecke-lista → `songTrainerV2Enabled` mögötti kártya). |

## ⚠ B1 — VALÓDI TERMÉKHIBA: az AI-tutor tudásanyag NEM kerül be az APK-ba

Ez az egyetlen olyan lelet ebben a jelentésben, amely **nem** gazdagép-műtermék,
és **valós eszközön is jelentkezik**. A kör (E18-R01) nem okozta és nem érinti,
de a merge előtti teljes-app ellenőrzés célja épp az ilyen felderítése.

**Tünet a futó appon (emulátor, Android 14):** minden indításkor, a konzolon:

```
I/flutter: [error] tutor.knowledge_index.load_failed {code=tutorKnowledge.indexLoad.assetReadFailure} error=<FlutterError>
I/flutter: #0  PlatformAssetBundle.load.<anonymous closure> (package:flutter/src/services/asset_bundle.dart:332:13)
I/flutter: #1  AssetBundle.loadString (package:flutter/src/services/asset_bundle.dart:92:27)
I/flutter: #2  AssetKnowledgeRepository._loadDocument (…/asset_knowledge_repository.dart:116:11)
I/flutter: #3  AssetKnowledgeRepository.loadIndex (…/asset_knowledge_repository.dart:85:23)
I/flutter: #4  buildTutorProductionOverrides (package:strumsight/main.dart:32:21)
I/flutter: #5  _runAppWithSongTrainerRepositories (package:strumsight/main.dart:85:28)
I/flutter: #6  main (package:strumsight/main.dart:64:7)
```

**Mért ok.** A lemezen 11 fájl van:

```
assets/tutor_knowledge/manifest.json
assets/tutor_knowledge/en/{chord-changes,practice-short-loop,rhythm-counting,safety-pain,technique-relaxed-hand}-en.json
assets/tutor_knowledge/hu/{chord-changes,practice-short-loop,rhythm-counting,safety-pain,technique-relaxed-hand}-hu.json
```

A lefordított debug APK-ban viszont **egyetlen egy**:

```
$ unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep -i tutor_knowledge
   4991  assets/flutter_assets/assets/tutor_knowledge/manifest.json
```

A `pubspec.yaml` a könyvtárat deklarálja:

```yaml
  assets:
    - assets/tutor_knowledge/
```

A Flutter könyvtár-alapú asset-deklarációja **NEM rekurzív** — csak a
könyvtárban KÖZVETLENÜL lévő fájlokat csomagolja be, az `en/` és `hu/`
alkönyvtárak tartalmát nem. Ezért a `loadIndex` beolvassa a manifestet, majd az
első dokumentumnál `assetReadFailure`-t kap.

**Miért nem fogta meg a CI.** A `knowledge_manifest_test.dart` és a
`knowledge_retriever_test.dart` a FÁJLRENDSZERRŐL olvas (`tool/build_tutor_knowledge_manifest.dart`),
nem a becsomagolt `AssetManifest`-ből — ott mind a 11 fájl megvan. A hiba csak
az összeépített artefaktumban jelentkezik, amit egyetlen host-teszt sem néz.

**Hatás:** a `buildTutorProductionOverrides` tudás-index üres/ hibás marad,
tehát az AI-tutor visszakeresése (retrieval) tudásanyag nélkül indul. A hiba
KEZELT (az app nem omlik össze, „Fully drawn" 6,2 s), de a funkció csendben
csonka.

**Nem javítottam** (ADR 0055). A javítás a következő kör dolga; a nyilvánvaló
irány az `en/` és `hu/` alkönyvtárak külön felvétele a `pubspec.yaml`
`assets:` listájába, plusz egy őr, amely a BECSOMAGOLT `AssetManifest`-et méri,
nem a fájlrendszert.

## §15 — Automata teljes-app ellenőrzés

Minden parancs KÜLÖN processzben, egyenként; `analyze && test` láncolás sehol.
Az emulátort a §15 idejére leállítottam (S9 után az erőforrás-verseny elkerülésére).

| # | Parancs | Eredmény | Idő | Mért |
|---|---|---|---|---|
| 1 | `flutter analyze lib/ test/ tool/` | **PASS** | 100 s | „No issues found! (ran in 94.3s)" |
| 2 | `flutter test` (TELJES suite) | **FAIL** | 815 s | `+10069 ~21 -203` — 10 069 zöld, 21 kihagyott, **203 piros**. Osztályozás lent (B2). |
| 3 | `PROPERTY_SEED=4137 flutter test test/property` | **PASS** | — | `+122: All tests passed!` — **a property seed: `4137`** |
| 4 | `flutter test test/tooling/real_audio_dsp_baseline_test.dart` | **PASS** | 6 s | `+8: All tests passed!` — a valós-audio DSP alapvonal tartja magát |
| 5 | `flutter test test/e2e/full_app_walkthrough_test.dart` | **PASS** | 9 s | `+1: All tests passed!` |
| 6 | `dart run tool/check_screen_reachability.dart --format json` | **PASS** | 3 s | `measuredScreenCount: 96`, `reachableCount: 74`, **`unreachableCount: 22`**, `flagGatedCount: 27`. Alapvonal (`docs/release/full-app-verification.md`): 96 / 73 / **23** / 27 → az `unreachable` **CSÖKKENT** (23 → 22), tehát nem nőtt. |
| 7 | `flutter build apk --debug` | **PASS** | 141 s | `√ Built build\app\outputs\flutter-apk\app-debug.apk` |
| 8 | `adb install -r …app-debug.apk` + `adb logcat` | *(a §8–§14 bejárás alatt)* | | |

### B2 — a teljes suite 203 pirosa Windowson

A CI ugyanezen a kódon (`476b01d`, a HEAD-hez képest csak két docs-commit
különbség) **10 272 zöld, 0 piros** volt. A 203 piros itt a gazdagép-különbségből
ered; a mintázatok:

| Minta | Példa | Miért Windows-specifikus |
|---|---|---|
| POSIX fájlmód / symlink | `beta_release_notes_test.dart` „the bundle file mode is 0600", „a symlinked `--output` is refused"; `import_workspace_test.dart` „rejects traversal and symlink escapes" | Windowson nincs `chmod` 0600 és a symlink-szemantika eltér |
| Útvonal-elválasztó | `architecture_dependency_test.dart` (`lib\features\community\…`); `knowledge_manifest_test.dart` (`assets/tutor_knowledge\manifest.json` — KEVERT elválasztó) | a tesztek előre-perjeles útra illesztenek |
| Abszolút POSIX út a redakcióban | `beta_release_notes_test.dart` „an absolute POSIX path … is masked" | a maszkoló mintája platformfüggő |
| Pixel-golden | `e13_r24_screens_golden_test.dart` (6 cella) | a goldenek linuxos CI-n készültek |
| Temp-könyvtár törlése | `import_flow_test.dart` A2 | nyitott fájlkezelő melletti `Directory.delete` |

**Nem javítottam egyet sem, és egyetlen goldent sem regeneráltam.** A jelentés
célja a hű mérés; a 203 piros ezen a gazdagépen NEM minősíti a kört —
a kör mércéje a CI, ami zöld.

<!-- A §3, §8–§13, §16 szakaszok a mérés előrehaladtával kerülnek ide. -->
