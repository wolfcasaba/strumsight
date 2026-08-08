# E05-R27 biztonsági review — AI Tutor és Analysis vision evidence adapterek

- **Kör:** E05-R27 · branch `codex/e05-r27-tutor-analysis-vision-adapters` · HEAD `6ba827c`
- **Diff:** `7570416..6ba827c` (14 fájl, +642/−1)
- **Reviewer:** `security-reviewer` ágens (READ-ONLY, AGENTS.md §15.1 — kötelező, `risk=high`)
- **Referencia-kontraktus:** `docs/rounds/e05-r27-tutor-analysis-vision-adapters.md`, `docs/adr/0194-tutor-analysis-vision-evidence-adapters.md`, AGENTS.md §5 / §5.1
- **Verdikt:** **PASS — nincs CRITICAL, nincs BLOCKER, nincs MAJOR.** 3 × MINOR (mind LATENS: nulla éles hívó, mindkét feature-flag `false`), 4 × NOTE. A biztonsági oldal a merge-et **nem blokkolja**. Az orchesztrátor a 3 MINOR-t egy javító körben zárja a merge előtt (a fő review-jelentés, `e05-r27-tutor-analysis-vision-adapters-review.md`, dönt a pontos hatályról).

## Osztályozás

| Súlyosság | Darab | Blokkol? |
|---|---|---|
| CRITICAL | 0 | — |
| BLOCKER | 0 | — |
| MAJOR | 0 | — |
| MINOR | 3 | nem (latens) |
| NOTE | 4 | nem |

---

## 1. A kör legkritikusabb állításának FÜGGETLEN megerősítése (tool-path)

Az orchesztrátor kérésére a `getContextField(field: "vision")` út viselkedését a kódból újrakövettem, az orchesztrátor állítására hagyatkozás nélkül — **az állítás igazolt**:

`lib/features/ai_tutor/application/tools/read_only_tutor_tools.dart:69-88`

1. `input.values['field']` = `"vision"` → a `length==1 && is String` kapu (70. sor) **átmegy**.
2. Enum-lookup (74-77. sor): `TutorContextFieldKey.values.where(name == "vision")`.
   - **Diff ELŐTT:** a `vision` enum-érték nem létezett → `fieldKey.length == 0` → `throw const TutorToolInputException()` (77. sor).
   - **Diff UTÁN:** az enum-érték létezik → `fieldKey.length == 1` → átmegy.
3. Snapshot-mező lookup (78-81. sor): `_snapshot.fields.where(key == vision)`. A `_snapshot.fields` élesben **soha** nem tartalmaz vision-mezőt (ld. §2), így `fields.length == 0` → `throw const TutorToolInputException()` (81. sor).
4. A registry (`tutor_tool_registry.dart:90-91`) mindkét dobást azonosan kapja el: `AppResult.failure(ValidationFailure())`.

A `TutorToolInputException` `const` és **üres** (`tutor_tool.dart:82-83`), a `ValidationFailure()` szintén const, mezők nélkül. **A kívülről megfigyelhető kimenet bitre azonos** a diff előtt és után (mindkét esetben `ValidationFailure`), és nincs oracle, amiből egy támadó megkülönböztethetné, hogy a `"vision"` érvényes enum-név-e vagy sem. **Nincs adatszivárgás, nincs viselkedésváltozás.** ✔

## 2. A `ContextPurpose` allow-list függetlenül ellenőrizve

`lib/features/ai_tutor/application/context/context_purpose.dart:13-59`: mind a hat `ContextPurpose.allowedFields` halmazát átolvastam — **egyik sem tartalmazza a `TutorContextFieldKey.vision`-t**. A `TutorContextAssembler` (`tutor_context_assembler.dart:33-40`) minden nem engedélyezett mezőt `purposeNotAllowed` omission-nel kihagy. Így a `TutorContextSnapshot.fields` **ma soha** nem tartalmaz vision-mezőt, függetlenül attól, hogy a `TutorVisionContextAdapter` előállít-e egyet. Production viselkedés bitre változatlan. ✔

