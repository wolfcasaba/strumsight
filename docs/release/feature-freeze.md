# Feature freeze — StrumSight Release Candidate előtt

**Kör:** `E12-R30` (Chapter 12, Kör 30). **Normatív forrás:**
[ADR 0489](../adr/0489-ga-scope-classification-and-contract-freeze.md) (a
freeze-hez kapcsolódó normát ez az ADR rögzíti, a Kör 28-ból; ez a kör maga
nem ír ADR-t, a `docs/adr/**` a tilos zónája). Lásd még
[`known-issues.md`](known-issues.md) (a MÉRT nyitott hibák a freeze
pillanatában) és [`blockers.md`](blockers.md) (a P0/P1/P2 blocker-nyilvántartás
egyetlen forrása — ezt a fájlt ez a dokumentum és a hozzá tartozó
`tool/release/verify_freeze.py` **olvassa**, nem írja át).

## 1. Mit jelent a freeze

A `freeze_base_sha` alatti fán a **szállított** termékkód (`lib/**`,
`backend/app/**`, `android/**`, `assets/**`, `pubspec.yaml`, …) **csak** egy
nyitott
`blockers.md`-beli P0/P1/P2 blocker javításaként módosulhat, és a commit
üzenete **megnevezi** a javított blocker azonosítóját (`R-…`). Minden más
változás a `documentation` vagy a `release-tooling` osztály valamelyikébe
tartozik. Nincs negyedik, „apró javítás, nem számít" kategória (§5.1 tiltása)
— egy változás, ami egyik osztályba sem sorolható be, **hiba**, nem
figyelmeztetés (A1).

## 2. Gépileg parszolható blokk — freeze bázisa és jóváhagyó

<!-- freeze-base:begin -->
freeze_base_sha: 4ac78365
approver_role: StrumSight release manager — a Chapter 12 sáv emberi jóváhagyója (a Kör 25 RC-workflow tervezett approval-gate szerepe, ADR 0488 D1/D8); a freeze feloldása és a `blockers.md` bővítése ennek a szerepnek a döntése, nem egy automatikus kapué.
<!-- freeze-base:end -->

A `freeze_base_sha` a jelen kör induló `origin/main`-je
(`docs(handoff): E12-R29 KÉSZ — Open Beta és canary cohort; queue done, RTM,
L577`, `4ac78365`) — a §0.0 P7 mérése szerint ez a kör-brief maga rögzíti,
nem ez a kör méri újra. A `tool/release/verify_freeze.py --since
<freeze_base_sha>` a git-történetet ETTŐL a pontól osztályozza.

