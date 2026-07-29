# Review-jelentés — sablon és szabály

A **review-jelentés** a Claude ellenőrzői kimenete
([ADR 0055](../adr/0055-agent-role-protocol.md), `AGENTS.md` §15).

**Hely:** `docs/reviews/eXX-rYY-review.md`
**Commitolva a merge ELŐTT.** A DoD „nincs unresolved blocking review" pontja
ezzel válik ellenőrizhetővé (`04-definition-of-done.md`).

**Review közben nem írunk production kódot.** A kimenet jelentés, nem csendes
átírás — különben az implementáló és az ellenőrző oldal újra összecsúszik, és
elveszik a független szem.

## Súlyossági osztályok

| Osztály | Jelentés | Merge-hatás |
|---|---|---|
| **BLOCKER** | Hibás viselkedés, adatvesztés, security/privacy sértés, megszegett termékhatár (`AGENTS.md` §5), scope-on kívüli változás, hamis „zöld" állítás | Merge tilos, amíg nyitva van |
| **MAJOR** | Architektúra- vagy contract-sértés, hiányzó teszt a viselkedésváltozásra, elnyelt hiba, nem felszabaduló erőforrás | Merge tilos, amíg nyitva van |
| **MINOR** | Karbantarthatóság, elnevezés, duplikáció, hiányos dokumentáció | Javítható a körben, ha nem növeli érdemben a diffet; egyébként follow-up |
| **NOTE** | Megfigyelés, későbbi lehetőség | Nem blokkol |

## Amit a review kötelezően ellenőriz

1. **Acceptance criteria** — tételesen, kritériumonként bizonyítékkal.
2. **Scope** — `git diff --stat` a brief engedélyezett-fájllistája ellen.
   Bármi a listán kívül automatikusan legalább MAJOR.
3. **Architektúra** (`AGENTS.md` §6): domain-függetlenség, core→feature import
   tilalom, `public.dart` contract, UI nem beszél pluginnal.
4. **Termékhatárok** (§5): nyers audio, rejtett hálózati kérés, mic-ownership,
   confidence-megjelenítés, secret a logban.
5. **Hibakezelés és lifecycle** (§7, §10): üres catch, cancellation, minden
   útvonalon felszabaduló `StreamSubscription`/isolate/mic/timer/wakelock.
6. **Tesztek** — valóban a viselkedést ellenőrzik-e, determinisztikusak-e, nem
   lett-e teszt kikapcsolva vagy küszöb lazítva a zöldért.
7. **Gate-bizonyíték** — a jelentett parancskimenetek tényleg futottak-e; a CI-run
   linkje létezik-e és zöld-e.
8. **Rejtett regresszió** — perzisztencia tényleg megtörtént-e (nem csak
   optimista UI), migráció visszaállítható-e.

Ne adj általános dicséretet. Ne fogadd el a kódot pusztán azért, mert a tesztek
zöldek.

---

## Sablon

```markdown
# EXX-RYY — Review

Brief: docs/rounds/eXX-rYY-<slug>.md
Diff: `git diff main...codex/eXX-rYY-<slug>`
Reviewer: Claude · Dátum: YYYY-MM-DD
Verdikt: APPROVED | CHANGES REQUIRED

## Összegzés

BLOCKER: n · MAJOR: n · MINOR: n · NOTE: n

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | ... | ✅ / ❌ | fájl:sor, teszt neve, parancskimenet |

## Scope-audit

Engedélyezett fájlokon kívüli változás: nincs / <lista>

## Megállapítások

### F1 — BLOCKER | MAJOR | MINOR | NOTE — <rövid cím>

- **Fájl:** `path/to/file.dart:123`
- **Probléma:** mi a konkrét hiba
- **Hatás:** mi történik a felhasználóval / az adattal
- **Kötelező javítás:** végrehajtható utasítás
- **Ellenőrzés:** milyen teszt/parancs igazolja a javítást
- **Státusz:** OPEN | FIXED (`<commit>`) | WONTFIX (`<indok>`)

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | ... | ✅ / ❌ |
| analyze | ... | ✅ / ❌ |
| célzott tesztek | ... | ✅ / ❌ |
| CI (teljes suite + property + APK) | run link | ✅ / ❌ |

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
```

---
