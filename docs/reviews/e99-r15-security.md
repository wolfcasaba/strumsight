# E99-R15 (GOV-09) biztonsági review — self-heal motor-eszkaláció + halt-emlékeztető throttle

- **Kör:** E99-R15 · branch `codex/e99-r15-gov-09-halt-escalation` · HEAD `05d81543` · base `1be7fe50`
- **Diff:** `git diff 1be7fe50 05d81543` (4 fájl, +376/−8) — `tools/round-pipeline.sh` (+182/−8), `tools/tests/test_selfheal_escalation.py` (+162), `docs/execution/pipeline-selfheal-prompt.md` (+2), `docs/rounds/e99-r15-gov-09-halt-escalation.md` (+38)
- **Reviewer:** `security-reviewer` ágens (READ-ONLY, AGENTS.md §15.1 — kötelező, `risk=high`: hitelesítés/kulcs-kezelő kódutat érint)
- **Referencia-kontraktus:** `docs/rounds/e99-r15-gov-09-halt-escalation.md`, `docs/execution/engine-registry.tsv` (ADR 0140), `tools/engine-profile.sh`, AGENTS.md §5 / §5.1
- **Verifikációs környezet:** friss izolált klón `/tmp/sec-review-e99-r15`. A `05d81543` HEAD a lokális `origin`-ban NEM volt jelen (a lokális tükör elmaradt); a `wolfcasaba/strumsight` GitHub-remote-ból `git ls-remote` igazolta a valódi branch-tipet `05d81543cbb9…`, onnan fetch-eltem és checkoutoltam. A diff-fájlkészlet pontosan a feladatban leírt 4 fájl, base = a HEAD közvetlen szülője (egyetlen commit).
- **Verdikt:** **PASS — nincs CRITICAL, nincs BLOCKER, nincs MAJOR, nincs MINOR.** 6 × NOTE (mind ELŐRE-MUTATÓ / defense-in-depth vagy commit-trust-boundary alatt). A biztonsági oldal a merge-et **nem blokkolja.**

## Osztályozás

| Súlyosság | Darab | Blokkol? |
|---|---|---|
| CRITICAL | 0 | — |
| BLOCKER | 0 | — |
| MAJOR | 0 | — |
| MINOR | 0 | — |
| NOTE | 6 | nem |

**Miért nincs MINOR sem:** a fegyelmi szabály szerint csak **reprodukálható** lelet jelenthető. A vizsgált kockázatok mindegyike vagy (a) a jelenlegi registry-tartalommal bizonyítottan **zárt** ebben a körben, vagy (b) csak egy JÖVŐBELI, a git-követett `engine-registry.tsv`-t módosító commit után válna élővé — az pedig a „ki commitolhat a repóba" bizalmi határ alatt van, ami ugyanaz a határ, mint a `round-pipeline.sh` közvetlen átírása. „Elvileg veszélyes, de nincs jelenleg reprodukálható rossz kimenet" = NOTE, nem MINOR.

---

## 1. A kör legkritikusabb állításának FÜGGETLEN, MÉRT megerősítése — a MiniMax auth-token NEM szivárog a session-naplóba, argv-be vagy commitba

Ez a kör legérzékenyebb kódutja a `run_selfheal_session()` MiniMax-ága
(`tools/round-pipeline.sh:807–812`): amikor az utolsó self-heal kísérlet egy
nem-Claude-natív modellű motort (ma egyedül `minimax`, `MiniMax-M3`) választ, a
runner-string beszúrja a hitelesítést. A kérdés: kikerül-e a **nyers token**
argv-be, a világ számára olvasható `$session_log`-ba (`.pipeline/heal-*.log`),
vagy commitolható állapotba? A választ nem hittem el a kód olvasásából — a
tényleges végrehajtási mechanikát követtem végig.

**A token életútja, lépésről lépésre (mind bizonyíték a diffből + a hívott, változatlan függvényekből):**

