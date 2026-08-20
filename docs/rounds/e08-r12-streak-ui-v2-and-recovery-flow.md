# E08-R12 — Streak felület V2 és visszatérés-folyamat

- **Státusz:** READY (pre-flight revízió 2026-08-20, kód olvasva: `main @ 7b5315b4`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 12
- **Kör-azonosító:** `E08-R12`
- **Branch:** `terra/e08-r12-streak-ui-v2-and-recovery-flow`
- **Előfeltétel:** `E08-R11` merge-elve (qualified day policy)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** [`0353`](../adr/0353-caller-fed-compassionate-streak-v2-presentation.md)

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/streak/screens/streak_screen.dart` (330 sor) TÉNYLEGES felépítését és a `test/features/streak/streak_screen_test.dart`-ot, valamint a `lib/app/routing/` útvonal-definícióját a `/streak` bejegyzésre — a kompatibilitás ezekre épül. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/presentation/screens/streak_detail_screen.dart",
  "lib/features/gamification/presentation/widgets/streak_status_card.dart",
  "lib/features/gamification/presentation/widgets/weekly_consistency_card.dart",
  "lib/features/gamification/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/gamification/presentation/streak_detail_screen_test.dart",
  "docs/rounds/e08-r12-streak-ui-v2-and-recovery-flow.md",
]
gate_tests = [
  "test/features/gamification/presentation/streak_detail_screen_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight revízió — 2026-08-20

1. **A tényleges státuszforrás pontosítva.** A `StreakState.graceState` ma
   kizárólag `StreakGraceState.none`; a megjeleníthető qualified / recovery /
   insufficient / planned-rest / grace / freeze / broken / already-qualified /
   clock-anomaly értékeket a `StreakService.evaluate()` tényleges return-ágai
   `StreakEvaluationReason`-ként produkálják (`streak_service.dart:104–203`).
   A V2 képernyő ezért hívó-adta `StreakState` + `StreakEvaluationReason` +
   kész `weeklyConsistencyDays` inputból renderel; nem talál ki vagy
   perzisztál új státuszt.
2. **A route-bizonyíték korrigálva.** A meglévő
   `test/features/streak/streak_screen_test.dart` közvetlenül pumpálja a
   `StreakScreen`-t, tehát nem bizonyítja a `/streak` route-ot. A repositoryban
   nincs route-cella erre. Az A5 ezért az új tesztből végzett forrásszintű
   regressziós őrrel méri az aktuális, pontos
   `GoRoute(path: AppRoutes.streak, builder: (_, _) => const StreakScreen())`
   wiringet; `lib/app/**` továbbra is változatlan és tilos.
3. **Nincs lifecycle-owner.** A tényleges `lib/features/gamification/**` és
   `lib/features/streak/**` hívási láncon nincs mic/lease/lock/acquire owner;
   az új passzív widget callbacken kívül nem szerez erőforrást.
4. **A numerikus a11y-cella kiszámolva.** A
   `python3 -c 'threshold=2.0; print({"below": threshold/2, "at": threshold,
   "above": threshold*1.5})'` kimenete `1.0 / 2.0 / 3.0`; ezek a kötelező
   text-scale cellák.
5. **Visszakeresett előzmény.** `lessons/L22` előírja a státuszok közötti
   kombinációk mérését, ezért a broken × non-zero weekly consistency külön
   cella. `lessons/L97` szerint route-ownert igénylő változás nem fér UI-only
   scope-ba, ezért ez a kör a jelenlegi route változatlanságát őrzi.
   `adr/0290`, `adr/0351` és `adr/0352` rögzíti az együttérző nyelvet, a
   caller-fed V2 állapotot és a reason-code/weekly projection forrást.
6. **Pre-flight döntés.** A foglaló `tools/round-slots.py reserve-adr --round
   E08-R12` a `0353` számot adta; ADR 0353 rögzíti a passzív presentation
   boundaryt és a későbbi route-wiring elválasztását. Az allowed paths nem
   bővült.

**Kockázat = high, indoklás:** az együttérző recovery-szöveg, a UI-oldali
jutalomszámítás tilalma és a régi route kompatibilitása termékbiztonsági
határ; a kör ezért Sol correctness + security review-t kap akkor is, ha a
fájlnév-minták önmagukban nem high-riskek.

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

## 1. Cél

Együttérző, magyarázható V2 széria-felület: a megszakadt állapot **hangsúlyozza, hogy
a tudás nem veszett el**, a visszatérés egy gomb — nem büntető visszaszámláló.

## 2. Jelenlegi állapot — mért tények

- `lib/features/streak/screens/streak_screen.dart` (330 sor) a mai felület; `test/features/streak/streak_screen_test.dart` és `skill_reframe_test.dart` MA zöld.
- A `/streak` útvonal ma a régi képernyőre mutat — ez a kör NEM cseréli le, csak új képernyőt ad mellé.
- Az R11 szállította a heti következetesség projekcióját és az indok-kódos átmeneteket.
- Az `ADR 0290` §1: a széria vége tényközlés, nem ítélet; nincs fizetős visszaállítás.
- i18n: minden felhasználónak látszó szöveg ARB-n át megy (`lib/l10n/app_en.arb`, `app_hu.arb`).

## 3. Scope

**Benne van:** a `current` / `longest` / összes nap / freeze / heti következetesség megjelenítése ·
a megszakadt állapot **újrakeretezése** (a tudás megmarad) · visszatérés-CTA büntető
visszaszámláló NÉLKÜL · a tervezett pihenőnap védettségének jelzése · a régi `/streak` mélylink
működésének megőrzése · reduced-motion és nagy szövegskála elrendezés.

**NINCS benne (tilos):**

- A `lib/features/streak/**` bármely fájljának módosítása — a régi képernyő érintetlen.
- A `/streak` útvonal átirányítása az új képernyőre — az útvonal-csere a Kör 30 migrációja (`lib/app/**` tilos zóna).
- Bármely jutalom-számítás a felületen (ADR 0290 §2) — abszolút tilos.
- Fizetős vagy hirdetés-alapú széria-visszaállítás (ADR 0290 §1).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/presentation/screens/streak_detail_screen.dart` | **ÚJ** — a V2 képernyő |
| `lib/features/gamification/presentation/widgets/streak_status_card.dart` | **ÚJ** — állapot + újrakeretezés |
| `lib/features/gamification/presentation/widgets/weekly_consistency_card.dart` | **ÚJ** — a heti mérőszám |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `lib/l10n/app_en.arb` | az ÚJ kulcsok — meglévő kulcs NEM módosítható |
| `lib/l10n/app_hu.arb` | az ÚJ kulcsok magyar párja |
| `test/features/gamification/presentation/streak_detail_screen_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**` · `lib/features/streak/**` · `lib/app/routing/**`

## 5. Kötött architekturális döntések

### 5.1 NINCS szégyenítő szöveg — a megszakadt széria tényközlés

A broken állapot szövege nem használ veszteség-nyelvet, felkiáltójelet vagy
sürgetést, és **kimondja**, hogy a megszerzett tudás megmaradt. Ez az ADR 0290 §1
közvetlen alkalmazása, és acceptance-cella (A1).

**NEM elfogadható gyengítés:** „motiváló” sürgetés („Ne veszítsd el!”). Rövid távon
növeli a visszatérést, hosszú távon szorongást termel.

### 5.2 A felület NEM számol jutalmat és NEM ír a főkönyvbe

Minden érték az application-rétegből érkezik készen. Az ADR 0290 §2 szerint a
felületi számítás minden újranyitáskor újabb jutalmat adna.

Az ADR 0353 szerinti pontos input-szerződés: a `StreakDetailScreen` kötelezően
kap `StreakState state`, `StreakEvaluationReason reason`, validált
`int weeklyConsistencyDays` (`0..7`) és `VoidCallback onRecoveryPressed`
értéket. Nem olvashat providert, órát, repositoryt vagy route-ot. A CTA csak
`reason == StreakEvaluationReason.broken` esetén látszik, és egy tap pontosan
egyszer hívja a callbacket.

### 5.3 A régi mélylink TOVÁBB MŰKÖDIK

A `/streak` útvonal változatlanul a régi képernyőre visz. Ez a kör az ÚJ
képernyőt hozza létre; az útvonal-csere a Kör 30 migrációjának a dolga. A régi
`streak_screen_test.dart` ezért zöld marad — elbukása `blocked` jelzés.

### 5.4 Akadálymentesség: teljes képernyőolvasó-címke, nagy szövegskála, reduced motion

Minden érték-kártyának van értelmes szemantikus címkéje; 200%-os szövegskálán
nincs levágás; a `MediaQuery.disableAnimations` esetén a mozgás **csökken**, nem tűnik el
a visszajelzés. A projekt meglévő a11y-mintája: `test/features/progress/weekly_bars_a11y_test.dart`.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A megszakadt állapot angolul és magyarul NEM tartalmaz veszteség-/sürgetés-nyelvet vagy felkiáltójelet, és kimondja, hogy a megszerzett tudás megmaradt | `streak_detail_screen_test.dart` — mindkét locale tiltott-szó listája + a megerősítő ARB-szöveg jelenléte |
| A2 | A visszatérés-CTA elérhető, és NINCS visszaszámláló | `streak_detail_screen_test.dart` |
| A3 | A tervezett pihenőnap védettsége látszik | `streak_detail_screen_test.dart` |
| A4 | A hívó-adta heti következetesség `0..7` értéke jelenik meg; broken + nem nulla értéknél is változatlan, és a UI nem számolja újra | `streak_detail_screen_test.dart` — 0/4/7 és broken × 4 kombináció + forrásőr |
| A5 | A régi `/streak` mélylink változatlanul a legacy `StreakScreen`-t adja | `streak_detail_screen_test.dart` — `app_router.dart` pontos route-wiring forrásőre + meglévő `streak_screen_test.dart` a §7 gate-ben |
| A6 | Minden felhasználónak látszó szöveg ARB-kulcsból jön; a három új production fájlban nincs beégetett felhasználói string | `streak_detail_screen_test.dart` — angol/magyar locale cella + production-forrásőr |
| A7 | 200%-os szövegskálán nincs túlcsordulás, és kis képernyőn sem | `streak_detail_screen_test.dart` — méret-mátrix |
| A8 | Minden értékkártya egy teljes, mértékegységes semantics label; reduced motion esetén a status-átmenet időtartama nulla, miközben a státusz szöveg/ikon/szemantika megmarad | `streak_detail_screen_test.dart` — semantics + normál/reduced páros cella |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A broken szöveg sürgetést használ | **A1** (tiltott-szó cella) |
| A CTA eltűnik, kétszer hív, vagy countdown kerül mellé | **A2** CTA/callback/countdown cella |
| Planned-rest reasonre nem jelenik meg a védettség, vagy brokenre is megjelenik | **A3** planned-rest/broken páros cella |
| A felület maga számolja a heti értéket, vagy brokennél lenullázza | **A4** 0/4/7 + broken × 4 cella és production-forrásőr |
| A `/streak` az új képernyőre irányítva | **A5** pontos `app_router.dart` route-wiring forrásőr |
| Beégetett angol vagy magyar szöveg a kártyán | **A6** két-locale render + három production-fájl forrásőre |
| Fix kártyamagasság vagy nem görgethető body kerül be | **A7** 1.0/2.0/3.0 × 320×568 és 412×732 méretmátrix |
| Hiányos értékkártya-címke, vagy reduced motion elrejti a visszajelzést | **A8** teljes semantics-label lista + normál/reduced duration és megmaradó tartalom |

**A küszöb három kötelező cellája** (a szövegskála (`textScaleFactor`) — a levágás-mentesség határa):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `textScaleFactor = 1.0` (alap) | nincs levágás — triviális eset |
| **rajta** (a küszöbön) | `textScaleFactor = 2.0` (200%, a projekt a11y-mércéje) | **nincs levágás és nincs túlcsordulás** — ez a kötelező cella |
| a küszöb **fölött** | `textScaleFactor = 3.0` | a tartalom görgethető marad; levágás helyett tördelés vagy görgetés — összeomlás NEM elfogadható |

A hármas tömören: **alatt** → elfogad · **rajta** → elfogad · **fölött** →
elfogad, ha görgethető marad és nincs overflow/exception.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tedd fixre az egyik kártya magasságát, futtasd a gate-et 200%-os szövegskálán →
az **A7** méret-mátrix cellájának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/presentation/streak_detail_screen_test.dart test/features/streak
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

1. Az ARB-kulcsok felvétele (angol + magyar), a szégyenítés-mentes szövegekkel;
   meglévő kulcs nem módosulhat.
2. `streak_status_card.dart` — állapot + újrakeretezés („a tudásod megmaradt”).
3. `weekly_consistency_card.dart` — a heti mérőszám.
4. `streak_detail_screen.dart` — az ADR 0353 kötelező, caller-fed
   `StreakState`/reason/weekly/callback contractja, kizárólag kész értékekből.
5. Visszatérés-CTA visszaszámláló nélkül; a pihenőnap védettségének jelzése.
6. a11y: szemantikus címkék, 200% szövegskála, reduced motion.
7. A `public.dart` export-sorai; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint — a RÉGI streak-tesztekkel együtt.

## 9. Kockázatok

- **A „motiváló” sürgetés.** A gamifikáció legkézenfekvőbb mintája, és az ADR 0290 §1 kifejezetten tiltja (A1).
- **A felületi számítás.** Egy `sum()` a widgetben ártatlannak tűnik, és minden újranyitáskor újabb jutalmat adna (A4).
- **A régi útvonal „rendbetétele”.** Az átirányítás kézenfekvő, `lib/app/**` viszont tilos zóna, és a meglévő teszt bukna (A5).

## 10. Implementation handoff — az implementer tölti ki

A handoff fájlonkénti összefoglalót, tényleges parancskimenetet, eltérést és
nem futtatott ellenőrzést tartalmaz. Kötelezően dokumentálja a fix
kártyamagasság valódi-sértés próbát: ideiglenes rontás → A7 PIROS →
visszaállítás → célzott teszt ZÖLD. A munkát a kör branchére commitolja, majd
`tools/codex-signal.sh done` jelzést ad; scope-ütközésnél előbb `stopped`.

## 11. Review — a Sol tölti ki

Correctness: `docs/reviews/e08-r12-review.md`.
High-risk security/product-boundary: `docs/reviews/e08-r12-security.md`.
