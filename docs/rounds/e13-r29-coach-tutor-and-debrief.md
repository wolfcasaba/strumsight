# E13-R29 — Coach Home, Tutor és Debrief UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ c732ec75`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 29
- **Kör-azonosító:** `E13-R29`
- **Branch:** `<motor>/e13-r29-coach-tutor-and-debrief`
- **Előfeltétel:** `E13-R28` merge-elve (egységes könyvtár)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0287`](../adr/0287-no-automatic-tool-execution-in-the-tutor.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES tanár-réteg
> tool-interfészét és a streaming API-t — a §5.1 kimondja, hogy egyetlen
> tool-akció sem futhat megerősítés nélkül, és ezt a mért interfészen kell
> kikényszeríteni. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  # §0.0/B1 — az eredeti `lib/features/coach/` és `lib/features/tutor/`
  # KÖNYVTÁR-előtag a verziókövetett fán NEM létezik (S13 lint, L497
  # hibaosztály), ÉS a brief §0.0/R1 feltevése („a képernyőket EZ a kör hozza
  # létre") MÉRHETŐEN hamis: a coach/tutor/debrief felület ma a
  # `lib/features/ai_tutor/presentation/` fában él. A csere szigorúan
  # KEVESEBB, mint a szomszéd, user-jóváhagyott E13-R22 lista (ott a TELJES
  # `presentation/widgets/` ÉS `presentation/providers/` ÉS a feature
  # `public.dart`-ja szerepelt): itt HÁROM nevesített képernyő, a widgets-fa,
  # és a providers-rétegből EGYETLEN nevesített fájl — se `public.dart`, se
  # `application/`, se `domain/`.
  "lib/features/ai_tutor/presentation/screens/tutor_home_screen.dart",
  "lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart",
  "lib/features/ai_tutor/presentation/screens/practice_plan_preview_screen.dart",
  "lib/features/ai_tutor/presentation/widgets/",
  # §0.0/B6 — az A1 (AI-mód MINDIG látható) ma NEM állítható elő a felületről:
  # a `TutorChatState` (`tutor_providers.dart:71-86`) `status`/`responseText`/
  # `banners`/`isOnline`/`draft`/`messages` mezőt hordoz, AI-módot nem, és a
  # `TutorBannerKind` (uo. 52-67) `offline|consent|rateLimit|error|cancelled`
  # értékei közt sincs helyi/tartalék fok. A jogosultság PONTOSAN a
  # presentation-szintű mód-kitétel; a `application/`/`domain/` viselkedése
  # NEM módosulhat (§3 tilalma), és a `tutor_production_wiring_test.dart` a
  # gate_tests szerkeszthetetlen pinje marad.
  "lib/features/ai_tutor/presentation/providers/tutor_providers.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/tutor/ai_mode_visibility_test.dart",
  "test/features/tutor/streaming_announcement_test.dart",
  "test/features/tutor/tool_confirmation_test.dart",
  "test/features/tutor/prompt_injection_ui_test.dart",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r29-coach-tutor-and-debrief.md",
]
gate_tests = [
  "test/features/tutor/ai_mode_visibility_test.dart",
  "test/features/tutor/streaming_announcement_test.dart",
  "test/features/tutor/tool_confirmation_test.dart",
  "test/features/tutor/prompt_injection_ui_test.dart",
  # §0.0/B2 — a kör SAJÁT fáján MA is zölden mérő, listán KÍVÜLI pinek:
  # futtatni KELL, szerkeszteni TILOS. Mind a tizenegy teszt közvetlenül a
  # migrálandó képernyőkre és widgetekre állít, tehát a migráció ADDITÍV: a
  # mai szerződéseket nem írja át. (A brief eredeti §0.0/R2-je „nincs ilyen"-t
  # állított — az a nem létező `lib/features/tutor/` fára volt igaz.)
  "test/features/ai_tutor/presentation/",
  # §0.0/B9 — a `TutorHomeScreen` típusát a kör fáján KÍVÜL élő két teszt
  # pinneli. Nem kerülnek az `allowed_paths`-ra (az tágítás lenne, L478): a kör
  # futtatja őket, de nem szerkesztheti — így a §0.0/B9 típus-tilalma GÉPILEG,
  # a LOKÁLIS kapun bukik, nem CI-only leletként (E13-R17/H3).
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/offline_network_guard_test.dart",
  # §0.0/B7 (ADR 0426 §3) — a golden-útvonal NEM kerül a lokális ARM-gate-re;
  # a lokális mérés egyetlen érvényes alakja:
  # `tools/golden-x86.sh check test/ui/goldens/e13_r29_screens_golden_test.dart`
  "test/ui/ui_inventory_test.dart",
  "test/core/architecture_dependency_test.dart",
  "test/tooling/dio_factory_guard_test.dart",
  "test/tooling/preferences_plugin_import_guard_test.dart",
  "test/tooling/route_literal_guard_test.dart",
]
native_gate = false
```

