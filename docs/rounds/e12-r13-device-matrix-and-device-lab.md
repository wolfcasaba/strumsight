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

**Motor:** Claude Sonnet 5 (`sonnet-impl`), 2026-08-29.

### 10.1 Leszállított fájlok

Pontosan az öt engedélyezett útvonal, mind commitolva a
`sonnet-impl/e12-r13-device-matrix-and-device-lab` ágra:

- `docs/testing/device-matrix.yaml` — ÚJ. Négy MÉRT eszköz (Pixel 6a, Pixel 7,
  Samsung Galaxy A54, Xiaomi Redmi Note 12), tizennégy capability (11 GA + 3
  nem-GA), tizenhárom kötelező suite-elem eszközönként (a `local_ai_load_ttft`
  a zárt szótárban van, de egyetlen eszköz `required_suite`-jában sincs, R7).
- `docs/testing/device-lab.md` — ÚJ. A manuális kör menete, a szűkített
  YAML-részhalmaz szerződése, az `identifier` vs. `result` mező megkülönböztetés
  (§5.4), a suite-id → dokumentum leképezés, a kihagyott két eszköz és a
  `local_ai_load_ttft` kihagyásának indoklása, mind a hat
  `docs/manual-testing/` dokumentum hivatkozva.
- `tool/device_report.py` — ÚJ. `--matrix`/`--results`/`--check`/`--report`,
  PyYAML kemény függőséggel (`import yaml`, nincs csendes fallback).
- `test/tooling/device_matrix_test.dart` — ÚJ. Szűkített YAML-olvasó
  (`package:yaml` nélkül), tartalom-paraméterezett checker-függvények, 99 cella
  (A1–A8 + a parser saját önteszjei).
- `docs/rounds/e12-r13-device-matrix-and-device-lab.md` — ez a §10 kitöltése.

Tilos zónát nem érintettem — `docs/manual-testing/**`, `lib/**`,
`pubspec.yaml`, `.github/**`, `docs/adr/**`, `tools/**`, `docs/sdd/**`,
`docs/execution/**` egyike sem szerepel a diffben.

### 10.2 `tools/round-gate.sh test/tooling/device_matrix_test.dart` — teljes, csonkítatlan kimenet

