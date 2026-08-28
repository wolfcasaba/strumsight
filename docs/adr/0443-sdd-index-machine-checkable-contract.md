# ADR 0443 — Az SDD index és a dependency graph gépileg ellenőrzött szerződése

- **Státusz:** Elfogadva (E12-R02 pre-flight, 2026-08-28)
- **Kör:** `E12-R02` — SDD index és dependency graph
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Epic / fejezet:** [Chapter 12 — Release Roadmap, Sprint Planning & Final
  Integration](../sdd/12-release-roadmap-final-integration.md) Kör 2
- **Az ADR-t az orchestrátor (Claude Opus 5) írta a pre-flightban**, a
  [`docs/rounds/e12-r02-sdd-index-and-dependency-graph.md`](../rounds/e12-r02-sdd-index-and-dependency-graph.md)
  brief §5 kötött döntéseinek normatív forrásaként.

## Kontextus — a MÉRT hibaosztály

A `docs/sdd/00-index.md` a program egyetlen belépési pontja: ebből dől el, melyik
fejezet melyik fájlban van, hány kört tartalmaz, és mi a végrehajtási sorrend.
Ma ez **kizárólag emberi olvasásra** épül, és a pre-flightban mérve **szét is
csúszott** a fejezet-fájloktól:

```
$ for f in docs/sdd/*.md; do echo "$f $(grep -cE '^#{1,2} Kör [0-9]+' "$f")"; done
docs/sdd/12-release-roadmap-final-integration.md 36     # az index 42-t ír
docs/sdd/14-chapter-14-recognition-ui-recovery.md 42     # az index 42-t ír, EGYEZIK
```

