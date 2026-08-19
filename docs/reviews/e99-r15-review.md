# E99-R15 — Review

Brief: docs/rounds/e99-r15-gov-09-halt-escalation.md
Diff: `git diff 1be7fe50...e938588a` (1be7fe50 = orchestrátor pre-flight §0.0 revízió `main`-en; 05d81543 = implementer első commit; e938588a = F1 javító commit a `codex/e99-r15-gov-09-halt-escalation` branchen)
Reviewer: Claude (Sonnet 5, orchesztrátor) · Dátum: 2026-08-19 (első verdikt), frissítve 2026-08-19 (F1 javítás után)
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 (1 zárva javítással) · MINOR: 0 · NOTE: 1

## F1 zárása (javító kör után)

A javító commit (`e938588a`, `fix(pipeline): preserve self-heal quota fallback`)
minimális diffet ad: amikor `heal_engine == round_engine` (1–2. kísérlet, vagy
alternatíva nélküli utolsó kísérlet), az `attempt_selfheal` a VÁLTOZATLAN
`run_orchestrator_session`-t hívja (a kvóta-tudatos Claude→Terra fallbackkel),
és a §0.0-ban javasolt új `heal_engine_for_attempt`/`run_selfheal_session` út
kizárólag a valódi motorváltás esetén fut. Pontosan a review javasolt iránya.

Saját, független ellenőrzés (**friss** `/tmp/review-e99-r15-2` klón, a
`https://github.com/wolfcasaba/strumsight.git`-ból, NEM a korábbi
`/tmp/review-e99-r15`-ből):

- **Regressziós teszt megléte:** `test_first_attempt_keeps_the_legacy_terra_fallback_when_claude_is_blocked`
  — szimulált `claude_unavailable_until` zárlat mellett méri, hogy a dispatch a
  Terra-fallback ágra esik (`CODEX_HOME=<terra_config>` a konstruált parancsban),
  nem az új `run_selfheal_session` útra.
- **Saját falszifikáció:** az `if [ "$heal_engine" = "$round_engine" ]`
  feltételt `if false`-ra cserélve (mindig az új, kvóta-tudatlan ág fut) → 3
  failed / 2 passed (a fenti regressziós teszt ÉS az „1–2. kísérlet legacy
  runner" subtestek PIROSAK: `AssertionError: 'sonnet-impl' != 'legacy-runner'`).
  Visszaállítás után `3 passed, 6 subtests passed`.
- **Célzott teszt (friss klón, önálló venv):** `3 passed, 6 subtests passed`.
- **Teljes suite (friss klón, önálló venv, `-u ENGINE_MODEL -u ROUND_ENGINE`):**
  `530 passed, 1 skipped, 565 subtests passed in 363.03s` — nulla piros.
- **Dart gate (friss klón):** `tools/round-gate.sh
  test/tooling/architecture_allowlist_guard_test.dart` → format/analyze/célzott
  teszt/architecture/secrets/l10n mind zöld.
- **Scope-audit (friss klón, `--base 1be7fe50`):** `Legacy scope audit OK
  (1be7fe50..e938588ac723, 6 changed path(s), 2 generated/ignored)` — a 2
  „generated/ignored" a KÉT review-jelentés saját fájlja (a review-jelentés
  soha nem sértés, `tools/ai_router/security.py::GENERATED_IGNORED_PREFIXES`),
  a maradék 4 pontosan az `allowed_paths`.

**F1 STÁTUSZ: FIXED (`e938588a`).**

