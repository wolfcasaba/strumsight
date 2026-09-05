# E14-R18 — Review (Claude, ADR 0055 · read-only)

- **Kör:** `E14-R18` — Streaming joint onset + direction prototípus
- **Ág:** `sonnet-impl/e14-r18-joint-streaming-prototype`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewed HEAD:** `f0a42aec` (pre-flight base: `ae1b0512`)
- **Dátum:** 2026-09-05

## 0. Gépi előfeltételek

| Ellenőrzés | Eredmény |
|---|---|
| Scope-audit (`scope_audit=ok`, base `ae1b0512`) | **OK** — 8 megváltozott útvonal, mind az `allowed_paths`-on |
| `dirty_files` a `done` jelzésnél | `1` — **kivizsgálva**: a jelzés utáni `git status --porcelain` a munkapéldányon **üres**; a jelzés pillanatában a záró commit még folyamatban volt |
| `gate_shape` | `VIOLATION` — **kivizsgálva, FALSE POSITIVE**, lásd §4/N2 |
| Gate újrafuttatva izolált `/tmp/review-e14-r18` klónban | **MINDEN ZÖLD** — format, analyze, `test/tooling/joint_io_schema_test.dart` **23/23**, architecture, secrets, l10n |
| Brief-lint (strict) a revideált briefen | nincs lelet (S12 + S15 a pre-flightban zárva) |
| Tilos zóna | érintetlen: `lib/**`, `assets/**`, `ml/` a `joint_prototype/`-on kívül, `docs/adr/**`, `.github/**`, `tools/**` |
| Repó-fába írt futási artefaktum (ADR 0517 D5) | **nulla** — súly, provenance és IO-dokumentum mind a `/tmp/e14r18-work` workdirben |

## 1. A döntő mérésem: a szállított szám REPRODUKÁLHATÓ

A review legerősebb próbája nem kódolvasás volt, hanem a mérés független
újrafuttatása az izolált klónban, a szállított súlyok ellen:

```
$ cd /tmp/review-e14-r18
$ /home/ubuntu/tf-venv/bin/python ml/joint_prototype/evaluate_prototype.py \
    --workdir /tmp/e14r18-work --output /tmp/review-repro.json
EXIT=0
```

A kapott dokumentum a szállítottal **bájtazonos** (`json.dumps(…, sort_keys=True)`
egyezés, **0 eltérő mező**), és a headline számok pontosan a §10.2-ben
jelentettek:

| Mező | Az én futásom | A jelentett érték |
|---|---|---|
| `prototypeOnsetF1At50ms` | 0,3824146481022315 | 0,3824146481022315 |
| `prototypeDirectionMacroF1` | 0,22403434521366614 | 0,22403434521366614 |
| `prototypeAlgorithmicLatencyMs` | 40,0 | 40,0 |
| `legacyOnsetF1At50ms` | 0,6739121651650438 | 0,6739121651650438 |
| `corpus.matchesBaselineManifest` | `true` (`4880face…5827`) | ugyanaz |
| `splitStrategy.leakageCheckPassed` | `true` | ugyanaz |

A `done` jelentés tehát nem bemondás: a szám a futtatási úton reprodukálódik.

## 2. Amit a kör helyesen old meg

- **A lookahead nem ígéret, hanem a train==serve geometria.** A
  `joint_window` (train_prototype.py:113) az `onset+lookahead` utáni audiót
  **nullázza**, és a kiértékelés UGYANEZT a függvényt hívja minden 10 ms-os
  keretre (`evaluate_prototype.py:150`). A `LOOKAHEAD_FRAMES = 4` konstans
  folyik a sémába és a reportba is (40 ms) — a modell tehát a mérésben sem lát
  több jövőt, mint amennyit a szerződés megenged. Ez az ADR 0517 D1
  tényleges teljesítése, nem szövegszintű megfelelés.
