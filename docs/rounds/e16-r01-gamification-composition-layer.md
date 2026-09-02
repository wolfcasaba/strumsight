# E16-R01 — A Gamification kompozíciós rétege: valós adat a felület mögé

- **Státusz:** PREPARED (előre megírva 2026-09-02, kód olvasva: `main @ 11d0d2bb`)
- **Típus:** Chapter 16 (Kompozíció és rollout), Kör 1
- **Kör-azonosító:** `E16-R01`
- **Branch:** `<motor>/e16-r01-gamification-composition-layer`
- **Előfeltétel:** `E15-R08` merge-elve (a gamification képernyők design-migrációja — a bekötés a MIGRÁLT képernyőkre megy)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0490` — a szám FOGLALT (Chapter 16 batch-tartomány: `0490`–`0494`).

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

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha egy képernyő olyan adatot kér, amire a `domain/`+`application/` rétegben NINCS előállító (nem csak provider hiányzik, hanem a számítás is), a kimenet a `stopped` jelzés és a lista — ÚJ üzleti logika írása nem ennek a körnek a hatásköre.

## 1. Cél

A Gamification felület valós, a meglévő `application/` szolgáltatásokból számított adatot kapjon, a kompozíció pedig a feature-ben éljen (ne a routerben), placeholder konstansok nélkül.

## 2. Jelenlegi állapot — mért tények

- `lib/features/gamification/application/` → **12** szolgáltatás; `data/` → repository-k (`gamification_repository`, `reward_ledger_repository`, `activity_outbox_repository` + lokális implementációik).
- `lib/features/gamification/` → **0** Riverpod provider-deklaráció; a 7 képernyő közül **0** olvas providert (mind „hívó-adta", ADR 0353).
- `lib/app/routing/app_router.dart` → 3 privát provider + beégetett `LevelCurve` + **6** konstans placeholder + **8** `TODO(E08-R30)`.
- `lib/features/gamification/public.dart` → **73** export (a barrel készen áll a providerek kivezetésére).
- A `test/app/navigation/` három őre a route→képernyő-típus párokat pinneli; a kör ezeket NEM cseréli le, csak az ADATFORRÁST.

## 3. Scope

**Benne van:** `application/gamification_providers.dart` — a feature saját kompozíciós rétege: repository-, `LevelCurve`-, profil-, streak-, inbox-, **achievement-progress-**, **quest-** és **mastery**-providerek, a MEGLÉVŐ `application/` szolgáltatásokra építve · a `public.dart` bővítése ezekkel · a router gamification-blokkjának átkötése: a három privát provider és a beégetett `LevelCurve` TÖRLÉSE, a hat placeholder cseréje valós projekcióra, a `onOpenLevelDetail` bekötése a MEGLÉVŐ `AppRoutes` konstansra (ha nincs ilyen, az `stopped`) · a nyolc `TODO(E08-R30)` felszámolása vagy — ha egy tétel bizonyítottan új üzleti logikát igényel — datált, gazdás áthelyezése a `docs/ui/legacy-backlog.md`-be (a §4 listán kívüli fájl, tehát ilyenkor `stopped` + jelentés).

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
| A1 | A gamification képernyők valós, repository-ból/evaluatorból számított adatot kapnak (achievement-progress, aktív questek, mastery, napi kihívás, heti konzisztencia) | `gamification_composition_test.dart` |
| A2 | A routerben NINCS gamification placeholder konstans (`0`, `{}`, `null`) és nincs beégetett `LevelCurve` | `gamification_composition_test.dart` statikus cellája a router forrásán |
| A3 | Adat hiányában a képernyő EXPLICIT üres állapotot kap, nem hamis nullát | `gamification_providers_test.dart` |
| A4 | Az XP/szint a ledger értékéből származik; kétszeri olvasás nem duplázza | `gamification_providers_test.dart` |
| A5 | A nyolc `TODO(E08-R30)` közül a routerben egy sem marad (a nem megoldható tétel `stopped` + backlog) | `grep -c "TODO(E08-R30)" lib/app/routing/app_router.dart` → **0**, a §10-ben |
| A6 | A három navigációs őr és a képernyő-leltár VÁLTOZATLANUL zöld | a §7 gate |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A provider megmarad a routerben, csak átnevezve | A2 |
| Hiányzó adatra `0` megy a képernyőnek üres állapot helyett | A3 |
| Az XP-t a provider újraszámolja a ledger helyett | A4 |
| A quest-provider a generátort minden `watch`-ra újrafuttatja (instabil lista) | A1 |
| Egy `TODO(E08-R30)` bent marad a routerben | A5 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** állítsd vissza az `activeQuestCount`-ot konstans `0`-ra, futtasd a §7 gate-et → az **A1** és **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/application/gamification_providers_test.dart test/app/routing/gamification_composition_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/tab_state_restoration_test.dart test/app/navigation/legacy_route_redirect_test.dart test/ui/ui_inventory_test.dart
```

A TODO-mérés (a kimenet a §10-be):

```bash
grep -c "TODO(E08-R30)" lib/app/routing/app_router.dart
```

## 8. Implementációs sorrend

1. `gamification_providers.dart` — repository/curve/profil/streak/inbox áthelyezése a routerből.
2. A hiányzó providerek: achievement-progress (`AchievementEvaluator`), questek (`daily`/`weekly` generátor), mastery (`MasteryEvaluator`), napi kihívás (`DailyChallengeService`).
3. `public.dart` export.
4. A router átkötése + a placeholderek és a `TODO`-k felszámolása.
5. A két teszt-fájl + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Hamis nulla.** A legveszélyesebb: a felhasználó „0 kitűzőt" lát, holott van adata (A3).
- **Dupla XP.** A ledger megkerülése párhuzamos számítással (A4, ADR 0333).
- **Router-regresszió.** A navigációs őrök pontosan ezt fogják (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
