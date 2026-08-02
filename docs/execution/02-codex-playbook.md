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

## 13. MiniMax-first headless router (`engine=auto`)

Normatív döntés: [ADR 0088](../adr/0088-minimax-first-development-router.md).
Az orchestrátor a branch/worktree és pre-flight commit után a router adaptert
**előtérben** futtatja:

```bash
PIPELINE_ROUTER_STATUS_FILE=<pipeline-state>/router-status \
  <worktree>/tools/ai-router-round.sh run \
  <worktree> docs/rounds/e03-rNN-<slug>.md \
  <worktree>/.ai/runs/E03-RNN/router-result.json
```

Review findings folytatása — ugyanaz a task és külső state, nincs budget reset:

```bash
<worktree>/tools/ai-router-round.sh resume \
  <worktree> docs/rounds/e03-rNN-<slug>.md \
  <worktree>/.ai/runs/E03-RNN/router-result.json \
  <worktree>/docs/reviews/e03-rNN-review.md
```

Állapot:

- `READY_FOR_REVIEW` → csak progress; scope-audit után az orchestrátor commitol,
  majd független review + CI következik;
- `STOPPED` → nincs további automatikus modellhívás;
- `DEFERRED` → szolgáltatás/provider-kvóta vagy pozitív, ideiglenes napi
  vészlimit után ugyanaz a task resume-olható;
- `BLOCKED` / `INTERNAL_ERROR` → előfeltétel vagy router-integritás javítandó.

Kézi diagnosztika:

```bash
python3 tools/model-router.py status --task-id E03-RNN --json
python3 tools/model-router.py terra-status
tools/pipeline-status.sh
~/.local/libexec/strumsight-ai/minimax-quota --check-only
```

`terra-status` esetén `daily_limit=0` és `unlimited=true` a normál,
korlátlan napi policy; ilyenkor `exhausted=false`, és nincs következő UTC-reset.
A taskonkénti egy Terra-hívásos korlát ettől függetlenül változatlan.

Gépi telepítés és read-only smoke:

```bash
python3 tools/install-ai-router.py \
  --home /home/ubuntu --source-config /home/ubuntu/.mmx/config.json
python3 tools/model-router.py smoke --profile m3 --worktree "$PWD"
python3 tools/model-router.py smoke --profile terra --worktree "$PWD"
```

A smoke nem módosíthatja a repót. A globális Codex default és a ChatGPT login
nem változhat. A source credential csak user-owned, nem symlink, `0600` fájl
lehet; kulcs vagy nyers quota-body nem kerülhet logba vagy TOML-ba. Az installer
az ugyanilyen, korábbi OpenSpace MCP literal kulcsot privát runtime-wrapperre
migrálja; ezt idempotencia- és exact-secret scan ellenőrzi.

Az Epic 3 queue-sorok `prepared` állapotban vannak. Ez szándékos: csak az Epic
2 lezárása és emberi döntés után állítható az első sor `pending`-re; R22 kézi
zárókör.

---
