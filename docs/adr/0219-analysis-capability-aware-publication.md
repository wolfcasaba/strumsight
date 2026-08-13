# ADR 0219 — Analysis capability-aware publication

- **Státusz:** Elfogadva (E06-R01 pre-flight, 2026-08-11)
- **Kör:** E06-R01 — Analyze V1 baseline, mérés és ADR-ek
- **Implementer motor:** Terra — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** [Chapter 7 — Epic 6: Audio Analysis 2.0](../sdd/07-epic-06-audio-analysis-2.md)
  Kör 1; §7 (Capability-modell, teljes szakasz: §7.1-7.5) — a batch
  harmadik, keresztmetsző kiegészítése (a brief §0.0 szerint az SDD Kör 1
  három ADR-t nevez meg; ez a batch-bővítés egyike)
- **Kontext-ADR-ek:** [0216](0216-analysis-confidence-calibration-and-abstention.md)
  (a confidence-küszöb a publikációs szabály egyik bemenete),
  [0114](0114-song-validator-normalizer-capability-boundary.md)
  (a `SongCapabilityResolver` severity→capability precedens, E03-R05)
- **Sorszám-jegyzet:** lásd [ADR 0215](0215-analysis-document-versioning.md)
  fejléce — a teljes hatos blokk 0200–0205-ről 0215–0220-ra tolódott.

## Kontextus

**Mért 2026-08-11-én:**

1. Az SDD Ch7 §7 már **tételesen specifikálja** ezt a döntést: `enum
   AnalysisCapability` (14 érték: `signalQuality` … `sectionComparison`,
   §7.1), `enum CapabilityStatus { available, degraded, unavailable,
   notApplicable }` (§7.2), `enum CapabilityUnavailableReason` (13 érték:
   `clipTooShort` … `internalFailure`, §7.3), `CapabilityReport { capability,
   status, confidence, reason?, details }` (§7.4). §7.5 (Publikációs
   szabály): egy metrika csak akkor jelenhet meg normál értékként, ha
   capability `available`/megfelelően jelölt `degraded`, a confidence a
   küszöb felett van, az input quality nem zárja ki, elegendő esemény áll
   rendelkezésre, és a metrika definíciója érvényes az adott analysis
   mode-ban. Ellenkező esetben az UI **magyarázott unavailable** állapotot
   mutat.
2. **Kétszeres, közvetlenül átvehető precedens létezik a kódban:**
   - `SongCapabilityResolver` (E03-R05, [ADR 0114](0114-song-validator-normalizer-capability-boundary.md),
     `lib/features/song_trainer/domain/services/song_capability_resolver.dart`) —
     severity→capability leképezés, ahol a chord/pitch tengelyek
     **függetlenek** a súlyosságtól, és a §6 acceptance-mátrix mind a négy
     kombinációja (persistable+degraded, persistable+full, stb.)
     reprezentálható. Ugyanez a „ne egyetlen boolean-ba sűrítsd a több
     dimenziót" elv alkalmazandó az Analysis capability-kre.
   - `MetricValue`/`MetricNotApplicable`/`MetricInsufficientData`
     (E02-R18, [ADR 0084](0084-practice-history-v2-and-coaching.md),
     `lib/features/practice/domain/model/practice_metrics.dart:7-68`) —
     sealed hierarchia, ahol `MetricNotApplicable` esetén a UI-blokk
     **ki sem kerül a fába**, `MetricInsufficientData` esetén lokalizált
     „nincs elég adat" jelenik meg, **soha nem 0% vagy N/A szám**
     (HANDOFF §2, E02-R18 bejegyzés). Ez SZÓ SZERINT a §7.5 elve, már
     szállítva egy másik feature-ben.
3. A jelenlegi V1 `AnalyzeResult`-nak **nincs** capability-fogalma: minden
   mező mindig jelen van (`bpm: 0` ha nincs elég strum, ld.
   `_bpmFromStrums` — `return median > 0 ? … : 0`), azaz a hiányt egy
   **hamis nullaérték** jelzi, nem egy explicit `unavailable` állapot.
   Ez pontosan az SDD §7.5 „NEM elfogadható: 0-t vagy N/A-t írunk ki és
   kész" mintája — a V1 jelenlegi viselkedése a rossz példa, amit a V2
   javít.

## Döntés

1. **A négy `CapabilityStatus` érték és a 13 `CapabilityUnavailableReason`
   érték az SDD §7.1-7.3 szerint, változtatás nélkül kerül át a V2
   domainmodellbe** (E06-R02, E06-R19) — ez az ADR nem módosítja az SDD
   enum-katalógusát, csak **kötelezővé teszi a betartását**.
