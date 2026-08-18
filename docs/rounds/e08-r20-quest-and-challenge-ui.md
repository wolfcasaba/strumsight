# E08-R20 — Küldetés és kihívás felület

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 20
- **Kör-azonosító:** `E08-R20`
- **Branch:** `<motor>/e08-r20-quest-and-challenge-ui`
- **Előfeltétel:** `E08-R19` merge-elve (Challenge V2)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** nincs — ez a kör nem hoz kötött architekturális döntést.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R16 állapotgépét és az R19 napi példány-szerződését; ellenőrizd a `lib/app/routing/app_route.dart` TÉNYLEGES típusos útvonal-mintáját — a CTA arra épül. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/presentation/screens/quests_screen.dart",
  "lib/features/gamification/presentation/widgets/quest_card.dart",
  "lib/features/gamification/presentation/widgets/challenge_card.dart",
  "lib/features/gamification/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/gamification/presentation/quests_screen_test.dart",
  "docs/rounds/e08-r20-quest-and-challenge-ui.md",
]
gate_tests = [
  "test/features/gamification/presentation/quests_screen_test.dart",
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

Áttekinthető napi/heti küldetés- és kihívás-élmény: **semleges** lejárati szöveggel,
**beváltás nélküli** jutalommal és biztonságos, típusos CTA-val.

## 2. Jelenlegi állapot — mért tények

- Az R16 zárt állapotgépet, az R19 napi kihívás-szolgáltatást ad.
- `quests_screen.dart` **nem létezik**.
- A projekt típusos útvonal-mintája: `lib/app/routing/app_route.dart` — a CTA ezt használja, de az útvonal-REGISZTRÁCIÓ a Kör 30.
- Az `ADR 0290`: nincs sürgető, szégyenítő nyelv; a jutalom nem beváltás-függő.

## 3. Scope

**Benne van:** objective-haladás, jutalom és a forrás-terv kapcsolatának megjelenítése · Start/Continue
CTA **típusos** útvonal-akcióval · helyettesítés felkínálása, ha az objective nem elérhető ·
**semleges** lejárati szöveg · a teljesített küldetés jutalma automatikusan látszik, beváltás
nélkül · offline és üres állapot.

**NINCS benne (tilos):**

- Beváltás (claim) gomb bevezetése — az R16 §5.1 tiltja.
- Sürgető visszaszámláló vagy szégyenítő lejárati szöveg.
- Jutalom-számítás a felületen (ADR 0290 §2).
- `lib/app/routing/**` — az útvonal-regisztráció a Kör 30.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/presentation/screens/quests_screen.dart` | **ÚJ** — a napi/heti nézet |
| `lib/features/gamification/presentation/widgets/quest_card.dart` | **ÚJ** — a küldetés-kártya |
| `lib/features/gamification/presentation/widgets/challenge_card.dart` | **ÚJ** — a kihívás-kártya |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `lib/l10n/app_en.arb` | az ÚJ kulcsok |
| `lib/l10n/app_hu.arb` | az ÚJ kulcsok magyar párja |
| `test/features/gamification/presentation/quests_screen_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések

### 5.1 NINCS beváltás-gomb — a jutalom már jóváírt

A teljesített küldetés jutalma a felület megnyitása nélkül is a főkönyvben van.
A kártya ezt **mutatja**, nem kiváltja.

**NEM elfogadható gyengítés:** „Begyűjtés” gomb animációval. Az elveszi a jutalmat attól,
aki nem nyitja meg a képernyőt.

### 5.2 A LEJÁRAT SEMLEGES — nincs visszaszámláló, nincs sürgetés

A lejárati szöveg tényközlő („ma éjfélig”, nem „Már csak 2 óra!!!”), és nincs
futó visszaszámláló. Ez az ADR 0290 §1 alkalmazása, és tiltott-szó listával mért
acceptance-cella (A3).

### 5.3 A CTA TÍPUSOS és BIZTONSÁGOS

A Start/Continue akció típusos útvonal-akciót ad vissza, nem szabad szöveges
útvonalat. Nem elérhető cél esetén a CTA letiltott vagy helyettesítést kínál — sosem vezet
összeomláshoz vagy üres képernyőre.

### 5.4 A felület NEM SZÁMOL

Minden haladás és jutalom készen érkezik az application-rétegből (ADR 0290 §2).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A teljesített küldetés jutalma beváltás nélkül látszik; NINCS „begyűjtés” gomb | `quests_screen_test.dart` |
| A2 | A haladás pontos, és az application-rétegből jön (a felület nem számol) | `quests_screen_test.dart` + review |
| A3 | A lejárati szöveg semleges: nincs visszaszámláló és nincs sürgető szó | `quests_screen_test.dart` — tiltott-szó cella |
| A4 | A CTA típusos útvonal-akciót ad; nem elérhető célnál letiltott vagy helyettesítést kínál | `quests_screen_test.dart` — CTA-mátrix |
| A5 | A forrás-terv kapcsolat látszik (melyik terv-blokkból jött a küldetés) | `quests_screen_test.dart` |
| A6 | Offline állapotban is teljes a nézet (nincs hálózati függés) | `quests_screen_test.dart` |
| A7 | Üres állapot van új felhasználónak | `quests_screen_test.dart` |
| A8 | 200%-os szövegskálán nincs levágás; a szemantikus címkék teljesek | `quests_screen_test.dart` — a11y-mátrix |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| „Begyűjtés” gomb a kártyán | **A1** |
| Futó visszaszámláló a lejárathoz | **A3** |
| A CTA szöveges útvonalat ad | **A4** |
| A kártya maga összegzi a haladást | **A2** |
| Hálózati hívás a nézetben | **A6** |
| Fix magasságú kártya | **A8** |

**A küszöb három kötelező cellája** (a szövegskála (`textScaleFactor`)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `1.0` | nincs levágás — triviális |
| **rajta** (a küszöbön) | `2.0` (200%, a projekt a11y-mércéje) | **nincs levágás, nincs túlcsordulás** — kötelező cella |
| a küszöb **fölött** | `3.0` | görgethető marad; összeomlás NEM elfogadható |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tegyél a kártyára „Begyűjtés” gombot, ami a jutalmat kiváltja, futtasd a gate-et →
az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/presentation/quests_screen_test.dart
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

1. Az ARB-kulcsok felvétele mindkét nyelven, semleges lejárati szövegekkel.
2. `quest_card.dart` — haladás, jutalom, forrás-terv, CTA.
3. `challenge_card.dart` — a napi kihívás.
4. `quests_screen.dart` — napi/heti nézet, offline és üres állapot.
5. A típusos CTA és a helyettesítés felkínálása.
6. a11y: szemantikus címkék, 200% szövegskála.
7. A `public.dart` export-sorai; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A begyűjtés-gomb.** A műfaj alapértelmezett mintája, és a jutalmat a képernyő-megnyitáshoz köti (A1).
- **A visszaszámláló.** „Segítőkésznek” tűnik, és sürgetést termel — az ADR 0290 tiltólistáján (A3).
- **A szöveges útvonal.** Elgépelésre összeomlik vagy üres képernyőt ad; a típusos akció ezt kizárja (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
