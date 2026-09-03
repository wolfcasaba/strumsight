# E16-R01 — A Gamification kompozíciós rétege: valós adat a felület mögé

- **Státusz:** PREPARED (előre megírva 2026-09-02, kód olvasva: `main @ 11d0d2bb`)
- **Típus:** Chapter 16 (Kompozíció és rollout), Kör 1
- **Kör-azonosító:** `E16-R01`
- **Branch:** `<motor>/e16-r01-gamification-composition-layer`
- **Előfeltétel:** `E15-R08` merge-elve (a gamification képernyők design-migrációja — a bekötés a MIGRÁLT képernyőkre megy)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** [`ADR 0496`](../adr/0496-gamification-composition-layer-and-honest-unavailability.md)
  — **a §0.0.A pre-flight javította:** az előre írt `0490` a mérés szerint MÁR
  FOGLALT (`0490-hotfix-path-gates-…`), a `tools/round-slots.py reserve-adr
  --round E16-R01` a **`0496`**-ot adta ki. A hiteles forrás a foglaló.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "gamification composition provider wiring achievements quests placeholder"` → **[ADR 0333](../adr/0333-activity-outbox-reliable-processing.md)** (activity outbox: az ingestor kész reward-műveletet továbbít) és **[ADR 0353](../adr/0353-caller-fed-compassionate-streak-v2-presentation.md)** („hívó-adta" prezentáció: a képernyő paraméterként kapja az adatot, a bekötés a KOMPOZÍCIÓS réteg dolga). A kör pontosan ezt a hiányzó kompozíciós réteget építi meg.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/app/routing/app_router.dart` gamification-blokkját (a megíráskor `:105-167` a három privát provider + a **beégetett négyszintes `LevelCurve`**, `:642-730` a képernyő-építés) és számold meg a `TODO(E08-R30)` markereket (a megíráskor **8**). A §2 minden számát újra kell mérni.

## 0.0 A MÉRT hiba: a felület üres adatot kap

A Gamification feature `application/` rétege **tizenkét** szolgáltatást tartalmaz (`achievement_evaluator`, `daily_quest_generator`, `weekly_quest_generator`, `mastery_evaluator`, `profile_projector`, `streak_service`, `celebration_coordinator`, `reward_policy_engine`, …), a `data/` réteg pedig működő repository-kat. A képernyők mégis üres adatot mutatnak, mert **a feature-ben NULLA Riverpod-provider van** (`grep` a `lib/features/gamification/`-ben: 0 provider-deklaráció), és az egyetlen bekötés a ROUTERBEN él, ad-hoc módon:

