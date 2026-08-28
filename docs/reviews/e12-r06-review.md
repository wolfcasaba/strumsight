# E12-R06 review — Versioning, provenance, SBOM és release manifest

- **Reviewer:** Claude (Opus 5), orchestrátor-szék, read-only
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kör-ág:** `sonnet-impl/e12-r06-versioning-provenance-and-sbom`
- **Review-alap:** `5734fc02` (pre-flight) → `11bd78dd` (implementáció)
- **Brief:** [`docs/rounds/e12-r06-versioning-provenance-and-sbom.md`](../rounds/e12-r06-versioning-provenance-and-sbom.md)
- **Szerződés:** [ADR 0447](../adr/0447-release-manifest-provenance-and-sbom.md) D1–D7
- **Dátum:** 2026-08-28

## 0. Előzetes ellenőrzések

| Ellenőrzés | Eredmény |
|---|---|
| Kör-jelzés (`.codex-round-status`) | `status=done`, `head=11bd78dd`, `dirty_files=1` |
| `dirty_files=1` kivizsgálva (L21) | a gitignore-olt `.codex-round-status` maga (`git check-ignore -v` → `.gitignore:66`); a munkafa egyébként tiszta |
| `scope_audit` a jelzésfájlban | `scope_audit=ok`, `scope_audit_base=5734fc02`, `scope_audit_changed=9` |
| Scope-audit ÚJRA, reviewer-oldalról | `python3 tools/scope-audit.py --repo /tmp/review-e12-r06 --brief … --base 5734fc02` → **`Legacy scope audit OK (5734fc02e64d..11bd78dddc1d, 9 changed path(s), 0 generated/ignored)`** |
| Handoff (§10) csonkolatlan, tényleges kimenettel | igen — gate-összegzés, két manifest-sha256, valódi-sértés próba |

**Változott fájlok (9, mind az `allowed_paths` listán):** `lib/app/build_info.dart`,
`tool/generate_release_manifest.dart`, `tool/release/generate_sbom.py`,
`tool/release/verify_artifacts.py`, `test/tooling/release_manifest_test.dart`,
`docs/release/workflows/release-apk-provenance.proposal.md`,
`docs/release/supply-chain.md`, `THIRD_PARTY_NOTICES.md`, a kör briefje (§10).
`+3120 / −0`. **`.github/**` érintetlen** — a védett zóna sértetlen (D4).

## 1. Gate-újrafuttatás izolált klónban

A mérce nem bemondás: friss `/tmp/review-e12-r06` klón az origin `11bd78dd`
fejére resetelve, `tools/prepare-flutter-generated.sh` után:

```
tools/round-gate.sh test/tooling/release_manifest_test.dart test/tooling/ml_asset_manifest_test.dart

    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/release_manifest_test.dart               zöld
    test test/tooling/ml_asset_manifest_test.dart              zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
MINDEN GATE ZÖLD.
```

