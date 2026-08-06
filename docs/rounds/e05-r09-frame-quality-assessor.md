# E05-R09 — Frame quality assessor

- **Státusz:** PLANNING (pre-flight §0.0 lezárva 2026-08-06, kód olvasva: origin/main @ `e16c02c`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 9; §14
- **Branch:** `codex/e05-r09-frame-quality-assessor`
- **Előfeltétel:** **E05-R06, E05-R07, E05-R08 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/quality/vision_frame_quality.dart",
  "lib/features/vision/domain/quality/frame_quality_assessor.dart",
  "lib/features/vision/domain/quality/vision_quality_summary.dart",
  "lib/features/vision/domain/quality/quality_thresholds.dart",
  "lib/features/vision/public.dart",
  "test/features/vision/domain/frame_quality_assessor_test.dart",
  "test/features/vision/domain/vision_quality_summary_test.dart",
  "test/fixtures/vision/quality",
  "docs/rounds/e05-r09-frame-quality-assessor.md",
]
gate_tests = [
  "test/features/vision",
]
native_gate = false
```

> ⚠ **Pre-flight LEZÁRVA (§0.0, R1–R2):** `origin/main` @ `e16c02c` (HEAD ==
> origin/main, nincs drift) + E05-R06/R07/R08 merge megerősítve. A
> `CameraFrame` pixelformátum-mezői (width/height/format/orientation/mirror/
> crop — R03/R06) és az R08 négy setup-profilja (`leftHandFocus`/
> `rightHandFocus`/`fullUpperBody`/`practiceBalanced`, `vision_setup_profile.dart`)
> mérve, egyeznek a brief állításával. Nincs ÚJ ADR — a bővítés célja
> [`ADR 0179`](../adr/0179-vision-capability-aware-feedback.md), **nem** a
> brief eredeti „0162" hivatkozása (E05-R01 óta renumbered). PLANNING→dispatch.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Mérve `origin/main` @ `e16c02c` (E05-R08 után), orchestrátor Claude Sonnet 5,
2026-08-06.** Előfeltétel (E05-R06/R07/R08 merge) megerősítve, working tree
tiszta, nincs párhuzamos inflight kör. Két mért tétel — egy javítás, egy
megerősítés —, egyik sem igényel ÚJ ADR-t.

**R1 — ADR-hivatkozás elavult.** A pre-flight callout és az §5 2. döntése
„ADR 0162"-re hivatkozott. `ls docs/adr | grep 0162` üres — az E05-R01 az
eredeti `0161–0166` blokkot `0178–0183`-ra számozta át. A döntés ma
[`ADR 0179` — „Vision capability-aware feedback"](../adr/0179-vision-capability-aware-feedback.md);
a 2. döntése szó szerint „Hiányzó megfigyelhetőség ⇒ `notObservable`, nem
gyengébb ítélet", ami pontosan a brief §5.2 tétele. Mindkét hivatkozás
javítva `0179`-re; a bővítés célja változatlan, nincs ÚJ ADR.

**R2 — megerősítve (nem hiba).** A `VisionFrameQuality` öt dimenziója
(framing/lighting/blur/kameramozgás/ROI-lefedettség, brief §5.3) pontosan
fedi az SDD §14.2 típusdefiníciójának öt mezőjét (`lighting`/`blur`/
`framing`/`occlusion`/`stability` + `overall`) — nincs kitalált vagy hiányzó
dimenzió. A §5.3 **sorrendje** nem az SDD §14.3 hét tételes listájának
egyszerű szűkítése: abból három tétel (kameraengedély, „nincs gitár/kéz a
frame-ben", alacsony modellconfidence) modellfüggő és e kör scope-ján kívül
esik (permission = E05-R04; a másik kettő landmark-inferenciát igényelne,
ami §3 szerint „Kívül — TILOS", R12+). A megmaradó négy tételből a brief
önálló, kötött architekturális döntést hoz (§5.3) a modell nélküli
sorrendre — ez a kör saját hatásköre, nem mért hiba, de a review-nak
érdemes külön mérlegelnie a termék-UX szempontból.

## 1. Cél

Eldönteni **modell nélkül**, hogy egy frame alkalmas-e vision feedbackre:
luminance, clipping, blur, kameramozgás és ROI-lefedettség — verziózott,
konfigurálható küszöbökkel és **determinisztikus** setup-cue prioritással.

## 2. Jelenlegi állapot (mért, `5d082dc` + megelőző körök)

- Nincs quality-réteg. A `CameraFrame` (R03/R06) hordozza a pixeladatot és a
  metaadatot; a `CameraTransform` (R07) adja a ROI-t normalizált térben.
- Az R08 négy setup-profilja adja a **profilfüggő** framing követelményt.
- A repó DSP-oldali precedense a küszöb-verziózásra:
  `lib/features/live/engine/dsp/dsp_config.dart` — **de ehhez tilos nyúlni**
  (AGENTS.md §9); a vision saját, külön konfigot kap.

## 3. Scope

**Benne:** `VisionFrameQuality` (frame-szintű), `VisionQualitySummary`
(ablakos), `FrameQualityAssessor` (downsampled grayscale számítás),
`QualityThresholds` (verziózott, konfigurálható), profilfüggő framing
követelmény, és a **prioritásos** setup-cue policy (egyszerre **egy** probléma).

**Kívül — TILOS:** landmark/inference (R12+), UI (a cue megjelenítése az R24),
DSP-konstans módosítása, camera adapter.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/quality/vision_frame_quality.dart` | ÚJ | frame-szintű modell |
| `.../domain/quality/frame_quality_assessor.dart` | ÚJ | metrikák |
| `.../domain/quality/vision_quality_summary.dart` | ÚJ | ablakos összegzés |
| `.../domain/quality/quality_thresholds.dart` | ÚJ | verziózott küszöbök |
| `lib/features/vision/public.dart` | R08-ból | additív export |
| `test/features/vision/domain/*` | ÚJ | fixture + boundary tesztek |
| `test/fixtures/vision/quality` | ÚJ | szintetikus képfixture-ök |
| `docs/rounds/e05-r09-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; `docs/rag`; DSP-paraméter. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A quality assessor modell nélkül működik** és **pure Dart** (a domain
   framework-mentes). **NEM elfogadható** bármely ML-hívás ebben a rétegben.
2. **Rossz quality mellett nincs technikai feedback** — a kimenet ilyenkor
   setup-cue, nem gyengébb bizonyosságú technikai ítélet (ADR 0179).
   **NEM elfogadható:** „alacsonyabb confidence-szel azért adjunk tanácsot".
3. **A cue-prioritás determinisztikus és teljes rendezés**: nincs olyan
   bemenet-pár, amelyre két futás más cue-t adna. A sorrend kötött:
   **framing → lighting (túl sötét/kiégett) → blur → kameramozgás → ROI-lefedettség**.
   **NEM elfogadható:** „a legrosszabb metrika nyer" heurisztika, ha az
   holtversenyben nem determinisztikus.
4. **A számítás downsampled grayscale-en fut**, és a downsample-faktor a
   verziózott konfig része — a költség mérhető és állítható.
5. **A küszöbök verziózottak** (`thresholdsVersion`), és a `VisionFrameQuality`
   **hordozza a verziót** — egy későbbi hangolás visszakövethető.
6. **NaN/Infinity soha nem kerülhet ki** a modellből: üres/degenerált frame
   esetén explicit `notObservable`, nem `double.nan`.

## 6. Acceptance criteria

- [ ] **Fixture-készlet** szintetikusan generálva (nem valós fotó, nincs
      személyes adat): sötét, kiégett, motion-blur, éles/stabil, részleges ROI.
      Minden fixture-höz elvárt quality-állapot.
- [ ] **Küszöb-mátrix minden metrikára:** a küszöb **alatt / pontosan rajta /
      fölött** — mindhárom cella külön assert (az „alatta/rajta/fölötte" hármas
      a mérce; egyetlen cella nem elég).
- [ ] **Prioritás-teszt:** egyszerre több hiba → **pontosan egy** cue, a §5.3
      sorrend szerint; és két azonos súlyú hiba esetén is determinisztikus
      (kétszeri futás azonos eredmény).
- [ ] **NaN/Infinity guard:** degenerált bemenetre (0 méret, konstans kép)
      `notObservable`, és egyetlen kimeneti mező sem NaN.
- [ ] **Költség-mérés:** a `FrameQualityAssessor` egy 640×480 fixture-re mért
      átlagos futásideje a §10-ben **számmal** szerepel (Dart benchmark, nem
      becslés), és a dokumentált budget alatt van.
- [ ] **Valódi-sértés próba (§10-ben dokumentálva):** a prioritás-sorrend
      felcserélése → a prioritás-teszt PIROS → visszaállítás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision
```

Külön processzek, nincs `&&`/pipe/`tail`. A low-tier eszközön mért latency a
device-mátrix **PENDING** sora; a lokális Dart-benchmark **nem** helyettesíti,
de a nagyságrendet rögzíti.

## 8. Implementációs sorrend

1. Fixture-generátor + RED küszöb-mátrix.
2. Metrikák (downsampled grayscale).
3. Ablakos summary + prioritás-policy.
4. Benchmark + gate.

## 9. Kockázatok

- **A blur-metrika képarány-/felbontásfüggő** — a fixture-mátrixnak legalább
  két felbontást tartalmaznia kell, különben a küszöb hamis biztonságot ad.
- **A „rajta a küszöbön" cella hiánya** a mért hibaosztály (L13): a mátrix
  celláit `python3 -c`-vel kell kiszámolni, nem szemre.

**STOP:** ML-hívás bevezetése, DSP-konfig érintése vagy küszöblazítás helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r09-frame-quality-assessor-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
