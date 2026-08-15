# E99-R13 — Security review

Brief: `docs/rounds/e99-r13-gov-30c-5-runner-audio-path-and-wiring.md`
Reviewer: Codex (gpt-5.6-terra) · Dátum: 2026-08-15
Verdikt: CHANGES REQUIRED (a funkcionális review F1 MAJOR megállapításával együtt)

## Ellenőrzés

- A `AnalysisRunRequest` a PCM-et külön, csak memóriabeli hordozóban tartja.
- A dokumentumkódoló nem kap PCM-mezőt. Egy eldobható negatív próba a kódolt JSON-hoz fűzött `0.918273645` markerrel az A4 tesztet pirosra váltotta; a próba visszaállítása után A4 zöld.
- A diff nem érint flaget, hálózati kódot, perzisztencia-sémát vagy logolást; nyers audio kiírására utaló új kód nincs.

## Nyitott kockázat

Az alkalmazás teljes V2 DSP-lánca jelenleg a UI-isolate-ban fut (`v2_analysis_runner.dart:16-36`). Ez nem közvetlen PCM-kiszivárgás, de megsérti az ADR 0254 izolátumos feldolgozási következményét, és a nagy audio-bemenet UI-lifecycle/erőforrás-kockázatát nyitva hagyja. A javítás a fő review F1 szerint kötelező; CRITICAL/BLOCKER security lelet nincs.
