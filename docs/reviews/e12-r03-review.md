# E12-R03 — Review

- **Kör:** `E12-R03` — GitHub delivery workflow, branch protection és review policy
- **Brief:** [`docs/rounds/e12-r03-delivery-workflow-and-branch-protection.md`](../rounds/e12-r03-delivery-workflow-and-branch-protection.md)
- **ADR:** [`0444`](../adr/0444-delivery-workflow-and-repository-policy.md) (D1–D6)
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5)
- **Reviewer:** Claude Opus 5 (orchesztrátor, read-only review — ADR 0055)
- **Review-bázis:** `de8d8eec` (pre-flight commit) → `27f22591` (implementáció)
  → `149582f1` (javító kör)
- **Izolált review-klón:** `/tmp/review-e12-r03` (a munkapéldányból klónozva,
  `prepare-flutter-generated.sh` után)

## Összegzés

A kör a teljes §3 scope-ot leszállította: öt issue-sablon + `config.yml`,
jelölő `.github/CODEOWNERS`, a PR-sablon `## Release evidence` bővítése,
`docs/process/backlog-policy.md`, `docs/process/branch-protection.md`,
`tool/audit_repository_policy.py` és a 28 cellás
`test/tooling/repository_policy_test.dart`. A gate zöld volt már az első
átadáskor is — a review mégis **1 MAJOR + 1 MINOR** leletet talált, mindkettőt
a reviewer SAJÁT valódi-sértés próbáival, nem szemrevételezéssel.

A MAJOR (F1) tanulságos: a kör anti-vakon-zöld őrei közül **pont az önvédő
cella volt vakon zöld** egy `Process.start` hívásra — arra a hibaosztályra,
amit az L110 óta mérni akarunk. Egy javító kör után mindkettő ZÁRVA, a
reprodukció mindhárom `dart:io` belépési pontra pirosra vált.

**VÉGSŐ DÖNTÉS: APPROVED** (0 BLOCKER / 0 MAJOR / 0 MINOR / 2 NOTE).

## Leletek

### F1 — MAJOR — Az A8 önvédő cella vakon zöld a `Process.start` alakra, és többet állít, mint amit mér

**Fájl:** `test/tooling/repository_policy_test.dart`, A8 group (`27f22591`).

