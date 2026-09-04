# E14-R07 — Review

Brief: `docs/rounds/e14-r07-annotation-contract-and-agreement.md`
Diff: `git diff main...sonnet-impl/e14-r07-annotation-contract-and-agreement` (`94a2e23d..13c21495`)
Reviewer: Claude (Opus 5) · Dátum: 2026-09-04
Implementer motor: `sonnet-impl` (Claude Sonnet 5, `--effort high`)
Verdikt: **APPROVED** (a kör MUNKÁJÁRA) — a merge-et egy ÖRÖKÖLT, `main`-oldali
piros CI blokkolja, nem ennek a körnek a diffje (lásd §6).

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 2

A review izolált `/tmp/review-e14-r07` klónban futott (a közös munkafán másik
kör dolgozik), a HEAD `13c2149594b8a42fd38380ed7ffa98478c232c9a`. A gate-et,
a CLI-t és mind a három falszifikációs próbát magam futtattam — semmit nem
fogadtam el bemondásra.

## 1. Gate — saját mérés, izolált klónban

```
tools/round-gate.sh test/features/live/evaluation/recognition_annotation_test.dart
GATE_EXIT=0

    format                                                     zöld
    analyze                                                    zöld
    test test/features/live/evaluation/recognition_annotation_test.dart zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
```

A célzott teszt 18 cellája zöld (`All tests passed!`).

## 2. Scope-audit — gépi

```
python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e14-r07 \
  --brief docs/rounds/e14-r07-annotation-contract-and-agreement.md --base 94a2e23d
Legacy scope audit OK (94a2e23d3624..13c2149594b8, 8 changed path(s), 0 generated/ignored)
```

Nyolc érintett útvonal, mind a brief `allowed_paths` listáján. A tilos zóna
érintetlen: `lib/features/live/public.dart`, `evaluation/analysis/**`,
`evaluation/recognition/{README.md,baseline_manifest*.json}`,
`test/fixtures/manifest.json`, `pubspec.yaml`, `docs/adr/**` (az ADR 0359 az én
pre-flight commitom, nem az implementeré), `.github/**`, `tools/**` — egyik sem
változott.

## 3. Acceptance criteria — tételesen, bizonyítékkal

| # | Kritérium | Bizonyíték |
|---|---|---|
| 1 | Séma-verzió eltérése típusos hiba | `recognition_annotation_parser.dart:85-92` → `invalidSchemaVersion`; cella: „unsupported schema version is a typed InvalidSchemaVersion failure" |
| 2 | Átfedő eseménypár elutasítva, MINDKÉT index a hibában | `:236-251` (`conflictingIndices: [i, j]`) és `:256-274` (akkord-sáv, `[startMs,endMs)` metszet); két cella pinneli mindkét indexet |
| 3 | Hiányzó `provenance` → típusos hiba; `auto` nem konvertálódik | `:186-192` `_requireEnum` → `missingField`; cella: „an \"auto\" provenance value is parsed as auto, never promoted”. **Falszifikálva** (§4 M2) |
| 4 | CLI determinisztikus, kétszeri futás bájtra azonos | saját mérés: két futás SHA-256-ja `3fc936d9…0bf5` = `3fc936d9…0bf5`, `cmp` egyezik. **Falszifikálva** (§4 M3) |
| 5 | Fixture: 10/10 esemény, 8 párosított, 7 irány-egyezés → `directionAgreement = 0.875` | CLI-kimenet: `"matchedEventCount": 8`, `"directionAgreement": 0.875`, `"matchedEventRatio": 0.8`, `"eventCountA": 10`, `"eventCountB": 10` |
| 6 | Onset-tolerancia inkluzív: 49 párosít, 50 párosít, 51 nem | `recognition_annotation.dart:298` (`<= toleranceMs`); cella a három küszöbre; **független mérés**: `--tolerance-ms 49` → `matchedEventCount: 7` (a fixture 2000↔2050 pontosan a határon lévő párja kiesik), alapértéken 8. **Falszifikálva** (§4 M1) |

A fixture nem túlillesztett: az annotátor-B `b9`/`b10` eseménye (50000/51000 ms)
szándékosan **nem párosítható**, az `a6`↔`b6` pár pedig irányban **eltér** —
így egy „mindent párosít" és egy „minden irány egyezik" implementáció is
pirosra vált. A `provenance` mindhárom értéke szerepel a fixture-ben.

## 4. Valódi-sértés próbák (eldobható mutációk, mind visszaállítva)

Mindhárom mutációt az izolált klónban futtattam, majd `git checkout --`-ral
visszaállítottam (`git status --short` üres a próbák után).

| # | Mutáció | Eredmény |
|---|---|---|
| M1 | `_matchEvents` határa `<=` → `<` | **PIROS** 2 cella: „onset-tolerance boundary is inclusive…" és „the fixture: … directionAgreement = 0.875" |
| M2 | hiányzó `provenance` → `AnnotationProvenance.human` default | **PIROS** 1 cella: „missing provenance is a typed failure, never defaulted to \"human\"" |
| M3 | `toJson`-ba `generatedAt: DateTime.now()…` | **PIROS** 2 cella: „the fixture report is byte-identical across two runs" és „toJson uses a fixed, canonical (alphabetical) key order" |

