# E06-R22 — Review

Brief: `docs/rounds/e06-r22-analysis-runner-progress-cancellation.md`
Diff: `git diff 4ef44008..6c27935a` (pre-flight commit → implementer HEAD), isolated clone `/tmp/review-e06-r22`
Reviewer: Claude Sonnet 5 (orchestrator) · Dátum: 2026-08-12
Verdikt (első kör): **APPROVED** — de lásd az alábbi frissítést: a KÖTELEZŐ
dedikált biztonsági review (risk=high) ezen a diffen egy független, valódi
MAJOR leletet talált, amit ez a review nem fogott meg (a saját tesztkészlet
csak fake runnert használt a cancel-takarítás cellán — lásd F2 alább, ami
ugyanezt a hiányt más szögből már jelezte).

## Frissítés — Javító kör #1 után (2026-08-12, fix commit `63f39515`)

**Végső verdikt: APPROVED.** A dedikált biztonsági review
(`e06-r22-analysis-runner-progress-cancellation-security.md`) MAJOR-1
(cancel-during-spawn isolate leak) leletét a Terra javító kör #1 zárta,
orchesztrátor-oldali független újramérés (gate + valódi-sértés próba,
ld. a security-jelentés frissítése) után. Ugyanabban a körben F2 (lent) is
javítva. F1 nyitva marad follow-up-ként (MINOR, nem blokkol).

## Összegzés

BLOCKER: 0 · MAJOR: 0 nyitva (1 volt, a dedikált security review-ban, FIXED) · MINOR: 1 nyitva (follow-up) + 1 FIXED · NOTE: 2

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Állapot-mátrix — tíz cella | ✅ | `analysis_controller_test.dart`: teljes siker (l.14), degradált (l.29), fatal (l.48), input-nélküli 0-kredit (l.70), késői eredmény+cancel-utáni-új-futás (l.88), permission/input denied (l.167), tab-switch+app-background (l.177–200, parametrizált). Mind a 10 cella lefedve, függetlenül futtatva zöld (lásd Gate-bizonyíték). |
| 2 | Késői eredmény, `rejectedLateResults == 2` | ✅ | `analysis_controller_test.dart:88-114`, zöld. **Valódi-sértés próba** (lásd Megállapítások előtt): a `_onResult` run-ID őrének ideiglenes kiiktatása (`if (false)`) a várt `2`-ről `1`-re csökkentette a számlálót — a teszt PIROSRA váltott, majd a mutáció visszaállítva (`git checkout --`), a klón újra tiszta. |
| 3 | Kredit-mátrix — hat cella | ⚠️ 5/6 explicit, 1 strukturálisan garantált | `complete`+esemény→1 (l.14), `complete`+nincs esemény→0 (l.70), `degraded`→0 (l.29), `failed`→0 (l.48) mind explicit tesztelt. `cancelled`→0: **nincs dedikált teszt**, de a `_creditOnce` hívás az `_onResult` switch-ének KIZÁRÓLAG a `complete` ágában szerepel (`analysis_controller.dart:132-140`) — szerkezetileg lehetetlen, hogy egy `cancelled`/`degraded`/`failed` kimenet krediteljen. Lásd F1 (MINOR). Az „ismétlődő late event → még mindig 1" cellát a run-ID kapu már a `_onResult` belépésénél kiszűri (`analysis_controller.dart:126-129`), mielőtt a `_creditedRunIds` Set egyáltalán szóhoz jutna — a Set emiatt ma védelmi többlet, nem az elsődleges mechanizmus, de nem hibás. |
| 4 | Progress throttle küszöb hármas (4/5/6, inkluzív az 5.-nél) | ✅ | `analysis_controller_test.dart:116-165`. Kézzel követve a `_onProgress` számlálóját (`analysis_controller.dart:105-123`): 4. esemény után `emittedProgressEvents == 0`, 5. után `== 1`, 6. után változatlanul `== 1` (a számláló nullázódik az 5.-nél) — pontosan az előírt inkluzív határ. |
| 5 | Cancel-takarítás (`disposed`, stream `isClosed`, temp-lista üres) | ✅ | `analysis_cancellation_test.dart:10-39`. |
| 6 | Nincs DSP a controllerben | ✅ | `analysis_controller_test.dart:202-213` forrásolvasó teszt (`engine/`, `jsonEncode`, `jsonDecode` string-tiltás) + manuális import-ellenőrzés: `analysis_controller.dart` importjai kizárólag `domain/analysis_document.dart`, `domain/analysis_progress.dart`, `domain/analysis_event.dart` és saját `application/` fájlok — nincs `engine/` import. |
| 7 | Isolate smoke (valódi `Isolate.spawn`, szerializálhatóság) | ✅ | `analysis_cancellation_test.dart:41-50` — valódi `Isolate.spawn` a `AnalysisDocumentCodec` JSON-ján át, echo-operationnel; a dekódolt dokumentum azonos ID-t ad vissza. |
| 8 | Progress-nézet szemantika (lokalizált fázis, cancel `Semantics`, nincs hamis %) | ✅ | `analysis_progress_view_test.dart` — `find.text('Preparing audio')`, `find.bySemanticsLabel('Cancel analysis')`, `find.textContaining('%')` → `findsNothing`. |
| 9 | V1 érintetlen | ✅ | `git diff --stat` nem tartalmaz `lib/features/analyze/**`/`progress/**`/`streak/**` útvonalat (lásd Scope-audit); `test/features/analyze` gate-út zöld, 64 teszt. |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.** `git diff --stat 4ef44008..HEAD` pontosan a brief `allowed_paths` 15 bejegyzését adja (7 új `application/` fájl, 1 additív `application/analysis_providers.dart`, 1 új `presentation/` fájl, 1 additív `public.dart`, 2 additív ARB, 3 új teszt, a brief §10 handoff-frissítése). A wrapper gépi scope-auditja is megerősíti: `scope_audit=ok`, `scope_audit_changed=15` (`.codex-round-status`). `lib/features/audio_analysis/engine/**` és `domain/**` importálva, nem módosítva.

