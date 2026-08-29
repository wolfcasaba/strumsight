# E12-R13 — Device matrix és device lab nyilvántartás

- **Státusz:** READY (pre-flight újramérve 2026-08-29, kód olvasva: `main @ 1e376d4d`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 13
- **Kör-azonosító:** `E12-R13`
- **Branch:** `sonnet-impl/e12-r13-device-matrix-and-device-lab`
- **Előfeltétel:** `E12-R01` merge-elve (a baseline sorolja fel a mai eszköz-bizonyítékokat)
- **Brief szerzője:** Claude (Opus 5) · **Pre-flight revízió:** Claude (Opus 5), 2026-08-29
- **Előre kiosztott ADR:** nincs — a kör nyilvántartást és riportot szállít, kötött architekturális döntés nélkül (a tier-szerződést az [ADR 0196](../adr/0196-vision-device-tier-performance-and-thermal-contract.md) MÁR rögzíti, a `package:yaml`-mentes gépi mércét az [ADR 0444](../adr/0444-delivery-workflow-and-repository-policy.md) D3/D6 és az [ADR 0447](../adr/0447-release-manifest-provenance-and-sbom.md) D5 MÁR rögzíti). A kör-jelzésben és a §0.0-ban ez a döntés dokumentált, nem hallgatólagos.

**Visszakeresett előzmény (ADR 0312, MÉRT — `node tools/knowledge-rag.mjs`):**

| Kérdés | Találat | Mit visz be a körbe |
|---|---|---|
| `--corpus lessons,halts,adr "device matrix tier capability release blocking device lab report"` | [ADR 0196](../adr/0196-vision-device-tier-performance-and-thermal-contract.md) (`bm25#1`), [L249](../LESSONS.md#l249) (`emb#2`) | a tier-fogalom MÁR definiált (nem vezetünk be újat); L249: egy capability-mátrixban MINDEN EGYES kapuhoz saját, mért igazolás kell — a „capability szerint" elv önmagában nem kapu |
| `--corpus lessons,halts "YAML parsing dart test without package:yaml python tool exit code guard"` | [L86](../LESSONS.md#l86), [L527](../LESSONS.md#l527) (`emb#2`), [L102](../LESSONS.md#l102) | L527: az ÖNVÉDŐ cella volt a vakon zöld — a saját forrását olvasó guard-cellának a TELJES tiltott halmazt kell néznie; L102: az implementer önálló `flutter test` hívása NEM a `round-gate.sh` |
| teljes korpusz: `"device-matrix.yaml device_report.py device_matrix_test.dart docs/testing device lab"` | a saját brief §7/§8, majd az SDD Ch12 §165 | nincs további, korábbi kör-előzmény ezen a három fájlon — a kör tényleg új nyilvántartást hoz |

---

## 0.0 Pre-flight revízió (2026-08-29) — MÉRT állítások, amelyek felülírják a 2026-08-27-i brief-szöveget

A brief előre íródott; az alábbi hét pontot a pre-flight **kigrepelte a fából**, és
ezek a mai igazságok. Ahol a régi szöveg mást mondott, **ez a szakasz az érvényes**.

### R1 — `docs/manual-testing/` HAT dokumentumot tartalmaz, nem négyet

```
analysis-eval-matrix.md          gov-05-shipping-device-run.md
practice-engine-device-matrix.md vision-camera-spike-runbook.md
vision-device-matrix.md          vision-performance-benchmark.md
```

A régi §2 „négy eszköz-dokumentum" állítása avult. **Az A6 mind a hatra
vonatkozik** (mind a hatot hivatkozni kell, egyiket sem szabad átírni).

### R2 — a `VisionDeviceTier` enum NEM a `domain` rétegben van

MÉRT hely: `lib/features/vision/data/landmarks/hand_landmark_provider.dart:125` —
`enum VisionDeviceTier { basic, mid, flagship }`. A
`lib/features/vision/domain/performance/vision_device_tier.dart` ezt **importálja,
nem redefiniálja** (ADR 0196 Következmények). A brief régi „`lib/features/vision/domain`
tier-enumja" megfogalmazása pontatlan volt; a mátrix a **három** mért értéket
(`basic`, `mid`, `flagship`) használhatja, újat nem vezet be.

### R3 — a Dart-oldali mércének `package:yaml` NÉLKÜL kell mennie

MÉRT: a `yaml` csomag **tranzitív** függőség (`pubspec.lock:1261`, `dependency: transitive`),
és a `pubspec.yaml` **NINCS** az engedélyezett fájlok listáján, tehát nem is
tehető direkt függőséggé ebben a körben. A `test/tooling/device_matrix_test.dart`
ezért **saját, szűkített YAML-részhalmaz-olvasót** tartalmaz, pontosan úgy, ahogy a
`test/tooling/repository_policy_test.dart` (ADR 0444 D3) és a
`test/tooling/release_manifest_test.dart` (ADR 0447 D5) teszi. Önvédő cella
kötelező (lásd A8).

### R4 — az A4-nek GÉPI mércéje van, nem csak §10-be másolt kimenete

MÉRT precedens: `test/tooling/release_manifest_test.dart:173,228,…` és
`test/tooling/signing_policy_test.dart:35` **`Process.runSync('python3', …)`**-szel
méri a saját Python eszközét, **skip-ág nélkül** (`release_manifest_test.dart:599-635`:
ha nincs `python3`, a `ProcessException` PIROS, nem skip). A `python3` a
CI-runneren és ezen a boxon is elérhető; a tiltott bináris a `rg`/`grep`/`jq`/`gh`
([L110](../LESSONS.md#l110)). **Az A4 tehát a `device_matrix_test.dart`-ból,
ideiglenes fixture-könyvtárakon mérve is bizonyítandó** — a §10-be másolt kimenet
ezt kiegészíti, nem helyettesíti.

### R5 — a „user valódi tesztkészüléke" a fában NÉVVEL nincs kitöltve; a mért elsődleges teszteszköz a **Pixel 6a**

MÉRT: a `docs/manual-testing/gov-05-shipping-device-run.md:120` „Készülék és
Android-verzió:" mezője **üres** (kitöltetlen menet). Az egyetlen MÉRT, névvel
kijelölt elsődleges eszköz:

- `docs/manual-testing/vision-device-matrix.md:160` — **Pixel 6a** … „Kötelező (elsődleges teszteszköz)"
- `docs/manual-testing/vision-performance-benchmark.md:117` — **Pixel 6a** … „Kötelező (elsődleges baseline)"

**Az A5 ezért így érvényes:** a mátrixnak a MÉRT elsődleges teszteszközt
(`Pixel 6a`) kell névvel, `release_blocking: true` értékkel tartalmaznia, minden
eszköznél a forrás-hivatkozással (`provenance`). **Nem mért készüléknevet kitalálni
TILOS** (§9 első kockázat) — ha a user más készüléket használ, azt egy későbbi kör
írja be a saját menete alapján.

### R6 — a GA-scope capability-lista MÉRT forrása az SDD Ch12 §5.1 + §5.4, a nem-GA-é az §5.2

MÉRT (`docs/sdd/12-release-roadmap-final-integration.md:259-289` §5.1 Core Learning
Scope; `:300-312` §5.4 GA scope szabály; `:280-289` §5.2 Intelligent Coaching Scope;
`:1105-1110` §18.3 device support policy):

**GA scope (`ga_scope: true`) — mind a tizenegy, ZÁRT lista:**
`onboarding` · `live_and_tuner` · `practice_engine` · `song_trainer_local` ·
`audio_analysis_core` · `progress_goals_streak` · `storage_migration` ·
`offline_operation` · `localization_en_hu` · `accessibility_minimum` ·
`session_lifecycle_stability`

**NEM GA scope (`ga_scope: false`, informational) — mind a három:**
`computer_vision` (Ch12 §5.2: „Computer Vision opt-in preview") ·
`offline_ai` (Ch12 §5.2 + az Epic 10 sáv MÉRT `hold` státusza,
`docs/execution/pipeline-queue.tsv:634-638`) · `ai_tutor` (Ch12 §5.2).

A régi brief csak az Offline AI-t vette ki a GA scope-ból; **MÉRVE a Computer
Vision és az AI Tutor is `preview`, tehát szintén nem GA** — az A2 invariáns
kizárólag a fenti tizenegyre kötelező.

### R7 — a kötelező tesztcsomag MÉRT forrása az SDD Ch12 §18.2

MÉRT (`docs/sdd/12-release-roadmap-final-integration.md:1091-1104`) — tizennégy
mérés, ez a `required_suite` ZÁRT szótára:
`install_and_update` · `cold_start` · `live_start_latency` · `mic_release` ·
`practice_soak_20min` · `analyze_memory_peak` · `camera_preview_and_thermal` ·
`local_ai_load_ttft` · `background_resume` · `battery_saver` · `airplane_mode` ·
`low_storage` · `text_scale_200` · `screen_reader_path`.

A `local_ai_load_ttft` a §18.2 szerint „ha támogatott" — a `not_ga_scope` Offline AI
miatt MA egyetlen eszközön sem kötelező, ezért **nem kerül** a `required_suite`-ba,
és ezt a `device-lab.md` kimondja.

---

## 0.1 Mi az, ami valóban új

A fán hat, egymástól független manuális eszköz-dokumentum él, mind más formában.
Ami hiányzik: (a) egy géppel olvasható eszköz-nyilvántartás (`device-matrix.yaml`),
(b) az a szabály, hogy MELYIK GA-capabilityhez KELL legalább egy release-blokkoló
eszköz, (c) egy riport-generátor, ami a manuális futások eredményét beolvassa. A kör
ezt a hármat adja.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/testing/device-matrix.yaml",
  "docs/testing/device-lab.md",
  "tool/device_report.py",
  "test/tooling/device_matrix_test.dart",
  "docs/rounds/e12-r13-device-matrix-and-device-lab.md",
]
gate_tests = [
  "test/tooling/device_matrix_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

**A kör-jelzés KÖTELEZŐ** — jelzés nélküli futás bukott futás:

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll (scope-ütközés):** ha a munka olyan fájl módosítását kívánná,
amely a §4 engedélyezett listáján NINCS rajta (pl. `pubspec.yaml`, `lib/**`,
`docs/manual-testing/**`, `.github/**`), az **nem** a lista önkezű tágításának,
hanem a `stopped` jelzésnek az esete: `tools/codex-signal.sh stopped "<mi ütközik>"`,
és a jelentésben az ütköző fájl + a szükséges döntés.

**STOP-protokoll (lefedetlen capability):** ha a mátrix egy GA-scope capabilityhez
EGYETLEN elérhető eszközt sem talál, az nem a szabály lazításának, hanem a `stopped`
jelzésnek az esete — a döntés (scope-vágás vagy eszköz beszerzése) a useré.

**A §8 a terved — nincs külön task-lista.** Doc-commentben csak tesztben bizonyított
állítás szerepelhet.

## 1. Cél

Evidence-alapú eszköztámogatási döntés: melyik készülék-tier melyik capabilityt
blokkolja, és melyik csak informál.

## 2. Jelenlegi állapot — mért tények (2026-08-29)

- `docs/manual-testing/` **hat** dokumentumot tartalmaz (R1), mind Markdown, mind
  kézi kitöltésű, gépi séma nélkül.
- **Minden manuális sor `PENDING`** mind a hat dokumentumban — valós eszközös
  eredmény MA nincs a fában. A mátrix ezért a *nyilvántartást* és a *kötelező
  csomagot* rögzíti; az eredmény-mezők értéke `pending` (ez NEM helykitöltő, hanem
  a séma érvényes állapotértéke — lásd A7).
- A `VisionDeviceTier` enum kódban ÉL, három értékkel (R2). Az Offline AI tier
  MÉG NEM (Epic 10 `hold`), ezért az Offline AI oszlop `not_ga_scope` (R6).
- `docs/testing/` a Kör 11/12 után létezik (`e2e-harness.md`, `release-fixture-corpus.md`).
- `tool/` MA **egy** Python fájlt tartalmaz (`audit_repository_policy.py`, Kör 3) —
  a `device_report.py` a második. A `tools/round-gate.sh` és a
  `.github/actions/flutter-gates` **nem futtat lintert** a `tool/*.py`-ra (a `ruff`
  csak a `backend/`-re megy), ezért a Python eszköz egyetlen gépi mércéje a
  Dart-oldali teszt (R4).
- A `flutter analyze lib/ test/ tool/` a `tool/`-t is analizálja — de csak Dart
  fájlokat; egy `.py` fájl nem ad analyzer-diagnosztikát ([L86](../LESSONS.md#l86)).

### 2.1 A MÉRT eszköz-készlet (a mátrix pontosan ezt viszi be)

| Eszköz | OS | RAM | SoC | Kamera | Mért szerep | Forrás |
|---|---|---|---|---|---|---|
| Pixel 6a | Android 14 (API 34) | 6 GB | Google Tensor, Mali-G78 | 12.2 MP, 30 fps, AF | Kötelező (elsődleges teszteszköz) | `vision-device-matrix.md:160`, `vision-performance-benchmark.md:117` |
| Pixel 7 | Android 14 (API 34) | 8 GB | Google Tensor G2, Mali-G710 | 50 MP, 30 fps, AF | Kötelező | `vision-device-matrix.md:161`, `vision-performance-benchmark.md:118` |
| Samsung Galaxy A54 | Android 14 (API 34) | 6 GB | Exynos 1380, Mali-G68 | 50 MP, 30 fps, AF | Ajánlott (középkategóriás) | `vision-device-matrix.md:162`, `vision-performance-benchmark.md:119` |
| Xiaomi Redmi Note 12 | Android 13 (API 33) | 4 GB | Snapdragon 685, Adreno 610 | 48 MP, 30 fps, AF | Ajánlott (alsó-közép határ) | `vision-device-matrix.md:163`, `vision-performance-benchmark.md:120` |

**A leképezés:** `Kötelező` → `release_blocking: true`; `Ajánlott` → `release_blocking: false`.

**KIHAGYVA — és ezt a `device-lab.md` kimondja:** a `vision-device-matrix.md:164-165`
**Samsung Galaxy S23** és **Pixel 4a** sorai — ezekhez a fában **nincs mért RAM és
SoC** (a `vision-performance-benchmark.md:117-120` négy eszközt sorol). Kitalált
RAM-értékkel felvenni őket a §9 első kockázata (látszat-lefedettség), ezért
kimaradnak; egy későbbi kör mérés után felveheti őket.

**ABI:** `arm64-v8a` mind a négy eszközre. MÉRT levezetés: az
`android/app/build.gradle.kts`-ben **nincs `abiFilters` szűkítés** (a fájl 102.
sora csak `ndkVersion = flutter.ndkVersion`), a fenti négy SoC pedig kivétel nélkül
64 bites ARM. Ezt a levezetést a `device-lab.md` kiírja, hogy a szám ne
forrás nélküli állítás legyen.

## 3. Scope

**Benne van:** `docs/testing/device-matrix.yaml` — eszközönként: OS-verzió, RAM, ABI,
SoC, audio-képesség, kamera-képesség, vision-tier, offline-AI-tier,
`release_blocking: true|false`, `required_suite` és `provenance` · capabilityenként:
`ga_scope` és a lefedő eszközök · `docs/testing/device-lab.md` (hogyan fut egy
manuális kör, mit kell rögzíteni, mi maradt ki és miért) · `tool/device_report.py`
(a manuális eredmények beolvasása és riport-generálás; hiányzó kötelező futás →
nem-nulla kilépés) · `test/tooling/device_matrix_test.dart` (séma-validáció, a §6
invariánsai, a Python eszköz gépi mérése).

**NINCS benne (tilos):**

- A `docs/manual-testing/` meglévő dokumentumainak törlése vagy átírása (hivatkozni szabad).
- Új tier-fogalom bevezetése a kódban vagy a YAML-ban (a `VisionDeviceTier` három értéke a szótár).
- `docs/adr/**`, `lib/**`, `pubspec.yaml`, `.github/**`, `tools/**`.
- Nem mért készüléknév, RAM, SoC vagy eredmény beírása.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/testing/device-matrix.yaml` | ÚJ — a géppel olvasható nyilvántartás |
| `docs/testing/device-lab.md` | ÚJ — a manuális kör leírása |
| `tool/device_report.py` | ÚJ — riport-generátor |
| `test/tooling/device_matrix_test.dart` | ÚJ — a §6 cellái |
| `docs/rounds/e12-r13-device-matrix-and-device-lab.md` | a §10 handoff kitöltése |

**Tilos zóna:** minden más — kiemelten `docs/manual-testing/**` · `lib/**` ·
`pubspec.yaml` · `pubspec.lock` · `.github/**` · `docs/adr/**` · `tools/**` ·
`docs/sdd/**` · `docs/execution/**`.

## 5. Kötött szabályok

Nincs ADR (a §0 indoklása szerint); négy, a briefből és a mért forrásokból következő
KÖTELEZŐ szabály:

### 5.1 Minden GA-scope capabilityhez legalább egy `release_blocking: true` eszköz tartozik

A GA-scope lista a R6 szerinti **tizenegy** elem. **NEM elfogadható gyengítés:** egy
capability `ga_scope: false`-ra állítása azért, mert nincs rá blokkoló eszköz — a
hiány a `stopped` jelzés esete, a döntés a useré.

### 5.2 Az Offline AI (vagy bármely nem-GA capability) hiánya NEM jelent core-inkompatibilitást

MÉRT normatív forrás: Ch12 §18.3 — „Az app nem állíthatja, hogy az egész készülék
inkompatibilis csak azért, mert a helyi generatív modell nem fut rajta." Egy eszköz,
ami a helyi AI-t nem bírja, továbbra is `core_support: supported`. **NEM elfogadható
gyengítés:** eszköz-szintű globális „nem támogatott" jelölés egyetlen opcionális
capability miatt.

### 5.3 A Dart-oldali mérce `package:yaml` nélkül, saját szűkített olvasóval megy (R3)

A `device-matrix.yaml` ezért a **szűkített részhalmazra** korlátozódik, amit a saját
olvasó determinisztikusan parse-ol: 2 szóközös behúzás, `kulcs: érték`, `- ` listaelem,
`kulcs:` blokk, inline `[a, b]` lista, `#` kommentek; **nincs** ankor/alias, több-soros
skalár, flow-map, tab-behúzás. A `device-lab.md` ezt a részhalmazt kiírja, mert ez a
fájl szerkeszthetőségi szerződése.

### 5.4 A `pending` eredmény-érték érvényes állapot, a hiányzó azonosító-mező NEM

Az eredmény-mezők (`audio.result`, `camera.result`, `vision_tier`, a `required_suite`
futásainak eredménye) felvehetik a `pending` értéket — ez a mért igazság (§2), nem
helykitöltő. Az **azonosító- és provenance-mezők** (`id`, `name`, `os`, `api_level`,
`ram_gb`, `abi`, `soc`, `release_blocking`, `provenance`) viszont **kötelezők, és
helykitöltő értékkel (`unknown`, `n/a`, `tbd`, `?`, `pending`, üres) TILOSAK** — ez az
[E12-R12 mért leckéje](../LESSONS.md#l546): ott az „unknown" licenc-helykitöltő ment
át a checkeren, és a teszt ezt zöldként rögzítette.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték (gépi, hacsak nem jelölt) |
|---|---|---|
| A1 | A `device-matrix.yaml` séma-valid: minden eszközön ott van mind a kilenc kötelező azonosító-mező (`id`, `name`, `os`, `api_level`, `ram_gb`, `abi`, `soc`, `release_blocking`, `provenance`), és egyiken sincs helykitöltő érték (§5.4) | `device_matrix_test.dart` — valódi fájl + fixture-negatív |
| A2 | Mind a **tizenegy** GA-scope capabilityhez van legalább egy `release_blocking: true` eszköz | `device_matrix_test.dart` — valódi fájl + 0/1/2 cellahármas (§6.2) |
| A3 | Egy `offline_ai_tier: not_ga_scope`/`unsupported` eszköz `core_support: supported` marad; eszköz-szintű globális „unsupported" nincs | `device_matrix_test.dart` — valódi fájl + fixture-negatív |
| A4 | `tool/device_report.py` hiányzó kötelező futásra **nem-nulla** kóddal lép ki, teljes eredményhalmazra **0**-val | `device_matrix_test.dart` `Process.runSync('python3', …)` ideiglenes fixture-könyvtáron (R4) **és** a §7 parancs kimenete a §10-ben |
| A5 | A MÉRT elsődleges teszteszköz (`Pixel 6a`) névvel, `release_blocking: true` értékkel szerepel, és minden eszköz `provenance`-a létező `docs/manual-testing/…:<sor>` hivatkozás | `device_matrix_test.dart` (a hivatkozott fájlok LÉTEZÉSÉT is méri) |
| A6 | A `device-lab.md` mind a **hat** `docs/manual-testing/` dokumentumot hivatkozza, és a kör egyiket sem írja felül | `device_matrix_test.dart` + `git diff --stat` a §10-ben |
| A7 | A `required_suite` és a capability-lista a MÉRT zárt szótárakból jön (R6, R7): ismeretlen capability-azonosító vagy ismeretlen suite-elem PIROS | `device_matrix_test.dart` — fixture-negatív |
| A8 | Önvédő cellák: a teszt nem importál `package:yaml`-t, és külső processzként **kizárólag** `python3`-at indít (soha `rg`/`grep`/`jq`/`gh`/`git`); a `python3` elérhetőségét külön cella méri, **skip-ág nincs** | `device_matrix_test.dart` — a saját forrását olvasva ([L527](../LESSONS.md#l527)) |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA | Melyik őr méri |
|---|---|---|
| Egy GA-capability csak `release_blocking: false` eszközökkel szerepel | A2 | fixture-negatív + valódi fájl |
| Egy GA-capability `ga_scope: false`-ra állítva, hogy „elférjen" | A7 (ismeretlen/hiányzó GA-azonosító a zárt listához képest) | fixture-negatív |
| Az Offline AI hiánya eszköz-szintű „unsupported" jelölést kap | A3 | fixture-negatív |
| A riport-generátor hiányzó futásra 0-val lép ki (csak figyelmeztet) | A4 | `Process.runSync('python3', …)` fixture-könyvtáron |
| A YAML-ból hiányzik az ABI vagy a RAM mező egy eszközön | A1 | fixture-negatív |
| Egy eszköz `ram_gb: unknown` / `abi: tbd` helykitöltőt kap | A1 (§5.4) | fixture-negatív, a teljes helykitöltő-listát végigjárva |
| A `provenance` egy nem létező fájlra vagy sorra mutat | A5 | valódi fájl-létezés mérése |
| Kitalált készülék (pl. `Samsung Galaxy S23` mért RAM nélkül) kerül a mátrixba | A5 (provenance-hivatkozás hiánya) | fixture-negatív + valódi fájl |
| A teszt `import 'package:yaml/yaml.dart'`-tal old meg mindent | A8 | önvédő cella |
| A teszt `Process.runSync('rg', …)`-vel keres | A8 | önvédő cella, a TELJES tiltott halmazt nézve (L527) |

### 6.2 Numerikus küszöb — az „legalább egy blocking eszköz" cellahármasa

A küszöb `>= 1`. A három cella (fixture-vezérelt, ugyanazon a checker-függvényen):

```
python3 -c "print([(n, n >= 1) for n in (0, 1, 2)])"
# [(0, False), (1, True), (2, True)]
```

| Cella | Fixture | Elvárt |
|---|---|---|
| alatta | egy GA-capability **0** `release_blocking: true` eszközzel | a checker PIROS, és megnevezi a capabilityt |
| rajta | ugyanaz **1** blocking eszközzel | a checker ZÖLD |
| fölötte | ugyanaz **2** blocking eszközzel | a checker ZÖLD |

### 6.3 Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva)

Állítsd a **valódi** `docs/testing/device-matrix.yaml`-ban az egyik GA-capabilityt
lefedő ÖSSZES eszköz `release_blocking` mezőjét `false`-ra, futtasd a §7 gate-et →
az **A2** cellának PIROSNAK kell lennie → állítsd vissza, és a §10-ben mutasd meg,
hogy a visszaállítás után `git diff --stat` a fájlon üres.

## 7. Kötelező ellenőrzések

A mérce EGYETLEN futtatható artefaktum — csővezeték (`| tail`), `&&`-lánc és
egyenkénti `flutter test` hívás **nem** bizonyíték ([L102](../LESSONS.md#l102)):

```bash
tools/round-gate.sh test/tooling/device_matrix_test.dart
```

A riport-generátor közvetlen futtatása (a kimenet a §10-be, szó szerint):

```bash
python3 tool/device_report.py --matrix docs/testing/device-matrix.yaml --check
```

MA — valós eredmény-fájl nélkül — ennek a parancsnak **nem-nulla** kóddal kell
kilépnie, és fel kell sorolnia a hiányzó kötelező futásokat. Írd a §10-be az
`echo $?` értékét is.

## 8. Implementációs sorrend

1. A hat meglévő manuális dokumentum MÉRÉSE (a §2.1 tábla ellenőrzése a fán).
2. `docs/testing/device-matrix.yaml` — a §2.1 négy eszköze, a R6 tizennégy
   capabilityje, a R7 tizenhárom kötelező suite-eleme.
3. `test/tooling/device_matrix_test.dart` — szűkített YAML-olvasó (R3),
   tartalom-paraméterezett checker-függvények (hogy fixture-ből ÉS valódi fájlból is
   hívhatók legyenek, ADR 0444 D6), A1–A8 cellái.
4. `tool/device_report.py` — `--matrix`, `--results`, `--check`, `--report`;
   PyYAML-lel (a fán 6.0.1, `tool/audit_repository_policy.py` precedens: az
   `import yaml` KEMÉNY függőség, csendes fallback nincs).
5. `docs/testing/device-lab.md` — a manuális kör menete, a rögzítendő mezők, a
   szűkített YAML-részhalmaz szerződése, a kihagyott két eszköz indoklása, a
   `local_ai_load_ttft` kihagyásának indoklása, a hat manuális dokumentum hivatkozása.
6. `tools/round-gate.sh test/tooling/device_matrix_test.dart` + a §6.3 valódi-sértés
   próba + a §10 kitöltése.

## 9. Kockázatok

- **A mátrix kitalálása.** Nem létező eszközök vagy nem mért RAM/SoC felsorolása
  látszat-lefedettséget ad; csak a §2.1 MÉRT sorai kerülhetnek be, `provenance`-szal.
- **A capability-oszlop elavulása.** Az Epic 10 `hold`-on áll: az Offline AI
  `not_ga_scope` jelölése MA igaz, és a sáv indulásakor felül kell vizsgálni. Ezt a
  `device-lab.md` kimondja.
- **Helykitöltő-vakság.** Az E12-R12 MAJOR-ja ([L546](../LESSONS.md#l546)) pontosan
  az volt, hogy a helykitöltő átment a checkeren, és a teszt ezt zöldként rögzítette.
  Az A1 cellájának a TELJES helykitöltő-listát végig kell járnia.
- **Önvédő cella vaksága.** [L527](../LESSONS.md#l527): a `Process.run`-t kereső, de
  a `Process.start`-ot átengedő guard a saját hibaosztályán ment át. Az A8 cellájának
  mindkét alakot (`Process.run`, `Process.runSync`, `Process.start`) néznie kell.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
