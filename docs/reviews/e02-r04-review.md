# E02-R04 review — Practice catalog és beépített gyakorlatok

- **Kör:** E02-R04 (`docs/rounds/e02-r04-practice-catalog.md`), ADR 0070
- **Implementer motor:** MiniMax M3 (`engine=minimax-m3`, [ADR 0069](../adr/0069-two-engine-implementer-pool.md))
- **Reviewer:** Claude (read-only; production kódot nem írt)
- **Diff:** `300b06e` — 7 fájl, +900 sor
- **Verdikt:** **CHANGES REQUESTED** — 0 BLOCKER · **3 MAJOR** · 1 MINOR · 3 NOTE

## 1. Független gate-újrafuttatás

A bemásolt kimenetet nem fogadtam el evidenciának (AGENTS.md §15.1). A négy
gate-parancsot magam futtattam újra a munkapéldányban, `tail` nélkül:

| Parancs | Eredmény |
|---|---|
| `dart format --set-exit-if-changed lib test` | `Formatted 487 files (0 changed)`, exit 0 |
| `flutter analyze lib/ test/` | `No issues found!` |
| `flutter test test/features/practice/` | **143/143 zöld** |
| `flutter test test/core/architecture_dependency_test.dart` | **12/12 zöld** |

Az implementer jelentése ezekkel egyezik. A §7 mind a négy sorát lefuttatta.

## 2. Scope-audit

`git diff --stat` + új fájlok vs. a brief §4 engedélyezett listája: **7/7 fájl a
listán**, tilos zóna érintetlen (`lib/l10n/**`, `docs/adr/**`, a többi
`domain/model/*.dart`, meglévő tesztek). `legacyLearnParity` bitre változatlan
(§6.10 teljesül).

## 3. MAJOR leletek

### MAJOR-1 — a katalógus `events` és `skillTags` listái MUTÁBILISAK

`PracticeDefinition` dokumentált szerződése (`practice_definition.dart:16-17`,
ADR 0068): *„[events] and [skillTags] must be immutable; pass const lists or
unmodifiable lists."* A katalógus növelhető lista-literálokat és
comprehension-eket ad át, `const` / `List.unmodifiable` nélkül.

**Bizonyítva**, nem feltételezés — ideiglenes review-próba a munkapéldányban
(futtatás után törölve):

```
PROBE events mutable: true, skillTags mutable: true
```

Bármelyik hívó `definition.events.add(...)`-szal megváltoztathatja a MEGOSZTOTT
katalógus-adatot minden további hívó számára. Az `all()` `List.unmodifiable`
burkolása csak a KÜLSŐ listát védi, az elemek belsejét nem.

**Javítás:** `_folkPatternEvents()` / `_alternatingChordEvents()` és minden
inline comprehension eredménye `List.unmodifiable(...)`-be csomagolva;
`skillTags:` mindenhol `const [...]`; a free-practice `events: const []`.

### MAJOR-2 — a fájl doc-commentje valótlant állít a `const`-ságról

`builtin_practice_catalog.dart:23-26`: *„every element is a `const
PracticeDefinition` constructed at build time"*. Ez **nem igaz**: egyetlen
definíció sem `const`-konstruált (a `for`-comprehension és a helper-hívás
kizárja a const kontextust). A dokumentáció így pont azt a garanciát ígéri,
amit a MAJOR-1 megcáfol — ez a magabiztosan hibás állítás osztálya, amire az
ADR 0069 külön figyelmeztet.

**Javítás:** a MAJOR-1 rendezése után a komment mondja azt, ami tényleg igaz
(build-time `final` adat + unmodifiable nézetek), vagy — ahol lehet — legyen
tényleg `const`.

### MAJOR-3 — a G↔D és Em↔C akkordváltás ÜTEMENKÉNT helyett ÜTÉSENKÉNT vált

A brief §5.4 tábla 4. és 5. sora: *„negyedek; **ütemenként** váltakozva `G` és
`D`"* — vagyis négy ütés G, majd négy ütés D. Az implementáció
(`_alternatingChordEvents`, `chord: index.isEven ? firstChord : secondChord`)
**minden ütésen** vált, és a saját kommentje ki is mondja: *„the chord toggles
on every beat"*.

60 BPM-en ütésenkénti akkordváltás nem kezdő gyakorlat, hanem egy lényegesen
nehezebb és zeneileg más feladat. **Egyetlen teszt sem pinneli ki a szerkezetet**,
ezért a gate zölden fut a hibás tartalommal — a `validate()` mindkét változatot
elfogadja.

**Javítás:** ütem-szintű váltás (`(index ~/ 4).isEven`), plusz egy teszt, ami
kipinneli az első nyolc esemény akkord-szekvenciáját mindkét gyakorlatnál.

