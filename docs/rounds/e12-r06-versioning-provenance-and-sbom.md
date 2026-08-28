# E12-R06 — Versioning, provenance, SBOM és release manifest

- **Státusz:** READY (pre-flight lefutott 2026-08-28, kód újramérve: `main @ f1cba2f9`; a §0.0.A négy brief-revíziót rögzít. Előre megírva 2026-08-27, `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 6
- **Kör-azonosító:** `E12-R06`
- **Branch:** `<motor>/e12-r06-versioning-provenance-and-sbom`
- **Előfeltétel:** `E12-R01` merge-elve (a release-history audit adja a verziószám-stratégia kiindulópontját)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0447` — a szám FOGLALT (Chapter 12 batch-tartomány). A SDD `docs/adr/versioning.md` fájlnevet ír; a repó konvenciója a SORSZÁMOZOTT ADR, ezért a döntés az `ADR 0447` fájlba kerül, és azt a Claude írja.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "versioning build number provenance SBOM release manifest third party license"` → **[ADR 0063](../adr/0063-generated-ml-manifest-and-backend-ci.md)** (generált ML asset manifest — a repó MÁR ismeri a „generált manifest + checksum + CI-ellenőrzés" mintát) és **[ADR 0135](../adr/0135-tutor-knowledge-governance.md)** (tudás-csomag governance). A release-manifest ezekre épül, nem mellettük.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `.github/workflows/release-apk.yml` „Read APK metadata from pubspec" lépését (a megíráskor: regex kényszeríti a `<version>+<build>` alakot, az artefaktum-név `strumsight-<ver>-<build>-<sha7>-production.apk`) és a `tool/` MÉRT ML-manifest eszközeit. A kör BŐVÍTI ezeket.

## 0.0 A workflow-fájl a MÉRCE VÉDETT zónája — a kör JAVASLATOT ír, nem workflow-t

A `.github/workflows/**` a `protect_factory_files.py` `PROTECTED_GLOBS` listáján van (ADR 0321), és az ADR 0372 álló felhatalmazásának FÁJLJA (`.claude/gate-edit-policy`) a fán MA NEM létezik — a pre-flight ezt MÉRTE (`tools/gateguard-scan.py`). Egy implementer-session tehát strukturálisan nem tudná megírni: a kör `H-GATEGUARD`-dal állna meg.

Ezért a kör a workflow-változást **javaslatként** szállítja (`docs/release/workflows/…`), teljes, bemásolható YAML-részlettel és a beillesztés pontos helyével. A tényleges `.github/workflows/` szerkesztés és a dispatch **orchesztrátor/emberi lépés**, a kör merge-e UTÁN — ugyanaz a határ, amit az ADR 0112 §3 az egyetlen emberi kapuként tart fenn. A kör saját mércéje ettől nem gyengül: a javaslat YAML-validitását és a hivatkozott lépések meglétét gépi cella méri.

## 0.0.A Pre-flight brief-revízió (2026-08-28, orchestrátor: Claude Opus 5 — `main @ f1cba2f9`)

A brief-lint `strict` szintje **0 leletet** adott
(`.pipeline/brief-lint-E12-R06.md`). A kód-mérés viszont a §1 pre-flight
mintája szerint (a TÉNYLEGES utat mérni, nem a leírást) **négy ütközést**
talált a brief és a fa között. Mindegyik a kör SAJÁT, még nem merge-elt
artefaktumát érinti, ezért az ADR 0087 §2 szerint dokumentált revízióval
oldom fel — nem lista-tágítással. **Az engedélyezett-fájllista NEM bővül.**

**Visszakeresés (ADR 0312, KÖTELEZŐ).** Szűkítve előbb:
`--corpus lessons,halts,adr "versioning provenance SBOM release manifest supply chain license"`
→ [ADR 0063](../adr/0063-generated-ml-manifest-and-backend-ci.md) (bm25#3
emb#4) és [ADR 0135](../adr/0135-tutor-knowledge-governance.md) (bm25#2
emb#6); `--corpus lessons,halts "deterministic generated manifest checksum test tooling dart script"`
→ [L206](../LESSONS.md#l206), [L86](../LESSONS.md#l86),
[L164](../LESSONS.md#l164). Teljes korpuszon kiegészítésként a saját brief és
az SDD Ch12 feladatlistája jött vissza — új tanulság nélkül. A döntő,
kifejezetten releváns lecke a szűkített ágon **nem** jött elő magától, ezért
célzottan mérve: **[L110](../LESSONS.md#l110)** (teszt SOSE shell-eljen ki nem
garantált binárisra) — ez az R2 alapja.

### R1 — A license-adat forrása MÉRT hiány (a §9 harmadik kockázata pontatlan volt)

**Mérés:** `grep -ci license pubspec.lock` → **`0`** (160 csomag).
`backend/requirements.txt` (11 pin) és `backend/requirements-dev.txt` (3 pin)
szintén license-mentes. A brief §3/§9 „a `pubspec.lock` nem tartalmaz
license-mezőt **minden** csomagra" fogalmazása azt sugallja, hogy néhányra
igen — a valóságban **egyre sem**. Így a §7 valódi futtatása
(`generate_sbom.py --profile production`) a brief eredeti szerződésével
MINDIG nem-nulla kóddal állna meg, és a `THIRD_PARTY_NOTICES.md` sosem jönne
létre: elérhetetlen cél-státusz (§1.1 hibaosztály).

**Feloldás — [ADR 0447 D3](../adr/0447-release-manifest-provenance-and-sbom.md):**
a license két, egyaránt MÉRT forrásból oldódik fel — (1) hosted Dart csomag:
a pub cache-beli `LICENSE` fájl (mérve: `~/.pub-cache/hosted/pub.dev` alatt
423-ból **422** könyvtárban van `LICENSE`; a kivétel a `.cache`
szolgáltatás-könyvtár), (2) SDK-beli/nem-hosted Dart csomag és Python pin: a
generátorban élő, kézzel gondozott `_CURATED_LICENSES` jegyzék, a
`tool/ci/check_song_fixture_licenses.dart` bevett fájlon-belüli
provenance-jegyzék mintájára. Egyik forrás sem ad találatot → **nem-nulla
kilépés a csomag megnevezésével**. A fail-closed tehát NEM gyengül; a
generátor futtathatóvá válik.

### R2 — A gate-cella nem importálhat `package:yaml`-t, és nem shell-elhet ki tetszőleges binárisra

**Mérés:** `package:yaml` a fán csak **tranzitív** (`pubspec.lock:1261`), és a
`pubspec.yaml` ennek a körnek **tilos zóna** — a
`depend_on_referenced_packages` lint miatt a teszt nem importálhatja. Ezt az
E12-R03 már mérte és a kódban dokumentálta
(`test/tooling/repository_policy_test.dart:92`). Az A5 („a YAML-részlet
önmagában valid") eredeti szövege nem mondta meg, mivel mérje.

**Feloldás — [ADR 0447 D5](../adr/0447-release-manifest-provenance-and-sbom.md)
+ [ADR 0444](../adr/0444-delivery-workflow-and-repository-policy.md) D3
precedens:** a YAML-validitást a tesztfájlban élő **korlátozott
részhalmaz-parser** méri. Továbbá [L110](../LESSONS.md#l110) alapján a teszt
`rg`/`grep`/`jq`/`gh` binárisra **nem** shell-elhet; a két Python eszköz
kilépési kódját `python3`-mal, **kizárólag a standard könyvtárra**
támaszkodva méri (PyYAML tilos — a runner-image nem garantálja). `python3`
hiánya esetén a cella **PIROS**, nem skip.

### R3 — A §5.1 két mondata egymásnak feszült; a szigorúbb ág a döntés

Az eredeti §5.1 engedett egy „külön, explicit build-idő mezőt, amit a
determinizmus-teszt kizár", ugyanabban a bekezdésben, amelyben a
mező-kihagyásos teszt-lazítást megtiltotta. **Feloldás —
[ADR 0447 D1](../adr/0447-release-manifest-provenance-and-sbom.md): a
manifestbe SEMMILYEN formában nem kerül időbélyeg**, sem a fő objektumba, sem
testvér-mezőként. A determinizmus-cella a **TELJES fájlt** méri, nincs kizárt
mező. A §5.1 ezzel a szigorúbb szöveggel értendő.

### R4 — A tudáscsomagnak nincs csomag-szintű verziómezője

**Mérés:** `assets/tutor_knowledge/manifest.json` kulcsai
`['schemaVersion', 'documents']` (10 dokumentum, dokumentumonként `license`,
`version`, `contentHash`); `assets/ml/model_manifest.json` →
`schema_version: 1` + `models[]` (4 bejegyzés). Csomag-szintű `version` mező
**egyikben sincs**, tehát az A4 „tudáscsomag-verzió" elvárása szó szerint nem
teljesíthető.

**Feloldás — [ADR 0447 D6](../adr/0447-release-manifest-provenance-and-sbom.md):**
a release manifest a tudáscsomagot a `schemaVersion` + a manifest-fájl
sha256-a + a dokumentumszám hármasával, az ML-manifestet a `schema_version` +
fájl-sha256 + modellszám hármasával hivatkozza. Kitalált „package version"
mező beírása tilos. (Vö. [L164](../LESSONS.md#l164): a manifest-bővítés a
pinnelt assertion grep-eléséből induljon, ne feltételezésből — az
`ml_asset_manifest_test.dart` `expectedModelCount: 4` pinje ezért marad
érintetlen, ez az A6.)

### R5 — A fixture-ök FUTÁSIDEJŰ temp-könyvtárban élnek, nem új commitolt fájlokban

Az A2/A3 fixture-vezérelt cellái fixture `pubspec.lock`-ot, fixture pub
cache-könyvtárat és fixture manifesteket igényelnek. Az engedélyezett-fájllista
**nem tartalmaz** `test/fixtures/**` útvonalat, és a lista bővítése tilos
(ADR 0087 §2 — csak szűkíthető). **Feloldás:** a teszt a fixture-öket
`Directory.systemTemp.createTempSync(...)`-kal hozza létre és `tearDown`-ban
törli. Új commitolt fixture-fájl létrehozása a listán kívül **H3** — a
tesztfájlon belüli, futásidőben kiírt fixture nem az.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/app/build_info.dart",
  "tool/generate_release_manifest.dart",
  "tool/release/generate_sbom.py",
  "tool/release/verify_artifacts.py",
  "docs/release/workflows/release-apk-provenance.proposal.md",
  "THIRD_PARTY_NOTICES.md",
  "docs/release/supply-chain.md",
  "test/tooling/release_manifest_test.dart",
  "docs/rounds/e12-r06-versioning-provenance-and-sbom.md",
]
gate_tests = [
  "test/tooling/release_manifest_test.dart",
  "test/tooling/ml_asset_manifest_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a munkához a `build-apk.yml` vagy a `full-gate.yml` (a MERGE-kapu) módosítása kellene, a kimenet a `stopped` jelzés és brief-revízió kérése — a gate-workflow változtatása ADR 0052/0053 hatálya alatti külön kör ([L478](../LESSONS.md#l478)).

## 1. Cél

Minden kiadott artefaktum (app, backend, modell, tudáscsomag) legyen commitig visszakövethető, verzió-monoton és supply-chain szempontból leírt.

## 2. Jelenlegi állapot — mért tények

- `pubspec.yaml`: `version: 1.0.0+1` — a build number MÉG SOHA nem emelkedett.
- `.github/workflows/release-apk.yml` (174 sor) MA: fail-closed signing-secret ellenőrzés, `pubspec` verzió-regex, `strumsight-<ver>-<build>-<sha7>-production.apk` artefaktum-név, keystore materializálás + törlés. **Manifest, SBOM és license-bundle NINCS.**
- `lib/app/build_info.dart` **nem létezik** — a verzió/SHA ma nem jelenik meg a felületen.
- `tool/build_tutor_knowledge_manifest.dart` és a `test/tooling/ml_asset_manifest_test.dart` MÁR mutatják a „generált manifest + checksum" mintát (ADR 0063) — a release-manifest ezt követi.
- `THIRD_PARTY_NOTICES.md` és `docs/release/supply-chain.md` **nem létezik**; `tool/release/` **nem létezik**.
- A `pubspec.lock` verziókövetett (160 csomag, ebből 27 direkt) — a Flutter/Dart dependency-inventory determinisztikusan előállítható belőle. **License-mezőt viszont EGYETLEN csomagra sem tartalmaz** (`grep -ci license pubspec.lock` → `0`), és a `backend/requirements.txt` (11 pin) / `backend/requirements-dev.txt` (3 pin) sem — a license-forrás ezért a §0.0.A R1 szerinti kettős, MÉRT út (pub cache `LICENSE` + `_CURATED_LICENSES` jegyzék).
- `~/.pub-cache/hosted/pub.dev`: 423 könyvtárból **422-ben** van `LICENSE` fájl (kivétel: `.cache`).
- `package:yaml` csak **tranzitív** (`pubspec.lock:1261`) — tesztből nem importálható, mert a `pubspec.yaml` ennek a körnek tilos zóna (§0.0.A R2).

## 3. Scope

**Benne van:** `lib/app/build_info.dart` (compile-time `String.fromEnvironment` alapú build-metaadat: verzió, build number, rövid SHA, channel — a `main`/bootstrap NEM módosul, a megjelenítés későbbi kör dolga) · `tool/generate_release_manifest.dart` (determinisztikus JSON: app verzió, build, SHA, channel, ML-modell-manifest hivatkozás, tudáscsomag-verzió, artefaktum-checksumok) · `tool/release/generate_sbom.py` (Flutter/Dart a `pubspec.lock`-ból, backend a `requirements*.txt`-ből; license-mező hiánya → nem-nulla kilépés) · `tool/release/verify_artifacts.py` (checksum-audit egy artefaktum-könyvtáron) · `THIRD_PARTY_NOTICES.md` (generált) · `docs/release/supply-chain.md` · `docs/release/workflows/release-apk-provenance.proposal.md` — a `release-apk.yml`-hez JAVASOLT lépések (manifest + SBOM + notices artefaktum-feltöltés) teljes YAML-részletként, a beillesztés helyének megnevezésével.

**NINCS benne (tilos):**

- **Bármely `.github/workflows/**` fájl módosítása** (a §0.0 szerint: védett mérce-zóna; a kör javaslatot ír).
- A verzió/SHA UI-megjelenítése (`lib/features/settings/**`) — külön kör.
- `pubspec.yaml` verzió-emelés.
- `docs/adr/**` — az ADR 0447-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/app/build_info.dart` | ÚJ — compile-time build-metaadat |
| `tool/generate_release_manifest.dart` | ÚJ — a release manifest generátor |
| `tool/release/generate_sbom.py` | ÚJ — SBOM + license report |
| `tool/release/verify_artifacts.py` | ÚJ — checksum-audit |
| `docs/release/workflows/release-apk-provenance.proposal.md` | ÚJ — a workflow-lépések JAVASLATA (a beillesztés emberi lépés) |
| `THIRD_PARTY_NOTICES.md` | ÚJ — generált notice-bundle |
| `docs/release/supply-chain.md` | ÚJ — a supply-chain leírás |
| `test/tooling/release_manifest_test.dart` | a §6 cellái |

**Tilos zóna:** `.github/workflows/**` (MIND, a §0.0 szerint) · `.github/actions/**` · `pubspec.yaml` · `lib/features/**` · `lib/app/bootstrap/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0447)

### 5.1 A manifest determinisztikus: azonos bemenet → bájtazonos kimenet

*(§0.0.A R3 szerint pontosítva — ADR 0447 D1.)* Rendezett kulcsok, `\n`
sorvég, és **a manifest SEHOL nem tartalmaz generálási időbélyeget** — sem a
fő objektumban, sem testvér-mezőként. A determinizmus-cella a **TELJES fájlt**
hasonlítja össze, nincs kizárt mező. **NEM elfogadható gyengítés:** időbélyeg
bárhol a fájlban; rendezetlen map; a cella lazítása mező-kihagyással.

### 5.2 A build number SZIGORÚAN monoton: a csökkenés ÉS az egyenlőség is HIBA

*(ADR 0447 D2.)* A `verify_artifacts.py` a `--previous <korábbi manifest>`
opcióval kapott bázishoz méri az új build numbert; a szerződés szigorú `>`.
Bázis nélkül a monotonitás-ellenőrzés nem fut, de az eszköz ezt **kimondja**
(`baseline: none`). **NEM elfogadható gyengítés:** figyelmeztetés kilépési kód
nélkül; `>=` szerződés; a bázis hiányának néma elnyelése.

### 5.3 Hiányzó license vagy checksum BLOKKOL

*(§0.0.A R1 szerint pontosítva — ADR 0447 D3.)* A license két MÉRT forrásból
oldódik fel: (1) hosted Dart csomag → a pub cache-beli `LICENSE` fájl
(`--pub-cache`, különben `$PUB_CACHE`, különben `~/.pub-cache`); (2)
SDK-beli/nem-hosted Dart csomag és Python pin → a generátorban élő,
kézzel gondozott `_CURATED_LICENSES` jegyzék (SPDX-azonosító + forrás
bejegyzésenként). Egyik sem ad találatot → **nem-nulla kilépés a hiányzó
csomag megnevezésével**. **NEM elfogadható gyengítés:** „unknown"/`null`/üres
license-érték beírása és továbbmenetel; SPDX-azonosító kikövetkeztetése
license-szövegből; a hiányzó csomag kihagyása a leltárból.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A manifest kétszeri generálása bájtazonos, és a fájl SEHOL nem tartalmaz időbélyeget (a determinizmus-cella a TELJES fájlt méri, kizárt mező nélkül) | `release_manifest_test.dart` |
| A2 | Olyan függőség esetén, amelyre sem a pub cache `LICENSE` fájlja, sem a `_CURATED_LICENSES` jegyzék nem ad találatot, az SBOM-generátor **nem-nulla** kóddal lép ki, és megnevezi a csomagot; a kimenetben SEHOL nincs `"unknown"`/üres license-érték | `release_manifest_test.dart` (fixture `pubspec.lock` + fixture cache-könyvtár, `python3` stdlib) |
| A3 | Csökkenő ÉS egyenlő build number esetén a `verify_artifacts.py` nem-nulla kóddal lép ki; `--previous` nélkül `baseline: none`-t ír ki és 0-val lép ki | `release_manifest_test.dart` (küszöb-cellahármas) |
| A4 | A manifest hivatkozza az ML-modell-manifestet (`schema_version` + fájl-sha256 + modellszám) ÉS a tudáscsomag-manifestet (`schemaVersion` + fájl-sha256 + dokumentumszám); kitalált „package version" mező NINCS | `release_manifest_test.dart` |
| A5 | A javaslat-fájl YAML-részlete a korlátozott részhalmaz-parserrel valid, megnevezi a beillesztés helyét (a `release-apk.yml` létező lépésének nevével), és a manifest/SBOM/notices artefaktumot mind a hárommal feltölti | `release_manifest_test.dart` (saját YAML-parser + kötelező lépés-cellák) |
| A6 | A meglévő `ml_asset_manifest_test.dart` VÁLTOZATLANUL zöld (az `expectedModelCount: 4` pin érintetlen) | a §7 gate |
| A7 | A tesztfájl nem importál `package:yaml`-t, és nem shell-el ki `rg`/`grep`/`jq`/`gh` binárisra; a Python-eszközöket `python3`-mal, harmadik-feles csomag nélkül futtatja, és `python3` hiányában PIROSRA vált (nem skip) | `release_manifest_test.dart` (önmagát mérő forrás-introspekciós cella, [L110](../LESSONS.md#l110)) |

**Küszöb-cellahármas a build numberre** (a határ az EGYENLŐSÉG, ami TILOS — a
korábbival azonos build number újrafelhasználás). A cellák `python3 -c`-vel
kiszámolva, `previous_build = 42`:

| Cella | Új build | Elvárt |
|---|---|---|
| küszöb **alatt** | `41` (`42-1`) | **PIROS** — nem-nulla kilépés |
| **pontosan rajta** | `42` (`42`) | **PIROS** — nem-nulla kilépés |
| küszöb **fölött** | `43` (`42+1`) | **ZÖLD** — 0 kilépés |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A manifest generálási időbélyeget tesz a fő objektumba VAGY testvér-mezőbe | A1 |
| A license-hiány „unknown"/üres értékkel csúszik át | A2 |
| Az egyenlő build number elfogadott | a küszöb-cellahármas „pontosan rajta" cellája |
| `--previous` nélkül a monotonitás némán kimarad (`baseline: none` nélkül) | A3 |
| A modell-manifest hivatkozás kimarad a release manifestből | A4 |
| A tudáscsomagra kitalált „package version" kerül a mért `schemaVersion`+sha256 helyett | A4 |
| A javaslat YAML-je szintaktikailag törött vagy hiányzik belőle a notices-feltöltés | A5 |
| A teszt `package:yaml`-t importál vagy `rg`-re shell-el ki (boxon zöld, CI-n piros — L110) | A7 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki a manifest-generátorból a kulcs-rendezést, futtasd a §7 gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/release_manifest_test.dart test/tooling/ml_asset_manifest_test.dart
```

Az eszközök közvetlen futtatása (kimenet a §10-be):

```bash
dart run tool/generate_release_manifest.dart --output build/release-manifest.json
python3 tool/release/generate_sbom.py --profile production --output-notices THIRD_PARTY_NOTICES.md
python3 tool/release/verify_artifacts.py --manifest build/release-manifest.json
```

A `generate_release_manifest.dart` **kétszer** futtatva bájtazonos kimenetet
ad — a §10-be a két futás kimenetének `sha256`-a is kerüljön be.

A javaslat tényleges beillesztése és a dispatch orchesztrátor/emberi lépés a kör merge-e UTÁN — az implementer sem `.github/`-ot nem ír, sem `gh`-t nem hív.

## 8. Implementációs sorrend

1. `lib/app/build_info.dart` (ADR 0447 D7: `const`, `String.fromEnvironment`, dokumentált defaultok).
2. `tool/generate_release_manifest.dart` (determinisztikus JSON, időbélyeg NÉLKÜL — D1; ML- és tudáscsomag-hivatkozás D6 szerint).
3. `tool/release/generate_sbom.py` (D3 kettős license-forrás, fail-closed) + `THIRD_PARTY_NOTICES.md` generálás.
4. `tool/release/verify_artifacts.py` (checksum + szigorú monotonitás, D2).
5. `test/tooling/release_manifest_test.dart` — A1–A7, benne a küszöb-cellahármas és az A7 önmérő cella.
6. `docs/release/workflows/release-apk-provenance.proposal.md`.
7. `docs/release/supply-chain.md` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **A védett zóna érintése.** Bármely `.github/workflows/**` írása `H-GATEGUARD` halttal állítja meg a kört (§0.0) — a javaslat-fájl az egyetlen megengedett kimenet.
- **Nem-determinisztikus manifest.** Időbélyeg vagy rendezetlen map → a checksum minden buildben más (A1).
- **A license-adat hiánya.** *(§0.0.A R1 szerint pontosítva.)* A `pubspec.lock` **egyetlen** csomagra sem tartalmaz license-mezőt (mérve: `0` találat), ezért a license a pub cache `LICENSE` fájljából vagy a `_CURATED_LICENSES` jegyzékből jön; ami egyikből sem oldható fel, azt a generátornak HIBÁNAK kell jeleznie, nem kitalálnia (A2).
- **Boxon zöld / CI-n piros gate-cella.** Nem garantált binárisra shell-elő teszt ([L110](../LESSONS.md#l110)) vagy tranzitív csomag importja (`package:yaml`) a lokális gate-en átmegy, az exact-SHA CI-n megbukik (A7).

## 10. Implementation handoff — az implementer tölti ki

**Motor:** `sonnet-impl` (Claude Sonnet 5). **Ág:**
`sonnet-impl/e12-r06-versioning-provenance-and-sbom`, alap: `main @ 5734fc02`.

### Mit épített

- `lib/app/build_info.dart` — `BuildInfo`: `const` értékosztály, minden mező
  `String.fromEnvironment`/`int.fromEnvironment` default-értékű paraméterrel
  (`STRUMSIGHT_BUILD_VERSION`/`_BUILD_NUMBER`/`_BUILD_SHORT_SHA`/`_BUILD_CHANNEL`).
  Dokumentált defaultok (`0.0.0-dev` / `0` / `unknown` / `dev`) — a teszt
  ezeket pinneli. `main`/bootstrap nem hivatkozza (ADR 0447 D7).
- `tool/generate_release_manifest.dart` — pure `buildReleaseManifest(...)`
  függvény + `canonicalJsonBytes(...)` kanonikus JSON-enkóder (kulcsok
  rekurzívan rendezve minden szinten, `\n` sorvég, **nincs időbélyeg
  sehol** — D1). A `main()` beolvassa a `pubspec.yaml` verzió/build sorát
  (`parsePubspecVersion`), a git rövid SHA-t (`--git-sha` vagy
  `git rev-parse --short=7 HEAD`), az ML- és tudáscsomag-manifestet, és
  opcionális `--artifact` checksumokat. A tudáscsomagot/ML-csomagot
  KIZÁRÓLAG `schemaVersion`/`schema_version` + manifest-sha256 + elemszám
  hármassal hivatkozza, kitalált „version" mező nélkül (D6).
- `tool/release/generate_sbom.py` — csak stdlib. `pubspec.lock`-ot saját,
  sor-alapú parserrel olvassa (nem YAML-parser). License-forrás: (1) hosted
  Dart csomag → pub cache `LICENSE` fájl (path+sha256+első sor, **SPDX-et
  NEM következtet**), (2) SDK-csomag (`flutter`, `flutter_localizations`,
  `flutter_test`, `flutter_web_plugins`, `sky_engine`) és backend Python-pin
  → kézzel gondozott `_CURATED_LICENSES` (SPDX + forrás bejegyzésenként).
  Feloldatlan csomagnál nem-nulla kilépés, névvel (D3). `THIRD_PARTY_NOTICES.md`-t
  és egy `sbom.json`-t ír.
- `tool/release/verify_artifacts.py` — csak stdlib. Checksum-audit a
  manifest `artifacts` listáján; `--previous`-szal szigorú `>`
  build-number-ellenőrzés (csökkenés ÉS egyenlőség is hiba — D2);
  `--previous` nélkül `baseline: none` kiírás, 0 kilépés.
- `test/tooling/release_manifest_test.dart` — A1–A7, a `python3`-ra
  shell-elő cellák (A2/A3) `Directory.systemTemp.createTempSync`
  fixture-öket írnak és `addTearDown`-ban törlik (R5) — nincs új
  `test/fixtures/**` fájl. A5-höz saját, korlátozott GitHub Actions
  `steps:` YAML-részhalmaz-parser a tesztfájlban (`parseWorkflowSteps`),
  az ADR 0444 D3 mintája szerint. A7 önméri: nincs `package:yaml` import
  (import-sor regex, nem puszta substring), és minden `Process.*` hívás
  végrehajtható neve pontosan `{python3}` (regex-kinyerve, nem
  substring-keresés — ez rg/grep/jq/gh-t IS kizár, nem csak nem
  említi őket).
- `docs/release/workflows/release-apk-provenance.proposal.md` — teljes,
  bemásolható YAML-részlet 6 lépéssel (manifest generálás, SBOM+notices
  generálás, verify, 3× upload-artifact), a beillesztés helye névvel
  megnevezve (`Read APK metadata from pubspec` UTÁN, `Materialize
  production keystore` ELŐTT).
- `docs/release/supply-chain.md` — a fenti eszközök szerződésének leírása.
- `THIRD_PARTY_NOTICES.md` — a valódi fán generált kimenet (171 komponens:
  160 Dart + 11 backend Python pin, `--profile production`).

### Futtatott parancsok — tényleges kimenet

```
$ tools/round-gate.sh test/tooling/release_manifest_test.dart test/tooling/ml_asset_manifest_test.dart
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/release_manifest_test.dart               zöld
    test test/tooling/ml_asset_manifest_test.dart              zöld
    architecture                                                zöld
    secrets                                                     zöld
    l10n                                                        zöld
MINDEN GATE ZÖLD.
```

```
$ dart run tool/generate_release_manifest.dart --output build/release-manifest.json --channel production
Release manifest written: build/release-manifest.json
$ sha256sum build/release-manifest.json
d24ec1bb2e69158af441ca0e65ebfd5be0e982769db7df2629646cb6dd705965  build/release-manifest.json

$ dart run tool/generate_release_manifest.dart --output build/release-manifest.json --channel production
Release manifest written: build/release-manifest.json
$ sha256sum build/release-manifest.json
d24ec1bb2e69158af441ca0e65ebfd5be0e982769db7df2629646cb6dd705965  build/release-manifest.json
```

**A két futás sha256-a egyezik** (A1 valódi bizonyítéka a fán, `main @
5734fc02` állapotán, tényleges pub cache-szel).

```
$ python3 tool/release/generate_sbom.py --profile production --output-notices THIRD_PARTY_NOTICES.md --output-sbom build/sbom.json
SBOM written: build/sbom.json (171 components). Notices written: THIRD_PARTY_NOTICES.md.
(exit 0)

$ python3 tool/release/verify_artifacts.py --manifest build/release-manifest.json
baseline: none
artifacts: 0 verified
(exit 0)
```

### Valódi-sértés próba (§6.1, KÖTELEZŐ)

A `tool/generate_release_manifest.dart` `_writeCanonical` függvényéből
kivettem a kulcs-rendezést (`value.keys.toList()..sort()` →
`value.keys.toList()`), majd lefuttattam a §7 gate-et:

```
$ tools/round-gate.sh test/tooling/release_manifest_test.dart test/tooling/ml_asset_manifest_test.dart
...
00:00 +0 -1: A1 … canonicalJsonBytes sorts object keys ascending at every nesting level … [E]
  Expected: '{"a":{"b":3,"y":2},"m":[{"a":2,"z":1}],"z":1}\n'
    Actual: '{"z":1,"a":{"y":2,"b":3},"m":[{"z":1,"a":2}]}\n'
...
00:00 +6 -2: A1 … keys are sorted ascending, recursively, in the REAL release manifest … [E]
  Expected: ['app', 'artifacts', 'knowledgePackage', 'modelPackage', 'schemaVersion']
    Actual: ['schemaVersion', 'app', 'modelPackage', 'knowledgePackage', 'artifacts']
...
    → [3] test test/tooling/release_manifest_test.dart: PIROS (kilépési kód 1)
GATE_EXIT=10
```

Pontosan a két A1-cella (a `canonicalJsonBytes` közvetlen kulcs-rendezés
tesztje és a valódi manifest kulcs-rendezettség tesztje) váltott PIROSRA —
a többi 23/25 teszt (A2–A7) érintetlen maradt, ahogy a mérce-mátrix
előírja. Ezután a sort-hívást visszaállítottam
(`git diff tool/generate_release_manifest.dart` üres), és a gate-et
újrafuttatva minden lépés ismét ZÖLD (lásd fent).

### Amit NEM futtattam le, és miért

- **CI (`build-apk.yml`)** — a brief és AGENTS.md szerint a teljes suite +
  property gate + APK a CI-ban fut, azt az orchestrátor indítja
  (`gh workflow run`); implementer-session ezt nem hívja.
- **A `.github/workflows/release-apk.yml` tényleges szerkesztése és
  dispatch-a** — védett zóna (§0.0/D4), a kör helyette a
  `docs/release/workflows/release-apk-provenance.proposal.md` javaslatot
  szállítja; a tényleges bekötés orchesztrátor/emberi lépés a merge után.
- **`pubspec.yaml` verzió-emelés** — tiltott zóna (§3), nem a kör dolga.

## 11. Review — a Claude tölti ki
