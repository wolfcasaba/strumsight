# ADR 0543 — A tananyag-körök készség-evidenciává válnak, és a létra ettől tud haladni

- **Státusz:** elfogadva
- **Dátum:** 2026-09-12
- **Kör:** E18-R13
- **Kapcsolódó:** ADR 0260 (normalizált készség-evidencia), ADR 0294, ADR 0482
  (perzisztens evidencia-tár), ADR 0319 / `EvidenceSource`,
  `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §2, §4

## Kontextus

Az E18-R12 szállította a létrát (`curriculum_ladder_screen.dart`), de
**őszintén** azzal, hogy nem mutat haladást: a `missionAvailability` üres
becslés-térképet kapott, tehát minden kapuzott rung „még nem elért" maradt
örökre. A lánc minden más darabja MÁR létezett — a perzisztens
`LocalPracticeEvidenceRepository` (ADR 0482), a `SkillEstimateReducer`, az
`EvidenceWeightPolicy`, és a kapu (`UnlockRule.isSatisfiedBy`). Egyetlen darab
hiányzott: a **fordító** a lefokozott kör-eredmény (`RhythmAttempt`) és a
`SkillEvidence` között.

## Döntés

### D1 — A fordító egyetlen dolgot mond, és a metrikakód ezt ki is mondja

A `gradeRhythm` EGY dolgot mér: melyik irányba haladt a kéz minden notált
slotnál. Nem minősíti az akkordot, a tónust vagy a lefogást. Ezért a metrika
kódja `rhythm.directionAccuracy`, és semmi nem tesz úgy, mintha más lenne. Egy
későbbi akkord-pontozott kör SAJÁT metrikakódot és SAJÁT fordítót kap, nem
kölcsönzi ezt a számot.

### D2 — Négy visszautasítás: nincs evidencia, ami NEM alacsony pontszám

Egyik sem ír semmit: (1) nem ritmus-küldetés; (2) nem mért küldetés, vagy nem
nevez meg készséget; (3) a fedettségi padló alatt (`isReportable` hamis); (4)
semmi nem hallatszott. Ez a `SkillEstimate` `unknown` és az alacsony `level`
különválasztásának egész indoka: az „ezt nem hallottam elég jól" nem pontszám, és
alacsonyat írni belőle a csendes szobát rossz játéknak mutatná.

### D3 — A fedettség a bizalomba és a mintaszámba megy, SOSEM az értékbe

A fedettség a `confidence` és a `sampleCount`. Az értékbe folyatni azt jelentené,
hogy az „nem hallottam" össze lenne átlagolva a „rossz felé pengettél"-lel, és a
kettő ellentétes választ kíván: még egy ismétlést, illetve javítást. A §3
ugyanezt mondja a másik oldalról — egy kihagyott slot semmit nem von le.

**Mérve, és kimondva:** a szállított `EvidenceWeightPolicy` mellett a `confidence`
ma SEMMIT nem változtat. A rekordonkénti befolyás-plafon (0.25) minden olyan
körnél kötelez, ami átjutott a fedettségi padlón, tehát egy 50 %-os és egy 100 %-os
fedettségű kör **azonos szintet** ad (0.7500 mindkettő,
`curriculum_progress_test.dart`). Azért van leírva, mert a mérésről igaz, nem
azért, mert hangol — és azért van MÉRVE, hogy senki ne hitte később, hogy ez a
mező olyan munkát végez, amit nem.

### D4 — Nincs önlejárat; a fakulás mérve van, nem választva

A `validUntil` null. A policy már folytonosan diszkontál a mért 30 napos
recency-felezési idővel; egy kemény lejárati szirt ezen felül egy MÁSODIK,
kitalált bomlás lenne, és a `stale` állapotba lökné az evidenciát, amit egyetlen
kapu sem fogad el — a rung egy DÁTUMON csapódna be, nem fakulna.

A tényleges fakulás mérve (`curriculum_progress_test.dart`): két tiszta kör után
a rung +0, +30 és +60 napon NYITVA (szint 0.750 → 0.750 → 0.690), és +90 napon
zár (0.595, a kurzus 0.6-os kapuja alatt). Soha nem lesz `stale`. Hónapok
kihagyása hónapok új evidencia nélkül — és a semleges „még nem érted el"
szövegezés az, ami ezt nem büntetésként olvastatja.

### D5 — A dedup-kulcs tartalmazza a készség-azonosítót, mert tartalmaznia KELL

A `PracticeEvidenceRepository` szigorúan egy rekordot tárol
`sourceOutcomeId`-onként. Egy kör, ami két készséget tanít, közös id-vel a második
rekorddal **csendben felülírná** az elsőt — egy készség evidenciája egyszerűen
eltűnne. A meglévő `analysis_evidence_adapter` ugyanezért hordozza a skill
hintjét az id-ben. Az id a kör identitásából származik (küldetés + készség +
`measuredAt`), nem számlálóból: így egy widget-újraépítés nem szerez rungot.

### D6 — Új `EvidenceSource.curriculum`, `learn`-nel AZONOS megbízhatósággal

A `source` perzisztált proveniencia. `learn`-ként jelenteni egy rekordot, amit a
Learn feature soha nem állított elő, bármilyen későbbi auditot hamissá tenne
arról, mi járult hozzá egy becsléshez. A megbízhatóság viszont **ugyanaz a 0.8**,
és nem egy új közbülső szám: a tananyag-kör ugyanúgy vezetett gyakorlat, aminek a
feladatát az app maga adta, mint egy Learn lecke, és nincs mérés, ami szerint
MEGBÍZHATÓBB lenne — a 0.85 a `learn` és az `analyzeV2` közé beszúrva olyan
precizitás lenne, ami mögött nincs semmi. Külön `switch`-ág, hogy egy későbbi kör
a saját mérései alapján átértékelhesse a tananyag-evidenciát anélkül, hogy a
Learn-ét elmozdítaná.

### D7 — A létra a kör-SZÁMOT mutatja, nem az állapot nevét — és ezt egy mérés döntötte el

A kézenfekvő sor az állapot sima nyelven lett volna („Steady", „Solid"). **Téves,
és a `curriculum_progress_test.dart` mutatta meg:** hat kör, amelyben minden
stroke megerősítve a ROSSZ irányba haladt, `SkillEstimateState.stable`-ra
redukálódik **0.000 szinten**. A `stable` azt jelenti, hogy az evidencia
konzisztens, nem azt, hogy a játék jó — tehát a „Steady" dicséret lett volna egy
tanulónak, aki mindent visszafelé pengetett. Az állapot azt írja le, mennyit TUD
az app; csak a `level` írja le, milyen jól játszott a tanuló, és ezt a rung saját
verdiktje már hordozza. Ezért ez a sor a kör-SZÁMOT jelenti, és a megtartott két
állapotszó az a kettő, ami valóban az EVIDENCIÁRÓL szól: megöregedett, vagy a
körök nem egyeztek.

Ugyanezért nincs százalék és nincs sáv: a `level` bizalom-csillapított szám,
aminek az absztrakt értéke olyan precizitásra hívna, amivel nem rendelkezik —
a 0.625 egy tökéletes kör után a policy óvatossága, nem az, hogy a tanuló 62,5 %-ban
jó.

## Mért következmények

| Tiszta körök | Állapot | Szint | Bizonytalanság | A következő rung |
|---|---|---|---|---|
| 1 | `initial` | 0.625 | 0.750 | még nem |
| 2 | `emerging` | 0.750 | 0.500 | **NYITVA** |
| 3 | `strong` | 0.875 | 0.250 | nyitva |
| 4 | `strong` | 1.000 | 0.050 | nyitva |

**Két tiszta kör nyit rungot.** Ez nem választott szám: HÁROM policy
kölcsönhatásából adódik (a rekordonkénti plafon, az állapot-küszöbök, és a kurzus
`emerging` / 0.6 kapuja), és pedagógiailag is védhető — egy jó futás lehet
szerencse, és az `UnlockRule` doksija maga írja, hogy a kapu a bizalom, nem a
találatszám. Lepinezve, hogy egy policy-változás, ami elmozdítja, szándékos tett
legyen.

Hat rossz irányú kör: `stable`, szint **0.000** — soha nem nyit (a kapu a szintet
is kéri, nem csak az állapotot). Hat padló alatti kör: a készség `unknown` marad,
a szint `null` — **mérés nélkül**, nem rosszul mérve.

## Amit ez a kör NEM ér el, kimondva

Csak ritmus-hozzárendelést hordozó rungok játszhatók, tehát csak azok termelnek
evidenciát. A `mission.dDuUdU` a `chord.emToAm`-ra van kapuzva, amit egy
akkord-küldetés tanít, amit ez a képernyő nem tud megnyitni — az a rung tehát
egyelőre **nem kiérdemelhető**, bármilyen jól játszik a tanuló. A végig működő
lánc: `mission.downQuarters` → `mission.downUpEighths`.

A rungok és a készségek a képernyőn még a perzisztencia-azonosítójukkal jelennek
meg (`mission.downQuarters`, `rhythm.downQuarters`). Ez belső token, nem mondat —
ugyanaz a hibaosztály, amit az E18-R12 a képességeknél kijavított. A következő kör
dolga.

## Következmények

- A `CurriculumProgress` semmilyen policy-t nem birtokol: minden ítélet már
  létezett, és újra van használva, nem újra eldöntve.
- Az `estimatesFor` minden készséget megnevez, amit a kurzus tanít, az `unknown`-
  okat is: a kapu azonosan kezeli a hiányzó és az `unknown` bejegyzést, tehát a
  térkép lehet teljes anélkül, hogy bármelyik verdikt megváltozna.
- A becslések SOSEM tárolódnak, csak az evidencia: a redukció olvasáskor fut, így
  egy policy-változás a MÁR megszerzett evidenciára is érvényesül, ahelyett hogy
  a tanulónál olyan számok maradnának, amiket az app szabályai már nem adnának.
- A `tools/tests/test_e07_r25_vision_evidence_scope.py` parse-olása kommenttűrő
  lett: egy `///` doc comment két enum-érték között `AttributeError`-t dobott
  üzenet helyett. Az állítás változatlan.
