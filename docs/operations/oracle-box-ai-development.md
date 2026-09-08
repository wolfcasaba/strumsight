# Az Oracle ARM box mint AI-fejlesztő gép — helyzetkép és ajánlás (2026-09-08)

> **Miért készült:** a user kérdése — *„hogy lenne a legjobb fejleszteni
> applikációkat AI-al az Oracle szerveremen"*. Ez a lap a repó SAJÁT mérési
> adatait (ADR-ek, LESSONS, HANDOFF) veti össze a 2026 szeptemberi külső
> tényekkel, és rangsorolt teendőket ad. Egy remote Claude Code konténerből
> íródott, ahol a boxra mutató híd-session indítása le volt tiltva — ezért a
> §4 ellenőrző parancsait a boxon a usernek kell lefuttatnia.

## 1. Amit a box-ról MÉRTÜNK (repó-forrás)

| Tény | Forrás |
|---|---|
| Oracle Ampere A1, `linux_arm64`, Ubuntu; hostnév-prefix `free-tier-arm` | `docs/baseline/epic-01-start.md`, `docs/execution/remote-container-environment.md` §6 |
| **4 OCPU / 24 GB RAM / 4 Gbps** — a user az OCI konzolból megerősítette **2026-09-08-án** (a repó 2026-08-05-i mérése: 4 mag, 23 GB, ~11 GB szabad, 77 GB lemez) | user-közlés 2026-09-08; ADR 0171 §„A box" |
| teljes `flutter test` **~15 perc** a boxon vs **4–5 perc** CI-ban (x86) | ADR 0053 |
| `flutter analyze && flutter test` láncolva → **OOM** | L05, CLAUDE.md |
| **Nincs lokális APK-build**: ARM64 Linux hoston a Flutter nem szállít `linux-arm64` host `gen_snapshot`-ot → az APK CSAK CI-ből jön | ADR 0052/0053; upstream: flutter/flutter #189724 |
| `flutter analyze` „Too many open files" — `fs.inotify.max_user_instances` kimerülés elárvult `tail` processzektől | L142, L144 |
| a tmux-szerver túléli a kört és env-változót/FD-t szivárogtat; a crontab `PIPELINE_ORCH_SWAP_ENGINE=minimax`-ot exportál | L312, L313, ADR 0307 §1.3.1 |
| Codex OAuth refresh-token „already used" 401 → API-kulcs állította helyre | L314 |
| `bwrap` (Codex `workspace-write` sandbox) a boxon nem megy → a wrapperek `danger-full-access` + külön klón-izoláció | L32, L43, `sdd-round-driver` §3 |
| medián kör-idő **82 perc**, halt-állás a naptári idő **~27 %-a** | ADR 0307 §1 |
| A remote Anthropic-konténer NEM tud Flutter SDK-t letölteni (403) és `gh`-t hitelesíteni → a valódi munka helye a box VAGY a CI | `docs/execution/remote-container-environment.md` §1–3 |
| Claude Code híd-environment a boxhoz: `env_012yGf199STmScPWnikMieeY` (`kind=bridge`, 2026-08-19) | uo. §6 |

A motorpark (`docs/execution/engine-registry.tsv`, ADR 0140): Codex CLI
(`gpt-5.6-terra`), MiniMax M3 (Claude Code harness, `~/.claude-minimax`), a
Kilo-család, `sonnet-impl` (Claude CLI), és az `engine=auto` router (ADR 0088).
A lánc cron-ból (5 percenként) + tmux-ból fut (ADR 0087/0307).

## 2. Külső tények (2026. szeptember)

### 2.1 Az Oracle felezte az Always Free A1 keretet — EZ A LEGSÜRGŐSEBB

- **2026-06-15-től** az Always Free A1 keret **4 OCPU / 24 GB → 2 OCPU / 12 GB**
  (havi 3 000 → 1 500 OCPU-óra, 18 000 → 9 000 GB-óra). Nyilvános bejelentés
  nem volt, csak a doksi frissült; e-mail szerint a **2026-08-18 után** a keret
  fölött járó Always Free példányokat **leállítják/törlik**.
- A **Pay-As-You-Go**-ra váltott fiókok — a beszámolók szerint — megtartják a
  4 OCPU / 24 GB-ot ingyen, de a support és a doksi ellentmondó („all
  tenancies" vs „csak free-tier fiókok"), ezért a PAYG fiókon is érdemes a
  számlázást figyelni.
