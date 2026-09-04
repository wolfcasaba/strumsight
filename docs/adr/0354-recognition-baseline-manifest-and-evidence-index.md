# ADR 0354 — A felismerési baseline egyetlen géppel olvasható manifest, és egyetlen szám sem áll forrás és parancs nélkül

- **Státusz:** Elfogadva
- **Kör:** `E14-R02` (Chapter 14 — Recognition Accuracy & Useful UI Recovery, Kör 2)
- **Dátum:** 2026-09-04
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:** [ADR 0249](0249-analysis-evaluation-dataset-governance.md)
  (analysis evaluation dataset governance — a követett minta),
  [ADR 0271](0271-recognition-recovery-program.md)
  (előbb a mérés, aztán a modellcsere),
  [ADR 0136](0136-tutor-knowledge-retrieval.md)
  (determinisztikus offline artefaktum + hash-lezárás),
  `docs/eval/recognition-release-guard.md` (E14-R01 aktivációs szerződés)

## Kontextus — a pre-flight MÉRT tényei (2026-09-04, `main @ d26f1958`)

A felismerési mérések ma **egy prózai reportban** élnek
(`docs/eval/real-audio-dsp-baseline.md`, E99-R04, javítva E99-R05-ben), a
belőlük következő aktivációs szerződés viszont **egy másik fájlban**
(`docs/eval/recognition-release-guard.md`, E14-R01). A release guard
`Baseline manifest` sora egy olyan artefaktumra hivatkozik —
`evaluation/recognition/baseline_manifest.json` —, ami **ma nem létezik**
(`ls -d evaluation/recognition` → nincs ilyen könyvtár). A guard tehát olyan
bizonyítékot követel az aktiváláshoz, aminek nincs formája; ez a kör adja meg.

A mérés, amiből a manifest tartalma jön, a MAI fán ellenőrizve:

- **Korpusz elérhető:** `ml/data/klangio`, **82** `*_phone.wav`, SHA-256
  `4880faceab27217640701f1b93db477606d5fb3aa2c4434574040b6590315827`,
  11 767 esemény, 0 kihagyott felvétel.
- **Akkord:** 7 892 / 11 767 = **67,069%**; G-major többségi baseline
  2 216 / 11 767 = 18,832%; moll részhalmaz 185 / 222 = 83,333%.
- **Onset:** három tűrésre (25/50/100 ms) precision/recall/F1.
- **BPM: VISSZAVONT** — a GOV-06b javítás kimondja, hogy a `.strums` események
  pengetések, nem ütem-annotációk; a 45,067 BPM „hiba" pengetés-sűrűség-eltérés
  volt, nem tempóminőség.
- **Nem mért:** `direction`, `noChord`, `latency`, `calibration` — ezekre
  `grep -rn "latency|direction|noChord" docs/eval/*.md` **nulla** találatot ad.
- **A mért konfiguráció NEM használt ML-modellt:** a report a változatlan
  `const ClipAnalyzer()`-t futtatta, aminek `strumRefiner` alapértéke `null`
  (`lib/features/analyze/engine/clip_analyzer.dart:36`) — egyetlen
  `assets/ml/*.bin` súly sem vett részt benne.
- **Nincs JSON-Schema könyvtár:** a `pubspec.yaml` nem deklarál ilyet, és a
  meglévő minta sem használ: az `evaluation/analysis/manifest_schema.json`
  szerződését az `evaluation_manifest_parser.dart` kézzel kényszeríti ki.

## Döntés

### D1 — A manifest sosem hordoz nyers audiót

Az `evaluation/recognition/baseline_manifest.json` kizárólag **azonosítót és
összegzést** tartalmaz: `corpusId`, `corpusSha256`, `recordingCount`,
`eventCount`. Egyetlen bájt hangminta sem kerül a repóba — ugyanaz a határ,
amit az ADR 0249 §Döntés 1 húzott meg az analysis-korpuszra, és amit ott a
`analysis_evaluation_regression_test.dart` `git diff --stat` őre mér.

*Miért ez a helyes vonal:* a korpusz 423 MB licencelt, telefonos felvétel. Ha a
bizonyíték hordozná az adatot, minden későbbi kör kényszerűen választana a
„reprodukálható" és a „megosztható" között. Hash-szel mindkettő megmarad.

### D2 — Minden szám mellett ott a FORRÁS és a PARANCS, mező-szinten

Metrikánként kötelező a `value`, `n`, `sourceFile`, `command` négyes. **Egy
közös „lásd a report parancsát" lábjegyzet nem elfogadható helyettesítés.**

*Miért nem elég a lábjegyzet:* pontosan az volt a mért baj, hogy a számokhoz nem
tartozott visszakereshető futtatás. Egy dokumentum-szintű lábjegyzet akkor is
igaznak látszik, amikor egy KÉSŐBBI kör hozzáír egy metrikát, amit soha nem az a
parancs termelt. A mező-szintű `command` ezt a csendes drift-et zárja ki.

### D3 — A „nem mértük" ELSŐOSZTÁLYÚ állapot, nem hiányzó mező

Minden metrika-blokk `status` mezőt hordoz, és a séma `oneOf`-fal pontosan két
alakot enged:

| `status` | Kötelező | Tilos |
|---|---|---|
| `"measured"` | `metrics`, benne MINDEN metrikára a D2 négyese | — |
| `"not-measured"` | nem üres `notMeasuredReason` | `metrics` |

A félig kitöltött blokk (`"measured"` üres `metrics`-szel, vagy
`"not-measured"` indoklás nélkül) **hiba**, nem tolerálható köztes állapot.

