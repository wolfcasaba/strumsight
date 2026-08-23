# E08-R26 — Review

Brief: docs/rounds/e08-r26-cross-feature-gamification-integration.md (post
pre-flight revision, ADR 0392)
Diff: `git diff edcf7ae4..c5b7b6e5` (pre-flight commit → implementer HEAD),
branch `minimax/e08-r26-cross-feature-gamification-integration`
Reviewer: Claude Sonnet 5 (orchestrator) + `security-reviewer` agent (risk = "high")
Dátum: 2026-08-22
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 3

Gate újrafuttatva SAJÁT kézzel, izolált klónban (`/tmp/review-e08-r26`,
klónozva közvetlenül a GitHub originből, nem a megosztott munkafából):
`tools/round-gate.sh test/features/gamification/integration/cross_feature_reward_flow_test.dart
test/core/architecture_dependency_test.dart` → **MINDEN GATE ZÖLD** (format,
analyze, 2 test-útvonal — 16 cross-feature-reward teszt + 37
architecture-dependency teszt —, architecture, secrets, l10n).

Scope-audit (`tools/scope-audit.py --repo /tmp/review-e08-r26 --brief
docs/rounds/e08-r26-cross-feature-gamification-integration.md --base
edcf7ae4` — a bázis a pre-flight commit, ami az implementer indulási
HEAD-je volt, NEM `2dc9a149`, ami tévesen az orchestrátor SAJÁT ADR-commitját
is a diffbe vonná): `Legacy scope audit OK (7 changed path(s), 0
generated/ignored)` — pontosan a négy adapter + a két teszt-útvonal +
a brief saját fájlja, semmi más.

`security-reviewer` agent (risk="high" a brief ai-router blokkjában, AGENTS.md
kötelező): **PASS**, 0 BLOCKER/MAJOR, 2 NOTE (lásd lent).

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Tutor-beszélgetés önmagában NULLA XP-t ad | ✅ | `gamification_tutor_adapter.dart` ZÉRÓ importtal az `ai_tutor`-ból (§0.0/1 mint pinned E04-R01 guard, `ai_tutor_boundary_test.dart`); `recordConversation` minden ágon `noOp()`-ot ad. Teszt: `cross_feature_reward_flow_test.dart` „A1: a tutor conversation emits NO event", „A1: even… an hour…", „A1 valódi-sértés próba" (3 zöld cella; a próba egy valódi, önálló `_BrokenTutorAdapter`-t futtat a valós ingestor/eligibility/policy láncon át, és bizonyítja `totalXp > 0`-t — a produkciós adapter ezt az ágat nem futtatja). |
| A2 | Alacsony megbízhatóságú Vision-eredmény nem ad technikai haladást, alap-XP jár | ✅ | `gamification_vision_adapter.dart` két esemény (`vision-base`, `vision-technical`), a második csak `VisionClaimGuard.evaluate().isAllowed` esetén. §6.1 küszöb-hármas szó szerint tesztelve: `0.69` (alatt, nincs technical), `0.70` (rajta, VAN — a guard `confidence < minimumConfidence` szigorúan-kisebb feltétele miatt a küszöb maga elfogadó), `0.71` (fölött, VAN) — mindhárom zöld. Hiányzó evidence külön cellában fail-close. |
| A3 | A terv befejezése csak bónuszt ad; a blokkok jutalma nem ismétlődik | ✅ | `gamification_plan_adapter.dart` caller-fed `planCompleted: bool`-t fogad (§0.0/4 — `PlanStatus.completed` mérve elérhetetlen), és a ledger-bejegyzésben `bonusXp` KÉNYSZERÍTETTEN `0` (`_buildLedgerEntry:302`) — csak a policy `baseXp`-je kerül a főkönyvbe. Teszt: 1 esemény fixen `bonusXp==0`; `planCompleted=false` → nincs esemény; reopen ugyanarra a `planId`-ra collapszol; valódi-sértés próba (`_BrokenAggregatingPlanAdapter`) bizonyítja, hogy egy blokk-összegző ág `bonusXp > 0`-t termelne. |
| A4 | Ugyanazon felvétel újraelemzése AZONOS elemző-verzióval nem ad új jutalmat | ✅ | `eventIdFor(sourceHash, analyzerVersion)` determinisztikus; két hívás ugyanazzal a jellel ugyanazt az `eventId`-t adja, a ledger append-if-absentje egy bejegyzésen marad. |
| A5 | ÚJ elemző-verzió új jutalmat ad | ✅ | Verzióváltás új `eventId`-t termel, a ledger bejegyzésszáma nő; valódi-sértés próba (`_BrokenHashOnlyAnalysisAdapter`, csak `sourceHash`-re dedupol) bizonyítja, hogy a hash-only alak a verzióváltást is nullázná. |
| A6 | Az adapterek CSAK public szerződést importálnak | ✅ | `architecture_dependency_test.dart` új „cross-feature gamification adapter boundary — A6 (E08-R26)" csoport (5 teszt): mind a négy adapter csak a gamification `public.dart`-on át ér gamification-t; mindegyik a SAJÁT forrás-feature-ét csak public barrelen(eken) át éri el (a vision-nél mindkét elfogadott barrel: top-level `vision/public.dart` — `InsightCode`/`VisionEvidence` innen jön, mert a szűkebb `domain/integration/public.dart` ezeket NEM exportálja újra — és a szűkebb `domain/integration/public.dart` a `VisionClaimGuard`-hoz, ADR 0392 3. döntés/§0.0-6 kifejezetten mindkettőt engedi); nincs kereszt-feature „bleed" egy testvér-feature belsejébe. A `check_architecture.dart` (12 allowlisted deviáció, változatlan) is zöld. |
| A7 | Hiányzó forrás-feature esetén a build és a folyamat ép marad | ✅ | Mind a négy adapter `featureEnabled: false` esetén `noOp()`-ot ad, fordítási hiba nélkül (1 teszt, mind a négy adapterre). |
| A8 | Semmilyen új AI-hívás nem történik a jutalmazási úton | ✅ | Forrás-szintű scan mind a négy adapter fájlon 12 tiltott import-mintára (http, dio, google_mlkit_*, tflite_flutter, flutter_tts, speech_to_text, image_picker, audioplayers, webview_flutter, flutter_localizations, mobile_scanner, health) — egyik sem található; a `security-reviewer` agent függetlenül megerősítette (grep http/dio/socket/Random/secret/token/File/Process/dart:io → nincs találat egyik fájlban sem). |

