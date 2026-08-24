# E13-R14 — Accessibility foundation audit és semantics toolkit

- **Státusz:** READY (pre-flight lemérve 2026-08-24, `main @ b93fbdc0`; eredetileg
  előre megírva 2026-08-15, kód olvasva: `main @ 6adea220`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 14
- **Kör-azonosító:** `E13-R14`
- **Branch:** `sonnet-impl/e13-r14-accessibility-toolkit`
- **Előfeltétel:** `E13-R13` merge-elve (overlay-rendszer)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0280`](../adr/0280-accessibility-contract-and-live-region-budget.md)
  — **MÁR MERGE-ELVE (2026-08-15); a kör ADR-t NEM ír, lásd §0.0/D1. A
  `docs/adr/` végig TILOS zóna.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R01
> `docs/ui/baseline/accessibility-findings.md` prioritásos leletlistáját — a §3
> „scope képernyők" halmaza abból jön, nem találgatásból. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/design_system/foundations/ss_semantics.dart",
  "lib/core/design_system/accessibility/ss_live_region.dart",
  "lib/core/design_system/accessibility/ss_tap_target.dart",
  "lib/core/design_system/public.dart",
  "test/accessibility/semantics_contract_test.dart",
  "test/accessibility/tap_target_test.dart",
  "test/accessibility/screen_reader_copy_test.dart",
  "docs/ui/accessibility.md",
  "docs/rounds/e13-r14-accessibility-toolkit.md",
]
gate_tests = [
  "test/accessibility/semantics_contract_test.dart",
  "test/accessibility/tap_target_test.dart",
  "test/accessibility/screen_reader_copy_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight revízió (Claude Opus 5, 2026-08-24, `main @ b93fbdc0`)

**Kockázat = high, indoklás:** a kör a képernyőolvasó-felület (élő régió,
semantics-címkék) **szerződését** vezeti be, és a StrumSight fő használati módja
(Stage Mode / Live) másodpercenként sokszor frissülő felismerés. Egy naiv élő
régió a felolvasót használó felhasználónak **használhatatlanná teszi** a fő
funkciót (ADR 0280 „Kontextus"), miközben minden egyes bejelentés önmagában
helyes — vagyis a hiba a gépi zöld mellett is fennállhat. A router
`high_risk_path_fragments` listájából egyetlen fragmentum sem illeszkedik az
`allowed_paths`-ra (nincs auth/crypto/upload/payment útvonal); a `high` besorolás
tehát **hozzáférhetőségi hozzáférés-vesztés** kockázata miatt áll, nem
adat-/hálózat-kitettség miatt. A `security-reviewer` ezért ebben a körben
**nem kötelező**; a review-t az `sdd-round-review` protokoll viszi.

### D1 — Az ADR 0280 MÁR LÉTEZIK és merge-elve van: a kör ADR-t NEM ír

Mérve: `docs/adr/0280-accessibility-contract-and-live-region-budget.md` a
`main`-en van (dátum 2026-08-15, `Kör: E13-R14`), és a szövege a §5.1–§5.5
döntéseivel **pontról pontra egyezik** (költségvetés 1000 ms inkluzív, tuner
cents + strum-irány felolvasható, nincs csak-szín, ≥ 48 dp, a gépi teszt nem
elégséges). A Ch13 ADR-jei (0273–0282) előre, az `a4fdfec2`-ben lettek
merge-elve. A foglalótól kapott `0423` szám **felhasználatlan marad**.
`docs/adr/**` végig TILOS zóna — az ADR bármilyen módosítása **H1**. Ez a
minta most **ötödször** fut (E13-R08/0275, R09/0276, R10/0277, R12/0278,
R13/0279).

### D2 — Új ARB-kulcs TILOS: az A2/A6 MEGLÉVŐ, mért kulcsokból épül

`lib/l10n/app_{en,hu}.arb` **generált aggregátum** (ADR 0307 §4,
`tool/gen_l10n_segments.dart` fejléc); a forrás a `lib/l10n/base/app_<locale>.arb`
és a `lib/l10n/features/<feature>_<locale>.arb`. **Egyik sincs az
`allowed_paths`-on**, tehát új felolvasó-szöveg kulcs felvétele scope-sértés →
`stopped` jelzés. Nem is kell: a szükséges szövegek MINDKÉT nyelven léteznek:

| Kulcs | Forrás-fragmentum | en | hu |
|---|---|---|---|
| `tunerCentsFlat` | `features/tuner_{en,hu}.arb` | `{cents} cents flat` | `{cents} centtel mély` |
| `tunerCentsSharp` | `features/tuner_{en,hu}.arb` | `{cents} cents sharp` | `{cents} centtel magas` |
| `tunerInTune` | `app_{en,hu}.arb` (base) | `In tune` | megvan |
| `strumDown` | `app_{en,hu}.arb` (base) | `Down` | `Le` |
| `strumUp` | `app_{en,hu}.arb` (base) | `Up` | `Fel` |

A design system **importálhatja** az `AppLocalizations`-t — mérve: 11 meglévő
DS-fájl teszi (pl. `components/feedback/ss_status_badge.dart`,
`components/overlays/ss_dialog.dart`). A `screen_reader_copy_test.dart` tehát
`AppLocalizations.delegate.load(Locale('en'))` és `Locale('hu')` mellett mérje a
szerződés-építőket, és **követelje meg, hogy a két nyelv kimenete különbözzön**
(különben egy angolra drótozott implementáció is zöld maradna → A6).

### D3 — A1: a három cellának a VALÓDI bejelentési utat kell hajtania (L443)

[L443](../LESSONS.md) mért hibaosztálya: az E13-R06-ban a küszöb-cellák csak egy
tiszta `isWithinSyncTolerance(Duration)` predikátumot hívtak, a widgetet soha nem
építették fel — a tiltott implementáción is zöld maradt. **Ugyanez itt tilos:**
az A1 celláinak az `SsLiveRegion` tényleges bejelentés-kibocsátását kell mérniük
(a felépített widget/vezérlő által kiadott bejelentések listáját), injektált
órával. Egy önmagában hívott `SsLiveRegion.isWithinBudget(...)` predikátum
**nem** teljesíti az A1-et.

A §6.1 három cellája `python3`-mal kiszámolva, hogy ne maradjon értelmezési rés
(küszöb `gap = 1000 ms`, a határ inkluzív, azaz `delta >= 1000` → bejelenthető):

| Cella | Pontos bemenet (idő ms, érték) | Elvárt bejelentés-szám | Mit ejt ki |
|---|---|---|---|
| küszöb ALATT | `(0,'C')`, `(400,'G')`, `(800,'D')` | **1** (`t=0 → 'C'`) | minden kereten bejelentő implementáció |
| küszöbÖN | `(0,'C')`, `(1000,'G')` | **2** | szigorú `>` összehasonlítás (`delta > 1000`) |
| küszöb FÖLÖTT | `(0,'C')`, `(2500,'G')`, `(5000,'D')` | **3** | fix-ütemű throttle, ami a ritka változást is elnyeli |
| **érdemi változás** | `(0,'C')`, `(2500,'C')` | **1** | dedup nélküli, csak időre néző implementáció |

A negyedik sor a §5.1 „csak **érdemi** változásnál szólal meg" felének gépi
mércéje — enélkül az azonos akkordnév ismételt bejelentése átmenne.

**Valódi-sértés próba (a §6.1-ben már kötelező, itt pontosítva):** a
költségvetés-ellenőrzés kivétele után az A1 **„küszöb ALATT"** cellájának
pirosnak kell lennie, a tényleges hibaüzenettel a §10-ben. [L453](../LESSONS.md)
szerint az őrnek saját mérő cellája kell — a próba szövegét ne parafrazeáld,
másold be.

### D4 — A5: a 48 dp cella MÉRJEN, ne a konstansot ismételje

Mérve, hogy a kritikus komponensek MÁR a nevesített konstanst használják, tehát
a kör **nem javít komponenst** (mind TILOS zóna, csak olvasható/pumpálható):

- `components/actions/ss_button.dart:122` — `minHeight: SsSemantics.minimumInteractiveDimension`
- `components/actions/ss_icon_button.dart:62-63` — `minWidth`/`minHeight` ugyanaz
- `components/inputs/ss_switch_row.dart:45`, `components/inputs/ss_choice.dart:105`,
  `components/cards/ss_coach_action_card.dart:70` — ugyanaz
- `SsSemantics.minimumInteractiveDimension == 48` (`foundations/ss_semantics.dart:3`),
  már pinnelve: `test/core/design_system/foundations_test.dart:26`

A `tap_target_test.dart` ezért a **felépített** komponensek tényleges méretét
mérje (`tester.getSize(...)` ≥ 48), ne a konstans újra-assertálásával — a §6.1
„44 dp-s érintési cél" hibás implementációját csak így fogja pirosra. A viewportot
**kizárólag** `tester.view.physicalSize` méretezi ([L452](../LESSONS.md)); a
`MediaQuery(size:)` inert, a `textScaler` viszont helyesen megy `MediaQuery`-n át.

### D5 — A8: a csökkentett mozgás API MÁR LÉTEZIK

`motion/ss_motion_scope.dart`: `SsMotionScope.reduceMotionOf(context)`,
`SsMotionScope.durationOf(context, base)` (reduced esetén `Duration.zero`) és a
tiszta `SsMotionScope.resolve(appOverride:, systemReduced:)`. Az A8 cellája ezt
használja, ÚJ mozgás-API nélkül: reduced motion mellett a **semantics-visszajelzés
megmarad**, csak a mozgás terjedelme esik nullára (ADR 0274 §5.1).

### D6 — Visszakeresett előzmények (ADR 0312, brief-lint S8)

Szűkített korpuszon (`lessons,halts,adr`) és teljes korpuszon is lefuttatva:

- [`adr/0280`](../adr/0280-accessibility-contract-and-live-region-budget.md) — a kör
  normatív forrása; **már merge-elve** (D1).
- [`adr/0381`](../adr/0381-semantic-theme-and-accessibility-contract.md) — az
  E13-R03 szemantikus téma-/accessibility-szerződése, amire a §5.4 épít.
- `lessons/L443` (E13-R06) — küszöb-cella tiszta predikátumon = nem őrzi a
  viselkedést → **D3**.
- `lessons/L453` (E13-R09) — az invariáns-őrnek saját mérő cellája kell → **D3**
  valódi-sértés próba.
- `lessons/L452` (E13-R11) — widget-teszt viewport csak `tester.view.physicalSize`
  → **D4**.
- `lessons/L460` (E13-R11) — jelenlét ≠ láthatóság; ne `find.byType` jelenléttel
  őrizz láthatósági invariánst → az A3/A4 celláira is áll.
- `lessons/L393` (E13-R05) — egy DS-változás a MEGLÉVŐ, listán kívüli teszt-
  szerződéseket is érinti; ez a kör azonban **nem módosít komponenst** (D4),
  tehát a `component_catalog_test.dart` exact-count csapdája nem aktiválódik.
- `lessons/L122` (E04-R13) — szinkron fake-óra + aszinkron stream: a timer a
  rossz `now`-hoz köthet. Az A1 óra-injekciója ezért **szinkron, determinisztikus**
  legyen (a bejelentések listája a hívás után azonnal olvasható).

### D7 — `gate_tests` és CI

A `gate_tests` három útvonala változatlan; a kör **nem** módosít meglévő
komponenst, ezért a `component_catalog_test.dart` NEM kerül be negyediknek
(ellentétben az E13-R12-vel). `native_gate = false`, a diff tisztán
Dart + dokumentum → a CI-tervet a `tools/round-ci-plan.py` dönti el.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A design system accessibility-**szerződésének** automatizálása és a
legkritikusabb leletek javítása (SDD Ch13 Kör 14).

## 2. Jelenlegi állapot — mért tények

- Az R03–R13 minden komponens-körében szerepelt semantics-szabály; ez a kör
  **gépi szerződéssé** teszi őket egy helyen.
- Az R01 prioritásos leletlistája megnevezi a legsúlyosabb baseline-hibákat.
- A Live felismerés **másodpercenként sokszor** frissül — a naiv élő régió
  ettől folyamatosan beszélne.

## 3. Scope

**Benne van:** semantics helper és audit utility (heading, élő régió, mérőszám,
akkord, strum, beat, tuner, diagram-összegzés) · minimális érintési cél
ellenőrzése a kritikus komponensekre · **élő régió költségvetés** (mikor és
milyen sűrűn beszélhet a felület) · képernyőolvasó-szöveg fixture angolul és
magyarul · a kézi TalkBack/VoiceOver ellenőrzőlista dokumentálása.

**NINCS benne (tilos):** `lib/features/**` képernyők átírása (a migrációs
körök dolga; a leletek javítása ott történik) · a DSP vagy a felismerési
frekvencia módosítása (AGENTS.md §9) · `lib/core/theme/**` · `docs/adr/**`,
`tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `foundations/ss_semantics.dart` | a szerződés kibővítése |
| `accessibility/ss_live_region.dart` | **ÚJ** — élő régió + költségvetés |
| `accessibility/ss_tap_target.dart` | **ÚJ** — érintési cél ellenőrzés |
| `public.dart` | az export bővítése |
| `test/accessibility/*_test.dart` (3) | a §6 cellái |
| `docs/ui/accessibility.md` | **ÚJ** — szerződés + kézi ellenőrzőlista |
| `docs/rounds/e13-r14-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` · `lib/core/theme/**` · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0280)

### 5.1 Az élő régió NEM spammelheti a képernyőolvasót

A felismerés gyors frissülése nem fordítható át folyamatos beszédre. Az élő
régiónak **költségvetése** van: csak érdemi változásnál szólal meg, és van
minimális szünet két bejelentés között.

**NEM elfogadható gyengítés:** minden felismerési kereten kimondott akkordnév.
Az felolvasóval használhatatlanná teszi a Stage Mode-ot.

### 5.2 Az automatizált teszt NEM helyettesíti a valós próbát

A `docs/ui/accessibility.md` kimondja, hogy a TalkBack/VoiceOver ellenőrzőlista
kézi lépés marad. A gépi cella szükséges, de nem elégséges.

### 5.3 A tuner cents-eltérése és a strum-irány FELOLVASHATÓ

Nem elég vizuálisan jelezni. A hangoló és a strum-visszajelzés szöveges
formában is elérhető.

### 5.4 Nincs csak színnel közölt siker / hiba / confidence

Az R03 §5.3 és az R12 §5.2 gépi kikényszerítése egy helyen.

### 5.5 A kritikus akciók címkézettek

Minden interaktív elem semantics labelje kötelező a szerződésben.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az élő régió betartja a bejelentés-költségvetést | `semantics_contract_test.dart` |
| A2 | A tuner cents és a strum-irány felolvasható szövegként | `screen_reader_copy_test.dart` |
| A3 | Nincs csak színnel közölt siker/hiba/confidence | `semantics_contract_test.dart` |
| A4 | Minden kritikus akció címkézett | ugyanott |
| A5 | A kritikus komponensek érintési célja ≥ 48 dp | `tap_target_test.dart` |
| A6 | A képernyőolvasó-szöveg angolul ÉS magyarul is létezik | `screen_reader_copy_test.dart` |
| A7 | A kézi TalkBack/VoiceOver ellenőrzőlista dokumentált | `docs/ui/accessibility.md` |
| A8 | Csökkentett mozgás mellett a visszajelzés megmarad | `semantics_contract_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Minden kereten bejelentett akkordnév | **A1** |
| A tuner eltérése csak vizuális | **A2** |
| A confidence csak színes pötty | A3 |
| Címke nélküli ikonos akció | A4 |
| 44 dp-s érintési cél | A5 |
| Csak angol felolvasó-szöveg | A6 |
| A dokumentum a gépi tesztet elégségesnek mondja | A7 |

**Az élő régió kötelező cellái** (a küszöb: két bejelentés közti minimális
szünet, **1000 ms**, a határ INKLUZÍV; a pontos bemeneteket a §0.0/D3 számolta
ki `python3`-mal — azokat használd, ne közelítsd):

| Cella | Pontos bemenet (idő ms, érték) | Elvárt bejelentés-szám |
|---|---|---|
| a küszöb alatt | `(0,'C')`, `(400,'G')`, `(800,'D')` | **1** (`t=0 → 'C'`) |
| rajta (a küszöbön) | `(0,'C')`, `(1000,'G')` | **2** (a határ inkluzív) |
| a küszöb fölött | `(0,'C')`, `(2500,'G')`, `(5000,'D')` | **3** |
| érdemi változás | `(0,'C')`, `(2500,'C')` | **1** (azonos érték nem szólal meg újra) |

A celláknak a felépített `SsLiveRegion` **tényleges bejelentés-kibocsátását**
kell mérniük injektált órával — egy önmagában hívott tiszta predikátum NEM
teljesíti az A1-et (§0.0/D3, `docs/LESSONS.md` L443).

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a
költségvetés-ellenőrzést az élő régióból → az **A1 „a küszöb alatt"** cellájának
PIROSNAK kell lennie → a tényleges hibaüzenetet szó szerint másold a §10-be →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/accessibility/semantics_contract_test.dart test/accessibility/tap_target_test.dart test/accessibility/screen_reader_copy_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_semantics.dart` — a szerződés (heading, mérőszám, akkord, strum, beat,
   tuner, diagram).
2. `ss_live_region.dart` — költségvetés + a három cella.
3. `ss_tap_target.dart` + a 48 dp cella.
4. Felolvasó-szöveg fixture en + hu.
5. `docs/ui/accessibility.md` — szerződés és **kézi** ellenőrzőlista.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A beszédes élő régió.** A „minden változást jelentsünk be" szabály
  jóindulatú, és pont a fő használati módot teszi felolvasóval elviselhetetlenné
  (A1).
- **A gépi zöld mint bizonyíték.** A semantics teszt nem hallja, amit a
  TalkBack mond — a dokumentumnak ezt ki kell mondania (A7).
- **A scope-tágulás.** A leletlista javításra hív a feature-ökben; az a
  migrációs körök dolga.

## 10. Implementation handoff — az implementer tölti ki

**Motor:** `sonnet-impl` (Claude Sonnet 5).

### 10.1 Mit épített

- `lib/core/design_system/foundations/ss_semantics.dart` — bővítve:
  `liveRegionAnnouncementGap` (1000 ms konstans), `tunerAccuracyLabel(l10n,
  {cents, inTune})` és `strumDirectionLabel(l10n, {isDown})` (a
  `cents_gauge.dart` már meglévő kerekítési logikáját tükrözi, DS-szintű,
  újrafelhasználható „szerződés-építő"-ként).
- `lib/core/design_system/accessibility/ss_live_region.dart` (**ÚJ**) —
  `SsLiveRegion extends ChangeNotifier`: `report(value, {at})` csak akkor
  jelent be, ha (a) az érték eltér az utoljára bejelentettől ÉS (b) a
  bejelentés óta `liveRegionAnnouncementGap` (1000 ms, inkluzív határ) telt
  el. A küszöb alatt érkező olvasat ELDOBÓDIK (nem sorba áll) — az utolsó
  BEJELENTETT értékhez hasonlítunk, nem az utoljára LÁTOTTHOZ. Emellett
  `SsLiveRegionAnnouncer` widget (`Semantics(liveRegion: true, ...)`), ami a
  kontroller aktuális bejelentését adja tovább a képernyőolvasónak.
- `lib/core/design_system/accessibility/ss_tap_target.dart` (**ÚJ**) —
  `SsTapTarget.meetsMinimum(Size)`: mért `Size`-t (pl. `tester.getSize(...)`)
  hasonlít `SsSemantics.minimumInteractiveDimension`-höz mindkét tengelyen;
  nem `flutter_test`-függő, tiszta `dart:ui` check.
- `lib/core/design_system/public.dart` — a két új accessibility-fájl exportja.
- `docs/ui/accessibility.md` (**ÚJ**) — a gépi szerződés összefoglalója +
  kimondott állítás, hogy a gépi teszt SZÜKSÉGES, DE NEM ELÉGSÉGES + 8 pontos
  kézi TalkBack/VoiceOver ellenőrzőlista.

### 10.2 Melyik cella melyik acceptance-pontot méri

| Cella (fájl) | A# | Mit bizonyít |
|---|---|---|
| `semantics_contract_test.dart` — A1 csoport (4 mátrix-cella + 1 épített widget-cella) | A1 | `SsLiveRegion.report`/`.announcements` a TÉNYLEGES kibocsátást méri, a §6.1 4 sorával pontosan (1/2/3/1 bejelentés) + egy `testWidgets` cella, ami a `SsLiveRegionAnnouncer` widgetet pumpálja és a szemantika-fát olvassa (`find.bySemanticsLabel`) |
| `semantics_contract_test.dart` — A3 csoport | A3 | `SsStatusBadge` minden `kind`-jére a VALÓDI szemantika-címkét méri (`find.bySemanticsLabel`, nem csak az Icon/Text widgetet) + `tunerAccuracyLabel` három állapotának egyedisége |
| `semantics_contract_test.dart` — A4 csoport | A4 | `SsIconButton` üres label ⇒ `throwsArgumentError`; destruktív `SsButton` `matchesSemantics(label:, hint:, ...)` egy node-on; `SsCoachActionCard` dismiss-gombjának saját címkéje |
| `semantics_contract_test.dart` — A8 csoport | A8 | `SsMotionScope(appOverride: true)` mellett `durationOf(...) == Duration.zero`, DE az `SsLiveRegion` bejelentése és a szemantika-címke változatlanul megjelenik |
| `tap_target_test.dart` (6 cella) | A5 | Az 5, §0.0/D4-ben nevesített komponens (`SsButton`, `SsIconButton`, `SsSwitchRow`, `SsChoice` radio, `SsCoachActionCard` dismiss) FELÉPÍTETT méretét `tester.getSize(...)` méri, `SsTapTarget.meetsMinimum`-mal — nem a konstans újra-assertálása. Viewport kizárólag `tester.view.physicalSize`; a `textScaler` külön cellában `MediaQuery`-n megy át. |
| `screen_reader_copy_test.dart` (8 cella) | A2, A6 | `AppLocalizations.delegate.load(Locale('en'\|'hu'))` mellett a `tunerAccuracyLabel`/`strumDirectionLabel` szerződés-építőket méri; az A6 csoport KIFEJEZETTEN megköveteli, hogy a hu kimenet eltérjen az en-től (`isNot`) |
| `docs/ui/accessibility.md` | A7 | Explicit szakasz: „What the automated tests cannot tell you" — kimondja, hogy a zöld `flutter test` szükséges, de nem elégséges bizonyíték, és 8 pontos kézi TalkBack/VoiceOver ellenőrzőlistát ad |

### 10.3 Valódi-sértés próba (§6.1 kötelező)

A `ss_live_region.dart`-ból ideiglenesen kivettem a küszöb-ellenőrzést (csak
a dedup maradt):

```dart
bool report(String value, {required Duration at}) {
  if (value == _lastAnnouncedValue) return false;
  // TEMP — real-violation proof (§10), budget check removed on purpose.
  _lastAnnouncedValue = value;
  _lastAnnouncedAt = at;
  _announcements.add(value);
  notifyListeners();
  return true;
}
```

Ezután lefuttatva KIZÁRÓLAG az A1 „below the threshold" cellát:

```
flutter test test/accessibility/semantics_contract_test.dart --plain-name "below the threshold: rapid readings collapse into the first one"
```

A tényleges hibaüzenet (szó szerint):

```
00:00 +0 -1: A1 — the live region honours the announcement budget (ADR 0280 §2) below the threshold: rapid readings collapse into the first one [E]
  Expected: ['C']
    Actual: ['C', 'G', 'D']
     Which: at location [1] is ['C', 'G', 'D'] which longer than expected

  package:matcher                                        expect
  package:flutter_test/src/widget_tester.dart 473:18     expect
  test/accessibility/semantics_contract_test.dart 27:11  main.<fn>.<fn>
```

A küszöb-ellenőrzést utána visszaállítottam (`git diff` a végén tiszta —
nincs elhagyott TEMP-kód), és a teljes `semantics_contract_test.dart` újra
zöld (13/13).

### 10.4 A kötelező gate eredménye

```
tools/round-gate.sh test/accessibility/semantics_contract_test.dart test/accessibility/tap_target_test.dart test/accessibility/screen_reader_copy_test.dart
```

Minden lépés ZÖLD, csonkítatlan futás:

```
    format                                                     zöld
    analyze                                                    zöld
    test test/accessibility/semantics_contract_test.dart       zöld
    test test/accessibility/tap_target_test.dart               zöld
    test test/accessibility/screen_reader_copy_test.dart       zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
```

(`test/accessibility/semantics_contract_test.dart`: 13/13 teszt zöld;
`tap_target_test.dart`: 6/6; `screen_reader_copy_test.dart`: 8/8.)

### 10.5 Scope

Csak az `allowed_paths` 9 útvonala módosult/jött létre (`git status
--porcelain`):

```
 M lib/core/design_system/foundations/ss_semantics.dart
 M lib/core/design_system/public.dart
?? docs/ui/accessibility.md
?? lib/core/design_system/accessibility/
?? test/accessibility/
```

Komponens-fájlt (`ss_button.dart`, `ss_icon_button.dart`,
`ss_switch_row.dart`, `ss_choice.dart`, `ss_coach_action_card.dart`,
`ss_status_badge.dart`), ARB-forrást vagy `docs/adr/**`-t a kör NEM
módosított — csak olvasta/pumpálta őket a tesztekben, a §0.0/D2 és D4
előírása szerint.

## 11. Review — a Claude tölti ki

**Verdikt: ✅ APPROVED** — nincs BLOCKER, nincs MAJOR. Teljes jelentés:
[`docs/reviews/e13-r14-review.md`](../reviews/e13-r14-review.md).

- A gate **saját kézzel újrafuttatva** izolált `/tmp` klónban: mind a 8 lépés
  zöld, kilépési kód 0 — a §10.4 állítása igaz.
- `tools/scope-audit.py --base origin/main` → `scope_audit=ok`, 9 útvonal.
  (A `--base 5be0a3a3` négy „sértése" a §0.3 upstream-merge `origin/main`-ből
  hozott fájlja, nem a kör munkája — **nem H3**.)
- Mind a 8 acceptance-kritérium tételes bizonyítékkal áll.
- A két kötelező **valódi-sértés próbát a reviewer is lefuttatta**: a
  költségvetés kivétele az A1 „below the threshold" celláját ÉS a felépített
  widget celláját pirosra váltotta (a §10.3 üzenetével szó szerint egyezve);
  az angolra drótozott `tunerAccuracyLabel` az A6 celláját váltotta pirosra.
  Mindkét mutáció visszaállítva.
- 4 MINOR + 3 NOTE **follow-upra** (teszt-higiénia és jövőbeli
  karbantarthatóság; egyik sem érint acceptance-pontot).
