# ADR 0255 — A gyakorlóterv determinisztikus; a modell javasol, nem hajt végre

**Státusz:** elfogadva (2026-08-15, user-döntés: *„folytassuk a fejlesztést …
indítsd az Epic 7-et"*). Az Epic 7 (AI Practice Generator) nyitó döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md)
§2.2 („A generátor nem autonóm tanár"), §2.3 („Deterministic-first"),
§2.4 („Offline-first").
Épít: [ADR 0087](0087-autonomous-round-pipeline.md) (kör-pipeline).

## Kontextus

Az Epic 7 gyakorlóterveket állít elő a tanuló céljai, elérhető ideje, a
Learn/Progress/Streak előzményei és — ahol van — az elemzési bizonyítékok
alapján. A kézenfekvő megvalósítás az lenne, hogy egy nyelvi modell írja meg a
tervet. Ez három okból elfogadhatatlan ebben a termékben:

1. **Offline-first.** A StrumSight detektálása 100%-ban eszközön fut, és az
   app kijelentkezve is teljes értékű. Egy modell-függő tervező ezt elrontaná.
2. **Kiszámíthatóság.** A gyakorlóterv a felhasználó idejét osztja be. Egy
   nem determinisztikus terv nem reprodukálható, nem tesztelhető, és nem
   magyarázható meg neki.
3. **Bizonyíthatóság.** A projekt mércéje a futtatható artefaktum. Egy
   modell kimenetére nem lehet olyan invariánst írni, amit a CI kapuz.

## Döntés

### 1. A terv előállítása determinisztikus

A tervező egy tiszta, bemenet→kimenet függvény: adott célok, elérhető idő,
katalógus és előzmény mellett **ugyanaz a bemenet ugyanazt a tervet adja**.
Nincs benne véletlen, óra-olvasás vagy hálózati hívás — az idő és az
azonosítók injektáltak (`Clock`, `IdGenerator`).

### 2. A modell JAVASOL, nem hajt végre

A modell kimenete **soha nem közvetlenül végrehajtható terv**. A javaslat egy
külön, validált csatornán érkezik, és a determinisztikus tervező **fogadja
el vagy utasítja el** — a végrehajtott terv mindig a validátoron átment,
determinisztikus artefaktum.

*A tiltás konkrétan:* nincs olyan út, amelyen egy modell-válasz mezői
közvetlenül a végrehajtott terv mezőivé válnak.

### 3. Két külön feature flag

- `practiceGeneratorEnabled` — maga a funkció elérhetősége;
- `plannerAssistEnabled` — a **modell-segített** javaslat elérhetősége.

Egyetlen közös flag elrejtené, hogy a determinisztikus út önmagában is
élesíthető. A kettő szétválasztása teszi mérhetővé az 1. döntést: a
generátornak `plannerAssistEnabled = false` mellett **teljes értékűen kell
működnie**.

### 4. Mindkét flag alapértelmezetten OFF, minden környezetben

Nem csak productionben. A rollout — mindkettőé, külön-külön — önálló emberi
döntés, ahogy az Epic 5 és 6 esetében is.

## Következmények

- A generátor domainje Flutter- és hálózat-független marad, tehát
  egységtesztelhető és a CI-ban kapuzható.
- A modell-segítség **opcionális réteg**, nem alap. Ha soha nem élesedik, a
  termék akkor is működik.
- A tervező kimenete magyarázható: minden blokk visszavezethető a bemeneti
  célra és a katalógus-elemre.
- A `plannerAssistEnabled` rollout **külön** kockázati profilú döntés
  (adatvédelem, költség, hálózat) — nem csúszhat be a funkció-rollouttal.

## Mérce

Az `E07-R01` §6.1 mérce-mátrixa méri a két flag szétválasztását és a
`false` alapértelmezést mindhárom környezeti cellán. A determinisztikusság
invariánsát a Kör 2-től épülő domain-tesztek mérik (ugyanaz a bemenet →
ugyanaz a terv), a modell-út tiltását pedig a validátor-kör.
