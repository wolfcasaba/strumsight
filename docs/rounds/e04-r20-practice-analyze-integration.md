# E04-R20 — Practice és Analyze post-session integráció

- **Státusz:** PLANNING (pre-flight 2026-08-06, kód mérve: main @ `58a0ca3`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 20; §35
- **Branch:** `codex/e04-r20-practice-analyze-integration`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R08, R16, R18 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/application/context/adapters/practice_result_context_adapter.dart",
  "lib/features/ai_tutor/application/context/adapters/analyze_result_context_adapter.dart",
  "lib/features/ai_tutor/presentation/widgets/session_tutor_entry_card.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/ai_tutor/application/practice_result_context_adapter_test.dart",
  "test/features/ai_tutor/application/analyze_result_context_adapter_test.dart",
  "test/features/ai_tutor/presentation/session_tutor_entry_card_test.dart",
  "docs/rounds/e04-r20-practice-analyze-integration.md",
]
gate_tests = [
  "test/features/ai_tutor/application",
  "test/features/ai_tutor/presentation",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R08/R16/R18 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5, `HANDOFF.md`. Nincs ÚJ ADR (R01 0132 privacy bővítése).
> `rg`: a Practice Result + Analyze eredmény **public** felülete
> (`lib/features/{practice,analyze}/public.dart`) — az adapter csak ezt fogyasztja,
> NEM a result-UI belsőt; a progress/streak író felület (chat-nyitástól NEM változhat).
> **ARB gen** a gate előtt. PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Pre-flight mérve 2026-08-06, baseline: `main` @ `58a0ca3` (== `origin/main`).**
Előfeltételek merge-elve: E04-R08 (`ddd7674`), R16 (`df25806`), R18 (`104e685`).
Brief-lint (strict): nincs lelet.

**ADR-döntés: nincs ÚJ ADR.** A kör kizárólag már merge-elt döntéseken belül
mozog — ADR 0132 (deterministic-result-primary + immutable context-snapshot) és
az R08 debrief. Nincs új normatív döntés; a mintát követi (R18: „no new ADR,
0131+0134 scope", R19: „0132+0133 scope"). ADR-szám ezért NINCS lefoglalva.

**Mért tények (a briefben hivatkozott utak és tulajdonlás):**

1. **Streak/progress tulajdonlás (§1 rule 2).** A streak-írás KIZÁRÓLAG a
   deterministic result-úton történik, pontosan két hívási helyen:
   `lib/features/practice/application/practice_session_recording.dart:183`
   (`streak.recordPracticeToday(finishedAt)`, practice-completion) és
   `lib/features/analyze/providers/analyze_providers.dart:226`
   (`ref.read(streakProvider.notifier).recordPracticeToday()`, analyze-completion).
   **Egyik sem a chat/tutor út.** A `StreakController.recordPracticeToday` az
   egyetlen streak-mutáló belépő (`lib/features/streak/providers/streak_provider.dart:23`).
   ⇒ A tutor-belépő adapter/kártya CSAK a már előállított eredményt olvassa;
   NEM hívhat `recordPracticeToday`-t, NEM triggerelhet practice/analyze
   újrafuttatást. A „no streak on chat" acceptance így mért őrrel bír.
2. **Cél-státuszok elérhetők (§1 rule 1).** A `deleted-result`,
   `version-mismatch`, `deterministic-fallback` és `capability-aware` NEM
   elérhetetlen átmenettábla-élek, hanem input-előállítható őr-feltételek:
   null/elavult result-referencia, ill. null `AnalyzeResult.diagnostics`
   (`lib/features/analyze/model/analyze_result.dart:24`). Tesztben közvetlenül
   előállíthatók.
3. **Provenance-őr.** A `ContextProvenance`/`TutorContextField.available`
   megköveteli a scorer VAGY schema verziót
   (`lib/features/ai_tutor/application/context/tutor_context_snapshot.dart:78`);
   a meglévő `PracticeContextAdapter._hasVersion` ezt már betartja. Az ÚJ
   `*_result_context_adapter.dart` ugyanezt a guardot vigye.

**Elhatárolás a meglévő adapterektől (anti-duplikáció).** A
`.../context/adapters/` már tartalmaz `practice_context_adapter.dart` és
`analyze_context_adapter.dart` fájlokat — ezek a LIVE tutor-context mezőit
projektálják. Az ÚJ `practice_result_context_adapter.dart` /
`analyze_result_context_adapter.dart` külön cél: a POST-SESSION belépő-kártya
kattintásakor rögzített immutable context-snapshot-referenciát + előre kitöltött
kérdést állítja elő. A reviewer ellenőrizze, hogy az új adapter NEM duplikálja a
meglévő context-adaptert és NEM módosítja a result-UI-t.

### §0.0-R1 revízió (2026-08-06, implementer STOP nyomán — scope NARROWING)

**Mért ütközés.** A brief §4 eredetileg `lib/features/ai_tutor/public.dart`-ot
„előző körökből additív export" címen engedélyezte. Ez a mért állítás **avult**:
a `public.dart` ma ÜRES (csak `library;`), és egy **E04-R01-ben befagyasztott**
őr-teszt tiltja bármely export/import hozzáadását:
`test/features/ai_tutor/ai_tutor_boundary_test.dart` — *"the empty baseline
boundary must not pull in another feature's … internals"* (merge: `814388a`,
ADR 0131–0134). Az implementer helyesen `stopped`-ot jelzett, mert az export a
listán-kívüli őr-teszt módosítását igényelte volna.

