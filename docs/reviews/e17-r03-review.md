# Review — E17-R03 (A Song Trainer setlist-session bekötése, V2-natív)

- **Kör:** `E17-R03` · **Brief:** [`docs/rounds/e17-r03-setlist-session-wiring.md`](../rounds/e17-r03-setlist-session-wiring.md)
- **ADR:** [`0585`](../adr/0585-setlist-session-v2-native-entry-and-measured-outcome.md)
- **Ág / diff:** `sonnet-impl/e17-r03-setlist-session-wiring`, `b2cbd029..c6980fa0` (22 fájl, +1183 / −35)
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`) · **Reviewer:** Claude (Opus 5), read-only
- **Review-példány:** friss `/tmp/review-e17-r03` klón az origin `c6980fa0` HEAD-jén (a közös munkafán próba NEM futott)

## VÉGSŐ DÖNTÉS: az implementáció **APPROVED** (0 nyitott BLOCKER/MAJOR a diffben),
## de a kör **NEM MERGE-ELHETŐ**: `H3` — l. a §10-et

A CI a merge SHA-n egyetlen cellán piros, és a gyökérok **a brief scope-ja**,
nem az implementáció. A feloldás `allowed_paths`-tágítást kíván, ami az
ADR 0087 §2 szerint nem a kör-orchestrátor hatásköre.

---

## 1. Jelzés és handoff

`.codex-round-status`: `status=done`, `head=c6980fa0`, `scope_audit=ok`,
`gate_shape=ok`. A `dirty_files=1` a jelzés pillanatában a gitignore-olt
`test/ui/goldens/failures/` könyvtár volt; a mérés idejére `git status`
üres, a könyvtár nincs meg. A brief §10 handoffja kitöltött, és — szemben a
mért hibamintával — **nem bemondás**: minden állítása mellé odaírja a
futtatott parancsot és annak kimenetét.

**Az első futás `stopped`/`VIOLATION` jelzése az orchestrátor hibája volt, nem
az implementeré:** a scope-audit a `.round-prompt.md`-t kifogásolta, amit ÉN
másoltam a munkapéldány gyökerébe. A fájl eltávolítása után a teljes körre
vett audit tiszta:

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e17-r03 \
    --brief docs/rounds/e17-r03-setlist-session-wiring.md --base b2cbd029
Legacy scope audit OK (b2cbd029c388..c6980fa0b5db, 22 changed path(s), 0 generated/ignored)
```

A második (időkorlát miatti) dispatch folytatás volt, nem újrakezdés — az
implementer `implementer_status=timeout`-tal halt az első menetben a
golden-felvétel közben, egyszer. (H6 küszöb: KÉT halál `unknown`/`stalled`
állapotban — nem ért el odáig.)

## 2. Gate — SAJÁT kézzel újrafuttatva

Izolált klónban, csonkítatlanul, a golden-útvonalak nélkül (l. M2):

```
$ tools/round-gate.sh test/features/song_trainer/ test/features/songs/setlist_list_test.dart \
    test/features/songs/song_library_test.dart test/e2e/song_trainer_walkthrough_test.dart \
    test/app/navigation/ test/app/routing/ test/tooling/screen_reachability_test.dart \
    test/tooling/route_literal_guard_test.dart test/l10n/
GATE_EXIT=0 — mind a 14 lépés ZÖLD (format, analyze, 9× test, architecture, secrets, l10n)
```

## 3. Acceptance criteria — tételesen

