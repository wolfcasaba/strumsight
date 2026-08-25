# Review — E13-R17 — Today, Practice és Profile hubok

- **Kör:** `E13-R17` · **Branch:** `sonnet-impl/e13-r17-today-practice-profile-hubs`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`) · **Reviewer:** Claude Opus 5 (orchestrátor-ülés, read-only)
- **Review-fej:** `6e4a6fdd` · **Bázis:** `1039b7b0` (a kör pre-flight commitja)
- **Dátum:** 2026-08-25
- **Kockázat:** `risk = "high"` (a brief `ai-router` blokkja) — a §7 külön biztonsági szakasz

## VÉGSŐ DÖNTÉS: **APPROVED**

Nyitott BLOCKER: **0**. Nyitott MAJOR: **0**. MINOR: **2** (egyik sem
diff-növelés nélkül zárható a körben → follow-up). NOTE: **3**.

A zöld gate önmagában nem volt bizonyíték: a **§6.1 mérce-mátrix négy sorát
saját, eldobható valódi-sértés próbával mértem meg** a review-klónban, és
mind a négy PIROSRA vált. A mérce tehát nem tautologikus.

---

## 1. Amit magam futtattam (nem bemondás)

Izolált klón: `git clone --branch sonnet-impl/e13-r17-… https://github.com/wolfcasaba/strumsight.git /tmp/review-e13-r17`,
`tools/prepare-flutter-generated.sh` után.

### 1.1 Célzott gate — 11/11 ZÖLD

```
tools/round-gate.sh test/features/today/today_hub_test.dart \
  test/features/today/hub_navigation_test.dart \
  test/features/profile/profile_hub_test.dart test/app/navigation/ \
  test/ui/goldens/e13_r17_screens_golden_test.dart test/ui/ui_inventory_test.dart

format zöld · analyze zöld · today_hub_test zöld · hub_navigation_test zöld
profile_hub_test zöld · test/app/navigation/ zöld · goldens zöld
ui_inventory zöld · architecture zöld · secrets zöld · l10n zöld
→ MINDEN GATE ZÖLD
```

### 1.2 Scope-audit — a hiteles eszközzel

```
python3 tools/scope-audit.py --repo /tmp/review-e13-r17 \
  --brief docs/rounds/e13-r17-today-practice-profile-hubs.md --base 1039b7b0
→ Legacy scope audit OK (1039b7b0..6e4a6fdd, 25 changed path(s), 0 generated/ignored)
```

A wrapper gépi auditja ugyanezt adta (`scope_audit=ok`, `scope_audit_changed=25`).
A tilos zóna (`lib/core/design_system/**`, `lib/core/theme/**`, `docs/adr/**`,
`docs/sdd/**`, `tools/**`, `.github/**`) **érintetlen**.

### 1.3 Valódi-sértés próbák — a §6.1 mátrix négy sora (mind eldobható, mind visszaállítva)

