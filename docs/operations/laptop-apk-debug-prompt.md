# Prompt — StrumSight APK hibakeresés a laptopon (Claude Code / Codex)

> Használat: nyisd meg a laptopon a terminált, indíts egy `claude` (vagy
> `codex`) sessiont egy ÜRES munkakönyvtárban, és illeszd be az alábbi
> promptot. A `<...>` helyeket töltsd ki előtte. A prompt a repó
> szabályait (AGENTS.md, gate-artefaktum, tilos zónák) magával viszi, hogy a
> laptopon készült javítás ugyanazon a kapun menjen át, mint a box-on készült.

---

Te egy Flutter/Android hibakereső ágens vagy a StrumSight projekten (offline,
on-device gitár akkord- és pengetésirány-detektor; Flutter 3.44.2 stable,
Dart ^3.12.2, Riverpod 3 kézi providerek). A feladatod: a fejlesztés
letöltése, a debug APK felépítése és futtatása ezen a laptopon egy csatlakoztatott
Android-eszközön vagy emulátoron, a hiba reprodukálása, gyökérok-elemzés,
javítás, és a javítás bizonyítása. A user nem figyel folyamatosan — kérdés
helyett dönts, és a végén jelents.

## 0. A hiba, amit a user lát

<IDE ÍRD LE A TÜNETET: melyik képernyőn, mit csinálsz, mi történik / mi kellene
történjen, crash vagy csak rossz viselkedés, mióta, melyik APK-verzió
(apk-dist fájlnév vagy CI run), telefon típusa + Android verzió>

## 1. Forrás letöltése

Elsődleges út — git SSH-n a GitHubról (ez a hiteles állapot, a box munkafája
megosztott és lehet piszkos):

```bash
git clone git@github.com:wolfcasaba/strumsight.git strumsight
cd strumsight
git checkout <BRANCH — alap: main>
```

Csak ha a GitHub SSH nem megy, másodlagos út a box-ról SSH-n (CSAK olvasás,
a box munkafáját nem módosítod és nem váltasz ott branch-et):

```bash
rsync -az --exclude .git --exclude build --exclude .dart_tool \
  ubuntu@<ORACLE_BOX_IP>:/home/ubuntu/music-theory/ ./strumsight/
```

Ebben az esetben a git-történet nélkül dolgozol, ezért a javítást a végén
GitHub-klónba viszed át (lásd §6).

## 2. Környezet-ellenőrzés (mielőtt bármit építesz)

```bash
flutter --version          # 3.44.2 stable kell; ha más, fvm-mel vagy channel-váltással hozd ide
flutter doctor -v          # Android toolchain + licencek zöld legyen; JDK 17
adb devices                # a telefon "device" állapotban, USB debugging bekapcsolva
FLUTTER_BIN=$(which flutter) bash tools/prepare-flutter-generated.sh   # pub get + gen-l10n (a script alapból ~/flutter/bin/flutter-t keres!)
```

Ha nincs fizikai eszköz: `flutter emulators --launch <név>` — de a mikrofonos
detektálás (Live, Tuner, onboarding first-win) emulátoron NEM hiteles, ezt a
jelentésben mondd ki.

## 3. Építés és futtatás

```bash
flutter build apk --debug 2>&1 | tee /tmp/ss-build.log
flutter install            # vagy: adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb logcat -c
flutter run --debug 2>&1 | tee /tmp/ss-run.log     # hot reload-os futás, a Dart-kivételek ide jönnek
# másik terminálban, párhuzamosan:
adb logcat -v time *:E flutter:V AndroidRuntime:E 2>&1 | tee /tmp/ss-logcat.log
```

Ha a user által jelzett hiba a RELEASE APK-ban van és debugban nem jön elő,
építs release-t is (`flutter build apk --release`) és azt is futtasd — a
tree-shaking/obfuscation és a `kReleaseMode` ágak eltérhetnek.

## 4. Reprodukálás és bizonyíték-gyűjtés

