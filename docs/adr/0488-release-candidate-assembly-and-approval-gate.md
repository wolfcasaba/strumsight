# ADR 0488 — Release Candidate összeállítás: jóváhagyás a build ELŐTT, fail-closed összeállító és a javaslat-fájl mint kimenet

- **Státusz:** Elfogadva
- **Dátum:** 2026-09-02
- **Kör:** E12-R25 (Chapter 12 — Release Roadmap, Sprint Planning & Final Integration)
- **Kontextus-ADR-ek:**
  [0052](0052-ci-apk-automerge-session-per-round.md) (zöld kapu — a teljes mérce-lánc),
  [0062](0062-ci-gate-chain-and-fail-closed-release-signing.md) (CI gate-sor és
  fail-closed release signing — az RC ezt HÍVJA, nem duplikálja),
  [0321](0321-gateguard-round-hold-not-chain-halt.md) (`PROTECTED_GLOBS` — a
  `.github/workflows/**` védett mérce-zóna),
  [0372](0372-gate-edit-policy.md) (a gate-szerkesztés álló felhatalmazásának fájlja),
  [0447](0447-release-manifest-provenance-and-sbom.md) (release manifest, SBOM,
  checksum-audit, javaslat-fájl a védett workflow helyett, D5: `python3` az EGYETLEN
  külső bináris a gate-tesztben),
  [0448](0448-production-signing-policy-and-secret-hardening.md) (production signing
  policy, korlátozott YAML-részhalmaz parszer a javaslat-fragmentre),
  [0481](0481-program-threat-model-and-release-security-scan.md) (release security scan),
  [0484](0484-privacy-safe-telemetry-contract-and-release-slo-schema.md) (AI-riport /
  SLO séma), [0112](0112-self-healing-pipeline.md) (a merge UTÁNI orchesztrátor-lépés)

## Kontextus

A Chapter 12 eddigi körei külön-külön leszállították a kiadási bizonyíték darabjait:
release manifest + SBOM + THIRD_PARTY_NOTICES (`E12-R06`), production signing policy
(`E12-R07`), AI-riport aggregáció (`E12-R16`), release security scan (`E12-R18`).
Ezek ma **egyenként futtatható** eszközök — nincs egyetlen olyan út, amely tiszta
checkoutból, egyetlen jóváhagyás mellett, auditálhatóan összerakja belőlük a
release-jelöltet.

A kör pre-flightja a fán ÚJRAMÉRTE az összeállítás előfeltételeit:

1. **A `.github/workflows/**` MA is védett zóna.** A `PROTECTED_GLOBS` (ADR 0321)
   tartalmazza, és az ADR 0372 álló felhatalmazásának fájlja — `.claude/gate-edit-policy`
   — a fán **nem létezik** (mérve: `ls -la .claude/gate-edit-policy` → nincs ilyen fájl).
   Egy implementer-session tehát `H-GATEGUARD`-dal állna meg az első workflow-íráson.
2. **A közös mérce-lánc egyetlen composite actionben él:**
   `.github/actions/flutter-gates/action.yml` — `flutter pub get` → `dart format
   --output=none --set-exit-if-changed lib test tool` → `flutter analyze lib/ test/ tool/`
   → `dart run tool/check_architecture.dart` → `dart run tool/ci/check_secrets.dart` →
   `dart run tool/ci/check_l10n_parity.dart` → `dart run tool/ci/check_assets.dart` →
   `flutter test` → `flutter test test/property`. Ezt hívja a `full-gate.yml`, a
   `build-apk.yml` ÉS a `release-apk.yml` is.
3. **A repó egyetlen `environment:`-alapú manuális jóváhagyást SEM használ ma.** A tíz
   workflow egyikében sincs `environment:` kulcs — az RC-workflow lenne az első.
4. **A testvér release-eszközök CLI-je mért, nem feltételezett:**
   `generate_sbom.py --profile {production|development} --pubspec-lock --pub-cache
   --output-sbom --output-notices`; `verify_artifacts.py --manifest [--previous]
   [--base-dir]`; `build_ai_report.py --profile --scope-file …`;
   `security_scan.py [--root --threat-model --exceptions --requirements --today --only
   --secrets-cmd --format]`; `tool/generate_release_manifest.dart`.
5. **A production signing út env-szerződése mért** (`release-apk.yml`):
   `STRUMSIGHT_RELEASE_STORE_FILE`, `STRUMSIGHT_RELEASE_STORE_PASSWORD`,
   `STRUMSIGHT_RELEASE_KEY_ALIAS`, `STRUMSIGHT_RELEASE_KEY_PASSWORD`,
   `STRUMSIGHT_REQUIRE_RELEASE_SIGNING=true`, a négy `ANDROID_*` secret előzetes
   jelenlét-ellenőrzésével egy külön `signing-prerequisites` jobban.

