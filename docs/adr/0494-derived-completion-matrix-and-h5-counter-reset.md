# ADR 0494 — A completion-matrix a queue-ból SZÁRMAZTATOTT, és a H5 piros-CI-számláló egy merge-elt önjavítás után nulláról indul

- **Státusz:** elfogadva (2026-09-03)
- **Kontextus:** ADR 0112 (önjavító lánc), ADR 0087 (kör-sor és halt-protokoll),
  ADR 0052 (zöld kapu), `docs/LESSONS.md` L590 (a mérce IRÁNYA), L591, L592
- **Döntéshozó:** ADR 0112 önjavító kör (E15-R09 / H5, 1. kísérlet), mérés alapján

## Kontextus — KÉT független akadály állította meg ugyanazt a láncot

2026-09-03 hajnalban a kör-pipeline **kétszeresen** akadt el, és a két ok
egymástól teljesen független:

1. **A `main` Full Gate-je PIROS** (run `33704424852`, `e9691f74`). A driver
   előfeltétele — „a lánc nem indul piros main fölé" — 02:25 és 03:54 között
   **18 firingen keresztül, 89 percig** minden körindítást kiejtett. Ok: az
   E15-R08 merge a queue `E15` eloszlását `8 done / 6 pending`-ről
   `9 done / 5 pending`-re vitte, a `docs/sdd/program-completion-report.md` §3
   matrixa viszont a kézzel írt régi értéken maradt, és a
   `test/tooling/program_completion_test.dart` `A1` cellája SZIGORÚ
   egyenlőséget mér a queue ellen.
2. **Az E15-R09 kör H5 haltja** (a CI kétszer piros: `33707997183`,
   `33711465885`). A 2. piros mért gyökéroka: az öt migrált Tutor-képernyő
   **24 MÉLY importtal** éri el a design-rendszert a `public.dart` barrel
   helyett, ami az E13-R02 szerződést sérti. A szabályt viszont **kizárólag a
   teljes CI-suite** mérte (`test/core/architecture_dependency_test.dart:754`);
   sem a kör célzott `gate_tests` listája, sem a gate `architecture` lépése
   (`dart run tool/check_architecture.dart`) nem ismerte — mindkettő ZÖLDEN
   ment ugyanazon a fán. MÉRVE: a `main` állapotú checker ugyanarra a fára
   `Architecture dependencies OK`-ot ad, miközben a CI kétszer elbukott rajta.

Az L590 ezt a hibaosztályt előre leírta („minden jövőbeli kör… PIROSRA váltja
ezt a cellát"), és a feloldást egy KÖVETKEZŐ körre halasztotta. Az első
queue-flip azonnal detonált.

## Döntés

**D1 — A §3 completion-matrix négy szám-oszlopa SZÁRMAZTATOTT adat.**
A `tools/sync-completion-matrix.py` a `docs/execution/pipeline-queue.tsv`-ből
számolja őket (ugyanaz a sor-minta, mint az `A1`-é), és a kör-driver
(`tools/round-pipeline.sh`, `merged` ág) **ugyanabban a commitban** futtatja,
amelyben a queue-sort `done`-ra billenti. A `Riport-státusz` prózát a szinkron
SOHA nem írja — az az emberi őszinteség oszlopa, az `A2` szó szinten olvassa.

**Az `A1` egyenlősége VÁLTOZATLANUL szigorú.** Az L590 két felkínált iránya
(befagyasztott pillanatkép, vagy nem-egyenlőség alapú „nem overstate"
reláció) **nem kell** — mindkettő gyengítette volna vagy elbonyolította volna
a mércét. Ami megszűnt, az kizárólag a KÉZI bookkeeping.

**D2 — A design-rendszer barrel-szerződése a gate `architecture` lépésének a
része.** Új szabály a `tool/check_architecture.dart`-ban:
`designSystemImportsMustUsePublicBarrel` — `lib/**` (a design-rendszeren
kívülről) a `lib/core/design_system/**`-ot kizárólag a `public.dart` barrelen
át érheti el. Így **minden** kör `tools/round-gate.sh`-ja méri, lokálisan, a
push előtt; nem kell hozzá per-brief `gate_tests` bookkeeping, és nem a
15 perces teljes CI-suite az első jelzés. A mai `main` a szabály alatt tiszta
(0 sértés, allowlist-bejegyzés nélkül) — a szabály bevezetése nem hoz
technikai adósságot.

**D3 — A H5 piros-CI-számláló egy merge-elt önjavító kör után NULLÁRÓL indul,**
ha az a heal a pirosak MÉRT gyökérokát javította. A `zöld kapu` változatlan:
minden gate + a teljes CI-suite + a Router CI zöldje a merge SHA-n kötelező.
Indoklás: a H5 egy VAK újrapróbálkozás-hurok őre, az ADR 0112 önjavítás pedig
épp az a mechanizmus, ami a hurkot megtöri. E kikötés nélkül egy önjavítással
FELOLDOTT H5 örökre megállítja a kört:

```
halt → önjavítás (gyökérok javítva) → folytatás → azonnali halt (a heal ELŐTTI
két pirosra hivatkozva) → önjavítás → … a 3 kísérlet kimerül → ember
```

vagyis pont az a holtpont, aminek a megszüntetésére az ADR 0112 létezik.

## Következmények

- A queue-flip commit ezentúl két fájlt vihet (`pipeline-queue.tsv` +
  `program-completion-report.md`). A szinkron **idempotens**: ha az
  orchesztrátor záró commitja már elvégezte, a fail-safe ág no-op marad
  (a D2/E99-R19 „nincs üres commit" tulajdonság megmarad).
- Egy design-rendszer-migrációs kör mostantól **lokálisan** bukik el a mély
  importon, a gate `architecture` lépésében — ez a kör dolgát nehezíti a
  helyes irányba, és a lánc H5-jeit előzi meg.
- A D3 kizárólag a SZÁMLÁLÓRÓL szól. Ha a folytatás CI-ja ismét kétszer piros
  lesz, a H5 újra érvényes — a halt-protokoll nem lazult.

## Mérce

| Döntés | Őr |
|---|---|
| D1 | `tools/tests/test_completion_matrix_sync.py` (mért drift `--check`-en piros; `--write` csak a szám-cellákat írja; a driver a flip-commitban szinkronizál; a valódi fa szinkronban van) |
| D2 | `test/tooling/design_system_barrel_architecture_test.dart` (a 24 MÉRT import mindegyike sértés; barrel-importtal tiszta; a design-rendszer a sajátjait elérheti; a valódi fa tiszta) |
| D3 | `tools/tests/test_h5_counter_resets_after_selfheal.py` (a H5 sor megmarad; a reset kimondva; a zöld kapu nem lazul) |
