# ADR 0474 — Benchmark-rekord, forrás-kötött baseline és a kétfokozatú, irány-tudatos regresszió-összevetés

- **Státusz:** elfogadva
- **Dátum:** 2026-08-29
- **Kör:** `E12-R14` (Chapter 12, Kör 14)
- **Kapcsolódó:** [`0248`](0248-analysis-cache-key-and-performance-budget.md)
  (analysis cache-kulcs és performance budget — „a szám gépfüggő, nem
  merge-kapu"), [`0298`](0298-time-budget-allocation-contract.md) (typed budget,
  INKLUZÍV hard maximum, alatta/határon/fölötte cellahármas),
  [`0196`](0196-vision-device-tier-performance-and-thermal-contract.md) (vision
  device-tier teljesítmény-szerződés), [`0473`](0473-release-fixture-corpus-manifest.md)
  (fail-closed manifest-minta, „ismeretlen ≠ zöld"),
  [`0447`](0447-release-manifest-provenance-and-sbom.md) (determinisztikus,
  gép-független manifest)

## Kontextus

A fán MA nincs közös teljesítmény-rekord. A pre-flight mérése
(2026-08-29, `main @ 7b28744a`):

- `tool/benchmarks/` **két** eszközt tartalmaz, közös séma nélkül:
  `real_audio_dsp_baseline.dart` (718 sor, saját `toJson()`-ökkel épített
  riport-JSON) és `song_trainer_pitch_benchmark.dart` (69 sor, soronkénti
  `PASS`/`FAIL` szöveg a stdout-ra, nem-nulla kilépés eltérésre);
- `docs/baseline/` **16** dokumentumot tartalmaz, mind Markdown;
- `tool/compare_benchmarks.py` és `docs/performance/` **nem létezik**;
- `flutter analyze lib/ test/ tool/` (`tools/round-gate.sh:225-226`) — a `tool/`
  alatti Dart forrás az analyzer hatókörében van.

A `docs/baseline/` tartalmának mérése azonban egy olyan tényt hozott elő, amit a
kör előre megírt briefje (2026-08-27) nem tudott: **a baseline-dokumentumok
számai NEM egyfajták.** Három, egymással össze nem keverhető osztály van:

1. **MÉRT érték** — valódi futás valódi kimenete. Egyetlen dokumentum hordoz
   ilyet: `docs/baseline/epic-06-analysis-performance.md:10-15` (2026-08-13,
   `flutter test --reporter expanded tool/audio_analysis_benchmark.dart`, Linux
   `6.17.0-1019-oracle`, aarch64, 4 CPU) — pl. cache-miss `30 589 µs`, cache-hit
   `5 317 µs`, modell read+parse `43 578 µs`, `strums_120_bpm` elemzés
   `496 777 µs`.
2. **FELSŐ KORLÁT** — nem mérés, hanem állítás egy mérésről.
   `docs/baseline/epic-04-performance.md:27-30` végig `< 0.1 ms`, `< 1 ms`,
   `< 2 ms` alakú; a dokumentum maga mondja ki, hogy „a tesztek futási ideje
   tartalmazza a komponensek végrehajtási idejét", azaz nincs izolált mérőszám.
3. **SZÁRMAZTATOTT SZERZŐDÉS-HATÁR** — tervezési döntés, nem megfigyelés:
   `docs/baseline/epic-03-backing-drift-benchmark.md:20-31` (17 ms
   pozíció-precizitás = egy 60 Hz render-frame felső egésze; 34/51/68 ms
   policy-cellák), `docs/baseline/epic-03-pitch-observation-benchmark.md:9-21`
   (12/35/70 cent, ±80 ms onset-ablak, 0,014 RMS-kapu).

Van egy negyedik osztály is: a **CÉL, mérés nélkül**. A
`docs/manual-testing/vision-performance-benchmark.md:35-40` öt FPS-metrikára ad
production-célt és minimum-küszöböt, de MINDEN „Mért átlag" / „Mért p95" cellája
`PENDING` — a dokumentum kifejezetten kimondja: „E05-30 nem ír be szintetikus
számot valós eszközös eredmény helyett".

Ha egy közös rekord-séma ezt a négy osztályt egy „érték" mezőbe mossa, a
harness pontosan azt a hamis biztonságot állítja elő, aminek a lezárása a
feladata: egy `< 0.1 ms` felső korlátból „mért 0,1 ms baseline" lesz, egy
`PENDING` FPS-célból pedig hallgatólagos zöld.

## Döntés

**D1 — Metaadat nélküli mérés nem rekord.** Minden bejegyzés kötelezően
hordoz build-azonosítót (`buildSha`) és eszköz-azonosítót (`deviceId`); a
hiányuk nem-nulla kilépés az összehasonlítóban.

**NEM elfogadható gyengítés:** `"unknown-device"` / `"local"` alapérték. Két
különböző készüléken mért érték összevetése értelmetlen, és pont ezt rejtené el.

**D2 — Az eszköz-szótár ZÁRT, és a Kör 13 mátrixából jön.** A `deviceId`
megengedett értékei kizárólag a `docs/testing/device-matrix.yaml` `id`-jai
(mérve: `pixel_6a`, `pixel_7`, `samsung_galaxy_a54`, `xiaomi_redmi_note_12`),
plusz a **CI-host** azonosítója a gépen futó, nem eszközös mérésekre. Ismeretlen
azonosító hiba, nem új eszköz néma felvétele.

*Indok:* az E12-R13 mátrixa pontosan azért kötött 11 kötelező azonosító-mezőt
eszközönként, hogy a „melyik készüléken" kérdés géppel megválaszolható legyen;
egy szabad szöveges `deviceId` ezt egyetlen mezővel visszabontaná.

**D3 — Minden érték hordozza a SAJÁT osztályát, és csak a `measured` hasonlítható
össze.** A rekord `kind` mezője a fenti négy osztályt különbözteti meg
(`measured`, `upperBound`, `derivedContract`, `target`). Az összehasonlító
kizárólag `measured` ↔ `measured` párokra számol regressziót; a
`baseline.json`-ban ettől eltérő osztályú bejegyzés dokumentált kontextus,
amelyre az összevetés nem ad se PASS-t, se FAIL-t, hanem az `unknown`
osztályozáson keresztül a D5 szerint viselkedik.

**NEM elfogadható gyengítés:** a `< 0.1 ms` alakú felső korlátot `0.1`-ként
`measured`-nek felvenni. Az `epic-04-performance.md` maga mondja ki, hogy nincs
izolált mérőszáma — egy ilyen bejegyzés a mérés LÁTSZATÁT állítaná elő, ami
ennek a körnek a fő kockázata.

**D4 — Minden bejegyzés forrás-hivatkozást hordoz, és a forrásnak léteznie kell.**
A `source` mező repó-relatív útvonal, lehetőleg sor-hivatkozással
(`docs/baseline/epic-06-analysis-performance.md:10`). Forrás nélküli, „körülbelül"
felvett érték nem kerülhet a baseline-ba; a nem létező forrásra mutató bejegyzés
hiba. Abszolút gép-útvonal (`/home/`, `C:\`) tilos ([ADR 0447](0447-release-manifest-provenance-and-sbom.md),
[L530](../LESSONS.md#l530)).

**D5 — A hiányzó mérés `unknown`, és az `unknown` a release-kapun HIBA.** Ha egy
kötelező metrika hiányzik a jelölt-riportból, az összesítés `unknown`-ként
sorolja be, és az összehasonlító nem-nulla kilépéssel zár.

**NEM elfogadható gyengítés:** a hiányzó metrika kihagyása az összesítésből. Egy
riport, ami azért zöld, mert nem mért, rosszabb a pirosnál — ez a
[`0473`](0473-release-fixture-corpus-manifest.md) D4 („ismeretlen licenc =
megállás, nem `"unknown"`") ugyanazon fail-closed mintája.

**D6 — A regresszió-küszöb kétfokozatú, a rekordban rögzített, és MINDKÉT határ
INKLUZÍV.** Figyelmeztetés **5,0 %**, hiba **10,0 %** romlás. A pontosan 5,0 %-os
romlás MÁR `warn`; a pontosan 10,0 %-os MÁR `fail`. A küszöbök nem a hívó
paraméterei.

**NEM elfogadható gyengítés:** futásidejű küszöb-felülírás „a CI-ban lazábban"
indoklással; illetve szigorú `>` használata `>=` helyett. Az utóbbi a mért
hibaosztály: az [ADR 0298](0298-time-budget-allocation-contract.md) ugyanezt az
inkluzív hard-maximumot alatta/határon/fölötte cellahármassal kötötte meg, mert
a határ-cella az egyetlen, ami a `>` / `>=` tévesztést pirosra váltja.

**D7 — A „romlás" iránya metrikánként van rögzítve, nem feltételezve.** Minden
bejegyzés kötelező `direction` mezőt hordoz: `lowerIsBetter` (késleltetés,
memória, indulási idő) vagy `higherIsBetter` (FPS, pontosság, találati arány).
A romlás-százalék ebből következik: `lowerIsBetter` esetén a NÖVEKEDÉS, a
`higherIsBetter` esetén a CSÖKKENÉS a romlás.

*Mért indok:* a fán mindkét irány valóban előfordul — az
`epic-06-analysis-performance.md` mikroszekundumai `lowerIsBetter`, a
`vision-performance-benchmark.md:35-40` öt FPS-metrikája `higherIsBetter`
(minimum-küszöbökkel: 15/8/5/5/15 fps). Egy irány-vak, „nagyobb = rosszabb"
összehasonlító a teljes vision-oldalt fordítva ítélné meg, és pont az FPS-esést
— a felhasználó által ténylegesen érzékelt regressziót — engedné át zölden.
Alapértelmezett irány NINCS: a hiányzó `direction` hiba, nem `lowerIsBetter`.

**D8 — A rekord determinisztikus és gép-független.** A séma verziózott
(`schemaVersion`); a `timestamp` a MÉRÉS ideje, nem a riport generálásáé; a
`sampleCount` kötelező, mert egy egymintás érték és egy 100-mintás átlag nem
ugyanaz az állítás.

**D9 — A harnesst a `flutter test`-en át futó cella méri, skip-ág nélkül.** A
`test/tooling/benchmark_budget_test.dart` `Process.runSync('python3', …)`-szel
futtatja az összehasonlítót ideiglenes fixture-eken. Ha a `python3` hiányzik, a
`ProcessException` PIROS, nem skip. A tiltott bináris a `rg`/`grep`/`jq`/`gh`
([L110](../LESSONS.md#l110)); a `python3`-ra a mért, zölden merge-elt precedens a
`test/tooling/device_matrix_test.dart` (E12-R13, PR #503) és a
`test/tooling/release_manifest_test.dart`. Az önvédő cella
([L527](../LESSONS.md#l527)) kötelező: a fájlnak bizonyítania kell, hogy a saját
külső-bináris készlete pontosan `{python3}`.

## Következmények

- A `docs/performance/baseline.json` lesz a gépi baseline egyetlen belépője; a
  `docs/baseline/**` Markdown-dokumentumok **változatlanok maradnak** és
  forrásként szolgálnak. Egyik sem íródik át ebben a körben.
- A meglévő két benchmark-eszköz (`real_audio_dsp_baseline.dart`,
  `song_trainer_pitch_benchmark.dart`) **változatlan** — a séma-adaptálásuk
  külön kör dolga; ez a kör a szerződést és a mércét szállítja.
- A CI-integráció (`.github/workflows/benchmark.yml`, SDD Ch12) **nem ebben a
  körben** történik; a `.github/**` a kör tilos zónája.
- A `baseline.json` a D3 miatt kezdetben KEVÉS `measured` bejegyzést hordoz —
  ez szándékos és mért állapot, nem hiányosság: a fán ma ennyi valódi mérés van.
  A `target` osztályú vision-bejegyzések a D5-ön keresztül teszik láthatóvá,
  hogy a release-riport ezekre `unknown`-t ad, nem zöldet.
- Amit ez az ADR NEM dönt el: a cold-start és a memória-metrikák tényleges
  mérési eljárása (eszközös HORIZON-elfogadás), a benchmark CI-ba kötése, és a
  `docs/baseline/**` Markdown-dokumentumok esetleges generálása a JSON-ból.
