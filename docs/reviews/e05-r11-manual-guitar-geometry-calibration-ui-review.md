# E05-R11 — Review

Brief: `docs/rounds/e05-r11-manual-guitar-geometry-calibration-ui.md`
Diff: `git diff origin/main...minimax/e05-r11-manual-guitar-geometry-calibration-ui`
Reviewer: Claude Sonnet 5 (orchestrator) · Dátum: 2026-08-07
Verdikt: **APPROVED** (javító kör #1 után, exact-head `38dac1a`)

## Összegzés

Első pass: BLOCKER 3 · MAJOR 0 · MINOR 0 · NOTE 1. Javító kör #1
(`38b7a4b`, `c324cd2`, `b286637`, `b69e9aa`, `38dac1a`) mind a három
BLOCKER-t zárta, **függetlenül újra-ellenőrizve** (nem az implementer
önjelentésére hagyatkozva — lásd „Javítás igazolása" lent). Nyitva marad
egyetlen NOTE (N2, follow-up jellegű, nem blokkoló).

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
- **Státusz: FIXED (`38b7a4b`).** `_selfEvaluate` mostantól
  `reason == degenerateGeometry || extendedGeometryCheck`-et ad vissza,
  ahol `extendedGeometryCheck = isGeometryDegenerate(...)` — pontosan a
  javasolt alak. **Függetlenül újra-futtatva** a review EREDETI
  próbatesztje (kollineáris polygon, egészséges nut/bridge távolság) —
  friss `/tmp` klónban, nem a MiniMax munkapéldányában:
  `selfEvaluationReason=degenerateGeometry`, `canSave=false` (korábban
  `null`/`true` volt). Kontroll (nem-regresszió): az eredeti egészséges
  seed-polygon továbbra is `canSave=true`. Két ÚJ, véglegesített teszt
  került a controller-teszt fájlba (`f1: collinear polygon…`, `f1:
  zero-area polygon…`), mindkettő zöld a hivatalos gate-ben.

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
- **Státusz: FIXED (`c324cd2`).** Új `_clampedHandle` state a szülő
  `_GuitarAnchorEditorState`-ben; a klemp-detektálás a PREVIEW-térbeli
  pointer klemp-elésére épül (nem a normalizált végeredményre —
  robusztusabb), és a handle-specifikus kulccsal állítja be, MELYIK handle
  klemp-elt. `_AnchorHandle`: border alpha 0.2→0.95 ÉS width 1→3 a
  klemp-állapotban; `_PolygonHandle`: border szín surface→error és width
  1→2. **Kódból ellenőrizve** (nem csak az implementer állítása alapján —
  a review EREDETI F2 lelete pontosan azért BLOCKER, mert az implementer
  korábbi önjelentése hasonlót állított, ami a kódban nem volt igaz): a
  feltételes logika ténylegesen jelen van, nem konstans. Új, véglegesített
  widget-teszt (`f2: clanp visibility — dragging outside the frame
  thickens the handle border`) zöld a hivatalos gate-ben.

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
- **Státusz: FIXED (`b286637`, `b69e9aa`).** `guitarCalibrationRuntimeContextProvider`
  mostantól `keyValueStoreProvider`-en keresztül olvassa
  `StorageKeys.visionCamera`/`StorageKeys.visionSetupProfile`-t (az R08
  `VisionSetupController.build()` mintáját követve). `_GeometryCanvas`
  kiszámolja `mirrorPreview = context.camera == front`-ot, és átadja MIND a
  `GuitarGeometryPreview`-nak, MIND a `GuitarAnchorEditor`-nak — utóbbi a
  `toNormalized`/`toPreview` mindkét hívásán átvezeti. Új, véglegesített
  tesztek: „reads the saved camera preference…", „reads the saved setup
  profile…", „falls back to back camera + balanced profile when no key
  set", „saveIfValid persists the saved camera + setup profile, not the
  hardcoded one", „f3: front-camera mirror — dragging right decreases
  normalised x" — mind zöld a hivatalos gate-ben.
  **Részlegesen fedett, ŐSZINTÉN dokumentálva (nem blokkoló, lásd N2):** az
  `orientation` mező továbbra is `degrees0` fallback — a §10.6 kifejezetten
  leírja, hogy az R11 engedélyezett fájljain belül nincs elérhető
  device-orientation forrás, és ez a jelen review saját, előre engedélyezett
  kimenete („ha nincs egyszerű forrás, dokumentált brief-revízió, nem
  hallgatólagos kihagyás") — ez PONTOSAN megtörtént.

## NOTE

### N2 — Landscape-cella follow-up kör (nem blokkoló)

A §6 #4 acceptance négy cellát kér (portrait/landscape × front/back). A
javító kör a front/back tengelyt teljesen lefedte (mindkettő éles-preferencia-
alapú és tesztelt). A landscape tengely infrastrukturálisan tesztelhetetlen
marad — nincs device-orientation forrás az R11 allowed_paths-on belül
(§10.6 részletesen dokumentálja, miért nem a `camera_session_lease.dart`/
`camera_capture.dart` pár és miért nem a `MediaQuery.orientation`). Ez
NEM blokkoló ebben a körben (a §0.0 pre-flight kifejezetten megengedte ezt
a kimenetet, HA dokumentált — megtörtént), de follow-up kör tárgya: egy
jövőbeli SDD-kör vezessen be egy device-orientation providert (valószínűleg
`lib/core/camera/**`-ben, tehát R11 scope-ján kívül), és bővítse ezt a
képernyőt a landscape cellával.

### N1 — a §10 implementer-önjelentés fájlneve elavult

§10.3/§10.7 még `guitar_calibration_drag_matrix_test.dart`-ot említi; a
tényleges fájl (orchestrátor-javítás után) `guitar_calibration_screen_test.dart`.
Nem blokkoló, csak a következő javító kör frissítse a §10-et a valós
állapotra.

## Gate-bizonyíték ellenőrzése

**Első pass** (`/tmp/review-e05-r11`, head `549b5fe`): format/analyze/mindkét
teszt-útvonal/architecture/secrets/l10n mind zöld — de ez ELŐTTE volt a
három BLOCKER javításának, tehát a Save-kapu/clamp/mirror hibák a zöld gate
MELLETT álltak fenn (a review-sablon saját elve: „a zöld gate nem
bizonyíték").

**Javítás utáni pass** (`/tmp/review-e05-r11-fix1`, FRISS klón, head
`38dac1a`, `tools/prepare-flutter-generated.sh` + `tools/round-gate.sh
test/features/vision test/core/l10n_parity_test.dart`, csonkítatlan
kimenet):

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ |
| analyze | zöld | ✅ |
| `test/features/vision` | zöld (78/78, az öt új F1/F2/F3 teszttel együtt) | ✅ |
| `test/core/l10n_parity_test.dart` | zöld (3/3) | ✅ |
| architecture | zöld (12 allowlistelt eltérés, változatlan) | ✅ |
| secrets | zöld (0 lelet, 1869 fájl) | ✅ |
| l10n parity (tool) | zöld (964 üzenet) | ✅ |
| Saját, eldobható próbateszt (F1 re-verify) | `canSave=false` a kollineáris esetre, `canSave=true` az egészséges esetre | ✅ (futtatva, törölve) |
| Dedikált security-review (risk=high) | PASS, 0 CRITICAL/BLOCKER/MAJOR/MINOR, 2 NOTE (`docs/reviews/e05-r11-…-security.md`) | ✅ |
| CI teljes suite + property + APK | lásd alant — merge ELŐTT exact-head-en újra-dispatch kötelező | ⏳ |

## Merge-döntés

**Javító kör után: 0 nyitott BLOCKER/MAJOR.** Mindhárom F1/F2/F3 FIXED,
függetlenül újra-ellenőrizve (saját próbateszt F1-re, kódolvasás + a kör
saját új tesztjeinek zöldje F2/F3-ra), a dedikált security-review PASS. Az
egyetlen nyitott pont (N2, landscape-cella) explicit, előre engedélyezett
kimenet, nem blokkoló.

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR →
merge. A helyi/gate-bizonyíték megvan; **a CI teljes suite + property +
APK futása a merge előtti utolsó feltétel** — lásd a záró CI-dispatchet a
kör-jelentésben, exact-head `38dac1a` (vagy az azt követő, ha időközben
módosul).