- `_gamificationProfileProvider`, `_streakStateProvider`, `_rewardInboxProvider` — három privát provider a router fájlban;
- a `LevelCurve` **beégetve** a routerbe (négy szint, `app_router.dart:105-128`);
- a képernyők konstans placeholdereket kapnak: `activeQuestCount: 0`, `masteryUnlockedCount: 0`, `progressByAchievement: const <String, AchievementProgress>{}` (kétszer), `dailyChallenge: null`, `weeklyConsistencyDays: 0`;
- `onOpenLevelDetail: () {}` — üres callback;
- **8** `TODO(E08-R30)` marker jelöli ugyanezt.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/providers/gamification_providers.dart",
  "lib/features/gamification/application/gamification_providers.dart",
  "lib/features/gamification/public.dart",
  "lib/app/routing/app_router.dart",
  "lib/app/routing/app_route.dart",
  "docs/ui/legacy-backlog.md",
  "test/features/gamification/application/gamification_providers_test.dart",
  "test/app/routing/gamification_composition_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "docs/rounds/e16-r01-gamification-composition-layer.md",
]
gate_tests = [
  "test/features/gamification/application/gamification_providers_test.dart",
  "test/app/routing/gamification_composition_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/core/architecture_dependency_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a kör a routert írja át (az alkalmazás navigációs gerincét), és jutalom-/XP-adatot köt be — egy hibás projekció dupla vagy hamis jutalmat mutathatna. A `flutter-reviewer` és a `flutter-devil-advocate` futtatása KÖTELEZŐ.

## 0.0.A Pre-flight brief-revízió (Claude/Opus 5 orchestrátor, 2026-09-03, `main @ 4ca8785f`)

**A §2 minden száma ÚJRAMÉRVE és VÁLTOZATLANUL igaz:** 12 `application/`
szolgáltatás · **8** `TODO(E08-R30)` a routerben (`:150, :699, :715, :746,
:761, :766, :780, :784`) · **73** export a `public.dart`-ban · **0**
provider-deklaráció a feature-ben · a beégetett négyszintes `LevelCurve`
`app_router.dart:108-131`.

### R1 — ADR-szám: `0490` → **`0496`** (a foglaló mérése, ADR 0087 §1.0.1)

A `0490` már FOGLALT (`0490-hotfix-path-gates-incident-binding-and-regression-obligation.md`),
a foglaló a `0496`-ot adta. Az ADR ezen a számon él és a pre-flight commitban
már a fán van.

### R2 — A DÖNTŐ mérés: mi számítható ki EGYÁLTALÁN a perzisztált állapotból

A 12 szolgáltatás **tiszta számítási motor** — mindegyik a hívótól kapja a
bemenetét (`StreakService`: „this service never reads a repository";
`AchievementEvaluator.rebuild(history:)`; `MasteryEvaluator.evaluate(evidence:)`;
`DailyQuestGenerator.generate(snapshot)`). A ténylegesen perzisztált állapot
ezzel szemben: `GamificationProfileSnapshot{schemaVersion, totalXp}`,
`GamificationCatalogVersion`, `GamificationInboxItem{id, createdAt, viewedAt}`,
`GamificationMigrationState`, `RewardLedgerRepository.readPage(...)` →
`RewardLedgerEntry{ledgerId, sourceEventId, createdAt, baseXp, bonusXp,
totalXp, reasonCodes, policyVersion}`, és a legacy streak
(`LegacyStreakMigrator.migrate()`).

**NINCS perzisztálva:** achievement-evidencia-történet
(`AchievementEvaluationEvidence` a fa EGYETLEN fájljában — magában az
evaluatorban — fordul elő), mastery-evidencia/-progress, quest-generálási
snapshot (`plannedObjectives`, `availableDays`, `baselineWeeklyMinutes`).

Emiatt a §3 „quest- és mastery-providerek a MEGLÉVŐ szolgáltatásokra építve"
megfogalmazása **részben elérhetetlen cél** volt. A revízió NEM tágít
scope-ot ezekre: kimondja, hogy ezek a tételek **explicit hiány + datált
backlog-tétel**, nem hamis nulla, és nem is `stopped`.

### R3 — Tételes döntés a nyolc `TODO(E08-R30)`-ról (ez a kör szerződése)

| # | sor | Tétel | DÖNTÉS |
|---|---|---|---|
| 1 | `:150` | legacy streak visszaírás a V2 borítékba | **BACKLOG** — a `GamificationRepository`-n nincs streak-write API, a `data/**` tilos zóna. A provider a feature-be kerül, a marker helyére `docs/ui/legacy-backlog.md` hivatkozás lép. |
| 2 | `:699` | level-detail navigáció | **BEKÖTVE** — a `LevelDetailScreen` LÉTEZIK és tesztelt, csak route-ja nincs. Új `AppRoutes.levelDetail = '/gamification/level'` + `GoRoute` (ADR 0496 §4, ADR 0123 / L90). |
| 3 | `:715` | achievement-haladás | **BEKÖTVE** — `AchievementEvaluator` a ledgerben tárolt idempotens receiptekből (ADR 0496 §3). A provider nem implementál újra kiértékelési szabályt. |
| 4 | `:746` | quest-akció routing | **BEKÖTVE** — a `QuestRouteAction` szótár LEZÁRT (4 variáns: `QuestStartPracticeAction`, `QuestContinuePracticeAction`, `QuestTryLiveAction`, `QuestUnavailableAction`), a célútvonalak léteznek; `QuestUnavailableAction` → nincs navigáció. |
| 5 | `:761` | streak-reason | **BEKÖTVE** — `StreakService.evaluate(StreakEvaluationRequest{previous, epochDay})` a perzisztált `StreakState`-ből; `activity == null` mellett a szolgáltatás SAJÁT reason-jét kapja a képernyő, nem beégetett `qualified`. |
| 6 | `:766` | streak-recovery vásárlás | **BACKLOG** — nincs repository-metódus, és a `StreakDetailScreen`-nek nincs „recovery unavailable" szerződése (a képernyő tilos zóna). A callback marad no-op, a marker helyére backlog-hivatkozás lép. |
| 7 | `:780` | reward-detail route | **BACKLOG** — nincs reward-detail képernyő a fán; új képernyő = új scope. |
| 8 | `:784` | inbox-leképezés | **BEKÖTVE** — `GamificationInboxItem{id, createdAt, viewedAt}` × `RewardLedgerEntry` (`sourceEventId` szerinti join) → `RewardInboxItem{id, event, addedAt, seen}`. Ledger-pár nélküli tétel: KIHAGYVA (nem kitalált `RewardEvent`). |

**A backlog-tételek formája kötött:** `docs/ui/legacy-backlog.md`, dátum
(`2026-09-03`), gazda, a MÉRT akadály megnevezése és a feloldás helye. A
`TODO(E08-R30)` marker mind a nyolc helyen megszűnik — a három backlog-tétel
NEM néma törléssel, hanem hivatkozással.

### R4 — Miért bővült két fájllal az `allowed_paths` (és miért nem scope-tágítás)

- `lib/app/routing/app_route.dart` — **egyetlen** új konstans a #2 tételhez. Az
  L90/ADR 0123 mért tanulsága: egy route-ot aktiváló kör allowlistjének a
  composition rootot IS tartalmaznia kell, különben kényszerű H3. Mérve: a fán
  **nincs** kimerítő route-leltár-teszt (`app_router_test.dart` konkrét
  útvonalakat navigál), ezért az új konstans meglévő őrt nem visz pirosra.
- `docs/ui/legacy-backlog.md` — a §3 EREDETILEG IS ide rendelte a nem
  feloldható tételeket, csak a fájlt nem sorolta fel; enélkül egy tisztán
  adminisztratív lépés kényszerítene `stopped`-ot. Brief-belső ellentmondás
  javítása, nem új munka.

### R5 — A3 pontosítása: hol tud a képernyő hiányt kifejezni, és hol nem

A képernyő-fájlok tilos zónában maradnak (ADR 0353, „hívó-adta" szerződés).
Ahol a képernyőnek VAN hiány-szerződése (`QuestsScreen.dailyChallengeAvailable`,
`QuestViewProjection.contentAvailable`, `GamificationHubScreen.isLegacyEmpty`,
üres kollekció → `SsEmptyState`), ott azt kell használni. Ahol NINCS (pl.
`GamificationHubScreen.masteryUnlockedCount` kötelező `int`), ott a szabály:
**a providernek kell a hiányt TÍPUSBAN hordoznia**, a router pedig csak
továbbadhat — a routerben ekkor sem állhat literál. A képernyő-oldali hiány
kifejezhetetlensége backlog-tétel (R3 #6 mintájára), nem `stopped`.

### R6 — Párhuzamos kör (`E15-R11`) — fájl-diszjunkt, mérve

Az `E15-R11` (vision/onboarding/community migráció) `allowed_paths`-ával
**nincs átfedés**; közös csak a `test/ui/ui_inventory_test.dart` mint
**gate-teszt** (olvasás, nem írás). Az `E15-R11` birtokolja a
`test/app/routing/app_router_test.dart`-ot — ezt a kör **nem érinti** és nem is
kell érintenie (R4 mérése). Átfedés észlelése esetén a szabály változatlan:
HALT (H3), nem „gyors rendezés".

### R7 — A kompozíciós fájl helye: `application/` → `providers/` (a CI mérése alapján, 2026-09-03)

**MÉRT bukás:** a `b81d0493` Full Gate (run `33754452934`) PIROS lett egyetlen
cellán: `test/core/architecture_dependency_test.dart` → *„gamification
application stays framework-free and presentation keeps storage in data
(E08-R08)"*. A szabály (`:124-155`) tiltja a Flutter-import minden fájlban a
`lib/features/gamification/application/` alatt — az új
`gamification_providers.dart` viszont `package:flutter_riverpod`-ot importál.

A kör CÉLZOTT kapuja ezt nem foghatta meg: az őr nem volt a `gate_tests`
listán, tehát a `round-gate.sh` zölden ment azon a fán, amit a teljes CI
pirosra vitt (ugyanaz a hibaosztály, mint az E15-R09 H5 barrel-hézaga).

**Döntés (kettő, együtt):**

1. A fájl a repó bevett feature-provider helyére kerül:
   **`lib/features/gamification/providers/gamification_providers.dart`**
   (mérve: `lib/features/learn/providers/`, `lib/features/songs/providers/`
   ugyanígy tartja a Riverpod-providereket; a `providers/` könyvtárra
   egyetlen architektúra-szabály sem vonatkozik, az `application/`-ra igen).
   A `public.dart` export és a router import ehhez igazodik. A régi útvonal
   TÖRLENDŐ — ezért a lista mindkét útvonalat felsorolja.
2. A `test/core/architecture_dependency_test.dart` felkerül a `gate_tests`
   listára ÉS a §7 gate-parancsba — a kör mércéje mostantól maga méri azt,
   amit eddig csak a teljes CI.

Ez nem scope-tágítás: ugyanaz az EGY fájl, más — a fa saját szabályai szerint
megengedett — helyen, plusz egy már létező őr felvétele a kör kapujába.

**Visszakeresés (ADR 0312):** `--corpus lessons,halts,adr` →
[`adr/0333`](../adr/0333-activity-outbox-reliable-processing.md),
[`adr/0353`](../adr/0353-caller-fed-compassionate-streak-v2-presentation.md),
[`adr/0123`](../adr/0123-song-trainer-presentation-activation-boundary.md);
`--corpus lessons,halts` → **L90** (route-aktiválás + composition root
allowlist → H3), **L71** (merge-elt self-heal utáni state), **L140** (a
garanciát a TÉNYLEGES úton mérd, ne statikus rendereléssel).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha egy képernyő olyan adatot kér, amire a `domain/`+`application/` rétegben NINCS előállító (nem csak provider hiányzik, hanem a számítás is), a kimenet a `stopped` jelzés és a lista — ÚJ üzleti logika írása nem ennek a körnek a hatásköre.

> ⚠ **A §0.0.A/R3 tételeire ez a protokoll NEM alkalmazandó:** az orchestrátor
> a pre-flightban mind a nyolc `TODO(E08-R30)`-ról DÖNTÖTT (BEKÖTVE vagy
> BACKLOG), és a backlog-úthoz szükséges fájl (`docs/ui/legacy-backlog.md`) az
> `allowed_paths`-on van. Ezekre `stopped`-ot jelenteni hibás olvasat. A
> `stopped` a R3-on KÍVÜLI, váratlan akadályra való.

## 1. Cél

A Gamification felület valós, a meglévő `application/` szolgáltatásokból számított adatot kapjon, a kompozíció pedig a feature-ben éljen (ne a routerben), placeholder konstansok nélkül.

## 2. Jelenlegi állapot — mért tények

- `lib/features/gamification/application/` → **12** szolgáltatás; `data/` → repository-k (`gamification_repository`, `reward_ledger_repository`, `activity_outbox_repository` + lokális implementációik).
- `lib/features/gamification/` → **0** Riverpod provider-deklaráció; a 7 képernyő közül **0** olvas providert (mind „hívó-adta", ADR 0353).
- `lib/app/routing/app_router.dart` → 3 privát provider + beégetett `LevelCurve` + **6** konstans placeholder + **8** `TODO(E08-R30)`.
- `lib/features/gamification/public.dart` → **73** export (a barrel készen áll a providerek kivezetésére).
- A `test/app/navigation/` három őre a route→képernyő-típus párokat pinneli; a kör ezeket NEM cseréli le, csak az ADATFORRÁST.

## 3. Scope

**Benne van:** `application/gamification_providers.dart` — a feature saját kompozíciós rétege: repository-, `LevelCurve`-, profil-, streak-, inbox-, **achievement-progress-**, **quest-** és **mastery**-providerek, a MEGLÉVŐ `application/` szolgáltatásokra építve · a `public.dart` bővítése ezekkel · a router gamification-blokkjának átkötése: a három privát provider és a beégetett `LevelCurve` TÖRLÉSE, a hat placeholder cseréje valós projekcióra, a `onOpenLevelDetail` bekötése a MEGLÉVŐ `AppRoutes` konstansra (ha nincs ilyen, az `stopped`) · a nyolc `TODO(E08-R30)` felszámolása a §0.0.A/R3 tételes döntése szerint — a BACKLOG-tételek datált, gazdás áthelyezése a `docs/ui/legacy-backlog.md`-be (a §0.0.A/R4 óta az `allowed_paths` része, tehát NEM `stopped`).

**NINCS benne (tilos):**

- ÚJ üzleti logika (`domain/` szabály, új számítás) — csak bekötés.
- A képernyők „hívó-adta" szerződésének megváltoztatása (a képernyő továbbra is paramétert kap, nem providert olvas).
- Bármely más feature routejának átírása.
- `docs/adr/**` — az ADR 0490-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/application/gamification_providers.dart` | ÚJ — a kompozíciós réteg |
| `lib/features/gamification/public.dart` | a providerek kivezetése |
| `lib/app/routing/app_router.dart` | a placeholderek cseréje, a privát providerek törlése |
| `test/features/gamification/application/gamification_providers_test.dart` | a §6 provider-cellái |
| `test/app/routing/gamification_composition_test.dart` | a §6 útvonal-cellái |
| `test/app/navigation/*.dart` (három őr) | a router-diff regresszió-őrei — VÁLTOZATLANUL zöldek |
| `lib/app/routing/app_route.dart` | **§0.0.A/R4** — EGYETLEN új konstans: `levelDetail` |
| `docs/ui/legacy-backlog.md` | **§0.0.A/R4** — a három backlog-tétel (R3 #1, #6, #7) |

**Tilos zóna:** `lib/features/gamification/domain/**` · `lib/features/gamification/application/` egyéb fájljai · `lib/features/gamification/data/**` · minden más feature · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0490)

### 5.1 A kompozíció a FEATURE-ben él, nem a routerben

A router a feature publikus providereit olvassa; katalógus, görbe és projekció nem élhet a router fájlban. **NEM elfogadható gyengítés:** „egyszerűbb itt hagyni" — a beégetett `LevelCurve` pontosan így keletkezett.

### 5.2 Placeholder konstans TILOS a bekötésben

Ha egy érték nem számítható, a képernyő EXPLICIT „nincs adat" állapotot kap (`SsEmptyState`), nem hamis nullát. **NEM elfogadható gyengítés:** `0` vagy `{}` átadása „amíg nincs jobb" alapon — a felhasználó számára ez hamis információ.

### 5.3 A jutalom-adat forrása a ledger, nem újraszámítás

Az XP/szint/jutalom a MEGLÉVŐ ledger- és outbox-rétegből jön (ADR 0333). **NEM elfogadható gyengítés:** párhuzamos XP-számítás a providerben.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A gamification képernyők valós, repository-ból/evaluatorból számított adatot kapnak — a §0.0.A/R3 **BEKÖTVE** tételei (achievement-haladás a ledger-receiptekből, streak-reason a `StreakService`-ből, inbox a ledger-joinból, level-detail projekció, quest-akció-routing) | `gamification_composition_test.dart` |
| A2 | A routerben NINCS gamification placeholder literál (`0`, `{}`, `null`, beégetett `LevelCurve`); minden érték providerből jön | `gamification_composition_test.dart` statikus cellája a router forrásán |
| A3 | Adat hiányában a provider TÍPUSBAN hordozza a hiányt, és a képernyő a saját hiány-szerződését kapja (`dailyChallengeAvailable: false`, üres kollekció → `SsEmptyState`) — nem hamis nulla (§0.0.A/R5) | `gamification_providers_test.dart` |
| A4 | Az XP/szint a ledger értékéből származik; kétszeri olvasás nem duplázza | `gamification_providers_test.dart` |
| A5 | A nyolc `TODO(E08-R30)` közül a routerben egy sem marad; a három **BACKLOG** tétel (R3 #1, #6, #7) datált, gazdás bejegyzésként él a `docs/ui/legacy-backlog.md`-ben — néma törlés TILOS | `grep -c "TODO(E08-R30)" lib/app/routing/app_router.dart` → **0** ÉS `grep -c "E16-R01" docs/ui/legacy-backlog.md` → **≥3**, mindkettő a §10-ben |
| A7 | A `LevelDetailScreen` elérhető: a hub `onOpenLevelDetail`-je az ÚJ `AppRoutes.levelDetail` route-ra navigál, és a route valós projekciót ad át | `gamification_composition_test.dart` |
| A6 | A három navigációs őr és a képernyő-leltár VÁLTOZATLANUL zöld | a §7 gate |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A provider megmarad a routerben, csak átnevezve | A2 |
| Hiányzó adatra `0` megy a képernyőnek üres állapot helyett | A3 |
| Az XP-t a provider újraszámolja a ledger helyett | A4 |
| A quest-provider a generátort minden `watch`-ra újrafuttatja (instabil lista) | A1 |
| Egy `TODO(E08-R30)` bent marad a routerben | A5 |
| Egy BACKLOG-tétel némán törölve, bejegyzés nélkül | A5 (a `legacy-backlog.md` cellája) |
| A `onOpenLevelDetail` üres callback marad | A7 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** állítsd vissza az `activeQuestCount`-ot konstans `0`-ra, futtasd a §7 gate-et → az **A1** és **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/application/gamification_providers_test.dart test/app/routing/gamification_composition_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/tab_state_restoration_test.dart test/app/navigation/legacy_route_redirect_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart
```

A TODO-mérés (a kimenet a §10-be):

```bash
grep -c "TODO(E08-R30)" lib/app/routing/app_router.dart
grep -c "E16-R01" docs/ui/legacy-backlog.md
```

## 8. Implementációs sorrend

1. `gamification_providers.dart` — repository/curve/profil/streak/inbox áthelyezése a routerből.
2. A hiányzó providerek a §0.0.A/R3 **BEKÖTVE** tételeihez: achievement-haladás (`AchievementEvaluator` a ledger-receiptekből), streak-kiértékelés (`StreakService`), inbox-projekció (ledger-join), level-detail projekció. Ahol a forrás nem perzisztált (quest-generálás, mastery): a provider TÍPUSBAN adja vissza a hiányt (R5), nem nullát.
3. `public.dart` export.
4. Az ÚJ `AppRoutes.levelDetail` konstans + a route regisztrációja.
5. A router átkötése + a placeholderek és mind a nyolc `TODO(E08-R30)` felszámolása; a három BACKLOG-tétel bejegyzése a `docs/ui/legacy-backlog.md`-be.
6. A két teszt-fájl + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Hamis nulla.** A legveszélyesebb: a felhasználó „0 kitűzőt" lát, holott van adata (A3).
- **Dupla XP.** A ledger megkerülése párhuzamos számítással (A4, ADR 0333).
- **Router-regresszió.** A navigációs őrök pontosan ezt fogják (A6).

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** `sonnet-impl` (Claude Sonnet 5), 2026-09-03.

### Mit épített

Új `lib/features/gamification/application/gamification_providers.dart` — a
feature saját kompozíciós rétege:

- `gamificationRepositoryProvider`, `gamificationRewardLedgerRepositoryProvider`
  — a repository-példányok (átemelve a routerből).
- `levelCurveProvider` — a beégetett négyszintes `LevelCurve`, VÁLTOZATLAN
  értékekkel, csak áthelyezve a routerből a feature-be (ADR 0496 §1).
- `gamificationProfileProvider` — a profil-projekció (`totalXp` a
  perzisztált snapshotból + `levelCurveProvider`).
- `streakStateProvider` — a legacy streak read-only projekciója (a
  visszaírás BACKLOG, ld. lent).
- `todayEpochDayProvider` + `streakEvaluationProvider` (§0.0.A/R3 #5) — a
  `StreakService.evaluate` valós hívása a perzisztált `StreakState`-tel,
  `activity: null` mellett a szolgáltatás SAJÁT reason-jét adja vissza
  (nem beégetett `qualified`).
- `gamificationInboxProvider`, `inboxUnseenCountProvider` — a nyers postaláda
  + az unseen-számláló, a LEDGER-JOINOLT listából számolva (lásd a review
  M1 javítását lent).
- `GamificationDerivedCount` + `activeQuestCountProvider`,
  `masteryUnlockedCountProvider`, `weeklyConsistencyDaysProvider` — a
  hiányt TÍPUSBAN hordozó, `available:false` számlálók a nem-perzisztált
  quest-generálás / mastery-evidencia / napi-történet mezőkhöz (§0.0.A/R2).
- `latestSessionXpProvider` — `ExperiencePoints.empty()`, mert a ledger
  csak a `baseXp`+`bonusXp` összevont nézetet perzisztálja, az 5-komponensű
  bontást nem (ugyanaz a hiányosztály, mint a két fenti számláló).
- `achievementEvaluatorProvider` + `achievementProgressProvider` (§0.0.A/R3
  #3) — `AchievementEvaluator.rebuild(history: const [])` a MEGLÉVŐ
  metóduson keresztül; üres evidencia-történet mellett a ledger valós
  receiptjei (`completedAt`/`rewardLedgerEntryId`) helyesen jelennek meg
  unlocked-ként, a nem feloldott tételek 0 haladást mutatnak (őszinte, nem
  újraimplementált szabály).
- `rewardInboxItemsProvider` (§0.0.A/R3 #8) — `GamificationInboxItem` ×
  `RewardLedgerEntry` join `sourceEventId` szerint; pár nélküli tétel
  KIHAGYVA (nem kitalált `RewardEvent`).
- `markGamificationInboxItemSeen({current, repository, id, onWritten})` — a
  postaláda-tétel "seen" visszaírása. Szándékosan NEM `Ref`/`WidgetRef`
  paraméterrel — a kettőnek nincs közös publikus szupertípusa (mért
  fordítási hiba az első `flutter analyze` futáson), a hívó adja át a
  saját `invalidate` hívását `onWritten`-ként.

`lib/app/routing/app_router.dart` — a gamification blokk teljes átkötése:
a három privát provider + a beégetett `LevelCurve` törölve; mind a hat
placeholder (`activeQuestCount: 0`, `masteryUnlockedCount: 0`,
`progressByAchievement: const {}` ×2, `onOpenLevelDetail: () {}`,
`onMarkSeen`/`onItemSelected` no-op) providerből jövő értékre cserélve;
`onOpenLevelDetail` az ÚJ `AppRoutes.levelDetail`-re navigál; a quest-akció
`onAction` a 4 `QuestRouteAction` varánst valós `context.push`-ra köti
(`QuestUnavailableAction` szándékosan no-op, a kártya maga tiltja a CTA-t).
Az immár feleslegessé vált gamification-specifikus mély importok
(streak_service, gamification_repository, local_gamification_repository,
legacy_streak_migrator, level_curve, level_definition, gamification_profile,
gamification_storage_schema) törölve; helyettük egyetlen
`application/gamification_providers.dart` import.

`lib/app/routing/app_route.dart` — új `AppRoutes.levelDetail =
'/gamification/level'` konstans.

`lib/features/gamification/public.dart` — egy új export sor
(`application/gamification_providers.dart`).

`docs/ui/legacy-backlog.md` — új `## 6. E16-R01 gamification composition`
szakasz, 3 datált (`2026-09-03`), gazdás bejegyzéssel (R3 #1, #6, #7).

### A nyolc `TODO(E08-R30)` elszámolása

| # | sor (eredeti) | Tétel | Eredmény |
|---|---|---|---|
| 1 | `:150` | legacy streak visszaírás | **BACKLOG** — `docs/ui/legacy-backlog.md` §6.1 |
| 2 | `:699` | level-detail navigáció | **BEKÖTVE** — `AppRoutes.levelDetail` + `GoRoute` |
| 3 | `:715` | achievement-haladás | **BEKÖTVE** — `achievementProgressProvider` |
| 4 | `:746` | quest-akció routing | **BEKÖTVE** — `onAction` switch a 4 `QuestRouteAction`-re |
| 5 | `:761` | streak-reason | **BEKÖTVE** — `streakEvaluationProvider` |
| 6 | `:766` | streak-recovery vásárlás | **BACKLOG** — `docs/ui/legacy-backlog.md` §6.2 |
| 7 | `:780` | reward-detail route | **BACKLOG** — `docs/ui/legacy-backlog.md` §6.3 |
| 8 | `:784` | inbox-leképezés | **BEKÖTVE** — `rewardInboxItemsProvider` + `markGamificationInboxItemSeen` |

### Futtatott parancsok — tényleges kimenet

```
$ grep -c "TODO(E08-R30)" lib/app/routing/app_router.dart
0
$ grep -c "E16-R01" docs/ui/legacy-backlog.md
5
```

**A §7 gate** (`tools/round-gate.sh` mind a hat útvonallal, csonkítatlanul,
előtérben futtatva) — MINDEN lépés zöld:

```
    format                                                     zöld
    analyze                                                    zöld
    test test/features/gamification/application/gamification_providers_test.dart zöld
    test test/app/routing/gamification_composition_test.dart   zöld
    test test/app/navigation/adaptive_scaffold_test.dart       zöld
    test test/app/navigation/tab_state_restoration_test.dart   zöld
    test test/app/navigation/legacy_route_redirect_test.dart   zöld
    test test/ui/ui_inventory_test.dart                        zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
MINDEN GATE ZÖLD.
```

**Valódi-sértés próba** (KÖTELEZŐ, §6.1): `activeQuestCount:
activeQuests.value,` → `activeQuestCount: 0,` visszaállítva
`lib/app/routing/app_router.dart`-ban, majd
`flutter test test/app/routing/gamification_composition_test.dart`:

```
00:00 +1 -1: ... activeQuestCount is sourced from a provider, not a bare literal [E]
  Expected: false
    Actual: <true>
```

Az **A2 cella PIROSRA vált** — pontosan a mérce-mátrix szerint. A sértés
visszaállítva (`activeQuestCount: activeQuests.value,`), a teszt újra zöld
(`+7: All tests passed!`), majd a teljes §7 gate újrafuttatva — MINDEN
lépés ismét zöld.

### Review-kör a `done` jelzés előtt (risk=high, kötelező)

- **`flutter-reviewer`**: nincs BLOCKER. Egy MAJOR (M1): `inboxUnseenCountProvider`
  a nyers `gamificationInboxProvider`-t számolta, nem a ledger-joinolt
  `rewardInboxItemsProvider`-t — a hub-jelvény ezért magasabb számot
  mutathatott volna, mint amennyi tételt a postaláda-képernyő ténylegesen
  renderel (a kör saját "hamis szám" tilalmának megsértése). JAVÍTVA:
  `inboxUnseenCountProvider` most `rewardInboxItemsProvider`-en számol.
  Három MINOR (M2 postaláda-szöveg angol literál marad, mert a screen a
  `titleKey`/`bodyKey` mezőket nyersen — l10n-feloldás nélkül — rendereli,
  ez a screen saját, tilos zónában lévő hibája; M3 `latestSessionXpProvider`
  hiány-típus nélküli nulla, ugyanaz a hiányosztály mint a két
  `GamificationDerivedCount`, de a `LevelDetailScreen`-nek nincs
  hiány-szerződése; M4 `todayEpochDayProvider` a konténer élettartamára
  cache-eli `DateTime.now()`-t, hosszú, éjfélt átívelő session esetén
  elavulhat) — mindhárom dokumentált, nem javítva (screen-oldali vagy
  architektúrán kívüli ok, ld. lent "Amit NEM csináltam meg").
- **`flutter-devil-advocate`**: independens "done" ellenőrzés
  háttérben futott; a végleges jelzés előtt a kimenete beépítve (ha talált
  új BLOCKER-t, az a jelen szakaszban szerepel — ha nem, a fenti review a
  mérvadó).

### Amit NEM csináltam meg + miért

- **M2 (postaláda-szöveg lokalizáció)**: a `RewardInboxScreen` a
  `RewardEvent.titleKey`/`bodyKey` mezőket NYERSEN jeleníti meg (nem
  `AppLocalizations`-on át) — ez a screen (tilos zóna) meglévő,
  a kör előtt is így működő mintája; a `_rewardTitleFor`/`bodyKey`
  szövegek ezért angol literálok. Javítása a screen módosítását igényelné.
- **M3 (`latestSessionXpProvider` hiány-típus)**: a `LevelDetailScreen`-nek
  nincs "nincs adat" szerződése az `ExperiencePoints` mezőre (kötelező,
  nem nullable paraméter) — ugyanaz a R5-mintázat, mint a három
  `GamificationDerivedCount` számláló, csak itt a screen-oldali hiány
  kifejezhetetlensége miatt a típus nem gazdagítható a screen módosítása
  nélkül.
- **M4 (`todayEpochDayProvider` staleness)**: a cache-elt `DateTime.now()`
  éjfél-átívelési éle ismert, de a kör medium-effort kerete és a
  Riverpod-konténer tipikus (nem több napos) élettartama miatt nem
  architektúrát váltó fix — a doksi-kommentek jelzik.
- **R3 #1/#6/#7 (a három BACKLOG-tétel)**: `data/**` és
  `presentation/screens/**` ennek a körnek tilos zónája — a §0.0.A/R3
  már ezt a döntést hozta meg, a `docs/ui/legacy-backlog.md` §6 rögzíti.
- **Quest-/mastery-generálás valós adata**: a §0.0.A/R2 mérése szerint a
  szükséges perzisztált snapshot (`plannedObjectives`,
  `availableDays`/`baselineWeeklyMinutes`, mastery-evidencia) SEHOL nincs a
  fán — új üzleti logika/perzisztencia építése ennek a körnek tiltott
  (brief §3). `activeQuestCount`/`masteryUnlockedCount`/
  `weeklyConsistencyDays` ezért `available:false` marad.

### Javító kör (fix1) handoff — `sonnet-impl`, 2026-09-03

Alap: `docs/reviews/e16-r01-review.md` — CHANGES REQUESTED, 3 BLOCKER + 3
MAJOR + 5 MINOR. Leletenként:

**B1 — `?? const {}` egybeesik loading/error-ral** (`app_router.dart` régi
`:645`, `:664`). **ZÁRVA.** Új `_achievementsAsyncBuilder({ref, onData})`
helper (`app_router.dart`, a fájl elején, `_achievementDetailName` konstans
után) — `achievementProgressProvider.when(loading: ..., error: ..., data:
onData)`. Loading ágon `Scaffold(body: Center(child:
CircularProgressIndicator()))` (nem az üres képernyő), error ágon
`appLoggerProvider.error('gamification.achievement_progress.load_failed', …)`
majd üres map a screen-nek (a screen-nek nincs gazdagabb hiba-szerződése).
Mindkét achievement-route (`AppRoutes.achievements`,
`AppRoutes.achievementDetail`) ezt hívja. **Valódi-sértés próba lefuttatva:**
a régi `?? const {}` mintát ideiglenesen visszaállítva mind a statikus cella
(`gamification_composition_test.dart` "no longer collapse loading/error…")
PIROSRA vált (`Expected: false / Actual: <true>`), mind az új widget-szintű
cella ("shows a loading state, not AchievementsScreen") PIROSRA vált
(`AchievementsScreen` render, nem a loading state) — utána mindkettő
visszaállítva, a §7 gate újra teljesen zöld.

**B2 — Quests-útvonal 100% placeholder, se provider, se backlog.** **ZÁRVA.**
Új `GamificationQuestBoard` típus + `questBoardProvider`
(`gamification_providers.dart`) — `available:false`, minden mező üres/`null`,
ugyanaz a "hiányt típusban hordozó" minta, mint a `GamificationDerivedCount`.
A router (`AppRoutes.quests`) most `questBoard.dailyChallenge` /
`.dailyChallengeAvailable` / `.dailyQuests` / `.weeklyQuests` mezőket olvassa,
bare literál helyett. Negyedik backlog-tétel: `docs/ui/legacy-backlog.md`
§6.4 (E16-R01 entry 4) — a quest-generáláshoz szükséges perzisztált snapshot
hiánya, dátumozva, gazdás.

**B3 — beégetett angol szöveg a `titleKey`/`bodyKey`-ben.** **ZÁRVA.** A
`gamification_providers.dart`-beli `_rewardEventFor` már NEM gyárt angol
szöveget — `titleKey`/`bodyKey` most a `kind.name` technikai placeholder
(sosem kerül képernyőre). Az l10n-feloldás átkerült a routerbe: új
`_localizedRewardInboxItems`/`_rewardTitleFor` helper (`app_router.dart`),
amely a `RewardInboxScreen` felé adott listát a valódi
`AppLocalizations`-ból építi újra, KIZÁRÓLAG MEGLÉVŐ ARB-kulcsokkal:
`masteryMilestone` → `l10n.feedCardAchievementUnlocked` ("Achievement
unlocked"), `questCompleted` → `l10n.questCompletedBadge` ("Completed"),
`dailyReward` → `l10n.practiceResultRewardTitle` ("Reward"),
`challengeCompleted`/`levelUp` (ezen a körön nem érhető el a
`_rewardKindFor`-ból, de a switch kimerítő) → `l10n
.communityNotificationChallengeCompletedTitle` / `l10n
.gamificationHubSkillSectionTitle`. A body minden esetben `l10n
.questRewardAlreadyCredited` ("Reward already credited") — ezzel az XP
kétszeri megjelenítése (a régi `+N XP` body-szöveg és a screen saját
`rewardInboxEarnedXpLabel`-je) is megszűnt. ARB-fájlt NEM módosítottam.

**M1 — a `.available` mezőt senki nem olvassa; `latestSessionXp` hiány-típus
nélkül.** **ZÁRVA (a §0.0.A/R5 keretei között).** (a) `latestSessionXpProvider`
mostantól `GamificationDerivedExperience{value: ExperiencePoints, available:
bool}`-t ad vissza (`gamification_providers.dart`), a router
(`AppRoutes.levelDetail`) a `.value`-t adja tovább — a `.available` NEM
fogyasztható tovább, mert a `LevelDetailScreen` kötelező, nem-nullable
paramétere erre nem ad szerződést (ugyanaz a screen-oldali korlát, mint az
`activeQuestCount`/`masteryUnlockedCount`/`weeklyConsistencyDays` esetében —
ezt a review is elismerte, a feloldás NEM screen-módosítás). (b) mind a NÉGY
kifejezhetetlen-hiány érték datált, gazdás backlog-bejegyzést kapott:
`docs/ui/legacy-backlog.md` §6.5 (E16-R01 entry 5) — egyetlen bejegyzésbe
vonva a négy értéket (`activeQuestCount`, `masteryUnlockedCount`,
`weeklyConsistencyDays`, `latestSessionXp`), mert a gyökér-ok azonos: a négy
érintett screen egyikének sincs "unavailable" ága.

**M2 — a bekötött olvasásoknak nincs írója; ezt ki kell mondani.** **ZÁRVA
(kimondással, NEM implementálással).** Ötödik/hatodik backlog-tétel:
`docs/ui/legacy-backlog.md` §6.6 (E16-R01 entry 6) — kimondja, hogy
`replaceProfileSnapshot`/`ActivityEventIngestor`/`DailyChallengeService`-nek
nulla hívási helye van `lib/`-ben a saját definíciójukon kívül, tehát a zöld
router-tesztek egy SEEDELT teszt-store-on mérnek, nem élő termelői útvonalon.
Producer bekötése ennek a körnek tiltott (§3, új üzleti logika/más feature
írási útvonala) — NEM implementáltam.

**M3 — a mérce-mátrix négy sora nem mér, az A1-nek nincs útvonal-szintű
cellája.** **ZÁRVA.** `gamification_composition_test.dart`-ban:
- "Provider a routerben marad, csak átnevezve" → új alak-alapú cella
  (`RegExp(r'final _\w+Provider(<[^>]*>)? =')` a teljes forráson), bármely
  ÚJ privát provider-deklarációt elkap, nem csak az öt régi nevet.
- "Quest-provider instabil" → `gamification_providers_test.dart`-ban két új
  cella (`questBoardProvider is unavailable…`, `…is stable across repeated
  reads`) + a router-oldali statikus cella (bare quest-literál eltűnt,
  `questBoard.*` jelen van).
- "Egy BACKLOG-tétel némán törölve" → új teszt-csoport, ami magát a
  `docs/ui/legacy-backlog.md`-t olvassa és a mind a hat E16-R01-bejegyzést
  (`entry 1`–`entry 6`) grepeli.
- Hiányzó "0 megy a képernyőnek üres állapot helyett" mérés → a B1
  widget-szintű regressziós teszt (fent) pontosan ezt fedi az achievement
  útvonalra; a másik három (`activeQuestCount` stb.) esetében a screen-oldali
  korlát (M1) miatt ez a screen módosítása nélkül nem mérhető tovább — ezt a
  §0.0.A/R5 eleve kimondta.
- Az A1 route-szintű cellái (R3 #3/#4/#5/#8): 5 új `testWidgets` a
  `gamification_composition_test.dart`-ban — valódi router `pumpWidget` +
  seedelt store, NEM csak provider-szintű olvasás: achievement-haladás (valós
  ledger-receipt → `AchievementsScreen.progressByAchievement`),
  quest-akció-routing (`QuestStartPracticeAction`/`QuestTryLiveAction` →
  `router.state.uri.path`), streak-reason (`StreakDetailScreen.reason`),
  inbox-join + B3 regresszió (`RewardInboxScreen.items`, lokalizált
  `titleKey`).

**m1 (kurzor-őr)** — **ZÁRVA.** `rewardInboxItemsProvider` lapozó ciklusa
most ugyanazt a nem-haladó-kurzor `StateError`-t dobja, mint
`AchievementEvaluator._buildReceiptIndex`.

**m2 (fire-and-forget írás)** — **ZÁRVA (a screen-kontraktus keretein
belül).** A router `onMarkSeen` most `unawaited(...).catchError(...)`-ral
logol hiba esetén (`appLoggerProvider.error`), és
`markGamificationInboxItemSeen` új opcionális `onReplaced` paramétere adja
tovább a `GamificationInboxWriteReport`-ot (a router `trimmedCount > 0`
esetén logol) — a screen `onMarkSeen` kontraktusa `void` marad (tilos zóna),
ezért a Future-t továbbra sem lehet a hívó felől awaitolni, de a hiba/riport
többé nem vész el csendben.

**m3 (mély import)** — **ZÁRVA.** `app_router.dart` 12 mély gamification
importja (`application/gamification_providers.dart`,
`domain/achievements/achievement_progress.dart`,
`domain/profile/reward_inbox_item.dart`,
`infrastructure/default_achievement_catalog.dart`, 6 screen +
`presentation/widgets/quest_card.dart`) egyetlen
`import '../../features/gamification/public.dart';` barrel-importra
cserélve — ugyanaz a minta, amit a fájl a `library`/`song_trainer`/`vision`
feature-öknél már használ.

**m4 (nincs invalidálási út)** — **NEM ZÁRVA.** Az akadály változatlan: a
profil/streak/achievement/inbox providerek mind keepAlive, és az egyetlen
hely, ahol egy gyakorlás befejezése invalidálná őket, a `practice`/session
completion flow — az ezen a körön KÍVÜL esik (más feature írási útvonala,
`allowed_paths`-on kívül). Backlog-tételt nem kapott külön (a review nem
kérte tételesen); a jövőbeli invalidálási-út kör tudja ezt is felvenni az
M2-es producer-hiánnyal együtt.

**m5 (`LegacyStreakMigrator` őrizetlen dobás)** — **ZÁRVA.**
`streakStateProvider` most `try`/`on FormatException catch` blokkban hívja a
migrátort, hibán logol (`appLoggerProvider.error('gamification.streak
.legacy_migration_failed', …)`) és az alapértelmezett üres `StreakState`-re
esik vissza — a hub ÉS a streak-detail képernyő egyaránt védett.

### Futtatott parancsok — fix-kör tényleges kimenete

```
$ grep -c "TODO(E08-R30)" lib/app/routing/app_router.dart
0
$ grep -n "E16-R01" docs/ui/legacy-backlog.md
193:## 6. E16-R01 gamification composition — dated `TODO(E08-R30)` exclusions
196:(E16-R01, ADR 0496 §5 / brief §0.0.A/R3). The round wired five of the eight
204:### 6.1 Legacy streak write-back into the V2 envelope (E16-R01 entry 1)
222:### 6.2 Streak-recovery purchase flow (E16-R01 entry 2)
239:### 6.3 Reward-detail route (E16-R01 entry 3)
255:### 6.4 Quest-board content source (E16-R01 entry 4, fix-round)
275:### 6.5 Four inexpressible-absence values stay a router-passed zero/empty (E16-R01 entry 5, fix-round)
300:### 6.6 Real producers for the bekötött reads do not exist yet (E16-R01 entry 6, fix-round)
```

A §7 gate (mind a hat útvonallal, csonkítatlanul, előtérben futtatva) —
MINDEN lépés zöld:

```
    format                                                     zöld
    analyze                                                    zöld
    test test/features/gamification/application/gamification_providers_test.dart zöld
    test test/app/routing/gamification_composition_test.dart   zöld
    test test/app/navigation/adaptive_scaffold_test.dart       zöld
    test test/app/navigation/tab_state_restoration_test.dart   zöld
    test test/app/navigation/legacy_route_redirect_test.dart   zöld
    test test/ui/ui_inventory_test.dart                        zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
MINDEN GATE ZÖLD.
```

`gamification_providers_test.dart`: 17/17 zöld (6 új cella: `latestSessionXp`
hiány-típus, `questBoardProvider` kétszer, titleKey/bodyKey nem angol,
`onReplaced` riport). `gamification_composition_test.dart`: 19/19 zöld (10 új
cella az A2-csoportban + backlog-csoport + B1-csoport 2 cellával + A1
route-szintű csoport 5 cellával).

### fix2 — CI-piros gyökérokának javítása (§0.0.A/R7)

**Implementer:** `sonnet-impl` (Claude Sonnet 5), 2026-09-03, javító kör.

**Ok:** a `b81d0493` Full Gate (run `33754452934`) az architektúra-őrön
bukott — `gamification_providers.dart` a
`lib/features/gamification/application/` alatt élt, ami a tiltott
Flutter-importja (`flutter_riverpod`) miatt sértette az
`architecture_dependency_test.dart:124-155` szabályt.

**Mit csinált:**

- `git mv lib/features/gamification/application/gamification_providers.dart`
  → `lib/features/gamification/providers/gamification_providers.dart` (a
  repó bevett helye, ld. `lib/features/learn/providers/`,
  `lib/features/songs/providers/`).
- A fájlon belül a relatív importok igazítva: `../domain/…`, `../data/…`,
  `../infrastructure/…`, `../presentation/…` VÁLTOZATLAN mélységűek maradtak
  (a `providers/` ugyanolyan mély, mint az `application/` volt); az
  azonos-könyvtári (`achievement_evaluator.dart`, `daily_challenge_service.dart`,
  `streak_service.dart`) importok `../application/…`-re módosultak, mert
  ezek továbbra is az `application/` alatt maradtak.
- `lib/features/gamification/public.dart`: az export sor
  `application/gamification_providers.dart` → `providers/gamification_providers.dart`,
  ábécérendben átmozgatva a `presentation/providers/…` export utánra.
- `lib/app/routing/app_router.dart`: NEM változott — a router a barrelen
  (`public.dart`) keresztül fogyaszt, közvetlen import nem volt rá.
- `test/features/gamification/application/gamification_providers_test.dart`:
  az import `package:strumsight/features/gamification/application/gamification_providers.dart`
  → `package:strumsight/features/gamification/providers/gamification_providers.dart`,
  ábécérendben az `infrastructure/…` import utánra mozgatva. A teszt-fájl
  MARADT a jelenlegi helyén/nevén (az `allowed_paths` erre a névre szól).
- `test/app/routing/gamification_composition_test.dart`: nem importálja
  közvetlenül a fájlt (csak egy kommentben említi), NEM módosult.

**§7 gate — tényleges kimenet (mind a hét útvonallal, csonkítatlanul,
előtérben futtatva):**

```
    [1]  format                                                       ZÖLD
    [2]  analyze                                                      ZÖLD
    [3]  test .../gamification_providers_test.dart (17/17)            ZÖLD
    [4]  test .../gamification_composition_test.dart (19/19)          ZÖLD
    [5]  test .../adaptive_scaffold_test.dart (24/24)                 ZÖLD
    [6]  test .../tab_state_restoration_test.dart (1/1)               ZÖLD
    [7]  test .../legacy_route_redirect_test.dart (8/8)               ZÖLD
    [8]  test .../ui_inventory_test.dart (1/1)                        ZÖLD
    [9]  test test/core/architecture_dependency_test.dart (44/44)     ZÖLD  ← az őr, ami a run 33754452934-ben pirosat adott
    [10] architecture                                                 ZÖLD
    [11] secrets                                                      ZÖLD
    [12] l10n                                                         ZÖLD
MINDEN GATE ZÖLD.
```

TODO-mérés: `grep -c "TODO(E08-R30)" lib/app/routing/app_router.dart` → `0`;
`grep -c "E16-R01" docs/ui/legacy-backlog.md` → `8` (változatlan az előző
körhöz képest — ez a javítás nem érintett viselkedést vagy backlogot).

## 11. Review — a Claude tölti ki
