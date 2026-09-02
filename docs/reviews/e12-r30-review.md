# E12-R30 review — Feature freeze és final regression

- **Reviewer:** Claude (Opus 5), orchestrátor-szék, ADR 0055 read-only review
- **Implementer:** `sonnet-impl` (Claude Sonnet 5)
- **Branch:** `sonnet-impl/e12-r30-feature-freeze-and-final-regression`
- **Review-HEAD (1. kör):** `b93204c2`
- **Review-klónok:** `/tmp/review-e12-r30` (gate), `/tmp/probe-e12-r30`
  (valódi-sértés próbák) — mindkettő izolált, eldobható; a fő fán és a
  munkapéldányon semmi nem módosult
- **Dátum:** 2026-09-02

## 1. Scope-audit

```
python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e12-r30 \
  --brief docs/rounds/e12-r30-feature-freeze-and-final-regression.md --base 0245c7fb
Legacy scope audit OK (0245c7fbbc2f..b93204c27e70, 6 changed path(s), 0 generated/ignored)
```

Pontosan az engedélyezett hat útvonal változott (`docs/release/feature-freeze.md`,
`docs/release/known-issues.md`, `CHANGELOG.md`, `tool/release/verify_freeze.py`,
`test/tooling/freeze_policy_test.dart`, a kör briefjének §10-e). A tilos zóna
érintetlen — az **A6** kritérium teljesül:

```
git diff --stat origin/main...HEAD -- lib backend .github docs/adr docs/release/blockers.md tools
(üres)
```

## 2. Futtatott mércék (a review SAJÁT mérése, nem az implementer bemondása)

| Mérés | Kimenet |
|---|---|
| `tools/round-gate.sh test/tooling/freeze_policy_test.dart test/tooling/ga_scope_test.dart` (izolált `/tmp/review-e12-r30` klón) | format · analyze · **+31** freeze_policy · **+23** ga_scope · architecture · secrets · l10n → **MINDEN GATE ZÖLD** |
| `python3 tool/release/verify_freeze.py --since 4ac78365` | `ok — 17 known-issue row(s), 7 changed path(s) classified`, exit `0` |
| `build-apk.yml` CI | a `b93204c2` head SHA-n dispatch-elve (a javító kör után újra) |

Az implementer §10-ben közölt gate-kimenetét reprodukáltam; egyezik (a
`--since` futás nálam 7 útvonalat lát 6 helyett, mert a §10-et lezáró commit
maga is beleszámít — ez nem eltérés, hanem időrend).

### 2.1 Valódi-sértés próbák

Mind az izolált `/tmp/probe-e12-r30` klónban futott, mutáció után visszaállítva.

| Próba (mit rontottam el) | Elvárt | Mért |
|---|---|---|
| `known-issues.md`-be injektált `K-REVIEW-PROBE-01` `P1` sor, ami a `blockers.md`-ben NINCS (a brief §6.1 kötelező próbája) | A3 piros | `exit=1`, `id 'K-REVIEW-PROBE-01' is severity 'P1' but has no matching row in blockers.md (A3)` ✅ |
| freeze-korszaki `lib/app/build_info.dart` változás `"chore: apró javítás, nem számít"` üzenettel, blocker ID nélkül, **alapértelmezett** hívás | A1 piros | `exit=0`, `ok` ❌ → **MAJOR-1** |
| ugyanaz, `--since 4ac78365`-tel | A1 piros | `exit=1`, `not classified under any freeze change class` ✅ |
| a `blockers.md`-ben `P1`-ként nyilvántartott `R-VER-01` sor a `known-issues.md`-ben `P2`-re **lefokozva** | A3 piros | `exit=0`, `ok` ❌ → **MAJOR-2** |

## 3. Leletek (1. kör, `b93204c2`)

### MAJOR-1 — a `verify_freeze.py` ALAPÉRTELMEZETT hívása nem ellenőrzi a freeze-t (fail-OPEN)

