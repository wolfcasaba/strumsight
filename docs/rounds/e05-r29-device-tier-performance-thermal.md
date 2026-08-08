# E05-R29 — Device tier, performance és thermal hardening

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-08 — ld. §0.0)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 29; §29
- **Branch:** `codex/e05-r29-device-tier-performance-thermal`
- **Előfeltétel:** **E05-R24, E05-R26 merge** — teljesült
- **Brief szerzője:** Claude (batch, 2026-08-05) · **Pre-flight:** Claude Sonnet 5
  (2026-08-08) · **Implementáció:** Codex (Terra)
- **ADR:** [0196](../adr/0196-vision-device-tier-performance-and-thermal-contract.md)
  (a pre-flight írta — nem volt előre kiosztott szám, ld. §0.0)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/performance/vision_device_tier.dart",
  "lib/features/vision/domain/performance/vision_performance_summary.dart",
  "lib/features/vision/application/vision_degradation_policy.dart",
  "lib/features/vision/data/performance/device_tier_benchmark.dart",
  "lib/features/vision/data/performance/thermal_state_adapter.dart",
  "lib/features/vision/public.dart",
  "test/features/vision/domain/vision_device_tier_test.dart",
  "test/features/vision/application/vision_degradation_policy_test.dart",
  "test/features/vision/data/thermal_state_adapter_test.dart",
  "docs/manual-testing/vision-performance-benchmark.md",
  "docs/rounds/e05-r29-device-tier-performance-thermal.md",
  "docs/adr/0196-vision-device-tier-performance-and-thermal-contract.md",
]
gate_tests = [
  "test/features/vision",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ, lezárva 2026-08-08 — ld. §0.0 a teljes mért
> listáért):** `origin/main` + E05-R24/R26 merge — teljesült; olvasd újra az
> R26 `VisionCadencePolicy`-t (ez a kör **bővíti**, nem duplikálja) és az
> **ADR 0182**-t (audio-elsőbbség — a brief eredeti „ADR 0165" hivatkozása
> mérve tévesnek bizonyult, nincs ilyen fájl; ld. §0.0 1. pont). **ÚJ ADR
> [0196](../adr/0196-vision-device-tier-performance-and-thermal-contract.md)**
> — a pre-flight írta (nem volt előre kiosztott szám). PREPARED→PLANNING,
> brief commit az implementer indítása ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Mért, dokumentált revíziók (Claude Sonnet 5, 2026-08-08) — teljes indoklás:
[ADR 0196](../adr/0196-vision-device-tier-performance-and-thermal-contract.md).**

