# E05-R27 — Review

Brief: `docs/rounds/e05-r27-tutor-analysis-vision-adapters.md`
ADR: `docs/adr/0194-tutor-analysis-vision-evidence-adapters.md`
Diff: `git diff 7570416..6ba827c` (pre-flight commit → implementer commit), egyenértékű `git diff origin/main...codex/e05-r27-tutor-analysis-vision-adapters`-szel
Reviewer: Claude Sonnet 5 (orchesztrátor) · Dátum: 2026-08-08
Implementer: Terra (Codex CLI, `gpt-5.6-terra`), 1 forduló, jelzés: `done`
Verdikt: **CHANGES REQUESTED** (csak MINOR-szintű leletek — a merge-et biztonsági/gate szempontból semmi nem tiltja, de a kockázat=high besorolás és a leletek olcsó zárhatósága miatt egy javító kört kérek a merge előtt)

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 3 · NOTE: 3

A 3 MINOR mindegyikét a dedikált biztonsági review (`e05-r27-tutor-analysis-vision-adapters-security.md`) találta; a saját, független kódolvasásom megerősítette mindháromra. Nincs önálló MAJOR/BLOCKER lelet ezen a felül.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Minimization snapshot teszt (pinnelt kulcshalmaz) | ✅ | `vision_context_snapshot_test.dart:13-19` — `toJson().keys` pontos, sorrendezett lista-egyezés 5 kulcsra |
| 2 | Tiltott-mező mátrix (frame/landmark/arcpont/kép-URI) | ✅ | `vision_context_snapshot_test.dart:21-34` — mind a 4 tiltott kulcsnév ellenőrizve; a típus konstrukció szerint sem tud ilyen mezőt hordozni (erősebb garancia, mint a szöveges AC kér) |
| 3 | Claim-guard mátrix (confidence alatt/rajta/fölött × evidence van/nincs, 6 cella) | ✅ | `vision_claim_guard_test.dart:12-64` — pontosan 6 sor, 0.69/0.70/0.71 × evidence null/jelen; + külön teszt a `notObservable`/alacsony-evidence-confidence esetre |
| 4 | Fallback-teszt (`notObservable`, kétszeri futás azonos) | ✅ | `vision_claim_guard_test.dart:66-74` |
| 5 | Analysis round-trip (közös session-idő, wall clock nincs) | ✅ | `analysis_vision_adapter_test.dart:9-25` (round-trip) + `:87-101` (forrás-scan: nincs `DateTime`) |
| 6 | Network-spy teszt (adapterek, nulla hálózati kérés) | ⚠️ RÉSZLEGES | Analysis-adapter: valódi `HttpOverrides` spy, `analysis_vision_adapter_test.dart:71-85` — ✅. Tutor-adapter: **nincs** ilyen teszt, csak import-forrás-scan (`tutor_vision_context_adapter_test.dart:34-45`) — a tulajdonság igaz (nincs Dio/http import), de futásidejű bizonyíték hiányzik. Ld. F1/MINOR-3. |
| 7 | Valódi-sértés próba (§10) | ✅ | Brief §10 „Implementation handoff" dokumentálja a pontos próba-kimenetet (landmark-kulcs ideiglenes felvétele → a kulcslista-teszt PIROS lett, `Which: ... longer than expected`); a próba nincs a végleges diffben (visszaállítva) |
| 8 | SDD Chapter 5/7 integrációs jegyzet | ✅ | `docs/sdd/05-epic-04-ai-guitar-teacher.md:4600-4602`, `docs/sdd/07-epic-06-audio-analysis-2.md:4388` — mindkettő additív, tartalmilag pontos. Ld. F3/NOTE a szöveg elhelyezéséről. |

7,5/8 kritérium teljes bizonyítékkal; a #6 részleges (ld. F1).

## Scope-audit

`git diff --stat 7570416..6ba827c` = 14 fájl, mind a brief `allowed_paths` 17 bejegyzésén belül (a 3 nem érintett: `ai_tutor/public.dart`, `analyze/public.dart` — helyesen kihagyva, nincs élő cross-feature hívó ebben a körben —, és `docs/adr/0194-*.md`, amit az implementer nem is módosít). `tools/round-ci-plan.py` `origin/main...branch` alapon 15 egyedi fájlt lát (a plusz 1 az orchesztrátor pre-flight-commitjából, `docs/adr/0194-*.md`), ugyanaz az eredmény.

**Engedélyezett fájlokon kívüli változás: nincs.**

A `tutor_context_snapshot.dart` diffjét külön, sor szinten ellenőriztem: KIZÁRÓLAG a két additív enum-érték (`TutorContextFieldKey.vision`, `ContextSourceFeature.vision`) — a `context_purpose.dart`/`context_budget.dart` fájlok bájtra érintetlenek, ahogy az ADR 0194 Döntés 5 előírta.

## Megállapítások

### F1 — MINOR — Network-spy teszt hiányzik a Tutor-adapterre (AC #6 részleges)

