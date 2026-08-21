# E08-R20 — Review

Brief: `docs/rounds/e08-r20-quest-and-challenge-ui.md`
Diff: `git diff 3b5ddba0199f...minimax/e08-r20-quest-and-challenge-ui`
Reviewer: Claude Sonnet 5 (orchestrátor+reviewer) · Dátum: 2026-08-21
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 1

Három dispatch: (1) `docs/rounds/...md` prompttal induló implementáció
jogosan `stopped`-ot jelzett az `app_en.arb`/`app_hu.arb` GENERÁLT-aggregátum
felismerésekor (ADR 0307 §4) — az orchestrátor §0.0.1 brief-revízióval
felvette a tényleges forrást (`lib/l10n/features/gamification_{en,hu}.arb`)
az `allowed_paths`-ba; (2) egy fókuszált javító-prompt (a §0.0.1 szerint) a
kulcsokat átvitte a fragmentumba és regenerálta az aggregátumot — `done`
jelzéssel zárt, célzott gate zöld; (3) az első CI-dispatch
(`full-gate.yml`, run 32530048719) a teljes suite-ban egyetlen, a kör saját
`gate_tests`-én kívüli tesztet buktatott (`test/ui/ui_inventory_test.dart`,
rögzített 60-elemű production-screen bázisvonal az új `quests_screen.dart`
miatt 61-re nőtt) — §0.0.2 brief-revízió az `allowed_paths`/`gate_tests`
bővítésével, egysoros javító-prompt (`hasLength(60)` → `hasLength(61)`),
`done` jelzéssel zárt, gate zöld friss izolált klónban is (lásd lent).

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Beváltás nélkül látszó jutalom, nincs „begyűjtés" gomb | ✅ | `quest_card.dart:147-155,180-187` (`_QuestReward` completed-ágon `creditedLabel`, nincs gomb); teszt: `quests_screen_test.dart:282-311`; **saját mutáció-próba** (lásd lent) megerősítette, hogy a teszt valódi sértést fog |
| A2 | Haladás caller-fed, a felület nem számol | ✅ | `quest_card.dart:78-85,336-338` (`ratio` a caller `completedUnits`/`targetUnits`-ból, nincs domain-hívás); `quests_screen.dart:13-30` (`QuestViewProjection` — minden caller-fed) |
| A3 | Semleges lejárat, nincs visszaszámláló/sürgető szó | ✅ | `quest_card.dart:233-251` (`_expiryLabel`: nap/hét/dátum szöveg, nincs `Timer`/`Ticker`); saját ARB-scan 0 találat a tiltott szavakra (`hurry`, `urgent`, `!!`, `last chance` stb., 197 kulcs); teszt: `quests_screen_test.dart` A3-csoport |
| A4 | Típusos CTA, letiltott/helyettesítő nem elérhető célnál | ✅ | `quest_card.dart:12-46` (`sealed class QuestRouteAction` + 4 konkrét típus, sosem string route); `_QuestCta` letiltja a gombot `contentAvailable=false`-nál; CTA-mátrix teszt lefedi mind a 4 ágat |
| A5 | Forrás-terv kapcsolat látszik | ✅ | `quest_card.dart:216-231` (`_sourceLabel`: `sourcePlanLabel` caller-fed, vagy fallback az objective típusra) |
| A6 | Offline állapot teljes, nincs hálózati függés | ✅ | `grep -rn "package:dio\|package:http\|HttpClient\|Supabase" lib/features/gamification/presentation/` → 0 találat (saját mérés); `quests_screen.dart:173-206` (`_OfflineBanner` mindig renderel hálózat nélkül) |
| A7 | Üres állapot új felhasználónak | ✅ | `quests_screen.dart:74-75,208-237` (`_isEmpty` → `_EmptyQuestsState`) |
| A8 | 200%-os szövegskálán nincs levágás | ✅ | `quests_screen.dart` `ListView` + `Card`+`Column(mainAxisSize: min)` — nincs fix magasság; teszt: `textScaler 1.0/2.0/3.0` csoport, mind zöld a saját gate-futásban |

## Scope-audit

```
python3 tools/scope-audit.py --repo /tmp/review-e08-r20 --brief docs/rounds/e08-r20-quest-and-challenge-ui.md --base 3b5ddba0199f
→ Legacy scope audit OK (3b5ddba0199f..7a2c9420d27b, 10 changed path(s), 0 generated/ignored)
```

Engedélyezett fájlokon kívüli változás: **nincs**. A `public.dart` diffje
kizárólag export-sor (mérve: `git diff 3b5ddba0199f -- lib/features/
gamification/public.dart` → 2 új export sor, más nem változott).

## Megállapítások

### F1 — MINOR — A §6.1 „valódi-sértés próba" a shipping test suite-ban nem a production widgetet mutálja, és a brief §10 handoff üres

