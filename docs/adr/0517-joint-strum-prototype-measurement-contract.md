# ADR 0517 — A joint strum-prototípus mérési szerződése: a lookahead szám, a legacy sor horgonyzott, a küszöb inkluzív

- **Státusz:** Elfogadva
- **Kör:** `E14-R18` (Chapter 14 — Recognition Accuracy & Useful UI Recovery, Kör 18)
- **Dátum:** 2026-09-05
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:** [ADR 0354](0354-recognition-baseline-manifest-and-evidence-index.md)
  (a legacy baseline gépi, hash-horgonyzott artefaktuma — ez a kör ezt olvassa,
  nem méri újra), [ADR 0509](0509-grouped-recognition-evaluation-and-leakage-protection.md)
  (grouped split, fail-closed leakage, a metrika a definíciójával ÉS az irányával
  utazik), [ADR 0369](0369-reference-model-reproduction-and-licence-audit.md)
  (a reprodukciós script semmit nem ír a repó fájába; a workdir kívül van),
  [ADR 0249](0249-analysis-evaluation-dataset-governance.md)
  (a CI kicsi fixture-ön fut, a valós korpusz külső és kézi)

## Kontextus — a pre-flight MÉRT tényei (2026-09-05, `main @ 368cd179`)

A brief 2026-08-20-án készült, `main @ 6371aa3` olvasata alapján. Azóta két
előfeltétel-kör landolt (`E14-R08` grouped harness, `E14-R17` referencia-audit),
és a pre-flight mérése az alábbi tényeket találta.

- **Az előre kiosztott `0370` szám elavult.** A foglaló
  (`tools/round-slots.py reserve-adr --round E14-R18`) a **`0517`**-et adta; a
  fán a legmagasabb szám `0512`. A `ls docs/adr | tail` alak sorszám-választásra
  kifejezetten tiltott (mért ütközés 2026-08-05, `tools/tests/test_adr_numbering.py`).

- **A tanító-környezet MEGVAN, tehát a `blocked` jelzés ezen a címen HAMIS
  volna.** Mérve: `/home/ubuntu/tf-venv/bin/python -c "import tensorflow"` →
  **TF 2.21.0**; a rendszer `python3` viszont **nem** tartalmazza a TensorFlow-t
  (`ModuleNotFoundError`), numpy-ja `1.26.4`, a venv-é `2.5.1`. A prototípus
  Python-oldala tehát KIZÁRÓLAG a `/home/ubuntu/tf-venv/bin/python`
  interpreterrel futtatható, miközben a `python3 -m pytest ml -q` (rendszer-
  interpreter, ma **115 passed / 21,23 s**) továbbra is zöld kell maradjon.

- **A korpusz HORDOZ irány-igazságot, és eléggé kiegyensúlyozott.** Mérve az
  `ml/data/klangio` 82 `.strums` fájlján: **7228 `D` / 4539 `U`**, összesen
  11 767 esemény (= a baseline manifest `eventCount`-ja), és **76 felvétel
  tartalmaz `U`-t**. A `ml/klangio.py::parse_strums` szigorú (ismeretlen betű →
  `ValueError`). Egy joint down/up fej tehát ezen a korpuszon MÉRHETŐ.

- **A legacy lánc irány- és latencia-száma ezen a korpuszon NEM létezik.** A
  merge-elt `evaluation/recognition/baseline_manifest.json` (E14-R02, ADR 0354)
  `metricBlocks.direction.status = "not-measured"` és
  `metricBlocks.latency.status = "not-measured"`; a latencia indoklása szó
  szerint: „offline batch run (flutter test) over pre-recorded WAV files, not a
  real-time on-device run". Ami MÉRVE VAN, az a legacy **onset** oldal, korpusz-
  hash-sel horgonyozva (`corpusSha256 = 4880face…5827`, 82 felvétel):
  `tolerance50000us.f1 = 0.6739121651650438` (n = 16 411),
  `tolerance25000us.f1 = 0.4042664942830592`, `tolerance100000us.f1 = 0.8520059795563816`.
  A `direction` blokk indoklása a *Dart-oldali annotációs útra* igaz; a Python-
  oldali `.strums` irány-igazságot a fenti mérés cáfolja meg mint korpusz-
  állítást — ezt a különbséget a report KIMONDJA, nem hallgatja el.

