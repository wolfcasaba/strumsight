# E06-R19 — Biztonsági / adatvédelmi / prompt-injection review

- **Kör:** E06-R19 — Confidence calibration és capability resolver
- **Branch:** `codex/e06-r19-confidence-calibration-capability-resolver` @ `c912766f`
- **Baseline:** `origin/main` @ `cc8faca1` (merge-base; a diff lineáris a baseline fölött)
- **Reviewer:** Claude (security-reviewer, READ-ONLY — AGENTS.md §15.1)
- **Kötelezettség:** a brief `risk = "high"` → dedikált security review kötelező (AGENTS.md §15.1)
- **Dátum:** 2026-08-12
- **Verdikt:** **PASS** — 0 CRITICAL, 0 BLOCKER, 0 MAJOR, 1 MINOR, 2 NOTE

---

## Összefoglaló

Tisztán számítási confidence/capability-döntési modul az Audio Analysis V2-ben:
`ConfidenceCombiner` (geometriai átlag), `CalibrationTable.identityV1`,
`CapabilityThresholds`, `CapabilityResolver`, plus additív domain-bővítés
(`ConfidenceCalibrationSource` enum, `CapabilityReport.calibrationVersion`/
`calibrationSource`, véges-confidence guard), 4 export és 13+13 ARB-kulcs.
**Nincs** hálózat, mic, nyers-audio, secret, auth, AI-provider, prompt vagy
logolás érintés (grep + olvasás + gépi secret-scan igazolva). A modul
**bekötetlen**: `lib/`-ben 0 fogyasztó, csak a `public.dart` export teszi
elérhetővé. Ezért minden lelet **latens** — reprodukálható, de éles adatútja
addig nincs, amíg egy jövőbeli kör be nem köti.

A kör **három visszatérő biztonsági magot lezár**, nem újranyit:

1. **NaN-vak guard lezárva.** A `CapabilityReport` confidence-ellenőrzése a
   korábbi range-only `confidence < 0 || confidence > 1` (ami `NaN`-t átenged,
   mert `NaN < 0` és `NaN > 1` is hamis — az E06-R07/R16 leletek magja) helyett
   most `!confidence.isFinite || confidence < 0 || confidence > 1`
   (`analysis_capability.dart:54`). A `ConfidenceCombiner` és a
   `CalibrationTable` is `!x.isFinite`-tal validál. Reprodukálva: `NaN`/`Infinity`
   minden value-típuson `ArgumentError`-t dob.
2. **Őszinte kalibráció-jelölés kikényszerítve.** A ctor tiltja a
   `calibrated + identity.v1` kombinációt (`analysis_capability.dart:71-76`), a
   resolver kizárólag `identity` forrást ad ki. Nyers score sosem megy ki
   `calibrated`-nak álcázva (§5, ADR 0216/0237). Reprodukálva.
3. **Determinizmus.** A resolvernek nincs mutable/global állapota; 100 azonos
   hívás bitazonos. Reprodukálva + a suite `is bit-identical across one hundred
   equal resolutions` teszttel fedi.

