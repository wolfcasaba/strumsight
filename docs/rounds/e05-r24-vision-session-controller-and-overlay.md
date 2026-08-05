# E05-R24 — Vision session controller és realtime overlay

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 24; §10, §24
- **Branch:** `codex/e05-r24-vision-session-controller-and-overlay`
- **Előfeltétel:** **E05-R05, E05-R08, E05-R11, E05-R16, E05-R22, E05-R23 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/application/vision_session_controller.dart",
  "lib/features/vision/application/vision_session_state.dart",
  "lib/features/vision/domain/vision_session.dart",
  "lib/features/vision/domain/vision_session_result.dart",
  "lib/features/vision/presentation/screens/vision_session_screen.dart",
  "lib/features/vision/presentation/overlays/vision_preview_overlay.dart",
  "lib/features/vision/public.dart",
  "lib/app/routing/app_route.dart",
  "lib/app/routing/app_router.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/vision/application/vision_session_controller_test.dart",
  "test/features/vision/application/vision_session_lifecycle_test.dart",
  "test/features/vision/presentation/vision_session_screen_test.dart",
  "docs/rounds/e05-r24-vision-session-controller-and-overlay.md",
]
gate_tests = [
  "test/features/vision",
  "test/core/camera",
  "test/core/l10n_parity_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + az összes felsorolt kör merge;
> olvasd újra az R05 coordinator revoke-sorrendjét, az R23 cue-budget
> szerződését és az R07 overlay-mappingjét. Nincs ÚJ ADR.
> PREPARED→PLANNING, brief commit az implementer indítása ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

## 1. Cél

A teljes vision state machine összekötése: permission → camera lease → quality →
calibration → inference → fusion → feedback, **immutable** állapottal, preview
overlay-jel, és minden kilépési úton felszabadított erőforrással.

## 2. Jelenlegi állapot (mért, megelőző körök)

- Minden építőelem kész és **külön** tesztelt; ami hiányzik, az a **kapcsolat**.
- Az R05 coordinator revoke-ja bontja az ownert, majd a lease-t; az app-háttér
  (`paused|hidden|detached`) azonnal zár, és **nincs auto-resume**.
- Az R23 garantálja: egyszerre **egy** realtime cue, setup-cue elsőbbséggel.
- A repó ismert csapdája: **dispose utáni state-frissítés** (silent no-op osztály).

## 3. Scope

**Benne:** `VisionSessionController` (immutable state, sealed állapotok),
`VisionSession`/`VisionSessionResult` domain modellek, preview overlay
(hand/pose/guitar **quality chipek**, a részletes skeleton csak debug vagy
explicit user-toggle mellett), Pause / Resume / Recalibrate / Stop műveletek,
route + guard, en+hu ARB, **egyszeri** finalizáció.

**Kívül — TILOS:** Practice/Song/Tutor integráció (R25–R27), persistence (R28),
device tier (R29), új metrika vagy policy, pixelfeldolgozás a UI szálon.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../application/vision_session_controller.dart` | ÚJ | state machine |
| `.../application/vision_session_state.dart` | ÚJ | immutable állapotok |
| `.../domain/vision_session.dart` | ÚJ | session azonosság |
| `.../domain/vision_session_result.dart` | ÚJ | eredmény-modell |
| `.../presentation/screens/vision_session_screen.dart` | ÚJ | képernyő |
| `.../presentation/overlays/vision_preview_overlay.dart` | ÚJ | overlay + chipek |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `lib/app/routing/*` | meglévő | **csak** új route + guard |
| `lib/l10n/app_*.arb` | meglévő | **csak additív** kulcs |
| `test/features/vision/*` | ÚJ | controller + lifecycle + widget |
| `docs/rounds/e05-r24-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Nincs frame buffer a provider state-ben** (SDD §8.1). Az állapot csak
   immutable summary + státusz. **NEM elfogadható:** `CameraFrame` vagy
   pixeltömb bármely Riverpod state-ben, még „debug módban" sem.
2. **A UI szál nem végez pixelfeldolgozást és inference-t.** **NEM elfogadható**
   a `build`-ben vagy egy `AnimatedBuilder`-ben futó számítás.
3. **A finalizáció pontosan egyszer emit-el eredményt** — kétszeri Stop, Stop +
   route-leave, Stop + app-háttér esetén is. **NEM elfogadható:** „általában
   egyszer" viselkedés.
4. **Minden kilépési út zár:** Stop / route-leave / app-háttér / hiba / dispose
   — a lease felszabadul, a stream megszűnik, és **nincs** state-frissítés
   dispose után.
5. **Overlay:** alapból csak quality-chipek és az aktuális **egy** cue; a
   részletes skeleton **explicit** kapcsolóval (debug vagy user-toggle),
   alapértelmezetten kikapcsolva (ADR 0161 szellemében: a felhasználó lássa,
   mi történik, de a termék ne a skeleton legyen).
6. **A cue megjelenítés az R23 döntését követi** — a UI **nem** választ cue-t,
   nem szűr, nem rangsorol. **NEM elfogadható:** UI-oldali „még egy kis
   kiegészítő tipp".

## 6. Acceptance criteria

- [ ] **Állapotgép-mátrix:** idle → setup → calibrating → running → paused →
      finalizing → completed, plusz a hibaágak; minden **érvénytelen** átmenet
      kontrollált (nem crash, nem néma no-op) — cellánként assert.
- [ ] **Kilépési-út mátrix (a kör kulcsbizonyítéka):** Stop / route-leave /
      app-háttér / kivétel / dispose — mind az **öt** után: lease szabad,
      stream lezárva, **nincs** dispose utáni state-írás, és **pontosan egy**
      eredmény keletkezett (számlálóval).
- [ ] **Dupla-finalizáció teszt:** Stop + azonnali route-leave → **egy** eredmény.
- [ ] **Provider-state audit teszt:** a state szerializált alakja egy rögzített
      kulcshalmazzal egyezik, és **nem** tartalmaz frame/pixel mezőt.
- [ ] **Cue-teszt:** az overlay pontosan azt az egy cue-t mutatja, amit az R23
      engine ad; több jelölt esetén a UI nem duplikál.
- [ ] **Golden overlay teszt** portrait és landscape módban (a koordináták az
      R07 mappingjéből — nincs widget-oldali korrekció).
- [ ] **Lokalizációs paritás** zöld; a route `visionEnabled` guard mögött.
- [ ] **Valódi-sértés próba (§10):** a finalizáció egyszeresség-őrének
      kiiktatása → a dupla-finalizáció teszt PIROS → visszaállítás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision test/core/camera test/core/l10n_parity_test.dart
```

Külön processzek, nincs `&&`/pipe/`tail`. A valós eszközös jank/profilozás a
device-mátrix **PENDING** sora.

## 8. Implementációs sorrend

1. RED: állapotgép-, kilépési-út- és provider-state audit.
2. Immutable state + controller.
3. Overlay + képernyő (R07 mapping, R23 cue).
4. Route + ARB + golden; gate.

## 9. Kockázatok

- **A dispose utáni state-írás** a repó ismert csapdája; a kilépési-út mátrix
  minden cellájában külön assert kell rá.
- **A skeleton-overlay „termékké" válik** — a SDD §2.2 kifejezetten tiltja;
  a default OFF és a chipek elsőbbsége ezt tartja.
- **A widget saját koordinátamatekot vezet be** → golden teszt portrait +
  landscape mindkét irányban.

**STOP:** frame a state-ben, UI-oldali cue-választás vagy a finalizáció
egyszeresség-őrének lazítása helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r24-vision-session-controller-and-overlay-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
