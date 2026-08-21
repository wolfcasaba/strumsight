# Accessibility baseline findings

These are prioritized audit findings for follow-up work. E13-R01 records them
without changing application code.

| Priority | Area | Finding | Evidence / next validation |
| --- | --- | --- |
| P0 | All compact screens | A complete 200% text-scale sweep of the 58-screen inventory is absent. | Add the Chapter 13 accessibility matrix before migration sign-off. |
| P0 | Live and Tuner | These microphone-owning surfaces need lifecycle-safe semantics and recovery checks after layout migration. | Preserve the existing owner boundary while testing screen-reader actions. |
| P1 | Dialog and sheet flows | 24 `showDialog`/`showModalBottomSheet` call sites need an explicit focus-order and dismissibility audit. | Test the listed overlays with keyboard and screen reader. |
| P1 | Compact layout | Existing small-phone guard covers selected screens, not every screen and not every dynamic state. | Expand overflow coverage around long localized copy and error states. |
| P1 | Tuner compact layout | The 390×844 `tuner-compact-portrait.png` baseline visibly shows a render-overflow warning stripe at the upper-right edge. | Reproduce at the same compact viewport and fix in the later Tuner layout migration; do not change production code in this baseline round. |
| P1 | Onboarding compact layout | The 390×844 `onboarding-compact-portrait.png` baseline visibly shows a render-overflow warning stripe at the upper-right edge. | Reproduce at the same compact viewport and fix in the later onboarding layout migration; do not change production code in this baseline round. |
| P1 | Visual status | Confidence, progress, and tuning states must remain distinguishable without color. | Audit status widgets against Chapter 13 semantic-token work. |
| P2 | Feature-local empty states | Empty-state structure is duplicated across multiple features. | Consolidate only after component contracts exist. |

Known overlay sources include Learn, Songs, Library, Progress, Settings, Vision,
Practice, Practice Generator, Song Trainer, AI Tutor and Guitar Calibration.
This document is a backlog, not a statement that an individual flow currently
fails accessibility review.
