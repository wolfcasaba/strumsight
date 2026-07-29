# Review-jelentések

Körönként egy fájl: `eXX-rYY-review.md`.

A jelentés a Claude ellenőrzői kimenete — a merge ELŐTT commitolva, BLOCKER /
MAJOR / MINOR / NOTE osztályozással. Sablon és szabály:
[`docs/execution/09-review-report.md`](../execution/09-review-report.md).
Protokoll: [ADR 0055](../adr/0055-agent-role-protocol.md), `AGENTS.md` §15.

A merge-bar nem változott ([ADR 0052](../adr/0052-ci-apk-automerge-session-per-round.md)):
minden gate zöld → auto squash-merge. A jelentés a DoD eddig is meglévő
„nincs unresolved blocking review" pontját teszi ellenőrizhetővé.
