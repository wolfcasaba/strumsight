# E14-R15 review — Hard-negative taxonómia és SZŰKÍTETT false-visible-event metrika

- **Kör:** `E14-R15`, branch
  `sonnet-impl/e14-r15-hard-negative-corpus-and-false-visible-metric`
- **Reviewer:** Claude (Opus 5), orchestrátor-szék, **read-only** (a kód
  javítását javító kör végzi; a kör SAJÁT, még nem merge-elt ADR-jét és
  briefjét az orchestrátor módosítja — ADR 0087 §2)
- **Reviewelt HEAD:** `e180c0d2` (pre-flight alap: `d68af4f2`)
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Dátum:** 2026-09-05
- **Verdikt:** **APPROVED** — 0 BLOCKER, 0 MAJOR, 1 MINOR, 2 NOTE

## 0. Amit MÉRTEM (nem olvastam, hanem futtattam)

Minden mérés IZOLÁLT klónban (`/tmp/review-e14-r15`, a kör-branchről), nem a
közös munkafán.

| Mérés | Eredmény |
|---|---|
| `python3 tools/scope-audit.py --repo … --base d68af4f2` | `Legacy scope audit OK (13 changed path(s), 0 generated/ignored)` — a diff MINDEN fájlja az `allowed_paths`-on |
| Munkafa a `done` jelzéskor | tiszta (`git status --short` üres a `e180c0d2`-n); a jelzés `dirty_files=1` értéke a jelzésfájl saját írása — utána mérve nincs se módosított, se követetlen fájl |
| `tools/round-gate.sh <a brief §7 négyese>` a saját klónomban | **MINDEN GATE ZÖLD** (format, analyze, 4 célzott teszt, architecture, secrets, l10n) |
| Falszifikáció #1 — `d.accepted` szűrés kivéve | a **4. acceptance-cella PIROS** (`abstaining one of the three -> 1.0/min`), visszaállítva zöld |
| Falszifikáció #2 — `kind == strum` szűrés kivéve | az **5. (zárt partíció) ÉS a 6. (anti-alias) cella PIROS**, visszaállítva zöld |
| Próbateszt F — időben párosított, de ROSSZ IRÁNYÚ strum | `dir=1 agnostic=1` — a szállított leírás („matched with the wrong direction") igaz |
| Próbateszt G — helyes, elfogadott strum | `dir=0` — nem számol hamisat |
| Próbateszt H — `durationMs == 0` | `dirValue=null` (nem `0`) — ADR 0521 D3 teljesül |
| Próbateszt D — `categories` unmodifiable | `throwsUnsupportedError` — a doc-comment állítása igaz |
| Próbateszt A/B — hibás mezőérték a JSON-ban | **bare `ArgumentError`** (lásd MINOR-1) |

Az eldobható próbatesztek (`test/tmp_review_probe_test.dart`) a mérés után
törölve; a mutációk után a klón `git status --short`-ja üres.

## 1. Acceptance criteria — tételesen

| # | Kritérium | Bizonyíték | Állapot |
|---|---|---|---|
| 1 | taxonómia ≥ 10 kategória, inkluzív határ (9 / 10 / 11) | `negative_taxonomy_test.dart` hármas cellája; a küszöb `NegativeTaxonomy` konstruktorában (`negative_taxonomy.dart:100-106`), a szállított JSON 11 kategóriát ad | ✅ |
| 2 | ismeretlen kategória TÍPUSOS hiba, nem `other` | `NegativeTaxonomyErrorKind.unknownCategory` a `categoryById`-ban (`:126-135`) és a `parseSample` szegmens-ágán (`:337`); két cella méri; nincs `other` bucket a fában | ✅ |
| 3 | 3 hamis irány-esemény / 120 s → 1,5/perc | `recognition_metrics_test.dart` — `eventCount=3`, `durationMinutes=2.0`, `value=1.5` | ✅ |
| 4 | abstained esemény nem számít | ugyanott, `eventCount=2`, `value=1.0`; a mutációs próbám pirosra vitte | ✅ |
| 5 | zárt partíció (`direction + chord == agnosztikus`) | cella `mixedKindCase(includeFalseOnset: false)`-on, `4 == 4` | ✅ |
| 6 | anti-alias: onsettel az összeg SZIGORÚAN kisebb, és `direction.value != agnosztikus.value` | cella `includeFalseOnset: true`-n (`4 < 5`, `2.0 != 5.0`); a `kind`-mutáció pirosra viszi | ✅ |
| 7 | nevezhetőség: extractor-kulcsok + mindhárom renderelés azonos érték | `recognition_release_gate_test.dart` két új cellája (kulcs-lét + küszöb-kiértékelés `higherIsBetter=false`-szal), `recognition_report_renderer_test.dart` JSON/MD/HTML egyezés-cellája; a renderer forrása változatlan (generikus `_summarize`) | ✅ |
| 8 | a szállított küszöbfájl VÁLTOZATLAN | `git diff d68af4f2..e180c0d2 -- evaluation/recognition/recognition_release_gate.json` üres; a bejegyzés-listát pinnelő cella érintetlen és zöld | ✅ |

**Az ADR 0521 kötött döntései:** D1 (partíció, nem második definíció) —
a két ráta a `computeRecognitionMetrics` UGYANAZON menetében, ugyanabból a
`correctAccepted`/`acceptedDetections` párból készül
(`recognition_metrics.dart:764-816`); **nincs** új metrika-fájl a fában. D2
(`accepted` szűrés), D3 (`null` üres nevezőn), D4 (zárt partíció), D5
(extractor + saját `higherIsBetter`), D6 (küszöbfájl változatlan), D7
(taxonómia + típusos hiba), D8 (nincs audio a diffben — a `git diff --stat`
csak `.md`/`.json`/`.dart` fájlokat sorol), D9 (dashboard-lista) mind
teljesül.

## MINOR-1 — A parser doc-commentje „minden elutasítás típusos"-t állít, de a mezőértékek hibáin bare `ArgumentError` szökik ki (L630 osztály)

**Mit találtam.** A `NegativeTaxonomyParser` szállított doc-commentje
(`negative_taxonomy.dart:215-218`) ezt mondja:

> „Every rejection surfaces as a typed `NegativeTaxonomyException` naming its
> `NegativeTaxonomyErrorKind` and, where applicable, the offending JSON path —
> never a bare `FormatException` or `TypeError`."

A JSON-ból parse-olt értékek tartalmi ellenőrzését viszont a
`NegativeTaxonomyCategory` (`:65-78`) és a `NegativeTaxonomySegment`
(`:157-173`) konstruktora végzi, **bare `ArgumentError`-ral**. Mérve, a
szállított alakú JSON-nal:

```
PROBE_A type=ArgumentError value=Invalid argument (id): must not be empty: ""
PROBE_B type=ArgumentError value=Invalid argument (endMs): must be >= startMs (500): 100
```

Ez pontosan az `L630` hibaosztály (E14-R08 MAJOR-1): a SZÁLLÍTOTT mondat
többet állít, mint amit a kód tesz, és minden zöld cella átengedi — a
`negative_taxonomy_test.dart` egyetlen cellája sem próbál üres mezőértéket
vagy fordított intervallumot a **parse** úton.

**Miért MINOR és nem MAJOR.** (a) A kör acceptance-szerződése (2. pont, ADR
0521 D7) kifejezetten az **ismeretlen kategóriára** ír elő típusos hibát, és
az hibátlanul típusos; (b) az érintett út a fixture-parse, nincs felhasználói
felülete; (c) a bare hiba nem hamis eredményt ad, hanem hangosan elszáll —
a `L630` kárt (csendben hamis szám) itt nem okozza.

**Javasolt irány (NEM kész patch).** Vagy a konstruktor-ellenőrzések is
`NegativeTaxonomyException`-t dobjanak (`malformedValue` vagy egy új
`invalidValue` kind), vagy a doc-comment mondja ki pontosan, hogy a
mező-alakra `NegativeTaxonomyException`, a mező-ÉRTÉK invariánsaira
(`nem üres`, `endMs >= startMs`) `ArgumentError` jár — és legyen rá cella,
ami ezt pinneli. Az első a jobb, mert a hívó ma két hibaosztályt kell
elkapjon egy fájl beolvasásához.

## NOTE-1 — A dashboard záró mondata a lezárás után félrevezetővé vált

`docs/eval/recognition-dashboard.md` a „still … deliberately absent" lista
után változatlanul ezt viszi tovább:

> „Mechanising any of these requires extending the E14-R08 harness
> (`recognition_metrics.dart`) with a genuinely scoped metric — out of this
> round's allowed-files list."

A „this round" itt még az E14-R09-re utal, miközben ugyanez a dokumentum most
már egy külön szakaszban dokumentálja, hogy az E14-R15 pontosan ezt tette meg
kettőre. A mondat nem hamis, de körfüggő mutatóval él egy merge-elt
dokumentumban. Nem blokkol.

## NOTE-2 — A taxonómia tartalma design-döntés, nem mért érték

A 11 kategória, a leírások és a fixture 11 szegmense terv, nem mérés — az
implementer ezt a §10-ben becsületesen kimondta. A gépi szerződés (≥10,
egyediség, típusos ismeretlen-hiba) áll; a lista bővítése/finomítása
későbbi körben szabad, a `docs/eval/recognition-hard-negatives.md` táblájával
együtt.

## 2. Architektúra és termékhatárok (AGENTS.md §5–§6)

- `negative_taxonomy.dart` **`dart:io`-mentes** (csak `dart:convert`), a
  fájlbeolvasás a hívóé — a domain-réteg tiszta marad; a `public.dart` export
  additív.
- Nincs hálózat, mikrofon, engedély, secret vagy felhasználói adat a diffben;
  a `secrets` gate zöld (4419 fájl, 0 lelet).
- Nincs bináris/audio artefaktum: a 13 fájl mind `.dart`/`.json`/`.md`
  (ADR 0249 / ADR 0521 D8).
- A `recognition_release_gate.json` és a `recognition_split.dart` érintetlen;
  a tilos zóna nem sérült.

## 3. Verdikt

**APPROVED.** A kör azt építette meg, amit az ADR 0521 előír: a merge-elt
`falseVisibleEventsPerMinute` **partícióját**, nem egy második metrika-fát —
és ezt a két mutációs próbám függetlenül is bizonyította. A MINOR-1 nem
blokkolja a merge-et; a következő kör asztalára kerül a HANDOFF §6-on
keresztül.
