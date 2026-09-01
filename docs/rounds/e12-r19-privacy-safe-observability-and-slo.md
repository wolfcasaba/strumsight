# E12-R19 — Privacy-safe observability, SLO és release dashboard

- **Státusz:** READY (pre-flight lefutott 2026-09-01, kód újramérve: `main @ 877e356b`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 19
- **Kör-azonosító:** `E12-R19`
- **Branch:** `sonnet-impl/e12-r19-privacy-safe-observability-and-slo`
- **Előfeltétel:** `E12-R17` merge-elve (a telemetria-mezők a data-inventory bejegyzései) — TELJESÜLT (`3b49c501` óta a `main`-en)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** [`0484`](../adr/0484-privacy-safe-telemetry-contract-and-release-slo-schema.md) — a foglalótól kapott szám (lásd §0.0 R1); az előre kiosztott `0459` elavult.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "telemetry redaction opt-out SLO dashboard cohort unknown not success"` → a `halts/halted-20260813T040134.txt` (E06-R23 H-INDEP) és **[ADR 0418](../adr/0418-leaderboards-and-opt-in-competition.md)** (opt-in verseny-nézet, `verified`-only projekció). A telemetria opt-in/opt-out logikája ugyanezt a mintát követi: az alapállapot a NEM-küldés.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/core/logging/log_redactor.dart` és a `lib/core/network/redacted_log_interceptor.dart` MÉRT redakciós szabályait — az esemény-redakció ezeket ÚJRAHASZNÁLJA, nem ír melléjük második listát.

## 0.0 Pre-flight brief-revízió (2026-09-01, Claude) — KÖTELEZŐ OLVASNI

A brief 2026-08-27-én, előre készült (`main @ 9ca4a0dc`). A pre-flight a mai fán
(`main @ 877e356b`) újramérte az állításait. Az alábbi revíziók a kör **saját,
még nem merge-elt** artefaktumát érintik (ADR 0087 §2), tehát az orchestrátor
hatáskörében vannak.

**Visszakeresés (ADR 0312, szűkítve ELŐSZÖR):**
`--corpus lessons,halts,adr "telemetry event redaction consent opt-out no-op sink"`
→ [ADR 0132](../adr/0132-ai-tutor-privacy-and-consent.md) (a consent-flow és a
redakció külön körök felelőssége; „a döntés nem lazítható azért, hogy egy teszt
zöld legyen"), [ADR 0178](../adr/0178-vision-privacy-by-default.md) (a raw frame
a legérzékenyebb adat; elvetve az „opt-in mentés a termékben"),
[ADR 0217](../adr/0217-analysis-raw-audio-retention.md) (a nyers PCM
élettartam-korlátja). `--corpus lessons,halts "unknown metric not success …"` →
**[L549](../LESSONS.md#l549)** — *a metaadat MEGLÉTÉT mérni nem ugyanaz, mint a
JELENTÉSÉT érvényesíteni*: 33 zöld cella közül egy sem mérte a lényeget. Ez a
kör mérce-mátrixának (§6.1) vezérelve. Teljes korpuszon: az E12-R19 saját
brief-szakaszai és az SDD Ch12 fájllistája — új tartalom nélkül.

### R1 — Az ADR-szám `0459` → **`0484`**

`tools/round-slots.py reserve-adr --round E12-R19` → `0484`. Az előre kiosztott
`0459` elavult; ugyanez a csúszás mérve az E12-R16 (`0456`→`0477`), E12-R17
(`0457`→`0479`) és E12-R18 (`0458`→`0481`) körökben. A foglaló (`O_CREAT|O_EXCL`
marker) az EGYETLEN érvényes forrás — az `ls docs/adr | tail` alak tiltott
(prompt §1.0.1, `tools/tests/test_adr_numbering.py`).

### R2 — A §2 „mért tények" újramérve: két állítás pontosítva

| Brief §2 állítás | 2026-09-01 mérés |
|---|---|
| `lib/core/telemetry/` nem létezik | **igaz** (`ls` → No such file or directory) |
| `docs/analytics/` nem létezik | **igaz** |
| `docs/operations/` „MA egy Community runbookot tartalmaz" | **pontosítva:** HÁROM fájl — `backend-deploy.md`, `community-moderation-runbook.md`, `database-recovery.md`. Az `slo.yaml` és a `release-dashboard.md` tényleg hiányzik. |
| `test/privacy/` létezik | **igaz** (`consent_enforcement_test.dart`) |
| `backend/app/telemetry/` nem létezik | **igaz** — a kör kliens-oldali |

### R3 — MÉRVE: telemetria-consent kapcsoló MA NEM LÉTEZIK → a consent INJEKTÁLT

`grep -rn "analyticsConsent\|telemetryConsent" lib/ --include=*.dart` → **nulla
találat**; a `docs/privacy/data-inventory.yaml` öt valódi route-ja
(`account_api`, `diagnostics_upload`, `tutor_stream`, `community_media`,
`share_export`) közül egyik sem telemetria.

**Következmény, ami KÖT:** a `telemetry_sink.dart` a hozzájárulást
**konstruktor-paraméterként / injektált olvasóként** kapja. TILOS provider,
`SharedPreferences`, settings-repository vagy bármely `lib/features/**` hivatkozás
— az a scope-sértés (STOP-protokoll, §0.1) ÉS egy második consent-igazságforrás
lenne (az [L555](../LESSONS.md#l555) hibaosztálya). A telemetria data-inventory
route-jának felvétele **külön kör** (`docs/privacy/**` nincs az engedélyezett
listán).

### R4 — Az A1 „típus-szintű cella" MÉRT alakja: FORRÁS-SZKEN, nem reflexió

A `flutter_test` alatt nincs `dart:mirrors`, tehát „ebbe a típusba nem fér bele
szabad szöveg" futásidőben nem állítható. A fán MÉRT precedens a forrás-szken:
`test/tooling/legacy_identifier_guard_test.dart`,
`test/tooling/repository_policy_test.dart`,
`test/tooling/screen_reachability_test.dart` (mind `Directory.current`-ből olvas
valódi forrást). Az A1 cella tehát **beolvassa** a
`lib/core/telemetry/telemetry_event.dart` forrását, és pirosra vált, ha megjelenik
benne `Map<String, dynamic>`, `dynamic`, `Object?`-értékű payload-mező vagy
szabad `String` mező, amely nem zárt szótárból (enum) származik.

### R5 — Az A5 séma-cella MÉRT alakja: kézi sor-parszer, mert nincs `yaml` csomag

`pubspec.yaml` `dev_dependencies`: **csak** `flutter_test` + `flutter_lints ^6.0.0`
— `yaml` csomag NINCS deklarálva, és a kör nem adhat hozzá (a `pubspec.*` nincs
az engedélyezett listán). A `package:yaml` a lock-fájlban TRANZITÍVAN jelen van
(`yaml 3.1.3`, mérve a `flutter pub get` kimenetén), de a **közvetlen importja
TILOS**: nem deklarált függőség (`depend_on_referenced_packages`), és a
tranzitív jelenlét bármely upstream frissítéssel elillanhat. A fán MÉRT precedens: `tool/check_data_inventory.dart`
saját, `RegExp`-alapú sor-parszere (`^  - id:\s*(.*)$` stb.), amit a
`test/tooling/data_inventory_test.dart` valódi fán futtat. Az A5 cella
UGYANEZT csinálja a `docs/operations/slo.yaml`-lel, a teszt-fájlon belüli
minimál-parszerrel. Ezért a `slo.yaml`-nak **géppel olvasható, lapos** alakúnak
kell lennie (kétszintű behúzás, listaelemek `- id:` kezdettel), nem
tetszőleges YAML-nek.

### R6 — KÖTELEZŐ tiltás: a telemetria-fájlok nem lehetnek hálózat-alakúak

`tool/check_data_inventory.dart` a `lib/**` fán EGRESS-útvonalat fedez fel a
következő mintákra: `DioFactory.create<Név>Client`, `Dio`-típusú mező/paraméter
+ kérés-ige hívás, `ApiClient`-típusú tag + kérés-ige, `HttpClient(`,
`package:http` ige, `SharePlus`. A `test/tooling/data_inventory_test.dart` A2
cellája a VALÓDI fán keresztellenőrzi ezt a `docs/privacy/data-inventory.yaml`
ellen — ez a cella **nincs** a §7 gate-ben, de **benne van a teljes CI-suite-ban**.

**Következmény:** ha a `lib/core/telemetry/**` bármelyik fájlja `Dio`-t,
`ApiClient`-et, `HttpClient(`-et, `package:http`-t vagy `SharePlus`-t említ
típusként vagy hívásként, a teljes CI PIROS lesz egy olyan cellán, amit a
kör-gate nem mutat meg. Ez a §0.1 „semmit nem küld hálózatra" kikötésének
GÉPI őre — és egyben az egyetlen mért módja, hogy ez ne csak szándék legyen.

### R7 — A `LogRedactor` MÉRT felülete (A2: nincs második lista)

`lib/core/logging/log_redactor.dart` — `abstract final class LogRedactor`,
újrahasznosítandó tagok: `fields(Map<String, Object?>)`, `value(String, Object?, [int])`,
`text(String)`, `isSensitiveKey(String)`, `redacted`, `redactedEmail`,
`redactedToken`, `maxStringLength = 200`, `maxNumberListLength = 16`,
`maxDepth = 4`, `sensitiveKeyFragments` (22 elem: `password`, `token`, `jwt`,
`authorization`, `auth`, `secret`, `apikey`, `credential`, `cookie`, `session`,
`signature`, `pcm`, `audio`, `wav`, `clip`, `samples`, …).

**KÖT:** a `telemetry_redactor.dart` ezeket HÍVJA. Saját minta-lista, saját
kulcs-szótár vagy a fenti konstansok újradeklarálása **A2-sértés** — az
importált `lib/core/logging/**` **olvasása** megengedett (import), **módosítása**
tilos zóna.

### R8 — Az `allowed_paths` felsorolja a kör SAJÁT ADR-jét

Az ADR-t a pre-flightban az orchestrátor írja (ADR 0055, prompt §1.0.1), a §3
pedig pontosan ezért zárja ki az implementer scope-jából. A gépi
`tools/scope-audit.py` ezt a megkülönböztetést nem tudja kifejezni, ezért a
fájlnak szerepelnie KELL az `allowed_paths`-ban, különben a scope-audit
`VIOLATION`-t ad egy protokoll szerint kötelező artefaktumra (MÉRVE: E12-R18
§0.0 R6). **Ez nem munkaszcope-tágítás:** az implementer engedélyezett listája
változatlanul a §4 táblázata, a `docs/adr/**` az ő számára TILOS zóna marad.

### R9 — A gate_tests kiegészült a `docs/`-őrökkel

A kör három ÚJ dokumentumot hoz létre (`docs/analytics/event-catalog.md`,
`docs/operations/slo.yaml`, `docs/operations/release-dashboard.md`). A §7
gate-sor változatlan marad (a két teszt-útvonal), mert az A5 cellája a
`telemetry_redaction_test.dart`-ban él és onnan olvassa a `slo.yaml`-t —
külön dokumentum-teszt nem készül, hogy ne legyen második igazságforrás.

## 0.1 A kör határa: szerződés és redakció, nem szolgáltató

A kör NEM köt be külső analytics-szolgáltatót és nem küld semmit hálózatra. Amit szállít: a typed esemény-katalógus, a redakciós és consent-kapu, valamint a dashboard/SLO BEMENETI sémája. A tényleges gyűjtés bekapcsolása a rollout-körök (31–33) user-döntése, és feature-flag mögött marad.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/telemetry/telemetry_event.dart",
  "lib/core/telemetry/telemetry_redactor.dart",
  "lib/core/telemetry/telemetry_sink.dart",
  "lib/core/telemetry/public.dart",
  "test/core/telemetry/telemetry_redaction_test.dart",
  "docs/analytics/event-catalog.md",
  "docs/operations/slo.yaml",
  "docs/operations/release-dashboard.md",
  "docs/rounds/e12-r19-privacy-safe-observability-and-slo.md",
  "docs/adr/0484-privacy-safe-telemetry-contract-and-release-slo-schema.md",
]
gate_tests = [
  "test/core/telemetry/telemetry_redaction_test.dart",
  "test/privacy/consent_enforcement_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a telemetria a felhasználói tanulási tartalom közelében dolgozik (prompt, hang, videó, szabad szöveg) — egy hiányos redakció érzékeny adatot vinne ki. A `security-reviewer` futtatása a review-ban KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a bekötés a `lib/features/**` érintését igényelné (esemény-kibocsátás beépítése), a kimenet a `stopped` jelzés — a feature-oldali kibocsátás külön kör.

## 1. Cél

Olyan telemetria-szerződés, amely érzékeny tartalmat elvileg sem tud kivinni, opt-out mellett bizonyíthatóan no-op, és amelyből SLO/dashboard-bemenet készíthető — az `unknown` állapot pedig sosem számít sikernek.

## 2. Jelenlegi állapot — mért tények

- `lib/core/telemetry/` **nem létezik**. A meglévő rokon réteg: `lib/core/logging/{app_logger,debug_app_logger,log_redactor,logger_provider}.dart` és `lib/core/network/redacted_log_interceptor.dart`.
- `lib/features/diagnostics/` MA opt-in, Lab-módhoz kötött diagnosztikai feltöltést végez (`diagnostics_uploader.dart`) — ez a MÉRT precedens az „alapból nem küld" mintára.
- `docs/analytics/` és `docs/operations/slo.yaml` **nem létezik**; `docs/operations/` MA egy Community runbookot tartalmaz.
- `backend/app/telemetry/` **nem létezik** — ez a kör a KLIENS-oldali szerződést szállítja; a backend-oldali gyűjtés külön kör.
- `test/privacy/` a Kör 17 után létezik.

## 3. Scope

**Benne van:** `telemetry_event.dart` (typed esemény: név, kategória, művelet-eredmény, időtartam-BUCKET, capability-metaadat — szabad szöveges mező NEM megengedett a típusban) · `telemetry_redactor.dart` (a `log_redactor.dart` szabályainak újrahasználata + a nyers prompt/audio/videó/„felhasználói szöveg" mezők STRUKTURÁLIS tiltása) · `telemetry_sink.dart` (interfész; az alapértelmezett implementáció opt-out mellett NO-OP, hálózat nélkül) · `docs/analytics/event-catalog.md` · `docs/operations/slo.yaml` (a core SLO-k és küszöbeik) · `docs/operations/release-dashboard.md` (bemeneti séma, cohort-szűrő, `unknown` kezelés).

**NINCS benne (tilos):**

- Külső analytics SDK vagy hálózati küldés.
- `lib/features/**` érintése (esemény-kibocsátás bekötése).
- Backend-oldali telemetria-végpont.
- `docs/adr/**` — az ADR 0459-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/core/telemetry/telemetry_event.dart` | ÚJ — typed esemény |
| `lib/core/telemetry/telemetry_redactor.dart` | ÚJ — redakció a MEGLÉVŐ szabályokra építve |
| `lib/core/telemetry/telemetry_sink.dart` | ÚJ — sink-interfész, no-op alapértelmezéssel |
| `lib/core/telemetry/public.dart` | ÚJ — barrel |
| `test/core/telemetry/telemetry_redaction_test.dart` | a §6 cellái |
| `docs/analytics/event-catalog.md` | ÚJ — esemény-katalógus |
| `docs/operations/slo.yaml` | ÚJ — SLO-k |
| `docs/operations/release-dashboard.md` | ÚJ — dashboard-bemenet |
| `docs/rounds/e12-r19-privacy-safe-observability-and-slo.md` | a §10 handoff kitöltése |

**Tilos zóna (az implementer számára):** `lib/features/**` · `lib/core/logging/**` (olvasni/importálni SZABAD, írni TILOS) · `lib/core/network/**` · `backend/**` · `.github/**` · `docs/adr/**` (a `0484`-et a Claude írta a pre-flightban — lásd §0.0 R8) · `docs/privacy/**` · `pubspec.*` · `tool/**`

## 5. Kötött architekturális döntések ([ADR 0484](../adr/0484-privacy-safe-telemetry-contract-and-release-slo-schema.md))

> A §5.1–§5.5 az ADR 0484 **D1–D5** döntéseinek rövid alakja. Ütközés esetén az
> ADR szövege az irányadó.

### 5.1 A tiltás STRUKTURÁLIS, nem szűrő

A typed eseményben nincs olyan mező, amibe nyers prompt, hang, kép vagy szabad felhasználói szöveg beleférne — a redakció a második védelmi vonal, nem az első. **NEM elfogadható gyengítés:** általános `Map<String, dynamic> payload` mező „a rugalmasság kedvéért".

### 5.2 Opt-out mellett a sink NO-OP, nem pufferel

**NEM elfogadható gyengítés:** „gyűjtsük, és majd ha hozzájárul, elküldjük" — az a hozzájárulás előtti gyűjtés.

### 5.3 Az `unknown` NEM zöld

A dashboard-sémában a hiányzó metrika `unknown`, és a release-döntésben ez NEM sikeres állapot (a Kör 14 §5.2 szabályával egyezően — `tool/compare_benchmarks.py`). **NEM elfogadható gyengítés:** hiányzó metrika kihagyása az összesítésből.

### 5.4 A consent INJEKTÁLT, nem szerzett (§0.0 R3)

A sink a hozzájárulást konstruktor-paraméterként vagy injektált olvasóként kapja.
**NEM elfogadható gyengítés:** provider, `SharedPreferences` vagy
settings-repository olvasása a `lib/core/telemetry/**`-ból — ma nincs
telemetria-consent kapcsoló a fán, tehát bármely ilyen hivatkozás egy MÁSODIK
igazságforrást hozna létre, és scope-sértés is (`lib/features/**`).

### 5.5 A telemetria-réteg szerkezetileg hálózat-képtelen (§0.0 R6)

A `lib/core/telemetry/**` fájljai nem hivatkozhatnak `Dio`-ra, `ApiClient`-re,
`HttpClient(`-re, `package:http`-ra vagy `SharePlus`-ra — sem típusként, sem
hívásként, sem importként. **NEM elfogadható gyengítés:** „csak egy interfész,
sosem hívjuk meg". A `tool/check_data_inventory.dart` egress-felfedezése
pontosan ezekre a mintákra épül, és a
`test/tooling/data_inventory_test.dart` A2 cellája a teljes CI-ban pirosra vált.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték (a MÉRT alakkal — §0.0 R4/R5) |
|---|---|---|
| A1 | A typed eseménybe szabad szöveges/nyers tartalom szerkezetileg nem tehető | `telemetry_redaction_test.dart` **forrás-szken cellája**: beolvassa `lib/core/telemetry/telemetry_event.dart`-ot (`Directory.current`-ből) és pirosra vált `Map<String, dynamic>` / `dynamic` / `Object?` payload-mezőre, vagy zárt szótárból nem származó szabad `String` mezőre |
| A2 | A redaktor a MEGLÉVŐ `log_redactor` szabályait alkalmazza (token, e-mail, hosszú szöveg) | `telemetry_redaction_test.dart`: (a) viselkedés — JWT/`Bearer …`/e-mail/`>200` karakteres érték és `token`-szerű kulcs redaktálva; (b) forrás-szken: `telemetry_redactor.dart` importálja és HÍVJA a `LogRedactor`-t, és nem deklarál saját kulcs-szótárat/regexet |
| A3 | Opt-out mellett a sink NO-OP: nem tárol és nem pufferel | `telemetry_redaction_test.dart`: rögzítő fake delegate **0** eseményt kap; és consent `false → true` váltás után a korábban eldobott események **NEM** kerülnek ki (nincs utólagos flush) |
| A4 | Időtartam bucket-ként, nem nyers ezredmásodpercként kerül az eseménybe | `telemetry_redaction_test.dart`: küszöb-cellahármas + forrás-szken (nincs `int`/`Duration` nyers ms mező az eseményen) |
| A5 | A dashboard-séma hiányzó metrikát `unknown`-ként jelöl, és ez nem `success` | `telemetry_redaction_test.dart` séma-cellája: **beolvassa és parszolja** `docs/operations/slo.yaml`-t (teszt-lokális `RegExp` sor-parszer), és állítja: minden SLO deklarál `on_missing: unknown`-t, az `unknown` egyetlen SLO-nál sem szerepel a sikeres/zöld verdikt-halmazban, és minden deklarált SLO kötelező a release-összesítésben |
| A6 | A Kör 17 consent-cellái VÁLTOZATLANUL zöldek | a §7 gate (`test/privacy/consent_enforcement_test.dart`) |
| A7 | A telemetria-réteg szerkezetileg hálózat-képtelen (§5.5) | `telemetry_redaction_test.dart` forrás-szken cellája a `lib/core/telemetry/` MINDEN `.dart` fájljára: nincs `Dio`, `ApiClient`, `HttpClient(`, `package:http`, `SharePlus` említés |

**Az időtartam-bucket határai (KÖTÖTT, `python3`-mal kiszámolva):**
`[0,250) [250,500) [500,1000) [1000,3000) [3000,10000) [10000,∞)` — a határ
**INKLUZÍV az ALSÓ oldalon**.

**Küszöb-cellahármas az `1000 ms` határra** (mérve:
`python3 -c "b=[0,250,500,1000,3000,10000]; …"`):

| Bemenet | Elvárt bucket |
|---|---|
| `999` ms (a küszöb **alatt**) | `[500,1000)` |
| `1000` ms (**pontosan rajta**) | `[1000,3000)` |
| `1001` ms (a küszöb **fölött**) | `[1000,3000)` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az esemény kap egy általános `payload` mapet | A1 |
| A redaktor saját kulcs-listát/regexet deklarál a `LogRedactor` helyett | A2 (b) forrás-szken |
| Opt-out mellett a sink memóriában gyűjt | A3 (0-esemény cella) |
| A sink pufferel, és consent-váltáskor utólag kiküldi | A3 (nincs-flush cella) |
| A nyers ezredmásodperc kerül az eseménybe | A4 forrás-szken |
| A hiányzó metrika kimarad, és a dashboard zöld | A5 |
| Az `unknown` bekerül a zöld verdikt-halmazba | A5 |
| A bucket-határ kizáró, így a pontosan 1000 ms rossz bucketbe esik | a küszöb-cellahármas „pontosan rajta" cellája |
| A sink `Dio`/`ApiClient` mezőt kap „a későbbi bekötéshez" | A7 (és a teljes CI-ban `data_inventory_test.dart` A2) |

> **[L549](../LESSONS.md#l549) alkalmazva:** minden cella a JELENTÉST méri, nem a
> mező MEGLÉTÉT. Nem elég, hogy van `unknown` konstans — mérni kell, hogy nem
> zöld; nem elég, hogy van `DurationBucket` — mérni kell a határ inkluzivitását.

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki a sink opt-out ágát (mindig gyűjtsön), futtasd a §7 gate-et → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/telemetry/telemetry_redaction_test.dart test/privacy/consent_enforcement_test.dart
```

## 8. Implementációs sorrend

1. `telemetry_event.dart` — a strukturális tiltással.
2. `telemetry_redactor.dart` — a meglévő szabályok újrahasználata.
3. `telemetry_sink.dart` — no-op alapértelmezés.
4. `telemetry_redaction_test.dart` — a küszöb-cellahármassal.
5. `docs/analytics/event-catalog.md`, `docs/operations/slo.yaml`, `release-dashboard.md`.
6. A valódi-sértés próba a §10-be.

### 8.1 A `docs/operations/slo.yaml` KÖTÖTT alakja (§0.0 R5)

Nincs `yaml` csomag a fán, ezért a fájl **lapos, géppel olvasható** alakú. A
kulcsok kötelezőek, a behúzás pontosan az alábbi (a teszt-lokális parszer ezt a
szerkezetet olvassa):

```yaml
schema_version: 1
# Az `unknown` SOHA nem sikeres állapot (ADR 0484 D3).
verdict_values: [success, degraded, breach, unknown]
success_verdicts: [success]
blocking_verdicts: [degraded, breach, unknown]
slos:
  - id: <gépi azonosító>
    title: <egy sor>
    metric: <a mérendő mennyiség>
    objective: <küszöb, mértékegységgel>
    window: <időablak>
    required: true
    on_missing: unknown
    source: <MELYIK mérés/artefaktum adja — létező útvonal vagy kör>
```

Kötelező invariánsok (az A5 cella ezeket méri):
`unknown ∉ success_verdicts`, `unknown ∈ blocking_verdicts`, minden SLO-nál
`on_missing: unknown` és `required: true`, és minden `slos[].id` egyedi.
A `docs/operations/release-dashboard.md` a bemeneti sémát (metrika-sor, cohort-szűrő
mezők, `unknown` kezelés) EHHEZ a fájlhoz köti, nem ismétli meg a küszöböket.

## 9. Kockázatok

- **A rugalmas payload csapdája.** Egy `Map<String, dynamic>` minden strukturális védelmet kinyit (A1).
- **Kettős redakciós lista.** A `log_redactor` mellé írt második lista szétcsúszik (A2).
- **A hiányzó metrika zöldre fordítása.** Ugyanaz a hibaosztály, mint a Kör 14-ben és 16-ban (A5).

## 10. Implementation handoff — az implementer tölti ki

**Motor:** `sonnet-impl` (Claude Sonnet 5, `--effort medium`). A §4 engedélyezett-fájllistán kívül semmit nem érintettem.

### Szállított fájlok

| Fájl | Tartalom |
|---|---|
| `lib/core/telemetry/telemetry_event.dart` | `TelemetryEvent` + öt zárt enum (`TelemetryEventName`, `TelemetryEventCategory`, `TelemetryOperationResult`, `TelemetryCapability`, `TelemetryDurationBucket`). Az eseményen **kizárólag enum mezők** vannak (nincs `String`, `int`, `Duration`, `Map`, `dynamic`, `Object?`) — ez szigorúbb, mint amit az A1/A4 forrás-szken megkövetel, hogy a cellák egyértelműen ne ütközzenek egymással. A `TelemetryDurationBucket.fromMilliseconds` a küszöb-cellahármas alsó-inkluzív logikáját valósítja meg (első találat `milliseconds < upperExclusiveMs` alapján, felfelé haladva). |
| `lib/core/telemetry/telemetry_redactor.dart` | `TelemetryRedactor` — vékony wrapper, kizárólag a `LogRedactor.fields/text/isSensitiveKey`-t hívja. Nincs saját `RegExp` vagy `Set<String>` deklaráció. |
| `lib/core/telemetry/telemetry_sink.dart` | `TelemetrySink` interfész, `NoopTelemetrySink`, `ConsentGatedTelemetrySink` (a hozzájárulást `bool Function() consentGranted` konstruktor-paraméterként kapja; opt-out mellett a `record()` semmit nem tárol/pufferel). |
| `lib/core/telemetry/public.dart` | barrel export a fenti három fájlhoz. |
| `test/core/telemetry/telemetry_redaction_test.dart` | Az A1, A2, A3, A4, A5, A7 cellák EBBEN az egy fájlban (A6 változatlanul a meglévő `test/privacy/consent_enforcement_test.dart`-ban). Két helyi segédfüggvény: `_withoutCommentsAndStrings` (komment/string-literál kiürítés a forrás-szken cellákhoz, hogy a doc-comment szövege ne adjon hamis találatot) és a `docs/operations/slo.yaml` kézi sor-parszere (`_parseSloYaml`, a `tool/check_data_inventory.dart` mintáját követve). |
| `docs/analytics/event-catalog.md` | A `telemetry_event.dart` enumjainak emberi-olvasható katalógusa — szinkronban tartandó a Dart fájllal. |
| `docs/operations/slo.yaml` | 5 SLO (`chord_detection_latency_p95`, `tuner_pitch_accuracy`, `offline_egress_free`, `crash_free_sessions`, `tutor_turn_success_rate`), mind `required: true` + `on_missing: unknown`; `unknown ∉ success_verdicts`, `unknown ∈ blocking_verdicts`. |
| `docs/operations/release-dashboard.md` | Bemeneti séma (metrika-sor, cohort-szűrő, `unknown`-kezelés), a küszöböket NEM ismétli meg — a `slo.yaml`-ra mutat. |

### Valódi-sértés próba (§6, KÖTELEZŐ) — elvégezve

1. Kivettem a `ConsentGatedTelemetrySink.record()` opt-out ágát (`if (!consentGranted()) return;` törölve — mindig gyűjt).
2. `tools/round-gate.sh test/core/telemetry/telemetry_redaction_test.dart test/privacy/consent_enforcement_test.dart` → **PIROS**, kilépési kód 1, kizárólag a `test test/core/telemetry/telemetry_redaction_test.dart` lépésen, azon belül pontosan az **A3** csoport mindkét cellája:
   - `A3 … record() with consent=false never reaches the delegate` — `Expected: empty / Actual: [Instance of 'TelemetryEvent', Instance of 'TelemetryEvent']`
   - `A3 … events dropped while consent was false are NOT flushed after consent flips true …` — `Expected: empty / Actual: [Instance of 'TelemetryEvent']`
   Minden más cella (A1, A2, A4, A5, A7, A6) zöld maradt — a sértés pontosan az A3-at találta el, semmi mást.
3. Visszaállítottam az opt-out ágat, újrafuttattam a gate-et → **MINDEN GATE ZÖLD** (format, analyze, mindkét teszt-útvonal, architecture, secrets, l10n).

### Eltérések a brieftől

- Nincs eltérés az engedélyezett-fájllistától vagy a §5 kötött döntésektől.
- A `TelemetryEvent`-en nem szerepel semmilyen `int`/`Duration` mező (a brief csak a "raw ms" mezőt tiltja explicit) — szándékosan szigorúbb választás, hogy az A1 és A4 forrás-szken egyértelműen, átfedés nélkül mérje a saját kritériumát.
- A `docs/operations/slo.yaml` két SLO-jának (`crash_free_sessions`, `tutor_turn_success_rate`) `source` mezője a jövőbeli 31–33. rollout-körre mutat, mert a gyűjtés bekapcsolása explicit KÉSŐBBI kör (ADR 0484 §0.1) — ez nem hiányosság, hanem a `unknown`/`on_missing` szabály pontosan erre az esetre való: amíg a gyűjtés nincs bekötve, a dashboard ezeket a sorokat `unknown`-ként (blokkoló) fogja jelenteni, sosem `success`-ként.

## 11. Review — a Claude tölti ki
