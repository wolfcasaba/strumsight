# E12-R19 — Review (Claude, Opus 5) — VÉGSŐ DÖNTÉS: APPROVED

> **Frissítve 2026-09-01, a javító kör #1 (`bbf7c3a1`) után.** Az eredeti,
> CHANGES REQUESTED verdiktű jelentés alább változatlanul olvasható; a zárás
> lelet-soronkénti, ÚJRAMÉRT ellenőrzése a **§7**-ben. **Nyitott lelet: 0.**

- **Kör:** `E12-R19` — Privacy-safe observability, SLO és release dashboard
- **Ág:** `sonnet-impl/e12-r19-privacy-safe-observability-and-slo`
- **Diff:** `a96dceaf..fb210553` — 9 fájl, +912 / −0
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5)
- **Reviewer:** Claude Opus 5 (orchestrátor) + `security-reviewer` ügynök (a kör
  `risk = "high"`, ADR 0171 szerint kötelező)
- **Dátum:** 2026-09-01
- **Verdikt:** **CHANGES REQUESTED** — 0 BLOCKER, **2 MAJOR**, 5 MINOR, 4 NOTE

## 0. Mérési lánc (amit MAGAM futtattam, nem bemondásra vettem át)

| # | Mérés | Eredmény |
|---|---|---|
| M1 | `tools/round-gate.sh test/core/telemetry/telemetry_redaction_test.dart test/privacy/consent_enforcement_test.dart` izolált `/tmp/review-e12-r19` klónban | **EXIT=0**, mind a 7 lépés (format, analyze, mindkét teszt, architecture, secrets, l10n) ZÖLD |
| M2 | `tools/scope-audit.py --repo … --brief … --base a96dceaf` | `Legacy scope audit OK (9 changed path(s), 0 generated/ignored)` |
| M3 | Router CI a kör HEAD-jén (`fb210553`) | `conclusion=success` (run `33527050724`) |
| M4 | **Mutációs próba**: `final Map<String, String>? attributes;` a `TelemetryEvent`-en | **15/15 ZÖLD** — az A1 NEM fogja |
| M5 | **Mutációs próba**: `final List<String>? tags;` | **15/15 ZÖLD** — az A1 NEM fogja |
| M6 | **Mutációs próba**: `final double? durationMs;` (nyers ezredmásodperc!) | **15/15 ZÖLD** — az A4 NEM fogja |
| M7 | Kontroll: `final Map<String, dynamic>? payload;` | **PIROS** (1 bukott cella) — a szó szerinti alakot fogja |
| M8 | **Mutációs próba**: 6. SLO 4-szóközös behúzással, `required: false`, `on_missing: success` | **15/15 ZÖLD** — az A5 némán ELDOBJA az SLO-t |
| M9 | **Mutációs próba**: a `success_verdicts:` sor törlése a `slo.yaml`-ből | **15/15 ZÖLD** — az „unknown nem success" állítás vákuumban teljesül |
| M10 | **Mutációs próba**: `static const List<String> extraSensitiveKeys = [...]` a `telemetry_redactor.dart`-ban | **15/15 ZÖLD** — az A2(b) NEM fogja |

A próbák eldobhatók voltak, a klón a végén `git status --short` szerint tiszta.

## 1. Ami RENDBEN van

- **A kód maga helyes.** A `TelemetryEvent` (`telemetry_event.dart:91-105`) öt
  mezője MIND zárt enum; nincs `toString()`/`toJson()` override, nincs
  azonosító-mező (session/user/screen), tehát korrelációs vektor sincs.
- **D2 teljesül:** a `telemetry_redactor.dart` egyetlen importja a
  `log_redactor.dart`, három tagja átadó (`:18-19,23,26`); nincs saját
  `RegExp`/`Set`/konstans.
- **D4 teljesül szerkezetileg:** a `ConsentGatedTelemetrySink` (`:35-49`) `const`
  konstruktorú, két `final` mezővel — puffer fizikailag nem létezik; a consent
  minden híváskor frissen olvasva (`:46`), injektált `bool Function()`.
