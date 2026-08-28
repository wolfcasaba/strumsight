# ADR 0447 — Release manifest, provenance és SBOM

- **Státusz:** elfogadva (2026-08-28, E12-R06 pre-flight)
- **Kontextus:** SDD Chapter 12, Kör 6;
  [`docs/rounds/e12-r06-versioning-provenance-and-sbom.md`](../rounds/e12-r06-versioning-provenance-and-sbom.md)
- **Kapcsolódó:** [ADR 0063](0063-generated-ml-manifest-and-backend-ci.md)
  (generált ML asset manifest + checksum-gate a `flutter test`-en át),
  [ADR 0135](0135-tutor-knowledge-governance.md) (tudáscsomag verziózás,
  license-mező, tartalmi hash), [ADR 0321](0321-gateguard-round-hold-not-chain-halt.md)
  (`PROTECTED_GLOBS` — a `.github/workflows/**` védett mérce-zóna),
  [ADR 0372](0372-gate-edit-policy.md) (a gate-szerkesztés
  álló felhatalmazásának FÁJLJA), [ADR 0444](0444-delivery-workflow-and-repository-policy.md)
  (D3: korlátozott YAML-részhalmaz saját parserrel, `package:yaml` nélkül),
  [ADR 0052](0052-ci-apk-automerge-session-per-round.md) / [ADR 0053](0053-ci-full-test-suite.md)
  (a zöld kapu)

## Kontextus — mért tények (E12-R06 pre-flight, `main @ f1cba2f9`)

1. `pubspec.yaml` → `version: 1.0.0+1`; a build number MÉG SOHA nem emelkedett.
2. `.github/workflows/release-apk.yml` (174 sor) a `Read APK metadata from
   pubspec` lépésben (78–96. sor) regexszel kényszeríti a `<version>+<build>`
   alakot, és a `strumsight-<ver>-<build>-<sha7>-production.apk` nevet állítja
   elő. **Manifest, SBOM és notice-bundle nincs benne.**
3. `lib/app/build_info.dart` nem létezik — a verzió/SHA sehol nem jelenik meg.
4. `tool/release/`, `THIRD_PARTY_NOTICES.md`, `docs/release/supply-chain.md`
   nem létezik.
5. **`pubspec.lock` NEM tartalmaz license-mezőt: `grep -ci license pubspec.lock`
   → `0`, 160 csomagra.** A `backend/requirements.txt` (11 pin) és a
   `backend/requirements-dev.txt` (3 pin) szintén nem hordoz license-adatot.
6. A `~/.pub-cache/hosted/pub.dev` alatt **423 könyvtárból 422-ben van
   `LICENSE` fájl** (az egyetlen kivétel a `.cache` szolgáltatás-könyvtár) —
   a hosted Dart csomagok license-SZÖVEGE tehát lokálisan, offline elérhető.
7. `assets/ml/model_manifest.json` → `schema_version: 1`, `models[]`
   (4 bejegyzés, `sha256` mezővel). `assets/tutor_knowledge/manifest.json` →
   `schemaVersion: 1` + `documents[]` (10 dokumentum, dokumentumonként
   `license`, `version`, `contentHash`). **Csomag-szintű verziómező egyikben
   sincs.**
8. `package:yaml` a fán csak **tranzitív** függőség (`pubspec.lock:1261`); a
   `depend_on_referenced_packages` lint miatt tesztből nem importálható —
   ezt az E12-R03 (`test/tooling/repository_policy_test.dart:92`) már mérte és
   dokumentálta.
9. `.claude/gate-edit-policy` a fán **nem létezik** (`tools/gateguard-scan.py`),
   tehát a `.github/workflows/**` írása egy implementer-sessionben
   strukturálisan `H-GATEGUARD`-dal állna meg.

## Döntések

### D1 — A release manifest determinisztikus, és NEM tartalmaz időbélyeget

`tool/generate_release_manifest.dart` a bemenetei (pubspec verzió/build, git
rövid SHA, channel, `assets/ml/model_manifest.json`,
`assets/tutor_knowledge/manifest.json`, opcionális artefaktum-könyvtár) tiszta
függvénye: rendezett kulcsok, `\n` sorvég, kétszeri futtatásra **bájtazonos**
kimenet.

A manifestbe **semmilyen formában nem kerül generálási időbélyeg** — sem a fő
objektumba, sem testvér-mezőként. A build ideje a CI artefaktum-metaadata
dolga, nem a manifesté.

> **Miért szigorúbb, mint a kör-brief eredeti §5.1-e.** Az eredeti szöveg egy
> „külön, explicit build-idő mezőt, amit a determinizmus-teszt kizár" engedett,
> ugyanabban a bekezdésben, amelyben a mező-kihagyásos teszt-lazítást
> kifejezetten megtiltotta. A két mondat egymásnak feszül: egy kizárt mező
> pontosan az a lazítás. A feloldás a szigorúbb ág — nincs időbélyeg, tehát
> nincs mit kizárni, és a determinizmus-cella a TELJES fájlt méri.

**NEM elfogadható gyengítés:** időbélyeg bárhol a fájlban; rendezetlen map;
a determinizmus-cella mező-kihagyással.

### D2 — A build number szigorúan monoton, az EGYENLŐSÉG is hiba

`tool/release/verify_artifacts.py` a `--previous <korábbi manifest>` opcióval
kapott bázishoz méri az új build numbert. A szerződés **szigorú `>`**: a
csökkenés ÉS az újrafelhasználás (egyenlőség) egyaránt **nem-nulla kilépés**.

