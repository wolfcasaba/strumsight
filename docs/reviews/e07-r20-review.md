# E07-R20 — Review

Brief: docs/rounds/e07-r20-plan-setup-wizard.md
Diff: `git diff e5374943..d1a7a898` (`main...terra/e07-r20-plan-setup-wizard`)
Reviewer: Claude (Sonnet 5) · Dátum: 2026-08-18
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 2 · MINOR: 1 · NOTE: 2

A gate (format/analyze/mindkét célzott teszt/architecture/secrets/l10n)
SAJÁT, izolált `/tmp/review-e07-r20` klónban újrafuttatva **zöld** — ez a
formai fegyelmet igazolja, de a review protokoll alapelve szerint ("a zöld
gate NEM bizonyíték") ez önmagában nem elég. Két, saját, eldobható
próbateszttel MÉRT (nem csak olvasott) hibát találtam, mindkettő az A2/A4
kereszteződésében és a wizard alapcéljában (§1: "a generálási kérés...
felülete"): a heti elérhetőség lépés egyetlen kiválasztható napja egy
kőkemény, órától független naptári dátum, ami MA MÁR egy nappal a múltban
van; és a `_resumeStep` nem tudja megkülönböztetni "a lépést a tanuló
'nem tudom'-mal válaszolta" és "a lépést még nem is látta" — mindkettő a
domain "unknown" ábrázolása (üres/hiányzó), és a wizard emiatt egy korábbi
lépésre ugrik vissza újraindítás után, valahányszor egy lépést unknown-nal
zártak le.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Alapfolyamat végigvihető, lépésenkénti draft-mentés | ✅ | `plan_setup_screen_test.dart`: "starts without a draft and persists each completed step" — SAJÁT klónban újrafuttatva zöld |
| A2 | App-újraindítás után a wizard folytatható **ott, ahol abbamaradt** | ⚠️ **RÉSZLEGES — ld. F2** | a meglévő tesztek (goal-only, illetve teljesen kész draft) zöldek, de a saját probateszt megmutatja, hogy egy `unknown`-nal lezárt köztes lépés után a resume egy korábbi lépésre esik vissza |
| A3 | Visszalépés nem veszít adatot | ✅ | `plan_setup_screen_test.dart`: "back navigation retains the previously entered answer" |
| A4 | "Nem tudom" sosem fordul default értékre | ✅ | teszt + a brief §10-be írt kötelező valódi-sértés próba (rhythm-default → piros → visszaállítva zöld), saját olvasással is megerősítve (`selectGoal`, `setAvailability`, `_setCategory` mind hiányzó/üres listát ír unknale-nál) |
| A5 | Hard konfliktus azonnal látszik | ✅ | `plan_setup_screen_test.dart`: "shows a hard conflict on the step where it is created (A5)" — a `custom` goal type valódi `RequestValidator.customGoalNotExecutable` hibát vált ki (nem kitalált/mock jelzés), a Next gomb `hasHardConflict`-nál letiltva mind UI-, mind controller-szinten (`next()` saját belső guardja is van) |
| A6 | Nagy betűméretnél nincs túlcsordulás | ✅ | `availability_editor_test.dart` textScaler×2, `tester.takeException()` null — SAJÁT klónban újrafuttatva zöld |
| A7 | Semantics címkék jelen vannak | ✅ | `availability_editor_test.dart`: `find.bySemanticsLabel('Monday availability')`; a többi lépés Material-widgetjei (RadioListTile/SwitchListTile/TextField) beépített semantics-szel |
| A8 | Minden szöveg ARB-ből (hu+en) | ✅ | SAJÁT klónban `check_l10n_parity.dart` zöld ("L10n parity OK (en → hu, 1298 message(s))"); diff-ben mind a 19 új kulcs mindkét fájlban jelen |
| A9 | Kényelmetlenségi szöveg nem kerül naplóba | ⚠️ **PRÓBA HIÁNYZIK — ld. F3** | a tulajdonság ma igaz (`grep -rniE "print\(\|debugPrint\|logger\|log\.\|\.log\(\|analytics" lib/features/practice_generator/presentation/` → csak egy doc-comment-találat, hívás nincs), de a brief saját "gyűjtő logger" bizonyíték-előírása nem teljesült — a leszállított teszt csak a perzisztenciát méri, nem a naplózás-tilalmat |

## Scope-audit

`tools/scope-audit.py --repo /tmp/review-e07-r20 --brief docs/rounds/e07-r20-plan-setup-wizard.md --base 4c4de25beb3d059faec793eafbb068d86114b6f4`
→ **`Legacy scope audit OK (4c4de25beb3d..d1a7a898f1c7, 10 changed path(s), 0 generated/ignored)`**.
Mind a 10 megváltozott fájl az `allowed_paths`-on. Engedélyezett fájlokon
kívüli változás: **nincs**.

## Megállapítások

### F1 — MAJOR — Az elérhetőség-szerkesztő egyetlen napja egy kőkemény, órától független naptári dátum

- **Fájl:** `lib/features/practice_generator/presentation/widgets/availability_editor.dart:19`
- **Probléma:** `static final LocalDate _monday = LocalDate(2026, 8, 17);` — nincs
  `DateTime.now()`, nincs injektált óra, nincs semmilyen viszonyítás egy
  aktuális dátumhoz. Ez az EGYETLEN nap, amit a teljes wizard elérhetőségként
  felkínál (a `PracticeGoalPicker`/equipment/preference lépések is csak 1-1
  fix választ kínálnak, de azok ÉRTÉKE időfüggetlenül helyes marad — a
  naptári dátum más: helyessége a mérés PILLANATÁHOZ kötött).
- **Mérve, nem csak olvasva:** saját próbateszt (`python3 -c`):
  `2026-08-17` **Monday**, `2026-08-18` (a doksi-fejlécben mért "ma") **Tuesday**
  — a kód írásának pillanatában helyes volt, de MA MÁR EGY NAPPAL A MÚLTBAN
  van, és minden további napon tovább öregszik. A widget forráskódjában
  nincs `DateTime.now()` és nincs `clock` hivatkozás sem (grep-pel
  megerősítve).
- **Hatás:** a `WeeklyAvailability.days` — ami a draftban és (egy jövőbeli
  körben) a generálási kérésben is perzisztálódik — egy már elmúlt naptári
  napra mutat, sosem a tanuló tényleges következő hetére. A felhasználó a
  UI-n csak "Hétfő" feliratot lát (a `planSetupMonday` ARB-kulcs napnevet ír,
  nem dátumot), tehát a hiba NEM látszik a képernyőn — csendes, adatszintű
  hiba, ami csak akkor derül ki, amikor egy későbbi kör a tárolt dátumra
  próbál ütemezni.
- **Kötelező javítás:** a widget kapjon egy injektált referenciadátumot
  (pl. `DateTime Function()` vagy egy már felbontott `LocalDate` paraméter a
  hívótól — a `PlanSetupController` MÁR rendelkezik `clock`-kal, ez a minta
  egyenesen adja magát), és számítsa ki belőle a tényleges következő
  (vagy aktuális) hetet — ne egy fordítás-idejű konstansot.
- **Ellenőrzés:** egy teszt, ami KÉT különböző injektált "ma" mellett
  futtatja a widgetet, és megméri, hogy a felkínált nap dátuma a hívó által
  megadott referenciához igazodik (nem egy fix literál).
- **Státusz:** OPEN

### F2 — MAJOR — A `_resumeStep` nem tudja megkülönböztetni az "unknown"-nal lezárt lépést a "még meg sem nyitott" lépéstől

- **Fájl:** `lib/features/practice_generator/presentation/controller/plan_setup_controller.dart:231-250`
- **Probléma:** `_resumeStep` kizárólag ADAT JELENLÉTÉBŐL következtet a
  legutóbb befejezett lépésre (`availability.days.isNotEmpty`,
  `constraints.any(category==equipment/preference/comfort)`). Mivel az A4
  szerint MINDEN lépés "unknown" válasza pontosan ugyanazt az ÜRES/HIÁNYZÓ
  domain-állapotot hozza létre, mint amikor a tanuló még el sem érte azt a
  lépést, a metódus nem tud különbséget tenni — és ILYENKOR EGY KORÁBBI
  lépésre esik vissza, nem az igazi következő, még megválaszolatlan lépésre.
  Ez NEM csak az elérhetőség lépésre igaz — ugyanez a minta az equipment,
  preference és comfort lépésre is fennáll (mindegyik "unknown" válasza
  hiányzó constraint-bejegyzés).
- **Mérve, nem csak olvasva:** saját, eldobható próbateszt (izolált
  `/tmp/review-e07-r20` klónban futtatva, `flutter test`):
  1. cél kiválasztva → Next (step 1-re lép);
  2. elérhetőség lépésen **explicit "nem tudom"** (`setAvailability(const [])`,
     pontosan az UI "nem tudom" gombjának hívása) → Next (ugyanabban a
     sessionben helyesen step 2-re lép — `expect(first.state.currentStep, 2)` zöld);
  3. controller eldobva, ÚJ controller UGYANAZZAL a store-ral (app-újraindítás
     szimulációja), `restore()`;
  4. **`expect(restored.state.currentStep, 2)` → PIROS: `Expected: <2> Actual: <1>`.**
     A wizard visszaesik az elérhetőség lépésre, amit a tanuló már
     kifejezetten megválaszolt.
- **Hatás:** A2 sérül minden olyan valós útvonalon, ahol a tanuló egy lépést
  "nem tudom"-mal zár le, majd megszakítja a wizardot — vagyis pontosan
  azokon az útvonalakon, amiket az A4/§5.1 KIFEJEZETTEN elsőosztályúként
  próbál ösztönözni. Adatvesztés nincs (a végső mentett request tartalma
  helyes marad, ha a tanuló újra végigmegy a lépéseken), de a
  §6.1 "a határon" cella szó szerinti elvárása ("a wizard OTT folytatódik")
  nem teljesül erre a bemenetosztályra.
- **Kötelező javítás:** ne adat-jelenlétből derítsd a resume-pontot — perzisztáld
  magát a `currentStep`-et (vagy egy explicit "ez a lépés lezárva" jelzőt
  lépésenként) a draftban/kulcs-érték tárban, és azt olvasd vissza, ne
  következtess rá a domain-tartalomból.
- **Ellenőrzés:** a fenti próbateszt (vagy ezzel ekvivalens) mint állandó
  regressziós teszt — unknown-nal lezárt lépés → restart → helyes
  folytatási pont, legalább az elérhetőség és az equipment lépésre.
- **Státusz:** OPEN

### F3 — MINOR — Az A9 bizonyítéka nem a brief által előírt alakú; a tulajdonság ma igaz, de nincs regressziós őre

- **Fájl:** `test/features/practice_generator/presentation/plan_setup_screen_test.dart:151-177`
- **Probléma:** a brief §6 acceptance-táblája A9 bizonyítékaként kifejezetten
  "gyűjtő logger"-t ír elő (egy fake/spy logger, ami méri, hogy a szöveg
  SOSEM jut el hozzá — ez a repo bevett mintája, ld. E07-R10
  `PracticeGoalSummary.userNote` kizárásának poison-pill tesztje). A
  leszállított "comfort free text is retained only in the local draft (A9)"
  teszt kizárólag azt méri, hogy a szöveg megjelenik-e
  `controller.state.request!.constraints...value`-ban — ez a PERZISZTENCIÁT
  bizonyítja, nem a NAPLÓZÁS-TILALMAT.
- **Mérve:** `grep -rniE "print\(|debugPrint|logger|log\.|\.log\(|analytics" lib/features/practice_generator/presentation/`
  → egyetlen találat, egy doc-comment ("this controller deliberately has no
  logging or analytics dependency") — tényleges hívás nincs. A tulajdonság
  MA igaz, de nincs teszt, ami egy jövőbeli regressziót (pl. egy központi
  hiba-/analytics-logger bevezetése a controllerbe) elkapna.
- **Hatás:** alacsony ma, de ez pontosan az a fajta doc-comment-állítás, amit
  a review-protokoll saját szabálya szerint ("doc-comment állításokat
  tesztben bizonyíts") tesztnek kellene őriznie — érzékeny (egészség-jellegű)
  szövegről lévén szó, a védelem hiánya aránytalanul nagy jövőbeli
  kockázatot rejt egy önmagában kis diffhez képest.
- **Kötelező javítás:** egy teszt, ami egy befecskendezett/spy logger-t (vagy
  ha a projektben nincs ilyen absztrakció ezen a rétegen, akkor egy
  `Zone`-alapú `print`-elfogás vagy hasonló mérés) ad a controller/screen
  köré, és megméri, hogy a comfort szabad szöveg SOSEM jelenik meg benne,
  még hibás mentés (`saveDraft` failure) esetén sem.
- **Státusz:** OPEN

### N1 — NOTE — A "custom" cél mindig megoldhatatlan hard-konfliktust hoz létre, kiút nélkül ezen a körön belül

- **Fájl:** `lib/features/practice_generator/presentation/widgets/practice_goal_picker.dart:30-34`
- **Megfigyelés:** a `PracticeGoalType.custom` az egyik mindössze 2
  felkínált célopcióból (`rhythm`, `custom`), és a kör scope-ja miatt
  SOSEM válik végrehajthatóvá (`normalizedTargetId` beállítása egy
  jövőbeli kör domain/application-feladata) — a tanuló, ha ezt választja,
  a Next gomb letiltva marad, amíg VISSZA nem vált egy másik opcióra. Nem
  hibás (a §5.3 "azonnal látszik" elvárásnak pont ez felel meg, és a
  felhasználó bármikor válthat), de termékszempontból furcsa egy olyan
  választható opciót kínálni, ami garantáltan zsákutca ebben a körben.
  Érdemes megfontolni egy jövőbeli körben: vagy rejtsd el "custom"-ot,
  amíg a normalizáció nem elérhető, vagy adj mellé egy szövegbeviteli
  mezőt.

### N2 — NOTE — Használaton kívüli `textScaleFactor` paraméter

- **Fájl:** `test/features/practice_generator/presentation/plan_setup_screen_test.dart:19-32`
- **Megfigyelés:** a `pumpWizard` helper elfogad egy `textScaleFactor`
  paramétert (alapérték 1), de egyetlen tesztesetből sem hívják más
  értékkel — az A6 bizonyítéka helyesen az `availability_editor_test.dart`-ban
  van (a brief §6 táblája is ezt írja elő), tehát ez nem hiányzó
  lefedettség, csak egy holt paraméter. Ártalmatlan, `flutter analyze`
  nem jelzi.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer) | Ellenőrizve (reviewer, SAJÁT izolált klón) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld | ✅ zöld |
| test plan_setup_screen_test.dart | zöld, 7 teszt | ✅ zöld |
| test availability_editor_test.dart | zöld, 2 teszt | ✅ zöld |
| architecture | zöld | ✅ zöld (12 allowlisted deviation — pre-existing, e kör nem bővítette) |
| secrets | (nem jelentve) | ✅ zöld (2833 fájl, 0 lelet) |
| l10n parity | (nem jelentve) | ✅ zöld (1298 üzenet, en→hu) |
| CI (teljes suite + property + APK) | nem futott (orchestrátor feladata) | még nem dispatch-elve — a fix kör után |

`scope_audit=ok` a `.codex-round-status`-ban is (base `4c4de25b`, 10 changed
path), a hiteles `tools/scope-audit.py` eszközzel függetlenül megerősítve.

## Merge-döntés

**Merge TILOS** — 2 nyitott MAJOR (F1, F2). A gate teljes egészében zöld, de
az ADR 0052 feltétele ("minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR")
csak az első felére teljesül. Javító kör szükséges (ugyanaz a motor, `terra`,
user-döntés 2026-07-31 szerint ez a lánc normál útja) F1+F2+F3 leletlistával;
a javítás után a gate-et és a scope-auditot újra, saját kézzel, friss
izolált klónban futtatom, és a jelentést frissítem.

Külön biztonsági review fut párhuzamosan (a brief `risk = "high"`), annak
eredménye `docs/reviews/e07-r20-security.md`-ben, a merge-döntés arra is vár.