## Megállapítások

### F1 — MINOR — hiányzó dedikált teszt a „cancelled → 0 kredit" cellára

- **Fájl:** `test/features/audio_analysis/application/analysis_controller_test.dart` (nincs ilyen teszt); a garantáló kód: `lib/features/audio_analysis/application/analysis_controller.dart:132-149`.
- **Probléma:** a brief §6 explicit hat cellát ír elő a kredit-mátrixhoz, ezek egyike a `cancelled → 0`. Ez ma NEM egy dedikált `expect(credit.calls, 0)` asszerció után egy `AnalysisCompletionStatus.cancelled` eredményre — a lifecycle-tesztek (tab-switch/app-background) cancel-t váltanak ki, de a bennük használt `_FakeCreditRecorder`-re a tesztnek nincs referenciája.
- **Hatás:** a mai kód strukturálisan biztonságos (a `_creditOnce` hívás kizárólag a switch `complete` ágában van), tehát nincs éles kockázat — de egy jövőbeli refaktor, amely a switch-et átalakítja, ezt a cellát ÉSZREVÉTLENÜL elronthatná, mert nincs teszt, ami PIROSRA váltana.
- **Kötelező javítás:** egy `test('does not credit a cancelled run', ...)` hozzáadása, amely `completion: AnalysisCompletionStatus.cancelled`-lel zár egy futást, és `expect(credit.calls, 0)`-t állít, a `credit`-et a `_controller(run, credit: credit)` már meglévő paraméterén át átadva.
- **Ellenőrzés:** az új teszt önmagában PIROSRA váltana, ha valaki a `_creditOnce`-t a `cancelled` ágba is bekötné.
- **Státusz:** OPEN (follow-up — nem blokkolja a merge-et, MINOR).

### F2 — MINOR — `AnalysisController.analyze()` nem szakítja meg az aktív futást újraindításkor