- **Fájl:** `test/features/ai_tutor/application/context/adapters/tutor_vision_context_adapter_test.dart:1-46`
- **Probléma:** a fájl 3 tesztje egyike sem futtat valódi hálózat-spy-t (`HttpOverrides`); csak egy import-forrás-szöveg-scan van (barrel-boundary). A brief §6 AC szó szerint többes számban ("az adapterek") követeli a nulla-hálózat bizonyítékot mindkét adapterre.
- **Hatás:** a tulajdonság (nincs hálózati hívás) igaz és stabil, mert az `adapt()` metódus (`tutor_vision_context_adapter.dart:12-22`) tiszta függvény — csak `snapshot.toJson()`-t hív és egy `TutorContextField`-et konstruál, nincs Dio/http az import-gráfban. A hiány tehát nem funkcionális hiba, hanem bizonyíték-lefedettségi rés: egy jövőbeli, gondatlan edit hálózati hívást vezethetne be anélkül, hogy bármelyik teszt PIROS lenne.
- **Kötelező javítás:** másold az `analysis_vision_adapter_test.dart:103-111`-beli `_NetworkSpyOverrides` osztályt (vagy egyenértékű mechanizmust) a Tutor-adapter tesztfájlba, és fuss egy `HttpOverrides.runZoned` alatt egy `adapt()` hívást, elvárva `clientCreations == 0`-t.
- **Ellenőrzés:** az új teszt zöld, és a `tools/round-gate.sh test/features/ai_tutor` a bővítés után is zöld marad.
- **Státusz:** OPEN → javító kör kéri.

### F2 — MINOR — `VisionClaimGuard` egységes küszöbe a szállított `FeedbackPolicy` negatív-irányú küszöbe (0.85) alatt engedi át a korrekciós ("Focus") kódokat

*(a dedikált biztonsági review MINOR-1 leletének átvétele, saját kódolvasással megerősítve.)*

- **Fájl:** `lib/features/vision/domain/integration/vision_claim_guard.dart:22,46,48` vs. `lib/features/vision/domain/feedback/feedback_policy.dart:37-39,76,91,106`
- **Probléma:** a guard egyetlen, iránytól független `_minimumConfidence = 0.70`-et használ minden katalógus-kódra, beleértve a 3 negatív-irányú (`frettingFocus`/`pickingFocus`/`postureFocus`) kódot is — miközben a MEGLÉVŐ, szállított `FeedbackPolicies` katalógus ugyanezekre a kódokra `negativeConfidenceThreshold = 0.85`-öt ír elő.
- **Hatás:** ha ez a snapshot valaha bekötésre kerül (R28+), egy "javíts a testtartásodon" jellegű korrekciós vizuális állítás 0.70–0.84 közötti confidence-szel átmenne a Tutor-facing guardon, miközben a termék saját, lezárt E05-R23 policy-ja szerint ez alatt-küszöbű, tehát a valós idejű cue-rendszer ugyanezt elutasítaná. Ma nulla hatás (nincs élő hívó, mindkét flag `false`).
- **Kötelező javítás:** vezess be egy második, magasabb küszöböt (`_minimumNegativeConfidence = 0.85`) a 3 negatív-irányú kódra, `FeedbackPolicies` mintájára; a pozitív/semleges kódok maradjanak 0.70-en.
- **Ellenőrzés:** a meglévő 6-cellás mátrix (`InsightCode.frettingStable`-re) változatlan marad; egy ÚJ, párhuzamos cellahármas egy negatív kódra (pl. `postureFocus`) 0.84/0.85/0.86 confidence-szel, ami pontosan a 0.85-ös határnál vált allowed/blocked között.
- **Státusz:** OPEN → javító kör kéri.

### F3 — MINOR — `VisionContextSnapshot.sessionId` nyers `String`, a meglévő tipizált `VisionSessionId` helyett

*(a dedikált biztonsági review MINOR-2 leletének átvétele, saját kódolvasással megerősítve.)*

- **Fájl:** `lib/features/vision/domain/integration/vision_context_snapshot.dart:26`
- **Probléma:** a `sessionId` mező nyers `String` (csak trim+nem-üres validációval), miközben a repóban MÁR létezik egy tipizált, rendszer-generált session-azonosító (`VisionSessionId` extension type, `lib/features/vision/domain/vision_session.dart:5-11`, `.create()` faktorral).
- **Hatás:** a `ContextRedactor` (`redaction_report.dart`) a string-ÉRTÉKEKET tartalom szerint nem szűri (csak a mező-KULCSOT dönti el allowed/omitted). Amíg a `sessionId` nyers `String`, semmi nem tereli a jövőbeli integrátort a rendszer-generált, nem-felhasználó-vezérelt forrás felé — egy jövőbeli, gondatlan bekötés (pl. import-fájlnévből vagy felhasználói címkéből származó session-azonosító) szűretlen szabad szöveget vinne a redaktált Tutor-kontextusba. Ma nulla hatás (nincs élő hívó).
- **Kötelező javítás:** cseréld a `sessionId` mező típusát `VisionSessionId`-re; a szűk barrel (`vision/domain/integration/public.dart`) kapjon egy `export '../vision_session.dart' show VisionSessionId;` sort (a testvér `VisionSession` osztály NE kerüljön exportra); a `toJson()` `sessionId.value`-t szerializáljon.
- **Ellenőrzés:** a két érintett teszt (`vision_context_snapshot_test.dart`, `tutor_vision_context_adapter_test.dart`) a string-literált `VisionSessionId(...)`-re cserélve továbbra is zöld; `flutter analyze` nem jelez típushibát.
- **Státusz:** OPEN → javító kör kéri.

