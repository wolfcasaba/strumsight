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

**PREPARED.** Nincs előre kiosztott ADR — ez a kör NEM hoz új ADR-t (R1
alább csak egy hivatkozás-javítás).

Mérve `origin/main` @ `a6e3081` (R07/R08/R10 mind mergelve). Hét pontos
revízió — mindegyik grep-elt forrásreferenciával, nem feltételezésből:

**R1 — Stale ADR-hivatkozás.** A fenti figyelmeztető sor „(0164 végrehajtása)"-t
ír. Az E05-R08 saját, már rögzített pre-flightja (`HANDOFF.md`, E05-R08
szakasz) ezt már egyszer átszámozta: „ADR-hivatkozás `0161/0162/0164` →
`0178/0179/0181`". A fájl is megerősíti:
`docs/adr/0181-vision-manual-calibration-fallback.md` létezik, a címe pontos
szemantikai egyezés. **A helyes szám: ADR 0181.** Nincs ÚJ ADR — ez a kör a
0181 döntést hajtja végre, csak a citáció elavult. Ugyanez a +17-es
átszámozás (`0161→0178 … 0166→0183`, HANDOFF E05-R01) érinti a §1 „(ADR
0164)" és a §5.3 „(ADR 0161/0166)" előfordulását is — mindkettő javítva lent
(0181, illetve 0178/0183).

**R2 — Nincs élő kameraelőnézet, és ez a kör nem is szerez be egyet.** Mérve:
(a) `CameraFrame` bufferje kizárólag a stream-callback szinkron törzsén belül
érvényes (`lib/core/camera/camera_frame.dart:51-57,81-83`,
`assertValid`/`invalidate`) — nincs mögötte hosszú-életű, widgetből olvasható
kép; (b) `grep -rln "CameraPreview\|Texture(" lib/` **nulla találat** — a
repóban SEHOL nincs élő kamerakép-renderelő widget; (c) `CameraOwner`
pontosan négy értékű zárt enum (`lib/core/camera/camera_session_lease.dart:6`:
`visionSetup, visionPractice, songVision, labCapture`) — nincs kalibrációs
owner, és ez a fájl **nincs** az engedélyezett listán, tehát nem bővíthető;
(d) még az R08 `VisionSetupStep.ready` lépése is — pedig OTT ténylegesen
aktív a kameralease (`vision_setup_controller.dart:157-195`) — nem jelenít
meg élő framet: az egyetlen kamera-analóg widget a `VisionSetupFrameGuide`,
aminek a doc-commentje explicit kimondja: „contains no camera preview and
therefore cannot retain or expose image data"
(`vision_setup_frame_guide.dart:6`). **Következmény:** az anchor-editor egy
ABSZTRAKT, normalizált `[0,1]×[0,1]` frame-területen dolgozik (statikus/üres
hátterű canvas, az R08 `VisionSetupFrameGuide`-precedenst követve) — ÉLŐ
kamera-lease-t vagy preview-widgetet ez a kör NEM szerez be és NEM rajzol; a
„érvényes frame-területre korlátozás" (§3) erre az absztrakt téglalapra
vonatkozó clamp, az R07 `PreviewFit`/`NormalizedRect` gépezetével.

