# ADR 0382 — Quest objective- és életciklus-szerződés

- **Státusz:** elfogadva (E08-R16 pre-flight)
- **Dátum:** 2026-08-21
- **Kör:** `E08-R16` — Quest domain, objective és életciklus
- **Kapcsolódó:** [`0073`](0073-practice-session-state-machine.md),
  [`0290`](0290-compassionate-streaks-and-idempotent-claims.md),
  [`0329`](0329-canonical-activity-event-contracts.md),
  [`0341`](0341-explainable-xp-policy-and-diminishing-returns.md),
  [`0374`](0374-achievement-domain-and-catalog-contract.md)

> **Számozási megjegyzés:** az előre írt brief `0312`-t nevezett meg, de az
> már az elfogadott tudás-RAG ADR száma. A kötelező
> `tools/round-slots.py reserve-adr --round E08-R16` futás `0382`-et adott;
> a foglaló mért eredménye az irányadó, az ADR 0312 változatlan marad.

## Kontextus

A Chapter 9 napi és heti questjei tartós állapotot és jutalmat kapcsolnak
össze. A két rész eltérő okból veszélyes: egy nyitott vagy hallgatólagos
állapotgép elveszítheti a részleges haladást, egy UI-hoz vagy claimhez kötött
jutalom pedig kimaradhat vagy ismétléskor duplikálódhat.

Az R03 már ad immutable `RewardLedgerEntry` receiptet és idempotens ledger
repositoryt. Az R13 zárt achievement-objective metrikát ad, a practice és a
practice-generator publikus határa pedig stabil `PracticeMode` és `BlockId`
típusokat exportál. A quest domainnek ezeket kell újrahasznosítania; belső
feature-import, szabad expression string és repository-I/O nem kerülhet a
domainbe.

## Döntés

1. **Zárt, típusos objective.** A quest objective sealed hierarchiája négy
   konkrét hivatkozást enged: validált stabil skill-tag, publikus `BlockId`,
   publikus `PracticeMode`, illetve az R13 `AchievementMetric`. Egy explicit
   unknown sentinel csak a fail-closed decode/validáció útját teszi
   mérhetővé; érvényes quest-definícióban nem fogadható el.

2. **Verziózott, tiszta domain.** A definíció, schedule és progress explicit
   `schemaVersion`-t hordoz és ismeretlen verzióra kontrollált hibát ad. A
   modellek immutable pure Dart értékek; órát, storage-ot, repositoryt vagy
   UI-t nem olvasnak.

3. **A schedule az eredeti naphatárt őrzi.** A perzisztált alak
   `generationEpochDay`, `timezoneOffsetMinutes`, pozitív `catalogVersion` és
   UTC `expiresAt` mezőt tárol. A timezone offset nem számolódik újra az
   aktuális eszközbeállításból. Az aktív intervallum felső határa exkluzív:
   `now < expiresAt`; a határon és utána a quest lejárt.

4. **Zárt state machine, explicit eredmény.** A definiált élek
   `active → completed|expired|replaced` és
   `completed|expired|replaced → archived`; az `archived` terminális. Minden
   sikeres él stabil reason code-ot ad, minden nem definiált él típusos
   failure-t, nem `bool`-t és nem hallgatólagos no-opot. A replacement külön
   stabil indokkódot hordoz.

5. **Az expiry semleges.** A lejárati átmenet megőrzi az addigi számlált
   haladást, completion-adatot és már létrejött ledger-hivatkozást. A quest
   domain nem törölhet practice eredményt, XP-t vagy ledger bejegyzést.

6. **Completion és reward külön, de elválaszthatatlan tranzakciós eredmény.**
   A progress külön tárolja a completion tényét és a reward ledger
   hivatkozását. Az első sikeres completion eredménye kötelezően és azonnal
   tartalmazza az R03-kompatibilis `RewardLedgerEntry`-t
   `RewardReason.questCompleted` indokkal. Nincs `claim()` állapot vagy API;
   a UI megnyitása nem előfeltétel. A domain nem ír repositoryt: az
   application-hívó az eredmény receiptjét az R03 idempotens append útjára
   továbbítja.

7. **Completion idempotens.** A ledger ID a stabil quest ID-ból
   determinisztikusan származik. Az ismételt completion megtartja az eredeti
   completion időpontot és ugyanazt a receiptet adja; nem képez új rewardot.
   Ez a command-idempotencia explicit kivétel, nem új önél az
   állapotátmenet-gráfban.

## Következmények

A Kör 17/18 generátora ellenőrizhető, stabil objective-ekre építhet, a Kör 20
felülete pedig csak megjelenítheti a már eldöntött completion/reward állapotot.
A reward repositoryba írás application-integráció marad; ez a domain-purity
ára, de completion reward nélküli reprezentációját a típus nem engedi.

A timezone offset és az eredeti expiry instant együtt perzisztált adat, ezért
utazás vagy DST-váltás nem írja át visszamenőleg a quest naphatárát. A
terminális progress rekordok archiválhatók, de a felhasználó gyakorlási
eredményei és főkönyve nem részei ennek a lifecycle-nak.

## Mérce

Az E08-R16 brief A1–A9 cellái mérik az automatikus receiptet, UI/claim
függetlenséget, semleges expiry-t, a teljes átmenetmátrixot, reason code-okat,
typed/fail-closed objective-et, schedule round-tripet, schema fail-closed
viselkedést és completion-idempotenciát. A lejárati határ kötelező három
cellája: `expiresAt - 1s`, pontosan `expiresAt`, `expiresAt + 1s`. A reviewer
eldobható mutációval eltávolítja az automatikus receiptet; az A1 cellának
pirosra kell váltania, majd a mutációt vissza kell állítani.
