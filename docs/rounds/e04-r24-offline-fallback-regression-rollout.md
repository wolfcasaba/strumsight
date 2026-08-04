# E04-R24 — Offline fallback, teljes regresszió és fokozatos rollout (EPIC-ZÁRÓ)

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 24; §36 (Epic 4 végső DoD); §35
- **Branch:** `codex/e04-r24-offline-fallback-regression-rollout`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R01…R23 MIND merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/application/offline/local_tutor_fallback.dart",
  "lib/features/ai_tutor/public.dart",
  "docs/sdd/epic-04-completion-report.md",
  "docs/baseline/epic-04-performance.md",
  "docs/runbooks/ai-tutor-rollout.md",
  "test/features/ai_tutor/application/local_tutor_fallback_test.dart",
  "test/app/offline_network_guard_test.dart",
  "docs/rounds/e04-r24-offline-fallback-regression-rollout.md",
]
gate_tests = [
  "test/features/ai_tutor/application",
  "test/app/offline_network_guard_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + az összes E04-R01…R23 merge;
> olvasd újra `AGENTS.md`, Chapter 1/5 (**§36 végső DoD**), `HANDOFF.md`,
> `docs/LESSONS.md`. **Nincs ÚJ ADR** (záró/regressziós kör). `rg`: a teljes
> `ai_tutor` feature public felülete + a flag-készlet + `offline_network_guard`
> mai alakja. PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió — ZÁRÓ-KÖR WAIVER

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Nincs előre kiosztott ADR.

**HUMAN-REVIEW WAIVER (user-döntés 2026-08-04, ld. `epic-04-batch-index.md` §6):**
ez a záró kör **NEM** kap ADR 0087 §7 szerinti **kézi epic-záró indítást** — a
queue-ban `pending` (auto, engine=codex). A brief **pre-decidálja** az összes emberi
kérdést, hogy a pre-flightnak ne legyen eldöntetlen pontja:

- **Rollout-létra (eldöntve):** internal → Lab → opt-in beta → limited production → GA.
- **Flag-politika (eldöntve):** `aiTutorEnabled` + `aiTutorCloudEnabled` a merge-kor
  **OFF** marad; a **GA-flip pipeline-on kívüli, külön user/termék döntés**, amelyet a
  `docs/runbooks/ai-tutor-rollout.md` rögzít. → a pre-flightban **nincs** rollout-kérdés.
- **ADR (eldöntve):** nincs új architekturális ADR a záró körben.

**Ami a waiver mellett is VÁLTOZATLAN:** az automata **Claude független review**
(ADR 0055), az **exact-SHA zöld CI** (teljes Flutter suite + randomizált property +
APK + backend), és a **HORIZON valós-eszközös elfogadás** — ez utóbbi a merge UTÁNI
**termék-elfogadás**, nem pipeline-kapu. A waiver kizárólag a kézi epic-záró indítást ejti.

## 1. Cél

Az Epic lezárása **stabil offline élménnyel**, teljes rendszerellenőrzéssel és
biztonságos, dokumentált feature-rollouttal.

## 2. Jelenlegi állapot

- R01–R23 után a teljes tutor-stack kész, flag mögött. Hiányzik: egységes offline
  fallback-integráció, a completion-report, a performance-baseline és a rollout-runbook.
- Az `offline_network_guard` (E01-R16) őrzi a 0-request offline utat — cloud AI OFF
  állapotban nincs tutor network request.

## 3. Scope

**Benne:** `LocalTutorFallback` (deterministic + retrieval offline fallback),
capability-resolver integráció (online/offline/limit/consent), teljes regresszió-futtatás,
latency-mérés, valós eszközös hálózatvesztés/background-checklist, cloud-off no-network
igazolás, delete-all igazolás, rollout-lépcsők + rollback-runbook, README/HANDOFF/
completion-report frissítés.

**Kívül — TILOS:** új tutor-feature, új ADR, flag GA-flip a merge-ben, source-belső import.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../application/offline/local_tutor_fallback.dart` | ÚJ | offline fallback integráció |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `docs/sdd/epic-04-completion-report.md` | ÚJ | epic zárójelentés |
| `docs/baseline/epic-04-performance.md` | ÚJ | latency baseline |
| `docs/runbooks/ai-tutor-rollout.md` | ÚJ | rollout + rollback + GA-döntés |
| `test/features/ai_tutor/application/local_tutor_fallback_test.dart` | ÚJ | fallback tesztek |
| `test/app/offline_network_guard_test.dart` | meglévő | cloud-off no-network regresszió |
| `docs/rounds/e04-r24-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. (A README/HANDOFF frissítést az orchestrátor végzi a záró rituáléban,
nem az implementer-diff — ADR 0055.) Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. Az offline fallback **hasznos és őszinte**: cloud nélkül determinisztikus debrief +
   retrieval; a capability-resolver **őszintén** jelzi az online/offline/limit/consent állapotot.
   **NEM elfogadható:** offline állapotban cloud-képességet ígérő UI.
2. **Cloud AI OFF ⇒ nincs tutor network request** (`offline_network_guard`).
3. Nincs új ADR; a flagek **OFF** maradnak (GA külön user-döntés a runbookban).

## 6. Acceptance criteria (Epic 4 végső DoD, §36)

- [ ] **full Flutter suite** + **backend suite** + **prompt snapshots** + **knowledge
      hashes** + **tool contracts** + **evaluation gate** mind zöld (CI).
- [ ] **offline no-network:** cloud AI OFF ⇒ `offline_network_guard_test.dart` zöld,
      nincs tutor request; reviewer eldobható mutációval (offline-ban cloud-hívás) pirosra váltja.
- [ ] **delete-all** (local + remote-policy) igazolt; **feature-flag rollback** tesztelt.
- [ ] **real-device checklist** dokumentált (hálózatvesztés + background) — HORIZON,
      a merge UTÁNI termék-elfogadás.
- [ ] `epic-04-completion-report.md` + `epic-04-performance.md` + `ai-tutor-rollout.md`
      elkészült; a §36 DoD-checklist minden cellája lefedve.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/application test/app/offline_network_guard_test.dart
```

Külön processzek, nincs `&&`/pipe/`tail`. **A teljes suite + property + APK + backend
a CI-ben fut** (orchestrátor exact-SHA dispatch) — a záró körnél ez a valódi mérce.
A synthetic green nem „done": a HORIZON valós-eszközös menet a merge utáni termék-elfogadás.

## 8. Implementációs sorrend

1. RED offline-fallback + cloud-off-no-network tesztek.
2. `LocalTutorFallback` + capability-resolver integráció.
3. completion-report + performance-baseline + rollout-runbook.
4. Gate; orchestrátor exact-SHA teljes CI + záró rituálé (HANDOFF/git-notes/Viking).

## 9. Kockázatok

- Offline „cloud-ígéret" (őszintétlen capability) — a resolver-jelzés kötelező.
- A záró kör scope-tágulhat („még egy kis feature") — TILOS; csak fallback + zárás.
- README/HANDOFF az orchestrátoré (ADR 0055), nem implementer-diff.

**STOP:** új feature, őszintétlen offline-capability vagy flag GA-flip a merge-ben
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r24-offline-fallback-regression-rollout-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
A **záró-kör waiver** nem érinti ezt a független review-t (ld. §0.0).