- **A Chapter 14 §7.2 Strum Alpha kapu mért értékei:** Onset F1 @50 ms **0,82**;
  end-to-end direction macro-F1 **0,80**; accepted direction accuracy 0,90;
  coverage 0,70; false visible arrow ≤ 2/perc; verdict latency p50 ≤ 180 ms,
  p95 ≤ 280 ms.

- **A küszöb-összehasonlítás IEEE-754-ben biztonságos, ha LITERÁL.** Mérve
  `python3`-mal: `repr(0.80) == '0.8'`, `0.80 >= 0.80 → True`,
  `0.79 >= 0.80 → False`, `0.81 >= 0.80 → True`, `0.82 >= 0.82 → True`. Az
  L637 csapdája (kerek tizedessel felírt „a küszöbön" cella aritmetikából
  előállítva pirosra megy) tehát csak akkor él, ha a cella a határértéket
  SZÁMOLJA; literálból olvasva nem.

- **A `evaluation/recognition/**` alá KERÜLŐ új fájlt semmilyen meglévő őr nem
  leltározza.** Mérve: nulla találat `Directory('evaluation…')` / könyvtár-
  bejáró mintára a `test/` és `tool/` fában, és a
  `test/tooling/recognition_baseline_manifest_test.dart` kizárólag a saját két
  fájlját olvassa. Új séma + fixture felvétele tehát nem visz pirosra
  briefen kívüli tesztet (S11/S14 nem áll fenn).

- **Ehhez a körhöz NEM tartozik Dart production-belépési pont.** Az
  `allowed_paths` egyetlen Dart fájlt enged, és az maga a teszt
  (`test/tooling/joint_io_schema_test.dart`) — `lib/` és `tool/` a tilos
  zónában van, a §5.5 pedig szállítható artefaktumot sem enged.

## Döntés

### D1 — A lookahead SZÁM, és a sémában utazik

Mobil jelöltként kizárólag olyan architektúra értékelhető, amelynek a
lookahead-je **számszerűen korlátozott**. A prototípus IO-sémája kötelező
mezőként hordozza a lookahead-et keretben ÉS milliszekundumban, a report pedig
ugyanazt a számot közli. „Offline jobb, majd a mobilon lesz valami" nem
elfogadható kimenet.

### D2 — Grouped split játékos szerint, fail-closed leakage

A train/eval split játékos szerint csoportosított (`ml/klangio.py::guitarist_of`,
`logo_folds`). Leakage észlelésekor a futás **hibával áll meg és NEM ír
reportot** — a leakage soha nem figyelmeztetés. Ez az ADR 0509 D1/D2
fail-closed vonalának folytatása a Python-oldalon.

### D3 — Az IO-séma verziózott, az ismeretlen verzió TÍPUSOS hiba

A `schemaVersion` kötelező és `const`-ként rögzített. Ismeretlen verzióra a
Dart-oldali őr **típusos hibát** ad — soha nem esik vissza defaultra, és nem
tolerál hiányzó mezőt. A validáció kézzel írt (nincs séma-könyvtár függés), az
ADR 0354 D8 precedense szerint.

### D4 — A go/no-go az Alpha kapuhoz mér, a határ INKLUZÍV

A javaslat akkor és csak akkor „go", ha a mért érték **eléri** a Chapter 14
§7.2 Alpha küszöböt a grouped spliten: a küszöb **alatt** → no-go, pontosan
**rajta** → go, **fölötte** → go. A „majdnem elérte" no-go. A verdikt a
szállított IO-dokumentumban is szerepel, és a Dart-oldali őr a hármas cellát
(alatta / rajta / fölötte) a fixture-ből épített változatokon méri — a
határértékek LITERÁLOK, nem aritmetika eredményei (L637).

### D5 — A prototípus nem szállítható artefaktum, és nem ír a repó fájába

