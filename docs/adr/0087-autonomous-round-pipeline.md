# ADR 0087 — Autonóm kör-pipeline: körönként friss session, kötött megállási szerződéssel

**Státusz:** elfogadva (GOV-02, 2026-07-31, user-döntés).
Épít az [ADR 0052](0052-ci-apk-automerge-session-per-round.md) (zöld kapu, egy session = egy kör),
[ADR 0053](0053-ci-full-test-suite.md) (a teljes suite a CI-ban),
[ADR 0055](0055-agent-role-protocol.md) (szerep-protokoll),
[ADR 0069](0069-two-engine-implementer-pool.md) (két implementer motor) és
[ADR 0086](0086-ci-dispatch-only-build-gate.md) (dispatch-only build gate) döntéseire.

## Kontextus

Az Epic 2-ből kilenc kör van hátra (E02-R12…R20), mindegyikhez **előre megírt
brief** és **kiosztott ADR-szám**. A körök levezénylése ma minden lépésnél
emberi indítást kíván, pedig a lépéssor maga determinisztikus:

```
pre-flight → brief-revízió → implementer indítás → jelzésre várás →
review → javító kör → CI-dispatch → zöld kapus merge → HANDOFF → STOP
```

A gépi részek már artefaktumok (`mm-round.sh`, `wait-for-round.sh`,
`round-gate.sh`, `codex-signal.sh`); ami hiányzik, az a **körök láncolása**.

**A mérés, amiből ez az ADR született — az E02-R11 (2026-07-31):** az implementer
**kétszer** állt meg `stopped` jelzéssel, mindkétszer valós, blokkoló
ellentmondáson, amit a kör orchestrátora írt a briefbe:

1. a controllerre bízott audio lease ütközött a `MicCapture` lease-ével
   (`audio.session_busy` — a production út halott lett volna);
2. a `failed` státuszra írt acceptance **elérhetetlen** volt (az egész
   reducerben egyetlen sor állítja, `preparing`-re őrizve).

Mindkét feloldás **ítélet** volt, nem szabályalkalmazás — a másodikat az
döntötte el, hogy a `cancelled` ág nem hív recordert, tehát **nem keletkezik
hamis history-bejegyzés**. Egy pipeline, amely az ilyen döntéseket felügyelet
nélkül, korlátlanul hozza meg, több körön át beépíthet egy rossz döntést,
mielőtt bárki látná. Egy pipeline viszont, amely **minden** `stopped`-nál
megáll, az E02-R11-et kétszer állította volna le fél órára — éjszaka a lánc az
első ütközésnél elhalna.

Az ADR ezt a két szélsőséget zárja ki egy **kötött megállási szerződéssel**.

## Döntés

### 1. Egy futtatás = egy kör = egy FRISS session

A `tools/round-pipeline.sh` egyetlen meghívása **legfeljebb egy** kört visz
végig, és ehhez **új, headless orchestrátor-sessiont** indít
(`claude -p`, a projekt gyökerében, a `sdd-round-driver` skillel).

Ez nem kikerüli az [ADR 0052](0052-ci-apk-automerge-session-per-round.md) „egy session = egy kör"
szabályát, hanem **teljesíti**: minden kör tiszta kontextussal indul, és az
előző kör kontextusa nem szivárog át.

### 2. Az autonómia határa: a kör SAJÁT, még nem merge-elt artefaktumai

Az orchestrátor-session **önállóan dönthet és folytathat**, ha az ütközés
feloldása a kör **saját**, még nem merge-elt artefaktumát érinti:

- a kör-brief (`docs/rounds/eXX-rYY-*.md`) — dokumentált **§0.0 revízióval**;
- a kör **saját**, ebben a pre-flightban írt ADR-je (pl. az E02-R11-nél a 0077);
- a kör engedélyezett-fájllistája **szűkítés** irányban;
- a javító kör (ugyanaz a motor, findings-listával).

Az orchestrátor **KÖTELEZŐEN MEGÁLL** (halt, merge nélkül), ha a feloldás:

| # | Halt-feltétel |
|---|---|
| H1 | egy **már merge-elt** ADR módosítását kívánná |
| H2 | egy **lezárt kör** viselkedésének megváltoztatását kívánná (a brief tilos zónája) |
| H3 | a **tilos zóna feloldását** kívánná (új fájl az engedélyezett listán kívül) |
| H4 | **BLOCKER vagy MAJOR** lelet, amely **egy** javító kör után is nyitva van |
| H5 | a **CI kétszer piros** ugyanazon a körön |
| H6 | az implementer **`blocked`** jelzést ad, vagy `unknown`/`stalled` állapotban hal meg kétszer |
| H7 | a `tools/round-gate.sh` nem hozható zöldre |
| H8 | a `main` a dispatch óta mozdult, és a rebase konfliktust ad |

