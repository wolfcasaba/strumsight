# E99-R04 (GOV-06) — Review

Brief: `docs/rounds/e99-r04-gov-06-real-audio-dsp-baseline.md`
Diff: `git diff dc201524...d3c8a516` (`codex/e99-r04-gov-06-real-audio-dsp-baseline`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-09
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 4

Ez egy mérési kör: egy önálló Dart benchmark (`tool/benchmarks/real_audio_dsp_baseline.dart`)
a bájtra változatlan, alapértelmezett `const ClipAnalyzer()`-t futtatja 82 valódi
telefonos gitárfelvételen, és a mért akkord/onset/BPM-pontosságot egy
elkötelezett riportba írja. A review a jelentett számokat **saját, független
futtatással** reprodukálta — nem csak a diffet olvasta.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Valódi `ClipAnalyzer`, alapértelmezett konstrukció, `lib/` változatlan | ✅ | `tool/benchmarks/real_audio_dsp_baseline.dart:480` `final analyzer = const ClipAnalyzer();`; saját `git diff --stat dc201524 HEAD` (mindkét klónban) 0 `lib/` útvonal |
| A2 | Onset-tűréshatár hármas (49999/50000/50001 µs) | ✅ | `test/tooling/real_audio_dsp_baseline_test.dart:8-20`; saját futtatás zöld; saját mutáció (`<=`→`<`) a 50000 µs cellát PIROSRA váltotta (`Expected: <1> Actual: <0> deltaUs=50000`), visszaállítás után zöld |
| A3 | Nincs újrafelhasználás a párosításban | ✅ | teszt 22-32. sor; kézzel nyomon követve (2 GT esemény, 1 predikció, mindkettő 50000 µs-on belül → csak 1 találat); saját futtatás zöld |
| A4 | Fedetlen esemény = hibás találat, nem kihagyott | ✅ | teszt 34-44. sor; kézzel nyomon követve: `support=1, correct=0, recall=0` a nem fedett eseményre |
| A5 | Címke-normalizálás hatcellás mátrixa | ✅ | teszt 46-66. sor; mind a 6 cella kézzel ellenőrizve (`Csus4`/`Cm`/bare-root-as-major helyesen elutasítva, `Bb`≡`A#` helyesen elfogadva) |
| A6 | Baseline számolva, nem hard-kódolva | ✅ | teszt 68-81. sor; a valódi korpuszon **18,8323%** (2216/11767) — egyezik az ADR 0199 pre-flight mérésével |
| A7 | Riport kötelező elemei (osztályonkénti bontás, baseline, moll-részhalmaz, 3 onset-tűrés, BPM+kizárás) | ✅ | `docs/eval/real-audio-dsp-baseline.md` — mind a 12 címke jelen (a support-ok összege 11767, kézzel ellenőrizve), baseline+moll-részhalmaz kiemelve, mindhárom tűréshatár (25/50/100 ms) táblázatban, BPM-módszertan+kizárási kritérium (0 kizárás, kimondva) |
| A8 | Reprodukálhatósági blokk | ✅ | riport „Reprodukálhatóság és korlátok" szakasz: parancs, 82/82 fájlszám, 11767 esemény, SHA-256, „nem reprodukálható a boxon kívül" kimondva |
| A9 | Nincs küszöb/kapu | ✅ | kódolvasás: `exitCode` csak usage-hibára (64) és hiányzó corpus-dirre (66) áll, sosem a mért számra; `.github/` diff üres (mindkét independens `git diff --stat`) |
| A10 | Unit teszt nem hivatkozik a korpuszra | ✅ | saját `grep -c "ml/data" test/tooling/real_audio_dsp_baseline_test.dart` → **0** |
| A11 | Gate zöld | ✅ | saját, izolált `/tmp/review-e99-r04` klónban `tools/round-gate.sh test/tooling test/features/analyze` → mind a 7 lépés zöld (lásd lent) |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.**

```
docs/eval/real-audio-dsp-baseline.md               | 872 +++++++++++++++++++++
docs/rounds/e99-r04-gov-06-real-audio-dsp-baseline.md | 86 +-
test/tooling/real_audio_dsp_baseline_test.dart     |  83 ++
tool/benchmarks/real_audio_dsp_baseline.dart       | 625 +++++++++++++++
4 files changed, 1657 insertions(+), 9 deletions(-)
```

Pontosan a brief négy `allowed_paths` bejegyzése; `docs/eval/` új könyvtár, ahogy
a brief előírta. `scope_audit=ok` a jelzésfájlban (implementer-oldali automatikus
audit), és a review saját, független `git diff --stat` hívása is ugyanezt
mutatja.

## Független mérés-reprodukció (a review saját futtatása)

A review MÉRT, nem csak olvasott. Saját, izolált `/tmp/review-e99-r04` klón,
friss `flutter pub get`+`gen-l10n`, a korpusz **valódi másolatként** (nem
szimlinkkel — lásd Megfigyelés lent) bemásolva, majd:

```bash
~/flutter/bin/flutter test --dart-define=REAL_AUDIO_DSP_BASELINE_CORPUS=ml/data/klangio \
  tool/benchmarks/real_audio_dsp_baseline.dart
```

Az eredmény **bájtra egyezik** a commitolt riporttal minden ellenőrzött mezőn:

| Mező | Riport | Saját futtatás |
|---|---|---|
| akkord-pontosság | 0.6706892156029575 | 0.6706892156029575 |
| többségi baseline | G-major, 2216/11767, 0.1883232769609926 | ugyanaz |
| moll-részhalmaz | 185/222, 0.8333333333333334 | ugyanaz |
| onset F1 @25/50/100ms | 0.4042664942830592 / 0.6739121651650438 / 0.8520059795563816 | ugyanaz mindhárom |
| BPM MAE | 45.06716069579421 | ugyanaz |
| korpusz SHA-256 | `4880fac…315827` | ugyanaz |
| feldolgozott/kihagyott | 82/82, 0 kihagyott | ugyanaz |

Ez a szintű determinisztikus egyezés (11 767 esemény + 82 BPM-számítás
tizedesjegyre pontos egyezése egy teljesen független processzben) erős
bizonyíték arra, hogy a szám valódi futtatásból származik, nem bemondás.

## Megállapítások

Nulla BLOCKER/MAJOR/MINOR. Négy NOTE, mindegyik nem blokkoló.

### N1 — NOTE — A brief szó szerinti `dart run` parancsa nem futtatható; a helyettesítés dokumentált és verifikáltan ártalmatlan

- **Fájl:** `docs/eval/real-audio-dsp-baseline.md:30`, `docs/rounds/e99-r04-gov-06-real-audio-dsp-baseline.md:520-522`
- **Megfigyelés:** a brief §7 által előírt `~/flutter/bin/dart run tool/benchmarks/real_audio_dsp_baseline.dart ml/data/klangio` piros: a `ClipAnalyzer` tranzitívan `dart:ui`-t importál, ami a sima Dart VM-en nem elérhető (`Dart library 'dart:ui' is not available on this platform`). Terra emiatt `flutter test --dart-define=REAL_AUDIO_DSP_BASELINE_CORPUS=... tool/benchmarks/real_audio_dsp_baseline.dart`-ra váltott.
- **Miért nem BLOCKER:** (1) a helyettesítés a `lib/`-et NEM módosítja (A1 zöld); (2) a `main()` továbbra is sima `void main(List<String> arguments)`, tehát a script elvben `dart run`-nal is futna egy olyan környezetben, ahol a `ClipAnalyzer` importlánca nem húzna be `dart:ui`-t — ez a box/csomaggráf tulajdonsága, nem a harness tervezési hibája; (3) a review saját, független futtatása **bájtra egyező** számokat adott, ami kizárja, hogy a Flutter-tesztrunner-környezet bármilyen mérési torzítást vezetne be; (4) a helyettesítés mindkét kötelező helyen (riport + brief §10) átlátszóan dokumentált, nem elhallgatott.
- **Irány:** nincs kötelező teendő. Follow-up (opcionális, nem e kör hatóköre): ha a `dart:ui` import forrása azonosítható és elkerülhető egy jövőbeli, tisztán-Dart mérőeszköz-célra szánt exportfelülettel, a `dart run` közvetlenül is futtathatóvá válhatna.
- **Státusz:** OPEN (informatív, nem blokkoló).

### N2 — NOTE — A helyettesített `flutter test` hívás sikeres mérésnél is nem-nulla kilépési kóddal zár

- **Megfigyelés:** mivel a `tool/benchmarks/real_audio_dsp_baseline.dart` `main()`-je nem `test()` blokkokat regisztrál, a Flutter-tesztrunner "No tests ran. / No tests were found." üzenettel és **nem-nulla shell exit code**-dal zár — a review saját futtatásán is (`EXIT_CODE=79`) — FÜGGETLENÜL attól, hogy a mérés maga hibátlanul lefutott és a teljes JSON-kimenet helyesen megjelent. Ez a `flutter test` keretrendszer saját konvenciója, NEM a harness A9 szerinti eredmény-alapú kapuja (a harness `exitCode`-ot csak usage-hibára és hiányzó corpus-dirre állít, sosem a mért számra — kódolvasással megerősítve).
- **Hatás:** egy jövőbeli, a parancsot kézzel újrafuttató személy tévesen hihetné, hogy a mérés elhasalt, ha csak a shell exit code-ot nézi.
- **Irány (opcionális, nem blokkoló):** a riport reprodukálhatósági blokkja kiegészíthető egy mondattal: „a `flutter test` parancs nem-nulla kilépési kóddal zár, mert a fájl nem `test()`-alapú — ez várt, a mérési eredmény a stdout JSON-ban van, nem a kilépési kódban."
- **Státusz:** OPEN (dokumentációs finomítás, nem blokkoló).

### N3 — NOTE — (biztonsági review átvéve) lokális build-útvonal a csonkítatlan kimenetben

- **Fájl:** `docs/eval/real-audio-dsp-baseline.md:88`
- **Megfigyelés:** a beágyazott nyers kimenet egy sora (`00:00 +0: loading /home/ubuntu/ss-codex-e99-r04/tool/benchmarks/...`) a build-környezet abszolút útvonalát és a userless-t (`ubuntu`) commitolja. Nem secret/credential (a dedikált security-review is ezt találta, NOTE szinten).
- **Irány:** opcionális kurálás egy jövőbeli riport-frissítésnél; nem e kör hatóköre.
- **Státusz:** OPEN.

### N4 — NOTE — (biztonsági review átvéve) a skip-error string elvben korpusz-eredetű szöveget echózhatna

- **Fájl:** `tool/benchmarks/real_audio_dsp_baseline.dart:445-447,526-531`
- **Megfigyelés:** a `_SkippedRecording.error = error.toString()` egy jövőbeli, malformed `.strums`-fájlt tartalmazó korpusz esetén a hibás sort/címkét visszhangozhatná a commitolt riportba. Ebben a futásban `skippedRecordings: []`, tehát semmi nem szivárgott.
- **Irány:** ha egy jövőbeli korpusz érzékeny szöveget hordozhatna a `.strums` fájlokban, a hibaüzenetet redaktálni érdemes kurálás előtt.
- **Státusz:** OPEN (nagyon alacsony prioritás).

## Kódkorrektség — kézi nyomkövetés (a review saját munkája)

A kétoldali mohó onset-párosítást (`matchOnsetsUs`) és a címke-normalizálást
(`labelsMatch`) a review kézzel, több szélső esetre lefuttatta (nem csak a
kipinnelt teszt-cellákra) — a mohó, rendezett-sorrendű párosítás a maximális
számosságú illesztésre bizonyítottan optimális ezen az 1D, fix-tűréshatáros
feladaton (a klasszikus intervallum-illesztési eredmény), és minden kézzel
próbált eset (beleértve az „egy predikció két kompatibilis GT-esemény között"
helyzetet) a helyes/maximális illesztést adta.

Egy pozitív minőségi megfigyelés: az implementáció útközben saját magától
talált és javított egy hibát (a `Bb-major` belső enharmonikus normalizálása
`A#-major` néven jelent volna meg a per-label bontásban) — a §5.3 „a
ground-truth eredeti 12 címkéjét kell megőrizni a riportban" követelmény
sérülését, MIELŐTT a végleges mérést lezárta volna. Ez a `labelsByCanonical`
mechanizmusban látszik (`tool/benchmarks/real_audio_dsp_baseline.dart:452-455`).

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer) | Ellenőrizve (review, saját `/tmp` klón) |
|---|---|---|
| format | zöld | ✅ zöld (1216 fájl, 0 változott) |
| analyze | zöld | ✅ zöld (0 lelet) |
| test test/tooling | 52 zöld | ✅ 52 zöld (a fentiek + saját mutációs próba) |
| test test/features/analyze | zöld | ✅ 64 zöld |
| architecture | zöld | ✅ zöld (12 allowlisted deviation, változatlan) |
| secrets | (nem állítva) | ✅ zöld (2096 fájl, 0 lelet) |
| l10n | (nem állítva) | ✅ zöld (en→hu, 1019 üzenet) |
| CI (teljes suite + property + APK) | — | orchestrátor lépése, e review után |

## Biztonsági review

Dedikált `security-reviewer` ágens (kötelező, `risk = "high"`):
**PASS, 0 CRITICAL/BLOCKER/MAJOR/MINOR**, 2 NOTE (N3/N4 fent átvéve). Zéró
hálózat, zéró secret, `lib/` bájtra változatlan, path-traversal strukturálisan
kizárva. Teljes jelentés: [`e99-r04-gov-06-real-audio-dsp-baseline-security.md`](e99-r04-gov-06-real-audio-dsp-baseline-security.md).

## Merge-döntés

ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → **merge
mehet** a CI-dispatch (teljes suite + property + build) zöld visszaigazolása
után.
