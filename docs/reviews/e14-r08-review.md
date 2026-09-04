# E14-R08 review — Csoportosított evaluation harness és leakage-védelem

- **Kör:** `E14-R08` · **Ág:** `sonnet-impl/e14-r08-grouped-evaluation-harness`
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5) · **Reviewer:** Claude (Opus 5), read-only
- **Review-elt commit:** `664a4d1d` (pre-flight: `2f56635f`) → javító kör: `97ad9b7f`
- **Dátum:** 2026-09-04
- **ADR:** [0509](../adr/0509-grouped-recognition-evaluation-and-leakage-protection.md)

## VÉGSŐ DÖNTÉS: APPROVED (a javító kör után, `97ad9b7f`)

**1. forduló: CHANGES REQUESTED (2 MAJOR)** — a leletek alább, változatlanul.
**2. forduló (`97ad9b7f`): APPROVED** — mindkét MAJOR és a MINOR-1 lezárva, a
zárás leletenként ellenőrizve (§5), a kaput friss izolált klónban magam
futtattam újra (§5.1). Nyitott BLOCKER/MAJOR/MINOR: **nincs**.

---

## 1. forduló — CHANGES REQUESTED (2 MAJOR)

A kör terméke érett és nagyrészt kiváló: a párosítás valóban maximális
kardinalitású, a határ inkluzív, a fixture-értékek kézzel levezetve és
literálként állítva, a leakage-detektor fail-closed, a falszifikációs cella
elvégezve. **Két MAJOR lelet blokkolja a merge-öt**, és mindkettő ugyanabba a
mért hibaosztályba tartozik: a *szám* helyes, a *körülötte lévő állítás* nem
mért (`docs/LESSONS.md` L549, L577).

## 1. Amit magam mértem (nem bemondás)

### 1.1 Gate-újrafuttatás izolált klónban

```
git clone --branch sonnet-impl/e14-r08-grouped-evaluation-harness \
  /home/ubuntu/ss-sonnet-impl-e14-r08 /tmp/review-e14-r08
tools/round-gate.sh test/features/live/evaluation/recognition_split_test.dart \
                    test/features/live/evaluation/recognition_metrics_test.dart
```

```
    format                                                     zöld
    analyze                                                    zöld
    test …/recognition_split_test.dart                         zöld
    test …/recognition_metrics_test.dart                       zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
MINDEN GATE ZÖLD.   GATE_EXIT=0
```

A §10.6 gate-állítása tehát **igazolt**, nem bemondás. Az `architecture` zöld
volta egyben az acceptance 10. pontját (nincs kereszt-feature import) is
bizonyítja.

### 1.2 Scope-audit (ADR 0138)

```
python3 tools/scope-audit.py --repo … --brief … --base 2f56635f
→ Legacy scope audit OK (2f56635f940f..664a4d1dcb16, 8 changed path(s), 0 generated/ignored)
```

Sértés nincs. A `docs/adr/0509-…` és a `docs/rounds/…` §0.0 revízió az
orchestrátor pre-flight commitja (`2f56635f`), nem az implementeré.

### 1.3 Eldobható próbatesztek (lefuttatva, majd törölve)

`/tmp/review-e14-r08/test/features/live/evaluation/zz_reviewer_probe_test.dart`
— a jelentés megírása után törölve, a diffbe nem került.

## 2. Leletek

### MAJOR-1 — A reportban SZÁLLÍTOTT metrika-definíció ellentmond a számításnak (ADR 0509 D3 sérül)

**Hol:** `lib/features/live/domain/evaluation/recognition_metrics.dart:501-513`
(`directionDefinition`) és `:564-575` (`chordMacroDefinition`).

**Mit állít a szállított definíció:**

> „Macro-averaged per-direction (down/up) F1 **among time-matched strum
> pairs**: a strum **missed or falsely detected in time** … **does not enter
> this metric**."
> denominator: „per-class: precision over detected-as-class pairs, recall over
> expected-as-class pairs, **among the time-matched set**"