A drift ma **prózai mentesítéssel** van kezelve (`00-index.md:30`: „végrehajtáskor
a fájl tartalma az irányadó"). Ez pontosan az a hibaosztály, amit a program
máshol már gépi őrre cserélt — vö. [ADR 0052](0052-ci-green-gate.md) zöld kapu és
a `tool/check_architecture.dart` + `test/tooling/architecture_allowlist_guard_test.dart`
pár: **a prózai mentesítés nem mérce**, mert nem tud pirosra váltani.

A drift nem elméleti kockázat: az E12 sáv 36 körét a queue a fejezet-fájl
kör-fejlécei alapján osztotta ki, miközben az index 42-t hirdetett — a hat kör
különbség egy sáv-tervezésben mért, nem levezetett hiba lett volna.

## Döntés

### D1 — A körszám FORRÁSA a fejezet-fájl; az index csak tükrözi

Az ellenőrző a fejezet-fájlból **SZÁMOLJA** a kör-fejléceket, és az index tábla
körszám-oszlopát ehhez a mért értékhez méri. Az irány kötött és nem fordítható
meg.

**NEM elfogadható gyengítés:** az index számának „hivatalossá" tétele és a
fájl-mérés elhagyása — akár azzal az indoklással, hogy egy fejezet fejlécei nem
egységesek. A pre-flightban mérve a Chapter 1–13 a `# Kör N`, a Chapter 14 a
`## Kör N` alakot használja: az ellenőrzőnek **MINDKETTŐT** kezelnie kell, mert
egyetlen alak támogatása némán nulla kört mérne a Chapter 14-re, és a hiba
pontosan úgy nézne ki, mint egy „helyes" mérés.

### D2 — A dependency graph körmentessége gépi állítás, nem ábra

A `docs/sdd/dependency-graph.yaml` az **egyetlen forrás** a fejezetek közti
függőségekre; a `00-index.md` „Függőségi kép" ASCII-blokkja ettől kezdve
**illusztráció**, nem szerződés. A körmentességet a checker méri, és a mérést egy
szándékosan ciklikus fixture váltja pirosra.

**NEM elfogadható gyengítés:** a körmentesség „szemre ellenőrzött" jelzése teszt
nélkül, vagy a ciklus-detektálás elhagyása azzal, hogy a csomópontok léte
ellenőrzött.

### D3 — A manifest olvasása SAJÁT, szűkített parserrel történik, nem `package:yaml`-lel

**Mérve a pre-flightban:** a `yaml` csomag a `pubspec.lock`-ban
`dependency: transitive` (`pubspec.lock:1261-1264`), a `pubspec.yaml`-ben
**nincs** deklarálva. A `package:flutter_lints/flutter.yaml`
(`analysis_options.yaml:10`) tartalmazza a `depend_on_referenced_packages`
szabályt, ezért egy `import 'package:yaml/yaml.dart'` a `flutter analyze`
lépését pirosra váltaná — a `pubspec.yaml` viszont **nincs a kör
`allowed_paths`-án**, tehát a dependency deklarálása H3 lenne.

A `dependency-graph.yaml` ezért egy **szándékosan szűkített YAML-részhalmaz**,
amit a checker sor-alapú, hibára beszédes parserrel olvas. Ez összhangban van a
brief §9 kockázatával (a Markdown-tábla parse-olása is szigorúan sor-alapú
legyen): ebben a körben sem általános Markdown-, sem általános YAML-parser
bevezetése nem indokolt. A szűkítés ára, hogy a manifest alakja kötött — ez a
**szerződés része**, nem hiányosság, és a checker hibaüzenetében ki kell mondva
lennie.

### D4 — A checker magja tesztelhető, gyökér-paraméteres API

A `tool/check_sdd_index.dart` nem merítheti ki magát egy `main()`-ben, ami
beégetett `docs/sdd/` útvonalon dolgozik: a brief A1/A2/A4 cellái **hibás
bemenetekre** mérnek (duplikált fejezet, nem létező hivatkozás, ciklikus graph),
amiket a repó valódi tartalmán nem lehet előállítani. A követett minta a repó
saját párja: a `test/tooling/architecture_allowlist_guard_test.dart` relatív
importtal (`../../tool/check_architecture.dart`) éri el a tool top-level
szimbólumait.

A checker ezért **top-level, gyökér- vagy tartalom-paraméteres** függvényeket
exportál, a `main()` pedig csak ezek vékony, `exitCode`-ot állító burkolója.

### D5 — Az ellenőrző ebben a körben NEM kerül a gate-be

A `tools/round-gate.sh` `architecture` lépése ma a `check_architecture.dart`-ot
futtatja. A `check_sdd_index.dart` gate-sorba emelése az [ADR 0052](0052-ci-green-gate.md)
hatálya alá tartozó, külön döntés — ebben a körben a `tools/**` **tilos zóna**.
A gépi mércét a körben a `test/tooling/sdd_index_guard_test.dart` adja, ami a
teljes CI-suite része, tehát a zöld kapu így is méri.

### D6 — A hivatkozás-ellenőrzés EGYIRÁNYÚ

A checker azt méri, hogy **minden index-hivatkozás létező fájlra mutat**. A
fordított irányt (minden `docs/sdd/` fájl legyen hivatkozva) **nem** követeli
meg: a pre-flightban mérve nyolc `epic-NN-completion-report.md` létezik, az index
négyet linkel (01, 02, 03, 06). A hiányzó négy link pótlása tartalmi döntés a
zárójelentések státuszáról, nem index-konzisztencia — külön kör tárgya.

## Következmények

- Az „aktuális fejezet / következő kör" kérdés emberi olvasás nélkül is
  eldönthető lesz, és a válasz **mérve** igaz, nem hitelezve.
- A `00-index.md` Chapter 12 sorának `42` értéke a mért `36`-ra javul; a többi
  tizenhárom sor a pre-flightban mérve **már egyezik**, tehát ez a kör egyetlen
  szám-javítást hoz, nem tömeges átírást.
- Egy fejezet-fájl kör-fejlécének jövőbeli hozzáadása/törlése ettől kezdve
  **pirosra váltja a suitet**, amíg az index nem követi — a drift a keletkezése
  körében derül ki, nem hat sávval később.
- A `docs/sdd/01-…14-…` fejezet-fájlok TARTALMA változatlan marad: az ellenőrző
  hozzájuk csak olvasóként nyúl.

## Alternatívák, amiket elvetettünk

| Alternatíva | Miért nem |
|---|---|
| A prózai footnote megtartása („a fájl tartalma az irányadó") | Nem tud pirosra váltani; ez a MÉRT jelenlegi állapot, ami a driftet elfedte |
| `package:yaml` a manifesthez | Transitive dependency; `depend_on_referenced_packages` → piros `flutter analyze`; a `pubspec.yaml` az `allowed_paths`-on kívül (H3) |
| JSON manifest YAML helyett | Az SDD Ch12 Kör 2 „Fő érintett fájlok" blokkja `dependency-graph.yaml`-t nevez meg; a formátumváltás fejezet-szerződést írna felül |
| A checker azonnali gate-be emelése | ADR 0052 hatálya; a `tools/**` a kör tilos zónája (D5) |
| Az index számának forrássá tétele | Az index a származtatott adat; a fejezet-fájl a forrás (D1) |

## Hivatkozások

- [ADR 0052](0052-ci-green-gate.md) — a zöld kapu, aminek a gate-sor módosítása
  a hatálya alá tartozik (D5)
- [`docs/sdd/12-release-roadmap-final-integration.md`](../sdd/12-release-roadmap-final-integration.md) Kör 2
- [`docs/rounds/e12-r02-sdd-index-and-dependency-graph.md`](../rounds/e12-r02-sdd-index-and-dependency-graph.md)
- Minta-pár: `tool/check_architecture.dart` (850 sor) +
  `test/tooling/architecture_allowlist_guard_test.dart`
