# E15-R09 — kör-review (AI Tutor 5 képernyő migrálása)

- **Kör:** `E15-R09`, ág `sonnet-impl/e15-r09-ai-tutor-migration`
- **Reviewer:** Claude (Opus 5, orchestrátor-ülés), ADR 0055 szerint READ-ONLY
- **Implementer:** `sonnet-impl` (Claude Sonnet 5), 11 commit `ba6be648..c6504b53`
- **Kockázat:** `high` → a `flutter-reviewer` ÉS a `flutter-devil-advocate` futott (KÖTELEZŐ, brief §0.0)
- **Dátum:** 2026-09-03

## 1. Mért bizonyítékok (a reviewer SAJÁT futásai)

| Mérés | Eredmény |
|---|---|
| Célzott gate izolált `/tmp` klónban (`/tmp/review-e15-r09`, a §7 12 útvonala) | **ZÖLD**, `GATE_EXIT=0` |
| `tools/scope-audit.py --base ba6be648` | `Legacy scope audit OK (18 changed path(s), 0 generated/ignored)` |
| Wrapper-jelzés | `status=done`, `scope_audit=ok`, **`gate_shape=VIOLATION`** → az implementer csővezetéken futtatta a gate-et, tehát a „17/17 zöld" sora NEM bizonyíték (L09); ezt a fenti saját futásom váltja ki |
| `flutter test test/features/ai_tutor/presentation/tutor_home_screen_test.dart` (a célzott gate-en KÍVÜLI fájl) | **PIROS — 2 cella:** `R18-R1` és `R18-R3` |
| Router CI a `c6504b53` head SHA-n | `success` (`33707993024`) |
| Full Gate a `c6504b53` head SHA-n | futott, de a fenti piros cellák a **teljes suite** része → a kapu nem zárható ezen a SHA-n |
| Migrációs arány (független újramérés) | `MIGRATED=80 / TOTAL=96` (83.333%) — az állítás igaz |

## 2. Leletek

### BLOCKER-1 — a kör pirosra viszi a `tutor_home_screen_test.dart`-ot; a hordozó premissza („`SsCard` extension-mentes") MÉRTEN HAMIS

**Mérve.** `lib/core/design_system/components/surfaces/ss_card.dart:15-17` → `SsSurface` →
`ss_surface.dart:42` `elevation.resolve(Theme.of(context))` →
`lib/core/design_system/foundations/ss_elevation.dart:14-15`:

```dart
final colors = theme.extension<SsColorScheme>()!;
final behavior = theme.extension<SsThemeBehavior>()!;
```

Két bang. Az `SsCard` tehát **NEM** extension-mentes (az `SsSection` igen, az
állítás rá helytálló). A `test/features/ai_tutor/presentation/tutor_home_screen_test.dart:118-129`
csupasz `MaterialApp.router`-t pumpál `theme:` NÉLKÜL, és a cellák
`expect(tester.takeException(), isNull)`-t állítanak:

- `R18-R1` → `/tutor/home` → `TutorHomeScreen` → `_ModelStatusCard` → `SsCard` → null-check TypeError;
- `R18-R3` → `/tutor/chat` → `TutorChatScreen` → `_AiModeIndicator`/`SsProvenanceBadge` + `_EmptyState` (`tutor_chat_screen.dart:228-229`) → ugyanaz.

Saját futásom kimenete: `Some tests failed. … R18-R1 … R18-R3`. A fájl sem az
`allowed_paths`-on, sem a `gate_tests`-ben nincs, ezért a célzott gate zöld
maradt — a **teljes CI-suite** viszont ezt futtatja, tehát a zöld kapu ezen a
SHA-n nem zárható (H5-kockázat).

**Irány:** brief-revízió (`§0.0.B/R10`): a teszt-fájl felkerül az `allowed_paths`-ra
ÉS a `gate_tests`-be, és megkapja ugyanazt az egysoros `theme: SsLightTheme.data()`
drótozást, mint a másik hat harness. Ezzel a Home-képernyő „extension-mentes"
kényszere is megszűnik.

### MAJOR-1 — hamis MÉRT állítások három committolt helyen (a BLOCKER-1 gyökéroka)