- **Az L630 lecke beépült.** A `direction_macro_f1` (evaluate_prototype.py:245)
  szállított definíciója szó szerint a **javított** E14-R08-as olvasat („a
  soha nem párosított esemény is a saját osztálya ellen számít"), és a kód
  pontosan ezt teszi: `false_negatives = total_expected - true_positives` a
  TELJES populáción, nem a párosított halmazon. A szám és a MONDAT egyezik —
  és az `A5` cellacsoport gépileg is együtt méri őket.
- **A két fail-closed kapu élesben működik, nem csak kódolvasásból.** A saját
  mérésem véletlenül ki is provokálta: a review-klónban hiányzó korpusszal a
  futás **nem** adott reportot, hanem a hash-eltérésre hivatkozva megállt
  (ADR 0517 D6). Ugyanez a leakage-ágra a §10.3-ban dokumentált, a valós
  `main()`-en át futtatott próbával.
- **A legacy sor becsületesen HIÁNYOSNAK van jelentve.** A táblában a legacy
  irány-cella `not-measured`, a felső korlát pedig kimondottan korlát, kiírt
  származtatással (`TP_direction ⊆ TP_onset`), plusz egy explicit mondat, hogy
  ez **nem** alapoz meg „a prototípus jobb" következtetést. Az `A6`
  cellacsoport ezt gépileg is őrzi (jelöletlen `bound` → elutasítva;
  `bound` `derivation` nélkül → séma-hiba).
- **A go/no-go a küszöbből SZÁMOL, nem a szerző jóindulatából.** Az `A4`
  csoport a literál 0,82 / 0,80 konstansokból újraszámolja a hármas cellát, és
  pirosra vált (a) exkluzív határra, (b) a dokumentumban meghamisított
  küszöbre, (c) a `decision`-nel nem egyező `comparison`-re. Az L637 csapdája
  ki van kerülve: a határértékek literálok.
- **A jelentés nem túlállít.** Sehol nem hivatkozik bootstrap CI-re,
  három-utas splitre vagy multi-seed sweepre — a §8 tételesen felsorolja, mit
  NEM mért (egy LOGO fold, nincs kalibráció, mohó párosítás), és a §10.5
  helyesen szűkíti a NO-GO hatályát: *ez a tanítási recept* cáfolt, nem a
  joint architektúra ötlete.

### 2.1 Saját valódi-sértés próbám (a §7.1-től FÜGGETLEN)

A szállított fixture `lookahead.lookaheadMs` mezőjét 40 → 50-re rontottam, majd
visszaállítottam:

```
$ flutter test test/tooling/joint_io_schema_test.dart      # rontott fixture
00:00 +21 -2: Some tests failed.
Failing tests: A1 (a szállított fixture validál) és A4
$ (fixture visszaállítva)
00:00 +23: All tests passed!
```

Megvizsgáltam, miért maradt zöld közben az `A3` („lookaheadMs == frames × hopMs"):
az `A3` a fixture MÁSOLATÁN dolgozik és a mezőt maga írja felül `999`-re, tehát a
szabályt méri, a szállított fixture-t pedig az `A1` őrzi ugyanazzal a
validátorral. A két cella együtt lefedi a szabályt ÉS a szállított artefaktumot
— nincs hézag.

## 3. Acceptance criteria — tételesen

| # | Kritérium | Bizonyíték | Ítélet |
|---|---|---|---|
| 1 | Egy paranccsal futtatható, a split nem beégetett | `evaluate_prototype.py` a foldot a provenance-ból veszi, de a felosztást `guitarist_of`-fal **függetlenül újraszámolja** és leakage-t ellenőriz (`recompute_split`, :114); semmilyen felvétel-lista nincs a kódban | ✅ (lásd N1) |
| 2 | Egy tábla, azonos korpusz-hash, legacy sorral | report §5 egyetlen táblája; a hash-egyezés gépi (`matchesBaselineManifest: true`), a legacy sor a manifestből, forrás-mezőkkel | ✅ |
| 3 | A lookahead száma a reportban ÉS a sémában | 4 keret / 40 ms mindkettőben, `A3` konzisztencia-cellával | ✅ |
| 4 | Ismeretlen `schemaVersion` → típusos hiba | `A2` három cellája + a §7.1 falszifikáció (PIROS→ZÖLD, idézett kimenettel) | ✅ |
| 5 | Alpha-küszöb hármas cella, inkluzív határ | `A4` öt cellája literál küszöbökből | ✅ |
| 6 | Leakage → hiba, nincs report | `assert_no_leakage` a valós `main()`-en át kipróbálva; `A7` a dokumentum-oldalon | ✅ |
| 7 | Definíció + `higherIsBetter` együtt mérve | `A5` három cellája (irány megfordítása → piros) | ✅ |
| 8 | Semmi a repó fája alá | `git status --porcelain` üres; minden artefaktum `/tmp/e14r18-work` | ✅ |

## 4. Leletek

**Nincs BLOCKER, MAJOR vagy MINOR lelet.** Négy NOTE:

- **N1 (NOTE, brief-hiba, az enyém).** A §6 AC1 szövege szerint a prototípus „a
  splitet a **manifestből** veszi". Ehhez a korpuszhoz nincs split-manifest a
  fában, és a §0.0 revízióm ezt a szót nem oldotta fel. Az implementer a
  kritérium tartalmát (nem beégetett, korpuszból származtatott, függetlenül
  újraszámolt és leakage-ellenőrzött split) teljesíti; a „manifest" szerepét a
  futás provenance JSON-je tölti be. Nem kifogás az implementer felé — a
  brief-szó pontatlansága, tanulságként rögzítve.
- **N2 (NOTE, infrastruktúra — NEM ebben a körben javítandó).** A jelzésfájl
  `gate_shape=VIOLATION`-t írt, holott a gate-et kétszer, csővezeték nélkül
  futtatták (`tools/round-gate.sh test/tooling/joint_io_schema_test.dart`). A
  `tools/mm-round.sh:381-383` mintája (`round-gate\.sh[^\n]*(\| *(tail|head)|&&)`)
  a log BÁRMELY sorára illeszkedik, így az első Bash-hívás
  `cat …/tools/round-gate.sh | head -60` alakja — a script **elolvasása** —
  is sértésnek minősül. A mérce fájlját ez a kör nem érintheti (ADR 0087 §4),
  ezért ez önjavító körnek szóló lelet.
- **N3 (NOTE).** Hiányzó korpusz esetén a `check_corpus_matches_baseline` az
  ÜRES bemenet hash-ét jelenti (`e3b0c442…b855`) és hash-eltérésként áll meg,
  nem „a korpusz hiányzik/üres" hibával. Fail-closed marad (helyes), de a
  diagnosztika félrevezető; a productizálás köre adjon külön, beszélő hibát.
- **N4 (NOTE).** A párosítás mohó, nem Kuhn-féle maximális (L269 / ADR 0509 D5)
  — a §8 kimondja. Iránya a prototípus KÁRÁRA torzít (a mohó párosítás nem
  maximalizálja a TP-t), tehát a NO-GO ítéletet nem gyengíti; a 0,3824 vs 0,82
  távolság mellett nem is fordíthatna rajta.

## 5. Merge-ítélet

**VÉGSŐ DÖNTÉS: APPROVED.**

A kör a mérési szerződését (ADR 0517 D1–D8) nemcsak leírja, hanem gépi őrökkel
tartja, a szállított szám pedig független futtatáson bájtazonosan
reprodukálódott. A NO-GO ítélet hatálya helyesen szűkített, és a report a
korlátait maga sorolja fel. Merge a zöld kapu (Full Gate + Router CI a merge
SHA-n) teljesülésekor.
