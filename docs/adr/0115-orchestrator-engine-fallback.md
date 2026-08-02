# ADR 0115 — Orchestrátor-fallback: a Claude-kvóta kimerülése nem szakíthatja meg a láncot

**Státusz:** elfogadva (2026-08-02, user-döntés: *„a te kvótád 94 százalék …
állítsd be fallbackre a GPT Terra modellt, hogy ha leállsz a review-val, akkor
ő vegye át a munkádat"* / *„a lényeg, hogy a pipeline ne szakadjon meg"*).
Épít: [ADR 0087](0087-autonomous-round-pipeline.md) (kör-pipeline),
[ADR 0112](0112-self-healing-pipeline.md) (önjavítás),
[ADR 0088](0088-minimax-first-development-router.md) (implementer-router — **nem
változik**), [ADR 0069](0069-two-engine-implementer-pool.md).

## Kontextus

A lánc két szerepet oszt ki: az **implementer** (MiniMax M3 → szükség esetén
Terra, a router dolga) és az **orchestrátor/reviewer** (eddig kizárólag Claude).
Az ADR 0112 megszüntette azt, hogy egy hiba megállítsa a fejlesztést — egy
kivétellel: **ha maga az orchestrátor-motor esik ki**, nincs, aki javítson. Az
önjavító kör is Claude-session, tehát kvótakimerülésnél az is elhal, és három
néma kísérlet után a lánc emberre vár.

A user Claude-kerete 2026-08-02-án **94%-on** állt. A kockázat tehát nem
elméleti: a következő körök közben fogy el.

## Döntés

### 1. Az orchestrátori munkadarabnak két motorja van, sorrendben

A `tools/round-pipeline.sh` minden orchestrátori sessiont (kör-levezénylés ÉS
önjavító kör) a `run_orchestrator_session` függvényen át indít:

1. **Claude** (`PIPELINE_MODEL`, alap: `claude-sonnet-5`) — az elsődleges;
2. **Terra** (`codex exec`, `CODEX_HOME=~/.codex-terra`, ahol a default modell
   `gpt-5.6-terra`) — a fallback, **ugyanazzal a prompt-fájllal**.

A fallback nem külön munkafolyamat: a Terra ugyanazt a kör- vagy önjavító
promptot kapja, elé fűzve a
`docs/execution/pipeline-codex-orchestrator-preamble.md` motor-előszóval.

### 2. A kiváltó ok KIZÁRÓLAG a kvóta — minden más hiba marad halt

A váltás akkor és csak akkor történik, ha a Claude-session **jelzés nélkül halt
meg**, ÉS a session-naplója illeszkedik a mért kvóta-mintákra (`usage limit
reached`, `Claude usage limit`, `quota exceeded`, `limit will reset`, …).

**Miért ilyen szűk:** ha minden néma halálra motort váltanánk, egy valódi
programhibát kétszer fizetnénk meg — egyszer Claude-, egyszer Terra-kvótából —,
és a hibás kört a második motor is elrontaná. A minták szándékosan angolok és
CLI-specifikusak: a magyar „kvóta" szó a promptokban is szerepel, arra
illeszteni hamis pozitív lenne.

### 3. A zárlat 5 órára szól, hogy ne minden kör fizesse ki a próbát

Kvóta-találatkor a driver `.pipeline/claude-blocked-until`-ba írja a lejáratot
(alap: **+5 óra**, `PIPELINE_CLAUDE_BLOCK_SECONDS`). Amíg ez él, a további
körök **egyből** a Terrával indulnak — nem égetnek el egy-egy sikertelen
Claude-indítást körönként. A lejárat után a lánc magától visszatér Claude-ra
(a fájl törlődik); azonnali visszatérés: `tools/pipeline-status.sh --unblock-claude`.

### 4. Amit a fallback NEM lazít

A Terra-orchestrátorra **ugyanaz a zöld kapu** (ADR 0052/0086), ugyanaz a
független review-kötelezettség, ugyanaz az engedélyezett-fájllista, és ugyanaz
a kötelező kör-jelzés vonatkozik. A mérce-őrszem (ADR 0112 §3) is változatlanul
fut a Terra önjavító körei fölött is.

Az **implementer**-routing nem változik: a kör motorja továbbra is a sor
`engine` oszlopa és az ADR 0088 routere dönti el. Ez az ADR kizárólag arról szól,
**ki vezényel és ki review-z**.

### 5. Kikapcsolható

`PIPELINE_FALLBACK_ENGINE=none` → a régi viselkedés (Claude kiesése = halt).

## Következmények

- A lánc a Claude-kvóta kimerülésétől **nem áll meg**: a következő firing a
  Terrával viszi ugyanazt a kört, és az önjavító kört is.
- A Terra-orchestrátor a Claude-harness korlátaitól is mentes: **nincs 600 s-os
  Bash-plafonja**, ezért a router egyetlen hosszú blokkoló hívása (az E03-R05
  H6 halt oka, L42) nála nem korlát — a fallback nemcsak pótol, hanem ezen az
  osztályon jobb is.
- Költség: a Terra-hívások a Codex-keretet fogyasztják. A napi automatikus
  Terra-korlát (`max_automatic_terra_calls_per_utc_day`) az **implementer**
  útra vonatkozik; az orchestrátori fallback ettől külön él, mert enélkül a
  lánc egyáltalán nem haladna.
- A telefonos értesítés motorváltásnál `high` prioritású (`🔁 motorváltás`), így
  látszik, hogy melyik motor viszi a kört.