## 0.0 BRIEF-REVÍZIÓ — 2026-08-25, batch pre-flight (E13-R17…R35)

A brief 2026-08-15-én készült; ez a pre-flight `main @ 41fbd40` ellen mért.
**Visszakeresett előzmény:** [L478](../LESSONS.md) (a pre-flight csak szűkíthet;
a tágítás H3), [ADR 0307 §4](../adr/0307-parallel-round-execution.md) (a
`lib/l10n/app_*.arb` GENERÁLT aggregátum, a forrás a `base/` és a
`features/` szegmens), [L481](../LESSONS.md) (a lánc remote konténerből nem
indítható). A hibaosztályt a **teljes Ch13 sávon** mérte ki egy batch-vizsgálat:
az R17–R35 MIND a generált aggregátumot sorolta fel forrásként (`agg=2, frag=0`).

**Kockázat = high, indoklás:** a coach/tutor AI-provider hívást közvetít: a prompt-határ és a megjelenített válasz prompt-injection felület.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/coach/`, `lib/features/tutor/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `coach` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek
- `tutor` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - nincs ilyen.

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — nincs ilyen. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/coach/`, `lib/features/tutor/` könyvtár-előtag
alá képernyőt hoz vagy hozhat, tehát a szám **elmozdul**, és az exact-SHA Full
Gate pirosra vált.

A `test/ui/goldens/` előtag ezt **nem** fedi (az a `test/ui/` fának csak az egyik
ága), a leltárteszt utólagos felvétele pedig tágítás, azaz **H3** — az
orchestrátor a pre-flightban nem oldhatja fel ([L478](../LESSONS.md)). Ezért
kerül a listára MOST, az önjavító körben.

**MÉRVE (E13-R16, 2026-08-25):** pontosan ez a hiány állította meg a sáv első
migrációs körét — [full-gate 32867296946](https://github.com/wolfcasaba/strumsight/actions/runs/32867296946)
6366 passed / 2 failed, `hasLength(79)` a tényleges 81 ellen. A `9acd14e5`
sáv-szintű batch pre-flight azért nem találta meg, mert a `tools/brief-lint.py`
`S9` szabálya csak LITERÁLIS `*_screen.dart` útvonalat nézett, KÖNYVTÁR-előtagot
nem — a predikátumot ugyanez az önjavító kör javította, regressziós teszttel
([L483](../LESSONS.md)).

**A jogosultság PONTOSAN a szám emelése** a kör tényleges képernyőszámára; a
leltárteszt minden más állítása érintetlen marad. Kerülőút (képernyő-átnevezés
vagy a `tool/ui_inventory.dart` szabályának lazítása) **TILOS** — az a mérce
meghamisítása.

### S12 — a fa-szintű őrök a kör LOKÁLIS kapujába (2026-08-25)

A kör lokális kapuja eddig KIZÁRÓLAG a saját céltesztjeit futtatta, ezért a
teljes `lib/` fát pásztázó őrök leletei szerkezetileg csak a ~17 perces
exact-SHA Full Gate-en jelentek meg — javító kör árán. MÉRT eset: **E13-R16/F8**
(`docs/reviews/e13-r16-review.md`), ahol mind a három új képernyő közvetlenül
importálta a `design_system/foundations/**`-ot a `public.dart` helyett — **11
sértés** —, és a review szó szerint rögzíti, miért nem fogta a célzott gate:
a `tools/round-gate.sh` `architecture` lépése a `tool/check_architecture.dart`-ot
futtatja, ami egy MÁSIK, tágabb szabálykészlet; a design-system-határ mércéje
egy külön `test/core/` teszt, amit csak a teljes suite futtat.

Ezért ez a kör mostantól a `gate_tests`-ben futtatja ezeket az őröket:

- `test/core/architecture_dependency_test.dart`
- `test/tooling/dio_factory_guard_test.dart`
- `test/tooling/preferences_plugin_import_guard_test.dart`
- `test/tooling/route_literal_guard_test.dart`

A kiválasztás MÉRT, nem vaktában: a globális őrök a `Directory('lib')` teljes
fát pásztázzák (bármelyik kör diffje elmozdíthatja őket), a szűkített őrök pedig
csak akkor kerülnek fel, ha a kör `allowed_paths`-a metszi a pásztázott
gyökeret.

**Ezek az őrök NEM kerülnek az `allowed_paths`-ra** — és ez szándékos: a kör
futtatja, de NEM szerkesztheti őket, tehát a lelet javítása kizárólag a kör
SAJÁT kódjában történhet. Cella törlése, `skip`-je vagy küszöb-lazítása így
gépileg kizárt, a mérce pedig tiszta erősítést kap.

## 0.0/B BRIEF-REVÍZIÓ — 2026-08-27, a kör SAJÁT pre-flightja (`main @ 388cdc2f`)

**Visszakeresett előzmény** (ADR 0312, `tools/knowledge-rag.mjs`, szűkített
korpusz először): [ADR 0133 §2](../adr/0133-ai-tutor-tool-confirmation.md)
(kétlépcsős write/launch confirm; a tisztán olvasó válasz nem action),
[ADR 0137 §1–2](../adr/0137-ai-tutor-readonly-tool-contract.md) (read-only
tool-contract, fail-closed allowlist), [ADR 0139](../adr/0139-ai-tutor-action-proposal-confirmation.md)
(proposal/confirmation mechanika), [ADR 0426 §3](../adr/0426-golden-rasterization-on-the-gate-architecture.md)
(a golden a kapu architektúráján mérendő), [L397](../LESSONS.md#l397) (a
képernyő-leltár CI-only lelete), [L403](../LESSONS.md#l403) (a valódi-sértés
próba widget-TÍPUS szinten átengedhet tartalmi sértést),
[L478](../LESSONS.md#l478) (a pre-flight csak szűkíthet), [L497](../LESSONS.md#l497)
(nem létező könyvtár-előtag az `allowed_paths`-on).

### B1 — a két KÖNYVTÁR-előtag nem létezik, és a §0.0/R1 feltevése hamis

A `tools/brief-lint.py` S13 lelete szerint `lib/features/coach/` és
`lib/features/tutor/` NULLA fájlt fed. A §0.0/R1 ezt azzal oldotta fel, hogy
„a képernyőket ez a kör hozza létre" — **mérve hamis**:

| §3 szerinti felület | MÉRT hely a fán |
|---|---|
| Coach kezdőképernyő | `lib/features/ai_tutor/presentation/screens/tutor_home_screen.dart` (49 sor) |
| beszélgetés-felület | `…/screens/tutor_chat_screen.dart` (261 sor) |
| debrief / terv-előnézet | `…/screens/practice_plan_preview_screen.dart` (311 sor) |
| tool-akció kártya | `…/widgets/tutor_action_card.dart` (287 sor) |
| bizonyíték-panel, forrás-lap | `…/widgets/tutor_evidence_chip.dart`, `…/widgets/tutor_source_sheet.dart` |
| szerkesztő, üzenetbuborék, bannerek | `…/widgets/tutor_composer.dart`, `…/widgets/tutor_message_bubble.dart`, `…/widgets/tutor_banners.dart` |
| debrief-tartalom forrása | `lib/features/ai_tutor/application/debrief/` — **TILOS zóna** (§3) |

Ez tehát **migrációs**, nem zöldmezős kör: a mai fa `lib/features/ai_tutor/`.
A csere a fenti MÉRT rétegre megy, és szigorúan kevesebb, mint a szomszéd,
user-jóváhagyott E13-R22 alak (§0.0/B1 megjegyzés az `ai-router` blokkban).

A §0.0/R1 l10n-következtetése **változatlanul áll**: az `aiTutorHomeTitle` és
társai mérve a `lib/l10n/base/app_{en,hu}.arb` szegmensben élnek (a
`lib/l10n/features/` alatt NINCS `ai_tutor_*.arb`), tehát a FORRÁS a `base/`,
az `app_{en,hu}.arb` pedig kizárólag generált kimenet.

### B2 — a kör saját fáján TIZENEGY zöld pin él (a §0.0/R2 „nincs ilyen" hamis)

`test/features/ai_tutor/presentation/` — `practice_plan_preview_screen_test`,
`session_tutor_entry_card_test`, `song_tutor_entry_card_test`,
`tutor_action_card_test`, `tutor_chat_screen_test`, `tutor_data_screen_test`,
`tutor_evidence_source_test`, `tutor_home_screen_test`,
`tutor_privacy_screen_test`, `tutor_production_wiring_test`,
`tutor_profile_screen_test`. **Nem** kerülnek az `allowed_paths`-ra: a kör
futtatja őket (`gate_tests`), de nem szerkesztheti — a migráció ADDITÍV. Ha
egy elbukik, az `blocked` jelzés és célzott brief-revízió, nem csendes
átírás (§0.0/R3). Ez a mérce ERŐSÍTÉSE: az E13-R05/H3 ([L393](../LESSONS.md#l393))
és az E13-R04/H3 ([L387](../LESSONS.md#l387)) hibaosztálya pontosan az volt,
hogy a legacy finder-contract CI-only leletként jött elő.

### B3 — mi számít „tool-akciónak" az A2/A4-ben (merge-elt ADR-határ, H2-védelem)

Az ADR 0287 §2 „explicit, zárt, tervben rögzített listát" enged mentesítésként.
A fán ez a lista MÁR LÉTEZIK és merge-elt:

- **`TutorAction`** (write/launch) — az `ActionConfirmationService`
  propose → confirm útján fut; ez az, amit az A2/A3/A4/A6 mér.
- **read-only tool** — `ReadOnlyTutorTools.safeToolNames`
  (`{getContextField, summarizeContext}`, verzió `ai_tutor.read_only_tools.v1`,
  `application/tools/read_only_tutor_tools.dart:12-17`): zárt halmaz,
  fail-closed registry-allowlist mögött (ADR 0137 §1–2), és az
  [ADR 0133 §2](../adr/0133-ai-tutor-tool-confirmation.md) kimondja, hogy a
  tisztán olvasó/magyarázó válasz nem igényel action-megerősítést.

**Kötelező olvasat:** az A2/A4 cellái **`TutorAction`-re** mérnek. Olyan cellát
írni, amely a fenti zárt read-only halmazra is megerősítést követel, **egy
lezárt kör viselkedésének megváltoztatása lenne (H2)** — tilos. A §6.1
valódi-sértés próbája ezért így értendő: *engedd, hogy egy `TutorAction`
megerősítés NÉLKÜL végrehajtódjon* → az A2 cellának pirosnak kell lennie →
állítsd vissza.

### B4 — a megerősítési állapotgép MÉRT bemenet→állapot leképezése (§1/1. szabály)

`application/orchestration/action_confirmation_service.dart` (mérve, nem az
átmenettáblából):

| Cél-állapot | Az EGYETLEN input, ami előállítja |
|---|---|
| `pendingConfirmation` | `propose(p)` érvényes validációval ÉS `p is TutorAction` (`:86`) |
| `blocked` | `propose()` érvénytelen validációval (`:78`) VAGY `p is! TutorAction` (`:80-84`) VAGY `_confirmOnce` újravalidálása bukik (`:128`) |
| `rejected` | `reject(c)` **kizárólag** `pendingConfirmation` állapotú, nem-null action-ös bemeneten (`:88-95`) |
| `confirmed` | `confirm(c)` pending bemeneten → `_confirmOnce` → `executor.execute` (`:131`) |

**Csapda az A3-hoz (a „pontosan egyszer" cella):** a szolgáltatás
`_confirmedClientActionIds` + `_inFlightConfirmations` párral,
`action.metadata.clientActionId` kulcson dedupál (`:106-119`) — egy MÁSODIK
`confirm()` UGYANAZZAL a `clientActionId`-val végrehajtás NÉLKÜL ad
`confirmed`-et. Egy olyan A3-cella tehát, amely ugyanazt a proposalt küldi be
kétszer, akkor is zöld, ha a FELÜLET hibás. Az A3-at a **felületi úton** kell
mérni (a lap megerősítés-visszahívása), a §6.1 „a küszöb fölött" cellája pedig
**új `clientActionId`-val** állítsa elő az ismételt modell-kérést — különben a
szolgáltatás dedupe-ja hamis zöldet ad. Ez a [L403](../LESSONS.md#l403)
hibaosztálya: a cella a rossz rétegen mér.

### B5 — erőforrás-tulajdonlás (§1/2. szabály)

`grep -rn "\.execute(" lib/features/ai_tutor/` → három hívási hely, amiből a
**végrehajtó** pontosan egy: `action_confirmation_service.dart:131`
(`await executor.execute(action)`), a `_confirmOnce` belsejében. A másik kettő
a registry read-only útja (`domain/tools/tutor_tool_registry.dart:69`) és az
orchestrátor tool-hopja (`orchestration/tutor_orchestrator.dart:386`). A
felület **soha** nem hívja közvetlenül az executort; a felületi invariáns
ezért: `ActionConfirmationService.confirm()` kizárólag az
`SsToolConfirmationSheet` megerősítés-visszahívásából hívható.

### B6 — az AI-mód ma nem áll elő a felületről (az `allowed_paths` egyetlen bővítése)

Lásd az `ai-router` blokk §0.0/B6 megjegyzését. A design system a
komponenseket MÁR szállítja — `lib/core/design_system/components/ai/ss_provenance_badge.dart`,
`…/ai/ss_model_status_card.dart`, `…/cards/ss_coach_action_card.dart`,
`…/cards/ss_insight_card.dart`, `…/overlays/ss_tool_confirmation_sheet.dart` —,
és a `lib/core/design_system/**` a **TILOS zónában marad**: a kör ezeket
**használja**, nem módosítja, és kizárólag a `design_system/public.dart`
barrelen át importálja (E13-R16/F8, a brief §0.0/S12-je).

### B7 — a golden a KAPU architektúráján mérendő (ADR 0426 §3)

A brief §7-je eredetileg `flutter test --update-goldens`-t írt elő, és a
golden-útvonalat a `gate_tests`-be tette. Mindkettő ütközik a merge-elt
[ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)
§2–§3-mal: ez a box **aarch64**, a zöld kaput adó CI **x86_64**, a komparátor
nulla toleranciájú — az ARM-felvétel a CI-ban mindig piros (E13-R17: 2 vak
javító kör; E13-R20: 3 piros CI, majd H5 halt). A §7 ezért a
`tools/golden-x86.sh record` / `check` alakra vált, a golden-útvonal pedig
kikerül a lokális gate-ből. **Ez nem lazítás:** az ARM-futás ezekre a cellákra
a rossz gépet méri (ma hamis zöld), a valódi mérce a `golden-x86.sh check` és
az exact-SHA CI. Merge-elt precedens: E13-R23…R27.

### B8 — a képernyő-leltár őre FELTÉTELESEN mozdul (a §0.0/R4 pontosítása)

A §3 mind a három cél-képernyője **MA is létezik** `*_screen.dart` néven,
tehát ha a kör nem hoz ÚJ képernyőt, a `test/ui/ui_inventory_test.dart`
`hasLength(...)` értéke **nem mozdul, és nem is szabad hozzányúlni**. A
jogosultság a listán marad, de kizárólag arra az esetre, ha a kör tényleges
ÚJ `lib/features/**/*_screen.dart` fájlt hoz — akkor PONTOSAN a szám emelése,
más állítás nem érinthető ([L397](../LESSONS.md#l397)).

### B9 — a kör a képernyőket MÓDOSÍTJA, nem cseréli le (az S11 lint második ága)

A revideált lista mellett a `tools/brief-lint.py` **S11** leletet ad: a
`TutorHomeScreen` típusát a kör fáján KÍVÜL két teszt pinneli
(`test/app/navigation/adaptive_scaffold_test.dart`,
`test/app/offline_network_guard_test.dart`), a `TutorChatScreen`-t és a
`PracticePlanPreviewScreen`-t pedig a saját fájuk tesztjei (§0.0/B2).

Az S11 **első** ága (a pinek felvétele az `allowed_paths`-ba) az
orchestrátornak **tágítás, azaz H3** — a lint saját lábjegyzete és
[L478](../LESSONS.md#l478) is ezt mondja; mérve: a szabály
`outside_screen_pins` predikátuma (`tools/brief-lint.py:234`) KIZÁRÓLAG az
`allowed_paths`-t nézi fedésnek, a `gate_tests`-et nem, tehát a lelet ezzel a
revízióval **láthatóan bent marad**. Ez a második ág tudatos vállalása:

> „Ha a kör a képernyőt bizonyíthatóan nem cseréli le, a §0.0 mondja ki ezt a
> mérést."

**A mérés, és egyben KÖTELEZŐ előírás:** ez a kör a három képernyő
**belsejét** migrálja a design system komponenseire; a `TutorHomeScreen`,
`TutorChatScreen` és `PracticePlanPreviewScreen` **típusneve, fájlneve és
route-regisztrációja változatlan marad**. Átnevezés, típuscsere vagy a
képernyő új típussal való helyettesítése **NEM fér a kör scope-jába** — az
`stopped` jelzés és célzott brief-revízió (§0). A lint által megjelölt
hibaosztály (a kifelé mutató pin CI-only pirosa) ezért nem áll elő; a
biztosíték pedig nem ígéret, hanem **gépi**: mind a négy pinnelő teszt a
`gate_tests`-ben fut, azaz a típus-csere a **lokális** kapun bukik el, a
szerkesztésük viszont a listán kívüliség miatt kizárt.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-42–UI-44 **provenance-tudatos** AI-coaching felülete: streaming,
bizonyíték és tool-megerősítés (SDD Ch13 Kör 29).

## 2. Jelenlegi állapot — mért tények

- Az R12 ADR 0278 kimondta: az AI-eredet látható. Az R13 ADR 0279 kimondta: a
  tool-megerősítés megmutatja az érintett adatot és a módot.
- Az R14 ADR 0280 élő régió költségvetése itt a streaming üzenetre vonatkozik.
- A tanár-réteg **eszközöket** hívhat, amelyek adatot módosítanak vagy
  publikálnak.

## 3. Scope

**Benne van:** a Coach kezdőképernyő helyi / felhő / tartalék és hiányzó modell
állapotai · a beszélgetés streaming üzenete, szerkesztője, beszélgetés-listája és
**bizonyíték-panelje** · a debrief / terv-előnézet megfigyelés–ok–akció és
terv-diff szerkezete · **minden tool-akció** az `SsToolConfirmationSheet`-en át ·
streaming megszakítás, hálózatvesztés, helyi tartalék és tool-eredmény
állapotok · prompt/tool-injekció **felületi fixture**, ami igazolja, hogy nincs
automatikus végrehajtás.

**NINCS benne (tilos):** a tanár-réteg vagy a tool-végrehajtó logikájának
módosítása · a beszélgetés-tartalom analitikába küldése · más képernyők ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `…/ai_tutor/presentation/screens/tutor_home_screen.dart` | a Coach kezdőképernyő (§0.0/B1) |
| `…/ai_tutor/presentation/screens/tutor_chat_screen.dart` | a beszélgetés-felület (§0.0/B1) |
| `…/ai_tutor/presentation/screens/practice_plan_preview_screen.dart` | a debrief / terv-előnézet és a terv-diff (§0.0/B1) |
| `…/ai_tutor/presentation/widgets/` | tool-akció kártya, szerkesztő, üzenetbuborék, bizonyíték-chip, forrás-lap, bannerek (§0.0/B1) |
| `…/ai_tutor/presentation/providers/tutor_providers.dart` | **kizárólag** az AI-mód presentation-szintű kitétele — az A1 ma nem állítható elő (§0.0/B6); `application/`/`domain/` viselkedés NEM módosulhat |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a coaching-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/tutor/*_test.dart` (4) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r29-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a fenti öt bejegyzés KIVÉTELÉVEL — kiemelten
`lib/features/ai_tutor/application/**` és `…/domain/**` (a tanár-réteg és a
tool-végrehajtó logikája, §3) ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0287)

