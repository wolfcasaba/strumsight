# E04-R03 — Student profile, guitar profile, goals és consent

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 3; §35
- **Branch:** `codex/e04-r03-student-guitar-profile-goals-consent`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R01 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/domain/models/student_profile.dart",
  "lib/features/ai_tutor/domain/models/guitar_profile.dart",
  "lib/features/ai_tutor/domain/models/learning_goal.dart",
  "lib/features/ai_tutor/domain/models/tutor_consent.dart",
  "lib/features/ai_tutor/data/local/tutor_profile_codec.dart",
  "lib/features/ai_tutor/public.dart",
  "test/features/ai_tutor/domain/student_profile_test.dart",
  "test/features/ai_tutor/domain/tutor_consent_test.dart",
  "test/features/ai_tutor/data/tutor_profile_codec_test.dart",
  "docs/rounds/e04-r03-student-guitar-profile-goals-consent.md",
]
gate_tests = [
  "test/features/ai_tutor/domain",
  "test/features/ai_tutor/data",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R01 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5, `HANDOFF.md`. Nincs ÚJ ADR — a §5 a R01 **0132**
> (privacy/consent) + **0134** (memory) ADR-re hivatkozik; igazold a végleges
> számokat. `rg`: domain-purity őr + R02 ID-készlet mai alakja. PREPARED→PLANNING,
> brief commit a kör-branchre az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract/ellentmondó
acceptance → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Nincs előre kiosztott
ADR (R01 0132/0134 bővítése).

## 1. Cél

A személyre szabás és az adatvédelmi döntések explicit, **megtekinthető**
domainjének létrehozása — a consent szerkezetileg elkülönített tengelyekkel.

## 2. Jelenlegi állapot

- `lib/features/ai_tutor/domain/` ma csak az R02 conversation/message modelleket
  tartalmazza; profil/goal/consent nincs (greenfield).
- A `SongMetadata`/`PracticeSessionConfig` value-equal, validált, immutable domain
  a követendő precedens (E03-R02 / E02-R03).
- Consent-precedens az appban nincs tutor-specifikusan — ez a kör vezeti be.

## 3. Scope

**Benne:** `StudentProfile` (szint/preferenciák/avoid-lista), `GuitarProfile`
(hangszer/tuning/capo referencia), `LearningGoal` (aktív célok), `TutorConsent`
(model-use / storage / evaluation **külön** tengely), verziózott codec.

**Kívül — TILOS:** UI (R22), repository/storage-írás (R17), cloud-hívás, provider-SDK.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/models/student_profile.dart` | ÚJ | tanulói profil |
| `.../domain/models/guitar_profile.dart` | ÚJ | hangszerprofil |
| `.../domain/models/learning_goal.dart` | ÚJ | célmodell |
| `.../domain/models/tutor_consent.dart` | ÚJ | granular consent |
| `.../data/local/tutor_profile_codec.dart` | ÚJ | verziózott codec |
| `lib/features/ai_tutor/public.dart` | R01/R02-ből | additív export |
| `test/features/ai_tutor/domain/*`, `.../data/tutor_profile_codec_test.dart` | ÚJ | tesztek |
| `docs/rounds/e04-r03-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. A **consent három független tengely** (model-use / storage / evaluation) — egyik
   engedélyezése soha nem implikálja a másikat (ADR 0132). **NEM elfogadható:**
   egyetlen összevont „AI engedélyezve" boolean.
2. Minden modell immutable, value-equal, validált, verziózott codec-cel (ADR 0134).
3. A domain Flutter-/provider-SDK-mentes (purity-őr).
4. Nyers audio/PII-mező nincs a profilban.

## 6. Acceptance criteria

- [ ] `TutorConsent` a három tengelyt külön reprezentálja és round-tripeli; a
      grant/revoke minden tengelyre függetlenül tesztelt (mind a 3 kombináció-él).
- [ ] `StudentProfile`/`GuitarProfile`/`LearningGoal` validáció + value-equality +
      immutabilitás literálisan tesztelt (stabil validációs kódkészlet).
- [ ] Codec round-trip bit-stabil; ismeretlen/hiányzó mező policy dokumentált+tesztelt.
- [ ] Domain purity-őr zöld; **≥90% coverage** az új domainen.

A reviewer a consent-függetlenséget eldobható mutációval (egy tengely implikálja a
másikat) pirosra váltja.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/domain test/features/ai_tutor/data
```

Külön processzek, nincs `&&`/pipe/`tail`. CI = orchestrátor.

## 8. Implementációs sorrend

1. RED consent-tengely + validációs tesztek.
2. Modellek + codec.
3. Additív export; gate.

Javasolt commit: `feat(ai-tutor-domain): add student profile goals and granular consent`.

## 9. Kockázatok

- A consent-tengelyek összemosása csábító a UI-kényelemért — a domain szinten TILOS.
- Retention-mező itt csak modellezhető; a tényleges érvényesítés R17/R22.

**STOP:** összevont consent, provider-SDK import vagy mércegyengítés helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r03-student-guitar-profile-goals-consent-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