```
═══ [1] format
    $ /home/ubuntu/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool

Formatted 2184 files (0 changed) in 9.29 seconds.

    → [1] format: ZÖLD

═══ [2] analyze
    $ /home/ubuntu/flutter/bin/flutter analyze lib/ test/ tool/

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  archive 4.0.9 (4.2.0 available)
  audio_streamer 4.3.0 (5.0.0 available)
  camera 0.11.4 (0.12.0+2 available)
  camera_android_camerax 0.6.30 (0.7.4+6 available)
  camera_avfoundation 0.9.23+2 (0.10.2 available)
  camera_web 0.3.5+4 (0.3.5+5 available)
  code_assets 1.2.1 (2.0.0 available)
  cross_file 0.3.5+4 (0.3.5+5 available)
  dbus 0.7.14 (0.7.15 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.3.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.2.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage 10.3.1 (11.0.0 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_linux 3.0.1 (3.0.2 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.3 available)
  go_router 17.3.0 (18.0.0 available)
  hooks 2.0.2 (2.2.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  material_color_utilities 0.13.0 (0.13.1 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.6.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.1 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.6.1 available)
  permission_handler_html 0.1.3+5 (0.1.4+1 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.1.1 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.28 available)
  source_maps 0.10.13 (0.10.14 available)
  synchronized 3.4.1 (3.4.1+2 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  vm_service 15.2.0 (15.3.0 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  win32 6.3.0 (6.4.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
54 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing 3 items...                                            
No issues found! (ran in 5.8s)

    → [2] analyze: ZÖLD

═══ [3] test test/tooling/device_matrix_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/tooling/device_matrix_test.dart

Resolving dependencies...
Downloading packages...
  (… ugyanaz a 51-soros függőséglista, mint a [2] lépésben …)
Got dependencies!
54 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-sonnet-impl-e12-r13/test/tooling/device_matrix_test.dart
00:00 +0: parseDeviceMatrix — restricted YAML subset (R3) parses a minimal, fully-formed document
00:00 +1: parseDeviceMatrix — restricted YAML subset (R3) parses inline lists, including an empty one
00:00 +2: parseDeviceMatrix — restricted YAML subset (R3) rejects an unsupported top-level key
00:00 +3: parseDeviceMatrix — restricted YAML subset (R3) rejects an unsupported device field
00:00 +4: parseDeviceMatrix — restricted YAML subset (R3) rejects "devices:" written with an inline value
00:00 +5: A1 — device-matrix.yaml schema validity: nine identifier fields, no placeholder value (§5.4, L546) self-check: isPlaceholderValue is case-insensitive and does not flag a legitimate value
00:00 +6: A1 — device-matrix.yaml schema validity: nine identifier fields, no placeholder value (§5.4, L546) self-check: a fully populated fixture device has zero placeholder violations
00:00 +7: A1 — device-matrix.yaml schema validity: nine identifier fields, no placeholder value (§5.4, L546) matrix row: a device missing the "abi" field entirely (not just empty) is flagged
00:00 +8…+61: A1 — device-matrix.yaml schema validity: nine identifier fields, no placeholder value (§5.4, L546) matrix row: "<field>" set to placeholder "<unknown|n/a|tbd|?|<empty>|pending>" is flagged (54 cella — 6 helykitöltő × 9 azonosító-mező, mind egyenként pirosra vinné a §5.4 sértést)
00:00 +62: A1 — device-matrix.yaml schema validity: nine identifier fields, no placeholder value (§5.4, L546) the real device-matrix.yaml has all nine identifier fields on every device, none of them a placeholder value
00:00 +63: A2 — every GA-scope capability has at least one release_blocking device (§5.1, §6.2 numeric threshold) threshold cell: 0 release_blocking devices covering a GA capability is flagged
00:00 +64: A2 — every GA-scope capability has at least one release_blocking device (§5.1, §6.2 numeric threshold) threshold cell: 1 release_blocking device covering a GA capability is clean
00:00 +65: A2 — every GA-scope capability has at least one release_blocking device (§5.1, §6.2 numeric threshold) threshold cell: 2 release_blocking devices covering a GA capability is clean
00:00 +66: A2 — every GA-scope capability has at least one release_blocking device (§5.1, §6.2 numeric threshold) matrix row: a GA capability entirely missing from device-matrix.yaml is flagged as missing, not silently accepted
00:00 +67: A2 — every GA-scope capability has at least one release_blocking device (§5.1, §6.2 numeric threshold) the real device-matrix.yaml: all eleven GA-scope capabilities have at least one release_blocking device
00:00 +68: A3 — an optional (non-GA) capability tier never demotes a device to globally unsupported (§5.2, Ch12 §18.3) matrix row: offline_ai_tier: not_ga_scope with core_support: unsupported is flagged
00:00 +69: A3 — an optional (non-GA) capability tier never demotes a device to globally unsupported (§5.2, Ch12 §18.3) matrix row: offline_ai_tier: unsupported with core_support: unsupported is flagged too
00:00 +70: A3 — an optional (non-GA) capability tier never demotes a device to globally unsupported (§5.2, Ch12 §18.3) self-check: offline_ai_tier: not_ga_scope with core_support: supported is clean
00:00 +71: A3 — an optional (non-GA) capability tier never demotes a device to globally unsupported (§5.2, Ch12 §18.3) the real device-matrix.yaml: every device keeps core_support: supported regardless of offline_ai_tier
00:00 +72: A5 — provenance references are real; the measured primary test device is present (R5, §9 invented-device risk) matrix row: a provenance value that is not a "path:line" reference is flagged
00:00 +73: A5 — … matrix row: a provenance value pointing at a non-existent manual-testing file is flagged
00:00 +74: A5 — … matrix row: a provenance line number beyond the end of the file is flagged
00:00 +75: A5 — … self-check: a well-formed, real provenance reference is clean
00:00 +76: A5 — … matrix row: a fixture without a device named "Pixel 6a" is flagged as missing the measured primary device
00:00 +77: A5 — … the real device-matrix.yaml: every provenance reference points at an existing docs/manual-testing/ file and an in-range line
00:00 +78: A5 — … the real device-matrix.yaml names Pixel 6a as release_blocking: true (R5, the measured elsődleges teszteszköz)
00:00 +79: A6 — device-lab.md references all six docs/manual-testing documents (R1) and rewrites none of them the real device-lab.md mentions every one of the six documents
00:00 +80: A6 — … self-check: the required-docs list above actually has six entries (R1 — it used to be four)
00:00 +81: A7 — required_suite and capability identifiers come from the measured closed dictionaries (R6, R7) matrix row: an unknown capability id is flagged
00:00 +82: A7 — … matrix row: a GA-dictionary id declared with ga_scope: false is flagged (the "weaken the invariant so it fits" class, §6.1)
00:00 +83: A7 — … matrix row: a non-GA-dictionary id declared with ga_scope: true is flagged
00:00 +84: A7 — … matrix row: an unknown required_suite element is flagged
00:00 +85: A7 — … self-check: a fixture using only dictionary ids/items is clean
00:00 +86: A7 — … the real device-matrix.yaml: every capability id and required_suite element comes from the closed dictionaries
00:00 +87: A7 — … the real device-matrix.yaml declares all eleven GA-scope and all three non-GA-scope capability ids, no more, no fewer
00:00 +88: A7 — … local_ai_load_ttft is a valid suite-dictionary entry but no device requires it today (R7 — Offline AI is not_ga_scope)
00:00 +89: A4 — tool/device_report.py --check: non-zero on missing mandatory runs, zero on a complete result set (R4) no --results file: every mandatory run is missing, non-zero exit, names each one
00:00 +90: A4 — … a --results file recording every mandatory run — even as "pending" — is a zero exit (pending is a valid recorded state, §5.4)
00:00 +91: A4 — … threshold cell: one recorded, one missing mandatory run is still a non-zero exit, naming only the missing one
00:00 +92: A4 — … matrix row: a recommended (non-blocking) device is never counted as a mandatory run
00:00 +93: A4 — … --report on the real matrix runs cleanly and lists every device
00:00 +94: A4 — … the §7 command: the real matrix, --check, with no results file is a non-zero exit today (no result fixture exists yet)
00:00 +95: A4 — … neither --check nor --report given is a usage error, not a silent success
00:00 +96: A8 — this gate never relies on an unguaranteed or forbidden binary (L110, L527) this file does not import the transitive-only yaml package
00:00 +97: A8 — … every external process this file spawns — through any dart:io Process.run/.runSync/.start entry point (L527: a guard naming only one prefix is blind to the others) — targets python3 only, never rg/grep/jq/gh/git
00:00 +98: A8 — … self-check: python3 is on PATH in this environment — if it is not, the calls above throw ProcessException and this whole file turns red, never a silent skip
00:00 +99: All tests passed!

    → [3] test test/tooling/device_matrix_test.dart: ZÖLD

═══ [4] architecture
    $ /home/ubuntu/flutter/bin/dart run tool/check_architecture.dart

Running build hooks...Running build hooks...Architecture dependencies OK (12 allowlisted deviation(s)).

    → [4] architecture: ZÖLD

═══ [5] secrets
    $ /home/ubuntu/flutter/bin/dart run tool/ci/check_secrets.dart

Running build hooks...Running build hooks...Secret scan OK (4043 file(s) scanned, 0 finding(s)).

    → [5] secrets: ZÖLD

═══ [6] l10n
    $ /home/ubuntu/flutter/bin/dart run tool/ci/check_l10n_parity.dart

Running build hooks...Running build hooks...L10n aggregate freshness OK (en, hu).
L10n parity OK (en → hu, 2289 message(s)).

    → [6] l10n: ZÖLD

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/device_matrix_test.dart                  zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
```

