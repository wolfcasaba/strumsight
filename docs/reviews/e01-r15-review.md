# E01-R15 review — Backend és ML CI

Reviewer: Claude (ADR 0055 szerinti független review; production kód a review
alatt nem változott)
Dátum: 2026-07-30
Vizsgált fej: `66c87e5` (`codex/epic-01-round-15-backend-ml-ci`, 8 commit a
brief-commit fölött)
Brief: [`docs/rounds/e01-r15-backend-and-ml-ci.md`](../rounds/e01-r15-backend-and-ml-ci.md)

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 4

## Scope-audit

`git diff --stat a281ae4..66c87e5` — 18 fájl, mindegyik a brief §4 táblájában:
a workflow, a requirements-pár, a pyproject, a README, a generátor, a manifest,
a guard-teszt, a brief §10-e, és a `backend/app+tests` formázó-diffje. Tilos
zónás fájl **nem változott** (külön ellenőrizve: `pubspec.yaml`, `tool/ci/`,
`.bin`-ek, a többi workflow, `HANDOFF.md` — mind érintetlen). A Codex nem hívott
`gh`-t és nem pushol; a commit-felosztás a §8 sorrendjét követi, a Ruff-formázás
önálló commit (`1e1ba32`) — §5.4 teljesül.

## Függetlenül újramért gate-ek (a saját checkoutomon, nem a Codexén)

