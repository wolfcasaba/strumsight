# Kör-briefek

Körönként egy fájl: `eXX-rYY-<slug>.md`.

A brief a Claude tervezői kimenete és a Codex implementációs szerződése — a
kör indítása ELŐTT commitolva. Sablon és szabály:
[`docs/execution/08-round-brief.md`](../execution/08-round-brief.md).
Protokoll: [ADR 0055](../adr/0055-agent-role-protocol.md), `AGENTS.md` §15.

Az E01-R01…R09 körök még a brief bevezetése előtt futottak; a történetük a
`HANDOFF.md`-ben és a PR-okban van.

## Státuszok

`PREPARED` → `PLANNING` → `IN PROGRESS` → `IN REVIEW` → `DONE`.

A **`PREPARED`** egy előre, batchben megírt brief: a „Jelenlegi állapot" a
megírás pillanatának `main`-jét tükrözi, ezért minden ilyen brief fejlécében ott
a ⚠ **pre-flight** blokk — indítás előtt az orchestrátor újraolvassa az érintett
kódot, javítja a driftet, megírja az előre kiosztott számú ADR-t, majd
`PLANNING`-re állítja és a **kör-branchre** commitolja (ADR 0055: a brief a kör
indítása ELŐTT commitolva).

**Előre megírt batch (2026-07-31, `main` @ `ce8fbce`):** E02-R10…R20, ADR
0076–0085 kiosztva; az első szabad ADR-szám utána **0086**. A körök közti
függőségek és az összefoglaló tábla: `HANDOFF.md` §6.
