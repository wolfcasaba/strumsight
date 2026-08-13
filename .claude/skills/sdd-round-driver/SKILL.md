---
name: sdd-round-driver
description: Egy StrumSight SDD-kör TELJES levezénylése az orchestrátor (Claude / Opus 5) székéből — pre-flight, kör-brief, implementer-motor kiválasztás (Codex vs MiniMax M3), headless indítás a wrapper scriptekkel, kör-jelzés figyelése, review-kézfogás, javító kör, CI-dispatch, zöld-kapus squash-merge és a záró rituálék (HANDOFF, git-notes, Viking). Használd, amikor a feladat "vidd a következő kört", "indítsd az E02-RXX-et", "folytasd az SDD-t" vagy bármilyen kör-végrehajtás; akkor is, ha a modell először vezényel le kört ebben a repóban.
---

# SDD kör-levezénylés (orchestrátor-oldal)

Egy kör = egy session (ADR 0052). A lánc: tervezés → implementálás (másik
motor!) → review → javítás → merge → zárás → STOP. Te vagy a karmester; a
production kódot a körben NEM te írod (kivétel: explicit user-utasítás, vagy
a motor-oldal nem elérhető — jelentésben rögzítve).

## 0. Pre-flight

1. `HANDOFF.md` §6 — melyik kör a következő, mik az előfeltételei.
2. `git status --short` — ismeretlen working-tree változást NE módosíts.
3. `gh pr list` + `gh run list --limit 5` — fut-e párhuzamos autonóm driver
   ugyanazon a körön (ismert jelenség ezen a boxon). Ha igen: állj meg, jelents.
4. A kör SDD-fejezete + érintett kód + a legutóbbi review tanulságai.

## 1. Kör-brief (→ `round-brief-prep` skill)

A brief a `docs/rounds/eXX-rYY-<slug>.md` fájl, a `docs/execution/08-round-brief.md`
sablonra. Kritikus elemek: mért „Jelenlegi állapot", **engedélyezett fájlok
tételes listája + tilos zóna**, előre kiosztott ADR-szám (az ADR-t TE írod),
mérhető acceptance criteria, és a **gate-hívás az artefaktumon** —
`tools/round-gate.sh <érintett terület> [további …]` (a mérce artefaktum,
nem prompt-szöveg: a csővezeték elrejti a kilépési kódot, lásd
`docs/LESSONS.md` L09; normatív forrás: `AGENTS.md` §12). A brief a kör
indítása ELŐTT commitolva van a kör-branchre.

**Kötelező tanulság-átvitel (E02-R04/R05):** a zöld gate nem bizonyíték —
minden szövegesen leírt tartalmi előírás mellé GÉPI mércét adj (kipinnelt
szekvencia, legacy-referenciával szembe mérő teszt az éleken), különben a
review-nak kell próbateszttel megfognia.

## 2. Motor-választás (ADR 0069, AGENTS.md §15.6)

| Kör jellege | Motor |
|---|---|
| Jól specifikált domain/model/teszt, adapter, katalógus, i18n, mechanikus refaktor, boilerplate | **MiniMax M3** |
| DSP-hangolás, baseline-érzékeny scorer/matcher, perf-kritikus, felderítő/kétértelmű | **Codex** |
| Bizonytalan | **Codex** (a drágább a biztonságos default) |

A szűkös erőforrás a Codex-kvóta — volument inkább M3-nak.

**MiniMax-briefbe KÖTELEZŐ öt elem** (mért hibák ellenszere): (1) záró gate-sor
szó szerint, csővezeték és `tail` nélkül; (2) STOP-klauzula scope-ütközésre
(`stopped` jelzés + jelentés); (3) a kör-jelzés kötelezettsége a prompt elején;
(4) „a brief §8 a terved — nincs külön task-lista"; (5) „doc-commentben csak
tesztben bizonyított állítás (`const`, `immutable`)".

## 3. Indítás (SOHA nem csupasz `codex exec`)

