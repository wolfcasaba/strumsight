# E99-R15 (GOV-09) — Halt-eszkaláció: motorváltás az utolsó önjavító kísérletnél és ismétlődő riasztás

- **Státusz:** READY FOR IMPLEMENTATION (brief 2026-08-18, `main @ 52324cb3`)
- **Típus:** **governance-kör** — a lánc SAJÁT vezérlése
- **Kör-azonosító:** `E99-R15`. Emberi neve **GOV-09**.
- **Előfeltétel:** `E99-R14` merge-elve (ugyanaz a fájl, `tools/round-pipeline.sh`)
- **Brief szerzője:** Claude (Opus 5, orchesztrátor) · **ADR:** [`0307`](../adr/0307-pipeline-throughput-program-v2.md) **§2** — az ADR MÁR MEGÍRVA, a `docs/adr/` TILOS zóna.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "tools/round-pipeline.sh",
  "tools/tests/test_selfheal_escalation.py",
  "docs/execution/pipeline-selfheal-prompt.md",
  "docs/rounds/e99-r15-gov-09-halt-escalation.md",
]
gate_tests = [
  "test/tooling/architecture_allowlist_guard_test.dart",
]
native_gate = false
```

> **Kockázat = high, indoklás:** a diff a lánc saját vezérlésébe (self-heal ág,
> riasztás) nyúl; egy hibás feltétel némán megállíthatja vagy végtelen
> ismétlésbe hajthatja a láncot. A `gate_tests` cella fa-egészség őr; a kör
> tényleges mércéje a `pytest tools/tests` + Router CI (§7).

## 0.0 Pre-flight revízió (orchesztrátor, 2026-08-18)

**Visszakeresés (ADR 0312 §4.2, brief-lint S8):**
`node tools/knowledge-rag.mjs --top 5 "self-heal önjavítás motorváltás engine
escalation last attempt different engine"` és
`node tools/knowledge-rag.mjs --corpus lessons --top 6 "önjavító session sajat
motorja orchestrator engine Claude Terra fallback run_orchestrator_session"`
lefutott. Releváns találat: **L127** (E04-R16) — a Kilo-qwen motorok
„bejelent-majd-megáll" (`status=unknown`) hibája HARNESS-szintű, nem
modell-egyedi; ha a D1 determinisztikus választása valaha egy `qwen-*`/Kilo
sorra esne, ez a kockázat érvényes rá (a mai regiszter-sorrendben ez csak
akkor fordulhat elő, ha a `codex`/`terra`/`minimax`/`sonnet-impl` sorok mind
kizáródnak vagy elérhetetlenek). L278/L215/L229/L174/L289 a Claude/Terra
fallback-ág és a kvóta-védőháló korábbi méréseit írják le, ezen brief tartalmi
döntését nem módosítják. Nincs korábbi lecke, ami magát a „self-heal
motorváltás az utolsó kísérletnél" mintát vagy egy ismétlődő-riasztás
throttle-t mérte volna — mindkettő ÚJ terület.

**D2 korrekció — MÉRT: a §2 „Jelenlegi állapot" azon állítása, hogy „a
riasztás egyszer ment ki… és nem ismétlődött", TÉVES a kódhoz és a naplóhoz
képest.** `grep -c "KIMERÜLT" .pipeline/chain.log` → **455** találat; az
E07-R16 ablakában (2026-08-16T15:35 → 2026-08-18T09:02, kb. 42 óra) a napló
**5 percenként, folyamatosan** „az önjavítás KIMERÜLT" sort ír — pontosan a
cron-cadenciával (`crontab -l`: `*/5 * * * * … round-pipeline.sh`). Az
`attempt_selfheal()` (`tools/round-pipeline.sh:1039-1045`) a kimerülési ágat
FELTÉTEL NÉLKÜL újrafuttatja minden firingen (a `heal_count_file` a
feloldásig változatlan), és a benne lévő
`notify "🛑 önjavítás kimerült…" high` hívás **throttle nélkül** fut —
tehát a mai valódi hiba **nem csend, hanem kontrollálatlan, 5 percenkénti,
high-prioritású spam** (~504 push egy 42 órás ablakban). A „éjszaka ez egyenlő
a csenddel" fordulat feltehetően azt írja le, hogy egy alvó/távoli emberre az
500 azonos push ugyanolyan hatástalan, mint a nulla — nem azt, hogy a rendszer
ne küldött volna újra.

**Következmény a D2 implementációjára:** a feladat NEM egy új, párhuzamos
emlékeztető hozzáadása a változatlan hívás MELLÉ (az kettőzött spam-et adna),
hanem a **meglévő, throttle nélküli `notify` hívás lecserélése**
`PIPELINE_HALT_REMINDER_MIN`/`PIPELINE_HALT_REMINDER_MAX_H` által kapuzott
változatra, UGYANAZON a kódponton (`attempt_selfheal()` kimerülési ága,
`tools/round-pipeline.sh:1039-1045`). A `log "az önjavítás KIMERÜLT…"` sor
marad feltétel nélküli — ez adja a §4 „küszöb fölött" cella „a napló továbbra
is ír" elvárását —, kizárólag a `notify(...)` hívás kap throttle-kaput.

