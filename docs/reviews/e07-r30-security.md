# E07-R30 — Biztonsági / adatvédelmi review

- **Kör:** E07-R30 — „Evaluation harness, shadow rollout és Epic 7 lezárás"
- **Reviewer:** Claude (security-reviewer, READ-ONLY — AGENTS.md §15.1)
- **Dátum:** 2026-08-19
- **Branch / HEAD:** `codex/e07-r30-evaluation-and-epic-closure` @ `ce9e7ba5`
- **Diff-tartomány:** `04c44841 .. ce9e7ba5` (7 fájl, 6 ÚJ + 1 doc-módosítás, +615 sor)
- **Kör kockázata:** `risk = "high"` → a review AGENTS.md §15.1 szerint KÖTELEZŐ
- **Végeredmény:** **PASS** — 0 CRITICAL · 0 BLOCKER · 0 MAJOR · 0 MINOR · 3 NOTE (mind előretekintő)

---

## 1. Áttekintés — mit csinál a kör

Tisztán **evaluation/shadow** kör, nulla új terméki felület:

- `lib/.../application/service/shadow_plan_generator.dart` (ÚJ) — az Epic 7 ELSŐ
  éves vég-az-végig kompozíciója (evidence → skill estimate → priority →
  candidate → time budget → weekly schedule → `GenerationOrchestrator.generate()`),
  de a VALÓDI orchestrátorba egy SAJÁT, no-op `_ShadowActivation`-t injektál,
  ami CSAK számol (`calls += 1`), semmit nem perzisztál.
- `test/fixtures/practice_planner/golden_profiles.dart` (ÚJ) — 3 determinisztikus,
  commitolt Dart-builder tanulói profil.
- `test/property/planner_invariants_property_test.dart` (ÚJ) — 80 seedes próba,
  bitre azonos terv, nulla írás, aktiválási határ elérve.
- `test/property/planner_golden_fixture_test.dart` (ÚJ) — nulla hard sértés +
  elvárt candidate-ek.
- `tool/practice_plan_eval/plan_quality_report.dart` (ÚJ) — aggregált metrikák
  stdout-ra.
- `docs/sdd/epic-07-completion-report.md` (ÚJ) + `docs/rounds/e07-r30-…md` §10.

**Prompt-injection / bizalmi határ: N/A ebben a körben.** Nincs provider-hívás,
nincs tudásbázis-visszakeresés, nincs tool-calling, nincs import-parser (zip/
MXL/MIDI/GP), nincs futásidejű külső bemenet. A golden profilok statikus,
commitolt Dart-kód; a `plannerAssistEnabled` OFF és a completion report maga
rögzíti, hogy „Planner Assist has no live transport rollout in this round".

---

## 2. Nem tárgyalható termékhatárok (AGENTS.md §5) — ellenőrzés

| Határ | Verdikt | Bizonyíték |
|---|---|---|
| §5.1 Nyers audio/kamera-frame nem hagyja el az eszközt | **PASS (N/A)** | A diff-fájlok `audio\|camera\|microphone\|pcm\|wav\|frame\|recorder\|capture\|dart:ffi\|image_picker\|speech_to_text` grepje NULLA valós hitet ad; az egyetlen „microphone" a `requiresMicrophone` **`ExerciseCapability` enum** + `CapabilitySupport.supported` flag = tiszta képesség-metaadat, nem nyers minta. Nincs mic/audio plugin import. |
| §5.2 Kijelentkezve/diagnostics-off nincs rejtett hálózat | **PASS** | A 7 fájlban NULLA `Dio\|http\|HttpClient\|Socket\|WebSocket\|Uri.parse\|connect\|Process.run\|Process.start`. Az egyetlen `dart:io` felhasználás: `Platform.environment['PROPERTY_SEED']`, `ProcessInfo.currentRss`, `stdout.writeln` — mind lokális. |
| §5.3 Secret/token/kulcs/nyers audio/frame nem kerül logba/commitba | **PASS** | A golden fixture-ök szintetikus ID-k (`rhythm.quarterNotes`, `chord.gToC`, `strumming.downUp`, `fixture.accuracy`, `fixture.baseline`, dátumok) — nincs credential. A `check_secrets.dart` gate zölden futott; szemantikailag megerősítve: a fixture-ök valóban fake-ek. A `plan_quality_report.dart` stdout-ja kizárólag aggregált számok + stabil `profile.id`-k (`starter-rhythm`, `chord-transition`, `micro-strumming`). |
| §5.4 Cloud/community nem rontja az offline alapélményt | **PASS (N/A)** | Nincs cloud/community felület érintve; minden flag OFF marad; nincs hálózat. |
| §5.5 Gyenge confidence nem jelenik meg biztos állításként | **PASS (N/A)** | Nincs user-facing confidence-megjelenítés; a `confidence: 0.9` fixture-érték egy invariáns-harness bemenete, nem UI-állítás. A completion report korrekten caveatolja: „development-box corpus measurement, not an Android performance claim". |