`lib/features/ai_tutor/presentation/screens/tutor_home_screen.dart:22` és `:30-31`
(„`SsCard` (an extension-free surface primitive)", „`SsCard`/`SsSurface`/`SsSection`
read no extension"), `docs/ui/migration-status.md:18,25`, valamint a brief §10.2
(„`Card` → `SsCard` (extension-mentes…)"). Ezeket későbbi körök MÉRT igazságként
bányásszák ki — a javítás nem elég a kódban, a három dokumentum-helyet is javítani kell.

### MAJOR-2 — információvesztés a hiba-ágakon (§5.1 + ADR 0277)

`lib/features/ai_tutor/presentation/screens/tutor_data_screen.dart:193-204` és `:233-244`
eldobja a tényleges hibát (`error: (_, _) =>`) és beégeti a
`const UnknownFailure(retryable: true)`-t. Következmények: (a) a két korábban
KÜLÖNBÖZŐ lokalizált üzenet (`tutorDataMemoryLoadFailed`,
`tutorDataConversationsLoadFailed`) egyetlen generikus szövegre olvad, és a két
kulcs `lib/`-ben mérten sehol nem hivatkozott (holt kulcs); (b) egy valóban NEM
újrapróbálható hiba is újrapróbálhatóként jelenik meg; (c) egy
`networkUnavailable` sosem kapja meg a saját címét/`continueOffline` akcióját.
Az `SsFailurePresentation.from` (`failure_presentation.dart:38-47`) pontosan a valódi
`AppFailure` leképezésére való.

### MAJOR-3 — az A2 négy állapoton nem teljesül, és három közülük DOKUMENTÁLATLAN

| Hely | Mai állapot | Miért lelet |
|---|---|---|
| `tutor_chat_screen.dart:183` | nyers `CircularProgressIndicator` | a §5.2 szó szerint ezt nevezi meg „NEM elfogadható gyengítés"-ként; a fájl az `allowed_paths`-on van; a §10.7 nem említi |
| `tutor_data_screen.dart:178` | `Text(l10n.tutorDataMemoryEmpty)` | üres állapot, sem `SsEmptyState`, sem R6-kivétel — és NINCS tokenizálva |
| `tutor_data_screen.dart:215` | `Text(l10n.tutorDataConversationsEmpty)` | ugyanaz |
| `tutor_profile_screen.dart:93-101` | nyers `Text` inline `TextStyle`-lel | validációs hiba; az `SsValidationSummary` létezik és nem lett használva; a §10 nem indokolja |

A §0.0.A/R6 kivétel-osztály CSAK akkor áll, ha az állapot (a) tokenekkel van
stílusozva ÉS (b) képernyőnként, mért indoklással dokumentált — a chat `_EmptyState`-nél
ez teljesül, a fenti négynél nem.

### MAJOR-4 — az A3-nak nincs committolt mércéje; a két megtalált túlcsordulás-javítás védtelen

A §10.5 mérőeszköze `/tmp/e15_r09_textscale_probe_test.dart` volt, ami törölve
lett. A repóban egyetlen `textScaler` cella sincs a batch öt képernyőjére
(`grep`-elve a `test/features/ai_tutor/presentation/` és `test/features/tutor/` alatt);
2.0×-en csak a golden `_scale2` pár mér, az is `en`+dark, csak home+chat. Az
implementer SAJÁT mérése szerint `data@1.5hu` és `home@2.0hu` pirosak VOLTAK —
pontosan ezek a cellák térhetnek vissza észrevétlenül.

### MAJOR-5 — a §6.1 első sorának mércéje egyetlen képernyőn létezik

A batch egészében EGY produkciós design-rendszer-állítás van:
`test/features/ai_tutor/presentation/tutor_data_screen_test.dart:459`
(`find.byType(SsFailureState)`). Egy hibás/üres állapot nyers `Text`-re
visszaállítása a chat/home/profile/privacy képernyőn — és a data-képernyő
`conversations` ágán — SEMMIT nem vinne pirosra. A kötelező valódi-sértés próba
azon az egy helyen futott, ahol az őr amúgy is létezik (a próba maga korrekt).

### MINOR

- **m1 — az A6 hivatkozott bizonyítéka üres halmaz.** `test/l10n/hardcoded_string_guard_test.dart:18-23`
  csak a `lib/core/design_system/**` alá néz, `lib/features/**`-ot nem — az A6
  „Bizonyíték" oszlopa és a §6.1 4. sora ezen a körön halott cella. (A TARTALOM
  rendben: mindkét reviewer kézi olvasása szerint nincs új beégetett szöveg.)
- **m2 — a golden fejléc-komment új hamis állítást kapott.** `test/ui/goldens/e13_r29_screens_golden_test.dart:12-16`:
  a `TutorHomeScreen` „renders identically under either theme choice" — a régi
  `AppTheme.dark()` alatt ma összeomlana (BLOCKER-1), és a PNG-je is változott.
- **m3 — ikon-divergencia a körön BELÜL.** A Home `_ModeChip` `Icons.smartphone_outlined`-et
  ad a „local"-hoz, a Chat viszont `SsProvenanceBadge`-en át `SsStatusMarkers`
  `Icons.memory_outlined`-ját — két glyph ugyanarra a fogalomra, egy tapra egymástól.
- **m4 — dokumentálatlan elrendezés-változás három CTA-n.** `tutorDataExportRedacted`,
  `tutorDataDeleteAllTrigger`, `tutorProfileAddGoal` teljes szélességből
  `Align(centerStart)`-tal intrinsic szélességűvé vált (kisebb tap-target); a §10
  nem említi.
- **m5 — token-adoptálás következetlen a batch-en belül.** `tutor_data_screen.dart:259/264/271/276`
  nyers `vertical: 2` / `width: 8` marad, míg a `tutor_privacy_screen.dart`
  byte-azonos lista-blokkja tokenizálva lett; a privacy `SsSpacing.space1 / 2`
  aritmetikát használ, ami leviszi a rögzített skáláról.
- **m6 — két kártya-kezelés egy oszlopban.** `_MemoryFactRow` → `SsCard`,
  `_ConversationRow` → nyers `Card` (a `ListTile(contentPadding: EdgeInsets.zero)`
  út nyitva állt).

### NOTE

- **n1 — a §3 „chat hibaállapot" előírása MÉRTEN hamis premisszán állt.** A
  „nincs backend" állapot nem „nyers szöveg": strukturált `TutorBanner`
  (`lib/features/ai_tutor/presentation/widgets/tutor_banners.dart:160-170` — ikon +
  cím + törzs + `semanticsLabel` + `retry` akció), ami a kör fájllistáján KÍVÜL él.
  Az implementer ezt helyesen, önként jelentette (§10.7), nem kerülte meg némán.
  Feloldás: `§0.0.B/R9` revízió + follow-up kör a banner-migrációra.
- **n2 — az `SsSection` a szemantika-fát is megváltoztatja** (`Semantics(header: true)`,
  `titleMedium`) — a11y-javulás, de a §5.1 „bitre azonos" kikötése mellett a §10-ben
  ki kell mondani.
- **n3 — a viselkedés-megőrzés a chat stream-úton MÉRTEN rendben:** `initState`/`dispose`,
  `_onControllerChanged`, `_scrollToBottom`, `controller.cancel`, `TutorBanner`/`onRetry`,
  a `liveRegion` szemantika és a `TutorComposer` érintetlen; minden `Key` és
  szemantika-címke megmaradt; a consent-kapcsolók (ADR 0132) változatlanok; a
  teszt-diff kizárólag additív (nincs törölt/`skip`-elt/lazított cella).

## 3. Acceptance-mérleg (első kör)

| # | Verdikt | Indok |
|---|---|---|
| A1 | teljesül (a mérés definíciója szerint) | 80/96, függetlenül újramérve |
| A2 | **NEM** | MAJOR-3 (4 állapot), n1 (chat hibabanner) |
| A3 | **bizonyítatlan** | MAJOR-4 |
| A4 | **NEM** | a kipinnelt `tutor_home_screen_test.dart` 2 cellája piros (BLOCKER-1); a teszt-diff maga viszont additív |
| A5 | teljesül | 96 képernyő, változatlan |
| A6 | **bizonyítatlan** | m1 (a hivatkozott őr nem nézi a `lib/features/**`-ot) |
| A7 | teljesül | `migration-status.md` 80/96 (83.333%) |

## 4. Verdikt

**CHANGES REQUESTED** — merge TILOS. Nyitva: 1 BLOCKER + 5 MAJOR. A javító kör a
lánc normál útja (user-döntés 2026-07-31): ugyanaz a motor (`sonnet-impl`), a
fenti leletlistával, a `§0.0.B` brief-revízió mellett.

## 5. Javító kör után (kitöltés a második menetben)

_(a reviewer tölti ki)_
