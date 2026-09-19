# ADR 0544 — Az akkord-pillér, és hogy egy készség MILYEN mérésből van

- **Státusz:** elfogadva
- **Dátum:** 2026-09-12
- **Kör:** E18-R15
- **Kapcsolódó:** ADR 0543 (a kör-eredmény evidenciává válik), ADR 0260,
  `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §2, §3

## Kontextus

Az R13 és R14 után a létra haladt és olvasható volt, de csak **két** rungot lehetett
kiérdemelni. Minden akkord-rungnak (`mission.eMinor`, `mission.aMinor`,
`mission.emToAm`, és a négy további akkord és három váltás) **nem volt gyakorlata**:
ott álltak a létrán, és bármilyen jól játszott bárki, soha nem nyíltak meg — tehát a
`mission.dDuUdU` és minden fölötte lévő rung **elérhetetlen** volt. A létra olyan út
térképe volt, ami két lépés után megszakad.

Egy akkord-rung megmérhetőségének azonban előfeltétele, hogy az akkord-felismerés
valóban működjön. Ez **mérve** van, és a mérést ez a kör újra lefuttatta
(`chord_recognition_modelled_audio_test.dart`): **7/7**, akkordonként pontosan,
43 képkockából 30–36 megerősítve, és mindkét pengetési irány ugyanazt a nevet adja.
A kampány korábbi defektje (G → Bm, D soha nem konfirmál) megszűnt. A hét természetes
dúr valódi gitáron is 7/7 (`live_chord_wav_probe_test.dart`). **Kimondva: az Em és Am
valódi-gitár megerősítése továbbra is hiányzik** — erre a gépen nincs címkézett
felvétel —, tehát a két első akkordra a bizonyíték modellezett audio.

## Döntés

### D1 — A mérési egység a TAKTUS, nem a pengetés

Egy akkord **tartott**, nem ütött. A dekódernek több képkocka kell egy csengő
alakzatból (30–36 a 43-ból), tehát a „melyik akkord volt megerősítve ennek a
pengetésnek a pillanatában" kérdés a **dekóder saját latenciáját** mérné, nem a
tanuló ujjait. A taktus az az egység, amire az akkordot kérik — a ciklus taktusonként
változik —, tehát a taktus az, amit osztályozunk.

A taktus ablaka **nincs** toleranciával kiszélesítve, ellentétben egy pengetés
onset-ablakával. Egy pengetés pillanat, ami lehet korai vagy késő; egy akkord a
taktuson át tartott, és az előző taktusból származó észlelés az **előző** akkordról
szóló evidencia. Az ablak kiszélesítése pontosan az, amivel egy váltást soha meg nem
tévő tanuló mindkét taktusra kreditet kapna.

### D2 — Ez attól is a VÁLTÁS mérése

Egy váltás-rung taktusonként alternál (`chord.emToAm` → Em, Am, Em, Am). Mindkét
taktus nem kapható meg anélkül, hogy a tanuló váltott volna. **Mérve:** Em-et tartva
végig egy Em/Am rungon a szint **0.500** — a kurzus 0.6-os kapuja alatt, tehát nem
nyit semmit.

Kimondva, amit NEM mér: azt, hogy a váltás a **taktusvonalra** esett-e. A rung
folytonossági tanítását (a pengető kéz ne álljon meg) ugyanannak a futásnak az
irány-mérése mutatja és osztályozza; a „a váltás N ms-on belül megérkezett"
önálló mérés, amit itt semmi nem állít.

### D3 — Egy készség csak abból a mérésből kap kreditet, AMIBŐL VAN

Egy futás két mérést termel: irányt és (ha a mód akkordot pontoz) akkordot. A
kézenfekvő bekötés mindkettőt beírja a rung minden tanított készségéhez — és akkor a
`mission.eMinor` akkord-készsége egy **irány-pontosságból** kapna kreditet, ami
semmit nem mond arról, hogy a tanuló ujjai a jó bundokon voltak-e. **Egy jó mezőben
lévő, rossz dolgot mérő szám rosszabb, mint a semmi, mert utána semmi nem tudja
megállapítani.**

Ezért a `skill_metrics.dart` osztályoz: `rhythm.*` és `strumPattern.*` →
`strumDirection`, `chord.*` → `chordShape`, minden más → `notMeasuredHere` (és
`notMeasuredHere` **nem** kitöltendő hely a legközelebbi elérhető számmal: ott a
készség semmilyen evidenciát nem szerez). A ritmus-fordító csak az irány-, az
akkord-fordító csak az akkord-készségeket írja, saját metrikakóddal
(`rhythm.directionAccuracy`, illetve `chord.shapeAccuracy`) és saját dedup-kulccsal —
közös kulcs mellett a másodikként írt rekord törölte volna az elsőt.

### D4 — Minden akkord-rung kap gyakorlatot, és ezért irány-pontozást is kér

Az app csak olyan akkordot tud hallani, amit épp játszanak, tehát valaminek meg kell
mondania, **mikor** kell játszani. A legegyszerűbb ilyen dolog az a gyakorlat, amit a
tanuló a 2. rungon már teljesített: negyedeken lefelé pengetés, tartott alakzat fölött
(`withChord`, nem fojtott — egy fojtott húrnak nincs megnevezhető akkordja). Így egy
akkord-rung **pontosan egy** új elhibázható dolgot ad, ami a kurzus saját sorrendi
alapelve.

Következmény: **nincs többé csak-akkord képességkészlet.** Minden akkord-rung
pengetett rács fölött fut, tehát mindegyik valóban igényel irány-pontozást is, és
kevesebbet állítani azt állítaná, hogy a gyakorlat nem pengettet.

### D5 — A dal-rung TELJESÍTÉS-rung, nem pontozott — ezt egy guard találta meg

A `mission.twoChordSong` `accuracyThreshold`-ot deklarált 0.6-os céllal, miközben
ebben az appban **nincs dal-előadás mérés**. A rung tehát azt mondta, „erre pontozni
fogok", majd semmit nem pontozott. Az új `skill_metrics_test.dart` találta meg: egy
mért rung, aminek a saját gyakorlata nem tudja előállítani a mérést, amiből a
készsége van.

A kurzus saját 7. szabálya írja elő a javítást a pontszám kitalálása helyett: akinek
nincs mit mérnie, az **őszinte** erről. A rung tehát nem tanít készséget, nem állít
mérést, és mikrofont sem kér — nem hallgatunk semmit. A helyét a létrán megtartja,
mert a célja soha nem a pontszám volt: igazi zene, amint két akkord megvan,
dokumentált lemorzsolódás-ellenszer, és akkor is működik, ha egy gép nem osztályozza.

A `songPerformance.twoChord` készség-azonosító **megszűnt**: egy azonosító, amit
semmi nem tanít és semmi nem mér, olyan állítás, ami mögött nincs semmi. Visszatér,
amikor a mérés megjön.

## A kör fő mérése

`curriculum_progress_test.dart` → „a learner who plays every rung cleanly reaches the
top", a szállított kurzussal, a valódi értékelőkkel, reducerrel és policyval:

```
LADDER WALK: 14/14 rungs opened in 24 attempts over 24 days
chord.eMinor after 2 clean attempts: emerging, level 0.750
Em held through an Em/Am change rung, 6 attempts: stable, level 0.500
```

**14/14 rung.** A létra végigjárható — ez volt hamis a kör előtt, és nem
feltételezésből tudjuk. Egy akkord-rung ugyanazzal a két tiszta körrel nyit, mint egy
ritmus-rung (az `emerging`/0.6 kapu nem akkord-specifikus), és a váltást meg nem tevő
tanuló 0.500-on marad.

## Következmények

- `RhythmMode.withChord` akkord-pontozó rungok ciklusát a `mission_chords.dart`
  vezeti le a tanított készségből, nem az assignmentből — az assignment
  szándékosan nem nevez akkordot, és két otthon közül a nem egyező lenne az, ami
  alapján a tanulót pontozzák.
- `mission_chords_test.dart` minden kérhető címkét a szállított ujjrendekhez ÉS a
  dekóder szótárához mér, és csak sima dúr/moll hármast engedélyez — a kurzus
  korábbi mérése szerint a `G6` nincs a szótárban (`G`-nek olvas), a `Cmaj7` pedig
  32 képkockából 24-en nem konfirmál.
- Az akkord-eredmény a képernyőn **külön** sor, soha nem összeolvasztva az iránnyal:
  akinek az alakzata tiszta de a keze megáll, és akinek a keze egyenletes de az ujjai
  tévednek, **ellentétes** tanácsot kíván, és egy szám elrejtené, melyik ő.
- Az akkord-észlelés a képkocka saját motor-idejével van elhelyezve, nem egy mért
  valódi onsettel (olyan nincs egy döntésre), tehát a dekóder lagját hordozza. A
  taktus-szintű osztályozás az, ami ezt elfogadhatóvá teszi: egy taktus 3,4 s ezen a
  tempón, és bárhol a taktusban lévő megerősítés kreditálja a taktust.
