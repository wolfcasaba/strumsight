# E08-R23 — Gamification Hub és szint-felület

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 23
- **Kör-azonosító:** `E08-R23`
- **Branch:** `<motor>/e08-r23-gamification-hub-and-level-ui`
- **Előfeltétel:** `E08-R22` merge-elve (jutalom-postaláda)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** nincs — ez a kör nem hoz kötött architekturális döntést.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R07 profil-projekcióját, az R21 mastery-jelvényét és az R22 postaláda-jelzőjét; ellenőrizd a `lib/features/progress/screens/progress_screen.dart` (516 sor) mai szerkezetét — a Hub NEM váltja le. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/presentation/screens/gamification_hub_screen.dart",
  "lib/features/gamification/presentation/screens/level_detail_screen.dart",
  "lib/features/gamification/presentation/widgets/xp_progress_bar.dart",
  "lib/features/gamification/presentation/widgets/level_badge.dart",
  "lib/features/gamification/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/gamification/presentation/gamification_hub_screen_test.dart",
  "docs/rounds/e08-r23-gamification-hub-and-level-ui.md",
]
gate_tests = [
  "test/features/gamification/presentation/gamification_hub_screen_test.dart",
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

Központi, de **nem domináló** áttekintő felület — és a legfontosabb invariáns:
az **XP vizuálisan NEM téveszthető össze a készség-szinttel** (ADR 0289).

## 2. Jelenlegi állapot — mért tények

- Az R07 szintet és haladást, az R21 mastery-jelvényt, az R22 postaláda-jelzőt ad.
- `gamification_hub_screen.dart` **nem létezik**; a `progress_screen.dart` (516 sor) a mai fejlődési felület, és ez a kör NEM váltja le.
- Az `ADR 0289`: az XP a részvételt méri, az elsajátítottság mért teljesítményt.

## 3. Scope

**Benne van:** szint, XP-haladás, küldetések, széria, mastery és a legutóbbi eredmény megjelenítése ·
„Hogyan működik?” magyarázó nézet az XP-komponensekről · az XP és a készség-mutató **vizuális
szétválasztása** · nincs villogás és nincs agresszív visszaszámláló · üres állapot legacy és új
felhasználónak · a postaláda-jelző integrálása.

**NINCS benne (tilos):**

- A `lib/features/progress/**` módosítása vagy leváltása.
- Jutalom-számítás a felületen (ADR 0290 §2).
- `lib/app/routing/**` — az útvonal-regisztráció a Kör 30.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/presentation/screens/gamification_hub_screen.dart` | **ÚJ** — a Hub |
| `lib/features/gamification/presentation/screens/level_detail_screen.dart` | **ÚJ** — a szint részletei + magyarázat |
| `lib/features/gamification/presentation/widgets/xp_progress_bar.dart` | **ÚJ** — az XP-sáv |
| `lib/features/gamification/presentation/widgets/level_badge.dart` | **ÚJ** — a szint-jelvény |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `lib/l10n/app_en.arb` | az ÚJ kulcsok |
| `lib/l10n/app_hu.arb` | az ÚJ kulcsok magyar párja |
| `test/features/gamification/presentation/gamification_hub_screen_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**` · `lib/features/progress/**`

## 5. Kötött architekturális döntések

### 5.1 AZ XP ÉS A KÉSZSÉG VIZUÁLISAN ELKÜLÖNÜL

A két mutató nem osztozik színen, alakon vagy elrendezési sávon, és a feliratok
kimondják, melyik mit mér. Az `ADR 0289` szerint ez a termék legfontosabb őszinteségi
kérdése a fejlődési felületen.

**NEM elfogadható gyengítés:** azonos stílusú két sáv egymás alatt. A felhasználó a
kettőt ugyanannak fogja olvasni.

### 5.2 A MAGYARÁZAT ELÉRHETŐ — „Hogyan működik?”

A szint-részletek képernyőn megnyitható magyarázat mondja el, milyen komponensekből
áll az XP (R06 bontása). A magyarázhatatlan pontszám önkényesnek hat.

### 5.3 NEM DOMINÁLÓ: nincs villogás, nincs visszaszámláló

A Hub nyugodt felület. Sem villogó elem, sem sürgető visszaszámláló nem
szerepelhet rajta (ADR 0290 §1).

### 5.4 OFFLINE ÉS GYORS

A Hub hálózat nélkül teljes értékű, és a profil-projekcióból dolgozik (nem
számol a főkönyvön minden megnyitáskor).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az XP-sáv és a készség-mutató eltérő vizuális kezelést kap, és a feliratok kimondják a különbséget | `gamification_hub_screen_test.dart` — szétválasztás-cella + review |
| A2 | A „Hogyan működik?” magyarázat elérhető, és az R06 komponenseit sorolja | `gamification_hub_screen_test.dart` |
| A3 | Nincs villogó elem és nincs visszaszámláló | `gamification_hub_screen_test.dart` — tiltott-minta cella |
| A4 | A Hub offline teljes értékű (nincs hálózati hívás) | `gamification_hub_screen_test.dart` |
| A5 | Üres állapot van legacy és új felhasználónak is | `gamification_hub_screen_test.dart` |
| A6 | A postaláda-jelző megjelenik, ha van új elem | `gamification_hub_screen_test.dart` |
| A7 | A `lib/features/progress/**` ÉRINTETLEN | `git diff --stat` |
| A8 | 200%-os szövegskálán nincs levágás; a szemantikus címkék teljesek | `gamification_hub_screen_test.dart` — a11y-mátrix |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Két azonos stílusú sáv egymás alatt | **A1** |
| A magyarázat hiányzik vagy általános szöveg | **A2** |
| Pulzáló „szintlépés közeleg” elem | **A3** |
| A Hub a főkönyvön számol megnyitáskor | **A4** |
| A Hub átveszi a `/progress` útvonalat | **A7** |
| Fix magasságú kártyák | **A8** |

**A küszöb három kötelező cellája** (a szövegskála (`textScaleFactor`)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `1.0` | nincs levágás — triviális |
| **rajta** (a küszöbön) | `2.0` (200%, a projekt a11y-mércéje) | **nincs levágás, nincs túlcsordulás** — kötelező cella |
| a küszöb **fölött** | `3.0` | görgethető marad; összeomlás NEM elfogadható |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** add az XP-sávnak és a készség-mutatónak ugyanazt a stílust, futtasd a gate-et →
az **A1** szétválasztás-cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/presentation/gamification_hub_screen_test.dart
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

1. Az ARB-kulcsok felvétele mindkét nyelven.
2. `xp_progress_bar.dart` és `level_badge.dart` — az XP vizuális nyelve.
3. A készség-mutató vizuálisan ELTÉRŐ megjelenítése, kimondott felirattal.
4. `level_detail_screen.dart` — „Hogyan működik?” magyarázat az R06 komponenseiből.
5. `gamification_hub_screen.dart` — áttekintés, postaláda-jelző, üres állapotok.
6. a11y: szemantikus címkék, 200% szövegskála.
7. A `public.dart` export-sorai; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A két egyforma sáv.** Vizuálisan letisztult, és pontosan azt a félreértést termeli, amit az ADR 0289 tilt (A1).
- **A Hub „főképernyővé” tétele.** Az Epic célja nem-domináló réteg; a `progress` leváltása scope-sértés (A7).
- **A megnyitáskori újraszámolás.** Nagy főkönyvön érezhető akadás (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
