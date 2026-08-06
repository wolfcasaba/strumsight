# E05-R08 — Review

Brief: docs/rounds/e05-r08-vision-setup-wizard.md
Diff: `git diff main...codex/e05-r08-vision-setup-wizard` (3828a23..b20ff23, 15 files)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-06
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 2 (WONTFIX ezen a körön) · NOTE: 1

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Permission-mátrix, mind az öt állapot külön teszttel | ✅ | `camera_permission_panel.dart` 5-ágú `switch`, egyedi kulcsokkal; `vision_setup_screen_test.dart:93-185` öt `testWidgets`, mindegyik pozitív ÉS negatív asserttel. **Mutáció-kill próbával igazolva** (lásd Próbatesztek) — a `permanentlyDenied` ág retry-gombra rontva a pontos tesztet buktatta pirosra. |
| 2 | Profil-mátrix (4 profil, egyedi frame-guide, leftHanded-ajánlás felülírható) | ✅ | `vision_setup_profile.dart` 4 érték (`practiceBalanced`, nem `balanced` — §0.0 R5 szerint); `vision_setup_controller_test.dart:73-98` recommendation+override; `vision_setup_screen_test.dart:188-196` mind a 4 profilhoz egyedi `vision-setup-guide-<name>` kulcs. |
| 3 | Skip minden lépésről, kamera nem indul (`start`==0) | ✅ (szigorúbb) | `vision_setup_screen_test.dart:198-231` — 0/1/2 lépés-előrehaladás után Skip, mindig eléri az audio-only célt. `vision_setup_controller_test.dart:175-192` — `captures` lista **üres** (a factory-t sem hívta), szigorúbb, mint a brief `start==0` előírása. |
| 4 | Camera-switch lease-fegyelem (§0.0 R4 szerint szűkítve: NEM fizikai lencseváltás) | ✅ | `vision_setup_controller.dart:117-123` `selectCamera()` — close-előbb-mint-open, `restart` flag csak akkor nyit újra, ha aktív volt. `vision_setup_controller_test.dart:143-173` — buggy nyitás-előbb esetben a coordinator `busy`-t adna, ami `captures.last.startCalls`-t 0-n tartaná és `captures.first.closeCalls`-t is 0-n — a teszt mindkettőt 1-re várja, tehát a rossz sorrendet pirosra fogná (levezetve, nem external próbával — a `CameraSessionCoordinator.acquire()` forráskódja garantálja az exkluzivitást). |
| 5 | Perzisztencia csak profil+kamera kulcs | ✅ | `vision_setup_controller_test.dart:101-120` — `store.values` **egzakt map-egyenlőség**, nem csak `contains`. `storage_keys.dart` diffje tisztán additív (2 kulcs + `all`-bővítés, meglévő kulcs érintetlen). |
| 6 | Lokalizációs paritás | ✅ | `tools/round-gate.sh` `l10n_parity_test.dart` zöld (saját futtatás, ld. lent); a CI `check_l10n_parity.dart` is zöld (942 üzenet, en→hu). |
| 7 | Flag-teszt (`visionEnabled=false` → route hiányzik) | ✅ | `app_router.dart:225-230` — a `GoRoute` maga `if (visionEnabled && visionSetupEnabled) ...[...]` mögött, tehát a route **nem regisztrálódik** (nem csak UI-szinten rejtett). `vision_setup_screen_test.dart:233-253` a router `configuration.routes`-át rekurzívan járja be mindkét flag-kombinációra. |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs**. `git diff --stat 3828a23..b20ff23` (a pre-flight §0.0 revízió utáni bázisról, amely már tartalmazza a `storage_keys.dart` felvételét) pontosan a brief §4 15 fájlját listázza; a Codex-wrapper saját `scope_audit=ok` jelzését (15 changed) függetlenül megerősítettem ugyanerre a bázisra kézzel futtatott `diff --stat main...codex/e05-r08-vision-setup-wizard`-vel is (azonos 15 fájl, azonos sorszámok).

## Megállapítások

### F1 — MINOR — A két terminál wizard-lépésnek (`ready`, `audioOnly`) nincs előre-navigációja

- **Fájl:** `lib/features/vision/presentation/screens/vision_setup_screen.dart:252-292`
- **Probléma:** `_ReadyStep` nem tartalmaz semmilyen interaktív elemet; `_AudioOnlyStep` „Continue to practice" gombja `onPressed: () {}` — üres no-op.
- **Hatás:** ha a felhasználó eléri ezt a két állapotot, nincs módja tovább navigálni (a `ready`-ből még mindig elérhető a felső Skip, tehát NEM csapda — §5.1 szabály nem sérül —, de az `audioOnly` gomb látszólag működik, mégsem tesz semmit).
- **Miért nem BLOCKER/MAJOR ezen a körön:** `visionSetupEnabled` ma minden környezetben OFF (E05-R03 óta), tehát éles felhasználót nem érint; a brief §3 explicit kizárja a shell-tab/onboarding-bekötést, ez a képernyő ma egy önálló, hívatlan route. Amikor egy jövőbeli kör ezt a wizardot ténylegesen bekapcsolja/meghívja, a hívó felelőssége (vagy egy kis kiegészítő diff) a navigáció bekötése.
- **Kötelező javítás (jövőbeli körre halasztva):** `onPressed` navigáljon vissza a hívóhoz (`Navigator.of(context).maybePop()` vagy a jövőbeli belépési pont route-jára).
- **Ellenőrzés:** egy jövőbeli widget-teszt, ami a gombnyomás utáni navigációt méri.
- **Státusz:** WONTFIX ezen a körön (dokumentált, follow-up).

