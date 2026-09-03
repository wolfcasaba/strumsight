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
tools/round-gate.sh test/features/gamification/application/gamification_providers_test.dart test/app/routing/gamification_composition_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/tab_state_restoration_test.dart test/app/navigation/legacy_route_redirect_test.dart test/ui/ui_inventory_test.dart
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

## 11. Review — a Claude tölti ki