- **Fájl:** `lib/features/audio_analysis/application/analysis_controller.dart:70-86`.
- **Probléma:** ha `analyze()` úgy hívódik meg, hogy MÁR van aktív futás (`_activeRun != null`), a metódus feltétel nélkül felülírja `_activeRun`/`_activeRunId`-t az ÚJ futással, és SOSEM hívja meg az előző futás `cancel()`-jét. Az előző futás így nem szakad meg — csak a saját természetes befejezéséig fut tovább, és az eredménye a run-ID kapun helyesen `late`-ként bukik el (nincs adatsérülés), de az isolate-je feleslegesen fogyaszt erőforrást eddig a pontig.
- **Mérve (eldobható próba, törölve a review után):** két egymást követő `analyze()` hívás, közbenső `cancel()` nélkül → `first.cancelCalled == false` a teljes folyamat alatt, miközben `rejectedLateResults == 1` helyesen jelzi a késői eredményt. A próbateszt a review lezárása előtt törölve (`git status --short` a klónban tiszta).
- **Hatás:** ma nincs UI-hívó, ami ezt a sorrendet előidézhetné (a brief ezt a képernyő-drótozást kizárja a scope-ból) — gyakorlati hatás csak egy jövőbeli host-képernyő hibás (dupla-tap elleni védelem nélküli) drótozásával jelentkezne.
- **Kötelező javítás:** `analyze()` elején: ha `_activeRun != null`, vagy hívja meg `cancel()`-t implicit módon az új futás indítása előtt, vagy (UI-döntésként) egyszerűen `return`-öljön no-opként — a döntés a jövőbeli host-drótozó kör dolga, mert termékszinten kell eldönteni, hogy az „ismételt analyze" auto-cancel-and-restart vagy elutasított legyen.
- **Ellenőrzés:** a fenti eldobható próba mintája újrafelhasználható a jövőbeli fix teszteként.
- **Státusz:** **FIXED** (`63f39515`, javító kör #1) — `analyze()` immár
  `unawaited(cancelAnalysis(previousRun))`-t hív a korábbi aktív futáson,
  mielőtt az újat indítaná. Ezt a dedikált security review NOTE-2-je
  függetlenül ugyanígy azonosította.

### F3 — NOTE — az isolate runner egy-üzenetes, nincs valódi köztes progress-csatorna

- **Fájl:** `lib/features/audio_analysis/application/analysis_isolate_runner.dart:90-142,192-197`.
- **Megfigyelés:** az `_IsolateAnalysisRun._start()` PONTOSAN egy szintetikus `finalizing` fázis-eseményt küld (a spawn UTÁN, még a válasz megérkezése ELŐTT), majd egyetlen `messages.first`-re vár — az `_isolateEntry`/`_IsolateRequest`/`operation` aláírása nem ad módot arra, hogy egy jövőbeli, valódi több-stage `operation` köztes fázis-eseményeket küldjön vissza a fő isolate-nak. Ez konzisztens azzal, hogy ma nincs valódi pipeline (ADR 0240 Döntés 4), és a brief OD-01 elfogadási köre is csak a szerializálhatóságot kéri bizonyítani (nem a köztes streaminget) — tehát ez NEM a brief megsértése.
- **Miért NOTE, nem MAJOR:** az ADR 0240 „Következmények" szakasza azt állítja, hogy egy jövőbeli valódi-pipeline kör „csak egy stage-listát és egy provider-felülírást ad hozzá — a runner/controller/use-case réteget nem kell újraírni." Ez a controller/use-case rétegre pontos (azok a `progress`/`result` absztrakción át bármennyi eseményt transzparensen kezelnek), de az ISOLATE RUNNER saját üzenet-topológiáját BŐVÍTENI kell egy progress-csatornával, ha a valódi lánc szakaszonként akar jelezni — ez egyetlen fájlra (`analysis_isolate_runner.dart`) korlátozott, kontrollált bővítés, nem újratervezés.
- **Javasolt irány:** az ADR 0240 „Következmények" szövegét ez a review pontosítja (orchesztrátor-oldali, saját pre-flight artefaktum javítása, ADR 0087 §2 szerint saját hatáskörben) — lásd a kísérő ADR-commit.
- **Státusz:** NOTE (nem blokkol; az ADR-szöveg pontosítása ezzel a review-val egy körben megtörténik).

### F4 — NOTE — `PracticeEntry.seconds` csonkol, a V1 kerekít

- **Fájl:** `lib/features/audio_analysis/application/analysis_providers.dart` (`_RiverpodAnalysisPracticeCreditRecorder.record`, `seconds: timeline.duration.inSeconds`) vs. V1 `lib/features/analyze/providers/analyze_providers.dart:233` (`result.durationSec.round()`).
- **Megfigyelés:** a `Duration.inSeconds` nullafelé csonkol, a V1 legközelebbi egészre kerekít — egy 29,6 s-os felvétel V1-en 30, V2-n 29 másodpercet írna a gyakorlási naplóba. A brief/ADR 0240 „bitre azonos" követelménye kifejezetten a KREDITÁLÁSI FELTÉTELRE (van-e akkord/pengetés) vonatkozik, nem a metaadat-mezők pontosságára — ez a mező informatív statisztika, nem a kredit-döntés maga.
- **Hatás:** elhanyagolható, legfeljebb 1 másodperces eltérés a gyakorlási naplóban.
- **Státusz:** NOTE (nem blokkol; egy jövőbeli kör olcsón igazíthatja `.round()`-ra, ha valaki előveszi).

## Gate-bizonyíték ellenőrzése

Két kör: az első implementáció (`6c27935a`) ÉS a javító kör #1 (`63f39515`)
után is, mindkétszer friss `/tmp/review-e06-r22` klónban.

| Gate | 1. kör (implementer) | 1. kör (reviewer) | 2. kör — javítás után (reviewer) |
|---|---|---|---|
| format | zöld | ✅ zöld | ✅ zöld |
| analyze | zöld | ✅ zöld | ✅ zöld |
| test test/features/audio_analysis | zöld | ✅ zöld, **435 teszt** | ✅ zöld, **438 teszt** (+3 fix) |
| test test/app | zöld | ✅ zöld, **69 teszt** | ✅ zöld, **69 teszt** |
| test test/features/analyze | zöld | ✅ zöld, **64 teszt** | ✅ zöld, **64 teszt** |
| architecture | zöld | ✅ zöld (12 allowlistelt eltérés) | ✅ zöld |
| secrets | (a gate futtatta) | ✅ zöld (2370 fájl, 0 lelet) | ✅ zöld |
| l10n parity | (a gate futtatta) | ✅ zöld (en→hu, 1099 üzenet) | ✅ zöld |
| CI (teljes suite + property + APK) | — | — | orchesztrátor a fix után dispatch-eli (§3.0 CI-terv), a `63f39515` SHA-n |

Az 1. kör `.codex-round-status`-a `gate_shape=ok`-t adott. A javító kör #1
jelzése `gate_shape=VIOLATION`-t jelzett — **ellenőrizve, ÁLPOZITÍV**: az
egyetlen regex-találat egy `sed -n '1,260p' tools/round-gate.sh && git
status --short && git diff --check` sor volt (a gate SCRIPT FORRÁSÁNAK
kiolvasása diagnosztikai céllal, nem a gate futtatásának láncolása) — a
tényleges `tools/round-gate.sh test/features/audio_analysis test/app
test/features/analyze` hívás mind a négy előfordulásnál csonkítás/láncolás
nélküli. A reviewer saját, független `/tmp/review-e06-r22` gate-újrafuttatása
(fenti táblázat 4. oszlopa) ettől függetlenül is megerősíti a zöld eredményt.

## Merge-döntés

ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge. A
dedikált security review (risk=high) MAJOR-1 leletét a javító kör #1
(`63f39515`) zárta, orchesztrátor-oldali független újramérés (gate + valódi-
sértés próba) után. A feltétel **teljesül**: 0 BLOCKER, 0 nyitott MAJOR; F1
(MINOR) follow-up-ként nyitva marad, nem blokkol. A CI-dispatch (ADR 0171 §3
terv) a `63f39515` SHA-n az orchesztrátor következő lépése.
