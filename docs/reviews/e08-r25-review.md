# E08-R25 — Review

Brief: docs/rounds/e08-r25-song-trainer-and-setlist-integration.md (post
pre-flight revision, ADR 0391)
Diff: `git diff d06a9bf8..c41e3323` (pre-flight commit → implementer HEAD),
branch `minimax/e08-r25-song-trainer-and-setlist-integration`
Reviewer: Claude Sonnet 5 (orchestrator) + `security-reviewer` agent (risk = "high")
Dátum: 2026-08-22
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 2

Gate újrafuttatva SAJÁT kézzel, izolált klónban (`/tmp/review-e08-r25`,
klónozva közvetlenül a GitHub originből, nem a megosztott munkafából):
`tools/round-gate.sh test/features/gamification/integration/song_reward_flow_test.dart
test/features/songs` → **MINDEN GATE ZÖLD** (format, analyze, 2 test-útvonal
— 15 song-reward teszt + 49 songs teszt —, architecture, secrets, l10n).
Scope-audit (`tools/scope-audit.py --repo /tmp/review-e08-r25 --brief
docs/rounds/e08-r25-song-trainer-and-setlist-integration.md --base d06a9bf8`):
`Legacy scope audit OK (3 changed path(s), 0 generated/ignored)` — pontosan
az `allowed_paths` 3 fájlja, semmi más.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Szakaszok+teljes dal együtt NEM ad kétszeres alap-jutalmat (§6.1 alatt/rajta/fölött) | ✅ | `song_reward_flow_test.dart:31,68,138,162` — a "rajta" cella tesztje SZÁMSZERŰEN bizonyítja: `reducedTotal > 0` ÉS `reducedTotal < naturalTotal` (két külön session összehasonlítva) |
| A2 | Gyermek események szülő session-azonosítót hordoznak (ADR 0391 §Döntés 3 szerint: namespace-elt `eventId`) | ✅ | `:215-237` minden eventId tartalmazza a sessionId-t; `:239-279` a setlist-namespace nem ütközik egy azonos sessionId-jű szabad futással |
| A3 | Ugyanazon felvétel újrajátszása NEM ad második jutalmat | ✅ | `:283-304` — reopen ugyanazokat az eventId-ket adja, a ledger mérete nem nő |
| A4 | Új felvétel ÚJ jutalmat ad | ✅ | `:306-324` — eltérő sessionId → eltérő eventId-k, 4 ledger-bejegyzés |
| A5 | Főkönyvben NEM szerepel dalcím/előadó/fájlnév | ✅ | `:326-386` — explicit negatív asszerció a cím, a slug és az importer-prefix ellen, PLUSZ pozitív asszerció a hash jelenlétére. Függetlenül megerősítve a `security-reviewer` agent által (lásd F2/F3 lent): az adapter EGYETLEN `song.*` mezőt olvas (`song.id`, `:308`), és az azonnal `hashedSongId()`-n megy át — `song.name` sehol nincs felhasználva |
| A6 | Tempó-mérföldkő megadja az előző legjobbat és idejét | ✅ | `:389-412` |
| A7 | A `songs` feature dal-haladása VÁLTOZATLAN | ✅ | a gate `test/features/songs` útvonala 49/49 zöld; az adapter nem importál a `songs` feature progress-kódjából |
| A8 | A folyamat offline teljes | ✅ | `:414-434` — csak in-memory outbox/ledger, nincs hálózat/plugin |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.** `scope_audit=ok`,
`scope_audit_changed=3` (a `.codex-round-status` implementer-oldali
mérése is ezt jelezte, függetlenül megerősítve a `tools/scope-audit.py`
saját futtatásával).

## §6.1 valódi-sértés próbák — függetlenül megerősítve

A brief §6.1 KÉT kötelező próbát írt elő (a pre-flight §0.0 ADR 0391
mérése alapján). Mindkettő valódi, a termelési gépezettel (`DefaultRewardPolicy`,
`DefaultRewardEligibilityPolicy`) futtatott próba, nem csak dokumentált
állítás:

