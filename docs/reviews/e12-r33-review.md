# E12-R33 review — Staged rollout 50–100% és GA

- **Kör:** `E12-R33` (Chapter 12, Kör 33)
- **Branch:** `sonnet-impl/e12-r33-staged-rollout-50-to-100-and-ga`
- **Reviewelt HEAD:** `bfd0c2fd2ffc193aa57763ed62a436216a752a77`
- **Implementer:** Claude Sonnet 5 (`sonnet-impl`, `--effort high`)
- **Reviewer:** Claude Opus 5 (orchestrátor), READ-ONLY, izolált klón
  (`/tmp/review-e12-r33`), 2026-09-02
- **Diff:** 5 fájl, +1854 / −5

## VÉGSŐ DÖNTÉS: **APPROVED** — 0 nyitott BLOCKER/MAJOR/MINOR

## 1. Scope-audit

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e12-r33 \
    --brief docs/rounds/e12-r33-staged-rollout-50-to-100-and-ga.md --base origin/main
Legacy scope audit OK (6ae19fce159a..bfd0c2fd2ffc, 5 changed path(s), 0 generated/ignored)
exit=0
```

Az implementer jelzésfájljában **nem volt `scope_audit=` kulcs**, ezért az
audit a szerződés szerint bizonyítatlan maradt — a fenti kézi futtatás pótolja.
Mind az 5 útvonal az `allowed_paths` listán van; a tilos zóna (`lib/**`,
`backend/**`, `.github/**`, `tools/**`, `docs/adr/**`,
`docs/release/staged-rollout-log.md`) **érintetlen**.

## 2. A kötelező gate — függetlenül újrafuttatva

Izolált klónban, a review HEAD-jén, `prepare-flutter-generated.sh` után:

```
$ tools/round-gate.sh test/tooling/ga_record_test.dart test/tooling/rollout_decision_test.dart
format zöld · analyze zöld · test ga_record_test.dart zöld · test rollout_decision_test.dart zöld (28 cella)
architecture zöld (12 allowlisted deviation) · secrets zöld (4190 fájl, 0 lelet) · l10n zöld (en→hu, 2298 üzenet)
MINDEN GATE ZÖLD          exit=0
```

## 3. Valódi-sértés próbák — a REVIEW SAJÁT, eldobható próbái

Nem az implementer §10-ét fogadtam el: a `verify_ga_record.py`-t 12 saját
mutációval mértem meg az izolált klónban, majd minden esetben visszaállítottam
(`git status` a végén tiszta).

| # | Mutáció | Elvárt | Mért |
|---|---|---|---|
| P0 | érintetlen rekord | `0` | **`0`** (`ga_status=not-yet, 16 flag(s)`) |
| P1 | `app_build_number` `1` → `2` | `1` (A2) | **`1`** |
| P2 | `ml_manifest_sha256` egy karaktere átírva | `1` (A2) | **`1`** |
| P3 | `ga_status` → `ga` | `1` (A7) | **`1`** — `step(s) ['stage-1','stage-5','stage-20'] are not 'approved' (A7)` |
| P4 | `ga_status` → `shipped` (zárt készleten kívül) | `1` (A1) | **`1`** |
| P5 | egy flag-sor törölve | `1` (A3) | **`1`** |
| P6 | `adaptiveShellEnabled` besorolása `preview` → `ga` | `1` (A3) | **`1`** |
| P7 | `rollback_target` → `TBD` | `1` (A4) | **`1`** |
| P8 | `rollback_target` → nem létező útvonal | `1` (A4) | **`1`** |
| P9 | az emberi-közzététel mondat átírva | `1` (A6) | **`1`** |
| P10 | a `ga-status` marker-blokk törölve | `2` (fail-closed) | **`2`** |
| P11 | visszaállítás után | `0` | **`0`** |

**P12 — inverz próba (a legfontosabb).** Egy „mindig piros" A7 használhatatlan
lenne a valódi GA pillanatában, ezért megmértem az ellenkező irányt is:
szintetikus `staged-rollout-log` (mind a 3 lépcső `approved`) + üres
blocker-tábla mellett a `ga_status: ga` **`exit=0`**-t ad. Az invariáns tehát
**adat-vezérelt, nem bedrótozott tiltás** — ma pirosat ad, a valódi GA-kor
zöldet.

## 4. Acceptance criteria

| # | Kritérium | Verdikt | Bizonyíték |
|---|---|---|---|
| A1 | kitöltetlen/placeholder kötelező mező → nem-nulla | ✅ | P4, P7 |
| A2 | verzió-mezők = manifest-bemenetek | ✅ | P1, P2; a Dart-oldali összevetés a `generate_release_manifest.dart` importjával (`ga_record_test.dart:33`, `_buildRealManifest()`) — a §0.0.1 P3 előírt útvonala |
| A3 | flag-profil pillanatkép (16 kulcs) | ✅ | P5, P6; élő összevetés a `ga-scope.md` marker-blokkjával, nem befagyasztott másolat |
| A4 | érvényes rollback-cél | ✅ | P7, P8 |
| A5 | determinisztikus release-notes + `known-issues.md` | ✅ | nincs ISO-8601 minta a jegyzetben; a teszt **saját vakság-őrt** is tartalmaz (a regex bizonyítottan felismer egy valódi időbélyeget) |
| A6 | a publikálás EMBERI művelet | ✅ | P9; `ga-record.md` §8 |
| A7 | `ga_status: ga` tiltása nyitott P0/P1 vagy nem-`approved` lépcső mellett | ✅ | P3 + **P12 inverz** |

## 5. A §0.0.1 pre-flight revízió teljesülése

- **P2/§5.4** — a `ga_status` gépi mező zárt értékkészlettel megvan, a
  szállított érték `not-yet` (helyes: ma 3 `pending` lépcső + 1 P0 + 5 P1).
- **P3** — a Python ellenőrző **nem** olvas statikus manifest fájlt és **nem**
  hív `dart run`-t (`grep` mérve); a három deklarált bemenetből számol újra.
- **P4** — mind a 16 kulcs jelen van, élő összevetéssel.
- **P5** — a rollback-cél a fán feloldható útvonal.
- **P6** — ADR nem született, a `docs/adr/**` érintetlen.
- **P7** — az engedélyezett-fájllista változatlan.

## 6. Leletek

**BLOCKER:** nincs. **MAJOR:** nincs. **MINOR:** nincs.

**NOTE-1 (nem blokkoló).** Az implementer jelzésfájlja `dirty_files=1`-et írt,
miközben a fa a mérés pillanatában tiszta volt (`git status --short` üres, 3
commit) — a számláló a záró `docs(handoff)`-commit előtti pillanatképet
rögzítette. Kivizsgálva, valós eltérés nincs.

**NOTE-2 (nem blokkoló, jövőbeli kör anyaga).** A rekord §2 build-SHA, §6
support-link és §7 publikálási időbélyeg mezői szándékosan
`GA UTÁN, EMBERI KITÖLTÉS` jelölésűek. Az `A1` placeholder-szabály ezeket a
prózában élő `<...>` jelöléseket **nem** méri (a marker-blokkokon kívül
vannak), tehát ha egy ember GA-kor elfelejti kitölteni őket, azt gépi őr ma
nem fogja meg — az `A7` viszont igen, amint `ga_status: ga`-t akar állítani
nyitott blockerek mellett. A rés zárása (a három emberi mező marker-blokkba
emelése és A1-hatókörbe vonása) egy jövőbeli kör olcsó munkája.

## 7. CI

- **Router CI** `33673090369` — **success**, `headSha=bfd0c2fd` (exact-SHA).
- **Full Gate** `33673087297` — a `round-ci-plan.py` terve
  (`dispatch: ["full-gate.yml"]`, `native_gate=false`, `apk_required=false`).
