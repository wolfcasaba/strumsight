# E12-R14 — Review: Performance budget harness

- **Kör:** `E12-R14` (Chapter 12, Kör 14)
- **Branch:** `sonnet-impl/e12-r14-performance-budget-harness`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude (Opus 5), read-only, izolált `/tmp/review-e12-r14` klón
- **Review-lt commit:** `90adb996` (pre-flight bázis: `f96edc1c`)
- **ADR:** [`0474`](../adr/0474-benchmark-record-and-performance-budget-comparison.md)
- **Dátum:** 2026-08-29

## 0. VERDIKT (1. menet)

**CHANGES REQUESTED** — 2 MAJOR, 2 MINOR, 2 NOTE. (A javító kör mind a hatot lezárta — §5.)

Mindkét MAJOR ugyanabból a gyökérből fakad: a `compare_benchmarks.py`
összehasonlítási KULCSA a puszta metrika-NÉV, holott az ADR 0474 D1/D2 egész
létezési oka az, hogy egy mérés a `deviceId` + `buildSha` PÁRJÁVAL együtt
értelmes. Az eszköz ma ellenőrzi, hogy a metaadat JELEN VAN és ismert — de soha
nem ellenőrzi, hogy a két oldal metaadata EGYEZIK-e. Ezzel a brief §5.1
kifejezetten nevesített hibaosztálya („két különböző készüléken mért érték
összevetése értelmetlen, és pontosan ezt rejtené el") a mérce alatt marad.

## 1. Gépi ellenőrzések — a reviewer SAJÁT futtatása

| Ellenőrzés | Parancs | Eredmény |
|---|---|---|
| Scope-audit | `python3 tools/scope-audit.py --repo /tmp/review-e12-r14 --brief docs/rounds/e12-r14-performance-budget-harness.md --base f96edc1c` | `Legacy scope audit OK (f96edc1ced0c..90adb9961dfc, 6 changed path(s), 0 generated/ignored)` |
| Implementer-jelzés | `.codex-round-status` | `status=done`, `gate_shape=ok`, `scope_audit=ok`, `head=90adb996` |
| Diff-terjedelem | `git diff --stat f96edc1c HEAD` | 6 fájl, +1575 sor, mind a `allowed_paths` listáján |
| Kör-gate | `tools/round-gate.sh test/tooling/benchmark_budget_test.dart` (izolált klón) | lásd §5 |
| CI (exact-SHA) | `full-gate.yml` [33237506161](https://github.com/wolfcasaba/strumsight/actions/runs/33237506161), `router-ci.yml` [33237506332](https://github.com/wolfcasaba/strumsight/actions/runs/33237506332) — head `90adb9961dfc` | lásd §5 |

A `tools/round-ci-plan.py` a `full-gate.yml`-t írta elő (`apk_required: false`,
`router_ci_expected: true`), a Router CI-t a `docs/rounds/**` érintése triggereli.

## 2. Leletek

### F1 — MAJOR: két KÜLÖNBÖZŐ eszközön mért érték némán `pass`-t kap

**Hely:** `tool/compare_benchmarks.py:176-194` (`compare()`).

**Mérés (eldobható próba, `/tmp/review-e12-r14`):** ugyanaz a metrika, baseline
`deviceId: pixel_6a`, jelölt `deviceId: xiaomi_redmi_note_12`, azonos érték:

```
PROBE1b cross-device equal rc= 0
analysis_cache_miss_latency: status=pass delta=0.000000 baseline=30589 candidate=30589 direction=lowerIsBetter
compare_benchmarks: 1 measured metric(s) compared, 0 warn, 0 fail, 0 unknown
```

**Miért lelet.** A `validate_record()` (`:115-119`) helyesen elutasítja a hiányzó
és az ismeretlen `deviceId`-t — de a `compare()` a jelölt-oldalt kizárólag
`record["metric"]`-re kulcsolja (`:176-180`), és a talált párnál (`:194`) csak az
értéket és az irányt használja. Sem a `deviceId`, sem a `buildSha` egyezését nem
méri semmi. A kör alapállítása ezzel megfordul: a metaadat MEGLÉTE kötelező, a
JELENTÉSE viszont nem érvényesül — pontosan az a látszat-fedezet, amit az
ADR 0474 D1 „NEM elfogadható gyengítés" bekezdése kizárni hivatott.

**Javasolt irány (nem kész patch):** az összevetés kulcsa legyen
`(metric, deviceId)`, VAGY a `compare()` elején egy explicit egyezés-ellenőrzés,
amely eltérő `deviceId` esetén `RecordFormatError`-t emel (exit 2). A `buildSha`
esetében az eltérés NEM hiba (két build összevetése épp a cél), de a kimeneti
sornak hordoznia kell mindkét oldal `buildSha`-ját, hogy a riport önmagában
megmondja, mi mihez képest mozdult.

**Kötelező mérce a javításhoz:** a cellának PIROSNAK kell lennie arra az
implementációra, amely `deviceId`-t nem hasonlít össze — azaz a fenti PROBE1b
alakú cella (azonos metrika, eltérő eszköz, azonos érték) NEM lehet `pass`.

### F2 — MAJOR: azonos metrika-nevű második rekord elnyeli az elsőt; valódi regresszió tűnik el

**Hely:** `tool/compare_benchmarks.py:176-180` (a dict-comprehension).

**Mérés:** a jelölt-dokumentum KÉT `measured` rekordot tartalmaz ugyanarra a
metrikára — `pixel_6a` a baseline **kétszeresén** (100 % romlás) és `pixel_7` a
baseline értékén:

```
PROBE3 dup-metric rc= 0
analysis_cache_miss_latency: status=pass delta=0.000000 baseline=30589 candidate=30589 direction=lowerIsBetter
compare_benchmarks: 1 measured metric(s) compared, 0 warn, 0 fail, 0 unknown
```

**Miért lelet.** A dict-comprehension az UTOLSÓ azonos kulcsú rekordot tartja
meg; az első — a 100 %-os regressziót hordozó — bejegyzés nyom nélkül eltűnik, a
riport zöld, a kilépési kód 0. Ez ugyanaz a hibaosztály, amit a brief §9 első
kockázata („a hiányzó = zöld csapda") és az ADR 0474 D5 zár — csak nem a
HIÁNYZÓ, hanem az ÁRNYÉKOLT mérésen keresztül. A `(metric, deviceId)` kulcsra
váltás ezt az F1-gyel EGYÜTT zárja; ha a kulcs változatlan marad, a duplikátumot
külön kell hibának minősíteni.

**Javasolt irány:** az F1 kulcs-váltása után a duplikált `(metric, deviceId)`
pár maradjon explicit `RecordFormatError` (exit 2) — a néma „utolsó nyer"
semmilyen kulcsválasztás mellett nem elfogadható.

### F3 — MINOR: nulla (vagy negatív) baseline-érték kezeletlen `ZeroDivisionError`-t dob

**Hely:** `tool/compare_benchmarks.py:157-160` (`classify()`),
`:79-85` (`_require_number()`).

**Mérés:**

```
PROBE2 zero-baseline rc= 1
  File "/tmp/review-e12-r14/tool/compare_benchmarks.py", line 158, in classify
    delta = (candidate_value - baseline_value) / baseline_value
ZeroDivisionError: float division by zero
```

**Miért lelet.** A `_require_number()` a `0`-t és a negatív értéket is
elfogadja, a `classify()` viszont osztóként használja. A kilépési kód 1, tehát
fail-closed marad — de a dokumentált szerződés (a modul docstringje: `2` =
record-format error) helyett Python-traceback jön, és negatív baseline esetén a
`delta` ELŐJELE fordul, azaz a romlás javulásnak látszana. A `sampleCount` és a
`value` értéktartományára ma nincs cella.

**Javasolt irány:** a `validate_record()` utasítsa el a nem-pozitív `value`-t
(`RecordFormatError` → exit 2), vagy a `classify()` kezelje explicit ágon a
`baseline_value <= 0` esetet. Cella mindkét élre (`0.0` és negatív).

### F4 — MINOR: bizonyítatlan doc-comment állítás a `parseBenchmarkRecords`-on

**Hely:** `tool/benchmarks/benchmark_record.dart:192-214`.

A doc-comment azt állítja: „Throws [BenchmarkRecordFormatException] on the first
invalid record". A megvalósítás viszont `record! as Map<String, Object?>`
(`:211`) — `null` vagy nem-map elem esetén `TypeError`/`_CastError` jön, nem a
dokumentált kivétel. A Python oldal ugyanezt az esetet helyesen kezeli
(`validate_record`, `:95-96` → `RecordFormatError`). A kör brief §5 doc-comment
szabálya („csak tesztben bizonyított állítás") ezt a mondatot ma nem fedi.

**Javasolt irány:** explicit `is! Map<String, Object?>` ellenőrzés +
`BenchmarkRecordFormatException`, és egy cella rá.

### F5 — NOTE: az `unknown` metrika is „compared"-ként számolódik

`tool/compare_benchmarks.py:223-230`: `measured_count = len(lines)`, és az
összegző sor `"{measured_count} measured metric(s) compared"`. Az `unknown` sor
azonban pontosan azt jelenti, hogy a metrikát NEM lehetett összehasonlítani. A
kilépési kód helyes (fail-closed), csak a szöveg félrevezető egy release-riportban.

### F6 — NOTE: az öt vision `target` rekord `deviceId: ci_host`-ot visel

`docs/performance/baseline.json` — a
`docs/manual-testing/vision-performance-benchmark.md` FPS-céljai fizikai
eszközre vonatkoznak, a rekordjuk mégis a CI-hostot nevezi meg. Az ADR 0474 D2
szerint ez nem szabálysértés (a `ci_host` legális érték), és mért készüléknevet
kitalálni TILOS lett volna — a mai állapot tehát védhető. Ha az F1 után a
`deviceId` az összevetés kulcsává válik, ez a választás átgondolandó: egy jövőbeli,
`pixel_6a`-n mért FPS nem fog párt találni a `ci_host` targethez.

## 3. Acceptance criteria — tételes ellenőrzés

| # | Kritérium | Verdikt | Bizonyíték |
|---|---|---|---|
| A1 | rekord-séma parse-olható, metaadat kötelező | ✅ | `benchmark_budget_test.dart:41-141` — 11 cella; `fromJson` minden kötelező mezőre dob |
| A2 | metaadat nélküli bemenet → nem-nulla kilépés | ✅ | `:261-287` — hiányzó `deviceId` és `buildSha`, exit 2, stderr nevesíti a mezőt |
| A3 | hiányzó metrika → `unknown` + nem-nulla kilépés | ✅ | `:288-307`; a §10 valódi-sértés próbája pirosra váltotta |
| A4 | minden baseline-érték forrás-hivatkozást hordoz | ✅ | `:154-207`; reviewer-mérés: mind a 26 `source` létező fájlra mutat |
| A5 | küszöb-cellahármas szerinti döntés | ✅ | `:308-356` + `:357-472` — 4,9 % PASS / 5,0 % WARN / 10,0 % FAIL mindkét irányra |
| A6 | egyetlen DSP/ML paraméter sem módosul | ✅ | scope-audit OK; a diff 6 fájlja között `lib/**`, `ml/**` nincs |
| A7 | irány metrikánként, alapérték nélkül | ✅ | `:357-472` — a tükrözött hármas + irány-vak és hiányzó-`direction` cella |
| A8 | `kind` mező, csak `measured` ↔ `measured` | ✅ | `:473-538`; reviewer-mérés: 6 `measured`, 6 `upperBound`, 9 `derivedContract`, 5 `target` |
| A9 | `python3` skip-ág nélkül + önvédő cella | ✅ | `:560-590` — a külső-bináris készlet pontosan `{python3}`, plusz `--version` self-check |
| **§5.1** | **device-metaadat nélküli mérés nem rekord** | ⚠ **RÉSZBEN** | a MEGLÉTE kikényszerítve, az EGYEZÉSE nem — **F1**, **F2** |

A §0.0 R2 hűsége külön kiemelendő és **helyes**: a `baseline.json` egyetlen
`< 0.1 ms` alakú felső korlátot sem emelt `measured` osztályba, és erre saját
cellát is írt (`:189-198`). A hat `measured` érték pontosan az
`epic-06-analysis-performance.md:10-14` mért mikroszekundumai.

## 4. Architektúra és termékhatárok

- AGENTS.md §9 (DSP-tilalom): **tiszta** — a diff nem érint `lib/**`-ot,
  `ml/**`-ot, sem modell-binárist; a kör mér, nem hangol.
- AGENTS.md §6: a `tool/benchmarks/benchmark_record.dart` nem importál
  feature-kódot, csak `dart:convert`-et; nincs új `pubspec` függőség, nincs
  beágyazott `tool/<csomag>/pubspec.yaml` és `.dart_tool` cache (L85/L86 zárva).
- L110/L527: a tesztfájl külső-bináris készlete mérten `{python3}`, skip-ág
  nélkül, `--version` self-checkkel — a `rg`/`grep`/`jq`/`gh` nem fordul elő.
- A `docs/baseline/**` és a `tool/benchmarks/` meglévő két eszköze
  **érintetlen** (ADR 0474 Következmények).

## 5. Javító kör (1.) — reviewer-ellenőrzés leletenként

**Javító commit:** `80caea10` (`[E12-R14] Javító kör: deviceId-egyezés a
regresszió-összevetésben (F1–F6)`), 5 fájl, +330 / −24 sor, scope-audit `ok`.

A leleteket a reviewer **saját, eldobható próbáival** ellenőrizte a friss
`/tmp/review2-e12-r14` klónban (a próbák a mérés után visszaállítva):

| Lelet | Zárva? | Reviewer-mérés |
|---|---|---|
| **F1** MAJOR | ✅ | baseline `pixel_6a`, jelölt `xiaomi_redmi_note_12`, AZONOS érték → `rc=1`, `status=unknown (missing from candidate for deviceId 'pixel_6a')`. A korábbi néma `pass` megszűnt. |
| **F1** (nem-regresszió) | ✅ | azonos `deviceId`, ELTÉRŐ `buildSha` → `rc=0`, normálisan összehasonlít, és a sor mindkettőt nevezi: `baselineBuildSha='d325d60' candidateBuildSha='deadbee'`. Két build összevetése tehát továbbra is a cél, nem hiba. |
| **F2** MAJOR | ✅ | duplikált `(metric, deviceId)` a JELÖLT oldalon → `rc=2`, `duplicate measured record for metric … deviceId … — each (metric, deviceId) pair must appear at most once`; ugyanez a BASELINE oldalon → `rc=2`. |
| **F2** (a valódi eset) | ✅ | ugyanaz a metrika KÉT KÜLÖNBÖZŐ eszközön, a `pixel_6a` a baseline kétszeresén → a regresszió most MEGJELENIK: `status=fail delta=1.000000 … deviceId='pixel_6a'`, `rc=1`. A korábbi néma elnyelés megszűnt. |
| **F3** MINOR | ✅ | `value: 0.0` → `rc=2`, `field 'value' must be a positive number, got 0.0`; `value: -5.0` → `rc=2`. Traceback helyett a dokumentált record-format error. |
| **F4** MINOR | ✅ | `benchmark_record.dart:206-216` explicit `is! Map<String, Object?>` ág + `BenchmarkRecordFormatException`; két új cella (`records: [null]`, `records: [42]`). |
| **F5** NOTE | ✅ | `0 measured metric(s) compared, 0 warn, 0 fail, 1 unknown` — az `unknown` már nem számít „compared"-nek; saját cella is méri. |
| **F6** NOTE | ✅ | `docs/performance/budgets.md` +14 sor: kimondja, hogy ma minden bejegyzés `ci_host`, és mi a teendő az első fizikai eszközös mérésnél. Kitalált készüléknév nincs. |

### 5.1 Reviewer valódi-sértés próba — SEBÉSZI, egyetlen cellára

A kötelező próba nem az implementer bemondása. A reviewer a javított
`compare()`-be **device-vak visszaesést** injektált (ha a `(metric, deviceId)`
kulcs nem talál, essen vissza bármelyik eszközre), majd futtatta a
tesztfájlt — **pontosan EGY cella lett piros**, és az a helyes:

```
Failing tests:
  test/tooling/benchmark_budget_test.dart: … F1 — the comparison key is
  (metric, deviceId), not metric alone … a candidate measured on a DIFFERENT
  device than the baseline, even with the exact same value, is never reported
  "pass" — it must surface as unknown for that device instead
```

A módosítás visszaállítva (`git diff` üres). Ez bizonyítja, hogy az F1-cella
nem vakon zöld, és pontosan a lezárt hibaosztályra van kötve
([L527](../LESSONS.md#l527) ellenpróbája).

*(Egy durvább próba — a `key = (metric, deviceId)` teljes visszaírása
`key = metric`-re — 13 cellát váltott pirosra; ez is nem-vakságot bizonyít, de
a fenti sebészi próba a pontos mérés.)*

## 6. Gate és CI — a reviewer SAJÁT futtatása

**Kör-gate, izolált `/tmp/review2-e12-r14` klón, csővezeték nélkül:**

```
tools/round-gate.sh test/tooling/benchmark_budget_test.dart
GATE_EXIT=0

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/benchmark_budget_test.dart               zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
```

**Upstream-szinkron (ADR 0086 §2):** a `main` a dispatch óta mozdult
(`4c22d973`, a párhuzamos E15-R04 sáv). A kör-ág `git merge --no-ff origin/main`-nel
beépítette (`922e35cf`), `git diff --check` tiszta, konfliktus nem volt, és
`git merge-base --is-ancestor origin/main HEAD` 0-val tér vissza. A CI ezután a
FRISS head SHA-n futott újra — a régi, `80caea10`-es futás nem merge-evidencia.

**Exact-SHA CI:** lásd a §7 táblát.

## 7. VÉGSŐ DÖNTÉS

*(a CI zöldje után kitöltve)*
