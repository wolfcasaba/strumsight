# E08-R30 — Review

Brief: `docs/rounds/e08-r30-epic-08-migration-regression-and-closure.md` (with
the pre-flight `## 0.0` revision)
Diff: `git diff c93311c8...f80f8165` (pre-flight commit → implementer HEAD)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-22
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 2

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Öt/hat új képernyő útvonalon elérhető, a régi `/streak` + `/progress` mélylink VÁLTOZATLANUL működik | ✅ | `test/app/routing/app_router_test.dart` — a hat új `GoRoute`-ot navigáló `testWidgets` cellák a megfelelő V2 widget-típust találják (`GamificationHubScreen`, `AchievementsScreen`, `AchievementDetailScreen` — path-param átadás is ellenőrizve `/gamification/achievement/practice_starter`-en —, `QuestsScreen`, `StreakDetailScreen`, `RewardInboxScreen`), ÉS két külön cella (403, 416. sor) navigál a legacy `/streak`/`/progress`-re és a V1 `StreakScreen`/`ProgressScreen`-t találja. Saját kézzel újrafuttatva izolált klónban: ZÖLD. |
| A2 | Legacy migrációk VALÓS fixture-ökkel ellenőrizve, nincs adatvesztés | ✅ | `test/features/gamification/data/legacy_streak_and_practice_fixture_test.dart` (7 teszt, ÚJ) — valós `LegacyStorageKeys`/`StorageKeys` kulcsnevek alatt (nem szimbolikus, a tényleges string-konstansok), mindkét ág (pre-v22 nyers `practice_streak_v1`/`practice_log_v1` ÉS post-v22 namespaced envelope), plusz egy kevert-precedencia próba (namespaced nyer nyers fölött) és egy üres-fixture él. A meglévő `legacy_practice_migration_test.dart` változatlan és zöld marad. Saját kézhez: ZÖLD. |
| A3 | Offline/időzóna/óra-visszaállítás/több eszköz — nincs dupla jutalom, nincs törött széria | ✅ (idézett bizonyíték) | A completion report §4 táblája konkrét, MEGLÉVŐ (korábbi körökből örökölt) tesztfájlokra mutat soronként (`ledger_merge_policy_test.dart`, `streak_policy_test.dart`, `streak_service_test.dart`), ezek mind lefutottak a §7 gate-ben. Nem ÚJ állítás, hanem a meglévő lefedettség idézése — ez pontosan a §0.0 revízióm által engedett bizonyítási forma. |
| A4 | README gamifikáció/adatvédelem/offline szakaszai frissültek | ✅ | `README.md` — új „Gamification” szakasz (route lista, settings, storage, offline, accessibility), frissített feature-tábla sor és státusz-banner. |
| A5 | Kettős írás + legacy adapter kivezetési feltételei SZÁMSZERŰEK | ✅ | Completion report §3.2 — négy számszerű feltétel (30 fixture / 7 CI-run wire-shape parity, 3 property-seed zero-loss replay, mindkét adapter production hívási lánca, 14 napos zéró-mismatch soak). Nem „amikor stabilnak tűnik”. |
| A6 | Completion report ZÖLD CI futás-linket hivatkozik, nem lokálisat | ⏳ | A jelentés jelenleg `_to be inserted by the orchestrator after dispatch_` placeholdert tartalmaz — ez KORREKT állapot review időpontban (a CI-dispatch az orchestrátor lépése, §3.0 alább). A §6.1 valódi-sértés próba (szándékos piros link → elutasítás → helyes link) dokumentálva a HANDOFF-ban és a completion reportban. |
| A7 | HANDOFF.md tükrözi az Epic 8 lezárását | ✅ | Új „✅ E08-R30 KÉSZ” blokk a fejlécben; a „Pontos következő E08 kör” állítás (E09-R01) ellenőrizve a `pipeline-queue.tsv`-n — ez ténylegesen az első `pending` sor E08-R30 után (413. sor), a Chapter 13 E13-R05 (491. sor) UTÁN áll a fájlban. |
| A8 | `lib/features/**` érintetlen | ✅ | `git diff --stat c93311c8..f80f8165` — 7 fájl, egyik sem `lib/features/**` alatt. |

## Scope-audit

`tools/scope-audit.py --repo /tmp/review-e08-r30 --brief docs/rounds/e08-r30-epic-08-migration-regression-and-closure.md --base c93311c8`
→ **`Legacy scope audit OK (c93311c8..f80f8165, 7 changed path(s), 0
generated/ignored)`**. A 7 fájl pontosan a §0.0-revideált `allowed_paths`
listája (2 ÚJ elemmel: `lib/app/routing/app_router.dart`,
`test/features/gamification/data/legacy_streak_and_practice_fixture_test.dart`).
Engedélyezett fájlokon kívüli változás: **nincs**.

## Megállapítások

### N1 — NOTE — a három router-szintű Riverpod-provider egyszeri olvasás, nem élő stream

