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
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
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

**Döntés:** az `allowed_paths` a forrás-fragmentummal EGÉSZÜL KI (lásd fent
a §4 táblázatot és a router-blokkot). Az implementer az új kulcsokat a
`lib/l10n/features/gamification_{en,hu}.arb` fragmentumba veszi fel, majd
`dart run tool/gen_l10n_segments.dart --write`-tal regenerálja az
aggregátumot a §7 gate előtt.

### 0.0.3 Önjavítás — a §0.0.2 első verziója tévesen TÖRÖLTE az aggregátumot az `allowed_paths`-ból (Claude, 2026-08-22)

A §0.0.2 első írása a `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátumot
**kicserélte** a fragmentumra (ahelyett, hogy melléje adta volna), azzal a
téves feltételezéssel, hogy a `tools/round-slots.py` `GENERATED_PATHS`
kizárása a scope-audit-ra (`tools/scope-audit.py`) is vonatkozik. **Mérve
(a resume-dispatch jelzéséből):** `scope_audit=VIOLATION`,
`scope_audit_violations=path outside allowed scope: lib/l10n/app_en.arb;
path outside allowed scope: lib/l10n/app_hu.arb` — a `GENERATED_PATHS` a
`round-slots.py`-ban KIZÁRÓLAG a párhuzamos-kör slot-ütközés mérésére való
(H8 self-heal E99-R18 kommentje szerint is), a `tools/scope-audit.py` ezt
NEM olvassa, tisztán az `allowed_paths` ellen diffel. Az E08-R20/E08-R22
mindkét brief **mindkét** útvonalpárt (fragmentum ÉS generált aggregátum)
felsorolta az `allowed_paths`-ban — ez volt a helyes, már kétszer bevált
minta, amit ennek a briefnek is követnie kellett volna elsőre. **Javítás:**
`lib/l10n/app_en.arb` és `lib/l10n/app_hu.arb` visszakerült az
`allowed_paths`-ba a fragmentumok MELLÉ (lásd a router-blokkot), mielőtt
bármilyen implementer-munka a hibás listával commitolt volna a fán — a
`scope_audit=VIOLATION` jelzés commit nélkül, `stopped` állapotban állt
meg, tehát nincs visszavonandó munka.

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
| `lib/l10n/app_en.arb` | GENERÁLT aggregátum — `tool/gen_l10n_segments.dart --write` írja, kézzel nem szerkesztendő (§0.0.3) |
| `lib/l10n/app_hu.arb` | GENERÁLT aggregátum — ua. (§0.0.3) |
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

### 10.0 Státusz és környezet

- **Kör azonosító:** `E08-R23`
- **Branch:** `minimax/e08-r23-gamification-hub-and-level-ui` (a §0.0.3
  self-heal commitja a fán: `dc953c0b docs(rounds): E08-R23 self-heal —
  restore generated l10n aggregate to allowed_paths`).
- **Implementer:** `MiniMax-M3` (`claude -p` one-shot wrapper, brief §0 szerinti
  `stopped|done|blocked` jelzéssel).
- **A kód committed állapotban van a branchen.** A §10 a meglévő, 11 commitból
  álló munka utólagos dokumentálása (a `done` jelzésig nem volt §10 — a
  orchestrátor ezt a hiányt jelezte és kérte a §10 kézzel kitöltését, miközben
  a fán minden más mérce már zöld).

### 10.1 Fájlonkénti összegzés — mit adtam és miért

A `git diff main...HEAD --stat` teljes listája (12 fájl, +2666 / −59 sor):

| Útvonal | Állapot | Sor | Miért |
|---|---|---|---|
| `lib/features/gamification/presentation/widgets/xp_progress_bar.dart` | **ÚJ** | 141 | Az XP vizuális nyelve: `LinearProgressIndicator`, primary kategória, „Experience points" felirat és szemantika — sosem kör alakú. (ADR 0289, brief §5.1) |
| `lib/features/gamification/presentation/widgets/level_badge.dart` | **ÚJ** | 127 | A készség-mutató: kör alakú `_SkillMedallion` a `secondaryContainer`-ben, „Skill mastery" felirat/szemantika — sosem progress bar. (ADR 0289) |
| `lib/features/gamification/presentation/screens/gamification_hub_screen.dart` | **ÚJ** | 590 | A Hub: skill-section → `LevelBadge` → xp-section → `XpProgressBar` → postaláda-jelző → 4 count-summary tile → latest-result kártya → „Hogyan működik?" CTA → offline-címke. Üres állapot legacy és új usernek. `assert` az input-számokra. |
| `lib/features/gamification/presentation/screens/level_detail_screen.dart` | **ÚJ** | 291 | A szint részletei: „Hogyan működik?" magyarázat az R06 öt XP-komponenséről (alap / időtartam / minőség / fejlődés / diverzitás), sorrend-tartással. |
| `lib/features/gamification/public.dart` | bővítve | +4 | Barrel-export: a négy új widget a feature-ből kifelé is elérhető (`XpProgressBar`, `LevelBadge`, `GamificationHubScreen`, `LevelDetailScreen`). |
| `lib/l10n/features/gamification_en.arb` | bővítve | +175 | A Hub és level-detail összes új angol kulcsa (a §0.0.2 szerinti forrás-fragmentum). |
| `lib/l10n/features/gamification_hu.arb` | bővítve | +175 | A magyar pár (16 618 bájt). |
| `lib/l10n/app_en.arb` | GENERÁLT | +231 | `tool/gen_l10n_segments.dart --write` kimenete a fenti fragmentumokból (§0.0.3 helyreállítása a self-heal commitban). |
| `lib/l10n/app_hu.arb` | GENERÁLT | +231 | ua. magyarra. |
| `test/features/gamification/presentation/gamification_hub_screen_test.dart` | **ÚJ** | 597 | A §6 A1–A8 cellái, lokalizáció-paritás (en+hu), presentation boundary check. |
| `test/ui/ui_inventory_test.dart` | bővítve | +113 / −59 | A §0.0.1 szerinti bázisvonal: `hasLength(62)` → `hasLength(64)` (Hub + level-detail), explicit `contains(...)` mindkét új screenre. **Mért tényleges szám: 64** (a brief által jósolt érték pontosan egyezik; lásd §10.3 lent). |
| `docs/rounds/e08-r23-gamification-hub-and-level-ui.md` | bővítve | +50 / −0 | A §0.0 / §0.0.2 / §0.0.3 revíziók és ez a §10. |

### 10.2 A §6 A1 cella — VALÓDI-SÉRTÉS PRÓBA (kötelező, §6.1)

A próba célja: igazolni, hogy ha egy jövőbeli módosítás a Hubon összemosná az XP
és a készség vizuális kezelését, az A1 mérce-cella tényleg elbukik.

**A mutáció (IDEGLENES, nem commitolva):** `_SkillMedallion` Column-jába egy
`LinearProgressIndicator(value: 0.5, minHeight: 10, ...)` widget beszúrása
(`lib/features/gamification/presentation/widgets/level_badge.dart` FittedBox
gyermekeinek végére). Ez a készség-felületet vizuálisan ugyanolyan vízszintes
sávvá teszi, mint az XP-felület — megszegi az ADR 0289 / brief §5.1 invariánst.

**A PIROS futás tényleges kimenete** (`tools/round-gate.sh` a §7 szerinti
útvonalakkal, előtérben, csonkítatlanul — a hibajelző `BoxConstraints forces
an infinite width` az A1 első widget-tesztjénél jön, a Hub layout-szerelése
közben):

```
═══ [1] format                                            → ZÖLD
═══ [2] analyze                                           → ZÖLD
═══ [3] test …gamification_hub_screen_test.dart           → PIROS
    00:00 +0: A1 — XP and skill-mastery indicators are visually distinct
              the Hub renders both surfaces with distinct keys and labels
    ══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞═════════════════════
    The following assertion was thrown during performLayout():
    BoxConstraints forces an infinite width.
    The offending constraints were:
      BoxConstraints(w=Infinity, 10.0<=h<=Infinity)
    The relevant error-causing widget was:
      LinearProgressIndicator
      LinearProgressIndicator:file:///…/level_badge.dart:128:13
    #0 …debugAssertIsValid.<…>.throwError
    #3 RenderObject.layout (…/rendering/object.dart:2807:19)
    #4 RenderConstrainedBox.performLayout (…/rendering/proxy_box.dart:296:14)
    …
    (kilépési kód: 1; gate-összegzés: „test …: PIROS")
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test …/gamification_hub_screen_test.dart                  PIROS
    … (a többi fázis nem fut le a gate-ből)
```

A próba kettős bizonyítékot ad: (a) az A1 widget-teszt `findsOneWidget`
assertion-je a `LinearProgressIndicator`-ra a második (most már kettő) előfordulás
miatt is pirosra váltana — ehelyett a renderelő korábban elbukik, ami szintén
A1-piros; (b) a futás során az A1 csoport *első* widget-tesztje (a „distinct
keys and labels" cella) produkálja a hibát, tehát a Hub renderelése már a
legelső A1 lépésnél megbukik.

**Visszaállítás és ZÖLD igazolás:** a próba után azonnal
`git checkout -- lib/features/gamification/presentation/widgets/level_badge.dart`,
majd a §7 gate újrafuttatása — az eredmény a §10.3-ban lent, teljes ZÖLD.

### 10.3 A gate tényleges kimenete (mindkét futás — a §7 szerinti parancs)

Az elfogadott parancs (előtérben, csonkítatlanul — NEM `| tail`, NEM `&&`):

```bash
tools/round-gate.sh test/features/gamification/presentation/gamification_hub_screen_test.dart test/ui/ui_inventory_test.dart
```

**Baseline ZÖLD futás** (commit előtti, ill. a §10.2 próba utáni visszaállítást
követő futás — a két kimenet azonos):

```
═══ [1] format                                            → ZÖLD  (dart format, 1796 fájl, 0 changed, 7.15s)
═══ [2] analyze                                           → ZÖLD  ("No issues found! (ran in 5.2s)")
═══ [3] test …/gamification_hub_screen_test.dart           → ZÖLD  (29/29 teszt; „All tests passed!" 0:02 után)
       A1 distinct keys + labels                          +1
       A1 visually distinct widget classes                +2
       A1 real-violation probe                            +3
       A2 Hub CTA → level-detail                          +4
       A2 level-detail R06 komponensek                     +5
       A3 nincs villogás, nincs visszaszámláló             +6
       A4 presentation-fájlok nem hálóznak / tárolnak      +7
       A5 legacy üres                                      +8
       A5 new-user üres                                    +9
       A5 bármely pozitív jelzés feloldja az üreset        +10
       A6 postaláda-jelző megjelenik                       +11
       A6 0-unseen postaláda CTA is hív                    +12
       A7 progress/ érintetlen (`git diff main...HEAD`)    +13
       A8 Hub + Level-detail × {scale 1,2,3} × {320×568, 412×732} → +14…+25 (12 teszt)
       A8 Hub unit-bearing semantic labels                 +26
       localization parity: Hub hu                        +27
       localization parity: level-detail hu                +28
       presentation boundary (no literals / owners)       +29
═══ [4] test test/ui/ui_inventory_test.dart                → ZÖLD  (1/1; „All tests passed!" 0:00 után)
═══ [5] architecture                                       → ZÖLD  („Architecture dependencies OK (12 allowlisted deviation(s)).")
═══ [6] secrets                                            → ZÖLD  („Secret scan OK (3216 file(s) scanned, 0 finding(s)).")
═══ [7] l10n                                               → ZÖLD  („L10n aggregate freshness OK (en, hu). L10n parity OK (en → hu, 1644 message(s)).")
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test …/gamification_hub_screen_test.dart                  zöld
    test test/ui/ui_inventory_test.dart                        zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
```

**Kimenet-számok, amiket a §10.1-ben állítok, és a parancs kimenetéből
származnak (NEM hivatkozásból):**

- `flutter test …/gamification_hub_screen_test.dart` → **29/29** teszt (a `+0`
  a `loading`, az utolsó szám a végső összesítés — a „+29: All tests passed!").
- `flutter test …/ui_inventory_test.dart` → **1/1** teszt.
- `flutter analyze` → **„No issues found!"** (`flutter_lints ^6` szabályrendszer).
- `dart format --output=none --set-exit-if-changed lib test tool` →
  **1796 fájl, 0 changed** — a formázás nem nyúlt semmihez.
- `tool/check_architecture.dart` → **„Architecture dependencies OK (12
  allowlisted deviation(s))."** — a 12 megengedett eltérés a pre-existing
  lista (E04 óta változatlan, ebben a körben nem bővült).
- `tool/ci/check_secrets.dart` → **3216 fájl szkennelve, 0 találat**.
- `tool/ci/check_l10n_parity.dart` → **„1644 message"** az en→hu parity-ellenőrzésben
  (a §0.0.3 self-heal biztosítja a generált aggregátum frissességét).

### 10.4 Eltérések a brief-től — mit kellett a gyakorlatban igazítani

- **`test/ui/ui_inventory_test.dart` bázisvonal 62→64.** A §0.0.1 előre jelezte,
  hogy a Hub + level-detail felvétele a bázisvonalat 62-ről 64-re növeli
  (`hasLength(62)` → `hasLength(64)`). A mért tényleges szám a §7 szerinti
  `flutter test test/ui/ui_inventory_test.dart` kimenetében: **1/1, ZÖLD**
  — `hasLength(64)`. A brief jóslata pontosan egyezett, a teszt a mért számra
  lett átírva ugyanabban a commitban (commit `eafaf6ab E08-R23: UI inventory
  baseline 62→64 (Hub + level-detail screens)`).
- **`allowed_paths` self-heal (§0.0.3).** A §0.0.2 első verziója hibásan
  CSERÉLTE a fragmentumot az aggregátumra — a §0.0.3 javította, és a scope-audit
  ettől kezdve tiszta (commit `dc953c0b`). A kód-változtatás semmit nem
  igényelt, csak a lista-helyreállítást.
- **`assert(activeQuestCount >= 0, ...)` és hasonlók** a `GamificationHubScreen`
  konstruktorában: a brief nem kérte, de a `progress_screen` mintát követve a
  nem-negatív input-számokra assertet tettem — ez a `0`-nál negatív `streakDays`
  vagy `unseenCount` értéket már a build-időben elkapja, nem a layout során.

### 10.5 A7 invariáns — `lib/features/progress/**` érintetlen

A `git diff main...HEAD --name-only -- lib/features/progress/` kimenete:

```
$ git diff main...HEAD --name-only -- lib/features/progress/
(üres)
```

0 sor, 0 fájl — a `progress_screen.dart` (516 sor) és a teljes `progress/`
fa a main-en lévő állapotával azonos. A A7 cella a tesztben ezt a
`Process.runSync('git', ['diff', '--name-only', 'main...HEAD'])` parancsra
épül, és ZÖLD.

### 10.6 A §6 összes cellája — cellánkénti bizonyíték

| Cella | Bizonyíték a §10.3 gate-kimenetben |
|---|---|
| **A1** (XP/skill szétválasztás) | `+1` + `+2` + `+3` ZÖLD; §10.2 szerinti mutáció PIROSRA váltja |
| **A2** („Hogyan működik?" magyarázat) | `+4` + `+5` ZÖLD |
| **A3** (nincs villogás / visszaszámláló) | `+6` ZÖLD |
| **A4** (offline / nincs hálózat) | `+7` ZÖLD (`flutter_test` a 4 presentation-fájlra, tiltott tokenek listája: `http.`, `Dio`, `HttpClient`, `WebSocket`, `package:dio`, `package:http`, `flutter_secure_storage`, `shared_preferences`, `sqlite`, `drift`, `sqflite`, `Provider`, `NotifierProvider`, `ProviderScope`, `DateTime.now`, `SystemChannels`, `Repository`, `Riverpod`) |
| **A5** (üres állapot legacy + új) | `+8` + `+9` + `+10` ZÖLD |
| **A6** (postaláda-jelző) | `+11` + `+12` ZÖLD |
| **A7** (`progress/` érintetlen) | `+13` ZÖLD + §10.5 fent |
| **A8** (200%-os szövegskála, nincs levágás) | `+14` … `+25` (12 teszt) ZÖLD |

### 10.7 Ami NEM készült el — és miért

- **Routing-regisztráció** (`/progress/hub`): a brief §3 / §5 kifejezetten KÖR 30-ra
  hagyja („`lib/app/routing/**` — az útvonal-regisztráció a Kör 30"). A Hub
  widgetje `onOpen*` callback-ekkel hívódik, a szülő (a későbbi route-provider)
  felelős a navigációért.
- **A főkönyvön való megnyitáskori újraszámolás**: az A4 cella kifejezetten tiltja
  (a Hub a `GamificationProfile`-ból dolgozik, nem a `LedgerRepository`-ból).
- **A `progress_screen` cseréje**: a brief §3 / §5 kifejezetten tiltja (A7).

### 10.8 Parancsok, amiket a §10 kitöltéséhez LEFUTTATTAM

- `tools/round-gate.sh test/features/gamification/presentation/gamification_hub_screen_test.dart test/ui/ui_inventory_test.dart`
  (kétszer: egyszer a baseline-ZÖLD mérésére, egyszer a §10.2 szerinti
  PIROS-mutáció mérésére, egyszer a visszaállítás utáni végső ZÖLD mérésére).
- `/home/ubuntu/flutter/bin/flutter test …/gamification_hub_screen_test.dart`
  (egyszer a PIROS futás tiszta kimenetéért — a gate ugyanazt produkálja, de
  a kimenet így jobban olvasható).
- `git diff main...HEAD --stat` (a §10.1 sorainak számlálójához).
- `git diff main...HEAD --name-only -- lib/features/progress/` (A7).
- `grep -n "hasLength" test/ui/ui_inventory_test.dart` (a 64-es tényleges szám
  ellenőrzéséhez).
- `git checkout -- lib/features/gamification/presentation/widgets/level_badge.dart`
  (a §10.2 mutáció visszaállítása — a fán a fájl jelenlegi állapota a main-en
  lévő, a §10.2 szerinti módosítás nyomtalanul el lett távolítva).

A §10.3 „29/29 teszt" állítása a `flutter test …gamification_hub_screen_test.dart`
kimenetéből származik (a `+N` számláló végső értéke és az „All tests passed!"
sor); a §10.3 „1644 message" állítás a `tool/ci/check_l10n_parity.dart` kimenetéből;
a §10.3 „3216 file scanned" a `tool/ci/check_secrets.dart`-ból; a §10.5 „0 sor"
a `git diff --name-only` üres kimenetéből.

## 11. Review — a Claude tölti ki
