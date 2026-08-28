# ADR 0468 — Domain event katalógus és séma-registry

- **Státusz:** elfogadva (2026-08-28, E12-R09 pre-flight)
- **Kontextus-kör:** `E12-R09` — Domain event catalog és schema registry
- **Kapcsolódó:** [ADR 0329](0329-canonical-activity-event-contracts.md) (kanonikus
  tanulási esemény-szerződések), [ADR 0333](0333-activity-outbox-reliable-processing.md)
  (megbízható outbox-feldolgozás), [ADR 0215](0215-analysis-document-versioning.md)
  (dokumentum-verziózás precedense), [ADR 0176](0176-cross-feature-public-barrel-recognition.md)
  (cross-feature barrel)

> **Sorszám-megjegyzés.** A Chapter 12 batch-terv `0450`-et jelölte ki ehhez a
> körhöz, a foglaló (`tools/round-slots.py reserve-adr --round E12-R09`) viszont
> **`0468`**-at adta: a lemezen időközben a `0466`/`0467` (E15 sáv) landolt, és a
> foglaló a lemezen lévő ÉS a már foglalt számok fölé megy. A normatív szabály a
> foglaló (ADR 0087 pipeline-prompt §1.0.1: „ADR-számot a foglalótól kérj, ne
> `ls`-sel"), ezért ez az ADR `0468`. A `0450` szabadon marad.

## Kontextus

A SDD Chapter 12 Kör 9 eredeti feladata egy `DomainEventEnvelope` core típus
bevezetése volt. A fa MÉRT állapota szerint ez a szerződés **már él**, csak nem
`lib/core/` alatt: a `lib/features/gamification/domain/activity/learning_activity_event.dart`
`sealed class LearningActivityEvent` hierarchiája (ADR 0329) kötelező
`schemaVersion`-nel, hívó-adta stabil `eventId`-vel, `type` diszkriminátorral és
**hat** altípussal (`practice`, `song`, `analysis`, `plan`, `tutor`, `vision`) a
gamification `public.dart` barrelje mögött publikus.

Ami hiányzik, az nem típus, hanem **nyilvántartás és gépi mérce**: ma sehol nincs
leírva, melyik feature termeli és melyik fogyasztja az egyes esemény-típusokat,
ki a tulajdonos fejezet, mi az idempotencia-kulcs, és mi a kompatibilitási
szabály egy jövőbeli mezőbővítésre. Egy második, konkurens envelope-típus
bevezetése ezt nem oldaná meg, viszont kettős igazságot teremtene.

## Döntés

**D1 — A `LearningActivityEvent` A domain event envelope; nincs mellé második.**
Ez a kör NEM hoz létre `lib/core/events/` könyvtárat és nem vezet be új
altípust. A szállítmány dokumentum (`docs/contracts/event-catalog.md`), fixture-
készlet (`test/fixtures/events/*.json`) és gépi mérce
(`test/core/events/event_schema_compatibility_test.dart`) — `lib/**` diff nélkül.

**D2 — A katalógus a KÓDBÓL mért, nem az SDD-ből másolt.** Minden sor
producer/consumer cellája létező fájlra hivatkozik, és a hivatkozás gépileg
ellenőrzött: a fájlnak léteznie kell, és producer-cellánál a hivatkozott fájlnak
tartalmaznia kell az adott altípus konstruktor-hívását. Az SDD §14.1 „közös
események" listája terv, nem bizonyíték.

**D3 — A „nincs producer" MÉRT állapot, amit ki kell mondani, nem kitalálni.**
MÉRVE: a `TutorActivityEvent` altípusnak ma **nincs** termelője a `lib/**` fában
— a `lib/features/ai_tutor/application/gamification_tutor_adapter.dart` (18–19.
és 164. sor) kifejezetten dokumentálja, hogy a tutor-session
`PracticeActivityEvent`-ként jutalmazódik. A katalógus ilyen sorban explicit
„nincs producer (mért)" jelölést és indokot hordoz, és a mércének a **hiányt is
mérnie kell** (a típus konstruktor-hívása sehol nem szerepel a `lib/**`-ban) —
különben a jelölés a kitalált hivatkozás olcsó búvóhelye lenne.

**D4 — Egyetlen támogatott séma-verzió van, és a határ mindkét irányban
kontrollált hiba.** MÉRVE: `learningActivityEventSchemaVersion = 1`, és a
`_validateEventFields` `schemaVersion != 1` esetén `ArgumentError`-t dob. Tehát
`V = 1`, és **`< V` ÉS `> V` egyaránt kontrollált hiba** — nincs „régi verzió
best-effort olvasása" (ADR 0215 2. pont precedense) és nincs csendes
„legyen 1" alapértelmezés hiányzó verzióra (ADR 0329 1. pont). A katalógus
kompatibilitási szabálya ezt rögzíti: **additív bővítés (új mező) verzión belül
kompatibilis** — az olvasó az ismeretlen mezőt eldobja —, **minden más
alakváltás ÚJ verziószámot és explicit fogyasztói ágat igényel** (ADR 0329
„Negatív / ár" bekezdése).

**D5 — A fixture-ök kanonikusak, nem kézzel szépek.** Minden fixture BYTE-szinten
az, amit az adott esemény `toJson()`-je termel: `occurredAt` a
`DateTime.toIso8601String()` UTC alakja ezredmásodperccel és `Z` végződéssel,
`durationMicroseconds` egész, `score` tizedes tört. A mérce ezt cellában
ellenőrzi (`jsonDecode(fixture) == fromJson(fixture).toJson()`), mert a
kézzel írt mezőnév (`occurred_at`) és a nem kanonikus időbélyeg ugyanabba a néma
hibaosztályba tartozik.

**D6 — Az idempotencia-kulcs az `eventId`, a fán mérve.** A ledger
append-if-absent a `sourceEventId`-re szűr
(`local_reward_ledger_repository.dart:77`), a beemelő pedig kikényszeríti, hogy
`entry.sourceEventId == event.eventId`
(`activity_event_ingestor.dart:61`), és ugyanezt állítja az
`ActivityOutboxRecord` is (`activity_outbox_repository.dart:27`). A katalógus
idempotencia-oszlopa ezt a MÉRT kulcsot nevezi meg, nem egy tervezett másikat.

## Következmények

**Pozitív.** A cross-feature esemény-forgalomnak egyetlen, verziózott,
tulajdonossal ellátott nyilvántartása lesz, aminek az elavulását teszt méri: ha
egy altípus mezőt kap vagy egy producer megszűnik, a fixture- és a katalógus-
cella pirosra vált, nem némán hazudik tovább.

**Negatív / ár.** A kanonikus fixture-alak azt jelenti, hogy a fixture-öket nem
lehet kézzel „olvashatóbbra" írni; a `> V` verzió tiltása pedig azt, hogy egy
jövőbeli séma-bővítés kötelezően kör-szintű döntés (új verziószám + fogyasztói
ág + katalógus-sor), nem egy csendes mezőfelvétel.

**Amit ez az ADR NEM dönt el.** A `community_outbox.dart` (community-oldali,
külön szerződés) egyesítését a gamification outboxszal — az külön kör és külön
ADR tárgya; ez a katalógus a `LearningActivityEvent` forgalmát írja le.

## A visszavonás feltétele

Felülvizsgálandó, ha (a) egy valódi második envelope-család születik (pl. a
community-oldali esemény is cross-feature szerződéssé válik) — ekkor a katalógus
több szekcióra bomlik, de a mérce-elv (mért hivatkozás, kanonikus fixture,
kétirányú verzió-határ) marad; vagy (b) a `LearningActivityEvent` valóban
`schemaVersion = 2`-re lép — ekkor a D4 „egyetlen támogatott verzió" mondata egy
explicit, verziónkénti támogatási táblára cserélődik, ADR-hivatkozással.
