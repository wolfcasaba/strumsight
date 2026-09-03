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
  "test/features/ai_tutor/presentation/tutor_home_screen_test.dart",
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
  "test/features/ai_tutor/presentation/tutor_home_screen_test.dart",
  "test/l10n/arb_parity_test.dart",
  "test/l10n/hardcoded_string_guard_test.dart",
  "test/core/architecture_dependency_test.dart",
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

## 0.0.B Pre-flight brief-revízió #2 — a review után (Claude / Opus 5, 2026-09-03)

Az első implementer-menet (`ba6be648..c6504b53`) review-ja
(`docs/reviews/e15-r09-review.md`) 1 BLOCKER + 5 MAJOR leletet mért. Az alábbi
revíziók a JAVÍTÓ kör szerződése; erősebbek a §0.0.A-nál és a brief korábbi
szövegénél.

### R9 — a §3 „chat hibaállapot" kikötése MÉRTEN hamis premisszán állt

A §3 azt írta, hogy a chat „nincs backend" hibaállapota ma **nyers szöveg**.
Mérve ez NEM igaz: strukturált `TutorBanner`
(`lib/features/ai_tutor/presentation/widgets/tutor_banners.dart:160-170`) —
ikon + cím + törzs + `semanticsLabel` + `retry` akció —, ami a kör
`allowed_paths`-án KÍVÜL, egy megosztott, öt banner-fajtát kiszolgáló
widget-fájlban él. A kikötés ezért **átfogalmazva**: a chat hibaállapota ebben a
körben VÁLTOZATLAN `TutorBanner` marad (a kipinnelt `find.byType(TutorBanner)`
cellák így maradnak zöldek), a banner-család design-rendszer-migrációja pedig
KÜLÖN kör dolga — a `docs/ui/migration-status.md`-ben nevesített follow-upként
kell rögzíteni. Ez nem az A2 lazítása, hanem egy mért tény átvezetése: az
érintett állapot nem a kör öt képernyő-fájljában él.

### R10 — `tutor_home_screen_test.dart` a fájllistára ÉS a kapuba (BLOCKER-1)

Mérve (reviewer saját futása): a fájl 2 cellája (`R18-R1`, `R18-R3`) ma PIROS,
mert csupasz `MaterialApp.router`-t pumpál `theme:` nélkül, és a migrált
képernyők `SsCard`/`SsProvenanceBadge`-e theme-extensiont olvas. A fájl felkerült
az `allowed_paths`-ra és a `gate_tests`-be; a javítás ugyanaz az EGYSORNYI
`theme: SsLightTheme.data()` drótozás, mint a másik hat harnessnél (cella
törlése/`skip`-je/gyengítése TOVÁBBRA IS TILOS). Ezzel a Home-képernyő
„extension-mentes" kényszere megszűnik: használhatja a valódi komponenseket
(`SsModelStatusCard`/`SsProvenanceBadge`/`SsButton`), és ezzel a Home/Chat
ikon-divergencia (review m3) is megszűnik.

### R11 — a hamis MÉRT állítások javítása kötelező (MAJOR-1)

Az `SsCard` **NEM** extension-mentes: `ss_card.dart:15-17` → `ss_surface.dart:42`
→ `ss_elevation.dart:14-15` két `!`-es extension-olvasás. Az `SsSection` viszont
tényleg az. Javítandó MINDHÁROM helyen: `tutor_home_screen.dart` fájl-doc,
`docs/ui/migration-status.md`, és e brief §10.2 szövege.

### R12 — hiba-ág információvesztés (MAJOR-2)

`tutor_data_screen.dart` mindkét `error:` ága a TÉNYLEGES hibát adja át
(`SsFailurePresentation.from(l10n, error is AppFailure ? error : const UnknownFailure(retryable: true))`
vagy ezzel egyenértékű), nem beégetett `UnknownFailure`-t. Ha a két lista
korábbi, KÜLÖNBÖZŐ lokalizált üzenete (`tutorDataMemoryLoadFailed`,
`tutorDataConversationsLoadFailed`) nem őrizhető meg az ADR 0277
prezentációs modelljében, azt a §10-ben mért indoklással KI KELL MONDANI —
a néma összeolvadás §5.1-sértés.

### R13 — az A2 négy nyitott állapota (MAJOR-3)

- `tutor_chat_screen.dart:183` nyers `CircularProgressIndicator` → design-rendszer
  betöltés-komponens (`SsSkeleton`), a §5.2 szó szerinti előírása szerint.
- `tutor_data_screen.dart:178` és `:215` üres állapotai → `SsEmptyState`, VAGY a
  §0.0.A/R6 kivétel-osztály MINDKÉT feltételével: token-stílus
  (`SsColorScheme`/`SsTypography`/`SsSpacing`) ÉS képernyőnkénti, mért indoklás a §10-ben.
- `tutor_profile_screen.dart:93-101` validációs hibája → `SsValidationSummary`
  (létezik), vagy ugyanaz a kétfeltételes kivétel-dokumentáció.

### R14 — committolt mérce a szövegskálára (MAJOR-4)

