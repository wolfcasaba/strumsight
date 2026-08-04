# E04-R18 — Tutor Home, Chat UI és streaming UX

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 18; §35
- **Branch:** `minimax/e04-r18-tutor-home-chat-ui`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R13, R16, R17 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** MiniMax M3 (UI-dominált kör, ADR 0069 mért szabály)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/presentation/screens/tutor_home_screen.dart",
  "lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart",
  "lib/features/ai_tutor/presentation/widgets/tutor_message_bubble.dart",
  "lib/features/ai_tutor/presentation/widgets/tutor_composer.dart",
  "lib/features/ai_tutor/presentation/widgets/tutor_banners.dart",
  "lib/features/ai_tutor/presentation/providers/tutor_providers.dart",
  "lib/app/router/app_route.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/features/ai_tutor/public.dart",
  "test/features/ai_tutor/presentation/tutor_chat_screen_test.dart",
  "test/features/ai_tutor/presentation/tutor_home_screen_test.dart",
  "docs/rounds/e04-r18-tutor-home-chat-ui.md",
]
gate_tests = [
  "test/features/ai_tutor/presentation",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R13/R16/R17 merge; olvasd újra
> `AGENTS.md` (**§15.6 MiniMax-szabály**), Chapter 1/5, `HANDOFF.md`. Nincs ÚJ ADR
> (R01 0131–0134 bővítése). `rg`: a route-katalógus `app_route.dart` + a
> `route_literal_guard` mai alakja (a flag mögötti route-regisztráció mintája —
> ld. `e03-r17` anchor); az R16 orchestrator + R13 fake gateway + R17 repo public
> felülete. **ARB gen:** `flutter gen-l10n` a gate előtt. PREPARED→PLANNING, brief
> commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll (MiniMax M3)

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **STOP on scope conflict:** listán kívüli fájl,
hiányzó public contract, ellentmondó acceptance vagy megkülönböztetésre alkalmatlan
teszt esetén `stopped` — **nincs néma scope-tágítás és nincs mércegyengítés
kód-kommentben megindokolva** (MiniMax mért hibamódja). Az implementer nem hív `gh`-t.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Nincs előre kiosztott ADR.
**Motor:** MiniMax M3 — UI/ARB > domain+app+data, a kör UI-dominált (ADR 0069).

## 1. Cél

A beszélgetéses tutor első teljes, **accessibility-kompatibilis** Flutter felülete,
**fake gatewayre** építve — flag mögött, valós cloud nélkül.

## 2. Jelenlegi állapot

- Nincs tutor UI (SDD §3.2). R13 fake gateway + R16 orchestrator + R17 repo kész —
  a UI ezekre köt.
- A route flag mögött regisztrálódik; a `route_literal_guard` tiltja a nyers
  route-literált (E03-R17 minta). Flag OFF ⇒ route hiányzik.

## 3. Scope

**Benne:** Tutor Home + virtualizált Chat, message-bubble content-blockonként,
streaming-batching (screen reader nem olvas minden tokent), stop/retry/copy/feedback,
offline/consent/rate-limit/error banner (megkülönböztetve), draft-input megőrzés
route-váltáskor, raw-HTML/unknown-block biztonságos kezelés, `aiTutorEnabled` flag
mögötti routing, hu/en semantics.

**Kívül — TILOS:** valódi cloud/gateway, evidence/action-card (R19), új domain/app
logika, source-belső import.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../presentation/screens/tutor_home_screen.dart` | ÚJ | Home |
| `.../presentation/screens/tutor_chat_screen.dart` | ÚJ | virtualizált Chat |
| `.../presentation/widgets/tutor_message_bubble.dart` | ÚJ | content-block bubble |
| `.../presentation/widgets/tutor_composer.dart` | ÚJ | input + draft |
| `.../presentation/widgets/tutor_banners.dart` | ÚJ | offline/consent/rate/error |
| `.../presentation/providers/tutor_providers.dart` | ÚJ | Riverpod wiring (fake gateway) |
| `lib/app/router/app_route.dart` | meglévő | flag mögötti route (additív) |
| `lib/l10n/app_en.arb`, `app_hu.arb` | meglévő | UI-stringek (additív) |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `test/features/ai_tutor/presentation/*` | ÚJ | widget-tesztek fake gatewayjel |
| `docs/rounds/e04-r18-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje, nyers route-literál. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. A UI **fake gatewayjel teljesen tesztelhető**; valódi cloud nincs (ADR 0131).
2. A **routing az `aiTutorEnabled` flag mögött** — flag OFF ⇒ route hiányzik. **NEM
   elfogadható:** flag-független route-regisztráció.
3. A screen reader **nem olvas fel minden token-frissítést** (streaming-batching).
4. Raw-HTML/unknown-block **biztonságosan** (nem futtatható HTML).

## 6. Acceptance criteria (runnable artifact + mátrix — MiniMax-kötelező)

- [ ] empty-state; send; stream; cancel; retry; offline; consent; unknown-block;
      large-text; **semantics**; hu/en; scroll-anchoring — mind widget-teszt fake gatewayjel.
- [ ] **Flag-mátrix:** `aiTutorEnabled` OFF → route hiányzik (navigáció nem éri el);
      ON → elérhető. Mindkét cella tesztelt (nem elég az ON).
- [ ] A stream nem akad; a banner-állapotok **különböznek** (offline≠consent≠rate≠error).

A mérce **futtatható artefaktum** (a fenti widget-teszt-lista), nem prompt-szöveg.
A reviewer a flag-gating cellát eldobható mutációval (flag-check eltávolítása) pirosra váltja.

## 7. Kötelező ellenőrzések

Szó szerinti gate (ezt futtasd, változtatás nélkül):

```bash
tools/round-gate.sh test/features/ai_tutor/presentation
```

Egyetlen lokális záró gate: format → analyze → célzott test → architecture külön
processzekben; nincs `&&`, pipe, `tail` vagy csonkítás. ARB-változásnál `flutter
gen-l10n` a gate előtt. Full suite + property + APK CI = orchestrátor exact-SHA.

## 8. Implementációs sorrend

1. RED flag-gating + streaming + semantics widget-tesztek.
2. providers (fake gateway) + Home + Chat.
3. bubble/composer/banners + ARB.
4. flag mögötti route; `flutter gen-l10n`; gate.

## 9. Kockázatok

- Streaming-jank virtualizáció nélkül — virtualizált lista + batch.
- A11y: minden token felolvasása (screen reader spam) — batch + semantics-merge.
- Route-literál guard (E03-R17) — typed route, nem nyers string.

**STOP:** flag-független route, mércegyengítés vagy scope-tágítás helyett dokumentált
brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r18-tutor-home-chat-ui-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
