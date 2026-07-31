# GOV-01 review — a gate- és várakoztató artefaktum átvezetése

- **Kör:** GOV-01 (governance, nem SDD-fejezet)
- **Brief:** [`docs/rounds/gov-01-gate-artifact-rollout.md`](../rounds/gov-01-gate-artifact-rollout.md)
- **Branch:** `mm/gov-01-gate-artifact-rollout`
- **Implementer:** **MiniMax M3** (`engine=minimax-m3`), kör-jelzés `status=done`
- **Review HEAD:** `aa1bb6e` (implementáció `924db77` + §8 handoff `aa1bb6e`)
- **Verdikt (első kör):** **CHANGES REQUESTED** — 0 BLOCKER · 0 MAJOR · **1 MINOR** · 2 NOTE
- **Verdikt (javító kör után):** lásd §5

## 1. Módszer

Read-only review. A méréseket **izolált klónban** futtattam
(`git clone --branch mm/gov-01-gate-artifact-rollout /home/ubuntu/ss-mm-gov01 /tmp/review-gov01`),
nem a közös working tree-ben, és a brief §6 A1–A7 pontjait **saját kézzel újra
lemértem** — az implementer §8-beli kimenetét nem fogadtam el bemondásra.

Ez a kör Dart kódot nem érint, ezért a `tools/round-gate.sh` futtatása nem
követelmény (brief §9); a mérce a grep-mátrix és a `git diff`.

## 2. Scope-audit

`git diff --stat gh/main...HEAD` → 8 fájl, 445 beszúrás / 61 törlés:

```
 .claude/skills/round-brief-prep/SKILL.md          |  18 +-
 .claude/skills/sdd-round-driver/SKILL.md          |  21 +-
 .claude/skills/sdd-round-review/SKILL.md          |   7 +-
 .claude/skills/strumsight-how-we-develop/SKILL.md |  18 +-
 AGENTS.md                                         |  29 +-
 CLAUDE.md                                         |  16 +-
 docs/execution/04-definition-of-done.md           |   5 +-
 docs/rounds/gov-01-gate-artifact-rollout.md       | 392 ++++++++++++++++++++--
```

**Mind a nyolc a brief §4 engedélyezett listáján.** Új fájl nem keletkezett,
a tilos zóna (`lib/`, `test/`, `.github/`, `docs/sdd/`, `docs/adr/`,
`HANDOFF.md`, `pubspec.yaml`, `docs/execution/08-round-brief.md`) érintetlen.
`tools/mm-round.sh` és `tools/codex-round.sh` a §2 mérése szerint helyesen
maradt változatlan. **Scope-sértés: nincs.**

## 3. Acceptance criteria — tételes bizonyíték

