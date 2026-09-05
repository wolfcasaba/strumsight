# E14-R09 review — Baseline dashboard és fail-closed release gate

- **Reviewer:** Claude (Opus 5), orchestrátor-szék — read-only, produkciós kódot nem szerkesztettem
- **Dátum:** 2026-09-05
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Branch:** `sonnet-impl/e14-r09-baseline-dashboard-and-release-gate`
- **Review-alap:** `4e8c83da` (pre-flight commit) … `7f3a8f18` (implementer HEAD)
- **ADR:** [0511](../adr/0511-recognition-release-gate-and-single-source-report.md)
- **Brief:** [`docs/rounds/e14-r09-baseline-dashboard-and-release-gate.md`](../rounds/e14-r09-baseline-dashboard-and-release-gate.md)

## 1. Mit mértem

| Mérés | Parancs | Eredmény |
|---|---|---|
| Gépi scope-audit | `python3 tools/scope-audit.py --repo … --brief … --base 4e8c83da` | `Legacy scope audit OK (4e8c83da7160..7f3a8f1802dc, 8 changed path(s), 0 generated/ignored)` |
| Diff-terjedelem | `git diff --stat 4e8c83da HEAD` | 8 fájl, 2339 beszúrás, 0 törlés — pontosan az `allowed_paths` |
| Célzott suite izolált klónban | `flutter test <a két gate_test>` `/tmp/e14r09-probe`-ban | **27/27 ZÖLD** |
| Valódi-sértés próbák | 6 eldobható mutáció, lásd §3 | **6/6 PIROSRA vitte a suite-ot** |
| Kör-jelzés | `.codex-round-status` | `status=done`, `gate_shape=ok`, `head=7f3a8f18` |

A `dirty_files=1` a jelzésfájlban a jelzés pillanatában mért érték; a fán
utána `git status --short` **üres** — a §10 handoff commitja (`7f3a8f18`)
lezárta. Nincs elmaradt, commitolatlan munka (L21 ellenőrzés elvégezve).

## 2. A brief kilenc acceptance-pontja — cellánként igazolva

| # | Acceptance | Fedő cella | Verdikt |
|---|---|---|---|
| 1 | hiányzó/`null` metrika → FAIL, névvel | `recognition_release_gate_test.dart` „fail-closed: missing/null metric” (2 cella) | ✅ |
| 2 | határ az elfogadó oldalon, MINDKÉT irányon | „boundary belongs to the accepting side”: `0.899/0.9/0.901` és `2.001/2.0/1.999` (3 cella) | ✅ |
| 3 | három formátum ugyanaz a szám | „single source, three formats”: overall + csoport-metrika, MD/HTML **oszlop-fejléc** szerint olvasva | ✅ |
| 4 | három esemény-kategória külön, pontos képlet | „event categories” (3 cella), köztük a `rejected` nem-szivárgás cellája | ✅ |
| 5 | bájtra azonos, időbélyeg nélkül | „determinism” (3 cella) | ✅ |
| 6 | `thresholdsVersion` minden ítéletnél, minden formátumban | „every format names the gate thresholds version” | ✅ |
| 7 | ismeretlen `schemaVersion` / irány-deklaráció → típusos hiba | „typed configuration errors” (5 cella) | ✅ |
| 8 | négy `GroupKey`, determinisztikus sorrend, „ismeretlen” csoport számmal | „unknown group naming” (3 cella) + rendezés-cella | ✅ |
| 9 | a szállított v1 fájl kipinnelve hordozza a Ch14 Alphát | „shipped v1 threshold file” (2 cella) | ✅ |

**AC 3 külön kiemelve (L526):** a Markdown-visszaolvasó
(`_mdTableCell(markdown, heading:…, matchColumns:{…}, readColumn:'Value')`) a
tábla **fejléc-neve** alapján keresi meg az oszlopot, nem pozíció szerint —
pontosan az a hibaosztály van kizárva, amit az L526 mért. Ugyanez a HTML-nél.

**AC 9 külön kiemelve (L613):** a kipinnelt cella a fájlból beolvasott
értékeket a tesztbe írt konstansokhoz hasonlítja, **nem** méri újra az élő
fából. A küszöb csökkentése tehát csak a teszt egyidejű, látható átírásával
lehetséges.

