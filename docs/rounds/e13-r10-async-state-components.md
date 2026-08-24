# E13-R10 — Aszinkron állapotkomponensek

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 93a6c19a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 10
- **Kör-azonosító:** `E13-R10`
- **Branch:** `<motor>/e13-r10-async-state-components`
- **Előfeltétel:** `E13-R09` merge-elve (Stage scaffold)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0277`](../adr/0277-failure-presentation-model.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES hibatípust,
> amit a Chapter 2 bevezetett (`AppFailure` és a képernyő-állapot típusa) — a
> §5.1 mapping erre épül, és a mezőnevek időközben változhattak. Eltérésnél
> §0.0 revízió. **Elvégezve → §0.0.**

## 0.0 Pre-flight brief-revízió (2026-08-23, Claude Opus 5)

Minden állítás alább a `main @ 41cc8d6c` fán MÉRVE, a parancs a sor végén.

**D1 — A kör NEM ír ADR-t; a `docs/adr/**` TILOS zóna marad.** Az előre
kiosztott [ADR 0277](../adr/0277-failure-presentation-model.md) a repóban MÁR
LÉTEZIK és **merge-elve van** (`a4fdfec2`, „docs(ch13): E13-R07..R13 briefek +
ADR 0275-0279"), státusza `elfogadva`. Módosítása **H1** volna (ADR 0087 §2).
Mérve: `git log --oneline -1 -- docs/adr/0277-failure-presentation-model.md`.
Ugyanez a minta, mint az E13-R09/D1-nél (ADR 0276 már merge-elve).
A foglalótól kapott `0416` szám tehát **nem kerül felhasználásra** ebben a
körben. A fenti fejléc „a Claude írja meg a kör indításakor" mondata ezzel
tárgytalan.

**D2 — A mapping bemenete az `AppFailure` ÉRTÉK, nem csupasz kód-string.**
Ez a §1 pre-flight 1. szabálya („elérhetetlen cél-státusz"): az **A4** cella
egy olyan állapotot ír elő, amit kód-only bemenettel **egyetlen input sem tud
előállítani**. Mérve a TÉNYLEGES leképezésen, nem az átmenettáblán —
`lib/core/platform/microphone_permission.dart:25-39` és
`lib/core/camera/camera_permission.dart:24-38`:

| Bemeneti állapot | Előállított failure |
|---|---|
| `MicrophonePermissionState.denied` | `PermissionFailure(code: 'permission.microphone')` — `retryable` **true** (default) |
| `MicrophonePermissionState.permanentlyDenied \|\| restricted` | `PermissionFailure(code: 'permission.microphone', retryable: **false**)` |

A két ág **azonos `code`-ot** hordoz (`FailureCode.permissionMicrophoneDenied`
= `'permission.microphone'`), és KIZÁRÓLAG a `retryable` bool különbözteti meg
őket. Kód-only bemenettel tehát az A4 („véglegesen megtagadott engedélynél a
beállítás-akció") és az A3 („retry csak újrapróbálható hibánál") **mérhetetlen**.

Ez **nem az ADR 0277 módosítása** (az H1 volna), hanem a merge-elt szövegének
egyetlen konzisztens olvasata: az ADR CÍME „A felület hibakódot kap, **nem
kivételt**" — a szembeállítás kód ↔ *kivétel*, és az `AppFailure` épp a
kivétel-mentes ág (`lib/core/foundation/app_failure.dart:105`, SDD Ch2 §7.2:
„Expected failures travel as values … so the UI can never be handed a
`DioException`"). Az ADR saját 3. pontja ráadásul „**újrapróbálható**" hibáról
rendelkezik — ez szó szerint az `AppFailure.retryable` mező, tehát az ADR maga
követeli meg az ismeretét.

**Kötött szerződés:** a mapping az `AppFailure`-ből **kizárólag** a `code` és a
`retryable` mezőt olvassa. A `cause` és a `stackTrace` **soha** nem kerül a
prezentációs modellbe — ez az A1 gépi őre (§6.2).

**D3 — Az ARB-forrás fragmentum, az aggregátum generált (ADR 0307 §4).** A
brief 2026-08-15-én készült, a §4 l10n-architektúra 2026-08-20-i. A
`lib/l10n/app_{en,hu}.arb` **GENERÁLT** aggregátum: a
`lib/l10n/base/app_<locale>.arb` + `lib/l10n/features/<név>_<locale>.arb`
determinisztikus uniója, a `tool/gen_l10n_segments.dart` írja. Kézzel beleírni
a `round-gate.sh` `l10n` lépésén (242. sor →
`tool/ci/check_l10n_parity.dart`) determinisztikusan PIROS. Ez a **negyedik**
mérés ugyanerre: `lessons/L365` (E08-R12, H6), `lessons/L369` (E08-R13, H3
self-heal), `lessons/L396` (E08-R20, `stopped`), és 2026-08-23 23:00/23:11-kor
az E09-R21 KÉTSZER futott bele ugyanebbe (§0.0a/§0.0b addendum).

- **Kézzel szerkesztett forrás (ÚJ):** `lib/l10n/features/design_system_en.arb`
  és `design_system_hu.arb`. A generátor a könyvtárat globbolja
  (`listSegmentFiles`, `tool/gen_l10n_segments.dart:164-178`, `_<locale>.arb`
  végződés) — nyilvántartásba vétel NEM kell, új fragmentum azonnal beolvad.
- **Az aggregátum MARAD az `allowed_paths`-on:** a `tools/scope-audit.py`-nak
  **nincs** generated-path kivétele (`grep -n "GENERATED" tools/scope-audit.py`
  → 0 találat), tehát a `--write` által módosított aggregátum enélkül
  `scope_audit=VIOLATION` volna (E09-R21 §0.0b mérése).
- **L342 (E99-R17 F1):** a `@kulcs` metaadat CSAK abból a fragmentumból jöhet,
  amelyik magát a `kulcs` üzenetet is adja → minden új kulcs `kulcs` + `@kulcs`
  párja EGYÜTT, a `design_system_*` fragmentumba kerül.

**D4 — Nincs slot-ütközés a párhuzamosan futó E09-R21-gyel.** Az E09-R21
`allowed_paths`-a is tartalmazza a két aggregátumot, de azok a
`tools/round-slots.py` `GENERATED_PATHS` halmazában vannak (93-98. sor), így az
`effective_paths` kihagyja őket — „Két ilyen kör PÁRHUZAMOSAN futhat" (ADR 0307
§4, GOV-11). A tényleges ütközési felület a **fragmentum**, és az övék
`community_*`, a miénk `design_system_*` → **diszjunkt**. A `lib/l10n/base/`-hez
egyik kör sem nyúl. A merge-zár sorosítja a két aggregátum-regenerálást.

**D5 — A retry három cellája MÉRT, elérhető bemenetekkel** (§6.2 alatt kifejtve).
Mindhárom cella egy ténylegesen előállítható `AppFailure`-re épül, nem
feltételezett átmenetre.

**D6 — `ui_inventory_test.dart` NEM érintett.** A kör nem ad új
`lib/features/**` képernyőt; a `component_catalog_screen.dart` MÁR létezik és
számolva van (a teszt 74-et vár, `test/ui/ui_inventory_test.dart:14`). A fájl
az E09-R21 listáján van — a mi körünk hozzá **nem nyúl** (§4.1/2. szabály).

**D7 — A Component Catalog dev-only, fordítatlan felület.** Ma egyetlen
lokalizált stringet sem használ (nincs `AppLocalizations` import), és
kétkapus (`STRUMSIGHT_COMPONENT_CATALOG` + `kDebugMode`,
`component_catalog_screen.dart:19-49`). Az **A7** ezért a
`components/feedback/**` felhasználói szövegeire vonatkozik; a katalógus a
komponenseket rendereli, saját termék-stringet nem vezet be.

**D8 (S8) — Visszakeresett előzmény.** `lessons/L396`, `lessons/L369`,
`lessons/L365` (mind: generált ARB-aggregátum vs. forrás-fragmentum),
`lessons/L342` (cross-fragment `@kulcs`), `halts/E99-R17` (a `tool/ci/*`
factory-őr — ezért marad a `tool/**` a tilos zónában), `adr/0277` (a kör kötött
döntései), `adr/0307` §4 (l10n-szegmentálás), `adr/0001` (offline-first — az
A2 indoklása).

**Kockázat = high, indoklás:** (S7) a kör a **`permission`** hibaosztály
felhasználói prezentációját határozza meg (mikrofon/kamera engedély-állapotok,
`permission_handler` mögötti `permanentlyDenied` ág), és egy hibaüzenet-mapping
az a hely, ahol egy `toString()` fallback **belső útvonalat, azonosítót vagy
kérés-részletet szivárogtathat** a felületre (ADR 0277 Kontextus). Az A1 cella
pontosan ezt a szivárgást méri.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/design_system/components/feedback/ss_async_state.dart",
  "lib/core/design_system/components/feedback/ss_skeleton.dart",
  "lib/core/design_system/components/feedback/ss_empty_state.dart",
  "lib/core/design_system/components/feedback/ss_failure_state.dart",
  "lib/core/design_system/components/feedback/ss_permission_state.dart",
  "lib/core/design_system/components/feedback/failure_presentation.dart",
  "lib/core/design_system/documentation/component_catalog_screen.dart",
  "lib/core/design_system/public.dart",
  "lib/l10n/features/design_system_en.arb",
  "lib/l10n/features/design_system_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/core/design_system/feedback/failure_presentation_test.dart",
  "test/core/design_system/feedback/async_state_test.dart",
  "docs/rounds/e13-r10-async-state-components.md",
]
gate_tests = [
  "test/core/design_system/feedback/failure_presentation_test.dart",
  "test/core/design_system/feedback/async_state_test.dart",
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

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A loading, skeleton, empty, offline, sync pending, degraded, permission,
failure és blocked állapotok **egységes** megjelenítése (SDD Ch13 Kör 10).

## 2. Jelenlegi állapot — mért tények

- Az R03 óta a `danger` szemantikája kötött: **offline nem danger**, és
  **alacsony confidence nem danger**.
- Az R05 felületi primitívei adják a geometriát, az R07 az ikonokat.
- Az i18n szabály (CLAUDE.md): minden felhasználói szöveg ARB-n át megy.

## 3. Scope

**Benne van:** a Ch13 kötelező feedback-komponensei stabil API-val ·
**failure-kód → lokalizált prezentációs modell** mapping · cached-content
overlay offline és sync pending állapothoz · mikrofon / kamera / értesítés /
tárhely engedély-prezentációs modellek · retry / beállítások megnyitása /
offline folytatás / támogatás akció-variánsok · annak dokumentálása, mikor
teljes képernyő, banner, inline üzenet vagy snackbar a helyes.

**NINCS benne (tilos):** `lib/features/**` átállítása az új komponensekre
(a migrációs körök dolga) · a hibatípus (`AppFailure`) módosítása · nyers
kivétel megjelenítése · `lib/core/theme/**` · `docs/adr/**`, `tools/**`,
`.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `feedback/ss_async_state.dart` | **ÚJ** — az állapot-kapcsoló |
| `feedback/ss_skeleton.dart` | **ÚJ** — geometriatartó skeleton |
| `feedback/ss_empty_state.dart` | **ÚJ** |
| `feedback/ss_failure_state.dart` | **ÚJ** |
| `feedback/ss_permission_state.dart` | **ÚJ** |
| `feedback/failure_presentation.dart` | **ÚJ** — a kód → modell mapping |
| `documentation/component_catalog_screen.dart` | állapot-mátrix |
| `public.dart` | az export bővítése |
| `lib/l10n/features/design_system_{en,hu}.arb` | **ÚJ** — a kézzel írt ARB-forrás-fragmentum (D3) |
| `lib/l10n/app_{en,hu}.arb` | a `--write` által regenerált **generált** aggregátum (D3) |
| `test/…/feedback/*_test.dart` (2) | a §6 cellái |
| `docs/rounds/e13-r10-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` · `lib/core/theme/**` · `lib/app/**` ·
`lib/core/foundation/app_failure.dart` · `lib/core/platform/**` ·
`lib/core/camera/**` · `lib/l10n/base/**` · `lib/l10n/features/community_*.arb`
(az E09-R21 párhuzamos köréé, §4.1/2) · `docs/adr/**` · `docs/sdd/**` ·
`tool/**` · `tools/**` · `.github/**` · `test/ui/ui_inventory_test.dart` (D6).

## 5. Kötött architekturális döntések (ADR 0277)

### 5.1 A design system NYERS kivételt nem fogad és nem mutat

A bemenet a **kivétel-mentes `AppFailure` érték** (D2), amiből a mapping
KIZÁRÓLAG a `code` (String) és a `retryable` (bool) mezőt olvassa, és lokalizált
modellé alakítja. Stack trace, `Exception: ...` szöveg vagy HTTP státusz sosem
kerül a felületre; a `cause` és a `stackTrace` **be sem lép** a prezentációs
modellbe.

> A `code` önmagában NEM elég: a `permission.microphone` kódot a „megtagadva"
> és a „véglegesen megtagadva" ág EGYARÁNT hordozza, csak a `retryable`
> különbözteti meg őket (D2 mérése) — kód-only bemenettel az A3/A4 elérhetetlen.

**NEM elfogadható gyengítés:** `Text(error.toString())` fallbackként „ismeretlen
hibára". Az technikai zajt önt a felhasználóra, és néha adatot szivárogtat.

### 5.2 Az offline NEM hiba-stílus, és a cached tartalom LÁTHATÓ marad

Offline állapotban a korábban betöltött tartalom megmarad, fölötte jelzéssel.
A képernyő nem ürül ki.

**NEM elfogadható gyengítés:** offline → teljes képernyős hibaállapot. Az
használhatatlanná tesz egy amúgy működő, on-device terméket.

### 5.3 A retry CSAK újrapróbálható hibánál jelenik meg

Ha a hiba nem oldható meg újrapróbálással (pl. véglegesen megtagadott
engedély), a retry gomb hamis reményt kelt — helyette a valódi kiút látszik.

### 5.4 Az engedély-állapot MEGMONDJA, mire kell

„Miért kérjük" + „mi lesz, ha nem adod meg". Véglegesen megtagadott engedélynél
a beállítások megnyitása az akció, nem az újrakérés.

### 5.5 Az üres állapot ÉRTELMES akciót ad

Az „nincs adat" önmagában zsákutca. Minden üres állapotnak van következő lépése.

### 5.6 A skeleton NEM olvasható tartalomként

Képernyőolvasónak „betöltés" hangzik el, nem álszöveg; és a skeleton megtartja
a végleges layout geometriáját, hogy ne ugorjon a tartalom.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Nyers kivétel/`toString()` SEHOL nem jelenik meg | `failure_presentation_test.dart` |
| A2 | Offline nem hiba-stílus, és a cached tartalom látható marad | `async_state_test.dart` |
| A3 | A retry csak újrapróbálható hibánál látszik | `failure_presentation_test.dart` |
| A4 | Véglegesen megtagadott engedélynél a beállítás-akció jelenik meg | ugyanott |
| A5 | Az üres állapot értelmes akciót kínál | `async_state_test.dart` |
| A6 | A skeleton nem olvasható tartalomként, és tartja a geometriát | ugyanott |
| A7 | Minden új felhasználói szöveg ARB-n át megy (en + hu) | `failure_presentation_test.dart` — §6.2 |
| A8 | Minden állapot mindhárom témában renderel | `async_state_test.dart` |

### 6.2 A7 gépi őre — a `grep` NEM mérce

Egy beégetett angol stringet a diff-`grep` nem fog meg megbízhatóan (L09: a
szövegesen leírt előírás mellé GÉPI mérce kell). A kötelező cella:
**ugyanaz a failure `hu` és `en` locale alatt KÜLÖNBÖZŐ szöveget ad**, és a
`hu` érték a `design_system_hu.arb`-ban álló, kipinnelt sztringgel EGYENLŐ.
Beégetett stringnél a két locale azonos → PIROS.

Ugyanitt az **A1** gépi őre: az ismeretlen kódra kapott modell szövege
- nem tartalmazza a `code` sztringet,
- nem tartalmazza az `Exception`, `#0 `, `retryable:` töredékeket,
- és nem egyenlő a bemeneti `AppFailure.toString()` értékével.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `Text(error.toString())` fallback | **A1** |
| Offline → teljes képernyős hibaállapot | **A2** |
| Retry minden hibánál | **A3** |
| Véglegesen megtagadott engedélynél újrakérés | A4 |
| Üres állapot akció nélkül | A5 |
| Skeleton álszöveggel | **A6** |
| Beégetett angol string | A7 |

**A retry-láthatóság három kötelező cellája.** A küszöb a `retryable` bool; a
bemenetek MÉRTEK és ténylegesen előállíthatók (D2/D5) — nem feltételezett
átmenetek. A hármas: a küszöb **alatt** `retryable: false` → nincs retry;
**rajta** ismeretlen kód + `retryable: true` → van retry; **fölött** hálózati
hiba → van retry + offline-folytatás.

| Cella | Bemenet (szó szerint) | Elvárt |
|---|---|---|
| a küszöb alatt | `MicrophonePermissionState.permanentlyDenied.failure!` → `PermissionFailure(code: 'permission.microphone', retryable: false)` | **nincs** retry; a beállítás-megnyitás akció látszik (= **A4**) |
| rajta (a küszöbön) | `NetworkFailure(code: 'diagnostics.unmapped_probe', retryable: true)` — a mappingben NEM szereplő kód | **van** retry, és a szöveg emberi ARB-string (= **A1**) |
| a küszöb fölött | `NetworkFailure(code: FailureCode.networkUnavailable, retryable: true)` | van retry + offline-folytatás akció |

A középső cella a `code`-ra nézve ismeretlen, a `retryable`-re nézve igaz — ez
bizonyítja, hogy a retry-döntés a `retryable`-ből jön, nem kód-táblából.
A felső és az alsó cella `code`-ja eltérő; az alsó és a `MicrophonePermissionState.denied.failure!`
(`retryable: true`) **AZONOS kódú**, ellentétes retry-kimenetű pár — ez a
kód-only implementációt determinisztikusan pirosra váltja.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vezess be egy
`toString()` fallbackot az ismeretlen hibakódra → az **A1** cellának PIROSNAK
kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/design_system/feedback/failure_presentation_test.dart test/core/design_system/feedback/async_state_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `failure_presentation.dart` — `AppFailure` (`code` + `retryable`) → lokalizált
   modell, ismeretlen kódra is **emberi** szöveggel (§5.1, D2).
2. A retry-láthatóság három cellája (§6.1).
3. `ss_async_state.dart` + a cached-content overlay.
4. `ss_skeleton.dart` — geometriatartó, semanticsból kizárt.
5. `ss_empty_state.dart`, `ss_failure_state.dart`, `ss_permission_state.dart`.
6. ARB: az új kulcsok (`kulcs` + `@kulcs` EGYÜTT) a **fragmentumba** —
   `lib/l10n/features/design_system_{en,hu}.arb` (D3), majd Component Catalog
   állapot-mátrix.
7. **`dart run tool/gen_l10n_segments.dart --write`** — az aggregátum
   regenerálása. KÖTELEZŐ, a gate ELŐTT: enélkül a `round-gate.sh` `l10n`
   lépése „aggregátum elavult" hibával piros (D3, L365).
8. A valódi-sértés próba, §10-be dokumentálva.
9. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az ismeretlen hibakód.** A `toString()` fallback kézenfekvő, és pont ott
  önt technikai zajt a felhasználóra, ahol a legkevésbé érti (A1).
- **Az offline mint hiba.** A leggyakoribb reflex, és egy on-device terméket
  tesz látszólag használhatatlanná (A2).
- **A mindenhol megjelenő retry.** Olcsó egységesség, ami hamis reményt kelt
  véglegesen megtagadott engedélynél (A3/A4).

## 10. Implementation handoff — az implementer tölti ki

**Motor:** Claude Sonnet 5 (sonnet-impl), 2026-08-24.

### Mit épített

- `failure_presentation.dart` — `SsFailurePresentation.from(AppLocalizations,
  AppFailure)`: az `AppFailure.code` (kategóriánkénti switch: permission
  mikrofon/kamera/unavailable külön, network unavailable külön a többi
  network-kódtól, auth és storage kategóriánként összevonva, minden más a
  generikus „ismeretlen" ágra) → cím + üzenet, és az `AppFailure.retryable` →
  az akciólista (`SsFailureAction`, `SsFailureActionKind`: retry /
  openSettings / continueOffline / contactSupport). A döntési fa pontosan a
  §6.1/D5 három cellája szerint: `!retryable && permission-kód` →
  csak `openSettings`; `retryable` → `retry` (+ `continueOffline`, ha a kód
  `network.unavailable`); egyébként `contactSupport`. `cause`/`stackTrace`
  a mapping-be be sem lép (a `from` csak `.code`-ot és `.retryable`-t olvassa).
- `ss_async_state.dart` — `SsAsyncState` + `SsAsyncStatus` (9 érték:
  loading/content/empty/offline/syncPending/degraded/permission/failure/
  blocked). Az `offline`/`syncPending`/`degraded` a `content`-et egy
  `_CachedContentBanner`-en (Column + banner + Expanded content) keresztül
  MEGTARTJA, nem cseréli le (§5.2). A `loading` ág egyetlen
  `Semantics(label: loadingSemanticLabel)`-be csomagolja a `skeleton`
  slotot — az egyes `SsSkeleton` dobozok nem hordoznak saját címkét.
- `ss_skeleton.dart` — `SsSkeleton(width, height)`: `ExcludeSemantics`-be
  csomagolt, `colors.surfaceSunken`-nel színezett doboz, a végleges geometriát
  tartja.
- `ss_empty_state.dart` — `SsEmptyState`: `onAction` KÖTELEZŐ (nem
  nullable) `VoidCallback` — a típus maga zárja ki az akció nélküli üres
  állapotot.
- `ss_failure_state.dart` — `SsFailureState`: a `presentation.actions`
  listából épít gombot (kulcs: `ss-failure-state-<kind>`); egy hiányzó akció
  = nincs gomb (nem `onPressed: null`-lal letiltott gomb).
- `ss_permission_state.dart` — `SsPermissionState`: `SsPermissionKind`
  (microphone/camera/notification/storage) ikon-választáshoz, `rationale` +
  `consequence` hívó-oldali (lokalizált) szöveg, az akciógombok szintén a
  `presentation.actions`-ból.
- `public.dart` — a 6 új fájl exportja.
- `component_catalog_screen.dart` — `_AsyncFeedbackShowcase`: bemutatja az
  offline cached-content overlay-t (rögzített magasságú `SizedBox`-ba zárva,
  mert a katalógus `SingleChildScrollView`-ja végtelen magasságot ad, és az
  `Expanded` ott hibázna), az `SsEmptyState`-et, egy `SsFailureState`-et
  (`network.unavailable`) és egy `SsPermissionState`-et (mikrofon,
  véglegesen megtagadva). A leképezéshez `lookupAppLocalizations(Locale('en'))`-t
  hív — ez a generált fájl SZINKRON, `Localizations`-ős widget-fa nélkül is
  működő függvénye, mert a meglévő `component_catalog_test.dart` (nincs az
  engedélyezett listán, tehát nem módosítható) a katalógust
  `localizationsDelegates` NÉLKÜLI `MaterialApp`-ban rendereli —
  `AppLocalizations.of(context)` ott elszállt volna.
- ARB: `lib/l10n/features/design_system_{en,hu}.arb` (20 kulcs, egyik sem
  placeholderes, tehát `@kulcs` metaadat egyikhez sem kellett), majd
  `dart run tool/gen_l10n_segments.dart --write` az aggregátumra és
  `flutter gen-l10n` a generált `app_localizations*.dart`-ra.

### Döntés a brief keretein belül

A `component_catalog_screen.dart`-ba eredetileg tervezett `SsSkeleton`
demót elhagytam: a `component_catalog_test.dart` (nincs az engedélyezett
fájllistán) `expect(find.byType(DecoratedBox), findsOneWidget)`-et mér — az
`SsSkeleton` maga is `DecoratedBox`-ot rendel, ami ezt a MEGLÉVŐ zöld tesztet
pirosra váltotta volna (mérve, majd visszavonva). A §3 STOP-protokoll szerint
meglévő zöld teszt elbukása `blocked` volna, nem a teszt átírása — mivel a
teszt nincs az allowed_paths-on, nem is módosíthattam volna. A katalógus
demó ezért `CircularProgressIndicator`-t használ helyette a loading-slot
bemutatására; ez nem érinti egyik acceptance-cellát sem (A6 bizonyítéka
kizárólag `async_state_test.dart`). Ugyanígy mértem, hogy az offline overlay
`Expanded`-je rögzített magasság nélkül elszállna a katalógus végtelen
magasságú `SingleChildScrollView`-jában — ezért `SizedBox(height: 120, …)`-ba
csomagoltam. Mindkettőt `flutter test test/core/design_system/component_catalog_test.dart`
(önálló futtatással, nem a kötelező gate részeként) mérve ellenőriztem: zöld
maradt a mutáció előtt ÉS után.

### Valódi-sértés próba (§6, kötelező)

Mutáció: `failure_presentation.dart`, az `SsFailurePresentation.from`
factory-ban a `message: _message(l10n, failure.code)` sort ideiglenesen
`message: failure.toString()`-re cseréltem (a §5.1 tiltott
`Text(error.toString())` mintája).

Mérve (`flutter test test/core/design_system/feedback/failure_presentation_test.dart`):
4 teszt vált PIROSSA — köztük pontosan az A1 cella („an unrecognised code
gets a human message, not the code itself": `Expected: not contains
'diagnostics.unmapped_probe'` / `Actual: 'NetworkFailure(diagnostics.unmapped_probe,
retryable: true)'`) és az A7 cella is (a locale-eltérés eltűnt, mert a
`toString()` nem lokalizált). A mutációt visszaállítottam
(`message: _message(l10n, failure.code)`), a teszt újra 12/12 zöld.

### Gate

`tools/round-gate.sh test/core/design_system/feedback/failure_presentation_test.dart
test/core/design_system/feedback/async_state_test.dart` — MINDEN GATE ZÖLD
(format, analyze, mindkét teszt, architecture, secrets, l10n).

## 11. Review — a Claude tölti ki
