# ADR 0280 — Accessibility-szerződés és élő régió költségvetés

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R14` (Chapter 13, Kör 14)
- **Kapcsolódó:** [`0277`](0277-failure-presentation-model.md),
  [`0278`](0278-ai-provenance-is-visible.md)

## Kontextus

Az `E13-R03`-tól minden komponens-kör tartalmazott accessibility-szabályt
(nem-csak-szín, semantics label, érintési cél, csökkentett mozgás). Szétszórva
ezek betarthatók, de nem **kikényszerítettek**: az első sietős kör lazít rajtuk.

Külön probléma a StrumSight fő használati módja. A felismerés másodpercenként
sokszor frissül. A naiv élő régió (minden változás bejelentése) ebből
folyamatos beszédet csinál — a képernyőolvasót használó felhasználónak a Stage
Mode így **használhatatlan**, miközben minden egyes bejelentés önmagában
„helyes".

## Döntés

1. A design system accessibility-szabályai **egyetlen gépi szerződésbe**
   kerülnek (heading, élő régió, mérőszám, akkord, strum, beat, tuner,
   diagram-összegzés), és tesztek kényszerítik ki őket.
2. Az élő régiónak **bejelentés-költségvetése** van: érdemi változásnál szólal
   meg, és két bejelentés között minimális szünet van (a kör mérce-mátrixában
   **1000 ms**, a határ inkluzív). A sűrűbb változások összevonódnak.
3. A **tuner cents-eltérése és a strum-irány felolvasható szövegként** — nem
   elég vizuálisan jelezni.
4. Nincs csak színnel közölt siker, hiba vagy confidence (az ADR 0278 §2
   kikényszerítése).
5. A kritikus komponensek érintési célja **≥ 48 dp**.
6. **Az automatizált teszt nem elégséges bizonyíték.** A `docs/ui/accessibility.md`
   kimondja, hogy a TalkBack/VoiceOver ellenőrzőlista kézi lépés marad — a
   semantics-teszt nem hallja, amit a felolvasó mond.

## Következmények

**Pozitív.** A szabályok egy helyen mérhetők, és minden későbbi kör örökli
őket. A Stage Mode felolvasóval is használható marad.

**Negatív / ár.** A költségvetés késlelteti a bejelentést, tehát a felolvasót
használó felhasználó nem kap minden egyes felismerést — cserébe kap
értelmezhető beszédet.

**Amit ez a döntés TILT.** Minden felismerési kereten kimondott akkordnevet;
csak vizuális tuner-visszajelzést; a gépi zöld „bizonyítékként" való
felmutatását a kézi próba helyett.