---

## 3. Feladat-specifikus ellenőrzési pontok (a brief 1–7)

1. **Nincs audio/vision bemenet a domainbe** — igazolva (2. táblázat §5.1 sor).
2. **Nincs hálózati hívás** — igazolva; `shadow_plan_generator.dart` importjai kizárólag `core/foundation/*` és `domain/*` first-party modulok; `plan_quality_report.dart` csak `dart:io` (stdout/RSS) + a generátor.
3. **Nincs valós perzisztencia/aktiválás** —
   - `_ShadowActivation.activate()` no-op számláló (`shadow_plan_generator.dart:255-261`); `ShadowPlanRun.persistentWrites => 0` szerkezetileg hardcode-olt (`:66`).
   - `shadow_plan_generator.dart` NEM importál semmit a `data/local/`-ból vagy `active_plan_controller.dart`-ból (grep NULLA; az egyetlen „repository" hit a `:50` **kommentben** van: „owns no repository").
   - A VALÓDI `GenerationOrchestrator._run()` **egyetlen külső mellékhatása** az injektált `await activation.activate(activePlan)` (`generation_orchestrator.dart:154`); az orchestrátor maga NEM logol, NEM szerializál, NEM perzisztál (sink-grep NULLA). Így a shadow-futás összhatása: nulla írás, nulla hálózat, nulla log.
   - **Megerősítő invariáns:** `ShadowPlanGenerator`-t SEHOL nem importálja `lib/` kód (repo-szintű grep: csak a saját definíciója + tesztek + a tool + docs), és NINCS benne a `public.dart` barrelben → a futó appból elérhetetlen. A shadow-kimenet nem válhat tanuló-láthatóvá.
4. **Secret/kulcs nincs a fixture-ökben/commitban** — igazolva (2. táblázat §5.3 sor).
5. **Érzékeny tanuló-adat (discomfort/userNote/free-text) nincs logban** — a diff-fájlok `userNote\|discomfort\|songReference\|note\|painLevel` grepje NULLA. A `PracticeGoal`-t a builder KIZÁRÓLAG `skillIds`-szel építi (nincs `userNote`/`songReference`), a `DailyAvailability`-nek nincs `note`-ja beállítva. A riport stdout-ja csak aggregátum. (Lásd NOTE-1 az előretekintő `toJson`-felületről.)
6. **Flag-állapot változatlan** — `git diff --stat … lib/app/config/feature_flags.dart` ÜRES (a fájl nincs a diffben); a 7 új fájlban NULLA `Enabled\|setFlag\|enable(\|= true\|FeatureFlag`; `.github/**` érintetlen. (A7/A8 teljesül.)
7. **Prompt injection / bizalmi határ** — nincs futásidejű külső vezérlő bemenet; a golden profilok statikus commitolt Dart. Igazolva a §1-ben.

**Ellátási lánc:** nincs pubspec/dependency/asset változás (grep NULLA) → nincs új
karbantartandó függőség, nincs új provenance-igényű asset. PASS.

---

## 4. Leletek

### CRITICAL — nincs
### BLOCKER — nincs
### MAJOR — nincs
### MINOR — nincs

### NOTE (előretekintő, EGYIK SEM blokkol; egyik sem sérti a jelen kör határait)

**NOTE-1 — `AdaptivePracticePlan.toJson()` szerializálja a szabad szöveget; a
determinizmus-teszt ezt használja oracle-ként (jelenleg csírája sincs).**
- **Fájl:sor:** `test/property/planner_invariants_property_test.dart:37-38`
  (`jsonEncode(plan.toJson())`) ↔ `lib/.../domain/model/adaptive_practice_plan.dart:232,236`
  (`'songReference': goal.songReference`, `'userNote': goal.userNote`).