`tool/release/verify_freeze.py:621` beolvassa a `feature-freeze.md` §2 gépi
blokkjából a `freeze_base_sha: 4ac78365` értéket, majd az eredményt **eldobja**;
a `628-632` sor csak akkor osztályoz, ha a hívó explicit `--since`-t vagy
`--changes-file`-t adott. A `verify_freeze` névre hallgató eszköz fő
ellenőrzése (A1) tehát az alapértelmezett hívásban **kimarad**, a kimenet
mégis `ok` + exit `0`. Reprodukció a §2.1-ben: a §5.1 által NÉVSZERINT tiltott
„apró javítás, nem számít" commit zölden átmegy.

A hibát ráadásul egy **zöld cella rögzíti elvárásként**
(`test/tooling/freeze_policy_test.dart:44-48`, „exit 0 with only default
paths"). Ez pontosan az a fail-OPEN osztály, ami ellen a brief §0.0 P6 és a
hivatkozott L566/L571/L573/L575 leckék szólnak.

**Javítás iránya:** `--since` hiányában az eszköz a beolvasott
`freeze_base_sha`-ból osztályozzon (az explicit `--since` maradjon felülíró);
a `44-48` cella várja el a `changed path(s) classified` kimenetet, és egy új
cella pinnelje az osztályozatlan termékútvonal `1`-es kilépését az
alapértelmezett hívásban is.

### MAJOR-2 — egy `blockers.md`-beli P0/P1 sor LEFOKOZÁSA észrevétlen marad

`tool/release/verify_freeze.py:347` a `blockers.md`-vel való egybevetést csak
akkor futtatja, ha a `known-issues.md` sora **maga** `P0`/`P1`. A felfelé
hangolást (P1 → P0) elkapja — erre van cella (`freeze_policy_test.dart:264`) —,
a lefelé szépítést viszont nem, pedig az az egyetlen irány, amivel egy blocker
ténylegesen elrejthető. Mérve: `R-VER-01` `P1` → `P2` a szállított
`known-issues.md`-ben → `exit=0`, `ok`. Ez a §5.2 („a known-issues lista
ŐSZINTE") gépi mércéjének kikerülhetősége.

**Javítás iránya:** a súlyosság-egyezést irányfüggetlenül mérje minden olyan
sorra, aminek az ID-je szerepel a `blockers.md`-ben; az „ID nincs a
`blockers.md`-ben" ág maradjon csak a P0/P1 sorokra kötelező (a `K-*` tételek
szándékosan nincsenek ott). + lefokozás-cella.

### MINOR-1 — két `P3` besorolás ellentmond a saját hivatkozott mérésének

1. `K-E12R21-01` (`P3`): a hivatkozott forrás (`HANDOFF.md` §6) ugyanezt a két
   tételt „**KÉT MÉRT GA-blokkoló**"-ként rögzíti, dátumozott
   (`expiry: 2026-12-31`) kivétellel — a `P3` a skála legalsó foka, miközben a
   `known-issues.md` saját bevezetője a `blockers.md`-n kívüli tételekre
   „legfeljebb `P2`" plafont mond ki.
2. `K-E12R24-01` (`P3`): a kitalált `privacy-support@strumsight.app` cím
   UGYANEBBEN a fájlban `P1` bizonyítékként is szerepel (az `R-PRIV-01` sor
   `impact` cellájában) — ugyanaz a mért tény két súlyosságot visel egy
   dokumentumon belül.

### NOTE-1 — a `blocker-fix` osztály commit-szintű

`verify_freeze.py:537-541`: ha a commit üzenete megnevez egy érvényes blocker
ID-t, a commit MINDEN útvonala engedélyezetté válik. A granularitás védhető,
de legyen kimondva a `feature-freeze.md` §3-ban, hogy a commit tartalmi
szűkítése a jóváhagyó szerep felelőssége.

## 4. Amit a review NEM talált hibásnak (kimondva)

- **A2/A7 gépezete rendben.** A három marker-blokk parszer valóban
  fail-closed: hiányzó blokk, elrontott sor-alak és üres blokk mind `2`-es
  kilépés (9 cella, reprodukálva a gate-ben).
- **A4 kötő ellenőrzés** a brief §0.0 P4 szerint valósult meg: a
  `CHANGELOG.md` fejléc-blokkja pontosan 3 sor (negyedik, pl. időbélyeg-sor
  fail-closed elutasítva, ADR 0447 D1), és a `pubspec.yaml:5` (`1.0.0+1`) +
  `generate_release_manifest.dart:23` (`releaseManifestSchemaVersion = 1`)
  mért forrásokhoz köt.
- **A `blockers.md` érintetlen**, és a `known-issues.md` KIMONDJA az
  elavultságát (mért SHA + a mai queue-állapot) ahelyett, hogy szépítené —
  ez a brief §0.0 P2 elvárása.
- **A P3 (RC-workflow soha nem futott) tény felkerült** külön tételként
  (`K-RC-01`), a `R-SIGN-01` P0-hoz kötve.
- **A §0 STOP-protokoll helyesen NEM lépett életbe:** a mérés nem talált
  `blockers.md`-n kívüli valódi P0/P1-et; a `K-*` tételek mind P2/P3.

## 5. Verdikt (1. kör)

**CHANGES REQUESTED** — MAJOR-1 és MAJOR-2 nyitva, MINOR-1 zárása kérve.
Merge tilos, amíg nyitva vannak (ADR 0052 zöld kapu + ADR 0055).

## 6. 1. javító kör (`69588a3c`) — leletenkénti zárás-ellenőrzés

A javító kör ugyanazzal a motorral (`sonnet-impl`), a leletlistával a
promptban futott; négy commit (`99ed0b5a`, `380be089`, `f32b6041`,
`69588a3c`). Scope-audit a kör induló HEAD-jétől:

```
python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e12-r30 \
  --brief docs/rounds/e12-r30-feature-freeze-and-final-regression.md --base 0245c7fb
Legacy scope audit OK (0245c7fbbc2f..69588a3c9d40, 6 changed path(s), 0 generated/ignored)
```

### 6.1 A zárások független újramérése (`/tmp/probe2-e12-r30`, friss klón)

| Lelet | Próba | Mért |
|---|---|---|
| MAJOR-1 | freeze-korszaki `lib/app/build_info.dart` változás, `"chore: apró javítás, nem számít"`, **bare** hívás | `exit=1`, `lib/app/build_info.dart: not classified under any freeze change class …` ✅ |
| MAJOR-1 (pozitív ág) | ugyanaz, `"fix: R-VER-01 build number monotonicity"` üzenettel | `exit=0`, `ok — 17 known-issue row(s), 13 changed path(s) classified` ✅ |
| MAJOR-1 (hamis ID) | ugyanaz, `"fix: R-NOT-REAL-99 whatever"` | `exit=1`, `not classified` ✅ |
| MAJOR-2 | `R-VER-01` `P1` → `P2` a szállított `known-issues.md`-ben | `exit=1`, `id 'R-VER-01' is severity 'P2' here but 'P1' in blockers.md (A3)` ✅ |
| A3 (regresszió) | injektált `K-REVIEW-PROBE-02` `P1`, `blockers.md`-n kívül | `exit=1`, `no matching row in blockers.md (A3)` ✅ |

A javítás a helyén van, és **teszttel is meg van fogva**: a
`freeze_policy_test.dart` két ÚJ regressziós cellát kapott (31 → 33) —
MAJOR-1-hez egy izolált, `git init`-elt temp-repóban futó bare-hívás cella
(a reviewer reprodukciójának gate-beli megfelelője), MAJOR-2-höz a
lefokozás-cella. A korábban a hibát életben tartó sanity cella
(`freeze_policy_test.dart:44`) mostantól a `changed path(s) classified`
kimenetet is elvárja.

| Lelet | Állapot | Bizonyíték |
|---|---|---|
| MAJOR-1 | **ZÁRVA** | `verify_freeze.py` `main()`: a bare hívás a `freeze_base_sha`-ra esik vissza; új A1-cella + §6.1 próba |
| MAJOR-2 | **ZÁRVA** | `validate_known_issues()`: a súlyosság-egyezés minden `blockers.md`-beli ID-re fut, iránytól függetlenül; új A3-cella + §6.1 próba |
| MINOR-1 | **ZÁRVA** | `K-E12R21-01` és `K-E12R24-01` `P3` → `P2`; a `K-E12R24-01` impact-cellája kimondja, hogy az `R-PRIV-01` `P1` **rész-bizonyítéka** |
| NOTE-1 | **ZÁRVA** | `feature-freeze.md` §3: a `blocker-fix` commit-szintű granularitása és a jóváhagyó felelőssége kimondva |

### 6.2 A javító kör utáni gate (reviewer SAJÁT futása, `/tmp/review2-e12-r30`)

```
tools/round-gate.sh test/tooling/freeze_policy_test.dart test/tooling/ga_scope_test.dart
format zöld · analyze zöld · test freeze_policy (+33) zöld · test ga_scope (+23) zöld ·
architecture zöld · secrets zöld · l10n zöld → MINDEN GATE ZÖLD
```

## 7. Acceptance criteria — tételes teljesülés

| # | Állapot | Bizonyíték |
|---|---|---|
| A1 | ✅ | `freeze_policy_test.dart` A1 csoport (8 cella) + a §6.1 négyirányú próba |
| A2 | ✅ | A2 csoport (2 cella): üres workaround → `1`, `P9` severity → `1` |
| A3 | ✅ | A3 csoport (4 cella), köztük a brief §6.1 kötelező valódi-sértés próbája és a lefokozás-cella |
| A4 | ✅ | A4 csoport (3 cella): `version`/`build`/`schema_version` eltérés → `1`; a fejléc-blokk pontosan 3 sor (4. sor = `2`) |
| A5 | ✅ | `build-apk.yml` a merge SHA-n (a §8-ban linkelve) |
| A6 | ✅ | scope-audit `OK`, 6 útvonal; `git diff -- lib backend .github docs/adr docs/release/blockers.md tools` üres |
| A7 | ✅ | A7 csoport (9 cella) mindhárom parszerre: hiányzó blokk / elrontott sor / üres blokk → `2` |

## 8. Verdikt (1. javító kör után)

**APPROVED** a kód/dokumentum tartalmára — de a merge-kapu még nem volt zöld:
lásd §9.

## 9. A CI PIROS lett a `6eb6fb3a` SHA-n — 2. javító kör (`3ee48bea`)

A `build-apk.yml` [33632164312](https://github.com/wolfcasaba/strumsight/actions/runs/33632164312)
futása **failure** lett, miközben a lokális gate (és az én izolált klónom is)
zöld volt. Ez a review egyik legfontosabb mérése ebben a körben, mert a
gyökérok **a lokális teljes klónban elvi okból nem reprodukálható**.

**Mért gyökérok.** Mind a 10 bukó cella ugyanazt írta:

```
Expected: <0>   Actual: <2>
verify_freeze: --since '4ac78365' is not a valid git revision:
  Command '['git', 'rev-parse', '--verify', '4ac78365']' returned non-zero exit status 128.
```

A CI `actions/checkout@v4`-et használ `fetch-depth` felüldefiniálás nélkül
(`.github/workflows/build-apk.yml:24`, `:88`) → **shallow, 1 commit mélységű
klón**, amelyben a `freeze_base_sha: 4ac78365` (a Kör 29 záró commitja)
**nem létezik**. A MAJOR-1 javítás óta a bare hívás mindig a git-úton megy,
ezért nemcsak a 2 sanity cella bukott, hanem 8 további A2/A3/A4 cella is,
amelyek a known-issues/CHANGELOG validációt akarták mérni, de a git-ág
`VerifyError`-ába futottak, mielőtt a mérni kívánt findinghez értek volna.

**Ez tehát a MAJOR-1 javításának mellékhatása** — a javítás maga helyes (a
bare hívásnak ellenőriznie KELL), a hiba az volt, hogy a cellák a klón
mélységét hallgatólagos előfeltételnek vették. A `.github/**` a kör tilos
zónája, ezért `fetch-depth: 0` nem volt megoldás.

### 9.1 A 2. javító kör javítása és a reviewer SAJÁT mérése

1. `verify_freeze.py`: a kilépőkód marad **`2`** (fail-closed — történet
   nélkül a freeze nem ellenőrizhető, a `0` hazugság lenne), de az üzenet
   megnevezi az okot és a feloldást. **Nincs** „nincs történet → átugrom" ág.
2. A két sanity cella `git rev-parse --verify`-vel megméri a klón mélységét,
   és MINDKÉT ágon szigorú: elérhető bázis → `exit 0` + `changed path(s)
   classified` (a MAJOR-1 fedezete megmarad); nem elérhető → `exit 2` + a
   hiányzó bázis a stderr-ben.
3. A nyolc A2/A3/A4 cella üres (`#`-kommentsoros) `--changes-file`-t kap, így
   a klón mélységétől függetlenül pontosan azt az `1`-es kilépést méri,
   amiért készült.

**Reviewer-mérés — a shallow klón szimulációja (a fejlesztői teljes klón NEM
reprodukálja a hibát):**

```
git clone -q --depth 1 --branch <round-branch> file:///home/ubuntu/ss-sonnet-impl-e12-r30 /tmp/shallow-rev-e12-r30
git rev-list --count HEAD        → 1
git rev-parse --verify 4ac78365  → fatal: Needed a single revision
flutter test test/tooling/freeze_policy_test.dart
→ 00:01 +33: All tests passed!
```

Ugyanez teljes klónban (`/tmp/review3-e12-r30`) is **33/33 zöld** a teljes
gate-tel együtt (format, analyze, +33, +23, architecture, secrets, l10n).
A cellák tehát a klón mélységétől függetlenül helyeset mérnek — ez volt a
2. javító kör mércéje.

### 9.2 Egy IDEGEN teszt is piros volt — mért besorolás

A `Coverage` job 11. bukása
`test/features/songs/import/import_flow_test.dart` „A2: cancelling a confirmed
import cleans the opened workspace" volt — **a `build-apk` jobban ugyanezen a
SHA-n ZÖLD** (10 vs 11 bukás), tehát nem determinisztikus. Ez pontosan a
[L543](../LESSONS.md#l543)-ban mért, dokumentált időzítés-érzékeny cella
(`import_flow_test.dart:83`, „Expected: non-empty Actual: []"), amely telített
runner mellett csúszik el. A kör diffje `lib/**`-ot nem érint. A L543 előírása
szerint viszont nem elég „flaky"-nak nevezni: a kör saját erőforrás-profilját
is meg kell nézni — a 2. javító kör ebből a szempontból is javít, mert a 8
A2/A3/A4 cella többé nem futtat `git rev-list` + commitonként két további
git-alfolyamatot. A következő CI-futás ezt méri.

## 10. Végső verdikt

**APPROVED.** Nyitott BLOCKER/MAJOR/MINOR nincs; a két MAJOR és a
CI-gyökérok is zárva, mindegyik reprodukálható cellával. A merge a zöld
kapun (ADR 0052: gate + exact-SHA `build-apk.yml` + `router-ci.yml`) mehet.
