# ADR 0374 — Achievement domain- és katalógusszerződés

- **Státusz:** elfogadva (E08-R13 pre-flight)
- **Dátum:** 2026-08-20
- **Kör:** `E08-R13` — Achievement domain és katalógus
- **Kapcsolódó:** [`0289`](0289-mastery-is-evidence-not-xp.md),
  [`0328`](0328-measured-gamification-baseline-contract.md),
  [`0329`](0329-canonical-activity-event-contracts.md),
  [`0341`](0341-explainable-xp-policy-and-diminishing-returns.md),
  [`0344`](0344-gamification-storage-schema-versioned-documents-and-layer-purity.md)

> **Számozási megjegyzés:** az előre írt brief `0310`-et nevezett meg, de az
> atomi marker `.pipeline/inflight/adr/0310` ma `round=E99-R14` tulajdonú.
> A kötelező `tools/round-slots.py reserve-adr --round E08-R13` futás ezért
> `0374`-et adott. A foglaló mért eredménye az irányadó.

## Kontextus

Az R02 hat kanonikus tanulási eseményt szállított stabil `typeCode`-dal
(`practice`, `song`, `analysis`, `plan`, `tutor`, `vision`), közös
`duration` és `score` mezővel. Az R06 receipt öt önálló XP-komponenst
(`baseXp`, `durationXp`, `qualityXp`, `improvementXp`, `diversityXp`) és ezek
származtatott `totalXp` összegét adja. A mai inputban nincs `songId`,
`skillId` vagy technikaazonosító, ezért ilyen adatot az achievement-domain
nem találhat ki.

Az achievement ID később tartós profil- és ledger-hivatkozás lesz. A
katalógus egyszerre content és végrehajtható domain-konfiguráció: hibás ID,
ismeretlen objective, tier-kör vagy hiányzó fordítás felhasználói haladást
veszíthet vagy a következő kör kiértékelőjét hibás állapotba viheti.

## Döntés

1. **Stabil, contenttől független ID.** Az achievement `id` explicit,
   lower-snake-case kód, nem lokalizált címből vagy sorszámból képzett érték.
   Egy kiadott ID nem nevezhető át és nem használható újra más jelentéssel.

2. **Zárt, típusos objective-vokabulár.** A sealed objective-hierarchia öt
   támogatott alakja `count`, `threshold`, `distinct`, `sequence` és
   `compound`. Eseményhivatkozása csak az R02 hat fajtája lehet. Numerikus
   metrikája `eventCount`, `durationSeconds`, `score`, `baseXp`, `durationXp`,
   `qualityXp`, `improvementXp`, `diversityXp` vagy `totalXp`; a distinct
   objektív ma kizárólag `activitySource` szerint különböztethet. Fantom
   `songId`/`skillId`/technique mező tilos.

3. **Forward-compatibility fail-closed.** A sealed hierarchia része egy
   explicit `UnknownAchievementObjective`, amely egy ismeretlen stabil
   type-kódot őriz meg, de a katalógus-validáció mindig hibának tekinti.
   Ezzel az ismeretlen objektív tesztelhető anélkül, hogy szabad szöveges
   expression vagy nyitott subclass-határ kerülne a domainbe.

4. **Körmentes tier-gráf.** A definíció explicit előfeltétel-ID-ket hordoz.
   A validáció elutasítja az önélt, a hiányzó előfeltételt és minden közvetett
   kört. A validátor nem javítja és nem hagyja figyelmen kívül a hibás élt.

5. **Lokalizációs kulcsok, nem emberi szöveg.** A definíció külön
   `titleKey`, `descriptionKey` és rövid, felolvasható
   `accessibilityDescriptionKey` mezőt hordoz. A validáció mindhárom kulcsot
   mindkét átadott locale-készletben megköveteli. A shipping katalógusban
   egyik mező sem lehet természetes nyelvű cím vagy leírás.

6. **Verziózott, additív content lifecycle.** A katalógus pozitív
   `contentVersion`-t hordoz. Korábbi katalógussal összevetve elemszám-változás
   csak nagyobb content-verzióval fogadható el. Kiadott achievement nem
   törlődik: `deprecated` és opcionális kivezetési verzió jelöli, miközben az
   ID és a definíció a katalógusban marad.

7. **Immutable domain és explicit validációs eredmény.** A definíciók,
   objective-ek, progress és katalógus tiszta Dart értékek; a kapott
   listák/készletek nem maradhatnak kívülről módosíthatók. A validáció minden
   leletet típusos/stabil kóddal ad vissza, és bármely lelet mellett a
   katalógus nem tekinthető használhatónak. Fájl-I/O és ARB-olvasás nem kerül
   a domainbe; a teszt/összeállító adja át a locale-kulcskészleteket.

8. **A progress még nem értékelő.** Az `AchievementProgress` verziózott,
   monoton állapotot, opcionális completion timestampet és ledger-hivatkozást
   modellezhet, de eseményfeldolgozást, órát, tárolást vagy jutalomírást nem
   végez. Ezek az E08-R14 határai.

## Következmények

Az E08-R14 determinisztikusan indexelhet eseményfajta és metrika szerint,
miközben az R13 nem módosítja a lezárt R02/R06 szerződéseket. A distinct
achievementek első kiadása szűkebb a termékvíziónál: külön dalhoz vagy
skillhez kötött cél csak akkor adható hozzá, ha egy későbbi, külön kör
kanonikus, bizonyított azonosítót vezet be.

A kivezetett content a katalógust növeli és lokalizációs költséget tart fenn;
ez a megszerzett eredmények megőrzésének tudatos ára.

## Mérce

Az E08-R13 brief §6/§6.1 cellái: 20–30 elem inkluzívan; explicit unknown
objective elutasítása; valódi A→B→A kör piros; mindhárom localization-key
mindkét locale-ban; deprecated elem megmarad; elemszám-változás csak növelt
`contentVersion` mellett; kötelező accessibility-kulcs. A reviewer a
tier-ciklus őrét eldobható mutációval rontja és visszaállítja.
