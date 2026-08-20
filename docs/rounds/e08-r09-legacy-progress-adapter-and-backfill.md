# E08-R09 — Legacy progress adapter és activity backfill

- **Státusz:** PREPARED → **revideálva** (ADR 0112 önjavító kör, H3, 2026-08-20 — §0.0; előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 9
- **Kör-azonosító:** `E08-R09`
- **Branch:** `<motor>/e08-r09-legacy-progress-adapter-and-backfill`
- **Előfeltétel:** `E08-R08` merge-elve (gamification repository)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0307` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/progress/model/practice_entry.dart` TÉNYLEGES mezőit (86 sor) és a `lib/features/progress/data/practice_log_repository.dart`-ot — a determinisztikus legacy azonosító ezekből képződik. Ellenőrizd a `docs/baseline/epic-08-start.md` (R01) kulcslistáját is. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/data/gamification_storage_schema.dart",
  "lib/features/gamification/data/migration/legacy_practice_adapter.dart",
  "lib/features/gamification/data/migration/gamification_migrator.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/data/legacy_practice_migration_test.dart",
  "docs/rounds/e08-r09-legacy-progress-adapter-and-backfill.md",
]
gate_tests = [
  "test/features/gamification/data/legacy_practice_migration_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 0.0 Self-heal pre-flight revízió (ADR 0112 önjavító kör, 2026-08-20, halt H3)

Az első dispatch (implementer `terra`) H3-mal állt meg, MODELLHÍVÁS ELŐTT — a
saját pre-flightja mérte, hogy a §5.3 kötött döntés (migráció
**ellenőrzőponttal**, A5: „Félbeszakadt migráció az ellenőrzőponttól
folytatódik, nem elölről") és a §6.1 küszöb-hármas nem valósítható meg a mai
`GamificationMigrationState` alakjával. Mérve (`main @ 71512fff`, a self-heal
saját reprodukciója):

```
nl -ba lib/features/gamification/data/gamification_storage_schema.dart | sed -n '121,135p'
#   121  /// Versioned placeholder for the migration state contract owned by R09/R10.
#   122  final class GamificationMigrationState {
#   123    const GamificationMigrationState()
#   124      : schemaVersion = gamificationStorageSchemaVersion;
#   126    final int schemaVersion;
#   ...    -- nincs más mező, a checkpoint számára nincs hely
```

Ez nem implementer-hiba: az `ADR 0344` (E08-R08, elfogadva 2026-08-20) D7
pontja **explicit** ezt a kört (R09/R10) jelöli ki a tényleges migrációs
mezők forrásaként — „A tényleges migrációs mezőket a Kör 9/10 ... tölti ki"
—, miközben az E08-R08 brief `lib/core/**`-t tiltotta, a mai `allowed_paths`
pedig `lib/features/gamification/data/gamification_storage_schema.dart`-ot
egyáltalán nem sorolta fel. A gyökérok tehát Class B: a kör-tartalom (ADR
0344 D7 + a brief §5.3/A5 kötött döntése) ellentmond a saját
`allowed_paths` listájának — a fájl, amit a §5.3 megkövetel, nincs
engedélyezve.

**Feloldás — szűk bővítés, egyetlen fájl.** `allowed_paths` a
`gamification_storage_schema.dart`-tal bővült. A bővítés NEM ad új
architekturális szabadságot: az implementer ebben a fájlban **kizárólag** a
`GamificationMigrationState` osztályt bővítheti a checkpoint mezőjével/
mezőivel (pl. egy monoton `processedCount`/`checkpoint` index) — a másik
három dokumentum (`GamificationProfileSnapshot`, `GamificationCatalogVersion`,
`GamificationInboxItem`), a `GamificationStorageKeys` kulcslista (A8: négy
kulcs, változatlanul) és a `migrationStateMaxBytes` korlát NEM módosul.

**Kötelező visszafelé-kompatibilitási korlát (nem tárgyalható).** A már
merge-elt `test/features/gamification/data/gamification_repository_test.dart`
NINCS ezen a listán (R08 tulajdona, ma zöld, ebben a körben TILOS zóna
marad) és **A3 cellája** `const migration = GamificationMigrationState();`
nulla-argumentumos konstrukciót vár el, amit a séma után is visszaolvashatóvá
kell tenni. Az új mező(k)nek ezért **alapértelmezett értékkel** kell
rendelkezniük a const konstruktorban (pl. `this.processedCount = 0`), hogy ez
a zéró-argumentumos hívás és az A3 round-trip változatlanul zöld maradjon —
ha ez a korlát a §5.3 megvalósítását ellehetetlenítené, az `stopped`/
`escalate`, nem a R08 teszt átírása.

**Visszakeresett előzmény (S8, `.pipeline/brief-lint-E08-R09.md`, a self-heal
zárja le).** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5
"gamification migration checkpoint allowed_paths schema placeholder"` a repó
saját precedensét adja: [`ADR 0117`](../adr/0117-song-storage-migrator-boundary.md)
Döntés 2 (E03-R08, dalfájl-migráció) már eldöntötte, hogy egy migrációs
checkpoint **saját, verziózott JSON-dokumentumként** él, a meglévő
atomikus-írás infrastruktúrán (ott `AtomicFileWriter`, itt
`JsonDocumentStore.write()`) — ugyanaz a forma, amit ez a revízió a
`GamificationMigrationState` bővítésével követ, nem egy új tárolási
primitív. [`ADR 0328`](../adr/0328-measured-gamification-baseline-contract.md)
(E08-R01) a jelen epic saját, mért migrációs-adatvesztés elleni fegyelmét
rögzíti — ez a revízió nem ír felül belőle semmit, csak a §5.3/A5-öt teszi
megvalósíthatóvá a már kijelölt ADR 0344 D7 nyomvonalon.

Regressziós védelem:
`tools/tests/test_e08_r09_migration_state_schema_scope.py` — a valódi mért
halt-útvonalat futtatja `audit_legacy_scope()`-on a ténylegesen committolt
brief ellen, bizonyítva, hogy a mért útvonal az új listával belül van, egy
szomszédos, ugyanabban a könyvtárban élő fájl (`gamification_repository.dart`,
a repository-interfész — ezt a kört NEM érinti) viszont továbbra is kívül
marad — a bővítés egy fájl, nem az egész `data/` könyvtár.

Az eredeti E08-R09 dispatch modellhívás nélkül állt meg (nincs félkész
munkapéldány, nincs commit, nincs nyitott PR) — ez a self-heal nem visz
tovább tartalmi migrációs munkát, a friss dispatch a felfrissített
`allowed_paths`-szal indul újra.

## 1. Cél

A meglévő `PracticeEntry` előzmény használhatóvá tétele az új rendszerben — **dupla
jutalom nélkül** és **idempotensen**, akárhányszor fut le a migráció.

## 2. Jelenlegi állapot — mért tények

- `lib/features/progress/model/practice_entry.dart` (86 sor) a legacy rekord; a napló kulcsa `ss.progress.practice_log`, legacy párja `practice_log_v1`.
- `test/features/progress/practice_log_race_test.dart` MA is őrzi a napló versenyhelyzetét — ez a teszt nem írható át.
- Az R03 főkönyve `sourceEventId`-re dedupál; az R08 tárolja a migrációs állapotot.
- A legacy rekordoknak **nincs** stabil eseményazonosítójuk — ezt ez a kör származtatja determinisztikusan.

## 3. Scope

**Benne van:** determinisztikus legacy esemény-azonosító a régi `PracticeEntry` rekordokhoz · a live /
analyze / learn források leképezése `ActivitySource` értékekre · a backfill mint **történeti
statisztika és profil-alapvonal** · a visszamenőleges XP kérdésének eldöntése (a §5.2 kimondja:
**nulla retroaktív XP**) · a jövőbeli események nem duplikálódnak újrafuttatáskor · migrációs
ellenőrzőpont.

**NINCS benne (tilos):**

- A legacy `progress` feature bármely fájljának módosítása — a régi rendszer tovább él.
- A `practice_log_race_test.dart` vagy bármely meglévő teszt átírása.
- Streak-migráció (Kör 10), UI, hálózat.
- `docs/adr/**` — az ADR 0307-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/data/migration/legacy_practice_adapter.dart` | **ÚJ** — a legacy → kanonikus esemény leképezés |
| `lib/features/gamification/data/migration/gamification_migrator.dart` | **ÚJ** — a vezérlő, ellenőrzőponttal |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `test/features/gamification/data/legacy_practice_migration_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**` · `lib/features/progress/**` (a legacy rendszer ÉRINTETLEN)

## 5. Kötött architekturális döntések (ADR 0307)

### 5.1 A legacy azonosító DETERMINISZTIKUS — a rekord tartalmából

Az azonosító a legacy rekord stabil mezőiből (időbélyeg + forrás + időtartam)
képződik, tiszta függvényként. Ugyanaz a rekord újrafuttatáskor UGYANAZT az azonosítót adja,
és az R03 dedupja emiatt tud dolgozni.

**NEM elfogadható gyengítés:** növekvő sorszám vagy `Random`/`UUID v4` azonosító. A migráció
második futása ekkor minden rekordot duplikálna.

### 5.2 NULLA retroaktív XP — a backfill statisztikát épít, nem jutalmat

Az SDD Ch9 Kör 9 §4 az ADR-re bízza a döntést; ez a brief **kimondja**: a
visszamenőleges gyakorlás **nem** ad XP-t. Indok: a régi rekordok nem mentek át az R05
jogosultsági kapuin (nincs trust-szint, nincs jelminőség), ezért a retroaktív XP
ellenőrizetlen forrásból származna — és az ADR 0289 szerint az XP amúgy sem elsajátítottság.
A régi előzmény **statisztikaként és profil-alapvonalként** megmarad és látszik.

**NEM elfogadható gyengítés:** „egyszeri, korlátozott” retroaktív juttatás. Az is
ellenőrizetlen forrás, csak kisebb — és a főkönyv auditálhatóságát rontja.

### 5.3 A migráció IDEMPOTENS, ellenőrzőponttal

A migrátor rögzíti, meddig jutott. Az újrafuttatás nem dolgozza fel újra a már
feldolgozott rekordokat, és félbeszakadás után onnan folytatja, ahol abbahagyta.

### 5.4 A legacy rendszer ÉRINTETLEN marad

A `lib/features/progress/**` egyetlen fájlja sem módosul. A migráció **olvas**.
A régi képernyők és tesztek változatlanul működnek — ez acceptance-cella (A6).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A legacy azonosító determinisztikus: ugyanaz a rekord kétszer UGYANAZT az azonosítót adja | `legacy_practice_migration_test.dart` |
| A2 | A migráció kétszeri futtatása után a főkönyv bejegyzés-száma VÁLTOZATLAN | `legacy_practice_migration_test.dart` — idempotencia-cella |
| A3 | A backfill **nulla XP-t** ad a régi rekordokra; a statisztika mégis megjelenik | `legacy_practice_migration_test.dart` |
| A4 | A live / analyze / learn források helyes `ActivitySource` értékre képződnek | `legacy_practice_migration_test.dart` — forrás-mátrix |
| A5 | Félbeszakadt migráció az ellenőrzőponttól folytatódik, nem elölről | `legacy_practice_migration_test.dart` |
| A6 | A `lib/features/progress/**` ÉRINTETLEN | `git diff --stat` |
| A7 | A migráció után beérkező ÚJ esemény normálisan kap XP-t (a nulla-XP csak a backfillre vonatkozik) | `legacy_practice_migration_test.dart` |
| A8 | A régi gyakorlási előzmény egyetlen rekordja sem vész el | `legacy_practice_migration_test.dart` — darabszám-egyezés |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az azonosító növekvő sorszámból | **A1** és **A2** (a második futás duplikál) |
| A backfill retroaktív XP-t ad | **A3** |
| A migrátor nem ír ellenőrzőpontot | **A5** (a félbeszakadás után elölről kezd) |
| A migráció „rendbe teszi” a legacy naplót | **A6** (`git diff --stat` `progress/` útvonalat mutat) |
| A nulla-XP szabály az ÚJ eseményekre is érvényes | **A7** |
| A leképezés egy forrást kihagy | **A4** (a forrás-mátrix sora) |

**A küszöb három kötelező cellája** (a migrációs ellenőrzőpont (`checkpoint`) — meddig jutott a feldolgozás):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | a rekord indexe `checkpoint` ALATT van | **már feldolgozva** — újrafuttatáskor kihagyva |
| **rajta** (a küszöbön) | a rekord indexe pontosan `checkpoint` | **a következő feldolgozandó** — az ellenőrzőpont az ELSŐ FEL NEM DOLGOZOTT elemre mutat (exkluzív felső határ) |
| a küszöb **fölött** | a rekord indexe `checkpoint` FÖLÖTT | még feldolgozandó |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld a determinisztikus azonosítót növekvő sorszámra, futtasd a gate-et → az
**A2** (idempotencia) cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/data/legacy_practice_migration_test.dart
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. A determinisztikus legacy azonosító tiszta függvénye (a rekord stabil mezőiből).
2. `legacy_practice_adapter.dart` — a legacy → kanonikus esemény leképezés, forrásonként.
3. `gamification_migrator.dart` — ellenőrzőpontos, idempotens vezérlő.
4. A nulla-retroaktív-XP szabály érvényesítése (a backfill statisztikát épít).
5. A profil-alapvonal előállítása a backfillből.
6. A `public.dart` export-sorai.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A nem determinisztikus azonosító.** Az első futáson láthatatlan; a másodikon megduplázza a felhasználó teljes előzményét (A1/A2).
- **A „kis retroaktív jutalom” kompromisszum.** Jóindulatú, és ellenőrizetlen forrásból tölti fel a főkönyvet, rontva annak auditálhatóságát (A3).
- **A legacy „rendbetétele”.** A migráció közben látszó adósságok javítása scope-sértés, és a `progress` feature meglévő tesztjeit kockáztatja (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
