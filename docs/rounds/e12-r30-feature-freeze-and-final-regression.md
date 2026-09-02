# E12-R30 — Feature freeze és final regression

- **Státusz:** IN PROGRESS (előre megírva 2026-08-27, `main @ 9ca4a0dc`; pre-flight revízió 2026-09-02, `main @ 4ac78365` — §0.0)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 30
- **Kör-azonosító:** `E12-R30`
- **Branch:** `<motor>/e12-r30-feature-freeze-and-final-regression`
- **Előfeltétel:** `E12-R28` és `E12-R29` merge-elve (GA-scope + Open Beta tapasztalat)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör eljárást és riportot szállít; a freeze-hez kapcsolódó normát a **[ADR 0489](../adr/0489-ga-scope-classification-and-contract-freeze.md)** (Kör 28) rögzíti (a törzsszöveg eredeti „ADR 0464" hivatkozása MÉRTEN hibás — §0.0 P1).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "feature freeze final regression known issues changelog"` → a `halts/round-status-E08-R07`, `E09-R01` és `E09-R14` merge-elt körök (epic-nyitó/záró mérési minták). Release-domain előzmény nincs — ez a projekt ELSŐ feature-freeze köre.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd, hogy a `docs/release/blockers.md` naprakész-e, és hogy a Kör 25 RC-workflow-ja LEFUTOTT-e zölden legalább egyszer. A final regression a MÉRT kapuk újrafuttatása, nem újak kitalálása.
>
> **Elvégezve (orchestrátor, §0.0):** a `blockers.md` **ELAVULT** (mérés `main @ 92576977`, owner-körök azóta `done` — P2), az RC-workflow **SOHA nem futott** és innen nem is futtatható (P3). Mindkét tény a `known-issues.md` kimondott tartalma; egyik sem javítható ebben a körben.

## 0.0 Pre-flight revízió (orchestrátor, 2026-09-02, `main @ 4ac78365`)

A brief `PREPARED` állításait a fán ÚJRAMÉRTEM. Az alábbi P1–P7 a brief
**KÖTELEZŐ** része: ahol a mérés mást mond, mint a törzsszöveg, a **mérés**
győz. ADR nincs és nem is lesz — a §5 így dönt, és a `docs/adr/**` a tilos
zónában van (a `tools/round-slots.py reserve-adr` ezért nem futott).

**Visszakeresés (ADR 0312, szűkítve előbb):**
`--corpus lessons,halts,adr --top 5 "feature freeze known issues changelog
release regression"` → `adr/0489` (a Kör 28 GA-scope + contract-freeze ADR-je),
`adr/0487`, `adr/0067`; `--corpus lessons,halts --top 5 "python release tool
dart test invocation deterministic generated document parse fail-closed"` →
**[L206](../LESSONS.md#l206)** (a `paths:`-szűrős `router-ci.yml` a review-doc
commit után nem tüzel újra — kézi dispatch kell),
**[L573](../LESSONS.md#l573)**, és a fán mellette
**[L566](../LESSONS.md#l566)** / **[L571](../LESSONS.md#l571)** /
**[L575](../LESSONS.md#l575)**: mind a négy ugyanazt a hibaosztályt méri — a
kézzel írt doksi-parszer alapértelmezésben **fail-OPEN**, azaz ami nem
illeszkedik a mintára, az nem hibás, hanem „nem létezik". Ennek a körnek
MINDHÁROM parszere (freeze-osztályozó, known-issues, CHANGELOG) **fail-CLOSED**
kell legyen — lásd P6. Release-domain (feature freeze) előzmény a korpuszban
**nincs**: ez a projekt ELSŐ feature-freeze köre.

### P1 — a hivatkozott ADR-szám HIBÁS: 0464 helyett **0489**

Mérve: `ls docs/adr/0464*` → `No such file or directory`. A Kör 28 ADR-je
[`docs/adr/0489-ga-scope-classification-and-contract-freeze.md`](../adr/0489-ga-scope-classification-and-contract-freeze.md)
(„**Kör:** E12-R28", dátum 2026-09-02). A `pipeline-queue.tsv` `0464` oszlopa
elavult tervezési foglalás — a fán ilyen ADR nincs. A brief fejlécének
„a freeze szabályát az ADR 0464 (Kör 28) rögzíti" mondata ezennel **ADR 0489**-re
javítva; a jelen kör ADR-t továbbra sem ír.

### P2 — a `blockers.md` ELAVULT, de a tilos zónában van, és MÉGIS ő az A3 szótára

Mérve: `docs/release/blockers.md:3` → „**Mérés SHA-ja:** `main @ 92576977`"
(2026-08-28), és mind a 10 sor `Owner (kör) … (pending)` annotációt hordoz.
A `docs/execution/pipeline-queue.tsv` MAI állapota szerint viszont mind a tíz
owner-kör (`E12-R04`, `R06`, `R07`, `R08`, `R13`, `R17`, `R18`, `R19`, `R24`,
`R26`) **`done`**. Az `Owner … (pending)` annotáció tehát elavult; a
**zárási feltételek** viszont NEM automatikusan teljesültek — azt ennek a
körnek kell MÉRNIE, soronként.

Következmények, kötelezően:

1. A `blockers.md`-t **nem írjuk át** (§3 tilos zóna, és a
   `tool/release/verify_ga_scope.py` D7-mérése is ebből a fájlból olvassa a
   nyitott P0/P1 halmazt — egy „karbantartó" átírás egy MÁSIK kör zöld
   celláját mozdítaná el).
2. A `known-issues.md` **P0/P1 tételei kizárólag a `blockers.md`-ben szereplő
   ID-kkal** (`R-SIGN-01`, `R-VER-01`, `R-PRIV-01`, `R-SEC-01`, `R-STAGE-01`,
   `R-STORE-01`) azonosíthatók — ez az A3 gépi tartalma.
3. A `known-issues.md` **kimondja** az elavulást (mért SHA + a MAI queue-állapot),
   ahelyett hogy elhallgatná vagy szépítené.
4. **Ha a mérés olyan nyitott hibát talál, ami valóban P0/P1, de a
   `blockers.md`-ben NINCS benne:** az NEM súlyosság-lefokozással oldandó fel,
   hanem a §0 **STOP-protokolljával** (`tools/codex-signal.sh stopped` +
   jelentés). A `blockers.md` bővítése egy külön kör dolga. A „gyorsan
   P2-re teszem" út a §5.2 kimondott gyengítés-tilalmába ütközik.

### P3 — a Kör 25 RC-workflow-ja MÉG SOHA NEM FUTOTT, és ebből a körből nem is futtatható

A brief pre-flight-kérése („LEFUTOTT-e zölden legalább egyszer") mért válasza:
**NEM, egyszer sem.** `ls .github/workflows/` → 10 workflow
(`backend-ci`, `build-apk`, `chord-train`, `dsp-probe`, `full-gate`, `lab-apk`,
`ml-train`, `release-apk`, `router-ci`, `tutor-eval`) — `release-candidate.yml`
**nincs köztük**. A Kör 25 szándékosan *javaslatként* szállította
(`docs/release/workflows/release-candidate.proposal.yml`), a telepítés
[ADR 0488](../adr/0488-release-candidate-assembly-and-approval-gate.md) D1/D8
szerint **emberi lépés**, a futtatás pedig egy jóváhagyói environment mögött
van. A `.github/**` ennek a körnek **tilos zóna**, tehát:

- az **A5** bizonyítéka a §0.1 (a) szerinti orchesztrátor-dispatch
  (`build-apk.yml` / `full-gate.yml` a `tools/round-ci-plan.py` döntése szerint),
  **nem** az RC-workflow;
- „az RC-kapu még egyszer sem futott le" maga is **known-issues tétel**
  (súlyosság: a `R-SIGN-01` P0 zárási feltételéhez kötött), nem elhallgatandó
  részlet.

### P4 — A4: a körben NINCS CHANGELOG-generátor, ezért az A4 **kötő ellenőrzés**, nem generálás

A §3 „a Kör 6 manifest-adataiból generált" megfogalmazása a fán nem
kivitelezhető úgy, ahogy hangzik: az egyetlen engedélyezett ÚJ eszköz a
`tool/release/verify_freeze.py`, a manifest-generátor
(`tool/generate_release_manifest.dart`) pedig az engedélyezett listán **kívül**
van, tehát nem módosítható, és a fán nincs commitolt `release-manifest.json`
sem (CI-artefaktum). Mért manifest-bemenetek
(`tool/generate_release_manifest.dart:23-33`): `releaseManifestSchemaVersion = 1`,
a verzió/build a `pubspec.yaml`-ból (`pubspec.yaml:5` → **`1.0.0+1`**), rövid
git SHA, `channel`, ML- és tutor-knowledge-manifest — és a manifest
[ADR 0447](../adr/0447-versioning-provenance-and-sbom.md) D1 szerint
**semmilyen időbélyeget nem tartalmaz**.

Az **A4 ezért így mérendő:** a `CHANGELOG.md` egy gépileg parszolható
release-fejléc blokkot hordoz (marker-párral határolva), amelynek mezői a MÉRT
manifest-bemenetekkel egyeznek — `version` + `build` a `pubspec.yaml`-ból,
`schema_version` a `generate_release_manifest.dart` konstansából (fail-closed
olvasás; precedens: a `verify_ga_scope.py` `feature_flags.dart`-olvasója) —,
és a blokk **determinisztikus**: nem tartalmaz generálási időbélyeget vagy
dátumot (ADR 0447 D1). Az ellenőrzést a `verify_freeze.py` végzi, a cella a
`freeze_policy_test.dart`-ban él. „Kézzel írt, manifest-hivatkozás nélküli
CHANGELOG" = a fejléc-blokk hiánya vagy a mezők eltérése ⇒ **piros** (a §6.1
sora ezzel változatlanul teljesül).

### P5 — a kilépő-kód szemantika BE VAN FAGYASZTVA: `verify_freeze.py` is 0/1/2

A `docs/release/contract-freeze.md` negyedik sora a `verify_ga_scope.py` /
`verify_beta_profile.py` **0 = ok, 1 = validációs találat, 2 = használati/
formátumhiba** szemantikáját fagyasztja. Az új `verify_freeze.py` ugyanezt a
három kódot használja (az A1 „nem-nulla" elvárását az `1` teljesíti) — negyedik
kód bevezetése tilos, mert a testvéreszközök szerződését olvasztaná fel.

### P6 — mindhárom parszer FAIL-CLOSED (L566 / L571 / L573 / L575)

Marker-párral határolt blokkon belül **minden** nem-fejléc, nem-elválasztó sor
kötelező adatsor, és teljes egészében illeszkednie kell a tábla sor-alakjára;
ami nem illeszkedik, az **hiba** (`2`-es kilépés a sor megnevezésével), soha
nem csendben eldobott sor. Tilos a `continue`-val átugrott „nincs mintám hozzá"
ág, és tilos a `- [ ]`/`- [x]` alakra szűkített őr. Ez a P6 a `freeze_policy_test.dart`
külön celláival bizonyítandó (legalább: hiányzó marker-blokk, elrontott sor-alak,
üres blokk — mindhárom nem-nulla kilépés).

### P7 — a freeze bázisa és az osztályozás zárt készlete

A `feature-freeze.md` gépileg parszolható blokkja rögzíti:
`freeze_base_sha: 4ac78365` (a jelen kör indulási `origin/main`-je,
`docs(handoff): E12-R29 KÉSZ …`), a jóváhagyó szerepét, és az engedélyezett
változás-osztályok **zárt** készletét:

| osztály | mit fed | mi kell hozzá |
|---|---|---|
| `blocker-fix` | a freeze alatt engedett termékváltozás | a commit MEGNEVEZ egy `blockers.md`-beli blocker ID-t (`R-…`) |
| `documentation` | `docs/**`, `CHANGELOG.md` | nem kell blocker ID |
| `release-tooling` | `tool/release/**`, `test/tooling/**` | nem kell blocker ID |

Minden más útvonal (`lib/**`, `backend/**`, `android/**`, `assets/**`,
`pubspec.yaml`, …) blocker ID nélkül **osztályozatlan ⇒ találat ⇒ `1`-es
kilépés**. Az „apró javítás, nem számít" osztály (§5.1) a zárt készlet miatt
gépileg sem létezik. A `verify_freeze.py` a változáslistát a git-ből
(`--since <sha>`) VAGY egy explicit, fail-closed formátumú bemeneti fájlból
veszi, hogy a negatív cellák git-fixtúra nélkül is determinisztikusak
legyenek; egy cella a VALÓDI fán futtatja a `--since`-t.

## 0.1 Mit jelent itt a „teljes regresszió"

A boxon a teljes Flutter-suite ~15 perc, a CI-ban 4–5; a MÉRT szabály (ADR 0053) szerint a teljes suite + property-gate + APK a CI-ban fut. A kör „final regression"-je ezért: (a) egy ZÖLD `build-apk.yml` / RC-dispatch az orchesztrátortól, (b) a backend és a release-eszközök lokális sávja, (c) a `known-issues.md` MÉRT tartalommal. A kör NEM ír új gate-et.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/release/feature-freeze.md",
  "docs/release/known-issues.md",
  "CHANGELOG.md",
  "tool/release/verify_freeze.py",
  "test/tooling/freeze_policy_test.dart",
  "docs/rounds/e12-r30-feature-freeze-and-final-regression.md",
]
gate_tests = [
  "test/tooling/freeze_policy_test.dart",
  "test/tooling/ga_scope_test.dart",
]
native_gate = true
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a regresszió P0/P1 hibát talál, a kimenet a `stopped` jelzés és jelentés — a javítás önálló kör, és a freeze pontosan azért van, hogy ez látszódjon.

## 1. Cél

Kimondott scope- és kódfagyasztás, MÉRT teljes regresszió és őszinte known-issues lista a Release Candidate előtt.

## 2. Jelenlegi állapot — mért tények

- `CHANGELOG.md` **nem létezik** a repóban (a történet a `HANDOFF.md`-ben és a PR-okban él).
- `docs/release/` a korábbi körök után gazdag; `feature-freeze.md` és `known-issues.md` **nincs**.
- A merge-kapu `build-apk.yml` / `full-gate.yml`; a választást a `tools/round-ci-plan.py` dönti a brief `native_gate` mezőjéből.
- A property-gate `test/property/` alatt él, CI-ban randomizált maggal fut (HORIZON konvenció).
- A `docs/release/blockers.md` (Kör 1) a blocker-nyilvántartás egyetlen forrása.

## 3. Scope

**Benne van:** `docs/release/feature-freeze.md` (mi fagy be, mi az engedélyezett változás — kizárólag P0/P1/P2 blocker, és ki hagyhatja jóvá) · `tool/release/verify_freeze.py` (a freeze utáni diff osztályozása: a nem-blocker változás nem-nulla kilépést ad) · `test/tooling/freeze_policy_test.dart` · `docs/release/known-issues.md` (a MÉRT nyitott hibák, súlyossággal és megkerülő úttal) · `CHANGELOG.md` (a release-történet első, generált változata a Kör 6 manifest-adataiból).

**NINCS benne (tilos):**

- Feature-fejlesztés vagy hibajavítás (a freeze tárgya éppen ez).
- ÚJ gate vagy workflow.
- A `blockers.md` átírása (olvasni kell, nem szépíteni).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/release/feature-freeze.md` | ÚJ — a fagyasztási szabály |
| `docs/release/known-issues.md` | ÚJ — a nyitott hibák |
| `CHANGELOG.md` | ÚJ — generált release-történet |
| `tool/release/verify_freeze.py` | ÚJ — a freeze-ellenőrző |
| `test/tooling/freeze_policy_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/**` · `backend/**` · `.github/**` · `docs/release/blockers.md` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések

Nincs ADR. Két kötelező szabály:

### 5.1 A freeze alatti változás OSZTÁLYOZOTT és indokolt

Minden commit vagy P0/P1/P2 blocker-javítás, vagy dokumentáció. **NEM elfogadható gyengítés:** „apró javítás, nem számít" kategória.

### 5.2 A known-issues lista ŐSZINTE

Minden ismert, nyitott hiba felkerül, még ha kellemetlen is. **NEM elfogadható gyengítés:** a „nem reprodukálható" kategóriába söprés mérési kísérlet nélkül.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | `verify_freeze.py` a nem-blocker (osztályozatlan) változást **`1`-es** kóddal jelzi, a sértő útvonalak megnevezésével; a `documentation` / `release-tooling` osztályú változás `0` (§0.0 P5, P7) | `freeze_policy_test.dart` |
| A2 | A `known-issues.md` minden tétele hordoz súlyosságot (`P0`–`P3`), hatást és megkerülő utat — az „nincs megkerülő út" is **kimondva**, üres cella nem elfogadható | `freeze_policy_test.dart` |
| A3 | A `known-issues.md` minden P0/P1 tétele szerepel a `blockers.md`-ben is (nincs elrejtett blocker); a `blockers.md` **változatlan** (§0.0 P2) | `freeze_policy_test.dart` + `git diff --stat` |
| A4 | A `CHANGELOG.md` release-fejléc blokkja a MÉRT manifest-bemenetekkel egyezik (`version`/`build` a `pubspec.yaml`-ból, `schema_version` a generátor konstansából) és determinisztikus (nincs benne időbélyeg) — §0.0 P4 | `freeze_policy_test.dart` |
| A5 | ZÖLD teljes CI-futás a kör-branchen (`build-apk.yml` / `full-gate.yml` a `round-ci-plan.py` szerint — **nem** az RC-workflow, §0.0 P3) | orchesztrátor-dispatch linkje a §10-ben |
| A6 | A kör egyetlen termékkód-fájlt sem módosít | `git diff --stat` |
| A7 | Mindhárom parszer **fail-CLOSED**: hiányzó marker-blokk, elrontott sor-alak és üres blokk mind nem-nulla kilépés (§0.0 P6, L566/L571/L573/L575) | `freeze_policy_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A freeze-ellenőrző csak figyelmeztet a nem-blocker változásra | A1 |
| Egy P1 hiba csak a known-issues-ban szerepel, a blockers-ben nem | A3 |
| A CHANGELOG kézzel íródik, manifest-hivatkozás nélkül (nincs fejléc-blokk, vagy a `version`/`build` eltér a `pubspec.yaml`-tól) | A4 |
| A kör „menet közben" javít egy talált hibát | A6 |
| Egy known-issues sor megkerülő-út cellája üres marad | A2 |
| A parszer a nem illeszkedő sort átugorja (`continue`), nem hibának veszi | A7 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vegyél fel a `known-issues.md`-be egy P1 tételt, ami a `blockers.md`-ben NEM szerepel, futtasd a §7 gate-et → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/freeze_policy_test.dart test/tooling/ga_scope_test.dart
```

A freeze-ellenőrző közvetlen futtatása a VALÓDI fán (a kimenet szó szerint a §10-be):

```bash
python3 tool/release/verify_freeze.py --since 4ac78365
```

A kör saját diffje `documentation` + `release-tooling` osztályú, tehát ennek a
hívásnak a kör végén **`0`-val** kell kilépnie (§0.0 P7).

A teljes suite + property-gate + APK a CI-ban fut (ADR 0053) — a dispatch az orchesztrátoré.

## 8. Implementációs sorrend

1. `docs/release/feature-freeze.md` — a szabály + a §0.0 P7 gépileg parszolható
   blokkja (`freeze_base_sha`, jóváhagyó, a három változás-osztály).
2. `tool/release/verify_freeze.py` — három ellenőrzés egy eszközben
   (freeze-osztályozás, `known-issues.md`, `CHANGELOG.md`), 0/1/2 kilépő-kóddal
   (§0.0 P5), végig fail-CLOSED parszerekkel (§0.0 P6).
3. `docs/release/known-issues.md` a MÉRT nyitott hibákból — a `blockers.md` tíz
   sorának MAI, soronkénti mérése (a zárási feltétel teljesült-e), plusz a
   §0.0 P2/P3 kimondott tényei.
4. `CHANGELOG.md` + a hozzá tartozó A4 ellenőrzés (§0.0 P4).
5. `test/tooling/freeze_policy_test.dart` — az A1–A4 és A7 cellái.
6. A valódi-sértés próba a §10-be; a CI-dispatch az orchesztrátortól.

## 9. Kockázatok

- **Szépített known-issues.** A GA utáni meglepetések forrása (A2, A3).
- **Freeze-szivárgás.** „Apró" változások a freeze alatt (A1).
- **Regresszió-lelet elfedése.** A talált P0/P1 `stopped` jelzés, nem gyors javítás (§0.0).

## 10. Implementation handoff — az implementer tölti ki

**Motor:** `sonnet-impl` (Claude Sonnet 5), 1 kör (javító kör nélkül).

### Szállítva (fájlonként)

- [`docs/release/feature-freeze.md`](../release/feature-freeze.md) — ÚJ. A
  freeze szabálya + két gépileg parszolható marker-blokk:
  `<!-- freeze-base:begin/end -->` (`freeze_base_sha: 4ac78365`,
  `approver_role`) és `<!-- freeze-classes:begin/end -->` (a zárt, 3 elemű
  osztály-tábla: `documentation` / `release-tooling` / `blocker-fix`, a
  `path_prefixes` és `requires_blocker_id` oszlopokkal — ezt olvassa be a
  `verify_freeze.py`, nem hardkódolja).
- [`docs/release/known-issues.md`](../release/known-issues.md) — ÚJ. Egy
  közös `<!-- known-issues:begin/end -->` blokk, ami mindhárom §-t (§1 a
  `blockers.md` tíz sorának MAI, soronkénti mérése; §2 a Kör 25
  RC-workflow-ja soha nem futott; §3 hat gazdátlan, korábban MÉRT nyitott
  lelet: `E12-R20`/`R21`/`R23`/`R24`/`R29`) átfogja — 17 adatsor
  (`id`/`severity`/`title`/`impact`/`workaround`).
- [`CHANGELOG.md`](../../CHANGELOG.md) — ÚJ. `<!-- release-header:begin/end
  -->` marker-blokk (`version: 1.0.0`, `build: 1`, `schema_version: 1`,
  pontosan 3 sor — negyedik sor, pl. időbélyeg, fail-closed elutasítva), a
  Chapter-szintű mérföldkövek `docs/sdd/00-index.md`-ből, és a jelen kör
  saját bejegyzése.
- [`tool/release/verify_freeze.py`](../../tool/release/verify_freeze.py) —
  ÚJ. Három ellenőrzés egy futásban: freeze-osztályozás (git `--since` VAGY
  fail-closed `--changes-file`), `known-issues.md` (A2/A3), `CHANGELOG.md`
  fejléc (A4) — 0/1/2 kilépő-kóddal (`verify_ga_scope.py`/
  `verify_beta_profile.py` szemantikája, negyedik kód nélkül).
- [`test/tooling/freeze_policy_test.dart`](../../test/tooling/freeze_policy_test.dart)
  — ÚJ. 31 cella, `ga_scope_test.dart` mintája (`Process.runSync`, temp-dir
  fixtúrák, valódi-fán futó sanity cellák).
- Ez a fájl (`docs/rounds/e12-r30-…md`) — csak a §10 (jelen szakasz)
  kitöltve, a törzsszöveg és a §0.0 pre-flight változatlan.

### A1–A7 megfeleltetés

| # | Bizonyíték a `freeze_policy_test.dart`-ban |
|---|---|
| A1 | csoport „A1 — freeze-era change classification" (7 cella): osztályozatlan útvonal → `1`; `documentation`/`release-tooling` → `0` blocker ID nélkül; `blocker-fix` érvényes `blockers.md` ID-vel → `0`; nemlétező ID → `1`; `P3` súlyosságú ID NEM elég → `1` (izolált fixtúrával, ld. lent); `--since`+`--changes-file` együtt és érvénytelen `--since` → `2` |
| A2 | csoport „A2" (2 cella): üres workaround-cella → `1`, ismeretlen severity (`P9`) → `1` — mindkettő a sértő `id`-t nevezi meg |
| A3 | csoport „A3" (3 cella): a §6.1 valódi-sértés próba mint reprodukálható regressziós cella (fixtúrán, `K-FAKE-01` a `blockers.md`-ben nincs) → `1`; severity-eltérés (`R-VER-01` itt `P0`, `blockers.md`-ben `P1`) → `1`; sanity — a szállított `known-issues.md`-ben egyetlen P0/P1 sor sincs `blockers.md`-n kívül |
| A4 | csoport „A4" (3 cella): `version`/`build`/`schema_version` eltérés külön-külön → `1`, mindegyik a hibás értéket nevezi meg |
| A5 | ld. „CI-dispatch" alszakasz lent — ez NEM a `freeze_policy_test.dart` cellája |
| A6 | `git diff --stat 4ac78365 HEAD` (lent) — nincs `lib/**`/`backend/**`/`android/**`/`assets/**`/`pubspec.yaml` a diffben |
| A7 | csoport „A7" (9 cella, mindhárom dokumentumra: `feature-freeze.md`, `known-issues.md`, `CHANGELOG.md`): hiányzó marker-blokk → `2`, elrontott sor-alak → `2`, üres blokk → `2` (a `feature-freeze.md`-nél a `freeze-base` ÉS a `freeze-classes` blokkra is, 4 cella) |

### `tools/round-gate.sh` — a TÉNYLEGES kimenet (csonkítás nélkül futtatva)

```
$ tools/round-gate.sh test/tooling/freeze_policy_test.dart test/tooling/ga_scope_test.dart
═══ [1] format                                                          → ZÖLD  (Formatted 2214 files (0 changed))
═══ [2] analyze                                                         → ZÖLD  (No issues found! (ran in 27.1s))
═══ [3] test test/tooling/freeze_policy_test.dart                       → ZÖLD  (00:01 +31: All tests passed!)
═══ [4] test test/tooling/ga_scope_test.dart                            → ZÖLD  (00:01 +23: All tests passed!)
═══ [5] architecture                                                    → ZÖLD  (Architecture dependencies OK (12 allowlisted deviation(s)))
═══ [6] secrets                                                         → ZÖLD  (Secret scan OK (4169 file(s) scanned, 0 finding(s)))
═══ [7] l10n                                                            → ZÖLD  (L10n aggregate freshness OK; L10n parity OK (en → hu, 2298 message(s)))

Gate-összegzés: format zöld · analyze zöld · test test/tooling/freeze_policy_test.dart zöld ·
test test/tooling/ga_scope_test.dart zöld · architecture zöld · secrets zöld · l10n zöld
MINDEN GATE ZÖLD.
```

### `verify_freeze.py --since 4ac78365` — a TÉNYLEGES kimenet (a kör saját diffjén, a végleges commitok után)

```
$ python3 tool/release/verify_freeze.py --since 4ac78365
verify_freeze: ok — 17 known-issue row(s), 6 changed path(s) classified
```

(A 6 osztályozott útvonal mind a jelen kör két commitjából jön —
`docs/release/feature-freeze.md`, `docs/release/known-issues.md`,
`CHANGELOG.md` → `documentation`; `tool/release/verify_freeze.py`,
`test/tooling/freeze_policy_test.dart` → `release-tooling`; a hatodik a
`docs/rounds/e12-r30-…md` §10-frissítés, szintén `documentation` — egyik sem
`blocker-fix`, konzisztens a §7 elvárásával, hogy a kör saját diffje
kizárólag `documentation` + `release-tooling`.)

### §6.1 Valódi-sértés próba — dokumentálva

1. A `docs/release/known-issues.md` `<!-- known-issues:begin -->` markere
   utáni sorba beszúrva: `` | `K-PROBE-01` | `P1` | valódi-sértés próba — nincs
   a blockers.md-ben | próba impact | próba workaround | ``.
2. `python3 tool/release/verify_freeze.py` (a valódi fán, felülírás nélkül)
   → `1` kilépő kód, `known-issues.md:23: id 'K-PROBE-01' is severity 'P1'
   but has no matching row in blockers.md (A3) — no P0/P1 known issue may
   hide outside the blocker registry`.
3. `flutter test test/tooling/freeze_policy_test.dart` a mutált fán → **PIROS**,
   pontosan az A3 „the shipped known-issues.md has no P0/P1 row outside
   blockers.md (sanity, tool-independent)" cella bukik (`Expected: 'P1',
   Actual: <null>` — `K-PROBE-01` nincs a `blockers.md`-ben), és emiatt két
   további, a valódi `known-issues.md`-re támaszkodó sanity/A1 cella is
   pirosra vált (kaszkád, nem hiba — mind ugyanazt a mutált bemenetet olvassa).
4. Visszaállítva: `cp /tmp/known-issues.md.orig docs/release/known-issues.md`,
   `git status --short` → tiszta munkafa, `python3 tool/release/verify_freeze.py`
   → újra `0`.

### CI-dispatch (A5)

Az orchesztrátor feladata (`tools/round-ci-plan.py` dönti a `build-apk.yml`/
`full-gate.yml` választást a brief `native_gate = true` mezőjéből) — ez az
implementer-kör nem hív `gh`-t (CLAUDE.md „REMOTE Claude Code konténerben").
A run-link a merge-kézfogás során kerül ide/`HANDOFF.md`-be.

### Amit NEM tettem meg, és miért

- **Nem írtam át a `blockers.md`-t** — tilos zóna (§0.0 P2, §3, §4). A
  `known-issues.md` P0/P1 tételei kizárólag a `blockers.md`-ben MA szereplő
  ID-kat használják.
- **Nem telepítettem és nem futtattam az RC-workflow-t** — a `.github/**`
  tilos zóna (§0.0 P3); az A5 bizonyítéka az orchesztrátor
  `build-apk.yml`/`full-gate.yml` dispatchja, nem az RC-kapu.
- **Nem javítottam egyetlen MÉRT nyitott hibát sem** (pl. `K-E12R23-01`,
  `K-E12R29-01/02`) — a `lib/**`/`backend/**` tilos zóna, és a freeze
  pontosan azért van, hogy ezek látszódjanak, ne tűnjenek el egy „gyors
  javítás" mögött (§5.1/§5.2, §9 „Regresszió-lelet elfedése").
- **Nem futtattam a teljes `flutter test` suite-ot vagy a property-gate-et
  lokálisan** — ADR 0053 szerint ez a CI dolga (0.1. szakasz); a lokális
  gate a brief §7 szerinti két célzott teszt + a `round-gate.sh` beépített
  architecture/secrets/l10n lépései.
- **Nem emeltem a `pubspec.yaml` build-számát** — az emelés `blocker-fix`
  osztályú termékváltozás lenne (§0.0 P7 táblázat), ami vagy egy nyitott
  blocker javítását igényelné, vagy kívül esne a három zárt osztályon;
  ehelyett a `CHANGELOG.md` a MÉRT, változatlan `1.0.0+1`-et rögzíti.

## 10.1 1. javító kör — a független review leleteinek zárása (implementer)

A kör ELSŐ futása (`b93204c2`) után egy független review két **MAJOR** és
egy **MINOR**/**NOTE** leletet mért. Mind a négyet ez a javító kör zárja,
az engedélyezett fájllista változatlan, a `blockers.md` továbbra is tilos
zóna.

### MAJOR-1 — a bare hívás fail-OPEN volt (nem klasszifikált)

**A hiba:** `verify_freeze.py` `main()`-ja `--since`/`--changes-file` nélkül
`changes = None`-t hagyott, a klasszifikációt (A1/A6) teljesen kihagyta, és
`ok` + `exit 0`-t nyomtatott — annak ellenére, hogy a `freeze-base:begin`
blokk `freeze_base_sha`-t deklarál, amit a `load_freeze_base()` beolvasott,
de eldobott.

**A javítás** (`tool/release/verify_freeze.py`, `main()`): a bare hívás
(sem `--since`, sem `--changes-file`) mostantól a `feature-freeze.md`-ből
beolvasott `freeze_base_sha`-val hívja a `get_changes_from_git()`-et — az
explicit `--since` továbbra is felülír. A `changes` így SOHA nem `None`,
a `classify_changes()` és az összegző sor mindig lefut.

**Teszt** (`test/tooling/freeze_policy_test.dart`):
- a `sanity` cella (44-56. sor) mostantól a `changed path(s) classified`
  szöveget is elvárja az alapértelmezett hívás stdoutjában (korábban csak
  `ok`-ot várt — ez tartotta életben a hibát);
- ÚJ A1-cella: egy izolált, `git init`-elt temp-repóban két commit
  (`seed`, majd egy `lib_stub.dart`-ot módosító, blocker-ID nélküli
  commit), a `verify_freeze.py`-t a temp-repó `workingDirectory`-jában, a
  temp-repó saját `freeze_base_sha`-jára mutató `--feature-freeze`
  fixtúrával híva, `--since`/`--changes-file` NÉLKÜL — `exit 1`,
  `lib_stub.dart` + `not classified` a stderr-ben. Ez pontosan a reviewer
  `/tmp/probe-e12-r30` reprodukciójának Dart-gate megfelelője.

### MAJOR-2 — a súlyosság-lefokozás észrevétlen maradt

**A hiba:** `validate_known_issues()` a `blockers.md`-vel való
súlyosság-egyeztetést csak akkor futtatta, ha a `known-issues.md` sora MAGA
`P0`/`P1` volt — egy `blockers.md`-ben `P1`-es tétel `known-issues.md`-beli
lefokozása `P2`-re (vagy alacsonyabbra) így egyetlen findinget sem
generált.

**A javítás:** a súlyosság-egyeztetés mostantól MINDEN olyan `id`-re fut,
ami szerepel a `blockers.md`-ben, iránytól függetlenül — a „nincs
`blockers.md`-ben" ág (ami a P0/P1 kötelező jelenlétet kényszeríti)
változatlanul csak a known-issues.md-beli P0/P1 sorokra kötelező.

**Teszt:** ÚJ A3-cella — `R-VER-01` `P1` → `P2` fixtúrán → `exit 1`,
`R-VER-01` + `blockers.md` a stderr-ben.

### MINOR-1 — két önmagával ellentmondó `P3` besorolás

`K-E12R21-01` és `K-E12R24-01` `P3` → `P2`-re emelve
(`docs/release/known-issues.md`), mert egyik sem indokolt egy, a saját
bevezetőben kimondott `P2`-plafonnál (§0.0) alacsonyabb besorolást:
`K-E12R21-01`-et a `HANDOFF.md` §6 „KÉT MÉRT GA-blokkoló"-ként nevezi meg;
`K-E12R24-01` impact-cellája mostantól kimondja, hogy a tétel az
`R-PRIV-01` `P1` blocker **rész-bizonyítéka**, nem tőle független, enyhébb
hiba.

### NOTE-1 — a `blocker-fix` osztály granularitása kimondva

`docs/release/feature-freeze.md` §3 `blocker-fix` bekezdése kiegészítve:
a commit-szintű granularitás (egy érvényes blocker ID a commit
üzenetében a commit MINDEN útvonalát engedélyezetté teszi) most explicit
mondat, a jóváhagyó szerep felelősségeként megnevezve.

### Az ÚJ gate-kimenet (a javítás UTÁN, csonkítás nélkül)

```
$ tools/round-gate.sh test/tooling/freeze_policy_test.dart test/tooling/ga_scope_test.dart
═══ [1] format                                                          → ZÖLD  (Formatted 2214 files (0 changed))
═══ [2] analyze                                                         → ZÖLD  (No issues found! (ran in 6.1s))
═══ [3] test test/tooling/freeze_policy_test.dart                       → ZÖLD  (00:02 +33: All tests passed!)
═══ [4] test test/tooling/ga_scope_test.dart                            → ZÖLD  (00:01 +23: All tests passed!)
═══ [5] architecture                                                    → ZÖLD  (Architecture dependencies OK (12 allowlisted deviation(s)))
═══ [6] secrets                                                         → ZÖLD  (Secret scan OK (4169 file(s) scanned, 0 finding(s)))
═══ [7] l10n                                                            → ZÖLD  (L10n aggregate freshness OK; L10n parity OK (en → hu, 2298 message(s)))

Gate-összegzés: format zöld · analyze zöld · test test/tooling/freeze_policy_test.dart zöld ·
test test/tooling/ga_scope_test.dart zöld · architecture zöld · secrets zöld · l10n zöld
MINDEN GATE ZÖLD.
```

```
$ python3 tool/release/verify_freeze.py --since 4ac78365
verify_freeze: ok — 17 known-issue row(s), 7 changed path(s) classified
```

(A cellaszám 31→33: a két új regressziós cella, MAJOR-1 az A1, MAJOR-2 az
A3 csoportban. A klasszifikált útvonal-szám 6→7 nem a javítástól jön,
hanem attól, hogy a HEAD a `0245c7fb`/`a30a9467`/`5cec7b2b`/`b93204c2`
négy kör-commitján áll, mindegyik `documentation`/`release-tooling`.)

### Independens reprodukció-visszajátszás (a reviewer `/tmp/probe-e12-r30`
lépéseivel, a javított kódon)

```
$ printf '\n// freeze-era probe\n' >> lib/app/build_info.dart
$ git commit -qam "chore: apró javítás, nem számít"
$ python3 tool/release/verify_freeze.py
verify_freeze: 1 finding(s):
  - lib/app/build_info.dart: not classified under any freeze change class … (A1)
exit=1                      # ← MAJOR-1 zárva: a bare hívás is elkapja

$ sed -i 's/| `R-VER-01` | `P1` |/| `R-VER-01` | `P2` |/' docs/release/known-issues.md
$ python3 tool/release/verify_freeze.py
verify_freeze: 1 finding(s):
  - known-issues.md:45: id 'R-VER-01' is severity 'P2' here but 'P1' in blockers.md (A3)
exit=1                      # ← MAJOR-2 zárva: a lefokozás is elkapva
```

## 10.2 2. javító kör — a shallow CI-klón mért hibája

**A MÉRT hiba.** A `build-apk.yml` a `6eb6fb3a` SHA-n PIROS
([run 33632164312](https://github.com/wolfcasaba/strumsight/actions/runs/33632164312)):
`test/tooling/freeze_policy_test.dart` 10 cellája bukott, mind ugyanazzal
a `verify_freeze: --since '4ac78365' is not a valid git revision: ...
returned non-zero exit status 128` okkal.

**Gyökérok.** `actions/checkout@v4` fetch-depth felüldefiniálás nélkül
**shallow (depth=1)** klónt ad — a `freeze_base_sha: 4ac78365` (a Kör 29
záró commitja) ott nem létezik, `git rev-parse --verify 4ac78365` exit
128-cal bukik. A MAJOR-1 javítás óta a bare hívás (és minden olyan cella,
ami nem ad `--changes-file`-t) mindig ezt az utat futtatja le ELŐSZÖR, a
`main()` try-blokkjában, még a known-issues/CHANGELOG validáció előtt —
ezért nemcsak a 2 sanity cella, hanem 8 további, a known-issues.md/
CHANGELOG.md validációt mérni kívánó A2/A3/A4 cella is ugyanide bukott,
mielőtt a mérni kívánt findinghez ért volna. A lokális gate azért volt
zöld, mert a munkapéldány teljes klón — a hiba csak sekély klónban látszik.

**Javítás (`.github/**` tilos zóna, tehát nem `fetch-depth: 0`):**

1. **`tool/release/verify_freeze.py` — `get_changes_from_git`.** A kilépőkód
   változatlanul `2` (fail-closed — a freeze-t történet nélkül nem lehet
   ellenőrizni, a `0`/`1` hazugság lenne), de a hibaüzenet most megnevezi a
   valódi okot és a feloldást:
   ```
   verify_freeze: freeze base '4ac78365' is not present in this clone
   (shallow checkout?) — the freeze classification needs full git history
   (`git fetch --unshallow` / `actions/checkout` `fetch-depth: 0`); use
   --changes-file to check the documents without git history
   ```
   Nincs „ha nincs történet, átugrom" ág — az a MAJOR-1 hibaosztály
   visszahozása lenne.
2. **A két sanity cella** (`freeze_policy_test.dart` — bare hívás és
   explicit `--since 4ac78365`) most `git rev-parse --verify` -zel méri a
   klón mélységét, és MINDKÉT ágon szigorú: elérhető bázis → `exit 0` +
   `changed path(s) classified`; nem elérhető → `exit 2` + a stderr
   megnevezi a hiányzó bázist. A MAJOR-1 fedezete (a bare hívás
   klasszifikál) így a fejlesztői (teljes klónú) oldalon megmarad, a
   sekély CI-klónban pedig determinisztikusan, a helyes okkal bukik —
   nem néma átcsúszás.
3. **A nyolc A2/A3/A4 cella** (5× known-issues.md: üres workaround,
   ismeretlen severity, hiányzó blockers.md id, severity-eltérés,
   MAJOR-2 lefokozás; 3× CHANGELOG.md: version/build/schema_version
   eltérés) most egy üres, csak `#` kommentsort tartalmazó
   `--changes-file`-t kap — `classify_changes` üres listára nem ad
   findingot, tehát a cellák a klón mélységétől függetlenül pontosan azt
   az 1-es kilépést mérik, amiért készültek. Az A7 (marker-block
   fail-closed) cellák NEM kaptak ilyen módosítást: ott a `VerifyError` a
   `load_freeze_classes`/`load_freeze_base`/`load_known_issues`/
   `load_changelog_header` hívásokban keletkezik, a git-ág elérése előtt —
   azok a klón mélységétől már eddig is függetlenek voltak.

**ÚJ gate-kimenet** (`tools/round-gate.sh test/tooling/freeze_policy_test.dart
test/tooling/ga_scope_test.dart`, teljes klónú munkapéldányon):

```
═══ [1] format                                                          → ZÖLD  (Formatted 2214 files (0 changed))
═══ [2] analyze                                                         → ZÖLD  (No issues found!)
═══ [3] test test/tooling/freeze_policy_test.dart                       → ZÖLD  (00:02 +33: All tests passed!)
═══ [4] test test/tooling/ga_scope_test.dart                            → ZÖLD  (00:01 +23: All tests passed!)
═══ [5] architecture                                                    → ZÖLD  (Architecture dependencies OK (12 allowlisted deviation(s)))
═══ [6] secrets                                                         → ZÖLD  (Secret scan OK (4170 file(s) scanned, 0 finding(s)))
═══ [7] l10n                                                            → ZÖLD  (L10n aggregate freshness OK; L10n parity OK (en → hu, 2298 message(s)))

Gate-összegzés: format zöld · analyze zöld · test test/tooling/freeze_policy_test.dart zöld ·
test test/tooling/ga_scope_test.dart zöld · architecture zöld · secrets zöld · l10n zöld
MINDEN GATE ZÖLD.
```

(A cellaszám 33: az 1. javító kör 2 regressziós cellája (MAJOR-1, MAJOR-2)
plusz a jelen kör két átalakított sanity cellája — a szám maga nem nőtt,
mert nem cellát adtunk, hanem a meglévőket tettük klón-mélység-független
próbává.)

**A shallow-klón szimuláció tényleges kimenete** (a §7 receptje szerint —
teljes klón NEM reprodukálja a hibát, ezért külön kell futtatni):

```
$ rm -rf /tmp/shallow-e12-r30
$ git clone -q --depth 1 --branch sonnet-impl/e12-r30-feature-freeze-and-final-regression \
    file:///home/ubuntu/ss-sonnet-impl-e12-r30 /tmp/shallow-e12-r30
$ cd /tmp/shallow-e12-r30 && git rev-parse --verify 4ac78365
fatal: Needed a single revision
exit=128                       # ← a CI-t okozó feltétel itt is reprodukálva

$ bash tools/prepare-flutter-generated.sh   # OK
$ flutter test test/tooling/freeze_policy_test.dart
...
00:00 +1: sanity … exit 0 … when the freeze base is reachable … — exit 2 naming
           the unreachable base when it is not (shallow CI clone; fail-closed,
           not a regression)
...
00:01 +33: All tests passed!
```

A sekély klónban is **mind a 33 cella zöld** — a sanity cellák a `2`-es
fail-closed ágon futottak le sikerrel (a bázis nem elérhető), a nyolc
A2/A3/A4 cella pedig az üres `--changes-file` miatt a git-történettől
függetlenül a mérni kívánt findingot mérte. Ez a kör mércéje: a cellák a
klón mélységétől függetlenül helyeset mérnek.

## 11. Review — a Claude tölti ki

**Jelentés:** [`docs/reviews/e12-r30-review.md`](../reviews/e12-r30-review.md)
(reviewer: Claude Opus 5, orchestrátor-szék, ADR 0055 read-only review).

- **1. kör (`b93204c2`):** CHANGES REQUESTED — **MAJOR-1** (a
  `verify_freeze.py` ALAPÉRTELMEZETT hívása nem osztályozott, `ok` + exit `0`
  a §5.1 által névszerint tiltott „apró javítás, nem számít" commitra is; a
  deklarált `freeze_base_sha`-nak nem volt gépi hatása, és a hibát egy zöld
  cella rögzítette elvárásként), **MAJOR-2** (egy `blockers.md`-beli P0/P1 sor
  LEFOKOZÁSA a `known-issues.md`-ben észrevétlen maradt — a §5.2
  őszinteség-mércéjének kikerülhetősége), **MINOR-1** (két `P3` besorolás
  ellentmondott a saját hivatkozott mérésének), **NOTE-1** (a `blocker-fix`
  osztály commit-szintű granularitása kimondatlan volt).
- **1. javító kör (`69588a3c`):** mind a négy lelet **ZÁRVA**, mindkét MAJOR
  ÚJ regressziós cellával megfogva (31 → 33 cella). A zárásokat a reviewer
  friss klónban, függetlenül újramérte (review §6.1, négyirányú próba).
- **2. javító kör (`3ee48bea`):** a `6eb6fb3a` SHA-n a CI **PIROS** lett,
  miközben a lokális gate zöld volt — mért gyökérok: az `actions/checkout@v4`
  **shallow (depth=1)** klónjában a `freeze_base_sha: 4ac78365` commit nem
  létezik, ezért a MAJOR-1 javítás óta git-úton menő bare hívás (és 8 további,
  csak dokumentumot mérni kívánó cella) `2`-es kilépéssel bukott. A `.github/**`
  tilos zóna, ezért a javítás a tool és a cellák oldalán történt: fail-closed
  `2` beszédes üzenettel, a két sanity cella MINDKÉT ágon szigorú (elérhető
  bázis → `0` + `changed path(s) classified`, sekély klón → `2` + a hiányzó
  bázis), a nyolc dokumentum-cella pedig üres `--changes-file`-lal független
  lett a klón mélységétől. Reviewer-mérés: sekély (`--depth 1`) klónban
  **33/33 zöld**, teljes klónban a teljes gate zöld.
- **Végső döntés: APPROVED.**
