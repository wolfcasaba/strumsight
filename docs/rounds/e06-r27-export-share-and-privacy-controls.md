# E06-R27 — Export, share és privacy controls

- **Státusz:** PLANNING (pre-flight frissítve 2026-08-13, main @ `6e13e635`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 27; §27.5, §28.1–28.5
- **Branch:** `codex/e06-r27-export-share-and-privacy-controls`
- **Előfeltétel:** **E06-R21, E06-R26 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/domain/export/analysis_export.dart",
  "lib/features/audio_analysis/domain/export/redaction_policy.dart",
  "lib/features/audio_analysis/data/export/analysis_export_codec.dart",
  "lib/features/audio_analysis/data/export/share_card_builder.dart",
  "lib/features/audio_analysis/application/export_analysis_use_case.dart",
  "lib/features/audio_analysis/application/delete_analysis_use_case.dart",
  "lib/features/audio_analysis/presentation/analysis_export_screen.dart",
  "lib/features/audio_analysis/presentation/widgets/export_preview.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/features/share/share_service.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/audio_analysis/data/analysis_export_codec_test.dart",
  "test/features/audio_analysis/application/export_analysis_use_case_test.dart",
  "test/features/audio_analysis/application/delete_analysis_use_case_test.dart",
  "test/features/audio_analysis/presentation/analysis_export_screen_test.dart",
  "test/features/share/share_service_test.dart",
  "test/property/analysis_export_redaction_property_test.dart",
  "docs/adr/0247-analysis-export-share-and-delete-contract.md",
  "docs/rounds/e06-r27-export-share-and-privacy-controls.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/features/share",
  "test/property",
  "test/app",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R21/R26 merge.
> Olvasd újra `lib/features/share/share_service.dart`-ot (a mai megosztási út,
> `dart:io`-val) és a `share/public.dart` exportjait — a megosztás **a meglévő
> szolgáltatáson** át megy; az OD-01 kötelező, mindkét úton kitakarított
> JSON-megosztásához a szolgáltatás **pontosan egy additív** publikus
> metódussal bővül (H3 self-heal, 2026-08-13 — ld. §0.0/§5.8), a meglévő
> `shareCard`/`shareImage`/`shareText` szignatúrája és viselkedése **nem**
> változik. Olvasd újra az R21 `AudioRetentionPolicy`-ját és a `delete`
> szerződését — a törlésnek a dokumentumot, az indexet, a cache-t és az
> (opcionális) audiot **egyaránt** el kell takarítania. PREPARED→PLANNING,
> brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**2026-08-13 pre-flight, main @ `6e13e635`.** A `ShareService` tényleges
publikus felülete továbbra is kizárólag `shareCard` / `shareImage` /
`shareText`; a három metódus közül egyik sem fogad export-fájlt és a meglévő
`_writeTemp` út sem garantál hívás utáni takarítást. Emiatt a §5.8 szerinti
egyetlen additív metódus szükséges. A `FileAnalysisRepository.delete` a
dokumentumot és az indexet ténylegesen törli (`file_analysis_repository.dart`
476–496); az R21 `AudioRetentionPolicy` dokumentáltan nem perzisztál
audio-byte-okat, R28 cache pedig még nincs. Ezért a `DeleteAnalysisUseCase`
csak az adott cache/audio portokon keresztül kaphat takarítási felelősséget;
nem módosíthatja az R21 repository-szerződést. A pre-flightban foglalt
**ADR 0247** rögzíti ezt a kiterjesztési és ownership-határt. A brief
`allowed_paths` listája az ADR-rel szűken bővült; más scope-változás nincs.

**2026-08-13, H3 self-heal (ADR 0112 önjavító kör, 1. kísérlet).** Az első
dispatch (Terra orchestráció, sonnet-impl implementer) a §5.1 OD-01
alapértelmezett feloldását — „...majd a MEGLÉVŐ share szolgáltatáson át
megosztási intentbe; a temp fájl a megosztás után (vagy hiba esetén)
TÖRLŐDIK, és ezt teszt méri" — a §3/§4 „Kívül — TILOS: a share feature
módosítása" tiltással összevetve helyesen `stopped`-ot (H3) jelzett,
dispatch és kódmódosítás nélkül. Mérve
(`lib/features/share/share_service.dart`, 103 sor): kizárólag
`shareCard`/`shareImage`/`shareText` publikus, mindhárom a képernyőről
készített PNG (vagy szöveg) megosztására épül; a privát `_writeTemp`
`Directory.systemTemp`-be ír, és EGYIK metódus sem takarít a hívás után —
nincs olyan publikus felület, amely egy tetszőleges (JSON) fájlt fogadna, és
annak takarítását sikeres/hibás kimenetel esetén EGYARÁNT garantálná. A
kötelező, mindkét úton kitakarított export-megosztás emiatt strukturálisan
megvalósíthatatlan volt a deklarált `allowed_paths`-on belül.

**Feloldás:** `allowed_paths` és §4 bővítve `lib/features/share/share_service.dart`
(meglévő, additív metódus) és `test/features/share/share_service_test.dart`
(ÚJ) fájlokkal; `gate_tests` bővítve `test/features/share`-vel, hogy a kör
saját §7 gate-je is lefedje az új tesztet. §3 „Kívül — TILOS" és a §4 „Tilos
zóna" pontosítva: a `lib/features/share/**` továbbra is tiltott zóna, KIVÉVE
a `share_service.dart`-ba illesztett, kizárólag additív bővítést (a
szerződést §5 8. pontja rögzíti kötelezően). Regressziós teszt:
`tools/tests/test_e06_r27_share_service_scope.py` (a javítás előtt PIROS: az
`allowed_paths`/`gate_tests` nem tartalmazta a fenti bejegyzéseket).

## 1. Cél

**Alapból adatvédelem-biztos** export és megosztás, előnézettel arról, hogy
mi kerül ki — plusz a teljes, ellenőrzött törlés (session, cache, opcionális
audio).

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- A megosztás ma a `lib/features/share/share_service.dart`-ban él, és az
  `analyze_screen.dart` a `share/public.dart`-on át hívja.
- **Nincs** exportformátum, **nincs** redakciós policy, **nincs** export
  előnézet, **nincs** „mit osztunk meg" képernyő.
- A törlés ma a Library sessionjére vonatkozik (a `library_screen` /
  `session_detail_screen` útján), és **egyetlen** SharedPreferences kulcsot
  ír át — cache- és audio-fogalom nincs.
- Az R21 adja a repository-t + retention policy-t, az R20 az insighteket, az
  R19 a confidence-t.

## 3. Scope

**Benne:** `AnalysisExport` (technikai JSON export + felhasználóbarát
összefoglaló + share-kártya adat); `RedactionPolicy` (allowlist-alapú
mezőválogatás); `AnalysisExportCodec`; `ShareCardBuilder`;
`ExportAnalysisUseCase`; `DeleteAnalysisUseCase` (dokumentum + index + cache +
opcionális audio); export-előnézet képernyő; ARB; a `ShareService` EGY
additív, tetszőleges fájlt megosztó és azt garantáltan takarító publikus
metódusa (H3 self-heal, §0.0 — kötött szerződés §5.8).

**Kívül — TILOS:** a `share` feature módosítása — KIVÉVE a fent nevezett
egyetlen additív `ShareService`-metódus (§5.8) —, felhő-feltöltés, Lab
diagnosztikai upload (a meglévő `diagnostics` út marad), CSV export
(későbbi), a Library UI.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/export/analysis_export.dart` | ÚJ | export modell |
| `.../domain/export/redaction_policy.dart` | ÚJ | allowlist-policy |
| `.../data/export/analysis_export_codec.dart` | ÚJ | JSON export |
| `.../data/export/share_card_builder.dart` | ÚJ | share-kártya adat |
| `.../application/export_analysis_use_case.dart` | ÚJ | export use case |
| `.../application/delete_analysis_use_case.dart` | ÚJ | teljes törlés |
| `.../presentation/analysis_export_screen.dart` | ÚJ | előnézet + megerősítés |
| `.../presentation/widgets/export_preview.dart` | ÚJ | „mi kerül ki" nézet |
| `.../public.dart` | meglévő | export |
| `lib/features/share/share_service.dart` | meglévő | **additív** metódus — kötött szerződés §5.8 (H3 self-heal) |
| `lib/l10n/*.arb` | meglévő | **additív** kulcsok |
| `test/**` | ÚJ | codec + use case + widget + property |
| `test/features/share/share_service_test.dart` | ÚJ | takarítás (siker/hiba) unit teszt (H3 self-heal) |
| `docs/adr/0247-analysis-export-share-and-delete-contract.md` | ÚJ | pre-flight döntés: export share + törlési ownership |

**Tilos zóna:** `lib/features/share/**` (KIVÉVE a `share_service.dart` §5.8
szerinti additív bővítése), `lib/features/diagnostics/**`,
`lib/features/library/**`, `lib/features/analyze/**`, `lib/core/network/**`.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Allowlist-alapú redakció, nem denylist:** a `RedactionPolicy` **felsorolja**
   a kivihető mezőket; minden más **kimarad**. **NEM elfogadható:** tiltólista
   („a fájlnevet kiszedjük") — egy új mező akkor csendben kiszivárogna.
2. **Alapból kizárt** (SDD §27.5, ADR 0202): nyers audio, importált fájlnév,
   eszközazonosító, bármilyen titok, teljes belső diagnosztika.
   **NEM elfogadható:** ezek bármelyike az exportban, akkor sem, ha
   „a felhasználó úgyis a sajátját exportálja".
3. **Alacsony confidence nem tény** (ADR 0201): a share-kártya
   **nem** mutat `unavailable` vagy alacsony confidence-ű metrikát biztos
   értékként; ha kell, **jelöli**. **NEM elfogadható:** a confidence
   elhagyása a kártyáról.
4. **Előnézet kötelező:** az export/megosztás **csak** azután indul, hogy a
   felhasználó látta a kimenő tartalmat. **NEM elfogadható:** azonnali
   megosztás előnézet nélkül.
5. **A törlés teljes és bizonyított:** dokumentumfájl + index-bejegyzés +
   cache-bejegyzés + (ha van) audiofájl — mind eltűnik, és a `getById`
   `null`-t ad. **NEM elfogadható:** „az index frissül, a fájl marad".
6. **Nincs hálózat ebben a körben:** az export **helyi** (fájl/megosztási
   intent a meglévő szolgáltatáson át); semmilyen új upload nem készül.
7. **A Lab export külön és figyelmeztetett:** ha egyáltalán készül, kizárólag
   Lab módban, **explicit** figyelmeztetéssel, és a redakciós policy
   **külön** allowlistjével.
8. **ShareService additív kiterjesztés (H3 self-heal, 2026-08-13 — ld. §0.0):**
   a §5.1 OD-01 kötelező, mindkét úton kitakarított export-megosztásához a
   meglévő `ShareService` PONTOSAN EGY új publikus metódussal bővül, amely
   egy tetszőleges, a hívó (`ExportAnalysisUseCase`) által előállított
   fájl + felirat megosztására szolgál, és a megosztás sikeres VAGY hibás
   kimenetelétől függetlenül (`try`/`finally`) törli az átadott fájlt. A
   meglévő `shareCard`/`shareImage`/`shareText` szignatúrája és viselkedése
   **változatlan**, és a `lib/features/share/**` egyetlen más fájlja sem
   módosul. **NEM elfogadható:** a takarítási felelősség áthárítása a
   hívóra, vagy a meglévő három metódus valamelyikének nem-kép/nem-szöveg
   tartalomra való újrahasznosítása workaroundként.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Hova írjon a JSON export?
    blocking: true
    resolution_policy: use_default
    default: >-
      az app privát temp könyvtárába, random névvel, majd a MEGLÉVŐ
      share szolgáltatáson át megosztási intentbe; a temp fájl a megosztás
      után (vagy hiba esetén) TÖRLŐDIK, és ezt teszt méri.
  - id: OD-02
    question: A share-kártya kép legyen vagy szöveg?
    blocking: true
    resolution_policy: use_default
    default: >-
      ebben a körben STRUKTURÁLT ADAT + lokalizált szöveg (a képgenerálás
      külön kör); így a redakció és a confidence-jelölés tesztelhető, és
      nincs golden-kép függőség.
  - id: OD-03
    question: Melyik insight kerüljön a kártyára?
    blocking: false
    resolution_policy: use_default
    default: >-
      a legmagasabb prioritású POZITÍV vagy SEMLEGES insight (SDD §27.5);
      ha nincs ilyen, a kártya insight NÉLKÜL készül, nem negatívval.
```

## 6. Acceptance criteria

- [ ] **Allowlist-redakció property:** `PROPERTY_SEED`-ből vezérelt véletlen
      `AnalysisDocument`-ekre az export JSON **kizárólag** az allowlistben
      szereplő kulcsokat tartalmazza — a teszt a **kulcshalmaz különbségét**
      méri, nem mintaillesztést.
- [ ] **Új mező szivárgás-próbája:** a teszt egy **ismeretlen** kulcsot
      injektál a dokumentum diagnosztikai ágába, és bizonyítja, hogy az
      **nem** jelenik meg az exportban (ez az a cella, amit egy denylist
      elbukna).
- [ ] **Tiltott tartalom mátrix — öt cella:** nyers PCM; importált fájlnév;
      eszközazonosító; belső stage-timing; Lab decoder-diagnosztika — mind
      **hiányzik** a normál exportból.
- [ ] **Confidence-jelölés:** egy `degraded` és egy `unavailable` metrikát
      tartalmazó dokumentum kártyája — a `degraded` **jelölve** jelenik meg,
      az `unavailable` **nem** jelenik meg értékként. Két cella.
- [ ] **Előnézet-kapu:** teszt méri, hogy a megosztási hívás **nem** történik
      meg, amíg a felhasználó nem erősítette meg (a fake share-szolgáltatás
      hívásszáma 0 → 1).
- [ ] **Temp-fájl takarítás:** sikeres megosztás után **és** hibás megosztás
      után is a temp könyvtár **üres** — két cella.
- [ ] **Törlés-teljesség:** mentés → cache-bejegyzés → törlés → (a) a
      dokumentumfájl nincs a lemezen; (b) az index nem tartalmazza;
      (c) a cache-bejegyzés eltűnt; (d) `getById` `null`; (e) ha volt
      audiofájl, az is eltűnt. Öt cella.
- [ ] **Nincs hálózat:** forrásolvasó teszt méri, hogy az új fájlok egyike
      sem importál `dio`-t, `http`-t vagy `lib/core/network/`-öt.
- [ ] **JSON-séma stabilitás:** az export JSON tartalmaz `exportSchemaVersion`
      mezőt, és a codec **round-trip** tesztje bizonyítja a
      determinisztikus, bájtazonos kimenetet.
- [ ] **UI:** az előnézet felsorolja a kimenő **kategóriákat** (nem a nyers
      JSON-t), hu/en paritással, 320 px-en és `textScaleFactor 2.0`-n
      overflow nélkül.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Denylist-alapú redakció | az „ismeretlen kulcs injektálása" szivárgás-próba |
| A fájlnév bekerül az exportba | a tiltott-tartalom mátrix fájlnév-cellája |
| A stage-timing kikerül | a belső stage-timing cella |
| Az `unavailable` metrika értékként jelenik meg | a confidence-jelölés `unavailable` cellája |
| A megosztás előnézet nélkül indul | az előnézet-kapu 0→1 hívásszám cella |
| A temp fájl hiba esetén marad | a hibás megosztás utáni „üres temp" cella |
| A törlés csak az indexet frissíti | a törlés-teljesség (a) fájl-cellája |
| A cache túléli a törlést | a törlés-teljesség (c) cellája |
| Hálózati hívás kerül be | a „nincs hálózat" forrásolvasó cella |
| Az export nem determinisztikus | a bájtazonos round-trip cella |
| **Valódi-sértés próba (§10):** egy tiltott mező ideiglenes felvétele az allowlistbe → a tiltott-tartalom mátrix megfelelő cellája **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/app test/features/share
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. `redaction_policy.dart` (allowlist) + a szivárgás-próba teszt (RED előbb).
2. `analysis_export.dart` + `analysis_export_codec.dart`.
3. `share_card_builder.dart` (confidence-jelölés, pozitív/semleges insight).
4. `export_analysis_use_case.dart` (temp + share + takarítás).
5. `delete_analysis_use_case.dart` (öt cellás teljesség).
6. Export-előnézet UI + ARB; property; gate.

## 9. Kockázatok

- **A megosztási intent platformfüggő** — a teszt a `share` szolgáltatás
  **fake**-jét használja; a valós viselkedés a device-mátrix PENDING sora.
- **A törlés cache-ága függ az R28-tól** — ha a cache még nem létezik, a
  cella a **jövőbeli** cache-kulcsra készül fel: a use case interfésze
  tartalmazza a cache-invalidálást, és a teszt fake cache-t ad. A §10 rögzíti.
- **A Lab export csábító** — a §5.7 külön allowlisthez köti; ha nem fér bele,
  **kimarad** ebből a körből (follow-up).

**STOP:** denylist-redakció, előnézet nélküli megosztás vagy új hálózati út
helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

**2026-08-13, sonnet-impl.** Minden §6 acceptance cella zöld a lenti fájlokkal.

### Fájlonkénti összefoglaló

- `domain/export/analysis_export.dart` (ÚJ) — `AnalysisExport` + almodelljei
  (`AnalysisExportInput/SignalQuality/Capability/Metric/Hotspot/Insight/
  Warning/Completion`), `analysisExportSchemaVersion = 1`.
- `domain/export/redaction_policy.dart` (ÚJ) — `RedactionPolicy.apply`:
  allowlist-mapping mezőnként; sosem olvassa `provenance`-t,
  `input.sourceName`/`fingerprint`-et, `CapabilityReport.details`-t,
  `metric.evidence`-t, `hotspot.metricIds/evidenceIds`-t, `insight.factIds`-t.
- `data/export/analysis_export_codec.dart` (ÚJ) — determinisztikus JSON
  encode/decode, `exportSchemaVersion` mezővel; a `analysis_document_codec.dart`
  mintáját követi (fix kulcs-sorrend, `_ensureFiniteJson` őr).
- `data/export/share_card_builder.dart` (ÚJ) — `ShareCardBuilder.build`:
  csak `available`/`degraded` metrikát tesz kártyára (`isDegraded` jelöléssel),
  `unavailable` sosem érték; a legmagasabb prioritású nem-`caution` insightot
  választja, vagy nincs insight (sosem negatív).
- `application/export_analysis_use_case.dart` (ÚJ) — `preview()` (tiszta,
  I/O nélkül) + `share()`: redaktált JSON → app-privát temp fájl (injektált
  `Directory`, random fájlnév) → `ShareService.shareExportFile` hívás.
- `application/delete_analysis_use_case.dart` (ÚJ) — `DeleteAnalysisUseCase`:
  `repository.delete` (R21, változatlan) + `AnalysisCachePort`/
  `AnalysisAudioPort` (alapértelmezett no-op portok — R28/audio-retention
  follow-up köti be a valódi implementációt); hiba esetén a portok nem futnak.
- `presentation/analysis_export_screen.dart` + `presentation/widgets/
  export_preview.dart` (ÚJ) — előnézet-kapu: `ExportPreview` kategóriákat
  listáz (nem nyers JSON-t), a megosztás csak az explicit "Share export"
  gombra fut.
- `lib/features/share/share_service.dart` (additív, H3 self-heal §5.8) —
  EGY új publikus metódus, `shareExportFile(file, caption, ...)`,
  `try/finally`-ban törli a fájlt sikeres/hibás megosztás után is; a
  meglévő `shareCard`/`shareImage`/`shareText` változatlan.
- `lib/l10n/app_en.arb` / `app_hu.arb` — additív `analysisExport*` kulcsok
  (cím, kategórianevek, "Share export" gomb, felirat).
- `lib/features/audio_analysis/public.dart` — additív exportok az új
  domain/data/application/presentation fájlokhoz.
- Tesztek (mind ÚJ): `analysis_export_codec_test.dart` (round-trip +
  `exportSchemaVersion` + "nincs hálózat" forrás-scan + `ShareCardBuilder`
  confidence-jelölés — ennek nincs önálló allowed_paths bejegyzése, ezért a
  codec teszttel egy fájlban él, mivel mindkettő a `data/export/` alá
  tartozik), `analysis_export_redaction_property_test.dart` (allowlist
  kulcshalmaz-diff property + új-mező szivárgás-próba + öt tiltott-tartalom
  cella), `export_analysis_use_case_test.dart`, `delete_analysis_use_case_test.dart`
  (öt cella + hiba-rövidzár), `analysis_export_screen_test.dart`
  (előnézet-kapu 0→1, hu/en paritás, 320px/2.0 overflow), `share_service_test.dart`
  (a VALÓDI `shareExportFile` siker/hiba utáni takarítása, a
  `dev.fluttercommunity.plus/share` platform-csatorna mockolásával — nem
  fake-kel — így a tényleges implementáció ellen bizonyít).

### Mért buktató (jegyzetnek follow-up körökhöz)

Widget-tesztben a valódi `dart:io` fájlírás (`ExportAnalysisUseCase.share`)
a sima `testWidgets` zóna alatt sosem fut le — a `pumpAndSettle` nem várja
meg a widget-újraépítéshez nem kötött, valódi async I/O-t. A megoldás:
`tester.runAsync(...)` a tap + a `ShareService` hívás megvárása körül
(`analysis_export_screen_test.dart` "preview gate" teszt).

### Gate

```
tools/round-gate.sh test/features/audio_analysis test/property test/app test/features/share
```

Eredmény: **MINDEN GATE ZÖLD** — format, analyze, `test
test/features/audio_analysis`, `test test/property`, `test test/app`,
`test test/features/share`, architecture (12 allowlisted deviation,
változatlan), secrets (2454 fájl, 0 találat), l10n parity (en→hu, 1276
üzenet). A backend sáv nem futott (a kör nem érinti a `backend/`-et).

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r27-export-share-and-privacy-controls-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
**Kötelező:** `security-reviewer` (risk = high, adatkivitel + törlés).