A hard-gate-döntés (`criticalUnavailable` → overall confidence 0 → status
`unavailable`; illetve legfeljebb `degraded`) minden úton a **konzervatív**
irányba téved, sosem publikál hamis-magas confidence-t. §5 ("gyenge confidence
sosem biztos állítás") teljesül.

Egyetlen érdemi (latens) lelet: a `resolve()` **kezeletlen `ArgumentError`-t
dob** minden-`notApplicable` bemenetre (MINOR-1). Nem határsértés (dob, nem
publikál rossz értéket), de a publikus API-ból elérhető és teszttel nem fedett.

---

## Módszer és bizonyíték

- Teljes diff: `git diff origin/main...c912766f` (14 fájl, ADR-t is beleértve).
- **Pure-Dart probe** (`/tmp/r19probe.dart`, a klón `package_config.json`-jával,
  Flutter nélkül) — a valódi prod-kódot importálja. Kimenet lentebb tételesen.
- **Gépi secret-scan:** `dart run tool/ci/check_secrets.dart` → `Secret scan OK
  (2328 file(s) scanned, 0 finding(s))`.
- **Sink-grep** a 3 új engine-fájlon + a módosított domain-fájlon
  (`dio|http|socket|print|log(|logger|secure|token|secret|jsonEncode|dart:io|
  prompt|provider`): 0 találat (a két „találat" a `math.log`/„confidence
  publication" doc-comment — se hálózat, se logolás, se IO).
- **Import-tisztaság:** a `confidence/**` és a domain-fájl csak `dart:math`-ot és
  relatív `audio_analysis/domain/**` fájlokat importál; **nincs** Flutter/
  Riverpod/plugin, **nincs** `features/analyze` vagy `features/settings` érintés
  (AGENTS.md §6 teljesül).

Probe-kimenet (rövidítve):

```
1. CapabilityReport(confidence: NaN)          => THROW ArgumentError (must be finite…)
   ConfidenceCombiner.combine([NaN])          => THROW ArgumentError
   CalibrationTable.calibrate(NaN)            => THROW ArgumentError
   CalibrationTable.calibrate(Infinity)       => THROW ArgumentError
2. CapabilityReport(calibrated + identity.v1) => THROW (identity cannot be calibrated)
   normal resolve sources={identity} versions={identity.v1}
3. two resolves identical=true  overall=0.9
4. resolve(supported: {})                     => THROW ArgumentError   [MINOR-1]
   resolve(target-only cap, mode: freePlay)   => THROW ArgumentError   [MINOR-1]
   resolve(signalQuality only, freePlay)      => NO THROW (kontroll, helyes)
```

---

## Leletek

### MINOR-1 — `resolve()` kezeletlen `ArgumentError` minden-`notApplicable` bemenetre (latens)

- **Fájl:sor:** `lib/features/audio_analysis/engine/confidence/capability_resolver.dart:109-116`
  → az üres `overallFactors` lista a `confidence_combiner.dart:38-41` `factors.isEmpty`
  ágán dob.
- **Failure scenario:** a hívó olyan `CapabilityResolverInput`-ot ad, amelyben
  **minden** capability `notApplicable` lesz. Két reprodukált eset:
  1. `supportedCapabilities: <AnalysisCapability>{}` (üres halmaz) — mind a 14
     capability a `capability_resolver.dart:133-140` ágon `notApplicable`.
  2. `supportedCapabilities` ⊆ `_targetCapabilities` **és** `mode` nem
     `practiceTarget`/`songReference` (pl. `freePlay`, `importedRecording`) — a
     `capability_resolver.dart:142-150` ág mindet `notApplicable`-re teszi.

  Ekkor az `overallFactors` (`capability_resolver.dart:109-112`,
  `status != notApplicable` szűrő) **üres**, a `_confidenceCombiner.combine([])`
  a `factors.isEmpty` guardon **`ArgumentError`-t dob**, ami kezeletlenül kilép a
  **publikus** `resolve()`-ból (mind a `CapabilityResolverInput`, mind a
  `resolve` exportált a `public.dart`-on). A hibaüzenet ráadásul félrevezető
  („Confidence factors must be finite and in [0, 1]." — valójában üres a lista),
  de **nem szivárogtat** érzékeny adatot.
- **Kontroll:** egyetlen NEM-target capability (`signalQuality`) `freePlay`-ben
  NEM dob — a hiba tényleg csak az üres-halmaz állapotra jellemző.
- **Sértett szabály:** robusztusság / fail-closed-de-nem-graceful. **Nem** §5
  határsértés (dob, nem ad ki rossz confidence-t), **nem** adatszivárgás.
- **Teszt-fedettség:** egyik teszt sem fedi. A `capability_resolver_test.dart`
  `_input` helpere mindig `practiceTarget` módot és ≥13 capability-t használ; a
  „supported but one unavailable" eset pontosan egy capability-t vesz ki (13
  marad). A brief sem említi az all-`notApplicable` esetet — tehát ez nem
  szándékolt dobás, hanem kezeletlen él.
- **Javasolt javítás iránya:** a `resolve()`-ban explicit ág az üres
  `overallFactors`-ra → `overallConfidence: 0` + `overallStatus: notApplicable`
  (vagy `unavailable`) `combine([])` hívás nélkül. **Bekötés előtt kötelező**,
  ha bármely fogyasztó szűrt `supportedCapabilities`-t adhat át.

---

## Megjegyzések (NOTE)

### NOTE-1 — az új `calibrationVersion`/`calibrationSource` mezőket a codec nem perzisztálja (előretekintő)

- **Fájl:sor:** `lib/features/audio_analysis/data/analysis_document_codec.dart:180-195`
  (`_capabilityToJson`/`_capabilityFromJson`) — **a diffen kívül**, nem módosult.
- **Scenario:** a `CapabilityReport` az `AnalysisDocument` részeként
  szerializálódik. A codec csak `capability/status/confidence/reason/details`
  mezőt ír/olvas; betöltéskor a ctor default `identity.v1` / `identity`
  értékeivel rekonstruál. Amikor E06-R29 valódi `calibrated` táblát szállít, egy
  perzisztált-majd-visszatöltött report **csendben elveszti** a `calibrated`
  provenance-t, és `identity`-ként jön vissza.
- **Irány:** **fail-SAFE** (calibrated → identity = alábecslés; sosem a veszélyes
  raw → calibrated irány, amit a ctor guard amúgy is tilt). Ebben a körben minden
  report `identity`, így az elhagyás jelenleg no-op. De a source-enum
  megfigyelhetőségi célját perzisztált dokumentumoknál kiüti.
- **Javasolt irány:** E06-R29-nél a codec round-tripelje mindkét mezőt (és
  decode-on érvényesítse újra a `calibrated ⇒ version != identity.v1`
  invariánst). Most jelezve, hogy ne maradjon el.

### NOTE-2 — a `details` diagnosztikai map ma tiszta, de downstream JSON-sink (előretekintő)

- **Fájl:sor:** `capability_resolver.dart:237-245`.
- A `details` **csak** véges számokat (garantált: `SignalQualityReport` kikényszeríti
  a véges `overall`-t; az input-ctor a véges [0,1] `modelConfidence`/
  `alignmentQuality`-t), enum `.name`-et és verzió-konstansokat tartalmaz —
  mind JSON-biztos, **nincs** PII/szabadszöveg/secret. Ezért ma **nincs**
  szivárgás és **nincs** `jsonEncode`-NaN veszély. Csak jelzem: a `details`
  szó szerint a `analysis_document_codec` `jsonEncode`-jába folyna bekötés esetén,
  így bármely jövőbeli nem-véges vagy szabadszöveges `details`-mező-bővítést
  újra kell nézni. Most nincs teendő.

---

## Amit végignéztem és tisztának találtam (üres-lelet bizonyíték)

- **§5.1 prompt-injection / adat-mint-utasítás:** a döntési bemenetek mind
  típusosak (bool/int/double/enum/`SignalQualityReport`); nincs szabadszöveg,
  ami vezérlővé válhatna. A `details` **kizárólag kimenet** — a resolver sehol
  nem olvassa vissza a döntési logikába (`capability_resolver.dart` egyetlen
  `report.details` olvasás sincs). AI-provider/tool-calling/hálózat érintés
  nincs → a szekció N/A, igazoltan.
- **ARB (§5 / lokalizáció):** 13 új kulcs mindkét nyelven, sima felhasználói
  nyelv, **nincs** fájlnév/stack trace/nyers szám/belső azonosító, **nincs**
  egyetlen ICU placeholder (`{…}`) sem → nincs format-string/HTML injekciós
  felület. Mind a 13 `CapabilityUnavailableReason` fedve (a
  `capability_report_test.dart` méri a kulcs-jelenlétet).
- **Numerikus biztonság:** `NaN`/`Infinity`/negatív bemenet minden value-típuson
  dob; a geometriai átlag `max(ε, x)` alsó vágása a `log(0)=-∞`-t zárja, a
  `.clamp(0,1)` a felső korlátot; a bemenetek végessége miatt a szorzat
  `(0,1]`-ben marad. A `CapabilityThresholds` ctor `minimumEventCount <= 0`-t
  tilt (nem a korábbi körökben látott `< 0`, ami a 0-t átengedte).
- **Titkok/naplózás/hálózat:** 0 sink a diffben; gépi secret-scan 0/2328.
- **Cross-feature/domain-tisztaság (§6):** csak `dart:math` + relatív domain;
  nincs Flutter/Riverpod/plugin/`analyze`/`settings` érintés.
- **Determinizmus/statelessség:** minden mező `final`, `CalibrationTable` const,
  nincs cache/singleton/RNG/óra/IO; 100 hívás bitazonos.

---

## Verdikt

**PASS.** 0 CRITICAL, 0 BLOCKER, 0 MAJOR, 1 MINOR (latens, bekötetlen), 2 NOTE
(előretekintő). Nem tárgyalható termékhatár nem sérül; a kör három visszatérő
NaN/kalibráció-magot lezár. A MINOR-1 (üres-`overallFactors` → kezeletlen
`ArgumentError`) **bekötés előtt javítandó**, de merge-blokkoló lelet nincs.
