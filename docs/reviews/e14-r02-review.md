# E14-R02 review — Reprodukálható felismerési baseline és evidence index

- **Reviewer:** Claude (Opus 5), orchestrátor-szék — READ-ONLY review
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Branch:** `sonnet-impl/e14-r02-baseline-and-evidence-index`
- **Implementációs commit:** `12c50314`; upstream-merge után a mért HEAD `5dacc3b6`
- **Brief:** `docs/rounds/e14-r02-baseline-and-evidence-index.md` (§0.0 pre-flight, R1–R8)
- **ADR:** [0354](../adr/0354-recognition-baseline-manifest-and-evidence-index.md) (D1–D9)
- **Dátum:** 2026-09-04

## 1. Módszer

A review izolált másolaton, a szállított kódot **futtatva** mér — nem a
diffet olvasva. Nyolc valódi-sértés próbát futtattam a checker ellen
(`/tmp/e14r02-probe`, `dart run … --check` a szállított generátorral,
mutált manifest/séma bemenetekkel), plusz egy determinizmus-próbát és a
számok visszamérését a forrás-reportra.

## 2. Findings

### MAJOR-1 — a checker az ISMERETLEN séma-kulcsot NÉMÁN átengedi (ADR 0354 D8 megsértése)

- **Fájl:** `tool/benchmarks/recognition_baseline_manifest.dart:135-327` (`_validate`)
- **A szerződés:** az ADR 0354 D8 kimondja: *„A séma és a checker együtt egy
  szerződés; a le nem fedett séma-kulcs hallgatólagosan érvénytelen, ezért a
  checker ismeretlen séma-kulcsra is fail-closed."* Ez a döntés a kézzel írt
  validátor ára — pontosan azért került az ADR-be, mert egy részhalmaz-validátor
  a le nem fedett kulcsokat nem hibának, hanem NEM LÉTEZŐNEK látja (ugyanaz a
  hibaosztály, amit az [L566](../LESSONS.md#l566) mért).
- **A mérés (P1 próba):** a `baseline_manifest_schema.json`-ban az
  `appCommit` mezőre felvettem egy `"maxLength": 3` megszorítást. A manifest
  `appCommit` értéke `5ceed22d` — **8 karakter**, tehát egy valódi draft-07
  validátor PIROSAT ad. A szállított checker kimenete:

  ```
  P1 — ISMERETLEN séma-kulcs (maxLength az appCommit-on)
    exit=0
  Recognition baseline manifest OK; idx.md is up to date.
  ```

  A `maxLength` a `_validate` `switch`-eiben nincs lefedve, ezért a
  megszorítás **nyomtalanul eltűnik**. Ugyanez áll a `maxLength`-en kívül az
  `allOf`, `anyOf`, `if`/`then`/`else`, `uniqueItems`, `exclusiveMinimum`,
  `exclusiveMaximum`, `maximum`, `multipleOf`, `propertyNames`, `dependencies`,
  `contains`, `patternProperties`, `format` kulcsokra is.
- **Hibaforgatókönyv:** egy KÉSŐBBI Chapter 14 kör (grouped evaluation,
  dashboard, A/B) szigorítani akarja a szerződést — pl. `"uniqueItems": true`
  a `models`-re, vagy `"allOf"` egy összetett feltételre. A séma-diff
  meggyőzően néz ki, a `--check` zöld, a gate zöld, a review zöld — és a
  megszorítás **soha nem érvényesül**. A hiba akkor derül ki, amikor egy
  érvénytelen manifest már bekerült a release-döntésbe. Ez pont az a csendes
  rés, aminek a bezárása ennek a körnek a TÁRGYA.
- **Kért javítás:** a `_validate` (és a `_resolveRef` által feloldott
  al-sémák) ismerjenek egy **zárt, felsorolt** kulcs-halmazt, és minden azon
  kívüli kulcsra adjanak `ManifestIssue`-t (nem kivételt), hogy a `--check`
  nem nulla kóddal álljon meg. A halmazba a nem-megszorító, dokumentációs
  kulcsok is beleértendők (`$schema`, `$id`, `title`, `description`,
  `definitions`, `examples`, `default`) — azokat átengedni helyes, de
  **kimondva**, nem hallgatólagosan. A javítás kapjon **saját cellát** a
  `test/tooling/recognition_baseline_manifest_test.dart`-ban, ami egy
  ismeretlen kulcsot tartalmazó sémára pirosat vár (a fenti `maxLength`
  próba a kész minta).

## 3. Amit MÉRTEM, és rendben van

| Próba | Várt | Mért |
|---|---|---|
| P0 — szállított állapot `--check` | 0 | **0** ✅ |
| P2 — `n = 0` egy metrikán | ≠0 | **1** — `$.metricBlocks.chord.metrics.accuracy.n: must be >= 1` ✅ |
| P3 — hiányzó `command` | ≠0 | **1** — `missing required property "command"` ✅ |
| P4 — a VISSZAVONT `bpm` blokk törlése | ≠0 | **1** — `missing required property "bpm"` ✅ |
| P5 — `measured` blokk ÜRES `metrics`-szel | ≠0 | **1** — `must have at least 1 propert(y/ies)` ✅ |
| P6 — üres `models` + törölt `modelsRationale` | ≠0 | **1** — `must match exactly one alternative (matched 0 of 2)` ✅ |
| P7 — `not-measured` blokk `metrics`-szel | ≠0 | **1** — `matched 0 of 2` ✅ |
| P8 — kétszeri renderelés | bájtra azonos | **azonos**, és a szállított indexszel is ✅ |

- **A számok visszamérve a forrásra** (`docs/eval/real-audio-dsp-baseline.md`):
  `accuracy 67.069% / n=11767`, `majorityClassBaselineAccuracy 18.832% / n=11767`,
  `minorSubsetAccuracy 83.333% / n=222` — mind egyezik, mindegyik mellett ott a
  `sourceFile` ÉS a mező-szintű `command` (D2 ✅). Kitalált szám nincs.
- **D7 ✅:** `models: []` + nem üres `modelsRationale`; idegen modell-hash nem
  került be (az A6 csoport külön cellája méri).
- **D3 ✅:** a `direction`/`noChord`/`latency`/`calibration` mind
  `status: "not-measured"` valódi indoklással, `metrics` kulcs nélkül. A
  `direction` indoklása a `recognition-release-guard.md` 80,7%-os számáról tett
  állítást is helyesen sorolja be külön mérésként — **ellenőriztem a
  forrásfájlban** (`recognition-release-guard.md:15`), az állítás igaz.
- **§7.1 falszifikációs cella ✅:** a §10.2 a rendezés kikapcsolásának TÉNYLEGES
  piros terminálkimenetét tartalmazza (A4 és A8 bukik, `Differ at offset 2066`),
  nem prózát.
- **Scope ✅:** a gépi audit tiszta —
  `Legacy scope audit OK (c209fe51368b..12c50314d7ee, 7 changed path(s), 0 generated/ignored)`.
  A `lib/**`, `ml/**`, `assets/**`, `pubspec.yaml`, `.github/**` érintetlen.
- **Tiszta Dart ✅:** a generátor csak `dart:convert` + `dart:io`-t importál; a
  teszt A4 csoportja ezt önellenőrző cellával is méri.

## 4. Verdikt

**CHANGES REQUESTED** — 1 MAJOR (MAJOR-1), 0 BLOCKER, 0 MINOR.

A kör terméke egyébként erős: a hat fail-closed cella mind valóban pirosra vált,
a determinizmus bájtra bizonyított, a számok a forrásra visszamérve helyesek. Az
egyetlen nyitott lelet a saját ADR-je egy kimondott döntésének hiánya — és épp
abban a mechanizmusban, ami a jövőbeli köröket védené.

## 5. Javító kör után — újra-ellenőrzés

_(a javító kör után tölti ki a reviewer)_
