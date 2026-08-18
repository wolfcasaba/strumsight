# E07-R18 — Review

Brief: `docs/rounds/e07-r18-generation-orchestrator.md`
Diff: `git diff 585a1c62..34db7a6f` (base = the pre-flight §0.0 revision commit,
head = the implementer's single feature commit), isolated clone
`/tmp/review-E07-R18` (branch `terra/e07-r18-generation-orchestrator`)
Reviewer: Claude (Sonnet 5) · Dátum: 2026-08-18
Verdikt (első kör): **CHANGES REQUIRED**

## Frissítés — javító kör #1 után (2026-08-18)

Javító commit: `bf821515` (`fix(planner): harden generation controller
review findings`), a `6b56878d` review-jelentés commit UTÁN dispatch-elve.
Gate-eket ÚJRA, saját kézzel, FRISS izolált klónban futtattam
(`/tmp/review-E07-R18-fix1`, `git clone --branch
terra/e07-r18-generation-orchestrator` az originról, `bf821515` HEAD):

- **F1 FIXED.** `plan_generator_controller.dart` guardja bővült
  `_state.status != GenerationStatus.running`-nal a záró publikálás előtt
  (pontosan a review javasolt iránya). Regressziós teszt: „A6 controller:
  double-tap generate()…" — a saját kezemmel megerősítve, hogy a javítás
  ELŐTTI állapoton (a review saját próbateszjével) PIROS, utána ZÖLD.
  `plan_generator_controller_test.dart`: 4/4 zöld (izolált klónban mérve).
- **F2 FIXED.** Új teszt: „A3: unrepairable validation failure never
  activates a partial plan" — 4 hard-avoided jelölt + 3 repair-iteráció,
  `ValidationFailure` + `activation.calls == 0`. Dokumentált valódi-sértés
  próba (§10.3): a repair-elutasítási `Failure` ideiglenes `Success`-re
  cserélésével PIROS, visszaállítás után ZÖLD.
  `generation_orchestrator_test.dart`: 7/7 zöld (izolált klónban mérve).
- **F3 empirikusan lezárva, NYITVA marad (elfogadva).** Terra kipróbálta a
  `sync: false`-ra váltást — az A7 controller teszt PIROSRA váltott (az
  aszinkron kézbesítés mellett a feliratkozó az `await` idejéig nem látta a
  `completed` átmenetet), tehát a kód TÉNYLEG támaszkodik a szinkron
  kézbesítésre a jelenlegi teszt-asszerciók mellett. Ez elfogadható,
  empirikusan alátámasztott indoklás — a MINOR follow-upként nyitva marad,
  NEM blokkolja a merge-et (a review-sablon szerint is: „MINOR:
  javítható… ha nem hizlalja a diffet; egyébként follow-up").
- **Scope-audit:** `Legacy scope audit OK (6b56878d..bf821515, 4 changed
  path(s), 0 generated/ignored)` — a 4 útvonal: a briefdoksi §10 frissítése +
  a 3 engedélyezett production/teszt fájl egyike-másika. Nincs listán kívüli
  fájl.
- **Gate — MINDEN ZÖLD** saját kézzel, izolált klónban: format, analyze,
  mindkét célzott teszt, architecture, secrets, l10n.

**Verdikt (javító kör után): APPROVED.** F1/F2 zárva, bizonyítva; F3 nyitott
follow-up, nem blokkoló. CI-dispatch és merge mehet.

## Eredeti (első körös) megállapítások

BLOCKER: 1 (F1, FIXED) · MAJOR: 1 (F2, FIXED) · MINOR: 1 (F3, OPEN — nem
blokkoló follow-up) · NOTE: 3 (F4-F6, nem blokkoló)

Lásd külön a biztonsági review-t: [`e07-r18-generation-orchestrator-security.md`](e07-r18-generation-orchestrator-security.md)
— **PASS**, 0 BLOCKER/MAJOR/MINOR, 4 forward-looking NOTE.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | `cancel()` után NINCS repository-írás | ✅ | `generation_orchestrator_test.dart`: "A1/A2" (`activation.calls, isZero`), "A2 boundary" (ugyanaz) — orchestrátor-szinten mérve. |
| A2 | Bármely lépésnél megszakítható | ✅ | Ugyanott, "korán" (assembling) és "a határon" (activating) cella lefedve; a `_checkpoint` mechanizmus mind a 4 stage-re (`assembling/validating/repairing/activating`) azonos, a két mért végpont reprezentatív a brief §6.1 kötelező 3 cellájából a "korán"/"a határon" sorra. |
| A3 | Részleges eredmény nem aktiválódik | ⚠️ **Részben — lásd F2** | "A3/A4" teszt csak az ASSEMBLY-szintű strukturális hibát (hiányzó catalog-candidate) méri. A `validate → repair → still-invalid → Failure(ValidationFailure)` ág (`generation_orchestrator.dart:123-143`) kód-olvasással helyesnek tűnik, de NULLA teszt fedi. |
| A4 | Lépés-hiba `AppFailure`-t ad, nem nyers kivételt | ✅ orchestrátor-szinten / ❌ controller-szinten | Orchestrátor: "A3/A4" teszt zöld. Controller: **F1 ugyanezt az elvet sérti** a `PlanGeneratorController.generate()`-ben — nyers `StateError` jut ki a határon. |
| A5 | Újrapróbálás TISZTA futást indít | ✅ | "A5: retry starts clean after a failed request" — ugyanaz a `request.id`, első hívás hibázik, második sikeres, `activation.calls == 1`. |
| A6 | Azonos kérés párhuzamos indítása kontrollált | ✅ orchestrátor-szinten / ❌ **controller-szinten (F1)** | Orchestrátor: "A6: duplicate request returns the in-flight run" — valódi interleaving (`Completer`), `identical(first, second)`. Controller: **NINCS ilyen teszt**, és a próbateszt (lásd F1) bizonyítja, hogy a controller a valóságban ELSZÁLL azonos kérés dupla `generate()` hívásán. |
| A7 | Az állapot-átmenetek kikényszerítettek | ✅ | `plan_generator_controller_test.dart`: "A7: immutable state rejects an invalid transition" + "A7: controller publishes ordered immutable terminal state". Megjegyzés: ugyanez a kikényszerítés okozza F1-et, amikor a controller két egyidejű hívása versenyben próbálja lezárni ugyanazt az állapotot. |
| A8 | A hosszú számítás nem blokkolja a UI szálat | ✅ | "A8: generation returns a future while activation is pending" — `controller.state.status == running` amíg az `activation.activate()` függőben van; a `_checkpoint` minden stage előtt/után `await Future.delayed(Duration.zero)`-val enged a event loopnak. |

## Scope-audit

```
tools/scope-audit.py --repo /tmp/review-E07-R18 \
  --brief docs/rounds/e07-r18-generation-orchestrator.md --base 585a1c62
→ Legacy scope audit OK (585a1c62..34db7a6f, 7 changed path(s), 0 generated/ignored)
```

Engedélyezett fájlokon kívüli változás: **nincs.** A 7. változott útvonal maga
a brief (`docs/rounds/e07-r18-generation-orchestrator.md`, a §10 handoff
kitöltése) — ez explicit az `allowed_paths` utolsó sora.

## Megállapítások

### F1 — BLOCKER — `PlanGeneratorController.generate()` nyers `StateError`-ral áll el azonos kérés párhuzamos (dupla-tap) hívásán

- **Fájl:** `lib/features/practice_generator/application/controller/plan_generator_controller.dart:51-59`
  (a hiányzó guard), gyökér-ok `lib/features/practice_generator/application/model/generation_state.dart:57-67`
  (`_canTransitionTo` — helyesen dob, csak rossz helyről hívva).
- **Probléma:** `generate()` a záró állapot-publikálás előtt csak azt
  ellenőrzi, hogy `_disposed` és hogy `_state.requestId == input.request.id`
  (51. sor) — azt NEM, hogy `_state.status` MÉG `running`-e. Az
  `GenerationOrchestrator.generate()` (helyesen) ugyanazt a Future-t adja
  vissza mindkét hívónak azonos `request.id`-ra (single-flight dedup,
  `generation_orchestrator.dart:82-97`) — de a KÉT controller-szintű hívás
  MINDKETTŐ megpróbálja lezárni az állapotot, amikor a közös Future teljesül.
  Az első `_state.transitionTo(completed)` sikerrel lezárja `running → completed`-re.
  A MÁSODIK ugyanezt hívja, miközben `_state.status` MÁR `completed` — a
  `_canTransitionTo` (generation_state.dart:64-66) `completed`-ből kizárólag
  `running`-ba enged átmenetet, tehát dob: `StateError('Cannot transition
  generation from GenerationStatus.completed to GenerationStatus.completed')`.
- **Hatás:** bármely hívó, aki ugyanarra a folyamatban lévő kérésre kétszer
  hívja a `generate()`-et (a leggyakoribb valós UI-hiba: türelmetlen
  dupla-tap a "Generálás" gombon — pontosan az a forgatókönyv, amit az A6 és
  az ADR 0266 §4/§6 biztonságossá akar tenni), a `Future<AppResult<...>>`
  helyett egy ELKAPATLAN kivételt kap — közvetlenül sérti az ADR 0266 6.
  döntését ("Minden hiba `AppFailure`-re képezve... Nincs nyers kivétel a
  határon") pontosan azon az egyetlen határon, ami a UI felé néz.
- **Valódi-sértés próba (eldobható, `/tmp/review-E07-R18`-ban futtatva, NEM
  része a diffnek):**
  ```dart
  test('PROBE: double-tap generate() on the same in-flight request', () async {
    final controller = PlanGeneratorController(
      orchestrator: GenerationOrchestrator(activation: _NoopActivation()),
    );
    final input = _input();
    final first = controller.generate(input);
    final second = controller.generate(input);
    final results = await Future.wait([first, second]);
    expect(results[0], isA<Success<AdaptivePracticePlan>>());
    expect(results[1], isA<Success<AdaptivePracticePlan>>());
  });
  ```
  Kimenet: **PIROS** —
  `Bad state: Cannot transition generation from GenerationStatus.completed to GenerationStatus.completed`
  a `plan_generator_controller.dart:59` sorból, `generation_state.dart:34`
  forrással. A hipotézis megerősítve, nem feltételezés.
- **Kötelező javítás:** a záró publikálás guardját bővíteni kell — csak akkor
  publikálj terminális állapotot, ha `_state.status == GenerationStatus.running`
  IS igaz a `requestId`-egyezés mellett; ha nem (mert egy másik egyidejű hívás
  már lezárta), a `result`-ot egyszerűen add vissza publikálás nélkül. A
  DIFFERING requestId eset (más kérésre indított generálás közben fut le egy
  korábbi) NE romoljon — az jelenleg helyesen viselkedik.
- **Ellenőrzés:** a fenti próbateszt (vagy ezzel ekvivalens) kerüljön be a
  végleges `plan_generator_controller_test.dart`-ba mint A6 controller-szintű
  cellája, és PIROS→ZÖLD legyen a javítás előtt/után.
- **Státusz:** FIXED (`bf821515`) — a guard bővült
  `_state.status != GenerationStatus.running`-nal; a regressziós teszt
  saját kézzel, izolált klónban ZÖLD.

### F2 — MAJOR — A3 "lépés hibázik → nincs aktiválás" csak az assembly-szintű hibaágra van tesztelve, a validate/repair-elutasítási ágra nincs

- **Fájl:** `lib/features/practice_generator/application/service/generation_orchestrator.dart:123-143`
  (a `validate → repair → still-invalid → Failure(ValidationFailure)` ág),
  teszt: `test/features/practice_generator/application/generation_orchestrator_test.dart`
  (hiányzó eset).
- **Probléma:** a `_run` metódusnak KÉT strukturálisan különböző módja van
  arra, hogy "a terv sosem aktiválódik": (1) egy `ArgumentError`/`StateError`
  az assembly alatt (pl. hiányzó catalog-candidate) → `UnknownFailure`; (2) a
  `PlanValidator.validate()` elutasítja, a `PlanRepairer.repair()` sem tudja
  javítani (vagy a javítás utáni újra-validálás is elutasítja) →
  `Failure(ValidationFailure(...))`. A meglévő "A3/A4" teszt KIZÁRÓLAG az (1)
  ágat méri. A (2) ág — ami a brief §6.1 saját sora szerint ("Hibás lépés
  után is aktiválódik a terv" → A3) a klasszikus célzott forgatókönyv — kód-
  olvasással helyesnek tűnik, de nulla teszt bizonyítja.
- **Hatás:** egy jövőbeli regresszió (pl. valaki véletlenül `return
  Success(plan)`-re cseréli a 138-142. sort) ZÖLDEN futna át ezen a körön —
  pontosan az a hiba-osztály, amit a kör saját "valódi-sértés próba"
  követelménye (brief §6, "Valódi-sértés próba (KÖTELEZŐ)") hivatott
  kiszűrni, de az csak az A1 cellára lett elvégezve (§10.3 dokumentálja),
  nem a validate/repair-elutasítási ágra.
- **Kötelező javítás:** egy új teszteset, amely egy olyan `GenerationPlanInput`-ot
  épít (a meglévő `validation_fixtures.dart` vagy egy bővítése segítségével),
  amire a `PlanValidator.validate()` `error`/`fatal` severity-vel elutasít
  ÉS a `PlanRepairer.repair()` sem tudja javítani (pl. egy repair-hatókörön
  kívüli hard-avoid sértés) — asserteld `Failure<AdaptivePracticePlan>` +
  `ValidationFailure` + `activation.calls == 0`.
- **Ellenőrzés:** az új teszt PIROS legyen, ha a 138-142. sor helyett
  `Success`-t adna vissza (rövid, ideiglenes mutáció-próbával igazolva, a
  brief §10-be dokumentálva — ugyanaz a minta, mint az A1-re már elvégzett
  próba).
- **Státusz:** FIXED (`bf821515`) — új „A3: unrepairable validation
  failure…" teszt, dokumentált valódi-sértés próbával (§10.3); saját
  kézzel, izolált klónban ZÖLD.

### F3 — MINOR — `StreamController(..., sync: true)` mindkét broadcast controlleren

- **Fájl:** `generation_orchestrator.dart:74-75` (`_progressController`),
  `plan_generator_controller.dart:22-23` (`_statesController`).
- **Probléma:** a Dart SDK saját dokumentációja kifejezetten óva int a
  `sync: true` broadcast controllerektől ("doing so leads quickly to
  hard-to-debug problems") a reentrancy-kockázat miatt — egy listener, ami
  szinkron módon vált ki egy másik `add()`-ot ugyanazon a controlleren,
  nehezen debuggolható állapotot okozhat. Nincs dokumentált indok a
  kódban, miért kellett itt kifejezetten szinkron kézbesítés.
- **Hatás:** ma nem okoz megfigyelt hibát (a tesztek zöldek), de F1 pont azt
  mutatja, hogy ennek az osztálynak MÁR van egyidejűségi éle — egy jövőbeli,
  hasonló módosítás könnyebben vezethet nehezen reprodukálható hibához
  `sync: true` mellett, mint a alapértelmezett aszinkron kézbesítéssel.
- **Javasolt irány:** válts `sync: false`-ra (az alapértelmezettre), hacsak
  nincs konkrét, dokumentált ok a szinkron kézbesítésre.
- **Státusz:** WONTFIX ezen a körön, empirikusan alátámasztva (§10.3): a
  `sync: false`-ra váltás próbája PIROSRA fordította az A7 controller
  tesztet (az aszinkron kézbesítés mellett a feliratkozó nem látta időben a
  `completed` átmenetet) — a kód ténylegesen támaszkodik a szinkron
  kézbesítésre a jelenlegi assertion-stílus mellett. Follow-up marad: vagy a
  tesztek igazítása aszinkron kézbesítéshez egy KÉSŐBBI körben, vagy a
  `sync: true` választás explicit dokumentálása a kódban. Nem blokkol.

### F4 — NOTE — Pihenő/nem elérhető napok szintetikus `planned` státuszt és 1 mikroszekundumos budget-et kapnak

- **Fájl:** `generation_orchestrator.dart:231-243` (`_assembleDay`).
- **Megfigyelés:** egy `restDay`/`dayUnavailable` `DaySchedulingDecision`
  (üres `selectedCandidates`) `PracticeDay`-je `status: PracticeItemStatus.planned`-ot,
  `primaryFocusSkillIds: ['schedule.noFocus']` placeholder-t, és egy
  mesterséges 1 mikroszekundumos `timeBudget`-et kap — annak ellenére, hogy
  a `PracticeItemStatus` enum tartalmaz egy explicit `unavailable` értéket.
  A `reasonCodes` VISZONT helyesen továbbadja a scheduler saját
  `restDay`/`dayUnavailable` kódját, tehát egy jövőbeli fogyasztó (Kör 19+
  repository/UI) ebből még helyesen le tudja vezetni a nap valódi
  jellegét — ez NEM funkcionális zsákutca, csak adat-hűségi darabosság.
- **Nem méri az A1-A8 egyike sem** — összhangban a brief §0.0 revíziójával,
  ami kifejezetten az orchestrátor döntésére bízta ezt a leképezést.
- **Státusz:** follow-up, nem blokkol.

### F5 — NOTE — `UnknownFailure` assembly-szintű adatintegritási hibákra, ahol `ValidationFailure` beszédesebb lehetne

- **Fájl:** `generation_orchestrator.dart:158-163` (`_run` catch-all),
  `:266-271`/`:304` (a dobott `ArgumentError`/`StateError`-ok).
- **Megfigyelés:** a hiányzó catalog-candidate vagy tartományon kívüli
  `duration` — bár valódi hiba — inkább "a bemenet nem validálható" jellegű,
  mint "ismeretlen/váratlan". Az ADR 0266 6. döntése nem ír elő konkrét
  `AppFailure` altípust, tehát ez nem szerződés-sértés, csak diagnosztikai
  beszédesség kérdése.
- **Státusz:** follow-up, nem blokkol.

### F6 — NOTE — "cancel az aktiválás KÖZBEN (még nem lezárt `activate()` alatt)" szándékos no-op, de nincs önálló teszt

- **Fájl:** `generation_orchestrator.dart:145-154` (a "Do not checkpoint
  after this await" komment és a mögötte álló döntés).
- **Megfigyelés:** kód-olvasással a viselkedés helyes és szándékos (a
  brief §6.1 3 kötelező cellájának egyike sem ezt az esetet írja elő — a
  "későn" cella a SIKERES aktiválás UTÁNI cancelt írja le, nem az alatta
  lévőt) — de a meglévő `_CompletingActivation`/`_BlockingActivation`
  fixture-ökkel (a teszt már használ ilyet A6-hoz és A8-hoz) egy sorban
  lefedhető lenne: `cancel()` hívása AZUTÁN, hogy `activation.started.future`
  teljesült, de MIELŐTT `activation.complete()` meghívódna — és utána
  asserteld, hogy az eredmény MÉGIS `Success` marad.
- **Státusz:** follow-up, nem blokkol.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (§10.3) | Ellenőrizve (saját kézzel, izolált `/tmp/review-E07-R18` klónban) |
|---|---|---|
| format | zöld | ✅ zöld (`dart format --output=none --set-exit-if-changed lib test tool` — 1599 fájl, 0 változott) |
| analyze | zöld (1 kör után, egy unused import javítva) | ✅ zöld (`flutter analyze lib/ test/ tool/` — „No issues found!") |
| test `generation_orchestrator_test.dart` | 9 passed (előzetes összegzés) / 6 teszt a végleges fájlban | ✅ zöld — 6/6 passed a végleges fájlon |
| test `plan_generator_controller_test.dart` | ugyanott | ✅ zöld — 3/3 passed |
| architecture | — (nem külön említve) | ✅ zöld (`tool/check_architecture.dart` — 12 allowlisted deviation, nincs új) |
| secrets | — | ✅ zöld (`tool/ci/check_secrets.dart` — 0 finding) |
| l10n | — | ✅ zöld (`tool/ci/check_l10n_parity.dart` — en→hu párban) |
| scope-audit | — | ✅ OK, 7 változott útvonal, 0 sértés |
| CI (teljes suite + property + APK) | még nem dispatch-elve | ⏳ a review után, a javító kör lezárása UTÁN dispatch-elendő |

Minden fenti gate a saját kezemmel, elkülönített `/tmp/review-E07-R18` klónban
futott, nem a közös munkafán és nem az implementer állításából átvéve.

### Javító kör #1 utáni gate-bizonyíték (saját kézzel, FRISS izolált `/tmp/review-E07-R18-fix1` klónban, HEAD `bf821515`)

| Gate | Ellenőrizve |
|---|---|
| format | ✅ zöld |
| analyze | ✅ zöld |
| test `generation_orchestrator_test.dart` | ✅ zöld — 7/7 passed (+1 az F2 javításból) |
| test `plan_generator_controller_test.dart` | ✅ zöld — 4/4 passed (+1 az F1 javításból) |
| architecture | ✅ zöld |
| secrets | ✅ zöld |
| l10n | ✅ zöld |
| scope-audit (`--base 6b56878d`) | ✅ OK, 4 változott útvonal, 0 sértés |
| CI (teljes suite + property + APK) | ⏳ a review lezárása után dispatch-elendő |

## Merge-döntés

**F1 és F2 zárva (FIXED, `bf821515`), saját kézzel újramérve.** F3 nyitott,
de WONTFIX-ként dokumentált follow-up (empirikusan indokolt, nem blokkoló).
F4-F6 (NOTE) és a biztonsági review 4 NOTE-ja nem blokkol. **A gate minden
eleme zöld → CI-dispatch és squash-merge mehet (ADR 0052).**