| Pont | Verdikt | Bizonyíték (saját mérés, `/tmp/review-gov01`) |
|---|---|---|
| **A1** — a gate-artefaktum mind a hét helyen | **PASS** | `grep -rln "round-gate.sh" …` pontosan a 7 elvárt fájl + a forrás `08-round-brief.md` = **8** |
| **A2** — a régi parancslisták eltűntek | **RÉSZLEGES** | a §4 hatókörében 0 találat, de **6 maradvány** három listán kívüli skillben → **MINOR-1** |
| **A3** — a várakoztató artefaktum a driver-skillben | **PASS** | `sdd-round-driver/SKILL.md:82`, és **mind a négy** kilépési kód (`0`/`3`/`4`/`5`) ott van a sorban |
| **A4** — nincs csővezeték a mérce körül | **PASS** | a 6 `\| tail` találat **mind negatív említés** („miért NE"), egyik sem futtatandó parancs |
| **A5** — a három új brief-szabály | **PASS** | `round-brief-prep/SKILL.md` — nem elfogadható gyengítés · a méréshez szükséges eszköz · paraméter-mátrix, mindhárom a mért L09/L10/L13 hivatkozással |
| **A6** — nulla kód-érintés | **PASS** | a diff-stat egyetlen sora sem esik a tilos útvonalakra |
| **A7** — az artefaktumok viselkedése változatlan | **PASS** | `git diff … -- tools/round-gate.sh tools/wait-for-round.sh` **üres** |

A tartalmi hűség jó: a régi parancslisták a **helyükre** cserélődtek (nem
mellé), a „miért artefaktum" indoklás mindenhol ott van a mért forrásra
(L09 / L12) hivatkozva, és a box mért igazságai (OOM/L05, win32, Riverpod
`.value`) sehol nem estek ki.

## 4. Leletek

### MINOR-1 — a gate-előírás három inherited skillben tovább él, és az egyikre a `CLAUDE.md` kifejezetten ráirányít

**Hely:** `.claude/skills/verify-before-done/SKILL.md:17,22,43` ·
`.claude/skills/review-loop/SKILL.md:22,31` · `.claude/skills/flutter-dev/SKILL.md:36`

**Bizonyíték:**

```
$ grep -rn "flutter analyze lib/" AGENTS.md CLAUDE.md .claude/skills/ docs/execution/
.claude/skills/review-loop/SKILL.md:22:3. `flutter analyze lib/` (ALONE) → baseline állapot.
.claude/skills/review-loop/SKILL.md:31:- `flutter analyze lib/` → javítsd az összes analyzer hibát/warningot/lintet (flutter_lints ^6).
.claude/skills/flutter-dev/SKILL.md:36:1. `analyze_files` → 0 hiba (vagy `flutter analyze lib/` ÖNÁLLÓAN, ≥240s timeout).
.claude/skills/verify-before-done/SKILL.md:17:`flutter analyze lib/<path>`. Fix surfaced errors before stacking more edits on a broken file.
.claude/skills/verify-before-done/SKILL.md:22:flutter analyze lib/        # run ALONE — must be 0 errors
.claude/skills/verify-before-done/SKILL.md:43:flutter analyze lib/        # call 1 — clean
```

**Miért lelet és nem csak kozmetika:** a kör célja (brief §1) az, hogy „a
rendszer minden pontja ugyanazt mondja". A `CLAUDE.md:116` a StrumSight
verify-gate szakaszából **név szerint a `verify-before-done` skillre irányít**
— tehát az az AKTÍV láncban van, és most a `CLAUDE.md`-vel ellentétes,
kézzel felsorolt parancslistát ír elő. Ez pontosan az a második, elsodródó
igazságforrás, amit a kör megszüntetni hivatott.

**Miért NEM az implementer hibája:** a három skill nincs a brief §4
engedélyezett listáján, mert az **orchestrátor §2-beli felmérése kihagyta
őket** — ugyanaz a hibaosztály, mint a §0.0-ban már egyszer javított
`strumsight-how-we-develop` kihagyás. Az implementer helyesen nem tágította a
listát, hanem jelentette (§8 „Eltérések" 1. pont). A feloldás **dokumentált
brief-revízió**, nem lista-tágítás — lásd §0.2.

**Javasolt irány (nem kész patch):** a `verify-before-done` skillbe **egy**
hivatkozó mondat, hogy StrumSight-ban a lokális mérce a
`tools/round-gate.sh` artefaktum (`AGENTS.md` §12); a skill többi része
(build/visual/persistence-proof) változatlan. A `review-loop` és a
`flutter-dev` a leírásuk szerint **kifejezetten recipewiser-mobile-hatókörű**
(„RecipeWiser-mobile fejlesztési workflow", „a recipewiser-mobile projektben"),
ezért azok **kimaradnak** — átírásuk egy másik projekt workflow-ját hamisítaná
meg. Ezt a döntést a §0.2 rögzíti.

### NOTE-1 — a `stopped` jelzés helyett `done` + follow-up

A brief §3 STOP-klauzulája szerint „a brief két előírása egymásnak ellentmond,
vagy egy előírás a mért állapottal ütközik" → `stopped`. Az A2 acceptance
(`0 találat a .claude/skills/ alatt`) és a §4 engedélyezett lista **ütközött**,
tehát a szó szerinti szerződés a `stopped` lett volna. Az implementer `done`-t
adott, de az ütközést a **kör-jelzés summary mezőjében** és a §8 „Eltérések"
1. pontjában is szó szerint jelentette, ezért a hiba nem maradt rejtve —
a jelzés információtartalma teljes volt. Nem blokkol.

### NOTE-2 — a §8 diff-statje a §8-commit ELŐTTI állapotot mutatja

A §8-ban idézett `git diff --stat` a `gov-01-…md` fájlra 181 sort mutat, a
végleges HEAD-en 392 — mert a §8-at magát egy későbbi commit (`aa1bb6e`) írta
be. Ez nem valótlan állítás, csak a mérés természetes időpont-eltolódása;
a többi hat parancs kimenete az én független mérésemmel **karakterre egyezik**.
Nem blokkol.

## 5. Javító kör — **APPROVED**

- **Javító commit:** `2770f5c` (implementer: MiniMax M3, jelzés `status=done`)
- **Diff:** `.claude/skills/verify-before-done/SKILL.md` **+3 sor** ·
  `docs/rounds/gov-01-gate-artifact-rollout.md` +77 sor (a §8 „Javító kör"
  alszakasza). Más fájl nem változott.

**MINOR-1 — LEZÁRVA.** Saját mérés friss `/tmp/review-gov01b` klónban:

```
$ grep -rn "round-gate.sh" .claude/skills/verify-before-done/SKILL.md
.claude/skills/verify-before-done/SKILL.md:43:> **StrumSight:** a lokális mérce a `tools/round-gate.sh <érintett terület> [további ...]` artefaktum (normatív forrás: `AGENTS.md` §12; indoklás: a csővezeték elrejti a kilépési kódot — `docs/LESSONS.md` L09). Az alábbi mobil-blokkok mint általános projekt-független ellenőrzések maradnak.
```

**A8 PASS** — egy találat, és a fájl 3 sorral nőtt (a plafon 6 volt). A
hivatkozás közvetlenül a „Tier 4 — before 'DONE' … (the full gate)" cím alá,
a `flutter analyze lib/` blokk **elé** került, tehát az olvasó nem tudja
kihagyni. A skill általános mobil-blokkjai (17., 22., 46. sor) az előírás
szerint **megmaradtak** — a skill nem íródott át StrumSight-ra.

`grep -rn "flutter analyze lib/" …` maradék találatai a `review-loop` és a
`flutter-dev` skillben, valamint a `verify-before-done` általános soraiban —
**mind a §0.2 lezárt döntése szerint elvárt**.

**NOTE-1 és NOTE-2** nem blokkol, javítást nem igényel; a NOTE-1-ből tanulság
lesz (`docs/LESSONS.md`).

### Merge-döntés

A brief §9 szerint ez a kör Dart kódot nem érint, ezért a `tools/round-gate.sh`
nem követelmény; a mérce az A1–A8 mátrix, ami **teljes egészében zöld**, saját,
független újraméréssel. A CI-dispatch a kör-branchre a merge előtt ettől
függetlenül kötelező (ADR 0052) — a run linkje a PR törzsében.

**Verdikt: APPROVED.**