**Mit csinál a kód:** a `_labelMacroF1` (`:909-924`) a FP-t és FN-t a
**teljes** elvárt/elfogadott populációból számolja
(`falsePositives: totalAcceptedDetected - truePositives`,
`falseNegatives: totalExpected - truePositives`), nem a párosított halmazból.
A `_labelMacroF1` saját kódkommentje (`:904-908`) ezt szó szerint ki is mondja
— tehát a **fájlon belül két, egymásnak ellentmondó állítás** él, és a
report a hibásat szállítja.

**Reprodukció (PROBE-1, futtatva):** egy elvárt `down` strum, **nulla**
detektálás:

```
PROBE-1 directionF1.value = 0.0
PROBE-1 down TP/FP/FN = 0/0/1
PROBE-1 shipped description = … does not enter this metric.
```

Nulla párosított pár van, tehát a szállított definíció szerint nincs mit
átlagolni; a kód mégis `0.0`-t ad, amit **kizárólag** egy „nem párosított"
elvárt esemény hajt. **PROBE-3** ugyanezt mutatja az akkord-oldalon
(`chordMacroF1.value = 0.0`, `C TP/FP/FN = 0/0/1`).

**A kör SAJÁT tesztje is falszifikálja a definíciót:**
`recognition_metrics_test.dart:213-221` — `down.falseNegatives == 1`,
`up.falsePositives == 2`. Ha az állítás igaz volna, mindkettő 0 lenne.

