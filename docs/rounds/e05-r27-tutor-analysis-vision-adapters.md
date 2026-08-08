# E05-R27 — AI Tutor és Analysis vision evidence adapterek

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-08, kód olvasva: main @ `dc78cc9`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 27; §27
- **Branch:** `codex/e05-r27-tutor-analysis-vision-adapters`
- **Előfeltétel:** **E05-R22, E05-R23, E05-R24 merge**; Epic 4 (AI Tutor) lezárva — teljesült.
- **ADR:** [0194](../adr/0194-tutor-analysis-vision-evidence-adapters.md) (a
  pre-flightban foglalva és megírva — a brief eredetileg `nincs ÚJ ADR`-t
  írt elő egy nem létező 0161/0162-re hivatkozva, ld. §0.0 1. pont).
- **Brief szerzője:** Claude (batch, 2026-08-05) + Claude (pre-flight-revízió,
  2026-08-08) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/integration/vision_context_snapshot.dart",
  "lib/features/vision/domain/integration/vision_claim_guard.dart",
  "lib/features/vision/domain/integration/public.dart",
  "lib/features/ai_tutor/application/context/adapters/tutor_vision_context_adapter.dart",
  "lib/features/ai_tutor/application/context/tutor_context_snapshot.dart",
  "lib/features/analyze/model/analysis_vision_reference.dart",
  "lib/features/analyze/providers/analysis_vision_adapter.dart",
  "lib/features/ai_tutor/public.dart",
  "lib/features/analyze/public.dart",
  "test/features/vision/domain/integration/vision_context_snapshot_test.dart",
  "test/features/vision/domain/integration/vision_claim_guard_test.dart",
  "test/features/ai_tutor/application/context/adapters/tutor_vision_context_adapter_test.dart",
  "test/features/analyze/analysis_vision_adapter_test.dart",
  "docs/sdd/05-epic-04-ai-guitar-teacher.md",
  "docs/sdd/07-epic-06-audio-analysis-2.md",
  "docs/rounds/e05-r27-tutor-analysis-vision-adapters.md",
  "docs/adr/0194-tutor-analysis-vision-evidence-adapters.md",
]
gate_tests = [
  "test/features/vision",
  "test/features/ai_tutor",
  "test/features/analyze",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ, lezárva 2026-08-08 — ld. §0.0 a teljes mért
> listáért):** `origin/main` + E05-R22/R23/R24 merge — teljesült. Olvasd újra
> az Epic 4 **`TutorContextSnapshot`** mai alakját (`lib/features/ai_tutor/
> application/context/tutor_context_snapshot.dart`) és a **redakciós
> szabályát** (ADR 0141: a prompt-builder CSAK redaktált snapshotot fogad),
> a `TutorContextAssembler`/`ContextRedactor` folyamot és a `TutorSourceRef`
> citációs típust. **A vision snapshot ehhez a mai alakhoz illeszkedik, NEM**
> egy elavult, batch-írt feltételezéshez — a fájl maga is `allowed_paths`-on
> van, KIZÁRÓLAG additív enum-bővítéshez (§0.0 5. pont). **ÚJ ADR
> [0194](../adr/0194-tutor-analysis-vision-evidence-adapters.md)** (a brief
> eredeti „Nincs ÚJ ADR (0161/0162 + 0141 bővítése)" állítása felülbírálva —
> a „0161"/„0162" sosem létezett fájl, ld. §0.0 1. pont). PREPARED→PLANNING,
> brief commit megtörtént.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Pre-flight lezárva 2026-08-08, orchesztrátor: Claude Sonnet 5.** Az eredeti
(2026-08-05-i) brief kilenc pontja mérve elavultnak/hiányosnak bizonyult —
egy ADR-hivatkozás, négy fájlútvonal, egy barrel-célpont, egy hiányzó
enum-bővítési pont, egy elhagyott SDD-feladat és egy alulspecifikált
típusleltár. Teljes indoklás:
[ADR 0194](../adr/0194-tutor-analysis-vision-evidence-adapters.md).

