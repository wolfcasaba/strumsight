# E08-R02 — Review

Brief: docs/rounds/e08-r02-canonical-activity-events.md
Diff: `git diff af86bc59...95ddec13` (pre-flight commit → implementer's final commit)
Reviewer: Claude (Sonnet 5) · Dátum: 2026-08-19
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 3

Tiszta, jól határolt implementáció: hat immutable esemény-altípus, hívó-adta
`eventId`, kötelező `schemaVersion` valódi elutasítással, explicit
`type`-discriminator JSON round-trip, nulla cross-feature import. Mindkét
brief-kötelező valódi-sértés próbát (§6.1 schemaVersion, §0.0.2
architektúra-guard) a review **saját kézzel, izolált `/tmp` klónban**
megismételte — mindkettő a várt cellát fogta pirosra, majd tisztán
visszaállt zöldre.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Minden altípus immutable (`final` mező, `const` konstruktor) | ✅ | `learning_activity_event.dart` — minden mező `final`, minden `._` privát konstruktor `const`; forráskód-ellenőrzéssel igazolva (lásd NOTE-1) |
| A2 | `schemaVersion` kötelező; ismeretlen érték hibát dob | ✅ | Saját mutációs próba: a `!= learningActivityEventSchemaVersion` ág ideiglenesen eltávolítva → `activity_event_test.dart` "A2: every event kind rejects an unknown schema version" pirosra váltott (`PracticeActivityEvent must not reinterpret version 2`), visszaállítás után 13/13 zöld |
| A3 | Explicit `type` discriminator, mind a hat altípusra | ✅ | `activity_event_test.dart:29-37` — a `type` mezőt kézzel `vision`-re írva a decode `VisionActivityEvent`-et ad vissza `practice`-forrású mezőkkel, bizonyítva hogy a döntés a `type`-on megy, nem mező-jelenléten |
| A4 | Negatív időtartam és tartományon kívüli pontszám elutasítva | ✅ | `activity_event_test.dart:71-106` — küszöb-hármas (`-1ms` elutasít, `Duration.zero` elfogad, `+1s` elfogad) mind a hat altípusra; `score` NaN/-0.001/1.001 elutasítva, 0/1 határ elfogadva |
| A5 | Üres/hiányzó `eventId` elutasítva | ✅ | `activity_event_test.dart:108-113` — `''` és `'   '` mind a hat altípusra `throwsArgumentError` |
| A6 | Domain nem importál Flutter/Riverpod/storage/UI-t, más feature-t | ✅ | Saját mutációs próba: `package:flutter/foundation.dart` beszúrva `activity_source.dart`-ba → az új "gamification domain stays framework-free" teszt pontos hibaüzenettel pirosra váltott, visszaállítás után 19/19 zöld. Forráskód-ellenőrzés: a 4 domain fájl egyike sem importál semmit a saját feature-én kívülről |
| A7 | Egyetlen `public.dart` belépő | ✅ | `checkArchitecture()` generikusan (nem hardcode-olt lista) fedi az összes `lib/features/*`-ot; ez a kör 0 cross-feature importot vezet be, az `architectureAllowlist` változatlan — `tool/check_architecture.dart` futása: "Architecture dependencies OK (12 allowlisted deviation(s))" |
| A8 | Mind a hat altípus létezik | ✅ | `PracticeActivityEvent`/`SongActivityEvent`/`AnalysisActivityEvent`/`PlanActivityEvent`/`TutorActivityEvent`/`VisionActivityEvent`, mindegyik a round-trip mátrixban |

## Scope-audit

`tools/scope-audit.py --repo /tmp/review-e08-r02 --brief docs/rounds/e08-r02-canonical-activity-events.md --base af86bc59`:

```
Legacy scope audit OK (af86bc59..95ddec135c74, 8 changed path(s), 0 generated/ignored)
```

Engedélyezett fájlokon kívüli változás: **nincs**. A 8 megváltozott útvonal
pontosan a brief `allowed_paths` 7 tétele + maga a brief (a §10 handoff
kitöltése).

## Megállapítások

### N1 — NOTE — Az A1 „const konstruktor" bizonyítéka forráskód-szintű, nem futásidejű teszt

- **Fájl:** `test/features/gamification/domain/activity_event_test.dart`
- **Megfigyelés:** a brief §6 A1 sora a bizonyítékot `activity_event_test.dart`
  — "a mezők nem írhatók" — néven nevezi meg, de a fájlban nincs erre
  dedikált assert. Dart-ban ez nem hiba: a `final` mező írásvédettsége
  fordítási idejű garancia (egy `event.eventId = 'x'` sor egyszerűen nem
  fordulna), egy futásidejű teszt ezt nem tudja pozitívan bizonyítani.
  A tényleges bizonyíték forráskód-ellenőrzéssel adott: minden `._` privát
  konstruktor `const` (`learning_activity_event.dart:122,180,238,296,354,412`),
  minden mező `final`.
- **Hatás:** nincs — a tulajdonság valós, csak a brief bizonyíték-oszlopa
  pontatlan.
- **Javasolt (nem kötelező):** egy jövőbeli brief A1-hez inkább „forráskód-
  ellenőrzés" bizonyítékot írjon elő explicit teszt helyett, hogy a mérce és
  a valós ellenőrzési mód egyezzen.

### N2 — NOTE — Az enum-kódok wire-formátuma a Dart `name`-en megy, nem explicit perzisztált kódon

- **Fájl:** `lib/features/gamification/domain/activity/learning_activity_event.dart:37-38,555-571`
- **Megfigyelés:** `toJson()` a `source.name`/`trust.name`-et írja a JSON-ba,
  a dekódolás (`_activitySourceFromName`/`_evidenceTrustFromName`) pedig
  visszakeresi a Dart-beli nevet. Ez ugyanaz a mintaosztály, amit az
  [ADR 0257](../adr/0257-planner-typed-ids-and-stable-enum-codes.md) §3
  kifejezetten tilt Epic 7 enumjaira („Tilos a `values.byName(json)` minta:
  az a Dart-beli azonosítót teszi adatformátummá, és egy ártatlan átnevezés
  perzisztált adatot tör el").
- **Hatás ma:** NULLA — a gamification még semmit nem perzisztál (a Kör 3
  ledger hozza az első írást), tehát nincs élő adat, amit egy átnevezés
  eltörhetne. A kockázatot ma jelentősen csökkenti, hogy
  `activity_event_test.dart:117-138` PONTOS, kipinnelt listát vár mindkét
  enumra — egy átnevezés ezt a tesztet PIROSRA vinné, tehát nem csendes.
  A különbség egy explicit kód-térképhez képest: a fejlesztő a piros tesztet
  a LISTA frissítésével is zöldre viheti, ezzel véletlenül megváltoztatva a
  már perzisztált (jövőbeli) adatok wire-alakját — az explicit kód-térkép ezt
  eleve kizárná (a régi kód megmaradna, csak új kód adódna hozzá).
- **Javasolt (nem blokkoló, kör E08-R02-n belül olcsón javítható lenne, de
  nem kötelező most):** mielőtt a Kör 3 ledger éles adatot ír ezekkel a
  kódokkal, fontolja meg egy explicit `static const Map<ActivitySource, String>`
  bevezetését, az ADR 0257 mintáját követve.

### N3 — NOTE — `score`/`duration` minden altípuson kötelező, univerzális mező

- **Fájl:** `lib/features/gamification/domain/activity/learning_activity_event.dart:9-18`
- **Megfigyelés:** a `docs/sdd/09-epic-08-gamification.md` §8.1 vázlata a
  bázisosztályon NEM ad `duration`/`score` mezőt (csak `eventId`/
  `occurredAt`/`localEpochDay`/`source`/`trust`/`schemaVersion`); ez az
  implementáció mind a hat altípuson kötelezővé teszi mindkettőt. A brief
  szövege ezt nem tiltja (a §6 A4 sora csak annyit ír elő, hogy A negatív
  időtartam/tartományon kívüli pontszám el legyen utasítva, altípus-
  bontás nélkül), úgyhogy ez NEM acceptance-sértés — de egy jövőbeli, nem
  folytonos pontszámú esemény (pl. egy bináris „DailyPlanCompleted") a Kör
  24-26 integrációkor mesterséges `score` értéket kényszerülhet adni.
- **Hatás ma:** nincs — ez a kör nem integrál egyetlen feature-t sem.
- **Javasolt:** a Kör 24-26 brief-je (vagy egy korábbi tervező-kör) explicit
  döntse el, marad-e univerzális `score`, vagy altípusonként nullázható lesz.

## Gate-bizonyíték ellenőrzése

Mind a hét lépést **saját kézzel, izolált `/tmp/review-e08-r02` klónban**
(GitHub origin-ról klónozva, ADR-hivatkozás: [[L331]]) futtattam újra —
az implementer önjelentése egyik lépésnél sem volt az egyetlen forrás.

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | 0 változás (1679 fájl) | ✅ |
| analyze | „No issues found” (19.8s) | ✅ |
| test activity_event_test.dart | 13/13 | ✅ (+ saját mutációs próba) |
| test architecture_dependency_test.dart | 19/19 | ✅ (+ saját mutációs próba) |
| architecture (`tool/check_architecture.dart`) | OK, 12 allowlisted deviation | ✅ |
| secrets | OK, 2969 fájl, 0 lelet | ✅ |
| l10n parity | OK, en→hu, 1405 üzenet | ✅ |
| CI (teljes suite + property + APK) | — | ⏳ dispatch ez után következik |

## Process-megjegyzés (nem code-review lelet)

A `.codex-round-status` `done` jelzése `head=95ddec13`-at állított, de az
origin branch-tip a jelzéskor még `af86bc59` (a pre-flight commit) volt — az
implementer commitolt, de nem pusholt. Az orchesztrátor pusholta a commitot a
review ELŐTT (`git push origin codex/e08-r02-canonical-activity-events:codex/e08-r02-canonical-activity-events`,
fast-forward, ütközés nélkül). Nem code-defekt, hanem a legacy Codex-motor
dispatch-szerződésének egy alulspecifikált pontja — a záró rituáléknál
`docs/LESSONS.md`-be kerül.

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR →
merge. A helyi gate (format/analyze/architecture/secrets/l10n/2 célzott
teszt) mind zöld, 0 BLOCKER/MAJOR/MINOR. **A CI-dispatch (teljes suite +
property + APK) még hátravan** — a merge csak azután, ha az is zöld
(exact-SHA a merge pillanatában).
