# Audio Analysis valós-audio kiértékelési mátrix

Minden sor **PENDING**: a V1 szintetikus baseline nem helyettesíti a valós eszközös, címkézett audio kiértékelést. A capability-nevek és unavailable-okok forrása: `docs/sdd/07-epic-06-audio-analysis-2.md:562-660`. A metrika-ID szerződését [ADR 0218](../adr/0218-analysis-metric-id-and-version-governance.md), az abstention és publikáció szerződését [ADR 0216](../adr/0216-analysis-confidence-calibration-and-abstention.md) és [ADR 0219](../adr/0219-analysis-capability-aware-publication.md) rögzíti.

**E06-R29 státusz ([ADR 0249](../adr/0249-analysis-evaluation-dataset-governance.md)):** a kör leszállította a futtatható evaluation harness-t (`evaluation/analysis/`, `tool/audio_analysis_evaluate.dart`), a kilenc SDD-metrikát és a szelet-lebontást, valamint a teszt-oldali regressziós kaput (`test/tooling/analysis_evaluation_regression_test.dart`, baseline: `docs/baseline/epic-06-analysis-evaluation.md`). A `ci_manifest.json` **kizárólag szintetikus** — az ADR 0249 §Döntés 3 szerint a harness/parser/regresszió szerződését méri, nem valódi modellpontosságot, ezért **egyetlen alábbi sort sem zár le**: mindegyik valós eszközös/audio bemenetet vagy címkézett valós corpust igényel, amit ez a box nem tud előállítani. A `confidenceObservations` (28 megfigyelés, a 30/bin és 300/összes minimum alatt) miatt a `CalibrationTable` a mai napig `identity.v1` — ez a helyes, őszinte állapot (lásd EVAL-06). A CI-oldali workflow-lépés bekötése (H-GATEGUARD) egy külön, ember által engedélyezett `GOV-xx` kör feladata marad.

| ID | Állapot | Felelős | Reprodukálható bemenet | Mérendő szám |
|---|---|---|---|---|
| EVAL-01 | PENDING | Device-lab owner | Csend, telefonmikrofon, 10 s | `signal.noise_floor_dbfs.v1` és hamis strum/event count |
| EVAL-02 | PENDING | Audio evaluation owner | Címkézett, metronómra játszott strum-klip | `onset.absolute_error_ms.v1`, precision, recall |
| EVAL-03 | PENDING | Audio evaluation owner | Ismert BPM-ű, címkézett strum-klip | `tempo.absolute_error_bpm.v1` |
| EVAL-04 | PENDING | Chord-evaluation owner | Címkézett C–G–Am–F és további progressziók | `chord.segment_time_accuracy.v1` és chord-label accuracy |
| EVAL-05 | PENDING | ML evaluation owner | Strum direction ground truth | `strum_direction.accuracy.v1`, kalibrációs ECE |
| EVAL-06 | PENDING | ML evaluation owner | Modell- és metrika-verziónkénti holdout corpus | `confidence.expected_calibration_error.v1`, reliability-bin count |
| EVAL-07 | PENDING | Performance owner | Középkategóriás Android eszköz, 30 s WAV | `analysis.wall_clock_ms.v1`, peak RSS byte |
| EVAL-27 | PENDING | Performance owner | Középkategóriás Android eszköz, 30 s WAV, hideg és meleg V2 cache | cache-miss/cache-hit `analysis.wall_clock_ms.v1`, peak RSS byte, modell read+parse számláló és cancel-latencia |
| EVAL-08 | PENDING | Privacy owner | Lab és normál Analyze futás, export/crash/diagnostics audit | `privacy.raw_audio_egress_count.v1` (elvárt 0 alapértelmezésben) |
| EVAL-09 | PENDING | Capability owner | `clipTooShort` fixture | `capability.unavailable_reason.clip_too_short.v1` eseményszám |
| EVAL-10 | PENDING | Capability owner | `insufficientEvents` fixture | `capability.unavailable_reason.insufficient_events.v1` eseményszám |
| EVAL-11 | PENDING | Capability owner | `inputTooNoisy` fixture | `capability.unavailable_reason.input_too_noisy.v1` eseményszám |
| EVAL-12 | PENDING | Capability owner | `inputClipped` fixture | `capability.unavailable_reason.input_clipped.v1` eseményszám |
| EVAL-13 | PENDING | Capability owner | `polyphonicInput` fixture | `capability.unavailable_reason.polyphonic_input.v1` eseményszám |
| EVAL-14 | PENDING | Capability owner | `backingTrackDominant` fixture | `capability.unavailable_reason.backing_track_dominant.v1` eseményszám |
| EVAL-15 | PENDING | Capability owner | Alacsony kalibrált confidence fixture | `capability.unavailable_reason.confidence_too_low.v1` eseményszám |
| EVAL-16 | PENDING | Capability owner | Hiányzó/hibás modell asset | `capability.unavailable_reason.model_unavailable.v1` eseményszám |
| EVAL-17 | PENDING | Capability owner | Nem támogatott fájlformátum | `capability.unavailable_reason.unsupported_format.v1` eseményszám |
| EVAL-18 | PENDING | Capability owner | Nem támogatott sample rate | `capability.unavailable_reason.unsupported_sample_rate.v1` eseményszám |
| EVAL-19 | PENDING | Capability owner | `noReferenceTarget` fixture | `capability.unavailable_reason.no_reference_target.v1` eseményszám |
| EVAL-20 | PENDING | Capability owner | Felhasználói cancel lifecycle | `capability.unavailable_reason.cancelled.v1` eseményszám |
| EVAL-21 | PENDING | Capability owner | Kontrollált pipeline-hiba | `capability.unavailable_reason.internal_failure.v1` eseményszám |

| EVAL-22 | PENDING | Technique-proxy eval owner | Címkézett akkordváltás-klip, ismert váltás-pár ≥4 ismétléssel | `technique.chord_change_gap.v1` korrelációja a felvétel emberi értékelésével (Pearson r, n≥20 klip) |
| EVAL-23 | PENDING | Technique-proxy eval owner | Címkézett klip `complete` chord-evidence-szel (nem `derived`) | `technique.confidence_collapse_duration.v1` és a modell top-k bizonytalanságának korrelációja |
| EVAL-24 | PENDING | Technique-proxy eval owner | Címkézett klip szándékos extra pengetéssel váltás után | `technique.unexpected_extra_onsets.v1` precision/recall a címkézett extra eseményekhez képest |
| EVAL-25 | PENDING | Technique-proxy eval owner | Címkézett klip szándékos kitartás-megszakítással | `technique.sustained_note_dropout.v1` precision/recall a címkézett dropout-eseményekhez képest |
| EVAL-26 | PENDING | Technique-proxy eval owner | Címkézett klip egyenletes vs. egyenetlen pengetéssel | `technique.attack_instability.v1` szórása a két csoport között (effect size, n≥20 klip) |

ADR 0236 §6: egyik technique-proxy sem léphet ki a Lab módból, amíg a fenti öt sor le nem zárul.

Numerikus publikációs küszöb még nincs rögzítve. Minden későbbi küszöbhöz a jegyzőkönyv külön, számított **alatta / pontosan rajta / fölötte** cellát ad. Forrás: `docs/rounds/e06-r01-analyze-v1-baseline-and-adrs.md:292-294`.