## 4. MINOR

### MINOR-1 — fölösleges indirekció és per-hívás allokáció

`static final List<PracticeDefinition> _definitions = _builtinPracticeDefinitions;`
csak átnevezi a top-level listát. Az `all()` minden híváson új
`List.unmodifiable` burkolót allokál; egyetlen, egyszer felépített unmodifiable
lista elég lenne (a `byMode`/`byDifficulty` szűrése természetesen marad
per-hívás).

## 5. NOTE

- **NOTE-1 — köztes gate-szűkítés.** Kétszer futott
  `flutter analyze lib/features/practice/ test/features/practice/` a teljes fa
  helyett. Ez gyors visszacsatolásnak legitim, és a ZÁRÓ gate-sort az implementer
  pontosan lefuttatta — a brief §7 szövege viszont ezt „körbukásnak" minősíti.
  A megfogalmazást pontosítani kell (köztes ellenőrzés szűkíthető, a záró nem).
- **NOTE-2 — a gate-kimenetek `tail`-en át kerültek a jelentésbe**, tehát
  csonkoltak. Ezért futtattam újra mindent; a brief írja elő, hogy a záró
  gate-parancsok csővezeték nélkül fussanak.
- **NOTE-3 — task-lista overhead.** 9 `TaskCreate` + 15 `TaskUpdate` hívás a
  ~75 érdemi hívás mellett, miközben a brief §8 már megadta a sorrendet.

## 6. Amit kifejezetten jól csinált (mérve a futás stream-json logjából)

- **0 hibás tool-hívás** ~75 hívásból, és **egyetlen fájlt sem olvasott kétszer**.
- Az olvasási sorrend a brief §2.1-et követte, majd magától elolvasta MINDKÉT
  gépi őrt (`domain_purity_test.dart`, `architecture_dependency_test.dart`) és a
  meglévő teszteket, mielőtt egy sort is írt.
- TDD-sorrend tartva (§8): előbb a `scoring_profile_test.dart` egyedül.
- A `rhythmOnly` eseményeken helyesen hordozott `direction`-t (a brief §2.4-ben
  mért `eventScorableMissing` szabály miatt) — ezt nem kellett külön kérni.
- A `data`-réteg tisztaság-őre (§6.7) valóban forrásolvasó teszt lett.
- Teljes idő: **~7 perc**, a kör-jelzés hibátlan.

## 7. Javító kör — lezárva (`e7ff69c`)

Javító brief: `docs/rounds/e02-r04-fix.md`, ugyanaz az implementer motor.
Mindhárom MAJOR és a MINOR zárva, 2 fájl, +145/−49 sor.

**A javításokat nem bemondásra fogadtam el**, hanem ugyanazzal az eldobható
review-próbával mértem újra (futtatás után törölve):

```
PROBE mutable: []
PROBE gToD  first 8 chords: [G, G, G, G, D, D, D, D]  (events: 32)
PROBE emToC first 8 chords: [Em, Em, Em, Em, C, C, C, C]
```

Az implementer a MAJOR-1-hez valódi RED → GREEN evidenciát adott: az új
per-definition immutability tesztek először a RÉGI kódon futottak, pirosan
(`Expected: throws UnsupportedError / Actual: returned <null>`), és csak utána
jött a javítás.

Ismételt független gate-sor, `tail` nélkül: `format` 0 changed · `analyze lib/
test/` tiszta · **147/147** practice teszt · **12/12** architecture teszt.

**Verdikt a javítás után: APPROVED** — a merge-bar az ADR 0052 zöld kapuja
(CI-oldali teljes suite + property gate + APK).

## 8. Munkamódszer-tanulságok (bekerültek az AGENTS.md §15.6-ba)

A kör stream-json logját a `tools/mm-trace.py` elemezte. A négy új
brief-szabály hatása a javító körben azonnal mérhető volt:

| Megfigyelés az alapkörben | Új szabály | Hatás a javító körben |
|---|---|---|
| 9 `TaskCreate` + 15 `TaskUpdate` a ~75 érdemi hívás mellett | „a brief a terved, ne készíts task-listát" | **0** task-hívás |
| záró gate `2>&1 \| tail -25`-tel, csonkolt evidencia | „a záró gate-eket csővezeték és `tail` nélkül" | mind a 4 záró gate csupaszon futott |
| köztes `analyze` a nyúlt alfára szűkítve, miközben a brief ezt „körbukásnak" mondta | „köztes szűkíthető, a záró nem" | ugyanez a viselkedés, de már szabályosan |
| valótlan `const` állítás a doc-commentben | „ne állíts olyat, amit nem ellenőriztél" | a komment a tényleges garanciákat sorolja |