**Döntés (ADR 0087 §2 — az engedélyezett-lista SZŰKÍTÉSE, nem tágítása):**
`lib/features/ai_tutor/public.dart` **kikerül** az `allowed_paths`-ból. A kör
teljes leszállítandója (a két `*_result_context_adapter`, a
`SessionTutorEntryCard` és a tesztjeik) az `ai_tutor` feature-ön BELÜL él, és a
`gate_tests` (`test/features/ai_tutor/{application,presentation}`) maradéktalanul
lefedi — az export a public boundaryn NEM előfeltétele sem a kör
acceptance-ének, sem a gate-nek.

- A `public.dart` **befagyasztva üres marad**; az E04-R01 boundary-tesztet TILOS
  módosítani (az egy lezárt kör őre — H2 volna).
- A belépő-kártya **cross-feature bekötése** a Practice/Analyze result-képernyőkbe
  (ami az ai_tutor public felületét igényelné) **külön, jövőbeli kör** dolga; az a
  kör kezeli majd a boundary-teszt együtt-változását a saját scope-jában.
- A `session_tutor_entry_card_test.dart` a kártyát **közvetlen import**tal
  példányosítja (nem a public barrelen át), így a teszt zöld lehet export nélkül.

## 1. Cél

A tutor összekötése a Practice/Analyze eredményekkel úgy, hogy a **deterministic
result elsődleges marad**, és a progress/streak nem torzul.

## 2. Jelenlegi állapot

- Nincs post-session tutor-belépő. A Practice Result (E02-R18) + Analyze eredmény a
  public barrelen át elérhető; R08 debrief + R16 orchestrator + R18 chat kész.
- **Progress/streak** csak tényleges practice-action után változik — chat-nyitástól SOHA.

## 3. Scope

**Benne:** Practice-result + Analyze-result context-adapter (csak public API),
`SessionTutorEntryCard` a Practice Result + Analyze eredményhez, immutable
context-snapshot-reference rögzítés kattintáskor, előre kitöltött szerkeszthető kérdés,
cloud-consent-hiány → deterministic debrief, suggested Practice action, deleted-result/
version-mismatch kezelés.

