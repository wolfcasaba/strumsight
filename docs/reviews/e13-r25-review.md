# E13-R25 review — Song Trainer, Result és Setlist Run UI

- **Reviewer:** Claude (Opus 5), orchestrátor-szék, READ-ONLY
- **Kör:** `E13-R25` · branch `sonnet-impl/e13-r25-song-trainer-and-setlist-run`
- **Review-elt HEAD:** `605e3215` (base `4185418d`)
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`), két futásban
- **Protokoll:** ADR 0055 — a review nem szerkeszt production kódot; a leletek
  eldobható próbatesztekkel mérve, amiket a review után töröltem.

## 0. Gépi mérések

| Mérés | Eredmény |
|---|---|
| Scope-audit a kör TELJES diffjén (`4185418d..605e3215`) | **ok** — 21 érintett útvonal, 0 listán kívüli |
| `scope_audit` (wrapper, resume-szakasz) | `ok` (11 fájl) |
| `gate_shape` (wrapper) | `VIOLATION` → **hamis pozitív, kivizsgálva** (lásd N1) |
| `dirty_files` a `done` jelzéskor | `1` → a jelzésfájl maga; a munkafa **tiszta** |
| A kör négy céltesztje + 5 meglévő pin + `app_router_test` + 4 fa-szintű őr | az implementer futtatta, zöld; a független igazolás az exact-SHA CI |
| Gyengítés-keresés (`skip`, `@Skip`, `ignore:`, `TODO`) a kör tesztjeiben | **0 találat** |
| `ui_inventory` diff | **ÜRES (86 → 86)** — a §0.0/B/B3 elvárása teljesült |
| Golden PNG-k | 8 fájl (4 képernyő × 2 keret), `tools/golden-x86.sh record` (ADR 0426 §3) |

## 1. Ami MÉRHETŐEN jó

- **A2/A3 — a lejátszófej valóban az audio órából vezetett.** A
  `_RunningBody.build` a `state.transportState.activePosition`-ból számol
  (`song_trainer_screen.dart`), **nincs** `Timer`, `Ticker` vagy
  `AnimationController` a fán. A viewport a KONFIGURÁLT `loopRangeEnd`-re
  clamp-el, kerekítés nélkül — pontosan az a hibaimplementáció, amit a §6.1
  „a vizuális loop-határ a kerekített ütemhez igazítva" sora tilt.
- **A9 — a golden VALÓDI hibát fogott.** `textScaleFactor: 2.0` mellett a
  `setlist_session_screen.dart` hangolás-kártyájának `Row`-ja **77 px-szel
  túlcsordult** (`RenderFlex overflowed`); a javítás (`Expanded` a címre) a
  diffben van. Ez a mérce dolgozott, nem a pecsét.
- **A1 — a valódi-sértés próba reprodukálható.** Az implementer §10-ben
  dokumentálta; a cella a `find.textContaining('%')` abszencia-asszercióval
  méri a kitalált pontszámot, ami a §0.0/B/B2 mért `isPlaybackOnly` ágára
  támaszkodik, nem új domain-módra.
- **A5 — a hangolás-váltás ELŐRE jelzett.** A `_tuningChangesAhead` a
  szomszédos elemek `overrides` különbségéből számol, és a kártya a futás
  INDÍTÁSA ELŐTT látszik — nem a dal kezdetekor.
- **Scope-fegyelem.** A `domain/`, `data/`, `application/` réteg érintetlen: a
  pontozás és a lejátszás logikája nem módosult (§3), gépileg igazolva.

## 2. Leletek

### MINOR-1 — a Stage olyan controllert `dispose`-ol, amit a PROVIDER birtokol

**Hol:** `lib/features/song_trainer/presentation/screens/song_trainer_screen.dart`,
`_SongTrainerScreenState.dispose()` → `unawaited(_ownedController?.dispose())`.

**A mért tény:** a `songTrainerControllerProvider` **`Provider.autoDispose.family`**,
és MÁR birtokolja a lezárást:
`ref.onDispose(() => unawaited(controller.dispose()))`
(`song_trainer_providers.dart:415`). A widget hívása tehát redundáns, és a
tulajdonoson KÍVÜLRŐL zárja le az erőforrást.

**Eldobható próbateszttel MÉRVE (két futás):**

| Forgatókönyv | Eredmény |
|---|---|
| A provider a widget unmountja alatt **cache-elve marad** (bármi más figyeli) → unmount → remount | `identical(first, second) = true`, és `prepare()` után `status = idle` — a controller **HALOTT, minden parancsa csendben no-op** |
| **Mai produkciós felállás** (a képernyő az EGYETLEN figyelő) → unmount → remount | `status = ready` — az `autoDispose` lebontja, a remount friss controllert kap |

**Ezért MINOR és nem MAJOR:** a mai bekötésben a hiba **nem érhető el** —
`grep -rn "songTrainerControllerProvider" lib/` szerint egyetlen produkciós
figyelő van, maga a képernyő. A `dispose()` idempotens (`if (_disposed) return`),
tehát a kettős lezárás sem árt ma.

**Miért lelet mégis:** a védelem az `autoDispose` + „pontosan egy figyelő"
együttállásán múlik, ami **nincs teszttel kikötve**. Amint egy jövőbeli kör
`ref.keepAlive()`-ot ad hozzá, vagy egy második widget (pl. egy mini-player,
egy setlist-beágyazás) is figyelni kezdi a providert, a felső sor lép életbe:
**néma no-op** — a projekt legveszélyesebb hibaosztálya, ami a felületen
„semmi sem történik"-ként jelenik meg, hibaüzenet nélkül.

**Javasolt feloldás (a kör SAJÁT fájljában, tágítás nélkül):** a widget ne
`dispose()`-oljon, hanem a tulajdonos kilépési útját hívja (pl. `stop()`/
`cancel()`), és a lezárást hagyja a `ref.onDispose`-ra — ez az, amit a brief
§0.0/B/B7 „a tulajdonos ÉRTESÍTÉSE, nem a lezárása" kikötése kér. A §5.6/A7
elvárása (minden kilépési úton felszabadul a lejátszás) ettől nem gyengül: az
`autoDispose` + `onDispose` lánc ma is elvégzi.

### MINOR-2 — a setlist ELSŐ elemének hangolása nem kerül az „előre jelzett" kártyára

**Hol:** `setlist_session_screen.dart`, `_tuningChangesAhead`.

A ciklus `previous == null` esetén nem ad hozzá, tehát ha a setlist **első**
dala már eltérő hangolást/capót kér, az nem jelenik meg az előrejelző
kártyán. Fellépési helyzetben ez pont a legelső átállás.

**Enyhítő tény:** az elem `trailing` `_reminder`-je a listában megjeleníti,
tehát nem láthatatlan — ezért MINOR, nem MAJOR.

## 3. Megjegyzések (nem leletek)

- **N1 — a `gate_shape=VIOLATION` HAMIS POZITÍV.** A wrapper regexe
  (`round-gate\.sh[^\n]*(\| *(tail|head)|&&)`, `tools/mm-round.sh:382`) a
  logban erre illeszkedett:
  `ls tools/round-gate.sh && cat tools/round-gate.sh | head -30` — ez a
  gate-script **elolvasása**, nem a futtatása. A tényleges négy
  `tools/round-gate.sh …` hívás a logban **csupasz**, csővezeték és `&&` nélkül
  (L09 betartva). A jelzés nem gyengíti a kör bizonyítékát; a regex
  finomítása az önjavító kör dolga, nem ezé (§4 — a mérce nem módosulhat
  attól, akit mér).
- **N2 — az első futás időkorlátba futott** (3600 s, jelzés nélkül), a
  részmunkát az orchestrátor commitolta (`0f617462`, scope-audit ok), a
  folytatás ugyanazon a branchen zárta le a kört. Ez a kör **egy** javító/
  folytató körnek számít; H6 nem áll fenn (egyszeri `timeout`, nem kétszeri).
- **N3 — a `trainer_setup_screen.dart` és a `song_result_screen.dart`
  módosítatlan.** Az implementer §10-ben kimondja, és a céltesztek a meglévő
  kód ellenében is mérik az A6/A8-at. Ez összhangban van a §0.0/B/B3-mal (a
  migráció HELYBEN, a leltár diffje üres).

## 4. Verdikt

**VÉGSŐ DÖNTÉS: APPROVED**

- **BLOCKER: 0**
- **MAJOR: 0**
- **MINOR: 2** (MINOR-1 latens néma-no-op kockázat, MINOR-2 az első setlist-elem)

A két MINOR **nem blokkolja a merge-et** (ADR 0052 zöld kapu: a mérce-lánc
zöld, a scope tiszta, gyengítés nincs). Mindkettő a **következő Ch13 körre**
átvihető follow-up, és a HANDOFF §6-ba kerül — a MINOR-1 kifejezetten azzal az
indoklással, hogy a mai védelme egy nem-tesztelt együttálláson múlik.

A merge feltétele változatlanul az **exact-SHA** CI: `full-gate.yml` ÉS
`router-ci.yml` `success` a merge SHA-ján.
