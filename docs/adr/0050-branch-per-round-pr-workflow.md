# ADR 0050 — Branch-per-round és PR workflow

**Státusz:** elfogadva (user döntés, 2026-07-28; E01-R01b).
Felváltja az ADR 0004 „Git-megjegyzés (nyitott P1 döntés)" szakaszát.

> **ADR-számozás:** a terv fenntartja a 0005–0007 (Epic 2, `docs/sdd/03` Kör 1)
> és a 0010–0011 (Epic 10, `docs/sdd/11`) számokat a saját ADR-jeinek — ezért a
> boxon született **folyamat-ADR-ek a 0050+ sávot** használják, a terv-fenntartott
> számok érintetlenül maradnak.

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
   része: önálló SDD-kör tárgya (a Ch12 branch-protection köre — jelenleg RTM
   `INT-R04`; a Ch12 fejezet-szöveg Kör 3-ba vonja össze, végrehajtáskor a
   fejezet-szöveg az irányadó), és feltétele, hogy a token Administration jogot
   kapjon. Addig a védett main **konvenció**, nem kikényszerített szabály.
3. **A döntés előtti commitok** (≤ r207) a `main`-en maradnak; a történetet
   visszamenőleg nem írjuk át.
4. **A `.github/pull_request_template.md`** a Ch12 Kör 3 (RTM `INT-R03`)
   scope-jából **előrehozott szelet** — a PR-workflow napi használatához kell már
   most. A kisbetűs útvonal a terv kanonikus útvonala; amikor a manifest
   kanonikus sablonja megérkezik / az INT-R03 kör lefut, a kettőt ott kell
   egyeztetni.

## Következmények

- ~~A box jelenlegi PAT-ja `git push`-ra 403-at ad~~ — **Feloldva 2026-07-29:**
  a user új fine-grained PAT-ot adott **Contents + Workflows + Pull requests:
  Read+write** jogokkal; a push, a PR-nyitás és a merge a boxról (és a
  megosztott credential store révén a telefonos sessionből is) működik.
- A HANDOFF és a traceability frissítése a PR része — a 05 „Tilos merge-elni"
  listája szerint frissítetlen HANDOFF mellett nem mehet be a változás.
- A `main` marad a release-alap; a release- és hotfix-ágakra a 05 külön
  szabályai érvényesek.
