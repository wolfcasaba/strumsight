# E99-R20 — Biztonsági review

Reviewer: Codex Sol · Dátum: 2026-08-20 · Kockázat: high

## Verdikt

**CHANGES REQUIRED.** CRITICAL: 0 · BLOCKER: 1 · MAJOR: 1.

Az argumentumok shell-szinten idézettek, a PR-szám és kör formátuma validált,
a konfliktus-allowlist ismeretlen útvonalon fail-closed. A két nyitott lelet
azonban a merge hitelességi határát sérti:

- **S1 / BLOCKER:** rebase után új HEAD keletkezik, de a script új exact-SHA
  CI nélkül eljut a merge-hívásig (`e99-r20-review.md` F1).
- **S2 / MAJOR:** a mért branch és a merge-elt PR identitása nincs
  kriptografikus/mezőszintű egyezéssel ellenőrizve (`e99-r20-review.md` F2).

Mindkettőt eldobható hermetikus próbateszt reprodukálta. A merge a két lelet
lezárásáig tilos; a szükséges javítás a brief engedélyezett `tools/`, teszt,
prompt és saját brief útvonalain belül marad.
