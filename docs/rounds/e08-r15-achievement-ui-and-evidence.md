# E08-R15 — Achievement felület és bizonyíték-nézet

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 15
- **Kör-azonosító:** `E08-R15`
- **Branch:** `<motor>/e08-r15-achievement-ui-and-evidence`
- **Előfeltétel:** `E08-R14` merge-elve (achievement kiértékelő)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** nincs — ez a kör nem hoz kötött architekturális döntést.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R13 `hidden` mezőjének és az R14 haladás-projekciójának TÉNYLEGES felületét, valamint a `lib/features/analyze/` eredmény-modelljét (a bizonyíték-nézet NEM mutathat nyers audiót). Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/presentation/screens/achievements_screen.dart",
  "lib/features/gamification/presentation/screens/achievement_detail_screen.dart",
  "lib/features/gamification/presentation/widgets/achievement_tile.dart",
  "lib/features/gamification/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/gamification/presentation/achievements_screen_test.dart",
  "docs/rounds/e08-r15-achievement-ui-and-evidence.md",
]
gate_tests = [
  "test/features/gamification/presentation/achievements_screen_test.dart",
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

Jól navigálható eredmény-lista és **közérthető** magyarázat: mindenki érti, miért kapta
(vagy miért nem kapta még) az adott eredményt — érzékeny adat felfedése nélkül.

## 2. Jelenlegi állapot — mért tények

- Az R14 haladás-projekciót és feloldási időbélyeget ad; az R13 `hidden` és tier mezőket.
- `lib/features/gamification/presentation/screens/achievement*` **nem létezik**.
- A projekt a11y-mintája: `test/features/progress/weekly_bars_a11y_test.dart`.
- Az `ADR 0289` §2: a bizonyíték auditálható — minden állítás mögött konkrét session áll.

## 3. Scope

**Benne van:** all / unlocked / in-progress / kategória szűrők · haladás és feloldási dátum ·
a rejtett achievement részletei CSAK feloldás után · a bizonyíték-nézet az indok-kódokból
épít közérthető magyarázatot · üres állapot új felhasználónak · validált útvonal-argumentum.

**NINCS benne (tilos):**

- Nyers hang, felvétel-részlet vagy érzékeny session-adat megjelenítése (§5.2) — abszolút tilos.
- Jutalom-számítás a felületen (ADR 0290 §2).
- A katalógus vagy a kiértékelő módosítása (Kör 13/14).
- `lib/app/routing/**` — az útvonal-regisztráció a Kör 30 dolga; itt a képernyő maga készül el.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/presentation/screens/achievements_screen.dart` | **ÚJ** — a lista, szűrőkkel |
| `lib/features/gamification/presentation/screens/achievement_detail_screen.dart` | **ÚJ** — a részletek és a bizonyíték |
| `lib/features/gamification/presentation/widgets/achievement_tile.dart` | **ÚJ** — a listaelem |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `lib/l10n/app_en.arb` | az ÚJ kulcsok |
| `lib/l10n/app_hu.arb` | az ÚJ kulcsok magyar párja |
| `test/features/gamification/presentation/achievements_screen_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` (az útvonal-regisztráció a Kör 30) · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések

### 5.1 A rejtett achievement NEM SZIVÁROG

Feloldás előtt sem a cím, sem a leírás, sem a haladás nem látszik — és a widget-fa
sem tartalmazza őket (a szemantikus fában sem). A „kiszürkítve, de ott van” megoldás
képernyőolvasóval felolvasható, tehát szivárgás.

**NEM elfogadható gyengítés:** a szöveg megjelenítése `Opacity(0)` vagy `Visibility`
mögött. A szemantikus fa attól még tartalmazza.

### 5.2 A bizonyíték PRIVACY-SAFE — nincs nyers hang, nincs érzékeny részlet

A magyarázat az indok-kódokból és összesített metrikákból épül. Nyers felvétel,
hangminta vagy azonosítható session-részlet nem jelenik meg.

**NEM elfogadható gyengítés:** „csak a hullámforma” megjelenítése — az is a felvételből
származó adat.

### 5.3 A felület NEM SZÁMOL — minden érték készen érkezik

Az ADR 0290 §2 alkalmazása: a haladás és a feloldás az application-rétegből jön.

### 5.4 Az útvonal-argumentum VALIDÁLT

Ismeretlen vagy hibás achievement-azonosítóval a részletek képernyő értelmes
üres/hiba állapotot mutat, nem omlik össze — mélylinkről is érkezhet.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A négy szűrő (all / unlocked / in-progress / kategória) helyes halmazt ad | `achievements_screen_test.dart` — szűrő-mátrix |
| A2 | A rejtett achievement részletei feloldás ELŐTT a szemantikus fában SEM jelennek meg | `achievements_screen_test.dart` — szivárgás-cella |
| A3 | A feloldott elem haladást és feloldási dátumot mutat | `achievements_screen_test.dart` |
| A4 | A bizonyíték-nézet indok-kódokból épít szöveget, és NEM tartalmaz nyers audio/session adatot | `achievements_screen_test.dart` |
| A5 | Üres állapot van új felhasználónak (nem üres lista, nem hiba) | `achievements_screen_test.dart` |
| A6 | Ismeretlen azonosítóval a részletek képernyő értelmes állapotot mutat, nem omlik össze | `achievements_screen_test.dart` |
| A7 | Minden szöveg ARB-kulcsból jön | `achievements_screen_test.dart` + review |
| A8 | 200%-os szövegskálán nincs levágás; a szemantikus címkék teljesek | `achievements_screen_test.dart` — a11y-mátrix |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A rejtett elem `Opacity(0)` mögött megjelenik | **A2** (a szemantikus fa tartalmazza) |
| A bizonyíték hullámformát mutat | **A4** |
| A szűrő a listát nem szűkíti, csak jelöl | **A1** |
| Ismeretlen azonosítón kivétel | **A6** |
| Beégetett angol szöveg | **A7** |
| Fix magasságú csempe | **A8** (200%-on levágás) |

**A küszöb három kötelező cellája** (a szövegskála (`textScaleFactor`)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `1.0` | nincs levágás — triviális |
| **rajta** (a küszöbön) | `2.0` (200%, a projekt a11y-mércéje) | **nincs levágás, nincs túlcsordulás** — kötelező cella |
| a küszöb **fölött** | `3.0` | görgethető marad; összeomlás NEM elfogadható |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** jelenítsd meg a rejtett achievement címét `Opacity(0)` mögött, futtasd a gate-et →
az **A2** szivárgás-cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/presentation/achievements_screen_test.dart
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
2. `achievement_tile.dart` — a listaelem, rejtett állapot kezelésével.
3. `achievements_screen.dart` — a négy szűrő és az üres állapot.
4. `achievement_detail_screen.dart` — részletek + bizonyíték az indok-kódokból.
5. Az útvonal-argumentum validációja.
6. a11y: szemantikus címkék, 200% szövegskála.
7. A `public.dart` export-sorai; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A rejtett elem „kiszürkítése”.** Vizuálisan meggyőző, és képernyőolvasóval teljesen felolvasható — valódi szivárgás (A2).
- **A „csak a hullámforma”.** Ártalmatlannak tűnik, és a felvételből származó adat (A4).
- **A fix magasságú csempe.** 200%-os skálán levágja a magyar (hosszabb) szövegeket (A8).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
