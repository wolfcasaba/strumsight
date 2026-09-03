# E15-R09 — AI Tutor képernyők migrálása

- **Státusz:** PREPARED (előre megírva 2026-08-28, kód olvasva: `main @ 4cb32eb0`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 9
- **Kör-azonosító:** `E15-R09`
- **Branch:** `<motor>/e15-r09-ai-tutor-migration`
- **Előfeltétel:** `E15-R03` merge-elve (a visszavonási terv dönti el, mit KELL migrálni)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — migrációs kör, kötött ÚJ architekturális döntés nélkül (a hivatkozott szerződéseket korábbi ADR-ek rögzítik).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "ai tutor chat home privacy profile UI"` → **[ADR 0132](../adr/0132-ai-tutor-privacy-and-consent.md)** (Tutor privacy & consent) és **[ADR 0213](../adr/0213-ai-tutor-production-wiring-and-sse-transport.md)** (production-drótozás, SSE transport) — a migráció sem a consent-kapukat, sem a stream-kezelést nem írhatja át.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd be a `docs/ui/retirement-plan.md` (E15-R03) sorait erre a batch-re, és mérd újra, mely képernyők legacyk MÉG:
> ```bash
> for f in lib/features/ai_tutor/presentation/screens/tutor_home_screen.dart lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart lib/features/ai_tutor/presentation/screens/tutor_profile_screen.dart lib/features/ai_tutor/presentation/screens/tutor_data_screen.dart lib/features/ai_tutor/presentation/screens/tutor_privacy_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
> ```
> A megíráskor mind a **5** felsorolt képernyő legacy volt. Ami időközben migrálódott, azt a §3 scope-ból ki kell venni.

## 0.0 A kör határa: MEGJELENÉS, nem viselkedés

A migráció a képernyők VIZUÁLIS rétegét cseréli design-rendszer-komponensekre. A képernyő TÍPUSA, route-ja, publikus API-ja és üzleti viselkedése VÁLTOZATLAN — a típus-pinnelő tesztek (§4) ezért maradnak zöldek, és a jogosultság pontosan ennyi: **cella törlése, `skip`-je vagy gyengítése TILOS**. Az `E15-R01` óta az app témája hordozza a tokeneket, tehát ÚJ `*ThemeScope` burkoló NEM vezethető be; a meglévő burkoló eltávolítható, ha a képernyő már az app témájából old fel.

Az `E15-R02` óta a Coach destination látszik a shellben, tehát a Tutor öt képernyője a fő navigációból elérhető — legacy megjelenéssel és a hálózati hibaállapotok mai, nyers formájában.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/presentation/screens/tutor_home_screen.dart",
  "lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart",
  "lib/features/ai_tutor/presentation/screens/tutor_profile_screen.dart",
  "lib/features/ai_tutor/presentation/screens/tutor_data_screen.dart",
  "lib/features/ai_tutor/presentation/screens/tutor_privacy_screen.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/features/ai_tutor/presentation/tutor_chat_screen_test.dart",
  "test/features/ai_tutor/presentation/tutor_data_screen_test.dart",
  "test/features/ai_tutor/presentation/tutor_privacy_screen_test.dart",
  "test/features/ai_tutor/presentation/tutor_profile_screen_test.dart",
  "test/features/tutor/ai_mode_visibility_test.dart",
  "test/features/tutor/streaming_announcement_test.dart",
  "test/ui/goldens/e13_r29_screens_golden_test.dart",
  "test/ui/goldens/goldens/e13_r29_coach_home_compact.png",
  "test/ui/goldens/goldens/e13_r29_coach_home_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r29_coach_chat_compact.png",
  "test/ui/goldens/goldens/e13_r29_coach_chat_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r29_practice_plan_preview_compact.png",
  "test/ui/goldens/goldens/e13_r29_practice_plan_preview_compact_scale2.png",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "docs/ui/migration-status.md",
  "docs/rounds/e15-r09-ai-tutor-migration.md",
]
gate_tests = [
  "test/ui/ui_inventory_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/features/ai_tutor/presentation/tutor_chat_screen_test.dart",
  "test/features/ai_tutor/presentation/tutor_data_screen_test.dart",
  "test/features/ai_tutor/presentation/tutor_privacy_screen_test.dart",
  "test/features/ai_tutor/presentation/tutor_profile_screen_test.dart",
  "test/features/tutor/ai_mode_visibility_test.dart",
  "test/features/tutor/streaming_announcement_test.dart",
  "test/ui/goldens/e13_r29_screens_golden_test.dart",
  "test/l10n/arb_parity_test.dart",
  "test/l10n/hardcoded_string_guard_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a diff felhasználói felületet ír át azon az úton, amit a felhasználó a leggyakrabban jár; egy elveszett állapot- vagy hibajelzés némán rontaná az élményt. A `flutter-reviewer` és a `flutter-devil-advocate` futtatása a review-ban KÖTELEZŐ.

## 0.0.A Pre-flight brief-revízió (Claude / Opus 5 orchestrátor, 2026-09-03, `main @ e9691f74`)

A brief 2026-08-28-i mért állításait a kör indítása előtt újramértem. Az alábbi
nyolc revízió KÖTELEZŐ; ütközés esetén ez a szakasz erősebb a brief korábbi
szövegénél. Visszakeresés (ADR 0312): `node tools/knowledge-rag.mjs --corpus
lessons,halts,adr --top 5 "ai tutor képernyő migráció design-rendszer SsCard
SsErrorState"` → [ADR 0273](../adr/0273-design-system-token-source-of-truth.md),
[ADR 0277](../adr/0277-failure-presentation-model.md), [L559](../LESSONS.md#l559);
`--corpus lessons,halts "design-rendszer token feloldás ThemeScope widget teszt
null-check összeomlás"` → [L387](../LESSONS.md#l387), [L466](../LESSONS.md#l466),
[L382](../LESSONS.md#l382). A batch közvetlen precedense az `E15-R08`
(`docs/rounds/e15-r08-gamification-migration.md` §0.0.A/R4, R8, R9 + `docs/ui/migration-status.md`
E15-R08 bejegyzése).

### R1 — A scope teljes egészében áll (mérve)

```
legacy lib/features/ai_tutor/presentation/screens/tutor_home_screen.dart
legacy lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart
legacy lib/features/ai_tutor/presentation/screens/tutor_profile_screen.dart
legacy lib/features/ai_tutor/presentation/screens/tutor_data_screen.dart
legacy lib/features/ai_tutor/presentation/screens/tutor_privacy_screen.dart
```

Mind az 5 képernyő legacy → a §3 scope-ból semmit nem kell kivenni. A
`retirement-plan.md` §4 táblája ezt a batch-et `E15-R05`-be írja (kör-számsodródás,
ugyanaz az osztály, mint az E15-R08-nál); az irányadó a queue sora és ez a brief,
a `retirement-plan.md` NINCS az `allowed_paths`-on, tehát változatlan marad.

### R2 — Az `ai_tutor` feature-nek NINCS `*ThemeScope` burkolója (mérve)

`grep -rn "class .*ThemeScope" lib/` → 9 találat (settings, auth, library_v2, share,
gamification, progress_v2, community, offline_ai, vision), `ai_tutor` NINCS köztük;
`grep -rn "ThemeScope" lib/features/ai_tutor/presentation/screens/` → 0 találat.
Ezért a §3 „a meglévő `*ThemeScope` burkoló eltávolítása" kikötése ezen a batch-en
**tárgytalan** (no-op), a §3 tiltása pedig (`Új *ThemeScope burkoló bevezetése`)
**VÁLTOZATLANUL ÉL**: a kör NEM vezet be `TutorThemeScope`-ot vagy bármi vele
egyenértékű téma-burkolót sem `lib/`-ben, sem teszt-helperben widget formájában.

### R3 — A token-feloldás mért útja: a HARNESS adja, nem a képernyő

Mérve:

- minden design-rendszer komponens `Theme.of(context).extension<SsColorScheme>()!`
  alakban old fel (bang, nem null-tűrő) — pl. `ss_button.dart:57`,
  `ss_empty_state.dart:29`, `ss_failure_state.dart:32`, `ss_metric_card.dart:48`;
- `lib/core/theme/app_theme.dart:47` → `extensions: [palette]`, tehát az `AppTheme`
  a design-rendszer kiterjesztéseit **NEM** hordozza;
- `lib/app/strumsight_app.dart:33-34` → a futásidejű app gyökere `SsLightTheme.data()`
  / `SsDarkTheme.data()`, tehát **PRODUKCIÓBAN a feloldás mért módon rendben van**;
- a kör mind a 6 kipinnelt widget-tesztje csupasz `MaterialApp`-ot pumpál
  (`tutor_chat_screen_test.dart:196`, `tutor_data_screen_test.dart:247`,
  `tutor_privacy_screen_test.dart:146`, `tutor_profile_screen_test.dart:61`,
  `ai_mode_visibility_test.dart:125` és `:146`, `streaming_announcement_test.dart:119`)
  → a kiterjesztések ott ma HIÁNYOZNAK.

**Következmény és kötelező megoldás:** a migrált képernyő komponens-használata
ezekben a harnessekben null-check összeomlást adna. A feloldás a teszt-harness
téma-drótozása — a hat teszt-fájl az `allowed_paths`-on VAN —, a mért precedens
`test/features/practice_generator/presentation/today_plan_screen_test.dart:141-142`
(`MaterialApp(theme: SsLightTheme.data())`). Ez **nem** cella-gyengítés: egyetlen
cella sem törölhető, `skip`-elhető vagy lazítható (§0.0), a kipinnelt elvárások
(`find.byType(TutorMessageBubble/TutorComposer/TutorBanner/TextField/Padding/Scrollable)`,
kulcsok, szövegek) szó szerint maradnak. Ha egy cella szándékosan téma nélküli
`MaterialApp`-ot mér (`ai_mode_visibility_test.dart:121-125` kommentje), a téma
hozzáadása CSAK annyi, amennyi a képernyő rendereléséhez kell.

### R4 — A golden-sáv KONSTRUKCIÓBÓL érintett: téma-csere + újrafelvétel

`test/ui/goldens/e13_r29_screens_golden_test.dart` a `_pump` (`:96-125`) helyén
`theme: AppTheme.dark()`-ot pumpál, és `TutorHomeScreen` (`:173`), `TutorChatScreen`
(`:187`), `PracticePlanPreviewScreen` (`:209`) képernyőt hasonlít 6 committolt
PNG-hez. A fájl fejléc-kommentje (`:5-8`) azt állítja, hogy egyik képernyő
perzisztens fája sem függ a design-rendszer kiterjesztéseitől — ez a migráció után
**HAMIS**, tehát a kommentet is javítani KELL.

Kötött megoldás: a `_pump` témája `SsDarkTheme.data()` legyen (ez a futásidejű app
sötét témája, `strumsight_app.dart:34` — a golden így hűbb lesz a valósághoz, nem
lazább), és mind a **6** `e13_r29_*` PNG újrafelvételre kerül. Az `allowed_paths`
ezért egészült ki a 6 PNG-vel — a bővítés a brief §7 SAJÁT újrafelvételi
előírásának mechanikus következménye, nem scope-tágítás.

Az újrafelvétel KIZÁRÓLAG a merge-kapu architektúráján (ADR 0426); az előfeltétel
ezen a boxon MÉRVE megvan (`docker 29.4.0`, `strumsight-golden-x86:3.44.2` image jelen):

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r29_screens_golden_test.dart
```

### R5 — A komponens-nevek javítása (a §3/§5.2 két nevet tévesen ír)

Mérve (`lib/core/design_system/`): **NINCS** `SsFailureState` (§0.0.A/R5), `SsListTile` és
`SsMetricTile` osztály. A ténylegesen létező, ide illő nevek: `SsCard`,
`SsContentCard`, `SsInsightCard`, `SsMetricCard`, `SsButton`, `SsIconButton`,
`SsEmptyState`, **`SsFailureState`** (hibaállapot, `SsFailurePresentation`
bemenettel — ADR 0277), `SsSkeleton` (betöltés), `SsSection`, `SsSurface`,
`SsSwitchRow`, `SsStatusBadge`, `SsTextField`, valamint az `SsSpacing`/
`SsTypography`/`SsRadius`/`SsColorScheme` tokenek. A §3 és §5.2 minden
`SsFailureState` (§0.0.A/R5) említése **`SsFailureState`-ként**, minden `SsListTile`/`SsMetricTile`
említése a fenti tényleges megfelelőjeként olvasandó.

### R6 — Az `SsEmptyState`/`SsFailureState` kötelezettsége és a mért kivétel-osztály

Az `SsEmptyState` API-ja `required actionLabel` + `required onAction` (`:14-18`),
tehát VALÓDI következő lépést feltételez (ADR 0277 §5). Ahol a képernyő üres
állapotának mérten NINCS valódi akciója, ott az E15-R04/R06/R07/R08 precedens
kivétel-osztálya érvényes: a komponens NEM kényszeríthető ki hamis akcióval, az
állapot marad képernyő-lokális widget, de **KÖTELEZŐEN** `SsColorScheme`/
`SsTypography`/`SsSpacing` tokenekkel stílusozva — és a §10-ben képernyőnként,
mért indoklással dokumentálva. A brief §3 kifejezetten megnevezett esete (a
chat-képernyő „nincs backend" hibaállapota, ma nyers szöveg) NEM tartozik a
kivételbe: annak `SsFailureState`-et kell kapnia újrapróba-akcióval, ha a hiba
mérten újrapróbálható (ADR 0277 §3).

### R7 — ARB: a §3 engedélye és a fájllista ütközött (feloldva)

A §3 kimondottan engedi új kulcs felvételét mindkét locale-ra, de a `lib/l10n/*.arb`
NEM volt az `allowed_paths`-on — ez a brief hibája volt, nem tilos zóna. A két ARB
fájl felkerült a listára, a tiltás VÁLTOZATLAN: kulcs **nem törölhető**, meglévő
kulcs jelentése **nem változhat**, új kulcs csak `en` ÉS `hu` párban. A célzott
gate ezért kiegészült a `test/l10n/arb_parity_test.dart` és a
`test/l10n/hardcoded_string_guard_test.dart` cellákkal (mérce-erősítés).

### R8 — ADR: nincs, és nem is kell

A kör nem hoz ÚJ architekturális döntést: a token-forrás (ADR 0273), a
hiba-prezentáció (ADR 0277), a Tutor consent-kapui (ADR 0132) és az SSE-transport
(ADR 0213) mind merge-elt szerződések, amelyeket a migráció HASZNÁL, nem ír át. A
golden téma-cseréje (R4) teszt-hűségi javítás a már merge-elt futásidejű témára,
nem új döntés. `tools/round-slots.py reserve-adr` ezért nem futott; ha az
implementer szerint ÚJ architekturális döntés kellene, az **STOP-eset**
(`stopped` jelzés), nem önkezű ADR-írás.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a migrációhoz egy `application/`, `domain/` vagy `data/` réteg módosítása kellene, a kimenet a `stopped` jelzés — a viselkedés-változás nem ennek a körnek a hatásköre ([L478](../LESSONS.md#l478)).

## 1. Cél

A batch 5 képernyője a design-rendszer komponenseit és tokenjeit használja, változatlan viselkedés mellett — hogy a felület egységes legyen, és a 200%-os szövegskála, a képernyőolvasó és a két locale mindenhol működjön.

## 2. Jelenlegi állapot — mért tények

- A batch képernyői (MÉRVE `grep -L design_system`): `tutor_home_screen.dart`, `tutor_chat_screen.dart`, `tutor_profile_screen.dart`, `tutor_data_screen.dart`, `tutor_privacy_screen.dart`.
- Egyik sem importálja a `core/design_system`-et; a stílusuk közvetlen `Theme.of(context)` / `AppColors` / `AppPalette` hivatkozásokból jön.
- Az `E15-R01` óta az app futásidejű témája a design-rendszer témája, tehát a komponensek burkoló NÉLKÜL is feloldják a tokeneket.
- Az `E15-R02` óta az adaptív shell az alapértelmezett belépő, tehát ezek a képernyők a fő navigációból elérhetők.
- A `test/ui/ui_inventory_test.dart` EGZAKT képernyőszámot állít — a kör nem hoz létre és nem töröl képernyőt, tehát a szám VÁLTOZATLAN.

## 3. Scope

**Benne van:** a felsorolt 5 képernyő vizuális migrálása (`SsCard`, `SsButton`, `SsListTile`, `SsEmptyState`, `SsFailureState` (§0.0.A/R5), `SsMetricTile` és társaik; `SsSpacing`/`SsTypography` tokenek) · a meglévő `*ThemeScope` burkoló eltávolítása, ahol az `E15-R01` óta felesleges · a `migration-status.md` frissítése a MÉRT új aránnyal.

Batch-specifikus kikötések:

- a chat-képernyő stream-kezelése (SSE, részleges válasz, megszakítás) VISELKEDÉSBEN változatlan; a buborékok és az állapotjelzők kerülnek komponensekre
- a hibaállapot (nincs backend) `SsFailureState` (§0.0.A/R5) komponenst kap — ez a MÉRT állapot ma nyers szöveg
- a privacy- és adat-képernyő consent-kapcsolói és szövegei érintetlenek (ADR 0132)

**NINCS benne (tilos):**

- `application/`, `domain/`, `data/`, `providers/` réteg módosítása (viselkedés-változás).
- Új képernyő létrehozása vagy meglévő törlése.
- Új `*ThemeScope` burkoló bevezetése.
- ARB-kulcs törlése vagy szöveg-jelentés megváltoztatása (új kulcs FELVEHETŐ, ha a komponens ezt igényli — mindkét locale-ra, egyszerre).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/ai_tutor/presentation/screens/tutor_home_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/ai_tutor/presentation/screens/tutor_profile_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/ai_tutor/presentation/screens/tutor_data_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/ai_tutor/presentation/screens/tutor_privacy_screen.dart` | migráció design-rendszer komponensekre |
| `test/app/navigation/adaptive_scaffold_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/app/offline_network_guard_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/ai_tutor/presentation/tutor_chat_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/ai_tutor/presentation/tutor_data_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/ai_tutor/presentation/tutor_privacy_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/ai_tutor/presentation/tutor_profile_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/tutor/ai_mode_visibility_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/tutor/streaming_announcement_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r29_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/goldens/e13_r29_coach_home_compact.png` | golden újrafelvétel (§0.0.A/R4) |
| `test/ui/goldens/goldens/e13_r29_coach_home_compact_scale2.png` | golden újrafelvétel (§0.0.A/R4) |
| `test/ui/goldens/goldens/e13_r29_coach_chat_compact.png` | golden újrafelvétel (§0.0.A/R4) |
| `test/ui/goldens/goldens/e13_r29_coach_chat_compact_scale2.png` | golden újrafelvétel (§0.0.A/R4) |
| `test/ui/goldens/goldens/e13_r29_practice_plan_preview_compact.png` | golden újrafelvétel (§0.0.A/R4) — a téma-csere a megosztott `_pump`-ban van |
| `test/ui/goldens/goldens/e13_r29_practice_plan_preview_compact_scale2.png` | golden újrafelvétel (§0.0.A/R4) |
| `lib/l10n/app_en.arb` | ÚJ kulcs felvétele, ha a komponens igényli (§0.0.A/R7) — törlés/jelentés-változtatás TILOS |
| `lib/l10n/app_hu.arb` | ugyanaz, párban (§0.0.A/R7) |
| `docs/ui/migration-status.md` | a MÉRT arány frissítése |

**Tilos zóna:** a batch feature-einek `application/`, `domain/`, `data/`, `providers/` könyvtárai · minden más `lib/features/**` képernyő · `lib/app/**` · `lib/core/design_system/**` (a komponenseket HASZNÁLJUK, nem módosítjuk) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

Nincs ÚJ ADR. Három kötelező szabály:

### 5.1 A viselkedés bitre azonos marad

Ugyanaz az adat, ugyanaz a sorrend, ugyanazok az állapotok (üres, betöltés, hiba). **NEM elfogadható gyengítés:** „egyszerűsítettük a hibaállapotot" — az információvesztés, nem migráció.

### 5.2 Minden állapotnak van design-rendszer-megfelelője

Üres lista → `SsEmptyState`, hiba → `SsFailureState` (§0.0.A/R5), betöltés → a design-rendszer betöltés-komponense. **NEM elfogadható gyengítés:** nyers `CircularProgressIndicator` vagy csupasz `Text('Hiba')` meghagyása.

### 5.3 A szöveg lokalizált marad

Beégetett felhasználói szöveg nem kerülhet a migrált kódba; új szöveg egyszerre `en` ÉS `hu` ARB-kulcsot kap. **NEM elfogadható gyengítés:** angol placeholder „amíg lefordítjuk".

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Mind a 5 képernyő importálja a `core/design_system`-et, és a mérés szerint migráltnak számít | a §7 mérő-parancs kimenete a §10-ben |
| A2 | Minden migrált képernyő üres/betöltés/hiba állapota design-rendszer-komponens | a batch célzott widget-tesztjei |
| A3 | A képernyők `textScaler 2.0` mellett, `en` ÉS `hu` locale-on túlcsordulás nélkül renderelnek | a batch variáns-cellái |
| A4 | A típus-pinnelő tesztek VÁLTOZATLANUL zöldek, egyetlen cellájuk sem törölt/`skip`-elt | a §7 gate + `git diff` a teszt-fájlokon |
| A5 | A `ui_inventory_test.dart` egzakt száma VÁLTOZATLAN | a §7 gate |
| A6 | Nincs beégetett felhasználói szöveg a migrált kódban | `test/l10n/hardcoded_string_guard_test.dart` |
| A7 | A `migration-status.md` a MÉRT új arányt írja (a mérés parancsával) | a dokumentum |

**Küszöb-cellahármas a szövegskálára** (a kötelező határ `2.0`, INKLUZÍV): a küszöb **alatt** (`1.5`) → nincs túlcsordulás; **pontosan rajta** (`2.0`) → nincs túlcsordulás, EZ az A3 feltétele; a küszöb **fölött** (`2.5`) → nem követelmény, és a `2.0` teljesítése nem hivatkozhat rá.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A képernyő megkapja a komponenseket, de a hibaállapot nyers `Text` marad | A2 |
| A migráció csak `en` locale-on lett kipróbálva, a hosszabb `hu` szöveg túlcsordul | A3 |
| A migráció közben egy típus-pinnelő teszt cellája `skip`-re kerül a zöldért | A4 |
| Egy szöveg beégetve kerül a kódba | A6 |
| A képernyő importálja a design-rendszert, de a stílus továbbra is `AppColors`-ból jön | A1 (a mérés a MIGRÁLT/legacy besorolást is ellenőrzi a kód alapján) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** cserélj vissza EGY migrált képernyőn egy `SsFailureState` (§0.0.A/R5)-et nyers `Text`-re, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/ui/ui_inventory_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/offline_network_guard_test.dart test/features/ai_tutor/presentation/tutor_chat_screen_test.dart test/features/ai_tutor/presentation/tutor_data_screen_test.dart test/features/ai_tutor/presentation/tutor_privacy_screen_test.dart test/features/ai_tutor/presentation/tutor_profile_screen_test.dart test/features/tutor/ai_mode_visibility_test.dart test/features/tutor/streaming_announcement_test.dart test/ui/goldens/e13_r29_screens_golden_test.dart test/l10n/arb_parity_test.dart test/l10n/hardcoded_string_guard_test.dart
```

A migrációs mérés (a kimenet a §10-be, batch-enként MIGRATED/legacy sorokkal):

```bash
for f in lib/features/ai_tutor/presentation/screens/tutor_home_screen.dart lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart lib/features/ai_tutor/presentation/screens/tutor_profile_screen.dart lib/features/ai_tutor/presentation/screens/tutor_data_screen.dart lib/features/ai_tutor/presentation/screens/tutor_privacy_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
```

Ha a batch képernyőjének VAN golden PNG-je, az újrafelvétel KIZÁRÓLAG a merge-kapu architektúráján (ADR 0426):

```bash
tools/golden-x86.sh record <a batch érintett golden-teszt fájljai>
```

## 8. Implementációs sorrend

1. A `retirement-plan.md` beolvasása → a tényleges képernyő-lista.
2. Képernyőnként: komponens-csere → állapotok (üres/betöltés/hiba) → tokenek → `*ThemeScope` eltávolítása.
3. A batch célzott widget-tesztjei (állapotok + `textScale 2.0` + `en`/`hu`).
4. A mérés futtatása, `migration-status.md` frissítése.
5. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Néma információvesztés.** A migráció közben elveszett állapot vagy mező a leggyakoribb hiba (A2).
- **Locale-vak elrendezés.** A magyar szövegek hosszabbak; az `en`-re szabott elrendezés túlcsordul (A3).
- **Scope-csúszás a viselkedés felé.** Egy „apró" providers-módosítás a kör mérhetőségét rontja (STOP-eset).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