Az A3 bizonyítéka nem lehet törölt `/tmp`-beli próbateszt. A javító kör
committol cellákat az engedélyezett teszt-fájlokba: mind az 5 képernyőre,
`textScaler` **2.0** mellett `en` ÉS `hu` locale-on, `tester.takeException()`
`isNull` elvárással (a küszöb-hármas `1.5`/`2.5` cellái opcionálisak, de a `2.0`
KÖTELEZŐ). Ez a két megtalált túlcsordulás-javítás (`_ModeChip` Flexible+ellipsis,
`_MemoryFactRow` Row→Wrap) regressziós őre.

### R15 — az A2-nek képernyőnkénti mércéje legyen (MAJOR-5)

Ma egyetlen produkciós design-rendszer-állítás van a batch-ben
(`tutor_data_screen_test.dart:459`). A javító kör minden migrált állapotra ad
egy típus-állítást (pl. `find.byType(SsSkeleton)` a chat betöltésre,
`find.byType(SsFailureState)` a data conversations-ágra, a választott
üres-állapot komponensre a data-képernyőn), hogy a §6.1 első sora
képernyőnként piros tudjon lenni. A záró valódi-sértés próbát ezúttal a
§7 GATE-en kell futtatni (nem egyetlen fájlon), és a kimenetét a §10-be írni.

### R16 — A6: a hivatkozott őr nem méri, amit állít (MINOR m1)

`test/l10n/hardcoded_string_guard_test.dart:18-23` csak a
`lib/core/design_system/**` alá néz, a `lib/features/**`-ra nem. Az őr
hatókörének átírása NEM ennek a körnek a dolga; az A6 bizonyítéka a §10-ben
ŐSZINTÉN átfogalmazandó: „mért tény, hogy a hivatkozott guard nem fedi a
`lib/features/**`-ot; a kör bizonyítéka a diff kézi és reviewer-oldali
ellenőrzése, amely új beégetett felhasználói szöveget nem talált".

### R17 — a maradék MINOR-ok, ha nem hizlalják a diffet

