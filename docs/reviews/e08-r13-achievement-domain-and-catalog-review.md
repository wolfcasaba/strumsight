# E08-R13 — Review

Brief: `docs/rounds/e08-r13-achievement-domain-and-catalog.md`  
Diff: `731f52c5...c3812906`  
Reviewer: Codex / `gpt-5.6-sol` · Dátum: 2026-08-21  
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 0 · MAJOR: 2 · MINOR: 0 · NOTE: 1

Az implementáció scope-ja tiszta, a célzott round-gate 6/6 zöld, és a
tier-ciklus őre valódi production-mutatással bizonyítottan érzékeny. Két
domain-integritási rés azonban zöld maradt a szállított tesztek mellett: egy
korábban kiadott ID azonos elemszámú katalóguscserével eltűnhet, továbbá a
nem véges objective/progress számok érvényesnek látszanak. Mindkettő javító
kört igényel.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | 20–30 stabil, explicit ID | ✅ | 22 elem, exact ID-lista; 19/20/21 és 29/30/31 cellák |
| A2 | Típusos objective; unknown fail-closed | ⚠️ | unknown sentinel elutasítva, de nem véges támogatott threshold elfogadva (F2) |
| A3 | Tier-gráf körmentes | ✅ | A→B→A teszt; `_containsTierCycle` hívásának ideiglenes `false` rontása pirosra vitte A3-at |
| A4 | Minden kulcs mindkét locale-ban | ✅ | 1503 kulcsos l10n parity + A4 |
| A5 | Nincs beégetett emberi szöveg | ✅ | lowerCamel key-őr + locale-membership |
| A6 | Deprecated achievement megmarad | ❌ | a shipping deprecated elem megvan, de az előző ID eltávolítását a validátor nem tiltja (F1) |
| A7 | Elemszám-változás verzióemelést igényel | ✅ | 20→21 azonos/növelt verzió cellák |
| A8 | Rövid, felolvasható kulcs minden definíción | ✅ | title/description/semantics kulcs mindkét locale-ban |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e08-r13-a2CFaI --brief
docs/rounds/e08-r13-achievement-domain-and-catalog.md --base 731f52c5...`:

```text
Legacy scope audit OK (731f52c50a04..c3812906fc0a, 11 changed path(s), 0 generated/ignored)
```

Engedélyezett fájlokon kívüli implementer-változás: nincs.

## Megállapítások

### F1 — MAJOR — Korábban kiadott achievement ID azonos elemszám mellett eltűnhet

- **Fájl:** `lib/features/gamification/domain/achievements/achievement_catalog.dart:98`
- **Probléma:** a `previousCatalog` összevetése csak az elemszám változását
  figyeli. Egy régi ID új ID-ra cserélése azonos elemszám és akár növelt
  `contentVersion` mellett is valid. Ez megsérti az ADR 0374 D6 és a brief
  §5.5 additív deprecation-szerződését.
- **Hatás:** későbbi content-frissítés eltüntethet egy már megszerzett
  achievement definícióját; a profil/ledger hivatkozása árva lesz.
- **Bizonyíték:** reviewer eldobható cella: előző katalógus 20
  `test_achievement_*` ID-val, új katalógus azonos 20-as mérettel és
  `replacement_achievement`-tel. Elvárt invalid, tényleges `isValid=true`.
- **Kötelező javítás:** a validáció külön stabil kóddal utasítson el minden,
  `previousCatalog`-ban létező, de az újban hiányzó ID-t, verzióemeléstől és
  elemszámtól függetlenül. A kivezetett elem csak `deprecated` jelöléssel
  maradhat bent. Add hozzá a reprodukáló azonos-méretű replacement cellát.
- **Ellenőrzés:** a fenti cella piros a régi kódon, zöld a javításon; a
  shipping `legacy_first_step` teszt maradjon zöld.
- **Státusz:** OPEN

### F2 — MAJOR — Nem véges számok és release-ben kikapcsolt assertok gyengítik a domain-validációt

- **Fájl:** `lib/features/gamification/domain/achievements/achievement_definition.dart:61`,
  `lib/features/gamification/domain/achievements/achievement_progress.dart:24`
- **Probléma:** a count/distinct cél és threshold alsó határa csak `assert`,
  ami release-ben nincs; a threshold nem követel véges számot, a progress
  pedig a `value < 0` ellenőrzéssel elfogadja a `NaN`-t. `advanceTo` ugyanezen
  okból a monotonitást sem tudja NaN mellett rendezni.
- **Hatás:** egy hibás vagy későbbi dekódolt katalógus soha el nem érhető vagy
  azonnal teljesülő objective-et, illetve rendezhetetlen haladást hozhat létre;
  a fail-closed és monoton domain-szerződés release-ben eltűnik.
- **Bizonyíték:** reviewer eldobható cellák: `minimum: double.infinity`
  katalógusvalidációja ténylegesen `isValid=true`; `AchievementProgress(value:
  double.nan)` nem dob, hanem objektumot ad vissza.
- **Kötelező javítás:** minden objective/progress numerikus invariant legyen
  futásidejű `ArgumentError` vagy validációs kód, ne csak `assert`. A threshold
  és progress érték legyen véges és nem negatív; count/distinct target pozitív;
  `advanceTo` véges és nem csökkenő értéket fogadjon. Adj célzott cellákat
  nulla/negatív/non-finite bemenetre és NaN-es advance-re.
- **Ellenőrzés:** a két reviewer-cella és az új határmátrix zöld; release-ben
  kikapcsolható assert nem az egyetlen őr.
- **Státusz:** OPEN

### N1 — NOTE — A completion timestamp stabilitását az R14-nek külön kell pinnelnie

- **Fájl:** `lib/features/gamification/domain/achievements/achievement_progress.dart:58`
- **Megfigyelés:** az `advanceTo` ma új, nem-null `completedAt` értékkel át
  tudja írni a korábbit. Az E08-R14 brief A3-ja ezt a kiváltó esemény stabil
  időbélyegéhez köti; az R14 pre-flightja ellenőrizze, hogy ezt az evaluator
  vagy a progress value object őrzi-e.
- **Státusz:** OPEN, nem blokkolja önmagában az R13-at.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | 1732 fájl, 0 változás | ✅ izolált klón |
| analyze | No issues found | ✅ izolált klón |
| célzott teszt | 16/16 | ✅ izolált klón |
| architecture | 12 allowlisted deviation, OK | ✅ |
| secrets | 3104 fájl, 0 lelet | ✅ |
| l10n | aggregate freshness + parity, 1503 üzenet | ✅ |
| A3 mutáció | production cycle-őr kikapcsolva → A3 piros; restore → zöld | ✅ |
| reviewer adversarial | ID-removal, infinity threshold, NaN progress | ❌ 3/3 reprodukált piros |
| CI | még nem dispatch-elve | ⏳ javítás után |

## Merge-döntés

Két MAJOR nyitva, ezért merge tilos. Ugyanazzal a Terra motorral javítókör,
majd friss izolált re-review és teljes exact-SHA CI szükséges.
