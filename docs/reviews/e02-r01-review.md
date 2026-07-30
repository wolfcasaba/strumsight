# E02-R01 — Review

Brief: `docs/rounds/e02-r01-practice-baseline.md`
Diff: `git diff 27ef496..ea10a58` (8 fájl, +2422 / −13)
Reviewer: Claude · Dátum: 2026-07-30
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 1 · NOTE: 3

A kör érdemi és jó minőségű: a flag-oldal pontosan a kötött döntéseket
valósítja meg, a replay-teszt pedig **független legacy matchert** vezet a
scorer mellett, tehát nem puszta snapshot, hanem kettős implementáció
összevetése — ez több, mint amit a brief kért. A baseline-jelentés három olyan
rést is megtalált, amit a brief §2-je nem (lebegőpontos ablakhatár, a korai
`finalize()` inkonzisztens állapota, a chord kétpillanatos mintavétele),
mindhármat `fájl:sor` hivatkozással és a záró körre utalva.

Egyetlen érdemi baj van, és pont a kör magját érinti: **a befagyasztott
készlet soha nem lép be a match-window ütközési tartományba**, így a golden a
timing-aritmetikát rögzíti, a matchert nem — miközben az E02-R09 („Event
matcher és legacy timing parity") épp ezt a goldent fogja bizonyítékként
használni.

## Acceptance criteria — tételesen

| # | Kritérium | Bizonyíték | Állapot |
|---|---|---|---|
| 1 | 3 új mező, a 7 meglévő `const FeatureFlags(...)` hívóhely változatlan | `git diff --stat`: `app_bootstrap_test.dart` és `diagnostics_providers_test.dart` NEM szerepel a diffben; `app_config_test.dart` diffje csak `+164` sor, meglévő sor nem módosult | ✅ |
| 2 | Default-tábla mindhárom környezetre | `app_config_test.dart` „environment defaults match the guarded rollout table" — development/lab/production mind a három flagre | ✅ |
| 3 | Mindkét függőségi szabály valódi-sértés próbával, a hiányzó flag megnevezésével | két külön teszt + egy harmadik, amely `unorderedEquals`-szel bizonyítja, hogy EGY passban mindkét hiba kigyűlik (a `problems`-minta megőrzése) | ✅ |
| 4 | Mindhárom flag ON ⇒ `usesNetwork == false`, és nem követel URL-t | „all practice flags stay offline when dependencies are valid" — production környezetben, ÜRES `apiBaseUrl`-lel is átmegy | ✅ |
| 5 | A golden létezik, mind a 9 forgatókönyvvel, a replay zöld | `legacy_scorer_baseline.json` (651 sor), a katalógus-invariáns teszt halmaz-egyenlőséggel állítja a 9 ID-t | ✅ |
| 6 | A golden bizonyítottan érzékeny | **Független újrapróba (reviewer, nem a Codex kimenete):** `p44_basic_all_perfect` első strumja `4` → `4.06` ⇒ `Expected: "perfect": 8 / Actual: "perfect": 7`, `+3 -1: Some tests failed`; visszaállítás után `+4 ~1: All tests passed!` | ✅ |
| 7 | A forgatókönyvek a `test/support/`-ban, scorer-semlegesen újrahasználhatók | `practice_baseline_scenarios.dart` nem importál `LessonScorer`-t (csak `Lesson` + `StrumDirection`), a doc-comment kimondja a V2-újrahasználást, a listák `List.unmodifiable` | ✅ |
| 8 | `git diff --stat` a §4 listán belül, `lib/features/**` nem szerepel | a 8 érintett útvonal pontosan a §4 tábla; `lib/`-ből csak `app/config/{feature_flags,app_config}.dart` | ✅ |
| 9 | A meglévő tesztek zöldek | reviewer-oldali független újrafuttatás, lásd „Gate-bizonyíték" | ✅ |
| 10 | A jelentés az SDD §1.4 minden tételét fedi, `fájl:sor`-ral, külön ismert-rések szakasszal | 9 szekció, 275 sor; a §2.4 pause-rés az „Ismert rések" 1. pontja, golden-assertion nélkül (ADR 0067 §5 betartva) | ✅ |

Mind a tíz teljesül. A MAJOR nem egy kritérium megsértése, hanem a §5.1-ben
előírt készlet **diszkrimináló erejének** hiánya — lásd alább.

## MAJOR-1 — A befagyasztott készlet soha nem lép be a match-window ütközési tartományba

**Mérés (reviewer, számolva a forgatókönyv-adatokból):**

| Forgatókönyv | lecke | BPM | legkisebb cél-távolság |
|---|---|---:|---:|
| `p44_*` (8 db) | `_quarterLesson` / `_chordLagLesson` | 60 | **1000 ms** |
| `p34_waltz` | `Lessons.firstWaltz` | 76 | **789 ms** |

A legacy match window `±0.28 s`, azaz **560 ms teljes szélesség**. Mivel a
legkisebb cél-távolság 789 ms, **egyetlen observationnek sem lehet egynél több
jelölt targetje** a készlet egyetlen pontján sem.

**Amit a golden ezért NEM tud kimutatni:**

1. a „legközelebbi nyitott target" választása, ha kettő is jelölt;
2. a holtverseny-szabály (SDD Ch3 §15.1: „ugyanazon időeltérésnél a korábbi
   target nyer"; a mai kódban a `d < bestDelta` szigorúsága + a ciklus
   sorrendje dönti el, `lesson_scorer.dart:253-260`);
3. az „egy observation ⇒ legfeljebb egy target" kizárólagosság ütközés alatt;
4. hogy egy extra ütés **elnyeli-e a szomszédos targetet**. A
   `p44_extra_strums` extra ütései `4.5 / 5.5 / …`, azaz **pontosan 500 ms-re
   mindkét szomszédtól** — a windowon kívül, tehát triviálisan extrák. A mai
   scorer viszont a szándéktól függetlenül a legközelebbi nyitott targethez
   párosít: az érdekes eset (a window BELSEJÉBE eső extra) nincs rögzítve.

**Miért MAJOR:** a valódi tanterv állandóan ebben a tartományban él — a
nyolcados minták 80–104 BPM-en **288–375 ms** cél-távolságot adnak
(`lesson.dart:217-264`), vagyis a window mindig átfed két targetet. Az E02-R09
kör tárgya szó szerint a matcher parity, és ehhez ezt a goldent fogja
felhasználni: egy V2 matcher elvétheti mind a négy fenti szabályt, és a
készlet zöld marad. A parity-suite pontosan azt a dimenziót hagyja ki, amiért
létezik.

**Javítás (ebben a körben, kicsi diff):** egy tizedik forgatókönyv, pl.
`p44_eighths_contended` — nyolcados le/fel minta ~90 BPM-en (≈333 ms
cél-távolság), benne legalább:

- (a) egy két nyitott target közt **egyenlő távolságra** eső ütés
  (holtverseny-szabály),
- (b) egy extra ütés a szomszédos target windowának BELSEJÉBEN,
- (c) egy annyira késő ütés, amely egy már lezárt targetet nyithatna újra.

Ezután a golden újragenerálása (a §10-ben rögzített, engedélyezett
generátor-úton), és az új végállapot átnézése a `lesson_scorer.dart`
konstansaival. A `test/support/` + `test/fixtures/` + a baseline-jelentés
fixture-táblája a §4 listán belül van, tehát **nem igényel scope-bővítést**.

## MINOR-1 — A chunk 014 aktívan hamis állítást tartalmaz a pause-ról

A baseline-jelentés utolsó bekezdése helyesen jelzi, hogy
`docs/rag/chunks/014-play-along-learn.md` elavult (4-beat count-in, 12 lecke).
A felsorolásból viszont kimaradt a **veszélyes** tétel: a chunk azt írja, hogy
a `LearnScreen` a `liveFrameProvider`-re „**only while playing**" fizet elő,
„closed on pause/dispose" (`:56-59`). Ez ma **nem igaz** — `_pause()` nem
zárja a subscriptiont (`learn_screen.dart:232-237`), csak a `dispose` és a
jam-módú `_restart`.

Ez nem stílushiba: az AGENTS.md §9 szerint a `docs/rag/chunks/` a
viselkedés-igazság forrása, tehát a chunk épp azt tagadja, amit az „Ismert
rések" 1. pontja megtalált. Aki a chunkot olvassa, arra jut, hogy a rés nem
létezik.

A Codex helyesen NEM nyúlt hozzá (a §3 tilos zónában van). **Follow-up:** a
chunk 014 javítása külön, tételes körben (a pause-állítás, a count-in és a
lecke-szám együtt), a rés lezárásával (E02-R08/R11) egy commitban.

## NOTE-1 — A generátor-kiskapu nem hordozza magával az ADR 0067 szabályát

`UPDATE_LEGACY_SCORER_BASELINE=1` egyszerre kikapcsolja a freeze-assertiont és
újraírja a goldent (`legacy_scorer_baseline_test.dart:17,114-136`). A védelem
rendben van (env-gated, alapból skipped, CI-ben nincs beállítva), de az ADR
0067 §1/§3 szabálya — „a golden rögzít, nem előír; az újragenerálás
reviewelhető commit megnevezett okkal" — nem szerepel a fájlban. Aki hat kör
múlva pirosat kap és megtalálja a kulcsot, nem fogja megkeresni az ADR-t.
Javaslat: egy két soros doc-comment a kulcs mellé, az ADR-re hivatkozva.

## NOTE-2 — `FeatureFlags.toString()` címkéi átnevezve

`account:` → `accountEnabled:` stb. Nincs fogyasztója (grep: a mezőnevekre
csak a definíció hivatkozik; `app_config_test.dart:191` csak a `secret`
hiányát állítja), és a hat mezővel konzisztens is — de a kör briefje
viselkedés-változatlanságot írt elő, és ez egy meglévő diagnosztikai kimenet
átírása. Nem blokkol, nem kell visszavonni; feljegyzés.

## NOTE-3 — Amit érdemes megőrizni a következő körökre

A replay nem hisz a bemenetnek: a `targetEventIndex` **annotációt
ellenőrzi**, de a verdictet egy független, befagyasztott legacy matcherből
írja (`legacy_scorer_baseline_test.dart:180-257`), és két saját negatív teszt
bizonyítja, hogy ez a szigorítás él (félreannotált target ⇒ `TestFailure`;
késleltetett frame ⇒ 0 hit). A §10.2 rögzíti, hogy mindkettő valódi RED-ből
jött. Ez a minta az E02-R09 parity-körének is a helyes formája.

## Scope, architektúra, termékhatárok

- **Scope:** a diff 8 útvonala pontosan a brief §4 táblája. `lib/features/**`
  egyáltalán nem szerepel; `docs/adr/**`, `HANDOFF.md`, `.github/**`,
  `tool/**`, `ml/**`, `backend/**` érintetlen. A brief-fájlból csak a §10.
- **Architektúra:** `dart run tool/check_architecture.dart` → `12 allowlisted
  deviation(s)` — változatlan szám, a kör nem vett fel újat. A
  `test/support/practice_baseline_scenarios.dart` nem importál Fluttert és nem
  importál scorert.
- **Termékhatárok (AGENTS.md §5):** nincs új hálózati út — a #4 kritérium
  gépiesen állítja, hogy a három flag `usesNetwork`-öt nem mozdítja. Nyers
  audio nincs a fixture-ökben (idő + irány + akkord-label). Secret nincs.
  Mic-ownership nem érintett (nem változott production audio-kód).
- **Lifecycle / hibakezelés:** production oldalon a diff két `if`-blokk és
  három mező; nincs új catch, nincs új erőforrás.
- **DSP/ML:** `docs/rag/chunks/` és `ml/` érintetlen (a MINOR-1 follow-up
  ezért marad nyitva).

## Gate-bizonyíték — reviewer-oldali független újrafuttatás

Nem bemondásra (AGENTS.md §15.1). Külön hívásokként, `origin/…@ea10a58`-on:

```text
~/flutter/bin/flutter pub get                                    → Got dependencies!
~/flutter/bin/dart format --output=none --set-exit-if-changed …   → Formatted 452 files (0 changed)
~/flutter/bin/flutter analyze lib/ test/ tool/                   → No issues found! (9.5s)
~/flutter/bin/flutter test test/app test/features/learn          → +177 ~1: All tests passed!
~/flutter/bin/flutter test test/features/{progress,streak,metronome} → +50: All tests passed!
~/flutter/bin/dart run tool/check_architecture.dart              → OK (12 allowlisted deviation(s))
```

Az érzékenység-próbát is újra futtattam, a Codexétől **eltérő** forgatókönyvön
(`p44_basic_all_perfect`, nem `p44_timing_tiers`) — piros, majd visszaállítás
után zöld (lásd #6 kritérium). A `git status` a próba után tiszta.

Teljes suite + randomizált property gate + APK: CI-dispatch, a MAJOR-1
javítása után.

## Kért javítások (Codex)

1. **MAJOR-1:** `p44_eighths_contended` (vagy egyenértékű) forgatókönyv az (a)
   holtverseny, (b) windowon belüli extra és (c) lezárt target újranyitási
   próba esetekkel; golden újragenerálás az engedélyezett úton; a
   baseline-jelentés fixture-táblájának és a szükséges ID-halmaznak a
   bővítése; a §10 handoff frissítése az új végállapot átnézésének leírásával.
2. **NOTE-1** (opcionális, két sor): ADR 0067-hivatkozás a generátor-kulcs
   doc-commentjébe.

MINOR-1 **nem ebben a körben** javítandó (tilos zóna) — follow-upként rögzítve.
NOTE-2/NOTE-3 nem igényel változtatást.