| # | Bizonyíték | Verdikt |
|---|---|---|
| A1 | `check_screen_reachability --format json`: `SetlistSessionScreen reachable=true`, imperatív hivatkozás `setlist_list_screen_v2.dart:115` | ✅ |
| A2 | ugyanaz: `SetlistListScreenV2 reachable=true`, deklaratív `app_router.dart:767`, `flagGated=true [songTrainerEnabled]`; + `A2` widget-cella a belépési akcióra | ✅ |
| A3 | `A3/A4` cella VALÓS `ProviderContainer`-rel (`songRepositoryProvider`/`setlistRepositoryProvider` override), valós seed-dokumentummal, a valós `SetlistSessionScreen`-re | ✅ |
| A4 | ugyanaz a cella mindkét módra; a `_startSession(setlist, mode)` EGYETLEN indító metódus, egyetlen új route-konstans | ✅ |
| A5 | `A5` cella üres repository-val — **saját próbám igazolta** (l. §4) | ✅ |
| A6 | `A6/§6.1` cella — **saját próbám igazolta** (l. §4) | ✅ |
| A7 | `A7` cella: a session elhagyása a V2 listára tér vissza, nem a gyökérre | ✅ |
| A8 | `test/tooling/screen_reachability_test.dart` teljes egészében zöld (A3 cellástul); a `retirement-plan.md` két sora ÉS a §3.4 felsorolás átvezetve | ✅ |
| A9 | `test/l10n/` zöld + a gate `l10n` lépése: „L10n aggregate freshness OK (en, hu)", „L10n parity OK (en → hu, 2376 message(s))" | ✅ |
| A10 | `test/tooling/route_literal_guard_test.dart` zöld; az új útvonal `AppRoutes.songTrainerSetlists` konstans | ✅ |
| A11 | `git diff b2cbd029..c6980fa0 -- lib/app/config/feature_flags.dart` ÜRES; `songTrainerV2Enabled: nonProd` változatlan | ✅ |

Mért összesítő: **97 képernyő, 96 elérhető, 1 elérhetetlen** (`PracticePlanPreviewScreen`
— az E17-R04 tárgya). A kör indulásakor 3 volt elérhetetlen.

## 4. Saját, eldobható próbatesztek (a zöld gate NEM bizonyíték)

Mindkettőt ÉN futtattam a `/tmp` klónon, az implementer jelentésétől
függetlenül, majd visszaállítottam (`git diff --stat` üres):

**P1 (A6) — a runner kimenete fix `completed`-re cserélve:**

```
00:03 +3 -1: A6/§6.1 — leaving a pushed session before it reports a result never
             produces a synthesized completed … [E]
Expected: exactly one matching candidate
  Actual: _TextContainingWidgetFinder:<Found 0 widgets with text containing Completed 0 of 1: []>
```

Csak ez az egy cella váltott pirosra (a másik 4 zöld maradt).

**P2 (A5) — a resolver konstans `ready`-re cserélve:**

```
00:02 +2 -1: A5 — a song missing from the real repository index is skipped as
             missingSong … [E]
Expected: false
  Actual: <true>
```

Szintén pontosan egy cella. **A két őr tehát valóban harap** — nem
tautológia, és a brief §6.1 két kötelező falszifikációs próbája ezzel
függetlenül reprodukált.

## 5. Doc-comment-állítások — tesztben/kódban bizonyítva

A motor doc-commentjei mért állításokat tesznek; mindet visszamértem:

| Állítás | Mérés | Verdikt |
|---|---|---|
| „`TrainerMode.pitch` az első ágon feltétel nélkül playback-only" | `song_practice_compiler.dart:52-54` — `if (config.mode == TrainerMode.pitch) return const SongPracticeCompilation.playbackOnly();` közvetlenül a `_validateIdentity` után | ✅ igaz |
| „`TrainerMode.rhythm` alatt chord/strum/note MIND scored definíciót fordít" | `:57-60` csak `BackingAudioTrack`/egyéb kindre esik playback-onlyra; `_profileFor` (`:236-263`) minden ágon scored profilt ad (kifutó ág: `strumPattern`) | ✅ igaz |
| „playback-only sessionre SOHA nem tüzel `NavigateToSongTrainerResult`" | `song_trainer_controller.dart:386-388` — `_finishAndFinalize` azonnal visszatér, ha `_practiceSession?.state.status != completed` | ✅ igaz |
| `controller.isPlaybackOnly` / `controller.states` létezik | `song_trainer_controller.dart:122`, `:133` | ✅ igaz |

## 6. Architektúra és termékhatárok