### 5.1 EGYETLEN tool-akció sem fut automatikusan

Publikáló, destruktív és rögzítést indító akció **soha** nem indul a modell
javaslatára közvetlenül — mindig az `SsToolConfirmationSheet` megerősítése után.
A modell bemenete részben nem megbízható (importált dal, közösségi tartalom),
ezért a felület az utolsó védvonal.

**NEM elfogadható gyengítés:** „az olvasó jellegű eszközök futhatnak
megerősítés nélkül" — kivéve, ha a lista **explicit**, zárt és a tervben
rögzített. Nyitott kategória-alapú mentesítés tilos.

### 5.2 Az AI-mód MINDIG látható

Helyi, felhő vagy tartalék — az ADR 0278 §1 kikényszerítése a beszélgetésben,
üzenet szinten is.

### 5.3 A streaming NEM spammelheti a képernyőolvasót

Az ADR 0280 §2 költségvetése: a részleges tokenek nem hangzanak el
folyamatosan; a bejelentés összevont.

### 5.4 A terv-módosítás EXPLICIT, diff-fel

A gyakorlási terv változása előbb **különbségként** látszik, és a felhasználó
fogadja el vagy utasítja el.

### 5.5 A beszélgetés tartalma NEM kerül analitikába

Sem esemény-paraméterként, sem hibajelentésben. Ez adatvédelmi határ.

