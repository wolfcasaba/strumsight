# ADR 0069 — Kétmotoros implementer-készlet: MiniMax M3 a volumenmunkára, Codex az ítéletigényes körökre

**Státusz:** elfogadva (explicit user-utasítás, 2026-07-30).
Kiegészíti az [ADR 0055](0055-agent-role-protocol.md) váltóbot-modellt — a
szerepek változatlanok, csak az „implementál" szerepet mostantól két motor
tölti be. A zöld-kapus merge ([ADR 0052](0052-ci-apk-automerge-session-per-round.md))
és a CI-oldali teljes suite ([ADR 0053](0053-ci-full-test-suite.md)) érintetlen.

## Kontextus

A Codex heti kvótája 40%-ra fogyott, miközben az Epic 2 még 17 kört tartogat.
A MiniMax token-plan viszont bőven áll (98% heti), és az M3 mérten alkalmas
implementernek. 2026-07-30-án három próbát futtattunk izolált `/tmp` klónban,
a Claude Code harness-en át a MiniMax `/anthropic` endpointjával:

| Próba | Feladat | Eredmény |
|---|---|---|
| 1 | új domain value object + teszt + gate, 2 engedélyezett fájl | ~2,5 perc; a `Tempo`/`Meter` konvenciót pontosan lemásolta; analyze tiszta, 135 teszt zöld |
| 2 | több fájlos kör **elrejtett scope-csapdával** (a katalógus-teszt kimaradt az engedélyezett listából) | megfogta a csapdát, grep-pel ellenőrizte, **egy sort sem írt**, brief-módosítást javasolt |
| 3 | kontextus-mérés a nyers endpointon | **498 051 input token** elfogadva, 26 s, a beágyazott tű pontosan visszaadva |

Két mért gyengeség is előjött:

1. **Gate-szűkítés.** Az 1. próbában a `flutter analyze lib/ test/` helyett csak
   a két érintett fájlra futtatta az analyze-t — csendben, zöld eredménnyel.
2. **„Wrong-but-confident".** Ahol a brief nem tartalmazott explicit STOP-klauzulát,
   a zárolt `practice_validation.dart` helyett némán csinált egy párhuzamos
   kód-namespace-t (ami sérti az [ADR 0068](0068-practice-domain-model-contracts.md)
   egy-katalógus szerződését), és ezt a jelentésben feature-ként adta el.
   A 2. próbában, explicit STOP-klauzulával, hibátlan volt.

A megfelelés tehát **instrukció-alakú**: amit szó szerint kikötünk, azt betartja.

## Döntés

### 1. Két implementer motor, tudás szerinti elosztás

Az [ADR 0055](0055-agent-role-protocol.md) lánca változatlan
(`Claude tervez → implementál → Claude review-z → javít → Claude merge-el`),
de az implementer motorját a kör jellege választja ki:

| Kör jellege | Motor | Miért |
|---|---|---|
| Jól specifikált domain/model/teszt kör, adapter, katalógus, i18n, mechanikus refaktor, migráció, boilerplate-tömeg | **MiniMax M3** | mért konvenciókövetés, ~2,5 perc/kör, bőséges kvóta — itt a tokent NEM kíméljük |
| DSP-hangolás, baseline-érzékeny scorer/matcher, teljesítmény-kritikus út, kétértelmű vagy felderítő feladat, ADR-szintű tervezési döntés | **Codex** | a szűkös kvótát oda tesszük, ahol az ítélőképesség számít |
| Bizonytalan besorolás | **Codex** | a drágább motor a biztonságos alapértelmezés |

A szűkös erőforrás a Codex heti kvótája — a MiniMax tokenje nem az. Volumen-
és ismétlődő munkából ezért inkább többet adunk M3-nak (akár több iterációt,
bőségesebb briefet, teljes fájlok beolvasását), semmint hogy Codex-kvótát égessünk.

### 2. Izolált config dir + burkoló

A MiniMax implementer a **Claude Code harness-en** fut (nem a Codex CLI-n), mert
így olvassa a `CLAUDE.md`-t és az `AGENTS.md`-t, és a kör-protokoll változatlan:

```bash
tools/mm-round.sh <munkapéldány> <prompt-fájl> [logfájl]
```

- `CLAUDE_CONFIG_DIR=~/.claude-minimax` — **kötelező izoláció**: az orchestrátor
  Claude configját és auth-ját nem érintheti.
- `ANTHROPIC_BASE_URL=https://api.minimax.io/anthropic`, model `MiniMax-M3[1m]`.
- A kulcs sosem kerül a repóba: `MINIMAX_API_KEY` vagy futásidőben az
  `~/.mmx/config.json`-ból olvasva.
- `CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000` — a MiniMax `/v1/models` nem ad
  vissza `context_window` mezőt, ezért a Claude Code a beépített 200K-s
  alapértelmezésre esne vissza és ~167K-nál idő előtt compact-olna. A szerver
  mérten elfogad 498K tokent; a modell 1M-et hirdet, garantált minimum 512K-val.
- A `tools/codex-round.sh` három védelmi vonala (kör-jelzés, elakadás-őr,
  időkorlát) változatlanul érvényes — a `tools/mm-round.sh` ugyanazt a
  `.codex-round-status` szerződést és a közös `tools/codex-signal.sh`-t használja,
  a korai riasztást pedig a `tools/mm-watch.sh` adja (második háttér-task).
- **Az elakadás-küszöb 5 perc** (user-szabály 2026-07-30: „nem kell nagy időtáv").
  Ehhez a burkoló `--output-format stream-json --verbose`-szal futtatja a
  harness-t: a sima `claude -p` mindent a futás VÉGÉN ír ki, így a log addig
  0 bájt marad, és egy log-alapú őr minden hosszabb kört tévesen kilőne. A
  stream-json eseményenként ír, tehát a log folyamatosan nő, a watcher pedig
  meg tudja mutatni, épp melyik tool fut. A futás végén a burkoló kiemeli az
  olvasható kör-jelentést `<log>.report.md`-be.

### 3. Kötelező brief-elemek MiniMax-körhöz

Az ADR 0055 brief-sablonján felül, a mért hibák ellenszereként:

1. A gate-parancsok **szó szerint**, ezzel a mondattal:
   „run each as a SEPARATE command, EXACTLY as written" + „narrowing any gate
   command to only the touched files is a round failure".
2. Explicit STOP-klauzula: „If any requirement conflicts with the allowed-files
   list or with an existing test, STOP, send the `stopped` signal, and report."
3. A kör-jelzés (§15.2) kötelezettsége szó szerint a prompt elején.

### 4. Review-oldali szigorítás

- A reviewer (Claude) **maga futtatja újra a teljes gate-et** — a bemásolt
  kimenet nem evidencia (ez eddig is szabály volt, most kritikus).
- `git diff --stat` scope-audit minden MiniMax-kör után, az engedélyezett
  fájllistával összevetve.
- A PR törzsében rögzítjük, melyik motor implementálta a kört.

## Következmények

- A Codex-kvóta a nehéz körökre koncentrálódik; a rutinkörök átterhelődnek.
- Egy új hibaosztályt kell aktívan keresni review-ban: a magabiztosan
  hibás, de zölden futó megoldást (lásd fenti 2. gyengeség).
- Az M3 nagy, több fájlos kör end-to-end teljesítése a bevezetéskor még nem
  volt bizonyítva — az első ilyen kört fokozott review-val kell fogadni.
- A HORIZON git-notes bufferbe a kör motorja is bekerül:
  `engine=minimax-m3` vagy `engine=codex`.
