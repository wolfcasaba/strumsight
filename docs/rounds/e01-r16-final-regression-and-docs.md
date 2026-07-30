# E01-R16 — Végső regresszió, teljesítmény és dokumentáció

Státusz: PLANNING (pre-flight lefutott 2026-07-30, kód olvasva: `main` @ `3277e08`)
SDD: docs/sdd/02-epic-01-core-platform.md § „Kör 16 — Végső regresszió, teljesítmény és dokumentáció"
Branch: `codex/epic-01-round-16-final-regression`
Brief szerzője: Claude · Implementáció: Codex (szűk kód-scope) + Claude (dokumentáció, verifikáció) + **user (valódi eszközös tesztek)**
**Előfeltétel: R11–R15 mind merge-ölve.** Ez az Epic 1 zárókör — más jellegű, mint
a korábbiak: a Codex-rész kicsi és pontosan határolt, a kör súlya a teljes rendszer
végigmérésén és a záródokumentáción van.

> ✅ **Pre-flight LEFUTOTT (2026-07-30, Claude):** az Epic-1 DoD checklista
> (SDD Ch2 §10) tételes előszűrése megtörtént a friss `main`-en (@ `3277e08`,
> R11–R15 mind merge-ölve) — az eredmény a §2-ben; a Codex-scope az előszűrés
> + a két R14-review-MINOR alapján bővült (§3.2: CI gate-sor dedup + coverage
> külön jobba). Státusz → PLANNING, brief commitolva a kör-branchre.

## 1. Cél

Az Epic 1 lezárása **teljes rendszerellenőrzéssel**: minden gate (Flutter + backend
+ property + architecture + CI) egyszerre zölden, az offline-garancia gépi
bizonyítékával (0 hálózati kérés account+diagnostics nélkül), valódi eszközös
audio-regresszióval és teljesítmény-baseline-nal, végül a dokumentáció (README,
HANDOFF, Epic-záró jelentés) tényleges-kód-szintre hozásával. A kimenet a
`docs/sdd/epic-01-completion-report.md`, benne az SDD Ch2 §10 DoD checklista
tételes, evidenciázott kipipálása — ez nyitja meg az Epic 2-t (Practice Engine).

## 2. Jelenlegi állapot

2026-07-30-i pre-flight olvasás, `main` @ `3277e08` (R11–R15 mind merge-ölve).

**DoD-előszűrés (SDD Ch2 §10) — összegzés.** A hat blokkból négy (Kódszerkezet,
Storage, Backend, CI/release) minden tétele evidenciával fedett a mainen:
architecture guard + legacy-identifier guard + preferences-plugin guard CI-ben
fut (R14 óta a gate-sorban), a storage-modul teljes (migrator + 8 tesztfájl),
a backend R12/R13 tételei ADR 0060/0061-gyel és 64 zöld pytesttel, a CI-gate-ek
ADR 0062/0063-mal bizonyítottak. A maradék rések — ez a kör feladatlistája:

- **Hálózat / offline-garancia rendszer-szinten tesztfedetlen:** létezik
  `test/tooling/dio_factory_guard_test.dart` (egy production Dio-forrás),
  redakciós log-interceptor, 401-invalidáció és flag-gate-ek, de NINCS teszt,
  ami a teljes bootstrapet account-disabled + diagnostics-disabled +
  kijelentkezett állapotban felépíti és **nulla hálózati kérést** állít. → §3.1
- **Hibakezelés — 3 üres catch production kódban** (`chord_audio.dart:150`,
  `metronome.dart:55` — player-dispose; `live_screen.dart:115` — haptika):
  mindhárom best-effort mellékhatás-út, a completion reportban dokumentált,
  indokolt kivételként rögzítendő (nem javítandó ebben a körben).
- **CI-duplikáció (R14-review MINOR-2/3):** a gate-sor (format → analyze →
  architecture → asset → test+coverage → property) szó szerint duplikálva a
  `build-apk.yml` és a `release-apk.yml` közt → drift-kockázat; a coverage-lépés
  a kritikus úton +2 perc. → §3.2
- **HANDOFF.md** ~595 sor kör-történeti napló — a §16.6 szerinti rövid operatív
  szerkezet + külön archívum még nincs.
- **README.md** a backend/Lab/CI szekciókban az R12–R15 után elavult.
- **Teljesítmény-baseline nincs dokumentálva** (cold start, Live-start latency,
  CPU/memória, dropped frames — soha nem lett mérve/rögzítve).
