# ADR 0329 — Kanonikus tanulási esemény-szerződések

- **Státusz:** elfogadva
- **Dátum:** 2026-08-19
- **Kör:** `E08-R02` (Chapter 9, Kör 2)
- **Kapcsolódó:** [`0328`](0328-measured-gamification-baseline-contract.md)
  (gamification baseline), [`0289`](0289-mastery-is-evidence-not-xp.md),
  [`0290`](0290-compassionate-streaks-and-idempotent-claims.md),
  [`0257`](0257-planner-typed-ids-and-stable-enum-codes.md) (a
  domain-tisztaság és a stabil, hívó-adta ID precedense)

## Kontextus

Az Epic 8 gamifikációja négy feature (Progress, Streak, Learn, Share)
eredményéből táplálkozik, de ma egyiknek sincs közös alakja
(`docs/baseline/epic-08-start.md` §1). A Kör 3 reward ledgere, a Kör 4
outboxa és minden későbbi kör (XP, quest, achievement) ugyanarra az
esemény-bemenetre épül majd — ha ez a szerződés instabil vagy csendesen
gyengíthető, a hiba a láncon végig öröklődik, és a jutalom-egyenleg
visszamenőleg is hamissá válhat.

## Döntés

1. **A `schemaVersion` kötelező mező, ismeretlen érték hibát dob.** Nincs
   „legyen 1" alapértelmezés hiányzó vagy ismeretlen verzióra — az
   alapértelmezés pont azt a különbséget tüntetné el, amit a mező mérni
   hivatott (a Kör 3 ledgere ebből számol egyenleget).
2. **A domain tiszta Dart.** `lib/features/gamification/domain/activity/`
   nem importál Fluttert, Riverpodot, storage-ot vagy UI-t. Az immutabilitást
   `final` mező és `const` konstruktor adja, nem `package:flutter/foundation.dart`
   `@immutable` annotációja.
3. **Az `eventId` stabil és hívó-adta**, nem a konstruktorban óra- vagy
   véletlen-forrásból (`DateTime.now()`, `Random`) generált. A Kör 3
   idempotencia-indexe és a Kör 4 outboxa erre a stabilitásra épül —
   véletlenszerű azonosító mellett a dupla jutalom technikailag nem
   blokkolható.
4. **A JSON round-trip explicit `type` discriminatoron megy**, nem a mezők
   jelenlétéből következtetve. Strukturális kitalálás az első olyan
   altípusnál elromlik, amelynek mezői részhalmazát adják egy másiknak.
5. **Egyetlen belépő: `public.dart`.** A gamification feature kizárólag ezen
   a barrelen át importálható kívülről — a 21 meglévő feature bevett
   mintája (AGENTS.md §6).
6. **Hat esemény-altípus indul** (Practice, Song, Analysis, Plan, Tutor,
   Vision — `docs/sdd/09-epic-08-gamification.md` §8.1 javasolt listája). A
   séma additívan bővíthető; meglévő altípus mezőjének átnevezése vagy
   eltávolítása külön migrációs döntést igényel, mert a `type` discriminator
   és a `schemaVersion` már ezen a körön real kontraktussá válik.

## Következmények

**Pozitív.** A Kör 3–6 (ledger, outbox, XP, quest) a típusokra determinisztikusan
építhet; egy hibás implementáció (menet közbeni ID, csendes schema-default,
mezőkitaláló JSON) a saját tesztjén bukik meg, nem a lánc egy távoli pontján.

**Negatív / ár.** A `schemaVersion` szigorítása azt jelenti, hogy egy jövőbeli
mezőbővítés új verziószámot és explicit migrációs ágat igényel a
fogyasztóban — nincs olcsó, csendes bővítés.

## Mérce

Az `E08-R02` §6/§6.1 acceptance- és falszifikációs mátrixa: nyolc mérhető
kritérium (A1–A8), a `schemaVersion`-re kötelező valódi-sértés próbával (az
ismeretlen-verzió ág default-ra cserélve az A2 cellának pirosnak kell
lennie, majd visszaállítva zöldnek).