- **Fájl:** `lib/app/routing/app_router.dart:122` (`_gamificationProfileProvider`), `:137` (`_streakStateProvider`), `:153` (`_rewardInboxProvider`)
- **Megfigyelés:** mindhárom `Provider<T>` (nem `StreamProvider`), tehát a Hub/Streak-detail/Inbox képernyő az app-session életciklusa alatt csak EGYSZER olvassa be a repository-t; egy frissen befejezett gyakorlás vagy jutalom a Hub-on csak app-újraindítás után jelenne meg. A brief A1 acceptance-je ("útvonalon elérhető") ezt nem írja elő, és a `watchProfileSnapshots()` élő stream bekötése a §0.0 által is csak "használható" volt, nem kötelező — de érdemes egy jövőbeli, a screen saját `presentation/providers/`-ébe költöztető körnek élővé tenni.
- **Hatás:** nem blokkoló ebben a körben — a completion report és a HANDOFF ezt már explicit nyitott tételként kezeli (a provider-lift "future round" megjegyzés).
- **Kötelező javítás:** nincs ebben a körben.
- **Státusz:** OPEN (jövőbeli kör dolga, dokumentálva)

### N2 — NOTE — a brief `## 10. Implementation handoff` szakasza üres maradt a branchen

- **Fájl:** `docs/rounds/e08-r30-epic-08-migration-regression-and-closure.md:307`
- **Megfigyelés:** az implementer a handoff-tartalmat a `docs/sdd/epic-08-completion-report.md`-be írta (ami a completion report saját fejlécében explicit jelzi: "The §10 Implementation handoff ... is the per-file change log ... this document captures the measured state"), de a brief saját §10 sablon-sora technikailag kitöltetlen maradt.
- **Hatás:** nem blokkoló — a completion report tartalmilag lefedi ugyanazt, egy jövőbeli pre-flight (ami "mind a 29 korábbi kör §10 handoffját" olvassa újra) esetében érdemes tudni, hogy E08-R30-nál ez a completion reportban van.
- **Kötelező javítás:** nincs ebben a körben.
- **Státusz:** OPEN (dokumentációs pontosítás, nem blokkol)

## Architektúra + termékhatárok

- **`public.dart` contract / cross-feature import:** `app_router.dart` mélyen importál a `lib/features/gamification/**` alá (nem a `public.dart`-on át) — ELLENŐRIZVE: ez a MEGLÉVŐ, a kör előtt is fennálló mintázat minden más feature esetén ugyanebben a fájlban (pl. `features/streak/screens/streak_screen.dart:51`, `features/library/screens/library_screen.dart:37` — egyik sem `public.dart`-on át). A `tool/check_architecture.dart` cross-feature szabálya ("A cross-feature import is legal only when it targets a `public.dart` barrel") a `lib/app/**` kompozíciós gyökeret nem sorolja a "feature" kategóriába — az architecture gate saját kézzel újrafuttatva ZÖLD. Nem regresszió.
- **Erőforrás-lifecycle:** `_gamificationRepositoryProvider` `ref.onDispose(repo.dispose)`-t regisztrál; a `routerProvider` maga is `ref.onDispose` a router+refreshNotifier felszabadítására (ez már a kör előtt is megvolt, változatlan).
- **Nincs új domain-logika a tiltott zónában:** minden callback, ahol nincs kész publikus repository/service-metódus, dokumentált no-op (`// TODO(E08-R30):`), NEM kitalált üzleti szabály. Ellenőrizve: a `RewardInboxItem` (domain, `event: RewardEvent` mezővel) és a `GamificationInboxItem` (storage, csak `id`/`createdAt`/`viewedAt`) között VALÓBAN nincs triviális leképezés — a no-op indoklása mérve helytálló, nem kényelmi kibúvó.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | ZÖLD | ✅ saját izolált `/tmp/review-e08-r30` klón, exit 0 |
| analyze | ZÖLD | ✅ |
| test `test/app/routing/app_router_test.dart` | ZÖLD (22 teszt) | ✅ |
| test `test/features/gamification` | ZÖLD (7 új + meglévő) | ✅ |
| test `test/features/streak` | ZÖLD | ✅ |
| test `test/features/progress` | ZÖLD | ✅ |
| architecture | ZÖLD | ✅ |
| secrets | ZÖLD | ✅ |
| l10n | ZÖLD | ✅ |
| CI (teljes suite + property + APK) | — | ⏳ orchestrátor dispatch-eli a review UTÁN, §3.0 |

Mind a kilenc lokális gate-lépés saját kézzel, izolált klónban, `> log 2>&1`
csonkítás nélkül, előtérben újrafuttatva — a `GATE_EXIT=0` és a log
soronkénti "ZÖLD" jelzése egyaránt igazolja.

## Merge-döntés

ADR 0052 szerint: minden LOKÁLIS gate zöld ÉS scope-audit OK ÉS nincs nyitott
BLOCKER/MAJOR → **a review oldalról a merge útja szabad**, a fennmaradó
előfeltétel a CI-dispatch (Full/full-gate + Router CI a kör-branchre, exact-SHA
összevetés) — ez az orchesztrátor következő lépése ebben a sessionben.
