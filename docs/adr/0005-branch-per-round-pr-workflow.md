# ADR 0005 — Branch-per-round és PR workflow

**Státusz:** elfogadva (user döntés, 2026-07-28; E01-R01b).
Felváltja az ADR 0004 „Git-megjegyzés (nyitott P1 döntés)" szakaszát.

## Döntés

Az E01-R02 körtől kezdve minden SDD-kör saját branchen fut és PR-ként záródik:

- branch: `codex/e<epic>-r<round>-<slug>`
  (pl. `codex/e01-r02-project-identifiers`);
- egy kör = egy PR, a PR címe `[E01-R02] <imperative summary>`;
- a PR-leírás a `docs/execution/05-branch-and-pr-rules.md` „Kötelező PR
  tartalom" pontjait követi (SDD requirement és kör, cél és nem-cél, fő
  változások, migration/API hatás, tesztek pontos parancsokkal, device- és
  performance-evidence, privacy/security hatás, rollback, follow-up);
- merge: squash, kizárólag zöld required CI mellett;
- a commitok Conventional Commit formátumúak.

## Kontextus

A terv branch-per-round + PR + védett main modellt ír elő
(`docs/execution/05-branch-and-pr-rules.md`). A r207-ig (E01-R01) az autonóm
körök közvetlenül a `main`-re commitoltak — ez volt a kodifikált status quo,
amíg a user nem döntött a workflow-váltásról. A user 2026-07-28-án a terv
szerinti PR-workflow mellett döntött.

## Szóló-fejlesztői adaptációk (explicit eltérés a tervtől)

1. **A „legalább 1 review" szabály** (05 „Main protection") egyszemélyes
   projektben nem teljesíthető betű szerint: helyette az ügynöki second-eye
   review kötelező a PR előtt (`flutter-reviewer` + `flutter-devil-advocate`),
   a user pedig igény szerint review-zik. Az „unresolved blocking review-val
   tilos merge-elni" szabály változatlanul él.
2. **A GitHub branch-protection formális beállítása** (direct push tiltása,
   required check, merge queue, force-push korlátozás) NEM ennek a döntésnek a
   része: önálló SDD-kör tárgya (RTM `INT-R04` — Chapter 12, branch protection,
   CODEOWNERS és merge policy), és feltétele, hogy a token Administration jogot
   kapjon. Addig a védett main **konvenció**, nem kikényszerített szabály.
3. **A döntés előtti commitok** (≤ r207) a `main`-en maradnak; a történetet
   visszamenőleg nem írjuk át.

## Következmények

- A box jelenlegi PAT-ja `git push`-ra 403-at ad. Amíg a user nem ad
  fine-grained PAT-ot **Contents: Read+write**, **Workflows: Read+write** és
  **Pull requests: Read+write** jogokkal, a körök branche és PR-je lokálisan
  készül el és **sorban áll**: a kör munkája lezárható, de a push és a PR
  nyitása a token megérkezéséig várat.
- A HANDOFF és a traceability frissítése a PR része — a 05 „Tilos merge-elni"
  listája szerint frissítetlen HANDOFF mellett nem mehet be a változás.
- A `main` marad a release-alap; a release- és hotfix-ágakra a 05 külön
  szabályai érvényesek.
