# E13-R24 — Review (Song import, előnézet és szerkesztő UI)

- **Kör:** `E13-R24` · **Branch:** `sonnet-impl/e13-r24-song-import-and-editor`
- **Reviewelt HEAD:** `665c9fbd`
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude Opus 5 (orchestrátor-ülés), read-only, izolált `/tmp` klón
- **Dátum:** 2026-08-26
- **Verdikt:** **CHANGES REQUESTED** — 0 BLOCKER, **1 MAJOR**, 3 MINOR, 3 NOTE

---

## 1. Amit magam mértem (nem bemondás)

### 1.1 Gate-újrafuttatás izolált klónban

```
git clone --branch sonnet-impl/e13-r24-song-import-and-editor \
  /home/ubuntu/ss-sonnet-impl-e13-r24 /tmp/review-e13-r24
bash /tmp/review-e13-r24/tools/prepare-flutter-generated.sh      → exit 0
tools/round-gate.sh <a brief §7 szerinti 15 tesztút>
```

**Eredmény: 20/20 lépés ZÖLD**, `MINDEN GATE ZÖLD`. Lépésenként:

| # | Lépés | Verdikt | Teszt |
|---|---|---|---|
| 1 | format | ZÖLD | 2045 fájl, 0 changed |
| 2 | analyze | ZÖLD | — |
| 3 | `import_flow_test.dart` | ZÖLD | +2 |
| 4 | `import_blocking_error_test.dart` | ZÖLD | +4 |
| 5 | `editor_draft_test.dart` | ZÖLD | +3 |
| 6 | `editor_keyboard_flow_test.dart` | ZÖLD | +3 |
| 7 | `e13_r24_screens_golden_test.dart` | ZÖLD | +6 |
| 8 | `ui_inventory_test.dart` | ZÖLD | +1 |
| 9–12 | a négy listán KÍVÜLI pin-teszt | ZÖLD | +1/+1/+2/+2 |
| 13 | `app_router_test.dart` | ZÖLD | +22 |
| 14 | `architecture_dependency_test.dart` | ZÖLD | +44 |
| 15–17 | `dio`/`preferences`/`route_literal` guard | ZÖLD | +1/+2/+1 |
| 18–20 | architecture, secrets, l10n | ZÖLD | — |

Összesen **95 zöld teszt** — az implementer §10-beli állítása FÜGGETLENÜL
megerősítve. A négy pin-teszt (`song_import_screen_test`,
`song_import_preview_screen_test`, `song_editor_screen_test`,
`guitar_pro_conversion_guidance_test`) és az `app_router_test` **változatlanul**
zöld: a helyben-migráció (§0.0/B/R7) tartotta a típusneveket, útvonalakat és
konstruktor-szignatúrákat.

### 1.2 Scope-audit (a hiteles eszközzel, nem `git diff --stat`-tal)

```
python3 tools/scope-audit.py --repo /tmp/review-e13-r24 \
  --brief …/e13-r24-song-import-and-editor.md --base 3b88f757
→ Legacy scope audit OK (3b88f75792f8..665c9fbd7625, 20 changed path(s), 0 generated/ignored)
```

A wrapper gépi auditja is `scope_audit=ok` volt mindkét futáson.
`test/ui/ui_inventory_test.dart` diffje **ÜRES** — a §0.0/B/R13 előírás
teljesült, új `*_screen.dart` nem keletkezett (86 → 86).

### 1.3 Eldobható próbatesztek (mind visszaállítva; `git status` üres)

| # | Próba | Mért eredmény |
|---|---|---|
| P1 | `song_section_editor.dart`: a `constraints: BoxConstraints(minWidth/minHeight: 48)` **teljes eltávolítása** | az A7 érintési-cél cella **ZÖLD maradt** (`00:01 +3: All tests passed!`) |
| P2 | ugyanott `48` → **`32`** | az A7 cella **ismét ZÖLD** (`+3`) |
| P3 | eldobható méret-szonda ugyanezen a 32-es állapoton | `getSize(IconButton) = Size(48.0, 48.0)`, `inner ConstrainedBox = Size(40.0, 40.0)` |
| P4 | `song_editor_screen.dart`: az A5 hiba-sáv törlése | az **A5 cella PIROSRA váltott** ✔ |
| P5 | `song_editor_screen.dart`: a Save `canPersist`-kapujának kivétele | az **A6 cella PIROSRA váltott** ✔ |
| P6 | `SongValidator().validate()` + `SongCapabilityResolver().resolve()` költsége nagy dokumentumon (100 / 1000 / 4000 esemény, 20 futás átlaga) | `0,531 ms` / `0,577 ms` / `0,651 ms` — közel lapos |

