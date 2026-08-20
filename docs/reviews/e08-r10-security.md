# E08-R10 — Security review

Brief: `docs/rounds/e08-r10-streak-v2-domain-and-legacy-migration.md`  
Diff: `a2d5239e..f2e368b3`  
Reviewer: független Codex (GPT-5.6 Sol) · Dátum: 2026-08-20  
Verdikt: **APPROVED**

## Összegzés

CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

## Ellenőrzött kockázatok

- A migrátor a `KeyValueStore`-ból csak `readString`/`contains` műveletet
  végez; nincs write, remove, hálózat vagy globális mutable state.
- A namespaced forrás elsőbbséget élvez. Sérült, nem szöveges vagy jövőbeli
  envelope explicit `FormatException`, ezért nem esik vissza csendben egy
  régebbi blobra és nem gyárt hamis üres streaket.
- A felhasználó öt számlálója validált, az ismeretlen JSON-mezők nem kerülnek
  végrehajtási vagy vezérlési útra, egyik forrásbájt sem kerül logba.
- A domain policy nem használ órát, IO-t, Fluttert vagy Riverpodot; a
  `plannedRestDays` másolás ellen védett halmaz.
- A diff nem érint audiot, kamerát, hitelesítést, secretet, hálózatot vagy
  lifecycle-erőforrást. A független secret scan 3052 fájlon 0 leletet adott.

## Bizonyíték

- Implementer scope-audit: 7 engedélyezett path, 0 sértés.
- Teljes reviewer gate: format/analyze/31 célzott+legacy teszt/architecture/
  secrets/l10n zöld.
- Read-only teszt: mindkét source byte-azonos, `writeLog` üres két migráció
  után is.
- Malformed/future namespaced envelope mellett a raw fallback nem rejti el a
  hibát; mindkét állandó teszt explicit kivételt vár és kap.

## Merge-döntés

Security szempontból nyitott blokkoló lelet nincs. Az általános exact-SHA CI-
kapu változatlanul kötelező.
