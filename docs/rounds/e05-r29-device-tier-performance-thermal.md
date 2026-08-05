# E05-R29 — Device tier, performance és thermal hardening

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 29; §29
- **Branch:** `codex/e05-r29-device-tier-performance-thermal`
- **Előfeltétel:** **E05-R24, E05-R26 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

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
]
gate_tests = [
  "test/features/vision",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R24/R26 merge; olvasd újra az
> R26 `VisionCadencePolicy`-t (ez a kör **bővíti**, nem duplikálja) és az
> **ADR 0165**-öt (audio-elsőbbség). Nincs ÚJ ADR. PREPARED→PLANNING,
> brief commit az implementer indítása ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

## 1. Cél

Valós eszközökön fenntartható működés: mérhető **device tier**, tierenkénti
profilok, freshness/dropped-frame monitor, thermal adapter, és **lépcsőzetes,
audio-elsőbbségű** degradáció.

## 2. Jelenlegi állapot (mért, megelőző körök)

- Az R26 bevezette a cadence-szabályozást a Song Trainerhez; **általános**
  device-tier és thermal-politika **nincs**.
- Az R06 dropped-frame számlálót ad; az R22 méri az evidence-pipeline memóriáját.
- Az ADR 0165 kimondja: romló audio-deadline esetén a **vision** degradál.

## 3. Scope

**Benne:** `VisionDeviceTier` (low/mid/high) + **determinisztikus** benchmark,
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
| `.../domain/performance/vision_device_tier.dart` | ÚJ | tier-modell |
| `.../domain/performance/vision_performance_summary.dart` | ÚJ | session-összegzés |
| `.../application/vision_degradation_policy.dart` | ÚJ | lépcsős degradáció |
| `.../data/performance/device_tier_benchmark.dart` | ÚJ | benchmark |
| `.../data/performance/thermal_state_adapter.dart` | ÚJ | thermal/heurisztika |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `test/features/vision/*` | ÚJ | tier + degradáció + thermal |
| `docs/manual-testing/vision-performance-benchmark.md` | meglévő | mérési sorok |
| `docs/rounds/e05-r29-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; `lib/core/audio/`; DSP; `docs/rag`.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Audio-elsőbbség (ADR 0165):** ha az audio deadline romlik, **a vision**
   degradál — lépcsőzetesen: overlay cadence ↓ → pose ki → input felbontás ↓ →
   hand FPS ↓ → vision ki. **NEM elfogadható:** az audio pipeline bármely
   paraméterének módosítása, sem a lépcsők átugrása egyenesen a „vision ki"-ig,
   ha egy enyhébb lépcső elég.
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
- [ ] **Degradációs lépcső-mátrix:** öt lépcső × (belépési / kilépési küszöb) —
      a policy a **legenyhébb elegendő** lépcsőt választja, és a hiszterézis
      miatt nem ingadozik (állapotváltások száma ≤ dokumentált korlát).
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

Külön processzek, nincs `&&`/pipe/`tail`. **A low/mid/high tier valós
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

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r29-device-tier-performance-thermal-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
