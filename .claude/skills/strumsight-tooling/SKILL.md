---
name: strumsight-tooling
description: A StrumSight ágens-eszköztár bekötése és használata — Dart MCP szerver (analyzer-hibák, tesztfuttatás, hot reload, widget-fa), Serena MCP (szimbolikus Dart-navigáció és -szerkesztés), golden tesztek (spec-ben leírt UI-állapot képernyőképes rögzítése) és integration_test (emulátoros út-söprés, fájlból etetett Live). Használd minden StrumSight-kör elején (mit hívj kódolás helyett vakon), UI-t érintő körben (golden-cella kötelező), és amikor "nem látom a hibát / nem tudom, mi hívja" jellegű kérdés merül fel.
---

# StrumSight — ágens-eszköztár (Dart MCP · Serena · golden · integration_test)

**Mi ez:** az ágens nem vakon kódol. Négy eszköz méri helyette a valóságot,
mindegyik ezen a boxon 2026-09-18-án MÉRVE működik. Ez a skill azt mondja meg,
melyiket mikor, és mi a mért csapdája.

## 0. Gyors döntési tábla

| Kérdés | Eszköz |
|---|---|
| Fordul-e / mit mond az analyzer erre a fájlra? | Dart MCP `analyze_files` (vagy Serena `get_diagnostics_for_file`) |
| Mi van ebben a fájlban, hol definiálják, ki hívja? | Serena `get_symbols_overview` → `find_symbol` → `find_referencing_symbols` |
| Egy metódus törzsét cserélem / átnevezek | Serena `replace_symbol_body`, `rename_symbol` (LSP-pontos, nem regex) |
| Egy tesztfájlt futtatok | Dart MCP `run_tests` VAGY `/c/src/flutter/bin/flutter test <fájl>` |
| A spec-ben leírt képernyő-állapot így néz ki? | golden-cella (`test/ui/goldens/`), mérés a CI-ban (`record-goldens.yml` / full gate; ezen a boxon nincs Docker) |
| Minden route felnyílik hiba nélkül a készüléken? | `integration_test/route_sweep_test.dart` (emulátor, fejnélküli) |
| A Live valódi hangra reagál? | `integration_test/live_strum_feedback_headless_test.dart` (WAV fájlból) |
| Fut az app, mit mutat a widget-fa / runtime-hiba? | Dart MCP `launch_app` → `hot_reload` / `widget_inspector` / `get_runtime_errors` |

## 1. Dart MCP szerver (`dart mcp-server`, hivatalos)

**Bekötés:** `.mcp.json` → `node tools/dart-mcp-launcher.mjs --enable cli
--enable flutter_app_lifecycle`. A launcher platformfüggetlen (Windows dev-box:
`C:/src/flutter`; Oracle: `/home/ubuntu/flutter`; vagy `FLUTTER_SDK` env), és a
Flutter-be csomagolt `dart.exe`-t hívja (a `.bat` shim-et a Node ≥ 20 nem
spawnolja — EINVAL).

**Miért a két `--enable`:** a 0.1.4-es szerver alapból CSAK az analysis /
DTD / pub eszközöket adja (13 db). A `run_tests`, `dart_format`, `dart_fix`,
`create_project` (cli) és a `launch_app`, `stop_app`, `list_devices`,
`get_app_logs`, `list_running_apps` (flutter_app_lifecycle) csak a kategória
kifejezett engedélyezésével jelenik meg — MÉRVE `tools/list`-tel. Együtt 22
eszköz.

**Mért csapdák:**
- Az első `analyze_files` a teljes projektet elemzi: **~2 perc** ezen a boxon
  (utána gyors). Ne értelmezd lefagyásnak.
- A nem-ASCII projektútvonal (`gitár trainer`) a `flutter analyze` CLI-t
  megöli, de a Dart MCP `analyze_files`-t NEM (MÉRVE: "No errors" a fő
  worktree-n). Az `aapt`/`flutter drive` továbbra is ASCII worktree-t kér
  (`C:/src/ss-drive`, memória: `strumsight-emulator-headless-recipe`).
- `flutter analyze` és `flutter test` külön hívás marad (OOM, L05) — a
  `run_tests` MCP-eszköz egy fájlra ugyanolyan drága, mint a CLI.

## 2. Serena MCP (szimbolikus Dart-navigáció)

**Bekötés:** a `serena` Claude-plugin (`uvx --from git+…/oraios/serena`) a
szerver; a projekt `.serena/project.yml`-je (`language_servers: [dart]`)
commitolt. Session elején: `activate_project` a repo útvonalával (a Serena a
`strumsight` néven ismeri), majd `initial_instructions`.

