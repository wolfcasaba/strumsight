# E05-R24 — Vision session controller és realtime overlay

- **Státusz:** PLANNING (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`;
  pre-flight revízió 2026-08-08, kód mérve: `main` @ `b14a753`, E05-R22/R23
  merge után)
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
  "test/features/vision/presentation/vision_preview_overlay_test.dart",
  "test/features/vision/presentation/vision_session_routing_test.dart",
  "test/features/vision/presentation/goldens/vision_preview_portrait.png",
  "test/features/vision/presentation/goldens/vision_preview_landscape.png",
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

**PREPARED → mérve `origin/main` @ `b14a753` (E05-R05/R08/R11/R16/R22/R23
MERGED — a teljes előfeltétel-lista teljesül), egy javítás (elavult
ADR-hivatkozás), nulla scope-eltérés.** Az eredeti PREPARED szöveg
2026-08-05-én íródott, az E05-R22/R23 (observation fusion, feedback policy,
cue budget) kód létezése előtt.

1. **R1 — Stale ADR-hivatkozás javítva.** A §5 pont 5 „(ADR 0161 szellemében:
   ...)" a batch-írás idején fenntartott, **átszámozás előtti** szám
   (`docs/rounds/epic-05-batch-index.md` §3: „0161–0166 → 0178–0183"
   blokk-eltolás — az Epic 4 hátralévő körei a tervezett 0161–0170 tartomány
   fölé futottak, ld. E05-R01 §0.0). `ls docs/adr/ | grep 0161` **nulla
   találat** — a fájl sosem létezett ezen a számon. A batch-index §3 táblája
   szerint az eredeti „0161 | R01 | Vision privacy by default" tétel a
   ténylegesen elfogadott [`ADR 0178`](../adr/0178-vision-privacy-by-default.md)
   ugyanezzel a címmel („Vision privacy by default", elfogadva E05-R01
   pre-flight, 2026-08-06). Ez a `0161→0178` pár nem esik egybe azzal a
   `0164→0181`/`0162→0179` párral, amit E05-R10/R11/R16 §0.0 R1 korábban
   önállóan javított — de ugyanabból a batch-index §3 shift-táblából
   számolódik, amit az a három független találat már megerősített: a
   mechanizmus bizonyított, ez az első alkalom, hogy pont ez a sor
   (`0161`) kerül elő egy §5 hivatkozásban. A skeleton-overlay-alapból-visszafogott állítás szó szerinti
   forrása egyébként nem is ADR, hanem az **SDD Ch6 §2.2** („Nem a skeleton
   overlay a termék") és **§24.2** („skeletal overlay alapértelmezetten
   visszafogott… külön kapcsolható debug landmark mód") — a §5 pont 5 szövege
   ezt a két SDD-hivatkozást kapja elsődleges forrásként, az ADR 0178-at
   csak a „szellemében" (privacy-by-default motiváció) másodlagos
   kontextusként. **Nincs ÚJ ADR** — a hivatkozott ADR már elfogadott, ez a
   kör annak szellemi kontextusát idézi, nem új döntést hoz (ugyanaz az
   indoklás, mint az R07 brief saját „Nincs ÚJ ADR" pre-flight jegyzeténél —
   R07 a szerkezetileg analóg „meglévő kontraktusokat összekötő" kör-típus).
2. **Mért megerősítések (nem igényeltek javítást):** az R05
   `CameraSessionCoordinator.revokeActive()` ténylegesen az owner
   `onRevoke` teardownját futtatja ELŐSZÖR, és csak a `finally`-ban szabadítja
   fel a lease-t (`_finishRelease()`) — a brief §2 „bontja az ownert, majd a
   lease-t" állítása pontos (`lib/core/camera/camera_session_coordinator.dart`).
   A meglévő `CameraLifecycleGuard` (`lib/core/camera/camera_lifecycle_guard.dart`)
   már ma is pontosan az „app-háttér azonnal zár, nincs auto-resume"
   szerződést adja (`inactive`/`resumed`-nél szándékosan no-op) — újrahasználható,
   nem kell újraírni. Az R23 `CueBudget.selectRealtime(...)` egyetlen
   `VisionInsight?`-ot ad vissza — a brief „a UI nem választ cue-t" állítása
   pontos. Az R07 „overlay-mapping" a `PreviewFit`/`CameraTransform`
   screen-fit kontraktusa (`lib/core/camera/preview_fit.dart`) — **nem**
   azonos az R15 `GuitarLandmarkMapper` guitar-space homographyjával; a
   brief helyesen az előbbire hivatkozik (golden overlay teszt portrait/
   landscape = preview-fit, nem guitar-space mapping).
3. **A route-guard mintája tisztázva (nem brief-hiba, csak explicit jegyzet
   a kétértelműség elkerülésére):** az `app_router.dart` meglévő mintája
   (`visionSetup`, `visionGuitarGeometry`) **kettős** flag-gate — a globális
   `visionEnabled` ÉS egy per-feature flag (`visionSetupEnabled`,
   `visionGuitarGeometryEnabled`). A §6 acceptance-cella viszont kifejezetten
   **egyetlen** flaget nevez meg („a route `visionEnabled` guard mögött") —
   ez SZÁNDÉKOS eltérés az előd-mintától, mert `lib/app/config/feature_flags.dart`
   **nincs** az `allowed_paths`-on: egy új per-feature flag hozzáadása ezt a
   fájlt is módosítaná (H3). Az implementer a meglévő globális `visionEnabled`
   flaget használja, ÚJ flaget nem vezet be.
4. **R4 — Tesztútvonal-rés pótolva, mérve az implementer STOP-jelzéséből
   (2026-08-08 12:21 UTC).** Terra a §6 acceptance criteria szerint (Cue-teszt,
   Golden overlay teszt portrait/landscape, Lokalizációs paritás + route-guard)
   implementált, de a három eredetileg felsorolt teszt-fájlnév helyett a
   tényleges lefedettséget más bontásban adta: a lifecycle-mátrix a
   `vision_session_controller_test.dart`-ba olvadt (a külön
   `vision_session_lifecycle_test.dart` nem jött létre — az eredeti bejegyzés
   a listán marad, felhasználatlanul, ártalmatlan), a „screen test" helyett
   pedig két célzottabb fájl: `vision_preview_overlay_test.dart` (chip/cue/
   skeleton-toggle + golden) és `vision_session_routing_test.dart`
   (`visionEnabled`-only guard, a §0.0 R3 pontosan ezt várta el). A
   golden-tesztekhez két PNG-fixture is kellett. Egyik sem volt az
   `allowed_paths`-on — a scope-audit helyesen `stopped`-ra váltott, commit
   nem történt (a leállás pillanatában 6 módosított + 11 új fájl állt a
   working tree-ben, mind a §4 táblán belül a most pótolt 4 kivétellel). A
   négy hiányzó pontos útvonal (nem könyvtár-prefix, hogy a scope-audit
   tovább is szűk maradjon) felkerült a fenti `allowed_paths` tömbre:
   `test/features/vision/presentation/vision_preview_overlay_test.dart`,
   `test/features/vision/presentation/vision_session_routing_test.dart`,
   `test/features/vision/presentation/goldens/vision_preview_portrait.png`,
   `test/features/vision/presentation/goldens/vision_preview_landscape.png`.
   Ez a §2 „engedélyezett-fájllista szűkítését" bullet testvér-esete
   (bővítés, nem szűkítés), de a kör SAJÁT, még nem merge-elt allowed_paths-át
   érinti, ezért nem H3 — a fájlok tartalmilag a §6 saját, már elfogadott
   acceptance-köréhez tartoznak (golden overlay teszt, cue-teszt, route-guard
   teszt), nem új funkció. A munkapéldányban a stop óta semmi nem lett
   commitolva — a teljes diff a working tree-ben ül, veszteség nélkül.

> **Módosítás (ADR 0112 önjavító kör, 2026-08-08, H5):** az `allowed_paths` a
> fenti 4 `test/features/vision/presentation/...` bejegyzéssel (2 teszt-fájl +
> 2 golden PNG) bővült. A `codex/e05-r24-vision-session-controller-and-overlay`
> ágon már folyó implementáció (saját pre-flight revíziója, munkapéldány-mérés)
> ugyanezt a négy pontos útvonalat igényelte a §6 acceptance saját golden-
> overlay/cue/route-guard teszteihez — emiatt a
> `tools/tests/test_pipeline_integration.py::test_open_rounds_follow_the_measured_engine_rule`
> mért összetétele (UI/ARB=9 > core=6) már `minimax`-ot várt, miközben
> `docs/execution/pipeline-queue.tsv` E05-R24 sora még a `codex` értéket
> tartotta (Router CI kétszer piros ugyanarra a subTest-re → H5 halt). Ez a
> self-heal kizárólag ezt a listát hangolja a mérce elé; az implementáció
> maga (§10 handoff, a teljes pre-flight indoklás) a kör saját branchjén él és
> azzal érkezik main-re.

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
   alapértelmezetten kikapcsolva (SDD Ch6 §2.2 „Nem a skeleton overlay a
   termék" + §24.2 „skeletal overlay alapértelmezetten visszafogott… külön
   kapcsolható debug landmark mód", [ADR 0178](../adr/0178-vision-privacy-by-default.md)
   privacy-by-default szellemében — ld. §0.0 R1: a felhasználó lássa, mi
   történik, de a termék ne a skeleton legyen).
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

### Módosítások

- `VisionSessionController` + immutable `VisionSessionState`: explicit
  permission → setup → calibration → exclusive `visionPractice` lease →
  running/paused lifecycle. A frame-listener nem olvas pixel-bufferből és nem
  ír frame-et state-be; csak a sessionen belüli számlálót tartja.
- `VisionSession` és raw-media-mentes `VisionSessionResult`: a finalization
  future-őr Stop/route-leave/app-háttér/hiba/dispose versenyben is egyetlen
  aggregate-et és listener-emissziót ad. A close sorrend stream → capture →
  lease, az R05 revoke-pathját tiszteletben tartva.
- `VisionPreviewOverlay`: hand/pose/guitar minőség-chip + kizárólag az R23
  által átadott egy cue; debug landmark réteg default OFF. A landmark mapping
  az R07 `PreviewFit` → `CameraTransform.previewToOverlay` utat használja.
- Új `/vision/session` route, kizárólag a meglévő `visionEnabled` flag mögött,
  valamint additív en/hu szövegek és `public.dart` exportok.

### Bizonyíték

- `flutter test test/features/vision/application/vision_session_controller_test.dart`
  → **10/10 PASS**: állapotgép, summary-only state audit, Stop/route-leave/
  app-háttér/stream-hiba/dispose exit-mátrix és dupla-finalizáció.
- `flutter test test/features/vision/presentation/vision_preview_overlay_test.dart`
  → **3 PASS, 2 skip** (golden-ek normál futásban host-policy szerint opt-in);
  `GOLDENS=1 flutter test --update-goldens ...` → **5/5 PASS**, portrait és
  landscape golden-ek generálva.
- `flutter test test/features/vision/presentation/vision_session_routing_test.dart`
  → **2/2 PASS**: `visionEnabled` az egyetlen route guard.
- Valódi-sértés próba: a `_finalization` in-flight őr ideiglenes kiiktatása
  után a „Stop + route leave” teszt **PIROS** volt (2 resultot mért); az őr
  visszaállítása után a célzott suite ismét zöld.

### Nem futtatott ellenőrzés

- A kötelező teljes kör-gate még futtatásra vár; a valós készülékes
  jank/profilozás továbbra is a brief szerinti device-mátrix PENDING sora.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r24-vision-session-controller-and-overlay-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
