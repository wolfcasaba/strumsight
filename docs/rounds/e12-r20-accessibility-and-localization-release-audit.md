# E12-R20 — Accessibility és localization release audit

- **Státusz:** READY (pre-flight lefutott 2026-09-01, `main @ f54ee8c7` — lásd §0.0.A; előre megírva 2026-08-27, `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 20
- **Kör-azonosító:** `E12-R20`
- **Branch:** `<motor>/e12-r20-accessibility-and-localization-release-audit`
- **Előfeltétel:** `E13-R36` és `E12-R11` merge-elve (a teljes UI és az e2e harness egyaránt bemenet)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a szerződéseket az [ADR 0280](../adr/0280-accessibility-contract-and-live-region-budget.md), [ADR 0383](../adr/0383-typography-and-text-scale-contract.md) és [ADR 0424](../adr/0424-localization-resilience-contract.md) MÁR rögzíti; ez a kör AUDITÁL.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "localization parity accessibility text scale semantics audit"` → **[ADR 0383](../adr/0383-typography-and-text-scale-contract.md)** (tipográfia és text-scale szerződés) és **[ADR 0280](../adr/0280-accessibility-contract-and-live-region-budget.md)** (akadálymentességi szerződés és élő régió költségvetés). Az audit ezek MÉRT kritériumait futtatja végig a core flow-n; új szerződést nem alkot.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `test/accessibility/` három tesztjét (`semantics_contract_test.dart`, `screen_reader_copy_test.dart`, `tap_target_test.dart`), a `test/l10n/` hármat (`arb_parity_test.dart`, `hardcoded_string_guard_test.dart`, `formatters_test.dart`) és a Chapter 13 sáv legutóbbi text-scale méréseit. Az audit ezekre ÉPÜL — új, párhuzamos ellenőrzőt nem ír.

## 0.0 Miért nem ír ARB-kulcsot ez a kör

A lokalizációs FORRÁS a `lib/l10n/base/` fragmentum-fa, és a Chapter 13 sáv tulajdona. Egy hiányzó fordítás itt LELET (a kivétel-nyilvántartásban vagy `stopped` jelzésként), nem javítandó munka — különben az audit a saját mércéjét írná át.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "test/accessibility/release_flow_text_scale_test.dart",
  "test/accessibility/release_flow_semantics_test.dart",
  "docs/accessibility/release-audit.md",
  "docs/accessibility/known-exceptions.yaml",
  "docs/rounds/e12-r20-accessibility-and-localization-release-audit.md",
]
gate_tests = [
  "test/accessibility/release_flow_text_scale_test.dart",
  "test/accessibility/release_flow_semantics_test.dart",
  "test/l10n/arb_parity_test.dart",
  "test/l10n/hardcoded_string_guard_test.dart",
]
native_gate = false
```

## 0.0.A Pre-flight revízió (orchestrátor, 2026-09-01, `main @ f54ee8c7`)

A brief 2026-08-27-én, `main @ 9ca4a0dc` ellen készült. Az alábbi tíz pont MÉRT
tény a MAI fán; ahol a brief törzse mást mond, **ez a szakasz az erősebb**.

**R1 — a §2 leltára pontosítva.** `docs/accessibility/` valóban **nem létezik**
(`ls` → No such file or directory). `test/e2e/` létezik (`first_practice_offline_test.dart`,
`returning_user_restart_test.dart`, `resource_coexistence_test.dart`).
`test/accessibility/` viszont ma **négy** fájl, nem három: a §2 által felsorolt
három mellett ott a `closure_suite_test.dart` is. Mind a négy a tilos zónában van.

**R2 — az e2e harness NINCS az engedélyezett listán, ÉS beégetett angol.**
`test/support/e2e_harness.dart` a §4 listáján nem szerepel, tehát módosítása
**H3 scope-sértés**. Ugyanakkor a benne lévő folyam-bejáró segédek MIND angol
literálra illesztenek — `walkOnboardingViaSkip` → `find.text('Skip')`
(`e2e_harness.dart:220`), `runFirstPracticeSession` → `'Quick start'` (:245),
`'Start practice'` (:251), `'Start'` (:266), `'Finish'` (:274) —, és a
`bootE2eApp` szignatúrájának (`:114-118`) **nincs sem locale-, sem
textScaler-paramétere**. Következmény, kötelező alak: **a két új tesztfájl a
SAJÁT, locale-paraméteres folyam-bejáróját írja meg**, a szövegeket
`lookupAppLocalizations(Locale(code))`-ból véve. A `bootE2eApp` / `E2eSession` /
`loadPracticeHistory` HÍVÁSA megengedett (import), a harness SZERKESZTÉSE nem.

**R3 — a locale-kapcsoló MÉRT útja (harness-módosítás nélkül).**
`bootE2eApp` felülírja a `keyValueStoreProvider`-t az átadott store-ral
(`e2e_harness.dart:128`), a `LocaleNotifier.build()` pedig a
`StorageKeys.locale` kulcsot olvassa (`lib/core/i18n/locale_provider.dart:13`,
a kulcs értéke `'ss.settings.locale'`, `lib/core/storage/storage_keys.dart:15`).
Tehát `InMemoryKeyValueStore({'ss.settings.locale': 'hu'})` a boot ELŐTT
átállítja az app locale-ját. **A2 falszifikációja:** mind az öt folyam-kulcs hu
értéke MÉRTEN eltér az angoltól (`onboardSkip` „Kihagyás", `practiceHubQuickStartLabel`
„Gyors indítás", `practiceSetupStart` „Gyakorlat indítása", `practiceSessionStart`
„Indítás", `practiceSessionFinish` „Befejezés"), tehát egy en-re beégetett
bejáró a hu cellában NEM talál rá az elemre → a cella pirosra vált. Ez a §6.1
első sorának gépi őre.

**R4 — a text-scale kapcsoló MÉRT útja.** A teljes app-fán a `StrumSightApp`
gyökere `MaterialApp.router` (`lib/app/strumsight_app.dart:31`), amely SAJÁT
`MediaQuery.fromView`-t szúr be — egy a fa FÖLÉ tett `MediaQuery` wrappert tehát
felülír. A működő kapcsoló:
`tester.platformDispatcher.textScaleFactorTestValue = <skála>` a `bootE2eApp`
hívása ELŐTT, `addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue)`-nel.
Bevett minta a fán: `test/features/audio_analysis/presentation/analysis_compare_screen_test.dart:17`,
`test/features/practice/presentation/practice_result_screen_test.dart:163`.
(Az `e13_r36_variant_matrix_test.dart:282-285` `MediaQuery`-wrapperes alakja
azért működik OTT, mert az a teszt a `MaterialApp` `builder`-ébe, tehát a
`MediaQuery.fromView` ALÁ teszi — a mi esetünkben az app gyökere nem a mienk.)

**R5 — KÖTELEZŐ telefon-méretű viewport ([L558](../LESSONS.md#l558), [L452](../LESSONS.md#l452)).**
A `flutter_test` alapértelmezett **800×600** viewportja szélesebb ÉS magasabb
minden telefonnál; az E15-R06 három képernyője rajta `1.5`/`2.0`/`2.5` skálán
MIND zöld volt, majd `Size(360, 640)`-en pirosra váltott (L558). Ráadásul a
`MediaQuery(data: MediaQueryData(size: …))` wrapper **nem** méretezi a layoutot
(L452: a deklarált 800×400 a valóságban 800×600-on mért). Ezért **minden
cellának** kötelező:

```dart
tester.view.physicalSize = const Size(412, 915);
tester.view.devicePixelRatio = 1.0;
addTearDown(tester.view.reset);
```

**Az alapértelmezett viewporton mért „nincs túlcsordulás" NEM bizonyíték**, és a
review eldobható próbája pontosan ezt fogja újramérni.

**R6 — a túlcsordulás észlelése `FlutterError.onError`-ral.** A bevett,
merge-elt minta az `e13_r36_variant_matrix_test.dart:269-294`: a pumpolás
idejére `FlutterError.onError = captured.add`, utána visszaállítás, és a cella a
`captured` listát vizsgálja. Szöveg-heurisztika a renderelt kimeneten TILOS.

**R7 — a folyam-hajtás publikus levői.** A harness `_driveSessionUntil`-ja
privát, de a hajtáshoz szükséges két lever publikus és importálható:
`session.clock.tick(tester, Duration)` (`fake_clock.dart`, a harness
re-exportálja) és `container.read(practiceSessionHostProvider)` →
`host.state.status` (`practice_session_providers.dart`,
`PracticeSessionStatus.running` / `.completed`). Az új tesztfájl ezekre építve
írja meg a saját, `maxTicks`-szel korlátozott hajtó ciklusát — végtelen
`pumpAndSettle` nélkül.

**R8 — ez a kör NEM ír ADR-t.** A pipeline ADR-rekesze `nincs`; a szerződéseket
az [ADR 0280](../adr/0280-accessibility-contract-and-live-region-budget.md),
[ADR 0383](../adr/0383-typography-and-text-scale-contract.md) és
[ADR 0424](../adr/0424-localization-resilience-contract.md) MÁR rögzíti, ez a kör
AUDITÁL. A `docs/adr/**` ezen felül a §4 **tilos zónája**: új ADR írása az
engedélyezett lista **tágítását** kívánná, ami az ADR 0087 §2 szerint nem az
orchestrátor hatásköre (szűkíteni szabad, tágítani nem). Döntés: **nincs új ADR**;
a `tools/round-slots.py reserve-adr` ezért nem futott.

**R9 — visszakeresés (ADR 0312 §4.9).** Szűkített futás
(`--corpus lessons,halts,adr` és `--corpus lessons,halts`) →
[ADR 0383](../adr/0383-typography-and-text-scale-contract.md) (`bm25#2 emb#1`),
[ADR 0280](../adr/0280-accessibility-contract-and-live-region-budget.md)
(`bm25#16 emb#2`), [L558](../LESSONS.md#l558) (`bm25#6 emb#2`),
[L452](../LESSONS.md#l452) (`bm25#5 emb#4`), [L460](../LESSONS.md#l460)
(`bm25#41 emb#1`). Az L460 tanulsága ide is köt: a **jelenlét-alapú** őr vak —
egy `find.bySemanticsLabel(x) != null` cella nem bizonyítja, hogy az elem
elérhető és a fókusz-sorrend értelmes; az A3 cellának a TÉNYLEGES szemantikus
fát kell bejárnia (`tester.ensureSemantics()` + `getSemantics` /
`SemanticsNode` bejárás), nem egyetlen finder-hívást.

**R10 — a STOP-eset megerősítve.** Minden talált túlcsordulás/fordítási hiba
**LELET**: `docs/accessibility/known-exceptions.yaml` sor + jelentés, és ha P1
súlyú, `stopped` jelzés. `lib/**` javítása ebben a körben H3.

### 0.0.A.1 A §6.1 mérce-mátrix kiegészítése

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A cella az alapértelmezett 800×600-as viewporton mér (R5) | A1/A2 — a `physicalSize` cella hiánya önmagában lelet; a review próbája 412×915-en újramér |
| A `textScaler` a `MaterialApp` alatt nem hat (R4) | a §6 valódi-sértés próbája: az `1.0` és a `2.0` kimenete azonos → a próba bukik |
| A teszt a harness angol bejáróját hívja a `hu` cellában (R2/R3) | A2 — a hu literál (`Kihagyás`, `Gyors indítás`…) nem illeszkedik |
| Az A3 egyetlen `find.bySemanticsLabel` jelenlét-próbára épül (R9/L460) | A3 — nem bizonyít elérhetőséget és fókusz-sorrendet |

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha az audit P1 súlyú akadálymentességi vagy fordítási hibát talál, a kimenet a `stopped` jelzés és jelentés — a `lib/**` javítása ebben a körben TILOS.

## 1. Cél

Bizonyítani, hogy a core tanulási út angolul ÉS magyarul, 200%-os szövegnagyítás mellett és képernyőolvasóval végigjárható — vagy pontosan megnevezni, hol nem.

## 2. Jelenlegi állapot — mért tények

- `test/accessibility/`: `semantics_contract_test.dart`, `screen_reader_copy_test.dart`, `tap_target_test.dart` — KOMPONENS-szintű mércék.
- `test/l10n/`: `arb_parity_test.dart` (en↔hu paritás), `hardcoded_string_guard_test.dart` (beégetett szöveg őre), `formatters_test.dart`.
- `tool/ci/check_l10n_parity.dart` és `tool/gen_l10n_segments.dart` a fragmentum-alapú ARB-forrást kezelik (ADR 0424).
- **FOLYAM-szintű, teljes core úton futó text-scale és semantics mérce NINCS** — a Chapter 13 körei képernyőnként mértek (a `textScaler 2.0` golden-keret ott derített fel valódi túlcsordulásokat).
- `docs/accessibility/` **nem létezik**.
- `test/e2e/` a Kör 11 után létezik — az audit ugyanazt a determinisztikus profilt használja.

## 3. Scope

**Benne van:** `test/accessibility/release_flow_text_scale_test.dart` — a core flow (indítás → onboarding → gyakorlás → eredmény) végigjátszása `textScaler 2.0` mellett, MINDKÉT locale-on, túlcsordulás-ellenőrzéssel · `test/accessibility/release_flow_semantics_test.dart` — ugyanaz a flow képernyőolvasó-szemantikával: minden interaktív elem elérhető, a fókusz-sorrend értelmes, az állapot nem CSAK színnel jelölt · `docs/accessibility/release-audit.md` (a futtatott mércék, az eredmény, és a NEM lefedett területek) · `docs/accessibility/known-exceptions.yaml` (owner + lejárat + hatás).

**NINCS benne (tilos):**

- `lib/**` és `lib/l10n/**` bármely módosítása (a §0.0 szerint).
- Meglévő a11y/l10n teszt gyengítése vagy `skip`-je.
- Új golden-kép felvétele (a golden-fa ADR 0426 hatálya alatt).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `test/accessibility/release_flow_text_scale_test.dart` | ÚJ — folyam-szintű text-scale mérce |
| `test/accessibility/release_flow_semantics_test.dart` | ÚJ — folyam-szintű semantics mérce |
| `docs/accessibility/release-audit.md` | ÚJ — az audit eredménye |
| `docs/accessibility/known-exceptions.yaml` | ÚJ — kivétel-nyilvántartás |

**Tilos zóna:** `lib/**` · `test/ui/goldens/**` · `test/accessibility/` meglévő fájljai · `test/l10n/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések

Nincs ADR. Két kötelező szabály:

### 5.1 A mérce a FOLYAM, nem a képernyő

Az audit a valódi app-fán, egymás után látogatott képernyőkön mér. **NEM elfogadható gyengítés:** képernyőnkénti, izolált pumpolás — a Chapter 13 már azt mérte; ez a kör azt a hibaosztályt keresi, ami CSAK a folyamban jelenik meg (megőrzött állapot, fókusz-átadás, dinamikus szöveg).

### 5.2 A hiba LELET, nem javítandó munka

**NEM elfogadható gyengítés:** a talált túlcsordulás „gyors" javítása a `lib/`-ben (§0.0, STOP-eset).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A core flow `textScaler 2.0` mellett `en` locale-on túlcsordulás nélkül végigjárható | `release_flow_text_scale_test.dart` |
| A2 | Ugyanez `hu` locale-on | ugyanaz a teszt (locale-páros cella) |
| A3 | A flow minden interaktív eleme elérhető képernyőolvasóval, értelmes fókusz-sorrenddel | `release_flow_semantics_test.dart` |
| A4 | Egyetlen állapot sincs KIZÁRÓLAG színnel jelölve a flow-ban | `release_flow_semantics_test.dart` |
| A5 | A meglévő `arb_parity_test.dart` és `hardcoded_string_guard_test.dart` VÁLTOZATLANUL zöld | a §7 gate |
| A6 | Minden talált kivétel ownerrel és lejárattal szerepel a `known-exceptions.yaml`-ben | a fájl + a teszt cellája |

**Küszöb-cellahármas a szövegnagyításra** (a kötelező határ `2.0`, INKLUZÍV): a küszöb **alatt** (`1.5`) → a flow zöld; **pontosan rajta** (`2.0`) → a flow zöld — EZ a release-feltétel; a küszöb **fölött** (`2.5`) → NEM követelmény, a teszt nem méri (és nem is enged rá hivatkozni a `2.0` teljesítéseként).

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A teszt csak `en` locale-on fut | A2 |
| A teszt képernyőnként pumpol, a folyam-állapot elveszik | A1 vagy A3 (a mért folyam-hiba nem jelenik meg) |
| Egy állapotjelzés csak színt kap, `Semantics` nélkül | A4 |
| A kivétel lejárat nélkül kerül a nyilvántartásba | A6 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** állítsd a text-scale cellát `1.0`-ra, futtasd a §7 gate-et, majd vissza `2.0`-ra → a próba akkor sikeres, ha a `2.0` cella mérete/eredménye BIZONYÍTHATÓAN eltér az `1.0`-étől (különben a teszt nem is skálázott). Dokumentáld mindkét kimenetet a §10-ben.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/accessibility/release_flow_text_scale_test.dart test/accessibility/release_flow_semantics_test.dart test/l10n/arb_parity_test.dart test/l10n/hardcoded_string_guard_test.dart
```

## 8. Implementációs sorrend

1. `release_flow_text_scale_test.dart` — a folyam `en` és `hu` cellapárral.
2. `release_flow_semantics_test.dart`.
3. A leletek gyűjtése (NEM javítása).
4. `docs/accessibility/release-audit.md` + `known-exceptions.yaml`.
5. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **A locale-páros hiánya.** Egyetlen locale-on futó cella pontosan az ellenkező nyelv beégetését engedi át (a Chapter 13 mért tanulsága).
- **Nem skálázott „skálázott" teszt.** Ha a `textScaler` nem hat, a cella zöld és értéktelen — ezért méri a §6 próbája az eltérést.
- **Javítás-csábítás.** Egy talált túlcsordulás javítása ebben a körben elrejtené, mit mért az audit (§5.2).

## 10. Implementation handoff — az implementer tölti ki

**Négy engedélyezett fájl, mind létrehozva:**

- `test/accessibility/release_flow_text_scale_test.dart` — ÚJ, saját
  locale-paraméteres folyam-bejáróval (a harness `walkOnboardingViaSkip`/
  `runFirstPracticeSession` beégetett angol literálra illesztene). 5 cella:
  `{en,hu} × {1.5,2.0}` (A1/A2 + a §6 küszöb-cellahármas két releváns pontja)
  + a §6 kötelező valódi-sértés próba (állandó teszt-cella, nem egyszeri
  manuális lépés).
- `test/accessibility/release_flow_semantics_test.dart` — ÚJ, ugyanaz a
  bejáró, `tester.semantics.simulatedAccessibilityTraversal()` +
  `SemanticsNode.getSemanticsData()` alapú valódi fabejárással (§0.0.A/R9,
  NEM `find.bySemanticsLabel` jelenlét-próba). 2 cella (`en`, `hu`): A3
  (elérhetőség + Pause→Finish→Exit fókusz-sorrend) + A4 (a readiness-row
  állapota szövegként is olvasható, nem csak színnel).
- `docs/accessibility/known-exceptions.yaml` — ÚJ, 3 bejegyzés, owner +
  lejárat + mért adat mindegyiken.
- `docs/accessibility/release-audit.md` — ÚJ, a teljes jelentés.

**Mit talált az audit — HÁROM LELET, mindegyik `lib/**`-ban, EGYIK SEM
javítva (§0.0/§5.2, tilos zóna):**

1. `practice_setup_screen.dart:418` (`_ScoringProfileReadout`) — 43px
   túlcsordulás `textScale 2.0`-n, MINDKÉT locale-on azonosan (a
   `profileId` nem lokalizált, a szűkösséget a label növekedése okozza).
2. `practice_feedback.dart:89` (combo-számláló `Row`) — 65px túlcsordulás
   `textScale 2.0`-n, CSAK `hu`-n (a hosszabb magyar fordítás miatt).
3. `ss_switch_row.dart` (`SsSwitchRow`, megosztott design-system komponens)
   — a szimulált akadálymentességi bejárás KÉT szomszédos csomópontot ad
   egy sor helyett: a külső (`InkWell` saját gesztus-szemantikája) néma
   `tap`-célpont, a belső (`MergeSemantics`) felirat nélküli `toggled`
   állapotot hordoz. 3 előfordulás/locale a Practice Setup képernyőn
   (Metronome, Accent, Chord hint) — a `screen_reader_copy_test.dart`-féle
   `find.bySemanticsLabel` jelenlét-próbák ezt NEM vették volna észre
   (L460), mert a BELSŐ csomópont felirata megvan.

**Súlyosság: mindhárom P2, egyik sem P1** — a két túlcsordulás másodlagos
feliratot vág (nem-lokalizált profil-id; combo-számláló), a switch-row hiba
opcionális beállításokat érint (a fő CTA-útvonal — Quick start → Start
practice → Start → Pause/Finish/Exit — MINDKÉT locale-on hibátlanul
elérhető és felirat-helyes). A STOP-protokoll (§0) ezért NEM lépett életbe.

**§6 valódi-sértés próba — MÉRT eredmény (2026-09-01, telefon-viewport
412×915, `en`, az onboarding „Skip" felirata):**

| textScale | magasság |
|---|---|
| 1.0 | 20.0px |
| 2.0 | 40.0px |

A két érték eltér (pontosan 2×), tehát a `textScaleFactorTestValue` kapcsoló
ténylegesen eléri a fát — ha nem érné el, mindkét cella 20.0px-et mérne, és
minden A1/A2 cella értéktelen lenne.

**Gate:**

```
tools/round-gate.sh test/accessibility/release_flow_text_scale_test.dart test/accessibility/release_flow_semantics_test.dart test/l10n/arb_parity_test.dart test/l10n/hardcoded_string_guard_test.dart
```

ZÖLD (lásd a kör-jelzés melletti gate-log). `format` → `analyze` → 4×
`test <útvonal>` → `architecture` → `secrets` → `l10n` lépések mind zöldek.

## 10.1 Javító kör (review CHANGES REQUESTED — 1 MAJOR, 2 MINOR)

**MAJOR-1 — az A6-nak nem volt gépi őre.** A review mérte, hogy a két
tesztfájl a `known-exceptions.yaml`-t kizárólag kommentben/`reason:`
sztringben említette — egyetlen cella sem nyitotta meg a fájlt. Javítás:

- `release_flow_semantics_test.dart`-ba egy fail-closed, kézzel írt sor-parszer
  került (`_parseKnownExceptions`, a `tool/check_data_inventory.dart` mintáját
  követve — `package:yaml` NINCS a fán deklarálva, csak tranzitív függőségként
  a `pubspec.lock`-ban, `import`-ja a `depend_on_referenced_packages` lintet
  ütné). Nem-parszolható sor, ismeretlen kulcs, hiányzó `exceptions:` blokk
  vagy hiányzó/olvashatatlan fájl mind kivételt dob — sosem "nulla bejegyzés,
  tehát zöld".
- Egy `"A6 — known-exceptions.yaml is a machine-checked registry"` csoport két
  cellával: (1) minden bejegyzésnek van nem-üres `id`/`owner`/`expiry`/
  `severity`/`file`/`measured_on`/`source_test` mezője, és `expiry:
  unscheduled` csak dátumozott `review_by:`-jal legális (mind a három
  bejegyzés kapott egy `review_by: "2026-12-01"` sort); (2) **kétirányú
  tükör-fedés** — a YAML `id`-halmaza és a két tesztfájl toleranciái
  (`release_flow_text_scale_test.dart`'s `knownOverflows` — publikussá téve,
  `id` mezővel bővítve — és `release_flow_semantics_test.dart`'s
  `switchRowSplitSemanticsId`/`switchRowSplitUnlabeledCount`) kölcsönösen
  fedik egymást.
- A cross-file hozzáférés útja: `release_flow_semantics_test.dart` importálja
  `release_flow_text_scale_test.dart`-ot (`as text_scale`) — ehhez a korábban
  privát `_KnownOverflow`/`_knownOverflows` publikussá vált
  (`KnownOverflow`/`knownOverflows`), a `main()` importálás nem futtatja a
  másik fájl `main()`-jét.

**Falszifikáció (KÖTELEZŐ, a review 3 pontja, mindhárom PIROSRA váltott,
utána visszaállítva — `diff` a visszaállítás után üres):**

1. Az első bejegyzés `owner:` sorának törlése →
   `"...is missing required field(s): owner"` — **PIROS** (mindkét A6 cella).
2. Egy negyedik, `falsification-orphan-entry` id-jű bejegyzés felvétele
   (tükör nélkül, `source_test` a text-scale fájlra mutatva) →
   `"...claims release_flow_text_scale_test.dart as its source_test, but no
   KnownOverflow entry in that file carries this id — orphan YAML entry..."`
   — **PIROS**.
3. A teljes `exceptions:` lista törlése (`_knownOverflows`/
   `knownUnlabeledCount` tesztoldali tolerancia megtartva) →
   `"knownOverflows references id(s) with no ... entry: {setup-scoring-
   profile-overflow, feedback-combo-row-overflow-hu} — an undocumented
   tolerance is not a valid state"` — **PIROS**.

Mindhárom próba után a fájl visszaállt az eredetire (`diff` üres), és az A6
csoport újra zöld:

```
flutter test test/accessibility/release_flow_semantics_test.dart --plain-name "A6"
→ 00:00 +2: All tests passed!
```

**MINOR-1 — a `PracticeResultFallback` korlát a NEM-lefedett listán.**
`release-audit.md` §5 kapott egy új pontot: a `PracticeResultScreen`
(`PracticeHistoryEntry`-vel, `Navigator.push`-sal nyitott, tartalmas
eredménynézet) nincs auditálva ebben a körben — sem `textScale 2.0`-n, sem
`hu`-n, sem képernyőolvasóval.

**MINOR-2 — az A6 „PASS" indoklása.** `release-audit.md` §2 A6 sora most a
gépi őrre hivatkozik (fájl + tesztcsoport neve), és az `expiry: unscheduled`
+ `review_by` feloldást is dokumentálja.

**Amit a javító kör NEM módosított:** `lib/**`, a §0.0.A/R2–R5 bejáró, a
valódi-sértés próba, az A3 traversal-alapú mérés, a `2.5` cella hiánya — mind
a review NOTE-1-e szerint változatlan.

## 11. Review — a Claude tölti ki
