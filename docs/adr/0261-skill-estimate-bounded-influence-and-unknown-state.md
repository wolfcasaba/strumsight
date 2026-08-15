# ADR 0261 — Egyetlen mérés hatása korlátos, és az „ismeretlen" nem gyengeség

**Státusz:** elfogadva (2026-08-15). Az Epic 7 skill-becslésének döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md) Ch8 Kör 6.
Épít: [ADR 0255](0255-deterministic-first-practice-planning.md) (determinizmus),
[ADR 0260](0260-skill-evidence-privacy-and-deduplication.md) (evidence-modell).

## Kontextus

A reducer sok, eltérő megbízhatóságú evidence-ből állít elő egy skill-becslést,
amire a tervező épít. Két hiba itt közvetlenül a felhasználó gyakorlását
rontja el, és mindkettő a legkényelmesebb megvalósításból jön.

## Döntés

### 1. Egyetlen evidence hatása felülről korlátozott

Egy gyakorlás nem ugrathat több szintet. A cap a policy **explicit**
paramétere, nem a súlyozás mellékhatása.

*Miért nem elég a kis súly:* amíg nem jelenik meg egy nagyon magabiztos
forrás. Akkor a „úgyis korlátoz" feltevés csendben megdől.

### 2. Az „ismeretlen" önálló állapot, nem alacsony érték

Ha egy skillre nincs érvényes evidence, a becslés `unknown` — nem `0.0`.

*Miért ez a legfontosabb:* a tervező a gyenge készségeket gyakoroltatja
többet. Ha a soha nem mért készség „nagyon gyengének" látszik, a rendszer
pont azt tolná a tanuló elé, amiről semmit nem tud — magabiztosan.

### 3. A konfliktus bizonytalanságot ad, nem átlagot

Ellentmondó evidence esetén a becslés **bizonytalansága nő**. Az átlagolás
elrejtené, hogy az adatok nem értenek egyet, és a tervező úgy döntene, mintha
biztos lenne a dolgában.

### 4. A discomfort nem megy a teljesítmény-értékbe

Az ADR 0260 §2 folytatása: a kényelmetlenség önálló jelként halad tovább, és a
nehézség **csökkentése** felé hat.

### 5. A reducer determinisztikus és sorrend-független

Ugyanaz az evidence-halmaz ugyanazt a becslést adja; a reducer rendez, mielőtt
súlyoz. Lebegőpontos összegzésnél a sorrend-függés észrevétlen, de az
ADR 0255 §1 reprodukálhatóságát rontja el.

## Következmények

- A tervező három megkülönböztethető állapotot lát: `unknown`, alacsony
  bizonyossággal becsült, magas bizonyossággal becsült — és mindhármat
  másképp kezelheti.
- Az „ismeretlen" készség felderítő gyakorlatot hív (mérés), nem intenzív
  drillt.
- Az elévült evidence (ADR 0260 §5) a tárolóban marad, így a „nincs adat" és
  a „régi adat" megkülönböztethető.

## Mérce

Az `E07-R06` §6.1 mérce-mátrixa, benne az evidence-mennyiség három kötelező
cellájával (nincs adat → `unknown` / **pontosan egy** → érték magas
bizonytalansággal, a cap alatt / sok konzisztens → alacsony bizonytalanság) és
a valódi-sértés próbával: az `unknown` ágat `0.0`-ra cserélve az **A5**
cellának pirosnak kell lennie.