## 3. Valódi-sértés próbák (eldobható mutációk, `/tmp/e14r09-probe`)

Mind a hat mutációt alkalmaztam, lefuttattam a két gate-tesztet, majd
`git checkout -- .`-val visszaálltam. A fán **nem maradt** nyoma.

| # | Mutáció | Melyik brief-mátrix sort próbálja | Eredmény |
|---|---|---|---|
| P1 | `value >= entry.threshold` → `value > entry.threshold` | „a küszöb-összehasonlítás szigorú (`>`)” | **PIROS** |
| P2 | a hiányzó-metrika ág `passed: false` → `passed: true` | „hiányzó metrika → `skip`” | **PIROS** |
| P3 | `sample.higherIsBetter ? … : …` → fixen `value >= threshold` | „az irány fixen `>=`” | **PIROS** |
| P4 | `uncertainCorrect: null` → `uncertainCorrect: 0` | „az `uncertainCorrect` `0`-t ad” | **PIROS** |
| P5 | `'generatedAt': DateTime.now().toIso8601String()` a JSON gyökerébe | „a renderer időbélyeget ír” | **PIROS** |
| P6 | a szállított `recognition_release_gate.json` első `0.9` küszöbe → `0.5` | „a küszöbfájl v1 értéke elcsúszik” | **PIROS** |

A P3 és a P6 azért fontos, mert ezek a kör legkönnyebben elnémuló
gyengítései: az irány-forrás összeolvasztása (L549 hibaosztálya) és a küszöb
csendes lazítása (ADR 0511 D9). Mindkettőt gépi cella fogja.

## 4. Az ADR 0511 döntéseinek megfelelése

- **D1 (fail-closed):** `_evaluateEntry` a `sample.value == null` ágon `passed:
  false`-t ad, és a `reason` szó szerint tartalmazza a `metricPath`-t
  (`recognition_release_gate.dart:355-367`). Ismeretlen `metricPath`, illetve
  az `overall.` prefixen kívüli útvonal **típusos hiba** (dobás), nem néma
  átengedés — ez szigorúbb, mint a FAIL-ítélet, tehát megfelel.
- **D2 (az irány a reportból):** a `recognitionMetricExtractors` regiszter
  minden bejegyzése UGYANARRÓL a metrika-példányról olvassa a `value`-t és a
  `definition.higherIsBetter`-t (`:59-108`) — nincs második irány-forrás. A
  `_directionKeys` (`higherIsBetter`, `direction`, `>=`, `<=`) ellenőrzése a
  `_checkKeys` **előtt** fut (`:289-300`), ezért az irány-deklaráció a
  megkülönböztető `directionDeclared` hibát kapja, nem a generikus
  `unknownField`-et. Ez a sorrend szándékos és helyes.
- **D3 (a határ az elfogadó oldalon):** `:370-372`, közvetlen `double`
  összehasonlítás, epszilon és kerekítés nélkül.
- **D4 (három kategória):** `RecognitionEventCategories.fromMetrics`
  (`recognition_report_renderer.dart:100-109`) pontosan a §0.0 R4 képleteit
  használja; az `uncertainCorrect` `null`, mellette **konstans** (tehát
  determinisztikus) `unavailableReason`.
- **D5 (egy forrás, három formátum):** a kerekítés egyetlen helyen, a
  `_round` függvényben történik a modell építésekor (`:34-35`); a három
  renderelő csak stringgé alakít. Lásd viszont az N1 megjegyzést.
- **D6 (verziózott séma):** `supportedRecognitionGateSchemaVersion = '1'`,
  eltérés → `unknownSchemaVersion` típusos hiba (`:254-261`); a
  `thresholdsVersion` MINDEN `RecognitionGateFinding`-ben ott van, nem csak a
  verdikt fejlécében.
- **D7 (determinizmus):** a küszöb-bejegyzések `metricPath` szerint
  rendezve (`:277`), a metrika-nevek rendezve (`:62`), a csoportok
  `SplayTreeMap`-ben gyűlnek, majd (groupKey, groupValue) szerint rendezve
  (`:191-194`, `:240`) — sehol nincs halmaz-iterációs sorrend.