Külön munkapéldányban (`/home/ubuntu/ss-<motor>-<kör>`), KÉT háttér-taskként.
**A munkapéldányt MINDIG `git clone <fő-repó> <cél>`-lal hozd létre, SOHA
`git worktree add`-dal** — a `git worktree add` `.git`-je FÁJL, nem könyvtár,
és a `tools/mm-round.sh`/`codex-round.sh` saját `[ ! -d "$workdir/.git" ]`
validációja ezt néma `exit 2`-vel bukja, MIELŐTT a log-fájl létrejönne. A
leválaszt-és-várj mintában ez teljesen észrevétlen: nincs log, nincs
jelzésfájl, a `wait-for-round.sh` csak a saját időkorlátjáig vár, majd
`exit 5`-öt ad („még futhat"), ami élő, lassú körnek tűnik, miközben a
dispatch el sem indult. Kétszer mérve, ismételten (E05-R18 L175, E05-R20) —
ha ismét megtörténne: `ps -ef | grep claude` NULLA találat + `stat -c '%F'
<munkapéldány>/.git` → `regular file` a diagnózis. Részletek:
`docs/LESSONS.md` L175, L179.

**A `git clone` UTÁN, a dispatch ELŐTT, MINDIG:**
`bash <munkapéldány>/tools/prepare-flutter-generated.sh` (a gitignore-olt
generált `lib/l10n/app_localizations*.dart` és a `flutter pub get` outputot
állítja helyre). Enélkül az implementer első `flutter analyze`-je 900+ hamis
hibával `blocked`-ot jelez — a gyökérok NEM kód, hanem a friss klón hiányzó
generált előfeltétele. Ez a HARMADIK mérés ugyanerre (L222 E06-R07, L228
E06-R10, L230 E06-R11) — a lecke önmagában, LESSONS.md-be írva, NEM
elegendő védelem, csak a workflow SAJÁT szövegébe ágyazott lépés az.

**A script NEM olvassa a saját argv-ját** — `repo_root`-ot a `BASH_SOURCE`
saját útvonalából számolja, ezért `bash tools/prepare-flutter-generated.sh
<munkapéldány>` (a forrásfa SAJÁT másolatát hívva, a munkapéldányt csak
argumentumként odaírva) NÉMÁN a forrásfát készíti elő, a munkapéldányt
érintetlenül hagyva (L232, E06-R13) — pontosan a fenti parancsalak a
hibás, a `<munkapéldány>/tools/...` (a munkapéldány SAJÁT másolatának
hívása, argumentum nélkül) a helyes.

```bash
# Codex:
tools/codex-round.sh /home/ubuntu/ss-codex-<kör> <prompt>.md /tmp/codex-<kör>.log
tools/codex-watch.sh /home/ubuntu/ss-codex-<kör> /tmp/codex-<kör>.log
# MiniMax M3:
tools/mm-round.sh /home/ubuntu/ss-mm-<kör> <prompt>.md /tmp/mm-<kör>.log
tools/mm-watch.sh /home/ubuntu/ss-mm-<kör> /tmp/mm-<kör>.log
```

A wrapper `-s danger-full-access`-szel fut (a bwrap itt nem megy) — az
izolációt a külön munkapéldány adja. Védelmi vonalak: kör-jelzés
(`.codex-round-status`), stall-őr (12 perc néma log → kill), timeout (3600s).

**Értesüléskor ELŐSZÖR a `.codex-round-status` fájlt olvasd** (`status`,
`summary`, `branch`, `head`, `dirty_files`), csak utána a logot. `status=unknown`
→ a motor jelzés nélkül halt meg; a jelentését ne fogadd el bemondásra.
Crash-nél: resume UGYANAZZAL a session-iddel + a TELJES gate-mátrix újrafuttatása.

**A várakozás a JELZÉSFÁJLRA megy, nem processz-életre — és nem kézzel írt
egysorossal.** Az E02-R08-ban egy `until ! pgrep -f "…"` ciklus a **saját
parancssorára** illeszkedett, és az implementer `stopped` jele hat órán át
rejtve maradt ([`docs/LESSONS.md`](docs/LESSONS.md) L12). A helyes várakozás
futtatható artefaktum:

```bash
tools/wait-for-round.sh /home/ubuntu/ss-<motor>-<kör>   # 0=done 3=stopped 4=stalled|timeout|unknown 5=lejárt
```

A négy kilépési kód a `done` / `stopped` / `stalled|timeout|unknown` / „még fut,
de lejárt az időkorlát" eseteket különbözteti meg — a `stopped` (3) a
döntést-kérő állapot, nem szabad futó körnek nézni.

## 4. Review (→ `sdd-round-review` skill)

Független, read-only review-jelentés a `docs/reviews/eXX-rYY-review.md`-be.
BLOCKER/MAJOR nyitva → nincs merge; a javító kört UGYANAZ a motor viszi, a
findings-listával a promptban. A javító kör után a review-t frissítsd
(APPROVED / újra CHANGES REQUESTED) és a zárást ellenőrizd leletenként.

## 5. CI-dispatch és merge

```bash
git fetch origin main && git rev-parse origin/main   # JEGYEZD FEL ezt a SHA-t
gh workflow run build-apk.yml --ref <kör-branch>
run_id=$(gh run list --workflow=build-apk.yml --branch <kör-branch> --limit 1 --json databaseId --jq '.[0].databaseId')
tools/wait-for-ci.sh "$run_id"   # 0=success 1=failure 4=lejárt(még futhat) 6=gh maga akadt el
```

**SOSE csupasz `gh run watch`/`gh run list`-ciklus** — egyik hívást sem védi
timeout. Mérve (E06-R25, H-NOSIGNAL önjavítás, 2026-08-13): egy ilyen védtelen
`gh run list` hívás a session BELSEJÉBEN fagyott le, miközben a várt futás már
zölden lezárult — a driver csak a 20 perces elakadás-őrrel, a teljes sessiont
ölve vette észre. A `tools/wait-for-ci.sh` minden hívást `timeout`-tal véd.

**A dispatch mehet, amint az implementer „kész"-t jelez — nem kell megvárni a
review-t.** A ~10 perces futás így a review alatt telik. Ha a javító kör KÓDOT
módosít, újra kell dispatch-elni (a `concurrency` a régi futást eldobja).

**Merge ELŐTT** (ADR 0086 §2 — a `build-apk.yml` már nem fut automatikusan a
`main`-re, ezt a rést ez az ellenőrzés zárja):

```bash
git fetch origin main && git rev-parse origin/main   # egyezzen a fentivel
```

Ha a `main` a dispatch óta mozdult (ezen a boxon egy másik autonóm kör-driver is
merge-el): rebase + **újra-dispatch**, és az új run a merge evidenciája.

A run linkje a PR kötelező build-evidenciája. A PR-törzs rögzíti, melyik motor
implementált. **Zöld kapu** (ADR 0052): format + analyze + architecture +
teljes CI-suite + randomizált property + APK mind zöld → **squash-merge külön
jóváhagyás nélkül**. Bármi piros/hiányzik → merge TILOS, jelents.

## 6. Zárás (mind kötelező, sorrendben)

1. `HANDOFF.md` frissítés (fejléc-dátum, §4–§6; a kész kör részletes története
   → `docs/handoff-archive.md`), `docs(handoff)` commit.
2. RTM (`docs/execution/06-…`) + ADR-hivatkozások, ha a kör érintette.
3. Git-notes: `git notes add -m "round=<n> verdict=pass tests=<n> lesson=<slug> engine=<motor>"`
   majd `git push origin 'refs/notes/*'`.
4. Viking: `viking_remember` (tanulságok) + `viking_session_commit`.
5. Végrehajtási jelentés a válaszban (AGENTS.md §16: összefoglaló, fájlok,
   acceptance-teljesítés, futtatott parancsok TÉNYLEGES kimenettel, nem
   futtatott ellenőrzések + ok, kockázatok, pontos következő kör).
6. **STOP.** A következő kör ÚJ sessionben indul — ne kezdd el.