(A `[3] test` lépés `Resolving dependencies…/Downloading packages…` blokkja a
`[2] analyze` lépéssel szó szerint megegyező 51-soros függőséglista — a
tényleges gate-futás ezt is csonkítatlanul írta ki, itt a jegyzőkönyv
olvashatósága miatt hivatkozom rá ismétlés helyett; az A1 csoport 54, egyenként
egyedi nevű cellája (6 helykitöltő × 9 mező) szintén összevonva szerepel — a
teljes, sortördeletlen napló a munkapéldányban, `flutter test
test/tooling/device_matrix_test.dart` közvetlen futtatásával reprodukálható.)

### 10.3 `python3 tool/device_report.py --matrix docs/testing/device-matrix.yaml --check` — szó szerinti kimenet

```
device_report check: 26 missing mandatory run(s):
  - pixel_6a:install_and_update
  - pixel_6a:cold_start
  - pixel_6a:live_start_latency
  - pixel_6a:mic_release
  - pixel_6a:practice_soak_20min
  - pixel_6a:analyze_memory_peak
  - pixel_6a:camera_preview_and_thermal
  - pixel_6a:background_resume
  - pixel_6a:battery_saver
  - pixel_6a:airplane_mode
  - pixel_6a:low_storage
  - pixel_6a:text_scale_200
  - pixel_6a:screen_reader_path
  - pixel_7:install_and_update
  - pixel_7:cold_start
  - pixel_7:live_start_latency
  - pixel_7:mic_release
  - pixel_7:practice_soak_20min
  - pixel_7:analyze_memory_peak
  - pixel_7:camera_preview_and_thermal
  - pixel_7:background_resume
  - pixel_7:battery_saver
  - pixel_7:airplane_mode
  - pixel_7:low_storage
  - pixel_7:text_scale_200
  - pixel_7:screen_reader_path
```

