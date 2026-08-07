# E05-R11 — Review

Brief: `docs/rounds/e05-r11-manual-guitar-geometry-calibration-ui.md`
Diff: `git diff origin/main...minimax/e05-r11-manual-guitar-geometry-calibration-ui`
Reviewer: Claude Sonnet 5 (orchestrator) · Dátum: 2026-08-07
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 3 · MAJOR: 0 · MINOR: 0 · NOTE: 1

Módszer: független `/tmp/review-e05-r11` klón (`tools/prepare-flutter-generated.sh`
+ `tools/round-gate.sh test/features/vision test/core/l10n_parity_test.dart`,
mind zöld), kézi `git diff --stat` scope-audit, és **futtatott, eldobható
próbateszt** a Save-kapu tényleges viselkedésére (nem csak a forráskód
olvasása — lásd F1). A kör orchestrátor-oldali önjavítása (a scope-audit
VIOLATION-jét okozó fájl átnevezése) e review ELŐTT megtörtént és zöld
scope-audittal lezárva — lásd alant, nem lelet.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Drag-mátrix (nut/bridge mozgatás, OOB→clamp+jelzés, egybeesés→invalid, valid→quality score) | ⚠️ RÉSZBEN | mozgatás+clamp-ÉRTÉK: `guitar_calibration_screen_test.dart` 2 teszt zöld. Clamp **látható jelzés**: NEM teljesül — lásd F2. Egybeesés→invalid és valid→score: csak controller-szinten (`guitar_calibration_controller_test.dart`), nem widget-szinten, de elfogadható helyettesítés. |
| 2 | Degenerált geometria mátrix (kollineáris / nulla terület / neckhossz alatt-rajta-fölött, „rajta" `python3 -c`-vel) | ❌ NEM (a valós Save-kapun) | A `neckPolygonIsCollinear`/`neckPolygonArea`/`isGeometryDegenerate` helperek helyesen íródtak és unit-tesztelve vannak IZOLÁLTAN, de a Save-kapu (`_selfEvaluate`) őket **soha nem hívja** — lásd F1, futtatott próbateszttel bizonyítva. A „rajta" cella (§10.2: neckLen=0.25=minAnchorSeparation) számítása helyes és dokumentált. |
| 3 | Save-kapu teszt (invalid⇒letiltott, `write` hívásszámláló 0) | ✅ a tesztelt cellákra (rövid nyak) | `moving anchors to a degenerate config blocks Save`, `saveIfValid blocks when the draft is degenerate` — de csak a rövid-nyak cellára; a kollineáris/nulla-terület cellára NEM igaz futásban (F1). |
| 4 | Orientation/mirror paritás (portrait/landscape × front/back, 4 cella) | ❌ NEM | Csak 1 sekély teszt létezik, és az sem mirrorozott `PreviewFit`-et használ — a nem-mirrorozott alapesetet ellenőrzi. A gyökérok: `guitarCalibrationRuntimeContextProvider` `camera`-ja HARDCODE `VisionCameraPreference.back`, sosem a ténylegesen elmentett preferencia — lásd F3. |
| 5 | Accessibility (Semantics + billentyűzet-alternatíva) | ✅ | `_AnchorHandle`/`_PolygonHandle`: `Semantics(label:, button: true, onIncrease:, onDecrease:)` mindkét handle-típuson. |
| 6 | Lokalizációs paritás | ✅ | `test/core/l10n_parity_test.dart` zöld a független klónban is (3/3 teszt). |
| 7 | Valódi-sértés próba (Save-kapu) | ✅ a dokumentált cellára | §10.4-1 szerint a gate kiiktatása 2 tesztet PIROSRA vitt — ELFOGADVA, de ez csak a rövid-nyak ágat fedi; F1 egy MÁSIK, dokumentálatlan sértési utat mutat (a kollineáris ág soha nem volt piros, mert soha nincs bekötve). |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs** — de csak azután, hogy az
orchestrátor a MiniMax-diffből érkező scope-audit `VIOLATION`-t javította
(lásd alant). Manuális `git diff --stat origin/main...HEAD` mind a 13
megváltozott fájlt a brief §4 listáján találta.

**Orchestrátor-oldali javítás a review ELŐTT (nem implementer-lelet, dokumentálva
a teljesség kedvéért):** a MiniMax futás a widget-tesztet
`test/features/vision/presentation/guitar_calibration_drag_matrix_test.dart`
néven adta le — ez NEM szerepel a brief `allowed_paths`-ában (csak
`guitar_calibration_screen_test.dart` szerepel), ezért a `.codex-round-status`
`scope_audit=VIOLATION`-ra váltott. Az orchestrátor a fájlt tartalom-változtatás
NÉLKÜL átnevezte az engedélyezett útvonalra (`549b5fe`), és a scope-audit
utána tisztán futott (`bae7a9a..549b5fe`, 13 fájl, 0 violation). A brief §10.3/§10.7
implementer-önjelentése még a régi fájlnevet említi — ez a review óta elavult,
nem hibaforrás.

## Megállapítások

### F1 — BLOCKER — A Save-kapu nem gátolja a kollineáris / nulla-területű polygont

- **Fájl:** `lib/features/vision/application/guitar_calibration_controller.dart:531-569` (`_selfEvaluate`), `:604-627` (`isGeometryDegenerate`)
- **Probléma:** `isGeometryDegenerate`, `neckPolygonIsCollinear` és `neckPolygonArea`
  helyesen implementált, tesztelt tiszta függvények, de **egyikük sincs
  meghívva** semelyik production-kódútból. `_selfEvaluate` — a TÉNYLEGES
  Save-kapu — kizárólag `CalibrationValidity.evaluate(...)`-t hívja, ami az
  R10 `_isDegenerate`-jén megy át (csak vertex-szám + nut↔bridge távolság).
  `grep -rn "isGeometryDegenerate\|neckPolygonIsCollinear" lib/` a saját
  definícióján kívül nulla hívási helyet ad.
- **Hatás:** egy felhasználó mind a négy neck-polygon csúcsot egy egyenesre
  húzhatja (kollineáris, nulla vizuális terület), egészséges nut/bridge
  távolsággal — a Save gomb **engedélyezve marad**, és a `write()` ténylegesen
  lefut. Ez közvetlenül megsérti a brief §5 1. döntését („Hibás geometria nem
  menthető… NEM elfogadható… csendben korrigált polygon" — itt nem is
  korrigált, hanem egyszerűen elfogadott) és a §6 #2 acceptance-t.
- **Futtatott bizonyíték (eldobható próbateszt, review után törölve):**
  `ProviderContainer` + valódi `GuitarCalibrationController`, `moveAnchor`
  egészséges nut/bridge-re, majd mind a 4 polygon-vertex `y=0.5`-re
  (kollineáris). Eredmény:
  ```
  helperSaysDegenerate=true
  selfEvaluationReason=null
  canSave=true
  ```
  A helper helyesen mondja degeneráltnak; a TÉNYLEGES gate szerint mégis
  menthető.
- **Kötelező javítás:** `_selfEvaluate`-nek (vagy a hívóinak: `moveAnchor`,
  `movePolygonVertex`, `saveIfValid`) figyelembe kell vennie
  `isGeometryDegenerate(...)`-t is — pl. `reason == degenerateGeometry ||
  isGeometryDegenerate(nutAnchor: nut, bridgeAnchor: bridge, neckPolygon:
  polygon)` — úgy, hogy a felhasználó felé a meglévő
  `CalibrationInvalidationReason.degenerateGeometry` lokalizált szövege
  jelenjen meg (nincs szükség új enumra, §0.0 R4 szerint).
- **Ellenőrzés:** a fenti próbateszt (vagy vele egyenértékű, a brief §6-ba
  felvett) mutassa `canSave == false`-t UGYANERRE a bemenetre; a meglévő
  `isGeometryDegenerate` unit-tesztek változatlanul zöldek maradjanak.
- **Státusz:** OPEN

### F2 — BLOCKER — A „clamp látható jelzés" nincs bekötve; az önjelentés téves állítást tartalmaz

- **Fájl:** `lib/features/vision/presentation/widgets/guitar_anchor_editor.dart:113-121,135-144,157-166` (`onClamp` callback, sosem hívva), `:198-202` (`wasClamped` kiszámítva, no-op ág), `:294` (`accentColor.withValues(alpha: 0.2)` — konstans, nem feltételes)
- **Probléma:** `_AnchorHandle`/`_PolygonHandle` mindkettő kap egy `onClamp`
  `VoidCallback`-et konstruktorparaméterként, de **egyikük `build()`-je sem
  hívja meg**. A szülő `_onPointerMove`-ban kiszámolt `wasClamped` boolean-t
  egy üres `if (wasClamped) { /* comment, no code */ }` blokk dobja el. A
  handle border színe (`accentColor.withValues(alpha: 0.2)`) FIX érték,
  független attól, hogy a pont épp klemp-elve van-e.
- **Hatás:** a brief §5 4. kötött döntése („a clamp látható a felhasználónak,
  a pont nem 'ragad' magyarázat nélkül") és a §6 #1 acceptance
  („kívülre húzás → clamp + LÁTHATÓ jelzés") nem teljesül — a felhasználó a
  keretre húzáskor semmilyen vizuális különbséget nem lát. **Az implementer
  §10.4-4 önjelentése kifejezetten állítja, hogy „a határhoz érve erősebben
  látszik" a kontúr — ez a kódban NEM igaz** (a `withValues(alpha: 0.2)`
  hívásnak nincs feltétele) — ez a review-sablon saját BLOCKER-definíciója
  szerinti „hamis zöld állítás".
- **Kötelező javítás:** az `onClamp` callback tényleges meghívása (vagy a
  `wasClamped` állapot előre vitele a widget state-jébe), és egy valódi,
  feltételes vizuális jel (pl. `accentColor` alpha/border-width növelése
  KIZÁRÓLAG amíg `wasClamped == true` az adott handle-re).
- **Ellenőrzés:** widget-teszt, ami a frame-területen kívülre húz, és
  ellenőrzi, hogy a handle dekorációja (szín/border) ELTÉR a nem-klemp-elt
  állapottól.
- **Státusz:** OPEN

### F3 — BLOCKER — A futásidejű kontextus hardkódolt; a mentett `setupProfile` szisztematikusan hibás, a mirror-paritás elérhetetlen

- **Fájl:** `lib/features/vision/presentation/providers/guitar_calibration_providers.dart:29-38` (`guitarCalibrationRuntimeContextProvider`)
- **Probléma:** a provider MINDIG `camera: VisionCameraPreference.back,
  orientation: CameraRotation.degrees0, zoom: 0.5, setupProfile:
  VisionSetupProfile.practiceBalanced`-et ad vissza — sosem olvassa az R08
  által már elmentett tényleges preferenciákat
  (`StorageKeys.visionCamera`/`StorageKeys.visionSetupProfile`, pontosan az a
  minta, amit a `VisionSetupController.build()` már használ). A doc-comment
  szerint „Tests override this" — production kódútban viszont semmi mást nem
  ír felül.
- **Hatás (kettős):**
  1. **Csendes adathiba:** minden `saveIfValid()`/`recalibrate()` hívás a
     mentett `CameraCalibrationProfile.setupProfile`-t `practiceBalanced`-re
     írja, FÜGGETLENÜL attól, mit választott a user az R08 setup wizardban
     (`leftHandFocus`/`rightHandFocus`/`fullUpperBody`). Ez később hibás
     `CalibrationValidity`-döntéseket és hibás UI-szöveget okozhat bármelyik
     jövőbeli, `setupProfile`-t olvasó fogyasztónál.
  2. **A §6 #4 acceptance strukturálisan elérhetetlen:** a front-kamera és a
     landscape cella SOHA nem fordulhat elő valós futásban, mert a kontextus
     sosem `front`/nem-`degrees0`. Ezzel a `PreviewFit`/`toNormalized`
     mirror-ága (`mirrorPreview: true`) sem a screen-ben, sem az editorban
     nincs sehol meghívva — a mirror-logikát a kör gyakorlatilag nem
     implementálta, csak a nem-mirrorozott alapesetet.
- **Kötelező javítás:** a provider olvassa a ténylegesen elmentett
  `StorageKeys.visionCamera`/`StorageKeys.visionSetupProfile` értékeket (az
  R08 `VisionSetupController.build()` mintáját követve) egy valós
  `keyValueStoreProvider`-en keresztül; a `guitar_calibration_screen.dart`
  `_GeometryCanvas`-a adja át a `mirrorPreview: context.camera ==
  VisionCameraPreference.front` értéket a `fit.toNormalized()`/`fit.toPreview()`
  hívásoknak. Az orientation (landscape) valós forrása a §0.0-ban nem volt
  mérve — ha nincs egyszerű, meglévő forrás rá, az egy ÚJABB, dokumentált
  brief-revízió tárgya, nem hallgatólagos kihagyás.
- **Ellenőrzés:** widget/controller teszt, ami `StorageKeys.visionCamera =
  'front'`-ot ír egy in-memory store-ba, és ellenőrzi, hogy (a) a mentett
  profil `camera == front`, (b) egy jobbra-húzás a mirrorozott elrendezésben
  a normalizált x-et a nem-mirrorozotthoz képest tükrözve változtatja.
- **Státusz:** OPEN

## NOTE

### N1 — a §10 implementer-önjelentés fájlneve elavult

§10.3/§10.7 még `guitar_calibration_drag_matrix_test.dart`-ot említi; a
tényleges fájl (orchestrátor-javítás után) `guitar_calibration_screen_test.dart`.
Nem blokkoló, csak a következő javító kör frissítse a §10-et a valós
állapotra.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (`/tmp/review-e05-r11`, teljes futás, csonkítatlan) |
| analyze | zöld | ✅ (uo., `tools/prepare-flutter-generated.sh` után — enélkül hamis PIROS az l10n-generált fájlok hiánya miatt, ez NEM a kör hibája) |
| `test/features/vision` | zöld (70/70 ill. 71/71, párhuzamos sorrendtől függő számozás) | ✅ |
| `test/core/l10n_parity_test.dart` | zöld (3/3) | ✅ |
| architecture | zöld (12 allowlistelt eltérés, változatlan) | ✅ |
| secrets | zöld (0 lelet) | ✅ |
| l10n parity (tool) | zöld | ✅ |
| CI teljes suite + property + APK | Full Gate dispatch folyamatban, Router CI zöld a scope-fix commiton | ⏳ folyamatban a review lezárásakor |

## Merge-döntés

**Merge TILOS.** Három nyitott BLOCKER (F1, F2, F3) — mindegyik a brief §5
kötött architekturális döntéseit és/vagy a §6 acceptance criteriát sérti, F1
futtatott próbateszttel bizonyítva, F2 az implementer saját, kódból nem
igazolható állítását tartalmazza. A motor-eszkaláció szabálya szerint
(AGENTS.md §2/H4, user-döntés 2026-08-01) a MiniMax EGY javító kört kap
ugyanezzel a leletlistával; ha BLOCKER marad utána, a következő javító kört a
Codex viszi.
