# E99-R08 (GOV-07) — Körönként kulcsolt orchestrátor-rotáció és biztonságos force-push

- **Státusz:** READY FOR IMPLEMENTATION (pre-flight rev. 1 lezárva 2026-08-13, `main @ ac75f91a`)
- **Típus:** **governance-kör** — a lánc SAJÁT infrastruktúrájának javítása, nem terméki viselkedés
- **Kör-azonosító:** `E99-R08`. Az `E99` a governance-körök fenntartott
  pszeudo-epic kódja (nem valódi epic). Emberi neve **GOV-07**.
- **Branch:** `sonnet-impl/e99-r08-gov-07-per-round-orchestrator-rotation`
- **Előfeltétel:** `E06-R23` merge-elve (PR #241, `d5a95e44`)
- **Brief szerzője:** Claude (Opus 5) · **Implementáció:** Codex (Terra)
- **Előre kiosztott ADR:** [`0242`](../adr/0242-per-round-orchestrator-rotation-and-safe-force-push.md)
  — **MÁR MEGÍRVA az orchesztrátor által, a `docs/adr/` a TILOS zónában van.**
  Az ADR 0242 **felülírja** az [ADR 0087](../adr/0087-autonomous-round-pipeline.md)
  §2 **H8-sorának szövegét**, és **kiegészíti** az
  [ADR 0222](../adr/0222-orchestrator-rotation-and-session-budget-gauge.md)
  rotációs szabályát. Az ADR 0087/0222 minden más döntése érvényben marad.
  **Az ADR 0087 fájlját tilos szerkeszteni** — az merge-elt ADR, a módosítása H1.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "tools/round-pipeline.sh",
  "tools/safe-force-push.sh",
  "tools/tests/test_orchestrator_rotation.py",
  "tools/tests/test_round_resume_independence.py",
  "tools/tests/test_safe_force_push.py",
  "docs/execution/pipeline-orchestrator-prompt.md",
  "docs/rounds/e99-r08-gov-07-per-round-orchestrator-rotation.md",
]
gate_tests = [
  "test/tooling/architecture_allowlist_guard_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight rev. 1 — 2026-08-13

- **Mért bázis:** `origin/main` és a munkapéldány `HEAD` egyaránt
  `ac75f91a4744ef8d6a824e98f1e290aa8cb6eb57`; a fő munkafa tiszta, nincs
  korábbi E99-R08 munkapéldány vagy nyitott E99-R08 PR.
- **ADR-feloldás:** az előre kiosztott ADR 0242 már a `4d2ff973` commitban
  létrejött; a `tools/round-slots.py reserve-adr --round E99-R08` már 0244-et
  ad vissza. Az ADR 0242 ezért változatlan, a tiltott `docs/adr/**` zónához
  nem nyúlunk.
- **Ág-identitás feloldása:** a korábbi `codex/…` ág-név ellentmondott a §5.2
  szerződésének: folytatáskor az ág-prefix a commitolt implementer, miközben
  e kör implementere `sonnet-impl`. A branch ezért `sonnet-impl/…`; ez teszi
  lehetővé a D2 mérését és nem adja ki a Terra-orchestrátornak a saját
  identitását implementerként.
- **Kódmérés:** `tools/round-pipeline.sh` ma egyetlen
  `$state_dir/orchestrator-last` fájlból dönt (`next_orchestrator`, 469–485),
  és minden dispatch végén felülírja (1516); a `resolve_independent_engine`
  (1071–1101) nem olvas kör-ágról. A `--next-orchestrator` argumentum nélküli
  teszthorga megvan (1138–1139). A `safe-force-push.sh` még nem létezik.

> A `gate_tests` **csak `test/` alatti Dart útvonalat fogad**
> (`tools/ai_router/brief.py:39`), a kör diffjében viszont **nulla Dart sor**
> van. A választott cella ezért **fa-egészség őr**, nem a kör saját mércéje: a
> `tools/` átrendezése ne törje meg az architektúra-allowlistát.
> **A kör TÉNYLEGES teszt-mércéje** a `python3 -m pytest tools/tests -q`
> (lokálisan) és a **Router CI** (`.github/workflows/router-ci.yml:66`, ami a
> `tools/tests/**` útvonalra indul) — lásd §7.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

2026-08-13-án az `E06-R23` **kétszer** állította meg a láncot, összesen
**4 óra 45 percre**, miközben a kör munkája végig kész és gate-zöld volt.
Egyik halt sem kódhiba volt: **mindkettő a lánc saját infrastruktúrájának
defektje.** Ez a kör azt a két defektet javítja, plusz a harmadikat, ami a
másodikat majdnem adatvesztéssé fokozta.

**Ez orchesztrátor-oldali hiba, nem implementer-hiba.** Az `E06-R23`
implementere pontosan azt szállította, amit a briefje kért; a review és a
security review is APPROVED lett. A lánc a KÉSZ munkát nem tudta átvinni.

## 2. Jelenlegi állapot — a defektek mérve

### 2.1 Ami ÉRVÉNYES és nem változik

- Az [ADR 0222](../adr/0222-orchestrator-rotation-and-session-budget-gauge.md)
  **rotációs elve** helyes: a körök felét a Terra vezényli, olyankor a Claude
  implementál. A defekt nem az elvben van, hanem az **állapot kulcsolásában**.
- Az [ADR 0138](../adr/0138-factory-hardening-scope-guard-and-independence.md)
  **függetlenségi követelménye** helyes és marad: az orchestrátor/reviewer nem
  lehet ugyanaz az identitás/kvóta, mint az implementer.
- A `H-INDEP` **nem önjavítható** (ADR 0138 S4) — ez is marad. A kör célja nem
  az, hogy a self-heal eldönthesse, hanem hogy a helyzet **elő se álljon**.
- Az `engine_uses_claude_quota()` (`tools/round-pipeline.sh:1064`) mérése helyes:
  `harness == claude` ÉS nincs saját `auth_env` → az előfizetéses keretet fogyasztja.
  Ezt a függvényt **használni kell**, nem újraírni.
- A `tools/round-gate.sh` és a `.github/` **érintetlen** (H-GATEGUARD).

### 2.2 D1 — a rotációs állapot GLOBÁLIS, nem körönkénti

`tools/round-pipeline.sh:1516` **minden dispatchnél** felülírja a rotáció
állapotát, a kör azonosítójától függetlenül:

```bash
printf '%s\n' "$orchestrator" > "$orch_last_file"     # :1516
```

`next_orchestrator()` (`:469-485`) pedig ugyanezt az **egyetlen, globális**
fájlt olvassa (`:481`), és `alternate` módban egyszerűen billen:

```bash
if [ "$last" = "claude" ]; then printf 'terra\n'; else printf 'claude\n'; fi
```

Következmény: **ha egy kör közben elhasal és újraindul, a második dispatch a
MÁSIK orchestrátort kapja** — pedig ugyanaz a munkadarab, aminek az
implementere az ágon már rögzült.

**Mért eset (`.pipeline/halted-20260813T040134.txt`):**

```
round=E06-R23
halt=H-INDEP
summary=... this orchestrator session is Claude -- same ~/.claude identity/quota
        as the sonnet-impl implementer per ADR 0222 -- so it cannot serve as the
        independent reviewer ADR 0222/0138 require; human decision needed on who reviews.
```

Az eseménylánc mérve: az eredeti dispatch `orchestrator=terra` +
`implementer=sonnet-impl` volt (helyes pár) → a session `H3`-ra elhalt → a
self-heal javította (PR #240) → az **újraindítás a globális flip miatt
`orchestrator=claude`-ot adott**, miközben az ágon már `sonnet-impl`
(ugyanaz a `~/.claude` kvóta) commitolt. Nincs független reviewer → `H-INDEP`.

**Állásidő: 4 óra 35 perc** (2026-08-12T23:30:06 → 2026-08-13T04:05:06),
végig kész, gate-zöld munka fölött.

### 2.3 D2 — a folytatás soha nem validálja újra a függetlenséget

`resolve_independent_engine()` (`:1071-1101`) **kizárólag friss dispatchre**
old fel implementert: a queue-motorból és az orchestrátorból számol. A
függvény **nem tud** arról, hogy a körnek lehet már **commitolt** implementere.

```bash
resolve_independent_engine() {   # $1=queue-motor [$2=orchestrátor]     # :1071
```

Ezért a konfliktus **pre-flightban nem detektálható**: a driver vidáman
elindítja a sessiont, és a felismerés az orchestrátor-session ítéletére marad —
ami a legdrágább hely, ahol kiderülhet.

**Reprodukció (mérve, ma):**

```bash
tools/round-pipeline.sh --independent-engine terra claude    # → "terra"
```

Az eszköz maga **soha nem választana `sonnet-impl`-t egy `claude`
orchestrátorhoz** — mégis pontosan az volt az ágon.

**Az identitás mérhető:** a kör-ág prefixe a motor neve
(`sonnet-impl/e06-r23-…`, `minimax/e05-r15-…`), a
`docs/execution/engine-registry.tsv` `name` oszlopával azonos kulcson. A
folytatáskori újravalidálásnak **van** bemenete; ma csak senki nem olvassa.

### 2.4 D3 — a H8 szerződése nem fedi a valóságot, és a téves diagnózis majdnem adatvesztést okozott

A második halt (`.pipeline/halted-20260813T044434.txt`):

```
halt=H8
summary=Rebase origin/main-re konfliktus nélkül sikerült (059e4e3), de az új history
        pushához szükséges --force-with-lease a branch-szabály szerint külön engedélyt
        igényel és a távoli referencia elutasította ...
```

**Három mérhető baj ebben az egy sorban:**

1. **A H8 szerződése nem illik rá.** Az
   [ADR 0087](../adr/0087-autonomous-round-pipeline.md) §2 és a
   `docs/execution/pipeline-orchestrator-prompt.md:293` egyaránt így definiálja:
   *„a `main` a dispatch óta mozdult, **és a rebase konfliktust ad**"*. A mai
   rebase **konfliktus nélkül sikerült** — a halt egy olyan kód alatt született,
   aminek a feltétele nem teljesült.
2. **A „branch-szabály" nem létezik.** Mérve: `gh api repos/:owner/:repo/rulesets`
   → `[]`; a branch-protection végpont 403-at ad, mert a PAT nem látja — ez nem
   tiltás, hanem láthatatlanság. A push **nem GitHub-tiltáson bukott**, hanem a
   git saját lease-ellenőrzésén (`stale info`).
3. **A javasolt feloldás adatvesztő lett volna.** A halt `detail` mezője ezt
   ajánlotta: *„fetch pontos remote-tracking ref, majd `--force-with-lease` push"*.
   A remote **közben előrement**: a session 04:38:41-kor pusholta a security
   review-t (`27bce64`, `docs/reviews/…-security.md`, 55 sor), a rebase viszont
   a KORÁBBI állapotból készült. A javaslat szó szerinti végrehajtása
   **eldobta volna a security review commitot** — épp azt a dokumentumot, ami a
   kör egyik merge-feltétele.

A helyes feloldás (ma kézzel, patch-id-vel ellenőrizve) az volt, hogy előbb
`cherry-pick 27bce64` a rebaseelt HEAD-re, és csak azután push explicit
lease-szel. A bizonyíték: a kör diffje a régi (`0869fd36`) és az új
(`origin/main`) bázison **bájtra azonos**, 181 618 B mindkettő.

**Ma a repóban `force-with-lease` egyetlen scriptben sem szerepel:**

```bash
grep -rn "force-with-lease" tools/ docs/execution/*.md   # → nulla találat
```

A rebase-és-push tehát **ad-hoc, sessiononként újra kitalált** művelet. Ez
pontosan az a hibaosztály, amire a `docs/LESSONS.md` L09 tanulsága szól: **a
szöveges előírás nem tart, a mérce futtatható artefaktum kell hogy legyen.**

### 2.5 Az eszközök a javításhoz — MÁR MEGVANNAK

- `PIPELINE_STATE_DIR` (`tools/tests/test_orchestrator_rotation.py:39`) — az
  állapotkönyvtár injektálható, tehát a rotáció **hermetikusan tesztelhető**,
  hálózat és tmux nélkül.
- Kiexportált teszthorgok: `--next-orchestrator` (`:1138`),
  `--independent-engine` (`:1126`), `--orchestrator-engine` (`:1130`).
- `engine_registry_row()` + `engine_uses_claude_quota()` (`:1064`) — az
  identitás-összevetés kész építőköve.
- A `git` lokális bare-repókkal teljes push/lease-szemantikát ad, tehát a
  force-push protokoll is **hálózat nélkül** tesztelhető.

## 3. Scope

**Benne van:**

1. A rotációs állapot **körönkénti kulcsolása**, hogy egy kör másodszori
   dispatchje ugyanazt az orchestrátort kapja.
2. A függetlenség **folytatáskori újravalidálása** az ágon már commitolt
   implementer-identitás ellen, **dispatch ELŐTT**.
3. `tools/safe-force-push.sh` — futtatható artefaktum a rebase utáni pushra,
   ami **megtagadja** a pusht, ha a remote-on olyan commit van, ami nálunk nincs.
4. A `docs/execution/pipeline-orchestrator-prompt.md` frissítése: a H8-sor
   pontosítása és a force-push protokoll a scriptre mutatva.
5. Tesztek mind a háromra.

**NINCS benne (tilos):**

- A `H-INDEP` önjavíthatóvá tétele. Az ADR 0138 S4 tiltja, és **ez a kör sem
  oldja fel** — a cél a megelőzés.
- A `tools/round-gate.sh`, a `.github/**` és bármely teszt **gyengítése**
  (H-GATEGUARD → emberi döntés).
- A `docs/adr/**` bármely fájlja. Az ADR 0242-t az orchesztrátor MÁR megírta;
  az ADR 0087 merge-elt, a szerkesztése **H1**.
- Bármilyen Dart/`lib/`/`test/` változtatás. Ez a kör nulla terméki sort ír.
- A rotáció ELVÉNEK megváltoztatása (ki vezényel, milyen arányban) — az ADR 0222
  user-döntése, nem implementációs kérdés.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `tools/round-pipeline.sh` | D1 + D2: körönkénti kulcsolás, folytatáskori újravalidálás, új teszthorgok |
| `tools/safe-force-push.sh` | **ÚJ** — D3: a rebase utáni push futtatható protokollja |
| `tools/tests/test_orchestrator_rotation.py` | a meglévő rotációs mérés kiegészítése a körönkénti cellákkal |
| `tools/tests/test_round_resume_independence.py` | **ÚJ** — D2 guard-tesztjei |
| `tools/tests/test_safe_force_push.py` | **ÚJ** — D3 guard-tesztjei lokális bare repókon |
| `docs/execution/pipeline-orchestrator-prompt.md` | a H8-sor pontosítása + a force-push protokoll a scriptre mutatva |
| `docs/rounds/e99-r08-gov-07-per-round-orchestrator-rotation.md` | a §10 handoff kitöltése |

**Tilos zóna (a lista bármely elemének érintése → `stopped`):**
`docs/adr/**` · `tools/round-gate.sh` · `.github/**` · `lib/**` · `test/**` ·
`docs/execution/pipeline-queue.tsv` · `HANDOFF.md` · `docs/LESSONS.md`
(az utóbbi kettőt a merge után az orchesztrátor írja).

## 5. Kötött architekturális döntések (ADR 0242)

### 5.1 A kör orchestrátora a KÖRHÖZ rögzül, nem a lánchoz

Az állapot körönként kulcsolt: `<state_dir>/orchestrator-round/<ROUND>`. Az
első dispatch beírja a kör orchestrátorát; **minden további dispatch ugyanazt
olvassa vissza, léptetés nélkül.** A globális `orchestrator-last` **megmarad**,
és továbbra is az `alternate` léptetés hordozója — de **kizárólag ÚJ kör
indításakor** frissül.

**NEM elfogadható gyengítés:** „a második dispatch is léptet, de a
függetlenséget utólag ellenőrizzük". Ez a mai állapot egy réteggel odébb tolva:
a kör így is elveszítheti az eredeti orchestrátorát, és az `alternate` számlálás
is torzul minden elhalt körnél. A rögzítés a döntés, nem az utólagos ellenőrzés.

### 5.2 Folytatáskor az implementer-identitás az ágról MÉRT tény

Ha a körhöz tartozik már távoli ág (`git ls-remote --heads origin`, a
kör-slugra illesztve), akkor az ág **prefixe** a commitolt implementer neve, és
ezt a `docs/execution/engine-registry.tsv` `name` oszlopával kell feloldani.

A dispatch előtti ellenőrzés: az így mért implementer és a feloldott
orchestrátor **nem oszthat kvótát/identitást** (`engine_uses_claude_quota()`).

**Feloldási sorrend ütközéskor — kötött:**

1. a körhöz rögzített (5.1 szerinti) orchestrátor, ha az független;
2. ha nem: a registry bármely olyan motorja, amely a mért implementerrel nem
   oszt kvótát **és** elérhető;
3. ha nincs ilyen: `H-INDEP` — **fail-closed**.

**NEM elfogadható gyengítés:** az implementer átbillentése. Folytatáskor az
implementer **fix** (commitok vannak az ágon); a mozgatható szereplő az
orchestrátor. Aki az implementert billenti, az a kész diffet dobja el.

### 5.3 Ismeretlen ág-prefix → fail-closed

Ha az ág prefixe nem oldható fel a registryből (elgépelés, kézi ág, régi
konvenció), az **nem** „akkor biztos rendben van", hanem `H-INDEP`. A
függetlenség bizonyítandó, nem vélelmezendő.

### 5.4 A `--next-orchestrator` argumentum nélküli alakja VÁLTOZATLAN

A horgot a `tools/pipeline-status.sh` és a meglévő tesztek argumentum nélkül
hívják. Az új, kör-argumentumos alak (`--next-orchestrator E06-R23`) **kiegészítés**;
az argumentum nélküli hívás viselkedése bitre ugyanaz marad.

### 5.5 A force-push protokoll futtatható artefaktum, nem prompt-szöveg

`tools/safe-force-push.sh <branch>` kötelező lépései:

1. a **pontos** ref lefetchelése (`refs/heads/<branch>:refs/remotes/origin/<branch>`) —
   e nélkül a lease „stale info"-t ad, ami ma téves halt-diagnózist szült;
2. a **remote-only** commitok felsorolása patch-id alapon
   (`git log --cherry-mark --left-right <remote>...HEAD`, a `=` jelöltek kiszűrve);
3. ha van remote-only commit → **exit 3, a lista kiírásával, push NÉLKÜL**;
4. ha nincs → `git push --force-with-lease=<branch>:<a 2. lépésben MÉRT remote SHA>`.

**NEM elfogadható gyengítés:** sima `--force`, vagy argumentum nélküli
`--force-with-lease` (az a lokális remote-tracking refre támaszkodik, ami épp a
mai hibamód volt). A lease **mindig explicit, mért SHA**.

### 5.6 A H8 jelentése pontosítva (az ADR 0242 felülírja az ADR 0087 §2 sorát)

- **H8 marad:** a `main` mozdult ÉS a rebase **konfliktust** ad.
- **NEM H8:** a `--force-with-lease` elutasítása önmagában. Az a protokoll
  **első lépése**, nem a vége: fetch → remote-only vizsgálat → beépítés → push.
- **H8 lesz** viszont, ha a remote-only commitok beépítése **konfliktust** ad.

Az ADR 0087 fájlja **nem szerkeszthető** (H1); a szövegi pontosítás a
`docs/execution/pipeline-orchestrator-prompt.md:293` sorában történik, az
ADR 0242-re hivatkozva.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Egy kör MÁSODIK dispatchje ugyanazt az orchestrátort kapja, mint az első | `test_round_resume_independence.py::test_a_second_dispatch_of_the_same_round_keeps_its_orchestrator` |
| A2 | Egy ÚJ kör első dispatchje továbbra is léptet (`alternate`) | `test_orchestrator_rotation.py` új cellája |
| A3 | A folytatás a commitolt implementert az ág prefixéből méri | `::test_resume_reads_the_committed_implementer_from_the_branch_prefix` |
| A4 | Kvóta-ütközésnél az ORCHESTRÁTOR billen, az implementer nem | `::test_on_conflict_the_orchestrator_flips_not_the_implementer` |
| A5 | Ismeretlen ág-prefix → `H-INDEP`, nem csendes átengedés | `::test_unknown_branch_prefix_fails_closed` |
| A6 | `--next-orchestrator` argumentum nélkül változatlan | a meglévő `test_orchestrator_rotation.py` zölden marad, módosítás nélkül |
| A7 | `safe-force-push.sh` megtagadja a pusht remote-only commit esetén | `test_safe_force_push.py::test_it_refuses_when_the_remote_has_commits_we_lack` |
| A8 | A megtagadás **felsorolja** a veszélyben lévő commitokat | `::test_the_refusal_names_the_remote_only_commits` |
| A9 | Tiszta esetben a push explicit, MÉRT SHA-ra vett lease-szel megy | `::test_the_push_uses_an_explicit_lease_on_the_measured_remote_sha` |
| A10 | A patch-id azonos (rebaseelt) commitok NEM számítanak remote-only-nak | `::test_rebased_equivalents_are_not_treated_as_remote_only` |
| A11 | A `docs/execution/pipeline-orchestrator-prompt.md` H8-sora az 5.6 szerinti | a diff a §293 körüli sorokon |
| A12 | Nulla Dart sor a diffben | `git diff --stat origin/main...HEAD` — nincs `.dart`/`lib/`/`test/` útvonal |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A körönkénti fájl írása kimarad, marad a globális flip | A1 |
| A körönkénti fájl írása megvan, de a második dispatch mégis léptet (előbb ír, aztán olvas) | A1 |
| A körönkénti rögzítés ÚJ körre is visszaadja a régi értéket (a rotáció megáll) | A2 |
| Az ág-prefix helyett a queue `engine` oszlopát olvassa | A3 (a queue `minimax`-ot mond, az ágon `sonnet-impl` van) |
| Ütközéskor az implementert billenti át | A4 |
| Ismeretlen prefixnél fail-open (elfogadja az orchestrátort) | A5 |
| A horog szignatúrája kötelezővé teszi a kör-argumentumot | A6 |
| A push a remote-only vizsgálat ELŐTT megy ki | A7 |
| A megtagadás csak exit-kódot ad, listát nem | A8 |
| Sima `--force`, vagy argumentum nélküli `--force-with-lease` | A9 |
| A remote-only vizsgálat SHA-t hasonlít, nem patch-id-t | A10 (a rebase MINDEN commitot remote-only-nak látna, és soha nem engedne pusholni) |

**Rotáció — a három kötelező cella** (a „határ" itt a kör-azonosító azonossága;
a rögzítés **inkluzív**: a kör ELSŐ dispatchje már rögzít):

| Cella | Bemenet | Elvárt `--next-orchestrator <kör>` |
|---|---|---|
| első dispatch (a határon) | `orchestrator-last=claude`, `E06-R23`-hoz nincs rögzítés | `terra`, és rögzül |
| második dispatch (a határon belül) | `orchestrator-last=terra`, `E06-R23`-hoz `terra` rögzítve | `terra` — **nem** billen |
| új kör (a határon kívül) | `orchestrator-last=terra`, `E06-R24`-hez nincs rögzítés | `claude`, és rögzül |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** a körönkénti
rögzítést ideiglenesen vezesd vissza globálisra → az A1 cellának **PIROSNAK**
kell lennie → állítsd vissza. Ugyanez a `safe-force-push.sh` 3. lépésének
ideiglenes kivételével az A7-re. Ha a rontás nem pirosít, a teszt nem mér.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart
```

```bash
python3 -m pytest tools/tests -q
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05).

A `round-gate.sh` a `format` / `analyze` / `test` / `architecture` / `secrets` /
`l10n` lépéseket külön processzként futtatja; a teszt-cella itt fa-egészség őr
(§ai-router indoklása). **A kör saját mércéje a második parancs**, a
`pytest tools/tests`, amit merge előtt a **Router CI** is lefuttat a kör-ágon
(exact-SHA dispatch, Claude-oldal).

## 8. Implementációs sorrend

1. **Tesztek előbb** (RED): `test_round_resume_independence.py` és
   `test_safe_force_push.py` a §6 celláival, a `PIPELINE_STATE_DIR` +
   lokális bare repo mintára. Futtasd — pirosnak kell lennie.
2. D1: körönkénti kulcsolás a `round-pipeline.sh`-ban + a `--next-orchestrator`
   kiegészítése (5.4 szerint visszafelé kompatibilisen).
3. D2: a dispatch előtti újravalidálás az ág-prefixből, az 5.2 feloldási
   sorrenddel.
4. D3: `tools/safe-force-push.sh` + tesztek zöldre.
5. A `pipeline-orchestrator-prompt.md` H8-sora és a force-push protokoll.
6. Valódi-sértés próbák (§6.1), a §10-ben dokumentálva.
7. `tools/round-gate.sh` + `pytest tools/tests`.

## 9. Kockázatok

- **A futó driver saját magát írja át.** A `cron` a
  `/home/ubuntu/music-theory/tools/round-pipeline.sh`-t indítja, a bash pedig a
  scriptet **darabokban olvassa** — egy merge menet közben elronthat egy éppen
  futó példányt. Precedens van rá (PR #240 ugyanezt a fájlt módosította), de a
  merge-t az orchesztrátor **két firing közé** időzítse, és a merge után
  ellenőrizze a következő firing naplóját.
- **A körönkénti állapotfájlok felhalmozódnak.** Az `orchestrator-round/`
  könyvtár körönként egy sorral nő. Ez szándékos (audit-nyom), de a
  takarításnak a `.pipeline/archive` mintáját kell követnie, nem törölhet
  ÉLŐ kört.
- **Az ág-prefix konvenció nem univerzális.** Az `ops/*` ágak nem kör-ágak; a
  slug-illesztésnek elég szűknek kell lennie, hogy `ops/pipeline-throughput`
  soha ne illeszkedjen egy kör-azonosítóra. Ezt A5 méri.
- **`.pipeline` állapotot csak a fő munkafából szabad írni** (mérve 2026-08-06,
  L156): a worktree-ből írt állapot sikert jelez, de az éles lánc nem áll át.
  A tesztek ezért `PIPELINE_STATE_DIR`-t injektálnak, éles állapotot nem írnak.

## 10. Implementation handoff — Claude Sonnet 5 (sonnet-impl)

### 10.1 Fájlonkénti változás

- **`tools/round-pipeline.sh`**
  - Új állapot: `orch_round_dir="$state_dir/orchestrator-round"` és
    `round_remote=${PIPELINE_ROUND_REMOTE:-origin}` (a §5.1/§5.2 hordozói).
  - `next_orchestrator()` (D1): opcionális `$1=kör` paramétert kapott. Ha adott
    és `$orch_round_dir/$1` már létezik, a fájl tartalmát adja vissza
    LÉPTETÉS NÉLKÜL. Ha nem létezik, a régi (ADR 0222) logikával számol egy
    értéket, és — CSAK ha kör-argumentum volt — beírja mind a kör-fájlba, mind
    a globális `orch_last_file`-ba. Argumentum NÉLKÜL a függvény kimenete
    bitre azonos a D1 előttivel (a `--next-orchestrator` teszthorog és a belső
    hívások — `resolve_independent_engine`, `--orchestrator-engine` —
    változatlanul ezt az alakot használják, A6 teljesül).
  - `--next-orchestrator` hook: `next_orchestrator "${2:-}"` — opcionális
    kör-argumentummal bővült, argumentum nélkül változatlan.
  - Új hookok: `--branch-implementer <kör>` és
    `--resume-orchestrator <kör> <implementer>`.
  - Új függvények (D2): `orchestrator_conflicts_with_implementer()` (a
    meglévő `engine_uses_claude_quota()`/terra-modell mérésre épít, nem írja
    újra), `resolve_branch_implementer()` (`git ls-remote --heads
    "$round_remote"`, a kör-slug UTÁN kötelező `-` határolóval — az `ops/*`
    ágak sosem illeszkednek), `resolve_resume_orchestrator()` (a §5.2 kötött
    feloldási sorrend: rögzített orchestrátor → másik orchestrátor → HALT_INDEP;
    ismeretlen registry-motor azonnal HALT_INDEP, §5.3).
  - A `# --- 4.5` dispatch-blokk kettéágazik: ha `resolve_branch_implementer
    "$round"` nem üres (a körnek MÁR van távoli ága), a D2 út fut (implementer
    fix, orchestrátor a mozgatható szereplő, HALT_INDEP → `halt=H-INDEP` a
    korábbi mintával); egyébként a régi (D0/ADR 0222) `resolve_independent_
    engine` út fut változatlanul.
  - A korábbi, minden dispatchnél FELTÉTEL NÉLKÜL globális írás
    (`printf '%s\n' "$orchestrator" > "$orch_last_file"`, a session indítása
    előtt) törölve — a perzisztencia immár a fenti függvényeken belül,
    kör-kulcsoltan történik.
- **`tools/safe-force-push.sh`** (ÚJ) — a §5.5 négy lépése: pontos fetch
  (`+refs/heads/<b>:refs/remotes/<remote>/<b>`) → remote-only commitok
  patch-id alapon (`git log --cherry-mark --left-right --pretty='format:%m
  %H %s'`, csak a `<` jelöltek) → ha van ilyen: a lista kiírása stderr-re és
  `exit 3`, push nélkül → ha nincs: `git push --force-with-lease="$branch:
  $remote_sha"` a FRISSEN mért SHA-ra. `exit 2` hibás híváskor vagy sikertelen
  fetchkor.
- **`docs/execution/pipeline-orchestrator-prompt.md`** — a H8-sor pontosítva
  (§293 körül): „…ÉS a rebase **konfliktust ad** — a remote-only commitok
  beépítése ütközik”. A H4/H5 tábla utáni bekezdésbe egy új „H8 pontosítása”
  szakasz került, ami kimondja, hogy a puszta `--force-with-lease`-elutasítás
  NEM H8, a `tools/safe-force-push.sh` négy lépését írja le, és az ADR
  0242-re hivatkozik.
- **`tools/tests/test_orchestrator_rotation.py`** — egy ÚJ cella
  (`test_a_new_round_still_steps_even_when_another_round_is_pinned`, A2); a
  meglévő tesztek nem módosultak.
- **`tools/tests/test_round_resume_independence.py`** (ÚJ) — D1 (A1, plusz egy
  kiegészítő "új kör lép" eset) és D2 (A3/A4/A5, plusz egy `ops/*`
  nem-illeszkedés próba és egy Terra↔Terra ütközés próba) hermetikus
  tesztjei, `PIPELINE_STATE_DIR` + lokális bare repo (`PIPELINE_ROUND_REMOTE`)
  mintára.
- **`tools/tests/test_safe_force_push.py`** (ÚJ) — A7–A10 hermetikus tesztjei,
  lokális bare "origin" + két klón (`work`, `other`) mintára.
- **`docs/rounds/e99-r08-gov-07-per-round-orchestrator-rotation.md`** — ez a
  §10 szakasz.

### 10.2 Tesztfuttatások (RED → GREEN, csonkítatlan)

RED (a próbateszt-fájlok megírása UTÁN, a D1/D2 kód megírása UTÁN, de a
két, alább dokumentált valódi-sértés próbával mérve — lásd 10.3, mert az
implementáció íráskor lépésenként haladt, nem külön RED-checkpointtal):

```
$ /tmp/rvenv/bin/python -m pytest tools/tests/test_round_resume_independence.py -q
..........
10 passed in 0.35s
$ /tmp/rvenv/bin/python -m pytest tools/tests/test_safe_force_push.py -q
.....
5 passed in 0.54s
$ /tmp/rvenv/bin/python -m pytest tools/tests/test_orchestrator_rotation.py -q
(a teljes suite futtatásában, lásd lent — mind zöld, a meglévő cellák is)
```

### 10.3 Valódi-sértés próbák (§6.1, KÖTELEZŐ)

**A1 (per-round pinning kikapcsolva):** a `next_orchestrator()`-ban a kör-fájl
visszaolvasását ideiglenesen `if false && [ -n "$round" ]; then …` alakra
cseréltem (a globális, körfüggetlen viselkedésre esve vissza). Eredmény:

```
FAILED tools/tests/test_round_resume_independence.py::PerRoundRotationTest::test_a_second_dispatch_of_the_same_round_keeps_its_orchestrator
FAILED tools/tests/test_round_resume_independence.py::ResumeOrchestratorConflictTest::test_no_conflict_keeps_the_pinned_orchestrator
2 failed, 8 passed in 0.36s
```

A mutáció a mátrix szerinti cellát (A1) — és egy másodikat, ami a D2 útra is
rá van építve a rögzítésre — pirosra váltotta, a többi 8 teszt zöld maradt.
Visszaállítva (`cp /tmp/round-pipeline.sh.bak tools/round-pipeline.sh`),
utána `bash -n` + a teszt újra zöld (10/10).

**A7 (a safe-force-push megtagadás kikapcsolva):** a 3. lépés
(`if [ -n "$remote_only" ]; then … exit 3; fi`) `if false && …`-ra cserélve.
Eredmény:

```
FAILED tools/tests/test_safe_force_push.py::RefusalTest::test_it_refuses_when_the_remote_has_commits_we_lack
FAILED tools/tests/test_safe_force_push.py::RefusalTest::test_the_refusal_names_the_remote_only_commits
2 failed, 3 passed in 0.61s
```

A megtagadás kiiktatása mindkét A7/A8-mérő cellát pirosra váltotta (a script
csendben force-pusholt, eldobva a remote-only commitot). Visszaállítva,
utána `bash -n` + a teszt újra zöld (5/5).

### 10.4 Kötelező ellenőrzések (§7, csonkítatlan)

```
$ tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart
```
Mind a hat lépés (`format`, `analyze`, `test`, `architecture`, `secrets`,
`l10n`) ZÖLD, „MINDEN GATE ZÖLD” összegzéssel.

```
$ /tmp/rvenv/bin/python -m pytest tools/tests -q
...
397 passed, 394 subtests passed in 233.34s (0:03:53)
1 failed: tools/tests/test_claude_harness_engines.py::WrapperModeTest::test_the_legacy_call_without_round_engine_stays_minimax
```

Ez az EGY piros **NEM ehhez a körhöz tartozik** — `tools/mm-round.sh`
wrapper-viselkedést mér, amit ez a kör nem érint (nincs az engedélyezett-
fájllistán, és a diffben sincs benne). Ellenőrizve: ugyanez a teszt
UGYANAZZAL a hibaüzenettel piros a `git stash`-elt, tiszta `ba9b65ea` bázison
is — tehát pre-existing, nem regresszió. (A pytest futtatásához a repóban
nincs telepített `pytest`; a már meglévő, korábbi körökből visszamaradt
`/tmp/rvenv` venv-et használtam — ugyanazt a mintát, amit a
`docs/execution/pipeline-selfheal-prompt.md:79` is dokumentál, nem a
tiltott ad-hoc `pip install`-t a repóban.)

Nem futtatott ellenőrzés: `.github/workflows/router-ci.yml` (Router CI) —
azt a §0.0 szerint az orchestrátor futtatja a kör-ágon dispatch/merge előtt.

### 10.5 Nem érintett / szándékosan kihagyott

- `docs/adr/**`, `tools/round-gate.sh`, `.github/**`, `lib/**`, `test/**`,
  `docs/execution/pipeline-queue.tsv`, `HANDOFF.md`, `docs/LESSONS.md` —
  egyik sem módosult (A12: `git diff --stat origin/main...HEAD` nulla
  `.dart`/`lib/`/`test/` útvonalat mutat).
- `H-INDEP` önjavíthatóvá tétele — nem történt meg (ADR 0138 S4 marad).

### 10.6 Javító kör — F1 (független review, 2026-08-13)

A független review a `0cf02cf5` commitot egy friss izolált klónban
`/tmp/rvenv/bin/python -m pytest tools/tests -q` alatt futtatta, és
`12 failed, 386 passed`-et mért. A gyökérok: `tools/round-pipeline.sh`
"3. Előfeltételek" szakasza (a D1/D2-től független, MEGLÉVŐ kód) a
munkafa-helyreállítás lépésben (`current_branch != main` és tiszta fa esetén)
**valódi** `git checkout -q main`-t futtat a hívó folyamat `cwd`-jén. A
`tools/tests/test_pipeline_integration.py` egy MEGLÉVŐ, `E99-R08`-tól
független teljes-firing tesztje (`test_a_full_firing_retries_the_round_
instead_of_healing_a_resolved_terra_wall`) ezt az utat éri el `cwd=ROOT`-tal
(nincs izolált worktree, csak `PIPELINE_STATE_DIR` van injektálva) — a
review klónjában ez a valódi klónt `main`-re kapcsolta át, mielőtt a nála
ABC-sorrendben KÉSŐBB következő `test_round_resume_independence.py` és
`test_safe_force_push.py` lefutott volna. Ezért azok a `main`-ág tartalmát
mérték (a `tools/safe-force-push.sh` ott nem is létezik), nem a review-zott
commitot.

**Javítás** (`tools/round-pipeline.sh`, a step-3 munkafa-helyreállítási ág):
a valódi `git checkout -q main` mostantól csak akkor fut, ha
`PIPELINE_STATE_DIR` **nincs beállítva** — ez a kódbázisban MÁR bevett
egyezmény jele arra, hogy a hívás valódi production cron-futás (a
`crontab` sosem állítja ezt a változót), NEM `tools/tests` alatti
teszt-/review-hívás (a `tools/tests` MINDEN esete injektál egy izolált
`PIPELINE_STATE_DIR`-t, lásd a brief §9 kockázat-jegyzetét és
`tools/round-pipeline.sh:64` alapértelmezését). Teszt-módban a driver ezért
**fail-closed** `die()`-zik ("teszt-módban (PIPELINE_STATE_DIR) a driver nem
mozdítja a megosztott munkafa ágát"), és nem nyúl a hívó folyamat `cwd`-jének
git-ágához. A production szemantika bitre változatlan (a crontab-hívás soha
nem állítja be `PIPELINE_STATE_DIR`-t — mérve: `crontab -l` a `/home/ubuntu/
music-theory` productionön). A `docs/execution/pipeline-orchestrator-prompt.md`
és a `tools/safe-force-push.sh` D3-logikája nem változott.

**Regressziós próba** (`tools/tests/test_round_resume_independence.py`,
`WorkspaceRestorationHermeticityTest`): egy hermetikus fixture-repót épít
(lokális bare "origin" + egy `sonnet-impl/e00-r00-fixture` nevű, main-től
eltérő, tiszta ágra checkoutolt work-klón), a drivert `cwd=`erre a
fixture-re futtatja argumentum nélkül, `PIPELINE_STATE_DIR`-rel, és
megméri, hogy (a) a driver nemnulla kóddal, a `PIPELINE_STATE_DIR` szót
tartalmazó üzenettel áll meg, ÉS (b) a fixture git-ága a hívás UTÁN is a
`sonnet-impl/e00-r00-fixture` marad — nem `main`. Ez a régi kódon PIROS lett
volna (a fixture ága ténylegesen `main`-re váltott volna).

**Ellenőrzések a javítás után** (mind csonkítatlan, külön processz):

```
$ /tmp/rvenv/bin/python -m pytest tools/tests/test_round_resume_independence.py -q
...........
11 passed in 0.80s
$ /tmp/rvenv/bin/python -m pytest tools/tests/test_safe_force_push.py -q
.....
5 passed in 0.54s
$ /tmp/rvenv/bin/python -m pytest tools/tests/test_orchestrator_rotation.py -q
......
6 passed, 4 subtests passed in ...s
```

Teljes suite a JELENLEGI munkafán:

```
$ /tmp/rvenv/bin/python -m pytest tools/tests -q
1 failed, 398 passed, 394 subtests passed in 192.49s (0:03:12)
FAILED tools/tests/test_claude_harness_engines.py::WrapperModeTest::test_the_legacy_call_without_round_engine_stays_minimax
```

Ugyanez az egy piros (pre-existing, `tools/mm-round.sh` wrapper-viselkedést
mér, e kör diffjén kívül esik — lásd §10.4) — a review 12 pirosa mind zöld.

**Teljes suite egy FRISS, izolált klónban, a javított commit-on**
(`git clone` → `git checkout sonnet-impl/e99-r08-gov-07-per-round-orchestrator-rotation`
a `b9e72ec6` commitra), pontosan a review reprodukciójának megfelelően:

```
$ cd /tmp/e99r08-hermetic-check && /tmp/rvenv/bin/python -m pytest tools/tests -q
1 failed, 398 passed, 394 subtests passed in 191.79s (0:03:11)
FAILED tools/tests/test_claude_harness_engines.py::WrapperModeTest::test_the_legacy_call_without_round_engine_stays_minimax
```

A futás UTÁN a klón mérve: `git branch --show-current` →
`sonnet-impl/e99-r08-gov-07-per-round-orchestrator-rotation`, `git status
--porcelain` → üres, `tools/safe-force-push.sh` a lemezen jelen van a suite
teljes futása alatt és után is. A klón NEM váltott `main`-re — F1 zárva.

`tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart` a
jelen munkafán újra lefuttatva: mind a hat lépés ZÖLD ("MINDEN GATE ZÖLD").

### 10.7 Javító kör — F2 (független review, 2026-08-13)

A független review mérve:

```
$ state_dir=$(mktemp -d)
$ mkdir -p "$state_dir/orchestrator-round"
$ printf 'terra\n' > "$state_dir/orchestrator-round/E06-R23"
$ printf '%s\n' $(( $(date +%s) + 3600 )) > "$state_dir/claude-blocked-until"
$ PIPELINE_STATE_DIR="$state_dir" bash tools/round-pipeline.sh \
    --resume-orchestrator E06-R23 terra
claude
```

A pinelt `terra` ütközik a `terra`-modell implementerrel (helyes), de a
`resolve_resume_orchestrator()` (`:1192-1222`) a candidate-hurokban
(`:1208-1219`) **csak a `orchestrator_conflicts_with_implementer()` függést**
nézte — a `claude_unavailable_until`/`claude_usage_block_until` aktív zárlatát
soha. Az `E06-R23`-hoz `claude-blocked-until` egy órával a jövőben állt, a
resolver mégis `claude`-ot adott vissza: ADR 0242 §5.2 sérülve (az alternatívának
független ÉS elérhető kell lennie, különben `HALT_INDEP`).

**Gyökérok:** a régi `resolve_independent_engine()` (friss dispatch útja) MÉRI
a `claude_unavailable_until`/`claude_usage_block_until`-t (`:1124-1125`), de a
D2 folytatás-útja (`resolve_resume_orchestrator`) ezt a mérést sosem hívta —
csak a függetlenséget (kvóta-azonosság), az elérhetőséget nem.

**Javítás** (`tools/round-pipeline.sh`): új `orchestrator_available()`
függvény (`:1190-1201`, a `resolve_resume_orchestrator` elé), ami
`claude`-ra a két meglévő zárlat-mérőt (`claude_unavailable_until`,
`claude_usage_block_until`), `terra`-ra a `fallback_engine != none` feltételt
nézi. A `resolve_resume_orchestrator()` mindkét ága (a pinned megtartása és a
candidate-hurok) mostantól `orchestrator_conflicts_with_implementer(...) &&
orchestrator_available(...)`-t követel — a korábbi, a hurokban duplikált
`fallback_engine = none` ellenőrzést az új függvény váltja ki.

Az ellenkező irány is fedve (a brief kérése szerint): ha a pinelt
orchestrátor független, de ELÉRHETETLEN, a régi kód azt is vakon megtartotta
volna (`if ! orchestrator_conflicts_with_implementer "$pinned" ...; then
printf pinned; return; fi` — elérhetőség-ellenőrzés nélkül). Az új kód a
pinned ágra is megköveteli az elérhetőséget, így a mozgatható szereplő (az
orchestrátor) a másik elérhető, független motorra billen, az implementer
(fix, ág-mért) nem mozdul.

**Regressziós próbák** (`tools/tests/test_round_resume_independence.py`,
`ResumeOrchestratorConflictTest`):

- `test_a_conflicting_pin_with_no_available_alternate_fails_closed` — a
  jelentés pontos reprodukciója (`--resume-orchestrator E06-R23 terra`,
  pinned=`terra`, `claude-blocked-until` a jövőben) → `HALT_INDEP` várt.
- `test_an_independent_but_unavailable_pin_is_not_retained` — az ellenkező
  irány: pinned=`claude` (független a `minimax` implementertől), de
  `claude-blocked-until` a jövőben → várt `terra`, és a kör-pin fájl
  ténylegesen frissül `terra`-ra (nem marad `claude` a lemezen).

**Valódi-sértés próba** (mindkét cellára): a `orchestrator_available "$pinned"`
és `orchestrator_available "$candidate"` feltételeket ideiglenesen
`&& true`-ra cseréltem (visszaállítva a review által talált, elérhetőséget
figyelmen kívül hagyó viselkedésre). Eredmény:

```
$ /tmp/rvenv/bin/python -m pytest tools/tests/test_round_resume_independence.py -q
......F.F....
2 failed, 11 passed in 0.87s
FAILED ...::test_a_conflicting_pin_with_no_available_alternate_fails_closed  ('claude' != 'HALT_INDEP')
FAILED ...::test_an_independent_but_unavailable_pin_is_not_retained          ('claude' != 'terra')
```

A mutáció pontosan a két új cellát pirosította, a többi 11 zöld maradt.
Visszaállítva (`cp /tmp/round-pipeline.sh.bak tools/round-pipeline.sh`),
`bash -n` + a teszt újra zöld (13/13).

**Ellenőrzések a javítás után** (csonkítatlan, külön processz):

```
$ /tmp/rvenv/bin/python -m pytest tools/tests/test_round_resume_independence.py -q
.............
13 passed in 0.89s
```

```
$ tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart
```
Mind a hat lépés (`format`, `analyze`, `test`, `architecture`, `secrets`,
`l10n`) ZÖLD, „MINDEN GATE ZÖLD” összegzéssel.

Teljes suite:

```
$ /tmp/rvenv/bin/python -m pytest tools/tests -q
1 failed, 400 passed, 394 subtests passed in 193.09s (0:03:13)
FAILED tools/tests/test_claude_harness_engines.py::WrapperModeTest::test_the_legacy_call_without_round_engine_stays_minimax
```

Ugyanaz az egy, e kör diffjén KÍVÜL eső, pre-existing piros, mint a §10.4/§10.6
alatt (`tools/mm-round.sh` wrapper-viselkedés, nem érintett a listán, nincs a
diffben) — a review talált F2-lelet zölddé vált, a 400 zöld a korábbi 398-hoz
képest a két új regressziós cellával nő.

## 11. Review — a Claude tölti ki