1. **Probe 1** (`:530-580`, session-bookkeeping kikapcsolva egy
   `_BrokenBookkeepingSongAdapter` alosztállyal): a törött ág egyenlő XP-t
   fizet egy szakasz-viselő és egy szakasz-mentes session teljes-dal
   eseményére — ez az A1 "rajta" infláció-cella PIROS állapota. A
   termelési adapter ezt a `reducedTotal < naturalTotal` asszerció révén
   kerüli el.
2. **Probe 2** (`:582-645`): a teszt KÖZVETLENÜL a `DefaultRewardPolicy`-t
   hívja egy `parentEventId: sectionEventId`-t hordozó kéréssel, egy olyan
   historyval, ahol a szekció már "parent" szerepben jutalmazott — az
   eredmény **pontosan 0 XP**, függetlenül megmérve, hogy a §0.0/ADR 0391
   bináris-dedup állítás igaz. A termelési adapter ezt elkerüli azzal, hogy
   MINDEN kérésen `parentEventId: null`-t állít (`:376`, `:437`).

Mindkét próba a gate-ben (`round-gate.sh`) fut, tehát a CI minden
futtatásakor újra bizonyít — nem egyszeri, eldobható próba, hanem
állandó regressziós őr. (A `sdd-round-review` protokoll az "eldobható
próbateszt, review után törölve" mintát javasolja default esetben; itt az
implementer a próbákat MEGTARTOTTA állandó teszt-cellaként, ami a §6.1
"Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva)" előírásának
szó szerint jobban megfelel, mint egy eldobott próba — nem lelet, hanem
erősebb bizonyíték.)

## Megállapítások

### F1 — MINOR — `utf8Bytes()` nem valódi UTF-8 kódolás, látens ütközés-kockázat

- **Fájl:** `lib/features/songs/application/gamification_song_adapter.dart:540-541`
- **Probléma:** `utf8Bytes()` a `String.codeUnits` (UTF-16 code unit-ok) minden
  elemét `& 0xff`-fel maszkolja — ez NEM UTF-8 kódolás. Mérve (önálló Dart
  szkripttel): `'musicxml-cafē'` (U+0113) és egy vele csak egyetlen, 0x100-cal
  eltérő kódponton különböző string a maszkolás UTÁN AZONOS bájtsorozatot ad,
  míg a valódi `utf8.encode()` helyesen megkülönbözteti őket.
- **Hatás:** a hash egyirányúságát/privacy-határát NEM sérti (a maszkolás
  csak információt DOB EL, sosem ad vissza felismerhetőbb tartalmat) — de
  KÉT KÜLÖNBÖZŐ, nem-ASCII karaktert tartalmazó `songId` ELMÉLETBEN azonos
  `hashedSongId`-re / `practiceKey`-re képződhetne (ütközés → két különböző
  dal gamification-könyvelése összemosódna). **Ma nem elérhető:** minden
  tényleges `Song.id` forrás ASCII-only (`songs_provider.dart:23`
  `_newId() = '${DateTime.now().microsecondsSinceEpoch}_${_seq++}'`; a
  song_trainer importerek `_slug()`-ja is `[a-z0-9-]`-ra szűkít) — a
  `security-reviewer` agent ezt függetlenül megerősítette.
- **Kötelező javítás:** cseréld `sha256.convert(utf8Bytes(songId))`-t
  `sha256.convert(utf8.encode(songId))`-ra (`import 'dart:convert';`), és
  töröld a saját `utf8Bytes` helper-t.
- **Ellenőrzés:** egy új unit-cella, ami egy nem-ASCII (pl. Latin
  Extended-A) karaktert tartalmazó `songId`-re két KÜLÖNBÖZŐ digestet vár
  két KÜLÖNBÖZŐ bemenetre.
