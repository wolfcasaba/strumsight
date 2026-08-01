# E02-R20 — Accessibility, teljesítmény, regresszió és Epic lezárás

- **Státusz:** **PLANNING** (előre megírva 2026-07-31; indításra engedve
  2026-08-01, `main` @ `0dd85d3` — az E02-R19 merge-elve, a sor kiürült)
- **SDD-kör:** [`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md) **„Kör 20"** (+ §22, §24, §25, §28)
- **Branch:** `codex/e02-r20-epic-closure`
- **Előfeltétel:** **E02-R19 merge-ölve** (minden funkcionális kör kész).
- **ADR:** **nincs** — a zárókör nem hoz új architekturális döntést. Ha a
  rollout-döntés (migrated Learn bekapcsolása) ADR-t igényel, azt az
  **orchestrátor** írja, a kör indítása előtt.
- **Implementer motor:** a pre-flightban a user dönt. *Ajánlás:* **Codex** —
  audit-jellegű kör, ahol a „mit nem teljesítettünk" őszinte kimondása a fő érték.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ)**
> 1. Gyűjtsd össze az E02-R01…R19 review-inak **nyitott** NOTE/MINOR leletét, és
>    írd be a §2-be — a zárójelentés ezekre hivatkozik.
> 2. Egyeztesd a userrel: a `migratedLearnEnabled` **bekapcsolása** része-e
>    ennek a körnek, vagy a kör csak a döntés **dokumentálása** (alapértelmezés:
>    csak dokumentálás).
> 3. Ellenőrizd az Epic-2 DoD (SDD §28) minden tételét a mai kód ellen — a
>    §6 A7 táblája ebből lesz.
> 4. Státusz → PLANNING, dátum/sha frissítés, brief commit a kör-branchre.
>
> **A 2. és 4. pont ELDÖNTVE — lásd a §0.0-t. Az 1. és 3. pont az orchestrátoré.**

## 0.0 Pre-flight döntések (user, 2026-08-01) — KÖTELEZŐEK

1. **`migratedLearnEnabled`: CSAK DOKUMENTÁLÁS.** A zárókör a flaget **NEM**
   kapcsolja be. A rollout-döntést és a feltételeit a zárójelentés rögzíti
   (mit kell teljesülnie a bekapcsoláshoz, ki és mikor méri), a bekapcsolás
   **külön, későbbi kör**. A `lib/app/config/**` marad tilos zóna (§4).
2. **Nincs új ADR.** A zárókör nem hoz architekturális döntést; a pipeline
   sor-fájljában az ADR-oszlop `nincs`. Az orchestrátor **NE** osszon ADR-számot
   ehhez a körhöz.
3. **Implementer motor: MiniMax M3-first router.** Az M3 viszi az
   implementációt, és a **jóváhagyott router-szemantika szerint EGY** javító
   kört kap; ha az után is nyitva marad BLOCKER/MAJOR, a következő javító kört
   a **Codex `gpt-5.6-terra`** viszi (a küszöb 3-ról 1-re szigorítva —
   `docs/execution/pipeline-orchestrator-prompt.md` §2). Indoka: az M3 mért
   gyengéje a valótlan „kész" állítás, a zárókör terméke pedig épp a DoD-tábla
   őszintesége — a review és az eszkaláció együtt a mérce.
4. **A független review, a CI és a merge változatlan marad** a routeren kívül
   (Claude review-zik, ADR 0052/0053 zöld kapu).

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done    "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne pusholj, PR-t ne nyiss.
**STOP-klauzula:** listán kívüli fájl, vagy ellentmondó előírás → `stopped`.
**A §7 a terved.**

## 1. Cél

A Practice Engine **production readiness** ellenőrzése és **dokumentált**
lezárása: accessibility-audit, lokalizációs paritás, teljesítmény-mérés,
teljes regresszió, valódi eszközös tesztmátrix és az Epic-2 zárójelentés.

Ez a kör **nem** ad új képességet. Amit talál, azt vagy **javítja** (ha a
javítás kicsi és az engedélyezett fájllistán belül fér el), vagy **nyitott
leletként dokumentálja** — a hiány elhallgatása a legrosszabb kimenet.

## 2. Jelenlegi állapot (a pre-flightban frissítendő)

- Az E02-R01…R19 körök mind merge-ölve; a nyitott follow-upok listája a
  pre-flight 1. pontjában gyűlik össze.
- **Epic-1 precedens:** `docs/sdd/epic-01-completion-report.md` — szerkezet:
  elkészült körök táblája (PR + ADR) · tudatosan elhalasztott follow-upok ·
  DoD-tételek egyenkénti igazolása · valódi eszközös tesztek szakasza.
  **Ezt a szerkezetet kövesd.**
- **`docs/manual-testing/` könyvtár MA NEM LÉTEZIK** (mérve) — ez a kör hozza
  létre az első fájljával.
- **Gate-infrastruktúra:** `tools/round-gate.sh` (format → analyze → test →
  architecture, külön processzekben), CI `build-apk.yml` a teljes suite-tal, a
  randomizált property gate-tel (`PROPERTY_SEED=${{ github.run_id }}`) és az APK-val.
- **Meglévő nem-funkcionális őrök:** `test/core/screen_size_guard_test.dart`
  (320×568 és 915×412), `test/core/l10n_parity_test.dart`,
  `test/app/offline_network_guard_test.dart` (0-request offline garancia),
  `tool/check_architecture.dart`.

### 2.1 Nyitott leletek E02-R01…R19-ből (orchestrátor gyűjtése, 2026-08-01)

Az összes `docs/reviews/e02-r01..19-review.md` NOTE/MINOR/follow-up tétele a
mai kód ellen mérve. BLOCKER/MAJOR egyik körben sem maradt nyitva merge-ig.

| Forrás | Lelet | Mai állapot |
|---|---|---|
| R11 §11.4/1 | `noSignal` a direction/rhythm dimenzióban "unpaired"-et jelent, nem "nem érkezett jel"-t — két scorer-szemantika összemosva (ADR 0077 ismert korlát). | Nincs későbbi javítás. **Nyitott.** |
| R11 §11.4/2 | `allowedTransitions`-ben van él (`countIn/running → failed`), amit runtime-on egyetlen input sem termel — holt átmenet, nincs gyakorolva. | Nincs későbbi javítás. **Nyitott.** |
| R11 §11.4/3 | A Practice a **Live** engine mikrofon-leasét (`AudioOwner.live`) használja, nincs saját tulajdonosa. | `lib/core/audio/lifecycle/audio_session_lease.dart` `AudioOwner` enumja ma is `live, tuner, analyzeRecorder, latencyCalibration, diagnostics` — nincs `practice` tag. **Nyitott.** |
| R11 §11.4/4 | `practiceSessionControllerProvider` nincs éles oldalon bedrótozva. | `lib/features/practice/application/practice_session_providers.dart:182-186` kommentje ma is: *"a Kör 13 pre-flight fogja definiálni"*. R12/R18 review is megerősíti. **Nyitott — ld. lent a rendszerszintű rés.** |
| R15 NOTE-1 | A chord-change elemzés az éles session-screenen null-drótozott (`analysis: null, latestChange: null`); ígéret: "R18 köti be". | `practice_session_screen.dart:330-336` ma is `null`. R18 briefje ezt nem tartalmazta. **Nyitott, az ígért R18-zárás elmaradt.** |
| R18 n1 / R19 followup | A Free Practice eredmény-képernyő "strum count" csempéje `attemptsCount`-ot mutat strumszám helyett. | `practice_result_screen.dart:165` ma is `entry.attemptsCount`. R19 scope-auditja szerint a fájlhoz nem is nyúlt. **Nyitott.** |
| R18 B2 residual | Az éles `practiceSessionRecorderProvider` becsületes Noop lett (nem hamis-siker), de emiatt **egyetlen önálló Practice V2 session sem perzisztálódik**, amíg a valós `mode/source/definitionId` metaadat nincs végigvezetve. | `practice_session_providers.dart:11,71-94` ma is `NoopPracticeSessionRecorder`. R19 csak a Learn-migrációs útvonalat drótozta be, az önálló Hub→Session utat nem. **Nyitott.** |
| R14 NOTE-1 | Az A4 "commands/verdict-list/HUD score unchanged" invariáns fél nem kapott saját regressziós cellát. | Nincs ilyen cella `practice_highway_test.dart`-ban. **Nyitott, alacsony prioritás.** |
| R16 N1 | `free_practice_property_test.dart` `_randomInput`-ja előre rendezi az observationöket — a "timeline ≤ active" invariáns rendezetlen inputon nincs property-tesztelve. | Nincs későbbi javítás. **Nyitott, alacsony prioritás.** |
| R17 N1 | Az adaptív policy "3 egymást követő step-up pass" küszöbe hardkódolt, nem policy-paraméteres. | Nincs későbbi javítás. **Nyitott, kozmetikai.** |

**Rendszerszintű rés (a fenti leletek összegzése, nem önálló review-tétel):**
a `practiceSessionHostProvider` éles defaultja **`null`**
(`lib/features/practice/presentation/practice_effect_listener.dart:21-22,64`,
doc-comment: *"the production default is `null`, which the screen renders as
a localised 'session unavailable' state"*), és a
`practicePrepareSinkProvider` éles defaultja is a placeholder logging sink
(`practice_setup_controller.dart:33-55`, "Kör 13 swaps the..." komment még
ma is ott van). **Ennek eredőjeként egy valós felhasználó a Practice
Hub → Setup → Session úton ma NEM tud önálló Practice V2 sessiont futtatni
az élesített appban** — a domain/application réteg kimerítően tesztelt, de a
presentation→controller drótozás az önálló (nem Learn-migrációs) útra R12/R13
óta nyitva maradt, és egyetlen későbbi kör sem zárta. Összhangban áll azzal,
hogy `practiceEngineV2Enabled` éles defaultja `false`
(`lib/app/config/feature_flags.dart:15,41`).

**Ez az egyetlen legfontosabb tétel, amit a zárójelentésnek ki KELL mondania**
— a DoD-tábla (A7) session-lifecycle/gyakorlási-mód/integráció celláinak
mindegyikét "teljesül domain/widget-teszt szinten, de nem elérhető
végponttól-végpontig az élesített appban" minősítéssel kell ellátni, nem
egyszerű "teljesül"-lel. **A drótozás pótlása ebben a körben TILOS** (§3 —
ez funkció, nem apró javítás, és az érintett fájl
`practice_session_providers.dart`/`practice_effect_listener.dart` a tilos
zónában van) — nyitott leletként dokumentálandó, a §11-es review kiemelt
figyelmet fordít arra, hogy ez a tétel ne halkuljon el a jelentésben.

### 2.2 DoD elő-audit (SDD §28, orchestrátor mérése) — a §6/A7 tábla alapja

A teljes 52 tételes ellenőrzés (Architektúra 1–8, Session lifecycle 9–14,
Pontozás 15–24, Gyakorlási módok 25–32, Integráció 33–41, Minőség 42–52) az
implementernek átadva egy külön kutatási jegyzetben; összegzés:

- **teljesül (statikus/teszt-szintű bizonyítékkal):** a legtöbb Architektúra
  (1–5, 7–8), Pontozás (15–23) és Gyakorlási mód / Integráció tétel — de a
  2.1 rendszerszintű rés miatt ezek a "teljesül végponttól-végpontig" jelzőt
  NEM kaphatják meg automatikusan az A7 táblában.
- **részleges:** #6 (gateway-absztrakció helyes, de sosem éles a rés miatt),
  #9 (lifecycle unit/integrációs szinten bizonyított, UI-n át nem elérhető),
  #24 (legacy parity dokumentált, de egy mért mikro-eltéréssel a 280ms
  határon — R19/b 4.1), #32 (loop a compiler szintjén bizonyított, UI-n át
  nem), #33/38–41 (recorder/streak/daily-goal a Learn-migrációs úton
  bizonyított, önálló Practice-session úton Noop miatt sosem fut le), #49
  (leak-védelem fake gateway-vel bizonyított, valós mikrofonos úton nem
  gyakorolt), #52 (a11y teszt-szinten bizonyított, valós eszközön nem).
- **nem teljesül:** #48 (valós eszközös teszt dokumentálva — ez maga R20 A8
  feladata, ma nem létezik).
- **nem ellenőrizhető staticusan (a gate/CI futtatja):** #42–45, #47 — minden
  korábbi kör review-ja zölden futtatta, de ez a pre-flight nem futtatta
  újra a teljes suite-ot.

Az implementer az A7 táblát **erre a mérésre alapozva** töltse ki, ne
nulláról; ahol a fenti minősítés "részleges" vagy "nem teljesül", az A7
cellába a **konkrét okot és a rendszerszintű rés hivatkozását** írja, nem
összevont "teljesül" szót.

## 3. Scope

**Benne:** audit + a talált **kis** hiányok javítása + a mérési és
dokumentációs artefaktumok.

**Kívül (ebben a körben TILOS):**

- **Új funkció, új mód, új képernyő.** Ha egy DoD-tétel funkcionális hiányra
  fut ki, az **nyitott lelet + külön kör**, nem itt megírt funkció.
- Nagy refaktor teljesítmény ürügyén. Optimalizálni csak **mért** szűk
  keresztmetszeten szabad, és a mérést a diffbe kell tenni.
- A `migratedLearnEnabled` bekapcsolása a user explicit döntése nélkül.
- DSP/ML paraméter és modell-bináris (AGENTS.md §9).

## 4. Engedélyezett fájlok

| Útvonal | Új? | Miért |
|---|---|---|
| `docs/sdd/epic-02-completion-report.md` | **ÚJ** | Epic-2 zárójelentés (az Epic-1 szerkezete szerint) |
| `docs/manual-testing/practice-engine-device-matrix.md` | **ÚJ** | valódi eszközös tesztmátrix (SDD §25.6) |
| `docs/sdd/00-index.md` | — | **CSAK** az Epic-2 állapotának átvezetése |
| `README.md` | — | **CSAK** a Practice Engine szakasz + ismert korlátok |
| `HANDOFF.md` | — | **CSAK** az állapot-pillanatkép frissítése |
| `test/features/practice/presentation/practice_a11y_audit_test.dart` | **ÚJ** | A1 accessibility-mátrix |
| `test/features/practice/practice_performance_test.dart` | **ÚJ** | A3 teljesítmény-mérés számlálókkal |
| `test/property/practice_engine_property_test.dart` | **ÚJ** | A4 epic-szintű invariánsok |
| `lib/features/practice/presentation/**` | — | **CSAK** az A1/A2 auditon megbukott, **kicsi** javítások (címke, kontraszt-független jelölés, touch target, overflow) |
| `lib/l10n/app_en.arb` · `lib/l10n/app_hu.arb` | — | **CSAK** hiányzó/hibás fordítások javítása |
| `docs/rounds/e02-r20-epic-closure.md` | — | **CSAK a §10** |

**Tilos zóna:** minden más. Nevezetesen `lib/features/practice/domain/**`,
`application/**`, `data/**` (viselkedés-változás a zárókörben **nem**),
`lib/features/learn/**`, `lib/app/config/**`, `.github/**`, `docs/adr/**`,
`docs/rag/chunks/**`.

> Ha az audit **viselkedésbeli** hibát talál a domain/application rétegben, az
> **nyitott lelet + `stopped`**, nem itt elvégzett javítás.

**Új fájl a listán kívül = scope-sértés** → `stopped`.

## 5. Kötött döntések (NEM tárgyalhatók)

1. **A zárókör nem ad funkciót.** A hiányt dokumentáljuk, nem pótoljuk.
2. **Minden állítás bizonyítékkal.** A zárójelentés minden „kész" sora mellett
   ott a teszt, a parancs-kimenet vagy a CI-futás linkje. Bizonyíték nélküli
   állítás = a jelentés hibája (mért tanulság: `docs/LESSONS.md`).
3. **A DoD tételei egyenként igazolandók** (SDD §28, ~50 checkbox). A „nagyrészt
   teljesül" nem elfogadható válasz: minden tétel **teljesül / nem teljesül +
   miért + hol a bizonyíték**.
4. **A valódi eszközös teszt a user feladata** (HORIZON-szabály: a szintetikus
   zöld sosem „done"). Ez a kör a **mátrixot** és a kitöltési útmutatót adja,
   nem a kipipálást.
5. **A teljesítmény-mérés determinisztikus számlálókkal történik**, nem fal-óra
   FPS-méréssel (CI-n az utóbbi értelmezhetetlen és flaky).
6. **Ismert korlátok kimondva.** A README és a zárójelentés tartalmazza a
   veszteséges akkord-leképezést (ADR 0071 §2), a legacy Learn pause-rését, a
   detektor szótár-korlátját és minden nyitott NOTE-ot.

## 6. Acceptance criteria

### A1 — Accessibility-audit mátrix

Minden Practice-képernyőre (Hub, Setup, Session, Result) és minden mód-nézetre
külön cella:

| Ellenőrzés | Mérce |
|---|---|
| érintőfelület | minden interaktív elem ≥ 48×48 dp |
| szemantika | címke **és** akció egy node-on |
| szín-függetlenség | minden verdict/állapot szöveggel vagy ikonnal is hordozott |
| 200% szövegméret | nincs overflow |
| landscape (915×412) | nincs overflow |
| reduced motion | `disableAnimations: true` mellett nincs animált átmenet, az információ megmarad |
| chart-szemantika | minden diagram/számblokk szemantikai összefoglalóval |
| screen reader | nem olvas fel minden frame-et; csak lényeges esemény a live-region |

***Pirosra fogja:*** a „csak a fő képernyőn ellenőriztük" audit.

**NEM elfogadható gyengítés:** a mátrix egy-két képernyőre szűkítése, vagy a
„vizuálisan rendben van" indoklás teszt helyett.

### A2 — Lokalizációs paritás és minőség

- `l10n_parity_test` zöld (azonos kulcshalmaz, üres fordítás nincs).
- **Minden** `practice*` kulcs magyar fordítása **valódi fordítás**, nem angol
  másolat — a teszt az azonos en/hu értékeket listázza, és a kör vagy javítja,
  vagy tételesen indokolja (pl. „BPM" mindkét nyelven ugyanaz).
- A coaching-kódokhoz **mindkét** nyelven van szöveg.
- Szám- és százalék-formázás lokalizált (`intl`), nem kézi string-összefűzés.

### A3 — Teljesítmény, MÉRVE (számlálókkal)

| Mérés | Eszköz | Küszöb |
|---|---|---|
| highway build-hatókör | az R14 `@visibleForTesting` számlálója | 2 000 célnál **≤ 64** épített marker |
| matcher vizsgálati hatókör | az R09 két számlálója | ≤ 64 × (pengetés + cél) |
| observation-áteresztés | fake gateway hívásnaplója | 10 perc szimulált session → a verdict-lista **korlátos** (nem nő eseményenként korlátlanul) |
| controller state-kibocsátás | state-stream számlálója | tickenként **legfeljebb 1** kibocsátás |
| memória-korlát | a verdict/history struktúrák elemszáma | a cap szerinti korlát tartva |

***Pirosra fogja:*** a korlátlanul növő verdict-lista — ez a 10 perces session
memóriaemelkedésének fő forrása.

### A4 — Epic-szintű property gate

`test/property/practice_engine_property_test.dart`, `PROPERTY_SEED` (hiány → 42),
véletlen definíció + config + megfigyelés-sorozat kombinációkra:

1. egy célesemény **legfeljebb egyszer** párosul, egy megfigyelés **legfeljebb
   egyszer** használódik;
2. minden score `0..1` között van **vagy** explicit `NotApplicable` /
   `InsufficientData`;
3. free-practice futásból **soha** nem keletkezik overall accuracy;
4. terminal állapot után **nulla** aktív erőforrás;
5. a session-idő invariáns végig tart: `playing <= active <= wall`.

### A5 — Teljes regresszió (a gate-en felül)

A záró gate mellett a CI-futás **zöld**: teljes `flutter test`, randomizált
property gate (`PROPERTY_SEED = run_id`), architecture guard, asset guard,
release APK. A futás **linkje** a §10-be.

Backend csak akkor futtatandó, ha az Epic módosította (mérve: az Epic 2 a
`backend/`-hez **nem** nyúlt → nem futtatandó, és ezt a §10-ben ki kell mondani).

### A6 — Nincs mikrofon-, ticker- vagy subscription-leak

Az R11 és R13 leak-számlálói zöldek egy **teljes, végigjátszott** session után,
mind a három terminal ágon; az `offline_network_guard_test.dart` zöld (a
practice session alatt **nulla** hálózati kérés).

### A7 — Az Epic-2 DoD tételes igazolása

`docs/sdd/epic-02-completion-report.md` tartalmaz egy táblát az SDD §28
**minden** tételéről:

| Tétel | Állapot | Bizonyíték |
|---|---|---|
| … | teljesül / **nem teljesül** | teszt-útvonal, PR, CI-futás, vagy „nyitott lelet #N" |

Az „elhalasztott" tételekhez tartozik **ok** és **hol folytatódik** (Epic 3+
vagy külön kör).

**NEM elfogadható gyengítés:** összevont „minden DoD-tétel teljesül" mondat
tételes tábla nélkül.

### A8 — Valódi eszközös tesztmátrix

`docs/manual-testing/practice-engine-device-matrix.md`:

- az SDD §25.6 tesztmátrixa (készülék, Android-verzió, mód, tempó, zaj,
  fejhallgató/hangszóró, balkezes mód, akkumulátor-takarékos mód);
- **kitöltési útmutató** (mit jelent a pass, mit kell rögzíteni);
- a **user** tölti ki — a kör nem állíthatja, hogy elvégezte.

### A9 — Dokumentációs zárás

- `README.md`: Practice Engine szakasz + **ismert korlátok** (§5.6 lista).
- `HANDOFF.md`: állapot-pillanatkép, a következő lépés (Epic 3 / rollout-döntés).
- `docs/sdd/00-index.md`: az Epic 2 állapota átvezetve.
- A zárójelentés hivatkozik minden Epic-2 ADR-re (0065–0085) és minden PR-re.

## 7. Implementációs sorrend (ez a TERVED)

1. Nyitott leletek összegyűjtése (pre-flight 1.) és a DoD-tábla váza.
2. A1 accessibility-audit — előbb **mérés**, aztán javítás; minden javítás
   mellett ott a cella, ami pirosra futott.
3. A2 lokalizációs audit.
4. A3 teljesítmény-mérések a meglévő számlálókra.
5. A4 epic-szintű property teszt.
6. A6 leak-ellenőrzés teljes sessionnel.
7. `epic-02-completion-report.md` (A7) és a device-mátrix (A8).
8. README / HANDOFF / SDD-index (A9).
9. Záró gate (§9), majd a §10 kitöltése; a CI-futás linkje az A5-höz.

## 8. Kockázatok

- **A „minden zöld" kísértése.** A zárójelentés értéke azon áll, hogy a nyitott
  leletek is benne vannak. Ha egy DoD-tétel nem teljesül, azt **ki kell mondani**.
- **Scope-tágulás javítás ürügyén.** Egy hiányzó funkció nem „apró javítás" —
  `stopped` + külön kör.
- **Fal-óra alapú teljesítmény-állítás.** CI-n értelmezhetetlen; a számlálók a
  mérce (§5.5).
- **A magyar fordítások „ideiglenes" angol értékei** — az A2 pont ezt fogja meg.
- **A valódi eszközös teszt kipipálása.** Az a useré; a kör csak a mátrixot adja.

## 9. Záró gate — szó szerint ez az egyetlen hívás

```
tools/round-gate.sh test/features/practice/ test/features/learn/ test/features/progress/ test/features/streak/ test/core/ test/app/ test/property/
```

Csővezeték nélkül, a teljes kimenetet a §10-be. A teljes suite + randomizált
property gate + APK a CI-ban fut (ADR 0053), és a **zöld CI-futás linkje**
kötelező része a §10-nek — `gh`-t az implementer NE hívjon.

## 10. Implementation handoff — az IMPLEMENTER tölti ki

*(Fájlonkénti összefoglaló · a záró gate TÉNYLEGES, teljes kimenete · az A1–A9
pontok teljesülése bizonyítékkal · **a nyitott leletek listája** · nem futtatott
ellenőrzések és okuk.)*

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r20-review.md`

Kiemelt figyelem: a DoD-tábla **őszintesége** (van-e „teljesül" bizonyíték
nélkül), az A1 mátrix teljessége (minden képernyő és mód-nézet), és hogy a
zárójelentés nem állít-e olyat, amit csak a user valódi eszközös tesztje
igazolhatna.
