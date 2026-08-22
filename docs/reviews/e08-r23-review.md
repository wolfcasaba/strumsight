# E08-R23 — Review

Brief: docs/rounds/e08-r23-gamification-hub-and-level-ui.md
Diff: `git diff 269f0532...minimax/e08-r23-gamification-hub-and-level-ui`
Reviewer: Claude Sonnet 5 (`--effort high`) · Dátum: 2026-08-22
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 1 · MAJOR: 0 · MINOR: 1 · NOTE: 1

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | XP-sáv és készség-mutató eltérő vizuális kezelés + kimondott felirat | ❌ | **F1 BLOCKER** — a `LevelBadge` VIZUÁLISAN valóban eltérő (kör alakú medál vs sáv), de a mögötte álló ADATFORRÁS ugyanaz, amit el kellett volna választani: `profile.currentLevel` (`GamificationProfile` `lib/features/gamification/domain/profile/gamification_profile.dart:31`) pusztán `totalXp`-ből számolt `LevelDefinition` (`level_curve.dart` — "The single source of truth for monotonically increasing XP levels"), miközben az UI-felirat kimondottan "Measured skill, not experience points"-ot állít (`gamificationHubLevelBadgeSemantics`, `lib/l10n/features/gamification_en.arb`). Ez maga a hazug állítás, amit az ADR 0289 tilt — nem a vizuális stílus, hanem a TARTALOM sérti a legfontosabb invariánst. |
| A2 | "Hogyan működik?" magyarázat elérhető, R06 komponensek | ✅ | `level_detail_screen_test.dart` / `gamification_hub_screen_test.dart` A2 csoport, `buildR06XpComponents()` öt komponens (base/duration/quality/improvement/…) |
| A3 | Nincs villogás, nincs visszaszámláló | ✅ | A3 teszt-csoport — `Timer`/`Ticker` widget-keresés, "hurry"/"urgent"/"sürg" szöveg-tiltás, mind zöld |
| A4 | Offline, nincs hálózati hívás | ✅ | A4 teszt — statikus forrás-szkennelés a négy ÚJ fájlon `http`/`Dio`/`Provider`/`Repository`/stb. ellen, mind zöld |
| A5 | Üres állapot legacy és új felhasználónak | ✅ | A5 csoport — `isLegacyEmpty` és `totalXp==0` ágak külön tesztelve |
| A6 | Postaláda-jelző megjelenik, ha van új elem | ✅ | A6 csoport — `inboxUnseenCount>0` eset + szemantika |
| A7 | `lib/features/progress/**` érintetlen | ✅ | `git diff --stat 269f0532..HEAD` — a `progress/` könyvtár NEM szerepel a 12 megváltozott fájl között; A7 teszt is fut |
| A8 | 200%-os szövegskálán nincs levágás | ✅ | A8 csoport — `scale∈{1,2,3}` × két képernyőméret, `tester.takeException()` null, `ListView` görgethető marad mindkét screenen |

## Scope-audit

`tools/scope-audit.py --repo /tmp/review-e08-r23 --brief docs/rounds/e08-r23-gamification-hub-and-level-ui.md --base 269f0532` →
**`Legacy scope audit OK (269f0532f027..cd5c970decd0, 12 changed path(s), 0 generated/ignored)`** — engedélyezett fájlokon kívüli változás nincs.

## Gate-bizonyíték (saját, izolált `/tmp` klón)

```
git clone --branch minimax/e08-r23-gamification-hub-and-level-ui /home/ubuntu/music-theory /tmp/review-e08-r23
bash tools/prepare-flutter-generated.sh
tools/round-gate.sh test/features/gamification/presentation/gamification_hub_screen_test.dart test/ui/ui_inventory_test.dart
```

`MINDEN GATE ZÖLD` — format, analyze, mindkét test-útvonal, architecture,
secrets, l10n (parity OK, en→hu, 1644 message). A gate-futás a `cd5c970d`
commitra (a §10 handoff-lezáró commit) mutat, ami a review-pillanatban HEAD.

CI: `full-gate.yml` run dispatch-elve a `minimax/e08-r23-gamification-hub-and-level-ui`
branchre (`headSha=cd5c970d`), a review-vel párhuzamosan fut.

## Megállapítások

### F1 — BLOCKER — a "készség-mutató" (LevelBadge) valójában az XP-szintet mutatja, hazug "not experience points" felirattal

