# E13-R15 — Lokalizációs resilience és content style

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 6adea220`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 15
- **Kör-azonosító:** `E13-R15`
- **Branch:** `<motor>/e13-r15-localization-resilience`
- **Előfeltétel:** `E13-R14` merge-elve (accessibility toolkit)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a Ch13 §9.15 tartalmi szabályai adottak.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg a `lib/l10n/app_en.arb` és
> `app_hu.arb` TÉNYLEGES kulcsszámát és eltéréseit — az R10–R13 körök közben
> bővítették őket. A §6 A1 paritás-cellája erre a mért állapotra épül.
> Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/core/i18n/ss_formatters.dart",
  "lib/core/i18n/pseudo_locale.dart",
  "lib/core/design_system/public.dart",
  "test/l10n/arb_parity_test.dart",
  "test/l10n/formatters_test.dart",
  "test/l10n/hardcoded_string_guard_test.dart",
  "docs/ui/content-style.md",
  "docs/rounds/e13-r15-localization-resilience.md",
]
gate_tests = [
  "test/l10n/arb_parity_test.dart",
  "test/l10n/formatters_test.dart",
  "test/l10n/hardcoded_string_guard_test.dart",
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

## 1. Cél

Az angol–magyar felület **törésbiztonsága**, a microcopy szabályai és a
locale-tudatos formázás (SDD Ch13 Kör 15).

## 2. Jelenlegi állapot — mért tények

- Az R10–R13 új ARB-kulcsokat vezetett be (visszajelzés, űrlap, kártya,
  overlay) — a paritás mostantól gépi kapu kell legyen.
- Az R04 kimondta: a magyar szöveg **≥30% tartalékot** igényel, és 2.0 text
  scale mellett sem clippelhet.
- A CLAUDE.md szabálya: minden felhasználói szöveg ARB-n át megy.

## 3. Scope

**Benne van:** a Chapter 13 komponens-string katalógus **stabil kulcs-elnevezéssel**
· hosszú magyar, többes szám, dátum, időtartam, pontszám és mértékegység
fixture-ök · a mondat-összefűzés és a beégetett szöveg javítása a **migrált core
komponensekben** · locale-tudatos időtartam-, BPM-, cents-, százalék- és
dátum-formázó · microcopy stílusútmutató (visszajelzés, engedély, AI-eredet,
offline, destruktív akció) · pszeudo-lokalizációs teszt-mód.

**NINCS benne (tilos):** `lib/features/**` képernyők szövegeinek migrálása
(a képernyő-körök dolga) · új nyelv felvétele · `lib/core/theme/**` ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/l10n/app_{en,hu}.arb` | a katalógus + a hiányzó párok |
| `core/i18n/ss_formatters.dart` | **ÚJ** — locale-tudatos formázók |
| `core/i18n/pseudo_locale.dart` | **ÚJ** — teszt-mód |
| `design_system/public.dart` | az export bővítése |
| `test/l10n/*_test.dart` (3) | a §6 cellái |
| `docs/ui/content-style.md` | **ÚJ** — microcopy szabályok |
| `docs/rounds/e13-r15-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` · `lib/core/theme/**` · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 Nincs MONDATSZERKEZETI string-összefűzés

`'$count ' + t.songs` alakú összefűzés tilos: a magyar szórend és a ragozás más.
Minden mondat egyetlen, paraméterezett ARB-kulcs.

**NEM elfogadható gyengítés:** „ez a két szó úgyis mindig ebben a sorrendben
van". Pont ez a feltevés bukik meg a második nyelven.

### 5.2 A paritás GÉPI kapu, nem szemrevételezés

Az en és a hu kulcshalmaza megegyezik. Hiányzó fordítás a tesztben bukik, nem
futásidőben, angol szövegként.

### 5.3 A formázás locale-tudatos

Időtartam, BPM, cents, százalék és dátum a felhasználó locale-ja szerint. A
tizedesjel és az ezres elválasztó eltér a két nyelvben.

### 5.4 A pszeudo-lokalizáció a TÖRÉST méri, nem szépít

A hosszított teszt-locale célja, hogy kiugorjon a clipping — ezért nem lehet
opcionális dísz, hanem a golden-mérés bemenete.

### 5.5 A beégetett szöveg GUARD-dal tiltott a migrált scope-ban

A szabály csak akkor tart, ha gépi. A guard a **már migrált** core
komponensekre néz, nem a teljes fára — különben az első futáskor pirosat adna
a még nem migrált feature-ökre, és kikapcsolnák.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az en és hu kulcsparitás teljes | `arb_parity_test.dart` |
| A2 | Nincs mondatszerkezeti string-összefűzés a migrált scope-ban | `hardcoded_string_guard_test.dart` |
| A3 | Nincs beégetett felhasználói szöveg a migrált core komponensekben | ugyanott |
| A4 | A formázók locale-tudatosak (időtartam, BPM, cents, %, dátum) | `formatters_test.dart` |
| A5 | A többes szám mindkét nyelven helyes | ugyanott |
| A6 | Pszeudo-locale mellett a kritikus komponensek nem clippelnek | `formatters_test.dart` + golden |
| A7 | A microcopy útmutató lefedi az öt kötelező helyzetet | `docs/ui/content-style.md` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Hiányzó magyar kulcs | **A1** |
| `'$n ' + t.songs` összefűzés | **A2** |
| Beégetett angol szöveg a komponensben | **A3** |
| `toString()` a dátumra | A4 |
| Egyetlen többes-szám alak | A5 |
| A pszeudo-locale nincs bekötve a goldenbe | A6 |

**A magyar szöveghossz három kötelező cellája** (a küszöb: az angol hosszhoz
képest **+30%** tartalék):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | +15%-kal hosszabb magyar szöveg | elfér, nincs clipping |
| rajta (a küszöbön) | pontosan **+30%** | **elfér** — ez a kötelező tartalék |
| a küszöb fölött | pszeudo-locale (+60%) | **nem clippelhet** a kritikus komponensben |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** törölj egy magyar
ARB-kulcsot → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/l10n/arb_parity_test.dart test/l10n/formatters_test.dart test/l10n/hardcoded_string_guard_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `arb_parity_test.dart` — a kapu ELŐBB, a hiányok láthatóvá tétele.
2. Az ARB-katalógus rendezése stabil kulcs-elnevezéssel, a hiányok pótlása.
3. `ss_formatters.dart` — locale-tudatos formázók + cellák.
4. `pseudo_locale.dart` + a hossz-cellák.
5. `hardcoded_string_guard_test.dart` a **migrált** scope-ra.
6. `docs/ui/content-style.md` — microcopy az öt helyzetre.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A guard túl széles hatóköre.** Ha a teljes fára néz, azonnal piros, és
  kikapcsolják — a migrált scope a helyes határ (A3).
- **Az összefűzött mondat.** Angolul helyesnek látszik, magyarul ragozási hibát
  ad, és csak fordításkor derül ki (A2).
- **A hiányzó kulcs mint néma angol szöveg.** Futásidőben nem hiba, csak
  minőségromlás — ezért kell gépi paritás (A1).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
