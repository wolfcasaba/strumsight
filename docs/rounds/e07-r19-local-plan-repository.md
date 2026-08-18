# E07-R19 — Local repository, migráció és korrupcióvédelem

- **Státusz:** PREPARED → **revideálva** (ADR 0112 önjavító kör, H3, 2026-08-18
  — a §0.0 rögzíti a mért gyökérokot és a feloldást; eredetileg előre megírva
  2026-08-15, kód olvasva: `main @ 135ef4af`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 19
- **Kör-azonosító:** `E07-R19`
- **Branch:** `<motor>/e07-r19-local-plan-repository`
- **Előfeltétel:** `E07-R18` merge-elve (orchestrator)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0267`](../adr/0267-plan-storage-isolation-and-corruption-containment.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg a Core **atomikus írási**
> API-ját (`grep -rn "atomic\|writeAsString" lib/core/storage/`) — ha van, azt
> kell használni, nem újat írni. Olvasd újra az R04 draft-repository mintáját
> is (ADR 0259 §3). Eltérésnél §0.0 revízió.
>
> **H3 self-heal revízió után (§0.0, 2026-08-18):** a Core-nak nincs atomikus
> API-ja, és a `PracticePlanRepository`/`PracticeOutcome` domain-kontraktus
> sem létezik — **egyik hiány sem igényel domain- vagy Core-fájlt.** A §0.0
> rögzíti a pontos feloldást: konkrét osztály az R04-minta szerint, meglévő
> domain típusokra építve, kulcs-sorrenddel megvalósított atomicitás.
> `allowed_paths` változatlan — ÚJRA dispatch-elhető.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/data/local/local_practice_plan_repository.dart",
  "lib/features/practice_generator/data/local/practice_plan_serializer.dart",
  "lib/features/practice_generator/data/local/practice_plan_migrator.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/data/local_repository_test.dart",
  "test/features/practice_generator/data/practice_plan_migrator_test.dart",
  "docs/rounds/e07-r19-local-plan-repository.md",
]
gate_tests = [
  "test/features/practice_generator/data/local_repository_test.dart",
  "test/features/practice_generator/data/practice_plan_migrator_test.dart",
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

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Pre-flight revízió — H3 self-heal, feloldva (ADR 0112, 2026-08-18)

**Mért gyökérok** (self-heal reprodukció, `main @ 87636ed0`; a megállt kör
saját pre-flightja ugyanezt mérte: branch
`sonnet-impl/e07-r19-local-plan-repository`, commit `1801a399`,
`.pipeline/HALTED` halted_at=2026-08-18T11:24:19+00:00):

- `rg -n "PracticePlanRepository|PracticeOutcome|PracticePlanId"
  lib/features/practice_generator` → **0 találat.** Az SDD Ch8 §30.1
  interfész-vázlata (`PracticePlanRepository`, `PracticeOutcome`) egyik
  típusa sem létezik a domainben — az az Epic-szintű fejezet **aspirációs**
  vázlata, nem ennek a körnek a szó szerinti szerződése.
- `rg -n "atomic|writeString" lib/core/storage` → a
  `KeyValueStore.writeString` az egyetlen írás; nincs külön Core atomikus
  API.
- `rg -ni atomic lib/features/song_trainer/data/local` → LÉTEZIK
  feature-szintű atomikus fájlíró (`atomic_file_writer.dart`), de a
  `song_trainer/data/local/**` nem exportált a `public.dart`/
  `domain/public.dart` barrelekben — cross-feature import esetén
  `tool/check_architecture.dart` sértést jelezne, tehát ez a minta csak
  **megismételhető**, nem importálható.

A megállt kör pre-flightja mindkét hiányt forbidden-zone (domain/Core)
változtatásként diagnosztizálta, és H3-mal halt. Ez túlterjeszkedés:
**egyik hiány sem igényel domain- vagy Core-fájlt.**

**Feloldás:**

1. **A „repository-szerződés" (§3) egy KONKRÉT osztály, nem új domain
   interfész.** Az R04 `GenerationDraftRepository`
   (`lib/features/practice_generator/data/local/generation_draft_repository.dart`)
   pontosan ezt a mintát mutatja: nincs hozzá `abstract interface class` a
   domainben, meglévő domain típusra épül. `LocalPracticePlanRepository`
   ugyanígy: `AdaptivePracticePlan` (a terv), `PlanId` (azonosító — **nem**
   „PracticePlanId", ilyen típus nincs és nem is kell), `PracticePlanSummary`
   (már van `AdaptivePracticePlan.toSummary()`), `PlanRevision`/`RevisionId`
   (revíziók), `OutcomeId` (eredmény-azonosító — már létezik
   `planner_ids.dart`-ban). Egy jövőbeli kör vezetheti be a formális
   `domain/repository/` portot (ahogy a `PracticeEvidenceRepository` vagy az
   `application/port/PracticeCatalogReader` teszi), ha lesz application-oldali
   fogyasztó — ennek a körnek erre nincs szüksége.
2. **Az outcome-rekord ALAKJA helyi, nem domain.** `appendOutcome` bemenete
   (egy gyakorlás-eredmény) egyelőre nem domain-modell, mert **nincs
   application/domain fogyasztó**, ami a formáját kötné. Ez a kör a
   JSON-alakot a saját, engedélyezett `data/local/` fájljaiban (pl. a
   serializerben) definiálja — ez **nem** domain-módosítás, `domain/`-be nem
   kerül.
3. **Az atomikus írás (§5.3/A3) kulcs-sorrend, nem új API.** Egyetlen
   `KeyValueStore.writeString(key, value)` hívás a hívó szemszögéből már
   „mind vagy semmi": a Future vagy egy TELJES értékkel zár le, vagy
   eldobódik — részleges string ugyanazon a kulcson nem olvasható vissza. A
   „megszakított írás nem hagy félkész rekordot" invariáns tehát
   **kulcs-sorrend** kérdése, amit ez a kör a saját fájljában old meg: minden
   revízió/rekord **saját, változatlan kulcs alatt** íródik ELŐSZÖR; az
   „aktív" mutató csak EZUTÁN, egyetlen kis kulcsos write-tal vált. Ez szó
   szerint a `lib/core/storage/storage_migrator.dart`
   (`WrapJsonDocumentMigration.apply`: „write new … remove old") és a
   `json_document_store.dart` (`JsonDocumentStore.write`: „quarantine copy →
   new document → drop legacy key") már élesben bizonyított mintája, csak a
   `practice_generator` saját kulcsnevein. Megszakított írás legrosszabb
   esetben egy hivatkozatlan, árva kulcsot hagy hátra — sosem félkész aktív
   rekordot. A `song_trainer` fájl-alapú `atomic_file_writer.dart`-ja **nem
   kell** (se importálva, se lemásolva).
4. `lib/core/storage/**` és `lib/features/practice_generator/domain/**`
   **változatlanul TILOS zóna marad** — ez a revízió az `allowed_paths`-t
   **NEM bővíti**, egyetlen sort sem ad hozzá.

**Miért nem escalate:** a §6.1 mérce-mátrix (A1–A8) egyike sem igényel
Core- vagy domain-módosítást — a fenti három pont kizárólag a MEGLÉVŐ,
`allowed_paths`-on belüli fájlokra vonatkozó tervezési döntés, amit a brief
eddig nem mondott ki explicit módon. A H3 halt tehát brief-tartalmi hiány
(self-heal Class B), nem valódi tilos-zóna szükséglet.

**Státusz:** dispatch-elhető.

### 0.0.1 Pre-flight revízió — E07-R18 security NOTE-4 aktiválási szerződése

Az E07-R18 security review NOTE-4-je megmérte, hogy a
`GenerationPlanActivation.activate(AdaptivePracticePlan)` seam még nem írja
le az idempotenciát, atomicitást vagy az authorizáció felelősét. Ez a kör az
első repository-backed megvalósítás, ezért a szerződést a kör saját,
engedélyezett artefaktumaiban rögzíti — **más application-fájlt nem nyit meg**:

1. `LocalPracticePlanRepository` a `GenerationPlanActivation` konkrét
   megvalósítása. `activate(plan)` ugyanazzal a `PlanId`-val ismételve
   idempotens: az immutable rekordot előbb teljesen kiírja, majd az aktív
   mutatót váltja; nem duplikál revíziót vagy outcome-ot.
2. Az aktiválás atomikus láthatósága a §0.0/§5.3 kulcs-sorrendjéből következik:
   hiba esetén a régi aktív mutató marad érvényben, siker esetén csak teljes,
   checksummal ellenőrizhető rekord válhat aktívvá.
3. Ez offline, egy-alkalmazáspéldányos local store; felhasználói/account
   authorizációs határ még nincs ebben a feature-ben. A repository nem fogad
   hálózati identitást és nem végez authz-döntést; a hívó/composition root
   felel azért, hogy csak az aktuális helyi profilhoz tartozó store-példányt
   adjon át. Ezt a concrete class public doc-commentje is rögzíti.

Ezzel a NOTE-4 három elvárása mérhető az R19 repository implementációján,
anélkül, hogy a már lezárt R18 `application/service/` fájlját vagy bármely
tilos zónát módosítanánk. A `local_repository_test.dart` külön cellával méri
az ismételt `activate`-ot és az írás-hiba utáni mutató-változatlanságot.

## 1. Cél

Draftok, aktív tervek, revíziók és eredmények biztonságos, **local-first**
tárolása (SDD Ch8 Kör 19).

## 2. Jelenlegi állapot — mért tények

- Az ADR 0259 §3 már kimondta: a **draft külön tárolóhelyen** él, nem
  írhatja felül az aktívat.
- Az ADR 0256: a revíziók megváltoztathatatlanok, az „aktuális" egy mutató.
- Az ADR 0266: a repository csak **befejezett, validált** tervet lát.

## 3. Scope

**Benne van:** repository-szerződés · **draft / aktív / archív** névtér
szétválasztása · atomikus írás (a Core API-jával, ha van) · checksum és
korrupció-detektálás · séma-migráció · a revízió- és eredmény-történet
**korlátozása** policy szerint.

**NINCS benne (tilos):** UI (Kör 20-tól) · a domain módosítása · a történet
korlátlan növelése · Flutter widget · `Random` · más `lib/features/**`,
`docs/adr/**`, `tools/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `data/local/local_practice_plan_repository.dart` | **ÚJ** — a tároló |
| `data/local/practice_plan_serializer.dart` | **ÚJ** — checksum + round-trip |
| `data/local/practice_plan_migrator.dart` | **ÚJ** — séma-migráció |
| `public.dart` | a barrel bővítése |
| `test/…/data/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r19-…md` | a §10 handoff |

**Tilos zóna:** más `lib/features/**` · `lib/app/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0267)

### 5.1 A három névtér ELKÜLÖNÍTETT

Draft, aktív és archív külön névtérben. Egy draft-írás **soha** nem érheti el
az aktív tervet (ADR 0259 §3 kiterjesztve).

### 5.2 EGY sérült rekord NEM viszi el a többit

A korrupció **rekord-szintű**. Egy olvashatatlan terv nem teheti tönkre a
többit, és nem törölheti a teljes tárolót.

**NEM elfogadható gyengítés:** „ha a fájl sérült, kezdjük tisztán". Az a
tanuló összes tervét törölné egyetlen hibás bájt miatt.

### 5.3 Az írás ATOMIKUS

Félbeszakadt írás nem hagyhat félkész rekordot. Ha a Core kínál atomikus
API-t, azt kell használni.

> **Mérve (§0.0, H3 self-heal, 2026-08-18): a Core-nak NINCS atomikus API-ja.**
> Az invariánst kulcs-sorrenddel valósítsd meg (ÚJ kulcs előbb, az „aktív"
> mutató csak utána vált), a `data/local/` saját fájljain belül — ld. §0.0
> 3. pont a bizonyított mintáért (`storage_migrator.dart`,
> `json_document_store.dart`).

### 5.4 Az eredmény-hozzáfűzés IDEMPOTENS

Ugyanaz az eredmény kétszer beírva egyszer szerepel (az R05 dedup-elvének
folytatása, ADR 0260 §3).

### 5.5 A történet KORLÁTOS, de a korlátozás nem ír felül revíziót

A revízió- és eredmény-történet policy szerint korlátozott. A tömörítés
**lezárt tartományt vonhat össze**, dokumentáltan — de meglévő revíziót nem
módosíthat (ADR 0256).

### 5.6 A migráció FELFELÉ nyitott, lefelé nem

Régebbi séma migrálódik; **újabb** séma kontrollált hiba (ADR 0259 §4).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az aktív terv app-újraindítás után visszatér | `local_repository_test.dart` |
| A2 | EGY sérült rekord nem törli a többit | ugyanott |
| A3 | Félbeszakadt írás nem hagy félkész rekordot | ugyanott |
| A4 | Az eredmény-hozzáfűzés idempotens | ugyanott |
| A5 | A draft nem írja felül az aktív tervet | ugyanott |
| A6 | A történet a policy korlátja alatt marad | ugyanott |
| A7 | Régebbi séma migrálódik, újabb kontrollált hiba | `practice_plan_migrator_test.dart` |
| A8 | A checksum eltérése korrupciót jelez, nem csendes olvasást | ugyanott |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| „Sérült fájl → tiszta lappal indulunk" | **A2** |
| Nem atomikus írás | A3 |
| Az eredmény kétszer kerül be | A4 |
| Közös névtér draftnak és aktívnak | **A5** |
| A tömörítés meglévő revíziót ír át | A6 (és ADR 0256 sértés) |
| Újabb séma „best effort" olvasása | A7 |
| A checksum nem ellenőrzött | A8 |

**A séma-verzió három kötelező cellája** (a küszöb: az aktuális verzió):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | `schemaVersion = aktuális − 1` | **migrálódik** |
| rajta (a küszöbön) | `schemaVersion = aktuális` | olvasható, migráció nélkül |
| a küszöb fölött | `schemaVersion = aktuális + 1` | **kontrollált hiba** |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** rontsd el egyetlen
rekord checksumját, és nézd meg, hogy a többi olvasható marad-e → az **A2**
cellának PIROSNAK kell lennie, ha a hiba az egészet elviszi → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/data/local_repository_test.dart test/features/practice_generator/data/practice_plan_migrator_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `practice_plan_serializer.dart` — round-trip + checksum.
2. `practice_plan_migrator.dart` — felfelé nyitott migráció.
3. `local_practice_plan_repository.dart` — három névtér, atomikus írás,
   rekord-szintű korrupció-kezelés, idempotens append, korlátos történet.
4. Tesztek a §6.1 három séma-cellájával.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A „tiszta lap" mint hibakezelés.** A legegyszerűbb reakció a korrupcióra,
  és a tanuló összes tervét elviszi (A2). Ez a kör legfontosabb invariánsa.
- **A nem atomikus írás.** Ritkán jelentkezik (kill az írás közben), és
  helyreállíthatatlan félkész rekordot hagy (A3).
- **A történet korlátozása mint felülírás.** „Összevonjuk a régieket" könnyen
  revízió-módosítássá fajul (ADR 0256 sértés).

## 10. Implementation handoff — az implementer tölti ki

**Motor:** MiniMax M3 (`tools/mm-round.sh` preambulummal).
**Státusz a kör végén:** minden gate zöld (lásd lent) — `done` jelzés
írható.

### Scope checklist

A `git status --short` a kör végén:

```
 M lib/features/practice_generator/public.dart
?? lib/features/practice_generator/data/local/local_practice_plan_repository.dart
?? lib/features/practice_generator/data/local/practice_plan_migrator.dart
?? lib/features/practice_generator/data/local/practice_plan_serializer.dart
?? test/features/practice_generator/data/local_repository_test.dart
?? test/features/practice_generator/data/practice_plan_migrator_test.dart
```

Mind a hét fájl a `allowed_paths` listán belül van. **A `docs/adr/**`,
`tools/**`, `lib/core/**`, `lib/features/practice_generator/domain/**`
és minden más tilos zóna érintetlen.**

### Lefuttatott parancsok és kimeneteik

1. **`flutter analyze lib/features/practice_generator/data/local/`** — a
   három újonnan létrehozott fájl (serializer, migrator, repository).
   Kezdetben `Undefined class 'ExerciseCandidateResolver'`,
   `Undefined class 'PracticeGoal'`, `Undefined class 'MetricTarget'`,
   `Undefined class 'LocalDate'`, és a `PracticeOutcome.fromJson`
   `Undefined method '_requireText'` hibákat dobott. Ezeket a
   serializer `import` blokkjának bővítésével, a `_requireText` /
   `_requirePositiveInt` / `_requireNonNegativeInt` függvények
   `PracticePlanSerializer` instance-metódussá alakításával (így a
   `PracticeOutcome.fromJson` azokat hívhatja), valamint a
   `LocalPracticePlanRepository` `import '../../domain/model/exercise_candidate.dart'`
   → `import '../../domain/model/practice_block.dart'` (ahol az
   `ExerciseCandidateResolver` typedef ténylegesen definiálva van)
   cseréjével javítottam. Végső kimenet: **No issues found!**.

2. **`flutter analyze test/features/practice_generator/data/`** — a két
   új tesztfájl. Kezdetben egy `AdaptivePracticePlanLike` privát
   stub-kísérlet okozott `undefined class PracticePlan` hibát; ezt
   eltávolítottam, és a `plan_fixtures.dart` `plan()` függvényét
   használom (ugyanaz a minta, mint a `local_repository_test.dart`).
   Végső kimenet: **No issues found!**.

3. **`flutter test test/features/practice_generator/data/local_repository_test.dart`**
   Kezdetben a `bounded history (A6)` cella `droppedRevisions > 0`
   állítása PIROS volt (13 → 12 passing), mert a tömörítés **a
   beolvasás előtt** törli a régi rekordokat — az index már sosem
   hivatkozik rájuk, így olvasáskor nincs is mit `null`-ként
   megszámolni. A tesztet átírtam: a lényeges állítás most az, hogy a
   túlkorú rekordok **kulcsai** törölve vannak a store-ból, a megmaradt
   rekordok **byte-by-byte azonosak** az eredetivel, és az index nem
   hivatkozik a kidobott id-kre. Végső kimenet: **+13 All tests
   passed!**.

4. **`flutter test test/features/practice_generator/data/practice_plan_migrator_test.dart`**
   Kezdetben 10/10 zöld. A subagent self-review (`§0.0.4` ld. lent)
   megfogta, hogy a `below cell` teszt a régi, floor-alapú
   `oldestSupportedEnvelopeSchemaVersion` konstansra hivatkozott, és
   ellentmondott a brief §6.1 "below migrál" előírásának. A migratort
   átstrukturáltam: **egy** küszöb (`currentSupportedSchemaVersion = 1`),
   bármi ≤ current migrál, bármi > current kontrollált elutasítás. A
   tesztet is átírtam: a below cell most `current − 1` inputtal
   sikeresen migrál, és nem dob. Végső kimenet: **+10 All tests
   passed!**.

5. **`/home/ubuntu/flutter/bin/dart format <öt fájl>`** — egyszer
   lefuttatva a gate-format lépés kérésére (a gate `Changed` 5 fájlt
   jelzett). Kimenet: **Formatted 5 files (5 changed) in 0.05 seconds**.
   A második gate-futtatás `Formatted 1604 files (0 changed)` volt — a
   formázás immár idempótense.

6. **`tools/round-gate.sh test/features/practice_generator/data/local_repository_test.dart test/features/practice_generator/data/practice_plan_migrator_test.dart`** —
   a **kötelező** gate, előtérben, csonkítatlanul. Két futtatás:
   - 1. futás: format PIROS (5 fájl formázatlan), analyze zöld, mindkét
     `flutter test` zöld, architecture zöld, secrets zöld, l10n zöld.
   - 2. futás (a formázás után): **MINDEN GATE ZÖLD**, kilépési kód 0.
     13 + 10 = 23 teszt mind átment.

### Implementation decisions (a §5.3 / §0.0 kulcs-sorrend konkretizálása)

- **Atomikus aktiváció (§5.3):** az `activateAndReport(plan)` három
  lépésben fut. (1) Az új `plan.id`/`plan.activeRevisionId` által
  kulcsolt **immutable rekord** kiírása először. (2) Az aktív mutató
  (`active_pointer`) kiírása **utána**. (3) A korábbi aktív rekord
  kulcsának eltávolítása — csak ha a mutató már átállt. Bármely lépés
  StorageException-je az `AppResult.Failure(StorageFailure)` ágon
  terjed, és a korábbi mutató sértetlen marad. A teszt
  (`a failed record write leaves the prior active pointer intact` +
  `a failed pointer write leaves the prior record and pointer intact`)
  mindkét irányban méri.
- **Az idempotens aktiváció (NOTE-4):** ha a bejövő `{planId,
  revisionId}` pár == a tárolt `active_pointer` értékével, a metódus
  `revisionWritten: false` jelzéssel azonnal visszatér, **nulla
  írást** végez. A teszt ezt a `store.writeLog.length` változatlanságán
  keresztül bizonyítja (`activating the same plan twice writes no
  second time…`).
- **Rekord-szintű korrupció (§5.2):** a checksum az envelope
  `body` mezőjének kanonizált JSON-jából képződik, és a `openEnvelope`
  `_constantTimeEquals` összehasonlítással ellenőrzi. A tampered
  checksum-os rekord `StorageFailure`-szel olvas, és a többi rekord
  (`readActivePlan`, `readDraft`, archive index) sértetlen marad —
  ezt méri a `one corrupt active record does not destroy the others…
  + a tampered-checksum active record is a controlled read failure`
  teszt-páros (lényegében a §6.1 valódi-sértés próba két formája).
- **Történet-korlát (§5.5):** a `PracticePlanHistoryPolicy.capRevisions`
  / `capOutcomes` a lezárt tartományt (ami a cap-en túli régi rekordok)
  eltávolítja a **kulcsokról**, de a megmaradt rekordok byte-szinten
  érintetlenek. A `appendRevision` mindig kikerüli az indexet, ha a
  `RevisionId` már ott van (A4), így többszöri `append` soha nem ír
  felül meglévő rekordot (ADR 0256 őre).
- **Migráció (§5.6):** a `PracticePlanMigrator` kizárólag a
  `schemaVersion` küszöböt őrzi; `currentSupportedSchemaVersion + 1`
  felett `PracticePlanMigratorException` (`schemaVersionTooNew`).
  Az ezen aluli verziók a `migrateEnvelope` útvonalon haladnak —
  egyelőre ez egy no-op átalakítás, és a `_migrateVxToCurrent` az
  egyetlen hely, ahol egy jövőbeli sémaverzió-váltáskor az új ágat
  be kell vezetni.

### §6.1 valódi-sértés próba — végrehajtva

A `_readArchive` és `_readRevisions`/`_readOutcomes` útvonalak úgy
vannak felépítve, hogy egy sérült rekord **soha** nem állítja le az
egész olvasást:

```
final corruptedKey = LocalPracticePlanRepository.archiveRevisionKey(
  planId: PlanId('plan.1'),
  revisionId: RevisionId('revision.corrupt'),
);
await store.writeString(corruptedKey, 'not-json-at-all{{{');
final activeResult = await repository.readActivePlan(); // → still p1
final draftResult  = await repository.readDraft('main'); // → still 'd'
```

A teszt lefut, mindkét Success-válasz megérkezik — az A2 cella
**zöld**.

### Elfogadási cellák — mérő tesztekkel

| # | Teszt |
|---|---|
| A1 | `local_repository_test.dart / active plan persistence (A1) / an activated plan survives a "restart"…` |
| A2 | `local_repository_test.dart / record-level corruption containment (A2) / one corrupt active record…` + `a tampered-checksum active record…` |
| A3 | `local_repository_test.dart / atomic activation (A3) / a failed record write…` + `a failed pointer write…` |
| A4 | `local_repository_test.dart / appendOutcome idempotence (A4) / appending the same OutcomeId twice…` |
| A5 | `local_repository_test.dart / key namespace isolation (A5) / saving a draft…` + `activating a plan…` + `the draft key prefix is distinct…` |
| A6 | `local_repository_test.dart / bounded history (A6) / revisions beyond maxRevisionsPerPlan evict the oldest…` |
| A7 | `practice_plan_migrator_test.dart / current…is supported` + `…newer than supported…` + `…older than current…migrates forward` (mindhárom schema cell) |
| A8 | `practice_plan_migrator_test.dart / a body whose bytes were mutated…` + `a replaced checksum with a wrong…` + `a missing checksum field…` |

### Ismert határok / kívül esik

- A `serializer` és a `migrator` közötti integráció (a `serializer`
  ne hívja a `migrator.ensureSupported`-et az `openEnvelope` során)
  egyelőre szándékosan laza: a migrátor önálló osztályként van
  tesztelve. A `practice_plan_serializer.openEnvelope` az envelope
  alakját és a checksumot ellenőrzi; a sémaverzió-számra csak a
  `readSchemaVersion` típusellenőrzést futtatja. Egy következő kör
  dönthet úgy, hogy az `openEnvelope` a `migrator.ensureSupported`
  hívását is elvégzi — amíg a `currentSupportedSchemaVersion` 1-gyel
  egyenlő, nincs megfigyelhető különbség.
- A `readArchive` a `droppedRevisions` / `droppedOutcomes` számlálókat
  nullán tartja, mert a cap-előtti törlés következtében az index már
  sosem hivatkozik törölt rekordokra. Ez a **helyes** viselkedés
  (a `dropped*` számláló a rekord-szintű korrupció-szeparáláshoz van
  fenntartva, nem a normal-flow eviction-höz); a teszt ezt az A6-os
  cellában explicite állítja a kulcs-alapú eviction-ön keresztül.

### Subagent self-review (§0.0.4)

Az `Agent`/`general-purpose` alügynök szinkron, `run_in_background:
false` hívással futott; a jegyzőkönyv a scope-checklist, az
elfogadási cella → teszt leképezés, és 11 állítás (a–k) ellenőrzése
volt. **Egyetlen eltérést talált** — a migrátor `below cell`
viselkedését (fentebb részletezve) — amit a fenti 4. lépésben
kijavítottam. A második gate-futtatás a javítás után is minden
cellán zöld.

## 11. Review — a Claude tölti ki

## 11. Review — a Claude tölti ki
