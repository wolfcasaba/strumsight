# E07-R22 — Weekly Plan és Today screen

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 135ef4af`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 22
- **Kör-azonosító:** `E07-R22`
- **Branch:** `<motor>/e07-r22-weekly-and-today-screen`
- **Előfeltétel:** `E07-R21` merge-elve (előnézet)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a határt az ADR 0258 §4 (helyi dátum)
  rögzíti.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R03 helyi-dátum
> modelljét és az R15 pihenőnap-jelölését — a §5.1/§5.2 ezekre épül. Mérd meg
> a projekt **deep link** mintáját is (`lib/app/routing/`). Eltérésnél §0.0
> revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/presentation/screens/weekly_plan_screen.dart",
  "lib/features/practice_generator/presentation/screens/today_plan_screen.dart",
  "lib/features/practice_generator/application/controller/active_plan_controller.dart",
  "lib/features/practice_generator/application/controller/today_plan_controller.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/presentation/today_plan_screen_test.dart",
  "test/features/practice_generator/application/today_plan_controller_test.dart",
  "docs/rounds/e07-r22-weekly-and-today-screen.md",
]
gate_tests = [
  "test/features/practice_generator/presentation/today_plan_screen_test.dart",
  "test/features/practice_generator/application/today_plan_controller_test.dart",
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

## 0.0 Pre-flight revízió (2026-08-18, Sonnet 5 orchestrátor)

- **Mérés — a pihenőnap TÉNYLEGES jelzése a `PracticeDay`-en:** a ma
  `main`-en élő `GenerationOrchestrator._assembleDay`
  (`lib/features/practice_generator/application/service/generation_orchestrator.dart:213-244`)
  minden napra `status: PracticeItemStatus.planned`-ot ír (a pinnelt 8 érték
  — `practice_block.dart:13` — között NINCS `rest` státusz), és a
  pihenőnap kandidátus nélkül marad, tehát `blocks: []` — a `BlockKind.rest`
  enum-érték (`plan_enums.dart`) létezik, de az `_assembleBlock` SOHA nem
  konstruálja (csak kiválasztott `ScheduleCandidate`-ból épít blokkot,
  pihenőnapon nincs ilyen). Az EGYETLEN túlélő jelzés a `reasonCodes` lista:
  a `WeeklyScheduler` a pihenőnapra pontosan
  `[ScheduleDecisionReason.restDay.code]`-ot ír (`weekly_scheduler.dart:245`),
  ami a `scheduling_policy.dart:95` szerint a `'schedule.decision.restDay'`
  string — textuálisan elkülönítve a kihagyott/nem-elérhető nap
  `'schedule.decision.dayUnavailable'` kódjától (`scheduling_policy.dart:92`)
  — és ez a lista a `PracticeDay`-be változatlanul bekerül
  (`reasonCodes: decision.reasonCodes`, `generation_orchestrator.dart:242`).
- **Feloldás — pihenőnap detektálás:** az A2/§5.2 kontraktusa PONTOSAN ez:
  `day.reasonCodes.contains(ScheduleDecisionReason.restDay.code)` (a
  `scheduling_policy.dart` már exportálva a `public.dart`-on, új export nem
  kell). Az implementáció NEM alapulhat `status`-on (mindig `planned`, amíg
  a nap el nem múlik) és NEM `blocks.any((b) => b.kind == BlockKind.rest)`-en
  (ez a konstruktor-út halott — mindig `false`, tehát a pihenőnap ezen az
  ágon MINDIG mulasztásnak látszana, pont az A2 által tiltott hiba). A
  kihagyott/nem-elérhető naptól a `'schedule.decision.dayUnavailable'` kód
  különbözteti meg — a két eset (`restDay` vs. `dayUnavailable`) vizuálisan
  is különböző, semleges (nem büntető) megjelenítést kap; a §5.2 csak a
  pihenőnapról rendelkezik explicit módon, a nem-elérhető nap megjelenítése
  implementer-választás, amíg nem büntető jellegű.
- **Mérés — deep link, TÉNYLEGES bekötés:** `lib/core/notifications/
  nudge_service.dart` (`_scheduleWeek`, sor 140–162) a `zonedSchedule`
  hívásban NEM ad `payload`-ot, és az `_init()` (sor 85–102) nem regisztrál
  `onDidReceiveNotificationResponse`-t — az értesítés koppintása ma
  SEMMILYEN adatot nem hordoz. `lib/app/routing/app_router.dart` és
  `app_route.dart` nem ismer értesítés-koppintásból induló navigációt, és
  mindkét fájl LISTÁN KÍVÜLI (nincs az `allowed_paths`-ban). A körnek tehát
  ma nincs élő „deep link"-je, amit mérni lehetne.
- **Feloldás — deep link scope:** az A7/§5.4 kontraktusa a kör saját,
  engedélyezett fájljain belül él: a `today_plan_screen.dart` (vagy egy
  típus a `today_plan_controller.dart`-ban) egy EXPLICIT, TÍPUSOS, nullable
  paraméter-objektumot fogad (pl. route `extra`, vagy egy már feloldott
  `Map<String, String>` — NEM nyers, parse-olatlan URI-string), és
  ismeretlen/hiányzó/rossz típusú érték esetén a §5.3 szerinti biztonságos
  nézetre esik vissza, kivétel nélkül. A teszt ezt a típust KÖZVETLENÜL
  konstruálja unit/widget szinten. A valódi értesítés-koppintás → útvonal
  bekötés (a `NudgeService` payloadja és az `app_router.dart` regisztrációja)
  NEM ennek a körnek a dolga — ugyanaz a minta, mint minden korábbi E07 kör:
  a kontraktus kész, a production bekötés egy későbbi, emberi döntésű kör
  (mindkét érintett fájl listán kívüli, `allowed_paths` byte-for-byte
  változatlan).
- **Mérés — ADR-szükséglet:** az ADR 0258 §4 („Az elérhetőség helyi
  dátumhoz kötött, nem UTC-pillanathoz") szó szerint lefedi az §5.1 határt —
  ellenőrizve a fájl tényleges szövegében, nem csak a brief-glosszájából
  (vö. L307: a glossza és az ADR eltérhet). A kör nem hoz új architekturális
  döntést, ezért **nincs új ADR-szám foglalva** — a brief saját „nincs" jelzése
  megerősítve, nem csak elfogadva.
- **Feloldás — change-set indoklás (§5.5):** a meglévő `PlanChangeReason`
  hat értéke közül (`plan_change_set.dart:37-43`) a tanuló-indított
  rövidítés/csere/kihagyás akció kódja `PlanChangeReason.learnerReschedule` —
  a `systemAdaptation` az ADR 0263 §4 szerint a determinisztikus
  `PlanRepairer` SAJÁT, automatikus lépéseinek van fenntartva, nem a tanuló
  explicit akciójának; a kettő összemosása provenance-hibát adna (vö. L308 —
  hasonló hibaosztály egy korábbi körben már mért).
- **Scope:** mindhárom feloldás kizárólag a már engedélyezett fájlokon
  belüli implementációs döntés — az `allowed_paths` byte-for-byte
  változatlan, 0 új fájl, 0 domain-módosítás.

## 1. Cél

Az aktív terv napi használati felülete és **egygombos következő lépés**
(SDD Ch8 Kör 22).

## 2. Jelenlegi állapot — mért tények

- Az R03/R15 helyi dátumot használ (ADR 0258 §4) — a „ma" számítása ebből jön.
- Az R15 megkülönbözteti a **pihenőnapot** a kihagyott naptól.
- Az R19 repositoryja adja az aktív tervet.

## 3. Scope

**Benne van:** heti és „ma" nézet · hátralévő idő és következő blokk ·
indítás / csere / kihagyás / rövidítés / szüneteltetés akciók · pihenőnap és
befejezett nap kezelése · **helyi dátum** alapú „ma" · értesítési deep link
biztonságos megnyitása.

**NINCS benne (tilos):** a Practice Engine végrehajtása (Kör 23) · a domain
módosítása · flag `true`-ra állítása · `DateTime.now()` a vezérlőben
(injektált óra) · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `presentation/screens/weekly_plan_screen.dart` | **ÚJ** |
| `presentation/screens/today_plan_screen.dart` | **ÚJ** |
| `application/controller/active_plan_controller.dart` | **ÚJ** |
| `application/controller/today_plan_controller.dart` | **ÚJ** — „ma" számítás |
| `lib/l10n/app_en.arb`, `app_hu.arb` | a szövegek |
| `public.dart` | a barrel bővítése |
| `test/…/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r22-…md` | a §10 handoff |

**Tilos zóna:** `lib/app/config/feature_flags.dart` · a generátor domain-rétege ·
más `lib/features/**` · `docs/adr/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A „ma" HELYI dátumból számol, injektált órával

Nem `DateTime.now()` a widgetben. Az időzóna-váltás nem duplikálhatja vagy
ugorhatja át a napot (ADR 0258 §4).

**NEM elfogadható gyengítés:** UTC-alapú „ma" — utazáskor és DST-váltáskor
rossz napot mutatna.

### 5.2 A pihenőnap NEM kihagyott nap

Vizuálisan és adatilag is elkülönül. A pihenőnap teljesített állapot, nem
mulasztás — különben a rendszer bünteti a tanulót azért, mert betartotta a
tervet.

### 5.3 Terv nélkül ÉRTELMES üres állapot

Nincs aktív terv → a képernyő elmagyarázza, mit lehet tenni, nem hibát mutat.

### 5.4 A deep link BIZTONSÁGOSAN nyit

Az értesítésből érkező link csak akkor visz a „ma" nézetre, ha van aktív terv
és a flag engedi; egyébként biztonságos célra esik vissza. Ismeretlen vagy
manipulált paraméter nem okozhat összeomlást.

### 5.5 A rövidítés OKKAL jár

A „ma rövidebb" akció change-setet ír (ADR 0263 §4 mintájára), nem csendben
módosít.

### 5.6 Minden szöveg ARB-n át, hu + en

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Nincs aktív terv → értelmes üres állapot | `today_plan_screen_test.dart` |
| A2 | A pihenőnap NEM mulasztásként jelenik meg | ugyanott |
| A3 | Időzóna-váltásnál a „ma" nem duplikálódik és nem ugrik | `today_plan_controller_test.dart` |
| A4 | A hátralévő idő és a következő blokk helyes | ugyanott |
| A5 | A rövidítés change-set okot ad | ugyanott |
| A6 | A szüneteltetés nem törli a tervet | ugyanott |
| A7 | Ismeretlen deep-link paraméter nem omlaszt össze | `today_plan_screen_test.dart` |
| A8 | Minden szöveg ARB-ből (hu + en) | l10n paritás |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| UTC-alapú „ma" | **A3** |
| A pihenőnap mulasztásként | **A2** |
| Üres állapot helyett hibaüzenet | A1 |
| A szüneteltetés törli a tervet | A6 |
| A deep link ellenőrzés nélkül | A7 |
| A rövidítés indoklás nélkül | A5 |

**A napváltás három kötelező cellája** (a küszöb: a helyi éjfél):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | helyi 23:59 | a mai nap látszik |
| rajta (a küszöbön) | helyi **00:00** | **már a következő nap** látszik |
| a küszöb fölött, időzóna-váltással | 00:30, közben +1 óra eltolás | **ugyanaz** a nap — nem duplikálódik |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** számold a „ma"-t
UTC-ből → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/presentation/today_plan_screen_test.dart test/features/practice_generator/application/today_plan_controller_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `today_plan_controller.dart` — helyi dátum, injektált óra.
2. `active_plan_controller.dart` — akciók, change-settel.
3. `today_plan_screen.dart` — üres állapot, pihenőnap, következő blokk.
4. `weekly_plan_screen.dart`.
5. Deep link kezelés, fail-safe visszaeséssel.
6. Tesztek a §6.1 három napváltás-cellájával.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az UTC-alapú „ma".** A legkönnyebb hiba, és utazáskor rossz napot mutat —
  a tanuló azt hiszi, lemaradt (A3).
- **A pihenőnap mint mulasztás.** A rendszer megbüntetné a tanulót azért,
  mert betartotta a saját tervét (A2).
- **A deep link.** Külső bemenet: ellenőrzés nélkül összeomlást vagy rossz
  állapotot okoz (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
