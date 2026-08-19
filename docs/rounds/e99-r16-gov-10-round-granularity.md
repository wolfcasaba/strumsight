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

## 0.0 Pre-flight brief-revízió (orchestrátor, 2026-08-19) — négy mért pont

| # | Mit állított/feltételezett a brief (vagy a pipeline-prompt) | Mért valóság | Feloldás |
|---|---|---|---|
| R1 | pipeline-prompt: „Előre kiosztott ADR: `nincs` — te írod meg a pre-flightban" | a brief SAJÁT fejléce már `ADR: 0307 §3`-at hivatkozza, és az ADR 0307 §3 (`docs/adr/0307-pipeline-throughput-program-v2.md:160-175`, elfogadva, `604253eb`, PR #308) SZÓ SZERINT leírja a D1/D2/D3 döntést; a brief SAJÁT §5 Tilos zónája explicit felsorolja `docs/adr/**`-t; a két testvér-kör (E99-R14, E99-R15) egyike sem hozott létre új ADR-fájlt (`git show --name-only 52200a81` / `dcbfb469`: nulla `docs/adr/` találat mindkét squash-commitban) | **nincs új ADR ehhez a körhöz.** A `tools/round-slots.py reserve-adr --round E99-R16` a pre-flight elején **0320**-at foglalt le — ez a szám EBBEN a körben NEM kerül fájlba (`docs/adr/**` tilos zóna, egy új fájl odaírása H3 lenne); a szám felhasználatlan marad, ahogy korábbi foglalások is kimaradtak (pl. 0313–0316) |
| R2 | D2 2. feltétele: „azonos feature-gyökér (`lib/features/<x>/` VAGY `lib/core/<x>/`)" — csábít a `brief-lint.py`-ban MÁR meglévő `_feature_root` helper újrahasznosítására, hiszen a fájl ebben a körben is érintett | `tools/brief-lint.py:148-154` `_feature_root`-ja `lib/features/<x>/...`-ra 3 szegmenst ad (helyes), DE minden más `lib/`-kezdetű útvonalra (pl. `lib/core/design_system/x.dart`) csak **2** szegmenst (`lib/core`) — összevonná az ÖSSZES `lib/core/*` alfeature-t egyetlen gyökérré, ellentétben a brief 3-szegmenses `lib/core/<x>/` szövegével | `brief-merge-plan.py` írjon **saját**, a brief szövegét szó szerint követő (3-szegmenses mindkét ágon) feature-gyökér-számítást; NE importálja/hívja a `brief-lint.py` `_feature_root`-ját. A `brief-lint.py` saját `_feature_root`-ja **változatlan marad** (az S5 lelet a 2-szegmenses viselkedésre épít — módosítása ott regressziót okozna) |
| R3 | D2 1. feltétele („egymás közvetlen előfeltételei") nem mondja ki explicit, hogy csak NYITOTT párokra vonatkozik | ADR 0307 §3: „a döntés a brief-előkészítésé" — egy már `done` kör briefje történelem (a másik fele már külön PR-ben, külön SHA-n megvan), összevonásra nincs mit javasolni; a projekt saját H2-elve (lezárt kör viselkedése nem módosul) ugyanide mutat | a pár mindkét tagja `pending` vagy `prepared` legyen a `docs/execution/pipeline-queue.tsv` 5. oszlopa szerint — kövesd a `brief-lint.py` `queue_rows()`-hoz hasonló, de SAJÁT (nem importált) 5-oszlopos TSV-olvasást |
| R4 | DoD #3 / 7. Gate 2. sora: „`python3 -m pytest tools/tests -q` zöld" | **MÉRVE, a kör diffje NÉLKÜL** (izolált venv: `python3 -m venv` + `pip install pytest`): `1 failed, 537 passed, 565 subtests passed in 300.51s` — a hiba `tools/tests/test_knowledge_rag.py::PipelineWiringTest::test_brief_lint_flags_a_brief_without_retrieved_precedent`, ami egy VALÓDI brief-fájlra (`docs/rounds/e99-r15-gov-09-halt-escalation.md`) és a VALÓDI queue-ra épít fixtúra helyett; az E99-R15 kör `done`-ra záródása (E99-R16 dispatch ELŐTTI kör, PR #320, `dcbfb469`) aktiválta a `brief-lint.py` S8-szabályának SAJÁT „csak nyitott körre" kivételét (`tools/brief-lint.py:292-295`) — a teszt elavult elvárása emiatt pirosra vált, a `brief-lint.py`-ban NINCS hiba | `tools/tests/test_knowledge_rag.py` **NINCS** az `allowed_paths`-on — javítása ennek a körnek tilos zónája. **A kör saját „zöld" mércéje ezért: PONTOSAN ez az 1, kör-független hiba + 537 passed + 565 subtests, nulla ÚJ hiba.** Bármilyen MÁSIK vagy TÖBB piros a kör diffjének regressziója |

Ezek a pontosítások **nem bővítik** az `allowed_paths`-t és **nem módosítják** a Definition of Done tartalmi elvárását (D1–D3 elkészül, a base brief-lint nulla lelet, a gate zöld) — kizárólag a meglévő szöveg egyértelműsítése és egy, a kör diffjétől független, előzőleg is piros teszt dokumentálása, mérve.

**Visszakeresett előzmény (ADR 0312 §4.1, brief-lint S8):**
- `node tools/knowledge-rag.mjs --top 5 "kör-granularitás mérés brief méret allowed_paths overhead"` — a top találatok ennek a briefnek saját szakaszai; nincs korábbi kör, ami ugyanezt már megépítette volna.
- `node tools/knowledge-rag.mjs --corpus lessons --top 5 "brief méret allowed_paths összevonás lineáris illesztés kiugró szűrés"` — a találatok (L270, L302, L129, L188, L187) mind `allowed_paths`-scope kérdésekről szólnak, de más hibaosztályról (brief-revízió/scope-konzisztencia). **Nincs közvetlenül releváns korábbi lecke** a D1–D3 tartalmára — a tényleges tervezési előzmény az ADR 0307 §3 és az ADR 0171 §5 (mindkettő már hivatkozva a brief fejlécében).

**Segítség, nem kötelező előírás:** a D1 „lineáris illesztéséhez" a `statistics.linear_regression(x, y)` (stdlib, Python 3.10+; ezen a boxon verifikálva: `LinearRegression(slope=2.0, intercept=0.0)` egy triviális bemeneten) elegendő — a `tools/round-metrics.py` már importálja a `statistics` modult, új függőség (numpy/scipy) bevezetése nem indokolt.

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
