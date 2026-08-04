# E04-R05 — Context adapterek és TutorContextSnapshot

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ fbe1e82)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 5
- **Branch:** `codex/e04-r05-context-adapters-and-snapshot`
- **Előfeltétel:** E04-R02 (conversation/message domain), E04-R03 (student/guitar profile, goals, consent), E04-R04 (skill taxonomy, evidence, reducer) merge; **Epic 3 (E03-R22) lezárva**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/application/context/tutor_context_snapshot.dart",
  "lib/features/ai_tutor/application/context/tutor_context_assembler.dart",
  "lib/features/ai_tutor/application/context/context_budget.dart",
  "lib/features/ai_tutor/application/context/context_purpose.dart",
  "lib/features/ai_tutor/application/context/redaction_report.dart",
  "lib/features/ai_tutor/application/context/inspectable_context_view.dart",
  "lib/features/ai_tutor/application/context/adapters/practice_context_adapter.dart",
  "lib/features/ai_tutor/application/context/adapters/song_trainer_context_adapter.dart",
  "lib/features/ai_tutor/application/context/adapters/analyze_context_adapter.dart",
  "lib/features/ai_tutor/application/context/adapters/progress_context_adapter.dart",
  "lib/features/ai_tutor/application/context/adapters/streak_context_adapter.dart",
  "lib/features/ai_tutor/application/context/adapters/settings_context_adapter.dart",
  "test/features/ai_tutor/application/context/tutor_context_assembler_test.dart",
  "test/features/ai_tutor/application/context/context_budget_test.dart",
  "test/features/ai_tutor/application/context/redaction_test.dart",
  "test/features/ai_tutor/application/context/inspectable_context_view_test.dart",
  "test/features/ai_tutor/application/context/adapters/practice_context_adapter_test.dart",
  "test/features/ai_tutor/application/context/adapters/song_trainer_context_adapter_test.dart",
  "test/features/ai_tutor/application/context/adapters/analyze_context_adapter_test.dart",
  "test/features/ai_tutor/application/context/adapters/progress_context_adapter_test.dart",
  "test/features/ai_tutor/application/context/adapters/streak_context_adapter_test.dart",
  "test/features/ai_tutor/application/context/adapters/settings_context_adapter_test.dart",
  "docs/rounds/e04-r05-context-adapters-and-snapshot.md",
]
gate_tests = [
  "test/features/ai_tutor/application/context",
]
native_gate = false
```

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd az `origin/main`-t és a
> merge-elt előfeltételeket (R02, R03, R04, valamint az Epic 3 zárás E03-R22);
> olvasd újra az `AGENTS.md`-t, a Chapter 1/2/5-öt, a `HANDOFF.md`-t, az
> [ADR 0131–0134](../adr/) alapozó tutor-döntéseket és a `docs/LESSONS.md`-t.
> `rg`-vel igazold minden `allowed_paths` útvonal mai állapotát (a 20 `lib`/`test`
> fájl mérve HIÁNYZIK — greenfield), a hat fogyasztott `public.dart` barrel exact
> exportjait, valamint az R02–R04 által bevezetett tutor-típusokat (profile,
> consent, skill/evidence). Ha E03-R21/R22 vagy a batch korábbi köre eltolta az
> ADR-blokkot, vagy ha a Song Trainer public felülete megváltozott (lásd §0.0),
> dokumentáld §0.0-ban, javítsd a scope/fájllistát, állítsd a briefet
> `PREPARED`→`PLANNING`-re, és commitold a körbranchre az implementer előtt. A
> `PREPARED` brief nem futtatható vakon.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Az implementer nem hív `gh`-t, nem pushol és
nem nyit PR-t. Listán kívüli fájl, hiányzó public contract, source feature belső
importja, ellentmondó acceptance vagy megkülönböztetésre alkalmatlan teszt esetén
`stopped`; nincs néma scope-tágítás vagy mércegyengítés.

## 0.0 Tervezési baseline és pre-flight revízió

**Batch-baseline: `main` @ `fbe1e82`. Előre kiosztott új ADR: nincs** — a kör az
R01 négy alapozó ADR-jét (0131 provider boundary, 0132 privacy/consent, 0133 tool
confirmation, 0134 memory policy) bővíti a §5-ben, nem tervez újat. Mért driftek,
amelyeket az élesítő pre-flight KÖTELEZŐEN újramér:

**D1 — A Song Trainer public felülete ma presentation-only.** Mérve
(`lib/features/song_trainer/public.dart` @ `fbe1e82`): kizárólag két képernyőt
exportál (`song_import_screen.dart`, `song_library_screen.dart`). Az E03-R20-ban
bevezetett `NoteScoringResult`/`NoteScoringNoteResult`
(`lib/features/song_trainer/domain/models/note_scoring_models.dart`) **NINCS** a
barrelben. Következmény: a `song_trainer_context_adapter` **csak** azt fogyaszthatja,
ami a public barrelben van; ha az élesítéskor a scoring-eredmény továbbra sem
publikus, az adapter **degradált** (üres/„nincs adat") Song-szekciót ad, provenance
`unavailable` jelzéssel — és NEM importál song_trainer internal-t. Belső import
kényszere esetén `stopped` + brief-revízió (public-surface bővítés külön körre).

**D2 — A fogyasztott public API-k (mérve `fbe1e82`).** A snapshot KIZÁRÓLAG ezekből
épül: `practice/public.dart` (`PracticeSessionResult`, `PracticeVerdict`,
`PracticeMetrics`, `AggregatedPracticeEntry`, …), `analyze/public.dart`
(`AnalyzeResult`), `progress/public.dart` (`PracticeEntry`, `PracticeStats`),
`streak/public.dart` (`streak_logic`, `daily_challenge`, `streak_provider`),
`settings/public.dart` (capo/input_latency/lab_mode/left_handed/tuning_reference/
visual_latency providerek), `song_trainer/public.dart` (D1 szerint korlátozott).

**D3 — Lab-only inspektálás jele.** A Lab kapu a `settings/public.dart`
`lab_mode_provider`-e; az inspectable view ehhez kötött és a teljes promptot NEM
tartalmazza (csak a strukturált snapshot mezőket + redaction reportot).

A fenti revíziók a kör saját, még nem merge-elt briefjét érintik
(orchestrátor-autonómia, ADR 0087 §2) — merge-elt döntést nem módosítanak.

## 1. Cél

A meglévő feature-ökből (Practice, Song Trainer, Analyze, Progress, Streak,
Settings) minimális, strukturált, redaktált és provenance-olt tutor context
összeállítása egy immutable `TutorContextSnapshot`-ba, amelyet a későbbi
prompt-/orchestration-körök (R12, R16) fogyasztanak. A context KIZÁRÓLAG a
feature-ök `public.dart` szerződéséből épül, request ID-hoz kötött, és a purpose
(intent) szerint determinisztikusan válogat mezőt.

## 2. Jelenlegi állapot

- `lib/features/ai_tutor/` **nem létezik** (greenfield) — mérve `fbe1e82`.
- A hat forrás-feature public barrelje létezik és stabil; a Song Trainer barrel
  presentation-only (§0.0 D1).
- Nincs semmilyen tutor context aggregátor, redaction vagy budget logika.
- A Lab kapu megvan (`settings` `lab_mode_provider`); a context inspektálásához
  nincs view.

## 3. Scope

**Benne:**

- `TutorContextSnapshot` immutable modell request ID-vel, per-mező provenance-szal
  (forrás feature + scorer/schema version).
- `ContextPurpose` (intent) + purpose-specifikus field-allowlist.
- `ContextBudget` — serialization size becslés + determinisztikus truncation.
- Hat adapter, mindegyik KIZÁRÓLAG a saját feature `public.dart`-jából olvas.
- `RedactionReport` — mit hagytunk ki és miért.
- Lab-only `InspectableContextView` (strukturált mezők + redaction; teljes prompt
  NÉLKÜL).

**Kívül — ebben a körben TILOS:**

- bármely source feature internal importja vagy módosítása (public barrel only);
- prompt-építés, model hívás, streaming (R12/R13/R16);
- új tárolt/perzisztált mező vagy storage kulcs;
- Song Trainer public felület bővítése (ha kell → `stopped`, §0.0 D1).

## 4. Engedélyezett fájlok

Csak az alábbi útvonalak módosíthatók. Bármi más → MEGÁLLÁS és jelentés.

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../context/tutor_context_snapshot.dart` | ÚJ | immutable snapshot + request ID + provenance |
| `.../context/tutor_context_assembler.dart` | ÚJ | adapterek orchestrálása, purpose-válogatás |
| `.../context/context_budget.dart` | ÚJ | size becslés + determinisztikus truncation |
| `.../context/context_purpose.dart` | ÚJ | intent + field-allowlist |
| `.../context/redaction_report.dart` | ÚJ | redaction eredmény modell |
| `.../context/inspectable_context_view.dart` | ÚJ | Lab-only view, prompt nélkül |
| `.../context/adapters/practice_context_adapter.dart` | ÚJ | practice/public.dart → context |
| `.../context/adapters/song_trainer_context_adapter.dart` | ÚJ | song_trainer/public.dart → context (D1 degradált) |
| `.../context/adapters/analyze_context_adapter.dart` | ÚJ | analyze/public.dart → context |
| `.../context/adapters/progress_context_adapter.dart` | ÚJ | progress/public.dart → context |
| `.../context/adapters/streak_context_adapter.dart` | ÚJ | streak/public.dart → context |
| `.../context/adapters/settings_context_adapter.dart` | ÚJ | settings/public.dart → context |
| `test/features/ai_tutor/application/context/**` (a listázott fájlok) | ÚJ | assembler/budget/redaction/inspectable + per-adapter teszt |
| `docs/rounds/e04-r05-context-adapters-and-snapshot.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl; **bármely source feature belső fájlja** (adapter
csak a `public.dart`-ot importálhatja — a source feature-t soha nem törheti);
`docs/rag` fejlesztői DSP-korpusz; a `pipeline-queue.tsv`, `HANDOFF.md` és más
körök briefjei. Új teszt-fixture/helper is fájl; listán kívül → `stopped`.

## 5. Kötött architekturális döntések

Az R01 ADR-ekre (0131–0134) épül, azok újratervezése nélkül:

1. **Provider boundary (ADR 0131):** a context CSAK a feature `public.dart`
   szerződéséből épül; source internal import TILOS.
2. **Privacy/consent (ADR 0132):** nyers audio, abszolút path, token/secret és
   teljes importált lyrics NEM kerül a snapshotba; a redaction kötelező és
   tesztelt. A minimum-szükséges elve: purpose-hoz nem tartozó mező kimarad.
3. **Provenance:** minden mező forrás-feature + scorer/schema version taget kap;
   a snapshot immutable és egyetlen request ID-hoz kötött.
4. **Memory policy (ADR 0134):** a snapshot pillanatkép, nem perzisztált állapot;
   inspektálása Lab-only és teljes prompt nélkül történik.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen. Ha az acceptance és
egy kötött döntés ütközik → `stopped` + dokumentált brief-revízió (§0.0), nem
csendes enyhítés.

## 6. Acceptance criteria

- [ ] Minden adapter KIZÁRÓLAG a saját feature `public.dart`-jából importál
      (a teszt `rg`-alapú import-audittal bizonyítja: nulla source-internal import).
- [ ] A snapshot immutable (mutációs kísérlet fordítási hiba / defenzív copy) és
      egyetlen `requestId`-hoz kötött; azonos bemenetre azonos snapshot.
- [ ] **Redaction:** nyers audio (PCM/minta-tömb), abszolút path, token/secret és
      teljes importált lyrics SOHA nem jelenik meg a snapshotban; a redaction
      report felsorolja a kihagyott mezőket. **NEM elfogadható gyengítés:** a
      lyrics „első N karakterének" beengedése redaction helyett — a teljes és a
      csonkolt lyrics egyaránt TILOS a snapshot content mezőiben (csak semleges
      metaadat, pl. cím/hossz mehet).
- [ ] Minden context-mező provenance-szal (forrás feature + scorer/schema version)
      érkezik; hiányzó version → a mező kimarad, nem kap hamis defaultot.
- [ ] Purpose-specifikus field-allowlist: adott `ContextPurpose`-ra csak az
      engedett mezőhalmaz kerül be (teszt: purpose × mező mátrix).
- [ ] A Song Trainer adapter degradált (üres, `unavailable` provenance) szekciót
      ad, ha a scoring public export hiányzik — és nem importál internal-t.
- [ ] Lab-only inspectable view a strukturált mezőket + redaction reportot mutatja,
      teljes promptot NEM (teszt: a view kimenete nem tartalmaz prompt-stringet).

### Kötelező megkülönböztető mátrix — context budget truncation

A `ContextBudget` a becsült serialization méretre (származtatott, **byte/char**)
determinisztikusan csonkol. Legyen `B` a budget limit; a truncation stabil,
prioritás-sorrend szerinti (nem véletlen). A három cellát **`python3 -c`-vel**
kell kiszámolni a tényleges méret-becslő függvénnyel, nem fejben:

| Származtatott érték (becsült méret) | alatta (`< B`) | pontosan rajta (`== B`) | fölötte (`> B`) |
|---|---|---|---|
| snapshot méret vs. budget | teljes snapshot, nincs truncation | kötött inclusive határ-politika (`<=` vs `<` itt dől el) | determinisztikus, prioritás-sorrendű csonkolás + truncation flag |

A „rajta" cella az egyetlen, ami a `<` és a `<=` közti különbséget méri. **NEM
elfogadható gyengítés:** nem-determinisztikus (map-iterációs sorrendtől függő)
csonkolás — a csonkolt mezőhalmaznak azonos bemenetre bitre azonosnak kell lennie.
Adj meg a truncation-hoz eszközt: a snapshot expose-oljon `estimatedSizeBytes`-t
és `truncatedFields` listát, és a teszt ezekre mérjen.

A reviewer legalább egy központi invariánst (pl. a redaction teljességét vagy a
budget „rajta" celláját) eldobható mutációval vagy független reference-számítással
pirosra vált; bemásolt zöld output nem önálló evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/application/context
```