**Miért MAJOR és nem MINOR:** az ADR 0509 D3 a kör egyik LÉTEZÉSI oka („a
metrika a definíciójával együtt utazik… egy szám definíció nélkül később nem
olvasható vissza"), és a §10.3 tanúsága szerint az implementer a *képletet*
javította, a *definíció-szöveget* viszont a javítás előtti állapotban hagyta.
Egy későbbi olvasó a definícióból más számot vezetne le, mint amit kap — ez
pontosan a GOV-06b visszavont BPM-mérce hibaosztálya, és az L549/L577 mért
mintája (az őr a SZÁMOT védte, a JELENTÉSÉT nem).

**Javasolt irány (nem kész patch):** a két `description`/
`denominatorDescription` mondja ki a tényleges szabályt — a TP a párosított
párokból jön, az FP/FN viszont a teljes elfogadott/elvárt populációból —, és
**egy új cella pinnelje a definíció-szöveget** ahhoz a viselkedéshez, amit
leír (pl. a PROBE-1 alakja: nulla párosítás mellett a `down` FN-je 1 és a
makró 0.0, a definíció pedig ezt állítja). A szám NEM változik.

### MAJOR-2 — A runner (389 sor) és a commitolt CI-fixture MÉRETLEN; az acceptance 6. „futtatás"-cellája megkerüli a runnert

**Hol:** `lib/features/live/data/evaluation/recognition_evaluation_runner.dart`
(teljes fájl), `evaluation/recognition/fixtures/ci_manifest.json`,
`test/features/live/evaluation/recognition_metrics_test.dart:410-425`.

**Mérve:**

```
grep -rn "RecognitionEvaluationRunner|RecognitionManifestParseException|
          recognition_evaluation_runner" test/   → NULLA találat
grep -n  "ci_manifest|File(" test/features/live/evaluation/*.dart → NULLA találat
```

- A 389 soros, kézzel írt parszer — négy tipizált hibafajtával
  (`missingField`, `unknownField`, `invalidSchemaVersion`, `malformedValue`),
  szigorú ismeretlen-kulcs ellenőrzéssel és a `_requireKindFields`
  invariánssal — **egyetlen teszttel sem rendelkezik**. (Hogy a kód JÓ, azt a
  PROBE-2 mutatja: `RecognitionManifestParseException(unknownField) at
  manifest.cases[0].kind` — a lelet nem a helyességről szól, hanem arról, hogy
  semmi nem őrzi.)
- A **commitolt fixture-t egyetlen teszt sem olvassa**. A gate zöld marad, ha
  a fixture elromlik, sémát sért vagy kiürül. A brief acceptance 1. pontja
  szó szerint „a fixture-ön" méri a négy split-stratégiát — a split-teszt
  viszont saját, inline `RecognitionCase` listán fut
  (`recognition_split_test.dart:7-33`), a commitolt fixture-t nem érinti.
- Az acceptance 6. pont („**Kétszeri futtatás** bájtra azonos JSON-t ad")
  cellája kézzel épít `RecognitionEvaluationReport`-ot és kétszer hívja a
  `computeRecognitionMetrics`-et (`:411-424`) — a `runFromJsonString`
  útvonalat, azaz a tényleges „futtatást", **nem** méri. Egy nem
  determinisztikus parszer (pl. kulcs-bejárási sorrendtől függő eset-sorrend)
  ezen a cellán átmenne.

**Miért MAJOR:** hét leszállított fájlból kettő gépi mérce nélkül kerül a
`main`-re, és két acceptance-cella a saját szövegénél gyengébbet mér. A
§10.6 „a CLI manuálisan is lefutott" kézi futtatás — nem artefaktum, a CI-ban
nem ismételhető (`docs/LESSONS.md` L09 mintája).

**Javasolt irány:** az `allowed_paths` **nem tágul** — a
`recognition_metrics_test.dart` befogadhatja: (a) a commitolt
`ci_manifest.json` beolvasása `runFromJsonString`-gel, a report kétszeri
előállítása és bájtazonos összevetése (acceptance 6 a valódi futtatási úton);
(b) a négy split-stratégia futtatása a fixture-ből parszolt eseteken
(acceptance 1 „a fixture-ön"); (c) néhány tipizált parszer-elutasítás
(ismeretlen kulcs, rossz `schemaVersion`, `strum` direction nélkül).

### MINOR-1 — A domén-típus nem őrzi a saját kind-invariánsát, ellentétben az E14-R07 precedensével

**Hol:** `recognition_metrics.dart:27-66` (`RecognitionExpectedEvent`,
`RecognitionDetectedEvent`).

A `kind == strum → direction != null` és `kind == chord → chordLabel != null`
invariánst **kizárólag a parszer** kényszeríti ki
(`recognition_evaluation_runner.dart:229-251`). A `computeRecognitionMetrics`
viszont nyilvános belépési pont, és `:515-521`/`:577-583` `!`-tel
dereferálja ezeket — egy kézzel épített, irány nélküli strum-eset nyers
`TypeError`-t dob, nem tipizált hibát. Az `E14-R07` ugyanezt a helyzetet a
konstruktorban oldotta meg (`recognition_annotation.dart:41-47`:
`ArgumentError.value(direction, 'direction', 'is only valid for strum
events')`), tehát a fában van precedens az ellenkezőjére.

### NOTE-1 — `correctAccepted` identitás-halmaz

`recognition_metrics.dart:615-628`: a helyes elfogadott detekciók
`Set<RecognitionDetectedEvent>`-ben gyűlnek, a típusnak nincs `==`
felüldefiníciója, tehát a tagság identitás szerint dől el. Két **`const`**
módon létrehozott, mezőre azonos detekciót a Dart kanonizál (ugyanaz a
példány) — ilyenkor a `.where(correctAccepted.contains).length` mindkettőt
helyesnek számolná. A parszolt úton nem érhető el (futásidőben épülnek a
példányok), kézzel írt tesztben igen. Nem blokkol; egy `caseId`+index kulcs
vagy `identityHashCode`-független azonosító kizárná.

### NOTE-2 — Az onset-metrika a strumokat is beleszámolja

`:426-434`: az „onset" metrika `onset`+`strum` eseményekre fut
(`isOnsetLike`). Ez védhető (a strum is onset), és a szállított definíció
kimondja („accepted onset+strum detections"), tehát nem hiba — de a brief §3
külön sorolja fel az „onset P/R/F1"-et és az „any-strum F1"-et, ezért a
§10-ben érdemes egy mondattal rögzíteni, hogy a kettő szándékosan átfed.

### NOTE-3 — A §10.2 scope-szűkítés rendben van

A runner nem ágazza fold-onként a jelentést. Az acceptance egyetlen pontja sem
követeli meg, a §9 kockázati pontja pedig kifejezetten megengedi a méret
szerinti szűkítést, és a döntés dokumentált — nem hiányos munka.

## 3. Acceptance criteria — tételes állás

| # | Kritérium | Állás | Bizonyíték |
|---|---|---|---|
| 1 | Négy split-stratégia, a foldok uniója a teljes halmaz | ⚠ részben | `recognition_split_test.dart:38-60` — **inline** eseteken, nem a commitolt fixture-ön (MAJOR-2) |
| 2 | Leakage-detektor dob, megnevezi az ütköző kulcsot | ✅ | `recognition_split_test.dart` cella + §10.5 falszifikáció (kikapcsolva PIROS, visszaállítva ZÖLD) |
| 3 | 50 ms határ inkluzív (49/50/51) | ✅ | `recognition_metrics_test.dart:306-340`, három cella |
| 4 | Kézzel levezetett metrika-értékek literálként | ✅ | `:166-305`, 16 cella; §10.4 levezetés + `python3` kimenet |
| 5 | A report tartalmazza a definíciókat | ⚠ | jelen van, de **tartalmilag hibás** két metrikán (MAJOR-1) |
| 6 | Kétszeri futtatás bájtazonos JSON | ⚠ részben | `:410-425` — a runnert megkerüli (MAJOR-2) |
| 7 | Hiányzó csoportkulcs → tipizált hiba, nincs `unknown` fold | ✅ | `recognition_split_test.dart:120-160`, üres string is hiány |
| 8 | L269-ellenpélda: 2 TP, nem 1 | ✅ | `:342-380`; a Kuhn-implementáció `:771-847` |
| 9 | Minden metrika hordozza az irányát | ✅ | `:382-408`, mind a négy hiba-metrika tételesen |
| 10 | Nincs kereszt-feature import | ✅ | gate `architecture` zöld (1.1) |

## 4. Merge-feltétel (1. forduló)

A **MAJOR-1** és **MAJOR-2** lezárása után: friss gate + a `full-gate.yml` és a
`router-ci.yml` `success` a merge SHA-n. A javító kör ugyanazzal a motorral
(`sonnet-impl`), az `allowed_paths` **tágítása nélkül** — mindkét lelet a már
engedélyezett fájlokon belül javítható.

---

## 5. 2. forduló — a javító kör ellenőrzése (`97ad9b7f`)

A javító kör diffje: 4 fájl, +433/−22, mind az `allowed_paths`-on
(`recognition_metrics.dart`, `recognition_metrics_test.dart`,
`ci_manifest.json`, a brief §10.8). Az `allowed_paths` **nem tágult**.

```
python3 tools/scope-audit.py --repo … --brief … --base 2f56635f
→ Legacy scope audit OK (2f56635f940f..97ad9b7f31f1, 9 changed path(s),
  1 generated/ignored)
```

(A `1 generated/ignored` a jelen review-fájl — állandó, kód szintű mentesség,
`tools/ai_router/security.py::GENERATED_IGNORED_PREFIXES`.)

### 5.1 Gate-újrafuttatás FRISS izolált klónban (`/tmp/review2-e14-r08`)

```
    format                                                     zöld
    analyze                                                    zöld
    test …/recognition_split_test.dart                         zöld
    test …/recognition_metrics_test.dart                       zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
MINDEN GATE ZÖLD.   GATE_EXIT=0
```

### 5.2 Leletenkénti zárás

| Lelet | Állás | Mi zárja, és mi fogta volna pirosra |
|---|---|---|
| **MAJOR-1** | ✅ zárva | A `directionDefinition` és a `chordMacroDefinition` most a TÉNYLEGES szabályt mondja: „true positives come only from time-matched … pairs, but its false positives and false negatives are counted over the FULL … populations … a strum missed or falsely detected in time (never time-matched at all) **still enters this metric**". Két új cella (`recognition_metrics_test.dart:431-494`) a SZÁMOT és a SZÖVEGET **együtt** méri: nulla párosítás mellett `down.falseNegatives == 1`, `directionF1.value == 0.0`, és a definíció `isNot(contains('does not enter this metric'))` + `contains('never time-matched at all')` + a nevező `contains('not restricted to the time-matched set')`. A régi, hamis szöveg visszaállítása ezt a cellát PIROSRA viszi — pontosan ez hiányzott az 1. fordulóban. |
| **MAJOR-2** | ✅ zárva | Új csoport (`:495-630`): (a) a **commitolt** `ci_manifest.json` beolvasása és **kétszeri** futtatása `RecognitionEvaluationRunner.runFromJsonString`-gel, bájtazonos JSON-elvárással — az acceptance 6. pontja immár a VALÓDI futtatási úton mér, nem kézzel épített reporton; (b) mind a négy `SplitStrategy` a **fixture-ből parszolt** eseteken, `evalIdsAcrossFolds` uniója = a fixture eset-halmaza és „minden eset pontosan egyszer" — az acceptance 1. pontja „a fixture-ön"; (c) három tipizált parszer-elutasítás (ismeretlen kulcs, rossz `schemaVersion`, `direction` nélküli strum). A fixture harmadik esettel bővült, hogy a fold-mérés ne legyen triviális. A runner és a fixture így nem kerül gépi mérce nélkül a `main`-re. |
| **MINOR-1** | ✅ zárva | A `RecognitionExpectedEvent`/`RecognitionDetectedEvent` konstruktora most kikényszeríti a kind-invariánst (`strum → direction`, `chord → chordLabel`), az `E14-R07` `AnnotationEvent` precedense szerint; három új cella méri (`:631-690`), köztük az „onset sosem követel direction/chordLabel" negatív eset. |
| NOTE-1/2/3 | nyitva marad, nem blokkol | Az identitás-halmaz (`correctAccepted`), az onset+strum átfedés és a §10.2 scope-szűkítés dokumentált; egyik sem hibás viselkedés a szállított úton. |

### 5.3 Amit a 2. fordulóban külön ellenőriztem

- A javító kör **nem változtatta meg egyetlen metrika SZÁMÁT sem** — a §10.4
  kézi levezetés értékei (`onset25 1/3`, `onset50 2/3`, `onset100 5/6`,
  `anyStrum 0.75`, `directionMacro 8/15`, `ECE 0.37`, `Brier 0.2025`,
  `coverage 10/11`, `falseVisible 2.5`) változatlanul állnak a
  `recognition_metrics_test.dart:166-305` literál-celláiban, és a gate zöld.
  A javítás a *definíción* és a *mércén* történt, nem a mért értéken.
- A fixture bővítése (3. eset) nem billentette meg a kézzel levezetett
  értékeket, mert azok a teszt saját `_fixtureCase()`-én állnak, nem a
  fájlon — a zöld célzott kapu ezt igazolja.
- Az `architecture` lépés zöld: a kereszt-feature import tilalma (ADR 0509
  D8 / acceptance 10) a javító kör után is áll.

## 6. Merge-feltétel (végleges)

Nyitott BLOCKER/MAJOR/MINOR nincs. Hátra: a `full-gate.yml` **és** a
`router-ci.yml` `success` a merge SHA-n (ADR 0086 §2, exact-SHA), majd
squash-merge a zöld kapun.
