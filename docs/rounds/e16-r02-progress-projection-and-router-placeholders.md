# E16-R02 — A Progress V2 bekötése és a router placeholder-mentesítése

- **Státusz:** PREPARED (előre megírva 2026-09-02, kód olvasva: `main @ 11d0d2bb`)
- **Típus:** Chapter 16 (Kompozíció és rollout), Kör 2
- **Kör-azonosító:** `E16-R02`
- **Branch:** `<motor>/e16-r02-progress-projection-and-router-placeholders`
- **Előfeltétel:** `E16-R01` merge-elve (a gamification kompozíció mintája és a router-diff ott készül el)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0491` — a szám FOGLALT (Chapter 16 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "progress projection dashboard skill detail unreachable screen wiring"` → az `E15-R03` saját mérése (`docs/ui/retirement-plan.md`): „progress_v2 is NOT wired into the router — `/profile/progress` still builds the legacy `ProgressScreen` (app_router.dart:528)", és **[ADR 0353](../adr/0353-caller-fed-compassionate-streak-v2-presentation.md)** (hívó-adta prezentáció). A kör ezt a MÉRT holt ágat élesíti.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd újra, hogy a `/profile/progress` route MÉG a legacy `ProgressScreen`-t építi-e, és hogy a `ProgressOverviewProjection` / `SkillDetailProjection` típusokra a `lib/features/progress_v2/`-n KÍVÜL még mindig **0** hivatkozás van-e.

## 0.0.H Módosítás (ADR 0112 önjavító kör, 2026-09-03) — a hiányzó mastery-forrás a kör RÉSZE lett

Az eredeti brief a `main @ 11d0d2bb` fán készült, és a §2 azt állította, hogy a
projekció mastery-oldalának forrása a gamification-profil és a ledger. A kör
pre-flightja ezt MEGCÁFOLTA (H3 halt, `.pipeline/halt-detail-E16-R02.md`), és az
önjavító kör a mérést újra elvégezte (`main @ 619232dd`):

| Mért parancs | Eredmény |
|---|---|
| `grep -rn "MasteryMilestone(" --include=*.dart lib test` | 9 hely: 1 definíciós fájl + 8 TESZT — produkciós katalógus **0** |
| `grep -rn "List<MasteryMilestone>\|milestoneCatalog\|masteryCatalog" --include=*.dart lib` | **0 találat** |
| `grep -rln "MasteryEvidence" --include=*.dart lib` | 4 fájl (2 domain, 1 evaluator, 2 progress_v2) — **egyetlen `data/` előállító sem** |
| `grep -o '"[a-zA-Z0-9]*"' lib/l10n/app_en.arb \| grep -i "mastery\|milestone"` | 3 kulcs, mind chrome — **0 milestone-cím/leírás** |

**A hibamód, amit az EREDETI A1–A7 cella NEM fogott volna meg.** Üres
`milestones` listával a `ProgressOverviewProjection.isNewUser` **igaz**
(`[].every(...)` → `true`, `progress_overview_projection.dart:65`), tehát a
`ProgressDashboardScreen` KIZÁRÓLAG a `_NewUserState`-et rendereli
(`progress_dashboard_screen.dart:38`) — a `/profile/progress` átkötése a MA
valós adatot mutató legacy `ProgressScreen`-t (`app_router.dart:545`) egy
ÖRÖKRE üres „get started" képernyőre cserélte volna, miközben minden cella zöld
marad, mert közvetlenül eteti a projekciót (L397/L449 hibaosztály).

**Az önjavítás döntése:** nem a cellákat gyengítjük és nem halasztjuk a
route-váltást — a hiányzó FORRÁST tesszük a kör részévé. Az `allowed_paths`
három darabbal bővül (mastery-katalógus, practice→evidence adapter,
milestone-l10n szegmens + a két generált aggregátum), az §5.4–5.7 pinneli a
küszöböket, a leképezést és az eldobási szabályokat, a §6 pedig ÚJ cellákat kap
(**A8–A12**), köztük az `A10`-et, ami pontosan a fenti hibamódot viszi pirosra.
A régi A1–A7 cellák közül egyet sem töröltünk és egyet sem lazítottunk.

