# E07-R22 — Review

Brief: docs/rounds/e07-r22-weekly-and-today-screen.md
Diff: `git diff 4c0b6b82..cbee3d1c` (pre-flight commit → implementer commit) on `terra/e07-r22-weekly-and-today-screen`
Reviewer: Claude (Sonnet 5, orchestrátor) · Dátum: 2026-08-18
Verdikt: APPROVED

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 2

Minden gate independently újrafuttatva egy izolált `/tmp/review-e07-r22`
klónban (nem az implementer saját munkapéldányában). A legmagasabb kockázatú
kritérium (A3, helyi dátum vs. UTC) egy saját, a jelentésben dokumentált
valódi-sértés próbával is megmérve — nem csak az implementer önjelentése
alapján elfogadva.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Nincs aktív terv → értelmes üres állapot | ✅ | `today_plan_screen_test.dart`: „A1: no active plan renders a useful empty state" zöld; `today_plan_screen.dart:49` `_EmptyState` |
| A2 | A pihenőnap NEM mulasztásként jelenik meg | ✅ | `today_plan_controller.dart:85` `day.reasonCodes.contains(ScheduleDecisionReason.restDay.code)` — a pontosan a §0.0 pre-flightban mért, egyetlen élő jelzés; teszt „A2: rest day is never rendered as a missed day" zöld |
| A3 | Időzóna-váltásnál a „ma" nem duplikálódik és nem ugrik | ✅ | `today_plan_controller.dart:54-55` `LocalDate(now.year, now.month, now.day)` — nincs `.toUtc()`. 3/3 `A3 …` teszt zöld. Saját reviewer-próba lent (§ „Valódi-sértés próba") |
| A4 | A hátralévő idő és a következő blokk helyes | ✅ | `today_plan_controller.dart:116-130` — nem-terminális blokkok `order` szerint rendezve, első = nextBlock, összeg = remainingTime; teszt „A4 …" zöld (order 1/3/2 bemeneten méri a rendezést, nem csak a lista-sorrendet) |
| A5 | A rövidítés change-set okot ad | ✅ | `active_plan_controller.dart:161-176` minden mutáció `PlanChangeReason.learnerReschedule`-t ír, nem `systemAdaptation`-t (a §0.0 pre-flight pontosan ezt pinnelte, mert az ADR 0263 §4 a `systemAdaptation`-t a repairer saját lépéseinek tartja fenn); teszt „A5 …" zöld |
| A6 | A szüneteltetés nem törli a tervet | ✅ | `active_plan_controller.dart:91-98` `pause()` csak `status`-t vált, `days` érintetlen; teszt „A6 …" explicit `expect(update.plan.days, plan.days)` zöld |
| A7 | Ismeretlen deep-link paraméter nem omlaszt össze | ✅ | `TodayPlanRouteRequest.tryParse` (`today_plan_controller.dart:156-163`) típus- és kulcs-ellenőrzött, csak `Map<String,String>` egyetlen helyes kulcs-érték párral ad vissza nem-null objektumot; `today_plan_screen.dart:36-42` a `permits()`-en átbukó/letiltott launch esetén `null` plant ad a kontrollernek. 2/2 „A7 …" teszt zöld (ismeretlen destination ÉS letiltott flag mellett is biztonságos üres állapot) |
| A8 | Minden szöveg ARB-ből (hu + en) | ✅ | gate `l10n` lépés: „L10n parity OK (en → hu, 1354 message(s))"; a két képernyőben nincs hardcoded felhasználói szöveg (csak `Key`-ek, amik nem UI-szöveg) |

### 6.1 Mérce-mátrix — a kötelező napváltás-cellák

| Cella | Bemenet | Elvárt | Teszt | Eredmény |
|---|---|---|---|---|
| a küszöb alatt | helyi 23:59 | a mai nap látszik | „A3 below threshold" | zöld |
| rajta | helyi 00:00 | a következő nap látszik | „A3 at threshold" | zöld |
| a küszöb fölött, TZ-váltással | 00:30 | ugyanaz a nap | „A3 above threshold" | zöld |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs**.

