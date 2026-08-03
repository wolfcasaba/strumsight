# Epic 3 — Guitar Pro import feasibility

**Mérés dátuma:** 2026-08-03. Ez a kutatás a production registryt és
feature-kódot nem módosítja; a futtatható bizonyíték kizárólag a
`tool/guitar_pro_feasibility/` izolált package-ben él.

## Vizsgált utak

| Út | Licence és forrás | GP verzió / fidelity | Mobil, offline és build | Security / maintenance | Döntés |
| --- | --- | --- | --- | --- | --- |
| A — `dart_gp_tab_reader` 0.4.0 | LGPL-3.0; [pub metadata](https://pub.dev/api/packages/dart_gp_tab_reader), [source/licence](https://github.com/ron-diesel/dart_gp_tab_reader/tree/b402e549afe9828d2ba07ff70161bb7ae3e9a020). Első kiadás 2026-06-27, 0.4.0: 2026-07-29. | Dokumentáltan GP3/4/5, GP6 GPX és GP7/8 GP; R13 nem teszi production dependencyvé. | Pure Dart (`archive`, `xml`), tehát nincs FFI/platform channel és a parser lokális byte-okból dolgozik. Android/iOS release APK/IPA és méretmérés nincs: a fejlesztői boxon nincs Android SDK; ez R14 gate. | A csomag új és rövid maintenance-történetű; az ADR 0091 resource-limit/cancellation boundary nincs bizonyítva. | **Nem választott A:** az R14 pre-flightig nincs kiadási és security-boundary evidencia. |
| B — alphaTab 1.8.4 adapter | MPL-2.0; [official introduction](https://www.alphatab.net/docs/introduction/), [NPM metadata](https://www.npmjs.com/package/@coderline/alphatab/v/1.8.4). A `npm view` 13,672,165-byte unpacked JS csomagot mért 2026-08-03. | Dokumentált GP3–5, GP6 GPX és GP7 GP import. A R13 isolated probe GP3/GP5/GPX fixturek mindegyikét dekódolta, a mandatory fieldeket compare-olta és 7-byte malformed inputot controlled failureként adott vissza. | A dokumentált integráció JS/.NET/Kotlin Android; az iOS-t a dokumentáció jövőbeli platformként írja le. Flutter bridge, iOS build, worker-isolation és mobil binary méret nincs. | Érett, de adapterként külső runtime és crash/worker boundary kellene. | **Nem választott B:** nincs közvetlen, reprodukálható iOS út vagy isolation proof. |
| B — TuxGuitar parser újracsomagolása | LGPL-2.1-only; [official file-format list](https://www.tuxguitar.app/files/1.6.0/desktop/help/file_formats.html), [upstream repository](https://github.com/helge17/tuxguitar). | A hivatalos lista GP3/4/5 save/load, GP6 GPX load és GP7 GP load képességet jelöl. R13-ban nem integráltuk. | Java desktop/Android alkalmazás, nem Flutter/iOS parser library; native wrapper és méretmérés hiányzik. | A teljes editorból történő extraction növelné az adapter- és licence-audit felületet. | **Nem választott B:** rossz boundary és nincs iOS build path. |
| C — külső konverzió → már támogatott MusicXML/MXL vagy MIDI | Nem kerül új parser vagy converter az appba. | A GP fidelityt a külső producer felelősséggel alakítja át; az app a már auditált MusicXML/MXL vagy MIDI subsetet méri és warningolja. | Offline az appban; a felhasználó saját eszközén végzi a konverziót. Nincs új build-size költség. | Nincs GP binary attack surface vagy hidden upload. Az eredeti GP technikák elveszhetnek, ezt a konverziós UX-nek őszintén kell jeleznie. | **Elfogadott C.** |

## Ismételhető B-candidate spike

Az isolated tool production Dart dependency nélkül alphaTab 1.8.4 Node modult
kap explicit `ALPHATAB_MODULE_PATH` environment változóval. A teszt előbb
hiányzó `gp_spike.dart` symbolra RED volt, majd a legkisebb probe
implementáció után GREEN lett. A parancs:

```bash
cd tool/guitar_pro_feasibility
npm pack @coderline/alphatab@1.8.4
tar -xzf coderline-alphatab-1.8.4.tgz
dart pub get
ALPHATAB_MODULE_PATH="$PWD/package" dart test test/gp_spike_test.dart
ALPHATAB_MODULE_PATH="$PWD/package" dart run bin/run_spike.dart ../../test/fixtures/song_trainer/guitar_pro/minimal_gp3.gp3 ../../test/fixtures/song_trainer/guitar_pro/minimal_gp5.gp5 ../../test/fixtures/song_trainer/guitar_pro/minimal_gpx.gpx
```

Mért output (alphaTab 1.8.4):

| Fixture | Parse | Track / tuning | Measure / note | String / fret | Tempo / meter | Delta |
| --- | --- | --- | --- | --- | --- | --- |
| `minimal_gp3.gp3` | success | `1` / `[64,59,55,50,45,40]` | `1` / `1` | `6` / `3` | `120` / `4/4` | string-order warning |
| `minimal_gp5.gp5` | success | `1` / `[64,59,55,50,45,40]` | `1` / `1` | `6` / `3` | `120` / `4/4` | string-order warning |
| `minimal_gpx.gpx` | success | `1` / `[64,59,55,50,45,40]` | `1` / `28` | `1` / `1` | `120` / `4/4` | string-order warning |
| 7-byte malformed GP header | controlled failure | — | — | — | — | `tryProbe` failure, nincs tool crash |

A test közvetlenül összeveti a track countot, hangolást, measure/note countot,
string/fretet, tempót és metert; így e központi invariánsok bármelyikének
mutációja piros tesztet ad. A fixture-provenance és SHA-256 értékek a
[`README`](../../test/fixtures/song_trainer/guitar_pro/README.md)-ben vannak.

## Döntés és R14 aktiválási szerződés

Az egyetlen R13 stratégiai döntés **C: külső, felhasználó által kezdeményezett
konverzió MusicXML/MXL vagy MIDI formátumba**. Az alkalmazás nem állíthat
közvetlen Guitar Pro támogatást, nem regisztrál GP extensiont, nem csomagol
convertert és nem tölt fel forrásfájlt.

R14 csak akkor aktiválhat A vagy B irányt, ha egy új pre-flight együtt
bizonyítja:

1. a candidate exact verziójának licence- és maintenance-auditját;
2. Android **és** iOS reproducible release buildet és a hozzáadott build-size
   mérést;
3. ADR 0091 szerinti byte/note/measure/wall-time korlátot, cancellationt és
   fail-closed malformed corpuszt;
4. a fenti fixture-mátrix bővítését (multi-track, capo, repeats és
   unsupported-technique warningok), valamint stable warning contractot;
5. adapter/domain boundaryt: candidate típus nem szivároghat production domainbe.

Addig R14 legfeljebb őszinte konverziós útmutatást adhat. Nem adhat hidden
convertert vagy hálózati kérést.