---

## 2. Leletek

### MAJOR-1 — az A7 érintési-cél cellája NEM TUD PIROSRA VÁLTANI (üres cella, L477)

**Fájl:** `test/features/songs/import/editor_keyboard_flow_test.dart:88-117`
(a mért production oldal: `lib/features/song_trainer/presentation/widgets/song_section_editor.dart:37-44,52-58`)

**Mit mértem.** A cella mind a hat átrendező gombot végigjárja, és
`tester.getSize(...)`-szal `>= 48.0`-t állít. A P1/P2/P3 próba viszont
megmutatta, hogy ez az érték **szerkezetileg konstans**:

```
constraints eltávolítva  → a cella ZÖLD (+3)
constraints 48 → 32      → a cella ZÖLD (+3)
mért méretek 32-es állapotban:
    getSize(IconButton)      = Size(48.0, 48.0)     ← ezt méri a cella
    inner ConstrainedBox     = Size(40.0, 40.0)     ← ez a kör tényleges kódja
```

A Material `IconButton` a `MaterialTapTargetSize.padded` alapértelmezés miatt a
saját render-boxát MINDIG 48 dp-re fújja fel, függetlenül a `constraints:`
paramétertől. A cella tehát **a Material alapértelmezését méri, nem a kör
kódját** — és nincs az az implementációs hiba, ami pirosra váltaná.

