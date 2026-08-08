# Epic 5 — Computer Vision completion report

- **Version:** 1.0 (2026-08-08)
- **Rounds:** E05-R01–R30
- **Status:** implementation evidence complete; all Vision user capabilities remain flag-OFF pending HORIZON device acceptance.

## Completion evidence

The architecture guard now rejects raw `VisionImage`, pixel buffers and related
payload types in Vision persistence or provider state, and rejects cross-feature
internal imports unless the target is a `public.dart` contract. Its allowlist
remains the pre-existing 12 `analyze → live` entries. The mutation tests cover
both new raw-payload rules; the project check reports exactly those 12 legacy
exceptions.

The model-integrity test exercises a good manifest and bad checksum, output
schema, and missing-license mutations. The Vision-off fixture pins all eleven
flags false in every environment and byte-exact Practice audio score, Song
timing, Analyze output, and Tutor context behavior. The evaluation harness has
`NO_DATA` plus 0%/1%/2% false-cue self-test cells; synthetic results do not
promote a user capability.

## Capability status

| Status | Capability |
|---|---|
| Production-supported | No Vision user-facing capability yet: there is no completed multi-device HORIZON evidence and every Vision flag is OFF. Audio-only Practice, Song Trainer, Analyze and Tutor remain supported. |
| Experimental / unavailable | Vision setup, hand tracking, pose tracking, guitar geometry, Practice/Song/Tutor/Analyze integration, fine-fret tracking and Lab capture. They require the rollout ladder and relevant evidence before a separate flag decision. |

## Definition of Done boundary

The software DoD items from SDD §39 are represented by the E05-R01–R30
implementation, tests, privacy/persistence controls, model manifest, capability
guards, integration contracts, performance policy and this rollout runbook.
Physical-device items (camera behavior, orientation, thermal/soak, parity,
latency and false-feedback review) are deliberately **not claimed as measured**.
They are HORIZON acceptance, not synthetic-green evidence.

## Pending real-device evidence

The two manual documents contain 86 `PENDING` occurrences: 81 distinct
device/benchmark rows below plus five explanatory PENDING declarations. Every
row remains PENDING; `device` means the planned device matrix entry, not an
invented result.

### Device matrix rows (41; each PENDING)

1. Permission allow; 2. permission deny; 3. permanently deny; 4. preview quality refresh; 5. low-light cue; 6. route-leave close; 7. background close; 8. explicit foreground restart.
9. Four-point calibration; 10. recalibration; 11. no-calibration `notObservable` fallback.
12. Right-hand confidence/FPS; 13. left-hand confidence/FPS; 14. two-hand FPS; 15. lost-hand transition; 16. occlusion visibility.
17. Shoulder confidence/FPS; 18. torso confidence/FPS; 19. calibrated posture-baseline metric.
20. Audio+camera score parity; 21. CPU degradation with audio preserved; 22. Vision-stop audio continuity; 23. audio–Vision sync offset.
24. Five-minute hand session; 25. fifteen-minute thermal session; 26. raw-frame-free `VisionSessionResult` persistence.
27. Automatic geometry proposal; 28. fine-fret confidence; 29. experimental-flag-off metric behavior.
30. M01 preview-start distribution; 31. M02 five-minute frame stream; 32. M03 image format; 33. M04 rotation metadata; 34. M05 latest-frame/copy audit; 35. M06 release; 36. M07 mirror; 37. M08 orientation; 38. M09 background; 39. M10 timestamps; 40. M11 support/license; 41. M12 dependency conflict.

### Performance benchmark rows (40; each PENDING)

42. Capture FPS; 43. hand FPS; 44. pose FPS; 45. combined FPS; 46. overlay FPS.
47. Hand inference latency; 48. pose inference latency; 49. preprocessing latency; 50. metric-engine latency; 51. end-to-end latency.
52. Dropped-frame count; 53. drop rate; 54. drop cascade; 55. maximum drop gap.
56. Five-minute temperature rise; 57. five-minute thermal throttle; 58. fifteen-minute throttle; 59. ten-minute soak throttle; 60. thirty-minute soak throttle.
61. Audio scoring impact; 62. audio frame-drop; 63. audio latency impact; 64. strum accuracy impact; 65. chord accuracy impact.
66. Vision-OFF idle memory; 67. Vision-ON memory; 68. memory delta; 69. session aggregate size.
70. Overlay degradation; 71. pose degradation; 72. hand-FPS degradation; 73. input-resolution degradation; 74. one-hand degradation; 75. quality-only degradation; 76. Vision-off/audio-on degradation.
77. Hand confidence in good light; 78. hand confidence in low light; 79. hand confidence under occlusion; 80. pose confidence; 81. false-feedback rate.

The remaining five PENDING occurrences are explanatory status declarations in
the two source documents (HORIZON/non-blocking policy and the unmeasured-cell
statements), not additional device tests; they are retained verbatim rather
than converted into fabricated measurements. Thus all 86 source PENDING
occurrences are accounted for without claiming a real-device result.

For exact row wording, measurement units and planned device columns, see
[`vision-device-matrix.md`](../manual-testing/vision-device-matrix.md) and
[`vision-performance-benchmark.md`](../manual-testing/vision-performance-benchmark.md).

## Remaining governance work

The workflow-side Vision model-integrity gate is intentionally absent. Its
addition changes `.github/`/`tool/ci/` and must be a separately authorized
governance round. A later product decision also owns every Vision flag flip and
the HORIZON acceptance of the pending device rows.
