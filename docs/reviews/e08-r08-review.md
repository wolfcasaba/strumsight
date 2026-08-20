# E08-R08 — Review

Brief: `docs/rounds/e08-r08-gamification-repository-and-storage-schema.md`
Diff: `git diff fa34423d..3c67f44f` (pre-flight commit → implementer HEAD)
Reviewer: Claude (Sonnet 5) · Dátum: 2026-08-20
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 1

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Pillanatkép-csere atomikus, megszakítás után a korábbi ép profil marad | ✅ | `gamification_repository_test.dart:16-35` (interrupting store, `writeLog` nem tartalmaz `remove:`); implementer §10 valódi-sértés próba (`_store.remove` beszúrva a write elé → write-log `remove:ss.gamification.profile_snapshot`); saját olvasás: `local_gamification_repository.dart:103-112` egyetlen `_profileDocument.write()` hívás |
| A2 | Sérült adat nem íródik felül, explicit „sérült" jelzés | ✅ (single-doksik) / ⚠️ (lista) | `gamification_repository_test.dart:37-80` (corrupt read + write-after-corrupt quarantines the old bytes) — de lásd **F1**, a postaláda (lista-alakú dokumentum) NEM ugyanezt a garanciát kapja |
| A3 | Minden perzisztált modell verziózott, ismeretlen verzió explicit hibát ad | ✅ | `gamification_repository_test.dart:99-133` (mind a 4 típus `throwsFormatException` jövőbeli verzióra) + `:135-168` (round-trip) |
| A4 | Repository interfész nem szivárogtat tárolási típust, fake-elhető | ✅ | `gamification_repository_test.dart:172-183` (forrás-szöveg nem tartalmaz `JsonDocumentStore`/`KeyValueStore`-t) + `_FakeGamificationRepository` (:290-339) sima Dart osztály |
| A5 | Application/presentation NEM importál `SharedPreferences`-t | ✅ | `architecture_dependency_test.dart` új csoport (694/701. sor környéki `_gamificationImportUriMarkers` újrafelhasználásával); gate `[4] test test/core/architecture_dependency_test.dart` zöld, benne a 2 új teszt |
| A6 | Figyelő adatfolyam friss értéket ad változás után | ✅ (happy path) | `gamification_repository_test.dart:185-198`. Lásd **N1** — a hibás írás esetét nem fedi |
| A7 | Megőrzési/méretkorlát dokumentált és érvényesül, a küszöb inkluzív | ✅ | `gamification_repository_test.dart:201-225` — pontosan a brief §6.1 három cellája (alatt/rajta/fölött), a megmaradó elemek sorrendje is ellenőrizve |
| A8 | Gamifikációs kulcsok egy helyen | ✅ | `gamification_storage_schema.dart:20-38` (`GamificationStorageKeys.all`) + `gamification_repository_test.dart:227-242` |

## Scope-audit

```
python3 tools/scope-audit.py --repo /tmp/review-e08-r08 \
  --brief docs/rounds/e08-r08-gamification-repository-and-storage-schema.md \
  --base fa34423d
→ Legacy scope audit OK (fa34423db776..3c67f44f3ef4, 7 changed path(s), 0 generated/ignored)
```

Engedélyezett fájlokon kívüli változás: **nincs**. A 7 megváltozott útvonal
pontosan a brief §4 listája (3 új `data/` fájl, `public.dart` 3 export-sor,
2 teszt fájl, a brief maga a §10 handoff-fal).

## Megállapítások

### F1 — MAJOR — `readInbox()` egyetlen sérült postaláda-elemre az EGÉSZ listát eldobja, ellentétben az ADR 0054 garanciájával