**Miért MAJOR és nem MINOR.** A brief §6.1 kifejezetten előírt egy
`47.0 → PIROS` cellát (a küszöb alatti eset); ez a cella nem létezik, és ebben
a formában nem is létezhet. Ez ráadásul a sáv **harmadik** egymást követő
érintési-cél lelete (E13-R20/MAJOR-1, E13-R21/MAJOR-2, [L496](../LESSONS.md#l496)),
és pontosan az [L477](../LESSONS.md#l477) hibaosztálya: a cella zöldje nem
bizonyíték, ha a bukási képessége nincs megmérve.

**Mellékmérés:** a production `constraints: BoxConstraints(minWidth: 48,
minHeight: 48)` hozzáadása ezen a témán **mért no-op** — a gomb enélkül is
48×48. A doc-comment viszont azt állítja, hogy „the default constraints do not
guarantee it"; ez az állítás a P1 próba szerint **hamis**.

**Javasolt irány (NEM kész patch).** A cella arra a tulajdonságra mérjen, ami
ténylegesen változhat és amit a kör birtokol — pl. a szemantikai csomópont
`SemanticsNode.rect`-je (`tester.getSemantics`), vagy az `IconButton`
effektív `constraints`/`iconSize`+`padding` értéke —, és a javítás
tartalmazza a bizonyítékot, hogy a reviewer 32 dp-s próbája **pirosra** váltja.
Ha a mérés azt adja, hogy a `constraints:` valóban fölösleges ezen a témán, azt
a doc-comment mondja ki őszintén, a jelenlegi (hamis) állítás helyett.

### MINOR-1 — `_canPersist()` minden `build()`-ben újraszámol, pedig csak `state.persisted`-től függ

**Fájl:** `lib/features/song_trainer/presentation/screens/song_editor_screen.dart:35-45,119`

A `SongEditorScreen.build` a `songEditorStateProvider`-re iratkozik, tehát
MINDEN szerkesztési lépésnél (undo/redo, metaadat-gépelés, akkord hozzáadása)
újrafut — és vele a teljes `SongValidator().validate(persisted)`. A `persisted`
viszont csak betöltéskor és sikeres mentéskor változik.

**Mérve (P6):** `0,531 / 0,577 / 0,651 ms` 100 / 1000 / 4000 eseménynél — a
16,7 ms-os képkocka-büdzsé ~4%-a, és lényegében lapos az eseményszámban.
**Ezért NEM jank-forrás, és nem blokkol** — de fölösleges munka a szerkesztő
forró útján. Irány: memoizáld a `state.persisted` identitására.

### MINOR-2 — `_saveCopy` a mentés SIKERE ELŐTT elszakítja a szerkesztőt az eredetitől

**Fájl:** `lib/features/song_trainer/presentation/screens/song_editor_screen.dart:360-395`

A sorrend `controller.startNew(copy)` → `await controller.save()`. A
`startNew` friss `SongEditorState`-et publikál (`persisted == null`), tehát ha
a másolat mentése elbukik — validáció (`hasFatalIssue` → `validationFailed`,
a `save()` ilyenkor NEM ír) vagy `create` I/O-hiba —, a felhasználó egy
`editor-copy-…` identitású, gazdátlan piszkozaton marad, a csak olvasható
eredeti kontextusa nélkül, miközben a `canPersist(null) == true` miatt a Save
újra aktívvá válik.

**Az A6 cella ezt az utat nem járja be:** előbb *megjavítja* a fatális
hivatkozást (`addChord`), és csak az így érvényessé vált másolatot menti. A
„javítás nélkül másolok" út — épp az, amit egy felhasználó először próbál —
mérés nélkül maradt. Irány: előbb írj, és csak siker után váltsd az állapotot
(vagy hiba esetén állítsd vissza), plusz egy cella a javítatlan másolásra.

### MINOR-3 — nyers `TextStyle(color: …)` a téma tipográfiai tokenje helyett

**Fájlok:** `song_import_screen.dart:100-104`, `song_import_preview_screen.dart:54-56`,
`song_editor_screen.dart:246-248`

Mindhárom helyen `style: TextStyle(color: …)` áll, ami a `TextTheme` méret-,
súly- és sormagasság-tokenjeit eldobja (a szín-szerep viszont helyesen
`colorScheme.error`). A sáv saját design-system fegyelme szerint ez
`Theme.of(context).textTheme.bodyMedium?.copyWith(color: …)` alakot kíván.
A goldeneket a javítás elmozdíthatja — újrafelvétel `tools/golden-x86.sh
record`-dal, SOHA nem `--update-goldens`-szel (ADR 0426).

### NOTE-1 — a §3 „expanded több-paneles elrendezés" nem valósult meg, és nincs cellája

A brief §3 nevesíti „a szerkesztő compact strukturált és **expanded
több-paneles** elrendezését"; a diffben nincs töréspont-vezérelt elrendezés
(`SsBreakpoints`/`SsAdaptiveScaffold` nulla találat), és az A1–A9 közül
egyetlen cella sem méri. **Nem regresszió:** a sáv merge-elt precedense
ugyanez — a `song_library_screen.dart`, `song_overview_screen.dart` és
`setlist_list_screen_v2.dart` (E13-R23) mindegyike **nulla** `design_system`
importtal él. Nevesített follow-up az E13-R36 vizuális regressziós körhöz.

### NOTE-2 — az A1/A2 az APPLICATION réteget méri, amit ez a kör nem módosított

Az `import_flow_test.dart` mindkét cellája a `SongImportController`-t hajtja
közvetlenül (beinjektált `workspaceRoot` temp könyvtárral). Ez **jó** regressziós
őr az ADR 0284 §1–2-re, de nem a kör SAJÁT UI-kódjáról tesz állítást. A
cellák megtartandók; a tény a §10-ben nincs kimondva.

### NOTE-3 — `DateTime.now()` / `Random.secure()` a presentation rétegben

`_saveCopy` (`song_editor_screen.dart:361-363`) ugyanazt a mintát követi, mint
a fájlban már meglévő `_newDraft` — nem új szabálysértés, csak öröklött minta.

---

## 3. Acceptance criteria — tételes ellenőrzés

| # | Kritérium | Bizonyíték | Verdikt |
|---|---|---|---|
| A1 | Az előnézet nem hoz létre tartós rekordot | `import_flow_test.dart` A1-cella, valódi temp root: `repository.list` üres ÉS `tempRoot.listSync()` üres | ✅ |
| A2 | A megszakított import után nem marad temp fájl | ugyanott, A2-cella: `confirmPreview()` KÖZBEN megszakítva, a workspace nyitva volt | ✅ |
| A3 | A blokkoló hiba nem kerülhető meg (két producer) | `import_blocking_error_test.dart` (a)+(b) cella; az implementer valódi-sértés próbája `+2 -2`-t mért, a §10 rögzíti | ✅ |
| A4 | Figyelmeztetés vs blokkoló hiba elkülönül | ikon (`error_outline` vs `warning_amber_outlined`), `colorScheme.error`, külön `Semantics` címke | ✅ |
| A5 | A piszkozat mentési hiba után is megmarad | `editor_draft_test.dart` A5; a **P4 próbám pirosra váltotta** | ✅ |
| A6 | Csak olvasható forrásból csak másolat | `editor_draft_test.dart` A6; a **P5 próbám pirosra váltotta**; `update()` hívása a fake-ben `StateError` | ✅ (a boldog úton — lásd MINOR-2) |
| A7 | Az átrendezés billentyűvel/gombbal is elvégezhető | a két gomb-cella valódi (a `Draggable`/`ReorderableListView` ABSZENCIA-állítással együtt) | ⚠️ a működés ✅, **az érintési-cél cella üres — MAJOR-1** |
| A8 | A mentetlen kilépés következménye szövegben megjelenik | `editor_draft_test.dart` A8 — VALÓDI `push`/`maybePop` úton, nem in-place | ✅ |
| A9 | Golden minden képernyőről, 412×915 ÉS `textScaler: 2.0` | 6 PNG a `test/ui/goldens/goldens/`-ben, commitolva, x86-on felvéve; a golden-teszt +6 zöld | ✅ |

---

## 4. Architektúra és termékhatárok

- **Presentation → `domain/services/**`:** a `song_editor_screen.dart` új
  `SongValidator`/`SongCapabilityResolver` importja **megengedett** — sem a
  `test/core/architecture_dependency_test.dart` (44 cella, zöld), sem a
  `tool/check_architecture.dart` nem tilt ilyen élt, és mindkét szolgáltatás
  framework-független, tiszta függvény. A §0.0/B/R10 előzetes mérése helyes volt.
- **Design-system határ:** nulla közvetlen `design_system/foundations/**`
  import (az E13-R16/F8 hibaosztály nem ismétlődött).
- **Hálózat / mikrofon / secret / plugin:** a diff egyikhez sem nyúl; a három
  `tooling` guard zöld.
- **Erőforrás-életciklus:** az `ImportWorkspace` minden terminális ágon zár
  (`_finish` → `_closeWorkspace`) — az A2 cella ezt élesben méri.

## 5. Merge-döntés

**MAJOR-1 nyitva → merge TILOS.** Javító kör indul ugyanazzal a motorral, a
fenti leletlistával. A MINOR-1–3 a javító körben együtt javítható (a diffet nem
hizlalják); a NOTE-ok nem blokkolnak.

A zöld kapu többi eleme készen áll: 20/20 lokális gate, scope-audit OK, és az
exact-SHA CI (Full Gate + Router CI) a `665c9fbd`-n fut — a javító kör után
ÚJRA kell dispatch-elni az új HEAD-re.

---

# 6. Javító kör #1 után — ÚJRA-REVIEW (`92a15e70`, 2026-08-26)

**Verdikt: CHANGES REQUESTED (második kör)** — a négy eredeti lelet **ZÁRVA**,
de a MINOR-2 javítása **ÚJ MAJOR-t vezetett be**.

## 6.1 A zárt leletek — leletenként megmérve

| Lelet | Javítás | A reviewer BIZONYÍTÉKA |
|---|---|---|
| **MAJOR-1** | az A7 cella a `tester.getSize` helyett az `IconButton.constraints`-re mér (a widget SAJÁT, regresszálható tulajdonsága), és megköveteli, hogy ne legyen `null` | **ZÁRVA** — friss klónban, saját próbával: `48 → 32` ⇒ `Expected: a value greater than or equal to <48.0> / Actual: <32.0>` **PIROS**; a `constraints` teljes eltávolítása ⇒ `Expected: not null / Actual: <null>` + `[<'song-editor-section-move-up-0'>] must declare an explicit minimum touch-target constraint` **PIROS**. A cella most már TUD pirosra váltani. |
| **MAJOR-1/doc** | a hamis „the default constraints do not guarantee it" doc-comment átírva a MÉRT igazságra (a `MaterialTapTargetSize.padded` már 48×48-ra fújja, a `constraints` a *deklarált szerződés*) | **ZÁRVA** — a szöveg most azt állítja, amit a mérés mutat. |
| **MINOR-1** | `_canPersistMemo` — `identical(persisted, _canPersistCacheKey)` szerinti memoizálás | **ZÁRVA** |
| **MINOR-3** | mindhárom helyen `Theme.of(context).textTheme.bodyMedium?.copyWith(color: …)` | **ZÁRVA** — a hat golden változatlanul zöld (+6), tehát a token-váltás nem mozdította el a raszterizációt. |

**Saját gate-futás a javított HEAD-en** (ÚJ, friss `/tmp/review2-e13-r24` klón):
**20/20 lépés ZÖLD**, `MINDEN GATE ZÖLD`, **96 teszt** (az `editor_draft_test`
+3 → +4 az új MINOR-2 cellával).

## 6.2 MAJOR-2 (ÚJ) — a MINOR-2 javítása NÉMÁN ELDOBJA a felhasználó mentetlen szerkesztéseit

**Fájl:** `lib/features/song_trainer/presentation/screens/song_editor_screen.dart:417-427`
(`_saveCopy` záró ága), a hiányzó fedezet:
`test/features/songs/import/editor_draft_test.dart:239-336` (a MINOR-2 cella).

**A javítás, ami a bajt okozza.** A `_saveCopy` most hiba esetén
`await controller.load(id)`-t hív, hogy a szerkesztőt visszaállítsa az
eredetire. A `load()` viszont `_publishReady(document, document)`-et publikál,
azaz a **draftot IS** a lemezről olvasott dokumentumra állítja — a felhasználó
minden mentetlen szerkesztése ezzel megsemmisül.

**Mérve** (eldobható próbateszt a friss klónban, azóta törölve): csak olvasható,
validátor-fatális dokumentum; a felhasználó átnevezi a dalt, majd — a fatális
hivatkozás javítása NÉLKÜL — a „Save copy"-ra koppint:

```
PROBE before copy: draft title = My careful rename
PROBE after  copy: draft title = Legacy Song      ← a szerkesztés ELVESZETT
PROBE createCalls = 0                             ← és semmi nem is íródott ki
```

**Miért MAJOR.** Ez pontosan az a hibaosztály, amit a kör SAJÁT ADR-je tilt —
[ADR 0284](../adr/0284-import-preview-is-not-a-commit.md) §Döntés 4: *„A
piszkozat mentési hiba után is megmarad — a szerkesztett tartalom nem vész el"*
—, és amit az A5 cella máshol gépi őrrel véd. A javítás előtti kód nem volt
szép (a felhasználó a gazdátlan másolaton maradt), de **nem semmisítette meg a
munkáját**; a javító kör tehát egy kényelmetlenséget cserélt néma
munkavesztésre.

**Az új MINOR-2 cella ezt nem fogja meg:** a fixture-je egy ÉRINTETLEN
dokumentum — sosem szerkeszt a másolás előtt —, ezért csak a `persisted?.id` /
`draft?.id` visszaállását állítja, a tartalom elvesztését nem. Zöld cella, ami
a hibát nem látja.

**Javasolt irány (NEM kész patch).** A hiba-ág csak a *persisted* mutatót
állítsa vissza az eredetire, a **draftot hagyja érintetlenül** (a felhasználó
munkája megmarad, a Save továbbra is zárolt, a „Save copy" újra próbálható) —
és a bukás okát nevesítse a felületen. A cellát a próbám szerint kell
megerősíteni: szerkesztés → sikertelen másolás → a szerkesztés MÉG MINDIG a
draftban van.

## 6.3 Merge-döntés

**MAJOR-2 nyitva → merge TILOS.** Második javító kör indul ugyanazzal a
motorral. (A Codex-eszkaláció tárgytalan: a Codex-oldal kvóta miatt nem
futtatható — a kör-prompt §1.1 „MOTOR-FELÁLLÁS" blokkja ezt kimondja, tehát a
javító kör is `sonnet-impl`, a mércét pedig gépi őr tartja.)

---

# 7. Javító kör #2 után — VÉGSŐ DÖNTÉS: **APPROVED** (`08b7b13c`, 2026-08-26)

**0 nyitott lelet.** Minden korábbi lelet lezárva, a MAJOR-2 javítása
FÜGGETLENÜL megmérve egy HARMADIK, friss `/tmp/review3-e13-r24` klónban.

## 7.1 MAJOR-2 — ZÁRVA

**A javítás.** A `_saveCopy` most **a controller érintése ELŐTT** validálja a
másolatot (`if (!_canPersist(copy)) { … return; }`), tehát a még mindig
fatális eset SOHA nem hívja a `startNew`-t — a felhasználó élő piszkozata
érintetlen marad, a bukás okát pedig `SnackBar` nevezi meg. A megmaradó
repository-írási hiba ágán a `load(id)` **megszűnt**: helyette egy
képernyő-szintű `_copyWriteFailed` jelző tartja zárolva a Save-et és láthatóan
a „Save copy" újrapróbát, amíg a `persisted` újra nem lesz nem-null. A
`draft`-ot egyik ág sem írja felül.

**A saját mérésem (a §6.2 próbájának megismétlése a javított HEAD-en):**

```
PROBE before copy: My careful rename
PROBE after  copy: My careful rename      ← a szerkesztés MEGMARADT
PROBE createCalls = 0                     ← és semmi nem íródott ki
PROBE save locked = true                  ← a Save továbbra is zárolt
PROBE retry visible = 1                   ← az újrapróba elérhető
```

**A cella bukási képessége bizonyítva.** Visszaállítottam a regressziót (az
előzetes validáció kivétele + `await controller.load(id)`), és a kör ÚJ cellája
pirosra váltott:

```
MAJOR-2: a failed copy attempt never discards an edit the user made before saving
Expected: 'My careful rename'
  Actual: 'Legacy Song'
```

Ez tehát valódi őr, nem üres cella — az [L477](../LESSONS.md#l477) mércéje
teljesül.

**Kimondott, őszinte korlát** (a doc-comment rögzíti, NEM elrejtve): a
`SongEditorController` az `application/**` tilos zónában van, és nincs publikus
API-ja a `persisted` visszaállítására a `draft` felülírása nélkül (`load` mindkettőt
állítja). A megmaradó repository-írási hiba ezért képernyő-szintű zárolással
kezelt, nem a controller állapotának helyreállításával. Ez mért korlát, nem
gyengítés — a felhasználó munkája egyik ágon sem vész el.

## 7.2 Zárt leletek összesítve

| Lelet | Állapot | Bizonyíték |
|---|---|---|
| MAJOR-1 (üres A7 cella) | **ZÁRVA** | `32.0` ⇒ PIROS, `null` constraints ⇒ PIROS (saját próba) |
| MAJOR-2 (néma munkavesztés) | **ZÁRVA** | a fenti PROBE + a piros regressziós próba |
| MINOR-1 (per-build validáció) | **ZÁRVA** | `identical`-alapú memoizálás |
| MINOR-2 (`_saveCopy` sorrend) | **ZÁRVA** | előzetes validáció + két cella |
| MINOR-3 (nyers `TextStyle`) | **ZÁRVA** | `textTheme.bodyMedium?.copyWith`, goldenek zöldek |
| NOTE-1/2/3 | nyitva, **nem blokkol** | NOTE-1 → nevesített follow-up (E13-R36) |

## 7.3 Végső mérések a `08b7b13c` HEAD-en

- **Saját gate-futás** (harmadik, friss klón): **20/20 lépés ZÖLD**,
  `MINDEN GATE ZÖLD`, **97 teszt**.
- **Scope-audit:** `Legacy scope audit OK (3b88f75792f8..08b7b13c4081,
  21 changed path(s), 1 generated/ignored)`.
- **Upstream-frissesség:** `git merge-base --is-ancestor origin/main HEAD`
  → exit 0; az `origin/main` változatlanul `3b88f757`.
- **Képernyő-leltár:** 86 → 86, a `ui_inventory_test.dart` diffje ÜRES.

**VÉGSŐ DÖNTÉS: APPROVED.** A merge az exact-SHA CI-kapun (Full Gate + Router
CI, mindkettő `08b7b13c`) múlik.