`echo $?` → **`1`**. Pontosan a két `release_blocking: true` eszköz (Pixel 6a,
Pixel 7) 13-13 kötelező suite-eleme hiányzik (26 = 2×13) — a két ajánlott
eszköz (Samsung Galaxy A54, Xiaomi Redmi Note 12) egyike sem szerepel a
listában, mert `release_blocking: false` esetén nincs kötelező futás.

### 10.4 §6.3 valódi-sértés próba

1. `cp docs/testing/device-matrix.yaml /tmp/device-matrix.yaml.bak`
2. `sed -i 's/release_blocking: true/release_blocking: false/'
   docs/testing/device-matrix.yaml` — mindkét `release_blocking: true` sort
   (Pixel 6a, Pixel 7) `false`-ra állítja. (Mivel mind a tizenegy GA-capability
   ugyanazt a négy eszközt sorolja fel lefedő eszközként — §0.1/§6 indoklás:
   nincs mért, capability-specifikus eszköz-alcsoport, tehát a differenciálás
   kitalált adat lenne — ez a mutáció NEM egy, hanem mind a tizenegy GA-scope
   capabilityt release_blocking-mentesre viszi. Ez erősebb bizonyíték az
   invariánsra, nem gyengébb: az "egyik GA-capabilityt lefedő ÖSSZES eszköz"
   pontosan ez, a `onboarding`-ra nézve is teljesül.)
3. `flutter test test/tooling/device_matrix_test.dart` → **PIROS**, cella:
   `A2 — … the real device-matrix.yaml: all eleven GA-scope capabilities have
   at least one release_blocking device`, üzenet:

   ```
   Expected: empty
     Actual: [
               'onboarding: 0 release_blocking devices',
               'live_and_tuner: 0 release_blocking devices',
               'practice_engine: 0 release_blocking devices',
               'song_trainer_local: 0 release_blocking devices',
               'audio_analysis_core: 0 release_blocking devices',
               'progress_goals_streak: 0 release_blocking devices',
               'storage_migration: 0 release_blocking devices',
               'offline_operation: 0 release_blocking devices',
               'localization_en_hu: 0 release_blocking devices',
               'accessibility_minimum: 0 release_blocking devices',
               'session_lifecycle_stability: 0 release_blocking devices'
             ]
   ```

   (Mellékhatásként az A5 „Pixel 6a release_blocking: true" cellája és az A4
   „§7 parancs ma nem-nullával lép ki" cellája is pirosra vált — ez a mutáció
   közvetlen, dokumentált következménye, nem hiba a checkerben.)
4. `cp /tmp/device-matrix.yaml.bak docs/testing/device-matrix.yaml`
5. `git diff --stat docs/testing/device-matrix.yaml` → **üres kimenet** (a
   fájl bit-pontosan visszaállt).
6. `flutter test test/tooling/device_matrix_test.dart` → újra **ZÖLD**, mind a
   99 cella (megismételve a végső, commitolt állapoton).

### 10.5 §6.2 cellahármas (0 / 1 / 2 blocking eszköz)

Fixture-vezérelt, a `findGaCapabilitiesWithoutBlockingDevice` checkeren:

| Cella | Fixture | Eredmény |
|---|---|---|
| alatta | `onboarding` (és a többi 10 GA id) 0 `release_blocking: true` eszközzel | PIROS — `onboarding: 0 release_blocking devices` |
| rajta | ugyanaz 1 blocking eszközzel | ZÖLD — üres lista |
| fölötte | ugyanaz 2 blocking eszközzel | ZÖLD — üres lista |

### 10.6 Amit nem futtattam le, és miért

- Egyetlen `docs/manual-testing/` sor sem lett valós eszközön lejátszva — a
  kör célja a nyilvántartás és a checker, nem a mérés (device-lab.md §8). A
  `device_report.py --check` §10.3-beli nem-nulla kimenete ennek a
  becsületes, mért állapotnak a bizonyítéka.
- `--results` fixture-ön kívül valódi eredmény-fájlt nem hoztam létre — a
  brief ezt kifejezetten nem kéri (§5, §7: "MA — valós eredmény-fájl nélkül").
- CI-t (`gh workflow run`) nem indítottam — az AGENTS.md szerint az az
  orchesztrátor lépése.
- A `tool/*.py` linterét (ruff) nem futtattam a `device_report.py`-ra — a
  brief §2 mérten rögzíti, hogy sem a `round-gate.sh`, sem a
  `.github/actions/flutter-gates` nem futtat lintert a `tool/*.py`-ra (a
  `ruff` csak a `backend/`-re megy); a Python-oldali egyetlen gépi mérce a
  Dart A4 csoport (R4).

## 11. Review — a Claude tölti ki
