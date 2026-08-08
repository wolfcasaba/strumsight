# ADR 0196 — Vision device-tier benchmark, degradation ladder and thermal adapter contract

- **Státusz:** Elfogadva (E05-R29 pre-flight, 2026-08-08)
- **Kör:** E05-R29 — Device tier, performance és thermal hardening
- **Implementer motor:** Terra (Codex CLI, `~/.codex-terra`, `gpt-5.6-terra`,
  `tools/codex-round.sh`) — az ADR-t az orchesztrátor (Claude Sonnet 5) írta a
  pre-flightban (ADR 0055, pipeline-prompt §0 — nincs előre kiosztott ADR).
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md) Kör 29; §29
- **Kontext-ADR-ek:** [0182](0182-vision-audio-priority-degradation.md)
  (audio-elsőbbség — a brief tévesen „ADR 0165"-ként hivatkozza, ld. Kontextus
  1. pont), [0186](0186-vision-pose-landmark-inference-stack.md)
  (`VisionDeviceTier` eredeti bevezetése + „reuse, ne redefine" elv),
  [0193](0193-song-trainer-vision-integration-contract.md) (Song Trainer vision
  integráció — explicit előre-hivatkozás erre a körre mint a `VisionDeviceTier`
  „detektorának" leendő gazdájára).

## Kontextus

**Mért a pre-flightban** (pipeline-prompt §1 mérési szabályai — minden
brief-hivatkozott ADR-számot, típust és numerikus küszöböt ki kell grep-elni,
nem a leírásból feltételezni):

1. **ADR-blokk-avulás.** A brief „ADR 0165"-re hivatkozik háromszor (fejléc,
   §2, §5 pont 1). `find docs/adr -iname '*0165*'` → 0 találat. A dokumentált
   +17 batch-eltolás ([`docs/LESSONS.md`](../LESSONS.md) L143/L147: „audio
   priority degradation" `0165→0182`) és a tartalmi egyezés (ADR 0182 Döntés 1
   szó szerint az „audio deadline romlásakor a vision degradál" elvet írja le)
   együtt egyértelműen **ADR 0182**-re mutat. Az [ADR 0193](0193-song-trainer-vision-integration-contract.md)
   Kontextus 1. pontja saját pre-flightjában (E05-R26) MÁR mérte, hogy az
   E05-R29 brief ugyanezt a hibát hordozza, és explicit „nem e kör scope-ja"
   felirattal nyitva hagyta — ez a kör zárja.
2. **`VisionDeviceTier` név-ütközés.** A brief a `.../domain/performance/
   vision_device_tier.dart` (ÚJ) fájlban egy `VisionDeviceTier (low/mid/high)`
   típust ír elő (§3). Ez a szimbólumnév **már foglalt**:
   `enum VisionDeviceTier { basic, mid, flagship }`
   (`lib/features/vision/data/landmarks/hand_landmark_provider.dart:125`), és
   a teljes fájl már exportálva van a wide `lib/features/vision/public.dart`
   barrelen (nincs `show`/`hide`). Egy második, azonos nevű, eltérő
   értékkészletű enum ugyanabban a barrelben **ambiguous export** fordítási
   hibát adna — ezt a `flutter analyze`/`dart format` gate garantáltan elkapná
   (H7), de csak a dispatch UTÁN, drágán. Mérve: a repóban ZÉRÓ nem-default
   hívás létezik (`grep -rn "VisionDeviceTier\.\(basic\|mid\|flagship\)" lib/`
   csak a két konstruktor-default sort adja vissza,
   `hand_landmark_provider.dart:111` és `pose_landmark_provider.dart:28`) — a
   típus élő, de „detektor" nélküli, pontosan ahogy az
   [ADR 0193](0193-song-trainer-vision-integration-contract.md) Elutasított
   alternatívák szakasza írja: „a `VisionDeviceTier` enum már létezik, de
   detektorja nincs... Kör 29 dolga". Az [ADR 0186](0186-vision-pose-landmark-inference-stack.md)
   (R14 §0.0 „R5") kötelezővé teszi az újrafelhasználást: „Ne definiálj
   párhuzamos, majdnem-azonos típusokat." Precedens import-stílus
   (`pose_landmark_provider.dart:17-18`):
   `import 'package:strumsight/features/vision/data/landmarks/hand_landmark_provider.dart' show VisionDeviceTier, VisionImage;`
   — ugyanez a feature (`vision`), tehát a `tool/check_architecture.dart`
   `crossFeatureImportsMustUsePublicApi` szabálya nem is érinti (csak
   feature-közi importra vonatkozik), a `sharedDomainMustRemainFrameworkIndependent`
   szabály pedig kizárólag `core/music/`, `core/audio/codec/` és
   `features/practice/domain/` útvonalakra vonatkozik — a `vision/domain/`
   nincs ezen a listán, tehát egy domain→data intra-feature import ma nem
   sért gépi architektúra-szabályt.
3. **Degradációs lépcsőszám-eltérés.** A brief §5 pont 1 és §6 **öt** lépcsőt
   ír elő (`overlay cadence ↓ → pose ki → input felbontás ↓ → hand FPS ↓ →
   vision ki`). A most helyesen hivatkozott **ADR 0182 Döntés 3** explicit
   **hét** lépcsőt határoz meg, kötött sorrenddel: *overlay-frekvencia ↓ →
   pose-pipeline ritkítás → hand-pipeline FPS ↓ → model-input felbontás ↓ →
   egy kéz követése → csak quality-monitor → vision leállítása (audio
   megtartása)*. A [`docs/manual-testing/vision-performance-benchmark.md`](../manual-testing/vision-performance-benchmark.md)
   §2.7 tábla (a repóban E05-R01 óta, „ADR 0182 §3" fejléccel) **már rögzíti**
   mind a hét lépcső nevét és a BELÉPÉSI triggerét Hand/Pose FPS-ben: **12 /
   10 / 5 / 8 / 6 / 4** (a 7. lépcső triggere „Audio scoring romlás", amelynek
   mérhető proxyja ugyanazon dokumentum §2.5 „Audio processing latency
   növekmény (vision ON)" cellája, küszöb **< 15 ms**). KILÉPÉSI (hiszterézis)
   küszöb sehol nincs még rögzítve — ez ennek a körnek a tényleges,
   dokumentálandó munkája (brief §5 pont 3).
4. **R06 dropped-frame számláló és R22 memóriakorlát — megerősítve.**
   `lib/core/camera/plugin_camera_capture.dart:52,55,165`
   (`_droppedFrameCount`/`droppedFrameCount` getter/increment);
   `docs/rounds/e05-r22-observation-fusion-and-evidence.md` §6
   „Memória-teszt" (megtartott observation-szám korlátos, számmal
   assertálva). A brief §2 mindkét állítása pontos, nincs revízió.
5. **Nincs thermal/battery/device-info Flutter-plugin.** `pubspec.yaml`
   grep-elve nulla találat, és a fájl NINCS az `allowed_paths`-on — a
   `ThermalStateAdapter` platform-ága ebben a körben nem köthető valós
   OS-jelzésre. A brief §5 pont 4 ezt már helyesen „opcionális" ágnak írta le.

## Döntés

1. **ADR-szám: 0196.** A brief minden `nincs` / pre-flight ADR-hivatkozása ide
   mutat.
2. **Minden „ADR 0165" szöveg a brief-ben „ADR 0182"-re javítva** (fejléc,
   §2, §5 pont 1) — lásd Kontextus 1. pont.
3. **`VisionDeviceTier` ÚJRAFELHASZNÁLT, nem újradefiniált.** A
   `.../domain/performance/vision_device_tier.dart` (ÚJ fájl, útvonal
   **változatlan**) a `data/landmarks/hand_landmark_provider.dart`-ból
   **importált** enumra épül (`show VisionDeviceTier` kombinátor, a
   `pose_landmark_provider.dart` precedens-mintája — Kontextus 2. pont), és a
   **determinisztikus benchmarkot** + a tier→profil (hand FPS / pose cadence /
   input felbontás / overlay cadence) leképezést definiálja. A brief `low/mid/
   high` szóhasználata **`basic/mid/flagship`**-re javítva mindenütt (§3, §6)
   — ezek a TÉNYLEGES enum-értékek. Az enum értékkészletének bővítése (pl. új
   tag) NEM ezen kör dolga — a `hand_landmark_provider.dart` a tilos zónában
   marad, csak import célként érhető el.
4. **A degradációs lépcsősor a már publikált HÉT lépcsős, ADR 0182 Döntés 3
   szerinti sorrendet követi**, nem egy új, öt lépcsős sémát (Kontextus 3.
   pont). A BELÉPÉSI küszöbök a `docs/manual-testing/vision-performance-benchmark.md`
   §2.7 táblájából újrafelhasználtak (12/10/5/8/6/4 Hand/Pose FPS; a 7.
   lépcső triggere az audio-processing-latency-növekmény §2.5 `< 15 ms`
   küszöbcellája) — nem újraszámolva, nem újratervezve. A KILÉPÉSI
   (hiszterézis) küszöböket ez a kör definiálja és dokumentálja számmal (brief
   kötött döntés #3), és az állapotváltások száma dokumentált felső korláttal
   bír (brief §6 „Degradációs lépcső-mátrix").
5. **`VisionPerformanceSummary` és `VisionDegradationPolicy` a session RÉSZE,
   de a valós kamera/inference pipeline-ba (`data/landmarks/*`,
   `core/camera/*`) EBBEN a körben NEM kötődik be** — a modellek/benchmark
   tisztán domain+application rétegben élnek, hívó/wiring nélkül, az Epic 5
   végig követett mintáját folytatva („hívó UI/provider nincs, production
   viselkedés változatlan").
6. **`ThermalStateAdapter` platform-ága ebben a körben mindig a heurisztikus
   ágra esik vissza** (nincs plugin, `pubspec.yaml` tilos zóna — Kontextus 5.
   pont); a summary a döntés **forrását** (`platform`/`heuristic`) mezőként
   rögzíti, hogy egy jövőbeli, valós plugint hozzáadó kör a heurisztikus ágat
   ne váltsa néma no-op-pá, hanem explicit átkapcsolja.

**NEM elfogadható:** egy második, `low/mid/flagship` vagy `low/mid/high`
értékkészletű, párhuzamos `VisionDeviceTier`-szerű típus bevezetése; a brief
eredeti öt lépcsős degradációs sémájának megtartása a már elfogadott hét
lépcsős ADR 0182 Döntés 3 helyett; valós thermal/battery plugin hozzáadása
(natív-gate-et érintő, külön kör dolga); a `hand_landmark_provider.dart`
módosítása (tilos zóna).

## Következmények

- `lib/features/vision/domain/performance/vision_device_tier.dart` (ÚJ) —
  determinisztikus benchmark + tier→profil leképezés, a meglévő
  `VisionDeviceTier` enumra építve (import, nem redefiníció).
- `lib/features/vision/domain/performance/vision_performance_summary.dart`
  (ÚJ) — session-szintű összegzés (tier, alkalmazott lépcsők, dropped-frame
  arány, freshness eloszlás, degradáció-időbélyegek, thermal-forrás).
- `lib/features/vision/application/vision_degradation_policy.dart` (ÚJ) — a
  hét lépcsős, hiszterézisű döntési szolgáltatás.
- `lib/features/vision/data/performance/thermal_state_adapter.dart` (ÚJ) —
  platform/heurisztika kettős forrású thermal-jelzés, mindig heurisztikára
  esik vissza ebben a körben.
- `lib/features/vision/public.dart` — additív export, ha a fogyasztói kör
  szükségesnek méri (nem kötelező ebben a körben, nincs hívó).
- A meglévő `VisionCadencePolicy` (`application/vision_cadence_policy.dart`,
  E05-R26) **változatlan** marad — ez a kör bővíti a device-tier-alapú
  tényleges FPS/felbontás-huzalozással, nem duplikálja a thermal-load→cadence
  döntést.

## Elutasított alternatívák

- **Új, párhuzamos `VisionDeviceTier` (low/mid/high) bevezetése a meglévő
  (basic/mid/flagship) mellett.** Elvetve: ambiguous-export fordítási hiba a
  wide barrelen keresztül, és ellentmond az ADR 0186/R14 „reuse, ne redefine"
  elvének.
- **A brief öt lépcsős degradációs sémájának megtartása.** Elvetve:
  ellentmond a már elfogadott ADR 0182 Döntés 3-nak és a már publikált
  benchmark-dokumentumnak; egy implementer-szintű, máshol dokumentálttól
  eltérő mátrix csendes inkonzisztenciát vinne a repóba, amit a review úgyis
  MAJOR-ként fogna el — olcsóbb most javítani.
- **Valós thermal/battery plugin hozzáadása ebben a körben.** Elvetve:
  `pubspec.yaml` tilos zóna (nincs az `allowed_paths`-on), és egy plugin
  natív-gate-et (`build-apk.yml`) igényelne, ami ellentmond a brief `ai-router`
  `native_gate = false` deklarációjának.