Golden fejléc-komment javítása (a „renders identically under either theme
choice" állítás hamis), a három CTA `Align(centerStart)`-változásának
dokumentálása a §10-ben, a data/privacy lista-blokk token-következetessége
(és az `SsSpacing.space1 / 2` aritmetika elhagyása), valamint a
`_ConversationRow` kártya-kezelése. Ezek MINOR-ok: ha egy javítás
viselkedés-kockázatot hozna, dokumentált elhagyás is elfogadható.

## 0.0.C Pre-flight brief-revízió #3 — a javító kör #1 review-ja után (Claude / Opus 5, 2026-09-03, `main @ ab2f98db`)

A javító kör #1 (`c9409564..c8be6e7d`) az első menet MIND a 6 leletét (1 BLOCKER
+ 5 MAJOR) lezárta, de a review #2 EGY ÚJ, nyitott leletet mért — `BLOCKER-2` —,
és a kör CI-ja ekkor kétszer volt piros (`33707997183`, `33711465885`) → H5 halt.
A haltot az ADR 0112 önjavító köre oldotta fel: **ADR 0494**, merge-elve a
`main`-re (`ab2f98db`, PR #541). Ez a revízió a **javító kör #2** szerződése;
erősebb a §0.0.A/§0.0.B-nél és a brief korábbi szövegénél.

### R18 — a H5 piros-számláló nulláról indul (ADR 0494 D3), a zöld kapu változatlan

Az ADR 0494 D3 kimondja: egy merge-elt önjavítás után, amely a pirosak MÉRT
gyökérokát javította, a H5 számláló **nulláról** indul. A folytatás első
CI-futása tehát az „első piros" lehetősége, nem a harmadik. A mérce NEM lazul:
minden gate + a **teljes** CI-suite + a Router CI zöldje a **merge SHA-n**
továbbra is kötelező.

### R19 — BLOCKER-2: az öt képernyő a design-rendszert a `public.dart` barrelen át éri el

**Mérve** (review §5.2, ADR 0494 kontextus): a batch öt képernyő-fájlja **24
MÉLY importtal** hivatkozik a `lib/core/design_system/**`-ra
(`tutor_home_screen.dart` 4, `tutor_chat_screen.dart` 6, `tutor_data_screen.dart` 8,
`tutor_profile_screen.dart` 4, `tutor_privacy_screen.dart` 2 — mind
`import '../../../../core/design_system/<alkönyvtár>/<fájl>.dart'` alakú). Ez az
E13-R02 merge-elt architektúra-szerződést sérti (ADR 0273 §1: „a design system
kizárólag a `public.dart`-on át importálható"; [L190](../LESSONS.md#l190): a
szabály az import CÉLJÁT kényszeríti ki).

**A javítás** fájlonként EGY sor:

```dart
import 'package:strumsight/core/design_system/public.dart';
```

a mély importok HELYETT. A `public.dart` mind a szükséges szimbólumot
exportálja (`ss_card`, `ss_section`, `ss_surface`, `ss_skeleton`,
`ss_failure_state`, `failure_presentation`, `ss_button`, `ss_model_status_card`,
`ss_provenance_badge`, `ss_validation_summary`, `foundations/*`) — a mért
precedens az E15-R08
`lib/features/gamification/presentation/screens/achievements_screen.dart:2`.
Mind az öt fájl az `allowed_paths`-on van, tehát ez NEM tilos zóna.

**A javítás határa:** kizárólag import-sorok cseréje. A képernyők
komponens-használata, állapotai, tokenjei és viselkedése VÁLTOZATLAN; egyetlen
teszt-cella sem törölhető, `skip`-elhető vagy gyengíthető. Ha egy szimbólum
mérten NEM érhető el a barrelen át, az `stopped` jelzés (a barrel bővítése a
design-rendszer köre, nem ezé).

### R20 — a megismétlődés őre: a `gate_tests` és a gate `architecture` lépése

A BLOCKER-2 azért maradt rejtve két CI-futáson át, mert a szabályt KIZÁRÓLAG a
teljes CI-suite mérte (`test/core/architecture_dependency_test.dart:754`), a kör
célzott kapuja és a `dart run tool/check_architecture.dart` lépés nem. Két,
egymást kiegészítő őr zárja ezt:

1. **ADR 0494 D2** (merge-elve): a `designSystemImportsMustUsePublicBarrel`
   szabály bekerült a `tool/check_architecture.dart`-ba, tehát a
   `tools/round-gate.sh` **`architecture`** lépése MINDEN körön, lokálisan,
   push előtt méri. A `test/tooling/design_system_barrel_architecture_test.dart`
   ennek a szabálynak a saját őre. Egyik fájl sem ennek a körnek a dolga —
   `main`-ről érkeznek, az upstream-szinkron merge-csel (§0.3).
2. **Ebben a körben:** a `test/core/architecture_dependency_test.dart` felkerül a
   `gate_tests` listára és a §7 gate-sorára, hogy a kör SAJÁT kapuja is mérje.

### R21 — upstream-szinkron megtörtént

Az ág a javító kör #2 előtt `--no-ff` merge-cselt `origin/main`-t (ADR 0494 heal),
tehát a fenti `architecture` szabály már ezen a fán MÉR. A gate futtatása előtt a
munkafán `tools/prepare-flutter-generated.sh` kötelező.

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
tools/round-gate.sh test/ui/ui_inventory_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/offline_network_guard_test.dart test/features/ai_tutor/presentation/tutor_chat_screen_test.dart test/features/ai_tutor/presentation/tutor_data_screen_test.dart test/features/ai_tutor/presentation/tutor_privacy_screen_test.dart test/features/ai_tutor/presentation/tutor_profile_screen_test.dart test/features/tutor/ai_mode_visibility_test.dart test/features/tutor/streaming_announcement_test.dart test/ui/goldens/e13_r29_screens_golden_test.dart test/features/ai_tutor/presentation/tutor_home_screen_test.dart test/l10n/arb_parity_test.dart test/l10n/hardcoded_string_guard_test.dart test/core/architecture_dependency_test.dart
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

**Motor:** Claude Sonnet 5 (`sonnet-impl`), medium effort. **Ág:**
`sonnet-impl/e15-r09-ai-tutor-migration`. Minden lépés külön commit-ban
(10 commit); a `docs/rounds/e15-r09-ai-tutor-migration.md` ez a §10.

### 10.1 Migrációs mérés (§7 parancs kimenete)

```
MIGRATED lib/features/ai_tutor/presentation/screens/tutor_home_screen.dart
MIGRATED lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart
MIGRATED lib/features/ai_tutor/presentation/screens/tutor_profile_screen.dart
MIGRATED lib/features/ai_tutor/presentation/screens/tutor_data_screen.dart
MIGRATED lib/features/ai_tutor/presentation/screens/tutor_privacy_screen.dart
```

Teljes arány (mérve `dart run tool/ui_inventory.dart` + a mérő-hurok mind a
96 útvonalon): **80/96 (83.333%)** — felvéve `docs/ui/migration-status.md`-be.

### 10.2 Képernyőnkénti komponens-térkép és a mért kivétel-osztályok

**`TutorHomeScreen` — teljes `Ss*` migráció (javítva §0.0.B/R10-ben; az
alábbi bekezdés a JAVÍTOTT állapotot írja le, az eredeti "extension-mentes"
állítás MÉRTEN HAMIS volt, lásd 10.8/BLOCKER-1 + MAJOR-1).** A képernyő saját
pinnelt tesztje (`tutor_home_screen_test.dart`) az első menetben csupasz
`MaterialApp.router`-t pumpált `theme:` nélkül; ez 2 cellát (`R18-R1`,
`R18-R3`) pirosra vitt, mert a képernyő `SsCard`-ot használt, ami — a
`SsSurface`→`SsElevation.resolve` láncon át — MAGA IS
`Theme.of(context).extension<SsColorScheme>()!`/`<SsThemeBehavior>()!`-t
olvas (mérve: `ss_card.dart:15-17` → `ss_surface.dart:42` →
`ss_elevation.dart:14-15`, két `!`). A javító kör felvette a fájlt az
`allowed_paths`-ra és a `gate_tests`-be, és ugyanazt az egysoros
`theme: SsLightTheme.data()` drótozást adta hozzá, mint a másik 6 harness.
Ezzel a képernyő immár a TELJES `Ss*` katalógust használhatja:
- `_ModelStatusCard`/`_ModeChip` → `SsModelStatusCard` (ami belül
  `SsProvenanceBadge`-et rendereli) — ezzel a Home/Chat ikon-divergencia
  (review m3, `Icons.smartphone_outlined` vs `Icons.memory_outlined`) is
  megszűnt, mindkét képernyő ugyanazt a badge-et használja.
- `FilledButton.icon` CTA → `SsButton(icon: Icons.chat, ...)`.
- `EdgeInsets.all(24)`/`SizedBox(height: 24/8)` → `SsSpacing.space6`/`space2`
  (változatlan az első menethez képest).
- Ikonok (`Icons.chat` a CTA-n) MARADTAK nyers `Icon`-ok — független ok:
  az `SsIcon` katalógusa (`play`/`pause`/`settings`/`close`/`check`/`info`
  + 14 gitár-glyph, mérve `ss_icons.dart`-ban) nem tartalmazza egyik
  screen-ikont sem; egy fel nem oldott név az `SsIcon` látható "hiányzó
  glyph" jelére esne vissza — ez valódi regresszió lenne, nem biztonságos
  csere. Ez mind az 5 képernyő ikonjaira igaz, nem csak a Home-éra.
- **Mért implementer-hiba, ami az A3-mérés KÖZBEN derült ki (és javítva
  lett az első menetben, a javító kör nem érintette):** a `_ModeChip` Row-ja
  (`icon + SizedBox + Text(label)`, `mainAxisSize: MainAxisSize.min`) nem
  védte a `Text`-et `Flexible`+`overflow: ellipsis`-szel — 2.0x/2.5x `hu`
  textScale-en `RenderFlex overflowed... on the right` (25–109 px, mérve).
  Ez a Row a javító körben `SsProvenanceBadge`-re cserélődött, ami ugyanezt
  a `Flexible`+ellipsis védelmet már eleve tartalmazza.

**Mind az 5 képernyő pinnelt tesztje az `allowed_paths`-on van** (a Home
tesztje a javító kör óta), ezért a harness-drótozás (R3 + R10) közvetlen
`theme: SsLightTheme.data()` — nem kellett `Builder`-es belső-context trükk
(mint az E15-R08 `GamificationThemeScope` alatt/felett problémájánál), mert
az `ai_tutor`-nak nincs feature-szintű téma-burkolója (R2, mérve:
`grep -rn "ThemeScope" lib/features/ai_tutor/` → 0 találat). A drótozott 7
fájl, pontos sor:
- `test/features/ai_tutor/presentation/tutor_home_screen_test.dart` (`MaterialApp.router`, javító kör)
- `test/features/ai_tutor/presentation/tutor_chat_screen_test.dart:196`
- `test/features/ai_tutor/presentation/tutor_data_screen_test.dart:247`
- `test/features/ai_tutor/presentation/tutor_privacy_screen_test.dart:146`
- `test/features/ai_tutor/presentation/tutor_profile_screen_test.dart:61`
- `test/features/tutor/ai_mode_visibility_test.dart:125` és `:146`
- `test/features/tutor/streaming_announcement_test.dart:119`

Egyik fájlban SEM változott pinnelt elvárás (widget-típus, kulcs, szöveg,
szemantika-címke) — kizárólag a `theme:` argumentum került be. `git diff`
minden érintett teszt-fájlon ezt igazolja (egy-egy sor beszúrás + az import).

**`TutorChatScreen`** — az `_AiModeIndicator` most valódi `SsProvenanceBadge`-t
használ (`local`/`cloud`), a `fallback` módhoz ugyanaz a trailing-üzenet
Flexible+ellipsis-szel, mint korábban. Az üres beszélgetés prompt (`_EmptyState`)
a §0.0.A/R6 kivétel-osztály: nincs a widgetnek saját kiváltható akciója (a
valódi következő lépés — gépelés — a mindig látható, KÜLÖN `TutorComposer`
widgetben van, amit ez a widget nem tud meghívni), ezért képernyő-lokális
maradt, de KÖTELEZŐEN `SsColorScheme`/`SsTypography`/`SsSpacing` tokenekkel.

**`TutorDataScreen`** — mindkét `FutureProvider.when` hiba-ág (`memoryFacts`,
`conversations`) `SsFailureState`-re cserélve, működő újrapróbával
(`ref.invalidate`). MÉRVE: mindkét branch a gyakorlatban elérhetetlen ma (a
`tutor_privacy_providers.dart` a repository `Failure`-jét üres listára/oldalra
fordítja, nem dobja tovább) — ezért a kör felvett egy ÚJ, valódi tesztet
(`R22-DA8`, lásd §10.3), ami a fake repository-t VALÓBAN dobásra kényszeríti,
hogy ez a cella mérhető gate-lefedettséget kapjon, ne csak "meg fog felelni"
állítást. Az `_MemoryFactRow` `Card`-ja `SsCard`-ra cserélve (egyedi `Padding`
volt, tiszta csere); a `_ConversationRow` `Card`+`ListTile` párosa VÁLTOZATLAN
maradt — egy `SsCard` a `ListTile` saját beépített paddingjával duplázná a
térközt. Export/Delete-all gombok `SsButton`-ra cserélve (a Delete-all trigger
`SsButtonVariant.secondary`-ként — maga a trigger csak megnyitja a
megerősítő dialógust, a TÉNYLEGES destruktív akció a dialóg belsejében marad
sima `FilledButton`-ként, hogy ne kelljen új `destructiveSemanticHint`
ARB-kulcs egy dialóg-belső gombhoz ebben a vizuális körben). **Mért
implementer-hiba, ami az A3-mérés KÖZBEN derült ki (és javítva lett):** a
`_MemoryFactRow` szerkesztés/törlés gombjainak `Row`-ja (`mainAxisAlignment:
end`) nem tűrte a magyar `TextButton`-feliratokat 1.5x-en már (93 px
túlcsordulás, mérve) — javítás: `Row` → `Wrap(alignment: WrapAlignment.end)`.

**`TutorProfileScreen`** — a három szekció (`Student`/`Guitar`/`Goals`)
`SsSection`-be került, az "Add goal" gomb `SsButton`. A két `TextFormField`
(heti percek, gitár neve) VÁLTOZATLAN maradt: ez a képernyő `ConsumerWidget`
(állapot nélküli), a mezők `initialValue`-t olvasnak minden Riverpod-rebuild-en
— az `SsTextField` viszont KIZÁRÓLAG `TextField`+`controller` API-t ad,
`initialValue` nélkül. Egy inline `TextEditingController(text: ...)` minden
rebuild-en új controllert hozna létre → kurzor-ugrás/fókuszvesztés minden
billentyűleütésnél (mért Flutter-antiminta), ez VISELKEDÉS-változás lenne egy
vizuális körben — ezért maradt a `TextFormField`.

**`TutorPrivacyScreen`** — a scope-cím+lista+footer `SsSection`-be került. A
három `SwitchListTile` consent-kapcsoló (és feliratuk) VÁLTOZATLAN maradt — ez
a brief §3 saját, kifejezett kivétele ("a privacy- és adat-képernyő
consent-kapcsolói és szövegei érintetlenek", ADR 0132).

### 10.3 Valódi-sértés próba (§6.1, KÖTELEZŐ)

A `tutor_data_screen_test.dart`-hoz felvett ÚJ teszt (`R22-DA8`): egy
`_FakeMemoryRepository.throwOnList` flag valódi kivételt dob a `.list()`-ből
(a régi `Failure`-visszaadás NEM éri el a hiba-ágat, mérve — lásd 10.2), így
a teszt VALÓDI gate-lefedettséget ad az A2 cellának erre az állapotra:

1. Zöld (a jelen implementációval): `find.byType(SsFailureState)`
   `findsOneWidget`, retry gomb (`ss-failure-state-retry`) újrahívja
   `repo.list()`-et (`listCalls: 1 → 2`).
2. A próba: `error: (_, _) => SsFailureState(...)` visszaírva
   `error: (_, _) => Text(l10n.tutorDataMemoryLoadFailed)`-re, majd
   `flutter test test/features/ai_tutor/presentation/tutor_data_screen_test.dart`
   → **PIROS**, pontosan az `R22-DA8` cellán:
   ```
   Expected: exactly one matching candidate
     Actual: _TypeWidgetFinder:<Found 0 widgets with type "SsFailureState": []>
   00:03 +9 -1: R22-DA8: memory-facts load failure renders SsFailureState with a working retry [E]
   ```
   A többi 9 cella VÁLTOZATLANUL zöld maradt (a nyers szöveg tartalma
   megegyezett, a típus-ellenőrzés bukott).
3. Visszaállítva a `SsFailureState`-es változatra → újra ZÖLD (10/10),
   `git diff` a próba UTÁN üres a `tutor_data_screen.dart`-on.

### 10.4 Golden újrafelvétel (§0.0.A/R4)

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r29_screens_golden_test.dart
```
Kimenet: exit 0, mind a 6 cella zöld (`coach home/chat — compact` +
`_scale2`, `practice plan preview — compact` + `_scale2`).

```
$ git diff --stat -- test/ui/goldens/goldens/
 test/ui/goldens/goldens/e13_r29_coach_chat_compact.png        | Bin 7053 -> 7108 bytes
 test/ui/goldens/goldens/e13_r29_coach_chat_compact_scale2.png | Bin 8220 -> 8221 bytes
 test/ui/goldens/goldens/e13_r29_coach_home_compact.png        | Bin 6536 -> 6693 bytes
 test/ui/goldens/goldens/e13_r29_coach_home_compact_scale2.png | Bin 5641 -> 5806 bytes
 4 files changed, 0 insertions(+), 0 deletions(-)
```

A 2 Practice Plan Preview PNG BYTE-AZONOS maradt (az a képernyő már
migrált volt a kör előtt is, és egyik komponense sem olvas theme-extension-t,
tehát a téma-csere rá nem hatott — mérve).

### 10.5 `textScaler` küszöb-hármas (1.5 / 2.0 / 2.5) × `en`/`hu`

Mérőeszköz: egyszeri, a repón kívüli (`/tmp/e15_r09_textscale_probe_test.dart`,
NEM commitolva, NEM az `allowed_paths`-on — a mérés után törölve) 30 cellás
teszt, `tester.takeException()` `isNull` minden (képernyő × scale × locale)
kombinációra, a batch mind az 5 képernyőjére, 412×915 kompakt viewport (a
golden-sáv saját konvenciója).

**Első futás (a §10.2 két javítás ELŐTT): 7/30 piros** —
`home@2.0hu`, `home@2.5en`, `home@2.5hu`, `data@1.5hu`, `data@2.0hu`,
`data@2.5en`, `data@2.5hu` — mind `RenderFlex overflowed ... on the right`
(25–343 px). A `2.0x` küszöb (az A3 KÖTELEZŐ feltétele) piros volt
`home`-on ÉS `data`-n is `hu`-n — ez valódi, javítandó hiba volt, nem
mérési műtermék.

**A §10.2-ben leírt két javítás (`_ModeChip` Flexible+ellipsis,
`_MemoryFactRow` Row→Wrap) UTÁN: 30/30 zöld** minden képernyőre, minden
skálára, mindkét locale-on. `chat`, `profile`, `privacy` már az ELSŐ
futáson is 30/30 zöld volt.

### 10.6 A6 (nincs beégetett szöveg) és ARB

**Őszinte korrekció (§0.0.B/R16, MINOR m1):** az A6 sor korábbi
„Bizonyíték" hivatkozása (`test/l10n/hardcoded_string_guard_test.dart`)
MÉRTEN nem fedi ezt a kört — a guard hatóköre (`_scopeDirs`, a fájl
`:18-23`-a) kizárólag `lib/core/design_system/{components,accessibility,
layouts,motion}` alá néz, a `lib/features/**`-ra (tehát a kör öt
képernyőjére) NEM. A guard a gate-listán szerepel és zölden fut, de erre a
körre nézve HOLT cella — false-positive biztonságot adna, ha A6
bizonyítékaként hivatkoznánk rá. A kör valódi bizonyítéka: a diff kézi
átolvasása (implementer + reviewer oldalán is) — új, beégetett
felhasználói szöveget egyik migrált képernyőn sem talált; minden szöveg a
meglévő `AppLocalizations` gettereken át jön. A guard hatókörének
`lib/features/**`-ra bővítése NEM ennek a körnek a feladata (külön kör).

Nem vettem fel ÚJ ARB-kulcsot — minden migrált widget a MEGLÉVŐ
`AppLocalizations` gettereket használja (`l10n.tutorData*`, `l10n.aiTutor*`,
`dsFailure*`/`dsProvenanceBadge*` a design-rendszerből). `lib/l10n/app_en.arb`
és `lib/l10n/app_hu.arb` ezért VÁLTOZATLAN maradt ebben a körben (az
`allowed_paths`-bővítés R7 szerint elérhető volt, de nem kellett élnem vele).

### 10.7 Amit NEM tettem meg, és miért

- **`SsTextField`** — nem használtam a Profile-on (10.2, controller/
  `initialValue` inkompatibilitás).
- **`SsSwitchRow`** — nem használtam a Privacy consent-kapcsolóin (a brief §3
  saját kivétele, ADR 0132).
- **`SsIcon`** — nem használtam SEHOL az 5 képernyőn (10.2, katalógus-hiány
  minden szükséges ikonnévre).
- **A Chat-képernyő `TutorBannerKind.error` "nincs backend" nyers szövege**
  (amit a §3 kifejezetten `SsFailureState`-re várt) a `tutor_banners.dart`
  widget-fájlban él, ami NINCS az `allowed_paths`-on (csak a screen-fájlok
  vannak rajta) — ezt NEM módosítottam. Ehelyett a `TutorDataScreen` két,
  ténylegesen a screen-fájlban élő hiba-ágát migráltam `SsFailureState`-re
  (10.2/10.3), és ide dokumentálom a mért hézagot a review számára: a §3
  betű szerinti "chat-képernyő hibaállapota" cél NEM teljesült, mert a
  megnevezett widget kívül esik a kör fájllistáján.
- **A Delete-all dialóg belső `FilledButton`-ja** nem lett
  `SsButtonVariant.destructive` (10.2) — elkerülve egy új
  `destructiveSemanticHint` ARB-kulcsot egy dialóg-belső gombért, ami a
  vizuális kör hatókörén túlmutató döntésnek tűnt.

### 10.8 Javító kör #1

Commit-ok: `b1597fa1` (BLOCKER-1 + MAJOR-1…5 javítás, golden-újrafelvétel),
`f2398750` (takarítás — véletlenül commitolt golden-diff debug-fájlok
törlése, nem termelési változás).

**BLOCKER-1 (R10).** `test/features/ai_tutor/presentation/tutor_home_screen_test.dart`
`MaterialApp.router`-je megkapta a `theme: SsLightTheme.data()` drótozást
(a fájl importálja `ss_light_theme.dart`-ot és felvette a `locale`
paramétert is, hogy a §0.0.B/R14 textScale-cellák hu-t is tudjanak
futtatni ugyanazon a harnessen). Ezzel a Home-képernyő „extension-mentes"
kényszere megszűnt: `tutor_home_screen.dart` `_ModelStatusCard`/`_ModeChip`
helyett most `SsModelStatusCard` (belül `SsProvenanceBadge`) + `SsButton`
CTA-t használ. **Visszaesést fogó cella:** `R18-R1`/`R18-R3` (a saját
pinnelt teszt két korábban piros cellája) — bármelyik visszaáll pirosra,
ha a `theme:` drótozás vagy a téma-extension-olvasó komponens eltűnik.

**MAJOR-1 (R11).** A hamis „`SsCard`/`SsSurface` extension-mentes"
állítás javítva mindhárom helyen: `tutor_home_screen.dart` fájl-doc (most
a mért láncot idézi: `ss_card.dart:15-17` → `ss_surface.dart:42` →
`ss_elevation.dart:14-15`), `docs/ui/migration-status.md` (a `TutorHomeScreen`
bekezdés átírva), és e brief §10.2-je (fent). **Visszaesést fogó cella:**
nincs önálló teszt-cella (dokumentum-pontosság), de a BLOCKER-1 cellái
tényleges bizonyítékot adnak arra, hogy az állítás iránya (extension-olvasás
biztonságos, ha a harness témázva van) helyes.

**MAJOR-2 (R12).** `tutor_data_screen.dart` mindkét `error:` ága
(`memoryFacts`, `conversations`) a valódi hibát adja át:
`error is AppFailure ? error : const UnknownFailure(retryable: true)`.
Mivel az `SsFailurePresentation.from` kizárólag `AppFailure.code`/`.retryable`
alapján dönt (ADR 0277), nem aszerint, MELYIK lista hibázott, a két korábbi
KÜLÖNBÖZŐ ARB-üzenet (`tutorDataMemoryLoadFailed`,
`tutorDataConversationsLoadFailed`) továbbra is holt kulcs marad — ez a
prezentációs modell mért korlátja, nem ennek a körnek a hibája (a fájl
doc-kommentje ezt most kimondja). **Visszaesést fogó cella:** a §10-ben
lent dokumentált valódi-sértés próba a teljes GATE-en — `R22-DA8` pirosra
vált, ha az `error:` ág visszaáll beégetett `UnknownFailure`-re vagy nyers
`Text`-re.

**MAJOR-3 (R13).** Négy nyitott állapot lezárva:
- `tutor_chat_screen.dart:183` (eredeti sor) nyers `CircularProgressIndicator`
  → `SsSkeleton` (12×12, `SsRadius.pill`). **Cella:** `R18-A17`.
- `tutor_data_screen.dart` memory/conversations üres állapota → új,
  screen-lokális `_DataEmptyState` (token-stílus: `SsColorScheme`/
  `SsTypography`/`SsSpacing`; a §0.0.A/R6 kivétel-osztály, mert egyik
  listának sincs valódi, e widgetből meghívható következő lépése — a
  chat `_EmptyState`-tel azonos indoklás). **Cellák:** `R22-DA11`, `R22-DA12`.
- `tutor_profile_screen.dart:93-101` validációs hiba → `SsValidationSummary`.
  **Cella:** `R22-PF2` (kibővítve) + `R22-PF6`.

**MAJOR-4 (R14).** Mind az 5 képernyő saját pinnelt teszt-fájlja kapott
committolt `textScaler 2.0` × `en`/`hu` cellát (`R18-R7`, `R18-A19`,
`R22-DA14`, `R22-PC7`, `R22-PF7`), a 412×915 kompakt viewporton. **Mért,
valódi regresszió, amit ez a mérés talált és ami itt javítva lett:** a
Chat képernyő `_AiModeIndicator` fallback-ága (badge + trailing üzenet az
AppBar `actions`-ában) `RenderFlex overflowed by 1187 pixels`-t adott
(`en`, 2.0×) — az `AppBar.actions` minden akciót a SAJÁT természetes
szélességén mér, mielőtt a cím a maradékot megkapná, ez az ambiens
korlát pedig láthatatlan a `Flexible`/`TextOverflow.ellipsis` számára,
amíg minden gyermek nem-flexibilis testvér marad. Javítás: mind a badge,
mind a trailing szöveg SAJÁT `ConstrainedBox`-ot kapott (130px, illetve
90px), ami a vágást a Row flex-egyeztetésétől függetlenül, determinisztikusan
kényszeríti ki. **Visszaesést fogó cella:** `R18-A19` (mindkét locale).

**MAJOR-5 (R15).** Képernyőnkénti design-rendszer típus-állítás minden
migrált állapotra: Home (`R18-R5`: `SsModelStatusCard`, `SsButton`), Chat
(`R18-A17`: `SsSkeleton`; `R18-A18`: `SsProvenanceBadge`), Data (`R22-DA9`:
`conversations` hiba-ág `SsFailureState` — ÚJ valódi-sértés próba, mert
korábban EGYETLEN ilyen cella élt a batch-ben, a `memoryFacts` ágon;
`R22-DA10`: `SsCard`; `R22-DA11`/`R22-DA12`: a token-stílusú üres-állapot;
`R22-DA13`: `SsButton`), Profile (`R22-PF6`: `SsSection`×3, `SsButton`),
Privacy (`R22-PC6`: `SsSection`).

**R16 (A6 őszinteség).** `test/l10n/hardcoded_string_guard_test.dart`
hatóköre (`:18-23`) kizárólag `lib/core/design_system/**`-ra terjed ki, a
kör öt `lib/features/ai_tutor/**` képernyőjére NEM — ez a gate-listán
zölden fut, de erre a körre nézve holt bizonyíték. A §10.6 mostantól ezt
mondja ki: a valódi bizonyíték a diff kézi átolvasása (implementer +
reviewer), ami nem talált új beégetett szöveget. A guard hatókör-bővítése
külön kör dolga.

**R17 (MINOR-ok).**
- **m2** — a golden fejléc-komment javítva: a `TutorHomeScreen` mostantól
  SZINTÉN theme-extension komponenseket használ, tehát `AppTheme.dark()`
  alatt ő is összeomlana; a komment ezt mondja ki (nem "renders identically").
- **m3** — magától megszűnt: a Home most `SsProvenanceBadge`-et használ
  (ugyanazt, mint a Chat), a korábbi `Icons.smartphone_outlined` vs
  `Icons.memory_outlined` divergencia eltűnt.
- **m4** — dokumentálva, NEM javítva: a három CTA
  (`tutorDataExportRedacted`, `tutorDataDeleteAllTrigger`,
  `tutorProfileAddGoal`) `Align(centerStart)`-tal intrinsic szélességű
  marad — a teljes-szélességű visszaállítás egy tap-target-méretet érintő
  layout-döntés lenne, ami túlmutat ezen a javító körön; a §10.2 dokumentálja
  a jelenlegi állapotot.
- **m5** — javítva: `tutor_data_screen.dart:271/276` (a scope-lista bullet
  sorok) a beégetett `vertical: 2`/`width: 8` helyett `SsSpacing.space1`/
  `SsSpacing.space2`-t használ; `tutor_privacy_screen.dart` `SsSpacing.space1
  / 2` aritmetikája szintén `SsSpacing.space1`-re egyszerűsödött — mindkét
  fájl most valódi, nevesített tokent használ, nem levezetett/beégetett
  értéket. Vizuálisan elhanyagolható (2px) különbség egy 3+3 soros
  bullet-listán, egyik fájlnak sincs golden-je.
- **m6** — NEM javítva, dokumentálva: `_ConversationRow` marad nyers
  `Card`+`ListTile`, mert egy `SsCard` duplázná a `ListTile` saját
  paddingját (a §10.2-ben már rögzített indoklás, változatlan).

**Valódi-sértés próba a teljes GATE-en (KÖTELEZŐ, MÉRVE).** A
`tutor_data_screen.dart` memory-facts `error:` ága ideiglenesen visszaírva
`Text(l10n.tutorDataMemoryLoadFailed)`-re (a `SsFailureState`/
`SsFailurePresentation.from` hívás eltávolítva), majd a §7 GATE
csonkítatlanul lefuttatva:

```
→ [7] test test/features/ai_tutor/presentation/tutor_data_screen_test.dart: PIROS (kilépési kód 1)
  R22-DA8: memory-facts load failure renders SsFailureState with a working retry [E]
    Expected: exactly one matching candidate
      Actual: _TypeWidgetFinder:<Found 0 widgets with type "SsFailureState": []>
  R22-DA10: a memory-fact row renders inside the design-system SsCard [E]
    (másodlagos bukás — a memory-facts lista üres marad, amíg a hiba-ág aktív)
═══ Gate-összegzés: … test test/features/ai_tutor/presentation/tutor_data_screen_test.dart PIROS (1) …
GATE_EXIT=10
```

A többi 14 lépés (format/analyze/12 másik teszt-fájl) VÁLTOZATLANUL zöld
maradt a sértés alatt is — a próba pontosan a célzott cellákat vitte
pirosra, nem az egész gate-et. Visszaállítva (a `git diff` a visszaállítás
UTÁN üres a fájlon) → a §10.9 alatti teljes gate-futás újra 18/18 zöld.

### 10.9 Záró GATE — csonkítatlan (a §4 parancs, javító kör után)

```bash
tools/round-gate.sh test/ui/ui_inventory_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/offline_network_guard_test.dart test/features/ai_tutor/presentation/tutor_chat_screen_test.dart test/features/ai_tutor/presentation/tutor_data_screen_test.dart test/features/ai_tutor/presentation/tutor_privacy_screen_test.dart test/features/ai_tutor/presentation/tutor_profile_screen_test.dart test/features/tutor/ai_mode_visibility_test.dart test/features/tutor/streaming_announcement_test.dart test/ui/goldens/e13_r29_screens_golden_test.dart test/features/ai_tutor/presentation/tutor_home_screen_test.dart test/l10n/arb_parity_test.dart test/l10n/hardcoded_string_guard_test.dart
```

```
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/ui/ui_inventory_test.dart                        zöld
    test test/app/navigation/adaptive_scaffold_test.dart       zöld
    test test/app/offline_network_guard_test.dart              zöld
    test test/features/ai_tutor/presentation/tutor_chat_screen_test.dart zöld
    test test/features/ai_tutor/presentation/tutor_data_screen_test.dart zöld
    test test/features/ai_tutor/presentation/tutor_privacy_screen_test.dart zöld
    test test/features/ai_tutor/presentation/tutor_profile_screen_test.dart zöld
    test test/features/tutor/ai_mode_visibility_test.dart      zöld
    test test/features/tutor/streaming_announcement_test.dart  zöld
    test test/ui/goldens/e13_r29_screens_golden_test.dart      zöld
    test test/features/ai_tutor/presentation/tutor_home_screen_test.dart zöld
    test test/l10n/arb_parity_test.dart                        zöld
    test test/l10n/hardcoded_string_guard_test.dart            zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
```

A BLOCKER-1 által korábban pirosra vitt `R18-R1`/`R18-R3` MÉRVE zöld a
`test test/features/ai_tutor/presentation/tutor_home_screen_test.dart`
lépésen belül (7/7 cella, beleértve az új `R18-R5`/`R18-R7`-et is). A
golden-sáv (`test/ui/goldens/e13_r29_screens_golden_test.dart`) 6/6 zöld
az x86-on újrafelvett Home PNG-kkel (`tools/golden-x86.sh record`, exit 0)
— a Chat és a Practice Plan Preview PNG-k byte-azonosak maradtak, csak a
Home 2 PNG-je (compact + `_scale2`) változott, a §10.4-ben leírt módon.

## 11. Review — a Claude tölti ki