- **Fájl:** `lib/features/gamification/presentation/widgets/level_badge.dart:6-12` (doc-comment: "Visual surface for the SKILL-MASTERY indicator"), a tényleges adat: `lib/features/gamification/domain/profile/gamification_profile.dart:31` (`currentLevel => progress.currentLevel`) ← `lib/features/gamification/domain/levels/level_curve.dart:63,68,70` (`LevelCurve.definitions[currentIndex]`, kizárólag `totalXp` alapján, "The single source of truth for monotonically increasing XP levels").
- **Probléma:** A Hub "Skill mastery" szekciója (`gamification_hub_screen.dart:103-111`, `l10n.gamificationHubSkillSectionTitle` = "Skill mastery", body = "Skill mastery is unlocked by measured evidence — never by experience points alone.") a `LevelBadge`-et jeleníti meg, aminek egyedüli bemenete `profile.currentLevel` — egy `LevelDefinition`, ami KIZÁRÓLAG `totalXp` küszöbökből származik (nincs mastery-bemenete, nincs `MasteryEvaluator`-hívás, nincs evidence-kapu). Eközben a widget felirata explicit **"Skill mastery — Level {level}"**, a szemantikája **"Skill mastery level {level}. {title}. Measured skill, not experience points."**, a level-detail képernyőn pedig **"Skill mastery is locked in at this level."** és **"skill mastery only crosses when measured evidence supports it"** szövegek állnak — miközben a level-detail UGYANEZEN a képernyőn a "Hogyan működik az XP?" szakasz (`buildR06XpComponents`) pontosan azt magyarázza el, hogy a szint az XP öt komponenséből adódik. A két szöveg EGYMÁSNAK ELLENTMOND ugyanazon a képernyőn: az egyik azt állítja, a szint bizonyítékból ered, a másik (a valós kód) azt bizonyítja, hogy XP-ből.
- **A brief SAJÁT elnevezése is ezt jelzi:** a §4 táblázat a fájlt **"a szint-jelvény"**-ként (level badge, NEM skill badge) sorolja fel — az implementer a WIDGET-et helyesen "level"-nek nevezte el (`LevelBadge`, `level-badge` kulcs), de a FELIRATOT "skill mastery"-re cserélte, ami sem a brief elnevezésével, sem a ténylegesen mért adattal nem egyezik.
- **A meglévő, valódi mastery-jelző MÁR OTT VAN a képernyőn** (`gamification-hub-mastery-tile`, `masteryUnlockedCount`, a `gamificationHubMasteryTitle`="Skill mastery milestones" felirattal) — ez a valós, R21-ből örökölt, evidence-gated mérőszám. A Hub-on emiatt **KÉT különböző dolog állítja magáról, hogy "skill mastery"**: a valódi (lent, a "mastery milestones" csempe) és a hamis (fent, a `LevelBadge`). Ez pontosan az a felhasználó-szembeni összemosás, amit az ADR 0289 és a brief §5.1 "NEM elfogadható gyengítés" sora tilt — csak a §6.1 mérce-mátrix egyetlen, dokumentált mutációja ("két azonos stílusú sáv") nem fedi le ezt a variánst, mert itt a stílus KÜLÖNBÖZIK, csak az ADAT és a FELIRAT hazudik.
- **Hatás:** Egy felhasználó (és minden accessibility/screen-reader felhasználó, mivel ez a szemantikai címke szó szerinti szövege) azt az üzenetet kapja, hogy a szintje bizonyított készség-teljesítmény, miközben az valójában tisztán az eltöltött/mért XP függvénye — ez a termék éppen azt az ígéretet szegi meg, amire az egész kör épült (ADR 0289: "az XP a részvételt méri, az elsajátítottság mért teljesítményt", "a legolcsóbb megvalósítás az XP... csakhogy... ha az elsajátítottság XP-ből származik, a felület pontosan azt hazudja, amit a felhasználó a legjobban szeretne hinni").
- **Kötelező javítás:** a `LevelBadge` felirata/szemantikája kerüljön vissza a brief saját elnevezéséhez illő, ŐSZINTE "level/XP-szint" framing-re (pl. "Level {level}" / "Reached from experience points"), a "Skill mastery"/"Measured skill, not experience points" szöveg TÖRLENDŐ innen — a valódi skill-mastery kommunikáció maradjon a már meglévő, evidence-gated `masteryUnlockedCount` csempén és a hozzá tartozó feliratokon. A `gamificationHubSkillSectionTitle`/`Body` szekció-fejléc (ami jelenleg a `LevelBadge` fölött ül) vagy távolítandó, vagy át kell címkézni "Level" szekcióra — a "Skill mastery" cím csak a mastery-csempéhez tartozhat.
- **Ellenőrzés:** egy ÚJ teszt-eset, ami az ARB-string TARTALMÁT (nem csak a jelenlétét) ellenőrzi — pl. `expect(l10n.gamificationHubLevelBadgeLabel(1), isNot(contains('skill', ignoreCase: true)))` vagy ezzel egyenértékű, plusz egy dokumentált valódi-sértés próba, ami a JELENLEGI hibás szöveggel mutatja, hogy egy ilyen teszt hiányában a build zöld marad (a mostani A1 teszt-csoport ezt nem fogja meg, mert csak típust/kulcsot/a label LÉTEZÉSÉT nézi, a szöveg tartalmát nem).
- **Státusz:** OPEN