### F2 — MINOR — A privacy-panel önmagában csak a négyből két SDD §12.3 üzenetet mondja ki explicit szövegként

- **Fájl:** `lib/features/vision/presentation/screens/vision_setup_screen.dart:86-112` (`_PrivacyNotice`)
- **Probléma:** SDD §12.3 négy állítást vár a setup előtti panelen („eszközön", „nincs mentés", „bármikor leállítható", „kamera nélkül is használható"). A `_PrivacyNotice` szövege (`visionSetupPrivacyBody`) csak az első kettőt mondja ki explicit egy helyen.
- **Hatás:** minimális — a másik két állítás ténylegesen IGAZ és kommunikálva VAN a flow más pontjain (az AppBar Skip gombja minden lépésen látható = „bármikor leállítható" ténylegesen demonstrálva, nem csak kimondva; `visionSetupAudioOnlyBody` = „kamera nélkül is használható" kimondva) — nem hiányzó garancia, csak nem egy helyen felsorolt checklist.
- **Kötelező javítás:** nem kötelező; ha egy jövőbeli kör bővíti a privacy-panelt, egészítse ki mind a négy pontra.
- **Ellenőrzés:** n/a.
- **Státusz:** WONTFIX (NOTE-hoz közeli MINOR, nem termékhatár-sértés).

### F3 — NOTE — `vision_setup_profile.dart` doc-commentje explicit dokumentálja a §0.0 R5 szűkítést

- **Fájl:** `lib/features/vision/domain/vision_setup_profile.dart:1-5`, `:28-29`
- **Megfigyelés:** az implementer nemcsak követte a pre-flight revíziót, hanem a doc-commentbe is beírta az indoklást (a `songPerformance`/`experimentalFretboard` deferral, és hogy a `VisionCameraPreference` „not a request to the platform adapter to select a particular physical lens"). Ez pontosan az `AGENTS.md` §10 „publikus contract dokumentálása" elvárását szolgálja, és megvédi a jövőbeli olvasót a §0.0 R4/R5 újra-felfedezésétől.
- **Hatás:** pozitív precedens, nem igényel akciót.

## Próbatesztek (eldobható, dokumentálva, visszaállítva)

**Mutáció-kill próba (F ellenőrzés az 1. acceptance-cellára):** a `/tmp/review-e05-r08` izolált klónban a `camera_permission_panel.dart` `permanentlyDenied` ágát ideiglenesen a `denied` ág másolatára cseréltem (retry-gombot adva Settings CTA helyett — pontosan a brief §6.1 mátrixának első sora). `flutter test test/features/vision/presentation/vision_setup_screen_test.dart` → **1 teszt pirosra váltott** (`permanently denied sends the user to Settings`), a többi 6 zöld maradt (tiszta, izolált hiba). `git checkout --` a fájlra → újrafuttatva **mind a 8 teszt zöld**. A teszt ténylegesen méri, amit állít.

## Gate-bizonyíték ellenőrzése

Saját, független futtatás izolált klónban (`/tmp/review-e05-r08`, `git clone --branch codex/e05-r08-vision-setup-wizard`), NEM a közös working tree-ben:

| Gate | Állított eredmény (implementer) | Ellenőrizve (reviewer, saját futtatás) |
|---|---|---|
| format | zöld | ✅ zöld (1061 fájl, 0 changed) |
| analyze | zöld, 0 issue | ✅ zöld (0 issue) |
| test test/features/vision | 13 passed | ✅ 13 passed |
| test test/core/l10n_parity_test.dart | 3 passed | ✅ 3 passed |
| architecture | zöld | ✅ zöld (12 allowlisted deviation — meglévő, nem ehhez a körhöz tartozó) |
| secrets | (nem jelentve, a gate saját lépése) | ✅ zöld (1836 fájl, 0 lelet) |
| l10n (CI-lánc lépés) | (nem jelentve) | ✅ zöld (942 üzenet, en→hu) |
| CI (teljes suite + property + APK/full-gate) | — | ⏳ orchestrátor dispatch-eli a review lezárása után |

## Biztonsági review

A brief `risk = "high"` — dedikált `security-reviewer` review kötelező (AGENTS.md §15.1).
Külön agent futtatva, kimenet: `docs/reviews/e05-r08-vision-setup-wizard-security.md`
(folyamatban / lásd külön dokumentum a review lezárásakor).

## Merge-döntés

0 nyitott BLOCKER/MAJOR — a két MINOR dokumentált WONTFIX-ként (indoklással, follow-up
jegyezve). Az ADR 0052 szerint a merge feltétele ezen felül: a CI (full-gate/build-apk +
router-ci, ahogy a `round-ci-plan.py` előírja) zöld a merge-SHA-n, ÉS a dedikált
security-review nem talál CRITICAL/BLOCKER-t. Mindkettő folyamatban — merge csak azok
után.
