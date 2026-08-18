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

## 11. Review — a Claude tölti ki