### F2 — MINOR — a §6.1 "valódi-sértés próba" csak a widget-TÍPUS szintjén mér, nem a tartalom szintjén

- **Fájl:** `test/features/gamification/presentation/gamification_hub_screen_test.dart:193-214`
- **Probléma:** a brief §6.1 kötelező próbája ("add az XP-sávnak és a készség-mutatónak ugyanazt a stílust, fusd a gate-et, az A1-nek pirosra kell váltania") a §10 handoff szerint kézzel (hand-execution) lett elvégezve, de a FÁN MARADÓ automatizált teszt csak azt méri, hogy a két widget `runtimeType`-ja különbözik és egy `findRuntimeCardinality` heurisztika eltér — ez egy jövőbeli refaktornál (pl. mindkettő egy közös `_MetricCard`-dá alakítva) nem feltétlenül venné észre, ha a KÉT ADATFORRÁS ismét összemosódna, csak azt, ha a Dart-osztályuk azonossá válna. Az F1 mutatja, hogy a valódi kockázat nem a widget-osztály, hanem az adatforrás/felirat szintjén jelentkezik.
- **Hatás:** a regressziós védelem szűkebb, mint amit a brief §6.1 szándéka sugall.
- **Kötelező javítás (F1 javításával egy körben, ha belefér):** a próbateszt egészüljön ki egy tartalom-alapú asszertummal (lásd F1 "Ellenőrzés").
- **Ellenőrzés:** az új teszt fut és PIROS-t ad, ha valaki visszaírja a "skill mastery" szöveget a `LevelBadge`-be.
- **Státusz:** OPEN (F1 javításával egy körben zárható)

### F3 — NOTE — a level-detail "Current level" body szövege is a hibás framing-et ismétli

- **Fájl:** `lib/l10n/features/gamification_en.arb` (`gamificationLevelDetailCurrentBody` = "Skill mastery is locked in at this level. The level only ever rises."), `gamificationLevelDetailNextBody` = "Experience points move the slider; skill mastery only crosses when measured evidence supports it."
- **Megfigyelés:** F1 javítása után ez a két string is felülvizsgálandó — jelenleg ugyanazt a hamis "a szint bizonyítékból ered" állítást ismétli a level-detail képernyőn, a magyar (`gamification_hu.arb`) párjával együtt. Nem külön BLOCKER, mert a gyökérok ugyanaz, mint F1-nél, és egy javítás mindkettőt lezárja.
- **Státusz:** OPEN (F1 javítás részeként várt)

## Architektúra + termékhatárok

`test/core/architecture_dependency_test.dart` a `test 4/4` gate-lépésen belül fut (l10n és architecture lépések zöldek) — a gamification `application/`/`domain/` réteg framework-független marad, az ÚJ fájlok mind `presentation/` alá kerültek. A4 teszt (fenti táblázat) statikusan igazolja, hogy a négy ÚJ presentation-fájl nem importál hálózatot/tárolást/Riverpod-ot. `public.dart` export-only bővítés (4 sor). Nincs plugin-, mic- vagy secret-érintés.

## Következő lépés

Javító kör szükséges (F1 BLOCKER) — ugyanaz a motor (`minimax`), a fenti F1/F2/F3 leletlistával a promptban. A CI-dispatch (`full-gate.yml`, `cd5c970d` SHA-n) formailag zöld lehet, de az F1 tartalmi hiba miatt a merge ETTŐL FÜGGETLENÜL tilos — a review-verdikt (CHANGES REQUIRED) a döntő, nem a gate.
