# ADR 0264 — A prioritás faktorokra bontható, a policy verziózott

**Státusz:** elfogadva (2026-08-15). Az Epic 7 rangsorolásának döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md) Ch8 Kör 12.
Épít: [ADR 0255](0255-deterministic-first-practice-planning.md)
(magyarázhatóság), [ADR 0258](0258-hard-and-soft-planning-constraints.md)
(hard korlátok), [ADR 0261](0261-skill-estimate-bounded-influence-and-unknown-state.md)
(`unknown` állapot).

## Kontextus

A prioritás-motor dönti el, mit gyakoroljon a tanuló. A legkényelmesebb
megvalósítás egyetlen pontszámot ad skillenként, és rendez. Ez három ponton
árt.

## Döntés

### 1. Az indoklás faktoronként bontható, nem utólagos szöveg

Minden prioritás mellé jár a hozzájáruló faktorok listája értékkel
(cél-illeszkedés, előfeltétel, bizonytalanság, lefedettségi adósság, fáradás,
újdonság). A felhasználónak megmutatható, **miért** ezt gyakorolja.

*A tiltás:* a pontszámból utólag generált magyarázat. Az nem magyarázat,
hanem racionalizálás — és el is térhet attól, ami valójában döntött.

### 2. Az `unknown` felmérést indokol, nem maximális hiányt

Az ADR 0261 §2 folytatása. Ha az `unknown`-t a legalacsonyabb becsléssel
egyenértékűnek vesszük, a **legmagasabb** prioritást kapja — a rendszer a soha
nem mért készséget tolná a tanuló elé, intenzív gyakorlással. A helyes válasz
egy **felmérő** jellegű, közepes prioritás.

### 3. Az elsődleges cél előnyt ad, de a biztonság felülírja

A `primary` cél emeli a kapcsolódó skillek prioritását — a kényelmetlenség/
fájdalom jelzés (ADR 0260 §2) viszont **felülírja**. A fókusz nem nyomhatja el
a biztonságot.

### 4. A hard korlát nem jelenik meg a pontszámban

Az ADR 0258 §1 megismételve a rangsorolásra: a hard korlát **szűrő**, nem
súly. Nagy negatív pontként elég jó egyéb pontszám mellett átengedné.

### 5. A holtverseny-feloldás stabil és reprodukálható

Rögzített, determinisztikus kulcs — nem `hashCode`, nem beolvasási sorrend.

### 6. A policy verziózott, és a verzió a tervbe kerül

A súlyok verziószámmal rendelkeznek, és a generált terv provenance-e rögzíti,
melyikkel készült. Enélkül egy súly-hangolás után nem lehet megkülönböztetni a
**tanuló** változását a **policy** változásától — és a rendszer fejlődése
mérhetetlenné válik.

## Következmények

- A terv-magyarázat UI-ja (Kör 21) a faktorokra épül, nem külön szöveg-generálásra.
- A policy hangolása visszamenőleg nem írja át a régi tervek értelmezését.
- A jelölt-választó (Kör 13) tiszta, hard-szűrt halmazon dolgozik.

## Mérce

Az `E07-R12` §6.1 mérce-mátrixa, benne a skill-állapot három kötelező
cellájával (ismert és erős → alacsony prioritás / **`unknown` → közepes,
felmérő** / ismert és gyenge → magas prioritás) és a valódi-sértés próbával:
az `unknown`-t `0.0` becslésként kezelve az **A2** cellának pirosnak kell lennie.