Saját, független futtatás (nem az implementer signal-fájljából átvéve):

```
$ python3 tools/scope-audit.py --repo /tmp/review-e07-r22 \
    --brief docs/rounds/e07-r22-weekly-and-today-screen.md --base 4c0b6b82
Legacy scope audit OK (4c0b6b82..cbee3d1c1b8a, 10 changed path(s), 0 generated/ignored)
```

A 10 megváltozott útvonal pontosan a brief §4 tíz bejegyzése (4 új Dart fájl,
2 ARB, `public.dart`, 2 teszt, a brief saját §10 kiegészítése). `test/fixtures/
practice_generator/validation/validation_fixtures.dart` (a megosztott
fixture) **érintetlen** — a meglévő `buildDay`/`buildPlan`/`buildBlock`/
`buildCandidate` helpereket használja módosítás nélkül.

## Valódi-sértés próba (reviewer-oldali, eldobható, ELVÉGEZVE)

A legmagasabb kockázatú kritérium (A3) az implementer önjelentésén TÚL saját
kézzel is megmérve, egy MÁSODIK izolált klónban (`/tmp/review-e07-r22`), az
implementertől függetlenül:

1. Ez a box UTC-ben fut (`timedatectl show Timezone` → `Etc/UTC`) — ambiens
   TZ nélkül egy `.toUtc()`-hiba NEM buktatna semmit, mert a konverzió
   no-op lenne. A próba ezért explicit `TZ=Europe/Berlin`-nel fut, ugyanúgy,
   ahogy az implementer §10 handoffja is leírja.
2. `today_plan_controller.dart:54` ideiglenesen `now = clock().toUtc()`-re
   cserélve.
3. `TZ=Europe/Berlin flutter test test/features/practice_generator/
   application/today_plan_controller_test.dart` → **PIROS**, pontosan a
   6.1 táblázat két felső cellájában:
   - „A3 at threshold": `Expected: DayId(day.19); Actual: DayId(day.18)`
   - „A3 above threshold": `Expected: LocalDate(2026-08-19); Actual: LocalDate(2026-08-18)`
   (a „below threshold" cella zöld marad — helyesen, hiszen 23:59 helyi idő
   UTC+2-ben még nem lépi át az UTC-éjfélt sem, tehát ez a cella önmagában
   NEM tudná megfogni a hibát; ez pontosan az oka, hogy a brief mindhárom
   cellát kötelezővé teszi, nem csak egyet).
4. A módosítás visszaállítva (`git diff` üres), `TZ=Europe/Berlin` mellett
   újra lefuttatva → 6/6 zöld.

Ez independently megerősíti, hogy a teszt-suite ténylegesen elkapja a brief
által legkockázatosabbnak jelölt hibaosztályt, és hogy a helyes implementáció
NEM az ambiens UTC boxnak köszönhetően látszik zöldnek.

## Megállapítások

### N1 — NOTE — a nap-címke besorolás (rest/unavailable/completed) duplikált a controller és a weekly screen között

- **Fájl:** `today_plan_controller.dart:85-114` és `weekly_plan_screen.dart:50-61` (`_dayLabel`)
- **Megfigyelés:** ugyanaz a három `reasonCodes`/`status` alapú elágazás két
  helyen él. Nem hiba — a brief §4 engedélyezett fájllistája NEM tartalmaz
  külön `weekly_plan_controller.dart`-ot, tehát az implementernek nem volt
  módja egy megosztott helyre kiemelni anélkül, hogy scope-ot sértsen (H3).
- **Javasolt irány:** ha egy jövőbeli kör `weekly_plan_controller.dart`-ot
  vagy egy megosztott domain-szintű `PracticeDayPresentationKind`-ot vezet be,
  ez a két ág egyesíthető. Nem blokkol, nem körön belüli follow-up.