### 5.6 A hiányzó bizonyíték KIMONDOTT

Ha egy állítás mögött nincs mérési bizonyíték, a felület ezt jelzi — nem
tünteti fel megalapozottként (az ADR 0283 elve a coachingra).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az AI-mód (helyi/felhő/tartalék) mindig látható | `ai_mode_visibility_test.dart` |
| A2 | Egyetlen tool-akció sem fut megerősítés nélkül | `tool_confirmation_test.dart` |
| A3 | A tool-megerősítés visszahívása pontosan egyszer fut | ugyanott |
| A4 | Nem megbízható tartalomból érkező tool-javaslat sem fut automatikusan | `prompt_injection_ui_test.dart` |
| A5 | A streaming bejelentés összevont, nem token-szintű | `streaming_announcement_test.dart` |
| A6 | A terv-módosítás diff-fel, elfogadás/elutasítás mellett jelenik meg | `tool_confirmation_test.dart` |
| A7 | A beszélgetés tartalma nem kerül analitikába | `grep` a diffben |
| A8 | A hiányzó bizonyíték kimondott, nem elhallgatott | `ai_mode_visibility_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r29_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| „Olvasó" tool megerősítés nélkül fut | **A2** |
| Az importált dalban elrejtett utasítás akciót indít | **A4** |
| A megerősítés visszahívása kétszer fut | **A3** |
| Token-szintű felolvasás streaming közben | **A5** |
| A terv némán módosul | **A6** |
| Az üzenet szövege esemény-paraméterként naplózva | **A7** |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A tool-akció három kötelező cellája** (a küszöb: a megerősítés megtörtént-e):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | a felhasználó megszakítja a megerősítést | **0** végrehajtás |
| rajta (a küszöbön) | egyszeri megerősítés | **pontosan 1** végrehajtás |
| a küszöb fölött | a modell ismételten kéri ugyanazt — **ÚJ `clientActionId`-val** (§0.0/B4) | **újabb megerősítés** kell — nincs „emlékezz rá" |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedd, hogy egy
**`TutorAction`** (write/launch proposal) megerősítés nélkül végrehajtódjon —
azaz hívd az `ActionConfirmationService.confirm()`-ot az
`SsToolConfirmationSheet` megerősítés-visszahívása NÉLKÜL → az **A2** cellának
PIROSNAK kell lennie → állítsd vissza. A próba célpontja **nem** a
`ReadOnlyTutorTools` zárt halmaza: arra az ADR 0133 §2 / ADR 0137 §1–2
merge-elt mentesítése áll, és a megkövetelése **H2** lenne (§0.0/B3).

**A mérés RÉTEGE kötött ([L403](../LESSONS.md#l403), §0.0/B4):** az A2/A3
celláinak a végrehajtás TÉNYÉT kell mérniük (az executor hívásszámát), nem egy
widget-típus vagy kulcs jelenlétét — a `clientActionId`-dedupe miatt egy
felszínesen mérő cella hibás felület mellett is zöld marad.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/tutor/ai_mode_visibility_test.dart test/features/tutor/streaming_announcement_test.dart test/features/tutor/tool_confirmation_test.dart test/features/tutor/prompt_injection_ui_test.dart test/features/ai_tutor/presentation/ test/app/navigation/adaptive_scaffold_test.dart test/app/offline_network_guard_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r29_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r29_screens_golden_test.dart
```