**R3 — A „quality score" számítása NEM az R10-é; ez a kör az első
implementáció.** Mérve: `CameraCalibrationProfile.qualityScore`
(`camera_calibration_profile.dart:27,48`) egy **tárolt** `double [0,1]`
(csak assert-tel határolt, `camera_calibration_profile.dart:29`); a
`vision_calibration_codec.dart:164,242,299` és a domain fájlok teljes
grepje (`grep -rln qualityScore lib/`) **egyetlen számító függvényt sem** ad
— a kódolás/dekódolás csak átmásolja, amit kap. Az SDD forrás is ezt
erősíti: „Kör 10" feladatlistája csak „Készíts calibration quality
score-t" (= mezőt/típust), míg **„Kör 11" (EZ a kör) feladatlistája
explicit: „Számíts calibration qualityt és magyarázd a hibát"**
(`docs/sdd/06-epic-05-computer-vision.md:2551,2589`). A brief §9 2. kockázata
(„A számítás kizárólag az R10-é") ezért **téves feltevésen alapul** — nincs
R10-formula, amit „elhagyva" két igazság keletkezne. **Ez a kör írja meg az
ELSŐ (és egyetlen) quality-score formulát**, kizárólag a
`guitar_calibration_controller.dart`-ban (nem a `calibration_validity.dart`-ban,
az nincs az engedélyezett listán) — determinisztikus, tiszta függvény, csak
már ismert geometriai jelekből (pl. az R4 alatti margin/vertex-jelek), a UI
ezt jeleníti meg és magyarázza. §9 2. kockázatát így kell olvasni: nem a
„két igazság" a veszély, hanem hogy a formula NE kerüljön a widget rétegbe és
NE duplikálódjon a Save-kapu és a kijelzés között (egy hívás, egy eredmény).

**R4 — A degenerált-geometria mátrix egy része R10-en TÚLI, saját ellenőrzés.**
Mérve: `CalibrationValidity._isDegenerate` (`calibration_validity.dart:91-98`)
KIZÁRÓLAG két dolgot néz: `neckPolygon.length < 3`, és a nut↔bridge normalizált
távolság `< 0.05` (`minAnchorSeparation`, neckhossz-proxy). **Nem néz**
kollinearitást és nem néz polygon-területet. Az SDD Kör 11 feladatlistája
viszont explicit ezt is előírja ennek a körnek: „Validáld a minimum
nyakhosszt, **polygon területet** és degenerált geometriát"
(`docs/sdd/06-epic-05-computer-vision.md:2587`). Mivel a
`calibration_validity.dart` NINCS az engedélyezett listán (R10 domain-fájl,
tilos zóna), ezt a két plusz ellenőrzést (kollinearitás — pl. keresztszorzat
közel nulla; nulla/közel-nulla polygon-terület — shoelace formula) a
**controller** (`guitar_calibration_controller.dart`) számolja, saját,
tiszta helper függvényként — a `grep -rln "collinear\|signedArea\|shoelace"
lib/ test/` nulla találatot ad, tehát nincs meglévő helper, amit újra
kellene használni vagy amivel ütközne. A felhasználó felé mindhárom eset
(rövid nyak / kollineáris / nulla terület) a **meglévő**
`CalibrationInvalidationReason.degenerateGeometry` lokalizált szövege alá
tartozik (nem kell új enum-érték); a §10 handoffban dokumentáld, melyik
al-ok melyik konkrét ARB-szöveget kapja.

**R5 — `evaluate()` két, EGYMÁST KIZÁRÓ hívási helye — csak az egyikben
érhető el mind az öt ok.** `CalibrationValidity.evaluate(...)`
(`calibration_validity.dart:65`) egy MENTETT profilt hasonlít egy ÉLŐ
runtime-kontextushoz. Ha a Save-kapu a still-szerkesztett draftot
önmagával hasonlítja (a `currentCamera`/`currentOrientation`/`currentZoom`
paraméterek a draft SAJÁT mezői, mert menteni még nem mentett semmit), akkor
`cameraDeviceChanged`/`orientationChanged`/`zoomChangedBeyondTolerance`/
`timestampExpired` **szerkezetileg elérhetetlen** (a draft egyenlő
önmagával) — **csak** `degenerateGeometry` (R4-gyel bővítve) tud kiváltódni.
Ez PONTOSAN fedi a §6 acceptance-lista igényét (Drag-mátrix, Degenerált
geometria mátrix, Save-kapu teszt — mindhárom geometria-alapú, egyik sem
kamera/zoom/idő-alapú). A másik négy ok a **Recalibrate-belépőnél** él: amikor
a képernyő egy MEGLÉVŐ, `VisionCalibrationRepository.read()`-del betöltött
rekorddal nyílik meg, az `evaluate()`-et a MENTETT profil vs. az ÉLŐ
kamera/orientation/zoom/now hívja — itt lokalizálandó mind az öt ok (§5.1
„az R10 invalidation reasonje lokalizálva" ide vonatkozik teljes körűen). A
két hívási hely ne keveredjen: a Save-kapu teszt NE várjon
cameraDeviceChanged-szerű okot, a Recalibrate-teszt NE hasonlítsa a draftot
önmagával.

**R6 — Módszernév-javítás a Save-kapu teszthez.** §6 „a repository `save`
metódusa nem hívódik" szövege elavult névre hivatkozik: a
`VisionCalibrationRepository`-nak nincs `save` metódusa, csak
`write({required profile, required guitar})`
(`vision_calibration_repository.dart:74`) és `read()` (uo. 57. sor). A
hívásszámláló/spy ezt a **`write()`** hívást számolja.

**R7 (megerősítés, nem hiba) — a route-guard flag.** `feature_flags.dart`
már tartalmaz egy pontosan erre a célra dedikált, ma nulla fogyasztós
flaget: `visionGuitarGeometryEnabled` (konstruktor + mező + default `false`
minden környezetben, doc: „Whether guitar geometry may be derived locally").
Az `app_router.dart` mintája (R08 precedens, 228-233. sor:
`if (visionEnabled && visionSetupEnabled) [...]`) ide `if (visionEnabled &&
visionGuitarGeometryEnabled) [...]`-ra másolandó — **nincs** új flag, a
`feature_flags.dart` nincs is az engedélyezett listán.

**Nincs allowed_paths-változás.** Mind a hét revízió a meglévő fájllistán
belül old meg mindent (elsősorban a `guitar_calibration_controller.dart`-ban) —
nincs új fájl, nincs bővítés, nincs szűkítés.

## 1. Cél

A **production fallback** (ADR 0181) kezelőfelülete: a felhasználó ujjal jelöli
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

1. **Hibás geometria nem menthető.** A Save gomb letiltott, amíg
   `CalibrationValidity.evaluate(...) != null` (a „valid" állapot a `null`
   visszatérés — nincs külön `valid` enum-érték), és a UI **megmondja, miért**
   (az R10 invalidation reasonje, R4-gyel bővítve, lokalizálva — §0.0 R4/R5).
   A Save-kapu hívása a draftot **önmagával** hasonlítja (§0.0 R5); a
   Recalibrate-belépő a **mentett** profilt élő kontextussal (uo.).
   **NEM elfogadható:** mentés „figyelmeztetéssel", vagy csendben korrigált
   polygon.
2. **Minden koordináta az R07 mappingjén megy át** — a widgetben nincs saját
   `1 - x`, `swap`, vagy `MediaQuery`-alapú kézi korrekció. **NEM elfogadható**
   ad hoc koordinátamatek (a review ezt BLOCKER-ként kezeli).
3. **A precision (nagyított) mód nem ment fájlt** és nem készít screenshotot
   (ADR 0178/0183); nagyítás = transzformáció, nem képmentés.
4. **A pontok az érvényes frame-területen belülre szorulnak** (clamp), és a
   clamp **látható** a felhasználónak (a pont nem „ragad" magyarázat nélkül).
   A „frame-terület" egy absztrakt, normalizált téglalap — nincs élő
   kamera-preview mögötte (§0.0 R2).
5. **Reset ≠ Recalibrate:** a Reset a jelenlegi szerkesztést dobja el, a
   Recalibrate a **mentett** profilt érvényteleníti — a kettő külön művelet,
   külön megerősítéssel a destruktívra.
6. **Minden szöveg ARB-ból**; hardcode-olt mondat BLOCKER.

## 6. Acceptance criteria

- [ ] **Drag-mátrix widget-teszt:** nut és bridge horgony mozgatása; a
      frame-területen **kívülre** húzás → clamp + látható jelzés; két horgony
      **egybeesése** → invalid; érvényes elrendezés → `evaluate(...) == null`
      (valid) + quality score (§0.0 R3/R5).
- [ ] **Degenerált geometria mátrix:** kollineáris pontok / nulla területű
      polygon / a minimum nyakhossz **alatt / rajta / fölött** — mind külön
      cella, a „rajta" cella értékét `python3 -c` számolja ki (a §10-ben idézve).
      A kollinearitás/terület a controller SAJÁT, új helperje (§0.0 R4) — a
      neckhossz-alatt/fölött cella az R10 `minAnchorSeparation`-jét méri.
- [ ] **Save-kapu teszt:** invalid állapotban a Save **letiltott**, és a
      repository `write` metódusa **nem hívódik** (hívásszámláló 0; §0.0 R6).
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
- **A quality-score formula két helyen (widget + controller) él és
  szétcsúszik.** Nincs R10-formula, amit „elhagyva" ütköznénk (§0.0 R3) — a
  tényleges kockázat, hogy a képernyő és a controller külön-külön számolja.
  Egyetlen hívás, a controllerben; a widget csak megjeleníti az eredményt.
- **Az implementer élő kameraelőnézetet próbál bekötni**, mert a „frame-terület"
  szöveg ezt sugallja — nincs hozzá `CameraOwner`-érték, engedélyezett fájl
  vagy meglévő preview-widget (§0.0 R2); ez `stopped`-hoz vezetne. Absztrakt
  normalizált terület, nem élő kép.

**STOP:** domain-szabály módosítása, saját koordinátamatek vagy a Save-kapu
lazítása helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r11-manual-guitar-geometry-calibration-ui-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
