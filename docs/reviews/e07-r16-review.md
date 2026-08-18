# E07-R16 — Review

Brief: `docs/rounds/e07-r16-progression-policy.md`
Diff: `ea6569fb..29be136a` (branch `terra/e07-r16-progression-policy`)
Reviewer: Claude (Sonnet 5) · Dátum: 2026-08-16
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 4

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Egyetlen adaptáció max EGY fokot lép | ✅ | `ProgressionPolicy._requireOneStep` a konstruktorban **strukturálisan** kizárja a ≠1 értéket (nem csak default); `adaptation_decider_test.dart` "A1" teszt (8 evidence → +1 minden dimenzióban); valódi-sértés próba brief §10-ben dokumentálva ÉS állandó regressziós tesztként is megmaradt (`progression_policy_test.dart` "rejects invalid… bounds": `ProgressionPolicy(maximumDifficultyStep: 2)` → `throwsArgumentError`) |
| A2 | Egy rossz session NEM okoz regressziót | ✅ | `ProgressionPolicy._requireRepeatedEvidence` strukturálisan kizárja a `repeatedStruggleEvidence < 2` értéket; `adaptation_decider_test.dart` "A2" (1 gyenge session → `maintain`, `next == current`) |
| A3 | Ismételt küzdelem regressziót okoz | ✅ | `adaptation_decider_test.dart` "A3" (2 gyenge session → `regress`, `difficultyLevel` −1) |
| A4 | Discomfort blokkolja az emelést, teljesítménytől függetlenül | ✅ | `adaptation_decider_test.dart` "A4" — 2 erős + 1 `pain`-discomfort evidence (a küszöb önmagában emelést adna) → mégis `maintain` |
| A5 | A „túl nehéz" jelzés azonnal hat | ✅ | `adaptation_decider_test.dart` "A5" — egyetlen `selfReport`+`frustration` evidence, evidence-küszöb és cooldown megkerülésével → azonnali `regress` |
| A6 | A cooldown alatt nincs újabb emelés | ✅ | `adaptation_decider_test.dart` "A6" + `progression_policy_test.dart` "A6" (határeset: 6 nap → cooldownban, pontosan 7 nap → szabad) |
| A7 | A tempó a támogatott tartományba van clampelve | ✅ | `adaptation_decider_test.dart` "A7" (175→180 advance-nél) + `progression_policy_test.dart` "A7" (30→40, 220→180 közvetlen unit-szinten) |
| A8 | Minden döntés evidence-hivatkozást hordoz | ✅ | `AdaptationDecision` konstruktora üres `evidenceIds`-t elutasítja; `AdaptationRequest` konstruktora üres `evidence`-t elutasítja — a lánc végig nem-üres; `adaptation_decider_test.dart` "A8" a stabil, rendezett `evidenceIds`-t és a `policyVersion` provenienciát is ellenőrzi |
| A9 | A korlátok egy helyen, a policyban vannak | ✅ | `AdaptationDecider` minden numerikus küszöböt `policy.*`-ból olvas, nincs szórt magic number a deciderben; `progression_policy_test.dart` "exposes all v1 bounds" tételesen felsorolja mind a 14 policy-mezőt |

A §6.1 evidence-küszöb hármas cellája mindhárom értéken lefedett: alatta
(`"one successful session below the minimum does not advance"`), rajta
(`"exactly the minimum successful sessions advance"`), fölötte (az "A1"
teszt 8 evidence-szel — emelés, de csak egy fokkal). A kötelező
valódi-sértés próba a brief §10-ében dokumentálva (`maximumDifficultyStep`
1→2, izolált A1 teszt PIROS lett a várt módon, majd visszaállítva) — ez a
guard emellett **állandó regressziós tesztként is bekerült** a szerkesztett
suite-ba, ami erősebb bizonyíték, mint a brief kért egyszeri manuális próba.

## Scope-audit

```
python3 tools/scope-audit.py --repo /home/ubuntu/ss-terra-e07-r16 --brief docs/rounds/e07-r16-progression-policy.md --base ea6569fb9ae0a9bb513a63c10e0eb5cc296a4d1a
→ Legacy scope audit OK (ea6569fb9ae0..29be136abea4, 7 changed path(s), 0 generated/ignored)
```

Mind a 7 megváltozott fájl a brief §4 engedélyezett listáján van (3 új
domain fájl, `public.dart` bővítés, 2 új teszt, a brief §10 handoff
kitöltése). Tilos zónában (más `lib/features/**`, `docs/adr/**`,
`docs/sdd/**`, `tools/**`, `.github/**`) nincs érintett fájl.