Ez az egyetlen lokális záró gate: `format` → `analyze` → célzott `test` →
`architecture` külön processzekben; nincs `&&`, pipe, `tail` vagy csonkítás. A
full suite + randomizált property + APK CI-t az orchestrátor exact branch
`headSha`-ra indítja (`gh workflow run build-apk.yml --ref <kör-branch>`).

## 8. Implementációs sorrend

1. Írd meg a `context_purpose.dart` + field-allowlist és a snapshot/provenance
   modelleket; RED teszt az immutabilitásra és a purpose-allowlistre.
2. Írd meg adapterenként a public-only RED tesztet (import-audit + fixture).
3. Implementáld az adaptereket, majd az assemblert (purpose-válogatás).
4. Implementáld a redaction reportot és a budget determinisztikus truncationjét
   (méret-becslő + prioritás-sorrend); a boundary-mátrix RED tesztje előbb.
5. Lab-only inspectable view (prompt nélkül).
6. Futtasd a §7 gate-et.

Javasolt commit: `feat(ai-tutor-context): assemble minimal grounded learning context`.

## 9. Kockázatok

- **Song Trainer public hiány (§0.0 D1):** ha az adapter internal-t akarna →
  `stopped`, nem néma import.
- Redaction-rés: új source-mező csendben átszivároghat — az allowlist legyen
  „deny by default", és a teszt tiltó irányból is mérjen.
- Nem-determinisztikus truncation map-sorrendből — stabil rendezés kötelező.

**STOP:** listán kívüli fájl, source-internal import, bizonyítatlan redaction vagy
gyengített mérce helyett dokumentált brief-revízió szükséges.

## 10. Implementation handoff — az implementer tölti ki

- Fájlonkénti összefoglaló + a bizonyító teszt minden viselkedési állításhoz.
- Futtatott parancsok + TÉNYLEGES kimenet (ne állíts sikert, ami nem futott).
- Eltérések a tervtől és okuk; nem futott ellenőrzések és okuk; follow-up issue-k.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r05-context-adapters-and-snapshot-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