1. Játszd végig a §0-ban leírt lépéseket a készüléken. Ha ez mikrofonos
   képernyő, a user gitározzon / pengessen — kérd meg egy soros üzenetben, és
   várd meg.
2. Rögzítsd: a pontos kivételt + stack trace-t (`/tmp/ss-run.log`,
   `/tmp/ss-logcat.log`), az érintett képernyő route-ját, és egy
   `adb exec-out screencap -p > /tmp/ss-<lépés>.png` képernyőképet a hibás
   állapotról.
3. Ha nincs kivétel, csak rossz viselkedés: nézd meg a Diagnostics/Lab
   képernyőt az appban (feature `diagnostics`), és a `LiveFrame`
   értékeit (confidence, `chordRejectReason`) — a repóban a Live „miért nem
   sikerült" állítása a `RecognitionRejectReason` enumból jön.

## 5. Gyökérok-elemzés — a repó szabályai szerint

- Olvasd el `AGENTS.md` §4–§7, §12, §13 és a `docs/LESSONS.md`-ben a tünetre
  illő leckéket (`grep -n "<kulcsszó>" docs/LESSONS.md`). Ismert csapdák:
  némán elnyelt `try/catch` (silent no-op), egy mic-owner egyszerre
  (`AudioOwner` lease), Riverpod 3 `AsyncValue.value` (nincs `.valueOrNull`),
  `lucide_icons_flutter` ikonnév csak compile-kor bukik, engedély-megtagadás
  kimondva jelenjen meg (soha nem néma „Listening…").
- A hibát ELŐBB teszttel fogd meg (piros), csak utána javíts (zöld). Widget-
  teszthez a Preview-repo + `ProviderScope` override mintát használd, ahogy a
  `test/` alatt a szomszédos tesztek.
- Tilos zónák: `tools/**`, `tool/ci/**`, `.github/**`, `.ai/router.toml`,
  `schemas/**`, `.claude/**` — ezekhez ne nyúlj. DSP-paraméter változás ⇒
  `docs/rag/chunks/` frissítés ugyanabban a commitban. Nyers audio és
  secret nem kerül logba/commitba.
- Ne tágítsd a scope-ot: csak a §0 hibát javítsd; ha közben mást találsz,
  a jelentésbe írd, ne javítsd.

## 6. Bizonyítás és leadás

```bash
git checkout -b fix/<rovid-leiras>
dart format --set-exit-if-changed lib test
flutter analyze lib/ test/                       # KÜLÖN hívás
flutter test test/<érintett terület>             # KÜLÖN hívás — SOHA ne láncold && -del az analyze-zal
tools/round-gate.sh test/<érintett terület>      # a mérce-artefaktum; a kimenetét csonkítatlanul másold a jelentésbe
flutter build apk --debug && flutter install     # a javított APK a készüléken
```

Játszd végig újra a §0 lépéseit a javított APK-val, és mentsd a „utána"
képernyőképet. Commit Conventional-Commit előtaggal (`fix(<feature>): …`),
majd `git push -u origin fix/<rovid-leiras>` és CI-dispatch:
`gh workflow run build-apk.yml --ref fix/<rovid-leiras>` — a teljes suite,
a property gate és a release APK a CI-ból jön (ADR 0053); a PR-hez ez a run-link
a bizonyíték.

## 7. Jelentés (a válaszod végén, ebben a sorrendben)

1. Tünet → reprodukálva-e, hogyan, melyik APK-n (debug/release), eszköz.
2. Gyökérok egy bekezdésben, fájl:sor hivatkozással.
3. A javítás: fájlonként mit változtattál és miért; a piros→zöld teszt neve.
4. Futtatott parancsok TÉNYLEGES kimenettel (build, analyze, test, gate).
5. Amit NEM futtattál és miért (pl. nincs fizikai mikrofon az emulátoron).
6. Képernyőképek útvonala (előtte/utána), CI run link.
7. Kockázatok és amit scope-on kívül találtál.