## 3. Minimalizáció (a kör kulcsbizonyítéka) függetlenül ellenőrizve

`vision_context_snapshot.dart:32-38` — a `toJson()` pontosan 5 kulcs: `sessionId`, `sessionTimestampUs`, `insightCode`, `confidence`, `observationState`. **Nincs benne `VisionEvidence.value`** (a nyers metrika-double), sem frame/landmark/facePoints/imageUri. A `vision_context_snapshot_test.dart:13-37` pinneli a kulcslistát ÉS tiltott-mező mátrixot futtat. A szűk barrel (`domain/integration/public.dart`) a `vision_evidence.dart`-ból **kizárólag** `show ObservationState`-et re-exportál (snapshot 5. sor) — a `VisionEvidence` osztály (és így a `.value`) cross-feature fogyasztó számára a barrelen át **nem elérhető**. A nyers-adat termékhatár (AGENTS.md §5.1) **tartva**. ✔

---

## MINOR leletek (latens — nulla éles hívó, mindkét flag `false`)

### MINOR-1 — A Tutor-facing guard a korrekciós ("focus") állításokat 0.15-tel a szállított policy küszöbe ALATT engedi át

- **Hely:** `lib/features/vision/domain/integration/vision_claim_guard.dart:22` (`_minimumConfidence = 0.70`, egységes, irány-ág nélkül) vs. `lib/features/vision/domain/feedback/feedback_policy.dart:37-39,133` (`confidenceThreshold` = negatív irány → **0.85**). A guard katalógusa **tartalmazza** a három negatív-irányú kódot: `frettingFocus`, `pickingFocus`, `postureFocus` — ezek a szállított `FeedbackPolicies`-ban 0.85-ös kapun mennek át.
- **Failure scenario:** `guard.evaluate(claim: InsightCode.postureFocus, evidence: <posture-evidence, confidence 0.72>, confidence: 0.72)` → **`allowed`, code=postureFocus**. Ugyanez a korrekciós állítás a valós idejű cue-motorban (0.85-ös kapun) **blokkolt** lenne.
- **Sértett elv:** AGENTS.md §5 határ 5 ("gyenge confidence nem jelenhet meg biztos állításként").
- **Miért csak MINOR:** nincs éles hívó; a snapshot a numerikus confidence-t magával viszi (a "biztosként való megjelenítés" a prompt-réteg felelőssége, tiltott zóna); ADR 0194 Döntés 3 tudatosan független küszöböt választott.
- **Javasolt irány:** irányfüggő küszöb a guardban (0.85 a negatív kódokra), pinnelt teszttel.

### MINOR-2 — A snapshot `sessionId`-je nyers `String`, a redaktor tartalom-vak a string-értékekre → latens prompt-injection felület

- **Hely:** `vision_context_snapshot.dart:26` (`final String sessionId`). A redaktor (`redaction_report.dart:100-121`) a string-**értékeket** csak abszolút-út mintára szűri; a kulcsnév-alapú `_reasonForKey` a `sessionId` kulcsot nem tiltja, az értéket semmi nem szűri.
- **Failure scenario:** ha egy jövőbeli bekötés a `sessionId`-t felhasználó által befolyásolható szövegből származtatja, és egy jövőbeli `ContextPurpose` engedélyezi a `vision` mezőt, a szöveg szűretlenül átfolyik a trusted Tutor-kontextusba.
- **Bizonyíték a kockázatra:** a repóban MÁR létezik tipizált, rendszer-generált session-azonosító: `VisionSessionId` extension type (`lib/features/vision/domain/vision_session.dart:5-11`, `VisionSessionId.create` trim+nem-üres validációval). A snapshot ezt nem használja.
- **Javasolt irány:** tipizáld a `sessionId`-t `VisionSessionId`-ként.

### MINOR-3 — A Tutor-adapter tesztje nem futtat valódi network-spy-t, csak import-forrás-szöveg scant