Az A8 cella deklarált célja az [L110](../LESSONS.md#l110) hibaosztály
megfogása: egy külső binárisra (`rg`) shell-elő guard a boxon ZÖLD, a
CI-runneren PIROS. A cella a saját forrását olvasta, és egyetlen darabolt
konstanst keresett benne: `'Process' + '.run'`.

**A reviewer reprodukciója** (izolált klón, `27f22591`) — a guard fájl
`main()`-jének elejére beszúrva `final _unused = Process.start('rg', ['-n','x']);`:

```
$ flutter test test/tooling/repository_policy_test.dart
00:00 +28: All tests passed!
```

**A pontosan mérni kívánt hibaosztály átment a saját őrén.** Két hiba egyben:

1. **Hiányos minta.** A `dart:io` külső-folyamat belépési pontja **három**
   (`Process.run`, `Process.runSync`, `Process.start`), de csak **kettő**
   osztozik a `Process.run` prefixen. A `Process.start` lefedetlen maradt.
2. **Túlállító doc-comment.** A group neve („never shells out to an external
   binary"), a teszt neve („never spawns an external process") és a komment
   („one check covers **both** external-process entry points") olyan
   tulajdonságot állított, amit a mérés nem fedett — szemben a brief §5
   doc-comment fegyelmével.

**Miért nem BLOCKER:** a `27f22591` fán ténylegesen nem volt `Process.*`
hívás, tehát a kör kiadott állapota nem volt hibás — a defektus a jövőbeli
regresszió elleni védelemben volt.

### F2 — MINOR — Az A6 tiltott-minta halmaz nem különbözteti meg az ELŐÍRÁST a TILALOMTÓL, és ez sehol nem volt kimondva

**Fájlok:** `test/tooling/repository_policy_test.dart`
(`forbiddenHumanApprovalPatterns`), `tool/audit_repository_policy.py`
(`FORBIDDEN_HUMAN_APPROVAL_PATTERNS`), `docs/process/branch-protection.md`.

**A reviewer reprodukciója** — a `branch-protection.md` végére fűzve egy
mondat, ami a D1 szabályt a SAJÁT szavaival mondja ki (nem sérti):

```
A `required_approving_review_count: 1` beállítás TILOS — kötelező emberi
jóváhagyás nem lehet a merge feltétele.
```

```
Failing tests:
  … A6 — no required human approval (ADR 0444 D1) the real
     branch-protection.md contains no forbidden pattern
```

A hamis pozitív iránya **fail-closed**, tehát önmagában nem veszélyes, és a
mintát negáció-érzékennyé tenni fölös bonyolítás. **A lelet az volt, hogy ez
a korlát sehol nem volt kimondva:** egy későbbi szerkesztő, aki a szabályt
egyszerűen leírja a dokumentumba, érthetetlen pirosat kap, és a kézenfekvő
„javítás" a MINTA GYENGÍTÉSE lenne — ami pont a D1 őrét ölné meg.

### F3 — NOTE — A szűkített YAML-részhalmaz kizár legitim GitHub issue-form kulcsokat

**Mérve:** a `feature.yml`-be egy `assignees:` blokkot beszúrva (a GitHub
Issue Forms hivatalosan támogatott kulcsa, és **PyYAML gond nélkül
beolvassa** — `top-level keys: ['name','description','title','assignees','labels','body']`)
az A1 cella PIROSRA vált, mert a `parseIssueForm` ismeretlen top-level
kulcsot dob.

Ez az ADR 0444 D3 **szándékos, dokumentált** következménye (a parser
doc-commentje kimondja: „A file needing one of these forms … needs rewriting
into the subset"), és a viselkedés **hangos**, nem néma — tehát nem lelet,
csak rögzített költség. A `projects:` és `type:` kulcsra ugyanez áll. Ha egy
későbbi kör használni akarja őket, a parsert bővíteni kell, nem megkerülni.

### F4 — NOTE — A CODEOWNERS fantom-út ellenőrzés glob-mintát is fantomnak lát

A `findPhantomCodeownersPaths` a mintából levágja a vezető/záró `/`-t, és
`FileSystemEntity.typeSync`-kel méri a létezést. Egy legitim glob CODEOWNERS-
minta (`*.dart`, `/lib/**/audio/`) így „fantom-útvonalnak" minősülne. A
jelenlegi fájl mind a 14 mintája **konkrét könyvtár**, tehát ma nincs hatása,
és az irány **fail-closed**. Follow-up, ha egy későbbi kör glob-mintát vezet
be.

## Acceptance criteria — tételesen

| # | Verdikt | Bizonyíték |
|---|---|---|
| A1 | ✅ | mind az öt sablon átmegy a `parseIssueForm`-on és mind a hat kötelező mezőt `required: true`-val hordozza; a hiányzó mezőt **fixture-ből** méri (nem `contains`-szel) — a reviewer valódi-sértés próbája (`bug.yml` `rollback` törlése) az A1 cellát váltotta pirosra |
| A2 | ✅ | `blank_issues_enabled: false`; a `parseBlankIssuesEnabled` hiányzó kulcsra `null`-t ad (a hívó fail-closed) |
| A3 | ✅ | mind a 14 CODEOWNERS-minta létező útvonalra mutat; a reviewer külön mérte, hogy `/assets/models/` és `/lib/audio/` fantomként bukik |
| A4 | ✅ | a mért 11 szakasz-fejléc mind megmaradt, a 12. (`## Release evidence`) hozzájött; fixture-cella méri a `## Tesztek` és `## Rollback` elvesztését |
| A5 | ✅ | `python3 tool/audit_repository_policy.py --dry-run` → `exit 0` a valós fán; a reviewer külön mérte: hiányzó `rollback` mező → `exit 1`, fantom `/assets/models/` → `exit 1`; hálózati hívás nincs a forrásban, a `gh api` parancsot csak `print`-eli |
| A6 | ✅ | a `branch-protection.md` §3 az approving-review mezőt kifejezetten **user-opcióként** írja le; a guard mindkét fájlon méri a tiltott mintákat; `required_approving_review_count: 0` NEM sértés (külön cella) |
| A7 | ✅ | a PR-sablon kötelezően kitöltendő release-asset sort kapott, a `backlog-policy.md` §5 kimondja a szabályt; a reviewer a sor törlésével pirosra mérte |
| A8 | ✅ (**a javító kör után**) | lásd F1 — a `149582f1` fán mind a három `dart:io` belépési pontra piros |

## Scope

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e12-r03 \
    --brief docs/rounds/e12-r03-delivery-workflow-and-branch-protection.md --base de8d8eec
Legacy scope audit OK (de8d8eece3ec..27f22591e015, 13 changed path(s), 0 generated/ignored)
```

A javító kör gépi audit-ja a wrapper jelzésfájljából: `scope_audit=ok`,
`scope_audit_base=27f22591…`, `scope_audit_changed=4`.

A tilos zóna érintetlen: `.github/workflows/**`, `.github/actions/**`,
`docs/execution/**`, `docs/adr/**`, `lib/**`, `backend/**`, `tools/**` egyike
sem változott. A `pubspec.yaml` / `pubspec.lock` nem módosult — az ADR 0444 D3
`package:yaml`-tilalma tartott.

## Gate-bizonyíték — a reviewer SAJÁT futtatása izolált klónban

`27f22591` (implementáció), `/tmp/review-e12-r03`:

```
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/repository_policy_test.dart              zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
gate_exit=0
```

`149582f1` (javító kör) — ugyanaz a hat lépés, `gate_exit=0`; a
`repository_policy_test.dart` 28/28 cella zöld.

## Próbatesztek (eldobható, reviewer-oldali)

Öt valódi-sértés próba, mind az izolált klónban, mind visszaállítva
(`git status --porcelain` a próbák után tiszta):

| # | Sértés | Elvárt | Mért |
|---|---|---|---|
| P1 | `Process.start('rg', …)` a guard fájlba (`27f22591`) | A8 PIROS | **ZÖLD — F1 MAJOR** |
| P2 | a release-asset sor törlése a PR-sablonból | A7 PIROS | A7 PIROS ✅ |
| P3 | a D1 tilalom kimondása a `branch-protection.md`-ben | zöld (a mondat nem sért) | **A6 PIROS — F2 MINOR** |
| P4 | `assignees:` kulcs a `feature.yml`-be | dokumentált korlát | A1 PIROS, hangos `FormatException` ✅ (F3 NOTE) |
| P5 | `rollback` mező törlése / fantom CODEOWNERS a Python auditban | `exit 1` | `exit 1` mindkettőre ✅ |

## Architektúra, termékhatárok, lifecycle

- **A merge kapuja nem változott.** A kör egyetlen merge-feltételt sem adott a
  zöld kapuhoz; a `branch-protection.md` §1 ezt kimondottan rögzíti. Az
  autonóm kör-pipeline squash-merge-e befagyasztás nélkül fut tovább —
  a §9 legsúlyosabb kockázata elhárítva.
- **Nincs hálózat és nincs `gh` az implementer oldalán.** A Python audit
  forrásában nincs `requests`/`urllib`/`subprocess`; a `gh api` parancs
  szövegesen, `print`-tel jelenik meg.
- **Két, egymástól független mérés** ugyanazokra a fájlokra (Dart szűkített
  parser a CI-kapuban, PyYAML az operátor oldalon) — az ADR 0444 D3 szerint,
  és a P4 próba meg is mutatta, hogy a kettő valóban eltérő szigorúságú.

## A javító körnek átadott leletlista

`/tmp/fix-e12-r03.md` — F1 (MAJOR) és F2 (MINOR), reprodukáló paranccsal,
javasolt javítási hellyel és kötelező második valódi-sértés próbával. F3/F4
NOTE, nem került a javító körbe.

## Javító kör — újra-ellenőrzés (`149582f1`)

### F1 — MAJOR → **ZÁRVA**

A guard mostantól **két** darabolt mintát keres (`'Process' + '.run'` és
`'Process' + '.start'`), és a komment kimondja, miért fedi ez le mind a három
belépési pontot (a `runSync` a `run` prefixén osztozik). Az önhivatkozási
csapda kezelése megmaradt: a keresett minta a fájl saját szövegében sehol nem
áll összefüggően.

**A reviewer megismételte a próbát mind a három belépési pontra:**

```
RE-PROBE: Process.start('rg', …)   → A8 PIROS ✅
RE-PROBE: Process.run('rg', …)     → A8 PIROS ✅
RE-PROBE: Process.runSync('rg', …) → A8 PIROS ✅
```

A teszt neve is a mért halmazhoz igazodott: „never spawns an external process
**through any dart:io Process entry point**".

### F2 — MINOR → **ZÁRVA**

A korlát három helyen van kimondva, pontosan ott, ahol a szerkesztő
találkozik vele: a `forbiddenHumanApprovalPatterns` (Dart) és a
`FORBIDDEN_HUMAN_APPROVAL_PATTERNS` (Python) doc-commentjében, valamint a
`branch-protection.md` új §6-jában („Miért kerüli ez a dokumentum a tiltott
szókapcsolatokat"). Mindhárom szöveg explicit: a minta **szöveges
előfordulást** mér, nem szándékot; a hamis pozitív szándékos és fail-closed;
**a minta gyengítése nem megoldás.**

### F3 / F4 — NOTE → változatlanul nyitva, follow-up

Egyik sem merge-blokkoló; mindkettő dokumentált, fail-closed korlát.

### Végső mérleg

| Súlyosság | Talált | Zárva | Nyitva |
|---|---|---|---|
| BLOCKER | 0 | — | 0 |
| MAJOR | 1 | 1 | 0 |
| MINOR | 1 | 1 | 0 |
| NOTE | 2 | 0 | 2 (follow-up) |

## VÉGSŐ DÖNTÉS: APPROVED

Nyitott BLOCKER/MAJOR/MINOR nincs. A zöld kapu (ADR 0052) a merge SHA-ján
külön igazolandó: Full Gate + Router CI `success`.
