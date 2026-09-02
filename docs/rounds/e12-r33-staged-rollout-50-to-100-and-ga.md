# E12-R33 — Staged rollout 50–100 százalék és GA

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 33
- **Kör-azonosító:** `E12-R33`
- **Branch:** `<motor>/e12-r33-staged-rollout-50-to-100-and-ga`
- **Előfeltétel:** `E12-R32` merge-elve ÉS a 20%-os lépcső USER általi lezárása
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör GA-rekordot és záró ellenőrzést szállít.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "general availability rollout 100 percent release notes support"` → **[ADR 0065](../adr/0065-practice-engine-v2-parallel-rollout.md)** és **[ADR 0197](../adr/0197-song-trainer-shipping-rollout-boundary.md)** — a repó MÉRT rollout-mintái (párhuzamos futás, availability flag, belépési pont). A GA-rekordnak ezért a FLAG-PROFILT is rögzítenie kell, nem csak a verziót.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd, hogy a `staged-rollout-log.md` 1/5/20%-os lépcsői KITÖLTVE és jóváhagyva vannak-e. Üres napló mellett a kör nem indítható (`blocked`).
>
> **ELVÉGEZVE, MÉRVE, FELOLDVA → lásd [§0.0.1 P1](#001-pre-flight-revízió--orchestrátor-2026-09-02-adr-0087-2-a-kör-saját-még-nem-merge-elt-briefje).** A napló sémája megvan, a lépcsők NINCSENEK kitöltve (mind `pending`/`TBD`), és nem is lehetnek, amíg egy P0 + öt P1 blocker nyitva van. A kapu ezért séma-létezés ellenőrzés, a kitöltetlenség pedig **gépi invariáns** lett (§5.4 / A7) — a kör indítható, és továbbra sem tesz közzé semmit.

## 0.0 EMBERI KAPU

A 50% és 100% lépcső, valamint a store-oldali GA **user-művelet**. Az implementer terméke: a GA-rekord sablonja és ellenőrzője (build, flag-profil, modell-verzió, időbélyeg, támogatási linkek), a végleges release-notes generálása, és a záró konzisztencia-ellenőrzés. A kör NEM tesz közzé semmit.

### 0.0.1 Pre-flight revízió — orchestrátor, 2026-09-02 (ADR 0087 §2: a kör SAJÁT, még nem merge-elt briefje)

**P1 — a ⚠ pre-flight kapu MÉRT feloldása (nem kihagyása).** A
`staged-rollout-log.md` LÉTEZIK és teljes sémájú (Kör 32, `f6db8a8d`): 3
döntés-sor + 15 megfigyelés-sor. Kitöltve azonban NINCS — minden `decision`
`pending`, minden `verdict` `unknown`, minden szöveges cella `TBD` (mérve:
`docs/release/staged-rollout-log.md`). Szó szerint olvasva a „Üres napló
mellett a kör nem indítható" mondat a láncot **véglegesen** megállítaná, mert
a napló csak egy VALÓDI store-rollouttal tölthető ki, az pedig ma maga is
blokkolt: `docs/release/blockers.md` szerint nyitva van **egy P0**
(`R-SIGN-01`) és **öt P1** (`R-VER-01`, `R-PRIV-01`, `R-SEC-01`,
`R-STAGE-01`, `R-STORE-01`), és a `ga-scope.md` fejléce ezért mondja ki:
**„NEM KÉSZ (NOT READY)"**. A brief §2 ezt az állapotot MÁR MÉRTE és a kört
kifejezetten rá tervezte („Store-jelenlét MA nincs … a GA-rekord ezért a
publikálás UTÁN kitöltendő mezőket EXPLICIT emberi jelöléssel viszi").

**Feloldás:** a kapu **séma-létezés** ellenőrzés (teljesül), a kitöltetlen
állapotot pedig nem elkenjük, hanem **gépi invariánssá** tesszük (P2/§5.4/A7).
Precedens: az E12-R32 ugyanígy szállított sémát + ellenőrzőt + üres naplót
tényleges rollout nélkül. A kör terméke sablon, ellenőrző, teszt és jegyzet —
egyik sem függ a napló kitöltöttségétől, és a kör **továbbra sem tesz közzé
semmit**.

**P2 — ÚJ kötött szabály (§5.4): a rekord nem állíthat meg nem történt GA-t.**
A GA-rekord gépi `ga_status` mezőt hordoz, zárt értékkészlettel
(`not-yet` | `in-progress` | `ga`). A `verify_ga_record.py` **nem-nulla
kilépéssel** áll meg, ha `ga_status: ga`, miközben (a) a
`staged-rollout-log.md` bármely `stage-*` döntése nem `approved`, VAGY (b) a
`blockers.md`-ben nyitott P0/P1 van. **NEM elfogadható gyengítés:** a rekord
csak PRÓZÁBAN mondja, hogy „még nincs GA", gépi mező nélkül. → **A7** cella.

**P3 — az A2 MÉRT útvonala (a §1 „táblát mértem, nem az utat" hibaosztály
ellen).** Statikus release-manifest fájl a fán **NINCS**. A manifest generált
Dart-artefaktum: `tool/generate_release_manifest.dart --output <path>` (mérve:
`tool/generate_release_manifest.dart:24-77`), amelynek verzió-bemenete a
`pubspec.yaml:5` (`1.0.0+1`), továbbá az `assets/ml/model_manifest.json` és az
`assets/tutor_knowledge/manifest.json`. Ezért:

- az A2 összevetés **Dartban** fut, a `ga_record_test.dart`-ban, a
  `../../tool/generate_release_manifest.dart` importálásával — ez a
  `test/tooling/release_manifest_test.dart:24` MÉRT mintája
  (`_buildRealManifest()`);
- a `verify_ga_record.py` UGYANEZEKET a mezőket a manifest **deklarált
  BEMENETEI** ellen ellenőrzi (`pubspec.yaml` verzió/build, a két
  asset-manifest sha256-ja). **Tilos** nem létező statikus manifest fájlt
  olvasnia, és **tilos** `dart run`-t hívnia.

**NEM elfogadható gyengítés:** kézzel a Pythonba másolt `1.0.0+1` literál.

**P4 — a flag-profil MÉRT forrása (A3).** A `docs/release/ga-scope.md` zárt
marker-blokkja: `<!-- ga-scope-capabilities:begin/end -->`, **16** flag-kulcs
`classification` + `production_default` oszlopokkal (mérve: `ga-scope.md:58-77`).
A pillanatképnek mind a 16 kulcsot hordoznia kell; az ellenőrző hibát jelez
hiányzó vagy többlet kulcsra ehhez a blokkhoz képest. **NEM elfogadható
gyengítés:** prózai „minden flag ki van kapcsolva" mondat.

**P5 — a rollback-cél MÉRT forrása (A4/§5.3).** Repó-relatív, a fán MA
feloldható útvonal (pl. `docs/release/client-migration.md`,
`docs/operations/disaster-recovery-drill.md`). Az ellenőrző elutasítja az
üres, `TBD`/`<…>` alakú vagy nem feloldható rollback-célt.

**P6 — ADR: nincs, és nem is lesz.** A §3/§4 tilos zónája a `docs/adr/**`, az
engedélyezett-fájllista pedig kizárólag **szűkíthető** (ADR 0087 §2) — az új
§5.4 ezért ugyanúgy briefbeli kötött szabály, mint a meglévő három.

**P7 — az engedélyezett-fájllista VÁLTOZATLAN.** A
`test/tooling/rollout_decision_test.dart` csak `gate_tests` bejegyzés, nem
módosítandó fájl.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/release/ga-record.md",
  "docs/release/release-notes.md",
  "tool/release/verify_ga_record.py",
  "test/tooling/ga_record_test.dart",
  "docs/rounds/e12-r33-staged-rollout-50-to-100-and-ga.md",
]
gate_tests = [
  "test/tooling/ga_record_test.dart",
  "test/tooling/rollout_decision_test.dart",
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

**STOP-protokoll:** ha a GA-rekord egy mezőjéhez nincs bizonyíték (pl. hiányzó modell-verzió a manifestben), a kimenet a `stopped` jelzés — kitöltetlen mező nem maradhat, és kitalált érték sem kerülhet bele.

## 1. Cél

A teljes elérhetőség elérése auditálhatóan: a GA-állapot minden lényeges paramétere rögzített, a support- és rollback-készenlét pedig fennmarad.

## 2. Jelenlegi állapot — mért tények

- `docs/release/staged-rollout-log.md` és `rollout-decision.md` a Kör 32 termékei.
- A release-manifest (Kör 6) hordozza a build-, modell- és tudáscsomag-verziót; a flag-profil a Kör 5 katalógus + a Kör 28 GA-scope.
- `docs/release/ga-record.md` és `release-notes.md` **nincs**.
- Store-jelenlét MA nincs (Kör 1) — a GA-rekord ezért a publikálás UTÁN kitöltendő mezőket EXPLICIT emberi jelöléssel viszi.

## 3. Scope

**Benne van:** `docs/release/ga-record.md` (GA időbélyeg, build-azonosító + SHA, flag-profil pillanatkép, modell- és tartalom-verzió, ismert hibák hivatkozása, rollback-cél, támogatási linkek) · `tool/release/verify_ga_record.py` (kitöltetlen kötelező mező, manifesttel nem egyező verzió, hiányzó rollback-cél → nem-nulla kilépés) · `test/tooling/ga_record_test.dart` · `docs/release/release-notes.md` (a Kör 6 manifestjéből és a `known-issues.md`-ből generált, determinisztikus jegyzet).

**NINCS benne (tilos):**

- Store-művelet, publikálás vagy rollout-százalék állítása.
- `lib/**`, `backend/**`, `.github/**` módosítás.
- A `staged-rollout-log.md` átírása.
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/release/ga-record.md` | ÚJ — a GA-rekord |
| `docs/release/release-notes.md` | ÚJ — végleges jegyzet |
| `tool/release/verify_ga_record.py` | ÚJ — a rekord ellenőrzője |
| `test/tooling/ga_record_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/**` · `backend/**` · `.github/**` · `docs/release/staged-rollout-log.md` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések

Nincs ADR. Három kötelező szabály:

### 5.1 A GA-rekord a FLAG-PROFILT is rögzíti

A repó mért tapasztalata (ADR 0065/0197): a rollout nem csak verzió, hanem elérhetőségi kapcsolók és belépési pontok kérdése. **NEM elfogadható gyengítés:** csak a verziószám rögzítése.

### 5.2 A verzió-mezők a MANIFESTBŐL származnak

**NEM elfogadható gyengítés:** kézzel írt verzió, ami a manifesttől eltérhet.

### 5.3 A rollback-készenlét a GA UTÁN is fennáll

A rekord megnevezi az érvényes rollback-célt és annak elérhetőségét. **NEM elfogadható gyengítés:** „GA után nincs visszaút" megfogalmazás.

### 5.4 A rekord nem állíthat meg nem történt GA-t (§0.0.1 P2)

Gépi `ga_status` mező, zárt értékkészlettel (`not-yet` | `in-progress` | `ga`).
A `verify_ga_record.py` nem-nulla kilépéssel áll meg, ha `ga_status: ga`,
miközben a `staged-rollout-log.md` bármely `stage-*` döntése nem `approved`,
VAGY a `blockers.md`-ben nyitott P0/P1 van. MA mindkét feltétel fennáll, tehát
a szállított rekord `ga_status`-a **`not-yet`**. **NEM elfogadható gyengítés:**
a tilalom csak prózában, gépi mező és ellenőrzés nélkül.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Kitöltetlen kötelező mező → `verify_ga_record.py` nem-nulla kilépés | `ga_record_test.dart` |
| A2 | A rekord verzió-mezői egyeznek a release-manifesttel | `ga_record_test.dart` |
| A3 | A rekord tartalmazza a flag-profil pillanatképét | `ga_record_test.dart` |
| A4 | A rekord megnevezi az érvényes rollback-célt | `ga_record_test.dart` |
| A5 | A release-notes determinisztikus és a `known-issues.md`-re hivatkozik | `ga_record_test.dart` |
| A6 | A dokumentum kimondja, hogy a publikálás EMBERI művelet | a dokumentum |
| A7 | `ga_status: ga` nyitott P0/P1 vagy nem-`approved` `stage-*` döntés mellett → `verify_ga_record.py` nem-nulla kilépés; a szállított rekord `ga_status`-a `not-yet` (§5.4) | `ga_record_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A verziót kézzel írjuk be, manifest-ellenőrzés nélkül | A2 |
| A flag-profil kimarad a rekordból | A3 |
| A rollback-cél mező üresen marad | A4 |
| A release-notes generálási időbélyeget tartalmaz | A5 |
| A rekord `ga_status: ga`-t állít, miközben nyitott P0/P1 van (§5.4) | A7 |
| A `ga_status` mező kimarad, a „még nincs GA" csak prózában szerepel | A7 |

**Valódi-sértés próba 1 (KÖTELEZŐ, a §10-ben dokumentálva):** írj a GA-rekordba a manifestétől ELTÉRŐ build-számot, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

**Valódi-sértés próba 2 (KÖTELEZŐ, §0.0.1 P2, a §10-ben dokumentálva):** állítsd a rekord `ga_status` mezőjét `ga`-ra (miközben a `blockers.md`-ben nyitott P0/P1 van), futtasd a `python3 tool/release/verify_ga_record.py --record docs/release/ga-record.md` parancsot → **nem-nulla** kilépés kell (A7) → állítsd vissza `not-yet`-re.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/ga_record_test.dart test/tooling/rollout_decision_test.dart
```

Az ellenőrző közvetlen futtatása (kimenet a §10-be):

```bash
python3 tool/release/verify_ga_record.py --record docs/release/ga-record.md
```

## 8. Implementációs sorrend

1. `docs/release/ga-record.md` sablon (emberi mezők jelölésével, `ga_status: not-yet`, flag-profil pillanatkép a §0.0.1 P4 szerinti 16 kulccsal).
2. `tool/release/verify_ga_record.py` (a §0.0.1 P3 szerint a manifest BEMENETEI ellen mér — nincs statikus manifest fájl, nincs `dart run`).
3. `test/tooling/ga_record_test.dart` (az A2 Dart-oldali manifest-összevetése a `release_manifest_test.dart:24` mintájára).
4. `docs/release/release-notes.md` generálás.
5. MINDKÉT valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Auditálhatatlan GA.** Flag-profil nélkül később nem rekonstruálható, mit kaptak a felhasználók (A3).
- **Verzió-eltérés.** Kézi mező és manifest szétcsúszása (A2).
- **Rollback-készenlét elvesztése.** A GA nem szünteti meg a visszaút kötelezettségét (§5.3).

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** Claude Sonnet 5 (`sonnet-impl`), 2026-09-02.

### 10.1 Szállított fájlok

| Útvonal | Mit |
|---|---|
| `docs/release/ga-record.md` | ÚJ — GA-rekord: `ga_status: not-yet` gépi mező (§1), verzió-mezők a manifest deklarált bemeneteiből (§2), 16 kulcsos flag-profil pillanatkép a `ga-scope.md`-ből (§3), `known-issues.md` hivatkozás (§4), rollback-cél a `disaster-recovery-drill.md`-re (§5), GA UTÁN emberi mezők (build-SHA §2 vége, support-link §6, publikálási időbélyeg §7) explicit `GA UTÁN, EMBERI KITÖLTÉS` jelöléssel, a közzététel emberi jellegét kimondó mondat (§8, A6). |
| `tool/release/verify_ga_record.py` | ÚJ — fail-closed ellenőrző: A1 (kitöltetlen/placeholder kötelező mező), A2 (verzió-mezők a `pubspec.yaml` + a két asset-manifest sha256/séma/elemszám ellen, nincs statikus manifest, nincs `dart run`), A3 (a flag-profil pillanatkép a `ga-scope.md` 16 kulcsával élőben összevetve), A4 (rollback-cél feloldhatósága), A6 (emberi-közzététel mondat), A7 (`ga_status: ga` tiltása nyitott P0/P1 vagy nem-`approved` `stage-*` döntés mellett, a `staged-rollout-log.md`/`blockers.md` friss beolvasásával). |
| `test/tooling/ga_record_test.dart` | ÚJ — gate-teszt: A2 Dart-oldali összevetés a `tool/generate_release_manifest.dart` importjával (`release_manifest_test.dart:24` `_buildRealManifest()` mintája), a többi cella `python3` shell-out a valós fára és temp fixture-ökre (rollout_decision_test.dart mintája), A5 (release-notes determinizmus + `known-issues.md` hivatkozás), A9 (fail-closed marker-blokk/tábla-parszer). |
| `docs/release/release-notes.md` | ÚJ — determinisztikus záró jegyzet a manifest-bemenetekből és a `known-issues.md`-ből, generálási időbélyeg nélkül. |
| `docs/rounds/e12-r33-staged-rollout-50-to-100-and-ga.md` | ez a §10 kitöltése. |

Tilos zóna érintetlen: `lib/**`, `backend/**`, `.github/**`,
`docs/release/staged-rollout-log.md`, `docs/adr/**`, `tools/**` — egyik sem
módosult.

### 10.2 §7 — `tools/round-gate.sh test/tooling/ga_record_test.dart test/tooling/rollout_decision_test.dart` (csonkítatlan)

```
═══ [1] format
    $ /home/ubuntu/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool

Formatted 2217 files (0 changed) in 10.16 seconds.

    → [1] format: ZÖLD

═══ [2] analyze
    $ /home/ubuntu/flutter/bin/flutter analyze lib/ test/ tool/

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (106.0.0 available)
  analyzer 12.1.0 (14.2.0 available)
  archive 4.0.9 (4.2.0 available)
  audio_streamer 4.3.0 (5.0.0 available)
  camera 0.11.4 (0.12.0+2 available)
  camera_android_camerax 0.6.30 (0.7.4+7 available)
  camera_avfoundation 0.9.23+2 (0.10.3 available)
  camera_web 0.3.5+4 (0.3.5+5 available)
  clock 1.1.2 (1.1.3 available)
  code_assets 1.2.1 (2.0.0 available)
  cross_file 0.3.5+4 (0.3.5+5 available)
  dbus 0.7.14 (0.7.15 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  file_selector_android 0.5.2+9 (0.5.2+10 available)
  file_selector_ios 0.5.3+5 (0.5.3+6 available)
  file_selector_linux 0.9.4 (0.9.4+1 available)
  file_selector_macos 0.9.5 (0.9.5+1 available)
  file_selector_windows 0.9.3+5 (0.9.3+6 available)
  flutter_local_notifications 22.0.1 (22.3.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.2.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage 10.3.1 (11.0.0 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_linux 3.0.1 (3.0.2 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.3 available)
  glob 2.1.3 (2.2.0 available)
  go_router 17.3.0 (18.0.0 available)
  hooks 2.0.2 (2.2.0 available)
  intl 0.20.2 (0.20.3 available)
  io 1.0.5 (1.1.0 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.3 available)
  matcher 0.12.19 (0.12.20 available)
  material_color_utilities 0.13.0 (0.13.1 available)
  meta 1.18.0 (1.19.0 available)
  mime 2.0.0 (2.1.0 available)
  objective_c 9.4.1 (9.6.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.1 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.6.1 available)
  permission_handler_html 0.1.3+5 (0.1.4+1 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  pool 1.5.2 (1.5.3 available)
  pub_semver 2.2.0 (2.2.1 available)
  record_use 0.6.0 (1.1.1 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.28 available)
  shared_preferences_foundation 2.5.6 (2.5.7 available)
  source_maps 0.10.13 (0.10.14 available)
  stack_trace 1.12.1 (1.12.2 available)
  stream_transform 2.1.1 (2.1.2 available)
  synchronized 3.4.1 (3.4.1+2 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  url_launcher_linux 3.2.2 (3.2.3 available)
  url_launcher_windows 3.1.5 (3.1.6 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  vm_service 15.2.0 (15.3.0 available)
  wakelock_plus 1.6.1 (1.8.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.7.0 available)
  win32 6.3.0 (6.4.0 available)
  xml 6.6.1 (7.0.1 available)
  yaml 3.1.3 (3.1.4 available)
Got dependencies!
71 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing 3 items...                                            
No issues found! (ran in 6.1s)

    → [2] analyze: ZÖLD

═══ [3] test test/tooling/ga_record_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/tooling/ga_record_test.dart

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (106.0.0 available)
  analyzer 12.1.0 (14.2.0 available)
  archive 4.0.9 (4.2.0 available)
  audio_streamer 4.3.0 (5.0.0 available)
  camera 0.11.4 (0.12.0+2 available)
  camera_android_camerax 0.6.30 (0.7.4+7 available)
  camera_avfoundation 0.9.23+2 (0.10.3 available)
  camera_web 0.3.5+4 (0.3.5+5 available)
  clock 1.1.2 (1.1.3 available)
  code_assets 1.2.1 (2.0.0 available)
  cross_file 0.3.5+4 (0.3.5+5 available)
  dbus 0.7.14 (0.7.15 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  file_selector_android 0.5.2+9 (0.5.2+10 available)
  file_selector_ios 0.5.3+5 (0.5.3+6 available)
  file_selector_linux 0.9.4 (0.9.4+1 available)
  file_selector_macos 0.9.5 (0.9.5+1 available)
  file_selector_windows 0.9.3+5 (0.9.3+6 available)
  flutter_local_notifications 22.0.1 (22.3.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.2.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage 10.3.1 (11.0.0 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_linux 3.0.1 (3.0.2 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.3 available)
  glob 2.1.3 (2.2.0 available)
  go_router 17.3.0 (18.0.0 available)
  hooks 2.0.2 (2.2.0 available)
  intl 0.20.2 (0.20.3 available)
  io 1.0.5 (1.1.0 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.3 available)
  matcher 0.12.19 (0.12.20 available)
  material_color_utilities 0.13.0 (0.13.1 available)
  meta 1.18.0 (1.19.0 available)
  mime 2.0.0 (2.1.0 available)
  objective_c 9.4.1 (9.6.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.1 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.6.1 available)
  permission_handler_html 0.1.3+5 (0.1.4+1 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  pool 1.5.2 (1.5.3 available)
  pub_semver 2.2.0 (2.2.1 available)
  record_use 0.6.0 (1.1.1 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.28 available)
  shared_preferences_foundation 2.5.6 (2.5.7 available)
  source_maps 0.10.13 (0.10.14 available)
  stack_trace 1.12.1 (1.12.2 available)
  stream_transform 2.1.1 (2.1.2 available)
  synchronized 3.4.1 (3.4.1+2 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  url_launcher_linux 3.2.2 (3.2.3 available)
  url_launcher_windows 3.1.5 (3.1.6 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  vm_service 15.2.0 (15.3.0 available)
  wakelock_plus 1.6.1 (1.8.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.7.0 available)
  win32 6.3.0 (6.4.0 available)
  xml 6.6.1 (7.0.1 available)
  yaml 3.1.3 (3.1.4 available)
Got dependencies!
71 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-sonnet-impl-e12-r33/test/tooling/ga_record_test.dart
00:00 +0: self-check — python3 is on PATH a missing python3 would turn every cell below red, not skip it
00:00 +1: sanity — the shipped ga-record.md validates against the real tree bare call (no flags) on the shipped tree is exit 0
00:00 +2: A1 — a required field with a placeholder/unknown value is a non-zero exit an empty version-field cell is a non-zero exit
00:00 +3: A1 — a required field with a placeholder/unknown value is a non-zero exit an unknown ga_status value is a non-zero exit
00:00 +4: A2 — recorded version fields must match the release-manifest inputs (round brief §0.0.1 P3) — never a hand-typed literal a build number that disagrees with pubspec.yaml is a non-zero exit (round brief §6.1 valódi-sértés próba 1)
00:00 +5: A2 — recorded version fields must match the release-manifest inputs (round brief §0.0.1 P3) — never a hand-typed literal an ML manifest sha256 that disagrees with the real file is a non-zero exit
00:00 +6: A2 — recorded version fields must match the release-manifest inputs (round brief §0.0.1 P3) — never a hand-typed literal the real committed version table matches the real release-manifest inputs, measured in Dart via generate_release_manifest.dart (round brief §0.0.1 P3, the release_manifest_test.dart:24 pattern)
00:00 +7: A3 — the flag-profile snapshot must match ga-scope.md key-for-key (round brief §0.0.1 P4) removing a flag row (16 -> 15) is a non-zero exit
00:00 +8: A3 — the flag-profile snapshot must match ga-scope.md key-for-key (round brief §0.0.1 P4) a classification that disagrees with ga-scope.md is a non-zero exit
00:00 +9: A3 — the flag-profile snapshot must match ga-scope.md key-for-key (round brief §0.0.1 P4) the real committed snapshot carries exactly the 16 keys the real ga-scope.md classifies (16, brief §0.0.1 P4)
00:00 +10: A4 — rollback_target must resolve on this tree (round brief §5.3) a TBD rollback_target is a non-zero exit
00:00 +11: A4 — rollback_target must resolve on this tree (round brief §5.3) a non-existent rollback_target path is a non-zero exit
00:00 +12: A4 — rollback_target must resolve on this tree (round brief §5.3) the real committed rollback_target resolves on this tree (sanity)
00:00 +13: A6 — the record states the GA publish is a human operation the shipped record carries the literal sentence (sanity)
00:00 +14: A6 — the record states the GA publish is a human operation a record missing the literal sentence is a non-zero exit
00:00 +15: A7 — ga_status: ga is blocked by open P0/P1 or a non-approved stage-* decision (round brief §0.0.1 P2 / §5.4, §6.1 valódi-sértés próba 2) flipping the shipped ga_status to ga is a non-zero exit against the REAL staged-rollout-log.md/blockers.md, which today are pending/open
00:00 +16: A7 — ga_status: ga is blocked by open P0/P1 or a non-approved stage-* decision (round brief §0.0.1 P2 / §5.4, §6.1 valódi-sértés próba 2) ga_status: ga is accepted when every stage-* decision is approved and no P0/P1 blocker is open (isolates the rule from the shipped tree's pending state — proves it is not vacuously always red)
00:00 +17: A9 — the marker-block/table parsers are fail-closed a missing ga-status marker block is exit 2
00:00 +18: A9 — the marker-block/table parsers are fail-closed a malformed version-table row (missing a column) is exit 2
00:00 +19: usage errors (exit 2) — missing files a missing --record path is exit 2
00:00 +20: usage errors (exit 2) — missing files a missing --ga-scope path is exit 2
00:00 +21: A5 — release-notes.md is deterministic and references known-issues.md release-notes.md contains no ISO-8601-shaped timestamp anywhere
00:01 +22: A5 — release-notes.md is deterministic and references known-issues.md self-check: the ISO-8601 regex used above actually detects a timestamp (guards against a vacuous checker)
00:01 +23: A5 — release-notes.md is deterministic and references known-issues.md release-notes.md references known-issues.md
00:01 +24: A5 — release-notes.md is deterministic and references known-issues.md release-notes.md names the same app version/build the release manifest inputs measure (1.0.0+1)
00:01 +25: A5 — release-notes.md is deterministic and references known-issues.md known-issues.md (the doc release-notes.md points at) exists on this tree
00:01 +26: All tests passed!

    → [3] test test/tooling/ga_record_test.dart: ZÖLD

═══ [4] test test/tooling/rollout_decision_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/tooling/rollout_decision_test.dart

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (106.0.0 available)
  analyzer 12.1.0 (14.2.0 available)
  archive 4.0.9 (4.2.0 available)
  audio_streamer 4.3.0 (5.0.0 available)
  camera 0.11.4 (0.12.0+2 available)
  camera_android_camerax 0.6.30 (0.7.4+7 available)
  camera_avfoundation 0.9.23+2 (0.10.3 available)
  camera_web 0.3.5+4 (0.3.5+5 available)
  clock 1.1.2 (1.1.3 available)
  code_assets 1.2.1 (2.0.0 available)
  cross_file 0.3.5+4 (0.3.5+5 available)
  dbus 0.7.14 (0.7.15 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  file_selector_android 0.5.2+9 (0.5.2+10 available)
  file_selector_ios 0.5.3+5 (0.5.3+6 available)
  file_selector_linux 0.9.4 (0.9.4+1 available)
  file_selector_macos 0.9.5 (0.9.5+1 available)
  file_selector_windows 0.9.3+5 (0.9.3+6 available)
  flutter_local_notifications 22.0.1 (22.3.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.2.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage 10.3.1 (11.0.0 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_linux 3.0.1 (3.0.2 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.3 available)
  glob 2.1.3 (2.2.0 available)
  go_router 17.3.0 (18.0.0 available)
  hooks 2.0.2 (2.2.0 available)
  intl 0.20.2 (0.20.3 available)
  io 1.0.5 (1.1.0 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.3 available)
  matcher 0.12.19 (0.12.20 available)
  material_color_utilities 0.13.0 (0.13.1 available)
  meta 1.18.0 (1.19.0 available)
  mime 2.0.0 (2.1.0 available)
  objective_c 9.4.1 (9.6.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.1 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.6.1 available)
  permission_handler_html 0.1.3+5 (0.1.4+1 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  pool 1.5.2 (1.5.3 available)
  pub_semver 2.2.0 (2.2.1 available)
  record_use 0.6.0 (1.1.1 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.28 available)
  shared_preferences_foundation 2.5.6 (2.5.7 available)
  source_maps 0.10.13 (0.10.14 available)
  stack_trace 1.12.1 (1.12.2 available)
  stream_transform 2.1.1 (2.1.2 available)
  synchronized 3.4.1 (3.4.1+2 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  url_launcher_linux 3.2.2 (3.2.3 available)
  url_launcher_windows 3.1.5 (3.1.6 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  vm_service 15.2.0 (15.3.0 available)
  wakelock_plus 1.6.1 (1.8.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.7.0 available)
  win32 6.3.0 (6.4.0 available)
  xml 6.6.1 (7.0.1 available)
  yaml 3.1.3 (3.1.4 available)
Got dependencies!
71 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-sonnet-impl-e12-r33/test/tooling/rollout_decision_test.dart
00:00 +0: self-check — python3 is on PATH a missing python3 would turn every cell below red, not skip it
00:00 +1: sanity — the shipped documents validate against the real tree bare call (no flags) on the shipped tree is exit 0 (A8)
00:00 +2: sanity — the shipped documents validate against the real tree --log pointed at the shipped log explicitly still validates against the real decision/blockers/slo defaults (A8 — the bare call does not silently skip a rule)
00:00 +3: A4 — the shipped log skeleton carries all three steps with a rollback_target column sanity, tool-independent
00:00 +4: A5 — the schema states the percentage is a human operation the shipped human-gate block carries the literal sentence (sanity, tool-independent)
00:00 +5: A5 — the schema states the percentage is a human operation a human-gate block missing the literal sentence is a non-zero exit
00:00 +6: A1 — a missing mandatory cell is a non-zero exit an empty decision_maker cell in an otherwise-valid row is a non-zero exit
00:00 +7: A1 — a missing mandatory cell is a non-zero exit an empty metric cell in an observation row is a non-zero exit
00:00 +8: A2 — an approved decision while blockers.md has an open P0/P1 row is a non-zero exit (§6.1 valódi-sértés próba: read against the REAL blockers.md, never a fixture copy, in this group) a clean, otherwise-valid approved stage-1 row is rejected because the REAL blockers.md has open P0/P1 rows today
00:00 +9: A2 — an approved decision while blockers.md has an open P0/P1 row is a non-zero exit (§6.1 valódi-sértés próba: read against the REAL blockers.md, never a fixture copy, in this group) the same fixture with a clean (no open P0/P1) --blockers override is accepted (isolates R5 from the other approved-decision rules)
00:00 +10: A3 — every observation row carries a machine/manual source tag a source value outside {machine, manual} is a non-zero exit
00:00 +11: A7 — the cohort cell carries exactly one dimension (§0.0.1 P7) a two-dimension (intersection) cohort cell is a non-zero exit
00:00 +12: A7 — the cohort cell carries exactly one dimension (§0.0.1 P7) a single, valid dimension cohort (platform:android) is accepted (isolates R4 from the other approved-decision rules)
00:00 +13: threshold triple — min_observation_hours is an INCLUSIVE bound, not a strict ">" (round brief §6, stage-1 W = 24) 23h (below the 24h threshold) is a non-zero exit naming the step and the 24h threshold
00:00 +14: threshold triple — min_observation_hours is an INCLUSIVE bound, not a strict ">" (round brief §6, stage-1 W = 24) 24h (exactly on the threshold) is exit 0 — the inclusive bound
00:00 +15: threshold triple — min_observation_hours is an INCLUSIVE bound, not a strict ">" (round brief §6, stage-1 W = 24) 25h (above the threshold) is exit 0
00:00 +16: A9 — all four marker-block parsers are fail-closed (L566/L571/L573/L575) rollout-decision.md a missing human-gate marker block is exit 2
00:00 +17: A9 — all four marker-block parsers are fail-closed (L566/L571/L573/L575) rollout-decision.md an empty rollout-steps block is exit 2
00:00 +18: A9 — all four marker-block parsers are fail-closed (L566/L571/L573/L575) rollout-decision.md a malformed rollout-steps row (broken backtick shape) is exit 2
00:00 +19: A9 — all four marker-block parsers are fail-closed (L566/L571/L573/L575) rollout-decision.md a rollout-steps table missing a declared step is exit 2
00:00 +20: A9 — all four marker-block parsers are fail-closed (L566/L571/L573/L575) staged-rollout-log.md a missing rollout-decisions marker block is exit 2
00:00 +21: A9 — all four marker-block parsers are fail-closed (L566/L571/L573/L575) staged-rollout-log.md an empty rollout-observations block is exit 2
00:01 +22: A9 — all four marker-block parsers are fail-closed (L566/L571/L573/L575) staged-rollout-log.md a malformed decisions row (missing a column) is exit 2
00:01 +23: A9 — all four marker-block parsers are fail-closed (L566/L571/L573/L575) staged-rollout-log.md a malformed observations row (extra column) is exit 2
00:01 +24: usage errors (exit 2) — missing files a missing --decision path is exit 2
00:01 +25: usage errors (exit 2) — missing files a missing --log path is exit 2
00:01 +26: usage errors (exit 2) — missing files a missing --blockers path is exit 2
00:01 +27: usage errors (exit 2) — missing files a missing --slo path is exit 2
00:01 +28: All tests passed!

    → [4] test test/tooling/rollout_decision_test.dart: ZÖLD

═══ [5] architecture
    $ /home/ubuntu/flutter/bin/dart run tool/check_architecture.dart

Running build hooks...Running build hooks...Architecture dependencies OK (12 allowlisted deviation(s)).

    → [5] architecture: ZÖLD

═══ [6] secrets
    $ /home/ubuntu/flutter/bin/dart run tool/ci/check_secrets.dart

Running build hooks...Running build hooks...Secret scan OK (4190 file(s) scanned, 0 finding(s)).

    → [6] secrets: ZÖLD

═══ [7] l10n
    $ /home/ubuntu/flutter/bin/dart run tool/ci/check_l10n_parity.dart

Running build hooks...Running build hooks...L10n aggregate freshness OK (en, hu).
L10n parity OK (en → hu, 2298 message(s)).

    → [7] l10n: ZÖLD

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/ga_record_test.dart                      zöld
    test test/tooling/rollout_decision_test.dart               zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
```

(kilépési kód: `0`)

### 10.3 `python3 tool/release/verify_ga_record.py --record docs/release/ga-record.md` (közvetlen futtatás, csonkítatlan)

```
verify_ga_record: ok — ga_status=not-yet, 16 flag(s), rollback_target='docs/operations/disaster-recovery-drill.md'
```

(kilépési kód: `0`)

### 10.4 Valódi-sértés próba 1 (§6.1, KÖTELEZŐ) — a build-szám eltér a manifesttől → A2 PIROS

A `docs/release/ga-record.md` `app_build_number` mezőjét a valódi fán
`1` → `2`-re írtam (a `pubspec.yaml`-től eltérő értékre), majd:

**Közvetlen ellenőrző-futtatás:**

```
$ python3 tool/release/verify_ga_record.py --record docs/release/ga-record.md
verify_ga_record: 1 finding(s):
  - ga-record.md: version field 'app_build_number' is '2', but the value recomputed from pubspec.yaml/the asset manifests is '1' (A2)
```

(kilépési kód: `1`)

**`tools/round-gate.sh test/tooling/ga_record_test.dart test/tooling/rollout_decision_test.dart` a mutált fával:** a `[3] test test/tooling/ga_record_test.dart` lépés `PIROS`-ra vált (kilépési kód `1`, a gate `10`-zel áll meg), és a bukott tesztek között — pontosan a várt A2 cellával — szerepel:

```
Failing tests:
  /home/ubuntu/ss-sonnet-impl-e12-r33/test/tooling/ga_record_test.dart: A1 — a required field with a placeholder/unknown value is a non-zero exit an empty version-field cell is a non-zero exit
  /home/ubuntu/ss-sonnet-impl-e12-r33/test/tooling/ga_record_test.dart: A2 — recorded version fields must match the release-manifest inputs (round brief §0.0.1 P3) — never a hand-typed literal a build number that disagrees with pubspec.yaml is a non-zero exit (round brief §6.1 valódi-sértés próba 1)
  /home/ubuntu/ss-sonnet-impl-e12-r33/test/tooling/ga_record_test.dart: A2 — recorded version fields must match the release-manifest inputs (round brief §0.0.1 P3) — never a hand-typed literal the real committed version table matches the real release-manifest inputs, measured in Dart via generate_release_manifest.dart (round brief §0.0.1 P3, the release_manifest_test.dart:24 pattern)
  /home/ubuntu/ss-sonnet-impl-e12-r33/test/tooling/ga_record_test.dart: A7 — ga_status: ga is blocked by open P0/P1 or a non-approved stage-* decision (round brief §0.0.1 P2 / §5.4, §6.1 valódi-sértés próba 2) ga_status: ga is accepted when every stage-* decision is approved and no P0/P1 blocker is open (isolates the rule from the shipped tree's pending state — proves it is not vacuously always red)
  ... and 2 more

    → [3] test test/tooling/ga_record_test.dart: PIROS (kilépési kód 1)
```

(A cascade — hogy más csoportok is elbuknak — abból jön, hogy több teszt a
valós, mutált `ga-record.md`-et olvassa és a saját `_mangle` előfeltétele
[„tartalmazza az eredeti `\`1\`` sort"] már nem teljesül a `2`-re írt fán;
maga az A2-cél cella — mind a közvetlen Python-hívás, mind a Dart-oldali
`_buildRealManifest()`-összevetés — a várt módon PIROS.) Ezután a mezőt
visszaírtam `1`-re; `git diff --stat docs/release/ga-record.md` és
`git status --porcelain` üres kimenetet adott (a fa visszaállt a commitolt
állapotra).

### 10.5 Valódi-sértés próba 2 (§6.1 / §0.0.1 P2, KÖTELEZŐ) — `ga_status: ga` nyitott P0/P1 mellett → nem-nulla kilépés

A `ga_status` mezőt `not-yet` → `ga`-ra írtam (a `blockers.md`-ben MA nyitva
van 1 P0 + 5 P1, és a `staged-rollout-log.md` mindhárom `stage-*` sora
`pending`), majd:

```
$ python3 tool/release/verify_ga_record.py --record docs/release/ga-record.md
verify_ga_record: 2 finding(s):
  - ga-record.md: ga_status is 'ga' but staged-rollout-log.md step(s) ['stage-1', 'stage-5', 'stage-20'] are not 'approved' (A7)
  - ga-record.md: ga_status is 'ga' but blockers.md has open P0/P1 row(s) ['R-PRIV-01', 'R-SEC-01', 'R-SIGN-01', 'R-STAGE-01', 'R-STORE-01', 'R-VER-01'] (A7)
```

(kilépési kód: `1` — nem-nulla, a §5.4/A7 kötelező szabály szerint.) Ezután
a mezőt visszaírtam `not-yet`-re; `git diff --stat docs/release/ga-record.md`
és `git status --porcelain` üres kimenetet adott.

### 10.6 A gate ÚJRA zöld a két próba után

A §10.2-ben dokumentált teljes, csonkítatlan `tools/round-gate.sh
test/tooling/ga_record_test.dart test/tooling/rollout_decision_test.dart`
futás EZ UTÁN a két próba UTÁN történt (a fa a próbák visszaállítása után),
és minden lépés `ZÖLD` — a §10.3 közvetlen ellenőrző-futtatás szintén a két
próba utáni, tiszta fán történt. A fa a kör végén commitolt, tiszta
állapotban van.

## 11. Review — a Claude tölti ki
