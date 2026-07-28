# ADR 0004 — Inkrementális refaktor, körönkénti végrehajtás

**Státusz:** elfogadva (E01-R01, 2026-07-28)

## Döntés

A fejlesztés kizárólag kis, önállóan review-zható és visszaállítható
SDD-körökben történik (egy session = egy kör; a kör végén megállás).
Nincs "rewrite from scratch"; contract+teszt → adapter → fogyasztók sorrend;
minden migráció után a teljes tesztcsomag zöld marad.

## Kontextus

R-020 kockázat: egyetlen fejlesztő + agens nem tud nagy programot követni
scope-fegyelem nélkül. A 204 korábbi kör bizonyította a kis-kör modellt.

## Git-megjegyzés (nyitott P1 döntés)

A terv branch-per-round + PR + védett main modellt ír elő (docs/execution/05).
Amíg a user nem dönt a workflow-váltásról, az elfogadott minimum a Ch2 §5.2
szerinti "külön, önálló commit" a main-en, HANDOFF + git-note kísérettel.
