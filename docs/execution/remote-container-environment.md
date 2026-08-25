# A Claude Code remote konténer — MÉRT képességtérkép

> **Mérve 2026-08-25**, egy `claude/pipeline-development-anvsky` remote sessionben
> (`main @ 0f05df02`). Ez a fájl NEM elmélet: minden sora egy lefuttatott parancs
> kimenete. A konténer **efemer** — amit nem commitolunk, elvész vele.
>
> **Miért van rá szükség:** a StrumSight pipeline a felhasználó SAJÁT boxára van
> tervezve. Remote sessionből indított körök kétszer futottak zátonyra úgy, hogy
> a gyökérok csak menet közben derült ki (E09-R27 folytatása, majd ez a session).
> Ez a lap előre megmondja, mi megy és mi nem.

## 1. A LÉNYEG — a pipeline itt NEM indítható

> **De nem is vagy elzárva tőle:** a `§6` hídján keresztül indítható session a
> felhasználó SAJÁT gépén, ahol minden megvan. „Itt nem futtatható" ≠ „nem
> vezényelhető".

Két, egymástól FÜGGETLEN blokkoló. Bármelyik önmagában elég.

| Blokkoló | Mért bizonyíték |
|---|---|
| **Nincs Flutter/Dart SDK, és nem telepíthető** | `storage.googleapis.com:443` CONNECT → **403** (`recentRelayFailures`: „gateway answered 403 to CONNECT (policy denial)"); `pub.dev` → nem elérhető. A `flutter`/`dart` bináris nincs a PATH-on, és `/opt`-ban sincs. |
| **A `gh` CLI telepíthető, de HITELESÍTENI NEM TUD** | lásd §3 |

**Ezért nincs olyan nyitott kör, amit itt mérni lehetne:** a queue MINDEN nyitott
sora (E13-R16…R36, E09-R28…R32, E10-R01…R32) érint Dart fájlt. Az E09-R27 azért
ment át remote konténerben, mert a diffje **véletlenül** egyetlen Dart fájlt sem
érintett — az a kivétel, nem a szabály.

## 2. Ami MŰKÖDIK

| Képesség | Mért állapot |
|---|---|
| **`sonnet-impl` implementer-motor** | `claude` CLI **2.1.245** a `/opt/node22/bin/claude`-on; `tools/engine-profile.sh list` → `sonnet-impl … kész`. **Ez az EGYETLEN elérhető motor.** |
| git (fetch/push) | a session git-proxyján át működik |
| GitHub API | **KIZÁRÓLAG az MCP tool-okon** (`mcp__github__*`) — lásd §3 |
| Python | `python3` 3.11 + `pip`; `pypi.org` és `files.pythonhosted.org` a proxy `noProxy` listáján → `pip install pytest` **működik** |
| `tools/tests` suite | lefut: **748 passed, 2 skipped, 665 subtest passed, 1 failed** (~8 perc). A bukó cella környezeti, lásd §5. |
| Go toolchain | **go 1.24.7** a `/usr/local/go`-ban; `proxy.golang.org` → **200** (szintén `noProxy`) — Go-eszközök telepíthetők |
| apt | `archive.ubuntu.com` elérhető (a `gh` innen jött, 8.8 MB, 1 s) |

**Ami NINCS:** `codex`, `~/.codex`, `~/.codex-terra`, `~/.codex-kilo`,
`~/.claude-minimax`, `~/.mmx`. Vagyis a `minimax`, `codex`, `terra`, `sol` és a
teljes Kilo-család (`qwen-*`, `gptoss`, `kimi`, `deepseek-pro`) **egyike sem
futtatható** — a nyilvántartás mind a 14 sorára `HIÁNYZIK a profil`.

## 3. A `gh` CLI — telepíthető, de használhatatlan

```
apt-get install -y gh      # SIKERES: gh 2.45.0 (noble-updates/universe)
```

Utána viszont:

```
gh auth status   →  X Failed to log in to github.com using token (GH_TOKEN)
                    The token in GH_TOKEN is invalid.       (GH_TOKEN = 14 karakter)
gh api repos/wolfcasaba/strumsight
                 →  HTTP 403 "GitHub access is not enabled for this session.
                    An org admin must connect the Claude GitHub App…"
gh pr list       →  HTTP 403 "This GraphQL query (PullRequestList, sent by gh pr
                    list) is not enabled for this session — only the pinned set
                    of PR-review operations is served."
gh run list      →  HTTP 403 (ugyanaz az Actions REST végponton)
```

**A 403 a PROXYTÓL jön, nem a GitHubtól** — a hibatörzs Anthropic-szerzőségű
(`documentation_url: docs.anthropic.com`, „Use add_repo"). Ebből következik a
legfontosabb tanulság: **érvényes PAT sem oldaná meg.** A tiltás a proxy
szintjén van, nem a hitelesítésnél. Az `add_repo … access:"push"` sem segít —
`already_present`, új kredencia nélkül.

**A GitHub API tehát KIZÁRÓLAG az MCP tool-okon érhető el** — ez mérve működik:
`mcp__github__actions_list(list_workflow_runs, build-apk.yml)` → `total_count: 479`.
De ezeket **csak a modell hívhatja, shell script nem** — vagyis `gh`-shimet írni
rájuk nem lehet.

### A driver fail-closed viselkedése (helyes, ne „javítsd meg")

`tools/round-pipeline.sh --dry-run` a `gh` telepítése ELŐTT és UTÁN:

```
előtte:  HIBA: nincs gh CLI
utána:   HIBA: a nyitott PR-ek nem kérdezhetők le (gh) — a lánc nem indul vakon
```

A `gh` telepítése tehát **egy lépéssel tovább viszi a drivert, majd az továbbra
is megáll** — és ez a helyes viselkedés. A driver öt gh-alparancsra épül
(`gh pr list`, `gh pr view`, `gh run list`, `gh run watch`, `gh workflow run`);
mind a 403-as felületen van.

## 4. Két git-csapda a shallow klónban

1. **A lokális `main` egy ROKONTALAN, ősi csonk.** Mérve: `main` = `1a051d8`
   (E08-R01), `origin/main` = `0f05df02`, és `git merge-base main origin/main`
   **üres**. Ezért `git pull --ff-only` → „Diverging branches can't be
   fast-forwarded", `git merge` → **„refusing to merge unrelated histories"**.
   Feloldás: `git reset --hard origin/main` (a lokális `main` eldobható, nincs
   benne semmi, ami ne lenne a távolin). A munka-ág maga rendben van — az a
   valódi HEAD-ből született.
2. **A git-notes NEM tolható fel.** `git push origin 'refs/notes/*'` →
   `send-pack: unexpected disconnect while reading sideband packet`, három
   kísérlet után is (exponenciális várakozással). A shallow klón nem tudja
   feltolni a notes objektum-gráfját. A HORIZON-rituálé notes-lépését ezért a
   saját boxon kell pótolni.

## 5. A `tools/tests` egyetlen bukó cellája — környezeti, nem regresszió

```
FAILED tools/tests/test_round_resume_independence.py::
       WorkspaceRestorationHermeticityTest::
       test_test_mode_dispatch_does_not_switch_the_working_tree_off_its_branch
AssertionError: 'PIPELINE_STATE_DIR' not found in 'HIBA: nincs gh CLI'
```

A teszt azt várja, hogy a driver a state-dir ellenőrzésnél haljon meg; itt már a
`gh`-előfeltételnél kilép. **A `gh` telepítése után ez a cella várhatóan
elmozdul** (a driver tovább jut), de attól még nem lesz zöld — a `gh pr list`
403-a állítja meg. Ne vedd regressziónak, és NE gyengítsd a tesztet miatta.

## 6. A HÍD a felhasználó boxához — `env_012yGf199STmScPWnikMieeY`

**Mérve 2026-08-25.** A remote konténer NEM zsákutca: van egy `bridge` típusú
environment, ami a felhasználó SAJÁT gépén, a pipeline valódi otthonában futtat
sessiont. Ott minden megvan, ami itt hiányzik: Flutter SDK, működő `gh`,
implementer-profilok, és a `.pipeline/` lánc-állapot.

```
mcp__Claude_Code_Remote__list_environments →
  env_012yGf199STmScPWnikMieeY  free-tier-arm:music-theory:0845  kind=bridge  state=active   ← EZ AZ
  env_019dJbPTwAp7AywHnL9t7Szx  free-tier-arm:Recipewiser:a8b5   kind=bridge   (másik projekt)
  env_011CUaPRnRYLByjSGKz4YDzE  Default                          kind=anthropic_cloud (= EZ a konténer)
```

Indítás:

```
mcp__Claude_Code_Remote__create_session(
  environment_id = "env_012yGf199STmScPWnikMieeY",
  title = "...", prompt = "...")
```

A repó ott: **`/home/ubuntu/music-theory`** (a `tools/*.sh` és a
`sdd-round-driver` skill `/home/ubuntu/ss-<motor>-<kör>` munkapéldányai is
innen indulnak).

**Mért viselkedés:** a `create_session` először `connection_status:
disconnected` + `SESSION_STATUS_PENDING` állapotot ad vissza — ez NEM hiba, a
híd másodperceken belül felveszi (`connected`). Ha tartósan `disconnected`
marad `computer_unreachable` hibával, a gép van offline.

### A visszacsatolás a szűk keresztmetszet — tervezd bele a promptba

**Nincs `list_events` tool ebben a sessionben**, tehát a gyerek-session
kimenetét közvetlenül NEM tudom elolvasni; a `get_session` csak státuszt ad.
Két járható út, a promptba építve:

1. **A gyerek írja a jelentését a repóba és pusholja** (pl. egy `ops/`-ág vagy
   egy `docs/` fájl) — így BÁRMELYIK session elolvassa. Ez a robusztus minta.
2. A felhasználó látja a gyerek-sessiont a saját kliensében, és továbbítja.

### Amit a hídnak adott prompt KÖTELEZŐEN tartalmazzon

A gyerek a valódi fán dolgozik, ezért a korlátok nem magától értetődők:

- `tools/**` NEM módosítható (H-GATEGUARD védett zóna)
- `.pipeline/HALTED` **nem oldható fel** magától — a halt emberi döntés
  (ADR 0087 §2, ADR 0112)
- piszkos munkafánál semmit nem szabad eldobni, csak jelenteni
- a `docs/execution/pipeline-queue.tsv` `hold` sorai szándékosak

## 7. Mit lehet mégis érdemben csinálni innen

Nem semmit — csak nem kört. Ez a session ezeket végezte el:

- **kör-brief pre-flight** (kód olvasása, mért tények, §0.0 revízió,
  `tools/brief-lint.py --level strict`)
- **sor-fájl / lánc-konfiguráció** (`tools/round-slots.py plan` bizonyítékkal)
- **`tools/tests` futtatása** (pip-pel telepített pytesttel)
- **doksi-karbantartás**, commit, push, merge

Amit NEM: kör-indítás, gate-futtatás, CI-dispatch `gh`-val, APK.
