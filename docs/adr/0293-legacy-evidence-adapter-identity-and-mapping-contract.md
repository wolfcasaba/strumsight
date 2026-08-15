# ADR 0293 — Legacy evidence adapterek explicit identity- és mapping-contractja

**Státusz:** elfogadva (2026-08-15). Forrás: E07-R07, SDD Ch8 Kör 7.
Épít: [ADR 0255](0255-deterministic-first-practice-planning.md),
[ADR 0260](0260-skill-evidence-privacy-and-deduplication.md) és
[ADR 0261](0261-skill-estimate-bounded-influence-and-unknown-state.md).

## Kontextus

A Learn publikus `Lesson` modellje lecke-azonosítót és difficulty-t ad, de nem
skill-tageket vagy eredmény-azonosítót. A Progress publikus `PracticeEntry`
aktív időt (`seconds`) és forrást (`source`) hordoz, de nincs saját stabil
outcome-ID-ja, pontos időbélyege vagy skill-kapcsolata. Az ADR 0260 szerint az
evidence deduplikációjának a forrás outcome-ID-ján kell alapulnia; azt
időből, iterációs sorrendből vagy tartalom-hashből előállítani nem megengedett.

## Döntés

1. A legacy adapterek kizárólag a másik feature `public.dart` contractját
   importálják.
2. A skill hozzárendelése kizárólag a verziózott, explicit mapping-táblából
   történhet. Lesson név, akkord, difficulty vagy Progress forrás alapján nem
   következtethető skill.
3. Minden evidence-et létrehozó adapter-bemenetnek hívó által adott, stabil
   `OutcomeId`, cél skill ID, `measuredAt` és `capturedAt` értéket kell
   hordoznia. A hiányos bemenet figyelmeztetéssel kimarad; nem dob és nem
   gyárt helyettesítő identitást.
4. A mapping tábla pozitív verziója a meglévő `SkillEvidence.measurementVersion`
   provenance mezőbe kerül. Új, párhuzamos provenance-mező nem szükséges.
5. A `PracticeEntry.seconds` aktivitási mennyiség, nem normalizált
   teljesítmény. A Progress adapter teljesítményt csak hívó által adott,
   ellenőrzött `[0,1]` értékből képezhet; időből nem kalibrálhat score-t.

## Következmények

- A meglévő domain nem igazodik a legacy tárolási hiányaihoz.
- A progressz-adapter egy explicit wrapperrel használható, amikor a hívó
  valóban ismeri az eredmény identitását és skill-kapcsolatát.
- Az azonosítatlan vagy nem leképezett legacy rekordok nem szennyezik a
  skill-estimate-et hamis, biztosnak látszó evidence-szel.

## Mérce

Az E07-R07 A1–A8 cellái: nincs heurisztikus mapping, a mapping-verzió a
`measurementVersion`, a kimenet legacy `source`, sorrendfüggetlen dedup és
identity/skill/normalizált érték nélküli Progress rekord kihagyása.
