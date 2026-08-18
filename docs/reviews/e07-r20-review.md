# E07-R20 — Review

Brief: docs/rounds/e07-r20-plan-setup-wizard.md
Diff: `git diff e5374943..201d7601` (`main...terra/e07-r20-plan-setup-wizard`)
Reviewer: Claude (Sonnet 5) · Dátum: 2026-08-18
Verdikt: **APPROVED** (javító kör után, `201d7601`)

## Frissítés a javító kör után (2026-08-18, `201d7601`)

Mind a négy lelet (F1, F2, F3, F4) zárva, javító commitok:
`63768316` (F1), `da6c02ba` (F2+F3), `da6c02ba` (F4), `5f664d10`
(analyzer-javítás a saját tesztükben). Leletenkénti zárás-ellenőrzés
lentebb, a saját eredeti — bug idejére írt — próbateszteimet is
ÚJRAFUTTATVA a javított kódon (friss `/tmp/review-e07-r20-fix` klón):

- F1 eredeti detektor-probe-ja (`source.contains('LocalDate(2026, 8, 17)')`)
  most PIROS — a kőkemény literál eltűnt, a widget saját, injektált
  `referenceDate` paraméterből számít hetet.
- F2 eredeti reprodukáló probe-ja (`restored.state.currentStep == 2` egy
  availability-unknown lépés után) most ZÖLD.
- Mindkettő a javító kör SAJÁT, a diffben látott regressziós tesztjeivel is
  megerősítve (ld. lent).

Gate + scope-audit a javított HEAD-en, SAJÁT, friss izolált klónban
(`/tmp/review-e07-r20-fix`), újra függetlenül lefuttatva — mindkettő zöld
(részletek a "Gate-bizonyíték" és "Scope-audit" szakaszban, frissítve).

A dedikált biztonsági review (`docs/reviews/e07-r20-security.md`) is
frissítve APPROVED-ra.

---

## Eredeti review (2026-08-18, `d1a7a898`, CHANGES REQUIRED) — változatlanul megőrizve

BLOCKER: 0 · MAJOR: 3 · MINOR: 1 · NOTE: 2

**Frissítve a dedikált biztonsági review után** (`docs/reviews/e07-r20-security.md`,
kötelező a brief `risk = "high"` miatt): a security-reviewer FÜGGETLENÜL
ugyanarra az A9-gyűjtő-logger hiányra bukkant, és MAJOR-nak minősítette
(lentebb F3 ennek megfelelően MINOR→MAJOR frissítve) — indoka: a §6.1
A9-hez tartozó piros-kiváltó ("A szabad szöveg naplózva → A9") ma
**működésképtelen**, mert nincs teszt, ami elkapná. Emellett egy ÚJ leletet
is talált (F4, MINOR): a controller doc-commentje "encrypted/local draft
path"-nak nevezi a draft-tárolást, holott az a MEGLÉVŐ (e körön kívüli)
`GenerationDraftRepository` → `KeyValueStore` → `SharedPreferencesStore`
láncon **plaintext**. Sem aktív adatszivárgást, sem termékhatár-sértést
(AGENTS.md §5) nem talált — a security-review teljes checklistje és a
"tisztának mért" lista a `docs/reviews/e07-r20-security.md` fájlban.

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
| A9 | Kényelmetlenségi szöveg nem kerül naplóba | ⚠️ **PRÓBA HIÁNYZIK — ld. F3 (MAJOR, a dedikált security review is önállóan ugyanide jutott)** | a tulajdonság ma igaz (`grep -rniE "print\(\|debugPrint\|logger\|log\.\|\.log\(\|analytics" lib/features/practice_generator/presentation/` → csak egy doc-comment-találat, hívás nincs), de a brief saját "gyűjtő logger" bizonyíték-előírása nem teljesült — a leszállított teszt csak a perzisztenciát méri, nem a naplózás-tilalmat; a §6.1 A9 piros-kiváltója ma működésképtelen |

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
- **Státusz:** **FIXED** (`63768316`) — a widget most `required this.referenceDate`
  paramétert kap (`plan_setup_screen.dart` a `widget.controller.clock()`-ot
  adja át), és `_mondayOf(referenceDate)` számítja ki a hetet. Javító kör
  saját regressziós tesztje: `availability_editor_test.dart` "uses the
  injected reference date for the current week" — KÉT különböző
  referenciadátummal (2026-08-18→2026-08-17, 2026-09-01→2026-08-31) méri a
  `DailyAvailability.date` eredményt. Saját, eredeti detektor-probe-om
  (`source.contains('LocalDate(2026, 8, 17)')`) a javított kódon
  PIROSRA vált — a literál eltűnt.

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
- **Státusz:** **FIXED** (`da6c02ba`) — a `currentStep` most külön,
  dedikált kulcs alatt (`{draftStorageKey}.step`) perzisztálódik
  `next()`-ben, és `restore()` ezt olvassa vissza (`_savedCurrentStep`),
  nem a domain-tartalom jelenlétéből következtet. Javító kör saját
  regressziós tesztjei: `plan_setup_screen_test.dart` "restores the next
  step after an unknown availability answer" (2. lépésre vár, nem 1-re) ÉS
  "restores the next step after an unknown equipment answer" (3. lépésre
  vár) — mindkettő a diffben olvasva megerősítve. Saját, eredeti
  reprodukáló próbatesztem (goal→next, availability=unknown→next, restart,
  `restored.state.currentStep == 2`) a javított kódon ÚJRAFUTTATVA ZÖLD.

