# E08-R12 — Streak felület V2 és visszatérés-folyamat

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 12
- **Kör-azonosító:** `E08-R12`
- **Branch:** `<motor>/e08-r12-streak-ui-v2-and-recovery-flow`
- **Előfeltétel:** `E08-R11` merge-elve (qualified day policy)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** nincs — ez a kör nem hoz kötött architekturális döntést.

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
| A1 | A megszakadt állapot szövege NEM tartalmaz veszteség-/sürgetés-nyelvet, és kimondja, hogy a tudás megmaradt | `streak_detail_screen_test.dart` — tiltott-szó lista + a megerősítő szöveg jelenléte |
| A2 | A visszatérés-CTA elérhető, és NINCS visszaszámláló | `streak_detail_screen_test.dart` |
| A3 | A tervezett pihenőnap védettsége látszik | `streak_detail_screen_test.dart` |
| A4 | A heti következetesség megjelenik, és megszakadt széria mellett is helyes | `streak_detail_screen_test.dart` |
| A5 | A régi `/streak` mélylink változatlanul a régi képernyőt adja | `streak_screen_test.dart` (meglévő) — a §7 gate |
| A6 | Minden felhasználónak látszó szöveg ARB-kulcsból jön (nincs beégetett string) | `streak_detail_screen_test.dart` + review |
| A7 | 200%-os szövegskálán nincs túlcsordulás, és kis képernyőn sem | `streak_detail_screen_test.dart` — méret-mátrix |
| A8 | A képernyőolvasó-címkék teljesek; reduced motion esetén a visszajelzés CSÖKKEN, nem tűnik el | `streak_detail_screen_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A broken szöveg sürgetést használ | **A1** (tiltott-szó cella) |
| A CTA mellé visszaszámláló kerül | **A2** |
| A felület maga számolja a heti értéket | **A4** és a review (ADR 0290 §2) |
| A `/streak` az új képernyőre irányítva | **A5** (a meglévő teszt elbukik) |
| Beégetett angol szöveg a kártyán | **A6** |
| Reduced motion esetén a visszajelzés eltűnik | **A8** |

**A küszöb három kötelező cellája** (a szövegskála (`textScaleFactor`) — a levágás-mentesség határa):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `textScaleFactor = 1.0` (alap) | nincs levágás — triviális eset |
| **rajta** (a küszöbön) | `textScaleFactor = 2.0` (200%, a projekt a11y-mércéje) | **nincs levágás és nincs túlcsordulás** — ez a kötelező cella |
| a küszöb **fölött** | `textScaleFactor = 3.0` | a tartalom görgethető marad; levágás helyett tördelés vagy görgetés — összeomlás NEM elfogadható |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

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

1. Az ARB-kulcsok felvétele (angol + magyar), a szégyenítés-mentes szövegekkel.
2. `streak_status_card.dart` — állapot + újrakeretezés („a tudásod megmaradt”).
3. `weekly_consistency_card.dart` — a heti mérőszám.
4. `streak_detail_screen.dart` — a V2 képernyő, kizárólag kész értékekből.
5. Visszatérés-CTA visszaszámláló nélkül; a pihenőnap védettségének jelzése.
6. a11y: szemantikus címkék, 200% szövegskála, reduced motion.
7. A `public.dart` export-sorai; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint — a RÉGI streak-tesztekkel együtt.

## 9. Kockázatok

- **A „motiváló” sürgetés.** A gamifikáció legkézenfekvőbb mintája, és az ADR 0290 §1 kifejezetten tiltja (A1).
- **A felületi számítás.** Egy `sum()` a widgetben ártatlannak tűnik, és minden újranyitáskor újabb jutalmat adna (A4).
- **A régi útvonal „rendbetétele”.** Az átirányítás kézenfekvő, `lib/app/**` viszont tilos zóna, és a meglévő teszt bukna (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
