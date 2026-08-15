# ADR 0268 — A technikai hiba nem a tanuló teljesítménye

**Státusz:** elfogadva (2026-08-15). Az Epic 7 végrehajtási döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md) Ch8 Kör 23.
Épít: [ADR 0260](0260-skill-evidence-privacy-and-deduplication.md),
[ADR 0261](0261-skill-estimate-bounded-influence-and-unknown-state.md),
[ADR 0265](0265-bounded-evidence-based-difficulty-adaptation.md).

## Kontextus

A gyakorlás sokféleképpen érhet véget: a tanuló végigcsinálja, megszakítja,
vagy **elromlik valami** — a mikrofon nem indul, az app összeomlik, hiányzik
egy asset, az engedélyt megtagadták.

A kényelmes megvalósítás egyetlen „sikerült / nem sikerült" mezőt tart. Ekkor
a technikai hiba **kudarcnak** könyvelődik: a becslés csökken, és az adaptáció
könnyíteni kezd. A tanuló azért kap alacsonyabb szintű tervet, mert elromlott
a mikrofonja.

## Döntés

### 1. A technikai hiba nem számít teljesítménynek

Mikrofon-hiba, összeomlás, hiányzó asset, engedély-megtagadás → az eredmény
**nem** módosítja a skill-becslést, és nem vált ki regressziót
(ADR 0265 §4 kiegészítése).

### 2. A megszakítás részleges, nem kudarc

A tanuló saját döntése abbahagyni nem teljesítmény-ítélet. Külön kimenet, ami
nem büntet — az `E07-R17` §5.2 („a bizonytalan nem büntet") rokona.

### 3. Az elavult blokk nem indul

Ha a hivatkozott gyakorlat revíziója megváltozott vagy a capability eltűnt
(ADR 0262 §3), a blokk helyettesítést vagy újratervezést kér — nem fut le
rosszul.

### 4. A session-konfig pontosan a recept szerinti

Amit a tervező előírt, az megy át a végrehajtóhoz. „Körülbelüli" konfig esetén
a mérés értelmetlen: 60 BPM helyett 70-en gyakorolva a visszacsatolás mást mér,
mint amit terveztünk.

### 5. Az eredmény idempotens

Ugyanaz a `blockExecutionId` kétszer visszatérve egyszer könyvelődik
(ADR 0260 §3).

## Következmények

- A skill-becslés csak **valódi** teljesítményből épül.
- A hibás eszköz vagy környezet nem torzítja a tanuló képének alakulását.
- A jelminőség-alapú hibák külön ágon kezelhetők (`E07-R25` §5.4): ilyenkor
  beállítási vagy felmérési javaslat indokolt, nem nehézség-változtatás.

## Mérce

Az `E07-R23` §6.1 mérce-mátrixa, benne az eredmény-típus három kötelező
cellájával (**technikai hiba** → a becslés változatlan / **megszakítás** →
részleges, nem büntet / **végigcsinálta** → teljes értékű evidence) és a
valódi-sértés próbával: a technikai hibát sikertelen teljesítményként
könyvelve az **A1** cellának pirosnak kell lennie.