### F3 — MAJOR (frissítve MINOR-ról a dedikált security review után) — Az A9 bizonyítéka nem a brief által előírt alakú; a tulajdonság ma igaz, de nincs regressziós őre

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
- **Státusz:** **FIXED** (`da6c02ba`) — új teszt: `plan_setup_screen_test.dart`
  "comfort free text never reaches debug output (A9)". Ideiglenesen
  felülírja `debugPrint`-et (`flutter/foundation.dart`), egy egyedi
  sentinel szöveggel végigviszi a comfort lépést KÉTSZER — egyszer sikeres
  `saveDraft`-tal, egyszer `InMemoryKeyValueStore.failingKeys`-szel
  szándékosan megbuktatott mentéssel —, és megméri, hogy a sentinel egyik
  esetben sem jelenik meg az elfogott kimenetben. Ez a repo bevett
  poison-pill mintáját követi, és MOST MÁR valódi piros-kiváltóval
  rendelkezik: egy jövőbeli `debugPrint(request)` regresszió elkapná.

### F4 — MINOR (a dedikált security review lelete) — A controller doc-commentje tévesen "encrypted"-nek nevezi a draft-tárolást

- **Fájl:** `lib/features/practice_generator/presentation/controller/plan_setup_controller.dart:143-144`
- **Probléma:** `/// Keeps comfort text exclusively inside the encrypted/local
  draft path;` — a draft ténylegesen a MEGLÉVŐ (e körön kívül eső)
  `GenerationDraftRepository` → `KeyValueStore` láncon át
  `SharedPreferencesStore`-ba kerül, ami **plaintext**, nem titkosított
  (`lib/core/storage/shared_preferences_store.dart` az EGYETLEN production
  `KeyValueStore` implementáció; a titkosított tárolás egy KÜLÖN,
  `SecureStore`/`flutter_secure_storage` interfész, amit ma kizárólag a JWT
  használ, `storage_keys.dart:111 secureAuthToken`).
- **Hatás:** alacsony ma (a doc-comment maga nem befolyásol futásidejű
  viselkedést), de egy jövőbeli karbantartó ezt a hamis állítást olvasva
  tévesen azt hihetné, hogy az egészség-jellegű szöveg titkosítva van
  nyugalmi állapotban, és emiatt óvatlanabbul bővítené a tárolt tartalmat
  vagy egy exportot.
- **Kötelező javítás:** a szó cseréje pontos leírásra (pl. "plaintext local
  draft path"), vagy a mondat átfogalmazása úgy, hogy ne állítson
  titkosítást. Egysoros javítás, nem növeli a scope-ot.
- **Státusz:** **FIXED** (`da6c02ba`) — a komment most: "Keeps comfort text
  exclusively inside the plaintext local draft path" — pontos, nem állít
  titkosítást.

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

**Eredeti kör (`d1a7a898`):**

| Gate | Állított eredmény (implementer) | Ellenőrizve (reviewer, SAJÁT izolált klón) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld | ✅ zöld |
| test plan_setup_screen_test.dart | zöld, 7 teszt | ✅ zöld |
| test availability_editor_test.dart | zöld, 2 teszt | ✅ zöld |
| architecture | zöld | ✅ zöld (12 allowlisted deviation — pre-existing, e kör nem bővítette) |
| secrets | (nem jelentve) | ✅ zöld (2833 fájl, 0 lelet) |
| l10n parity | (nem jelentve) | ✅ zöld (1298 üzenet, en→hu) |

`scope_audit=ok` a `.codex-round-status`-ban is (base `4c4de25b`, 10 changed
path), a hiteles `tools/scope-audit.py` eszközzel függetlenül megerősítve.

**Javító kör után (`201d7601`), SAJÁT, MÁSODIK friss izolált klónban
(`/tmp/review-e07-r20-fix`):**

| Gate | Állított eredmény (implementer) | Ellenőrizve (reviewer, SAJÁT izolált klón) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld | ✅ zöld |
| test plan_setup_screen_test.dart | zöld | ✅ zöld |
| test availability_editor_test.dart | zöld, 3 teszt (+1 F1 regresszió) | ✅ zöld |
| architecture | zöld | ✅ zöld (12 allowlisted deviation, változatlan) |
| secrets | — | ✅ zöld (2835 fájl, 0 lelet) |
| l10n parity | — | ✅ zöld (1298 üzenet, en→hu) |
| scope-audit (`tools/scope-audit.py`, base `4c4de25b`, FULL kör) | — | ✅ OK, 12 changed path (10 implementer + 2 saját review-doksi, ez utóbbi kettő a scope-audit `generated/ignored` mentessége alatt) |
| CI (teljes suite + property + APK) | nem futott (orchestrátor feladata) | dispatch következik ezután |

## Merge-döntés

**A review-oldal APPROVED.** Mind a négy lelet zárva, mindegyik SAJÁT
kézzel, friss izolált klónban ellenőrizve — gate, scope-audit ÉS (F1/F2
esetén) az eredeti, bug-reprodukáló próbateszt újrafuttatásával. A dedikált
biztonsági review is APPROVED (`docs/reviews/e07-r20-security.md`).
0 nyitott BLOCKER/MAJOR/MINOR marad; a fennmaradó N1/N2 NOTE nem blokkol.

Az ADR 0052 zöld-kapu még egy tételre vár: a **teljes CI-suite** (property
gate + APK) sikeres futása a kör-branchen, exact-SHA-n `201d7601` felett —
ez az orchesztrátor következő lépése, a review-jelentés ezt nem
helyettesíti.
