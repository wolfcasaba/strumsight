# ADR 0303 — Bounded spaced-repetition review queue contract

**Státusz:** elfogadva (E07-R17 pre-flight, 2026-08-18).
**Forrás:** [SDD Ch8 §24](../sdd/08-epic-07-ai-practice-generator.md),
[E07-R17 brief](../rounds/e07-r17-spaced-repetition.md).
**Épít:** [ADR 0255](0255-deterministic-first-practice-planning.md),
[ADR 0258](0258-hard-and-soft-planning-constraints.md) és
[ADR 0261](0261-skill-estimate-bounded-influence-and-unknown-state.md).

## Kontextus

A review queue-nak négy különböző target-típust, determinisztikus helyi dátumot,
bizonytalan eredményt, napi korlátot és katalógusból eltűnt tartalmat kell
kezelnie. A meglévő `PracticeCatalogSnapshot` csak revision-eltérést jelez, nem
mondja meg, hogy egy konkrét review target ma elérhető-e; a `LocalDate` viszont
szándékosan időzóna-semleges naptári nap.

## Döntés

1. A `ReviewTarget` saját stabil `kind + targetId` identity: chord transition,
   strumming pattern, lesson vagy song section. A deduplikáció pontosan ezen az
   identityn alapul.
2. A queue explicit aktuális target-halmazt kap. A hiányzó elem megmarad és
   `replacementRequired` jelzést kap; nem tűnik el és nem keletkezik kivétel.
3. A policy tiszta függvény: explicit `LocalDate`, előző intervallum és typed
   outcome bemenetből ad új intervallumot/due date-et. Nem olvas órát,
   időzónát vagy véletlent. `unknown` nem csökkenti az intervallumot.
4. A queue explicit napi összidőt és review-budgetet kap, ahol a review budget
   szigorúan kisebb az összidőnél. A queue legfeljebb ezt a budgetet választja;
   a heti scheduler arány-policyját nem implementálja újra.

## Következmények

- A domain deterministic, Flutter- és storage-független marad.
- A hívó dönt a helyettesítésről; a queue csak látható, typed jelzést ad.
- A napi karbantartás nem szoríthatja ki a fejlődési blokkot.

## Mérce

Az E07-R17 A1--A8 tesztjei bizonyítják a szigorú budgetet, a typed outcome
lépcsőket, az `unknown` változatlanságát, a helyi dátum determinizmusát, a
törölt target jelzését és a target-identity deduplikációját.
