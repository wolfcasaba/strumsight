# E99-R16 (GOV-10) — Kör-granularitás: a fix overhead mérése és az összevonás gépi javaslata

- **Státusz:** READY FOR IMPLEMENTATION (brief 2026-08-18, `main @ 52324cb3`)
- **Típus:** **governance-kör** — mérőeszköz, nem terméki viselkedés
- **Kör-azonosító:** `E99-R16`. Emberi neve **GOV-10**.
- **Előfeltétel:** `E99-R14` (a `tools/round-metrics.py` ott bővül először)
- **Brief szerzője:** Claude (Opus 5, orchesztrátor) · **ADR:** [`0307`](../adr/0307-pipeline-throughput-program-v2.md) **§3**

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "tools/round-metrics.py",
  "tools/brief-merge-plan.py",
  "tools/brief-lint.py",
  "tools/tests/test_brief_merge_plan.py",
  "tools/tests/test_round_metrics_granularity.py",
  "docs/rounds/e99-r16-gov-10-round-granularity.md",
]
gate_tests = [
  "test/tooling/architecture_allowlist_guard_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **STOP-protokoll:** listán kívüli fájl →
`stopped` + brief-revízió; az `allowed_paths` tágítása TILOS.

## 1. Cél — az ADR 0171 §5 döntése mérőeszköz nélkül maradt

Az ADR 0171 §5 kimondta: a kör-összevonás **mérésre** menjen, ne érzésre — a
mérőeszköz azonban nem épült meg. A 2026-08-18-i kézi mérés szerint a kör fix
overheadje (pre-flight + review + CI + záró rituálék) **40–50 perc**, miközben
az E07-epic körei **47–63 perc** alatt zárnak. Vagyis a körök jelentős részében
az overhead a munkánál nagyobb tétel — de ez ma kézi becslés, nem futtatható
artefaktum.

Ez a kör azt a két eszközt építi meg, amivel az összevonási döntés MÉRT lesz,
és a döntést továbbra is a brief-előkészítés hozza meg (a sor-séma nem változik).

## 2. Jelenlegi állapot — mérve a kódban

- `tools/round-metrics.py` kör-időt, holtidőt, önjavítási arányt és
  költség-főkönyvet ad — a kör MÉRETÉRŐL semmit.
- `tools/brief-lint.py` `base`/`strict` szintje a brief tartalmi hibáit fogja;
  a kör aránytalan kicsiségét nem.
- A `docs/execution/pipeline-queue.tsv`-ben ma **75** nyitott brief van
  (39 `pending`, 36 `prepared`).

## 3. Feladatok

### D1 — `tools/round-metrics.py --granularity`

Minden MÉRT (merge-elt) körre párosítja a `.pipeline/chain.log` kör-idejét a
briefje méretével (`allowed_paths` és `gate_tests` darabszám, `native_gate`).
Kimenet:

- méret-sávonkénti (1–4, 5–8, 9+ engedélyezett fájl) medián kör-idő és mintaszám;
- **lineáris illesztés** kör-idő ~ fájlszám: a tengelymetszet a MÉRT fix
  overhead, a meredekség a fájlonkénti határköltség;
- a 10 óránál hosszabb körök kiugróként kimaradnak (E07-R16 = 2636 perc, halt).

Kizárólag lokális adatból dolgozik (napló + sor-fájl + briefek), hálózat nélkül.

### D2 — `tools/brief-merge-plan.py`

Összevonásra javasolt brief-PÁROKAT ad (`--format json|text`), ezekkel a
feltételekkel — mind a négynek teljesülnie kell:

1. a két kör a sorban SZOMSZÉDOS és egymás előfeltétele (azonos epic, egymás utáni sorszám);
2. azonos feature-gyökér (`lib/features/<x>/` vagy `lib/core/<x>/`) az `allowed_paths` többségében;
3. az egyesített `allowed_paths` mérete a `--max-paths` küszöb (alap **12**) alatt marad;
4. egyik kör sem `native_gate = true`.

A kimenet minden párnál megadja a mért indokot (a két kör becsült ideje a D1
illesztésből, és az összevonással megspórolt overhead). **A tool nem ír át
briefet és nem nyúl a sorhoz** — javaslat, nem művelet.

### D3 — `brief-lint --level strict`: aránytalanul kicsi kör

Új `strict` lelet (`S6`): a brief `allowed_paths` listája a
**brief-fájlon és a gate-teszteken kívül 2-nél kevesebb** fájlt tartalmaz, és
`native_gate = false`. Üzenet: a kör valószínűleg összevonható a szomszédjával
(`tools/brief-merge-plan.py`). **`base` szinten NEM lelet** — a CI-kapu nem
szigorodik, mert a mai briefek egy része jogosan kicsi (pl. egy hotfix-kör).

## 4. Mérce-mátrix

`--max-paths = 12` küszöb hármas cellája (`tools/tests/test_brief_merge_plan.py`,
fixtúrás sor + briefek):

| eset | egyesített `allowed_paths` | elvárt |
|---|---|---|
| küszöb **alatt** | 11 fájl | a pár JAVASOLT |
| küszöb **rajta** | pontosan 12 fájl | a pár JAVASOLT (a küszöb inkluzív) |
| küszöb **fölött** | 13 fájl | a pár NEM javasolt, indoklással |

**Falszifikációs cella (kötelező):** a D2 4. feltételének (natív gate kizárása)
kiszedése → a fixtúrában szereplő `native_gate = true` pár megjelenik a
javaslatban → a teszt **PIROS** → visszaállítás után zöld.

Második falszifikáció: a D1 kiugró-szűrés kiszedése → a 2636 perces fixtúra-kör
a regresszió meredekségét elmozdítja a tesztben rögzített tűrésen kívülre →
**PIROS**.

## 5. Tilos zóna

`docs/adr/**`, `.ai/router.toml`, `docs/execution/pipeline-queue.tsv`,
`docs/rounds/**` (a saját briefen kívül), `.pipeline/**`, minden Dart forrás.
A `brief-lint.py` `base` szintje NEM bővül — csak `strict` lelet születik.

## 6. Definition of Done

1. D1–D3 kész; `--granularity` és `brief-merge-plan.py` determinisztikus
   kimenetet ad a fixtúrákra.
2. `python3 tools/brief-lint.py --open --level base` továbbra is **nulla lelet**
   (a CI-kapu nem szigorodott).
3. `python3 -m pytest tools/tests -q` zöld.
4. `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart` zöld.
5. Kör-jelzés `done`.

## 7. Gate

```bash
tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart
python3 -m pytest tools/tests -q
python3 tools/brief-lint.py --open --level base
```

A gate-lépések külön processzben futnak, a kimenet csonkítatlan. A teljes suite
+ property gate a CI-ban fut (ADR 0053).
