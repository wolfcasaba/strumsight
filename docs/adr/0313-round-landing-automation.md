# ADR 0313 — Kör-landolás automatizálása: rebase-őr, konfliktus-osztályozás és kapu a kombinált állapoton

- **Státusz:** elfogadva (2026-08-18)
- **Kontextus-ADR-ek:** [`0052`](0052-green-gate.md) (zöld kapu), [`0087`](0087-autonomous-round-pipeline.md) (kör-pipeline), [`0171`](0171-parallel-round-slots.md) (merge-zár), [`0307`](0307-pipeline-throughput-program-v2.md) (áteresztő-program v2)

## 1. Probléma — mérve

A lánc kódírása párhuzamos lett (`PIPELINE_SLOTS=2`, ADR 0307 §1.3.1), a
**landolás viszont soros és kézi maradt**. Ennek két mért ára van.

**(a) A H8 a harmadik leggyakoribb halt-kódunk.** A halt-történet és a
LESSONS korpusz alapján **36 H8 előfordulás** (H3: 136, H6: 129, H8: 36,
H2: 16). A H8 definíciója: „a `main` a dispatch óta mozdult, ÉS a rebase
konfliktust ad" — vagyis minden egyes alkalommal egy önjavító ciklus indul
egy olyan feladatra, aminek a többsége mérve **mechanikus**:

- [L77](../LESSONS.md#l77) (E03-R11): a konfliktus **kizárólag** a kör saját
  briefjében (`docs/rounds/e03-r11-….md`) volt — a main-oldal frissebb
  brief-státuszt hordozott, a branch-oldal régit;
- [L82](../LESSONS.md#l82) (E03-R12): ugyanez, „brief-only rebase-konfliktus";
- [L253](../LESSONS.md#l253) (E99-R08): két függetlenül írt, funkcionálisan
  **azonos** javítás — a guard-logika magától összefésülődött, **csak a
  komment szövege** ütközött.

**(b) A CI a rebase ELŐTTI ágon fut, a merge a rebase UTÁNI állapotot viszi
be.** A kettő nem ugyanaz. Egy slotnál ez elméleti kockázat volt; kettőnél
mérve valós: a PR #312 zöld CI (`ce403a3a`) után ment `DIRTY`-be, a rebase
után keletkezett `ff01cfae` állapotot **külön futtatás nélkül** lehetett volna
mergelni. Azt a kombinációt addig senki nem mérte.

Külső megerősítés: párhuzamos ágens-PR-eken mért textuális konfliktus-arány
**19,8%** azonos ágens PR-jei között és **41,7%** eltérő ágensek között
([arXiv 2607.04697](https://arxiv.org/html/2607.04697v2)); a szerzők ezt
*alsó becslésnek* nevezik, mert a build- és szemantikai ütközéseket nem
számolják. Az iparági ellenszer a merge queue, amely a PR-t a friss `main`-re
rebase-eli és **a kombinált állapoton** futtatja a kaput
([Mergify](https://mergify.com/product/merge-queue)).

## 2. Döntés

Bevezetünk egy **landolót** (`tools/round-land.sh`), amelyen keresztül minden
kör merge-e átmegy. A landoló a merge-záron belül fut, és három dolgot tesz,
amit ma ember (vagy önjavító kör) csinál:

1. **rebase** a friss `origin/main`-re;
2. **konfliktus-osztályozás** — szűk, fail-closed engedélylista alapján;
3. **kapu a kombinált állapoton** a merge ELŐTT.

### 2.1 A konfliktus két osztálya

**MECHANIKUS** — csak a következő útvonalak, és csak ezek:

| útvonal | feloldás | indoklás |
|---|---|---|
| `HANDOFF.md` | unió (mindkét oldal új szakasza megmarad) | append-only napló; L77 |
| `docs/LESSONS.md` | unió | append-only korpusz |
| `docs/rounds/<a kör saját briefje>` | **a `main` oldala nyer** | L77/L82 mért elve: a merge-elt main-scope az irányadó |

**SZEMANTIKUS** — **minden más** (forráskód, `tools/**`, `.github/**`,
`docs/adr/**`, a sor-fájl, idegen brief). Itt a landoló **nem old fel**:
`rebase --abort`, majd a mai H8 út változatlanul.

A lista bővítése ADR-döntés. A besorolás fail-closed: ismeretlen útvonal =
szemantikus.

### 2.2 Kapu a kombinált állapoton

Sikeres (konfliktusmentes VAGY mechanikusan feloldott) rebase után a landoló
lefuttatja a kör `gate_tests` szerinti kaput a rebase-elt HEAD-en. Piros kapu
= **nincs merge**, a kör `blocked` jelzést kap. Ez zárja be az (b) rést.

## 3. Amit ez a döntés NEM tesz

- **Nem old fel forráskód-konfliktust.** A szemantikus osztály továbbra is
  emberi/önjavító döntés — a 41,7%-os külső arány pont azt mutatja, hogy a
  gépi feloldás itt kockázat, nem nyereség.
- **Nem vesz át merge-előfeltételt.** Review, exact-SHA zöld CI, scope-audit
  változatlan (ADR 0052).
- **Nem GitHub natív merge queue.** A mi mércénk a lokális
  `tools/round-gate.sh`; a natív sor a GitHub-oldali checkeket ismeri, a
  kaput nem.
- **Nem nyúl a slot-tervezőhöz.** A file-diszjunktság (ADR 0171) marad az
  első védvonal; a landoló a maradék ütközést kezeli.

## 4. Következmények

- A mért 36 H8-ból a brief-/napló-osztály önjavító ciklus nélkül landol.
- Minden merge mérve zöld a **kombinált** állapoton, nem csak a branchen.
- Új kockázat: egy hibás unió-feloldás némán ronthat naplót. Ellenszer: a
  landoló minden automatikus feloldást naplóz (`.pipeline/land-<kör>.log`) és
  a feloldott fájlokat felsorolja a kör-jelzésben; a besorolás fail-closed.
- A `docs/execution/pipeline-orchestrator-prompt.md` merge-lépése a landolóra
  hivatkozik; a nyers `gh pr merge` már nem a kimondott út.