- `tool/check_architecture.dart` zöld (12 allowlistelt eltérés, változatlan szám).
- A router-builder `Consumer`-rel köt a meglévő providerekhez — **nincs új
  provider-híd**, és nincs cross-feature import a `songs` felé (a §0.1/R4
  korlátja betartva).
- A `public.dart` bővítése a képernyő + két provider exportjára szorítkozik.
- **Erőforrás-életciklus:** a `_states` StreamSubscription a `dispose`-ban
  lezárul (`song_trainer_session_route.dart`), a `_outcomeReturned` őr pedig
  kizárja a kettős `pop`-ot.
- **Az egydalos út érintetlen:** a `returnResultToCaller` alapértéke `false`,
  és a regisztrált `songTrainerSession` `GoRoute` builder-e nem állítja —
  a setup→session→result út, a „practice again" és a fail-closed
  `extra`-redirect bit-azonos.

## 7. Leletek

### MINOR

**M1 — a §5.4 betű szerinti eltérése: `MaterialPageRoute` a
`AppRoutes.songTrainerSession` helyett.**
`setlist_session_providers.dart::_runSetlistItem` a valós
`SongTrainerSessionRoute`-ot **nyers `Navigator.of(context).push(MaterialPageRoute(...))`-szal**
nyitja meg, míg a brief §5.4 szövege a *regisztrált* útvonalat nevezi meg.
Mérve, mi a tényleges költsége:

- az `if (songTrainerEnabled)` blokk a `routes:` **legfelső szintjén** áll
  (a `ShellRoute` a testvére, `app_router.dart:417`), tehát a
  `Navigator.of(context)` a GYÖKÉR navigátort adja → az E13-R08
  shell-branch-életciklus csapda **nem** aktiválódik;
- a `GoRouter`-en **nincs `observers:` lista**, tehát nincs kihagyott
  analitika/megfigyelő;
- a `_songTrainerPayloadRedirect` fail-closed őr tárgytalan: a widget
  közvetlenül, tipizált argumentumokkal épül, nem `extra`-ból;
