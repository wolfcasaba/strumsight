# ADR 0342 — Monoton szintgörbe és teljesen újraépíthető profil-projekció

- **Státusz:** elfogadva (E08-R07 pre-flight)
- **Dátum:** 2026-08-20
- **Kör:** `E08-R07` (Chapter 9, Kör 7)
- **Kapcsolódó:** [`0289`](0289-mastery-is-evidence-not-xp.md), [`0301`](0301-reward-ledger-append-only-idempotency.md), [`0341`](0341-explainable-xp-policy-and-diminishing-returns.md)

## Kontextus

Az R03 egy append-only reward ledgert ad, lapozottan olvasható felülettel
(`readPage({limit, cursor})`). Az R06 policy minden jutalmat egy verziózott,
öt-komponensű `ExperiencePoints` receiptté számol, amit a ledger
`baseXp`/`bonusXp`/`totalXp` mezőkre tömörít. A gamification rétegnek
szüksége van egy szintrendszerre és egy felhasználói profil-pillanatképre,
ami ebből a főkönyvből számolható, anélkül hogy második igazságforrást
hozna létre, vagy — a legkézenfekvőbb gamifikációs csapdaként — a szintet
tartalom-kapuvá tenné ([`ADR 0289`](0289-mastery-is-evidence-not-xp.md): az
XP a részvételt méri, nem a tudást).

## Döntés

1. **A szintküszöbök egyetlen `LevelCurve` definícióból származnak.** Nincs
   szórt küszöb feature-önként vagy UI-ba égetve; a görbe monoton növekvő,
   és egy adott XP-összeghez tartozó küszöb a **magasabb** szinthez tartozik
   (a határ inkluzív alsó korlát: `xp == threshold` már az új szint).
2. **A szint soha nem csökkenhet.** A projekció a valaha elért legmagasabb
   szintet tartja meg, akkor is, ha egy újraszámítás — például egy jövőbeli
   policy-verzióváltás más súlyokkal — alacsonyabb eredményt adna ugyanarra
   az XP-történetre. A felhasználótól elvett szint a termék legláthatóbb,
   legvisszafordíthatatlanabb bizalomvesztése; ezt semmilyen belső
   „korrektség" nem indokolja.
3. **A `GamificationProfile` verziózott (`schemaVersion`) pillanatkép, nem
   önálló igazságforrás.** A ledgerből (lapozott olvasással) TELJES
   EGÉSZÉBEN, determinisztikusan újraépíthető. Az inkrementális projekció —
   egy új ledger-bejegyzés alapján számolt gyorsítás — az eredményében
   azonos kell legyen a teljes újraépítéssel; eltérés esetén az inkrementális
   ág a hibás.
4. **Túlcsordulás-védelem és többszörös szintlépés.** Nagyon nagy
   XP-összegnél a görbe nem csordulhat túl és nem adhat negatív szintet
   (felső szaturáció). Egyetlen esemény több szintet is átléptethet; a
   projekció ilyenkor az ÖSSZES átlépett szintet visszaadja a kimenetében,
   nem csak a végállapotot — ez a bemenete a Kör 22 level-up
   celebrationjének.
5. **A szint és a profil kimenete soha nem hordoz tartalom-feloldási
   jelentést.** Sem a `LevelDefinition`, sem a `GamificationProfile` nem ad
   `unlock`/`unlockedContent`-jellegű mezőt. A tartalom-feloldás mért
   teljesítményhez köthető (Kör 21, mastery), az XP-szinthez soha
   ([`ADR 0289`](0289-mastery-is-evidence-not-xp.md)).

## Következmények

**Pozitív.** A szint és a profil egyetlen, auditálható számításból
származik; egy balance-hangolás (Kör 29 szimuláció) a görbe egyetlen
definícióját módosítja, és a meglévő felhasználók szintje soha nem esik
vissza. A profil bármikor eldobható és újraszámolható — nincs migrációs
kockázat a projekció belső alakjában.

**Negatív / ár.** A monoton „soha nem csökken" szabály azt jelenti, hogy egy
jövőbeli balance-hiba (túl nagy XP-jutalom) tartósan magas szintet fagyaszt
be, amíg a policy-hibát ki nem javítják — a hiba tünete a szinten marad, még
ha a jövőbeli számítás korrigál is. Ezt tudatosan vállaljuk a lefelé
számolás visszafordíthatatlan bizalomvesztésével szemben.

**Amit ez a döntés TILT.** A szint lefelé újraszámítását bármilyen belső ok
miatt; a profil önálló, ledger-megkerülő írását; a szintküszöbök feature-önkénti
duplikálását; bármilyen `unlock`-jellegű mező felvételét a szint- vagy
profil-kimenetbe.

## Elutasított alternatívák

- **Lefelé újraszámítás balance-váltás után** — elutasítva: visszafordíthatatlan
  bizalomvesztés, és nincs olyan belső „korrektség", ami ezt indokolná (§2).
- **A profil önálló írása/mutálása a ledger megkerülésével** — elutasítva: két
  igazságforrás lenne, és az első eltérésnél eldönthetetlen, melyik a helyes.
- **Szórt küszöbök (UI-ba vagy több helyre égetve)** — elutasítva: mérhetetlenné
  tenné a Kör 29 balance-szimulációját.
- **`unlockedContent`-jellegű kényelmi mező a projekció kimenetében** — elutasítva:
  az ADR 0289 kifejezett tilalma, még akkor is, ha csak informatív célú lenne.
- **Csak a végállapot visszaadása többszörös szintlépéskor** — elutasítva: a Kör 22
  celebrationja minden átlépett szintet meg kell tudjon jeleníteni.