### F4 — NOTE — SDD Chapter 5 jegyzet elhelyezése megtöri az eredeti mondat folyamatosságát

- **Fájl:** `docs/sdd/05-epic-04-ai-guitar-teacher.md:4598-4603`
- **Probléma:** az új bekezdés az „Az Epic 4 lezárása után kezdhető el:" mondat ÉS az általa bevezetett kódblokk (`Chapter 6 — Epic 5: Computer Vision`) KÖZÉ került, ami az eredeti mondat-tárgy kapcsolatot vizuálisan megszakítja.
- **Hatás:** kizárólag olvashatósági, nem tartalmi/architekturális kérdés.
- **Kötelező javítás:** nincs — opcionális follow-up (a bekezdés a kódblokk UTÁN is állhatna).
- **Státusz:** WONTFIX (nem éri meg egy külön diffet egy tisztán kozmetikai kérdésért).

### F5 — NOTE — A guard két, egymástól független confidence-bemenetet fogad (`evidence.confidence` ÉS a hívó saját `confidence` paramétere)

- **Fájl:** `lib/features/vision/domain/integration/vision_claim_guard.dart:42-49`
- **Megfigyelés:** a `evaluate()` mindkét confidence-értéket a küszöb fölé követeli (AND, nem OR). Ez szándékosnak és helyesnek tűnik (a hívó `confidence` paramétere a levezetett `VisionInsight.confidence`-nek felel meg, ami eltérhet az alap `VisionEvidence.confidence`-től egy jövőbeli fúziós lépés után) — a 6-cellás AC mátrix pontosan lefedi ezt a viselkedést. Nem lelet, csak dokumentált megfigyelés a jövőbeli olvasóknak.
- **Státusz:** nem blokkol.

### F6 — NOTE — A biztonsági review 4 további NOTE-ot rögzített

Ld. `e05-r27-tutor-analysis-vision-adapters-security.md` NOTE-1–4 (guard–evidence metrika-család relevancia-ellenőrzés hiánya; `experimental`/`inferred` evidence megkülönböztetés hiánya a guardban; a snapshot-fájl saját mini-barrel-jellege; egy doc-comment enyhe túlállítása). Egyik sem blokkol, mindegyik dokumentált follow-up.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer) | Függetlenül ellenőrizve |
|---|---|---|
| format | zöld | ✅ — saját, izolált `/tmp/review-E05-R27` klónban újrafuttatva |
| analyze | zöld | ✅ |
| test test/features/vision | zöld | ✅ |
| test test/features/ai_tutor | zöld | ✅ |
| test test/features/analyze | zöld | ✅ (64 teszt, „All tests passed!") |
| architecture | zöld (12 allowlistelt eltérés — MEGLÉVŐ, nem ebből a körből) | ✅ |
| secrets | zöld (2054 fájl vizsgálva, 0 lelet) | ✅ |
| l10n | zöld (1002 üzenet, en↔hu paritás) | ✅ |
| CI (teljes suite + property + APK) | — | Pending — a merge előtti dispatch az orchesztrátor dolga (ADR 0053) |

A gate-et **saját kézzel, izolált `/tmp/review-E05-R27` klónban** futtattam újra (nem a közös munkafán, nem az implementer saját munkapéldányában) — a teljes napló: `/tmp/review-E05-R27-gate.log`. Minden lépés `ZÖLD`, a végső összegzés „MINDEN GATE ZÖLD".

## Biztonsági review

Dedikált, kötelező (`risk=high`) review: [`e05-r27-tutor-analysis-vision-adapters-security.md`](e05-r27-tutor-analysis-vision-adapters-security.md) — **PASS, 0 CRITICAL/BLOCKER/MAJOR**, 3 MINOR (F1–F3 fent, ugyanaz a három lelet, két független módszerrel megerősítve), 4 NOTE.

## Merge-döntés

A zöld kapu (ADR 0052) minden eleme megvan, és nincs nyitott BLOCKER/MAJOR — **biztonsági/gate szempontból a merge ma is mehetne.** Mindazonáltal a 3 MINOR (F1–F3) mindegyike szűk, olcsó, a meglévő `allowed_paths` listán belül javítható, és a kör kockázat=high besorolása + a "csak valid bizonyítékból beszélhet" céljának pontosan a MÉRT szemantikáját érinti (küszöb-konzisztencia, típusbiztonság, teszt-lefedettség) — ezért **egy javító kört kérek a merge előtt**, ugyanazzal a motorral (Terra), a fenti F1–F3 leletlistával. A javító kör után a gate-et újra lefuttatom, és ezt a jelentést APPROVED-ra frissítem.