2. **A publikációs szabály (SDD §7.5) az EGYETLEN kapu egy metrika normál-
   érték-megjelenítéséhez.** A `SongCapabilityResolver` mintáját követve a
   resolver **pure, determinisztikus, side-effect-mentes** függvény: azonos
   bemenet (signal quality + confidence + esemény-szám + capability-státusz)
   mindig azonos `CapabilityReport`-ot ad.
3. **A capability-tengelyek egymástól függetlenek** (a `SongCapabilityResolver`
   chord/pitch-függetlenség mintája): egy `AnalysisDocument` egyszerre
   hordozhat `available` `signalQuality`-t és `unavailable` (`insufficientEvents`)
   `chordTimeline`-t — a kettő nem redukálható egyetlen dokumentum-szintű
   „sikerült/nem sikerült" flag-re.
4. **Amikor egy capability `unavailable`, a UI a `CapabilityUnavailableReason`-t
   lokalizált szöveggé fordítja** (a `MetricInsufficientData` „nincs elég
   adat" mintája) — a blokk vagy explicit „ezt nem tudtuk megmérni, mert…"
   szöveggel jelenik meg, vagy (ha a UX úgy dönt) ki sem kerül a fába
   (`MetricNotApplicable` mintája) — de **soha nem** egy csendes 0/N/A/üres
   mező.
5. **A `degraded` státusz explicit jelölt**, nem hallgatólagos: egy
   `degraded` metrika UI-ban megkülönböztethető egy `available`-től (pl.
   vizuális jelzés + a degradáció okának megjelenítése Lab módban).

**NEM elfogadható:** „0-t vagy N/A-t írunk ki és kész" — egy hiányzó vagy
alacsony-bizalmú mérés csendes nullaértékkel vagy üres cellával való
helyettesítése magyarázat nélkül; egyetlen dokumentum-szintű „sikerült"
flag, ami elfedi, hogy MELYIK capability miért nem elérhető; a `degraded`
és `available` UI-beli megkülönböztethetetlensége.

## Következmények

**E06-R30 (2026-08-13):** a döntés változatlan; a rollout továbbra is flag-off/shadow.

- A `CapabilityAwarePublicationPolicy`/`AnalysisCapabilityResolver`
  (E06-R19, SDD Kör 19) ennek az ADR-nek a szerződését implementálja a
  `SongCapabilityResolver` szerkezeti mintáján — ez a kör csak a döntést
  rögzíti dokumentumban.
- A UI-réteg (E06-R25+, Overview/Metric card) minden metrika-kártyát a
  `CapabilityStatus` szerint ágaztat, a `MetricNotApplicable`/
  `MetricInsufficientData` widget-mintát követve.
- A `docs/manual-testing/analysis-eval-matrix.md` (ez a kör hozza létre)
  PENDING sorokat kap minden `CapabilityUnavailableReason`-höz: melyik
  fixture/felvétel produkálja megbízhatóan.
- A V1 `_bpmFromStrums`-féle „0 ha nincs elég adat" minta **érintetlen
  marad** ebben a körben — a capability-alapú publikáció csak a V2 úton
  jelenik meg ([ADR 0220](0220-audio-analysis-v2-parallel-rollout-boundary.md)).

## Elutasított alternatívák

- **Egyetlen `bool hasEnoughData` flag `CapabilityStatus` enum helyett.**
  Elvetve: nem tudja kifejezni a `degraded`/`notApplicable` közti
  különbséget, és nincs helye az `unavailable` OKÁNAK — a felhasználó
  nem tudná meg, MIÉRT hiányzik a mérés.
- **A capability-modell újratervezése az SDD §7-től eltérően** (pl. kevesebb
  `CapabilityUnavailableReason` érték, „egyszerűsítés" indokkal). Elvetve:
  az SDD már tételesen specifikálja a 13 okot; egy szűkített lista egy
  jövőbeli kör számára hiányzó okkódot jelentene, amit csak egy SDD-
  felülvizsgálattal, nem hallgatólagosan lehetne pótolni.
- **A `SongCapabilityResolver` közvetlen újrafelhasználása (import)** az
  Analysis feature-ből. Elvetve: cross-feature import a `song_trainer`
  domainból megsértené a feature-határt (`tool/check_architecture.dart`
  `crossFeatureImportsMustUsePublicApi`) — a MINTA (szerkezeti elv)
  másolható, a KONKRÉT típus nem importálható.

## A visszavonás feltétele

Felülvizsgálandó, ha a valós-audio kiértékelés (SDD §29.6-29.7, a meglévő
`docs/eval/real-audio-dsp-baseline.md` korpuszon) azt méri, hogy egy adott
`CapabilityUnavailableReason` a gyakorlatban SOSEM fordul elő megkülönböz-
tethetően a többitől (pl. `inputClipped` és `inputTooNoisy` mindig együtt
jár a rendelkezésre álló DSP-vel) — ekkor az ok-lista egy dedikált,
mért kör keretében szűkíthető, ADR-felülvizsgálattal.