- **A §16.3 készülékes audio-regresszió nem történt meg dokumentáltan** —
  a végső elfogadás a user real-guitar APK-tesztje (HORIZON-szabály).
- **`docs/sdd/epic-01-completion-report.md` nem létezik.**

## 3. Scope

**Codex-rész (kód, szűk):**

- **§3.1** `test/app/offline_network_guard_test.dart` (ÚJ): account-disabled +
  diagnostics-disabled config + kijelentkezett állapot mellett a teljes app-boot
  és a fő képernyők felépítése **nulla** hálózati hívással — a `DioFactory`
  seamjén számláló/fake factory override-dal (a hívás ténye a mérés, nem mock-URL).
  Külön eset: account-ENABLED de kijelentkezett → szintén 0 kérés.
- **§3.2 CI gate-sor dedup (R14-review MINOR-2 + MINOR-3):** a közös gate-sor
  kiemelése egy lokális composite actionbe
  (`.github/actions/flutter-gates/action.yml`), amit a `build-apk.yml` ÉS a
  `release-apk.yml` egyaránt hív — a két workflow gate-sora többé nem driftelhet.
  A coverage a kritikus útról külön, párhuzamos jobba kerül (`flutter test
  --coverage` + LCOV artifact **kötelező, required jobként** — a fő jobban a
  suite `flutter test`-tel, coverage nélkül fut). A gate-ek SORRENDJE és
  szigora (hard gate, nincs continue-on-error) változatlan; a release-apk
  fail-closed secret-ellenőrzése és keystore-kezelése NEM kerül a composite-ba.
- A teljes regresszió által felszínre hozott hibák javítása — **de csak külön,
  tételes engedéllyel**: a Codex minden leletnél MEGÁLL és jelent; a javítás
  scope-ját Claude adja hozzá a §4-hez (a brief frissítésével).

**Claude-rész (verifikáció + dokumentáció):**

- Teljes regressziós futtatás a §16.1 szerint (Flutter: format/analyze/test/
  property/architecture; backend: ruff/pytest/alembic) + minden CI-workflow
  zöldre dispatchelve.
- README frissítése a tényleges állapotra (feature-ök, architektúra, build-envek,
  backend, Lab, tesztelés, offline-privacy, modell-assetek + manifest).
- HANDOFF átszervezése a §16.6 szerkezetre; a kör-történeti napló
  `docs/handoff-archive.md`-be (a történelem megmarad, csak elköltözik).
- `docs/sdd/epic-01-completion-report.md`: elkészült körök, kihagyott feladatok,
  architekturális változások, teszteredmények, teljesítménymérés, ismert
  kockázatok, dependency-allowlist állapota, Epic-2 előfeltételek — és az SDD
  Ch2 §10 DoD checklista tételesen, evidencia-linkekkel.

**User-rész (valódi eszköz — a kör nem zárható le nélküle):**

- A §16.3 audio-regressziós lista végigjátszása a friss APK-val (Live start/stop,
  tab-váltások, háttérbe küldés, képernyőzár, permission-megtagadás majd
  engedélyezés, hosszú session, mic-indikátor kialszik).
- A §16.4 teljesítmény-megfigyelések, amennyire telefonon mérhetők (cold start,
  Live-indulás, melegedés/akku szubjektív jelzése) — a számszerű profilozás
  amennyire eszköz nélkül nem megy, „nem mérhető"-ként dokumentálandó, nem kitalálandó.

**Kívül (ebben a körben TILOS):**

- Új feature, új képernyő, viselkedésváltozás (a jóváhagyott hibajavításokon túl).
- DSP/ML paraméter érintése (AGENTS.md §9).
- Verziószám-emelés / release-döntés (külön user-döntés).
- Epic 2 munka bármilyen előrehozása.

## 4. Engedélyezett fájlok (Codex)

| Útvonal | Miért |
|---|---|
| `test/app/offline_network_guard_test.dart` | ÚJ — a 0-request garancia gépi bizonyítéka (§3.1) |
| `test/support/**` | csak ha az offline-guard teszthez új fake/számláló kell |
| `.github/actions/flutter-gates/action.yml` | ÚJ — közös gate-sor composite action (§3.2) |
| `.github/workflows/build-apk.yml` | §3.2 — composite hívása + coverage külön jobba |
| `.github/workflows/release-apk.yml` | §3.2 — composite hívása (secret-guard/keystore érintetlen) |
| `docs/rounds/e01-r16-final-regression-and-docs.md` | **csak a 10. szekció** |

