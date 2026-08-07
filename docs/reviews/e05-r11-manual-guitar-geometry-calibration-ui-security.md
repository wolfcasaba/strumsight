# E05-R11 — Dedicated security review

Brief: `docs/rounds/e05-r11-manual-guitar-geometry-calibration-ui.md` (risk = "high")
Diff: `git diff origin/main...minimax/e05-r11-manual-guitar-geometry-calibration-ui`
Reviewer: `security-reviewer` agent (Claude), dispatched by the orchestrator · Dátum: 2026-08-07
Verdikt: **PASS** — nincs biztonsági/adatvédelmi merge-akadály

## Összegzés

CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 2

Módszer: a tényleges diff olvasása (`/tmp/review-e05-r11`, nem doc-comment),
grep-alapú kizárás minden AGENTS.md §5 határra a hét pontos checklistából.

## 7 pontos checklist — bizonyíték

1. **Raw frame/kép sosem hagyja el az eszközt / nem perzisztálódik — PASS.**
   Nulla találat `CameraFrame|CameraCapture|CameraOwner|Texture(|.acquire(|
   CameraPreview|rawImage|imageBytes|Uint8List|drawImage|toImage|
   RepaintBoundary|toByteData` mintákra mind az 5 új fájlban. A canvas egy
   ABSZTRAKT téglalapot ad `imageSize`-ként
   (`guitar_calibration_screen.dart:190-204`), nem kameratexturát. A
   perzisztált payload (`guitar_calibration_controller.dart:433-446,491-504`)
   kizárólag `NormalizedPoint` double-ök + enum + zoom double + timestamp +
   quality double — nincs képbyte. A precision-toggle (`:63-68`) csak a
   viewport magasságát váltja 240↔360 közt, fájl/screenshot nélkül (ADR
   0178/0183).
2. **Nincs rejtett hálózati kérés — PASS.** Nulla `dio|http|dart:io|
   HttpClient|WebSocket|Socket|Uri.parse|supabase` találat. A route flag
   mögött van, default OFF.
3. **Secretek/tokenek/logolás — PASS.** Nulla `token|secret|password|
   credential` találat. A controller a meglévő logger-t injektálja, de saját
   log-hívást nem ad; a `JsonDocumentStore` (változatlan) csak a dokumentum
   NEVÉT és reason-kódot logol, sosem az értéket.
4. **Confidence-őszinteség — PASS.** `computeQualityScore` egy tiszta
   geometriai heurisztika; az ARB szöveg
   (`guitarCalibrationQualityScore`/`guitarCalibrationQualityExplain`) csak a
   geometria tisztaságáról állít, nem ígér valós-világ pontosságot vagy
   detekciót.
5. **Nincs új storage-kulcs — PASS.** `StorageKeys.visionCalibration` (`ss.vision.calibration`)
   az egyetlen elsődleges kulcs; a `legacyKey: 'ss.vision.calibration.legacy'`
   NEM új — a R10 repository-teszt már ugyanezt a négyparaméteres configot
   használja.
6. **Kódinjekció — PASS.** Nincs `eval|exec|Process|SQL|shell|File(|dart:io`
   egyik új fájlban sem; az egyetlen külső bemenet a [0,1]-re klemp-elt drag-
   koordináta.
7. **Prompt-injection-adjacent — PASS.** Egyik új fájl sem olvas
   utasításként értelmezhető külső/importált tartalmat.

## NOTE

**N1 — Első production-wiring a repository providerekre (ártalmatlan).**
`visionCalibrationRepositoryProvider`/`visionCalibrationDocumentProvider`
(`guitar_calibration_controller.dart:192-214`) nem létezett `origin/main`-en
— R10 csak az osztályt+codecet szállította, providert nem. Ez a kör az ELSŐ
valódi bekötés, a R10-teszt által szentesített store-configot szó szerint
követve. Nyomon-követés céljából rögzítve, nem akadály.

**N2 — A hardkódolt runtime-kontextusnak van egy enyhe confidence-őszinteségi
vetülete (a funkcionális F3-lelet társítva).** `guitar_calibration_providers.dart:31-37`
hardkódolja `camera: back, orientation: degrees0, zoom: 0.5, setupProfile:
practiceBalanced`-et. Adatvédelmi szempontból SEMLEGES-BIZTONSÁGOS (generikus
defaultokat perzisztál, semmit nem szivárogtat). Az egyetlen biztonsághoz
közeli hatás: mivel a mentett profil kamera/orientation/zoom mezői mindig
megegyeznek az „élő" kontextus ugyanazon konstansaival, a Recalibrate-entry
staleness-ellenőrzés (`CalibrationValidity.evaluate`) SOHA nem tudja
felszínre hozni a `cameraDeviceChanged`/`orientationChanged`/
`zoomChangedBeyondTolerance` okokat — egy valóban elavult kalibráció
figyelmeztetés nélkül jelenne meg (§5 „gyenge confidence biztos
állításként", enyhe formában). Ez a functional review F3 leletének egy
vetülete, nem önálló lyuk; a funkcionális javítás (a valós preferencia
beolvasása) ezt is megoldja. A feature emellett default OFF.

**Pozitív megerősítés — route-gating.** `app_router.dart:235-241` a
`visionEnabled && visionGuitarGeometryEnabled` mögé zárja az új route-ot; a
flag minden konstruktor-ágban `false` (`feature_flags.dart:25,70`) — a
feature default elérhetetlen.

## Merge-döntés (biztonsági szempontból)

Biztonsági/adatvédelmi oldalról **nincs merge-akadály**. A merge-et a
független funkcionális review három nyitott BLOCKERje (F1/F2/F3,
`docs/reviews/e05-r11-manual-guitar-geometry-calibration-ui-review.md`)
tiltja — ez a security review azokat nem oldja fel és nem is helyettesíti.
