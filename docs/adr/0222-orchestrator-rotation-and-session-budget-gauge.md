# ADR 0222 — Orchestrátor-rotáció: a Terra ugyanannyit vezényel, mint a Claude

**Státusz:** elfogadva (2026-08-11, user-döntés: *„szeretném tudni miért nem
bírja a Claude 5 órás session korlátot — úgy állítsuk be a rendszert, hogy a
Terrát is használjuk ugyanannyira, mint a Claude-ot"*, és a szerepcserére:
*„sonnet-impl (szerep-csere)"*).
Épít: [ADR 0115](0115-orchestrator-engine-fallback.md) (orchestrátor-fallback —
**megmarad, alá kerül védőhálónak**), [ADR 0138](0138-factory-hardening-scope-guard-and-independence.md)
(reviewer-függetlenség), [ADR 0140](0140-switchable-implementer-engine-profiles.md)
(motor-nyilvántartás), [ADR 0171](0171-pipeline-throughput-program.md) (azonnali
lánc-folytatás), [ADR 0112](0112-self-healing-pipeline.md) (önjavítás).

## Kontextus — MIÉRT fogy el a Claude 5 órás kerete

Nem baleset, hanem a kiosztás következménye. Három mért tény:

**1. 100%-os kihasználtság.** A lánc minden körben a Claude-ot ültette az
orchestrátor+reviewer székbe (a Terra csak implementált). Mérve 2026-08-11-én:
hat kör 08:20→17:44 között, körönként ~85 perc, `--effort max`, és az ADR 0171
`azonnali lánc-folytatás` miatt szünet nélkül. Egy 5 órás ablakba **~3,5 kör**
fér — a negyedik nekimegy a falnak. A Claude kerete tehát nem „gyenge": egyedül
ő kapott munkát.

**2. A védőháló vak volt.** A `CLAUDE_LIMIT_PATTERN` egyetlen mintája sem
illeszkedett a CLI tényleges bannerére:

```
You've used 97% of your session limit · resets 3:40pm (UTC) · /upgrade to k…
```

A `.pipeline/session-E06-R05-20260811T134634.log`-ban **11 ilyen banner** van,
90→97%-ig számolva, és a driver egyiket sem látta. Ezért az ADR 0115 átadása nem
lépett: a sessiont a 20 perces elakadás-őr lőtte le a CI-dispatch+merge közben,
a kör H-NOSIGNAL-t kapott, két önjavító kör és egy leftover PR (#215) takarítása
kellett a feloldásához (docs/LESSONS.md L213).

**3. A második detektor halott kód.** A `claude_stats_cache` alapértelmezett
útja `~/.claude/stats-cache.json` — **ez a fájl nem létezik ezen a boxon**, tehát
a „ne is induljon el" ág soha nem futott le.

Emellé egy latens rés: az ADR 0138 függetlenség-védelme csak a `codex`
motornevet nézte, az ADR 0140 óta élő `.pipeline/engine-override=terra` mellett
viszont a motor neve `terra` — így kvótazárlat alatt a Terra a **saját diffjét**
review-zta volna.

## Döntés

### 1. Az orchestrátori széket rotáljuk, nem csak vészhelyzetben adjuk át

`tools/round-pipeline.sh` minden kör indításakor kiszámolja, melyik motor
vezényel: `next_orchestrator()` → `claude` | `terra`. Alapértelmezés
`PIPELINE_ORCH_ROTATION=alternate` — a körök fele a Terráé. Az állapot egyetlen
gitignore-olt fájl (`.pipeline/orchestrator-last`), a rotáció bármikor
kikötözhető egy motorra (`claude` | `terra`).

A rotáció **proaktív**: a cél, hogy egyik motor kerete se merüljön ki. Az
ADR 0115 fallback alatta marad, változatlanul.

### 2. Terra-vezényelt körön a szerepek cserélnek, nem gyengül a mezőny

A Terra nem review-zheti a saját diffjét (ADR 0138), ezért Terra-vezényelt körön
az implementer `PIPELINE_ORCH_SWAP_ENGINE`, alapból **`sonnet-impl`** (natív
Claude Sonnet 5 az előfizetésen). A két legjobb motor marad a körben, csak
széket cserélnek:

| kör | orchestrátor + reviewer | implementer |
|-----|-------------------------|-------------|
| páratlan | Claude | Terra |
| páros | Terra | Claude (`sonnet-impl`) |

A függetlenség-feltétel egyben javul: a trigger már a `codex` **és** a `terra`
motornév (ugyanaz a `gpt-5.6-terra` modell).

**Kimerült Claude-kereten a szerepcsere nem megoldás** — a csere-motor sem ehet
ugyanabból a keretből. Ilyenkor a `minimax` (saját kulcs, külső endpoint) lép be
implementernek; ha az sincs, marad a `H-INDEP` halt.

### 3. Fogyásmérő: a keret állását mérjük, nem a becsapódást várjuk

Két külön minta, mert két külön döntés:

* `CLAUDE_LIMIT_PATTERN` (kimerülés) — kiegészítve a mai CLI-alakokkal
  (`you've hit/reached your usage|session limit`, `session limit reached`,
  `used 100% of your session limit`, `N-hour limit reached`). Ez a futó
  sessiont állítja le és azonnal átad.
* `CLAUDE_SESSION_PCT_PATTERN` (fogyásmérő) — a banner százaléka. Ez **soha nem
  szakít meg futó munkát**; a session végén mérünk (`record_claude_usage`), és a
  következő kör indítását tiltja, ha a keret a küszöb fölött van
  (`PIPELINE_CLAUDE_SESSION_PCT_MAX`, alap **85%**). Indoklás: egy kör ~85 perc
  orchestrátor-munka, ezt a maradék néhány százalékon elindítani garantált
  H-NOSIGNAL.

A zárlat lejárata a bannerből olvasott reset-időhöz igazodik
(`resets 3:40pm (UTC)`), nem vak 5 órás felülbecslés — a Claude a reset
másodpercében újra sorra kerül. Ismeretlen alakra marad a régi, biztonságos
felülbecslés.

## Következmények

* A Claude orchestrátori terhelése ~50%-kal csökken, a keret nem merül ki, a
  H-NOSIGNAL-osztály megszűnik mint rendszeres kör-vesztés.
* A Terra terhelése nő — a saját kvótája is korlát (mérve E05-R15: kimerült).
  A rotáció mindkettőt kíméli, de ha a Terra esik ki, a lánc a Claude-nál marad
  (a zárlatok felülírják a rotációt, mindkét irányban).
* A körök felén a Claude implementál. A `sonnet-impl` a `~/.claude` config
  dirben él, tehát UGYANAZT az előfizetést fogyasztja, mint az orchestrátor —
  ez szándékos: a keret így egyenletesen oszlik el, nem egyetlen szerepre.
* Egy Terra-vezényelt kör review-ja `codex exec`, nincs Claude-skill-rendszere;
  a prompt-preambulum (ADR 0115) ezt már kezeli.

## Mérce

`tools/tests/test_orchestrator_rotation.py` (14 eset) — a fogyásmérő az ÉLES,
ANSI-vezérlős banner-alakon, a rotáció mindkét irányban, a preemption
lejáratostul, és a függetlenség a `codex`/`terra` névre egyaránt. A régi
`tools/tests/test_reviewer_independence.py` és
`tools/tests/test_round_pipeline_fallback.py` változatlanul zöld.
