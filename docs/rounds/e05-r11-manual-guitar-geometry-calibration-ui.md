# E05-R11 — Manual guitar geometry calibration UI

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 11; §13.3, §17.1
- **Branch:** `minimax/e05-r11-manual-guitar-geometry-calibration-ui`
- **Előfeltétel:** **E05-R07, E05-R08, E05-R10 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** MiniMax M3 (UI-dominált kör, ADR 0069 mért szabály)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/presentation/screens/guitar_calibration_screen.dart",
  "lib/features/vision/presentation/widgets/guitar_anchor_editor.dart",
  "lib/features/vision/presentation/widgets/guitar_geometry_preview.dart",
  "lib/features/vision/presentation/providers/guitar_calibration_providers.dart",
  "lib/features/vision/application/guitar_calibration_controller.dart",
  "lib/features/vision/public.dart",
  "lib/app/routing/app_route.dart",
  "lib/app/routing/app_router.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/vision/presentation/guitar_calibration_screen_test.dart",
  "test/features/vision/application/guitar_calibration_controller_test.dart",
  "docs/rounds/e05-r11-manual-guitar-geometry-calibration-ui.md",
]
gate_tests = [
  "test/features/vision",
  "test/core/l10n_parity_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R07/R08/R10 merge; olvasd újra
> `AGENTS.md` (**§15.6 MiniMax-szabály**), az R10 `GuitarCalibration` mezőit és
> validity-okait, valamint az R07 `NormalizedPoint`/preview-fit API-ját.
> Nincs ÚJ ADR (0164 végrehajtása). PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → **azonnal `stopped`**.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

## 1. Cél

A **production fallback** (ADR 0164) kezelőfelülete: a felhasználó ujjal jelöli
ki a nut és a bridge/body horgonyt, a rendszer centerline-t és neck polygont
rajzol, validál, quality score-t számol, és **csak explicit Save után** ment.

## 2. Jelenlegi állapot (mért, megelőző körök)

- Az R10 kész: `GuitarCalibration` (normalizált anchorok + polygon),
  `CalibrationValidity` + invalidation reason lista, quality score contract,
  verziózott repository. **Ez a kör nem ír új domain-szabályt** — használja.
- Az R07 kész: `NormalizedPoint`, preview fit/fill, letterbox offset — a drag
  koordinátái **kizárólag** ezen mennek át.
- Az R08 kész: setup wizard, route-guard minta, ARB `visionSetup*` kulcsprefix.

## 3. Scope

**Benne:** anchor-editor (touch/drag), nut + bridge/body horgony, centerline és
neck polygon előnézet, érvényes frame-területre korlátozás, nagyított precision
edit (**fájlmentés nélkül**), quality score kijelzése magyarázattal, Save /
Reset / Recalibrate flow, en+hu ARB, accessibility semantics.

**Kívül — TILOS:** automatikus detektor (R17), geometry tracking (R16),
homography (R15), új domain-szabály vagy új storage-kulcs, raw kép mentése.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../presentation/screens/guitar_calibration_screen.dart` | ÚJ | kalibrációs képernyő |
| `.../presentation/widgets/guitar_anchor_editor.dart` | ÚJ | drag-editor |
| `.../presentation/widgets/guitar_geometry_preview.dart` | ÚJ | polygon/centerline rajz |
| `.../presentation/providers/guitar_calibration_providers.dart` | ÚJ | providerek |
| `.../application/guitar_calibration_controller.dart` | ÚJ | szerkesztési állapot |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `lib/app/routing/*` | meglévő | **csak** új route + guard |
| `lib/l10n/app_*.arb` | meglévő | **csak additív** kulcs |
| `test/features/vision/*` | ÚJ | drag + controller tesztek |
| `docs/rounds/e05-r11-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; meglévő ARB kulcs átírása; az R10 domain-fájljai.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Hibás geometria nem menthető.** A Save gomb letiltott, amíg a validitás
   nem `valid`, és a UI **megmondja, miért** (az R10 invalidation reasonje
   lokalizálva). **NEM elfogadható:** mentés „figyelmeztetéssel", vagy
   csendben korrigált polygon.
2. **Minden koordináta az R07 mappingjén megy át** — a widgetben nincs saját
   `1 - x`, `swap`, vagy `MediaQuery`-alapú kézi korrekció. **NEM elfogadható**
   ad hoc koordinátamatek (a review ezt BLOCKER-ként kezeli).
3. **A precision (nagyított) mód nem ment fájlt** és nem készít screenshotot
   (ADR 0161/0166); nagyítás = transzformáció, nem képmentés.
4. **A pontok az érvényes frame-területen belülre szorulnak** (clamp), és a
   clamp **látható** a felhasználónak (a pont nem „ragad" magyarázat nélkül).
5. **Reset ≠ Recalibrate:** a Reset a jelenlegi szerkesztést dobja el, a
   Recalibrate a **mentett** profilt érvényteleníti — a kettő külön művelet,
   külön megerősítéssel a destruktívra.
6. **Minden szöveg ARB-ból**; hardcode-olt mondat BLOCKER.

## 6. Acceptance criteria

- [ ] **Drag-mátrix widget-teszt:** nut és bridge horgony mozgatása; a
      frame-területen **kívülre** húzás → clamp + látható jelzés; két horgony
      **egybeesése** → invalid; érvényes elrendezés → valid + quality score.
- [ ] **Degenerált geometria mátrix:** kollineáris pontok / nulla területű
      polygon / a minimum nyakhossz **alatt / rajta / fölött** — mind külön
      cella, a „rajta" cella értékét `python3 -c` számolja ki (a §10-ben idézve).
- [ ] **Save-kapu teszt:** invalid állapotban a Save **letiltott**, és a
      repository `save` metódusa **nem hívódik** (hívásszámláló 0).
- [ ] **Orientation/mirror paritás:** portrait és landscape, front és back
      kamera esetén ugyanaz a felhasználói pont ugyanoda kerül normalizált
      térben (négy cella).
- [ ] **Accessibility:** minden horgony `Semantics` címkével és
      billentyűzet/olvasó-elérhető alternatív állítási móddal rendelkezik.
- [ ] **Lokalizációs paritás** zöld; minden új kulcs en+hu.
- [ ] **Valódi-sértés próba (§10):** a Save-kapu feltételének kiiktatása →
      a Save-kapu teszt PIROS → visszaállítás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision test/core/l10n_parity_test.dart
```

Külön processzek, nincs `&&`/pipe/`tail`, **nincs `| tail`**. A valós eszközös
kalibrációs élmény a device-mátrix PENDING sora.

## 8. Implementációs sorrend

1. RED: drag-, degenerált-, Save-kapu mátrix.
2. Controller (szerkesztési állapot, validitás az R10-ből).
3. Editor + preview widget (R07 mapping).
4. Route + ARB + accessibility; gate.

## 9. Kockázatok

- **A widget saját koordinátamatekot vezet be**, mert „egyszerűbb" — ez a kör
  legvalószínűbb hibája; a mirror/orientation paritás-mátrix fogja meg.
- **A quality score UI-ban újraszámolódik** az R10-től eltérően → két igazság.
  A számítás **kizárólag** az R10-é.

**STOP:** domain-szabály módosítása, saját koordinátamatek vagy a Save-kapu
lazítása helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r11-manual-guitar-geometry-calibration-ui-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
