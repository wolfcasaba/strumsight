# E05-R08 — Vision setup wizard, camera profile és permission UX

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 8; §12.2–12.3, §13.1–13.2
- **Branch:** `minimax/e05-r08-vision-setup-wizard`
- **Előfeltétel:** **E05-R04, E05-R05, E05-R06, E05-R07 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** MiniMax M3 (UI-dominált kör, ADR 0069 mért szabály)

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

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R04/R05/R06/R07 merge; olvasd
> újra `AGENTS.md` (**§15.6 MiniMax-szabály**), a `lib/app/routing/app_route.dart`
> mai route-katalógusát, a `route_guards.dart` flag-őreit, és egy meglévő
> wizard-mintát (`lib/features/practice/presentation/screens/`).
> Nincs ÚJ ADR (0161/0162/0164 bővítése). PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl vagy contract → **azonnal
`stopped`**, nem „kis kiegészítés".

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

## 1. Cél

Vezetett, **kihagyható** és privacy-tudatos kameraelhelyezési flow: 3–5 lépés,
profilválasztás, kamera-választás, permission-UX minden állapotra, és mindenhol
elérhető **audio-only továbblépés**.

## 2. Jelenlegi állapot (mért, `5d082dc` + megelőző körök)

- A `lib/app/routing/app_route.dart` **statikus katalógus** (`AppRoutes`), a
  `shellTabs` a live/analyze/learn/library/settings ötös. A vision **nem** kap
  shell-tabot ebben a körben.
- `lib/app/routing/route_guards.dart` a flag-alapú route-őrzés helye — a vision
  route-ok `visionEnabled && visionSetupEnabled` mögé kerülnek.
- Az E05-R04 `CameraPermissionState` öt állapota + `failure` térképe kész, de
  **UI nélkül**; ez a kör adja az UI-t (a R04 §1 scope-megjegyzése szerint).
- `lib/l10n/app_en.arb` / `app_hu.arb` a két nyelvi forrás; a paritást a
  `test/core/l10n_parity_test.dart` méri (meglévő őr).
- A `leftHanded` beállítás **létezik**: `StorageKeys.leftHanded`
  (`ss.settings.left_handed`) — a setup ezt olvassa, és korrigálhatóvá teszi.

## 3. Scope

**Benne:** setup state machine (`VisionSetupController`) + képernyő, a négy
profil (`leftHandFocus`, `rightHandFocus`, `fullUpperBody`, `balanced`),
kamera-ábra overlay profilonként, front/back választás + switch-restart,
permission-panel (denied / permanentlyDenied → Settings CTA / restricted /
unavailable), privacy-állapot kijelzés („helyben dolgozunk fel, nem rögzítünk"),
Skip → audio-only CTA, a **profil és a kamera** perzisztálása, en/hu ARB.

**Kívül — TILOS:** kalibrációs anchor-editor (R11), quality assessor (R09),
landmark/inference, raw kép mentése, új storage-kulcs a profilon és a kamerán túl,
shell-tab hozzáadása.

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
| `lib/app/routing/app_route.dart`, `app_router.dart` | meglévő | **csak** új vision route + guard |
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
2. **Permission csak explicit gombnyomásra kérődik** (ADR 0161) — `initState`,
   provider-build vagy route-belépés **nem** kérhet engedélyt. **NEM
   elfogadható:** „a felhasználó úgyis a setupba jött" indoklás.
3. **A `permanentlyDenied` és `restricted` állapot Settings CTA-t kap**, nem
   újra-kérést; az `unavailable` **nem** viselkedhet `denied`-ként (más szöveg,
   nincs „próbáld újra" gomb, ami sosem segít).
4. **Perzisztálás:** kizárólag a választott **profil** és a **kamera-azonosító
   absztrakció** mentődik (`ss.vision.setup_profile`, `ss.vision.camera`),
   raw kép vagy preview-screenshot **soha** (ADR 0166).
5. **Nincs domainbe szivárgó Flutter típus:** a `vision_setup_profile.dart`
   framework-mentes (architektúra-őr méri).
6. **Minden felhasználói szöveg ARB-ból jön** — hardcode-olt magyar/angol
   mondat a widgetben BLOCKER.

## 6. Acceptance criteria

- [ ] **Permission-mátrix widget-teszt, cellánként:** granted → tovább;
      denied → kérés-gomb; permanentlyDenied → **Settings CTA** (nincs
      újra-kérés gomb); restricted → Settings CTA; unavailable → magyarázó
      állapot **kérés-gomb nélkül**. Mind az öt külön teszt.
- [ ] **Profil-mátrix:** mind a négy profil kiválasztható, mindegyikhez más
      frame-guide rajzolódik, és a `leftHanded` beállítás a `leftHandFocus`/
      `rightHandFocus` ajánlott értékét befolyásolja, de **felülírható**.
- [ ] **Skip-teszt minden lépésről** (lépésenként egy cella): a Skip után az
      audio-only CTA elérhető, és nem indul kamera (a fake capture `start`
      számlálója 0).
- [ ] **Camera switch:** front↔back váltás a coordinatoron át **close→open**
      sorrendben történik; a teszt méri, hogy egyszerre nincs két lease.
- [ ] **Perzisztencia-teszt:** csak a profil + kamera kulcs íródik; a store
      tartalma ellenőrizve — **más kulcs nem jelenik meg**.
- [ ] **Lokalizációs paritás:** `test/core/l10n_parity_test.dart` zöld, minden
      új kulcs en+hu.
- [ ] **Flag-teszt:** `visionEnabled=false` esetén a route nem elérhető
      (guard), és a mai route-ok viselkedése változatlan.

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

**STOP:** ha a kör csak úgy lenne zöld, hogy egy meglévő teszt módosul, vagy a
skip-út sérül — dokumentált brief-revízió, nem mércegyengítés.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r08-vision-setup-wizard-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