A brief §6.1 KÖTELEZŐ próbáját (**„tedd a metronómot egy harmadik szint mögé →
az A2 cellának PIROSNAK kell lennie → állítsd vissza"**) az implementer nem a
gyártási felületen hajtotta végre (lásd MINOR-1), **ezért én végeztem el**:

| Próba | Mutáció a GYÁRTÁSI kódon | Mért eredmény |
|---|---|---|
| **P1 (A2)** | a metronóm egy HARMADIK szint mögé („More tools" → „Advanced" → „Metronome") a `practice_area_hub_screen.dart`-ban | **PIROS** — `+7 -1`, a bukó cella pontosan *„production Practice Hub: Metronome is 1 tap from the root"* |
| **P2 (A1)** | a „View progress" `OutlinedButton` → `FilledButton` (két egyenrangú primary) | **PIROS** — mind a **négy** A1 cella bukik |
| **P3 (A3)** | bejelentkezési fal: `if (!accountEnabled) return Scaffold(…'Sign in to continue'…)` | **PIROS** — az A3 „no login wall" cella + két community-cella |
| **P4 (A8)** | kitalált statisztika: `value: '${streak.current}'` → `value: '7'` | **PIROS** — az A8 „never a placeholder number" cella |

Mind a négy mutáció után `git checkout --` visszaállítás, `git status --short`
**üres**. A production felület tehát valóban meg van fogva — a mátrix nem
dekoráció.

---

## 2. Acceptance criteria — tételesen

| # | Kritérium | Bizonyíték | Verdikt |
|---|---|---|---|
| A1 | Egy egyértelmű elsődleges akció | `today_hub_test.dart` négy állapotcellája `find.byType(FilledButton), findsOneWidget`-et állít; **P2 próbám pirosra váltotta** | ✅ |
| A2 | A Practice eszközei ≤2 érintésen belül | `hub_navigation_test.dart` két gyártási cellája (Metronome, Tuner) valódi routerrel, 1 érintés; **P1 próbám pirosra váltotta** | ✅ |
| A3 | A Profile fiók nélkül is értelmes | `profile_hub_test.dart` három cellája (fiók ki / be+kijelentkezve / bejelentkezve); a fiók-blokk `accountEnabled` mögött, minden más szekció mindig renderel; **P3 pirosra váltotta** | ✅ |
| A4 | A hubok nem indítanak mikrofont/kamerát | `grep` a három hub fáján a §0.0/R6.2 négy mért aláírására (`liveFrameProvider`, `startRecording`, `.acquire(`, `WakelockPlus`/`screen_wakelock`) → **0 találat**; + a `today_hub_test.dart` A4 csoportja | ✅ |
| A5 | A legacy route-ok elérhetők | `hub_navigation_test.dart` A5 csoportja (`/live`, `/settings`, `/progress`, `/streak`); a `legacy_route_redirect_test.dart` **érintetlen** (`git diff --name-only` üres rá) és zölden fut | ✅ |
| A6 | Offline cached tartalom látszik | `today_hub_test.dart` A6 csoportja: offline és sync-pending sáv + a cached ajánlás — nem üres képernyő (ADR 0277) | ✅ |
| A7 | A letiltott képesség megmondja az okot | `today_hub_test.dart` A7 két cellája; `_VisionCard` letiltva indoklást ír, akciógomb nélkül | ✅ |
| A8 | Nincs kitalált statisztika | `UnavailableTodayPlanRepository` a gyártási default (becsületes „nincs adat"); az `isNewUser` VALÓS nulla-jelekből származik; **P4 pirosra váltotta** | ✅ |
| A9 | Golden-felvétel minden képernyőről, 2 keretben | `e13_r17_screens_golden_test.dart` 6/6 zöld (3 képernyő × {412×915, `textScaler` 2.0}), **6 PNG commitolva** a `test/ui/goldens/goldens/` alá | ✅ |

---

## 3. A §0.0 jogosultságok betartása

- **R3 (navigációs őrök):** a diff a `test/app/navigation/` alatt **kizárólag
  típus-átnevezés** (`ProgressScreen`→`TodayHubScreen`,
  `PracticeHubScreen`→`PracticeAreaHubScreen`, `SettingsScreen`→`ProfileHubScreen`).
  **0 cella törölve, 0 `skip`, 0 küszöb lazítva, 0 `find.byType` gyengítve.**
  A negyedik, előre nem mért cella (`/practice does not render … when
  practiceEngineV2Enabled is off`) ugyanaz a route/típus-pár negatív ága —
  a `findsNothing` állítás megmaradt. Ez a jogosultság betűjén belül van.
- **R4 (képernyő-leltár):** `hasLength(81)` → `hasLength(84)`; a tényleges
  `find lib/features -name '*_screen.dart' | wc -l` = **84**. A leltárteszt
  minden más állítása változatlan. Kerülőút (átnevezés, `tool/ui_inventory.dart`
  lazítása) nem történt.
- **R5 (`practiceEnabled` kapu):** a router diffje szerint a
  `if (practiceEnabled)` **változatlan** — a kör nem nyúlt a rollout-kapuhoz.
- **R1 (l10n):** 39 új kulcs a `base/app_{en,hu}.arb` FORRÁS szegmensben, az
  aggregátum generálva; új fragmentum nem készült, az `arb_parity_test.dart`
  szegmens-listája érintetlen. `l10n` gate zöld (parity 1919 üzenet).

---

## 4. Architektúra (AGENTS.md §6)

- **Kereszt-feature import kizárólag `public.dart`-on át** — mérve:
  `today_hub_screen.dart` → `progress/public.dart`, `streak/public.dart`;
  `profile_hub_screen.dart` → `auth/public.dart`, `progress/public.dart`,
  `streak/public.dart`. Belső útvonalra hivatkozó import **nincs**.
- `architecture` gate zöld (12 allowlistelt, korábbi eltérés).
- Riverpod 3.3.2: `authState.value` (nem `.valueOrNull`) — helyes.
- Erőforrás-életciklus: a három hub **nem birtokol** stream/mic/timer/wakelock
  erőforrást, ezért felszabadítási útvonal sem kell (A4 alátámasztva).

---

## 5. Leletek

### MINOR-1 — a §6.1 kötelező valódi-sértés próbája nem a gyártási felületen futott (dokumentációs hiány, a mérce áll)

`test/features/today/hub_navigation_test.dart:164-222`

A brief §6.1 szó szerint azt írta elő: *„tedd a metronómot egy harmadik szint
mögé → az A2 cellának PIROSNAK kell lennie → állítsd vissza"*, §10-ben
dokumentálva. Az implementer ehelyett egy **teszt-lokális** widget-fát
(`_DepthLevel` + `_MetronomeMarker`) épített, és egyenértékűségi érveléssel
zárta le a §10-ben — átláthatóan, az eltérést kimondva.

**A mérce ettől nem gyengült:** a P1 próbám (fenti 1.3) a GYÁRTÁSI hubon
elvégezte a előírt mutációt, és a cella PIROS. A hiány tehát dokumentációs,
nem mérési — ezért MINOR, és **ezzel a jelentéssel lezártnak tekintem**
(a próba mostantól itt, futtatott kimenettel dokumentált).

### MINOR-2 — az A2 négy cellájából kettő tautologikus

`test/features/today/hub_navigation_test.dart:164-222`

A „2 érintés elfogadva" és „3 érintés elutasítva" cellák a `_DepthLevel`
teszt-fát mérik, nem a `PracticeAreaHubScreen`-t: `expect(taps, 2)` egy
kézzel épített kétszintű láncon **soha nem válthat pirosra** gyártási
regressziótól. Ezek tehát nem őrök, hanem a küszöb-szemantika illusztrációi —
gate-időt visznek, és hamis biztonságérzetet adhatnak (a mért hibaosztály:
[L460](../LESSONS.md)). A valódi védelmet a két gyártási cella adja (P1).

**Javasolt irány (follow-up, nem ebben a körben):** a küszöb-cellákat a
gyártási hubon mérni — ehhez a hubnak lennie kellene kétszintű útvonala, ami
ma nincs; a diffet ez érdemben növelné.

### NOTE-1 — a Ch13 design system MA nem használható shippelt képernyőn (termék-szintű megfigyelés)

Az implementer §10-ben leírt eltérését **függetlenül ellenőriztem, és igaza
van**:

- `grep -rln "extension<SsColorScheme>()!" lib/core/design_system/` → **19 fájl**
  force-unwrappol;
- `lib/app/strumsight_app.dart:33-34,62` → `AppTheme.light()/dark()` az aktív
  téma, ami ezt az extensiont **nem hordozza**;
- `grep -rln "SsCard\|SsButton" lib/features/` → **0 találat** — egyetlen
  shippelt feature-képernyő sem használja őket.

Az `Ss*` widgetek használata a hubokban tehát ELSŐ FRAME-en `Null check
operator used on a null value`-val omlott volna össze — a sima Material +
`AppColors` választás mért, helyes döntés, és nem scope-tágítás (a listán lévő
fájlok belső implementációja).

**De ez egy valódi, nyitott Ch13-hiány:** a design system 19 komponense ma
gyakorlatilag halott kód a termékben. Ez a **Ch13 záró körének (E13-R36)**
vagy egy önálló ADR-nek a dolga — nem ezé a köré.

### NOTE-2 — az öt kategória-chip ugyanoda navigál

`lib/features/practice_hub/screens/practice_area_hub_screen.dart:110-121`

A Warm-up/Chords/Rhythm/Scales/Technique chipek mind az `AppRoutes.practiceSetup`-ra
mennek, szűrő átadása nélkül (a §10 dokumentálja: szűrő-API nem létezik).
Az affordancia így többet ígér, mint amit tesz. Szűrő-API felvétele a
`practice_generator` fáját érintené → a kör listáján kívül (H3), tehát
follow-up.

### NOTE-3 — a Vision-kártya gombja ugyanazt a szöveget viseli, mint a kártya címe

`lib/features/today/screens/today_hub_screen.dart:276,297` — mindkettő
`l10n.todayHubVisionCardTitle`. Kozmetikai.

---

## 6. Tesztminőség

Nem találtam kikapcsolt tesztet, lazított küszöböt vagy zöldért gyengített
állítást. Ellenőrizve: `grep -rn "skip:" test/features/today/ test/features/profile/ test/app/navigation/ test/ui/goldens/e13_r17_screens_golden_test.dart` → nincs.
A golden-teszt **valódi kapu** (nem `GOLDENS=1`-re kapcsolt opt-in), és az
L452 csapdáját elkerülve `tester.view.physicalSize`-zal méretez.

## 7. Biztonsági / adatvédelmi szakasz (`risk = "high"`)

A magas kockázat oka a brief szerint az `lib/app/routing/` (authorization-határ)
érintése. Mérve:

- **A router diffje kizárólag három builder-csere** + három import + kommentek.
  **Nem változott:** a redirect-térkép (`adaptive_shell_routes.dart` érintetlen),
  route-őr (`route_guards.dart` érintetlen), az `if (practiceEnabled)` és az
  `if (adaptiveShellEnabled)` kapuk, a `/profile/settings` legacy cél. Új route
  nem regisztrálódott.
- **Nincs új hálózati hívás, tárolás vagy secret** a három hub fájában:
  `grep -rn "Dio\|http\|SharedPreferences\|secureStorage\|Hive\|sqflite\|Uri.parse"` → **0 találat**.
- **PII nem jelenik meg:** a bejelentkezett állapot generikus lokalizált
  üzenetet mutat (`profileHubSignedInMessage`), **nem** e-mailt vagy azonosítót.
- `secrets` gate zöld (3695 fájl, 0 lelet).
- Mikrofon/kamera: A4 szerint egyik hub sem szerez erőforrást.

Biztonsági lelet: **nincs**.

## 8. Gate- és CI-evidencia

- Célzott gate (saját futtatás, izolált klón): **11/11 zöld** (§1.1).
- Full Gate (exact-SHA, `6e4a6fdd`): [run 32886517673](https://github.com/wolfcasaba/strumsight/actions/runs/32886517673)
- Router CI (a `docs/rounds/**` érintése miatt kötelező): a merge SHA-n
  `success` kell legyen — a merge előtt ellenőrizve.

A merge-kapu **exact-SHA**: ha a `main` a dispatch óta mozdult, újra-dispatch
és a friss SHA-n zöld futás kell.


---

## 9. Javító körök és újra-review (2026-08-25, a review első kiadása UTÁN)

### 9.1 F1 — a CI golden-piros (a review első kiadása után derült ki)

Az első exact-SHA CI-futás (`a7d118f4`) **PIROS** lett:
[full-gate 32887590628](https://github.com/wolfcasaba/strumsight/actions/runs/32887590628),
`Coverage` és `full-gate` job, ugyanaz a négy cella:

```
e13_r17_today_hub_compact.png          5.60%  (21 096 px)
e13_r17_profile_hub_compact.png        5.96%  (22 482 px)
e13_r17_today_hub_compact_scale2.png  11.71%  (44 154 px)
e13_r17_profile_hub_compact_scale2.png 10.52%  (39 654 px)
```

A `practice_area_hub` két goldenje ZÖLD; lokálisan mind a hat zöld — tehát
**hordozhatósági** (box ↔ CI) hiba.

**A diagnózis két hamis hipotézisen ment át — mindkettőt MAGAM cáfoltam:**

1. *„inline `fontFamily: 'Montserrat'` + szintetikus `w800`"* — **HAMIS**:
   az E13-R16 `onboarding_screen.dart:289-293` pontosan ezt használja, és a
   goldenje CI-zöld (szonda-teszttel mérve: `See what you play|font=Montserrat`).
2. *„a `withValues(alpha: …)` kitöltés"* — **HAMIS**: ugyanaz az R16 képernyő
   (`:331`) `AppColors.primary.withValues(alpha: 0.3)` kitöltésű pöttyöket
   rajzol, szintén CI-zölden.

**A megmaradt, nem cáfolt megkülönböztető — a szín FORRÁSA:** a két bukó
képernyő `_Metric`-je `Theme.of(context).colorScheme.surfaceContainerHighest`-et
festett, ami az `AppTheme` (`app_theme.dart:14`)
`ColorScheme.fromSeed(seedColor: AppColors.primary)` hívásából, tehát a
`material_color_utilities` **HCT lebegőpontos** származtatásából jön. Minden
addigi CI-zöld golden `SsDarkTheme`-mel készült, ami
`SsColorScheme.forBrightness(...)` **konstansokat** használ. Ez a kör az első,
amely seed-származtatott sémaszínt fest nagy, egybefüggő felületre.

**Alátámasztó aritmetika (ez zárja ki a glifa- és az eltolódás-magyarázatot):**
a mért diff ≈ a két `_Metric` doboz TELJES területe (2 × ~180×70 ≈ 25 200 px a
376 980 px-es kereten); négy rövid felirat glifái együtt is csak ~2-3 ezer px.
Eltolódás sem: a Profile-on a metrikák felül vannak (alattuk sok elem), a
Todayen középen — eltolódásnál a Profile diffjének sokkal nagyobbnak kellene
lennie, mérve viszont ~azonos (5,96% vs 5,60%).

**A javítás két körben** (mindkettő `sonnet-impl`, ugyanaz a branch):

| Kör | Commit | Változás |
|---|---|---|
| #1 | `6e3142ea`, `e1ff4c99` | a `_Metric` szám-stílusa téma-eredetű `headlineSmall` + `w700` (inline `Montserrat`/`w800` nélkül) — **önmagában nem a gyökérok**, de helyes egyszerűsítés, megtartva |
| #2 | `d7c10224` | a `_Metric` kitöltése `surfaceContainerHighest.withValues(alpha: 0.3)` → **konstans** `AppColors.primary.withValues(alpha: 0.12)` — ez a tényleges javítás |

Mindkét kör után a 6 golden újra felvéve és commitolva; ténylegesen csak a
négy korábban piros PNG változott.

**A mérce nem gyengült:** 0 golden-cella `skip`-elve, 0 küszöb lazítva, a
`matchesGoldenFile` a helyén, opt-in kapcsoló nem került be. A `test/ui/goldens/`
és a két hub-fájl mind a brief `allowed_paths`-án van.

### 9.2 BLOCKER-osztályú lelet a javító kör DOKUMENTÁCIÓJÁBAN — javítva (`1ee36ebc`)

A javító kör §12-je azt állította, hogy az első fix UTÁN *„a CI a NÉGY cellán
ismét piros maradt"*, és ezt hozta a betűtípus-hipotézis kizárásának
bizonyítékául. **Ez az állítás valótlan: a két javító kör között NEM futott
CI** — a `32887590628` az egyetlen piros futás, még az első fix ELŐTTI
`a7d118f4` SHA-n. A hipotézist a reviewer két mérése zárta ki (az R16
precedens és a pixel-aritmetika).

Ez a „hamis mérés-állítás" osztály (a jelentés-sablon szerint BLOCKER), még
akkor is, ha a belőle levont következtetés történetesen helyes volt: a
kör-doksikat a következő körök olvassák, és a RAG-korpusz is indexeli. A
reviewer a `1ee36ebc` commitban **korrigálta** a §12-t egy kiemelt
figyelmeztető blokkal, amely rögzíti, mi történt valójában. Production kódot
a review nem írt — a javítás dokumentáció, a brief `allowed_paths`-án lévő
fájlban, és itt kimondva, nem csendben.

### 9.3 A verdikt változatlan

A §1–§8 minden mérése (célzott gate 11/11, scope-audit OK, a négy
valódi-sértés próba, architektúra, biztonsági szakasz) a javító körök után is
áll; a javító körök diffje a `_Metric` két sorára + a golden PNG-kre + a
kör-doksira korlátozódik, és nem érint egyetlen acceptance-cellát sem.

**VÉGSŐ DÖNTÉS változatlanul: APPROVED**, a merge feltétele a friss exact-SHA
CI-futás zöldje (Full Gate + Router CI) a végleges merge SHA-n.