**Kívül — TILOS:** a Practice/Analyze **result-UI felülírása**, dupla progress/streak,
source-belső import, unsupported metric claimbe emelése.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../application/context/adapters/practice_result_context_adapter.dart` | ÚJ | Practice→context |
| `.../application/context/adapters/analyze_result_context_adapter.dart` | ÚJ | Analyze→context |
| `.../presentation/widgets/session_tutor_entry_card.dart` | ÚJ | belépő kártya |
| `lib/l10n/app_en.arb`, `app_hu.arb` | meglévő | stringek (additív) |
| `test/features/ai_tutor/{application,presentation}/*` | ÚJ | adapter + card tesztek |

> **§0.0-R1:** `lib/features/ai_tutor/public.dart` KIKERÜLT az engedélyezett listáról —
> a boundary-teszt (E04-R01) befagyasztja üresre; a kör export nélkül teljes.
| `docs/rounds/e04-r20-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, a Practice/Analyze **belső** contractja + result-UI,
`docs/rag`, más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. A **deterministic result elsődleges** — a tutor-belépő nem írja felül az eredeti
   result-UI-t (ADR 0132). **NEM elfogadható:** a result-UI módosítása.
2. **Progress/streak csak tényleges practice-action után** változik, chat-nyitástól SOHA.
3. Cloud-consent hiányában **deterministic debrief** jelenik meg (R08).
4. **Unsupported metric nem kerül claimbe**; a context immutable snapshot-reference.

## 6. Acceptance criteria

- [ ] Practice-result entry; Analyze capability-aware entry; consent-flow (cloud/off);
      deleted-result; version-mismatch; deterministic-fallback; practice-action.
- [ ] **No streak on chat:** chat-megnyitás NEM változtat progress/streak-et — teszt;
      reviewer eldobható mutációval (chat-nyitás streak-inkrement) pirosra váltja.
- [ ] Az adapter csak public API-t fogyaszt; unsupported metric nem lesz claim.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/application test/features/ai_tutor/presentation
```

Külön processzek, nincs `&&`/pipe/`tail`. ARB-nál `flutter gen-l10n` a gate előtt.
CI = orchestrátor exact-SHA.

## 8. Implementációs sorrend

1. RED no-streak-on-chat + deterministic-fallback + version-mismatch tesztek.
2. Practice/Analyze adapterek (public API).
3. entry-card + ARB. (NINCS `ai_tutor/public.dart` export — §0.0-R1; a card-teszt
   közvetlen importtal példányosít.)
4. `flutter gen-l10n`; gate.

## 9. Kockázatok

- Dupla progress/streak (chat-nyitás mint „aktivitás") — TILOS; csak valós action.
- Result-UI felülírás kísértése — a belépő additív, nem módosítja a source-t.

**STOP:** result-UI felülírás, dupla progress vagy unsupported-metric-claim helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

**Megvalósítva (2026-08-06).**

- A `PracticeResultContextAdapter` és `AnalyzeResultContextAdapter` kizárólag
  a megfelelő feature `public.dart` szerződését importálja. A result-azonosító,
  összesített mért adatok és a provenance kerülnek immutable context-fieldbe;
  scorer- vagy schema-verzió nélkül nincs available field. Az Analyze adapter
  csak a diagnosztika elérhetőségét viszi át, a diagnosztikai metrikát nem.
- A `SessionTutorEntryCard` a változatlan `TutorContextSnapshot`-ot és a
  szerkeszthető kérdést callbacken adja tovább; consent-off esetén kizárólag a
  deterministic debrief callback elérhető. Törölt result és version mismatch
  külön kontrollált állapot. A kártya nem importál streak/progress API-t és
  nem indít Practice/Analyze újrafuttatást.
- Additív angol és magyar lokalizáció készült. A §0.0-R1 szerint
  `lib/features/ai_tutor/public.dart` és a fagyott boundary-teszt változatlan.

**Futtatott ellenőrzések.**

- `flutter gen-l10n` — sikeres (a `l10n.yaml` konfigurációját használta).
- `flutter test test/features/ai_tutor/application/practice_result_context_adapter_test.dart test/features/ai_tutor/application/analyze_result_context_adapter_test.dart test/features/ai_tutor/presentation/session_tutor_entry_card_test.dart` — 11/11 zöld.
- `tools/round-gate.sh --result-json /tmp/e04-r20-round-gate.json test/features/ai_tutor/application test/features/ai_tutor/presentation` — pass (`exit_code: 0`): format, analyze, application/presentation tesztek, architecture, secrets és l10n zöld.

**Nem futtatott ellenőrzések.** A teljes Flutter suite, property gate és APK
build nem lokális implementer-gate; ezek az orchestrátor exact-SHA CI kapui.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r20-practice-analyze-integration-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