*Miért ez a fontos:* a hiányzó mérés és a rossz mérés két különböző dolog, és
csak az egyikük javítható méréssel. Ha a `latency` blokk egyszerűen hiányozna,
egy későbbi olvasó nem tudja megkülönböztetni a „még nem mértük"-et az
„elfelejtettük"-től. Ez ugyanaz a döntés, mint az ADR 0261 §2 `unknown`
állapota: az ismeretlen nem alacsony érték.

### D4 — A visszavont állítás VISSZAVONT marad, gépileg is

A BPM-blokk `retracted: true` + `retractedReason` mezőt kap, és az indexben
kifejezetten **VISSZAVONT** jelöléssel jelenik meg. A visszavont szám csendes
törlése tilos.

*Miért:* a tévedés nyoma bizonyíték, nem szemét. A 45,067 BPM szám egyszer már
bekerült egy jelentésbe; ha most nyomtalanul eltűnik, a következő olvasó
ugyanabba a hibába eshet — és nem lesz mihez képest tudnia, hogy már megjártuk.

### D5 — Bitre azonos újrafuttatás, `DateTime.now()` nélkül

A generátor determinisztikus: kulcsok ábécésorrendben, listák explicit rendezési
kulccsal, lebegőpontos értékek fix formátummal (`toStringAsFixed(3)`), és az
időbélyeg **kizárólag a manifestből** jön — a generátor nem hív órát.

*Miért a fix formátum is:* a nyers `toString()` platformfüggő tizedesjegyeket
adhat, tehát a diff nem a tartalomtól, hanem a futtató géptől függene. Az
L109 mérése szerint a determinizmusnak több, egymást fedő mechanizmusa lehet,
és az egyszeres mutáció nem feltétlenül fogja meg — ezért a §7.1 falszifikációs
cella a rendezés kikapcsolásával MÉRI a pirosat, nem feltételezi.

### D6 — Fail-closed: a generátor nem ír „n/a" sort

Ha egy `"measured"` blokk metrikájára `n == 0`, vagy hiányzik a `sourceFile` /
`command`, a `--check` **nem nulla** kilépési kóddal áll meg. Nincs „n/a"
kiírás, nincs kihagyott sor.

*Miért:* az „n/a" sor a táblázatban ugyanúgy néz ki, mint egy mérés — a
riportban a hiány nem lehet csendesebb, mint az adat. Ugyanez a hibaosztály,
amit az L566 mért: a fail-open parszer számára ami nem illeszkedik a mintára,
az nem hibás, hanem NEM LÉTEZIK.

### D7 — Üres `models` lista csak INDOKLÁSSAL

A `models` mező a mért konfiguráció ML-súlyait sorolja fel. A mai baseline
`const ClipAnalyzer()`-je egyet sem használt, ezért a lista **üres** — és
ilyenkor a nem üres `modelsRationale` **kötelező**, a `--check` fail-closed
méri.

*Miért nem elég az üres lista magában:* a `recognition-release-guard.md` „model
SHA-256"-ot követel. Üres lista indoklás nélkül ugyanúgy olvasható
„nincs modell"-ként és „elfelejtettük kitölteni"-ként. Az ellenkező irány még
rosszabb: a repóban lévő `chord_crnn.bin` hash-ének „a teljesség kedvéért" való
bemásolása **hamis állítás** lenne arról, mi futott a mérés alatt.

### D8 — A séma-validálás kézzel írt Dart, nem új függőség

A `--check` beolvassa a sémafájlt, és a `type` / `required` /
`additionalProperties: false` / `const` / `enum` / `oneOf` szabályokat maga
érvényesíti — az `evaluation_manifest_parser.dart` és a
`tool/check_fixture_manifest.dart` bevett mintája szerint. Séma-könyvtár
felvétele `pubspec.yaml`-módosítást igényelne, ami ennek a körnek tilos zónája.

*Miért ez az ára megéri:* a validálás így ugyanabban a nyelvben és ugyanabban a
kapuban fut, mint a többi tooling-őr, külső verziófüggés nélkül — cserébe a
séma csak azokat a konstrukciókat használhatja, amiket a checker tényleg ismer.
A séma és a checker együtt egy szerződés; a le nem fedett séma-kulcs
**hallgatólagosan érvénytelen**, ezért a checker ismeretlen séma-kulcsra is
fail-closed.

### D9 — Az index HIVATKOZIK, nem másol

A `docs/eval/recognition-baseline-index.md` a
`docs/eval/real-audio-dsp-baseline.md`-re és a
`recognition-release-guard.md`-re **linkel**; a számokat a manifestből
rendereli, a prózát nem duplikálja.

*Miért:* két helyen tartott ugyanaz a szám a legolcsóbb drift-forrás — és a
report **történeti tény** (E99-R04/R05 mérése), amit ez a kör nem írhat át.

## Következmények

- Az E14-R01 release guard `Baseline manifest` sora ettől a körtől kezdve
  **teljesíthető**: van fájl, van séma, van gépi ellenőrzés.
- A későbbi Chapter 14 körök (grouped evaluation, A/B, dashboard) ehhez a
  manifesthez mérnek, nem prózát olvasnak újra.
- A `not-measured` blokkok **nyitott munka listája**: a `direction`, `noChord`,
  `latency`, `calibration` mind egy-egy későbbi kör tárgya, és a manifest
  megmutatja, melyik hiányzik.
- Ez a kör **nem mér újra és nem hangol semmit** — új DSP/ML konstans,
  küszöbváltás, modellcsere ebben a körben tilos (AGENTS.md §9).
