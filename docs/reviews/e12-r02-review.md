# E12-R02 — Review

Brief: [`docs/rounds/e12-r02-sdd-index-and-dependency-graph.md`](../rounds/e12-r02-sdd-index-and-dependency-graph.md)
ADR: [`docs/adr/0443-sdd-index-machine-checkable-contract.md`](../adr/0443-sdd-index-machine-checkable-contract.md)
Diff: `git diff 4437fdb6..3316b844` (implementer: `sonnet-impl` / Claude Sonnet 5 `--effort high`)
Reviewer: Claude (Opus 5) · Dátum: 2026-08-28
**Verdikt: ~~CHANGES REQUIRED~~ → APPROVED** (javító kör után, `a7d4308f` — lásd
a záró [„Javító kör — újra-ellenőrzés"](#javító-kör--újra-ellenőrzés-a7d4308f) szakaszt)

## Összegzés

**BLOCKER: 0 · MAJOR: 1 · MINOR: 1 · NOTE: 2**

A kör gépezete jó: a checker magja tesztelhető és gyökér-paraméteres (ADR 0443 D4),
a `package:yaml` tilalmát önvédő teszt őrzi (D3), a ciklus-detektálás valódi
fixture-ökön mér (D2), és a Chapter 12 `42 → 36` javítása mérve helyes (D1). A
teljes gate ZÖLD, 35/35 teszt.

**Ennek ellenére a kör fő terméke — a `00-index.md` tábla — 14 sorából 9-en
HIBÁSAN renderelődik**, és pontosan az a tolerancia fedi el, amit a brief §0.0.A
P2 kért. Ez az F1 MAJOR: a zöld gate itt nem bizonyíték, mert a checker és a
Markdown-renderer KÜLÖNBÖZŐ táblát olvas ugyanabból a fájlból.

## Leletek

### F1 — MAJOR — A `Zárójelentés` cella elhagyása 9 soron NÉGY oszlopot told el a renderelt táblában

**Hol:** `docs/sdd/00-index.md:13-27` (tábla), `tool/check_sdd_index.dart:157-163`
(a tolerancia), `test/tooling/sdd_index_guard_test.dart:133-151` (a cellát rögzítő teszt).

**Mit mértem.** A kör három új oszlopot tett a tábla végére
(`Státusz`, `Implementation progress`, `Dependency`), így a fejléc **9 oszlop**, és
a `Zárójelentés` a **6.** (index 5), nem az utolsó. A 14 adatsorból **9 sor csak 8
cellát ír** (Chapter 5, 6, 8, 9, 10, 11, 12, 13, 14) — ugyanaz az elhagyás, ami a
RÉGI, 6 oszlopos táblában még ártalmatlan volt, mert ott a `Zárójelentés` volt az
utolsó oszlop.

A GFM/CommonMark tábla-szemantika a hiányzó cellákat a sor **VÉGÉRE** teszi; a
checker viszont a `Zárójelentés` HELYÉRE szúr be üres cellát
(`check_sdd_index.dart:157-163`). Amíg a két hely egybeesett, a két értelmezés
azonos volt. Most szétvált:

```
$ python3 render_probe.py docs/sdd/00-index.md      # reviewer-próba, lásd §Próbatesztek
fejléc (9 oszlop): [Chapter, Cím, Fejlesztési körök, Fő előfeltétel, Fájl,
                    Zárójelentés, Státusz, Implementation progress, Dependency]
a "Zárójelentés" oszlop indexe: 5 (utolsó index: 8)

--- Chapter 12 (8 cella / 9) ---
  'Zárójelentés'             checker=''                          RENDERELT='folyamatban (10 nyitott blocker: P0×1, P1×5, P2×4)'
  'Státusz'                  checker='folyamatban (10 nyitott…)' RENDERELT='ld. `docs/release/program-baseline.md` + …'
  'Implementation progress'  checker='ld. `docs/release/…`'      RENDERELT='ch01–ch11'
  'Dependency'               checker='ch01–ch11'                 RENDERELT=''

Eltérő értelmezésű sorok: 9 / 14
```

**Mi ebből a tényleges kár.**

1. A renderelt indexben a Chapter 5, 6, 8–14 sorok **`Zárójelentés` oszlopa
   `specifikálva`-t mutat** — vagyis az index azt állítja, hogy ezeknek a
   fejezeteknek van zárójelentése, aminek `specifikálva` a neve. A `Zárójelentés`
   valós tartalma (nincs ilyen fájl) így pont az ellenkezőjére fordul.
2. A `Dependency` oszlop mind a 9 soron **üresen** renderelődik — az az oszlop,
   amit a brief §3 kifejezetten kért.
3. A Chapter 12 sora, a kör LEGFONTOSABB sora, mind a négy új cellájában el van
   csúszva.

**Miért MAJOR és nem MINOR.** A kör célja (`§1`) az, hogy „az »aktuális fejezet /
következő kör« kérdés emberi olvasás nélkül is eldönthető legyen" — de az emberi
olvasás sem lehet HAMIS. Ez nem kozmetika: a checker **más táblát validál**, mint
amit bárki más lát, és a divergenciát egy teszt
(`sdd_index_guard_test.dart:133-151`, „tolerates extra trailing columns beyond
Zárójelentés") KIFEJEZETTEN rögzíti helyes viselkedésként. Egy GFM-hű parser
ráadásul nem csak mást olvasna, hanem **el is hasalna**: a `specifikálva` cella a
`Zárójelentés` oszlopba kerülve nem üres és nem `—`, viszont nincs benne
Markdown-link → `parseChapterTable` `FormatException`-t dobna
(`check_sdd_index.dart:198-203`).

Ez ugyanaz a hibaosztály, mint [L476](../LESSONS.md#l476): a sor-alapú guard
szerkezetileg vak arra az alakra, amit a kanonikus feldolgozó előállít.

**Javasolt irány (NEM kész patch).** A 9 soron írd ki explicit módon a
`Zárójelentés` cellát (`—`, ahogy a Chapter 1 sora már ma is teszi), hogy MINDEN
sor 9 cellás legyen. A `parseChapterTable` toleranciáját ne vedd ki — maradjon
védőháló —, de mellé kell egy cella, ami **pirosra vált, ha a valódi
`00-index.md`-ben van a fejléctől eltérő cellaszámú sor**; enélkül a hiba
visszakúszik. Az F1 zárását ez a második, „a valódi táblán minden sor teljes
cellaszámú" cella teszi ellenőrizhetővé.

### F2 — MINOR — A `Dependency` oszlop a manifest kézzel karbantartott, NEM ellenőrzött másolata

**Hol:** `docs/sdd/00-index.md:15-27` (`Dependency` cellák) vs.
`docs/sdd/dependency-graph.yaml:91-151` (`edges:`).

**Mit mértem.** A `Dependency` oszlop ugyanazt az információt hordozza, mint a
manifest `edges:` blokkja, de a checker **nem veti össze a kettőt**: a
`validateSddIndex` a `Dependency` cellát nem is olvassa
(`parseChapterTable` nem is menti el). A Chapter 12 sora ráadásul más
jelöléssel él (`ch01–ch11`, en-dash-es tartomány), mint az összes többi sor
(`ch03, ch07` — vesszős felsorolás), tehát gépi összevetésre ma nem is alkalmas.

ADR 0443 D2 kimondja, hogy a manifest az EGYETLEN forrás, és az `00-index.md`
ASCII-ábrája ettől kezdve illusztráció. A `Dependency` oszlop viszont
**géppel olvashatónak látszik** (node-id-ket ír), miközben semmi nem őrzi —
pontosan az a „prózai duplikátum, ami elcsúszhat" hibaosztály, amiért ez a kör
egyáltalán létezik.

**Javasolt irány.** Vagy (a) a checker vesse össze a `Dependency` cellát a
manifest éleivel — ehhez a Chapter 12 celláját is egységes, vesszős listára kell
hozni; vagy (b) az ASCII-ábrához hasonlóan a tábla alatti jegyzet mondja ki, hogy
ez az oszlop **illusztráció**, a szerződés a `dependency-graph.yaml`. A (b) olcsóbb
és a diffet nem hizlalja.

### F3 — NOTE — A fejezet↔fájl összerendelés a fájlnév-prefixen múlik, nem a tábla linkjén

`check_sdd_index.dart:631-642`: a `measuredKorCounts` kulcsa a fájlnév `NN-`
prefixe, a `korokMismatch` pedig `measuredKorCounts[row.chapterNumber]`-t
hasonlít. Ha egy sor `Fájl` linkje egy MÁSIK fejezet-fájlra mutatna, az A2 (a
fájl létezik) átmenne, és a körszámot továbbra is a prefix-egyező fájlból mérné —
tehát a rossz link nem derülne ki. Ma mind a 14 sor prefix-helyesen linkel, és a
brief acceptance-cellái ezt az invariánst nem kérik, ezért NOTE. Egy jövőbeli kör
`row.filePath` prefixét összevethetné `row.chapterNumber`-rel.

### F4 — NOTE — Az ASCII „Függőségi kép" nincs a manifesthez mérve

A kör helyesen jelöli az ábrát illusztrációnak (`00-index.md:52-57`), és ezt a
manifest fejléc-kommentje is kimondja (`dependency-graph.yaml:25-31`). Ez
tudatos, dokumentált korlát, nem hiba — de az ábra így elcsúszhat a manifesttől
anélkül, hogy bármi pirosra váltana. Ha egy jövőbeli kör olcsón megfogná (az ábra
`Chapter N → Chapter M` sorainak összevetése az élekkel), az bezárná a rést.

## Acceptance criteria — tételesen

| # | Kritérium | Bizonyíték | Ítélet |
|---|---|---|---|
| A1 | Minden fejezet pontosan egyszer; duplikátum/hiány → nem-nulla kilépés | `sdd_index_guard_test.dart:325-353` (`duplicateChapter`, `missingChapter`), gate 35/35 zöld | ✅ |
| A2 | Minden index-hivatkozás létező fájlra mutat | `sdd_index_guard_test.dart:355-388` (`Fájl` + `Zárójelentés` dangling cellák) | ✅ |
| A3 | A tábla körszáma MINDEN fejezetre egyezik a mért fejléc-számmal (Ch12 42→36) | `00-index.md:26` mostantól `36`; `sdd_index_guard_test.dart:390-419` + `:545-576` (mind a 14 mért szám kipinnelve) | ✅ |
| A4 | A graph körmentes; bevitt kör pirosra vált | `findCycle` 3 cella (`:270-292`) + `validateSddIndex` ciklus-cella (`:421-455`) | ✅ |
| A5 | A checker mindkét fejléc-alakot (`# Kör`, `## Kör`) ismeri | `countKorHeaders` regex `^#{1,2} Kör \d+` (`check_sdd_index.dart:229`), 4 cella (`:48-83`), és a Ch14 42-es mért értéke a `:545` cellában | ✅ |
| A6 | A kritikus út és a capability-gated fejezetek jelöltek | `dependency-graph.yaml` mind a 14 node-ján `critical_path` + `capability_gated`; a hiányzó mező pirosra vált (`:193-212`) | ✅ |
| A7 | A checker a valódi `docs/sdd/`-n zölden fut | `dart run tool/check_sdd_index.dart` → `SDD index OK (0 issue(s)).`, exit 0 (reviewer futtatta a `/tmp/review-e12-r02` klónban) | ✅ |
| A8 | A parser tolerálja az 5- és 6-cellás sort; próza és `—` a körszám-cellában | `parseKorokCount` 5 cella (`:11-44`), `parseChapterTable` 5 cella (`:91-161`) | ⚠ **a betű teljesül, a szándék nem** — a tolerancia MEGVAN, de a valódi táblát nem hozta rendbe: lásd **F1** |
| A9 | Nincs `package:yaml` import, nincs `pubspec` módosítás | `sdd_index_guard_test.dart:493-533` (önvédő import-teszt mindkét fájlra); `git diff --name-status` → 5 fájl, `pubspec` nincs köztük | ✅ |

**Valódi-sértés próba (brief §6, KÖTELEZŐ).** Automatizált formában megvan
(`sdd_index_guard_test.dart:584-634`: a Chapter 12 `42`-re visszaírva az A3
`korokMismatch`-et ad a valódi, mért fájl-számok ellen), és az implementer a §10-ben
a lemezen mutált változatot is dokumentálta. **Elfogadva.**

## Scope

```
$ python3 tools/scope-audit.py --repo /tmp/review-e12-r02 \
    --brief docs/rounds/e12-r02-sdd-index-and-dependency-graph.md \
    --base 4437fdb6f2a92b6e87147cbdf029c12a975141f4
Legacy scope audit OK (4437fdb6f2a9..3316b84434f7, 5 changed path(s), 0 generated/ignored)
```

Az implementer jelzésfájlja ugyanezt mérte (`scope_audit=ok`,
`scope_audit_changed=5`, `scope_audit_base=4437fdb6…`). Az öt fájl mind a brief
§4 listáján van. **Scope-sértés nincs.** A `dirty_files=1` a gitignore-olt
`.codex-round-status` volt — a munkafa a `done` után `git status --short` szerint
tiszta, minden munka commitolva (4 commit).

## Gate-bizonyíték — a reviewer SAJÁT futtatása izolált klónban

```
$ git clone --branch sonnet-impl/e12-r02-… /home/ubuntu/music-theory /tmp/review-e12-r02
$ git -C /tmp/review-e12-r02 rev-parse HEAD      → 3316b84434f7b70027d1ecd8834d58cdf202974d
$ bash /tmp/review-e12-r02/tools/prepare-flutter-generated.sh   → exit 0
$ tools/round-gate.sh test/tooling/sdd_index_guard_test.dart
    → [1] format:       ZÖLD
    → [2] analyze:      ZÖLD   (No issues found!, 26.3s)
    → [3] test test/tooling/sdd_index_guard_test.dart: ZÖLD   (35/35, All tests passed!)
    → [4] architecture: ZÖLD   (Architecture dependencies OK, 12 allowlisted deviation(s))
$ dart run tool/check_sdd_index.dart
SDD index OK (0 issue(s)).      exit 0
```

**A zöld gate itt kifejezetten NEM bizonyíték az F1-re**, mert az F1 a checker és
a Markdown-renderer értelmezés-különbsége — a checker a saját értelmezését méri,
és abban a tábla helyes.

## Próbatesztek (eldobható, reviewer-oldali)

`render_probe.py` — a GFM-szemantika (hiányzó cellák a sor VÉGÉN) és a checker
`Zárójelentés`-helyre beszúró toleranciája ugyanarra a 14 sorra. Kimenet: **9/14
sor eltérő értelmezésű**, soronként oszlopra bontva (a teljes kimenet az F1-ben).
A próba a reviewer scratchpadjában futott, a repóba nem került be.

## Architektúra, termékhatárok, lifecycle

- **AGENTS.md §6:** a diff `lib/`-hez nem nyúl; a `tool/` → `test/tooling/`
  relatív import a repó bevett, meglévő mintája
  (`architecture_allowlist_guard_test.dart:3`). A `check_architecture.dart`
  gate-lépés zöld, az allowlist nem nőtt (12 tétel).
- **AGENTS.md §5 (termékhatárok):** a kör nem érint audiót, hálózatot, mikrofont,
  engedélyt, secretet vagy felhasználói adatot. `risk = "normal"`, a
  `.ai/router.toml` high-risk útvonalaira nincs találat → **security-reviewer nem
  kötelező** ebben a körben.
- **Lifecycle:** a checker szinkron `dart:io` olvasásokat végez, nem nyit
  stream/isolate/timer erőforrást. `main()` a `FormatException`-t elkapja és
  `exitCode=2`-vel jelez, a stack trace-szel — nincs elnyelt hiba.
- **Tesztek:** determinisztikusak (nincs időzítés, randomizáció, hálózat). Nem
  találtam kikapcsolt tesztet, `skip`-et vagy lazított küszöböt.

## A javító körnek átadott leletlista

| # | Osztály | Egy sorban |
|---|---|---|
| F1 | **MAJOR** | A 9 hiányos cellaszámú sor renderelve 4 oszloppal eltolódik — írd ki explicit `—`-t a `Zárójelentés` cellába mind a 9 soron, és tegyél mellé cellát, ami a valódi `00-index.md`-ben a fejléctől eltérő cellaszámú sorra PIROSRA vált |
| F2 | MINOR | A `Dependency` oszlop a manifest nem ellenőrzött másolata — vagy mérd a manifest éleihez (a Ch12 `ch01–ch11` celláját egységes listára hozva), vagy mondd ki jegyzetben, hogy illusztráció |
| F3 | NOTE | A fejezet↔fájl összerendelés a fájlnév-prefixen múlik, nem a link célján |
| F4 | NOTE | Az ASCII „Függőségi kép" nincs a manifesthez mérve (tudatos, dokumentált korlát) |

**Merge-hatás:** az F1 nyitva → **merge TILOS**. Az F2 a körben olcsón javítható
(egy jegyzet-sor), ezért a javító kör kapja. Az F3/F4 nem blokkol, follow-up.

---

## Javító kör — újra-ellenőrzés (`a7d4308f`)

Egy javító kör futott (`sonnet-impl`, ugyanaz a munkapéldány), commit
**`a7d4308f`**, 3 fájl / +167 −9. A reviewer minden leletet KÜLÖN mért újra.

### F1 — MAJOR → **ZÁRVA**

**(a) A valódi tábla rendben.** Mind a 9 hiányos sor megkapta az explicit `—`
`Zárójelentés` cellát (`00-index.md`, Chapter 5, 6, 8, 9, 10, 11, 12, 13, 14).
A reviewer render-próbája újrafuttatva:

```
$ python3 render_probe.py docs/sdd/00-index.md
fejléc (9 oszlop): [...]
Eltérő értelmezésű sorok: 0 / 14          # a javítás előtt: 9 / 14
```

Cellaszám-mérés: mind a 14 adatsor **9 cella**, egyezik a fejléccel.

**(b) Gépi őr, ami visszakúszás esetén pirosra vált.** Új cella:
`test/tooling/sdd_index_guard_test.dart:535-596` — *„F1 (e12-r02 review) — the
real chapter table has no GFM cell-count drift"*. A cella a valódi
`00-index.md`-t olvassa **saját, GFM-hű cellaszámlálóval** (`splitRowGfm`), tehát
szándékosan FÜGGETLEN a `parseChapterTable` név-alapú toleranciájától — pontosan
ezért tudja megfogni azt, amire a checker vak.

**A reviewer SAJÁT valódi-sértés próbája** (nem az implementer bemondása; izolált
`/tmp/review-e12-r02` klónban, a `a7d4308f` HEAD-en):

```
$ # a Chapter 5 sorból eltávolítva a "—" Zárójelentés cella (8 cella lesz)
$ flutter test test/tooling/sdd_index_guard_test.dart
  Expected: empty
    Actual: ['line 19: 8 cell(s), expected 9: "| 5 | Epic 4: AI Guitar Teacher | 24 | … |"']
  a GFM renderer places missing cells at the ROW END, not at the "Zárójelentés"
  column by name — a short row shifts every later column in the rendered table
  (e12-r02 review F1)
  test/tooling/sdd_index_guard_test.dart 586:7
00:00 +35 -1: Some tests failed.        exit 1
$ # a sértés visszaállítva → a munkafa tiszta
```

Az őr tehát **valóban piros** a sértésre, a hibás sort a sorszámával nevezve meg.
Az F1 két része együtt zárja a leletet: a tábla helyes, ÉS a visszakúszás
mérve piros.

### F2 — MINOR → **ZÁRVA**

A tábla alá bekerült a jegyzet (`00-index.md`), ami kimondja, hogy a
`Dependency` oszlop — az ASCII „Függőségi kép"-hez hasonlóan — **illusztráció,
nem szerződés**, a géppel ellenőrzött egyetlen forrás a
`dependency-graph.yaml` `edges:` blokkja (ADR 0443 D2). A jegyzet nevesíti a
Chapter 12 sorának eltérő jelölését (`ch01–ch11` tartomány) is, tehát a
felfedezett gépi-összevethetetlenség dokumentálva van, nem eltüntetve. Ez a
review által javasolt (b) út — a diffet nem hizlalja.

### F3 / F4 — NOTE → változatlanul nyitva, follow-up

A javító kör helyesen NEM nyúlt hozzájuk.

### Gate-bizonyíték a javítás után (reviewer, izolált klón, `a7d4308f`)

```
$ git -C /tmp/review-e12-r02 rev-parse HEAD → a7d4308f7271edacddf6073e23f8d51565f7b28f
$ tools/round-gate.sh test/tooling/sdd_index_guard_test.dart
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/sdd_index_guard_test.dart                zöld   (36/36, All tests passed!)
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
MINDEN GATE ZÖLD.                                              GATE_EXIT=0
```

### Scope a TELJES körre (pre-flight bázisról)

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e12-r02 \
    --brief docs/rounds/e12-r02-sdd-index-and-dependency-graph.md \
    --base 4437fdb6f2a92b6e87147cbdf029c12a975141f4
Legacy scope audit OK (4437fdb6f2a9..a7d4308f7271, 6 changed path(s), 1 generated/ignored)
```

A `1 generated/ignored` a `docs/reviews/e12-r02-review.md` — a reviewer saját
kötelező artefaktuma, kód szintű mentesség
(`tools/ai_router/security.py::GENERATED_IGNORED_PREFIXES`), nem sértés.

### Végső mérleg

| # | Osztály | Állapot |
|---|---|---|
| F1 | MAJOR | **ZÁRVA** — tábla javítva (0/14 eltérés) + független őr, reviewer-próbával pirosra mérve |
| F2 | MINOR | **ZÁRVA** — a `Dependency` oszlop kimondottan illusztráció |
| F3 | NOTE | nyitva (follow-up: fejezet↔fájl prefix-egyezés) |
| F4 | NOTE | nyitva (follow-up: az ASCII-ábra manifesthez mérése) |

**BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 2**

## VÉGSŐ DÖNTÉS: APPROVED

Nyitott BLOCKER/MAJOR/MINOR nincs. A merge a zöld kapu (ADR 0052) exact-SHA
teljesülése után mehet: `full-gate.yml` + `router-ci.yml` `success` a merge
SHA-ján.