### N2 — NOTE — a pihenőnap-ág megelőzi a `completed` ágat a controller switch-jében

- **Fájl:** `today_plan_controller.dart:85-114`
- **Megfigyelés:** ha egy `PracticeDay` egyszerre hordozná a `restDay`
  reasonCode-ot ÉS `status == completed`-et, a jelenlegi sorrend
  `TodayPlanMode.restDay`-t adna, nem `completedDay`-t. Ma ez
  ELÉRHETETLEN kombináció: ebben a körben (és a `main`-en élő
  `GenerationOrchestrator`-ban) semmi nem írja át egy pihenőnap `status`
  mezőjét `completed`-re — a pihenőnap mindig `planned` marad, amíg a Kör 23
  Practice Engine-je be nem köti a végrehajtást. Nem jelenlegi hiba, csak
  előre jelzett él-eset a jövőbeli végrehajtási körnek.
- **Javasolt irány:** amikor Kör 23 tényleges végrehajtást köt be és
  `PracticeDay.status`-t is módosíthat pihenőnapon, a sorrendet (vagy a
  `completed` elsőbbségét) explicit döntéssel kell rögzíteni.

## Gate-bizonyíték ellenőrzése

Mindkét futás egy TŐLEM klónozott, izolált `/tmp/review-e07-r22` munkapéldányban,
nem az implementer saját munkapéldányában.

| Gate | Állított eredmény (implementer, §10) | Ellenőrizve (reviewer, saját futás) |
|---|---|---|
| format | zöld | ✅ zöld (`dart format`, 1623 fájl, 0 változott) |
| analyze | zöld | ✅ zöld (`flutter analyze`, „No issues found") |
| `today_plan_screen_test.dart` | 5/5 zöld | ✅ 5/5 zöld |
| `today_plan_controller_test.dart` | 6/6 zöld | ✅ 6/6 zöld |
| architecture | zöld | ✅ zöld („12 allowlisted deviation(s)" — meglévő baseline, ez a kör nem érinti az allowlistet) |
| secrets | zöld | ✅ zöld (2852 fájl, 0 lelet) |
| l10n | zöld | ✅ zöld (1354 üzenet, en→hu paritás) |
| CI (teljes suite + property + APK) | nem futott (orchestrátor dolga, §7 szerint helyesen) | folyamatban — lásd a merge előtti CI-dispatch |

**Egy operatív megjegyzés a review-hoz, nem a kódhoz:** az implementer a
`cbee3d1c` commitot a saját munkapéldányában (`/home/ubuntu/ss-terra-e07-r22`)
hozta létre, de nem push-olta — a `.codex-round-status` `dirty_files=1`
mezője (jelzés-pillanatban mért, a push hiányától független tranziens érték)
erre önmagában nem hívta fel a figyelmet, de a review ELSŐ gate-futása a
`main`-ből klónozva (stale lokális branch-ref, az implementer push-a nélkül)
„Does not exist" hibával bukott a két új teszt-fájlon. Az orchestrátor
(én) a hiányzó push-t pótolta (`git push origin
terra/e07-r22-weekly-and-today-screen` az implementer saját, helyesen
konfigurált `origin`-jéből), a hub lokális branch-refjét szinkronizálta, és a
gate-et egy MÁSODIK, immár helyes klónon futtatta újra — a fenti eredmények
erről a másodikról valók. Nem a diff tartalmának hibája; a lánc egy hiányzó
lépését (implementer-push) pótoltam, mielőtt bármit elfogadtam volna.

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
Correctness review APPROVED. A dedikált biztonsági review (risk=high,
`docs/reviews/e07-r22-security.md`) külön fut, a merge-döntés arra is vár.
CI-dispatch (build-apk vagy full-gate, a `round-ci-plan.py` szerint) és a
Router CI exact-SHA zöldje a merge előfeltétele (§7 lásd a pipeline-promptban).
