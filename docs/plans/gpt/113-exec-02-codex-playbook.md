---
id: 113
topic: Codex Playbook — kör-végrehajtás lépései: baseline, terv, implementáció, ellenőrzési sorrend, diff audit, megállás
tags: [execution, playbook, workflow]
status: active
depends_on: [101]
canonical_target: docs/execution/02-codex-playbook.md
verify: minden kör e szerint fut
source: chatgpt-plan 2026-07-28 (Codex Execution Pack, 58-file manifest)
---

# Codex Implementation Playbook

## 1. Előkészítés

- Azonosítsd a pontos chaptert és kört.
- Ellenőrizd a Definition of Ready listát.
- Olvasd el az `AGENTS.md`, Chapter 1, kijelölt fejezet és HANDOFF releváns részeit.
- Futtasd a `git status --short` parancsot.
- Ne módosíts ismeretlen working-tree változtatást.

## 2. Repository felderítés

A kör elején készíts rövid belső térképet:

- érintett production fájlok;
- érintett tesztek;
- public contractok;
- perzisztencia/API/schema hatás;
- lifecycle és privacy hatás;
- előző és következő kör függősége.

A kódot olvasd el a módosítás előtt. Ne feltételezz fájlnevet vagy implementációt a régi dokumentációból.

## 3. Baseline

Futtasd a legkisebb releváns baseline ellenőrzést. Ha a baseline piros:

- rögzítsd a hibát;
- állapítsd meg, hogy a körhöz tartozik-e;
- ne állítsd saját regressziónak vagy saját sikernek;
- scope-on kívüli javítást ne keverj a körbe külön döntés nélkül.

## 4. Terv

A terv legfeljebb 5–8 végrehajtási lépés. Tartalmazza:

- contract vagy teszt;
- implementáció;
- migráció/adapter;
- UI/integráció, ha része;
- ellenőrzések;
- dokumentáció.

## 5. Implementáció

- Hibajavításnál először reprodukáló teszt.
- Új domain contractnál először invariáns és serializációs teszt.
- Migrációnál először régi adat fixture és rollback/retry viselkedés.
- API-nál először schema/authorization/idempotency teszt.
- Audio/ML-nél először parity és lifecycle gate.

## 6. Review a végrehajtás közben

Minden jelentős rész után ellenőrizd:

- nőtt-e a scope;
- keletkezett-e cross-feature import;
- maradt-e eldobott exception;
- kerülhet-e secret vagy PII logba;
- felszabadul-e minden erőforrás;
- determinisztikus-e a teszt;
- visszaállítható-e a migráció.

## 7. Ellenőrzési sorrend

1. formázás;
2. célzott unit teszt;
3. érintett feature teszt;
4. analyzer;
5. teljes Flutter teszt;
6. property gate, ha releváns;
7. backend/ML gate;
8. build vagy device gate, ha előírt.

A parancsokat külön futtasd.

## 8. Diff audit

A végén:

```bash
git status --short
git diff --stat
git diff --check
```

Ellenőrizd a teljes diffet:

- nincs secret;
- nincs véletlen bináris vagy dataset;
- nincs unrelated formatting churn;
- nincs kikapcsolt teszt;
- nincs debug signing vagy production insecure default regresszió.

## 9. Traceability és HANDOFF

- Jelöld a kör státuszát a traceability matrixban.
- Add meg a PR/issue hivatkozást, amikor létezik.
- Frissítsd a HANDOFF-ot tényszerű teszteredménnyel.
- Ne másold bele a teljes történeti naplót; használj archív linket.

## 10. Megállás

A kör után állj meg. Ne kezdj „még egy gyors” következő feladatot.

## 11. Ajánlott körméret

Egy kör ideális esetben:

- 1 public contract vagy 1 vertikális slice;
- legfeljebb néhány száz sor nettó production változás;
- önállóan tesztelhető;
- egy reviewer számára egy ülésben áttekinthető.

Ha ennél nagyobb, bontsd alfeladatokra úgy, hogy az SDD acceptance criteria ne vesszen el.

## 12. Hibakezelés

Ha egy parancs nem elérhető vagy környezeti okból nem fut:

- ne hamisíts eredményt;
- rögzítsd a pontos parancsot és hibát;
- futtasd a lehetséges kisebb ellenőrzést;
- jelöld a hiányzó gate-et blokkolónak, ha release-kritikus.

---