**A jelzésfájl `gate_shape=VIOLATION` mezője vizsgálva és FÉLREJELZÉSNEK
bizonyult**: az egyetlen illeszkedő log-sor (35738.) a `round-gate.sh`
FORRÁSÁT olvasta `sed -n '1,300p' tools/round-gate.sh`-sel, majd ezt
`&&`-lánccal kötötte össze FÜGGETLEN diagnosztikai parancsokkal
(`git status`, `git diff --check/--stat`) — nem a gate VÉGREHAJTÁSÁT
csonkolta vagy láncolta. A tényleges gate-hívások (log 165., 1794., 33688.,
37063., 39345., 44958. sor) mind önálló, csonkítatlan
`tools/round-gate.sh <útvonalak>` alakúak. A heurisztika (a naplóban
bárhol együtt szereplő `round-gate.sh` + `&&`/`| tail`/`| head`) ezt a
forrás-olvasást nem tudja megkülönböztetni egy tényleges csonkolástól —
ismert korlát, nem ennek a körnek a hibája.

## Megállapítások

### F1 — MINOR — `AdaptationAction`/`AdaptationReason` nem követi a repo-szintű stabil-kód dekódolási konvenciót

- **Fájl:** `lib/features/practice_generator/domain/model/adaptation_decision.dart:8-32`
- **Probléma:** Minden más ebben a feature-ben élő stabil-kódú enum-család
  (`CandidateSource`, `PlanStatus`, `BlockKind`, `ValidationSeverity`,
  `EvidenceSource`, `DiscomfortCategory`, `SchedulingPhase`,
  `ScheduleDecisionReason`, `ProgressionDirection`, `CandidateRejectReason`,
  `CandidateFactorKind`) egy szimmetrikus `fromCode(String? code)`
  dekódolót is ad, ami üres/ismeretlen kódra kontrollált hibát dob (ADR
  0257 §4, `plan_enums.dart` fejléc-dokumentációja). Az új
  `AdaptationAction` és `AdaptationReason` csak a `code` gettert adja,
  dekódolót nem.
- **Hatás:** Ma nincs hívó (a `AdaptationDecision`-nek — a `CandidateDecision`
  Kör 13 precedensét követve — nincs `toJson`/`fromJson`-ja sem, tehát
  jelenleg semmi nem dekódol), így éles hatás nincs. Egy jövőbeli
  perzisztencia-kör viszont vagy újra felfedezi ezt a hiányt, vagy —
  rosszabb esetben — `.name`-mel dekódol majd, ami az ADR 0257 §4 elleni
  csendes visszalépés lenne.
- **Kötelező javítás:** Nem kötelező ebben a körben (nem növeli érdemben a
  diffet, de nem is nulla — két kis statikus metódus + a megosztott
  `_decodeEnumCode` mintájának másolása). Ajánlott felvenni abban a körben,
  amelyik először perzisztálja az `AdaptationDecision`-t.
- **Státusz:** OPEN (follow-up, nem blokkoló)

### F2 — NOTE — A discomfort/repeated-struggle elsőbbség nem tesztelt kombináció