- **Fájl:** `test/features/gamification/presentation/quests_screen_test.dart:659-695`
- **Probléma:** a brief §6.1 KÖTELEZŐ előírása szerint a próba a
  **production** `quest_card.dart`-ra tenne egy „Begyűjtés" gombot, futtatná
  a gate-et, megfigyelné a PIROS A1 cellát, majd visszaállítaná — ezt kellett
  volna `§10`-ben dokumentálni. A ténylegesen bekerült teszt ehelyett egy
  önálló, a `QuestCard`-tól független `MaterialApp`/`Scaffold` fát épít fel
  kézzel beleírt „Begyűjtés" szöveggel, és csak azt állítja, hogy ez a szöveg
  megtalálható — ez semmit nem bizonyít az ÉLES widget viselkedéséről, csak a
  Flutter `find.text` API-ról. A `docs/rounds/e08-r20-quest-and-challenge-ui.md`
  §10 („Implementation handoff") szakasza üres maradt.
- **Hatás:** a shipping teszt-fájlban egy „Real-violation probe" nevű teszt
  fals biztonságérzetet kelt — jövőbeli olvasó azt hiheti, hogy az A1 guard
  mutáció-próbával verifikálva van, holott a próba nem a valós widgetet
  mutálja. Funkcionális hatás nincs (lásd lent — a valós guard működik).
- **Kötelező javítás:** nem blokkoló; follow-up körben cseréld a szintetikus
  tesztet egy olyanra, ami ideiglenesen (git-stash-elt vagy paraméterezett)
  módosítja a `QuestCard`-ot, VAGY törölje a félrevezető nevet/kommentet, és
  töltse ki a brief §10-ét a review-ban elvégzett (lásd lent) mutáció-próba
  hivatkozásával.
- **Ellenőrzés:** a reviewer SAJÁT kézzel elvégzett mutáció-próbája (lásd
  alább) — ez pótolja a hiányzó bizonyítékot erre a merge-re, a follow-up
  csak a test-suite tisztaságát javítaná.
- **Státusz:** OPEN (nem blokkol, follow-up ajánlott)

**Saját mutáció-próba (reviewer, `/tmp/review-e08-r20`):** a production
`quest_card.dart` `completed` ágába ideiglenesen egy
`FilledButton(child: Text('Begyűjtés'))` gombot szúrtam, majd:

```
flutter test test/features/gamification/presentation/quests_screen_test.dart --plain-name "A1"
→ A1 teszt PIROS: "Expected: no matching candidates / Actual: ... Found 1 widget with text 'Begyűjtés'"
```

Ezután a fájlt visszaállítottam (`cp` a mentett eredetiből), és a teszt újra
ZÖLD lett. **Ez az A1 guard valódi, működő védelem** — a fenti F1 lelet
kizárólag a shipping test-suite dokumentációs/tisztasági hiányosságára
vonatkozik, nem a termék viselkedésére.

### N1 — NOTE — CTA a teljesített küldetésnél „Start" feliratot mutat letiltva

- **Fájl:** `quest_card.dart:189-207,441`
- A `completed` állapotban a CTA felirata `startLabel` marad (letiltva), nem
  egy dedikált „teljesítve" felirat. A brief egyik acceptance-cellája sem
  írja elő a feliratot expliciten, és a jutalom-krediteltség külön szövegben
  (`_QuestReward`) látszik — nem blokkoló, csak UX-finomítási lehetőség egy
  jövőbeli körben.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ saját futás, `/tmp/review-e08-r20-v2` (2. javítás utáni HEAD) |
| analyze | zöld (0 hiba) | ✅ saját futás |
| `test/features/gamification/presentation/quests_screen_test.dart` | 28/28 zöld | ✅ saját futás, izolált klónban |
| `test/ui/ui_inventory_test.dart` | zöld (61 screen) | ✅ saját futás, izolált klónban |
| architecture | zöld (12 allowlisted deviation, változatlan) | ✅ saját futás |
| secrets | zöld (0 lelet) | ✅ saját futás |
| l10n (paritás + frissesség) | zöld | ✅ saját futás, a fragmentum→aggregátum generálás után |
| CI (teljes suite + property + APK) | 1. dispatch (32530048719) FAILURE — `ui_inventory_test.dart` | ❌ → javítva, 2. dispatch a javítás UTÁN, merge előtt |

## Merge-döntés

Minden lokális gate zöld, scope-audit tiszta, 0 BLOCKER/MAJOR. A CI-dispatch
(`tools/round-ci-plan.py`) és a merge SHA-egyezés a review UTÁNI lépés — a
merge csak azután történik, hogy a kör-branch push-olva van és a tervező
által kijelölt workflow zöld a merge-jelölt SHA-n.