- **D8 (a le nem fedett Alpha-sorok kimondva):** a szállított fájl 10
  bejegyzést hordoz, a két „szűkített jelentésű” sor (`acceptedAccuracy`,
  `falseVisibleEventsPerMinute`) `label` mezője **szó szerint kimondja**, hogy
  esemény-fajta-agnosztikus változatról van szó; a 4 kihagyott sort a §10.3 és
  a dashboard-doksi sorolja fel. Ez pontosan az L549 elkerülése.
- **D9 (a lazítás emberi döntés):** kipinnelt cella, lásd AC 9 és P6.

## 5. Leletek

### BLOCKER

Nincs.

### MAJOR

Nincs.

### MINOR

Nincs.

### NOTE

- **N1 — a kapu-ítéletek `value` mezője kikerüli az egyetlen kerekítési
  pontot.** A `RecognitionGateFinding.value` a nyers (kerekítetlen) metrika, a
  JSON így teljes pontossággal írja ki, a Markdown és a HTML viszont a
  renderelőben, a `_fmt` (`toStringAsFixed(4)`) útján kerekít. A D5 kockázata
  (a formátumok EGYMÁSTÓL való elcsúszása) **nem áll fenn**, mert MD és HTML
  ugyanazt az egyetlen `_fmt`-et használja, és mindhárom ugyanabból a
  `double`-ből indul; az AC 3 cellája a metrika-táblákon mér, ahol a kerekítés
  a modellben történik. Egy jövőbeli kör áthúzhatja a `finding.value`-t is a
  `_round`-on, ha a kapu-tábla is bekerül a formátum-egyezés cellájába. Nem
  igényel javítást ebben a körben.
- **N2 — `_summarize` metrikánként kétszer hívja az extraktort** (egyszer a
  `value`-ért, egyszer a `higherIsBetter`-ért,
  `recognition_report_renderer.dart:66-70`). Tiszta függvények, tehát az
  eredmény azonos; mikroszkopikus, mérhetetlen többletköltség. Stílus-megjegyzés.
- **N3 — a `(unknown)` bucket-név nem ütközhet valós csoportértékkel**, mert a
  zárójeles alak a manifest-fixtúrákban nem fordul elő; ha egy valós korpusz
  mégis „(unknown)” nevű játékost hozna, a két halmaz összeolvadna. Egy
  jövőbeli kör elkülönítő prefixszel zárhatja ki. A kockázat elméleti, a kör
  mércéjét nem érinti.

## 6. Scope és tilos zóna

A diff nyolc fájlja **pontosan** a brief `allowed_paths` listája. Külön
ellenőriztem, hogy a kör NEM nyúlt hozzá:

- `lib/features/live/domain/evaluation/recognition_metrics.dart`,
  `…/recognition_split.dart`, `…/data/evaluation/recognition_evaluation_runner.dart`
  (E14-R08 lezárt köre) — érintetlen;
- `docs/eval/recognition-release-guard.md` (E14-R01 rekordja) — érintetlen;
- `lib/features/live/public.dart`, `pubspec.yaml`, `docs/adr/**` (a `0511`-et
  az orchestrátor írta a pre-flightban), `.github/**`, `tools/**` — érintetlen.

A §10.6 kifejezetten rögzíti, hogy a `RecognitionSplitBuilder`/`LeakageDetector`
NEM került felhasználásra (azok train/eval fold-okhoz valók, és hiányzó
kulcsra dobnak) — a csoport-bontás saját, `SplayTreeMap`-alapú particionálás.
Ez helyes olvasat, nem kerülő út.

## 7. VÉGSŐ DÖNTÉS

**APPROVED.** Nyitott BLOCKER/MAJOR/MINOR lelet nincs; a három NOTE
tájékoztató jellegű, javító kört nem indokol. A merge a szokásos zöld
kapuhoz kötött: a `full-gate.yml` és a `router-ci.yml` a merge SHA-ján
`success` kell legyen (ADR 0052 / 0086 §2).
