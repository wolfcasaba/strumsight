# E12-R05 review — Feature flag registry és emergency kill switch

- **Kör:** `E12-R05` · **Branch:** `sonnet-impl/e12-r05-feature-flag-registry-and-kill-switch`
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5) · implementációs commit `d9dfe4f5`
- **Reviewer:** Claude Opus 5 (orchestrátor), read-only, izolált `/tmp/review-e12-r05` klónban
- **Normatív forrás:** [ADR 0446](../adr/0446-feature-flag-registry-and-emergency-kill-switch.md),
  [brief](../rounds/e12-r05-feature-flag-registry-and-kill-switch.md) §0.0 (R1–R7)
- **Kockázat:** `high` → a `security-reviewer` futtatása KÖTELEZŐ volt, lefutott (§4)

## 1. Verdikt

**CHANGES REQUESTED** (első kör) — 0 BLOCKER, 0 MAJOR, **3 MINOR**, 5 NOTE.
A kör tartalmi magja (a fail-closed prioritási lánc és az aszimmetrikus
vészkapcsoló) MÉRTEN helyes; a leletek a *gépi őr szorosságát* és egy
bizonyítatlan dokumentum-állítást érintenek — pontosan azt, amit ez a kör
ígér („a katalógus nem tud csendben elavulni").

## 2. Amit magam mértem (nem bemondásra)

### 2.1 Scope-audit — OK

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e12-r05 \
    --brief docs/rounds/e12-r05-feature-flag-registry-and-kill-switch.md --base c37904d0
Legacy scope audit OK (c37904d0ce6d..d9dfe4f559d9, 9 changed path(s), 0 generated/ignored)
```

Mind a 9 érintett útvonal a brief `allowed_paths` listáján van; a tilos zóna
(`lib/app/config/**`, `lib/features/**`, `backend/**`, `tools/**`, `.github/**`,
`docs/adr/**`) érintetlen. A `lib/app/config/feature_flags.dart` **nem**
módosult (`git diff c37904d0..d9dfe4f5 -- lib/app/config/` üres).

### 2.2 Kötelező gate — MINDEN ZÖLD (saját futtatás, izolált klón)

```
$ cd /tmp/review-e12-r05 && ./tools/round-gate.sh \
    test/core/feature_flags/feature_flag_registry_test.dart \
    test/tooling/feature_flag_audit_test.dart \
    test/app/config/feature_flags_test.dart
    format                                                     zöld
    analyze                                                    zöld
    test test/core/feature_flags/feature_flag_registry_test.dart zöld
    test test/tooling/feature_flag_audit_test.dart             zöld
    test test/app/config/feature_flags_test.dart               zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
MINDEN GATE ZÖLD.
```

```
$ dart run tool/check_feature_flags.dart
Feature flag audit OK (0 issue(s)).            # exit 0 — R5 teljesül
```

### 2.3 Katalógus-teljesség — mérve, mezőnév-szinten

```
$ grep -oE "final bool [A-Za-z0-9]+;" lib/app/config/feature_flags.dart | sort   # 40
$ grep -oE "key: '[A-Za-z0-9]+'"  lib/core/feature_flags/feature_flag_registry.dart | sort   # 40
$ diff <(fields) <(keys)  →  IDENTICAL
```

**Orchestrátor-önkorrekció:** a brief §0.0 **R1 pontja téves volt** (37 mező) —
a pre-flight regexem (`[a-zA-Z]+`) kiejtette a **számjegyet tartalmazó** három
mezőnevet (`practiceEngineV2Enabled`, `songTrainerV2Enabled`,
`audioAnalysisV2Enabled`). A helyes érték **40** (3 kötelező + 37
alapértelmezett), ahogy az implementer §10.1-ben — a briefet kijavítottam
(`docs(e12-r05): R1 számkorrekció`). Az implementer a helyes, MÉRT számot
követte, és ezt jelentette is: ez a kívánt viselkedés, nem eltérés.

### 2.4 Reviewer-próba — a teljesség-őr MÉRT szökési útja (F1 forrása)

A `/tmp` klónban két új mezőt szúrtam a `FeatureFlags` osztályba, majd
futtattam az auditot, végül visszaállítottam:

```
$ # beszúrva: `final bool? probeNullableFlag;`  és  `final bool probeInitializedFlag = true;`
$ dart run tool/check_feature_flags.dart
Feature flag audit OK (0 issue(s)).
AUDIT_EXIT=0                                   # ← MINDKÉT új flag CSENDBEN kicsúszott
$ git checkout -- lib/app/config/feature_flags.dart   # visszaállítva, working tree tiszta
```

### 2.5 A kötelező valódi-sértés próbák — reprodukálva

A brief §6.1 A1-próbája a suite-ba is be van kötve
(`feature_flag_audit_test.dart:174-197`: a `visionExperimentalFineFretEnabled`
bejegyzés kivétele a VALÓS katalógusból a VALÓS mért mezőnevek ellen →
`missingCatalogEntry`), és a §10.4 mindkét kézi próbát (A1 és A3) a bukó cella
nevével + a hibaüzenettel dokumentálja. A polaritást ellenőriztem: az A3 cella
(`:89-97`) a szimmetrikus emergency-felülírásra tényleg pirosra vált.

## 3. Acceptance criteria — tételesen

| # | Állapot | Bizonyíték |
|---|---|---|
| A1 | ✅ (F1/F3 szorítással) | mind a 40 mező katalogizálva (2.3); `missingCatalogEntry`/`unknownCatalogEntry`/`duplicateCatalogEntry` cellák zöldek |
| A2 | ✅ | `feature_flag_registry_test.dart:34-67` — nincs forrás / egyik forrásnak sincs véleménye → `failClosedDefault`, és a `true` alapérték cellája bizonyítja, hogy tényleg a definícióból olvas |
| A3 | ✅ | `:70-121` négy cella: `false` felülír mindent; `true` átcsordul (`local`, ill. `failClosedDefault`) — `feature_flag_source.dart:91` `emergencyValue == false` |
| A4 | ✅ | `:124-176` — bukott aláírás: az érték figyelmen kívül, `returnsNormally`, átcsordulás `capability`/`failClosedDefault`-ra |
| A5 | ✅ | `feature_flag_audit_test.dart:131-155` + küszöb-cellahármas (`:43-70`, injektált `now = 2026-08-28`, inkluzív határ) |
| A6 | ⚠️ NOTE (F4) | `:216-247` — szerkezeti bizonyíték: a resolver nem lát adattárat; a `security-reviewer` grep-je (`writeAsString\|delete\|clear(\|remove(\|SecureStorage\|Dio` → NO SINKS) erősíti |
| A7 | ✅ | `test/app/config/feature_flags_test.dart` zöld a saját gate-futtatásomban; a fájl nem módosult (2.1); `test/app/feature_flags_test.dart` az implementer szerint 16/16 zöld |

## 4. Biztonsági review (kötelező, `risk = high`) — PASS

A `security-reviewer` a teljes diffen futott. Verdikt: **PASS — 0
BLOCKER/MAJOR**, 3 NOTE. Kulcsmérések:

- **D1** (`feature_flag_source.dart:90-96`): az `emergencyOff` az egyetlen
  emergency-eredetű origin, és fix `false` értékű; `true`/`null`/„nincs kulcs"
  mind átcsordul, kivétel nélkül. Szimmetrikus felülírási utat nem talált.
- **D2** (`:98-125`): bukott aláírásnál a `payload.value` **soha nem olvasódik**;
  a resolver `const`, állapotmentes — nincs cache vagy „utolsó ismert érték".
  A szállított katalógus mind a 40 bejegyzésénél `failClosedDefault: false`.
- **D7**: az egész új rétegen és a toolon `writeAsString|delete|clear(|remove(|
  SecureStorage|Process|Socket|HttpClient|Dio` → **NO SINKS FOUND**.
- **Titok-szemantika:** a katalógus és a `kill-switches.md` csak dart-define
  NEVEKET és `fájl:sor` hivatkozásokat tartalmaz — nincs token, kulcs,
  endpoint vagy belső hostnév.
- **A tool read-only:** RegExp + `readAsStringSync`, nincs `Process.run`, nincs
  fájlírás.

Biztonsági NOTE-jai a lenti F1 (formátum-érzékeny regex), F6 (a resolver ma
unwired) és F7 (stackTrace stderr-re) pontokba épültek be.

## 5. Leletek

| # | Súly | Fájl:sor | Lelet |
|---|---|---|---|
| F1 | **MINOR** | `tool/check_feature_flags.dart:25` | A teljesség-regex (`final bool (\w+);`) csak a csupasz alakot fogja. **MÉRVE (2.4):** `final bool? x;` és `final bool x = true;` alakban felvett új flag CSENDBEN kicsúszik az auditból (exit 0) — pontosan a hibaosztály, amit a kör zárni hivatott. A shippelt fán ma nem reprodukálható (mind a 40 mező csupasz alakú), de a jövőbeli drift ellen az őr nem véd. **Irány:** a minta tágítása a nullable és inicializált alakra + RED-cella egy ilyen fixture-forrásra. |
| F2 | **MINOR** | `docs/release/kill-switches.md:12-14` | „ezt a táblát a katalógusból generáltuk (nem kézzel karbantartott lista)" — **generátor nincs a diffben**, és paritás-őr sem: a 40 soros tábla kézi vetület, ami csendben elavulhat. A brief §4 doc-fegyelme (csak bizonyított állítás) ezt tiltja. **Irány:** vagy a mondat átírása („kézi vetület, az igazság forrása a Dart katalógus"), vagy gépi paritás-cella a meglévő teszt-fájlban. |
| F3 | **MINOR** | `tool/check_feature_flags.dart:88-147` | Az A1 „owner, kockázat, alapérték, kill-switch-út" követelményéből az audit **csak a kulcs-lefedettséget** méri: egy `owner: ''` / `killSwitchPath: ''` bejegyzés zölden átmenne. A szállított katalógus teljes (mérve: 40 owner, 0 üres), tehát ez őr-hiány, nem hiba. **Irány:** üres-string cellák az audit-jelentésben + RED-fixture. |
| F4 | NOTE | `test/core/feature_flags/feature_flag_registry_test.dart:216-247` | Az A6 cella szerkezeti/tautologikus (a resolvernek nincs adattár-referenciája). Őszinte — a `reason` ki is mondja —, és a §4 grep-mérés erősíti, de nem viselkedési bizonyíték. |
| F5 | NOTE | `lib/core/feature_flags/feature_flag_registry.dart` | A szállított katalógusban **egyetlen `expiresOn` sincs** (mind `null`), tehát a lejárat-ág a valós fán ma sosem sül el; A5-öt fixture fedi. Ez az ADR 0446 D6-tal konzisztens (lejárat csak dátumozott rollout-végnél), de a jövőbeli körök feladata dátumot adni a valóban ideiglenes flageknek. |
| F6 | NOTE | — | A `FeatureFlagResolver`/`featureFlagRegistry` ma **UNWIRED**: 0 fogyasztó a `lib/`-ben a saját könyvtárán kívül. Szándékos (ADR 0446 D3, brief §0.1), és a `kill-switches.md:34-39` ki is mondja — a valós feloldásba kötés a Ch12 Kör 30/31 dolga. |
| F7 | NOTE | `tool/check_feature_flags.dart:183-185` | A catch-all a teljes `stackTrace`-t stderr-re írja; a bemenet publikus forrásfa, dev/CI-n fut → nem szivárgás, csak feljegyezve. |
| F8 | NOTE | `docs/rounds/…-kill-switch.md` §10 | A handoff `--effort medium`-ot ír; a `docs/execution/engine-registry.tsv` a `sonnet-impl` sorára `high`-t rögzít. Dokumentációs elcsúszás. |

**Merge-hatás:** BLOCKER/MAJOR nincs. F1–F3 MINOR, a diffet nem hizlalja
érdemben, és a kör saját ígéretét (gépi, nem-elavuló katalógus) szorítja —
ezért **egy javító kör** indul rájuk, nem follow-up.

## 6. CI

- **Full Gate** (`full-gate.yml`, `round-ci-plan.py` szerint ez a helyes ág:
  `apk_required=false`, tisztán Dart/dokumentum-diff): dispatch-elve a
  `d9dfe4f5` head SHA-n — a végső, exact-SHA zöldet a javító kör utáni HEAD-en
  kell megkapni.
- **Router CI** (`router-ci.yml`): a `d9dfe4f5`-ön **piros**
  ([33169042344](https://github.com/wolfcasaba/strumsight/actions/runs/33169042344))
  — a bukás **infrastruktúra-flake, nem a kör diffje**:
  `tools/tests/test_safe_force_push.py::RefusalTest::test_it_refuses_when_the_remote_has_commits_we_lack`
  a `TemporaryDirectory` takarításán hasalt el
  (`OSError: [Errno 39] Directory not empty: '/tmp/tmp2x0xbg97/work/.git'`),
  **804 passed, 1 failed**. A kör diffje egyetlen `tools/**` fájlt sem érint
  (2.1), és ugyanez a workflow a kör pre-flight commitján (`c37904d0`) zölden
  futott. A javító kör új SHA-t ad, azon újra le kell futnia — a merge-kapu az
  ott mért `success`.

## 7. A javító körnek átadott leletlista

F1, F2, F3 — a fenti „Irány" sorokkal. F4–F8 nem blokkol és nem javítandó
ebben a körben.

---

## 8. Javító kör után — újra-ellenőrzés (commit `82a97527`, 2026-08-28)

A javító kör a három MINOR-t zárta; a diff 4 fájl, +229/−8 sor
(`tool/check_feature_flags.dart`, `test/tooling/feature_flag_audit_test.dart`,
`docs/release/kill-switches.md`, a brief §10 kiegészítése). Gépi scope-audit a
jelzésfájlban: `scope_audit=ok`, `scope_audit_base=f5b8e6f5`,
`scope_audit_changed=4`. A `feature_flag_source.dart` resolver — a kör
biztonsági magja — **nem módosult**.

### 8.1 F1 — ZÁRVA, saját próbával mérve

`tool/check_feature_flags.dart:31-44` — a minta
`^\s*final bool\??\s+(\w+)\s*(?:;|=)` `multiLine`-nal: felismeri a csupasz, a
nullable és az inicializált alakot, és sor-elejéhez horgonyzottan kihagyja a
komment- és getter-sorokat. A javítás ELŐTT pirosra vitt volna cellák
bekerültek (`parseFeatureFlagFieldNames` + `auditFeatureFlagRegistry`
fixture-cellák).

**Saját, független reprodukció** (friss `/tmp/review2-e12-r05` klón, ugyanaz a
két mező, amivel a 2.4 szökést mértem):

```
$ # beszúrva: `final bool? probeNullableFlag;` és `final bool probeInitializedFlag = true;`
$ dart run tool/check_feature_flags.dart
Feature flag audit failed:
- [missingCatalogEntry] FeatureFlags field "probeNullableFlag" ... has no catalog entry in featureFlagRegistry.
- [missingCatalogEntry] FeatureFlags field "probeInitializedFlag" ... has no catalog entry in featureFlagRegistry.
AUDIT_EXIT=1                                   # ← korábban 0 volt
$ git checkout -- lib/app/config/feature_flags.dart && dart run tool/check_feature_flags.dart
Feature flag audit OK (0 issue(s)).
AUDIT_EXIT=0
```

**Túllövés-ellenőrzés (saját próba):** `// final bool commentedOutFlag;` és
`/// final bool docCommentFlag;` sorokat szúrva a forrásba az audit **egyetlen**
`missingCatalogEntry`-t sem adott rájuk — a horgonyzás helyes, nincs
komment-beli fals pozitív (`docs/LESSONS.md` L291 hibaosztálya).

### 8.2 F3 — ZÁRVA, saját próbával mérve

Új issue-kód `incompleteCatalogEntry` (`:70-74`, `:167-184`): üres vagy
csak-whitespace `owner`/`killSwitchPath`. Saját próba ugyanabban a klónban:

```
$ # a valós katalógus egyetlen bejegyzésén: owner: '   '
$ dart run tool/check_feature_flags.dart
Feature flag audit failed:
- [incompleteCatalogEntry] catalog entry "accountEnabled" has an empty or whitespace-only owner
  (A1 requires owner, risk, fail-closed default and kill-switch path).
AUDIT_EXIT=1
```

Visszaállítva a working tree tiszta, az audit újra `exit 0`. A valós katalógus
teljességét külön cella is méri („the real registry has no empty owner or
kill-switch path (40/40)").

### 8.3 F2 — ZÁRVA (a bizonyítatlan állítás visszavonva)

`docs/release/kill-switches.md:10-15` már azt írja, ami IGAZ: a tábla a Dart
katalógus **kézi vetülete** (nem generált); a Dart-oldali driftet a
`check_feature_flags.dart` gépileg fogja, „de magát ezt a markdown táblát ma
semmi nem méri — frissen tartása szerkesztői fegyelem kérdése". A választás
indoklása a brief §10.7-ben. Ez a kisebb diffű, őszinte út; a markdown↔katalógus
paritás-őr felvétele legitim follow-up marad.

### 8.4 F4–F8

Változatlanul NOTE, nem javítandó ebben a körben. Az F8 (`--effort medium` a
§10-ben vs `high` az engine-registryben) dokumentációs elcsúszás, nem
viselkedés.

### 8.5 Gate — saját, független futtatás a javító commit után

Friss `/tmp/review2-e12-r05` klónban, a `tools/round-gate.sh` artefaktumon
(format, analyze, a 3 célzott teszt, architecture, secrets, l10n): **minden
lépés ZÖLD**, és `dart run tool/check_feature_flags.dart` → `exit 0`.

## 9. VÉGSŐ DÖNTÉS: APPROVED

0 BLOCKER, 0 MAJOR, 0 nyitott MINOR. A három MINOR-t a javító kör zárta, és
mindhármat **saját, független próbával** ellenőriztem (8.1–8.3). A merge
feltétele a záró, exact-SHA CI-kapu: `full-gate.yml` és `router-ci.yml`
`success` a merge SHA-n.
