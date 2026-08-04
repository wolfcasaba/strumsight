# E04-R22 — Profile, privacy, data és consent UI

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 22; §35
- **Branch:** `codex/e04-r22-profile-privacy-data-consent-ui`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R03, R17 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/presentation/screens/tutor_profile_screen.dart",
  "lib/features/ai_tutor/presentation/screens/tutor_privacy_screen.dart",
  "lib/features/ai_tutor/presentation/screens/tutor_data_screen.dart",
  "lib/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart",
  "lib/app/router/app_route.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/features/ai_tutor/public.dart",
  "test/features/ai_tutor/presentation/tutor_privacy_screen_test.dart",
  "test/features/ai_tutor/presentation/tutor_data_screen_test.dart",
  "docs/rounds/e04-r22-profile-privacy-data-consent-ui.md",
]
gate_tests = [
  "test/features/ai_tutor/presentation",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R03/R17 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5, `HANDOFF.md`. Nincs ÚJ ADR (R01 **0132** privacy +
> **0134** memory bővítése). `rg`: az R03 consent-tengelyek + R17 memory/delete-all
> repo public felülete; a flag mögötti route-minta. **ARB gen** a gate előtt.
> PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Nincs előre kiosztott ADR.

## 1. Cél

A felhasználó számára **teljesen átlátható** profil-, memória-, consent-, retention-,
export- és törlésvezérlés — a delete-all scope egyértelmű.

## 2. Jelenlegi állapot

- Nincs privacy/profile UI. R03 granular consent + R17 memory/delete-all repo kész —
  a UI ezek fölé épül.
- A három consent-tengely (model-use/storage/evaluation) külön kapcsolható (R03).

## 3. Scope

**Benne:** student+guitar profile editor, aktív célok, cloud-AI consent képernyő
(plain-language), **külön** model-use/storage/evaluation consent, memory-fact lista +
edit, retention-beállítás, conversation export + törlés, **delete-all-AI-data** exact
scope-listával, consent-revoke → pending-request policy, cloud-sync-hiba local vs
remote-pending külön jelzés.

**Kívül — TILOS:** új consent/memory domain-logika (R03/R17), provider-SDK, source-belső import.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../presentation/screens/tutor_profile_screen.dart` | ÚJ | profil editor |
| `.../presentation/screens/tutor_privacy_screen.dart` | ÚJ | consent képernyő |
| `.../presentation/screens/tutor_data_screen.dart` | ÚJ | export + delete-all |
| `.../presentation/providers/tutor_privacy_providers.dart` | ÚJ | Riverpod wiring |
| `lib/app/router/app_route.dart` | meglévő | flag mögötti route (additív) |
| `lib/l10n/app_en.arb`, `app_hu.arb` | meglévő | privacy szövegek (additív) |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `test/features/ai_tutor/presentation/*` | ÚJ | consent/delete widget-tesztek |
| `docs/rounds/e04-r22-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. A **consent granular** (három tengely külön, R03/ADR 0132); a **delete-all scope
   egyértelmű** és tényleges (R17). **NEM elfogadható:** összevont consent vagy
   „részleges" delete-all félrevezető szöveggel.
2. Consent-revoke **törli/leállítja** a pending requestet policy szerint.
3. Cloud-sync-hiba → **local vs remote-pending külön** jelzés (nem néma).
4. A privacy-szöveg **lokalizált** (hu+en).

## 6. Acceptance criteria

- [ ] profile-edit; goal-edit; consent grant/revoke (tengelyenként); memory-edit/delete;
      retention; export; **delete-all confirmation** exact scope-listával; pending-request-cancel;
      remote-delete-failure külön jelzés; semantics.
- [ ] **Delete-all** a UI-ból ténylegesen az R17 delete-all-t hívja és a scope-lista
      pontos — teszt; reviewer eldobható mutációval (scope-lista ≠ tényleges törlés)
      pirosra váltja.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/presentation
```

Külön processzek, nincs `&&`/pipe/`tail`. ARB-nál `flutter gen-l10n` a gate előtt.
CI = orchestrátor exact-SHA.

## 8. Implementációs sorrend

1. RED delete-all-scope + consent-tengely + remote-failure tesztek.
2. providers + profile/privacy/data screen.
3. flag mögötti route + ARB.
4. `flutter gen-l10n`; gate.

## 9. Kockázatok

- Félrevezető delete-all szöveg (scope ≠ tényleges) — a scope-lista mérve egyezzen.
- Consent-tengely összemosás a UI-kényelemért — TILOS (R03 domain-szerződés).

**STOP:** összevont consent, félrevezető delete-all vagy néma cloud-hiba helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r22-profile-privacy-data-consent-ui-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
