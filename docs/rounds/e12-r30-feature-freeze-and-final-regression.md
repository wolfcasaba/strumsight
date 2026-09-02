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

## 11. Review — a Claude tölti ki