Minden regressziós lelet-javítás CSAK a brief frissítésével kerülhet ide.

**Tilos zóna (Codexnek):** minden más — kiemelten `README.md`, `HANDOFF.md`,
`docs/**` (a fenti fájl §10-én kívül) — a dokumentációs rész Claude-oldal.

## 5. Kötött architekturális döntések

Ez a kör várhatóan **nem igényel új ADR-t** (nem hoz architekturális döntést —
ha a regresszió mégis kikényszerítene egyet, a szám kiosztása a Claude-oldali
brief-frissítéssel történik).

1. **A 0-request bizonyíték a DioFactory-seamen mér**, nem HTTP-mockon: a
   „nem jött létre kliens / nem indult kérés" a tétel, mert a
   `dio_factory_guard_test.dart` már garantálja, hogy más úton nem születik Dio.
2. **A DoD-checklista minden tétele evidenciát kap** (tesztfájl, CI-futás link,
   mérési jegyzőkönyv vagy user-visszajelzés) — pipa evidencia nélkül nincs.
3. **A HANDOFF-átszervezés tartalommegőrző:** a történeti napló archívumba
   költözik, nem törlődik (a git-history nem helyettesíti a kereshető archívumot).
4. **A szintetikus zöld nem „done":** az Epic-zárás végső elfogadási predikátuma
   a user valódi-gitáros/valódi-eszközös tesztje (HORIZON-szabály, CLAUDE.md).
