# E08-R21 — Review

Brief: docs/rounds/e08-r21-mastery-milestone-domain-and-evaluator.md
Diff: `git diff a39c6b45...99c36e90` (implementer commits `75197be5`, `5088b855`, `a9352979`, `99c36e90` [1. javító kör], plus one orchestrator-committed leftover `5259e54c`)
Reviewer: Claude Sonnet 5 (high) · Dátum: 2026-08-21
Verdikt: **APPROVED** (1. javító kör után — lásd "Javító kör" szakasz)

## Összegzés

BLOCKER: 0 · MAJOR: 0 (1 FIXED) · MINOR: 0 · NOTE: 1

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Nincs XP/szint/ledger a kiértékelő bemenetei között | ✅ | `mastery_evaluator.dart:1-3` importlista csak `mastery_badge`/`mastery_milestone`/`mastery_progress`; `grep -rniE "ExperiencePoints\|RewardLedger\|GamificationProfile\|totalXp\|baseXp"` a mastery-fájlokon 0 találat (reviewer saját futtatás) |
| A2 | 1 session bizonyítéka NEM elég | ✅ | `mastery_evaluator_test.dart:68-81`, `threshold alatt` teszt (345-354); gate ZÖLD |
| A3 | Ugyanazon session szegmensei EGY bizonyítéknak számítanak | ✅ | `mastery_evaluator_test.dart:83-109`; **reviewer valódi-sértés próba**: a `_qualifyingSessions` dedup-kulcsát ideiglenesen `'${sessionId}#${bySession.length}'`-re mutálva az A3 teszt ténylegesen PIROSRA vált (`Expected: <1> Actual: <2>`), az összes többi teszt zöld marad; a mutáció visszaállítva (`git checkout --`) |
| A4 | Alacsony megbízhatóságú Vision/Analysis bizonyíték kizárva | ✅ | `mastery_evaluator_test.dart:111-163` (0.69 elutasítva, 0.70 pontosan áthalad — `_passesConfidenceGate`, `mastery_evaluator.dart:107-117`) |
| A5 | Elért mérföldkő gyengébb teljesítménytől nem vész el | ✅ (javítás után) | F1 FIXED `99c36e90`; új teszt `mastery_evaluator_test.dart:206-253` a kisebb-batch esetre is |
| A6 | Össze nem hasonlítható session-ök kizárva | ✅ | `mastery_evaluator_test.dart:206-264` (nehézség + tempó-tartomány külön eset) |
| A7 | Bizonyíték-összefoglaló privacy-safe | ✅ | `mastery_evaluator_test.dart:266-314`; `mastery_badge.dart:65-74` `toSummary()` zárt kulcskészlete forráskódból is ellenőrizve — nincs `sessionId`/`audio`/`waveform`/egészségügyi mező |
| A8 | Jelvény magyarázható | ✅ | `mastery_evaluator_test.dart:316-343`; `toSummary()` visszaadja skill/metric/difficulty/tempoRange/contributingSessionCount/achievedAt |
| §6.1 alatt/rajta/fölött hármas | Mind a három cella lefedve | ✅ | `mastery_evaluator_test.dart:345-395`; a `rajta` teszt az inkluzív határt (`==minEvidenceSessions`) explicit igazolja |

## Scope-audit

`tools/scope-audit.py --repo /tmp/review-e08-r21 --brief docs/rounds/e08-r21-mastery-milestone-domain-and-evaluator.md --base a39c6b45` → **OK** (7 changed path(s), 0 generated/ignored). A `docs/adr/0388-...md` és a brief-revízió az orchestrátor pre-flight commitjában van (`a39c6b45`, `--base` ezt megelőzi), nem az implementer diffjében — helyesen a tilos zónán kívül esik erre a hívóra nézve.

Engedélyezett fájlokon kívüli implementer-változás: **nincs**.

## Megállapítások

### F1 — MAJOR — A monotonitás-garancia (A5/ADR 0388 5. döntés) ArgumentError-ral bukik egy zsugorodó friss evidence-batch-nél