- **Failure scenario (hipotetikus, jövőbeli):** ha egy KÉSŐBBI golden profil
  beállít egy `userNote`/`songReference` szabad szöveget, és a bitre-azonos
  assertion elbukik, a `flutter_test` a teljes szerializált tervet (a szabad
  szöveggel együtt) a CI stdout-logba írja. A JELEN körben ez **inaktív**: a
  fixture-ök nem állítanak be szabad szöveget, így csak szintetikus ID-k
  jelennének meg. A `toJson()` a byte-identical determinizmus-teszthez a HELYES
  (teljes kanonikus) oracle — ez nem hiba.
- **Sértett szabály:** egyik sem a jelen körben; előretekintés §5.3-hoz +
  a completion report saját nyitott tételéhez (jövőbeli export `toSummary()`-t
  használjon).
- **Javaslat iránya:** amikor jövőbeli kör shadow-kimenetet ír/exportál diskre,
  hálózatra vagy AI-providernek, a jegyzeteket kihagyó `toSummary()`-t használja,
  ne a `toJson()`-t; a test-fixture-ökbe ne kerüljön valódi tanuló-PII.

**NOTE-2 — Az aktiválási határ továbbra is fuzionált az orchestrátorban (a
report korrektül közli).**
- **Fájl:sor:** `lib/.../application/service/generation_orchestrator.dart:150-155`
  (`plan.copyWith(status: active)` → `await activation.activate(activePlan)`
  egyetlen `generate()`-en belüli záró hatásként).
- **Failure scenario:** egy jövőbeli VALÓDI (perzisztáló) activation esetén a
  validálás/javítás és a perzisztálás egy hívásban fuzionál; a no-partial-
  activation csak a határ FÖLÖTT kényszerített. A jelen körben ez **nem harap**:
  a `_ShadowActivation` no-op. A `docs/sdd/epic-07-completion-report.md`
  „Open items" szakasza ezt kimondottan nevesíti („a future production
  preview-confirmation flow needs a separately scoped activation split").
- **Sértett szabály:** egyik sem; carry-forward tétel (egybevág az E07-R18
  „activation contract under-specified" jegyzetével).
- **Javaslat iránya:** a Planner Assist / preview-confirmation implementáló kör
  szedje szét a generálást és az aktiválást, és rögzítse az activation-kontraktus
  idempotencia/atomicitás/authz elvárásait, MIELŐTT valódi repository-írás
  bekötődik.

**NOTE-3 — Az eval-tool a `test/`-be nyúl (nem shippel, nem bekötött).**
- **Fájl:sor:** `tool/practice_plan_eval/plan_quality_report.dart:9`
  (`import '../../test/fixtures/practice_planner/golden_profiles.dart'`).
- **Failure scenario:** nincs futásidejű biztonsági hatás — a `tool/` nincs a
  `lib/` alatt, így a Flutter nem csomagolja az APK-ba; a tool standalone
  `main()`, `lib/` consumer nélkül. Réteg-higiéniai megjegyzés (production tool
  test-kódtól függ), nem szállítási/adatszivárgási kockázat.
- **Sértett szabály:** egyik sem.
- **Javaslat iránya:** ha az eval-korpusz később megosztott lesz production és
  teszt között, a golden profilokat érdemes egy nem-teszt eval-fixture modulba
  emelni; jelenleg elfogadható.

**Kiegészítő megfigyelés (nem lelet):** `planner_invariants_property_test.dart:12`
`int.parse(raw)` a `PROPERTY_SEED`-en nem-numerikus értékre `FormatException`-nel
elhasal → a teszt **fail-closed** megáll. A seedet a CI állítja (`github.run_id`,
numerikus); nem támadó-kontrollált. Nincs teendő.

---

## 5. Verdikt

**PASS.** A kör tisztán determinisztikus, offline, in-memory evaluation/shadow
pipeline. Nincs hálózat, nincs perzisztencia, nincs aktiválás (no-op, számlált),
nincs audio/kamera/import/provider felület, nincs flag-mozgás, nincs
dependency/asset változás, nincs secret vagy szabad-szöveg a logban/commitban. A
`ShadowPlanGenerator` szerkezetileg elérhetetlen a futó appból (nincs `lib/`
consumer, nincs barrel-export). A 3 NOTE mind előretekintő, egyik sem sérti a
jelen kör AGENTS.md §5 határait és egyik sem blokkolja a merge-öt. A completion
report (A9) őszintén nevesíti a nyitott tételeket.

**Merge-akadály biztonsági/adatvédelmi oldalról: NINCS.**