**D1 pontosítás — a `<kör-motor>` (4. paraméter) forrása.** A self-heal
session `run_orchestrator_session()`-ön megy (`tools/round-pipeline.sh`), ami
MINDEN körre és MINDEN önjavítási kísérletre AZONOS módon dönt: elsődlegesen
Claude CLI (`CLAUDE_CONFIG_DIR=$pipeline_claude_config_dir`,
`--model $heal_model`, alapból `claude-sonnet-5`), és KIZÁRÓLAG
Claude-kvótazárlat/rotáció alatt esik át a rögzített Terra-fallback ágra
(`CODEX_HOME=$codex_home`, fixen `~/.codex-terra`). Ez a választás **nem függ
attól, melyik kör vagy melyik IMPLEMENTER-motor halt el** — a
`docs/execution/pipeline-queue.tsv`/`engine-registry.tsv` implementer-neve
(minimax/codex/qwen-*/stb.) sosem jut el a self-heal dispatch-hoz; azt
kizárólag a Claude-kvóta/rotáció állapota dönti el. A §2 „a self-heal MINDIG a
kör saját motorjával indul" mondata tehát úgy pontos, hogy a self-heal motorja
MINDIG UGYANAZ a fix Claude/Sonnet-5 identitás, kör-függetlenül — ez a
nyilvántartás `sonnet-impl` sorával egyezik (harness=`claude`,
config_dir=`~/.claude`, model=`claude-sonnet-5` — mind a három mező
byte-egyenlő a `pipeline_claude_config_dir`/`heal_model` mai alapértékével,
mérve `tools/round-pipeline.sh:101-142` és `docs/execution/engine-registry.tsv`).
A `<kör-motor>` paraméter ÉRTÉKE ezért egy FIX konstans (`sonnet-impl`), NEM a
halt-olt kör implementer-motorja — a hívó helyen (`attempt_selfheal`, az
`attempts=$((attempts+1))` sor után) literál konstansként add át, ne a kör
branch-éből vagy a queue sorából származtatva.

