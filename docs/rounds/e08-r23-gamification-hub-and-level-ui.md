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
  "lib/l10n/features/gamification_en.arb",
  "lib/l10n/features/gamification_hu.arb",
  "test/features/gamification/presentation/gamification_hub_screen_test.dart",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e08-r23-gamification-hub-and-level-ui.md",
]
gate_tests = [
  "test/features/gamification/presentation/gamification_hub_screen_test.dart",
  "test/ui/ui_inventory_test.dart",
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

## 0.0 Pre-flight revízió (Claude, 2026-08-22)

**Kockázat = high, indoklás:** a `risk = "high"` a brief mérce-tartalma miatt
áll (ADR 0289 legszigorúbb, felhasználó-szembeni alkalmazása egy központi
áttekintő felületen — az XP/készség vizuális összemosása a termék legnagyobb
őszinteségi kockázata, L399/ADR 0388 ugyanezt a mintát mérte a mastery-jelvény
oldalon), NEM azért, mert az `allowed_paths` a router `high_risk_path_fragments`
listájából (auth, authorization, camera, credential, crypto, encryption,
migration, payment, privacy, secret, share, upload, vision) bármelyiket
tartalmazná — nem tartalmazza, a kör tisztán presentation-réteg.

**ADR:** a brief saját besorolása szerint ez a kör NEM hoz kötött
architekturális döntést (a Hub az ADR 0289/0342/0388 MEGLÉVŐ szabályait
alkalmazza vizuálisan, új szabályt nem vezet be) — a `tools/round-slots.py
reserve-adr` futása ezért ELMARAD; a queue `E08-R23` sorának `nincs` ADR-oszlopa
így marad.

**Kód-mérés a §2 „Jelenlegi állapot" ellen:** `wc -l
lib/features/progress/screens/progress_screen.dart` → **516 sor**, egyezik a
brief állításával. `grep -rn "gamification_hub_screen"
lib/features/gamification/` → 0 találat, a fájl valóban nem létezik.
`grep -c "hasLength(62)" test/ui/ui_inventory_test.dart` → a mai bázisvonal
**62** (az E08-R22 §0.0.2 javítása után).

**Visszakeresett előzmény (ADR 0312, §4.9):**
- `adr/0289` (mastery-is-evidence-not-xp), `adr/0342`
  (monotonic-level-curve-and-rebuildable-profile-projection), `adr/0388`
  (mastery-milestone…) — a Hub e három ADR MEGLÉVŐ szabályait vetíti UI-ra,
  új döntést egyik sem igényel (szűkített `lessons,halts,adr` lekérdezés,
  `adr/0342` bm25#12 emb#3, `adr/0289` bm25#28 emb#2).
- `lessons/L397` (és a mögötte álló `L395`) — **közvetlenül releváns**: a
  `test/ui/ui_inventory_test.dart` egy rögzített production-screen
  bázisvonalat őriz, és MÁSODSZOR is CI-only lelet volt, amikor egy UI-kör
  új screen-t adott a fájlrendszerhez a saját célzott gate-jén kívül
  (E08-R20, majd E08-R22 is bővítette 61→62-re). Ez a kör **két** új
  screent ad (`gamification_hub_screen.dart`,
  `level_detail_screen.dart`), tehát a bázisvonal 62→**64**-re nő —
  ugyanaz a hibaosztály harmadszor is bekövetkezne, ha nem kezelném itt.
  **Döntés:** a `test/ui/ui_inventory_test.dart` felvéve az
  `allowed_paths`-ba (lásd lent), az implementációs sorrend egy lépéssel
  bővül, és a §7 gate-parancs is kiegészül ezzel az útvonallal — a második
  CI-piros-kör elkerülése a cél, nem a mérce lazítása (a fájl tartalma
  ettől még egy MÉRT, futtatható asserttel védett bázisvonal marad).
- `lessons/L261`/`L270`/`L246` — az `allowed_paths` és az acceptance
  criteria/kód-valóság közti ellentmondást a brief-lint nem fogja meg, a
  pre-flight keresztellenőrzése a védelem; ez a bővítés pontosan ezt a
  mintát követi (BOUND kivétel egy konkrét fájlra, nem zóna-tágítás).

### 0.0.1 `allowed_paths` bővítés — `test/ui/ui_inventory_test.dart`

A router-blokk `allowed_paths` tömbje a fenti indoklással **egy fájllal**
bővül:

```
"test/ui/ui_inventory_test.dart"
```

Az implementer teendője: ha (és csak ha) a saját screen-számlálása a Hub +
level-detail felvétele után nem 64-et ad, a `hasLength(62)` asszertumot a
mért tényleges számra igazítsa **ugyanabban a commitban** — ne a `62`-t
feltételezze vakon, mérje (`git diff --stat` + a teszt saját hibaüzenete
kiírja a tényleges screen-listát).

### 0.0.2 Kör közbeni revízió — `stopped` után, 2026-08-22

Az implementer (`minimax`) jogosan `stopped`-ot jelzett: a brief eredeti
`allowed_paths`-a a GENERÁLT aggregátumokat (`lib/l10n/app_en.arb`,
`lib/l10n/app_hu.arb`) listázta, de **2026-08-20 óta** (PR #343, ADR 0307
§4) ezek generált fájlok — a tényleges forrás a `lib/l10n/features/
gamification_{en,hu}.arb` fragmentum, a `check_l10n_parity` frissesség-őr
ebből regenerálja az aggregátumot. Ugyanaz a hibaosztály, mint az E08-R20
§0.0.1 (L396) és az E08-R22 §0.0.1 — a brief 2026-08-18-i írása nem
ismerhette a váltást.

**Kód-mérés:** `ls lib/l10n/features/gamification_{en,hu}.arb` →
mindkét forrás-fragmentum létezik (16 288 / 16 618 bájt, utolsó módosítás
E08-R22-ből).

**Döntés:** az `allowed_paths` a generált aggregátum helyett a forrás-
fragmentumra cserélve (lásd fent a §4 táblázatot és a router-blokkot) — ez
**szűkítés + célfájl-csere**, nem tágítás, tehát a §2 szerint az
orchestrátor saját hatásköre. Az implementer az új kulcsokat a
`lib/l10n/features/gamification_{en,hu}.arb` fragmentumba veszi fel, majd
`dart run tool/gen_l10n_segments.dart --write`-tal regenerálja az
aggregátumot a §7 gate előtt — a generált `lib/l10n/app_{en,hu}.arb` fájl
maga NEM kerül `allowed_paths`-ba (a `tools/round-slots.py`
`GENERATED_PATHS` halmaza kifejezetten emiatt nem tekinti slot-ütközésnek),
a `check_l10n_parity` gate-lépés `--check` módban ellenőrzi a szinkront.

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
| `lib/l10n/features/gamification_en.arb` | az ÚJ kulcsok (forrás-fragmentum, §0.0.2) |
| `lib/l10n/features/gamification_hu.arb` | az ÚJ kulcsok magyar párja (forrás-fragmentum, §0.0.2) |
| `test/features/gamification/presentation/gamification_hub_screen_test.dart` | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | a rögzített production-screen bázisvonal 62→64 (§0.0.1, L397) |

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
tools/round-gate.sh test/features/gamification/presentation/gamification_hub_screen_test.dart test/ui/ui_inventory_test.dart
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
8. `test/ui/ui_inventory_test.dart` bázisvonal-frissítés (§0.0.1) — csak a
   TÉNYLEGES, mért screen-számra, nem vakon.
9. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A két egyforma sáv.** Vizuálisan letisztult, és pontosan azt a félreértést termeli, amit az ADR 0289 tilt (A1).
- **A Hub „főképernyővé” tétele.** Az Epic célja nem-domináló réteg; a `progress` leváltása scope-sértés (A7).
- **A megnyitáskori újraszámolás.** Nagy főkönyvön érezhető akadás (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