## §0.0 pre-flight revízió (ADR 0392) — implementáció-hűség

A négy mért pont mindegyike pontosan a tervezett caller-fed mintát követi:
1. `ai_tutor` ZÉRÓ import — igazolva import-listával.
2. `AnalyzeResult` nem bővült; `sourceHash`+`analyzerVersion` caller-fed mezőként landolt.
3. Vision-küszöb a mért `VisionClaimGuard._minimumConfidence=0.70` szimbólumon és a `domain/integration/public.dart` barrelen keresztül — az implementer egy jól indokolt, a §0.0/6 által kifejezetten megengedett kiegészítést tett (a top-level `vision/public.dart` is kell az `InsightCode`/`VisionEvidence` bemeneti típusokhoz, amit a §10 handoff dokumentál).
4. `PlanStatus.completed` NEM került megérintésre; a plan-adapter caller-fed `planCompleted: bool`-lal dolgozik, `active_plan_controller.dart`/`generation_orchestrator.dart` érintetlen (tilos zóna tiszteletben tartva).

## Próbatesztek (a review saját mérése)

- Az implementer 3 „valódi-sértés próbáját" (§6.1 A1/A3/A5) magam is elolvastam
  forráskódszinten: mindegyik egy ÖNÁLLÓ (nem alosztályozott) törött adapter-
  osztály, ami a VALÓDI `ActivityEventIngestor`/`RewardEligibilityPolicy`/
  `RewardPolicy` láncon fut át, és a teszt ténylegesen `expect(...,
  greaterThan(0))` / `expect(outcome.accepted, isTrue)` jellegű, a törött ágon
  MÁSKÉNT viselkedő asszerciót futtat — ezek valódiak, nem üres váz.
- Ledenger-mezőkig követtem minden caller-fed String-et (`sessionId`,
  `sourceHash`, `analyzerVersion`, `planId`) mind a négy adapterben: a
  `sourceHash` SHA-256 hash-elve landol (`practiceKey`), a `sessionId`/`planId`
  nyersen landol az `eventId`/`ledgerId`-ban — ez az ELFOGADOTT E08-R25
  precedens mintája (a dal-adapter is csak a title-eredetű `songId`-t hasheli,
  a session-azonosítót nyersen használja).

## NOTE-ok (nem blokkoló)

1. **`analyzerVersion` az egyetlen hash nélküli, caller-fed szabad string,
   ami szó szerint a ledgerbe kerül** (`gamification_analysis_adapter.dart`
   `_safeAnalyzerVersion`, csak `/`→`_` csere, nincs charset-korlát). Ma nincs
   hívó (unwired), tehát nem reprodukálható — de a jövőbeli analyze-wiring
   körnek kötnie kellene ezt charset-validációval vagy hasheléssel, tükrözve
   a `sourceHash` kezelését.
2. **A caller-fed jel-típusok (`sessionId`/`planId`/`sourceHash`/
   `analyzerVersion`) nyers `String`-ek, nem a típusos, charset-lezárt
   azonosítók** (pl. `PlanId`). Ma unwired, tehát nem reprodukálható — a
   jövőbeli UI-wiring körnek típusos id-t vagy explicit charset/hossz-
   validációt kellene bevezetnie a határon.
3. **A `utf8Bytes()` segédfüggvény** (`gamification_analysis_adapter.dart:305-306`)
   NEM valódi UTF-8 kódolás (`codeUnits.map((u) => u & 0xff)`, ami csak
   ASCII-bemenetre helyes) — ez egy MÁR MERGE-ELT minta szó szerinti
   másolata az E08-R25 dal-adapterből (`gamification_song_adapter.dart:540-541`),
   tehát NEM ez a kör vezette be, és a mai (hex-hash) bemenetekre helyesen
   működik. Egy jövőbeli körnek érdemes lenne a `dart:convert` `utf8.encode()`-ra
   cserélnie mindkét helyen, és megosztott helyre kiemelnie a duplikációt.

## Döntés

**APPROVED.** Nincs nyitott BLOCKER/MAJOR/MINOR. A három NOTE egyike sem
blokkolja a merge-et — mindhárom unwired, jövőbeli-kör hatókörű megfigyelés.
CI-dispatch: `full-gate.yml` (`tools/round-ci-plan.py` ajánlása — tisztán
Dart/dokumentum-diff, nincs natív/release-útvonal), a Router CI is várt
(`docs/rounds/**` érintett).