- **Státusz:** OPEN — **nem blokkolja a merge-et** (nem-blokkoló MINOR: a
  hiba ma nem elérhető egyetlen valódi hívási láncon sem, a javítás
  triviális, egysoros follow-up; a §6 acceptance egyikét sem sérti).

### F2 — NOTE — a session/section/setlist azonosítók nincsenek hash-elve

- **Fájl:** `lib/features/songs/application/gamification_song_adapter.dart:282-298,522-523`
- **Megfigyelés:** csak a dal-azonosító megy hash-en keresztül; a
  `sessionId`/`sectionId`/`setlistRunId`/`setlistItemId` NYERSEN kerül az
  `eventId`-be és így a `ledgerId`/`sourceEventId` mezőkbe. Ma nincs hívó
  (`grep` szerint a `GamificationSongAdapter`/`recordSession` sehonnan nem
  hívott), tehát ez ma nem elérhető támadási felület — de egy jövőbeli
  bekötés, ami cím-eredetű session/section-azonosítót adna át (ugyanaz a
  hibaosztály, mint amit az ADR 0391 a `SongId`-nál mért), csendben
  megkerülné az A5 privacy-határt egy MÁSIK mezőn.
- **Javasolt irány:** amikor egy jövőbeli kör bedrótozza a hívót, a
  brief/ADR mondja ki explicit módon a session/section-azonosítók
  tartalom-semlegességi szerződését (vagy hash-elje ezeket is).
- **Státusz:** NOTE — nem blokkol, a következő bekötő kör brief-jének
  pre-flightjában érdemes megmérni.

### F3 — NOTE — a 16 hex karakteres (64 bit) csonkolás megfelelő

- **Fájl:** `gamification_song_adapter.dart:259-263`
- **Megfigyelés:** egyirányú, felhasználón-belüli, nem cross-user
  namespace-hez 64 bit bőven elég (a születésnap-korlát ~2^32, a
  `SongsRepository.maxSongs` sapka ezt sosem közelíti meg). Nincs teendő.

## Architektúra + termékhatárok

- A gamification feature-t KIZÁRÓLAG `../../gamification/public.dart`-on
  keresztül éri el (`:43`) — nincs belső fájl import.
- A `song_trainer/**`-hez az adapter NEM nyúl (nincs import onnan) — a
  `Song` típus a `songs` feature SAJÁT `model/song.dart`-jából jön, ami az
  `allowed_paths`-on belüli fájl.
- Nincs Riverpod/Flutter/plugin import a domain-jellegű adapterben (tiszta
  Dart + `package:crypto` + `package:meta`).
- Erőforrás-felszabadítás: nincs stream/subscription/timer az adapterben —
  tisztán async/await, nincs lifecycle-kockázat.
- `gate_shape=VIOLATION` jelzés vizsgálva és FÉLREVEZETŐNEK bizonyult: a
  minta illesztése a `cat tools/round-gate.sh | head -80` (a script FORRÁSÁNAK
  olvasása, nem a tényleges gate-hívás csővezetéke) sorra ütött, nem a valódi
  gate-invokációra (`tools/round-gate.sh test/... 2>&1`, pipe/lánc nélkül,
  a log teljes, csonkítatlan kimenetét tartalmazza — ellenőrizve).

## Következtetés

A kör az ADR 0391 pre-flight korrekcióját (session-bookkeeping-alapú
bónusz-méretezés `parentEventId` helyett; SHA-256-hashelt dal-azonosító)
pontosan a leírt mechanizmus szerint, mindkét kötelező valódi-sértés próbával
alátámasztva implementálta. Nincs BLOCKER/MAJOR. Az egyetlen MINOR (F1) nem
érinti egyetlen acceptance-pontot sem, és nem elérhető a mai hívási láncon —
follow-up, nem merge-gát. **APPROVED, mehet a CI-dispatch és a merge.**
