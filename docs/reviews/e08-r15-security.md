# E08-R15 — Security/privacy review

Brief: `docs/rounds/e08-r15-achievement-ui-and-evidence.md`  
Reviewer: Codex / `gpt-5.6-sol` · Dátum: 2026-08-21  
Verdikt: **CHANGES REQUIRED**

## Összegzés

CRITICAL: 0 · BLOCKER: 0 · MAJOR (security/privacy): 1 · NOTE: 1

A diff nem vezet be storage-, hálózati-, plugin- vagy Analyze-importot. A
locked hidden content screenen és detailben is fail-closed; a reviewer
`Opacity(0)` mutációját az A2 cella pirosra vitte. A zárt evidence contract
nem hordoz session/event ID-t, timeline-t, waveformot, audio/video payloadot
vagy szabad user-szöveget. A numerikus trust boundary viszont validálatlan.

## Megállapítások

### S1 — MAJOR — Nem véges/érvénytelen aggregate megjeleníthető evidence-ként

- **Fájl:** `lib/features/gamification/presentation/screens/achievement_detail_screen.dart:13-23`
- **Kockázat:** hibás caller vagy sérült projekció NaN/infinity/negatív értéket
  hiteles „mért haladás” szöveggé alakíthat. Ez adat-integritási és
  truthfulness trust-boundary rés.
- **Bizonyíték:** reviewer invalid-mátrix `(NaN,5)`, `(∞,5)`, `(-1,5)`,
  `(1,0)`; az első objektumot adott `ArgumentError` helyett.
- **Kötelező javítás:** runtime finite/nonnegative current + finite/positive
  target validation és tartós regressziós cellák.
- **Státusz:** OPEN; a correctness report F4-gyel azonos javítás zárja.

### N1 — NOTE — A hidden/privacy negatív őr érzékeny

Locked hidden állapotban nincs valódi title/description/progress/category/
evidence a widget- vagy semantics-fában. Egy konkrét cím `Opacity(0)` mögötti
visszacsempészése az A2 cellát pirosra vitte, restore után 1/1 zöld.

## Döntés

Security/privacy merge-bar jelenleg piros S1 miatt. A javítás után külön
re-review szükséges; CRITICAL/BLOCKER nincs.
