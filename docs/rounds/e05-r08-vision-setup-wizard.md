# E05-R08 — Vision setup wizard, camera profile és permission UX

- **Státusz:** PLANNING (pre-flight §0.0 lezárva 2026-08-06, kód olvasva: `origin/main` @ `78ac3ce`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 8; §12.2–12.3, §13.1–13.2
- **Branch:** `codex/e05-r08-vision-setup-wizard`
- **Előfeltétel:** **E05-R04, E05-R05, E05-R06, E05-R07 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Terra (Codex CLI, `gpt-5.6-terra`) — aktív
  `.pipeline/engine-override=terra` a dispatch idején (§0.0-tól függetlenül mérve; a brief eredeti
  „MiniMax M3" javaslata az ADR 0069 UI-heurisztika szerinti alapértelmezés volt, felülírva)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/presentation/screens/vision_setup_screen.dart",
  "lib/features/vision/presentation/widgets/vision_setup_frame_guide.dart",
  "lib/features/vision/presentation/widgets/camera_permission_panel.dart",
  "lib/features/vision/presentation/providers/vision_setup_providers.dart",
  "lib/features/vision/application/vision_setup_controller.dart",
  "lib/features/vision/domain/vision_setup_profile.dart",
  "lib/features/vision/public.dart",
  "lib/app/routing/app_route.dart",
  "lib/app/routing/app_router.dart",
  "lib/core/storage/storage_keys.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/vision/presentation/vision_setup_screen_test.dart",
  "test/features/vision/application/vision_setup_controller_test.dart",
  "docs/rounds/e05-r08-vision-setup-wizard.md",
]
gate_tests = [
  "test/features/vision",
  "test/core/l10n_parity_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight LEZÁRVA (§0.0, R1–R6):** `origin/main` @ `78ac3ce` + E05-R04/05/06/07
> merge megerősítve; `AGENTS.md` újraolvasva; a route-katalógus és a tényleges
> (nem `route_guards.dart`, hanem inline `app_router.dart`) flag-gate minta mérve;
> egy meglévő wizard-minta (`lib/features/practice/presentation/screens/`) azonosítva.
> Nincs ÚJ ADR (0178/0179/0181 bővítése — renumbered). PLANNING→dispatch.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl vagy contract → **azonnal
`stopped`**, nem „kis kiegészítés".

## 0.0 Tervezési baseline és pre-flight revízió

**Mérve `origin/main` @ `78ac3ce` (E05-R07 után), orchestrátor Claude Sonnet 5,
2026-08-06.** Hat mért eltérés a leírt brief és a tényleges kód/SDD között —
mind dokumentált revízióval oldva, egyik sem igényel ÚJ ADR-t.

**R1 — ADR-hivatkozás elavult.** A fejléc „0161/0162/0164 bővítése" a
renumbering (E05-R01) ELŐTTI számokra hivatkozik. Mérve (`ls docs/adr/`): a
régi 0161–0166 tartomány megszűnt, helyette 0178–0183 él (+17 offset — ADR
0178 saját „Kontext-ADR-ek" sora is megerősíti: „0166→0183"). **Helyes
hivatkozás: 0178/0179/0181.** Változatlanul nincs ÚJ ADR — a kör kizárólag
meglévő döntéseket (privacy-by-default, capability-aware feedback,
manual-calibration-fallback) fogyaszt.

**R2 — Flag-gated route rossz fájlhoz kötve.** A §2 szerint
`route_guards.dart` „a flag-alapú route-őrzés helye" — mérve (a fájl teljes
tartalma): két tiszta függvényt tartalmaz (`mayLeaveEditor`,
`onboardingRedirect`), egyik sem flag-alapú és egyik sem vision-related. A
TÉNYLEGES minta (mérve `app_router.dart`-ban, 3 precedens: `practiceEnabled`,
`songTrainerEnabled`, `aiTutorEnabled` — pl. `if (aiTutorEnabled)
...[GoRoute(...)]` közvetlenül a route-listában, a flag
`ref.read(appConfigProvider).flags.<flag>`-ként olvasva a builder tetején):
a vision route ugyanezt kövesse, közvetlenül `app_router.dart`-ban — `if
(visionEnabled && visionSetupEnabled) ...[GoRoute(path:
AppRoutes.visionSetup, ...)]`. `route_guards.dart`-ot ez a kör NEM módosítja
(nincs is az `allowed_paths`-on).

**R3 — Hiányzó fájl az `allowed_paths`-ból: `lib/core/storage/storage_keys.dart`
(FELVÉVE fent).** A §5.4 két ÚJ perzisztencia-kulcsot ír elő
(`ss.vision.setup_profile`, `ss.vision.camera`), de mérve (a fájl teljes
tartalma): az app MINDEN kulcsa ide van központosítva („Every persisted key
in the app, in one place"), nincs feature-lokális kulcs-minta a kódbázisban,
és a uniqueness-guard teszthez használt `all` lista is itt él. AGENTS.md §10
tiltja a „magic string... központi definíció nélkül" mintát. Precedens:
E04-R18 pre-flightja ugyanígy vette fel `app_router.dart`-ot („a
flag-gating cellák enélkül nem teljesíthetők"). Az implementer KIZÁRÓLAG
additív módosítást tehet (két új `static const String` + felvétel az `all`
listába); meglévő kulcs átírása/törlése továbbra is tilos zóna (H2/H3).

**R4 — Elérhetetlen cél-állapot: a `CameraCapture` kontraktnak nincs facing
(front/back) paramétere.** Mérve: `CameraCapture.start()` argumentum
nélküli; `createPlatformCameraCapture()` nulla paraméterű;
`_PluginCameraController.create()` MINDIG a back kamerát preferálja
(`orElse: cameras.first`); `FakeCameraCapture`-nek nincs facing/lensDirection
mezője. A teljes stack egyetlen pontja sem tudja kiválasztani vagy akár
megkülönböztetni a facing-et. A §3/§6 „front/back választás + switch-restart"
ezért **a mai kódban nem terjedhet túl egy perzisztált preferencián**: a
wizard felveszi/perzisztálja a választást (a `ss.vision.camera` „kamera-
azonosító absztrakció" értéke), és a coordinator close→open lease-fegyelme a
MEGLÉVŐ, facing-agnosztikus `CameraCapture`/`FakeCameraCapture` felett
tesztelhető (a lease-számolás nem függ a facing-től) — de a preferencia éles
platformkamerához kötése (hogy a `PluginCameraCapture` TÉNYLEGESEN a kért
lencsét nyissa) **nem** ennek a körnek a hatóköre: `lib/core/camera/`
CORE-kontraktus bővítése, saját mutáció-tesztelt körben (az epic mintája:
R03 kontraktus, R04 permission, R05 coordinator, R06 production adapter —
mind külön kör). **A §6/§6.1 camera-switch cella szövege ennek megfelelően
pontosítva lent** — a lease-fegyelmet (close-előbb-mint-open a facing-
preferencia váltásakor) bizonyítja, NEM a fizikai kamera tényleges váltását.
Follow-up a §9 Kockázatoknál.

**R5 — SDD §13.2 hat profilt sorol fel, a brief négyet szállít.** Mérve
(`docs/sdd/06-epic-05-computer-vision.md` §13.2): `leftHandFocus,
rightHandFocus, fullUpperBody, practiceBalanced, songPerformance,
experimentalFretboard`. A §3/§6 csak négyet nevez, és a negyediket eltérő
névvel (`balanced` a kanonikus `practiceBalanced` helyett). Nem hiba, de
dokumentálatlan szűkítés volt (L151 mintája: a prózai/SDD-ígéret ne maradjon
a checkbox-listánál szélesebb dokumentálatlanul). Feloldás: (a) a negyedik
profil kanonikus neve **`practiceBalanced`** (nem `balanced`) — elkerüli a
későbbi átnevezést, amikor `songPerformance`/`experimentalFretboard`
bekerül; (b) `songPerformance` (Song Trainer-integráció-függő,
`visionSongIntegrationEnabled` mögötti) és `experimentalFretboard`
(`visionExperimentalFineFretEnabled` mögötti, deklaráltan kísérleti) explicit
kikerül a §3 „Kívül" listájába, jövőbeli körre halasztva — mindkét flag már
létezik `feature_flags.dart`-ban (E05-R03 óta, default OFF), nincs ADR-igény.

**R6 — Megerősítés (nem hiba, mérve).** (a) mind az öt `CameraPermissionState`
érték valós inputból származtatható (`camera_permission.dart` teljes
mapping-je) — a permission-mátrix nem tesztel elérhetetlen állapotot. (b)
`grep -rn "\.acquire("` a teljes `lib/`-ben ma KIZÁRÓLAG a mikrofon-
coordinatort találja (`mic_capture.dart:82`) — a kamera-coordinatornak
(E05-R05) ma NULLA fogyasztója van; ez a kör lesz az ELSŐ valódi hívó
(`CameraOwner.visionSetup` már létezik pontosan erre, `camera_session_lease.
dart:6`). (c) a meglévő CORE providerek (`cameraPermissionGatewayProvider`,
`cameraSessionCoordinatorProvider`, `cameraCaptureProvider`/
`cameraCaptureFactoryProvider` — mind `lib/core/camera/`-ban, importálhatók
listázás nélkül) pontosan a szükséges kompozíciós felületet adják a ÚJ
`vision_setup_providers.dart` alá. (d) `visionEnabled`/`visionSetupEnabled`
flag-nevek és a `leftHanded`/`StorageKeys.leftHanded` hivatkozás pontosan
egyezik a brief állításával — nincs korrekció.

## 1. Cél

Vezetett, **kihagyható** és privacy-tudatos kameraelhelyezési flow: 3–5 lépés,
profilválasztás, kamera-választás, permission-UX minden állapotra, és mindenhol
elérhető **audio-only továbblépés**.

## 2. Jelenlegi állapot (mért, `5d082dc` + megelőző körök)

- A `lib/app/routing/app_route.dart` **statikus katalógus** (`AppRoutes`), a
  `shellTabs` a live/analyze/learn/library/settings ötös. A vision **nem** kap
  shell-tabot ebben a körben.
- A flag-alapú route-őrzés **közvetlenül `app_router.dart`-ban** történik,
  feltételes `if (<flag>) ...[GoRoute(...)]` spreaddel a route-listában
  (precedens: `practiceEnabled`/`songTrainerEnabled`/`aiTutorEnabled`) — NEM
  `route_guards.dart`-ban, ami két, flag-független tiszta függvényt tartalmaz
  (mérve, §0.0 R2). A vision route ugyanezt a mintát követi:
  `visionEnabled && visionSetupEnabled` mögé kerül.
- Az E05-R04 `CameraPermissionState` öt állapota + `failure` térképe kész, de
  **UI nélkül**; ez a kör adja az UI-t (a R04 §1 scope-megjegyzése szerint).
- `lib/l10n/app_en.arb` / `app_hu.arb` a két nyelvi forrás; a paritást a
  `test/core/l10n_parity_test.dart` méri (meglévő őr).
- A `leftHanded` beállítás **létezik**: `StorageKeys.leftHanded`
  (`ss.settings.left_handed`) — a setup ezt olvassa, és korrigálhatóvá teszi.

## 3. Scope

**Benne:** setup state machine (`VisionSetupController`) + képernyő, a négy
profil (`leftHandFocus`, `rightHandFocus`, `fullUpperBody`,
**`practiceBalanced`** — kanonikus SDD §13.2 név, §0.0 R5), kamera-ábra
overlay profilonként, front/back **preferencia-választás** + a coordinator
close→open lease-fegyelme választás-váltáskor (a fizikai kamera tényleges
váltása KÍVÜL esik — §0.0 R4), permission-panel (denied / permanentlyDenied
→ Settings CTA / restricted / unavailable), privacy-állapot kijelzés
(„helyben dolgozunk fel, nem rögzítünk"), Skip → audio-only CTA, a **profil és
a kamera-preferencia** perzisztálása, en/hu ARB.

**Kívül — TILOS:** kalibrációs anchor-editor (R11), quality assessor (R09),
landmark/inference, raw kép mentése, új storage-kulcs a profilon és a
kamera-preferención túl, shell-tab hozzáadása, **a fizikai front/back kamera
tényleges kiválasztása** a `PluginCameraCapture` rétegben (a `CameraCapture`
kontraktnak ma nincs facing paramétere — §0.0 R4, jövőbeli `lib/core/camera/`
kör dolga), **`songPerformance`** és **`experimentalFretboard`** profil (SDD
§13.2 névtér, integráció-függő — §0.0 R5, jövőbeli kör).

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../presentation/screens/vision_setup_screen.dart` | ÚJ | wizard képernyő |
| `.../presentation/widgets/vision_setup_frame_guide.dart` | ÚJ | profil-ábra overlay |
| `.../presentation/widgets/camera_permission_panel.dart` | ÚJ | permission UX |
| `.../presentation/providers/vision_setup_providers.dart` | ÚJ | providerek |
| `.../application/vision_setup_controller.dart` | ÚJ | state machine |
| `.../domain/vision_setup_profile.dart` | ÚJ | profil-enum + szabályok |
| `lib/features/vision/public.dart` | ÚJ | feature public API |
| `lib/app/routing/app_route.dart`, `app_router.dart` | meglévő | **csak** új vision route + inline flag-guard (§0.0 R2) |
| `lib/core/storage/storage_keys.dart` | meglévő | **csak additív**: 2 új kulcs + `all` lista (§0.0 R3) |
| `lib/l10n/app_*.arb` | meglévő | **csak additív** kulcsok |
| `test/features/vision/*` | ÚJ | widget + controller tesztek |
| `docs/rounds/e05-r08-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; meglévő ARB kulcs átírása; `docs/rag`; DSP.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A setup kihagyható.** Minden lépésen elérhető a „Folytatás kamera nélkül"
   útvonal, és a kamera nélküli út a **mai** viselkedésre visz. **NEM
   elfogadható:** a Skip elrejtése, „csak az első lépésen" engedélyezése, vagy
   olyan állapot, amelyből csak permission-megadással lehet kilépni.
2. **Permission csak explicit gombnyomásra kérődik** (ADR 0178) — `initState`,
   provider-build vagy route-belépés **nem** kérhet engedélyt. **NEM
   elfogadható:** „a felhasználó úgyis a setupba jött" indoklás.
3. **A `permanentlyDenied` és `restricted` állapot Settings CTA-t kap**, nem
   újra-kérést; az `unavailable` **nem** viselkedhet `denied`-ként (más szöveg,
   nincs „próbáld újra" gomb, ami sosem segít).
4. **Perzisztálás:** kizárólag a választott **profil** és a **kamera-azonosító
   absztrakció** mentődik (`ss.vision.setup_profile`, `ss.vision.camera`),
   raw kép vagy preview-screenshot **soha** (ADR 0183).
5. **Nincs domainbe szivárgó Flutter típus:** a `vision_setup_profile.dart`
   framework-mentes (architektúra-őr méri).
6. **Minden felhasználói szöveg ARB-ból jön** — hardcode-olt magyar/angol
   mondat a widgetben BLOCKER.

## 6. Acceptance criteria

- [ ] **Permission-mátrix widget-teszt, cellánként:** granted → tovább;
      denied → kérés-gomb; permanentlyDenied → **Settings CTA** (nincs
      újra-kérés gomb); restricted → Settings CTA; unavailable → magyarázó
      állapot **kérés-gomb nélkül**. Mind az öt külön teszt.
- [ ] **Profil-mátrix:** mind a négy profil (`leftHandFocus`, `rightHandFocus`,
      `fullUpperBody`, `practiceBalanced`) kiválasztható, mindegyikhez más
      frame-guide rajzolódik, és a `leftHanded` beállítás a `leftHandFocus`/
      `rightHandFocus` ajánlott értékét befolyásolja, de **felülírható**.
- [ ] **Skip-teszt minden lépésről** (lépésenként egy cella): a Skip után az
      audio-only CTA elérhető, és nem indul kamera (a fake capture `start`
      számlálója 0).
- [ ] **Camera switch (lease-fegyelem, §0.0 R4):** a front/back
      preferencia-váltás a coordinatoron át **close→open** sorrendben történik;
      a teszt méri, hogy egyszerre nincs két lease. (A fizikai kamera tényleges
      váltása — hogy a preferencia a valódi lencsét nyissa — KÍVÜL esik: a
      `CameraCapture` kontraktnak ma nincs facing paramétere.)
- [ ] **Perzisztencia-teszt:** csak a profil + kamera-preferencia kulcs íródik;
      a store tartalma ellenőrizve — **más kulcs nem jelenik meg**.
- [ ] **Lokalizációs paritás:** `test/core/l10n_parity_test.dart` zöld, minden
      új kulcs en+hu.
- [ ] **Flag-teszt:** `visionEnabled=false` esetén a route nem elérhető
      (guard), és a mai route-ok viselkedése változatlan.

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A `permanentlyDenied` ág újra-kérés gombot rajzol Settings CTA helyett | permission-mátrix `permanentlyDenied` cellája |
| Az `unavailable` ág is kérés-gombot ad | permission-mátrix `unavailable` cellája |
| A Skip útvonal elindítja a kamerát | skip-teszt (a fake `start` számlálója 1 ≠ 0) |
| A facing-preferencia váltás `open`→`close` sorrendű | camera-switch teszt (két egyidejű lease) |
| A wizard a profilon és kamerán kívül bármit perzisztál | perzisztencia-teszt (idegen kulcs a store-ban) |
| A `visionEnabled=false` guard kimarad | flag-teszt (a route elérhető marad) |
| Új ARB kulcs `hu` fordítás nélkül | `test/core/l10n_parity_test.dart` |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision test/core/l10n_parity_test.dart
```

Külön processzek, nincs `&&`/pipe/`tail`, **nincs `| tail`**. CI-dispatch/PR/
merge = orchestrátor. A valós eszközös setup-élmény a device-mátrix PENDING sora.

## 8. Implementációs sorrend

1. RED: permission-, profil-, skip-mátrix widget-tesztek.
2. Domain profil + controller (state machine).
3. Képernyő + widgetek + providerek.
4. Route + guard + ARB; gate.

## 9. Kockázatok

- **A wizard „elnyeli" a felhasználót** permission nélkül — a skip-mátrix ezt méri.
- **ARB-kulcs ütközés** más körrel (párhuzamos munka): additív kulcsnevek
  `visionSetup*` prefixszel; meglévő kulcs átírása **`stopped`**.
- **A camera switch két lease-t nyit** — az R05 coordinator hibát ad; a UI-nak
  ezt kezelnie kell, nem megkerülnie.
- **Follow-up (§0.0 R4, nem blokkolja ezt a kört):** a facing-preferencia ma
  nem kötődik valódi lencseváltáshoz — a `CameraCapture` kontraktnak
  (`lib/core/camera/camera_capture.dart` + `plugin_camera_capture.dart` +
  `fake_camera_capture.dart`) facing paramétert kell kapnia egy jövőbeli,
  saját mutáció-tesztelt körben, mielőtt a wizard preferenciája ténylegesen a
  kért kamerát nyitná. `visionSetupEnabled` ma is OFF minden környezetben,
  tehát ez a rés éles felhasználót ma nem érint.

**STOP:** ha a kör csak úgy lenne zöld, hogy egy meglévő teszt módosul, vagy a
skip-út sérül — dokumentált brief-revízió, nem mércegyengítés.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r08-vision-setup-wizard-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