A cellák tehát a VISELKEDÉST mérik, nem a szerkezetet — az implementer §10-ben
állított falszifikációt függetlenül reprodukáltam.

## 5. Architektúra és termékhatárok

- **Nincs kereszt-feature import** (ADR 0359 D6): a két új `lib/` fájl kizárólag
  `dart:convert`, `dart:math` és `package:strumsight/core/music/strum.dart`
  importot használ — a `core` irány legális, az `audio_analysis` evaluation kódja
  NINCS importálva (a Kuhn-párosítás mintája MÁSOLVA van, dokumentáltan:
  `recognition_annotation.dart:277-283`). `architecture` gate zöld.
- **`lib/features/live/public.dart` érintetlen** — az új típusok nem publikus
  szerződés. A `live` barrel kézzel írott (nincs `public/` fragment-könyvtár),
  ezért nem is válhatott elavulttá (§0.0.1 R4).
- **Nyers hang érintetlen** (D1): a `lib/`-oldali kód `dart:io`-mentes; fájlt
  kizárólag a `tool/recognition_annotate.dart` olvas, írásra semmit nem nyit
  (`File(...).readAsString()` az egyetlen I/O).
- **Nulla egress** (§0.0.1 R7): a diffben nincs `Dio`, `HttpClient`,
  `package:http`, `path_provider`, `share_plus` — `docs/privacy/data-inventory.yaml`
  nem válik szükségessé; `secrets` gate zöld (4332 fájl, 0 lelet).
- **CLI-hibautak:** hiányzó fájl → `exit 2` (mérve), parse-hiba → `exit 1`,
  érvénytelen `--tolerance-ms` → `exit 2`. A hibaüzenet a `stderr`-re megy, a
  riport a `stdout`-ra — a kimenet diffelhető marad.

## 6. A merge-blokkoló: ÖRÖKÖLT `main`-oldali piros CI (nem ez a kör)

A kör exact-SHA CI-ja (`13c21495`):

- **Router CI** `33861665049` → **failure**, EGYETLEN piros cellával:
  `tools/tests/test_completion_matrix_sync.py::…::test_the_real_tree_is_in_sync`
  → `Ch14 (E14): reports done=3, queue measures done=4` /
  `reports pending=16, queue measures pending=15` (`1 failed, 914 passed`).
- Ugyanez a cella **a `main`-en is piros**: run `33859597093` a `1feecc11`
  SHA-n, azonos assertionnel — tehát a piros az `E14-R06` záró
  `docs(handoff)` commitjából örökölt drift, nem ennek a körnek a diffjéből.
  A `4a02b959` (az `E14-R06` merge-commitja, a queue-flip ELŐTT) még **zöld**
  volt.

A javítás egy parancs — `tools/sync-completion-matrix.py --write` — de az a
`docs/sdd/program-completion-report.md` fájlt írja, ami ennek a körnek a TILOS
zónájában van (nem a brief `allowed_paths`-án), és nem is a kör saját, még nem
merge-elt artefaktuma (ADR 0087 §2). Ezért a kör **H3 halttal** zárul, a
merge-lépés előtt; a feloldás az önjavító session dolga (ADR 0112). Részletek és
a mért gyökérok a kör-jelzésben.

## 7. Leletek

### NOTE-1 — Az esemény-„átfedés" azonos `timeMs`-t jelent, nem közelséget

`recognition_annotation_parser.dart:236-251`: két esemény akkor ütközik, ha
AZONOS sávon (`type`) PONTOSAN ugyanabban a `timeMs`-ben van. Pont-eseménynél ez
védhető definíció (két 1 ms-re lévő onset két külön onset), és a séma
(`annotation_schema.json:32`) meg a doksi ki is mondja — ezért NOTE, nem MINOR.
Ha egy későbbi kör „minimális esemény-távolságot" akar előírni, az új
acceptance-cella, nem ennek a körnek a hiánya.

### NOTE-2 — `matchedEventRatio` nevezője a nagyobb annotátor eseményszáma

`recognition_annotation.dart:259-261`: a nevező `max(countA, countB)`, nem a
párosított párok száma — a doc-comment (`:154-160`) és egy külön cella
(„matchedEventRatio divides by the larger annotator event count") ezt ki is
mondja, és a `directionAgreement`-tól (párosított nevező) elkülöníti. A fixture
egyenlő eseményszámai mellett a két nevező véletlenül egybeesne; az eltérő
eseményszámot mérő cella zárja ezt a rést. Megfigyelés, nem lelet.

## 8. Amit NEM mértem

- A teljes `flutter test` suite és a randomizált property gate CI-oldali
  eredményét (a Full Gate run `33861676472` a jelentés írásakor még futott; a
  Router CI eredménye a §6 szerint örökölt piros). A merge ezért NEM történt meg.
- APK-építés: a CI-terv (`tools/round-ci-plan.py`) `native_gate=false`,
  `apk_required=false` alapján `full-gate.yml`-t rendelt, `build-apk.yml`-t nem.