- **D5 teljesül a kódban:** egyetlen tiltott hálózati token sem szerepel a
  `lib/core/telemetry/**` kódjában (a `LogRedactor` maga import nélküli, tehát
  tranzitív egress sincs).
- **A küszöb-cellahármas helyes:** 999 → `[500,1000)`, 1000 → `[1000,3000)`,
  1001 → `[1000,3000)` — az alsó-inkluzív határ mérve.
- **A §10 valódi-sértés próba hiteles:** az A3 cellák szerkezete alátámasztja a
  jelentett PIROS-t, és a fán most 15/15 zöld.
- **A dokumentumok jó minőségűek:** a `release-dashboard.md` NEM ismétli meg a
  küszöböket (a `slo.yaml`-ra mutat), az esemény-szintű `unknown` és a
  verdikt-szintű `unknown` különbsége explicit dokumentálva.

## 2. MAJOR-1 — Az A1/A4 őr típusnév-DENYLIST, nem enum-ALLOWLIST

**Hely:** `test/core/telemetry/telemetry_redaction_test.dart:19-49` (A1),
`:184-203` (A4), a segédminta `:358-361`.
**Sértett szabály:** ADR 0484 **D1**, brief §5.1, és a brief **§6.1 mérce-mátrix
1. és 5. sora** („Az esemény kap egy általános `payload` mapet → **A1**", „A
nyers ezredmásodperc kerül az eseménybe → **A4**").

**Mért bizonyíték (M4/M5/M6, a VALÓDI teszttel a valódi fán):**

| Mutáns a `TelemetryEvent`-en | Eredmény |
|---|---|
| `final Map<String, String>? attributes;` | **15/15 zöld — túléli** |
| `final List<String>? tags;` | **15/15 zöld — túléli** |
| `final double? durationMs;` | **15/15 zöld — túléli** |
| `final Map<String, dynamic>? payload;` (kontroll) | piros ✓ |

**Miért csúszik át:** a `_freeTypedFieldPattern('String')` a `final String x;` /
`String x,` / `String x)` ALAKOT keresi. A `Map<String, String>? attributes;`
sorban az első `String` után vessző, a második után `>` áll, a `List<String>?`
után `?` — egyik sem illeszkedik. A `\bdynamic\b` és `Object\?` minták pedig
csak a szó szerinti alakot fogják.

**A hibaosztály:** a cella azt tiltja, amit a szerző ELŐRE elképzelt
(denylist), miközben az ADR állítása POZITÍV: „minden mező zárt enum". Ez
pontosan az [L549](../LESSONS.md#l549) hibaosztálya — az őr a MEGLÉTET méri
(„nincs `dynamic` a fájlban"), nem a JELENTÉST („minden mező zárt szótárból
jön"). Egy jövőbeli kör jóhiszeműen felveheti a `Map<String, String> attributes`
mezőt („nem `dynamic`, tehát nem sérti a D1 betűjét"), amibe prompt-részlet,
dalcím, fájlnév vagy URL kerül — és a kör mércéje zölden átengedi.

**Javítás iránya (NEM kész patch):** a cella állítsa az ALLOWLIST-et. A
`_extractClassBody(source, 'TelemetryEvent')` (`:366-381`) MÁR megvan: iterálj a
`final <Típus> <név>;` deklarációkon, és követeld meg, hogy minden `<Típus>` (a
`?`-t leszámítva) a `Telemetry*` enumok halmazába essen. Egy állítás, ami a
`Map`, `List`, `double`, `DateTime`, `Uri` és minden jövőbeli szabad típus ellen
egyszerre zár. A `dynamic`/`Object?`/`Map<String,dynamic>` meglévő cellái
maradhatnak — az allowlist mellett olcsó, beszédes hibaüzenetet adnak.

**A javítás mércéje:** a fenti négy mutáns MINDEGYIKÉNEK pirosnak kell lennie a
javítás után, és a javítás ELŐTTI teszttel zöldnek — ezt a javító körnek
dokumentálnia kell (a mutation-kill a mérce, nem a zöld gate,
[L563](../LESSONS.md#l563)).

## 3. MAJOR-2 — Az A5 `slo.yaml`-parszer fail-OPEN: egy SLO némán eltűnhet

**Hely:** `test/core/telemetry/telemetry_redaction_test.dart:417-502`
(`_parseSloYaml`), a cellák `:206-246`.
**Sértett szabály:** ADR 0484 **D3**, brief §5.3, és a brief **§6.1 mérce-mátrix
4. sora** („A hiányzó metrika kimarad, és a dashboard zöld → **A5**").

**Mért bizonyíték (M8, a VALÓDI teszttel):** a `slo.yaml` végére 4-szóközös
behúzással írt hatodik SLO —

```yaml
    - id: extra_unguarded_slo
      required: false
      on_missing: success
```

— a `sloStartPattern` (`^  - id:`) mellett nem illeszkedik, a `sloKvPattern`
(`^    (\w+):`) sem fogja meg (a `-` nem `\w`), ezért a parszer **némán
eldobja**. Az öt A5 cella mind ZÖLD marad, holott a fájlban most ott van egy
`required: false` + `on_missing: success` SLO — pontosan az az állapot, aminek a
tiltása a D3 létezési oka.

**Másodlagos fail-open (M9):** a `success_verdicts:` sor törlésekor a lista
`const []`-re esik vissza, így az `expect(doc.successVerdicts.contains('unknown'),
isFalse)` **vákuumban** teljesül. (A `verdict_values` és `blocking_verdicts`
hiányát a másik két cella helyesen pirosítja — ez a rés csak a success-listára
áll fenn.)

**Javítás iránya:** a parszer legyen fail-CLOSED, a `tool/check_data_inventory.dart`
mintája szerint: (a) a parszolt SLO-k száma egyezzen a nyers
`- id:` előfordulások számával (`RegExp(r'^\s*- id:', multiLine: true)`) —
eltérés → a cella PIROS, a nem értelmezett sorok kiírásával; (b)
`expect(doc.successVerdicts, ['success'])` a puszta „nem tartalmaz unknown"
helyett; (c) `schema_version == 1` ellenőrzése, hogy egy jövőbeli
séma-átalakítás ne csendben avulttá tegye a parszert.

**A javítás mércéje:** a fenti két mutáns (rossz behúzású SLO, törölt
`success_verdicts`) legyen PIROS a javítás után.

## 4. MINOR

### MINOR-1 — Az A1/A4 EGY fájlt szken, az A7 az egész könyvtárat

`:22` és `:187` kőbe vésett `File('lib/core/telemetry/telemetry_event.dart')`,
míg az A7 (`:261-263`) `Directory(...).listSync(recursive: true)`. Egy testvér
fájlban felvett `TelemetryContext { final Map<String, dynamic> data; }` típust az
A1/A4 el sem olvassa. Javítás: az A1/A4 is iteráljon a könyvtáron (az A7 mintája
kész).

### MINOR-2 — Az A2(b) „nincs második lista" őre két szintaxist néz

`:98` (`RegExp\s*\(`) és `:105` (`Set\s*<\s*String\s*>`). **Mérve (M10):** egy
`static const List<String> extraSensitiveKeys = ['lyrics', 'notes'];` a
redaktorban **15/15 zöld**. Javítás: a `List<String>` és az annotáció nélküli
halmaz-literál (`= {'…', '…'}`) is tiltott alak legyen.

### MINOR-3 — A D5 őrei a HÁLÓZATOT fedik, a lokális PERZISZTENCIÁT nem

Az A7 öt mintája és a `tool/check_data_inventory.dart` öt egress-mintája sem
ismeri a `dart:io`-t, a `File(...)`-t, a `Socket`/`WebSocket`-et, a
`SharedPreferences`-t vagy a `path_provider`-t. Egy jövőbeli
`telemetry_disk_buffer.dart` a hozzájárulás ELŐTT lemezre pufferelhetne, és
MINDKÉT őr zöld maradna — miközben az ADR 0484 D5 „kettős őr" állítása ezt
sugallja. Javítás: az A7 listájának bővítése (ma azonnal zöld lenne), és a D5
szövegének pontosítása arra, amit ténylegesen fed.

### MINOR-4 — A redaktor doc-ja túlígér: a `LogRedactor` a KULCSOKAT nem redaktálja

`telemetry_redactor.dart:11-14` szerint „any diagnostic context … must pass
through here first". A `log_redactor.dart:59-65` viszont `out[entry.key] =
value(...)` — a kulcs változatlanul kerül ki, se maszkolás, se 200-karakteres
vágás. A `security-reviewer` valódi futtatással mérte: egy fájlútvonalat és egy
e-mail címet TARTALMAZÓ kulcs szó szerint kijön, miközben az érték redaktálva
van. A `lib/core/logging/**` ebben a körben tilos zóna, ezért a javítás a
telemetria-oldali doc pontosítása + egy kimondott szabály (a metaadat kulcsai
zárt szótárból származnak).

### MINOR-5 — Semmi nem köti az `event-catalog.md`-t az enumokhoz

A `telemetry_event.dart:15-16` és az `event-catalog.md:4-6` egyaránt kimondja,
hogy a kettőnek szinkronban kell lennie („a Dart fájl nyer") — de egyetlen cella
sem méri. Ez ugyanaz a két-igazságforrás hibaosztály, ami ellen a kör egésze
épül. Javítás: egy cella, ami a `TelemetryEventName`/`Category` enum-értékeket
kikeresi a katalógusból mindkét irányban.

## 5. NOTE

1. **A réteg ma INERT:** `grep -rn "core/telemetry" lib/` → 0 fogyasztó. Minden
   fenti lelet LATENS — ma egyetlen bájt felhasználói tartalom sem éri el a
   réteget. Ez viszont nem enyhítő körülmény, hanem a kör TERMÉKÉNEK a lényege:
   a szállítmány maga a mérce, az értéke kizárólag az, mit fog a jövőben
   pirosra váltani.
2. A `TelemetryRedactor`-nak nincs production hívója (az eseményen nincs mit
   redaktálni) — a kör szerződés-jellegéből következik, nem hiba.
3. A `slo.yaml`-nak a kör tesztjén kívül nincs gépi fogyasztója (sem
   `tool/compare_benchmarks.py`, sem az E12-R18 `security_scan.py`), tehát az
   „`unknown` blokkol" ma deklaratív — a `release-dashboard.md` ezt korrektül
   „schema only"-ként jelöli. A bekötés a rollout-körök dolga.
4. A §10 handoff `--effort medium`-ot ír; a `docs/execution/engine-registry.tsv`
   a `sonnet-impl` sorra `high`-t rögzít. Kozmetikai eltérés, a diffre nincs
   hatása.
5. **Termékhatárok (AGENTS.md §5):** egyik sem sérül — nyers audio/kamera-frame
   a típusban nem hordozható, kijelentkezve nincs rejtett kérés (a réteg
   hálózat-képtelen és inert), titok nem kerül logba/hibaüzenetbe, az offline
   élmény érintetlen.

## 6. Merge-feltétel

**MAJOR-1 és MAJOR-2 zárása kötelező** (mindkettőhöz a javító körnek mutációs
bizonyítékot kell adnia: a jelentésben felsorolt mutánsok a javítás után
PIROSAK). A MINOR-1..5 ugyanebben a javító körben olcsón zárható, mert
mindegyik ugyanazt a teszt-fájlt (és MINOR-4 esetén egy doc-commentet) érinti —
a diffet nem hizlalja érdemben.

---

## 7. Javító kör #1 (`bbf7c3a1`) — a zárás ÚJRAMÉRVE → APPROVED

A javító kör a `test/core/telemetry/telemetry_redaction_test.dart` fájlt írta át
(a diff nagy része), plusz két doc-commentet (`telemetry_redactor.dart`,
`telemetry_sink.dart`). A `lib/` viselkedése NEM változott — az őrök változtak,
ahogy a review kérte.

**A mérés nem a jelentés átvétele:** a lenti táblázatot a reviewer futtatta le
saját mutációs harnessszel (`/tmp/mutate-e12-r19.sh`) az izolált
`/tmp/review-e12-r19` klónban, a JAVÍTOTT fán. Minden mutáns az igazi
`flutter test`-en ment át, nem szimuláción; a klón minden mutáns után
`git checkout -- .`-tal állt vissza, a végén `git status --short` üres.

| Lelet | Mutáns | Javítás ELŐTT (mérve, §0 M4–M10) | Javítás UTÁN (újramérve) |
|---|---|---|---|
| — | baseline, mutáció nélkül | 15/15 zöld | **20/20 ZÖLD** |
| MAJOR-1 | `TelemetryEvent`-en `Map<String, String>?` mező | zöld (átcsúszott) | **PIROS** |
| MAJOR-1 | `TelemetryEvent`-en `List<String>?` mező | zöld (átcsúszott) | **PIROS** |
| MAJOR-1 | `TelemetryEvent`-en `double?` mező (nyers ms) | zöld (átcsúszott) | **PIROS** |
| MAJOR-1 | kontroll: `Map<String, dynamic>?` mező | piros | **PIROS** |
| MAJOR-2 | 6. SLO 4-szóközös behúzással, `required: false`, `on_missing: success` | zöld (némán eldobva) | **PIROS** |
| MAJOR-2 | a `success_verdicts:` sor törölve | zöld (vákuum-igazság) | **PIROS** |
| MINOR-1 | testvér fájlban (`telemetry_sink.dart`) `final Map<String, dynamic>? data;` | zöld (az A1 csak `telemetry_event.dart`-ot olvasta) | **PIROS** |
| MINOR-2 | `static const List<String> extraSensitiveKeys` a redaktorban | zöld (M10) | **PIROS** |
| MINOR-3 | `import 'dart:io'` + `File(...).writeAsStringSync` a sinkben | zöld (az A7 5 mintája nem ismerte) | **PIROS** |
| MINOR-5 | új `TelemetryEventName.metronomeStarted` a katalógus frissítése nélkül | zöld (nem létezett cella) | **PIROS** |
| A3 (regresszió-próba) | statikus `_pending` puffer + flush a consent-flipnél | piros | **PIROS** (nem gyengült) |

MINOR-4 doc-comment-javítás, cellája nincs és nem is lehet — a
`telemetry_redactor.dart` fejléce most azt mondja, amit a hívott
`LogRedactor.fields` ténylegesen csinál (érték redaktálva, **kulcs
változatlanul kikerül**), és kimondja, hogy a metaadat kulcsainak zárt szótárból
kell származniuk. Ellenőrizve olvasással a `log_redactor.dart:59-65` ellen.

### Független ellenőrzések a javított HEAD-en (`bbf7c3a1`)

| Ellenőrzés | Eredmény |
|---|---|
| `tools/round-gate.sh test/core/telemetry/telemetry_redaction_test.dart test/privacy/consent_enforcement_test.dart` (izolált klón) | **EXIT=0** — format, analyze, mindkét teszt, architecture, secrets, l10n ZÖLD |
| `tools/scope-audit.py --base a96dceaf` | `OK — 10 changed path(s), 1 generated/ignored` |
| A6 (Kör 17 consent-cellák) | változatlanul ZÖLD, a kör nem érintette a `test/privacy/`-t |
| Tilos zóna | `lib/features/**`, `lib/core/logging/**`, `lib/core/network/**`, `backend/**`, `docs/privacy/**`, `pubspec.*`, `tool/**` mind érintetlen |

### Verdikt

**APPROVED** — 0 BLOCKER, 0 MAJOR, 0 nyitott MINOR. A kör mind a hét
acceptance-cellája (A1–A7) most már a JELENTÉST méri, nem a mező meglétét: a
brief §6.1 mérce-mátrixának mind az öt sorához van olyan mutáns, amit a
reviewer maga mért pirosra ([L549](../LESSONS.md#l549),
[L563](../LESSONS.md#l563) alkalmazva).

A merge feltétele már csak a zöld CI a merge SHA-ján (Full Gate + Router CI,
ADR 0086 §2).
