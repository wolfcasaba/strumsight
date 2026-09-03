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

## 5. Javító kör #1 utáni review (2026-09-03, `c9409564..c8be6e7d`)

### 5.1 Az első menet leletei — MIND ZÁRVA (mérve)

| Lelet | Zárás | Mérés |
|---|---|---|
| BLOCKER-1 | ZÁRVA | `tutor_home_screen_test.dart:128` `theme: SsLightTheme.data()`; a Home most `SsModelStatusCard` + `SsButton`; saját gate-futásom a fájllal együtt **ZÖLD** |
| MAJOR-1 | ZÁRVA | a hamis „extension-mentes" állítás javítva a fájl-docban, a `migration-status.md`-ben és a §10.2-ben |
| MAJOR-2 | ZÁRVA | `error: (error, _)` → `error is AppFailure ? error : …`; a két holt ARB-kulcs korlátja mért indoklással kimondva |
| MAJOR-3 | ZÁRVA | chat betöltés → `SsSkeleton`; data üres állapotok → tokenizált `_DataEmptyState` (R6 kivétel MINDKÉT feltétele teljesül: `SsColorScheme`/`SsTypography`/`SsSpacing` + §10-dokumentáció); profile validáció → `SsValidationSummary` |
| MAJOR-4 | ZÁRVA | committolt `textScaler 2.0` × `en`/`hu` cella mind az 5 képernyő saját teszt-fájljában (`R18-R7`, `R18-A19`, `R22-DA14`, `R22-PC7`, `R22-PF7`); a mérés közben egy VALÓDI 1187 px-es `AppBar.actions` túlcsordulást is talált és javított |
| MAJOR-5 | ZÁRVA | képernyőnkénti design-rendszer típus-állítások (Home, Chat, Data ×4, Privacy, Profile ×3) |
| m1–m6 / R16–R17 | ZÁRVA vagy dokumentáltan elhagyva | lásd §10.8–10.9 |

Egyetlen teszt-cella sem törölt, `skip`-elt vagy lazított (`git diff ba6be648..HEAD -- test/` → nincs `-` jelű `testWidgets`/`expect`, `skip: true` = 0).
Saját, izolált klónban futtatott célzott gate (13 útvonal): **ZÖLD, `GATE_EXIT=0`**.
`tools/scope-audit.py`: **OK** (20 changed path, 1 generated/ignored).

### 5.2 ÚJ, NYITOTT lelet — BLOCKER-2 (a CI mérte, nem a célzott kapu)

**A batch öt képernyője a design-rendszert MÉLY útvonalon importálja, nem a
`public.dart` barrelen keresztül — ez merge-elt architektúra-szerződést sért
(E13-R02).**

- Piros cella: `test/core/architecture_dependency_test.dart:754-771` —
  „design system boundaries (E13-R02) real production source reaches the design
  system only via public.dart".
- Sértő importok (24 db): `tutor_home_screen.dart` 4, `tutor_chat_screen.dart` 6,
  `tutor_data_screen.dart` 8, `tutor_profile_screen.dart` 4,
  `tutor_privacy_screen.dart` 2 — mind `import '../../../../core/design_system/<alkönyvtár>/<fájl>.dart'` alakú.
- **Nem a javító kör regressziója:** ugyanez a cella MÁR az első CI-futásban
  (`33707997183`) is piros volt (6 találat a `--log-failed` kimenetben) — az én
  első review-m nem fogta meg, mert a kör célzott kapujában nincs benne, és a
  gate `architecture` lépése (`dart run tool/check_architecture.dart`) ezt a
  szabályt NEM méri (a lépés zölden ment mindkét saját futásomon).
- **A javítás mechanikus és a kör fájllistáján belül van:** a 24 mély import
  helyett fájlonként EGY `import 'package:strumsight/core/design_system/public.dart';`
  — a `public.dart` mind a 68 szükséges szimbólumot exportálja (ellenőrizve:
  `ss_card`, `ss_section`, `ss_surface`, `ss_skeleton`, `ss_failure_state`,
  `failure_presentation`, `ss_button`, `ss_model_status_card`,
  `ss_provenance_badge`, `ss_validation_summary`, `foundations/*`). A mért
  precedens: `lib/features/gamification/presentation/screens/achievements_screen.dart:2`
  (E15-R08) pontosan így importál.
- **A megismétlődés őre:** a kör `gate_tests` listájába fel kell venni a
  `test/core/architecture_dependency_test.dart`-ot (a jövőbeli
  design-rendszer-migrációs briefek sablonjába is), különben a barrel-szabály
  ismét csak a teljes CI-suite-ban derül ki.

### 5.3 Verdikt: **H5 HALT** — merge TILOS

