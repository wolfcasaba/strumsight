# ADR 0139 — Visszakapcsolható implementer-motor profilok

**Státusz:** elfogadva (2026-08-05, user-döntés: „hozz létre külön konfigurációt
mindháromnak … később vissza akarom kapcsolni, hogyha visszajönnek a limitek").

Kiegészíti az [ADR 0069](0069-two-engine-implementer-pool.md) (két implementer
motor), [ADR 0088](0088-minimax-first-development-router.md) (MiniMax-first
router), [ADR 0115](0115-orchestrator-engine-fallback.md) (Terra
orchestrátor-fallback) és [ADR 0138](0138-factory-hardening-scope-guard-and-independence.md)
(reviewer-függetlenség) döntéseit.

## Kontextus

A motorok kvótája **külön-külön és kiszámíthatatlanul** merül ki: 2026-08-05-én
a Terra (`gpt-5.6-terra`, ChatGPT Pro) 9%-on állt, miközben a lánc még 15
Epic 4 kört akart végigvinni. Eddig a motorváltás konfigurációk átírását
jelentette (`~/.codex/config.toml` `model` mezője, `PIPELINE_MODEL`), ami két
bajjal járt: a régi beállítás elveszett, és a visszakapcsolás kézi
rekonstrukció volt.

A user döntése: **mindhárom motor konfigurációja éljen egymás mellett**, és a
váltás legyen egyetlen, visszavonható lépés.

### A választás mérési alapja

Nem benchmark-hivatkozásból választottunk. Egy 20 soros Dart specen mértünk
(tie-szabály, fail-closed `ArgumentError`, float-drift 10 000 lépésen), a
modell kódját **lefuttatva**, modellenként 5–10 futással:

| Motor | Passz | Idő/válasz | $/1M in-out |
|---|---|---|---|
| `qwen/qwen3.7-plus` | **5/5** | 97 s | 0.32 / 1.28 |
| `qwen/qwen3.7-max` | **5/5** | 93 s | 1.25 / 3.75 |
| `openai/gpt-oss-120b` | 9/10 | **5 s** | 0.03 / 0.17 |
| `minimax/minimax-m3` | 9/10 | **3 s** | 0.30 / 1.20 |
| `moonshotai/kimi-k2.5` | 4/5 | 7 s | 0.60 / 3.00 |
| `qwen/qwen3-coder-next` | 7/10 | 4 s | 0.30 / 1.50 |

**Egyik olcsó modell sem determinisztikus**, és mindig ugyanott bukik: a finom
invariánson, nem a szintaxison. Ez pontosan a MiniMax M3-ról dokumentált
gyengeség (`docs/LESSONS.md`: „invariánst lazít"). A modellválasztás tehát nem
váltja ki a gate-et, a scope-auditot és a független review-t — csak azt dönti
el, hányszor kell javító kört futtatni.

Az ingyenes modellek (nemotron, poolside, cohere, stepfun, tencent, ling) a
nehéz specen **0/8-at** teljesítettek, plusz rate limitbe futottak — kapuviselő
munkára alkalmatlanok.

## Döntés

### 1. Motor-nyilvántartás

`docs/execution/engine-registry.tsv` — egy sor egy választható motor:
harness, config dir, modell, auth, elakadás-küszöb, időkorlát, kontextusablak,
ár, megjegyzés (a mért passz-aránnyal).

Két harness él egymás mellett, mert a motorok API-ja eltér:

| harness | mechanizmus | motorok |
|---|---|---|
| `codex` | Codex CLI, `CODEX_HOME=<config_dir>`, `-m <model>` | terra, qwen-*, gptoss, kimi |
| `claude` | Claude Code CLI, `CLAUDE_CONFIG_DIR=<config_dir>` | minimax |

**Egy Codex-profil több modellt is kiszolgál.** A Kilo Code (`~/.codex-kilo`)
mögött nyolc modell él; a modellt és a kontextus-korlátokat a nyilvántartás
adja át `-m` és `-c model_context_window=` kapcsolóval — mert a Kilo
`/responses` végpontja **nem ad model-metaadatot**, és a Codex fallbackje
elrontaná a kontextusablak-becslést.

### 2. A váltás egyetlen visszavonható fájl

```bash
tools/engine-profile.sh list          # nyilvántartás + aktív + elérhetőség
tools/engine-profile.sh use qwen-plus # MINDEN kör ezzel megy
tools/engine-profile.sh clear         # vissza a queue soronkénti értékére
```

Az override a gitignore-olt `.pipeline/engine-override`. **Konfigurációt nem
ír át**, ezért egyik motor beállítása sem vész el: a Terra visszakapcsolása a
limitek visszatértekor egyetlen `use terra`.

A queue `engine` oszlopa változatlanul él; az override felülírja, a `clear`
visszaadja neki a döntést.

### 3. Motoronkénti elakadás-küszöb

A wrapper elakadás-őre (12 perc) a **gyors** motorokra volt hangolva. A Qwen
~95 s alatt válaszol, ami hosszabb gondolkodási szakaszokkal együtt hamis
elakadásnak látszana, és a wrapper kilőné a normálisan dolgozó kört. Ezért a
küszöb és az időkorlát a nyilvántartásból jön (`qwen-plus`: 25 perc / 7200 s).

### 4. A `codex exec` stdin-lezárása

A wrapper mostantól `< /dev/null`-lal indít. Enélkül a `codex exec` a promptot
megkapva IS stdin-re vár („Reading additional input from stdin"), és a kör
némán beragad — mérve a Qwen füst-tesztjén.

## Következmények

- A motorváltás másodpercek kérdése, és **visszafordítható**.
- A `validate_engine` fail-closed marad: csak a nyilvántartásban SZEREPLŐ név
  fogadható el, az ismeretlen érték továbbra is hiba.
- A reviewer-függetlenség (ADR 0138) érintetlen: a `qwen-*` motorok nem Terrák,
  tehát Claude-kvótazárlat alatt a Terra-reviewer független marad tőlük.
- Új motor felvétele egy sor a nyilvántartásban — kódváltoztatás nélkül.

## Ár és határ

A Kilo Code az OpenRouteren keresztül routol, tehát **egy további fél látja a
diffet**. Ez az AGENTS.md §5 határain belül van (a kód eddig is külső
implementerhez ment), de nyers audio, kamera-frame és secret továbbra sem
kerülhet a promptba. A kulcs a repón kívül él (`~/.kilocode-token`, 600).