1. **„ADR 0161"/„ADR 0162" nem létező fájlok.** `ls docs/adr | grep -E
   '^01(61|62)'` → 0 találat. Ugyanaz a mintázat, mint a 0170→0189 (R21),
   „0162"→0190 (R22) és „ADR 0165"→0182 (R25/R26) esetek: a batch-brief egy
   sosem realizálódott jövőbeli számra hivatkozott. **ÚJ ADR
   [0194](../adr/0194-tutor-analysis-vision-evidence-adapters.md)** rögzíti a
   döntéseket — nincs mit „bővíteni".
2. **A `TutorVisionContextAdapter` útvonala javítva.** A brief
   `lib/features/ai_tutor/data/context/...`-ot írt elő (nem létező
   könyvtár); a mind a nyolc meglévő tutor-oldali context-adapter
   `lib/features/ai_tutor/application/context/adapters/` alatt él — az
   allowed_paths ezt követi, a tesztje a tükör
   `test/features/ai_tutor/application/context/adapters/` alatt.
3. **`VisionContextSnapshot`-nak hiányzó dedikált tesztje pótolva.** ÚJ
   `test/features/vision/domain/integration/vision_context_snapshot_test.dart`
   — az AC #1 „kulcsbizonyítéka" korábban nem kapott saját fájlt.
4. **`VisionClaimGuard` tesztje a helyes, beágyazott könyvtárba került.**
   `test/features/vision/domain/integration/vision_claim_guard_test.dart` (a
   forrás `domain/integration/` alatt van, nem lapos `domain/` — a könyvtár
   már tükrözve van a tesztfában, `vision_integration_barrel_boundary_test.dart`,
   E05-R26).
5. **Exportpont a SZŰK, nested barrel, nem a wide.**
   `lib/features/vision/domain/integration/public.dart` váltja a brief
   eredeti `lib/features/vision/public.dart` bejegyzését — a HANDOFF.md §3
   kétszer explicit előírta, hogy minden ÚJ cross-feature vision-fogyasztó a
   szűk barrelt használja (ADR 0176/0193 mintája); a két új fájl pont a
   `domain/integration/` könyvtárba kerül, a meglévő szűk barrel mellé.
