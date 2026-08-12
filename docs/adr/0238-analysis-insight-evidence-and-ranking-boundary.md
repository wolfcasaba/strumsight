# ADR 0238 — Analysis insight evidence and ranking boundary

- **Státusz:** Elfogadva (E06-R20 pre-flight, 2026-08-12; újra-ellenőrizve
  egy második orchestrátor-sessionben ugyanazon a napon, ld. „Re-verifikáció")
- **Kör:** E06-R20 — Determinisztikus insightok és hotspot ranking
- **Implementer motor:** Terra
- **Epic:** [Chapter 7 — Epic 6: Audio Analysis 2.0](../sdd/07-epic-06-audio-analysis-2.md)
  Kör 20; §20.1–20.7 (Deterministic insight engine)
- **Kontext-ADR-ek:** [0216](0216-analysis-confidence-calibration-and-abstention.md)
  (abstention: bizonytalan/hiányzó mérésből nincs állítás),
  [0218](0218-analysis-metric-id-and-version-governance.md) (verziózott,
  kompatibilis metric ID), [0219](0219-analysis-capability-aware-publication.md)
  (csak publikálható, capability-aware tény lehet consumer-bemenet),
  [0228](0228-event-evidence-model-and-timeline-builder-contract.md)
  (stabil evidence ID-k), [0236](0236-analysis-technique-proxy-safety-and-naming.md)
  (Lab-only technique proxy tilalom).

## Re-verifikáció (második orchestrátor-session, 2026-08-12, main @ `7dbaa349`)

Ez az ADR eredetileg egy korábbi, önálló pre-flight-sessionben (fallback
orchestrátor, munkapéldány `/home/ubuntu/ss-mm-e06-r20`, pre-flight-commit
`fa836e87`) készült, de az a pre-flight-commit sosem futott be a `main`-be —
közben egy H3 self-heal (PR #236) a briefet a `main`-en, a pre-flight-commit
ismerete nélkül revideálta (a `test/fixtures/analysis/insights` megosztott
fixture-hely hiányát javítva). A jelen, második orchestrátor-session a §0.2
örökség-ellenőrzés szerint megtalálta ezt a nem-merge-elt pre-flightot, és
ÚJRA lemérte a lenti „Kontextus" minden állítását a mai kódon, mielőtt
felhasználta: `AnalysisHotspot` (`lib/features/audio_analysis/domain/analysis_segment.dart`)
ma is `metricIds`/`evidenceIds`-t hordoz és `AnalysisMetricId.contains`-szal
validál; `AnalysisMetricId` (`lib/features/audio_analysis/domain/analysis_metric_catalog.dart`)
ma is öt `technique.*` katalógus-bejegyzést tartalmaz; a meglévő
`domain/analysis_insight.dart` (R02, bekötetlen) `factIds`-t hordoz,
`evidenceIds`-t NEM; a technique-proxy modul
(`lib/features/audio_analysis/engine/metrics/technique_proxies.dart`)
önálló, `TechniqueProxyGate`/`CapabilityStatus`-mögötti fájl, `AnalysisDocument`-
bekötés nélkül (HANDOFF E06-R18 banner). Minden állítás stimmelt — az ADR
tartalma emiatt VÁLTOZATLAN marad, csak ez a szakasz és a fejléc bővült (két
divergens ADR-szöveg ugyanarra a számra rosszabb lenne, mint az
újrahasznosítás, a driver-skill §0.2 szabálya szerint).

## Kontextus

**Mért 2026-08-12-én, `main` @ `3f5ac41e`:**

1. `AnalysisDocument` immutable `metrics`, `hotspots`, `timeline` és a régi,
   bekötetlen `insights` listát tartja. A már létező
   `domain/analysis_insight.dart` payload `factIds`-t hordoz, de
   `evidenceIds`-t nem; a fájl nincs az E06-R20 `allowed_paths` listáján.
2. `AnalysisHotspot` már explicit `metricIds` és `evidenceIds` listát,
   severity-t és confidence-et hordoz. A timeline eventjei és chord segmentjei
   stabil ID-val rendelkeznek, így az R20 insightjai ellenőrizhetően
   visszavezethetők a dokumentum mért elemeire.
3. `AnalysisMetricId.known` öt `technique.*` azonosítót is tartalmaz, de ADR
   0236 szerint ezek nem jelenhetnek meg `AnalysisDocument.metrics`-ben; csak
   Lab-mode `TechniqueProxyReport` outputjai. Katalógus-tagság önmagában tehát
   nem jogosít consumer-facing insightot.

## Döntés

1. **Az R20 insight engine új, önálló és bekötetlen modul.** Saját
   evidence-first insight-outputot és `AnalysisInsightContext`-et definiál a
   `domain/insights/` alatt. Nem módosítja az R02-es
   `AnalysisDocument.insights` payloadot, nem ír document-codecet és nem
   köti a V1 Analyze vagy a V2 pipeline útvonalába.
2. **Minden szabályeredmény referenciálisan zárt.** Nem üres `factIds` és
   `evidenceIds` listát ad; minden fact ID a context dokumentumának publikált
   metrics-listájában, minden evidence ID event-, chord-segment- vagy
   hotspot-hivatkozásban létezik. Hiányzó, `unavailable` vagy
   `notApplicable` metric esetén a tényre épülő szabály `null`.
3. **A Lab-only `technique.*` namespace kemény kizárás.** Az insight context
   nem engedi ilyen azonosító használatát, és a szabályok nem importálják a
   technique-proxy modult. Ez az ADR 0236 consumer boundary-jának része, nem
   puszta jelenlegi pipeline-feltételezés.
4. **A rangsor state-mentes és determinisztikus.** Elsődleges rendezés a
   szabály priorityja, azonos priority mellett lexikografikus `ruleId`; a
   hotspotoknál severity, majd confidence és stabil ID ad sorrendet. A
   maximum-policy pontosan egy improvement, strength, next-action és quality
   warning slotot mutathat, a többi már rendezett `additionalInsights`.
5. **Lokalizáció és action boundary.** A domain output csak `messageKey`-t és
   string-alapú `messageArgs`-ot hordoz; kész UI-mondat, `BuildContext`, route
   vagy callback nincs benne. A recommended action sealed leíró, a UI/Tutor
   adapter és tényleges navigáció külön kör.

## Következmények

- A kilenc kezdeti szabály mind dokumentált mérést, nem generatív szöveget
  használ; az R25 trendje hiányában a comparison szabály `null` marad.
- A meglévő `AnalysisDocument.insights` és codec változatlan. Egy későbbi
  integrációs körnek kell a régi payload és e bizonyíték-first output közötti
  kompatibilis mappingról dönteni.
- A `public.dart` csak az új, cross-feature consumernek szánt contractokat és
  rangsort exportálja. V1 shipping viselkedés változatlan marad.

## Elutasított alternatívák

- **Az R02 `analysis_insight.dart` azonnali bővítése `evidenceIds`-szel.**
  Elvetve: scope-on kívüli fájl és document/codec migrációt indítana; az R20
  acceptance criterionjai közvetlenül az új, még be nem kötött module-on
  mérhetők.
- **Technique proxyból insight képzése.** Elvetve: ADR 0236 szerinti Lab-only
  adatból consumer-facing coaching állítás lenne.
- **Rangsor Map/Set iterációs sorrendje szerint.** Elvetve: nem
  reprodukálható, és a §20.5 maximum-policy tartalmát futásonként módosíthatná.

## A visszavonás feltétele

Felülvizsgálandó egy V2 document/pipeline-integrációs körben, ha a régi
`AnalysisDocument.insights` payload nem képezhető veszteségmentesen az
evidence-first contractra, vagy ha a fogyasztói API-nak több evidence típust
kell hordoznia, mint event, chord segment és hotspot.