5. **A CI-refaktor viselkedés-őrző:** a composite action kiemelése után a két
   workflow gate-halmaza, sorrendje és hard-gate jellege bitre azonos szigorú
   marad; a coverage-job required (a workflow nem lehet zöld nélküle). Mindkét
   workflow LÉTEZIK a default branchen, ezért a bizonyíték merge ELŐTT
   megszerezhető `workflow_dispatch --ref <kör-branch>` futással (az R14-tanulság
   — „új workflow bizonyítéka merge utáni" — itt NEM áll fenn).

## 6. Acceptance criteria

- [ ] `offline_network_guard_test.dart` zöld, és bizonyítottan érzékeny:
      egy szándékosan beinjektált kérés (ideiglenes teszt-változat) pirosra
      viszi (a §10-ben dokumentálva, majd visszavonva).
- [ ] A gate-sor EGY helyen él (`.github/actions/flutter-gates`), mindkét
      workflow onnan hívja; a `build-apk.yml` a kör-branchre dispatchelve zöld
      (coverage-job is), a `release-apk.yml` secret nélküli fail-closed
      viselkedése a refaktor után is bizonyított (első lépésen failure,
      0 artifact) — mindkét futás linkelve a §10-ben/completion reportban.
- [ ] A §16.1 teljes parancssora zöld — Flutter-oldal lokálisan (külön
      hívásokként) + a teljes suite/property/APK CI-ben; backend-oldal a
      backend-ci.yml zöld futásával.
- [ ] Minden workflow (build-apk, backend-ci, release-apk fail-closed próba)
      friss zöld/elvárt futással hivatkozva a completion reportban.
- [ ] A user végigjátszotta a §16.3 listát a friss APK-n és az eredmény
      (tételes OK / talált hibák) a completion reportban rögzített.
- [ ] Teljesítmény-baseline dokumentálva (a mérhető metrikák számmal, a nem
      mérhetők expliciten „nem mérhető ezen az eszközön" jelöléssel).
- [ ] README + HANDOFF a tényleges kódot tükrözi; a HANDOFF a §16.6 szerkezetben,
      az archívum linkelve.
- [ ] `docs/sdd/epic-01-completion-report.md` létezik, benne az SDD Ch2 §10
      DoD checklista minden tétele evidenciával kipipálva VAGY tételesen
      dokumentált, indokolt kivételként rögzítve.

## 7. Kötelező ellenőrzések

Külön parancsokként (`AGENTS.md` §12):

```bash
~/flutter/bin/flutter pub get
~/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool
~/flutter/bin/flutter analyze lib/ test/ tool/
~/flutter/bin/flutter test test/app
~/flutter/bin/dart run tool/check_architecture.dart
```

```bash
cd backend
python -m ruff check app tests
python -m ruff format --check app tests
python -m pytest -q
```

Teljes suite + property gate + APK + backend-ci: CI-dispatch (Claude-oldal,
ADR 0052/0053).

## 8. Implementációs sorrend

1. (Claude) Pre-flight DoD-előszűrés → a brief véglegesítése. ✅ 2026-07-30
2. (Codex) `offline_network_guard_test.dart` + érzékenység-próba; majd §3.2
   CI gate-sor dedup + coverage-job.
3. (Claude) Teljes regresszió lokál + CI; leletek → megállás, scope-döntés,
   szükség esetén Codex-javítókör.
4. (Claude) APK a userhez → (User) §16.3 + §16.4 eszközös menet.
5. (Claude) README + HANDOFF-átszervezés + archívum.
6. (Claude) `epic-01-completion-report.md` a DoD-checklistával.
7. Merge az összes gate zöldjével; HANDOFF-ban az Epic 2 következő lépése.

## 9. Kockázatok

- **A kör „minden egyszerre" jellege.** A regresszió bármely lelete könnyen
  scope-robbanást okoz — a szabály: lelet = megállás + tételes scope-döntés,
  nem menet közbeni javítgatás.
- **User-függés.** A §16.3/16.4 eszközös menet nélkül a kör nem zárható —
  időben kell kérni (APK-link a store-credential szabály szerint), és a
  session átnyúlhat több napra; a brief státusza addig IN PROGRESS marad.
- **HANDOFF-átszervezés információvesztése.** Az archívumba költöztetés
  diff-je nagy — a review-ban külön ellenőrzendő, hogy tartalom nem veszett,
  csak mozgott.
- **A „0 request" teszt flakiness-e.** A widget-tesztben minden async forrást
  (timerek, retry-k) determinisztikusan kell kezelni — a meglévő
  `test/support/` fake-minták követendők.

## 10. Implementation handoff — a Codex tölti ki

### Fájlonkénti összefoglaló

- `test/app/offline_network_guard_test.dart` (új): a valódi
  `AppBootstrap.run` + production konfiguráció + in-memory store/migrációk után
  felépíti a `StrumSightApp` gyökeret, majd végigjárja a Live, Analyze, Learn,
  Library, Settings, Tuner, Songs és Progress képernyőt. Két külön esetet fed:
  account+diagnostics disabled és account enabled, de üres token store miatt
  kijelentkezett állapot. Az account `DioFactory` providere valódi factoryt kap
  számláló `HttpClientAdapter`rel; az állítás egyszerre méri a factory/client
  létrehozását és az adapterig jutó requestet. A production diagnostics gate-et
  a valódi `diagnosticsApiClientProvider == null` és a null kliensű uploader
  ellenőrzi. Minden audio/plugin/secure-storage forrás determinisztikus fake.
- `.github/actions/flutter-gates/action.yml` (új): egyetlen composite actionben
  él a dependency-resolve és a kötött hard-gate sorrend: format → analyze →
  architecture → asset → teljes `flutter test` → randomizált property gate.
  Minden `run` lépés explicit `shell: bash`.
- `.github/workflows/build-apk.yml`: a build job a composite actiont hívja; a
  coverage külön, párhuzamos, nem opcionális job (`flutter test --coverage` +
  az eddigi LCOV artifactnév). Az APK metadata/build/stage/upload út változatlan.
- `.github/workflows/release-apk.yml`: a release job ugyanazt a composite
  actiont hívja, a coverage külön párhuzamos job. A rövid
  `signing-prerequisites` job megakadályozza, hogy secret nélküli próbán a
  coverage artifactot töltsön fel: hiányzó secret → első lépés failure, mindkét
  downstream job skipped, 0 artifact. Az eredeti release secret-guard és a
  materialize/build/cleanup keystore-lépések strukturálisan változatlanok és a
  release jobban az eredeti helyükön maradtak.
- `docs/rounds/e01-r16-final-regression-and-docs.md`: kizárólag ez a §10 handoff
  frissült.

### Futtatott parancsok és tényleges eredmény

- `~/flutter/bin/flutter pub get` → exit 0, `Got dependencies!`; 32 újabb,
  constrainttel inkompatibilis verzió csak informatív jelzés.
- Baseline: `~/flutter/bin/flutter test test/app` → `+39: All tests passed!`.
- Új guard GREEN:
  `~/flutter/bin/flutter test test/app/offline_network_guard_test.dart` →
  `+2: All tests passed!`.
- `~/flutter/bin/dart format --set-exit-if-changed lib test tool` →
  `Formatted 450 files (0 changed)`.
- `~/flutter/bin/flutter analyze lib/ test/ tool/` →
  `No issues found! (ran in 2.5s)`.
- Végső célzott suite: `~/flutter/bin/flutter test test/app` →
  `+41: All tests passed!` (a 39 baseline + 2 új guard).
- `~/flutter/bin/dart run tool/check_architecture.dart` →
  `Architecture dependencies OK (12 allowlisted deviation(s)).`
- Python 3 + PyYAML szintaxis-audit a composite és a két workflow fájlra →
  `YAML syntax OK: ...flutter-gates/action.yml, ...build-apk.yml,
  ...release-apk.yml`.
- Strukturális workflow-audit (gate-nevek/sorrend, minden composite shell,
  property seed, mindkét composite-hívás, coverage hard job, release `needs`,
  védett release-lépések összevetése a `HEAD`-del) →
  `Workflow semantics OK: shared ordered hard gates, parallel required
  coverage, protected release steps unchanged.`
- A signing-preflight lokális érzékenység-próbája üres env-vel exit 1 és csak a
  négy hiányzó secret nevét adta; nem üres tesztértékekkel exit 0 →
  `Release preflight sensitivity OK: missing secrets -> exit 1 with names
  only; non-empty test values -> exit 0.`
- `git diff --check` → exit 0, kimenet nélkül.

### Offline-guard érzékenység-próba

Az account-enabled/kijelentkezett esetbe ideiglenesen, a production
`accountApiClientProvider → DioFactory → ApiClient → HttpClientAdapter` útvonalon
egy public POST került. A futtatás:

```text
~/flutter/bin/flutter test test/app/offline_network_guard_test.dart \
  --plain-name 'account enabled but signed out: full boot and main screens stay offline' \
  --reporter expanded

Expected: [0, 0]
  Actual: [1, 1]
Which: at location [0] is <1> instead of <0>
00:02 +0 -1: Some tests failed.
```

A két szám sorrendben a factory/client létrehozás és az adapter-request. Az
ideiglenes request és a diagnosztikai logok vissza lettek vonva; ugyanaz a
végleges teszt ezután `+2: All tests passed!`.

Az első próba a Dio future/stream láncát közvetlenül awaitelte a widget-teszt
fake-async zónájában, ezért nem jutott el az assertig és kézzel meg lett
szakítva (`did not complete`); ez nem elfogadási evidencia. A Dio 5.10
csomagforrásának visszakövetése után az ideiglenes request kizárólag a RED
próbában `tester.runAsync` alatt futott, így determinisztikusan az adapterig
jutott és a fenti várt piros eredményt adta. A végleges fájlban sem request,
sem `runAsync`, sem debug log nem maradt.

### Eltérések, nem futtatott ellenőrzések és kockázatok

- Production kód nem változott. A `DioFactory` `final`, a diagnostics provider
  pedig közvetlenül hozza létre; a whitelist nem engedett új production seamet.
  Ezért az account-oldal a meglévő factory-provider override-on mér, a
  diagnostics-oldal pedig a valódi disabled early-returnt (`null`) bizonyítja.
  A repository tooling-guardja külön őrzi, hogy production Dio más úton nem
  jöhet létre.
- `actionlint`/`yamllint` nincs telepítve a boxon; a lokális YAML +
  strukturális audit zöld, a GitHub Actions futás marad az autoritatív
  workflow-validáció.
- A teljes Flutter suite, coverage, randomizált property gate és APK-build
  lokálisan szándékosan nem futott (ADR 0052/0053/0064 + aktuális user-utasítás);
  ezeket Claude dispatch-eli a kör-branchre. GitHub run-link ezért még nincs.
- A `release-apk.yml` secret nélküli 0-artifact bizonyítéka szintén Claude
  workflow-dispatche; lokálisan csak a preflight script két ágát mértük.
- Backend gate-ek nem futottak: backend diff nincs, a teljes §16.1 regresszió és
  a backend CI Claude-rész. Valódi készülék/audio/teljesítmény mérés a user-rész.

### Follow-upok

- Claude a CI-evidenciában külön ellenőrizze a `Coverage` job sikerét mindkét
  workflow-ban, és a release secret nélküli futásnál a 0 artifactot.
- A prompt/HANDOFF által hivatkozott ADR 0064 fájl nincs a jelenlegi branch
  történetében; a dokumentum csak a `chore/codex-code-complete-signal` branchen,
  `1959bc6` alatt található. A Claude-oldali záródokumentáció rendezze ezt az
  eltérést; Codex a §4 whitelist miatt nem nyúlt hozzá.
- Repo-kód follow-up lelet nincs.

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e01-r16-review.md`