| Gate | Eredmény |
|---|---|
| `ruff check app tests` | **All checks passed!** |
| `ruff format --check app tests` | **20 files already formatted** |
| `python -m pytest -q` (backend) | **64 passed** — a baseline nem csökkent |
| `python3 ml/make_manifest.py` | **unchanged** (idempotens, üres git-diff) ✓ §6 |
| `flutter test test/tooling` | **15 passed** (12 régi + 3 új) |
| Backend CI a kör-branchen | run [30517873919](https://github.com/wolfcasaba/strumsight/actions/runs/30517873919) **zöld** (push-trigger) |

## Saját piros-út próba (a Codexétől független sértéssel)

A Codex a `chord_crnn.bin` utolsó bájtját rontotta; én a
**`strum_crnn_live_3c.bin` 100. bájtját** nulláztam:

```
checksum mismatch for assets/ml/strum_crnn_live_3c.bin:
expected a9ea77d7… actual 062427ef…
Some tests failed. (exit 1)
```

Visszaállítás után `git diff` üres, a teszt 3/3 zöld. A guard fog, és nem a
Codex fixture-jére van hangolva.

## A formázó commit viselkedés-azonossága — függetlenül auditálva

Saját AST-összevetés (`ast.dump` régi vs. új, mind a 9 fájlra): 6 fájl
bitre azonos AST; 3 fájl (`app/main.py`, `tests/test_diagnostics.py`,
`tests/test_migrations.py`) AST-szinten eltér, de a diff **kizárólag
import-átrendezés/-szétbontás** (Ruff `I` szabály), ami viselkedés-azonos.
Logikai változás nincs — §5.4 és a §6 „nem tartalmaz logikai változást"
kritérium teljesül. (Lásd NOTE-1 a Codex-oldali audit megfogalmazásáról.)

## A provenance-döntés felülvizsgálata (a brief §5.3-tól való pozitív eltérés)

A brief a rekonstruálhatatlan esetre `origin: pre-manifest`-et írt elő. A Codex
ehelyett **rekonstruálta** mind a négy bináris shipping-revízióját, és
`origin: repository-history` + git-SHA-t írt. Mind az öt hivatkozott commitot
függetlenül ellenőriztem — léteznek, és a dátumuk egyezik a `created_at`-tal:

| Asset | Commit | Tartalma |
|---|---|---|
| chord_crnn | `9150dbc` (07-15) | round204: GuitarSet-trained chord model |
| strum_crnn | `66c0f9a` (07-13) | round163: strum CRNN + pure-Dart inference |
| strum_crnn_live | `cb325a2` (07-13) | round168: live 70ms CRNN |
| strum_crnn_live_3c | `f9293d6` (07-14) | round175: learned no-strum reject |
| export (chord) | `ea2bc10` (07-14) | round195: CCRN export script |

Ez nem kitalált azonosító (amit az 5.3 tilt), hanem **mért** provenance — a
brief szellemének megfelelő, jobb kimenet. A guard ráadásul rögzíti a négy
ismert revíziót, így visszacserélni sem lehet őket némán.

## Az R14-review MINOR-1 lezárása

A manifest-teszt a manifestből indul (négy kötelező bejegyzés), és
**mindkét irányban** ellenőrzi a pubspec-konzisztenciát (manifest→pubspec és
pubspec→manifest, a meglévő `checkAssets` importjával — a `tool/ci/` fájl
módosítása nélkül, §5.7 szerint). A Codex (c) piros útja a fixture-pubspecből
törölt deklarációval bizonyítja: üres/hiányos deklaráció → PIROS. **MINOR-1
lezárva.**

## Megállapítások

### NOTE-1 — a §10 „FORMAT_ONLY mind a 9 fájlra" állítás normalizált auditra igaz

A nyers AST-összevetés 3 fájlnál eltérést ad (import-sorrend). A Codex
állítása a viselkedésre nézve helyes, de az auditja láthatóan normalizálta az
importokat — a jelentésben pontosabb lett volna ezt kimondani. Nem hiba,
tanulság a jövőbeli evidencia-megfogalmazáshoz.

### NOTE-2 — kézzel írt SHA-256 a Dart-tesztben

A `pubspec.yaml` tilos zóna, így a `crypto` csomag nem volt felvehető — a
teszt saját SHA-256 implementációt hoz (~80 sor). Fedezete: két standard
NIST-vektor a tesztben + a négy valódi bináris Python-oldalon (hashlib)
számolt checksumjával való egyezés minden zöld futásban kereszt-validál.
Elfogadható trade-off; ha a `crypto` egyszer közvetlen dependency lesz, a
helyettesítés triviális follow-up.

### NOTE-3 — a négy ismert training-run azonosító a tesztben is hardcode-olt

Modellcserénél a manifest ÉS a teszt `_knownTrainingRunIdentifiers` táblája is
frissítendő — ez szándékos súrlódás (a modellcsere-szabály gépi fedezete,
SDD 15.6): binárist némán se kicserélni, se „pre-manifest"-re visszaminősíteni
nem lehet. A hibaüzenet explicit, a frissítés helye egyértelmű.

### NOTE-4 — a `backend-ci.yml` push-triggere branch-szűrés nélküli

Minden branch-push, ami `backend/**`-t érint, futtatja a backend CI-t. Ez ma
kívánatos (a kör-branchek pont így kapnak gate-et, lásd a zöld run-t), és a
backend CI olcsó (~1 perc). Ha a párhuzamos munka miatt zajos lenne, szűkítés
R16+ kérdés.

## Verdikt

**APPROVED.** BLOCKER, MAJOR és MINOR nincs. A kör mindkét fő állítását
teljesíti: a backend 64 tesztje mostantól merge előtt, CI-ben fut (a kör-branchen
bizonyítottan zölden), és a négy shippelt ML-bináris SHA-256 manifest +
guard-teszt mögé került — a gate fogát a Codexétől független sértéssel magam is
igazoltam. Az R14-review MINOR-1 lezárva; MINOR-2/3 a terv szerint az R16
pre-flight bemenete. A formázó commit függetlenül auditáltan viselkedés-azonos,
a provenance-eltérés a briefnél jobb, mért kimenet.

Merge-feltétel (ADR 0052): a `build-apk.yml` futás zöldje a kör-branchen —
a merge a futás lezárultával, külön lépésben.