A freeze-ellenőrzés **teljes git-történetet igényel**: egy sekély
(`--depth 1`) klónban, ahol a `freeze_base_sha` nem érhető el, a tool
fail-closed `2`-es kilépéssel áll meg, és megnevezi a hiányzó bázist (nem
`0`-val „nincs mit ellenőrizni" — az hazugság lenne).

## 3. Gépileg parszolható blokk — a zárt változás-osztály készlet

<!-- freeze-classes:begin -->
| class | path_prefixes | requires_blocker_id |
|---|---|---|
| `documentation` | `docs/`, `CHANGELOG.md`, `HANDOFF.md`, `AGENTS.md`, `CLAUDE.md`, `README.md` | `no` |
| `release-tooling` | `tool/release/`, `test/`, `backend/tests/`, `tools/` | `no` |
| `blocker-fix` | `*` | `yes` |
<!-- freeze-classes:end -->

- **`documentation`** — bármely `docs/**` alatti fájl, valamint a gyökér
  **dokumentum**-fájljai: `CHANGELOG.md`, `HANDOFF.md`, `AGENTS.md`,
  `CLAUDE.md`, `README.md`. Nem kell hozzá blocker ID.

  > **MÉRVE a merge UTÁN (E12-R30, post-merge gate):** az eredeti lista csak a
  > `docs/` prefixet és a `CHANGELOG.md`-t tartalmazta, ezért a lánc MINDEN kör
  > végén készülő `docs(handoff): …` commitja — ami a gyökér `HANDOFF.md`-t
  > írja — **osztályozatlan** lett, és a `verify_freeze.py` a `main`-en `1`-es
  > kilépést adott (`HANDOFF.md: not classified under any freeze change
  > class`). A gyökér dokumentum-fájljai tehát nevesítve szerepelnek. A lista
  > továbbra is ZÁRT: ami nincs rajta és nem `release-tooling` prefix, az
  > blocker ID nélkül nem változhat.
- **`release-tooling`** — a `tool/release/**`, `test/**`, `backend/tests/**`
  vagy `tools/**` alatti fájlok: a release-eszközök, a rájuk épülő
  gate-cellák, a Flutter- és backend-tesztek, valamint a pipeline/router
  segédeszközök és azok tesztjei. Közös nevezőjük, hogy **egyik sem kerül
  bele a szállított termékbe** — sem az APK-ba (`lib/**`, `assets/**`,
  `android/**`, `pubspec.yaml`), sem a telepített backendbe
  (`backend/app/**`) —, ezért a viselkedésüket nem tudják megváltoztatni.
  Nem kell hozzájuk blocker ID.

  > **MÉRVE a merge UTÁN (ADR 0112 önjavító kör, E12-R32 / H7, 2026-09-02):**
  > a lista eredetileg csak a `tool/release/` és `test/tooling/` prefixet
  > tartalmazta, ezért a freeze-korszakban merge-elt, NEM szállított
  > verifikációs kód osztályozatlan lett, és a `verify_freeze.py` a
  > `main`-en `1`-es kilépést adott — az E12-R32 kör §7 gate-je emiatt állt
  > meg, a saját diffje nélkül. A `main` csúcsán (`11d0d2bb`) **két**
  > találat volt egyszerre: `backend/tests/test_production_smoke_contract.py`
  > (E12-R31, `accd30c2`) és `tools/tests/test_sol_terra_both_slots.py`
  > (`11d0d2bb`). Ez ugyanaz a hibaosztály, mint a fenti `HANDOFF.md`-eset,
  > harmadszor: a prefix-lista szűkebb volt, mint a NEM szállított
  > útvonalak halmaza. A `.github/**` és a `.ai/**` szándékosan **nem**
  > került a listára — a CI-definíció és a router-politika maga a kapu, azt
  > a freeze alatt jóváhagyás nélkül változtatni nem szabad.
- **`blocker-fix`** — bármely más útvonal (tipikusan `lib/**`,
  `backend/app/**`, `android/**`, `assets/**`, `pubspec.yaml`). A
  `path_prefixes` értéke `*` (bármely útvonal), de **kizárólag** akkor
  fogadható el, ha az érintő commit
  üzenete megnevez egy, a `blockers.md`-ben ma szereplő, `P0`/`P1`/`P2`
  súlyosságú blocker-azonosítót (`R-[A-Z0-9-]+` alakú). A `P3` súlyosság
  (ha valaha felkerül egy sor `blockers.md`-be) **nem** elég önmagában —
  ez a §5.1 „minden commit vagy P0/P1/P2 blocker-javítás, vagy dokumentáció"
  mondatának pontos leképezése. **Az osztályozás commit-szintű, nem
  útvonal-szintű**: ha egy commit üzenete megnevez egy érvényes blocker ID-t,
  a commit MINDEN útvonala `blocker-fix`-nek minősül, akkor is, ha egy részük
  ténylegesen semmilyen kapcsolatban nincs a megnevezett blockerrel — a
  jóváhagyó szerep (`approver_role` fent) felelőssége a commit tartalmának
  szűkítése a valódi blocker-javításra, nem a gépi ellenőrzésé.

Ez a három osztály **zárt** — a `tool/release/verify_freeze.py` ezt a
táblázatot olvassa be (nem hardkódolja), de a táblázat maga csak ezt a három
sort tartalmazhatja: egy negyedik sor bevezetése ennek a dokumentumnak a
módosítását igényli, ami maga `documentation` osztályú változás, tehát
engedélyezett — de a `verify_freeze.py` a jelenlegi három osztályt olvassa a
jelenlegi fán.

## 4. Miért ez a kör az első, ami erre gépi mércét ad

A `docs/release/` korábbi körök után gazdag, de a freeze-szabály és a
freeze-ellenőrző eddig nem létezett — a `CHANGELOG.md` sem (§2 „Jelenlegi
állapot" a kör briefjében). Ez a kör az ELSŐ feature-freeze kör a projektben
(nincs release-domain előzmény a lessons/halts korpuszban — a brief §0.0
retrospektív keresése ezt kimondottan megerősítette).

## 5. Kapcsolódó dokumentumok

- [`known-issues.md`](known-issues.md) — a freeze pillanatában MÉRT nyitott
  hibák, súlyossággal, hatással és megkerülő úttal (vagy annak kimondott
  hiányával).
- [`blockers.md`](blockers.md) — a P0/P1/P2 blocker-nyilvántartás; ezt a
  fájlt ez a kör **nem** írja át (§0.0 P2).
- [`contract-freeze.md`](contract-freeze.md) — a Kör 28-ban már befagyasztott
  core-contractok; ez egy különálló, korábbi freeze-réteg, amit ez a
  dokumentum nem duplikál.
- [`../rounds/e12-r30-feature-freeze-and-final-regression.md`](../rounds/e12-r30-feature-freeze-and-final-regression.md)
  — a jelen kör brief-je és a §10 implementation handoff.