Az `ml_asset_manifest_test.dart` 13 cellája változatlanul zöld, az
`expectedModelCount: 4` pin érintetlen (**A6**, vö. [L164](../LESSONS.md#l164)).

## 2. Reviewer-próbák — a zöld gate NEM bizonyíték

Öt eldobható próbát futtattam a SZÁLLÍTOTT eszközökön (nem a teszteken
keresztül), hogy a szerződések a valódi kilépési kódokon is mérve legyenek:

| Próba | Parancs lényege | Mért kimenet | Verdikt |
|---|---|---|---|
| P1 — feloldhatatlan Dart license | fixture lock `mystery_pkg`-gel, fixture pub cache | `generate_sbom: no license source for Dart package mystery_pkg@2.0.0 …`, **exit 1**, és **sem `sbom.json`, sem a notices nem jött létre** (nincs részleges kimenet) | D3 ✅ |
| P2 — feloldhatatlan Python pin | `totally-not-a-real-pkg>=1` | `no license source for Python package totally-not-a-real-pkg: no _CURATED_LICENSES entry`, **exit 1** | D3 ✅ |
| P3 — küszöb-cellahármas | `--previous` build 42 ellen | `41 → exit 1` („not strictly greater"), `42 → exit 1`, `43 → exit 0` | D2 ✅ (a brief §6 hármasa pontosan) |
| P4 — checksum-eltérés | hamis sha256 egy létező artefaktumra | `checksum mismatch for art.bin: manifest says 000…, actual is 2d71…`, **exit 1** | D2 ✅ |
| P5 — notices útvonal-függés | fixture pub cache `/tmp/…` alatt | a notices `- License text: /tmp/tmp.JLAnHaoPa1/pc/hosted/…` sort ír | **lásd F1** |

Az implementer saját valódi-sértés próbáját (kulcs-rendezés kivétele →
**A1** pirosra vált, 2 cella, a többi 23 zöld marad) a §10 handoff
csonkolatlan kimenettel dokumentálja, és a mérce-mátrix sorával egyezik.

## 3. Acceptance criteria — tételesen

| # | Bizonyíték | Verdikt |
|---|---|---|
| **A1** | 8 cella: `canonicalJsonBytes` rekurzív kulcs-rendezés, kétszeri futás bájtazonossága, ISO-8601-minta hiánya **a teljes fájlon** (kizárt mező NÉLKÜL), időbélyeg-nevű kulcs hiánya rekurzívan, `DateTime.now()` hiánya a generátor forrásában — **és mindkét szkennerhez ön-ellenőrző cella** („a regex tényleg detektál"). A fán mért két futás sha256-a azonos (`d24ec1bb…`) | ✅ |
| **A2** | fixture lock + fixture pub cache; feloldhatatlan csomag → nem-nulla kilépés a NÉVVEL, részleges kimenet nélkül; feloldott esetben `_expectNoUnknownLicenseValues` végigjárja az SBOM-ot `unknown`/`null`/üres értékre. Reviewer-próbával megerősítve (P1, P2) | ✅ |
| **A3** | küszöb-cellahármas (41/42/43), `--previous` nélküli `baseline: none` cella, checksum-eltérés cella. Reviewer-próbával megerősítve (P3, P4) | ✅ |
| **A4** | a valódi manifest `modelPackage` = `schema_version`+`manifestSha256`+`modelCount` (4), `knowledgePackage` = `schemaVersion`+`manifestSha256`+`documentCount` (10); kitalált „version" mező nincs; mátrix-sor: `models` nélküli ML-manifest → elutasítás, nem néma átcsúszás | ✅ |
| **A5** | saját, korlátozott `steps:` részhalmaz-parser a tesztfájlban; 4 mátrix-sor (nem-literális `run:`, ismeretlen kulcs, hiányzó notices-feltöltés) + a VALÓDI javaslat-fájl parse-olása; a beillesztési pont a `release-apk.yml` LÉTEZŐ lépésneveihez mérve | ✅ |
| **A6** | `ml_asset_manifest_test.dart` 13/13 zöld, változatlan | ✅ |
| **A7** | önmérő cellák: nincs `package:yaml` import (import-sor **regex**, nem substring); minden `Process.*` hívás végrehajtható neve regexszel kinyerve, halmaz-egyenlőség `{python3}`-mal (ez rg/grep/jq/gh-t is kizár); `python3 --version` exit 0 → hiánya PIROS, nem skip | ✅ |

## 4. Leletek

| Kód | Súly | Fájl:sor | Lelet |
|---|---|---|---|
| F1 | **MINOR** | `tool/release/generate_sbom.py:241`, `THIRD_PARTY_NOTICES.md` | A notices-bundle **155 abszolút `/home/ubuntu/.pub-cache/…` útvonalat** tartalmaz |
| F2 | **MINOR** | `docs/release/workflows/release-apk-provenance.proposal.md:66-70` | A javasolt „Verify release artifacts" lépés a gyakorlatban **nulla artefaktumot** auditál |
| F3 | **NOTE** | `test/tooling/release_manifest_test.dart:561-565` | `_requirePython3()` üres függvény — a neve őrt ígér, a törzse nem csinál semmit |
| F4 | **NOTE** | `tool/release/generate_sbom.py:304` | A Python komponensek `version: null`-lal kerülnek az SBOM-ba |

### F1 (MINOR) — a committolt notices-bundle gép-függő abszolút útvonalakat hordoz

**Mérés.** `grep -c "/home/ubuntu" THIRD_PARTY_NOTICES.md` → **`155`**. Példa:

```
- License text: /home/ubuntu/.pub-cache/hosted/pub.dev/analyzer-12.1.0/LICENSE
```

A P5 próba megerősíti, hogy ez nem a generálás egyszeri melléktermékve: a
`_resolve_dart_license` a `licensePath`-ba a TELJES, feloldott cache-útvonalat
írja, tehát más `PUB_CACHE`-sel (CI runner, másik fejlesztő) **más fájl jön ki
ugyanabból a commitból**.

**Miért lelet.** Három, egymástól független ok:
1. a `THIRD_PARTY_NOTICES.md` egy **kiadott, jogi célú artefaktum** — egy
   olyan „License text" hivatkozás, ami az olvasó gépén nem létezik, nem
   teljesíti a notice-bundle funkcióját;
2. **nem reprodukálható**: a committolt fájl és egy CI-beli újragenerálás
   szükségszerűen eltér, tehát a „regeneráld és diffeld" ellenőrzés — a
   supply-chain kör legtermészetesebb jövőbeli őre — soha nem lehet zöld;
3. a build-box home-könyvtárának útvonala bekerül a repóba.

**Nem szerződésszegés:** az ADR 0447 D3 szó szerint „a fájl elérési útját"
írja elő — ezt a szöveget **én** írtam a pre-flightban, tehát a lelet az én
specifikációm gyengesége, nem az implementer hűtlensége. Ezért MINOR, nem
MAJOR.

**Javasolt irány (nem kész patch):** a `licensePath` a **pub cache gyökeréhez
képest relatív** legyen (`hosted/pub.dev/<pkg>-<ver>/LICENSE`), a
cache-gyökér pedig külön, `pubCacheRelative: true` jellegű jelzéssel vagy
egyáltalán ne szerepeljen; a notices újragenerálva; és egy ÚJ gate-cella
mérje, hogy sem az SBOM, sem a notices nem tartalmaz abszolút
filesystem-útvonalat (`^/` kezdetű `licensePath`, illetve `/home/`, `/Users/`,
`C:\` minta) — enélkül a hibaosztály visszatérhet.

### F2 (MINOR) — a javasolt verify-lépés nulla artefaktumot auditál

A javaslat a manifestet `--artifact` nélkül generáltatja, a beillesztési pont
(`Read APK metadata from pubspec` UTÁN, `Materialize production keystore`
ELŐTT) pedig még az APK build ELŐTT van, tehát ott nincs is mit
checksumolni. A `verify_artifacts.py` így mindig `artifacts: 0 verified` +
exit 0 kimenetet ad — a lépés a gyakorlatban no-op.

A javaslat a `--previous` hiányát **kimondottan és indokoltan** dokumentálja
(„Why there is no `--previous`…"); a nulla-artefaktum eset ugyanezt a kezelést
érdemli. **Javasolt irány:** vagy egy azonos szellemű „Why the verify step
audits zero artifacts here" szakasz a beillesztés-hely kényszerének
megnevezésével és a follow-up megjelölésével, vagy a verify-lépés
áthelyezése/duplikálása az APK-build UTÁNRA `--artifact` paraméterrel.

### F3 (NOTE) — üres `_requirePython3()`

A függvény törzse egyetlen kommentblokk; két `group()` hívja meg. A tényleges
őr az A7 harmadik cellája (`python3 --version` → exit 0). A név őrt ígér, a
kód nem az. **Javasolt irány:** vagy törlés a hívásokkal együtt (a
kommentjének tartalma a group doc-jába való), vagy tegye meg, amit a neve
mond.

### F4 (NOTE) — a Python komponensek verzió nélkül kerülnek az SBOM-ba

`components[].version` a Python ágon mindig `null` (a notices `(unpinned)`-et
ír), noha a `backend/requirements.txt` mind a 11 pinre hordoz
verzió-specifikációt (`fastapi>=0.115,<0.116`). A brief ezt nem írta elő,
tehát nem szerződésszegés, de egy verzió nélküli SBOM-sor a supply-chain cél
felét adja. Follow-up körre javasolt (a pin-string átvétele `versionSpec`
mezőként).

## 5. Architektúra és termékhatárok (AGENTS.md §5–§6)

- `lib/app/build_info.dart` tiszta `const` értékosztály, nincs import a
  `features/`-ből, nincs futásidejű mellékhatás; a `main`/bootstrap
  változatlan (D7 ✅). Az `architecture` gate zöld.
- Hálózat, mikrofon, tárolás, secret: a kör diffje egyiket sem érinti. A
  `check_secrets` gate zöld. A brief `risk = "normal"`, a diff nem érint
  hálózatot/hitelesítést/importált felhasználói adatot, ezért külön
  `security-reviewer` futtatása nem indokolt.
- A két Python eszköz csak stdlibet használ (`argparse`, `hashlib`, `json`,
  `os`, `re`, `sys`, `dataclasses`, `pathlib`) — nincs harmadik-feles import,
  tehát a runner-image nem garantált csomagjaira nem támaszkodik (D5 ✅,
  [L110](../LESSONS.md#l110)).

## 6. VÉGSŐ DÖNTÉS

**CHANGES REQUESTED** — 0 BLOCKER / 0 MAJOR / **2 MINOR** / 2 NOTE.

Nincs merge-blokkoló lelet: a hét acceptance-cella mind teljesül, a gate
függetlenül zöld, a scope tiszta, és mind a négy kötött döntés (D1–D3, D6)
reviewer-próbával, nem bemondásra igazolt. Az **F1** viszont egy committolt,
kiadásra szánt jogi artefaktumot tesz gép-függővé és
nem-reprodukálhatóvá — ez egy supply-chain kör központi állításának mond
ellent, és a javítása kicsi, a diffet nem hizlalja. Ezért egy javító kör
következik **F1 + F2 + F3** leletekkel; az **F4** follow-up.

## 7. Javító kör után — zárás leletenként

*(A javító kör után frissítve.)*