1. **A token neve, nem az értéke kerül a string-be.** A `806:812` sor
   `export ANTHROPIC_AUTH_TOKEN=\"\${$auth_env:-}\"` szerkezetében a `$auth_env`
   (a registry 5. oszlopa, `MINIMAX_API_KEY`) a **string-építéskor** bővül, a
   `\$`/`{`/`:-}` viszont literál marad. A runner-string tehát a
   `export ANTHROPIC_AUTH_TOKEN="${MINIMAX_API_KEY:-}"` **indirekt hivatkozást**
   tartalmazza, nem a titkot. A tényleges érték csak a tmux-shell-ben, futásidőben
   oldódik fel. (Ez a fejléc-komment kifejezett szándéka: „a MiniMax-kulcsot az
   engine-profile csak a tmux-beli shellben olvassa be, így nem kerül argv-be".)

2. **A kulcs-fájl olvasása captured stdout-on történik, nem a terminálon.** A
   `profile_env` (`811`) `eval "$(bash tools/engine-profile.sh env 'minimax')"`.
   Az `engine-profile.sh` `env` ága (`309:335`) a titkot **kizárólag stdout-ra**
   írja (`printf '%s=%s\n' "$auth_env" "$(… config.json api_key …)"`), amit a
   `$(...)` parancshelyettesítés **elnyel** — a terminálra (és így a `pipe-pane`
   által a `$session_log`-ba) semmi nem kerül. A `python3` JSON-kinyerés `2>/dev/null`,
   tehát a hibaág sem szór titkot stderr-re; az egyetlen stderr-írás a hibaágon a
   motor **neve** (`ismeretlen motor: $name`), nem titok.

3. **A pane-echo a literált mutatja, nem a feloldott értéket.** A
   `run_tmux_session` (`577:579`) interaktív bash-panelbe `send-keys`-eli a
   runner-stringet, és `pipe-pane`-nel menti a pane **kimenetét**. A PTY-echo a
   beírt **nyers karaktereket** tükrözi (`${MINIMAX_API_KEY:-}`), a bash a bővítést
   csak az Enter UTÁN végzi, és egy `export` értékadás **semmit nem ír stdout-ra**.
   A feloldott token tehát sosem jelenik meg a panelben → nincs a `$session_log`-ban.

4. **Nincs `set -x` sehol.** Sem a `round-pipeline.sh`-ban, sem az
   `engine-profile.sh`-ban (grep: 0 találat `set -x`/`xtrace`). Így nincs
   trace-út, amely a feloldott `export ANTHROPIC_AUTH_TOKEN=<titok>`-ot a
   stderr-en keresztül a naplóba juttatná. (Ez lett volna a CRITICAL-forgatókönyv;
   bizonyítottan zárt.)

5. **A `log()`/`notify()` hívások nem tartalmaznak titkot.** A
   `run_selfheal_session` mind a négy `log` sora (`793,797,821,830`) csak a motor-
   vagy harness-**nevet** interpolálja; a `config_dir`/`model`/`auth_env`/runner
   soha nem kerül `log`-ba. A `run_tmux_session` `log` sora (`580`) a session-nevet
   és a napló-útvonalat írja, a `$shell_command`-ot NEM.

6. **A napló commitolhatatlan.** `.gitignore:3` (`*.log`) és `:74–75` (`.pipeline/`
   — „sosem committolt"); `git ls-files | grep '^\.pipeline/'` = 0. Tehát még ha egy
   titok bele is kerülne egy heal-naplóba, git-commitba akkor sem juthat. Kettős védelem.

**Következtetés:** a hitelesítési út — épp az a rész, ami a review-t
kötelezővé tette — **szándékosan és helyesen** úgy van megépítve, hogy a nyers
token kimaradjon az argv-ből, az echo-zott parancssorból, a pane/`$session_log`-ból
és a commitolható állapotból. Ez egy bash-scriptben figyelemre méltóan gondos
titok-kezelés. **Nulla token-szivárgás — CRITICAL/BLOCKER egyik ágon sem.**

---

## 2. A feladatban kiemelt négy kérdés — tételes válasz

### (a) A runner-string idézőjelezés/injekció-biztonsága — NOTE

A `config_dir`, `model`, `prompt_file`, `auth_env` mind a **git-követett**
`engine-registry.tsv`-ből jön (5–6. mező), egy operátor által beállítható
`PIPELINE_ENGINE_REGISTRY` útvonalról — **nem** futásidejű, nem külső, nem
felhasználói bemenet. A jelenlegi registry minden érintett mezője biztonságos
karakterkészletű (`[a-z0-9./~-]`), ezért **jelenleg nincs reprodukálható**
quoting-törés vagy injekció. Egy ellenséges TSV (pl. `config_dir`-ben `'`, vagy
`auth_env`-ben `}` + shell-metakarakter, ami a `${…}` eval-pozícióba kerül a
`812` sorban) elronthatná az idézést vagy parancsot injektálhatna — de ehhez
commitolni kell a repóba, ami **ugyanaz a bizalmi határ**, mint a script átírása.
Megjegyzendő: az ÚJ `run_selfheal_session` runnerei (`807,824`) **több** idézőjelet
használnak (`'$config_dir'`, `'$model'`, `'$prompt_file'`), mint a MÁR MEGLÉVŐ
`run_orchestrator_session` testvérek (`855,881` — idézőjel nélküli bővítések),
tehát ez **nem regresszió**, sőt szigorítás. Fix-irány (defense-in-depth):
registry-mezők karakterkészlet-validálása betöltéskor, vagy a mezők eval-pozícióba
interpolálásának kerülése.

### (b) A hardcoded MiniMax-endpoint és az eval-forrásolt `engine-profile.sh env` ütközése — NOTE (korrektségi footgun, ma NEM kihasználható)

**Nem ütköznek — komplementerek.** Az `eval "$(engine-profile.sh env minimax)"`
a `MINIMAX_API_KEY`-t (és `CLAUDE_CONFIG_DIR`, `ENGINE_MODEL`… ) állítja be, de
`ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN`-t **nem**; a hardcoded `812` sor épp
ezt a két nevet tölti fel a MiniMax-endpointtal és a `${MINIMAX_API_KEY:-}`
indirekt hivatkozással. A sorrend helyes (eval előbb, a token-map utána), így a
kulcs a MiniMax auth-tokenné fordul. **Nincs clobber, nincs exploit ma:** a
registry EGYETLEN nem-natív-modellű `claude`-harness sora a `minimax`, amelyre a
hardcoded URL **helyes**; a `sonnet-impl` a `sonnet-*` mintára natív ágon fut, a
többi nem-natív modell (qwen*/gptoss/kimi/deepseek) `codex`-harness → a
`codex`-ágra megy, nem ide.

**A footgun (latens):** a `case "$model"` nem-natív ág (`809:813`)
**modell-agnosztikus**, de a törzse **MiniMax-specifikus** endpointot és
csak a token-**nevet** (helyesen, per-sor) kezeli. Ha valaki később egy MÁSODIK
`claude`-harness, nem-natív-modellű sort ad a registryhez (pl. egy `glm`/`GLM_API_KEY`
provider), annak tokenje a `api.minimax.io`-ra menne → **kereszt-provider
kulcs-szivárgás egy idegen felhő-endpointra**. Fix-irány: az ágat kösd a
tényleges `minimax` motorhoz (vagy a base URL-t is a prof­ilból/registry-oszlopból
származtasd, ne hardcode-old). Ma NOTE — a következő felhő-motor bekötése előtt
ez az #1 javítandó pont.

### (c) Titok a `$session_log`-ban vagy commitolható állapotban — NOTE (a pipeline kódja NEM szivárogtat; maradék: session-env)

Lásd az 1. szakasz 6 lépéses bizonyítását — a pipeline **saját kódja** nem juttat
tokent a naplóba/commitba. Egyetlen maradék, előre-mutató megfigyelés: a `812`
`export` a tokent a **heal-session bash-környezetébe** teszi (és onnan a `claude`
gyerekbe örökli). Ha a heal-ágens (`bypassPermissions`-nel, autonóm módon) BÁRMIKOR
lefuttat egy környezet-kiíró parancsot (`env`/`printenv`/`set`/összeomlás-dump),
a token a pane-en át a `$session_log`-ba kerülhet. Ez (i) az ágens
nem-determinisztikus viselkedésétől függ (nem reprodukálható lelet), (ii) a napló
`.gitignore`-olt (commitba nem juthat), (iii) egy-UID-os box saját kulcsa. Ezért
NOTE, nem MINOR. Fix-irány (defense-in-depth): `umask 077` / `chmod 600` a
heal-naplókra, vagy a titok-export a pipe-pane-elt interaktív panelen kívülre
emelése (pl. `tmux setenv`/`--env`-fájl, ami nem echo-zódik).

### (d) A `CODEX_HOME`/`CLAUDE_CONFIG_DIR` átirányíthatósága támadó-vezérelt könyvtárba — NOTE (a bizalmi határ TISZTELETBEN tartva)

A `config_dir` a registry 3. oszlopából jön, `~`-bővítéssel, és a
`selfheal_engine_is_available` (`710:717`) `[ -d "$config" ]`-t követel (és az
auth-fájl olvashatóságát, ha nem `-`). Egy támadó, aki egy registry-sort a saját
`/tmp/evil`-jére mutatna ÉS a `bypassPermissions`/`danger-full-access` mellé
tenné, **már rendelkezne** (i) commit-joggal a repóhoz ÉS (ii) fájlírással a boxon
— vagyis már kód-futtatással a gépen. A `config_dir`-választás tehát **nem ad új
képességet** a meglévő „ki commitolhat + ki írhat a boxra" határon túl; a határ
tiszteletben tartva, nincs priv-eszkaláció. NOTE.

---

## 3. Termékhatárok (AGENTS.md §5) és prompt-injekció

- **Nyers audio/kamera-frame:** N/A — ez CI/CD infra (bash driver), nem a szállított Flutter-app.
- **Rejtett hálózati kérés / consent:** a MiniMax-endpoint nem ÚJ provider — a `minimax` már a registry (ADR 0140) operátor-választott, saját API-kulccsal beállított motorja volt, eddig implementerként. Ez a kör csak ANNYIT változtat, hogy a `minimax` az utolsó **heal**-kísérletnél is választható. A kimenő adat (repo-diff, teszt-kimenet, halt-aláírás) fajtája nem változik, csak a mikor; nincs ÚJ egress-határ átlépve. NOTE-szinten megjegyzem: az utolsó heal-kísérletnél a repo-kontextus egy nem-Anthropic providerhez (MiniMax) juthat, ha az a motor kerül kiválasztásra — ez a meglévő több-motoros terv velejárója, nem itt bevezetett.
- **Prompt-injekció (a `{{ENGINE_CONTEXT}}` behelyettesítés, `1229`):** az
  `$engine_note` (`1206/1209/1212`) csak **registry-vezérelt motor-neveket**
  (`sonnet-impl`, `terra`, `minimax`…) + fix magyar szöveget interpolál —
  NEM szabad-szövegű külső tartalmat. A `sed s|…|$engine_note|g` a jelenlegi
  motor-nevekkel biztonságos (nincs `|`/`&`/`\` metakarakter). A rendered prompt
  az előző `.pipeline/heal-*.log` naplókat **adatként/bemenetként** utasítja
  olvasni („ezek bemenetek a diagnózishoz"), nem utasításként — nem vezet be új
  injekciós felületet. (Defense-in-depth: egy `&`/`\`/`|`-t tartalmazó JÖVŐBELI
  motor-név a sed-behelyettesítést elronthatná — committer-határ, NOTE.)
- **Secret/kulcs a fixture-ben:** a `test_selfheal_escalation.py` registry-fixture
  minden sora `auth_env=-`, `auth_file=-` — **nincs valódi kulcs, nincs valódi
  auth-fájl hivatkozva**; a fixture valóban fake. A `check_secrets.dart` szemantikai
  megfelelője: a teszt a `run_selfheal_session`-t STUB-olja, ezért a valódi
  MiniMax-token-ág **nincs automata teszttel fedve** — ez lefedettségi hézag
  (NOTE), nem sebezhetőség; magam olvasással verifikáltam az ágat (1. szakasz).

## 4. A halt-emlékeztető throttle biztonsági iránya — helyes (fail-safe)

A `halt_reminder_due` (`758:781`) több `return 0` (= „küldd MOST") fail-open ágat
tartalmaz (parse-hiba a `halted_at`-nál `763`, nem-szám konfig `764/765`, hiányzó/
rossz emlékeztető-fájl). Ez a **helyes** irány: a halt-emlékeztető **biztonsági/
figyelmeztető** jelzés; hiba esetén a degradáció a RÉGI (minden firingnél értesít)
viselkedés felé mutat, nem a néma elnyomás felé. A `KIMERÜLT` naplósor minden
firingkor megmarad (`1185`). A 24 órás felső korlát után az emlékeztető elhallgat
— ez a kör kifejezett, dokumentált szándéka (`PIPELINE_HALT_REMINDER_MAX_H`), nem
biztonsági hiány. Nincs rejtett hálózati kérés, nincs elnyelt halt.

---

## 5. Amit végignéztem, és a bizonyíték (az üres lelet is bizonyíték)

| Vizsgált felület | Bizonyíték | Eredmény |
|---|---|---|
| Token argv-ben | `807:812` runner-string indirekt `${VAR:-}` | nincs (érték futásidőben) |
| Token echo-zva a naplóba | `577:579` PTY-echo literál + captured `$(...)` + nincs `set -x` | nincs |
| Token stderr-en (`engine-profile.sh env`) | `309:335` success-ág csak stdout | nincs |
| Titok commitba | `.gitignore:3,74–75`, `git ls-files .pipeline` = 0 | strukturálisan zárt |
| Runner-string quoting/injekció | `807/824` (több idézőjel, mint `855/881`), registry-mezők `[a-z0-9./~-]` | committer-határ, ma zárt |
| Hardcoded MiniMax URL clobber | `811/812` komplementer az eval-lel, minimax = egyetlen nem-natív claude sor | ma helyes, latens footgun |
| `CODEX_HOME`/`CLAUDE_CONFIG_DIR` átirányítás | `716` `[ -d ]` + auth-check, committer-határ | határ tiszteletben |
| Prompt-injekció `{{ENGINE_CONTEXT}}` | `1206/1209/1212/1229` registry-nevek + fix szöveg | nincs új felület |
| Teszt-fixture valódi kulcsa | `test_…py` minden sor `auth_env=-`/`auth_file=-` | fake, nincs titok |
| Throttle fail-irány | `758:781` fail-open a küldés felé | fail-safe |

**Verdikt: PASS.** A hitelesítés/kulcs-kezelő út — a review kötelezővé tételének
oka — bizonyítottan nem szivárogtat titkot logba/argv-be/commitba, és a
trust-boundary (git-commit) mindenütt tiszteletben van tartva. A 6 NOTE mind
előre-mutató (a legfontosabb: a hardcoded MiniMax-endpoint általánosítása a
következő nem-natív felhő-motor bekötése ELŐTT). A merge biztonsági okból nem
blokkolt.

---
*Reviewer: `security-reviewer` ágens · READ-ONLY (AGENTS.md §15.1) · Dátum: 2026-08-19 · A jelentés a `docs/execution/09-review-report.md` szerkezetét követi. Titok soha nem került a jelentésbe — csak a helye.*