- Fizetős A1 ár: **$0,01 / OCPU-óra + $0,0015 / GB-óra**, minden régióban.

Források: [InfoQ](https://www.infoq.com/news/2026/07/oracle-cloud-free-tier-limits/),
[TerminalBytes](https://terminalbytes.com/oracle-cloud-free-tier-changes-2026/),
[Linuxiac](https://linuxiac.com/oracle-quietly-cuts-free-tier-ampere-a1-resources-in-half/),
[Oracle Always Free Resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm),
[Oracle A1 árlap](https://www.oracle.com/cloud/compute/arm/).

**Mit jelent nekünk:** a box 2026-09-08-án — három héttel a 08-18-i
határidő UTÁN — még mindig **4 OCPU / 24 GB**-on fut (user-megerősítés). Ez két
dolgot jelenthet: (a) a fiók már **Pay-As-You-Go** (akkor a beszámolók szerint
a 4/24 ingyen marad, de a számlát figyelni kell), vagy (b) Always Free fiók,
amelyen az Oracle még nem hajtotta végre a leállítást — ez esetben a példány
bármikor törlés-jelölt. **A §4/0 lépés ezért a fiók-típus ellenőrzése a
konzolban, nem a shape-é** (a shape-et már tudjuk). A lánc RAM-fedezete
slotonként 6 GB (`PIPELINE_MIN_FREE_GB_PER_SLOT`, ADR 0171), az OOM-csapda már
24 GB-nál is él — **12 GB-on a jelenlegi gate nem férne el**, tehát a 4/24
megtartása nem kényelem, hanem a pipeline működési feltétele.

| Opció | OCPU / RAM | Havi ár (730 h) | Megjegyzés |
|---|---|---|---|
| Always Free (új keret) | 2 / 12 GB | $0 | a mai pipeline-nak kevés; egy slot, kisebb gate |
| PAYG fiók, free kereten belül | 4 / 24 GB | $0 (beszámolók szerint) | a MAI állapot megtartása; „out of capacity" és idle-reclaim gond is enyhül |
| PAYG, fizetve | 4 / 24 GB | ≈ $55 | 4·0,01 + 24·0,0015 = $0,076/h |
| PAYG, fizetve | 8 / 48 GB | ≈ $111 | 2 párhuzamos kör (`PIPELINE_SLOTS=2`) RAM-fedezettel |

### 2.2 Claude Code a boxon: Remote Control (van), self-hosted runner (nincs)

- **Remote Control** — *minden csomagon* elérhető (Pro/Max is). `claude
  remote-control` szerver-módban több sessiont szolgál ki egy processzből, a
  gép nem nyit bejövő portot (kimenő HTTPS polling). **A processznek élnie
  kell**: SSH-bontás után csak `tmux`/`screen` alatt marad meg; leállás után
  ~4 óráig `claude remote-control --continue`-val visszahozható. A boxon ma
  élő `free-tier-arm:music-theory` híd pontosan ez.
  [Doksi](https://code.claude.com/docs/en/remote-control).
- **Self-hosted environments** (runner, amit a claude.ai felületről bármely
  session megcéloz) — **csak Team/Enterprise, public beta**, egyéni fiókon nem
  opció. [Doksi](https://code.claude.com/docs/en/self-hosted-environments).
- **Anthropic-felhő konténer**: Flutter SDK-t nem tud letölteni (403), `gh`-t
  nem tud hitelesíteni → csak brief/doksi/`tools/tests` munkára jó (§1).

### 2.3 Codex CLI headless

`codex exec` a nem-interaktív mód (stderr = folyamat, stdout = végső üzenet).
Headless/szerver környezetben az ajánlott hitelesítés az **API-kulcs**, nem a
ChatGPT-OAuth — pontosan az L314-es refresh-token-hiba ellenszere. A Linux
sandbox Landlock/bwrap alapú; a boxon a bwrap nem megy (L43), ezért marad a
klón-izoláció. A CLI alapmodellje 2026-09-03-tól változott (a repó
nyilvántartása `gpt-5.6-terra`-t pinnel — `codex --version` + a profil
`model` mezője ellenőrizendő frissítés után).
[Codex exec CI-guide](https://www.developersdigest.tech/blog/codex-exec-ci-headless-guide),
[Codex CLI guide 2026](https://www.aibuilderclub.com/blog/codex-cli-guide-2026).

### 2.4 GitHub Actions — a nehéz munka helye marad

- A `wolfcasaba/strumsight` **publikus** repó → GitHub-hostolt runnerek
  ingyenesek, az **arm64** (4 vCPU) hostolt runner is GA publikus repókra.
- 2026-03-01-től a **self-hosted** runnerek orchestration-díjat kapnak
  (publikus repóban továbbra is ingyenes) — a boxot runnernek használni így
  sem érné meg: lassabb, mint a hostolt x86, és a RAM-ot vinné.
  [arm64 GA](https://github.blog/changelog/2025-08-07-arm64-hosted-runners-for-public-repositories-are-now-generally-available/),
  [2026-os árváltozás](https://theplatformengineering.substack.com/p/github-actions-2026-pricing-changes).

### 2.5 Lokális LLM az A1-en — nem kódoló-motor

CPU-only A1-en 4 OCPU-val egy 7B Q4 modell **5–8 token/s**, 13B **3–4
token/s**; 2 OCPU-n ennek fele. Implementer-motornak használhatatlan; legfeljebb
embedding/RAG-segéd. Az API-alapú motorpark (MiniMax M3, Codex, Claude, Kilo)
marad. [Mérés](https://tiffena.me/blog/ai-infrastructure/benchmark-cpu-only-llm-inference-oracle-ampere-a1-llama.cpp-ollama-docker/),
[OCI free-tier LLM guide](https://blog.easecloud.io/ai-cloud/launch-oracle-cloud-llms-in/).

## 3. Ajánlás — rangsorolva

1. **Ma: fiók-típus ellenőrzés** (§4/0) — a shape már ismert (4/24). Ha a
   fiók Always Free: váltás PAYG-ra (a keret alatt $0; utána állíts $1-es
   számlázási riasztást, hogy egy esetleges A1-túlszámlázás azonnal
   látszódjon), különben a példány törlés-jelölt. Ha már PAYG: nincs teendő,
   csak a havi számla figyelése. Ha valaha 2/12-re esne: dönteni a §2.1
   táblából — a ~27 % halt-idő és a 82 perces kör mellett
   a $55/hó 4/24 a legolcsóbb tényleges gyorsítás (ADR 0171 §„A box" is ezt
   mondta: „a legolcsóbb lineáris gyorsítás a több RAM/mag").
2. **Szerepmegosztás marad:** box = orchestrálás + könnyű gate (format,
   analyze, célzott tesztek) + implementer-motorok; **CI = teljes suite,
   property gate, APK** (ADR 0053). APK-t ARM64 hoston ne is próbálj (Flutter
   #189724) — ha valaha kellene lokális APK, az egy x86 VPS, nem ez a gép.
3. **Memória-higiénia a boxon** (mind mért gyökérokra, L05/L142/L144):
   zram-swap (pl. 8 GB, `vm.swappiness=100` zram-mal), a gate futtatása
   `systemd-run --scope -p MemoryMax=…` alatt (az OOM a gate-et ölje, ne a
   drivert), `fs.inotify.max_user_instances=1024` +
   `max_user_watches=1048576` tartósan `/etc/sysctl.d/`-ben, és egy
   ütemezett „reaper" az elárvult `tail`/deleted-cwd `dart` processzekre
   (ez az L144-ben nyitva hagyott follow-up).
4. **Felügyelet cron+tmux helyett systemd user-service-ekkel**
   (`loginctl enable-linger ubuntu`): a Remote Control szerver
   (`claude remote-control`) és a lánc-driver külön unit, tiszta
   környezettel — megszűnik a tmux-szerver env-/FD-szivárgása (L312/L313) és a
   soha le nem járó crontab-override.
5. **Hitelesítés headless-módra:** Codex API-kulccsal (L314), Claude a
   boxon `claude`-loginnal (a Remote Controlhoz ez kell, API-kulcs nem
   elég). Kulcs csak `0600` fájlban, sosem crontab-sorban.
6. **Motorpark:** a MiniMax-first router (ADR 0088) és a visszakapcsolható
   profilok (ADR 0140) jók; frissítés után a Codex-alapmodell változását a
   registry `model` oszlopával ellenőrizd. Lokális LLM-re ne költs időt (§2.5).
7. **Új app ugyanígy:** a „gyár" újrafelhasználható — AGENTS.md +
   kör-brief + engedélyezett-fájllista + `round-gate.sh`-szerű artefaktum-gate
   + CI mint evidencia + Remote Control híd. A `free-tier-arm:Recipewiser`
   híd ugyanezen a boxon már így fut.

## 4. Ellenőrző parancsok a boxon (mind read-only)

```bash
# 0) Fiók-típus — az OCI konzolban: Billing & Cost Management → Upgrade and
#    Manage Payment: „Always Free" vs „Pay As You Go" — ez dönti el az 1. teendőt.
#    Plusz: Governance → Limits → Compute → „Ampere A1 Flex" OCPU/memória limit
#    (Always Free fiókon 06-15 óta 2 OCPU / 12 GB-nak KELLENE lennie).
# 1) OCI shape (a user 2026-09-08-án megerősítette: 4 OCPU / 24 GB / 4 Gbps)
curl -s -H "Authorization: Bearer Oracle" http://169.254.169.254/opc/v2/instance/ \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["shape"],d["shapeConfig"],d["region"])'
nproc; free -h; swapon --show; df -h /
# 2) a mért csapdák állapota
sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches vm.swappiness
pgrep -c tail; pgrep -c dart; ps -eo pid,etimes,rss,comm --sort=-rss | head -15
tmux ls; crontab -l | sed -E 's/(KEY|TOKEN|SECRET)=[^ ]+/\1=<redacted>/g'
# 3) motorok és verziók
codex --version; claude --version; flutter --version | head -1
cd /home/ubuntu/music-theory && tools/engine-profile.sh list
# 4) híd
ps -ef | grep -c '[c]laude remote-control'
```

A kimenetet érdemes `docs/operations/oracle-box-probe-<dátum>.md`-be
menteni, hogy a következő session mért tényből induljon (L09: a mérce
artefaktum, nem prompt-szöveg).

## 5. Laptop (VS Code) vagy az Oracle box? — a kettő nem egymás helyett van

A user kérdése (2026-09-08): *„szóval nem jó app-fejlesztéshez, jobb lenne a
laptopom VS Code-dal?"* A válasz: **más munkára valók.**

| Munka | Laptop + VS Code + Claude Code/Codex | Oracle box (4 OCPU / 24 GB ARM) |
|---|---|---|
| interaktív fejlesztés, hot reload, valódi telefonon próbálás | ✅ ez a természetes helye | ❌ nincs kijelző, nincs USB-eszköz |
| APK build, emulátor | ✅ x86/Apple Silicon hoston megy | ❌ ARM64 Linux hoston nem (Flutter #189724) |
| gyors `flutter test` | ✅ (egy mai laptop többszörös sebességű) | ⚠ ~15 perc a teljes suite |
| 24/7 automata kör-lánc (cron + tmux, éjjel is dolgozik) | ❌ csukott laptop = leáll | ✅ **ez az igazi értéke** |
| több motor párhuzamos, izolált klónokban | ⚠ RAM-tól függ | ✅ 24 GB-on 1 slot, 48 GB-on 2 |
| Remote Control a telefonról bárhonnan | ⚠ csak ha ébren van | ✅ mindig elérhető |
| teljes suite + property gate + APK evidenciája | CI | CI (ADR 0053 — egyik gépen sem) |

**Ajánlott felállás:** a laptop az *ember* gépe — ott futtatod a valódi
gitáros APK-tesztet, a hot reload-os UI-munkát, és onnan írod a
kör-briefeket VS Code-ban; a box a *gyár* — a cron-vezérelt kör-lánc, a
motor-profilok, a Remote Control híd. Az összekötő elem a git + a CI: a
laptop és a box ugyanazt a branch-et és ugyanazt a `round-gate.sh`
artefaktumot használja, a bizonyíték mindkettőnél a CI-run link.

Ha CSAK egy gép maradhatna: egy 16+ GB-os x86/Apple Silicon laptop az
interaktív fejlesztésre jobb, de az éjjel-nappal futó automata lánc elveszne —
azt a box adja, és az a StrumSight 600+ PR-jának a motorja volt.