- **Fájl:** `lib/features/gamification/application/mastery_evaluator.dart:51-55` (hívó), `lib/features/gamification/domain/mastery/mastery_progress.dart:182-196` (`advanceTo`, a `must not regress` guard)
- **Probléma:** Az `evaluate()` monoton ága (`previous.isAchieved && previous.badge != null`) `previous.advanceTo(evidenceSessionCount: distinctCount)`-ot hív. Az `advanceTo` viszont `ArgumentError`-t dob, ha az új `evidenceSessionCount` KISEBB, mint a korábban tárolt érték. Ha a friss `evidence` batch a korábbinál KEVESEBB minősítő session-t tartalmaz (pl. a hívó csak a legutóbbi sessionöket adja át, vagy egy korábbi bizonyíték utólag kiesik egy definíció-/verzióváltás miatt), a kiértékelő nem az elvárt „az elért állapot megmarad" választ adja, hanem **kivétellel megszakad**. Reviewer-próba (`/tmp/review-e08-r21`, ideiglenes teszt, törölve): 3 minősítő sessionnel elért progress + egy 1 elemű friss batch → `Invalid argument (evidenceSessionCount): must not regress: 1` a `mastery_progress.dart:191` sorból, `mastery_evaluator.dart:54`-en át dobva.
- **Hatás:** A brief §5.4 („A megszerzett mérföldkő nem vehető vissza egy későbbi gyengébb teljesítmény miatt") és az ADR 0388 5. döntése („a kiértékelő megőrzi ezt az időbélyeget… függetlenül attól, hogy az újonnan átadott bizonyíték-lista gyengébb vagy hiányos-e") pontosan ezt az esetet nevezi meg — egy hiányos/gyengébb friss batch nem regresszálhatja az állapotot. A jelenlegi kód ezt a garanciát egy kivétellel váltja fel egy valószínű hívási mintánál (a hívó nem köteles minden alkalommal a TELJES kumulált evidence-történetet visszaadni). A jelenlegi `A5` teszt csak az azonos-vagy-nagyobb session-számú esetet fedi, ezért a gate zölden ment át rajta.
- **Kötelező javítás:** a monoton ágban a session-számot ne a nyers `distinctCount`-tal, hanem a `math.max(distinctCount, previous.evidenceSessionCount)` értékkel hívja az `advanceTo`-t (vagy az `advanceTo`/`MasteryProgress` guard-ja engedje meg a csökkenést egy már elért progressnél, és belsőleg clampeljen a korábbi érték alá nem eső legkisebb értékre). A cél: az `evaluate()` SOHA ne dobjon kivételt egy már elért mérföldkőre, függetlenül a friss batch méretétől.
- **Ellenőrzés:** új teszteset — elért progress (pl. 3 minősítő session) + egy nála kisebb (pl. 1 elemű) friss batch → `evaluate()` NEM dob kivételt, `isAchieved` marad `true`, `achievedAt`/`badge` változatlan.
- **Státusz:** **FIXED** (`99c36e90`, 1. javító kör, motor: minimax). A monoton ág mostantól `clamped = distinctCount > previous.evidenceSessionCount ? distinctCount : previous.evidenceSessionCount`-tal hívja az `advanceTo`-t (`mastery_evaluator.dart:58-64`). Új teszt: `A5 monotonicity: achieved progress survives a SMALLER subsequent batch` (`mastery_evaluator_test.dart:206-253`) — a reviewer pontos reprodukciós forgatókönyvét (3 minősítő session elérve, majd 1 elemű friss batch) fedi, `evidenceSessionCount` a korábbi `3`-on marad, `achievedAt`/`badge` változatlan. Reviewer-oldali független ellenőrzés: friss izolált `/tmp/review-e08-r21-fix` klón, saját gate-futtatás (21/21 zöld, format/analyze/architecture/secrets/l10n mind zöld) + `scope-audit.py --base a39c6b45` → OK (8 changed path, 1 generated/ignored [a review-jelentés]).

### N1 — NOTE — `MasteryBadge` nem definiál `operator ==`/`hashCode`

- **Fájl:** `lib/features/gamification/domain/mastery/mastery_badge.dart`
- **Megfigyelés:** Az `A5` teszt (`expect(after.badge, badge)`) ma azért ad zöldet, mert a monoton ág ugyanazt az objektum-referenciát adja tovább — nem érték-egyenlőség alapján. Egy jövőbeli kör (perzisztencia/deszerializáció), ahol a badge új példányként épül fel ugyanazokkal az értékekkel, ezt az összehasonlítást hamisan buktatná. Nem blokkoló ebben a körben (tiszta in-memory domain, nincs perzisztencia a scope-ban), de érdemes felvenni a Kör 22/23 (UI-integráció) vagy egy perzisztencia-kör brief-jébe.
- **Státusz:** nem blokkol.

### §10.6 (implementer kérdés) — megválaszolva, nem lelet

A `MasteryTempoRange.contains()` inkluzív `minBpm == maxBpm` viselkedése (egy-BPM-es milestone lehetővé tétele) szándékos és a brief/ADR egyik pontjával sem ütközik — jóváhagyva változtatás nélkül.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (reviewer saját futtatás, izolált `/tmp/review-e08-r21` klón) |
| analyze | zöld (`No issues found!`) | ✅ |
| test `mastery_evaluator_test.dart` | 20/20 zöld | ✅ |
| architecture | zöld (12 allowlisted, változatlan a round előtti állapothoz képest — `tool/check_architecture.dart` a diffben nem szerepel) | ✅ |
| secrets | zöld | ✅ |
| l10n | zöld | ✅ |
| CI (Full Gate, teljes suite + property + coverage) | első dispatch (run 32534207301, head 5259e54c) elavult a javító kör után; a javítás utáni head-re (`99c36e90` + a review-jelentés commitja) újra-dispatch-elem merge előtt | lásd merge-döntés |

## Javító kör

1. javító kör, motor: `minimax`, ugyanazon a branch-en. F1 leletlistával
indítva (`.pipeline-fix` prompt, nem repo-fájl). Eredmény: `99c36e90`, gate
21/21 zöld helyben ÉS a reviewer saját, független `/tmp/review-e08-r21-fix`
klónjában is. F1 zárva. Nincs újabb nyitott BLOCKER/MAJOR.

## Merge-döntés

Az F1 javítva és independently újra-ellenőrizve. **Merge-előfeltétel:** a
javítás utáni HEAD-re (`99c36e90` + review-jelentés) exact-SHA CI-dispatch
és zöld futás (Full Gate + Router CI, ha érintett), utána squash-merge
külön jóváhagyás nélkül (ADR 0052).