Ebből következik, hogy az RC-összeállítás **nem** egy új mérce, hanem a meglévők
sorbarendezése egy fail-closed úton — és hogy a workflow maga ebben a körben nem
telepíthető, csak javaslatként szállítható.

## Döntések

### D1 — A workflow JAVASLATként szállítódik, az összeállító KÓDként

A kör kimenete `docs/release/workflows/release-candidate.proposal.yml`: a javasolt
`release-candidate.yml` **teljes** tartalma, telepítés nélkül. A `.github/workflows/**`
alá ez a kör egyetlen bájtot sem ír.

**Elutasított alternatíva:** „kérjünk gate-edit felhatalmazást a körre". Az ADR 0372
felhatalmazása ÁLLÓ, nem kör-szintű; a fájl hiánya nem a kör hatásköre, és az ADR 0321
`H-GATEGUARD` tartása pontosan az a mérce, amit egy kör nem lazíthat magán.

**Precedens:** `docs/release/workflows/release-apk-provenance.proposal.md` (ADR 0447 D4)
és `release-apk-fingerprint.proposal.md` (ADR 0448 D4). Eltérés: azok **fragmentet**
szállítottak `.md`-be ágyazva (meglévő workflow-ba illesztendő lépések), ez a kör
**teljes új workflow-t**, ezért a kiterjesztés `.yml` — a fájl így önmagában
YAML-dokumentum, és a gépi cella a teljes dokumentumot parszolja, nem egy kimásolt
darabot.

### D2 — Az RC a KÖZÖS composite gate-et hívja, a lépéseket nem másolja

A javaslat a mérce-láncot kizárólag `uses: ./.github/actions/flutter-gates` alakban
futtatja.