> ⚠ **Pre-flight-javítás (§0.0/B7, 2026-08-27):** a brief eredetileg
> `flutter test --update-goldens`-t írt elő, és a golden-útvonalat a lokális
> `gate_tests`-be tette. Ez a box **aarch64**, a kaput adó CI **x86_64**, a
> komparátor nulla toleranciájú — az ARM-felvétel a CI-ban mindig piros
> (E13-R17: 2 vak javító kör; E13-R20: 3 piros CI → H5 halt). A merge-elt
> [ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)
> §2–§3 szerint a felvétel a KAPU architektúráján történik, és a
> golden-útvonal NEM kerül a lokális gate-re. A `--update-goldens` **TILOS**.

A keletkezett PNG-ket **commitolni kell** — enélkül az A9 nem teljesült. A
márkabetűtípusok a teszt-hostban nem töltődnek be (fallback face); ez a
meglévő golden-teszt mért viselkedése, az elrendezést, méretezést és színeket
nem érinti. MIÉRT ez a kör dolga és nem az E13-R36-é: a záró vizuális
regressziós kör csak azt tudja megmondani, hogy valami MEGVÁLTOZOTT — azt,
hogy a képernyő eleve csúnya-e, a saját körében kell látni.

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

> **Review-megjegyzés:** ez a kör `risk = "high"` és AI-tool-végrehajtást érint,
> ezért a review-ban a `security-reviewer` ügynök futtatása kötelező.

## 8. Implementációs sorrend

1. A Coach kezdőképernyő állapotai + az AI-mód látható jelölése.
2. A beszélgetés-felület streaming üzenettel és összevont bejelentéssel.
3. Minden tool-akció az `SsToolConfirmationSheet` mögé + a három cella.
4. A prompt/tool-injekció fixture — automatikus végrehajtás NÉLKÜL.
5. A bizonyíték-panel és a hiányzó bizonyíték kimondása.
6. A debrief megfigyelés–ok–akció szerkezete és a terv-diff.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az „ártalmatlan" olvasó tool.** A kategória-alapú mentesítés csúszós lejtő:
  az injekció pont ezen az úton jut be (A2/A4).
- **A token-szintű felolvasás.** Jóindulatú „azonnali visszajelzés", ami
  felolvasóval elviselhetetlen (A5).
- **A beszélgetés naplózása.** Hibakeresés közben kézenfekvő, és a
  legérzékenyebb szöveges adatot viszi ki (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