**Dart nyelvi szerver:** a Serena alapból egy 3.7.1-es Dart SDK-t töltene le
(a projekt 3.12.2-es nyelvi elemeit nem értené). Ehelyett a
`~/.serena/language_servers/static/DartLanguageServer/dart-sdk` egy **junction**
a `C:\src\flutter\bin\cache\dart-sdk`-ra — így pontosan a projekt SDK-jának
analysis servere fut (MÉRVE: `serverInfo.version 3.12.2`). Új boxon ezt az
egyet kell megismételni (`mklink /J`).

**Mért csapdák:**
- Aktiváláskor a Dart analysis server 60 s-os kezdeti elemzési időkorlátja
  lejár (WARNING a logban), a Serena „proceeding anyway" — ez NEM hiba; az
  első szimbólum-lekérés után minden pontos (MÉRVE: `find_symbol
  StrumSightApp` → `lib/app/strumsight_app.dart:14`).
- A `.serena/cache` és a `project.local.yml` gitignore-olt; a
  `.serena/memories/` commitolható, tartsd rövidnek — a HANDOFF/AGENTS a
  forrás, a Serena-memória csak odamutat.
- Egyszerre EGY Serena-példány dolgozzon a repón; a Dart analysis server
  párhuzamos ágens-futás alatt összeomlik (memória: `strumsight-box-facts`).

## 3. Golden tesztek — a spec UI-állapotának rögzítése

**Minta:** `test/ui/goldens/e13_r32_screens_golden_test.dart` — `AppTheme`, a
képernyő szeletelve (`_hubScreen()` stb.), két keret: 412×915 compact portrait
és ugyanaz `textScaler 2.0`-val; PNG a `test/ui/goldens/goldens/` alatt
(`<kör>_<képernyő>_compact[_scale2].png`). Feature-közeli goldenek:
`test/features/live/goldens/`, `test/features/vision/presentation/goldens/`.

**Szabály UI-körben:** a brief §6.1 mérce-mátrixa minden spec-ben leírt
képernyő-állapothoz nevezzen meg egy golden-cellát (vagy PNG-mentes
variáns-mátrixot, mint `e15_r01_theme_adoption_test.dart`), és az ágens EHHEZ
igazodik — a golden **rögzít, nem ítél** (HANDOFF, ADR 0426).

**Mérés — csak a kapu architektúráján (ADR 0426):**

```bash
tools/golden-x86.sh check  test/ui/goldens/<fájl>.dart   # ellenőriz
tools/golden-x86.sh record test/ui/goldens/<fájl>.dart   # x86-on VESZ FEL
```

MÉRVE 2026-09-18 ezen a Windows-boxon: a natív `flutter test` a
`e13_r16_screens_golden_test.dart`-on **8/10 piros** (Windows-raszterizáció ≠
CI x86-Linux), ezért a natív golden-futás itt NEM mérce. A `golden-x86.sh`
Docker Desktop alatt fut (linux/amd64 natívan, qemu nélkül); a script
Windows-foltja (`cygpath`, `MSYS_NO_PATHCONV`) 2026-09-18 óta benne van.
**Ezen a Windows-boxon 2026-09-18 óta NINCS Docker Desktop** (a tulajdonos döntése, lemez-takarítás), tehát itt a golden-mérés kizárólag a CI: a felvétel útja a `record-goldens.yml` (Actions → Record
goldens (x86) → branch + tesztútvonal + indok). SOHA `flutter test
--update-goldens` ezen a boxon.

## 4. integration_test — készüléken mért viselkedés

- `integration_test/route_sweep_test.dart`: a VALÓDI app minden
  paraméter-mentes route-ja, Flutter-hibák gyűjtve, képernyőkép
  `build/screenshots/`, csak a végén bukik (egy törött képernyő nem takar
  másikat).
- `integration_test/live_strum_feedback_headless_test.dart`: a valódi engine
  (izolát, DSP, CRNN) egy WAV-ból etetve — mikrofon nélkül.
- Futtatás: ASCII worktree-ből (`C:/src/ss-drive`), fejnélküli emulátor,
  `flutter drive --driver=test_driver/integration_test.dart --target=… -d
  emulator-5554 --no-pub`, naplót FÁJLBA (a `| tail` elrejti a haladást). A
  teljes recept a `strumsight-emulator-headless-recipe` memóriában.
- Új képernyő = új sor a `_routes` listában, VAGY egy saját fájl a fenti két
  minta szerint (`IntegrationTestWidgetsFlutterBinding`, `takeScreenshot`).

## 5. Mit NEM csinálunk

- Nem futtatjuk a gate-et Gradle-build vagy Docker-golden-futás mellett
  (hamis piros, MÉRVE).
- Nem „javítjuk" a goldent újrafelvétellel, amíg a diffet meg nem néztük és
  szándékosnak nem ítéltük (a commit-üzenetbe: melyik képernyő, miért).
- Nem hagyjuk a Serena-t és a Dart MCP-t egyszerre ugyanarra a fájlra írni —
  a Serena szerkeszt (LSP-pontos), a Dart MCP mér (analyze / test / runtime).