- **Fájl:** `lib/features/gamification/data/local_gamification_repository.dart:127-146`
- **Probléma:** `readInbox()` egy SAJÁT, a `JsonCollectionStore` elé illesztett
  előzetes validáló ciklust futtat (`for (final rawItem in body) {
  GamificationInboxItem.fromJson(...); }`), és ha ELŐZETES dekódolás
  BÁRMELYIK elemen dob, a teljes metódus `GamificationRead.corrupt()`-ot ad
  vissza — a `_inboxStore.read()` (a ténylegesen felhasznált
  `JsonCollectionStore<GamificationInboxItem>`) SOSEM fut le ebben az ágban.
  Ez pontosan az ELLENKEZŐJE annak, amit a saját, ugyanebben a fájlban élő
  dartdoc-kommentje ígér ("A megszakadt írás után a KORÁBBI, ép pillanatkép
  marad érvényben" szellemében), és amit a projekt megosztott
  `JsonCollectionStore` infrastruktúrája MÁR biztosít — [ADR 0054](../adr/0054-versioned-user-content-documents.md)
  Következmények szakasza szó szerint: *"Corruption now costs one record,
  not one feature's entire content."* A pre-flight (§0.0, ADR 0344 Döntés 6)
  kifejezetten a `JsonCollectionStore` ÚJRAFELHASZNÁLÁSÁT javasolta PONTOSAN
  emiatt a garancia miatt — ez a redundáns előzetes hurok semlegesíti azt.
- **Hatás:** egyetlen, bármilyen okból (jövőbeli séma-babráció, ritka
  részleges platform-írás, kézi piszkálás) hibásan dekódolható postaláda-
  bejegyzés a TELJES, akár 49 érvényes bejegyzést tartalmazó jutalom-
  postaládát „sérültként" jelenti a hívónak — a bájtok a lemezen épek
  maradnak (nincs felülírás), de az API szintjén minden érvényes, még nem
  megtekintett jutalom-értesítés elérhetetlenné válik, amíg valaki nem
  javítja a kódot. Egy jövőbeli inbox-UI ezt üres/hiba állapotként mutatná a
  usernek, holott csak egyetlen bejegyzés hibás.
- **Mérve (eldobható próbateszt, review-só, NEM commitolva):**
  `/tmp/review-e08-r08/test/features/gamification/data/_probe_inbox_partial_corruption_test.dart` —
  3 elemű nyers envelope-ot írtam közvetlenül a store-ba (2 érvényes +
  1 hiányzó `id` mezővel érvénytelen középső elem), majd `readInbox()`-ot
  hívtam. Mért eredmény: `status: GamificationReadStatus.corrupt, value:
  null` — a 2 érvényes bejegyzés is elveszett a hívó szemszögéből, holott a
  `_inboxStore.read()` közvetlen hívása (a `JsonCollectionStore` saját,
  rekordonkénti hibatűrése miatt) a 2 jó bejegyzést visszaadta volna.
- **Kötelező javítás:** a saját előzetes validáló ciklus törlése; a
  `readInbox()` a `body is! List` ellenőrzés után közvetlenül
  `GamificationRead<List<GamificationInboxItem>>.available(_inboxStore.read())`-ot
  adjon vissza (pontosan úgy, ahogy a séma-fájl és a brief §0.0 eredetileg
  javasolta). A `_inboxStore.read()` már ma is logol
  (`storage.document.record_skipped`) minden kihagyott rekordot, tehát a
  diagnosztika nem vész el, csak a hibás all-or-nothing viselkedés szűnik
  meg.
- **Ellenőrzés:** a fenti próbateszt (vagy annak állandósított változata a
  `gamification_repository_test.dart`-ban, pl. `A2: one malformed inbox
  entry does not hide the other valid entries`) a javítás után `available`
  státuszt és 2 elemű listát várjon.
- **Státusz:** OPEN

### N1 — NOTE — a watch-stream optimistán sugározza az értéket, mielőtt a tényleges írás sikerét ellenőrizné

- **Fájl:** `lib/features/gamification/data/local_gamification_repository.dart:103-112`
- **Megfigyelés:** `_replaceProfileSnapshot` az `await _profileDocument.write(...)` UTÁN
  mindig `.add(GamificationRead.available(snapshot))`-ot közöl a
  figyelőknek — de a `JsonDocumentStore.write()` egy platform-szintű
  `StorageException`-t elnyel (logol, nem dob újra), tehát egy ilyen írási
  hiba esetén a stream a KÉRT (esetleg ténylegesen nem perzisztált) értéket
  jelenti „elérhető"-nek. Ez a viselkedés MEGEGYEZIK a projekt MINDEN egyéb
  `JsonDocumentStore`-alapú írásának meglévő kockázat-elfogadásával (egyik
  repository sem különbözteti meg ma a sikeres és az elnyelt írást a hívó
  felé) — ez a kör NEM vezet be új regressziót, csak a figyelő adatfolyam
  (A6, ezen a repositoryn ÚJ képesség) örökli ugyanazt a kockázatot.
- **Hatás:** szélsőséges esetben (platform megtagadja az írást) egy jövőbeli
  UI a ténylegesnél frissebb profilt mutathatna egy session erejéig, amíg
  újra nem olvas lemezről.
- **Javaslat (nem blokkoló, jövőbeli körnek):** a `write()` után a stream a
  ténylegesen `readProfileSnapshot()`-tal visszaolvasott állapotot
  sugározza a bemeneti érték helyett — önjavító, és a jövőbeli írás-hiba
  esetét is helyesen kezelné.
- **Státusz:** OPEN (nem blokkol)

## Gate-bizonyíték ellenőrzése

Saját kézzel, izolált klónban (`/tmp/review-e08-r08`, `git clone --branch
codex/e08-r08-gamification-repository-and-storage-schema
https://github.com/wolfcasaba/strumsight.git`, HEAD `3c67f44f`):

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (1712 fájl, 0 változott) |
| analyze | zöld | ✅ (0 lelet) |
| test `gamification_repository_test.dart` | zöld | ✅ (10/10 teszt) |
| test `architecture_dependency_test.dart` | zöld | ✅ (24/24 teszt) |
| architecture | zöld | ✅ (12 allowlistelt eltérés, változatlan) |
| secrets | zöld | ✅ (3033 fájl, 0 lelet) |
| l10n | zöld | ✅ (en→hu 1405 üzenet) |
| CI (teljes suite + property + APK) | — | még nem dispatch-elve — a javító kör UTÁN |

## Merge-döntés

**Merge TILTOTT amíg F1 nyitva** (ADR 0052 + AGENTS.md §15.2 — MAJOR nyitva
blokkol). F1 javítása a lánc NORMÁL útja (nem halt): javító kör ugyanazon a
motoron (`codex`), ugyanazon a branchen, a fenti leletlistával a promptban.
A javítás után: gate újrafuttatás saját kézzel, e jelentés frissítése
APPROVED-ra a javító commit SHA-jával, majd CI-dispatch és merge.
