# E06-R13 — Target alignment engine

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-12, kód újramérve: main @ `ce4b6b24`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 13; §9.4, §15.1, §15.4
- **Branch:** `codex/e06-r13-target-alignment-engine`
- **Előfeltétel:** **E06-R10, E06-R12 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/domain/target/analysis_target.dart",
  "lib/features/audio_analysis/domain/target/expected_event.dart",
  "lib/features/audio_analysis/domain/target/alignment_result.dart",
  "lib/features/audio_analysis/engine/alignment/event_aligner.dart",
  "lib/features/audio_analysis/engine/alignment/tolerance_policy.dart",
  "lib/features/audio_analysis/public.dart",
  "test/features/audio_analysis/engine/event_aligner_test.dart",
  "test/features/audio_analysis/engine/tolerance_policy_test.dart",
  "test/property/analysis_alignment_property_test.dart",
  "docs/rounds/e06-r13-target-alignment-engine.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R10/R12 merge.
> Olvasd újra a Practice Engine **meglévő** illesztőjét
> (`lib/features/practice/**` — a `practice_event_matcher_property_test.dart`
> és a `CompiledTargetEvent` mutatja a mai szerződést). Az `AnalysisTarget`
> **snapshot**, nem provider-referencia: a Practice-oldali fordítás az E06-R26
> dolga — ez a kör csak a **saját** target-típusát és az illesztőt szállítja.
> PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING.** Pre-flight lezárva 2026-08-12, `main @ ce4b6b24` (E06-R10 és
E06-R12 mindkettő merge-elve — az előfeltétel teljesül).

Mért, a briefet megerősítő ellenőrzések:

- `AnalysisTarget` nem létezik az `audio_analysis` fán, és a `domain/target/`
  / `engine/alignment/` alkönyvtárak sem — a kör teljes felülete ÚJ (nincs
  névütközés, ellentétben az R10/R11 pre-flightban mért résekkel).
- A Practice Engine illesztője (`CompiledPracticeTarget`/`CompiledTargetEvent`,
  `test/property/practice_event_matcher_property_test.dart`) létezik és
  változatlan marad — a brief §2/§3 hivatkozása pontos, a „tilos zóna" valódi.

**ADR 0231** ebben a pre-flightban íródott (a fenti eredeti „Új ADR nincs"
állítás a brief batch-authoring időpontjára vonatkozott; a tényleges
ADR-számot a pre-flight foglalja és írja meg) — l. [ADR
0231](../adr/0231-target-alignment-engine-boundary.md).

**Dokumentált, nem blokkoló eltérés:** a §9 kockázat-szakasz „ADR 0203"
hivatkozása jelenleg nem létező fájlra mutat (ugyanez a placeholder hét másik
E06 brief-ben is szerepel — R02, R14, R16, R19, R20, R25 —, az Epic korai
tervezéséből maradt visszaváltatlan szám). Indoklás: ADR 0231 „Kontextus"
szakasza. Nem blokkoló: a hivatkozás nem acceptance-cella, és R13
`allowed_paths`-a nem érinti a metric-katalógust.

## 1. Cél

A megfigyelt és az elvárt események **monoton, determinisztikus** illesztése —
a timing-, ritmus- és dinamika-metrikák (R14–R16) közös alapja.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- **Nincs** target-fogalom az Analyze úton: a `ClipAnalyzer` szabad játékot
  elemez; a mai Analyze képernyő nem kap elvárt eseményeket.
- A Practice Engine **saját** illesztéssel rendelkezik
  (`CompiledPracticeTarget` + `CompiledTargetEvent` +
  `practice_event_matcher_property_test.dart`) — ez a **Practice** pontozási
  szerződése, amit az SDD §27.1 szerint az Audio Analysis **nem írhat felül**.
- Az R10 adja a megfigyelt eseményeket, az R12 a beat-rácsot (tempófüggő
  tolerancia bemenete).

## 3. Scope

**Benne:** `AnalysisTarget` (verziózott **snapshot**: id, kind, timebase,
elvárt események/akkordok/hangok, szakaszok); `ExpectedEvent`;
`AlignmentResult` (matched párok, missed expected, extra observed, teljes
költség, confidence, diagnosztika); `EventAligner` (monoton dinamikus
programozás, determinisztikus tie-break); `TolerancePolicy` (tempófüggő ablak
min/max clamp-pel).