## Acceptance criteria (brief §6 DoD)

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | D1–D3 kész; a mai viselkedés minden nem érintett ágon bitre azonos | ⚠️ részben | D1/D2/D3 funkcionálisan megvan (lásd lent), DE lásd **F1 — MAJOR**: az 1–2. kísérlet dispatch-mechanizmusa NEM bitre azonos a mai viselkedéssel — a Claude-kvótazárlat→Terra automatikus fallback elveszett minden self-heal kísérletnél, nem csak az utolsónál. |
| 2 | `tools/tests/test_selfheal_escalation.py` lefedi a §4 mind a hat celláját | ✅ | Fájl elolvasva; mind a 6 cella (kísérlet 1/2/3, küszöb alatt/rajta/fölött) jelen van paraméterezett `subTest`-ekben. Saját, független falszifikációval is megerősítve (lásd „Próbatesztek"). |
| 3 | `python3 -m pytest tools/tests -q` zöld | ✅ | Önállóan futtatva, izolált `/tmp/review-e99-r15` klónban, saját venv-ből: `529 passed, 1 skipped, 565 subtests passed in 294.67s`. (Az implementer saját, más környezetében `528 passed, 2 skipped` — a különbség egy, a briefben is dokumentált, a körtől független ambiens-szivárgás `test_claude_harness_engines.py`-ban; az én tiszta környezetemben ez nem jelentkezett, ami megerősíti az ő diagnózisukat.) |
| 4 | `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart` zöld | ✅ | Önállóan futtatva, izolált klónban: format/analyze/célzott teszt/architecture/secrets/l10n mind zöld. |
| 5 | Kör-jelzés `done` | ✅ | `.codex-round-status`: `status=done`, `scope_audit=ok`. |

## Scope-audit

`tools/scope-audit.py --repo /tmp/review-e99-r15 --brief docs/rounds/e99-r15-gov-09-halt-escalation.md --base 1be7fe50` →
`Legacy scope audit OK (1be7fe50..05d81543cbb9, 4 changed path(s), 0 generated/ignored)`.
A 4 fájl pontosan az `allowed_paths` négy bejegyzése (`tools/round-pipeline.sh`,
`tools/tests/test_selfheal_escalation.py`, `docs/execution/pipeline-selfheal-prompt.md`,
`docs/rounds/e99-r15-gov-09-halt-escalation.md`). Engedélyezett fájlokon kívüli
változás: **nincs**.

## Próbatesztek (saját, független falszifikáció — izolált `/tmp/review-e99-r15` klónban)

1. **D1 kikapcsolása:** `heal_engine_for_attempt`-ban az `attempt -lt selfheal_max`
   ágat feltétel nélkülire cserélve (mindig visszaadja `round_engine`-t
   változatlanul) → `test_first_two_attempts_keep_sonnet_and_last_attempt_uses_a_different_model`
   pontosan a `previous_attempts=2` (utolsó kísérlet) subteszten **PIROS**ra
   váltott (`AssertionError: 'sonnet-impl' != 'terra'`), a másik két subteszt
   zöld maradt. Visszaállítás után zöld (`2 passed, 6 subtests passed`).
2. **D2 kikapcsolása:** `halt_reminder_due`-ban egy feltétel nélküli
   `return 0`-t szúrva az elejére → `test_halt_reminders_throttle_at_the_configured_boundaries`
   pontosan a `below` és `above` subteszteken **PIROS**ra váltott
   (`AssertionError: 1 != 0`), az `at` (ahol 1 ntfy-t vár) változatlanul zöld
   maradt. Visszaállítás után zöld.

Mindkét guard valódi, load-bearing — nem csak formálisan lefedett.

## Megállapítások

### F1 — MAJOR — A self-heal dispatch elveszti a Claude-kvótazárlat→Terra automatikus fallbacket, minden kísérletnél (nem csak az utolsónál)

- **Fájl:** `tools/round-pipeline.sh:1273` (`attempt_selfheal` a régi
  `run_orchestrator_session "heal-$halt_round-$attempts" ... "$heal_model"`
  hívást lecseréli `run_selfheal_session "$heal_engine" ...`-ra), és
  `tools/round-pipeline.sh:790-825` (az új `run_selfheal_session` teljes
  törzse).
- **Probléma:** a RÉGI kód (`run_orchestrator_session`, `tools/round-pipeline.sh:693-740`,
  ez a függvény MAGA változatlan a diffben) minden hívónak — a self-healnek
  is — automatikus Claude→Terra fallbacket adott
  `claude_unavailable_until`/`claude_usage_block_until`/
  `claude_stats_cache_unavailable_until` ellenőrzéssel. Az ÚJ
  `run_selfheal_session` ezt a három ellenőrzést **egyiket sem hívja** —
  mértem: `sed -n '/^run_selfheal_session/,/^}/p' tools/round-pipeline.sh |
  grep -c "claude_unavailable_until\|claude_usage_block_until\|claude_stats_cache_unavailable_until"`
  → `0`. Ez az 1–2. kísérletet IS érinti, nem csak a D1 által célzott utolsó
  kísérletet — az `attempt < selfheal_max` ágon `heal_engine_for_attempt`
  változatlanul `round_engine` (`"sonnet-impl"`) értéket ad vissza, tehát a
  dispatch a mai `~/.claude` profilt futtatja, de a régi kvóta-tudatos
  fallback NÉLKÜL.
- **Hatás:** a brief §6 DoD 1. pontja explicit ígéri: „a mai viselkedés minden
  NEM ÉRINTETT ágon bitre azonos". Az 1–2. kísérlet D1 szerint is „a kör saját
  motorjával megy (mai viselkedés)" — ez nem bitre azonos, mert a mai
  viselkedés RÉSZE volt az automatikus Terra-fallback Claude-kvótazárlat
  alatt (ADR 0115/ADR 0222, `docs/LESSONS.md` L215 és a HANDOFF több
  kvótazárlat-eseménye — ez egy MÉRTEN gyakori, visszatérő hibaosztály ezen a
  boxon). Ha a Claude-kvóta pont egy self-heal kísérlet közben merül ki, a
  RÉGI kód átmenetileg Terrára váltott UGYANAZON a kísérleten belül; az ÚJ
  kód ehelyett feltehetően jelzés nélkül elhal (a `claude` CLI hibázik,
  `run_tmux_session` nem kap terminális jelzést), ami az `attempt_selfheal`
  „az önjavító session jelzés nélkül ért véget" ágát váltja ki — ez a
  KORLÁTOS, 3 kísérletes self-heal büdzséből éget el egyet egy olyan
  ok miatt, amit a régi kód költségmentesen, ugyanazon a kísérleten belül
  kezelt. Egy risk=high, kifejezetten a self-heal REZILIENCIÁJÁT célzó
  körben ez egy ironikus, valódi regresszió egy MÁSIK, jól dokumentált
  hibaosztályra.
- **Kötelező javítás (irány, nem kész patch):** a legkisebb-diffű megoldás:
  az `attempt_selfheal`-ban ne cseréld le a hívást minden esetben
  `run_selfheal_session`-re — amíg `heal_engine == round_engine`
  (azaz az 1–2. kísérlet, VAGY az utolsó kísérlet is, ha nem talált
  alternatívát), hívd TOVÁBBRA IS a változatlan `run_orchestrator_session`-t
  (a `$heal_model` paraméterrel, ahogy ma), és `run_selfheal_session`-t
  KIZÁRÓLAG akkor, ha `heal_engine != round_engine` (a valódi
  motorváltás esete). Ez byte-pontosan megőrzi a mai viselkedést az
  „nem érintett" ágakon, és a `run_selfheal_session`/
  `selfheal_engine_is_available`/registry-alapú dispatch csak az ÚJ,
  ténylegesen más-motoros esetben fut — pontosan ott, ahol a brief D1-je
  előírja. (Alternatíva, ha a hívás-egységesítés szándékos: építsd be a
  három kvóta-ellenőrzést `run_selfheal_session`-be IS, amikor a választott
  sor `config_dir`-ja megegyezik `$pipeline_claude_config_dir`-ral — de ez
  nagyobb diff ugyanannak az eredménynek az eléréséhez.)
- **Ellenőrzés:** egy regressziós teszt, amely stub-olja
  `claude_unavailable_until`-t (visszaad egy jövőbeli epochot) attempt=1
  mellett, és megméri, hogy a dispatch a Terra-ágra esik (nem csupán a
  Claude-ág hibázik) — a jelenlegi `test_selfheal_escalation.py` ezt NEM
  fedi (a saját `run_orchestrator_session`/`run_selfheal_session` stubja a
  hívó FÜGGVÉNY NEVÉT rögzíti, nem a kvóta-ági viselkedést).
- **Státusz:** FIXED (`e938588a`) — lásd „F1 zárása" fent a mért bizonyítékért.

### N1 — NOTE — `run_selfheal_session` minimax-ági env-hidalása nem redundáns, de rejtett

- **Fájl:** `tools/round-pipeline.sh:801-807` (a `case "$model" in
  claude-*|sonnet-*|opus-*|haiku-*) ;; *) ... esac` ág).
- **Megfigyelés:** ellenőriztem, hogy ez NEM hibás (`tools/engine-profile.sh
  env <name>` a `claude` harness-hez csak `CLAUDE_CONFIG_DIR`/`ENGINE_*`/az
  `auth_env` nevű változót exportálja, `ANTHROPIC_BASE_URL`-t soha — a kézzel
  írt `export ANTHROPIC_BASE_URL=…; export ANTHROPIC_AUTH_TOKEN="${$auth_env:-}"`
  ezért SZÜKSÉGES híd, nem duplikáció). Nem blokkoló, csak dokumentálásra
  érdemes: ez a minimax-út a gyakorlatban csak akkor aktiválódik, ha SEM
  `codex`, SEM `terra` nem elérhető (mindkettő megelőzi a regiszter-sorrendben,
  ha a `~/.codex`/`~/.codex-terra` könyvtár létezik) — jelenleg ez a boxon
  mérve nem a valós útvonal, tehát élesben nincs füst-tesztje.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer, F1 javítás után) | Ellenőrizve (saját, FRISS izolált klón) |
|---|---|---|
| format/analyze/architecture/secrets/l10n | zöld | ✅ zöld (`tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart`) |
| célzott teszt (`test_selfheal_escalation.py`) | `3 passed, 6 subtests passed` | ✅ `3 passed, 6 subtests passed` |
| `python3 -m pytest tools/tests -q` | `529 passed, 2 skipped, 565 subtests` | ✅ `530 passed, 1 skipped, 565 subtests` (ugyanaz az ambiens-eltérés, mint korábban — a saját tiszta környezetemben 1-gyel több passed) |
| CI (`full-gate.yml`, `router-ci.yml`) | — | dispatch-elve a review után, az orchesztrátor várja be |

## Merge-döntés

**APPROVED — 0 nyitott BLOCKER/MAJOR** (F1 zárva `e938588a`-val, saját
méréssel megerősítve). Az ADR 0052 szerint minden gate zöld ÉS nincs nyitott
BLOCKER/MAJOR → merge, amint a CI (`full-gate.yml` + `router-ci.yml`) is
zöld a merge SHA-n.
