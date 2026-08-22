# ADR 0391 — Song gamification adapter: session-scoped bónusz-méretezés parent/child dedup nélkül, hashelt dal-azonosító

- **Státusz:** elfogadva (E08-R25 pre-flight)
- **Dátum:** 2026-08-22
- **Kör:** `E08-R25` — Song Trainer és setlist integráció
- **Kapcsolódó:** [`0341`](0341-explainable-xp-policy-and-diminishing-returns.md),
  [`0390`](0390-practice-and-learn-gamification-adapter-boundary.md),
  [`0329`](0329-canonical-activity-event-contracts.md),
  [`0089`](0089-song-trainer-v2-domain-and-import-pipeline.md)

## Kontextus

A kör-brief (2026-08-18-i írás) két kötött állítást tett, amit a pre-flight
méréssel megcáfolt:

**1. A "teljes dal bónusz" §5.1 leírása `parentEventId`-t (R06, ADR 0341)
jelölt meg mechanizmusként.** Mérve
(`lib/features/gamification/infrastructure/default_reward_policy.dart`
`_dedup()`, és ADR 0341 §Döntés 2. pontja: „Gyermek akkor kap nulla XP-t, ha
a parent már jutalmazott; parent akkor, ha korábbi gyermek már hivatkozott
rá."): a `RewardPolicyRequest.parentEventId` dedup **bináris, mind-vagy-semmi
összeomlás** — a párból (parent/child) amelyik MÁSODIKKÉNT érkezik egy már
jutalmazott társ ellenében, **teljes egészében NULLÁRA esik**. A mechanizmus
strukturálisan képtelen „a gyermek teljes jutalmat kap ÉS a parent egy
kisebb, de NEM nulla bónuszt" kimenetre — csak „az egyik fél teljes
jutalmat kap, a másik semmit" állítható elő, VAGY irányban.

A reális lejátszási sorrendben (a felhasználó előbb szakaszokat gyakorol,
utána fejezi be a teljes dalt) a szakaszok (gyermekek) érkeznek ELŐSZÖR — a
`rewardedChildParentIds` így már tartalmazza a dal saját eseményazonosítóját,
mire a teljes dal (parent) esemény befut, ezért a `_dedup()` a teljes dal
bónuszát **nullára** ejtené. Ez ellentmond a brief §6.1 „rajta" cellájának
(„a szakaszok alap-jutalma EGYSZER + a teljes dal BÓNUSZA — összesen NEM a
kétszerese" — vagyis a bónusz NEM lehet nulla).

Az ADR 0341 „Elutasított alternatívák" szakasza emellett kifejezetten
elutasítja a `parentEventId` kanonikus `LearningActivityEvent`-re vételét —
a mező kizárólag a `RewardPolicyRequest` alkalmazási rétegen él, és a
mechanizmus szándékosan bináris (nincs „részleges" dedup-variáns; egy ilyen
hozzáadása az ADR 0341 döntésének módosítása lenne, ami lezárt kör, és a
`reward_policy_engine.dart` / `default_reward_policy.dart` amúgy sem
`allowed_paths`-on belüli fájl ebben a körben).

**2. A §5.3 privacy-safe azonosító feltételezte, hogy a `SongId` már ma is
tartalom-semleges.** Mérve (`grep -n "SongId(" lib/features/song_trainer/
data/importers/*.dart`): `SongId('musicxml-${_slug(title)}')` és
`SongId('midi-${_slug(title)}')` — a `SongId.value` a dal **kisbetűs,
kötőjelezett CÍM-szeletét** hordozza, nem semleges belső azonosító. A
`lib/features/song_trainer/application/progress/song_progress_aggregator.dart`
`PracticeSessionSongCreditRecorder` már ma is `lessonId: 'song-${record.
songId.value}'` mintát használ a Practice napi-cél/széria hídon — ez a
minta **nem** másolható át a gamification főkönyvbe: a `_slug(title)` a
dalcím szinte olvasható alakja, tehát a mai `songId.value` közvetlen
felhasználása a főkönyvben pontosan azt a szivárgást okozná, amit a brief
§5.3 kifejezetten tilt.

## Döntés

1. **A szakasz/teljes-dal splitben egyetlen `gamification_song_adapter.dart`
   által küldött `RewardPolicyRequest` sem állítja be a `parentEventId`
   mezőt.** Minden kérés önálló (`parentEventId: null`), így a R06 bináris
   dedupja soha nem fut le a szakasz↔dal kapcsolatra, és nem tudja nullázni
   a bónuszt.
2. **Az inflláció-védelem (A1, §6.1 „rajta" cella) az adapter SAJÁT,
   session-hatókörű könyveléséből származik, nem a gamification rétegből.**
   Az adapter a rákapott `SongTrainerResult`/`SetlistResult` bemenetből
   (amit a hívó ad át — a `songs`/`song_trainer` public szerződés, nem a
   gamification belseje) eldönti, hogy ugyanabban a session-ben már küldött-e
   szakasz-eseményt a dalhoz:
   - ha IGEN → a teljes dal esemény **csökkentett** (bónusz-méretű)
     `validDuration`/`qualityScore` jelet kap;
   - ha NEM (a felhasználó a szakaszok kihagyásával közvetlenül a teljes
     dalt játszotta végig) → a teljes dal esemény a **természetes, teljes**
     (alap + bónusz) jelet kapja.
   Ez determinisztikus, tisztán az adapter saját állapotán (nem a
   gamification rétegen) múlik, és nem függ a nap folyamán korábban lezajlott,
   más session-ekhez tartozó gyakorlástól (a R06 `practiceKey`-alapú decay
   réteg NEM kerül bevonásra erre a célra — az egy másik, nap-szintű
   farmolás-ellenes réteg, más hatókörrel).
3. **Az A2 („a gyermek események szülő session-azonosítót hordoznak") a
   saját, stabil `eventId` session-be ágyazásával teljesül, nem
   `parentEventId`-vel.** Az `eventId`-k namespace-elt, session-ből
   determinisztikusan származtatott stringek (pl.
   `'song-section/<sessionId>/<sectionId>'`,
   `'song-full/<sessionId>'`, `'setlist-item/<setlistRunId>/<itemId>'`) — a
   session-hovatartozás így a mérce-mátrix és az audit számára is olvasható
   marad, a R06 dedup rétege pedig változatlanul csak az A3 (ugyanaz a
   felvétel, ugyanaz az `eventId`) egyszerű, plain `rewardedEventIds`
   ismétlés-dedupját végzi — ami már ma is helyesen működik, nem kell hozzá
   `parentEventId`.
4. **A privacy-safe dal-azonosító a `SongId.value` egyirányú hash-e, NEM a
   nyers érték.** Az adapter a `songId.value`-ból egy stabil, determinisztikus,
   nem visszafejthető digest-et származtat (pl. SHA-256 hex, csonkolva egy
   rögzített hosszra) minden ledgerbe kerülő `eventId`/`practiceKey`
   komponenshez — a mai `_slug(title)`-alapú `SongId.value` SOHA nem kerül a
   főkönyvbe nyers vagy felismerhető alakban. A `PracticeSessionSongCreditRecorder`
   `lessonId: 'song-${record.songId.value}'` mintája ezért **nem** vehető át
   1:1 — az egy MÁS (Practice napi-cél) hídra korábban jóváhagyott, nem
   audit-főkönyvi felhasználás, és ennek a körnek a scope-ján kívül esik a
   javítása.

## Következmények

- A brief §5.1/§5.3 szövege és a §6.1 mérce-mátrix implementáció-szintű
  hivatkozásai a fenti mechanizmusra frissülnek (§0.0 brief-revízió,
  ugyanebben a pre-flightban) — az acceptance kritériumok (A1–A8) külső,
  megfigyelhető viselkedésként változatlanok maradnak, csak a `parentEventId`
  téves hivatkozása cserélődik a session-bookkeeping mechanizmusra.
- A `PracticeSessionSongCreditRecorder` meglévő, cím-szivárgó `lessonId`
  mintája ezzel a körrel NEM javul (más feature, más scope) — ha egy jövőbeli
  audit ezt privacy-résnek minősíti, az egy külön kör tárgya.
- Jövőbeli, session-szintű bónusz-megosztást igénylő adapter ugyanezt a
  mintát követheti (standalone kérések + hívó-oldali kondicionális
  jel-méretezés) ahelyett, hogy a R06 `parentEventId` dedupját erőltetné rá
  egy olyan alakra, amire az nem lett tervezve.

## Elutasított alternatívák

- **`parentEventId` szó szerinti bevezetése a szakasz↔dal kapcsolatra**:
  mérve, hogy a reális (szakaszok-előbb) sorrendben nullázza a bónuszt —
  elutasítva.
- **A R06 `practiceKey`-decay réteg megosztott kulccsal való
  "kölcsönvétele"** a bónusz-kicsinyítésre: nap-szintű, session-eken átívelő
  számlálóra épül, tehát a "rajta" cella determinisztikus tesztje más,
  ugyanazon a napon lezajlott gyakorlástól is függne — elutasítva a
  session-hatókörű, tesztelhető adapter-oldali logika javára.
- **A `reward_policy_engine.dart`/`default_reward_policy.dart` módosítása**
  egy új, „részleges" dedup-variánssal: ezek a fájlok nincsenek az
  `allowed_paths`-on, és a módosítás az ADR 0341 lezárt döntését írná át —
  elutasítva.
- **`songId.value` közvetlen felhasználása a főkönyvben** (a
  `PracticeSessionSongCreditRecorder` mintáját másolva): mérve, hogy a
  `SongId` ma cím-szeletet hordoz — elutasítva a brief §5.3 kifejezett
  tilalma miatt.