**Kívül — TILOS:** a Practice Engine illesztőjének módosítása vagy
importálása, metrika-számítás (R14+), Practice/Song adapter (R26), UI.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/target/analysis_target.dart` | ÚJ | verziózott target snapshot |
| `.../domain/target/expected_event.dart` | ÚJ | elvárt esemény |
| `.../domain/target/alignment_result.dart` | ÚJ | illesztés eredménye |
| `.../engine/alignment/event_aligner.dart` | ÚJ | monoton DP |
| `.../engine/alignment/tolerance_policy.dart` | ÚJ | tempófüggő ablak |
| `.../public.dart` | meglévő | export |
| `test/**` | ÚJ | illesztés + tolerancia + property |

**Tilos zóna:** `lib/features/practice/**`, `lib/features/song_trainer/**`,
`lib/features/analyze/**`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Az illesztés MONOTON:** ha `observed[i] ↔ expected[j]`, akkor
   `observed[i+1]` csak `expected[k], k > j`-vel párosulhat.
   **NEM elfogadható:** greedy legközelebbi-szomszéd illesztés (SDD §15.1
   csak „bizonyítottan egyszerű use case-ben" engedi, ami itt nem áll fenn),
   és **NEM elfogadható** a keresztező párosítás.
2. **Determinisztikus tie-break:** azonos költségű megoldások közül a
   **korábbi** expected indexet választja a szabály; a tie-break **kimondott**
   és tesztelt. **NEM elfogadható:** a `Map`/`Set` iterációs sorrendtől függő
   eredmény.
3. **Az illesztő nem módosítja a bemenetet:** sem az observed, sem az expected
   lista nem változik (immutabilitás-teszt).
4. **A tolerancia tempófüggő, clamp-pel:** `tolerance = clamp(beatDuration ×
   ratio, minMs, maxMs)`; a `ratio`, `minMs`, `maxMs` néven nevezett,
   verziózott konstansok. **NEM elfogadható:** fix milliszekundum minden
   tempón (SDD §15.4), és **NEM elfogadható** a clamp elhagyása.
5. **A target snapshot, nem élő referencia** (SDD §9.4): nincs provider-,
   controller- vagy repository-hivatkozás benne; a `targetVersion` a
   provenance-be kerül.
6. **A komplexitás korlátos és dokumentált:** a DP `O(n·m)` idejű és
   `O(min(n,m))` memóriájú (sávos), a sáv szélessége a toleranciából
   származik. **NEM elfogadható:** dokumentálatlan `O(n³)` (SDD Kör 13
   elfogadási feltétel).

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Milyen költségfüggvény?
    blocking: true
    resolution_policy: use_default
    default: >-
      cost(match) = |Δt| / tolerance  (0..1 a toleranciaablakon belül,
      afölött nem párosítható) + 0.5 ha az irány eltér + 0.25 ha az
      eseménytípus eltér, mindez (2 − observedConfidence) szorzóval;
      cost(missed) = 1.0; cost(extra) = 1.0. Minden együttható néven
      nevezett konstans, a `tolerance_policy.dart`-ban, verzióval.
  - id: OD-02
    question: A toleranciaablakon kívüli pár egyáltalán párosítható?
    blocking: true
    resolution_policy: use_default
    default: >-
      NEM — a maximum match window kemény korlát (SDD §15.1); azon túl
      missed + extra keletkezik. Ez teszi a sávos DP-t helyessé.
  - id: OD-03
    question: Kezdeti tolerancia-paraméterek?
    blocking: false
    resolution_policy: use_default
    default: "ratio = 0.25 × beatDuration, minMs = 40, maxMs = 150 — ideiglenes az R29-ig."
```

## 6. Acceptance criteria

- [ ] **Illesztés-mátrix — kilenc cella:** tökéletes illeszkedés;
      egy hiányzó elvárt; egy többlet megfigyelt; **korai klaszter** (öt esemény
      egyaránt korán); **késői klaszter**; két jelölt azonos távolságra
      (tie-break); irány-eltérés; eseménytípus-eltérés; **üres** observed
      **és** üres expected. Mindegyikre a teljes `AlignmentResult` ellenőrzött
      (párok, missed, extra, költség).
- [ ] **Monotonitás property:** `PROPERTY_SEED`-ből vezérelt véletlen
      observed/expected párokra a matched párok indexei **mindkét** oldalon
      szigorúan növekvők — keresztezés **soha**.
- [ ] **Tolerancia-küszöb hármas** (120 BPM → `beatDuration = 500 ms`,
      `ratio = 0.25` → 125 ms, a clamp `[40, 150]` nem hat): egy esemény
      **124 ms**, **125 ms** és **126 ms** eltéréssel — a **125 ms**
      **párosul** (a határ inkluzív), a 126 ms **missed + extra**.
      Az értékeket `python3 -c "print(0.25*60/120*1000)"` alapján.
- [ ] **Clamp-mátrix — mindkét oldal:** 40 BPM-en (`beatDuration = 1500 ms`,
      ratio → 375 ms) a tolerancia **150 ms**-ra vágott — a **150 ms**
      párosul, a **151 ms** nem; 300 BPM-en (`beatDuration = 200 ms`,
      ratio → 50 ms) a tolerancia **50 ms** (a `minMs = 40` nem hat) — de
      400 BPM-en (`150 ms` → 37.5 ms) a **40 ms** lép életbe: a **40 ms**
      párosul, a **41 ms** nem. Mind a hat cella `python3 -c`-vel számolva.
- [ ] **Tie-break determinizmus:** a „két jelölt azonos távolságra" cella
      **100 ismételt** futtatásra **azonos** eredményt ad, és a választott
      pár a **korábbi** expected index.
- [ ] **Bemenet-immutabilitás:** az illesztés után az observed és expected
      listák elemenként változatlanok.
- [ ] **Teljesítmény-korlát:** 2 000 observed × 2 000 expected illesztése a
      gate környezetében **befejeződik** (nincs timeout), és a §10 rögzíti a
      mért időt; a memóriahasználat a sávos DP miatt `O(min(n,m))` — teszt
      méri a sáv szélességének korlátosságát (a belső allokáció mérete
      arányos a toleranciából számolt sávval, nem `n·m`-mel).
- [ ] **Confidence hatása:** azonos időeltérésű két jelöltnél a **magasabb**
      observed confidence-ű nyer (külön cella, a költségfüggvény
      confidence-szorzóját mérve).

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Greedy legközelebbi-szomszéd illesztés | a **korai klaszter** és **késői klaszter** cella (keresztező párok) + a monotonitás property |
| A tie-break a `Map` sorrendjétől függ | a 100 ismétléses determinizmus-cella |
| A tie-break a KÉSŐBBI indexet választja | a tie-break „korábbi index" cellája |
| A tolerancia exkluzív (`<` a `<=` helyett) | a **pontosan 125 ms** párosul-cella |
| A clamp felső ága hiányzik | a 40 BPM-es **151 ms párosul** hiba → a `151 ms nem párosul` cella |
| A clamp alsó ága hiányzik | a 400 BPM-es **40 ms** cella |
| A toleranciaablakon kívül is párosít | a 126 ms **missed + extra** cella |
| Az illesztő rendezi (mutálja) a bemenetet | a bemenet-immutabilitás cella |
| Teljes `O(n·m)` mátrix allokáció | a sávszélesség-korlátosság cella (2 000×2 000 futás) |
| **Valódi-sértés próba (§10):** a monotonitási feltétel ideiglenes kiszedése a DP-ből → a monotonitás property **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. RED: illesztés-mátrix, tolerancia- és clamp-hármasok, tie-break.
2. `analysis_target.dart` + `expected_event.dart` + `alignment_result.dart`.
3. `tolerance_policy.dart` (verziózott konstansok).
4. `event_aligner.dart` (sávos, monoton DP, determinisztikus tie-break).
5. Monotonitás- és teljesítmény-teszt; gate.

## 9. Kockázatok

- **A költségfüggvény együtthatói kalibrálatlanok** — a `tolerance_policy.dart`
  verziózza őket, az eval-mátrix PENDING sort kap, és a változtatás
  **metric version** emelést von maga után (ADR 0203).
- **A Practice Engine saját illesztésével való eltérés** zavaró lehet a
  felhasználónak — az SDD §27.1 szerint a Practice score marad az elsődleges;
  ezt az R26 adaptere érvényesíti, és a §10-ben follow-upként rögzítendő.
- **A 2 000×2 000 teszt lassíthatja a gate-et** — ha a mért idő > 10 s, a
  méretet 1 000×1 000-re kell csökkenteni, és ezt a §10 rögzíti (a
  sávkorlátosságot ez nem gyengíti).

**STOP:** a Practice illesztőjének importálása vagy módosítása helyett
`stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r13-target-alignment-engine-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