**D1 végrehajtási megjegyzés (kódolási gotcha, nem tartalmi döntés):** a
`docs/execution/engine-registry.tsv` fejlécsora (`name<TAB>harness<TAB>…`) NEM
adatsor — a meglévő `tools/engine-profile.sh` `engine_names()`/`row_for()`
mintáját kövesd (`grep -v '^[[:space:]]*#' … | grep -v '^name\t'`), különben a
determinisztikus „első a sorrendben" keresés a fejlécet találná első
jelöltként. Az „elérhető" (c) kritériumhoz a `tools/engine-profile.sh`
`availability()` már bevett, STATIKUS ellenőrzését használd (a `config_dir`
mezőnek könyvtárként kell léteznie, és ha az `auth_file` mező nem `-`,
olvashatónak kell lennie) — élő füst-teszt (`engine-profile.sh check`) NEM
indokolt egy önjavító-motorválasztáshoz, mert API-keretet égetne el a puszta
döntésért. Méréssel megerősítve: `~/.codex`, `~/.codex-terra`, `~/.claude`,
`~/.claude-minimax` mind léteznek ezen a boxon, tehát a `kör-motor=sonnet-impl`
eset NEM vezet üres jelölt-listára (nem „elérhetetlen cél-státusz") — a
regiszter-sorrendben az első illeszkedő, elérhető sor ma a `codex`.

**ADR-döntés:** ez a kör NEM ír új ADR-t (a brief fejléce és az `allowed_paths`
is kizárja a `docs/adr/**`-t) — az ADR 0307 §2 már lefedi, pontosan az E99-R14
mintáját követve (`docs/rounds/e99-r14-gov-08-engine-policy-measured.md`
fejléc, és a PR #317 diffje nem érintett ADR-fájlt). `tools/round-slots.py
reserve-adr` ezért NEM fut le — egy fel nem használt szám foglalása felesleges
könyvelés lenne.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **STOP-protokoll:** listán kívüli fájl →
`stopped` + brief-revízió kérése; az `allowed_paths` tágítása TILOS.

## 1. Cél — a mért 42 órás állás

2026-08-16 13:06-kor indult az `E07-R16`. 14:15-kor `H-NOSIGNAL`-lal halt (az
elakadás-őr helyesen mérte, hogy a session-napló 20 perce nem változott). Ezután
**három** önjavító kísérlet futott — mindhárom UGYANAZZAL a motorral —, és
mindhárom ugyanúgy, jelzés nélkül halt el (14:40, 15:05, 15:30). 15:35-kor „az
önjavítás KIMERÜLT (3/3)", a lánc megállt, és **2026-08-18 08:20-ig állt**:
**42 óra**, nulla munkával.

Mért kontextus: 2026-08-01 óta **115,7 óra** halt-állás 93 epizódban; a
self-heal 91 epizódot magától megoldott. A két valaha mért KIMERÜLÉS (E03-R09,
E07-R16) **mindkettő `H-NOSIGNAL`** volt — vagyis pontosan az a hibaosztály,
ahol a variáció nélküli ismétlés semmit nem változtat.

A riasztás egyszer ment ki (`round-pipeline.sh`, „önjavítás kimerült"), és nem
ismétlődött — éjszaka ez egyenlő a csenddel.

## 2. Jelenlegi állapot — mérve a kódban

- `selfheal_max=${PIPELINE_SELFHEAL_MAX:-3}`; a `heal_attempts` a (kör,
  halt-kód) párra számol kísérletet.
- Az önjavító session MINDIG a kör saját motorjával indul — a kísérlet
  sorszáma nem befolyásol semmit.
- Kimerüléskor egyetlen `notify … high` megy, majd a lánc minden firingen csak
  annyit naplóz, hogy „a lánc továbbra is áll — feloldás:
  tools/pipeline-status.sh --resume".
- A `H-GATEGUARD` ág (az önjavítás a gate-hez nyúlt) emberi döntést kér.

## 3. Feladatok

### D1 — Az utolsó kísérlet MÁS motorral fut

- Új függvény: `heal_engine_for_attempt <kör> <halt-kód> <kísérlet> <kör-motor>`.
- Szabály: az 1. és 2. kísérlet a kör saját motorjával megy (mai viselkedés);
  az **utolsó** (`selfheal_max`-adik) kísérlet a motor-nyilvántartásból
  (`docs/execution/engine-registry.tsv`) választ **determinisztikusan** másikat:
  a nyilvántartás sorrendjében az első olyan, elérhető motor, ami (a) nem a kör
  motorja, (b) nem ugyanaz a `model` érték (a `codex` és a `terra` sor mérve
  UGYANAZ a modell — a kettő cseréje nem variáció), (c) `harness`-e támogatott.
- A választás naplózva: `ÖNJAVÍTÓ MOTORVÁLTÁS: <kör> <régi> → <új> (utolsó kísérlet)`,
  és ntfy-jal jelezve.
- Ha nincs alkalmas másik motor, a mai viselkedés marad (ugyanaz a motor),
  naplózott indoklással — **fail-open a mai állapotra, nem néma kihagyás**.

### D2 — A kimerült állapot nem néma

- `PIPELINE_HALT_REMINDER_MIN` (alap **60** perc): amíg a `.pipeline/HALTED`
  létezik ÉS az önjavítás kimerült, a driver ennyi percenként ismételt,
  `high` prioritású ntfy-t küld. Az utolsó riasztás időbélyege a `$state_dir`-ben
  él, hogy az 5 perces cron ne spammeljen.
- `PIPELINE_HALT_REMINDER_MAX_H` (alap **24** óra): ennyi idő után az ismétlés
  leáll (a napló ettől még minden firingen ír).
- A riasztás törzse tartalmazza a kört, a halt-kódot és a
  `tools/pipeline-status.sh --resume` parancsot.

### D3 — A self-heal prompt tudjon a motorváltásról

`docs/execution/pipeline-selfheal-prompt.md`: az utolsó kísérlet promptja
mondja ki, hogy MÁS motor futtatja, és hogy az előző két kísérlet naplója
(`.pipeline/heal-*.log`) bemenet, nem megismételendő munka.

## 4. Mérce-mátrix

`PIPELINE_HALT_REMINDER_MIN = 60` és a kísérlet-küszöb hármas cellái
(`tools/tests/test_selfheal_escalation.py`):

| eset | bemenet | elvárt viselkedés |
|---|---|---|
| küszöb **alatt** | az utolsó riasztás 59 perce ment ki | NINCS új ntfy |
| küszöb **rajta** | pontosan 60 perce | pontosan EGY új ntfy |
| küszöb **fölött** | 25 óra telt el a halt óta (`MAX_H` fölött) | nincs több ntfy, a napló továbbra is ír |
| kísérlet 1 | `heal_attempts = 0` | a kör saját motorja |
| kísérlet 2 | `heal_attempts = 1` | a kör saját motorja |
| kísérlet 3 (utolsó) | `heal_attempts = 2` | MÁS motor, más `model` értékkel |

**Falszifikációs cella (kötelező):** a D1 motorváltás kiszedése (az utolsó
kísérlet is a kör motorjával induljon) → a „kísérlet 3" eset **PIROS** →
visszaállítás után zöld. Második falszifikáció: a D2 időbélyeg-ellenőrzés
kiszedése → a „küszöb alatt" eset **PIROS** (spam).

## 5. Tilos zóna — amit ez a kör NEM tesz

- **Nincs automatikus resume.** A kimerült halt feloldása változatlanul emberi
  döntés; a kör csak hangosabbá teszi az állapotot.
- A `H-GATEGUARD` ág változatlan.
- A `selfheal_max` alapértéke NEM nő (3 marad): a cél a variáció, nem a több
  próbálkozás.
- A gate, a review-protokoll és a merge-kapu érintetlen.
- Fájlok: `docs/adr/**`, `.ai/router.toml`, `.pipeline/**`, Dart források — tilos.

## 6. Definition of Done

1. D1–D3 kész; a mai viselkedés minden nem érintett ágon bitre azonos.
2. `tools/tests/test_selfheal_escalation.py` lefedi a §4 mind a hat celláját.
3. `python3 -m pytest tools/tests -q` zöld.
4. `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart` zöld.
5. Kör-jelzés `done`.

## 7. Gate

```bash
tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart
python3 -m pytest tools/tests -q
```

A gate-lépések külön processzben futnak; a csonkítatlan kimenet a bizonyíték.
A teljes suite + property gate a CI-ban fut (ADR 0053).

## Implementation handoff

- **Megvalósítás:**
  - `tools/round-pipeline.sh`: az utolsó self-heal-kísérlethez a rögzített
    `sonnet-impl` identitástól eltérő, más modellű, statikusan elérhető motort
    választ a registry-sorrendben; hiányzó jelöltnél naplózottan megtartja a
    mai viselkedést. A kiválasztott motor saját harnessén indul. A kimerült
    állapot `halt-reminder-last` állapotfájllal 60 perces throttlet és 24 órás
    felső korlátot kap, miközben a `KIMERÜLT` naplósor minden firingkor megmarad.
  - F1 review-javítás: amikor a kiválasztott self-heal motor megegyezik a
    rögzített `sonnet-impl` motorral, a dispatch a változatlan
    `run_orchestrator_session`-ön marad a `$heal_model` paraméterrel. Így az
    első két próbálkozás, illetve az alternatíva nélküli utolsó próbálkozás
    megőrzi a Claude-kvótazárlat → Terra fallbacket; csak a tényleges
    motorváltás használja a registry-saját `run_selfheal_session` útvonalat.
  - `tools/tests/test_selfheal_escalation.py`: a §4 hat cellája, valamint a
    váltási ntfy/log és a rendered prompt D3-követelményei hermetikus
    fixture-rel lefedve; F1-re egy szimulált `claude_unavailable_until`
    zárlat igazolja, hogy az első próbálkozás a Terra-fallback dispatchre esik.
  - `docs/execution/pipeline-selfheal-prompt.md`: a rendered utolsó-kísérlet
    promptja megkapja a motorváltás és az előző `.pipeline/heal-*.log` naplók
    bemenetként kezelésének utasítását.
- **RED/GREEN:** az F1 regressziós teszt a javítás előtt a `new-runner`
  dispatch-csel bukott a várt `terra-fallback` helyett; a javítás után
  `3 passed, 6 subtests passed`.
- **Falszifikáció:** a D1 választás ideiglenes kikapcsolása a 3. kísérlet
  celláját pirosra váltotta; a D2 időbélyeg-kapu ideiglenes kikapcsolása az
  59 perces és 24 órán túli cellát pirosra váltotta. Mindkét őr visszaállítva,
  utána célzottan zöld.
- **Futtatott ellenőrzések:**
  - `/tmp/e99-r15-pytest-fix/bin/python -m pytest tools/tests/test_selfheal_escalation.py -q`
    → `3 passed, 6 subtests passed`.
  - `env -u ENGINE_MODEL -u ROUND_ENGINE /tmp/e99-r15-pytest-fix/bin/python -m pytest tools/tests -q`
    → `529 passed, 2 skipped, 565 subtests passed`.
  - `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart`
    → format, analyze, célzott teszt, architecture, secrets és l10n zöld.
- **Környezeti eltérés:** a szanitálatlan teljes tooling-suite egyszer a
  `test_claude_harness_engines.py` meglévő legacy MiniMax-tesztjén bukott,
  mert a harness `ENGINE_MODEL=gpt-5.6-terra` értéke a teszt saját
  `dict(os.environ)` környezetébe öröklődött. A konkrét teszt az értékek
  eltávolításával zölden reprodukálható volt; a körtől független,
  allowed_paths-on kívüli teszt-higiéniai hiba, ezért itt nem módosult.
- **Nem futtatott ellenőrzések:** CI full suite/property/release APK, PR és
  független correctness/security review az orchestrátor következő lépése.