Bázis nélkül (`--previous` elhagyva) a monotonitás-ellenőrzés nem fut le, de
ezt az eszköz **kimondja** a kimenetében (`baseline: none`) — a hallgatólagos
átcsúszás tilos.

**NEM elfogadható gyengítés:** figyelmeztetés nem-nulla kilépési kód nélkül;
`>=` szerződés; a bázis hiányának néma elnyelése.

### D3 — Hiányzó license BLOKKOL, és a license-adat MÉRT, nem kitalált

Mivel a `pubspec.lock` és a `requirements*.txt` license-mezőt nem hordoz
(Kontextus 5.), `tool/release/generate_sbom.py` a licenszt **két, egyaránt
mért forrásból** oldja fel, ebben a sorrendben:

1. **Hosted Dart csomag:** a feloldott csomagverzió SAJÁT `LICENSE` fájlja a
   pub cache-ből (`--pub-cache`, különben `$PUB_CACHE`, különben
   `~/.pub-cache`) — a bejegyzés a fájl elérési útját, sha256-ját és első
   nem-üres sorát rögzíti.
2. **SDK-beli / nem-hosted Dart csomag és Python pin:** a generátorban élő,
   kézzel gondozott **license-jegyzék** (`_CURATED_LICENSES`), a
   `tool/ci/check_song_fixture_licenses.dart` már bevett fájlon-belüli
   provenance-jegyzék mintájára — bejegyzésenként SPDX-azonosító és forrás.

Ha egyik forrás sem ad találatot, a generátor **nem-nulla kóddal lép ki**, és
megnevezi a hiányzó csomagot. Az SBOM SPDX-azonosítót **nem következtet ki**
license-szövegből: vagy mért szöveg-hivatkozás van, vagy jegyzék-bejegyzés,
vagy hiba.

**NEM elfogadható gyengítés:** `"unknown"`, `null` vagy üres license-érték
beírása és továbbmenetel; SPDX-azonosító heurisztikus kitalálása; a hiányzó
csomag kihagyása a leltárból.

### D4 — A `.github/workflows/**` védett zóna: a kör JAVASLATOT szállít

A workflow-változás `docs/release/workflows/release-apk-provenance.proposal.md`
formában, teljes, bemásolható YAML-részletként és a beillesztés pontos
helyének megnevezésével készül. A tényleges szerkesztés és dispatch a kör
merge-e UTÁNI orchesztrátor/emberi lépés (ADR 0321 + ADR 0112 §3). A javaslat
YAML-validitását és a kötelező lépéseit gépi cella méri — a mérce nem gyengül,
csak a védett fájl marad érintetlen.

### D5 — A gate-cellák fixture-vezéreltek, és nem támaszkodnak nem garantált binárisra

- A Dart teszt **nem** importál `package:yaml`-t (Kontextus 8.); a javaslat
  YAML-részletét a tesztfájlban élő **korlátozott részhalmaz-parser**
  ellenőrzi, az ADR 0444 D3 precedense szerint.
- A teszt **nem** shell-el ki `rg`, `grep`, `jq` vagy `gh` binárisra
  ([L110](../LESSONS.md#l110)).
- A két Python eszköz kilépési kódját a teszt `python3`-mal, **kizárólag a
  standard könyvtárra** támaszkodva méri (PyYAML és bármely más
  harmadik-feles Python csomag használata tilos: a runner-image nem
  garantálja). Ha `python3` nem elérhető, a cella **PIROSRA vált** — a néma
  skip tilos, mert az a mérés hiányát zöldnek mutatná.
- Minden Python-eszközt fixture-bemeneten mér a gate (fixture `pubspec.lock`,
  fixture cache-könyvtár, fixture manifestek), nem a valódi fán — a valódi
  futtatás a kör §10 handoffjának dokumentált bizonyítéka.

### D6 — A tudáscsomag „verziója" a mért séma-verzió + manifest-checksum

Csomag-szintű verziómező nem létezik (Kontextus 7.), ezért a release manifest
a tudáscsomagot a `schemaVersion`, a manifest-fájl sha256-a és a
dokumentumszám hármasával hivatkozza; ugyanígy az ML-modell-manifestet a
`schema_version`, a fájl sha256-a és a modellszám hármasával. Kitalált
„package version" mező beírása tilos.

### D7 — `BuildInfo`: compile-time metaadat, futásidejű mellékhatás nélkül

`lib/app/build_info.dart` `String.fromEnvironment` / `int.fromEnvironment`
alapú, `const` konstrukciójú érték-osztály (verzió, build number, rövid SHA,
channel). A `main`/bootstrap NEM módosul, a megjelenítés külön kör dolga. A
`--dart-define` hiánya nem hiba: dokumentált default értékek lépnek életbe,
amelyeket a kör tesztje pinnel.

## Következmények

- Minden kiadott artefaktum commitig visszakövethető, és a lánc gépi
  ellenőrzést kap a `flutter test`-en át (ADR 0063 mintája).
- A supply-chain leírás (`docs/release/supply-chain.md`) és a
  `THIRD_PARTY_NOTICES.md` a generátorok kimenetéből él, nem kézi ápolásból.
- A workflow tényleges bekötése egy jövőbeli, emberi kapun átmenő lépés marad;
  addig a javaslat-fájl a szerződés.
- Új backend Python függőség felvétele license-jegyzék-bejegyzés nélkül
  **megbukik** a generátoron — ez szándékos, fail-closed költség.
