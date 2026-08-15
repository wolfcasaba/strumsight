# ADR 0267 — A terv-tároló névterei elkülönülnek, a korrupció rekord-szintű

**Státusz:** elfogadva (2026-08-15). Az Epic 7 tárolási döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md) Ch8 Kör 19.
Épít: [ADR 0256](0256-practice-plan-revisions-immutable-past.md) (immutable
revíziók), [ADR 0259](0259-generation-request-versioning-and-draft-isolation.md)
§3 (draft-izoláció), [ADR 0266](0266-generation-orchestration-and-no-partial-activation.md).

## Kontextus

A tároló a tanuló **teljes gyakorlási történetét** őrzi: draftokat, az aktív
tervet, a revíziókat és az eredményeket. Egy hiba itt nem egy képernyőt ront
el, hanem hónapok munkáját viszi.

## Döntés

### 1. Három elkülönített névtér: draft, aktív, archív

Egy draft-írás soha nem érheti el az aktív tervet. Az ADR 0259 §3 kiterjesztve
a teljes tárolóra.

### 2. A korrupció rekord-szintű: egy sérült rekord nem viszi el a többit

*A tiltás:* „ha a fájl sérült, kezdjük tisztán". Ez a legegyszerűbb reakció a
korrupcióra, és a tanuló **összes** tervét törölné egyetlen hibás bájt miatt.
A rekordonkénti checksum teszi lehetővé, hogy csak a sérült vesszen el —
jelzéssel.

### 3. Az írás atomikus

Félbeszakadt írás (kill, lemerülés) nem hagyhat félkész rekordot. Ha a Core
kínál atomikus API-t, azt kell használni, nem újat írni.

### 4. Az eredmény-hozzáfűzés idempotens

Ugyanaz az eredmény kétszer beírva egyszer szerepel — az ADR 0260 §3
dedup-elvének folytatása a tárolóban.

### 5. A történet korlátos, de a korlátozás nem ír felül revíziót

A tömörítés lezárt tartományt vonhat össze, dokumentáltan — meglévő revíziót
**nem módosíthat** (ADR 0256 §1).

### 6. A migráció felfelé nyitott, lefelé nem

Régebbi séma migrálódik; újabb séma kontrollált hiba (ADR 0259 §4).

## Következmények

- A tanuló története túléli a részleges hibákat: egy sérült terv elveszik, a
  többi megmarad.
- Az „aktív terv app-újraindítás után visszatér" ígéret tesztelhető
  invariánssá válik.
- A tömörítés bevezetése később nem sérti az immutable-múlt elvét.

## Mérce

Az `E07-R19` §6.1 mérce-mátrixa, benne a séma-verzió három kötelező cellájával
(a küszöb alatt → migrálódik / rajta → olvasható / fölött → kontrollált hiba)
és a valódi-sértés próbával: egyetlen rekord checksumját elrontva a többinek
olvashatónak kell maradnia — ha a hiba az egészet elviszi, az **A2** cella piros.