- **Fájl:** `lib/features/practice_generator/domain/service/adaptation_decider.dart:37-67`
- **Megfigyelés:** A `decide()` a discomfort-ellenőrzést (§5.3, 2. ág) a
  repeated-struggle-ellenőrzés (§5.4/A3, 4. ág) ELÉ helyezi. Ha egy
  request egyszerre hordoz discomfort-evidence-t ÉS eléri a
  `repeatedStruggleEvidence` küszöböt, az eredmény `maintain` +
  `discomfortBlocksAdvance` — a `regress` ág sosem fut le. A brief §5.3
  szó szerint csak az EMELÉST tiltja diszkomfort esetén ("nincs
  nehezítés"), tehát ez a viselkedés a szöveg szerint védhető, de a
  brief egyetlen acceptance-cellája sem teszteli explicit ezt a
  kombinációt, és pedagógiailag is elképzelhető lenne, hogy ilyenkor a
  helyes válasz éppen a regresszió (könnyítés), nem a `maintain`.
- **Ajánlás:** Egy jövőbeli körben (vagy ha a termék-oldal megerősíti a
  szándékot) érdemes egy explicit acceptance-cellát és tesztet adni erre a
  kombinációra — akár a jelenlegi `maintain`, akár egy `regress` a helyes
  válasz, most implicit.
- **Státusz:** OPEN (nem blokkoló, tisztázásra vár)

### F3 — NOTE — `evidenceIds` az ÖSSZES bemeneti evidence-t hordozza, nem csak az érdemben számításba vettet

- **Fájl:** `lib/features/practice_generator/domain/service/adaptation_decider.dart:20-22`
- **Megfigyelés:** `evidenceIds` a nyers `request.evidence`-ből épül, nem a
  döntéshez ténylegesen használt, `asOf`-nál érvényes `validEvidence`
  szűrt listából. Egy lejárt/érvénytelen evidence-elem tehát megjelenik a
  döntés provenienciájában, holott semmilyen szerepet nem játszott a
  végeredményben — ez enyhén gyengíti az §5.6 "megnevezi, MELY evidence
  alapján döntött" explainability-ígéretét. Az A8 teszt szó szerinti
  elvárását (nem-üres, stabil, rendezett hivatkozás) ez nem sérti.
- **Státusz:** OPEN (nem blokkoló megfigyelés)

### F4 — NOTE — Nincs közvetlen unit-teszt a `supportsTempo=false` ágra és a request/profile-validációkra

- **Fájl:** `lib/features/practice_generator/domain/service/adaptation_decider.dart:186-190` (`_nextTempo` korai `return null` ága), `lib/features/practice_generator/domain/model/adaptation_decision.dart` (`AdaptationRequest`/`DifficultyProfile` konstruktor-validációk: duplikált `sourceOutcomeId`, `skillId`-eltérés, jövőbeli `lastAdvanceAt`, negatív mezők, tempo/`supportsTempo` inkonzisztencia)
- **Megfigyelés:** Mindkét teszt-fájl kizárólag `supportsTempo: true`
  profilt használ, és egyik konstruktor-validációs ágat sem hívja hibás
  bemenettel. A brief §6 kötelező teszt-listája (threshold, single bad
  session, repeated struggle, comfort guard, cooldown, tempo clamp) ezt
  nem írja elő explicit, úgyhogy nem hiányzó acceptance — de valódi,
  jelenleg nem lefedett kódág/branch.
- **Státusz:** OPEN (follow-up javasolt, nem blokkoló)

### F5 — NOTE — „Egy fok" mind a négy dimenziót együtt mozdítja

- **Fájl:** `lib/features/practice_generator/domain/service/adaptation_decider.dart:159-184`
- **Megfigyelés:** Az `_advance`/`_regress` a `difficultyLevel`,
  `loopCount`, `variationLevel` és `strictnessLevel` mezőt EGYSZERRE, azonos
  `policy.maximumDifficultyStep` nagysággal mozdítja; a tempó külön,
  fixpontos `tempoStepBpm`-mel. Ez egy védhető olvasata az ADR 0265 2.
  döntésének ("legfeljebb EGY nehézségi fokot mozdít") — a valódi-sértés
  próba is ezt igazolja —, de az SDD/ADR szövege nem mondja ki
  explicit, hogy a négy dimenzió együtt vagy egymástól függetlenül mozog.
  Ha egy jövőbeli kör (pl. Kör 18 orchestrator) más olvasatot feltételez,
  ez a pont tisztázásra szorul.
- **Státusz:** OPEN (tervezési megfigyelés, nem blokkoló)

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ független újrafuttatás: `tools/round-gate.sh` a review-klónon, "Formatted 1588 files (0 changed)" |
| analyze | zöld | ✅ "No issues found!" |
| test `adaptation_decider_test.dart` | zöld | ✅ 11/11 teszt PASS |
| test `progression_policy_test.dart` | zöld | ✅ 4/4 teszt PASS |
| architecture | zöld | ✅ "Architecture dependencies OK (12 allowlisted deviation(s))" — a 12 meglévő, ehhez a diffhez nem kapcsolódó |
| secrets | zöld | ✅ "0 finding(s)" |
| l10n parity | zöld | ✅ (ez a kör nem érint ARB-ot, a lánc mégis lefutott és zöld) |
| scope-audit | ok | ✅ önálló `tools/scope-audit.py` futtatással megerősítve |
| CI (teljes suite + property + APK/full-gate) | — | ⏳ dispatch ez után következik |

## Merge-döntés

Nincs nyitott BLOCKER/MAJOR — a review önmagában **nem** tiltja a merge-et.
A brief `risk = "high"`, ezért az `AGENTS.md` §15.1 szerint kötelező
biztonsági review (`security-reviewer`, `docs/reviews/e07-r16-security.md`)
is szükséges CRITICAL/BLOCKER nélkül, mielőtt a CI-zöld után squash-merge
történik.
