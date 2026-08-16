# E07-R08 — Practice catalog capability adapter

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-16, kód olvasva: `main @ 5281d0f5`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 8
- **Kör-azonosító:** `E07-R08`
- **Branch:** `<motor>/e07-r08-practice-catalog-adapter`
- **Előfeltétel:** `E07-R07` merge-elve (legacy evidence adapterek)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0262`](../adr/0262-catalog-snapshot-revisions-and-capability-truth.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg a Practice Engine
> TÉNYLEGES gyakorlat-definíciós modelljét (`lib/features/practice/**`, a
> `public.dart`-ján át), és hogy milyen capability/időtartam/nehézség
> metaadatot ad ma. A brief §2 erre hivatkozik; eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/practice_generator/domain/model/practice_catalog_snapshot.dart",
  "lib/features/practice_generator/domain/model/exercise_candidate.dart",
  "lib/features/practice_generator/application/port/practice_catalog_reader.dart",
  "lib/features/practice_generator/data/adapter/practice_engine_catalog_adapter.dart",
  "lib/features/practice_generator/data/adapter/legacy_lesson_candidate_adapter.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/catalog/practice_catalog_snapshot_test.dart",
  "test/features/practice_generator/catalog/practice_engine_catalog_adapter_test.dart",
  "docs/rounds/e07-r08-practice-catalog-adapter.md",
]
gate_tests = [
  "test/features/practice_generator/catalog/practice_catalog_snapshot_test.dart",
  "test/features/practice_generator/catalog/practice_engine_catalog_adapter_test.dart",
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

## 0.0 Pre-flight mérés és brief-revízió (Claude, 2026-08-16, kód olvasva: `main @ 5281d0f5`)

**1. A „Practice Engine adapter" NEM érheti el a katalógus repository/controller
réteget — DRIFT, feloldva lent, `allowed_paths` változatlan.** Mérve:
`lib/features/practice/public.dart` (114 export sor) NEM exportálja a
`PracticeCatalogRepository`-t (`domain/repository/practice_catalog_repository.dart`),
a `BuiltinPracticeCatalog`-ot (`data/builtin_practice_catalog.dart`), sem a
`practiceCatalogRepositoryProvider`/`practiceCatalogProvider` Riverpod
providereket (`application/practice_catalog_controller.dart`) — csak
value-típusokat exportál (`PracticeDefinition`, `PracticeMode`,
`PracticeSource`, `ScoringProfile`, `Tempo`, `Meter`, `BeatPosition`,
`PracticeEvent`, …). Ezek a fájlok NINCSENEK ennek a körnek az engedélyezett
listáján, és kívül esnek a tilos zónán (`lib/features/practice/**`) —
bővítésük **H3** lenne, nem ennek a körnek a hatásköre.

**Feloldás (nem igényel `allowed_paths` bővítést):** a
`practice_engine_catalog_adapter.dart` NEM olvashat élőben katalógust — PURE,
**hívó-táplált** transzformátor legyen, ami `PracticeDefinition` értékeket
(egyenként, vagy egy hívó-átadott `Iterable<PracticeDefinition>`-ként) alakít
`ExerciseCandidate`-tá, saját Riverpod-függőség és
`PracticeCatalogRepository`-import NÉLKÜL. Ez pontosan azt a mintát követi,
amit az Epic 7 MINDEN eddigi adaptere alkalmaz
(`legacy_lesson_catalog_adapter.dart`, `legacy_progress_evidence_adapter.dart`:
hívó-táplált wrapper, nulla production hívó, nulla élő repository-olvasás) — a
valódi katalógus-beolvasás (`practiceCatalogRepositoryProvider.all()`)
bekötése egy JÖVŐBELI, dedikált wiring-kör dolga, nem ezé. A
`practice_catalog_reader.dart` PORT (`application/port/`) ettől függetlenül a
teljes hívó-oldali szerződést írhatja le (pl. `PracticeCatalogSnapshot
read(...)`) — csak a Practice Engine KONKRÉT adapter-implementációja marad
hívó-táplált ebben a körben. **NEM elfogadható gyengítés:** a
`practiceCatalogRepositoryProvider`/`BuiltinPracticeCatalog` közvetlen
importja vagy egy saját, párhuzamos Riverpod-provider bevezetése a
practice_generator oldalán — mindkettő scope-sértés (H3) VAGY architektúra-őr
piros.

**2. `PracticeDefinition.difficulty` (típus: `PracticeDifficulty`) exportálatlan,
de a `.code` lánc elérhető — nincs drift, csak pontosítás.**
`practice_difficulty.dart` (`beginner`/`intermediate`/`advanced`, stabil
`.code` String) sincs a public.dart-on, DE a `PracticeDefinition.difficulty`
mező maga publikus (a `PracticeDefinition` osztály exportált), és a Dart
tagfeloldás nem követeli meg, hogy a mező TÍPUSÁT is név szerint importáld a
tag-hozzáféréshez — tehát `definition.difficulty.code` (egy String) a
public.dart-on át, import-sértés NÉLKÜL olvasható; csak magát a
`PracticeDifficulty` azonosítót (típusannotáció, `switch`-eset,
`PracticeDifficulty.beginner` konstruktor) nem szabad leírni. **NE próbálj
`practice_difficulty.dart`-ot közvetlenül importálni** — az architektúra-őr ezt
tiltott cross-feature importként buktatja (A8 cella).

**3. A legacy `Lesson` (Learn feature) nem hordoz skill-taget — az R07
`LegacyMappingTable` mintája újrafelhasználható.** `lib/features/learn/model/lesson.dart`
(a `learn/public.dart` a TELJES fájlt exportálja) mezői: `id`, `name`, `bpm`,
`difficulty` (saját `Difficulty` enum, névvel is elérhető), `beatsPerBar`,
`events`, `totalBeats` — nincs skillTag/prerequisite mező. Mivel az ADR 0262
§5 explicit a skill-tag-hiányt hozza fel a kizárás példájaként, és a
`legacy_lesson_candidate_adapter.dart`-nak adnia kell a kötelező
`skillTargets` mezőt, a már szállított
`practice_generator/data/adapter/legacy_mapping_table.dart` (R07, UGYANEBBEN
a feature-ben — szabadon importálható, ez nem `allowed_paths`-sértés: az
csak az ÍRÁST korlátozza, az olvasást/importot nem) a kézenfekvő, ADR
0293-mintát követő forrás a lecke→skill leképezéshez (SDD Ch8 §5.1:
névhasonlóság-alapú találgatás tilos). Nem kötelező újrafelhasználni, de egy
önálló, párhuzamos mapping-mechanizmus bevezetése indoklást igényel a §10
handoffban.

**4. Az `ExerciseCandidate` mezőneveinek és a kapcsolódó enumoknak a forrása:
SDD Ch8 §14.1–14.6 — a brief §3/§4 prózája ennek tömörítése, nem
helyettesítése.** Szó szerint idézve:

```dart
final class ExerciseCandidate {
  const ExerciseCandidate({
    required this.exerciseId,
    required this.source,
    required this.skillTargets,
    required this.prerequisites,
    required this.supportedDurations,
    required this.difficultyRange,
    required this.capabilities,
    required this.loadProfile,
    required this.offlineAvailable,
    required this.contentRevision,
  });
}
```

Forrás-enum (§14.2, legalább ennyi érték): `practiceCatalog`, `legacyLesson`,
`songRange`, `analysisHotspot`, `visionCalibration`, `assessment`,
`freePractice`, `reflection`, `rest` — **ebben a körben csak a
`practiceCatalog` és a `legacyLesson` kap termelőt** (a két adapter), a többi
stabil kódú, de hívatlan érték marad (ne dobd el az enumból, csak nincs rá
gyártó ebben a körben).

Capability-példák (§14.3, NEM zárt lista — a kör saját, stabil kódú enumja
ebből indulhat ki): `requiresMicrophone`, `requiresCamera`,
`requiresBackingTrack`, `requiresSongAsset`, `supportsTempo`, `supportsLoop`,
`supportsDirectionScoring`, `supportsChordScoring`, `supportsPitchScoring`,
`supportsOffline`, `supportsLeftHandedUi`, `supportsReducedMotion` — mindegyik
`unsupported`, ha a forrás nem ad rá bizonyítékot (ADR 0262 §2, ez a kör §5.2
szabálya).

Load-profile dimenziók (§14.4, mind kötelező, ordinal `low`/`medium`/`high`):
cognitive load, fretting-hand load, picking-hand load, repetition load,
novelty, concentration demand. „A skála pedagógiai proxy, nem egészségügyi
mérés."

Kizárási okok (§14.6, a figyelmeztetés kódkészlete — legalább ennyi stabil
kód): `missingPrerequisite`, `hardAvoid`, `unsupportedDevice`, `wrongTuning`,
`missingAsset`, `offlineUnavailable`, `contentLocked`, `safetyConflict`,
`durationIncompatible`, `localeUnavailable`, `revisionMissing`. Ebben a
körben csak a metaadat-hiányhoz tartozó kód (pl. `missingPrerequisite`) kap
valódi termelőt (§6.1) — a többi stabil kódú, hívatlan érték marad.

**Mérési szabály 2 (erőforrás-tulajdonlás) — ellenőrizve, NEM alkalmazható.**
Ez a kör nem rendel lease/lock/handle/subscription erőforrást egyik rétegnek
sem: szinkron, tisztán funkcionális domain/adapter réteg, mikrofon/hálózat/
storage-hívás nélkül.

**Összegzés:** a fenti mérésekkel az `allowed_paths`/`gate_tests` **változatlan**
marad — mindkét deviancia a már engedélyezett fájlokon belül feloldható.

## 1. Cél

A **végrehajtható** gyakorlatok egységes, revíziózott jelölt-pillanatképe
(SDD Ch8 Kör 8).

## 2. Jelenlegi állapot — mért tények

- Az R05-R07 az evidence oldalt építette meg; ez a kör a **kínálati** oldal.
- Az architektúra-őr tiltja a más feature-ök belső importját — a Practice
  Engine csak a `public.dart`-ján át érhető el.
- Az offline-first elv (SDD Ch8 §2.4) miatt a jelölt **offline
  elérhetősége** metaadat, nem futásidejű találgatás.

## 3. Scope

**Benne van:** `ExerciseCandidate` (capability, időtartam, nehézség, terhelés,
offline metaadat, forrás-hivatkozás) · `PracticeCatalogSnapshot` (katalógus- és
tartalom-revízióval) · `PracticeCatalogReader` port · Practice Engine adapter ·
legacy lecke-jelölt adapter fallbackként · **determinisztikus rendezés**.

**NINCS benne (tilos):** prescription és success criteria (Kör 9) · tervezés
(Kör 12-től) · a Practice Engine módosítása · más feature belső importja ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/model/exercise_candidate.dart` | **ÚJ** — a jelölt + metaadatai |
| `domain/model/practice_catalog_snapshot.dart` | **ÚJ** — revíziózott pillanatkép |
| `application/port/practice_catalog_reader.dart` | **ÚJ** — a port |
| `data/adapter/practice_engine_catalog_adapter.dart` | **ÚJ** |
| `data/adapter/legacy_lesson_candidate_adapter.dart` | **ÚJ** — fallback |
| `public.dart` | a barrel bővítése |
| `test/…/catalog/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r08-…md` | a §10 handoff |

**Tilos zóna:** minden más `lib/features/**` tartalma · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0262)

### 5.1 A jelölt CSAK létező forrásra mutathat

Minden `ExerciseCandidate` egy valóban végrehajtható gyakorlatra hivatkozik.
Nincs „szintetikus" jelölt, amit a végrehajtó réteg nem tud lefuttatni.

**NEM elfogadható gyengítés:** placeholder jelölt „majd lesz hozzá tartalom"
alapon. A terv végrehajthatatlanná válna.

### 5.2 A nem támogatott capability EXPLICIT, nem hiányzó

Ha egy gyakorlat nem támogat pl. tempó-vezérlést, az **kimondott** `unsupported`,
nem hiányzó mező. A hiányzó mezőt a tervező „ismeretlennek" venné, és
megpróbálná használni.

### 5.3 A pillanatkép KÉT revíziót hordoz

Katalógus-revízió (mely gyakorlatok vannak) és tartalom-revízió (azok
tartalma). Egy terv provenance-e mindkettőt rögzíti, így később
megkülönböztethető: a terv változott, vagy a katalógus alatta.

### 5.4 A rendezés DETERMINISZTIKUS és teljes

Stabil rendezési kulcs (nem `hashCode`, nem beolvasási sorrend). Két azonos
bemenetből bitre azonos sorrend — az ADR 0255 §1 miatt.

### 5.5 Hiányzó kötelező metaadat: a jelölt KIMARAD, jelzéssel

Skill-tag vagy előfeltétel nélküli gyakorlat nem kerül a pillanatképbe, és ez
figyelmeztetésként látszik — nem kerül be „üres" metaadattal.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Minden jelölt létező forrásra mutat | `practice_engine_catalog_adapter_test.dart` |
| A2 | A nem támogatott capability explicit `unsupported` | ugyanott |
| A3 | A pillanatkép katalógus- ÉS tartalom-revíziót hordoz | `practice_catalog_snapshot_test.dart` |
| A4 | Revízió-eltérés detektált (mismatch) | ugyanott |
| A5 | A rendezés két futásban bitre azonos | ugyanott |
| A6 | Hiányzó kötelező metaadat → a jelölt kimarad + figyelmeztetés | adapter-teszt |
| A7 | Az offline elérhetőség metaadatból jön, nem találgatásból | adapter-teszt |
| A8 | Az adapter csak `public.dart`-on át ér el más feature-t | architektúra-őr + diff |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Placeholder jelölt forrás nélkül | **A1** |
| A nem támogatott capability hiányzó mezőként | **A2** |
| Csak egy revízió a pillanatképben | A3/A4 |
| `hashCode`-alapú rendezés | **A5** |
| Hiányzó metaadat üres értékkel pótolva | A6 |
| Offline-státusz futásidejű találgatásból | A7 |

**A metaadat-teljesség három kötelező cellája** (a határ: a kötelező mezők megléte):

| Cella | Bemenet | Elvárt |
|---|---|---|
| teljes | minden kötelező metaadat megvan | a jelölt bekerül |
| a határon | a kötelező megvan, az **opcionális** hiányzik | a jelölt **bekerül**, az opcionális `unknown`/`unsupported` |
| hiányos | **kötelező** metaadat hiányzik | a jelölt **kimarad** + figyelmeztetés |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** pótold a hiányzó
kötelező metaadatot default értékkel → az **A6** cellának PIROSNAK kell
lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/catalog/practice_catalog_snapshot_test.dart test/features/practice_generator/catalog/practice_engine_catalog_adapter_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `exercise_candidate.dart` — a metaadatok, `unsupported` explicit értékkel.
2. `practice_catalog_snapshot.dart` — két revízióval, stabil rendezéssel.
3. `practice_catalog_reader.dart` port.
4. Practice Engine adapter, majd a legacy fallback adapter.
5. Tesztek a §6.1 három metaadat-cellájával.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A placeholder jelölt.** Kényelmes a tervezés fejlesztéséhez, és
  végrehajthatatlan tervet szül (A1).
- **A hiányzó mező mint „ismeretlen".** A tervező megpróbálná használni a
  nem támogatott capabilityt (A2).
- **A rendezés instabilitása.** `hashCode` vagy `Map` iterációs sorrend
  futásonként más — a determinizmus csendben elveszik (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