**Miért ez a legkisebb javítás.** A route-váltás halasztása (a másik mért
opció) az A1/A2/A5 cella törlését jelentette volna, és az `E16-R03` kimondott
előfeltételét („a kompozíciós rétege valós adatot ad") is érintette volna —
tehát TÖBB mércét vett volna el, nem kevesebbet.

**Őrteszt:** `tools/tests/test_e16_r02_mastery_source_scope.py` — a revízió
ELŐTTI briefen PIROS.

**Az ADR-szám a foglalóból jön (L603).** A fejlécben álló `ADR 0491` az előre
megírt brief állítása; a kör indításakor a hiteles forrás a foglaló — a
pre-flight kérje le, és ha foglalt, a kapott számot használja.

## 0.0 A MÉRT hiba: kész felület, amihez nincs adatforrás

A `progress_v2` feature **hét** fájlt tartalmaz: két képernyőt (`ProgressDashboardScreen`, `SkillDetailScreen`), négy domain-projekciót (`progress_overview_projection`, `skill_detail_projection`, `progress_trend`, `metric_version_segment`) és egy téma-burkolót. A képernyők „hívó-adta" szerződésűek (`required this.projection`), de **a projekciót SENKI nem állítja elő**: a típusokra a feature-en kívül nulla hivatkozás van, és a router `/profile/progress` útvonala ma is a legacy `ProgressScreen`-t építi. A felület tehát elkészült, de halott kód.

Ez a kör a hiányzó ELŐÁLLÍTÓT írja meg a MEGLÉVŐ adatforrásokból (gyakorlás-történet, gamification-profil, elemzési eredmények), és élesíti a route-ot.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/domain/mastery/mastery_milestone_catalog.dart",
  "lib/features/gamification/data/practice_mastery_evidence_adapter.dart",
  "lib/features/gamification/public.dart",
  "lib/features/practice/public.dart",
  "lib/l10n/features/gamification_en.arb",
  "lib/l10n/features/gamification_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/features/progress_v2/application/progress_projection_builder.dart",
  "lib/features/progress_v2/application/progress_providers.dart",
  "lib/features/progress_v2/public.dart",
  "lib/app/routing/app_router.dart",
  "test/features/gamification/domain/mastery_milestone_catalog_test.dart",
  "test/features/gamification/data/practice_mastery_evidence_adapter_test.dart",
  "test/features/progress_v2/progress_projection_builder_test.dart",
  "test/app/routing/progress_composition_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/ui/ui_inventory_test.dart",
  "docs/ui/migration-status.md",
  "docs/rounds/e16-r02-progress-projection-and-router-placeholders.md",
]
gate_tests = [
  "test/features/gamification/domain/mastery_milestone_catalog_test.dart",
  "test/features/gamification/data/practice_mastery_evidence_adapter_test.dart",
  "test/features/progress_v2/progress_projection_builder_test.dart",
  "test/features/progress_v2/dashboard_states_test.dart",
  "test/features/progress_v2/mastery_evidence_test.dart",
  "test/app/routing/progress_composition_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/l10n/arb_parity_test.dart",
  "test/tooling/gen_l10n_segments_test.dart",
  "test/core/architecture_dependency_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a kör a `/profile/progress` felhasználói útvonalat cseréli át egy másik képernyőre, és tanulási előrehaladást jelenít meg — hibás projekció esetén a felhasználó a saját fejlődéséről kapna téves képet. A `flutter-reviewer` + `flutter-devil-advocate` KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha egy projekciós mező kiszámításához olyan adat kellene, ami a fán MÉRHETŐEN nem létezik (nincs forrás-repository), a kimenet a `stopped` jelzés és a mező-lista — kitalált vagy szintetikus érték TILOS.

## 1. Cél

A `/profile/progress` a Progress V2 dashboardot mutassa, VALÓS, meglévő adatokból számított projekcióval — a legacy `ProgressScreen` pedig kontrolláltan váltson át (átirányítás vagy visszavonás az `E15-R03` terve szerint).

## 2. Jelenlegi állapot — mért tények

- `lib/features/progress_v2/`: 2 képernyő + 4 domain-projekció + 1 téma-burkoló; **0 provider**, **0 application/data fájl**.
- `ProgressOverviewProjection` és `SkillDetailProjection` hivatkozás a feature-en kívül: **0**.
- `app_router.dart` `/profile/progress` → a legacy `ProgressScreen` (az `E15-R03` audit mérte).
- Elérhető adatforrások: gyakorlás-történet (`lib/features/practice/data/`, 14 fájl), gamification-profil és ledger (`E16-R01` providerei), elemzési eredmények (`lib/features/audio_analysis/data/`, 23 fájl), song-trainer eredmények (`lib/features/song_trainer/data/`, 40 fájl).
- A `legacy_route_redirect_test.dart` a tizenegy legacy útvonal célját pinneli — a route-váltás ezt érinti.
- **A mastery-oldalnak a §0.0.H szerint NINCS forrása a fán** (0 produkciós milestone-katalógus, 0 evidencia-előállító, 0 milestone-l10n kulcs) — a §2 korábbi „gamification-profil és ledger" állítása MÉRVE téves. A forrás előállítása ezért ennek a körnek a része (§5.4–5.6).
- MÉRT, felhasználható mezők a gyakorlás-történetben: `PracticeHistoryEntry.{id, createdAt, definitionId, finalMetricSnapshot.{chord,rhythm,direction,overall}}` (`practice_history_entry.dart:28`), a nehézség és a tempó pedig a `PracticeDefinition.{difficulty, defaultTempo}` (`practice_definition.dart:19`, `builtin_practice_catalog.dart`).
- A ténylegesen játszott tempót a history NEM őrzi: a `highestStableTempoBpm` egyedül a Speed Builder futásából származik (`speed_builder_engine.dart:74`, `practice_session_result_history_mapper.dart:91`) — ez a hiány az §5.5-ben van kezelve.

## 3. Scope

**Benne van (a §0.0.H revízió szerint):** `domain/mastery/mastery_milestone_catalog.dart` — a v1 mastery-katalógus az §5.4 tábla szerint · `data/practice_mastery_evidence_adapter.dart` — a gyakorlás-történet → `MasteryEvidence` tiszta leképezés az §5.5 szerint · a milestone cím/leírás kulcsok a `lib/l10n/features/gamification_{en,hu}.arb` szegmensbe + a generált aggregátum újragenerálása · a `gamification`/`practice` publikus barrel MINIMÁLIS bővítése (a katalógus, az adapter és a `practiceCatalogProvider` + `PracticeDefinition.difficulty` eléréséhez) · `application/progress_projection_builder.dart` — a `ProgressOverviewProjection` és a `SkillDetailProjection` előállítása a MEGLÉVŐ forrásokból (tiszta Dart, óra és véletlen nélkül) · `application/progress_providers.dart` — a kompozíciós réteg (az `E16-R01` mintájára) · `public.dart` export · a router `/profile/progress` útvonalának átkötése a `ProgressDashboardScreen`-re + a skill-detail útvonal bekötése · a legacy `ProgressScreen` kezelése az `E15-R03` terve szerint (átirányítás; a fájl TÖRLÉSE nem ennek a körnek a dolga) · `migration-status.md` frissítése.

**NINCS benne (tilos):**

- Új metrika vagy pontszám-definíció (`domain/` szabály) — a projekció a MEGLÉVŐ mezőket tölti.
- Szintetikus/„demo" adat bármilyen formában.
- Más feature képernyőinek átírása.
- A legacy `ProgressScreen` fájljának törlése.
- `docs/adr/**` — az ADR 0491-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/domain/mastery/mastery_milestone_catalog.dart` | ÚJ — a v1 mastery-katalógus (§5.4) |
| `lib/features/gamification/data/practice_mastery_evidence_adapter.dart` | ÚJ — gyakorlás-történet → `MasteryEvidence` (§5.5) |
| `lib/features/gamification/public.dart` | a katalógus és az adapter export-sora (barrel-szabály) |
| `lib/features/practice/public.dart` | KIZÁRÓLAG export-sor: `practiceCatalogProvider` + `PracticeDifficulty` — más változtatás TILOS |
| `lib/l10n/features/gamification_{en,hu}.arb` | a 3 milestone cím + 3 leírás kulcsa, mindkét locale (§5.6) |
| `lib/l10n/app_{en,hu}.arb` | **generált aggregátum** — `dart run tool/gen_l10n_segments.dart --write` kimenete, kézzel **közvetlenül nem szerkeszthető** |
| `test/features/gamification/domain/mastery_milestone_catalog_test.dart` | az A8 cella |
| `test/features/gamification/data/practice_mastery_evidence_adapter_test.dart` | az A9 cella |
| `lib/features/progress_v2/application/progress_projection_builder.dart` | ÚJ — a projekció-előállító |
| `lib/features/progress_v2/application/progress_providers.dart` | ÚJ — a kompozíciós réteg |
| `lib/features/progress_v2/public.dart` | export |
| `lib/app/routing/app_router.dart` | a `/profile/progress` átkötése |
| `test/features/progress_v2/progress_projection_builder_test.dart` | a §6 projekció-cellái |
| `test/app/routing/progress_composition_test.dart` | a §6 útvonal-cellái |
| `test/app/navigation/*.dart` (három őr) · `test/ui/ui_inventory_test.dart` | regresszió-őrök — a jogosultság PONTOSAN a `/profile/progress` adapter típusának átírása; cella törlése, `skip`-je vagy gyengítése TILOS |
| `docs/ui/migration-status.md` | a MÉRT állapot |

**Tilos zóna:** `lib/features/progress/**` (a legacy fájl) · `lib/features/progress_v2/domain/**` · `lib/features/{audio_analysis,song_trainer}/**` (olvasás igen, írás nem) · `lib/features/gamification/**` a §4 táblában NEM szereplő minden fájlja (az evaluator, a `mastery_progress.dart` és a `mastery_milestone.dart` VÁLTOZATLAN — a katalógus a MEGLÉVŐ típusokat tölti) · `lib/features/practice/**` a `public.dart` export-során kívül · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0491)

### 5.1 A projekció DETERMINISZTIKUS és tiszta

Azonos bemenet → azonos kimenet; `DateTime.now()` és `Random` a builderben TILOS (a hívó adja az időt). **NEM elfogadható gyengítés:** „az aktuális dátum kell hozzá" — az paraméter, nem mellékhatás.

### 5.2 Hiányzó forrás = EXPLICIT üres állapot

Ha egy készség-tengelyhez nincs mérés, a projekció ezt jelöli, és a képernyő üres állapotot mutat. **NEM elfogadható gyengítés:** nulla értékkel „kitöltött" trend, ami visszaesésnek látszik.

### 5.3 A legacy útvonal átirányít, nem tűnik el

**NEM elfogadható gyengítés:** a `/progress` mélylink csendes megszüntetése.

### 5.4 A v1 mastery-katalógus — annyi, amennyire MÉRT forrás van

`masteryMilestoneCatalogV1` (`const List<MasteryMilestone>`, `catalogVersion: 1`):

| id | skill | metric | forrás-dimenzió (`finalMetricSnapshot`) | `minimumThreshold` | `minEvidenceSessions` | `tempoRange` |
|---|---|---|---|---|---|---|
| `mastery.chordTransition.v1` | `chordTransition` | `accuracy` | `.chord` | `0.8` | `3` | `40–240` |
| `mastery.rhythmAccuracy.v1` | `rhythmAccuracy` | `accuracy` | `.rhythm` | `0.8` | `3` | `40–240` |
| `mastery.strumConsistency.v1` | `strumConsistency` | `accuracy` | `.direction` | `0.8` | `3` | `40–240` |

`MasterySkill.tempoStability` a v1-ben **NEM kap milestone-t**: a fán nincs mért
`tempoAdherence` forrás (a `highestStableTempoBpm` a Speed Builder csúcs-tempója,
nem adherence-metrika). Ez DOKUMENTÁLT hiány — kitölteni TILOS.

**NEM elfogadható gyengítés:** a küszöb csökkentése azért, hogy „legyen mit
mutatni"; a `minEvidenceSessions` 2 alá vitele (a domain amúgy elutasítja).

### 5.5 A bizonyíték MÉRT mezőkből jön, és ami nem mérhető, az KIMARAD

`PracticeHistoryEntry` → `MasteryEvidence` (tiszta függvény, óra és véletlen nélkül):

- `sessionId` = `entry.id` · `observedAt` = `entry.createdAt.toUtc()` ·
  `origin` = `MasteryEvidenceOrigin.device` (a mérés a készüléken, gyakorlás
  közben történt); `confidence` marad `null` — a `device` origin nem követeli
  meg, és nincs mért forrása.
- `metricValue` = a milestone skilljéhez rendelt dimenzió, **kizárólag**
  `PracticeMetricDimensionAvailable` esetén. `notApplicable` /
  `insufficientData` → **NINCS bizonyíték** (nem `0`).
- `difficulty` = a `entry.definitionId`-hoz tartozó `PracticeDefinition.difficulty`
  1:1 leképezése. Ismeretlen `definitionId` → **NINCS bizonyíték**.
- `tempoBpm` = ugyanannak a definíciónak a `defaultTempo.bpm`-je. **MÉRT hiány:**
  a history nem őrzi a ténylegesen játszott tempót, ezért a v1 milestone-ok
  tempó-hatóköre szándékosan a teljes tartomány — a tempó így egyetlen
  bizonyítékot sem zár ki és egyetlen felhasználói számot sem befolyásol. A
  hiányt a §10 handoff rögzíti egy későbbi history-séma körnek.
- Egy `sessionId` skillenként EGY bizonyíték; a dedup és a monotonitás az
  `MasteryEvaluator` dolga — azt a kör NEM írja át.

**NEM elfogadható gyengítés:** hiányzó dimenzió `?? 0`-val; ismeretlen nehézség
„beginnernek" vétele; a nem mért tempó kitalálása.

### 5.6 A lokalizált cím a kompozíciós rétegből jön, EXPLICIT leképezéssel

A 3 cím + 3 leírás kulcs a `lib/l10n/features/gamification_{en,hu}.arb`
szegmensbe kerül (MINDKÉT locale), majd `dart run tool/gen_l10n_segments.dart --write`
futtatása következik: a `lib/l10n/app_{en,hu}.arb` **generált aggregátum**, ami
kézzel **közvetlenül nem szerkeszthető** (ADR 0307 §4, [L497 osztály: E08-R12/H6]).
A `titleKey`/`descriptionKey` → lokalizált szöveg feloldás a kompozíciós
rétegben, EXPLICIT `switch`-csel; dinamikus kulcs-feloldás TILOS (E13-R31 §0.0.B/B7).

### 5.7 Két projekciós mező MÉRT ÁLLANDÓ, nem kitöltés

- `ProgressOverviewProjection.isOffline` = `false`: a fejlődés-adat 100%-ban
  helyi (a `practiceHistoryRepositoryProvider` lokális tár, a progress semmit nem
  szinkronizál a fiókkal), tehát „még nem szinkronizált helyi állapot" nem
  létezhet. Mért állandó, nem hiányzó forrás.
- `SkillDetailProjection.recommendation` = `null`: ajánlás-katalógus a fán nincs,
  a mező opcionális — az EXPLICIT hiány a helyes érték. Kitalált ajánlás TILOS.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A `/profile/progress` a `ProgressDashboardScreen`-t rendereli valós projekcióval | `progress_composition_test.dart` |
| A2 | A skill-detail útvonal a `SkillDetailScreen`-re visz, a kiválasztott készség azonosítójával | `progress_composition_test.dart` |
| A3 | A builder determinisztikus: ugyanaz a bemenet kétszer ugyanazt adja | `progress_projection_builder_test.dart` |
| A4 | Mérés nélküli készség EXPLICIT „nincs adat" jelölést kap (nem nullát) | `progress_projection_builder_test.dart` |
| A5 | A legacy `/progress` mélylink továbbra is működik (átirányít) | `legacy_route_redirect_test.dart` |
| A6 | A builderben nincs `DateTime.now()` és `Random` | statikus cella a `progress_projection_builder_test.dart`-ban |
| A7 | A képernyő-leltár és a navigációs őrök VÁLTOZATLANUL zöldek | a §7 gate |
| A8 | A `masteryMilestoneCatalogV1` pontosan az §5.4 táblát pinneli (id, küszöb, `minEvidenceSessions`, `catalogVersion`), és `tempoStability` milestone NINCS benne | `mastery_milestone_catalog_test.dart` |
| A9 | Az adapter a nem mérhető sessiont ELDOBJA (nem elérhető dimenzió, ismeretlen `definitionId`), a mérhetőből pedig a mért mezőkkel állít elő bizonyítékot | `practice_mastery_evidence_adapter_test.dart` |
| A10 | Három, a küszöböt elérő builtin gyakorlás-történettel a `/profile/progress` **NEM** a new-user állapotot rendereli, hanem a mért készség-sorokat | `progress_composition_test.dart` |
| A11 | Az új milestone-kulcsok MINDKÉT locale-ban megvannak, és a generált aggregátum a szegmensekből újragenerálva változatlan | `arb_parity_test.dart`, `gen_l10n_segments_test.dart` |
| A12 | A `minimumThreshold` (`0.8`) MINDHÁROM oldala mérve: a küszöb **alatt** (`0.79`) nincs elsajátítás, **rajta** (`0.80`) van, **fölött** (`0.81`) van — és ugyanígy a `minEvidenceSessions` (`3`): két bizonyíték-sessionnel nincs, hárommal van | `progress_projection_builder_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A route átkötve marad a legacy képernyőre | A1 |
| A builder `DateTime.now()`-ot hív | A3 és A6 |
| Hiányzó mérés 0-val töltődik ki (hamis visszaesés) | A4 |
| A `/progress` mélylink 404-re fut | A5 |
| A katalógus üres marad (a projekció üres milestone-listát kap) | A8 és **A10** |
| Az adapter a hiányzó dimenziót `0`-val tölti | A9 (és A4) |
| Az ARB-kulcs csak `en`-be kerül be, vagy az aggregátum nincs újragenerálva | A11 |
| A küszöb szigorú `>` helyett `>=` (vagy fordítva) — a „rajta" eset elcsúszik | A12 |

**Valódi-sértés próba (KÖTELEZŐ, MINDKETTŐ, a §10-ben dokumentálva):**
1. cseréld a hiányzó-mérés ágat konstans `0`-ra, futtasd a §7 gate-et → az **A4**
   cellának PIROSNAK kell lennie → állítsd vissza;
2. ürítsd ki a katalógust (`const <MasteryMilestone>[]`), futtasd a §7 gate-et →
   az **A8** ÉS az **A10** cellának PIROSNAK kell lennie → állítsd vissza. Ez az
   a hibamód, ami a kör első pre-flightját megállította (§0.0.H).

## 7. Kötelező ellenőrzések

```bash
dart run tool/gen_l10n_segments.dart --write   # az ARB-kulcsok felvétele UTÁN, a gate ELŐTT
tools/round-gate.sh test/features/gamification/domain/mastery_milestone_catalog_test.dart test/features/gamification/data/practice_mastery_evidence_adapter_test.dart test/features/progress_v2/progress_projection_builder_test.dart test/features/progress_v2/dashboard_states_test.dart test/features/progress_v2/mastery_evidence_test.dart test/app/routing/progress_composition_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/navigation/tab_state_restoration_test.dart test/ui/ui_inventory_test.dart test/l10n/arb_parity_test.dart test/tooling/gen_l10n_segments_test.dart test/core/architecture_dependency_test.dart
```

## 8. Implementációs sorrend

1. A MÉRÉS: milyen mezőket vár a két projekció, és melyikhez van forrás (a §0.0.H tábla az induló állapot).
2. `mastery_milestone_catalog.dart` az §5.4 tábla szerint + az A8 teszt (RED-ből).
3. Az ARB-kulcsok a `lib/l10n/features/gamification_{en,hu}.arb`-ba, majd `dart run tool/gen_l10n_segments.dart --write`.
4. `practice_mastery_evidence_adapter.dart` az §5.5 szerint + az A9 teszt (RED-ből); a `practice/public.dart` export-sora.
5. `progress_projection_builder.dart` (tiszta Dart, RED-ből).
6. `progress_providers.dart` + a két `public.dart`.
7. A router átkötése + a legacy átirányítás + az A10 cella.
8. `migration-status.md` + a KÉT valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Hamis fejlődés-kép.** Kitöltött nullák visszaesésnek látszanak (A4).
- **Mélylink-törés.** A `/progress` megszüntetése mentett hivatkozásokat törne (A5).
- **Forráshiány.** Ha egy projekciós mezőhöz nincs adat, az `stopped` — nem szintetikus kitöltés.
- **Örökre üres dashboard.** Ha a katalógus vagy a bizonyíték-lánc üresen marad, a képernyő a new-user állapotba ragad, miközben a felhasználónak VAN gyakorlás-története — ezt az **A10** cella méri (§0.0.H).
- **Nem mért tempó.** A history nem őrzi a játszott tempót; a v1 tempó-hatókör ezért nem szűr (§5.5). A hiányt a §10 handoff adja tovább.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
