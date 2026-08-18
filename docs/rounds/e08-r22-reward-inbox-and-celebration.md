# E08-R22 — Jutalom-postaláda és ünneplés-koordinátor

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 22
- **Kör-azonosító:** `E08-R22`
- **Branch:** `<motor>/e08-r22-reward-inbox-and-celebration`
- **Előfeltétel:** `E08-R21` merge-elve (mastery kiértékelő)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0316` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R07 „átlépett szintek listája” kimenetét (a több szintlépés összevonása erre épül) és a `lib/features/live/` gyakorlás-közbeni állapotjelzését — a „zenélés közben nincs felugró” szabály ezt kérdezi. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/domain/profile/reward_inbox_item.dart",
  "lib/features/gamification/application/celebration_coordinator.dart",
  "lib/features/gamification/presentation/screens/reward_inbox_screen.dart",
  "lib/features/gamification/presentation/widgets/reward_summary_sheet.dart",
  "lib/features/gamification/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/gamification/application/celebration_coordinator_test.dart",
  "docs/rounds/e08-r22-reward-inbox-and-celebration.md",
]
gate_tests = [
  "test/features/gamification/application/celebration_coordinator_test.dart",
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

A jutalmakat **nem zavaró**, összevont és akadálymentes módon jelenítsd meg. A
postaláda **nem beváltás-mechanika**: a jutalom már jóvá van írva, mire ide kerül.

## 2. Jelenlegi állapot — mért tények

- Az R07 az átlépett szintek listáját adja; az R03 főkönyve a jutalmakat.
- `reward_inbox_item.dart` és a koordinátor **nem létezik**.
- A `lib/features/live/` és `lib/features/practice/` aktív gyakorlási állapotot jelez — ez a felugró tiltásának bemenete.
- Az `ADR 0290` §2: a beváltás idempotens, a felület nem számol jutalmat.

## 3. Scope

**Benne van:** a session jutalmainak prioritizálása és **összevonása** · több szintlépés EGY
összefoglalóban · **nincs felugró zenélés közben** · háttérben vagy bezárt folyamatban
keletkezett jutalom a postaládába · a postaláda NEM beváltás · reduced motion, haptika és
hang beállítás tiszteletben tartása.

**NINCS benne (tilos):**

- Beváltás-mechanika a postaládában (§5.2) — abszolút tilos.
- Jutalom-számítás a felületen (ADR 0290 §2).
- A beállítások képernyő (Kör 27) — itt csak a meglévő beállítások OLVASÁSA történik.
- `docs/adr/**` — az ADR 0316-ot a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/domain/profile/reward_inbox_item.dart` | **ÚJ** — a postaláda-elem |
| `lib/features/gamification/application/celebration_coordinator.dart` | **ÚJ** — prioritás, összevonás, megszakítás-politika |
| `lib/features/gamification/presentation/screens/reward_inbox_screen.dart` | **ÚJ** — a postaláda |
| `lib/features/gamification/presentation/widgets/reward_summary_sheet.dart` | **ÚJ** — az összevont összefoglaló |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `lib/l10n/app_en.arb` | az ÚJ kulcsok |
| `lib/l10n/app_hu.arb` | az ÚJ kulcsok magyar párja |
| `test/features/gamification/application/celebration_coordinator_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0316)

### 5.1 ZENÉLÉS KÖZBEN NINCS FELUGRÓ — soha

Aktív gyakorlási vagy felvételi állapotban semmilyen ünneplés nem szakítja meg a
felhasználót. A jutalom a postaládába kerül, és a session VÉGÉN jelenik meg összevontan.

**NEM elfogadható gyengítés:** „csak egy kis toast”. A hangszeres gyakorlás megszakítása a
termék magját rontja el — és a jutalom amúgy is jóvá van írva.

### 5.2 A POSTALÁDA NEM BEVÁLTÁS — a jutalom már jóvá van írva

A postaláda **értesítési** felület: megmutatja, mi történt. A megnyitása nem
feltétele semminek, és a nem megnyitott elem nem jár le.

**NEM elfogadható gyengítés:** „Begyűjtés” gomb vagy lejáró postaláda-elem.

### 5.3 ÖSSZEVONÁS: több szintlépés EGY összefoglaló

Egy session során átlépett három szint egyetlen összefoglalóban jelenik meg, nem
három egymás utáni animációban. A prioritási sorrend **tesztelt** és determinisztikus.

### 5.4 REDUCED MOTION: a visszajelzés CSÖKKEN, nem tűnik el

Csökkentett mozgás beállítás mellett az ünneplés statikus, de **teljes értékű**:
ugyanaz az információ, animáció nélkül. A haptika és a hang külön kapcsolható.

**NEM elfogadható gyengítés:** reduced motion esetén az ünneplés teljes elhagyása — az
információt is elvenné.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Aktív gyakorlás közben SEMMILYEN ünneplés nem jelenik meg | `celebration_coordinator_test.dart` — megszakítás-mátrix |
| A2 | A session végén a jutalmak ÖSSZEVONTAN jelennek meg (három szintlépés → egy összefoglaló) | `celebration_coordinator_test.dart` |
| A3 | A jutalom a főkönyvben van, MIELŐTT a postaládába kerül | `celebration_coordinator_test.dart` — sorrend-cella |
| A4 | A postaláda-elem NEM jár le, és nincs begyűjtés-gomb | `celebration_coordinator_test.dart` |
| A5 | Háttérben/bezárt folyamatban keletkezett jutalom a postaládában megjelenik | `celebration_coordinator_test.dart` |
| A6 | A prioritási sorrend determinisztikus és tesztelt | `celebration_coordinator_test.dart` — prioritás-mátrix |
| A7 | Reduced motion mellett az ünneplés statikus, de UGYANAZT az információt adja | `celebration_coordinator_test.dart` |
| A8 | A postaláda tartós: app-újraindítás után is megvan | `celebration_coordinator_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Toast jelenik meg gyakorlás közben | **A1** |
| Három szintlépés három animáció | **A2** |
| A postaláda-elem a jutalom jóváírása ELŐTT jön létre | **A3** |
| Begyűjtés-gomb a postaládában | **A4** |
| Reduced motion esetén az ünneplés elmarad | **A7** |
| A prioritás a `Map` bejárási sorrendjéből | **A6** |

**A küszöb három kötelező cellája** (az összevonási ablak (`celebrationBatchWindow`) — meddig várunk további jutalomra összevonás előtt):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | két jutalom `celebrationBatchWindow - 1` időkülönbséggel | **ÖSSZEVONVA** — egy összefoglaló |
| **rajta** (a küszöbön) | pontosan `celebrationBatchWindow` időkülönbség | **MÉG ÖSSZEVONVA** — az ablak az ÖSSZEVONÓ oldalhoz tartozik (inkluzív) |
| a küszöb **fölött** | `celebrationBatchWindow + 1` időkülönbség | **KÜLÖN** összefoglaló; a második a postaládába kerül, ha közben gyakorlás indult |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedd meg a felugrót aktív gyakorlás közben, futtasd a gate-et → az **A1**
megszakítás-mátrix cellájának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/application/celebration_coordinator_test.dart
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

1. `reward_inbox_item.dart` — a postaláda-elem (lejárat NÉLKÜL).
2. `celebration_coordinator.dart` — prioritás, összevonás, megszakítás-politika.
3. A gyakorlási állapot lekérdezése (public contracton át) és a felugró tiltása.
4. `reward_summary_sheet.dart` — az összevont összefoglaló.
5. `reward_inbox_screen.dart` — a postaláda, begyűjtés nélkül.
6. Reduced motion / haptika / hang beállítás tiszteletben tartása.
7. Az ARB-kulcsok; a `public.dart` export-sorai; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A „csak egy kis toast”.** A legkisebb engedmény is megszakítja a hangszeres gyakorlást (A1).
- **A begyűjtés-mechanika.** A postaláda felület ránézésre kínálja; az ADR 0290 §2 tiltja (A4).
- **A reduced motion „kikapcsolásként” értelmezése.** Az információt is elveszi, nem csak a mozgást (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