- a **kódbázis SAJÁT bevett mintája ugyanez**: imperatív `MaterialPageRoute`
  push van a `settings_screen.dart:76-101` (ahol a doc-comment kimondottan
  döntésként rögzíti: „no new route registered (B5)"), a
  `setlist_list_screen.dart:23`, `setlist_detail_screen.dart:23`,
  `song_list_screen.dart:22`, `progress_screen.dart:79`, `streak_screen.dart:135`
  útvonalain is;
- a `check_screen_reachability` ezt a hivatkozást **méri** (imperatív
  referencia), tehát az A1 bizonyítéka nem gyengül.

Létezett a listán belüli alternatíva is (burkoló `extra`-típus a megengedett
`song_trainer_session_route.dart`-ban + egy builder-ág a megengedett
`app_router.dart`-ban), tehát „kényszer" nem volt — de mért viselkedésbeli
különbség sincs. **Feloldás: dokumentálás, nem átdolgozás** — a §5.4
NORMATÍV tartalma (a launcher használata + a státusz a session tényleges
kimenetéből + szintetizálás tilalma) maradéktalanul teljesül, és gépi őr
méri (P1). Egy zöld, őrzött implementáció átdolgozása mért nyereség nélkül
csak diffet hizlalna.

**M2 — a brief §7 / `gate_tests` sora ütközött az ADR 0426-tal (a brief hibája,
nem az implementációé).** A §7 gate-parancs és a `gate_tests` lista három
golden-útvonalat (`e13_r23`, `e13_r25`, `e15_r13`) is a
`tools/round-gate.sh` argumentumai közé fűzött, holott az
[ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md) 3.
pontja szó szerint kimondja: *„Golden-teszt-útvonal nem kerül a lokális
`tools/round-gate.sh` `gate_tests` listájára"* — az ARM-natív futás ezekre a
cellákra a rossz gépet méri. Ez az L516-ban NEVESÍTETT hibaminta (szomszéd
kör briefjéből öröklött sor), és a brief-lint jelenleg nem fogja meg.

Az implementer ezt MÉRTE, a §10.5-ben dokumentálta, a gate-et helyesen a
három útvonal NÉLKÜL futtatta, a goldeneket pedig az ADR által előírt
`tools/golden-x86.sh check`-kel ellenőrizte. **Ez a helyes döntés volt**, és
én ugyanígy futtattam a saját gate-emet. A brief S12-kompatibilitása
(§7 ↔ `gate_tests`) megmarad, mert mindkét helyen szerepelnek — a hiba
mindkettőben ugyanaz. Teendő: lecke a `docs/LESSONS.md`-be; a brief-lint
bővítése külön kör dolga (nem ennek a körnek a scope-ja).

### NOTE

- **N1 — a `requiresMigration` ág szűk, de nem holt.** A setlist-tétel nem
  pinneli a revíziót, és a `_trainerConfigFor` a FRISSEN olvasott dokumentum
  revíziójával épít; a launcher `staleRevision`-je így csak a
  `repository.get` és a launcher saját újraolvasása közti TOCTOU-ablakban
  tüzel. Őszinte (semmi kitalálva), csak ritka.
- **N2 — az `e15_r13` mátrix bővítése helyes irányba ment:** a két új
  képernyő a `_screens` térképbe került, NEM a `_exclusions` listára — az
  továbbra is egyetlen bejegyzés (`WrappedPreviewScreen`), az A5 csoport
  invariánsa sértetlen. A mátrix pumpája 412×915 / DPR 1.0 telefon-viewporton
  mér (`:358`, `:3975-3977`), tehát az [L558](../LESSONS.md) üres-fa csapdája
  itt nem áll fenn.
- **N3 — a pin-cellák bővültek, nem gyengültek:** `setlist_list_test.dart` és
  `setlist_session_controller_test.dart` csak az ÚJ konstruktor-paramétereket
  és a migráció miatt szükséges `theme: SsLightTheme.data()`-t kapta meg; egy
  assert sem törlődött, `skip` nem került be. A bennük lévő „A5/A6" hivatkozás
  a SAJÁT fájljuk celláira utal, nem a brief A5/A6-jára — apró
  olvashatósági ütközés.
- **N4 — az A4 cella a MÓD megérkezését méri, nem azt, hogy nincs második
  `GoRoute`.** Azt a felét a `route_literal_guard` + az egyetlen új
  útvonal-konstans + a diff fedi.

## 8. Design-migráció (D5) — valódi, nem kozmetikus

`setlist_list_screen_v2.dart`: `grep -c design_system` **0 → 1**, és a
használat érdemi: `SsColorScheme`, `SsTypography`, `SsEmptyState`, `SsCard`,
`SsSpacing.space1..4`. ÚJ `*ThemeScope` burkoló nincs (D5 előírása). A
`retirement-plan.md` mindkét sora `yes | yes | keep`-re vezetve, a §3.4
„no measured reference" felsorolásból mindkét képernyő kivéve — a terv és a
mérés együtt mozdult.

## 9. Ami NEM változott (ellenőrizve)

`feature_flags.dart` (A11), `setlist_session_controller.dart` szemantikája,
a legacy `songs` setlist-út, és a `test/tooling/screen_reachability_test.dart`
— utóbbi a kör mérőeszköze, és a diff nem érinti.


---

## 10. MERGE-BLOKKOLÓ — `H3`, és NEM implementációs hiba

### A mérés

`full-gate.yml` run [`35419712787`](https://github.com/wolfcasaba/strumsight/actions/runs/35419712787),
head SHA `5e11eb87` (= a merge SHA): **11185 teszt zöld, 1 piros, 26 skipped**.
A piros cella:

```
❌ test/tooling/placeholder_wiring_test.dart:312
   A4/A5 — the walked set (from actually RUNNING the walkthrough) and the
   excluded table are disjoint, and their union covers every measured
   reachable screen
Expected: empty
  Actual: Set:[
            'lib/features/song_trainer/presentation/screens/setlist_list_screen_v2.dart',
            'lib/features/song_trainer/presentation/screens/setlist_session_screen.dart'
          ]
reachable screens missing from both the walk and the exclusion table (A4)
```

**Ez pontosan a kör SIKERE** ([L612](../LESSONS.md) hibaosztálya): a guard
minden *mért-elérhető* képernyőtől megköveteli, hogy VAGY bejárja a
walkthrough, VAGY szerepeljen a dokumentált kimaradó táblában. A kör két
képernyőt tett elérhetővé, és egyik listán sincsenek.

### Miért nem oldható fel a kör hatáskörén belül

A guard PONTOSAN két bemenetből dolgozik, és **egyik sincs a brief
`allowed_paths`-ában**:

| Bemenet | Hol él | `allowed_paths`-ban? |
|---|---|---|
| a bejárt halmaz — `runCoreWalkthrough` | `test/e2e/full_app_walkthrough_test.dart` (`placeholder_wiring_test.dart:7`) | **NINCS** (a lista csak a `test/e2e/song_trainer_walkthrough_test.dart`-ot engedi) |
| a kimaradó tábla — §3.2 | `docs/release/full-app-verification.md` (`placeholder_wiring_test.dart:275-278`) | **NINCS** |

Maga a `test/tooling/placeholder_wiring_test.dart` sincs sem az
`allowed_paths`-ban, sem a **`gate_tests`-ben** — ezért a lokális, célzott
kapu (és az én reviewer-gate-em is) zölden ment át azon a fán, amit a kör
pirosra visz. A hiba csak a teljes CI-ban, ~40 perccel később derült ki.

**A feloldás tehát `allowed_paths`-TÁGÍTÁS**, ami az ADR 0087 §2 /
`brief-lint` S15 szerint nem a kör-orchestrátor hatásköre → **H3**.

### A precedens: az E17-R01 briefje EZT MÁR MEGOLDOTTA

Ugyanez a fejezet, két körrel korábban, ugyanezzel a hibaosztállyal
találkozott, és a briefje **fel is sorolta mindkét fájlt**:

```
$ grep -n "full_app_walkthrough\|placeholder_wiring" docs/rounds/e17-r01-onboarding-first-win-stage-wiring.md
29:  "test/e2e/full_app_walkthrough_test.dart",          # allowed_paths
43:  "test/e2e/full_app_walkthrough_test.dart",          # gate_tests
56:  "test/tooling/placeholder_wiring_test.dart",        # gate_tests
```

A feloldás ott **bejárás** volt, nem kimaradás (`c455e8ae [E17-R01] …`
módosította a walkthrough-t; a `b7bb53c1 fix(docs): a First-Win állomás
kikerült a §3.2 kimaradó táblából — a main óta BEJÁRT` commit pedig utólag ki
is vette a táblából). Egy megnyitható képernyőnél ez az őszinte irány.

### Javasolt javítás az önjavító körnek (ADR 0112)

1. A brief `allowed_paths`-ába: `test/e2e/full_app_walkthrough_test.dart`
   **és** `docs/release/full-app-verification.md`.
2. A brief `gate_tests`-ébe **és** a §7 gate-parancsba:
   `test/tooling/placeholder_wiring_test.dart` + `test/e2e/full_app_walkthrough_test.dart`
   — enélkül a lokális kapu megint zölden engedi át ugyanezt (a `brief-lint`
   S9 a képernyő-leltár EGYIK őrét, a `screen_reachability_test`-et keresi; ezt
   a MÁSODIK leltár-őrt nem ismeri).
3. A javító kör a két képernyőt **járja be** a `runCoreWalkthrough`-ban (az
   E17-R01 precedense), ne a kimaradó táblába tegye — a `/song-trainer/setlists`
   a `songTrainerEnabled` kapu alatt él, és a Song Library AppBar-akciójából
   nyílik.

### Ami ettől NEM változik

A §1–§9 minden megállapítása áll: a diff scope-tiszta, a 14 lépéses célzott
gate zöld, a két független falszifikációs próba harap, az A1–A11 teljesül, a
Router CI `success` a merge SHA-n (`35419236949`), és a kör diffjében **0
nyitott BLOCKER/MAJOR** van. A halt a brief scope-járól szól, nem a kódról.