Súly, checkpoint, feature-cache és köztes futási artefaktum **nem** kerül sem
`assets/`-be, sem bárhová a repó fája alá: minden futási kimenet egy kötelező,
a repón KÍVÜLre mutató workdir/cache útvonalra megy (ADR 0369 D1 precedense).
A repóba csak a report, a séma és a fixture kerül.

### D6 — A legacy sor HORGONYZOTT, nem újraszármaztatott — és amit nem mértek, azt nem közöljük mértként

A legacy összehasonlító sor forrása a merge-elt
`evaluation/recognition/baseline_manifest.json`. Az evaluate script kiszámolja
az `ml/data/klangio` korpusz hash-ét, és **egyeznie kell** a manifest
`corpusSha256` értékével; eltéréskor a futás hibával áll meg és nem ír reportot
(ez adja az „azonos korpusz-hash" gépi bizonyítékát). A legacy **onset** F1 a
manifestből átvett érték, a forrás-mezőivel együtt.

A legacy **end-to-end down/up F1 ezen a korpuszon nem létezik** (`direction:
not-measured`). Ezért:

- tilos legacy end-to-end irány-számot MÉRTKÉNT közölni;
- ha a report ad ilyen sort, az kizárólag **explicit felső korlát**, a
  származtatása (mely tényezőkből, milyen feltevéssel) kiírva, és a
  metrika-rekordban `bound: "upper"` jelöléssel;
- a felső korlát a prototípus javára szóló következtetést NEM alapozhat meg
  („a prototípus jobb a legacynél") — csak azt, ami egy felső korlátból
  levezethető.

A prototípus és a legacy latenciája **algoritmikus** (a lookahead + a
feldolgozási ablak konstansaiból), nem valós idejű eszközmérés; a report ezt
kimondja, mert a manifest szerint a legacy oldalon valós idejű latencia nincs.

### D7 — A metrika a definíciójával ÉS az irányával utazik, és a kettőt EGYÜTT mérjük

Minden szállított metrika-rekord hordozza a definícióját és a
`higherIsBetter` irányát (ADR 0509 D3/D4 folytatása). Az L630 mért
hibaosztálya ellen a Dart-oldali őr a **számot és a definíció-szöveget együtt**
méri: az a bemenet, amelyik a definíció szerinti olvasattól eltérő értéket ad,
egyszerre állítsa a tényleges számot és azt, hogy a definíció ezt mondja.

### D8 — A Dart-oldali validátor ebben a körben a TESZTBEN él — kimondottan, határoltan

Mivel a kör semmilyen production Dart fájlt nem enged (`lib/`, `tool/` tilos
zóna) és a §5.5 szerint nem szállít artefaktumot, a séma-validátor a
`test/tooling/joint_io_schema_test.dart` fájlban lakik. Ez tudatos, határolt
eltérés az L631 („a cella a SZÁLLÍTOTT belépési pontot mérje") mintájától:
ebben a körben nincs szállított belépési pont, amit mérni lehetne. **A
productizálás köre a validátort `tool/` alá mozgatja, és a teszt onnan
importálja** — ezt a következő kör briefje köti ki.

## Következmények

**Pozitív.** A kör kimenete minden számnál megmondja, honnan jön: a legacy sor
hash-horgonyzott merge-elt artefaktumból, a prototípus sora saját grouped
spliten mért futásból, a hiányzó legacy irány-szám pedig hiányzóként jelenik
meg, nem becslésként. A go/no-go egyetlen, inkluzív küszöbön dől el, gépi
cellával a határon.

**Negatív / ár.** A legacy oldal irány-összehasonlítása ebben a körben nem
zárható le — a teljes end-to-end legacy szám külön mérési kört kíván (a
Dart-oldali detektált onsetek eseményszintű exportját). A prototípus
kompute-költsége a lassú boxon valós korlát, ezért a mérés egy dokumentált,
szűkített konfiguráción fut, nem a `honest_eval.py` teljes multi-seed sweepjén.

**Amit ez a döntés TILT.** Súly vagy checkpoint a repó fájában; legacy
end-to-end irány-szám mértként közölve; ismeretlen `schemaVersion` defaultra
esése; „majdnem elérte" → go; leakage figyelmeztetésként; a lookahead szám
elhagyása; a korpusz-hash ellenőrzésének kihagyása.