6. **`lib/features/ai_tutor/application/context/tutor_context_snapshot.dart`
   felvéve az allowed_paths-ra, SZIGORÚAN additív scope-pal.** A brief §5
   pont 4 döntése („a beillesztés ugyanazon a redaktált úton történik")
   csak úgy teljesíthető, ha a Tutor-adapter valódi `TutorContextField`-et
   ad vissza — de a `TutorContextFieldKey`/`ContextSourceFeature` enumoknak
   ma nincs `vision` esete, és ez a fájl nem volt a listán. **A megengedett
   diff KIZÁRÓLAG:** egy `vision` érték mindkét enumhoz, semmi más ebben a
   fájlban (nincs `context_purpose.dart`/`context_budget.dart` érintés —
   egyik `ContextPurpose` sem engedélyezi még a mezőt, production
   viselkedés változatlan). ADR 0194 Döntés 5 a teljes indoklás (mért
   biztonság: nincs kimerítő switch e két enumra a `context_purpose.dart`-on
   és a `context_budget.dart` nem-exhaustive listáján kívül).
7. **A brief absztrakt mezőleltára („aggregátum + insight-kód + confidence +
   observability") meglévő típusokra kötve, nem új vokabuláriumra** — ld.
   §5.1 lent. Kötelező olvasmány dispatch előtt: `lib/features/vision/
   domain/evidence/vision_evidence.dart` (E05-R22), `lib/features/vision/
   domain/feedback/insight_code.dart` + `feedback_policy.dart` (E05-R23).
8. **„Közös session-idő" = `SessionTimestamp`**
   (`lib/features/vision/domain/sync/vision_clock.dart`, E05-R21) — nem új
   típus, nem a teljes `ClockMapping`-apparátus. Ld. §5.1.
9. **SDD Kör 27 saját feladatlistájának nyolcadik pontja pótolva a
   scope-ban.** `docs/sdd/06-epic-05-computer-vision.md` „Kör 27 →
   Feladatok" előírja: „Frissítsd a Chapter 5/7 integrációs
   dokumentációt." — ez hiányzott a brief §3/§4-ből. Két kis, additív
   beszúrás az allowed_paths-hoz és a §6 AC-hez adva (Chapter 5 =
   `docs/sdd/05-epic-04-ai-guitar-teacher.md`, Chapter 7 =
   `docs/sdd/07-epic-06-audio-analysis-2.md`).

## 1. Cél

A vision eredmények **minimális, privacy-safe és claim-guardolt** elérhetővé
tétele a Tutor és az Analysis számára — úgy, hogy a tutor **csak valid
bizonyítékból** beszélhessen a vizuális megfigyelésekről.

## 2. Jelenlegi állapot (mért, `5d082dc`; pre-flightban újramérve `dc78cc9`-n, változatlan)

- Az Epic 4 kész: `TutorContextSnapshot` **redaktált** bemenettel, trusted/
  untrusted határ, `TutorSourceRef` citációk (ADR 0141), tool-allowlist (0137),
  action-confirmation (0139).
- Az Analysis (`lib/features/analyze/`) audio-klip elemzést ad; vision-hivatkozás
  nincs.
- A `visionTutorIntegrationEnabled` és `visionAnalysisIntegrationEnabled` OFF.

## 3. Scope

**Benne:** `VisionContextSnapshot` (**csak** aggregátum + insight-kód +
confidence + observability), `VisionClaimGuard` (bizonyíték nélküli vizuális
állítás blokkolása), a Tutor-oldali context-adapter, az Analysis-oldali
vision-referencia adapter közös session-idővel, cross-modal **inferred**
provenance, és deterministic fallback `notObservable` esetre.

**Kívül — TILOS:** prompt-sablon módosítása, tutor tool/action réteg,
raw frame / teljes landmark-stream / arcpont bárhová továbbadása, UI,
persistence (R28).

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../vision/domain/integration/vision_context_snapshot.dart` | ÚJ | minimalizált snapshot |
| `.../vision/domain/integration/vision_claim_guard.dart` | ÚJ | claim-őr |
| `.../vision/domain/integration/public.dart` | meglévő | additív export (szűk barrel, §0.0 5. pont) |
| `.../ai_tutor/application/context/adapters/tutor_vision_context_adapter.dart` | ÚJ | tutor-oldali adapter (§0.0 2. pont) |
| `.../ai_tutor/application/context/tutor_context_snapshot.dart` | meglévő | **KIZÁRÓLAG** additív: `vision` érték a `TutorContextFieldKey`-hez és a `ContextSourceFeature`-höz (§0.0 6. pont, ADR 0194 Döntés 5) |
| `.../analyze/model/analysis_vision_reference.dart` | ÚJ | analysis-hivatkozás |
| `.../analyze/providers/analysis_vision_adapter.dart` | ÚJ | analysis-oldali adapter |
| `*/public.dart` (ai_tutor, analyze) | meglévő | additív export, opcionális (nincs élő cross-feature hívó ebben a körben) |
| `test/features/vision/domain/integration/vision_context_snapshot_test.dart` | ÚJ | kulcsbizonyíték: pinnelt kulcshalmaz (§0.0 3. pont) |
| `test/features/vision/domain/integration/vision_claim_guard_test.dart` | ÚJ | claim-guard mátrix (§0.0 4. pont) |
| `test/features/ai_tutor/application/context/adapters/tutor_vision_context_adapter_test.dart` | ÚJ | tutor-adapter teszt (§0.0 2. pont) |
| `test/features/analyze/analysis_vision_adapter_test.dart` | ÚJ | round-trip |
| `docs/sdd/05-epic-04-ai-guitar-teacher.md` | meglévő | additív, célzott bekezdés (§0.0 9. pont) |
| `docs/sdd/07-epic-06-audio-analysis-2.md` | meglévő | additív, egy checklist-sor (§0.0 9. pont) |
| `docs/rounds/e05-r27-*.md` | meglévő | §10 handoff |
| `docs/adr/0194-*.md` | meglévő (pre-flight írta) | nincs implementer-oldali edit |

**Tilos zóna:** minden más; `lib/features/ai_tutor/` prompt/tool/action fájlok
(`application/prompts/`, `application/orchestration/`, `application/tools/`,
`application/controller/`); `lib/features/vision/public.dart` (wide barrel —
§0.0 5. pont); `context_purpose.dart`/`context_budget.dart` (§0.0 6. pont);
`docs/rag`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Adatminimalizálás (ADR 0194 Döntés 2 — a brief eredeti „ADR 0161"
   hivatkozása nem létező fájl volt, ld. §0.0 1. pont):** a snapshot
   **kizárólag** aggregátumot,
   insight-kódot, confidence-t és observability-t tartalmaz. **NEM elfogadható:**
   raw frame, teljes landmark-idősor, arcpont, kép-URI, vagy „debug" mező —
   semmilyen flag mögött sem.
2. **Claim guard fail-closed:** ha egy vizuális állításhoz **nincs** megfelelő
   confidence-ű evidence, az állítás **blokkolt**, és a fallback egy
   determinisztikus `notObservable` szöveg-kód. **NEM elfogadható:** „a modell
   majd óvatosan fogalmaz" indoklás — a guard gépi.
3. **Cross-modal insight `inferred`-ként jelölt** (nem `observed`), és a
   provenance megmondja, mely audio és mely vision bizonyítékból származik.
4. **A vision snapshot az Epic 4 redakciós határának *untrusted-mentes*
   oldalán van:** géptől jövő, strukturált adat, nem felhasználói szöveg —
   de a beillesztés **ugyanazon a redaktált úton** történik. **NEM elfogadható**
   a snapshot beszúrása a prompt-építés megkerülésével.
5. **Analysis ↔ Vision összekapcsolás közös session-idővel** (R21 mapping),
   nem wall clockkal.
6. **Egyik adapter sem küld hálózatra semmit** — a network-guard teszt méri.
   Az adapterek pure függvények (bemenet: már kiszámolt evidence/insight
   adat; kimenet: minimalizált snapshot/referencia) — nincs Dio/http
   importjuk, tehát ez konstrukció szerint teljesíthető; a teszt-cella a
   `test/app/offline_network_guard_test.dart` mintáját (saját
   `HttpClientAdapter` fake, kérésszámláló) tükrözheti kicsiben, KÜLÖN,
   nehézsúlyú app-bootstrap nélkül — nem kötelező önálló fájl, elfér a §4
   listán már szereplő adapter-teszteken belül.

## 5.1 Mért alaptípusok — erre épülj, ne találj ki új vokabuláriumot

A pre-flight (ADR 0194 Kontextus 7–8. pont) kigrepelte a brief absztrakt
mezőleltárát a kódban. Ezek MÁR LÉTEZNEK — importáld és építs rájuk:

| Brief-fogalom | Konkrét típus, ma | Fájl |
|---|---|---|
| „insight-kód" | `InsightCode` (11 zárt érték) + `VisionInsight{code, confidence, evidenceIds, ...}` | `lib/features/vision/domain/feedback/insight_code.dart` |
| „confidence" | `VisionEvidence.confidence` / `VisionInsight.confidence` (`double [0,1]`, konstruktor-validált) | `lib/features/vision/domain/evidence/vision_evidence.dart` |
| „observability" | `ObservationState {observed, inferred, notObservable, experimental}` | ugyanott |
| „bizonyíték nélkül" (claim-guard bemenet) | `VisionEvidence` jelenléte/hiánya + `.confidence` — a MEGLÉVŐ `FeedbackPolicy` (`positiveConfidenceThreshold`/`negativeConfidenceThreshold`) AZONOS ALAKÚ, fail-closed katalógus-lookup mintáját kövesd, saját, Tutor-specifikus küszöbbel | `lib/features/vision/domain/feedback/feedback_policy.dart` |
| „közös session-idő" | `SessionTimestamp` (monotonic mikroszekundum-wrapper) — NEM `ClockMapping`/kalibráció (az élő audio+vision latency-problémára való, itt overkill) | `lib/features/vision/domain/sync/vision_clock.dart` |
| `notObservable` fallback-kód | ugyanaz a névalak, mint `ObservationState.notObservable` / `visionInsightSetupNotObservable` | (konvenció, nincs kötelező megosztott konstans) |

**Fontos, NE keverd össze:** a MEGLÉVŐ `SafetyClaimGuard`
(`lib/features/vision/domain/safety/safety_claim_guard.dart`, E05-R20) egy
MÁSIK tengelyen dönt (melyik TARTALOM-OSZTÁLY engedhető meg — orvosi/
diagnosztikai határ), nem azonos a brief ÚJ `VisionClaimGuard`-jával
(bizonyíték-elégségesség). A kettő egymás mellett él, nem összevonandó, egyik
sem helyettesíti a másikat.

## 6. Acceptance criteria

- [ ] **Minimization snapshot teszt (a kör kulcsbizonyítéka):** a
      `VisionContextSnapshot` szerializált kulcskészlete egy **rögzített**
      halmazzal egyezik; új mező csak a snapshot frissítésével kerülhet be.
- [ ] **Tiltott-mező mátrix:** frame / landmark-lista / arcpont / kép-URI —
      mind a négy típusra teszt, hogy a snapshot **nem tartalmazza**, még
      akkor sem, ha a forrás evidence hordozza.
- [ ] **Claim-guard mátrix:** confidence a küszöb **alatt / rajta / fölött** ×
      evidence **van / nincs** = 6 cella; állítás csak az „evidence van +
      küszöb fölött/rajta" cellákban engedélyezett.
- [ ] **Fallback-teszt:** blokkolt állítás esetén determinisztikus
      `notObservable` kód, kétszeri futás azonos.
- [ ] **Analysis round-trip:** a vision-referencia a közös session-idővel
      oda-vissza feloldható; wall clock **nem** szerepel.
- [ ] **Network-spy teszt:** az adapterek használata **nulla** hálózati kérést
      generál (a repó meglévő offline-guard mintájával).
- [ ] **Valódi-sértés próba (§10):** a landmark-lista átengedése a snapshotba
      → a minimization teszt PIROS → visszaállítás.
- [ ] **SDD Chapter 5/7 integrációs jegyzet (§0.0 9. pont, SDD Kör 27 saját
      feladatlistája):** rövid, additív bekezdés/checklist-sor a két
      fejezetben, ami rögzíti, hogy a vision evidence a Tutor/Analysis felé
      KIZÁRÓLAG ezen a minimalizált, claim-guardolt úton érhető el.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision test/features/ai_tutor test/features/analyze
```

Külön processzek, nincs `&&`/pipe/`tail`. CI-dispatch/PR/merge = orchestrátor.

## 8. Implementációs sorrend

1. RED: minimization + tiltott-mező + claim-guard mátrix.
2. `VisionContextSnapshot` + `VisionClaimGuard`.
3. Tutor-adapter (a redaktált úton).
4. Analysis-adapter + network-spy; gate.

## 9. Kockázatok

- **A „hasznos extra mező"** (pl. néhány landmark „a jobb magyarázatért")
  csendben sérti az adatminimalizálást — a rögzített kulcshalmaz az őr.
- **A guard megkerülése** a tutor prompt oldaláról: ezért a prompt-fájlok a
  tilos zónában vannak, és az integráció csak az adapteren át mehet.

**STOP:** raw/landmark adat továbbadása, prompt-fájl módosítása vagy a
claim-guard lazítása helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

### Megvalósítás

- `vision_context_snapshot.dart`: minimális, szerializálható Vision snapshot
  (`sessionId`, `SessionTimestamp`, `InsightCode`, confidence,
  `ObservationState`); a stabil JSON-alak pontosan öt rögzített kulcs.
- `vision_claim_guard.dart`: saját, zárt Tutor-claim katalógusú, 0.70-es
  küszöbű fail-closed gate. Hiányzó, `notObservable` vagy küszöb alatti
  evidence és érvénytelen confidence esetén a determinisztikus
  `InsightCode.setupNotObservable` fallbackot adja.
- `vision/domain/integration/public.dart`: kizárólag a két új,
  domain-safe integrációs contract exportja; a wide barrel érintetlen.
- `tutor_context_snapshot.dart`: csak a két additív `vision` enum-érték;
  `tutor_vision_context_adapter.dart`: valódi, verziózott
  `TutorContextField`-re vetíti a minimális snapshotot.
- `analysis_vision_reference.dart` és `analysis_vision_adapter.dart`:
  audio- és vision-evidence ID-ket `SessionTimestamp`-tel kapcsol össze,
  az eredmény `ObservationState.inferred`; nincs wall-clock vagy transport.
- A négy új teszt lefedi a minimization, claim-guard, Tutor-adapter és
  Analysis round-trip/network-spy contractot. A Chapter 5/7 célzott,
  additív integrációs megjegyzést kapott.

### Acceptance evidence

- **Minimization:** `vision_context_snapshot_test.dart` a pontos, sorrendben
  rögzített kulcshalmazt ellenőrzi:
  `sessionId`, `sessionTimestampUs`, `insightCode`, `confidence`,
  `observationState`.
- **Tiltott mezők:** ugyanaz a teszt külön ellenőrzi, hogy `frame`,
  `landmarks`, `facePoints` és `imageUri` nincs a szerializált snapshotban.
- **Claim-guard mátrix:** a hat cella (evidence nincs/van × confidence
  0.69/0.70/0.71) tesztelt; csak a jelenlevő evidence 0.70-en és fölötte
  engedélyezett. Külön teszt blokkolja a `notObservable` és a saját,
  0.69-es confidence-ű evidence-t akkor is, ha a bemeneti állított
  confidence magas.
- **Fallback:** két azonos denied hívás ugyanazt a
  `InsightCode.setupNotObservable` kódot adja.
- **Analysis:** 2.5 másodperces klip-eltolás
  `SessionTimestamp(1_000_000)`-ról `SessionTimestamp(3_500_000)`-ra és
  vissza round-tripel; a `TimelineChord.startSec` és
  `TimelineStrum.timeSec` is ugyanarra a közös idővonalra vetül. Az
  összekapcsolás `inferred`, mindkét evidence ID-t megtartja. A
  `HttpOverrides` spy klienslétrehozási száma 0.
- **Valódi-sértés próba:** ideiglenesen a snapshot JSON-jába került
  `'landmarks': const <Object>[]`; a célzott teszt PIROS lett. A pontos
  kulcspróba-kimenet: `Actual: ... 'observationState', 'landmarks' ...`
  és `Which: ... longer than expected`; a tiltott-mező próba pedig
  `Expected: not contains 'landmarks'`. A probe vissza lett állítva a gate
  előtt.
- **SDD-integráció:** Chapter 5 rögzíti a minimalizált, claim-guardolt Tutor
  utat; Chapter 7 checklistje a közös `SessionTimestamp`-es, inferred
  Analysis-hivatkozást írja elő.

### Futtatott ellenőrzések

- `flutter test test/features/vision/domain/integration/vision_context_snapshot_test.dart test/features/vision/domain/integration/vision_claim_guard_test.dart test/features/ai_tutor/application/context/adapters/tutor_vision_context_adapter_test.dart test/features/analyze/analysis_vision_adapter_test.dart`
  → előbb **18 teszt zöld**, majd a TimelineChord/TimelineStrum RED→GREEN
  bővítés után a külön Analysis-teszt **5 teszt zöld**.
- `flutter test test/features/vision/domain/integration/vision_context_snapshot_test.dart`
  a szándékos landmark-probe alatt → **2 várt hiba**, majd a probe
  visszaállítva.
- `tools/round-gate.sh test/features/vision test/features/ai_tutor test/features/analyze`
  → első futás: az analyzer 5 `unnecessary_import` infót talált; a redundáns
  tesztimportok eltávolítva, majd teljesen újrafuttatva.
- `tools/round-gate.sh --result-json /tmp/e05-r27-round-gate-final.json test/features/vision test/features/ai_tutor test/features/analyze`
  → **pass**, `exit_code: 0`, `failed_step: null`; format, analyze,
  mindhárom célzott test-rész, architecture, secrets és l10n zöld.

### Eltérések és nem futtatott ellenőrzések

- A brief által engedett `ai_tutor/public.dart` és `analyze/public.dart`
  exportbővítése nem kellett: nincs élő cross-feature hívó, a szerződés a
  szűk Vision barrelen keresztül elérhető.
- Lokális teljes `flutter test`, property gate és APK build nem futott;
  ezek a kör-branchre dispatchelt CI/orchestrátor kapui. Backend-kód nem
  változott, ezért backend gate nem releváns.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r27-tutor-analysis-vision-adapters-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.

> **Reviewer figyelem:** privacy- és prompt-injection-érintett kör — a
> `security-reviewer` ágens bevonása KÖTELEZŐ.
