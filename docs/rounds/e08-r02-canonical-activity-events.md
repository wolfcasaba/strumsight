# E08-R02 — Kanonikus tanulási esemény-szerződések

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 2
- **Kör-azonosító:** `E08-R02`
- **Branch:** `<motor>/e08-r02-canonical-activity-events`
- **Előfeltétel:** `E08-R01` merge-elve (baseline)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0300` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd, hogy a `lib/features/gamification/` fa tényleg nem létezik, és olvasd újra a baseline `docs/baseline/epic-08-start.md` esemény-forrás listáját — az esemény-típusok halmaza abból származik. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/domain/activity/learning_activity_event.dart",
  "lib/features/gamification/domain/activity/activity_source.dart",
  "lib/features/gamification/domain/activity/evidence_trust.dart",
  "lib/features/gamification/domain/activity/reward_eligibility.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/domain/activity_event_test.dart",
  "test/core/architecture_dependency_test.dart",
  "docs/rounds/e08-r02-canonical-activity-events.md",
]
gate_tests = [
  "test/features/gamification/domain/activity_event_test.dart",
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

Hozd létre a feature-agnosztikus, **immutable** és **verziózott** tanulási eseményeket:
ezek a gamifikáció EGYETLEN bemenetei. Minden későbbi kör (ledger, outbox, XP, quest)
ezekre épül, ezért a szerződés stabilitása itt dől el.

Ez a kör **nem integrál** feature-öket — csak a szerződést és a public exportot hozza.

## 2. Jelenlegi állapot — mért tények

- `lib/features/gamification/` **nem létezik** — ez a kör hozza létre az első fájljait.
- A gyakorlási eredmények ma feature-specifikus alakban élnek: `lib/features/progress/model/practice_entry.dart` (86 sor), `lib/features/learn/data/lesson_progress_repository.dart`, `lib/features/streak/model/streak_data.dart` (80 sor). **Nincs közös esemény-típus.**
- `test/core/architecture_dependency_test.dart` (467 sor) „allowlisted dependency deviations” alapon tiltja a cross-feature importot — az új feature-gyökeret ide kell felvenni.
- A projekt konvenciója: minden feature EGY `public.dart` barrelen át importálható (lásd `lib/features/*/public.dart`, 21 feature).

## 3. Scope

**Benne van:** a `LearningActivityEvent` sealed hierarchia stabil `eventId` / `occurredAt` / `epochDay`
mezőkkel · a Practice, Song, Analysis, Plan, Tutor és Vision esemény-altípusok ·
konstruktor-szintű validáció (negatív időtartam, tartományon kívüli pontszám, ismeretlen
schema-verzió) · JSON round-trip **explicit type discriminatorral** · `ActivitySource`,
`EvidenceTrust`, `RewardEligibility` enum-szerződések · `public.dart` barrel ·
architektúra-guard bejegyzés.

**NINCS benne (tilos):**

- **Bármely feature integrálása** (`lib/features/practice/**`, `learn/**`, `songs/**` …) — Kör 24–26.
- Ledger, outbox, XP-számítás, eligibility-**logika** — Kör 3–6. Itt csak a típusok vannak.
- Flutter-, Riverpod-, storage- vagy UI-típus importálása a domainbe (§5.2).
- A meglévő `practice_entry.dart` / `streak_data.dart` átírása vagy eltávolítása.
- `docs/adr/**` — az ADR 0300-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/domain/activity/learning_activity_event.dart` | **ÚJ** — a sealed esemény-hierarchia |
| `lib/features/gamification/domain/activity/activity_source.dart` | **ÚJ** — a forrás-feature azonosítója |
| `lib/features/gamification/domain/activity/evidence_trust.dart` | **ÚJ** — a bizonyíték megbízhatósági szintje |
| `lib/features/gamification/domain/activity/reward_eligibility.dart` | **ÚJ** — a jutalmazhatóság szerződése (típus, nem logika) |
| `lib/features/gamification/public.dart` | **ÚJ** — az EGYETLEN belépő a feature-höz |
| `test/features/gamification/domain/activity_event_test.dart` | a §6 cellái |
| `test/core/architecture_dependency_test.dart` | az új feature-gyökér határa |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0300)

### 5.1 Az esemény IMMUTABLE és verziózott — a `schemaVersion` KÖTELEZŐ mező

Minden eseménynek van `schemaVersion` mezője, és ismeretlen verzió **hibát ad**,
nem csendes alapértelmezést. A ledger (Kör 3) az eseményekből származtat jutalmat; egy
némán újraértelmezett régi esemény ott visszamenőleg hamis egyenleget termelne.

**NEM elfogadható gyengítés:** a hiányzó `schemaVersion` „legyen 1” alapértelmezéssel.
Az alapértelmezés pont azt a különbséget tünteti el, amit a mező mérni hivatott.

### 5.2 A domain TISZTA Dart — nincs Flutter, Riverpod, storage vagy UI import

Az esemény-típusok tesztelhetősége és újrafelhasználhatósága ezen áll. Az
architektúra-guard ezt kikényszeríti (A6).

**NEM elfogadható gyengítés:** `package:flutter/foundation.dart` behúzása `@immutable`
vagy `debugPrint` kedvéért. Az immutabilitást `final` mezők és a `const` konstruktor adja.

### 5.3 Stabil `eventId` — a dedup ezen fog állni

Az `eventId` a forrás-feature által adott, **stabil** azonosító: ugyanaz a
gyakorlási eredmény újrafeldolgozva UGYANAZT az azonosítót adja. A Kör 3 idempotencia-indexe
és a Kör 4 outboxa erre épül — véletlenszerű (`Random`, `UUID v4` menet közben generált)
azonosító mellett a dupla jutalom technikailag nem blokkolható.

**NEM elfogadható gyengítés:** az `eventId` generálása a konstruktorban óra- vagy
véletlen-forrásból. Az azonosítót a hívó adja, és a konstruktor validálja, hogy nem üres.

### 5.4 Explicit type discriminator a JSON-ban

A round-trip a `type` mezőn keresztül megy, nem a mezők jelenlétéből következtetve.
A strukturális kitalálás az első olyan altípusnál elromlik, amelynek mezői részhalmazát
adják egy másiknak — és némán rossz típusú eseményt ad vissza.

### 5.5 EGY belépő: `public.dart`

A gamification feature kizárólag a `public.dart`-on át importálható; belső fájl
importja kívülről tilos. A guard ezt méri (A6). Ez a 21 meglévő feature konvenciója.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Minden esemény-altípus immutable (`final` mezők, `const` konstruktor) | `activity_event_test.dart` — a mezők nem írhatók |
| A2 | A `schemaVersion` KÖTELEZŐ; ismeretlen verzió **hibát dob**, nem alapértelmezést ad | `activity_event_test.dart` — mind a hat altípusra |
| A3 | Stabil `type` discriminator: a JSON round-trip mind a hat altípusra azonosságot ad | `activity_event_test.dart` — mátrix, altípusonként egy cella |
| A4 | A konstruktor elutasítja a negatív időtartamot és a tartományon kívüli pontszámot | `activity_event_test.dart` — `throwsArgumentError` |
| A5 | Üres vagy hiányzó `eventId` elutasítva | `activity_event_test.dart` — `throwsArgumentError` |
| A6 | A domain NEM importál Flutter/Riverpod/storage/UI típust, és nem importál más feature-t | `architecture_dependency_test.dart` |
| A7 | A feature EGYETLEN `public.dart`-ból importálható | `architecture_dependency_test.dart` |
| A8 | A hat esemény-altípus (Practice, Song, Analysis, Plan, Tutor, Vision) mind létezik | `activity_event_test.dart` — a discriminator-mátrix hat sora |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A hiányzó `schemaVersion` 1-re alapértelmezik | **A2** (az ismeretlen-verzió cella nem dob) |
| A JSON round-trip a mezők jelenlétéből következtet típusra | **A3** (a részhalmaz-mezőjű altípus rossz típust ad vissza) |
| Az `eventId` a konstruktorban `Random`-ból generálódik | **A5** (üres azonosítót nem utasít el) — és a Kör 3 dedupja megbukna |
| `package:flutter/foundation.dart` importálva `@immutable` miatt | **A6** |
| Belső fájl közvetlenül importálható a barrel megkerülésével | **A7** |
| A negatív időtartam elfogadva, mert „a hívó úgyis validál” | **A4** |

**A küszöb három kötelező cellája** (az időtartam-validáció határa: `Duration.zero`):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `Duration(milliseconds: -1)` — negatív időtartam | `ArgumentError` — **elutasítva** |
| **rajta** (a küszöbön) | `Duration.zero` — pontosan a határon | **ELFOGADVA**: a nulla hosszú esemény legitim (megszakított session); a jutalmazhatóságát a Kör 5 eligibility dönti el, NEM a konstruktor |
| a küszöb **fölött** | `Duration(seconds: 1)` — a határ fölött | **ELFOGADVA** |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a `schemaVersion` ismeretlen-verzió ellenőrzését (engedd alapértelmezni 1-re),
futtasd a gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza. A visszaállítás
utáni zöld futás kimenete a §10-be kerül.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/domain/activity_event_test.dart test/core/architecture_dependency_test.dart
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

1. `activity_source.dart` és `evidence_trust.dart` — a két enum-szerződés.
2. `reward_eligibility.dart` — a jutalmazhatóság TÍPUSA (a döntési logika a Kör 5).
3. `learning_activity_event.dart` — a sealed bázis (`eventId`, `occurredAt`, `epochDay`, `schemaVersion`) + hat altípus.
4. Konstruktor-validáció: üres `eventId`, negatív időtartam, tartományon kívüli pontszám.
5. JSON round-trip explicit `type` discriminatorral, mind a hat altípusra.
6. `public.dart` — az egyetlen belépő.
7. Az architektúra-guard bejegyzése az új feature-gyökérre.
8. A valódi-sértés próba, §10-be dokumentálva.
9. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az `eventId` menet közbeni generálása.** Kényelmes, és három körrel később a dupla jutalom válik technikailag blokkolhatatlanná (A5). Ez a kör legfontosabb invariánsa.
- **A `flutter/foundation.dart` behúzása.** Egyetlen `@immutable` annotáció kedvéért, és ezzel a domain tesztelhetősége és újrafelhasználhatósága elvész (A6).
- **A schema-verzió „pragmatikus” alapértelmezése.** A régi eseményeket némán újraértelmezi, és a ledger egyenlege visszamenőleg hamis lesz (A2).
- **A hat altípus egyben.** Csábító előbb kettőt megcsinálni és a többit „később” — a `public.dart` barrel viszont a Kör 3-tól kezdve fix felület, és az utólagos bővítés minden fogyasztót érint.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