- **Hely:** `test/features/ai_tutor/application/context/adapters/tutor_vision_context_adapter_test.dart:34-45` — nincs `HttpOverrides`-alapú kliens-számláló, szemben az `analysis_vision_adapter_test.dart:71-85`-tel. A brief §6 AC többes számban követeli: "az adapterek használata nulla hálózati kérést generál".
- **Miért MINOR:** a `TutorVisionContextAdapter.adapt` tiszta függvény, nincs Dio/http az import-gráfjában — a tulajdonság konstrukció szerint fennáll, csak a futásidejű bizonyíték hiányzik.
- **Javasolt irány:** másold az `analysis_vision_adapter_test.dart` `_NetworkSpyOverrides` celláját a Tutor-adapter tesztbe.

---

## NOTE leletek

- **NOTE-1 — A guard nem köti a claim-et az evidence metrika-családjához** (a szállított `FeedbackPolicy.supports()` ezt megteszi). `evaluate(claim: frettingStable, evidence: <posture-family evidence 0.9>, confidence: 0.9)` → `allowed`. ADR 0194 szerint tudatos scope (a guard "bizonyíték-elégségesség", nem "relevancia") — a jövőbeli integrátornak tudnia kell erről.
- **NOTE-2 — A guard csak a `notObservable` állapotot utasítja el; az `inferred` és `experimental` evidence-t elfogadja** — önmagában átlátszó (a `observationState` a snapshotban is jelzi), de nincs finomabb megfigyelés-minőség-differenciálás a küszöbön túl.
- **NOTE-3 — `vision_context_snapshot.dart` maga is re-exportál 3 típust** (`show`-korlátozva, biztonságos forrásfájlokból) a hivatalos szűk barrel mellett — ma nincs sértés, de a mintázat (leaf-fájl mini-barrelként) precedenst teremt.
- **NOTE-4 — `tutor_vision_context_adapter.dart:5` doc-commentje** ("Projects... through the redacted Tutor context") kicsit többet állít, mint amit a fájl maga tesz (az adapter nem redaktál, csak `TutorContextField`-et állít elő) — pontos, de túlbizakodásra adhat okot egy jövőbeli olvasónál.

---

## Amit még végignéztem, és nem találtam leletet

- **Titkok/logok:** nincs új log/analytics/storage-írás; a tesztfixture-ök egyértelműen fake-ek. Gate `secrets` lépés zöld.
- **Hálózat/consent:** `analysis_vision_adapter_test.dart` valódi `HttpOverrides` spy-ja 0 kliens-létrehozást bizonyít; forrás-scan a `dio`/`http`/`DateTime` hiányát pinneli. Nincs új permission, nincs wall-clock.
- **Importált tartalom / path traversal:** N/A, nincs fájl/archívum-kezelés a körben.
- **Numerikus fail-closed:** minden konstruktor elutasítja a nem-finite/negatív/tartományon-kívüli bemenetet, tesztelve.
- **Scope-audit (mechanikus):** 14 fájl mind az `allowed_paths`-on belül; a `tutor_context_snapshot.dart` diffje kizárólag a két additív enum-érték.
- **`SafetyClaimGuard` átfedés/rés:** a két őr ortogonális, nincs rés — a guard-katalógus 10 kódjának `safetyCode`-jai egyike sem illeszkedik a `SafetyClaimGuard` tiltott lexémáira; a `setupNotObservable` katalógusból való kihagyása helyes (ő maga a fallback/deny-kód).
- **Éles hívó / flag-állapot:** az öt új típus egyetlen használata sem éles (csak definíció + tesztek); mindkét feature-flag hard-coded `false`.

---

## Merge-ajánlás

Biztonsági szempontból **nincs merge-blokkoló**. A nyers-adat minimalizáció, a fail-closed claim-guard, a redakciós-út-megkerülés hiánya és a nulla-hálózat mind igazolt; a legkritikusabb állítás (a `vision` enum-bővítés nulla production-hatása) függetlenül reprodukálva, az orchesztrátor saját elemzésével egyező eredménnyel. A 3 MINOR mind LATENS, de a most beégetett biztonsági primitívek szemantikájáról szólnak — javaslat: MINOR-1 és MINOR-2 a R28 (bekötés) kör kötelező előfeltétele legyen, ha nem záródik már ebben a körben.
