# ADR 0257 — A tervező ID-jai típusosak, az enum-kódok stabilak

**Státusz:** elfogadva (2026-08-15). Az Epic 7 domain-alapjainak döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md) Ch8 Kör 2.
Épít: [ADR 0255](0255-deterministic-first-practice-planning.md),
[ADR 0256](0256-practice-plan-revisions-immutable-past.md).

## Kontextus

Az Epic 7 domainje hat azonosító-fajtát kezel (plan, day, block, goal,
revision, outcome), és öt enum-családot (státusz, mód, block-kind, severity,
source). Ezek **perzisztálódnak** és a revíziós lánc (ADR 0256) miatt évekig
együtt élnek a felhasználó adataival.

**Mért kiindulás.** A kódbázis mai „ID"-mintája sima `String`:

```dart
// features/audio_analysis/domain/events/event_id.dart
final class EventId {
  static String onset({required String runId, required int sampleIndex}) => …
}
```

Ez validál, de nem véd a **felcseréléstől**: egy `String` planId
akadálytalanul átadható `dayId` helyére. Egy tervezőben, ahol hat ID-fajta
utazik együtt nap/blokk/revízió szinten, ez idő kérdése.

Közös `IdGenerator` absztrakció nincs (`grep` → nulla találat); a projekt
injektált `String Function()`-t használ.

## Döntés

### 1. Minden ID önálló típus

`PlanId`, `DayId`, `BlockId`, `GoalId`, `RevisionId`, `OutcomeId` — külön
típusok (`extension type` vagy value object), nem `typedef`. A felcserélés
**fordítási hiba**.

*Miért nem `typedef`:* az csak név, nulla védelemmel. A SDD „typed ID"
kérése így kimerülne egy kommentben.

### 2. A validáció a konstrukciónál történik

Üres, whitespace-only vagy formátumot sértő érték → `ArgumentError` a
létrehozáskor. Egy létező ID-példány mindig érvényes; a hívóknak nem kell
újra ellenőrizniük.

### 3. Az enum-kódok stabilak, és NEM a Dart `name`

A JSON explicit string kódot hordoz (pl. `'in_progress'`). Tilos a
`values.byName(json)` minta: az a Dart-beli azonosítót teszi
adatformátummá, és egy ártatlan átnevezés perzisztált adatot tör el.

### 4. Ismeretlen enum-kód kontrollált hiba, nem néma default

Ismeretlen kódra **tilos** visszaesni egy default értékre. A néma default
migrációkor csendes adatromlás: a felhasználó terve „megváltozik", és senki
nem tudja, mikor és miért. Ugyanaz a hibaosztály, mint az ADR 0251 §2 üres
referenciája és az ADR 0253 §3 kitalált értéke — **hiányzó bemenet sikeres
eredménynek álcázva.**

### 5. Az ID-generálás injektált függvény, nem új absztrakció

`String Function()` a `analysis_recorder.dart:36` bevált mintájára. Nincs
statikus vagy globális generátor, és a domainben nincs `DateTime.now()` vagy
`Random` — az ADR 0255 determinisztikussága ezen áll vagy bukik.

### 6. A domain nem importál Fluttert

Sem `package:flutter/...`, sem `dart:ui`. Így a tervező egységtesztelhető és
a CI-ban olcsón kapuzható.

## Következmények

- A későbbi körök (Kör 3-tól) ezekre a primitívekre épülnek; egy utólagos
  típus-váltás az egész epicet érintené — ezért dől el itt.
- A perzisztált enum-kódok **szerződéssé** válnak: bővíteni lehet őket, de
  meglévőt átnevezni csak migrációval.
- Az injektált ID-generátor teszi lehetővé, hogy a tervező kimenete
  reprodukálható legyen (ADR 0255 §1).

## Mérce

Az `E07-R02` §6.1 mérce-mátrixa, benne az enum-kód három kötelező cellájával
(ismert / üres / ismeretlen) és a valódi-sértés próbával: az ismeretlen-kód
ágát default értékre cserélve az **A6** cellának pirosnak kell lennie.