**NEM elfogadható gyengítés:** a composite lépéseinek bemásolása az RC-workflow-ba. Két
mérce-példány garantáltan szétcsúszik; a `full-gate.yml` fejléce ugyanezt az elvet már
kimondja („ugyanabból a composite actionből — tehát a mérce NEM gyengül").

### D3 — A manuális jóváhagyás a build ELŐTT áll, `needs:`-szel kikényszerítve

A jóváhagyás egy **külön job**, amelynek `environment:` kulcsa van, és amelyre minden
build-, összeállító- és upload-job `needs:`-szel hivatkozik. GitHub Actions szemantika:
az `environment` védelmi szabálya a **job indulását** tartja vissza, ezért a jóváhagyás
csak akkor áll ténylegesen a build előtt, ha a build job a jóváhagyó jobtól FÜGG.

**NEM elfogadható gyengítés:** „építsük meg, és csak a publikálás legyen
jóváhagyás-köteles" — az aláírt artefaktum előállítása maga a kockázatos lépés.
**NEM elfogadható gyengítés:** bármilyen `workflow_dispatch` input, amely a jóváhagyást
átugorja (`skip_approval`, `force`, `dry_run: publish` és társai).

### D4 — Hiányzó kötelező bemenet = nem-nulla kilépés, részleges csomag nincs

`tool/release/assemble_rc.py` a csomag összeállítása ELŐTT feloldja a kötelező
bemeneteket (artefaktum, release manifest, SBOM, THIRD_PARTY_NOTICES, AI-riport,
security-riport, teszt-riport). Ha bármelyik hiányzik, **nem-nulla** kóddal lép ki, és
kimeneti könyvtárat nem hagy maga után félkészen.

**`--dry-run` szemantika (kimondva, hogy a §7 lokális futása értelmezhető legyen):** a
`--dry-run` feloldja és kiírja a bemeneti tervet — melyik kötelező bemenet van meg és
melyik hiányzik —, de **nem** ír csomagot. A kilépési kód ugyanaz a fail-closed szabály:
hiányzó kötelező bemenet esetén nem-nulla. Egy tiszta munkafán (ahol egyetlen
release-artefaktum sincs megépítve) a `python3 tool/release/assemble_rc.py --profile
development --dry-run` tehát **várhatóan nem-nulla kóddal áll meg, a hiányzó bemenetek
felsorolásával** — ez nem hiba, hanem a D4 bizonyítéka, és így kerül a kör §10-ébe.

**NEM elfogadható gyengítés:** figyelmeztetés + folytatás („legalább valami"), vagy a
hiányzó bemenet üres/placeholder fájllal pótlása.

### D5 — A checksum-manifest a csomag MINDEN fájlára kiterjed

Az összeállító a csomag minden fájljáról sha256-ot számol, és determinisztikus
(útvonal szerint rendezett, időbélyeg-mentes) checksum-manifestet ír. Az újraellenőrzés
(`verify`) egyetlen bájt megváltozására is nem-nulla kóddal áll meg.

**NEM elfogadható gyengítés:** csak az APK/AAB hashelése; a manifest, SBOM, notices,
AI-riport és security-riport ugyanúgy a kiadási bizonyíték része. A checksum-manifest
maga nem hasheli önmagát (nem lehet), de a benne felsorolt fájlok halmazát a
`verify` a csomag tényleges fájllistájához köti: **többlet fájl is eltérés**, nem csak
hiányzó vagy megváltozott.

### D6 — A gépi mérce fail-closed parszer, és a cellák a JAVÍTÁS ELŐTTI eszközzel pirosak

`test/tooling/rc_assembly_test.dart` a kör egyetlen Dart tesztfájlja. Szerződése:

1. **Külső bináris kizárólag `python3`** (ADR 0447 D5 precedens) — nincs `rg`/`grep`/
   `jq`/`gh` shell-out, és nincs `skip:` ág sehol.
2. **A javaslat YAML-jét korlátozott részhalmaz-parszer olvassa**, amely ebben a
   tesztfájlban él. `package:yaml` NEM importálható: csak tranzitív függőség ezen a fán,
   az import a `depend_on_referenced_packages` linttel PIROSRA váltaná az analyze-t
   (ADR 0448 D6 / ADR 0447 D5 precedens). Az itteni parszer azok **szuperhalmaza**:
   job-szintet is olvas (`jobs:`, `needs:`, `environment:`, `if:`, `uses:`), nem csak
   `steps:`-et.
3. **A parszer fail-closed.** Minden nem illeszkedő sor `FormatException`, a sor
   számával — a néma eldobás tilos. Ezen felül a cella **köti a parszolt elemek számát a
   nyers előfordulások számához** (pl. a `jobs:` alatti job-fejlécek és a `- name:`
   lépések nyers `RegExp`-találatainak száma), és a „nem tartalmazza a rosszat" alakú
   állításokat PONTOS EGYEZÉSRE cseréli. Mért ok: [L566](../LESSONS.md) — egy kézzel írt
   sor-parszerre épülő őr alapértelmezésben **fail-OPEN**: ami nem illeszkedik, az nem
   hibás, hanem NEM LÉTEZIK, és a tiltott állapot vákuumban „teljesíti" az elvárást.
4. **Minden acceptance-cella a saját javítása ELŐTTI eszközzel PIROS.** Mért ok:
   [L563](../LESSONS.md) — egy cella, amely a hibás implementáción is zöld, nem mérce.
   A kör §10-e dokumentálja a valódi-sértés próbát (a kötelező-bemenet ellenőrzés
   kivétele → A3 pirosra vált → visszaállítás).

### D7 — Az összeállító stdlib-only Python

`assemble_rc.py` kizárólag a Python standard libraryre épül (`argparse`, `hashlib`,
`json`, `pathlib`, `shutil`, `sys`). Precedens és indok: `generate_sbom.py` és
`verify_artifacts.py` modul-docstringje — a CI runner image semmilyen külső Python
csomagot nem garantál, és a gate-teszt `python3`-at hív, nem virtuális környezetet.

### D8 — A telepítés és a KÉT dispatch a merge UTÁNI orchesztrátor/emberi lépés

A javaslat beillesztése `.github/workflows/release-candidate.yml` néven, majd két
futtatás — egy **ZÖLD** (jóváhagyás megadva, minden bemenet megvan) és egy **BIZONYÍTOTT
PIROS** (hiányzó jóváhagyás vagy hiányzó AI-riport) — az orchesztrátor/ember dolga a kör
merge-e után (ADR 0112 §3). A linkek a kör §11 review-jegyzetébe kerülnek. Az implementer
sem `.github/`-ot nem ír, sem `gh`-t nem hív.

## Következmények

- **Pozitív:** a kiadási bizonyíték egyetlen, auditálható úton áll elő; a mérce egy
  helyen (composite action) él; a jóváhagyás a kockázatos lépés ELŐTT áll; a fail-closed
  összeállító nem enged ki félkész csomagot.
- **Negatív / vállalt ár:** a workflow a merge után egy kézi lépéssel települ, tehát a
  javaslat és a telepített fájl elméletileg szétcsúszhat. Ezt a D6 gépi cellái csak a
  javaslat-fájlon mérik — a telepített workflow-t a D8 két dispatchje bizonyítja, és a
  szétcsúszás elleni álló védelem az ADR 0372 felhatalmazási fájljának hiányán múlik,
  ami program-szintű nyitott kérdés, nem ezé a köré.
- **Nyitott:** a repó ma nem épít AAB-t sehol. A javaslat a mért production signing
  úton (D-kontextus 5.) épít; az AAB-lépés ugyanazt a `signingConfig`-ot használná, de
  ebben a körben nincs rá futtatott bizonyíték, ezért a javaslat az APK-t tekinti a
  kötelező artefaktumnak, és az AAB-t opcionális, azonos env-szerződésű lépésként írja le.