A kör CI-ja **kétszer piros** (`33707997183` a BLOCKER-1-en, `33711465885` a
BLOCKER-2-n), ami az ADR 0087 §2 szerint kötelező megállás — a maradék javítás
önmagában triviális, de a szabály nem a nehézségtől függ. A kör munkája
(`c8be6e7d`, PR #540) megmarad az ágon; a folytatás az önjavító session dolga a
fenti, mért javítás-recepttel.

## 6. Javító kör #2 utáni review (2026-09-03, `41b6285f..d52410da`)

**Előzmény:** az §5.3 H5 haltját az ADR 0112 önjavító köre oldotta fel — **ADR 0494**
(`ab2f98db`, PR #541) a `main`-en. A heal (D2) a `designSystemImportsMustUsePublicBarrel`
szabályt a `tool/check_architecture.dart`-ba tette, tehát a barrel-szerződést mostantól
MINDEN kör `round-gate.sh` `architecture` lépése méri, lokálisan. A D3 szerint a H5
piros-CI-számláló egy ilyen, a gyökérokot javító merge-elt heal után **nulláról** indul;
a zöld kapu (teljes CI-suite + Router CI a merge SHA-n) változatlan.

**Upstream-szinkron (§0.3):** az ág `--no-ff` merge-cselte az `origin/main`-t (`70aeb83c`),
`git merge-base --is-ancestor origin/main HEAD` → **0**. A brief `§0.0.C` (R18–R21) a
javító kör #2 szerződése; a `test/core/architecture_dependency_test.dart` felkerült a
`gate_tests`-re és a §7 gate-sorára (R20).

### 6.1 A BLOCKER-2 ZÁRVA — mérve

| Mérés (a reviewer SAJÁT futása) | Eredmény |
|---|---|
| Célzott gate izolált klónban (`/tmp/review-e15-r09-fix2`, a §7 **19** lépése) | **MINDEN GATE ZÖLD** — benne `test/core/architecture_dependency_test.dart` **zöld** és `architecture` **zöld** |
| `tools/scope-audit.py --base 41b6285f` | `Legacy scope audit OK (6 changed path(s), 0 generated/ignored)` |
| Mély importok utó-állapota (`grep -c "core/design_system/"`) | mind az 5 képernyőn **1** (a barrel), előtte 4/6/8/4/2 = **24** |
| Router CI a `d52410da` head SHA-n | `success` (`33719099381`) |
| `flutter-reviewer` (KÖTELEZŐ, risk=high) | 0 BLOCKER / 0 MAJOR / 0 MINOR — a diff bizonyítottan import-only (a `design_system` sorok kiszűrésével a két revízió byte-azonos); mind a 13 mély-importált fájl exportált a barrelből; a barrel 117 nevű felülete metszve az összes többi import szimbólumaival: **0 ütközés**; extension-tag nincs, tehát ambiguous-extension sem lehet |
| `flutter-devil-advocate` (KÖTELEZŐ, risk=high) | falszifikálni nem tudta: teszt-cella törlés/`skip`/gyengítés az EGÉSZ ágon 0 (`git diff origin/main...HEAD -- test/`), a cella-számok nőttek (chat 16→19, data 9→16, home 4→6, privacy 6→8, profile 5→7); a **relatív** barrel-forma mérten megfelel (a checker `_resolveProjectUri`+`_normalizePath` után `lib/core/design_system/public.dart`-ra old fel, és a `design_system_barrel_architecture_test.dart:129` pont a relatív alakot pinneli); `lib/` egészében **0** mély design-system import maradt |

Az implementer §10.10 valódi-sértés próbája korrekt: egy mély import ideiglenes
visszaállítása MÉRTEN pirosra vitte a célzott
`test/core/architecture_dependency_test.dart` cellát és az `architecture` lépést,
majd a visszaállítás után a gate ismét zöld. Ez az őr tehát nem holt cella.

### 6.2 Acceptance-mérleg — záró

| # | Verdikt | Indok |
|---|---|---|
| A1 | teljesül | 80/96 (83.333%), függetlenül újramérve; a barrel-import a `contains('design_system')` mérést nem billenti |
| A2 | teljesül | MAJOR-3 zárva (javító kör #1); az n1 chat-banner dokumentált follow-up (R9) |
| A3 | teljesül | committolt `textScaler 2.0` × `en`/`hu` cellák mind az 5 képernyőn (MAJOR-4 zárva) |
| A4 | teljesül | a kipinnelt cellák zöldek; a teszt-diff az egész ágon szigorúan additív |
| A5 | teljesül | 96 képernyő, változatlan |
| A6 | teljesül (őszinte megszorítással) | a hivatkozott guard mérten nem fedi a `lib/features/**`-ot; a bizonyíték a két reviewer-agent és a saját kézi olvasás — új beégetett szöveg nincs |
| A7 | teljesül | `migration-status.md` 80/96 (83.333%) |

### 6.3 Nyitott leletek: **NINCS**

BLOCKER: 0 · MAJOR: 0 · MINOR: 0. A korábbi MINOR-ok (m1–m6) a javító kör #1-ben
zárva vagy dokumentáltan elhagyva (§10.8–10.9).

**NOTE (nem lelet, jövőbeli körre):** a `test/tooling/design_system_barrel_architecture_test.dart`
(a szabály saját, `main`-ről érkezett őre) nincs ezen a kör `gate_tests`-én; a fedése
átfed a gate `architecture` lépésével, tehát ez redundancia, nem rés — de a jövőbeli
design-rendszer-migrációs brief-sablonba érdemes felvenni.

## 7. VÉGSŐ DÖNTÉS: **APPROVED**

Merge engedélyezve, amint a zöld kapu a **merge SHA-n** teljesül: Full Gate
(`full-gate.yml`, a `round-ci-plan.py` terve: tisztán Dart/dokumentum-diff,
`native_gate=false`) + Router CI + a fenti célzott gate — mind zöld.