Halt esetén a lánc **leáll** (nem csak az adott kör): a
`.pipeline/HALTED` fájl elkészül a pontos okkal, és a következő cron-firing
azonnal kilép. A láncot **ember indítja újra** (`tools/pipeline-status.sh --resume`).

**Miért éppen itt a határ:** a kör saját, még nem merge-elt ADR-je definíció
szerint ebben a pre-flightban született, tehát a javítása ugyanannak a
tervezési aktusnak a része — ezt a mai (E02-R11) két eset is igazolta. Egy
merge-elt ADR viszont már **más körök alapja**; a csendes megváltoztatása
visszamenőleg érvényteleníti mások mérését.

### 3. A zöld kapu és a merge-jog változatlan

Az [ADR 0052](0052-ci-apk-automerge-session-per-round.md) kapuja nem lazul: format + analyze +
architecture + teljes CI-suite + randomizált property + APK **mind zöld** →
squash-merge külön jóváhagyás nélkül. Bármi piros vagy hiányzik → **merge
tilos**, és az halt-feltétel (H5/H7).

A pipeline **nem ad új merge-jogot** — csak automatizálja a meglévőt.

### 4. A lánc soros, és zárral védett

Egyszerre **egy** kör futhat. A `tools/round-pipeline.sh` `flock`-ot vesz a
`.pipeline/lock`-on; ha a zár foglalt, azonnal, sikerrel kilép („már fut").
Emellett indulás előtt ellenőrzi, hogy nincs **nyitott PR** és nincs **futó
workflow** — ezen a boxon mérten előfordult, hogy egy másik autonóm driver is
kört vezetett ugyanabban a repóban.

### 5. A sor a repóban van, auditálhatóan

A körök sorrendje és állapota a `docs/execution/pipeline-queue.tsv` fájlban él
(committolva). A futásidejű állapot (`lock`, `current`, `HALTED`, logok) a
`.pipeline/` alatt, **gitignore-olva**.

Ha egy kör befejeződik és merge-elődik, a pipeline a sor-fájlt `done`-ra
állítja és **külön commitban** viszi a `main`-re. A HANDOFF frissítése továbbra
is az orchestrátor-session dolga (ADR 0052 záró rituálé).

### 6. Az implementer motor sorfájlban dőlt el, de a halt-szerződés motorfüggetlen

A `pipeline-queue.tsv` `engine` oszlopa körönként rögzíti a motort
([ADR 0069](0069-two-engine-implementer-pool.md) besorolása szerint). A megállási
szerződés (§2) ettől független.

### 7. Amit a pipeline SOHA nem tesz meg

- nem nyit epikot, nem ír új SDD-fejezetet, nem oszt új ADR-számot merge-elt
  döntés fölé;
- nem módosítja ezt az ADR-t, a `tools/round-pipeline.sh`-t, a
  `round-gate.sh`-t vagy a `.github/`-ot **kör közben** (a mérce nem módosulhat
  attól, akit mér — lásd `docs/LESSONS.md` „a mércét is ellenőrizd");
- nem hagyja ki a review-t „mert a gate zöld";
- nem zárja le az epicet: az **E02-R20** (epic-zárás) elérése **halt** —
  a záró kört ember indítja.

## Következmények

- Az Epic 2 maradék kilenc köre felügyelet nélkül végigfuthat, de bármelyik
  ítéletet kívánó ponton ember elé kerül, és a lánc addig áll.
- A halt mindig **jelentéssel** jár: a `.pipeline/HALTED` tartalmazza a kört, a
  halt-feltétel kódját (H1–H8), és a legutolsó orchestrátor-jelentést.
- Az [ADR 0052](0052-ci-apk-automerge-session-per-round.md) „STOP a kör végén" szabálya
  session-szinten továbbra is él; a láncolást a **pipeline** végzi, nem a
  session maga — egy orchestrátor-session sosem indít második kört.
- A `docs/LESSONS.md`-be az E02-R11 két STOP-ja tanulságként bekerül: az
  **elérhetetlen cél-státusz** mérési szabálya (`grep -n "status:
  PracticeSessionStatus.<X>"` a reduceren, nem az átmenettábla) és az
  **erőforrás-tulajdonlás** mérési szabálya (`grep -rn "\.acquire(" lib/`).