1. **ADR 0165 → ADR 0182.** Nincs `docs/adr/*0165*` fájl. A dokumentált +17
   batch-eltolás ([`docs/LESSONS.md`](../LESSONS.md) L143/L147) és a tartalmi
   egyezés (ADR 0182 Döntés 1 = „romló audio-deadline esetén a vision
   degradál") **ADR 0182**-re mutat — [ADR 0193](../adr/0193-song-trainer-vision-integration-contract.md)
   Kontextus 1. pontja ezt saját pre-flightjában (E05-R26) már mérte erre a
   brief-re nézve is, és nyitva hagyta. Minden „ADR 0165" hivatkozás a
   fejlécben, §2-ben és §5 pont 1-ben javítva.
2. **`VisionDeviceTier` ÚJRAFELHASZNÁLT, nem újradefiniált.** A szimbólum már
   létezik: `enum VisionDeviceTier { basic, mid, flagship }`
   (`lib/features/vision/data/landmarks/hand_landmark_provider.dart:125`),
   már exportálva a wide `vision/public.dart` barrelen. Egy második,
   `low/mid/high` értékkészletű, azonos nevű enum **ambiguous export**
   fordítási hibát adna. A `.../domain/performance/vision_device_tier.dart`
   (ÚJ, útvonal **változatlan**) a meglévő enumot **importálja**
   (`show VisionDeviceTier`, a `pose_landmark_provider.dart:17-18` precedens
   mintája) és a determinisztikus benchmarkot + tier→profil leképezést
   definiálja rá. Minden `low/mid/high` szóhasználat a brief hátralévő
   részében **`basic/mid/flagship`**-re javítva (§3, §6) — ezek a TÉNYLEGES
   enum-értékek. Az enum értékkészlete NEM bővíthető ebben a körben
   (`hand_landmark_provider.dart` a tilos zónában marad).
3. **Degradációs lépcsőszám: öt → hét, ADR 0182 Döntés 3 szerint.** A brief
   eredetileg öt lépcsőt írt elő; az immár helyesen hivatkozott ADR 0182
   Döntés 3 explicit **hét** lépcsőt határoz meg kötött sorrenddel, és a
   [`docs/manual-testing/vision-performance-benchmark.md`](../manual-testing/vision-performance-benchmark.md)
   §2.7 tábla már rögzíti mind a hét lépcső nevét és BELÉPÉSI (entry)
   triggerét. §5 pont 1 és §6 lent javítva — az entry-küszöbök innen
   újrafelhasználtak, a kilépési (hiszterézis) küszöböket ez a kör
   definiálja és dokumentálja számmal.
4. **R06 dropped-frame számláló és R22 memóriakorlát-állítás — megerősítve,
   nincs revízió.** `lib/core/camera/plugin_camera_capture.dart:52,55,165`;
   `docs/rounds/e05-r22-observation-fusion-and-evidence.md` §6.
5. **Nincs thermal/battery plugin a `pubspec.yaml`-ben, és a fájl nincs az
   `allowed_paths`-on** — a `ThermalStateAdapter` platform-ága ebben a
   körben mindig a heurisztikus ágra esik vissza; a brief §5 pont 4 ezt már
   helyesen írta le, nincs revízió, csak megerősítés.

**ÚJ ADR: [0196](../adr/0196-vision-device-tier-performance-and-thermal-contract.md)**
(`tools/round-slots.py reserve-adr --round E05-R29` → `0196`) — a fenti öt
pontot és a teljes indoklást rögzíti tartósan.

## 1. Cél

Valós eszközökön fenntartható működés: mérhető **device tier**, tierenkénti
profilok, freshness/dropped-frame monitor, thermal adapter, és **lépcsőzetes,
audio-elsőbbségű** degradáció.

## 2. Jelenlegi állapot (mért, megelőző körök)

- Az R26 bevezette a cadence-szabályozást a Song Trainerhez; **általános**
  device-tier és thermal-politika **nincs**.
- Az R06 dropped-frame számlálót ad; az R22 méri az evidence-pipeline memóriáját.
- Az ADR 0182 kimondja: romló audio-deadline esetén a **vision** degradál
  (§0.0 1. pont — a brief eredeti „ADR 0165" hivatkozása javítva).

## 3. Scope

**Benne:** `VisionDeviceTier` — **meglévő** enum (`basic`/`mid`/`flagship`,
`lib/features/vision/data/landmarks/hand_landmark_provider.dart:125`),
**ÚJRAFELHASZNÁLVA, nem újradefiniálva** (§0.0 2. pont) — + **determinisztikus** benchmark,
tierenkénti profil (hand FPS, pose cadence, input felbontás, overlay cadence),
dropped-frame és inference-freshness monitor, `ThermalStateAdapter` (ahol a
platform ad állapotot; egyébként performance-heurisztika), lépcsőzetes
`VisionDegradationPolicy`, `VisionPerformanceSummary` a sessionben, és a
benchmark-dokumentum kitöltendő sorai.

**Kívül — TILOS:** audio DSP-paraméter vagy audio ütemezés módosítása,
soak-teszt tényleges futtatása (device-mátrix), UI, új metrika.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/performance/vision_device_tier.dart` | ÚJ | **(§0.0 2. pont)** determinisztikus benchmark + tier→profil leképezés; a meglévő `VisionDeviceTier` enumot (`data/landmarks/hand_landmark_provider.dart:125`) IMPORTÁLJA, nem redefiniálja |
| `.../domain/performance/vision_performance_summary.dart` | ÚJ | session-összegzés |
| `.../application/vision_degradation_policy.dart` | ÚJ | hét lépcsős degradáció (§0.0 3. pont) |
| `.../data/performance/device_tier_benchmark.dart` | ÚJ | benchmark |
| `.../data/performance/thermal_state_adapter.dart` | ÚJ | thermal/heurisztika |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `test/features/vision/*` | ÚJ | tier + degradáció + thermal |
| `docs/manual-testing/vision-performance-benchmark.md` | meglévő | mérési sorok |
| `docs/rounds/e05-r29-*.md` | meglévő | §10 handoff |
| `docs/adr/0196-vision-device-tier-performance-and-thermal-contract.md` | ÚJ | **(§0.0)** a pre-flight ADR-je — L188 tanulság: kötelező a listán |

**Tilos zóna:** minden más; `lib/core/audio/`; DSP; `docs/rag`.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Audio-elsőbbség (ADR 0182, §0.0 1. pont):** ha az audio deadline romlik,
   **a vision** degradál — **hét** lépcsőben, ADR 0182 Döntés 3 kötött
   sorrendjében (§0.0 3. pont; a brief eredeti öt lépcsős listája javítva):
   1. overlay-frekvencia ↓ (belépés: Hand FPS < 12)
   2. pose-pipeline ritkítás (Hand FPS < 10)
   3. hand-pipeline FPS ↓ (Pose FPS < 5)
   4. model-input felbontás ↓ (Hand FPS < 8)
   5. egy kéz követése (Hand FPS < 6)
   6. csak quality-monitor (Hand FPS < 4)
   7. vision leállítása, audio megtartása (audio processing latency növekmény
      ≥ a benchmark-dokumentum §2.5 „< 15 ms" küszöbcellája)

   A belépési triggerek a [`docs/manual-testing/vision-performance-benchmark.md`](../manual-testing/vision-performance-benchmark.md)
   §2.7 táblájából újrafelhasználtak — nem újraszámolandók. **NEM
   elfogadható:** az audio pipeline bármely paraméterének módosítása, sem a
   lépcsők átugrása egyenesen a „vision ki"-ig, ha egy enyhébb lépcső elég.
2. **A device tier determinisztikus és mérhető:** azonos benchmark-bemenetre
   azonos tier. **NEM elfogadható:** modellnév-alapú hardcode lista, sem
   véletlen mintavétel.
3. **A degradáció visszafordítható:** ha a terhelés csökken, a policy
   **hiszterézissel** léphet vissza; a küszöbök számmal dokumentáltak.
4. **A thermal adapter opcionális:** ahol a platform nem ad thermal state-et,
   a heurisztika (dropped frame + freshness + feldolgozási idő) lép be, és a
   summary **megmondja, melyik forrásból** származik a döntés.
5. **A performance summary a session része**, és tartalmazza: tier, alkalmazott
   lépcsők, dropped frame arány, freshness eloszlás, degradációk időbélyegei.
6. **Az unsupported eszköz viselkedése dokumentált**: vision `unavailable`,
   az app minden más funkciója változatlan.

## 6. Acceptance criteria

- [ ] **Tier-mátrix:** a benchmark bemenetének a tier-határok **alatt / rajta /
      fölött** értékei → determinisztikus tier; a cellák értékét `python3 -c`
      számolja (a §10-ben idézve).
- [ ] **Degradációs lépcső-mátrix:** **hét** lépcső (§0.0 3. pont / §5 pont 1
      felsorolása) × (belépési / kilépési küszöb) — a belépési küszöbök a
      benchmark-dokumentum §2.7 táblájából újrafelhasználtak, a policy a
      **legenyhébb elegendő** lépcsőt választja, és a hiszterézis miatt nem
      ingadozik (állapotváltások száma ≤ dokumentált korlát).
- [ ] **Audio-elsőbbség teszt:** szimulált romló audio-deadline mellett a
      vision lépcsőzetesen visszavesz, és az audio-oldali paraméterek
      **változatlanok** (assert a konfiguráción).
- [ ] **Thermal-forrás teszt:** platform-állapot elérhető / nem elérhető —
      mindkét ágon működő döntés, és a summary jelöli a forrást.
- [ ] **Freshness/dropped monitor:** szintetikus terhelésen a számlálók
      helyesek (assertált értékek).
- [ ] **Unsupported-eszköz teszt:** benchmark-hiba → vision `unavailable`,
      és a többi feature érintetlen.
- [ ] **Valódi-sértés próba (§10):** a lépcsők átugrása (azonnal „vision ki")
      → a lépcső-mátrix PIROS → visszaállítás.
- [ ] A benchmark-dokumentum tartalmazza a **10 és 30 perces soak** terv sorait
      **PENDING** státusszal, eszközzel és a mérendő számmal.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision
```

Külön processzek, nincs `&&`/pipe/`tail`. **A basic/mid/flagship tier valós
benchmarkja, a soak és a memory-leak mérés a device-mátrix PENDING sorai** —
ezek a merge UTÁNI termékelfogadás részei (HORIZON), nem pipeline-kapuk.

## 8. Implementációs sorrend

1. RED: tier-, lépcső- és audio-elsőbbség mátrix.
2. Tier-modell + determinisztikus benchmark.
3. Degradációs policy (hiszterézissel).
4. Thermal adapter + summary + benchmark-dokumentum; gate.

## 9. Kockázatok

- **A degradáció „mindent kikapcsol"** az első jelre → a vision használhatatlan
  lesz; a legenyhébb-elegendő-lépcső szabály és a mátrix ezt méri.
- **A tier hardcode-olt eszközlistából** származna — determinisztikus, de nem
  mérhető és nem általánosít; tiltva.

**STOP:** audio-paraméter módosítás, modellnév-alapú tier vagy lépcső-átugrás
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

### Megvalósítás

- `lib/features/vision/domain/performance/vision_device_tier.dart` — a már
  létező, importált `VisionDeviceTier { basic, mid, flagship }` enumra épülő,
  eszköznév-mentes frame-feldolgozási benchmark. `≤33 ms → flagship`,
  `34..66 ms → mid`, `≥67 ms → basic`; a profilok rendre `8/8/192/15`,
  `12/6/256/24`, `15/4/320/30` (hand FPS / pose cadence / input px / overlay
  FPS).
- `lib/features/vision/domain/performance/vision_performance_summary.dart` —
  privacy-safe session-összegzés: tier, alkalmazott lépcsők, dropped-frame
  arány, freshness minimum/átlag/maximum, degradáció-időbélyegek és a
  `thermalSource` mező (`platform` vagy `heuristic`). A
  `VisionPerformanceMonitor` csak a számlálókat és freshness-aggregátumokat
  tartja; a `unavailable` gyártó benchmarkhibát explicit, önálló eredményként
  közöl.
- `lib/features/vision/application/vision_degradation_policy.dart` — ADR 0182
  szerinti hétlépcsős döntés. A recovery-hiszterézis: hand FPS belépés/kilépés
  `12/13`, `10/11`, `8/9`, `6/7`, `4/5`; a hand-FPS-csökkentés Pose FPS
  `5/6`; vision-disabled audio-latency növekmény `15/<12 ms`. Az egy FPS-es,
  illetve audio esetén 3 ms-es rés megakadályozza a határértéki flappelést;
  egy kiértékelés legfeljebb egy állapotátmenetet ad.
- `lib/features/vision/data/performance/device_tier_benchmark.dart` — a hibás
  benchmarkmintát `unavailable` eredménnyé alakítja.
- `lib/features/vision/data/performance/thermal_state_adapter.dart` — platform
  jel esetén azt jelöli `platform` forrásnak, egyébként determinisztikus,
  0..100-ra korlátos dropped-frame/freshness/feldolgozási-idő heurisztikát
  használ. Plugin és valós provider-wiring nem került be.
- `lib/features/vision/public.dart` — az új performance contractok additív
  exportja.
- A benchmark-sablon két új, PENDING állapotú 10 és 30 perces soak sort kapott
  (Pixel 6a, illetve Samsung Galaxy A54); a meglévő 15 perces sor változatlan.

### Mért tesztadatok és ellenőrzések

- Tier-határ cellahármasok:

  ```text
  $ python3 -c "thresholds=(33,66); print('; '.join(f'{threshold}: {threshold - 1}/{threshold}/{threshold + 1} ms' for threshold in thresholds))"
  33: 32/33/34 ms; 66: 65/66/67 ms
  ```

- RED fázis: az új tesztfájlok az implementáció előtt a hiányzó performance
  contractok miatt fordítási hibával megálltak.
- Valódi-sértés próba: a policyt ideiglenesen úgy mutáltam, hogy `Hand FPS <
  12` azonnal `visionDisabled` legyen. `flutter test
  test/features/vision/application/vision_degradation_policy_test.dart` 11
  hibával piros lett (a legenyhébb és a köztes lépcsőket váró mátrixsorok
  ténylegesen `visionDisabled` értéket kaptak). A mutáció visszaállítva.
- Visszaállítás után: `dart format` az érintett Dart fájlokon → változtatás
  nélkül kész; `flutter test test/features/vision/domain/vision_device_tier_test.dart
  test/features/vision/application/vision_degradation_policy_test.dart
  test/features/vision/data/thermal_state_adapter_test.dart` → **26 teszt
  zöld**.
- Kötelező gate: `tools/round-gate.sh --result-json
  /tmp/e05-r29-gate-result.json test/features/vision` → **pass**
  (`exit_code: 0`, `format`, `analyze`, teljes `test/features/vision`,
  architecture, secrets és l10n zöld).

### Eltérések és nem futtatott ellenőrzések

- A landmark providerek és az audio pipeline nem lettek módosítva vagy
  huzalozva; ez a brief/ADR 0196 által előírt későbbi kör felelőssége.
- Valós eszközös benchmark, 10/15/30 perces soak és memory-leak mérés nem
  futott: HORIZON eszközmátrix, a dokumentumba PENDING tervsor került.
- A kötelező teljes gate a commit előtti végső ellenőrzésként következik.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r29-device-tier-performance-thermal-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
