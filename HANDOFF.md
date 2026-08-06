# HANDOFF — StrumSight 🎸

> **Read this first at the start of every session.** Single source of truth for
> "what's done / what's next" — short operational snapshot (SDD Ch2 §16.6
> structure since E01-R16). Update after every round (see
> [How to update](#how-to-update-this-file)). Last updated: **2026-08-06
> (E04-R19 MERGED — Evidence/source/action card UI, provenance chip + typed-executor
> preview + validated plan-edit, nincs új ADR / ADR 0132+0133 hatálya; MiniMax M3,
> exact-SHA zöld kapun át).**
>
> ## ✅ E04-R19 KÉSZ — Evidence, source & action card UI (2026-08-06)
>
> **E04-R19** MERGED (PR [#152](https://github.com/wolfcasaba/strumsight/pull/152),
> squash `f0f74fb`, **nincs új ADR** — az ADR 0132 (privacy/sanitize) + 0133
> (tool-confirmation/typed-executor) hatálya; implementer **MiniMax M3**,
> orchestrátor/reviewer **Claude Opus 4.8**). A tutor **állításainak és
> műveleteinek** átlátható, megerősíthető UI-ja: `TutorEvidenceChip` (prezentációs
> `TutorEvidenceKind` provenance-négyes — measured/trend/knowledge/inference —
> **text+ikon+szín**, a11y); `TutorSourceSheet` (+ `sanitizeTutorDisplayText`:
> control-char/bidi-strip, `<`/`>` semlegesítés; `chunkHash` privát érték sosem
> renderel); `TutorActionCard` (exact `preview.fields`, confirm/reject/**stale**/
> failed, idempotens confirm — kizárólag `ActionConfirmationService` typed executor,
> nyers route/URL/string lehetetlen); `PracticePlanPreviewScreen` (blokk-szerkesztés
> `copyWith`+`PracticePlanSource.userEdited`, validált save/start). en/hu ARB additív.
> 14 új widget-cella. **Pre-flight §0.0:** nincs új ADR (mérve — R13/R14/R17/R18
> precedens); a `stale`-út mérve (`TutorActionValidationIssue.expired` →
> `blocked`, executor soha). **Első implementer-futás stalled** a végén (log 5 perc
> néma → kilőve) commit előtt; a scope-tiszta munkát egy folytató dispatch fejezte
> be ugyanabban a munkapéldányban (nem worktree — mm-round.sh `.git`-**könyvtárat**
> vár, L131; a folytató-dispatch salvage-minta L132). **Review:**
> [`docs/reviews/e04-r19-evidence-source-action-card-ui-review.md`](docs/reviews/e04-r19-evidence-source-action-card-ui-review.md)
> — **APPROVED** (0 BLOCKER/MAJOR/MINOR), falszifikációs próbával igazolt
> sanitizer-guard, scope `ok`. CI exact-SHA `e447170`:
> full-gate [31059622555](https://github.com/wolfcasaba/strumsight/actions/runs/31059622555)
> + router-ci [31059616282](https://github.com/wolfcasaba/strumsight/actions/runs/31059616282) **success**.
>
> ## ✅ E04-R18 KÉSZ — Tutor Home, Chat UI & streaming UX (2026-08-05)
>
> **E04-R18** MERGED (PR [#151](https://github.com/wolfcasaba/strumsight/pull/151),
> squash `104e685`, **nincs új ADR** — presentation-only, az ADR 0131 (fake gateway)
> + 0134 (memory) hatálya; implementer **MiniMax M3**, orchestrátor/reviewer
> **Claude Opus 4.8**). Az AI-tutor első teljes, accessibility-kompatibilis
> Flutter felülete az `aiTutorEnabled` flag mögött, **fake gatewayre** kötve
> (valódi cloud = E04-R19): Tutor **Home** + virtualizált **Chat**;
> content-blockonkénti message-bubble (text/heading/bullet/metric/evidence/source/
> action/plan/warning/error/**unknown-safe** monospaced, nem futtatható HTML);
> streaming-batched a11y (screen reader turn-onként, nem tokenenként),
> scroll-anchoring, stop/retry/copy/feedback, draft-megőrzés; megkülönböztetett
> offline/consent/rate-limit/error bannerek. Route a flag mögött
> (`lib/app/routing/app_router.dart` `if (aiTutorEnabled) …[GoRoute]`, typed
> `AppRoutes.tutorHome/tutorChat` — E02-R12 precedens); flag OFF ⇒ route hiányzik
> ⇒ Live fallback (mindkét cella tesztelt). **Pre-flight §0.0:** nincs új ADR
> (mérve); base-korrekció — a brief `lib/app/router/app_route.dart` rossz útját
> `lib/app/routing/app_route.dart`-ra javítva **és** `app_router.dart` felvéve az
> `allowed_paths`-ba (a flag-gating cellák enélkül nem teljesíthetők).
> **Review:** [`docs/reviews/e04-r18-tutor-home-chat-ui-review.md`](docs/reviews/e04-r18-tutor-home-chat-ui-review.md)
> — **APPROVED javító kör #1 után**: az első implementer-futás a box lassúsága
> miatt a 3600s abszolút időkorlátot elérte a gate teszt-lépésében (`status=timeout`,
> `scope_audit=ok`) commit előtt; a scope-tiszta munkát az orchestrátor megmentette,
> a két valódi teszt-bukást (R18-A4 látható Stop streamingben; R18-A13 új-buborék
> rebuild) a MiniMax javító köre zöldre vitte. CI exact-SHA `a6165c5`:
> full-gate [31056115529](https://github.com/wolfcasaba/strumsight/actions/runs/31056115529)
> + router-ci [31056108608](https://github.com/wolfcasaba/strumsight/actions/runs/31056108608) **success**.
>
> ## ✅ E04-R17 KÉSZ — Conversation repository, summary & inspectable memory (2026-08-05)
>
> **E04-R17** MERGED (PR [#148](https://github.com/wolfcasaba/strumsight/pull/148),
> squash `1e9b2db`, **nincs új ADR** — ADR [0134](docs/adr/0134-ai-tutor-memory-policy.md)
> memory-policy hatálya, a tárolási minta ADR 0084/0090, privacy ADR 0132;
> implementer **Codex** `gpt-5.6-terra`). Lokális, verziózott tutor
> beszélgetéstárolás + felhasználó által megtekinthető memória: `TutorConversationRepository`
> / `TutorMemoryRepository` contract + `TutorMemoryFact` modell; `LocalTutorConversationRepository`
> (verziózott envelope, dokumentum-előbb-index sorrend index-újraépítéssel, lapozás,
> message-provenance summary, **rekord-szintű korrupt-karantén**, őrzött top-level decode);
> `LocalTutorMemoryRepository` (candidate-dedup, sensitivity-filter password/secret/token/
> email/telefon — pont/perjel-szeparátorral is, inspect/edit/delete, retention purge,
> redaktált export, **delete-all AI data** a teljes `StorageKeys.tutorAiData` + karantén felett).
> **Silent-no-op tilalom betartva:** minden tár-írási hiba → `AppResult.failure(StorageFailure)`.
> **Pre-flight (§0.0):** nincs új ADR (mérve); `public.dart` **kivéve** az `allowed_paths`-ból
> (az additív export az `ai_tutor_boundary_test.dart` üres-boundary invariánsát törte volna —
> a Router CI throughput-teszt itt NEM ütközött, ellentétben az R16 R15↔R16 esetével).
> **Review:** [`docs/reviews/e04-r17-conversation-repository-and-memory-review.md`](docs/reviews/e04-r17-conversation-repository-and-memory-review.md)
> — **APPROVED javító kör #1 után** (`6830e63`): a security-reviewer 2 MAJOR-t talált
> (M1 telefon-filter pont-formátum bypass; M2 őrizetlen top-level `jsonDecode` → tartós
> brick + content a cause-ban), mindkettő ZÁRVA hibát-pirosra-fogó regressziós teszttel.
> CI exact-SHA `41cafd5`: full-gate [31050133428](https://github.com/wolfcasaba/strumsight/actions/runs/31050133428)
> + router-ci [31050123599](https://github.com/wolfcasaba/strumsight/actions/runs/31050123599) success.
>
> ## ✅ E04-R16 KÉSZ — Tutor orchestration state machine & output validator (2026-08-05)
>
> **E04-R16** MERGED (PR [#147](https://github.com/wolfcasaba/strumsight/pull/147),
> squash `df25806`, **új ADR [0174](docs/adr/0174-ai-tutor-orchestration-state-machine.md)**,
> implementer **Codex** `gpt-5.6-terra`). A teljes tutor turn-pipeline
> determinisztikus, UI-mentes összekötése: `context → retrieval → prompt →
> gateway → tool → validator`. Sealed `TutorCommand`/`TutorSignal` + `TutorEffect`,
> pure `reduceTutorTurn` → `TutorTransition{state,effects,isRejected}`, broadcast
> `states`/`effects` + `dispatch` (Practice-controller precedens). **Kötött
> döntések:** repair-cap **1** → deterministic fallback; cancel utáni late-event
> **no-op** (request-id-korreláció); egy aktív turn/conversation; a
> `TutorOutputValidator` claim- (grounded típus + evidence ∈ trusted sources) ÉS
> action-schemát (allowlist + `TutorActionValidator`) is ellenőriz.
> **usage-limit + consent-revoked az orchestration-rétegben** modellezve (a
> gateway-réteg érintetlen — a `tutor.usage_limit` kód-konstans az orchestrator
> sajátja). 10 acceptance-scenárió scripted fake-kel determinisztikusan zöld, a
> repair-cap falszifikációs guarddal (`starts == 2`).
> Review: [`docs/reviews/e04-r16-orchestration-state-machine-review.md`](docs/reviews/e04-r16-orchestration-state-machine-review.md)
> — **APPROVED** (0 BLOCKER/MAJOR, 1 MINOR follow-up, 1 NOTE).
>
> **Pre-flight tanulságok (mérve):** (1) a `blocked` jelzés a friss munkapéldány
> hiányzó generált `lib/l10n/`-jából jött, nem kódhiba — `prepare-flutter-generated.sh`
> oldotta fel (nem H6). (2) A pre-flight §0.0 SZŰKÍTÉS (`public.dart` kivétele az
> `allowed_paths`-ból) pirosra váltotta a Router CI-t: a
> `test_pipeline_throughput.py` hardkódoltan elvárja az R15↔R16 `public.dart`-ütközést
> (slot-planner); a `tools/` tilos zóna, ezért a helyes feloldás a szűkítés
> visszavonása, nem a teszt módosítása. Tanulságok: [`docs/LESSONS.md` L129](docs/LESSONS.md).
>
> **⚠ MINOR follow-up (R18 előtt kötelező):** a `TutorPipelineFailed` terminális
> út nem szabadítja fel a gateway-subscription-t/gateway-t (a többi terminál
> igen). Ma fake-only, `dispose()` mitigál; a **valódi gateway bekötése (R18)
> ELŐTT** javítandó — lásd a review MINOR-1-et.
>
> **Zöld kapu (exact-SHA `c9a3834`):** Full Gate (no APK)
> [31046290808](https://github.com/wolfcasaba/strumsight/actions/runs/31046290808)
> `success` + Router CI
> [31046333319](https://github.com/wolfcasaba/strumsight/actions/runs/31046333319)
> `success`. **Következő:** E04-R17 — a pipeline új sessionben indítja.
>
> <details><summary>▶️ E04-R15 KÉSZ — AI tutor streaming transport (2026-08-05)</summary>
>
> **E04-R15 — Backend + Flutter streaming transport** MERGED (PR
> [#145](https://github.com/wolfcasaba/strumsight/pull/145), squash `1fe91d2`,
> ADR [0142](docs/adr/0142-ai-tutor-streaming-transport-protocol.md), implementer
> **qwen38-max** / Terra). Sorrendhelyes, megszakítható, újrapróbálható tutor
> streaming: monoton event-sequence, started/delta/usage/tool-call/complete/
> failure frame, gap/out-of-order → **kontrollált** `transport_*` failure (nem
> néma átugrás), duplicate-frame idempotens, retry nem duplikál user-message-et,
> disconnect → **nincs árva provider-request** (cleanup + cancellation), body +
> frame size-limit (alatt/rajta/fölött mátrix). Backend `stream.py` (SSE) +
> Flutter `TutorStreamDto` parser + `RemoteTutorModelGateway`.
> Review: [`docs/reviews/e04-r15-streaming-transport-review.md`](docs/reviews/e04-r15-streaming-transport-review.md)
> — **kód APPROVED**, minden lelet zárva (MAJOR-1 ruff-format, MINOR log-forging).
>
> **H3-feloldás (ADR 0112):** az eredeti merge-HALT a `build-apk` secret-scan
> PIROS-a volt egy **pre-existing R14** fixture-fájlon (`test_tutor_proxy.py`,
> tilos zóna). A self-heal (#143, `7b3b5b9`) fájl-szintű
> `# strumsight:allow-secret-file` jelölést tett a fájlra és merge-elt `main`-re;
> ez a session a branchet a gyógyított `main`-re rebase-elte, így a `secrets`-kapu
> zöld. CI: `full-gate.yml` + `router-ci.yml` exact-SHA `a7377ed` **success**
> (ADR 0171 CI-terv: nincs natív út → APK-építés nélkül). Tanulság:
> [`docs/LESSONS.md` L126](docs/LESSONS.md). **Következő:** E04-R16
> (orchestration state machine) — a pipeline új sessionben indítja.
>
</details>
>
> <details><summary>▶️ E04-R16 első kísérlet önjavítás (2026-08-05, H6) — motor visszaállítva Terra-ra (a végleges futás sikeres, fent)</summary>
>
> Az E04-R16 első kísérlete H6-tal állt meg: egy elszivárgott, gitignore-olt
> `.pipeline/engine-override=qwen38-max` (a párhuzamos `ops/qwen-implementer-
> hardening` session kísérleti beállítása) MINDEN kört a `qwen38-max`-ra
> pinnelt, ami kétszer `status=unknown`-nal (bejelent-majd-megáll) lépett ki.
> Az önjavító kör (ADR 0112) **NEM kódot javított** (a repo queue-értéke már
> helyes: E04-R16 → `codex`/Terra): `engine-profile.sh clear` visszaállította
> a queue-tervezett Terra motort, a félkész `codex/e04-r16-…` worktree+branch
> (local+remote) lezárva, `outcome=retry` — a lánc a KÖVETKEZŐ firingen
> Terra-val újrafuttatja E04-R16-ot. A „bejelent-majd-megáll" a Kilo-qwen
> motorok HARNESS-szintű hibája (qwen-plus-t is elvitte E04-R14-en); a mély fix
> a hardening-session élő munkája. Tanulság: [`docs/LESSONS.md` L127](docs/LESSONS.md).
>
> </details>
>
> <details><summary>▶️ E04-R14 KÉSZ — önjavító körrel zárva (2026-08-05)</summary>
>
> **E04-R14 — Backend tutor proxy, provider registry & usage guard** MERGED (PR
> [#142](https://github.com/wolfcasaba/strumsight/pull/142), squash `c1c0a77`,
> **nincs új ADR** — ADR [0131](docs/adr/0131-ai-tutor-provider-boundary.md)
> provider-boundary hatálya). Fail-closed feature-flagged tutor proxy
> (`/tutor/turn`, `/tutor/capability`): provider-allowlist registry,
> request/history/context méretkorlátok, rate-limit + napi token usage guard
> (429, nem nyelődik el), prod-boot guard a dev-default tutor API kulcs ellen.
>
> **Önjavító kör (ADR 0112, H6):** az eredeti implementer (`qwen-plus`) kétszer
> lépett ki záró jelzés nélkül (csak BEJELENTETTE a hátralévő ~5 teszt-fixture
> javítást, edit nélkül). Motorváltás `qwen-coder-plus`-ra (apply_patch nem
> támogatott → shell-fallback, imperatív continuation-prompt) fejezte be a
> munkát. A healer 2 további kört mért/javított: (1) `ruff format` — a lokális
> gate csak `ruff check`-et futtatott, a CI format-gate-je fogta meg; (2) 4
> teszt (`test_output_at_limit`, `test_output_above_limit`,
> `test_provider_timeout_normalized_error`, `test_provider_error_normalized_error`)
> `401`-re bukott CI-n, mert saját `create_app`-ot építettek a megosztott
> fájl-alapú SQLite-tal + egy MÁSIK app tokenjével — lásd
> [`docs/LESSONS.md` L123](docs/LESSONS.md#l123). CI exact-SHA `40d26d4`:
> backend-ci [31023075064](https://github.com/wolfcasaba/strumsight/actions/runs/31023075064)
> `success`; merge-SHA `c1c0a77` backend-ci
> [31023231779](https://github.com/wolfcasaba/strumsight/actions/runs/31023231779) `success`.
>
> <details><summary>▶️ E04-R13 KÉSZ (2026-08-05)</summary>
>
> **E04-R13 — TutorModelGateway & scripted fake** MERGED (PR
> [#141](https://github.com/wolfcasaba/strumsight/pull/141), squash `b9d2950`,
> **nincs új ADR** — ADR [0131](docs/adr/0131-ai-tutor-provider-boundary.md)
> provider-boundary hatálya). Implementer: **qwen-plus** (`qwen/qwen3.7-plus`,
> codex-harness, ADR 0140); orchestrátor/reviewer: **Claude Opus 4.8**.
> Providerfüggetlen streaming modellkapu (`TutorModelGateway` interface, `sealed
> TutorModelEvent` delta/tool-call/done/error, duplicate-terminal guard),
> scripted `FakeTutorModelGateway` (injektált `FakeClock`, first-event/inactivity/
> total timeout mátrix below/at/above, determinisztikus cancel) + capability-
> unavailable `LocalTutorModelGatewayStub`. **Nincs Flutter UI / provider-SDK
> típus** (mutáció-próbával igazolva: secret→`secrets` red, provider-import→
> `analyze` red). Pre-flight §0.0: `public.dart` kivéve (üres-boundary invariáns
> R16+-ig). 3 javító kör (F1–F4), review **APPROVED** (0 BLOCKER/MAJOR/MINOR,
> 3 NOTE). CI exact-SHA `2fe4b60`: build-apk
> [31012190270](https://github.com/wolfcasaba/strumsight/actions/runs/31012190270)
> + router-ci `success`; merge-SHA `b9d2950` router-ci `success`; post-merge gate zöld.
>
> <details><summary>▶️ E04-R12 KÉSZ (2026-08-05)</summary>
>
> **E04-R12 — Prompt templatek, output schema és injection boundary** MERGED (PR
> [#140](https://github.com/wolfcasaba/strumsight/pull/140), squash `c5b14e5`,
> **új ADR [0141](docs/adr/0141-ai-tutor-prompt-output-schema-injection-boundary.md)**,
> bővíti a 0131/0132/0137/0139-et). Verziózott, determinisztikus tutor-prompt-építés
> kemény **trusted/untrusted** tartalmi határral: `TutorPromptBuilder` **csak
> redaktált** `TutorContextSnapshot`-ot fogad (nyers audio/token/secret sosem); a
> trusted (system + `TutorSourceRef` citációk) és untrusted (user/import) szakaszok
> fizikailag külön, delimiterrel, az untrusted `<`/`>` escape-elve (delimiter-forgery
> ellen); tool-schema injection a registry-birtokolt allowlisttel
> (`schemasForTurn(policy)`); strukturált output-schema v1, nincs chain-of-thought;
> intentenkénti asset-template + bit-stabil snapshot + adversarial injection fixture.
> Implementer **Codex (Terra)**, orchestrátor/reviewer **Claude Opus 4.8**, review
> **APPROVED 1 javító kör után** (BLOCKER-1: `public.dart` export törte a merge-elt
> boundary-tesztet → scope-szűkítés, export R13+-ra halasztva; a teljes CI-suite
> fogta meg, nem a szűkebb lokál gate — L120). ADR 0140→0141 átszámozva (GOV-04
> ütközés). Zöld kapu: build-apk + router-ci `success` exact head `89a56fe`,
> merge-SHA router-ci `c5b14e5` success, post-merge lokális gate zöld.
> **Következő: E04-R13 (a pipeline indítja új sessionben).**
>
> <details><summary>E04-R11 — Action proposal, validation & confirmation service (2026-08-05) — snapshot</summary>
>
> **E04-R11** MERGED (PR [#137](https://github.com/wolfcasaba/strumsight/pull/137),
> squash `479550f`, **ADR [0139](docs/adr/0139-ai-tutor-action-proposal-confirmation.md)**).
> Kétlépcsős, user-megerősített action-rendszer — automatikus write/launch soha;
> providerfüggetlen sealed `TutorAction`, pure validator (confirm újrafuttat),
> idempotens confirmation-service. Review APPROVED (0 BLOCKER/MAJOR/MINOR, 1 NOTE);
> exact head `66fadfc`, merge-SHA `479550f`.
> </details>
>
> <details><summary>E04-R10 — Tutor Tool contract & read-only registry (2026-08-05) — snapshot</summary>
>
> **E04-R10** MERGED (PR [#136](https://github.com/wolfcasaba/strumsight/pull/136),
> squash `2f7fffc`, **ADR [0137](docs/adr/0137-ai-tutor-readonly-tool-contract.md)**).
> Typed, allowlistelt, fail-closed tool-rendszer **kizárólag read-only + lokális
> compute**. Implementer Codex (Terra), review APPROVED (0 BLOCKER/MAJOR, 1 NOTE);
> build-apk + router-ci `success` exact head `80a7b7b`.
> </details>
> </details>
> </details>
> </details>
>
> ## 📦 Korábbi kör-narratívák → archívum
>
> A GOV-03 és az azt megelőző körök (E03-as epic, E04 első fele) részletes
> története a [`docs/handoff-archive.md`](docs/handoff-archive.md) fájlban van.
> MIÉRT: ezt a fájlt MINDEN session és MINDEN kör elolvassa (orchestrátor +
> implementer), ezért a lezárt körök narratívája itt tiszta kontextus-adó
> (2026-08-05: 2102 sor). A friss állapot marad itt, a történet ott.

> ## 🔧 Governance: ADR 0171 — pipeline áteresztő-képesség (2026-08-05)
>
> User-döntés („hogyan gyorsítsuk a fejlesztést … biztonságosan, tesztekkel …
> a kódminőség ne romoljon"). Nem termék-kör: a lánc mérése és gyorsítása, a
> mérce változatlanul hagyásával. Mért kiindulás (`tools/round-metrics.py`,
> 41 kör): **medián kör-idő 79 perc, holtidő-arány 22,8%, 9/41 kör önjavítást
> igényelt.**
>
> Új eszközök: `tools/round-ci-plan.py` (melyik CI a kapu — APK csak natív
> diffre, különben az azonos mérce-láncú `full-gate.yml`), `tools/brief-lint.py`
> (a javító körök okait a pre-flightban fogja meg; a `base` szint Router-CI
> kapu a NYITOTT körökre), `tools/round-slots.py` (párhuzamos slotok
> diszjunktság + előfeltétel szerint, atomi ADR-foglalás),
> `tools/round-metrics.py` (kör-időmérleg), `tools/round-merge-lock.sh`.
> Driver: azonnali lánc-folytatás merge után (`PIPELINE_SELF_CHAIN=1`, alap),
> piros `main` fölé nem indul, slot-mechanika (`PIPELINE_SLOTS=1`, alap).
> Gate: globális zár, hogy két Flutter-gate soha ne fusson egyszerre (L05).
>
> **A mérce nem lazult** — 43 új teszt
> (`tools/tests/test_pipeline_throughput.py`) őrzi, hogy a gyorsított CI-sáv
> lépésről lépésre azonos az APK-ssal, hogy natív diff nem csúszhat az olcsó
> sávba, és hogy a gate egyetlen lépése sem tűnhet el. Részletek:
> [`docs/adr/0171-pipeline-throughput-program.md`](docs/adr/0171-pipeline-throughput-program.md).

> ## 🔧 Governance: ADR 0173 — Qwen implementer megerősítés (2026-08-05)
>
> User-kérés: „vizsgáld meg a Qwen fejlesztését az előzmények alapján … hozzuk
> ki belőle a legjobbat". Négy kör naplójából (E04-R13…R16) három visszatérő,
> NEM képességbeli hibaminta: (1) a forduló **bejelentéssel** zárul tool-hívás
> helyett → félkész fa, nincs jelzés; (2) a session fejlécében mérve
> `reasoning effort: none`; (3) a backend-mérce csak a CI-ban futott
> (E04-R15 MAJOR-1: `ruff format --check` piros → 2 javító kör).
>
> Ellenszerek (mind gépi): a `codex-round.sh` **automatikus folytatása**
> ugyanabban a session-ben (`codex exec resume`, max 2, kilövés után soha,
> `continuations=` a jelzésben) · **implementer-preambulum** artefaktumként
> minden forduló elé · motoronkénti **`reasoning`** oszlop
> (`qwen38-max = medium`, mérve) · a gate **backend sávja**
> (`ruff format --check` + `ruff check` + `pytest`, user-engedéllyel, ADR 0173 §4)
> · az ADR-foglaló mostantól a **futó ágakon** kiosztott számokat is látja.
>
> Őrök: `tools/tests/test_qwen_implementer_hardening.py` (13 teszt) + bővített
> `test_engine_profile.py` / `test_pipeline_throughput.py`. Részletek:
> [`docs/adr/0173-qwen-implementer-hardening.md`](docs/adr/0173-qwen-implementer-hardening.md),
> [`docs/LESSONS.md` L126](docs/LESSONS.md).

## 1. Current release state

- **StrumSight** — offline, on-device guitar chord + strum-direction detector
  (Flutter, Dart SDK ^3.12.2, Material 3, Riverpod 3 hand-written providers).
- `pubspec` version: **1.0.0+1** (development). No production release yet —
  release signing is fail-closed via `release-apk.yml` (ADR 0062); a version
  bump / release is a separate user decision.
- Development APK per round from CI (`build-apk.yml`), artifact name
  `strumsight-<ver>-<build>-<sha>-development.apk` (ADR 0051).
- **Epic 1 (Core Platform) technikailag kész** — a zárókör (E01-R16) gépi
  gate-jei zöldek; a végső elfogadás a user valódi-eszközös §16.3/§16.4 menetén
  áll (HORIZON-szabály: synthetic green ≠ done). Evidencia:
  [`docs/sdd/epic-01-completion-report.md`](docs/sdd/epic-01-completion-report.md).
- **Epic 2 (Practice Engine) lezárva** — E02-R20 (epic-zárókör) kész; a
  Practice V2 domain és application réteg kimerítően tesztelt, a migrated
  Learn útvonal (`migratedLearnEnabled`) élesíthető. Az önálló Practice V2
  Hub→Setup→Session út production-drótozása **KÉSZ** (E02-R21, PR #55,
  `6e5cec7`) — a `practiceSessionHostProvider` élesben él, a §3
  rendszerszintű rés pótolva.
  Evidencia: [`docs/sdd/epic-02-completion-report.md`](docs/sdd/epic-02-completion-report.md).
- **Epic 3 (Song Trainer) elkezdve** — E03-R01 (kickoff, baseline+ADR-ek+flag),
  E03-R02 (SongDocument V2 identitás/metaadat domain modell + codec),
  E03-R03 (section/measure struktúra + determinisztikus tempo/meter/key map +
  SongTimeMap), E03-R04 (track/event domain modell + monophonic elemzés),
  E03-R05 (validator/normalizer/capability resolver), E03-R06 (legacy
  Song/Setlist migrációs adapter) és E03-R07 (fájlrendszeres Song repository
  és asset store) kész. A modell flagek mögött, hívó UI/import-runner nincs
  — production viselkedés változatlan.

## 2. What is working

- **SongDocument V2 identitás/metaadat (E03-R02, ADR 0089 §Döntés 2/3):**
  `lib/features/song_trainer/domain/models/` — hat típusos ID (`SongId`,
  `SongSectionId`, `SongTrackId`, `SongEventId`, `SongAssetId`,
  `SongMarkerId`) közös `SongIdValidator`-ral (trim/nem-üres/≤128
  karakter/determinisztikus `safeFilename`); `SongMetadata` (cím kötelező,
  capo 0–15, dedup+lowercase tag-lista, immutable); `SongSource`
  (proveniencia: 7 stabil forrás-típus, SHA-256, importer-verzió,
  warning-summary); `SongAssetReference`, `SongMarker`; a minimális
  `SongDocument` identitás-vázlat (`schemaVersion`/`id`/`revision`/
  `metadata`/`source`/`assets`/`markers`/`createdAt`/`updatedAt` —
  section/track/tempoMap E03-R03-ban bővíti). `data/local/
  song_document_codec.dart` — determinisztikus kulcssorrendű UTF-8 JSON,
  UTC ISO-8601 timestamp policy, ismeretlen source type fail-closed.
  Framework-/Riverpod-/storage-mentes (`Domain purity` teszt-scanner őrzi,
  reviewer-oldali valódi-sértés próbával verifikálva). Hívó UI/repository
  még nincs — production viselkedés változatlan.
- **Songstruktúra és determinisztikus időmodell (E03-R03, ADR 0093):**
  `lib/features/song_trainer/domain/models/` — `SongSection` (kind-enum,
  measure-range validáció), `SongMeasure` (index/durationBeats/pickup/
  repeat-mezők); `TempoMap`/`MeterMap`/`KeyMap` **lokális, tick-alapú**
  idő-primitívekkel (a Practice Engine `BeatPosition`/`Tempo`/`Meter`
  importja a domain-purity scanner és ADR 0092 miatt kizárva — csak a
  tervezési elvek öröklődnek, a típusok nem). `domain/services/
  song_time_map.dart` — 480 PPQ tick, szegmensenkénti egész-mikroszekundum
  összegzés egyetlen kerekítési ponttal, **≤1 tick round-trip tolerancia**
  (500 rendezett, seedelt property-mintán mérve), left-closed tempo/meter
  boundary policy (reviewer-oldali mutáció-tesztelt próbával verifikálva),
  speed-multiplier a forrás mapet nem mutálja. `SongDocument` (R02) bekötve
  az öt új mezővel, **value-equal** `operator==`/`hashCode`-dal minden
  strukturális mezőn (a review F1 MAJOR leletének javítása). Hívó UI/
  repository még nincs — production viselkedés változatlan.
- **Track/event domain modell és monophonic elemzés (E03-R04, ADR 0113):**
  `lib/features/song_trainer/domain/models/` — sealed `SongTrack`
  (`ChordTrack`/`StrumTrack`/`NoteTrack`/`LyricsTrack`/`MarkerTrack`/
  `BackingAudioTrack`) + sealed-szerű event-készlet (`SongChordEvent`
  core `Chord` szimbólummal, `SongStrumEvent` nullable core
  `StrumDirection?` iránnyal — `null` = unknown, `SongNoteEvent` MIDI
  pitch/string/fret/velocity validációval, `SongLyricEvent`,
  `SongMarkerEvent`); `SongInstrument` (opcionális core `Tuning` — az
  EGYETLEN canonical tuning contract); `SongNoteTechnique` (8 ismert
  technika + `unknown` raw/display escape hatch, sosem ad hamis scoring
  capabilityt). `domain/services/note_track_analyzer.dart` —
  `NoteTrackAnalyzer` **active-notes sweep-line**-nal (nem
  adjacent-pair-only — ez volt a review BLOCKER leletének gyökere, ld. §5)
  határozza meg az overlap/tie/monophonic reportot. Codec bővítés
  kanonikus (start asc → track id → event id) sorrenddel és fail-loud
  ismeretlen-altípus kezeléssel (`trackTypeUnknown`/`eventTypeUnknown`).
  `SongDocument.tracks` mező bekötve. Hívó UI/repository még nincs —
  production viselkedés változatlan.
- **Validator, normalizer és capability resolver (E03-R05, ADR 0114):**
  `lib/features/song_trainer/domain/services/` — `SongValidator`
  (cross-collection ellenőrzés: section range vs. `measures.length`,
  section-overlap, `StrumEvent.targetChordId` cél-hivatkozás — sorrend-
  független két lépéses gyűjtés+validálás, ld. §5 review-tanulság —,
  ismeretlen chord-root/technique/strum-direction, `NoteTrackAnalyzer`
  polyphony-reuse; sosem dob, mindig `SongValidationReport`-ot ad
  determinisztikus `severity asc, code asc` sorrenddel), `SongNormalizer`
  (idempotens: `normalize(normalize(x)) == normalize(x)`, kanonikus
  `(kind, id)`/`(start, id)` rendezés minden track/event típusra, ID-t
  soha nem ír át), `SongCapabilityResolver` (severity→capability
  szerződés: `fatal` ⇒ minden profil — importPreview/persist/trainer/
  export — `canPersist=false`; chord/pitch display/scoring ÖNÁLLÓ
  tengely a severity-től, a §6 négy kombináció mind reprezentálható).
  Chord-support grammar önálló, domain-lokális (`Root[m?]`), sosem a
  `practice`-feature szótára (ADR 0114 §Döntés 1 — cross-feature import
  + kívül esik az `allowed_paths`-on). Hívó UI/repository még nincs —
  production viselkedés változatlan.
- **Legacy Song/Setlist migrációs adapter (E03-R06, ADR 0116):**
  `lib/features/song_trainer/data/migration/` — `LegacySongReader` (JSON
  DTO boundary, `LegacySongRecord`/`LegacySetlistRecord`, kanonikus
  SHA-256, nincs presentation import), `LegacySongAdapter` (legacy
  `Song` record → `SongDocument`: `ChordTrack`+`StrumTrack`+egy
  `SongSectionKind.custom` „Full Song" section, egyetlen mikroszekundum-
  kerekítési pont eseményenként, `Meter` denominator mindig 4),
  `LegacySetlistAdapter` (sorrend/duplikáció megőrzés, missing id →
  unresolved report, nincs crash), `LegacyMigrationReport` (önálló,
  adapter-lokális fidelity report — NEM a `SongValidationReport`/
  `ImportWarning` kiterjesztése, ADR 0116 §Döntés 1). Veszteségmentes,
  determinisztikus, tartós írás vagy legacy törlés nélkül. Hívó
  UI/migration-runner még nincs — production viselkedés változatlan.
- **Fájlrendszeres Song repository és asset store (E03-R07, ADR 0090):**
  `lib/features/song_trainer/domain/repositories/` — `SongRepository`
  (`list`/`get`/`create`/`update`/`moveToTrash`/`restore`/
  `permanentlyDelete`, optimistic `expectedRevision`), `SongAssetRepository`
  (`put`/`get`/`summary`/`incrementReference`/`decrementReference`/
  `permanentlyDelete`). `data/local/` — `FileSongRepository` (validate→
  temp-serialize→flush→verify→atomic document rename→temp index→atomic
  index rename, `SongValidator`/`SongCapabilityResolver` a mentés előtt),
  `FileSongAssetRepository` (streamelt SHA-256 content-hash store,
  reference count, korrupt sidecar/asset stabil hibakóddal, sosem néma
  playback), `AtomicFileWriter` (temp/flush/verify/rename, staging a
  songs-root `temp/` alatt, előzetes törlés nélküli atomikus rename),
  `SongRepositoryRecovery` (nem-destruktív startup scan: orphan temp,
  orphan document, corrupt index, orphan asset), `InMemorySongRepository`
  (fake). `application/song_trainer_providers.dart` — éles Riverpod
  wiring `path_provider.getApplicationSupportDirectory()` felett
  (tranzitív import, ugyanaz a precedens, mint az E03-R06 `crypto`
  használata). Nincs `SongDocument`/asset SharedPreferences-ben. Három
  független review pass + két javító kör után **APPROVED**
  ([`docs/reviews/e03-r07-song-repository-asset-store-review.md`](docs/reviews/e03-r07-song-repository-asset-store-review.md)) —
  a második pass egy, a saját első javító kör bevezette regressziót
  talált (streamelt-hash `writeFromSync` length/end-index csere,
  `docs/LESSONS.md` L60), amit az orchestrátor javított (implementer-oldal
  mérve nem elérhető: M3 kerete + Terra napi kerete egyaránt kimerült).
  Hívó UI/import-runner még nincs — production viselkedés változatlan.
- **Detektálás (100% on-device):** Live képernyő (akkord + pengetésirány valós
  időben, DSP + CRNN ML), Analyze (felvett klip elemzése), Tuner, metronóm.
  DSP-igazság: `docs/rag/chunks/` — paraméter csak ADR-rel és ugyanabban a
  commitban frissített chunkkal változhat (AGENTS.md §9).
- **Tanulás/tartalom:** Learn (leckék), Songs, Library (sessionök), Progress,
  Streak, onboarding, i18n (en/hu ARB).
- **Opcionális account-réteg:** FastAPI + SQLite + JWT backend (`backend/`),
  login + settings-sync; **az app kijelentkezve teljes értékű**, a 0-request
  offline-garanciát rendszer-szintű teszt őrzi
  (`test/app/offline_network_guard_test.dart`, E01-R16).
- **Core platform (Epic 1):** validált fail-closed AppConfig-bootstrap ·
  `AppResult`/`AppFailure` + redakciós logging · verziózott storage
  (migrátor + karanténos JSON-dokumentumok) · egyetlen `DioFactory`, 401
  session-generációs invalidáció, POST-retry-tilalom · exkluzív mikrofon-session
  (owner+lease, lifecycle guard, ADR 0056) · közös zenei/audio domain
  (`core/music`, `core/audio`, ADR 0057/0058) · route-katalógus + idempotens
  onboarding-redirect (ADR 0059) · Alembic-backend health-endpointokkal és
  prod-hardeninggel (ADR 0060/0061).
- **CI:** `build-apk.yml` + `release-apk.yml` közös gate-sorral
  (`.github/actions/flutter-gates`: format → analyze → architecture → asset →
  test → randomizált property), coverage külön párhuzamos required jobban;
  `backend-ci.yml` (ruff + pytest + alembic-gate); fail-closed release signing.
  ADR 0062/0063 + E01-R16.
- **Practice V2 parity-mérce (E02-R01):** `test/support/practice_baseline_scenarios.dart`
  (10 scorer-semleges forgatókönyv) + `test/fixtures/practice/legacy_scorer_baseline.json`
  (befagyasztott golden, event-szintű verdictekkel). A replay független legacy
  matchert vezet a scorer mellett; a golden regenerálása csak
  `UPDATE_LEGACY_SCORER_BASELINE=1`-gyel, megnevezett okkal (ADR 0067 §1/§3).
- **Practice V2 domain időalap (E02-R02):** `lib/features/practice/domain/model/`
  — `BeatPosition` (480 PPQ integer tick, ADR 0066; egzakt subdivision-factoryk,
  egyetlen auditált legacy `double beat` híd ≤ 1/960 beat toleranciával),
  `Tempo` (30–300 BPM zárt tartomány, clamp nélküli lista-validáció), `Meter`
  (4/4·3/4·6/8, egzakt `ticksPerBar`), stabil validációs kódkészlet. A
  `lib/features/practice/domain/` prefix framework-independence-e GÉPI őr alatt
  (`tool/check_architecture.dart`). Hívója még nincs — production viselkedés
  változatlan.
- **Practice V2 domain-szerződések (E02-R03, ADR 0068):** a teljes modellkészlet
  a `lib/features/practice/domain/model/` alatt — `PracticeEvent`/`PracticeDefinition`
  (kanonikus sharp-spelled chord-labelkészlet, rendezettség/egyediség/tartomány
  aggregáló validációval), `PracticeSessionConfig`, sealed observation-hierarchia,
  `PracticeVerdict` (+TimingGrade/outcome/coaching kódok), `MetricValue`/`PracticeMetrics`,
  attempt/session result (+`PracticeFinishReason`), `ScoringProfile`
  (integer-percent súlyok, összeg=100; `perfect<=good<=match` ablak-rendezés;
  `legacyLearnParity` const profil), mode/source/difficulty enumok stabil
  `code`+fallback-mentes `fromCode` párral — összesen 60 stabil validációs kód,
  mind literálisan tesztelve. `Meter.ticksPerBar` szimmetrikus fail-fast
  (E02-R02 MINOR-1 zárva). Test-oldali purity-őr (`domain_purity_test.dart`).
  Hívó továbbra sincs — production viselkedés változatlan, flagek OFF.

- **Practice V2 accessibility-mátrix és performance-számlálók (E02-R20, nincs új ADR — a zárókör nem hoz architekturális döntést):**
  `test/features/practice/presentation/practice_a11y_audit_test.dart` (A1.1–A1.10) — Hub/Setup/Result képernyőkön a touch-target + label+action + 200%-os szöveg + landscape + reduced motion + chart-szemantika + screen reader + ARB-paritás cellák zöldek, a `_HubCard` / `PracticeModeCard` / `PracticePatternPreview` / `TimingBiasChart` Semantics-merge fixekkel; `test/features/practice/practice_performance_test.dart` (A3) — R14 highway számláló, R09 matcher számlálók, 10 perces szimulált session cap, controller state-emission cap; `practice_a11y_audit_test.dart` A2.1–A2.4 cellái (A2) — minden `PracticeInsightCode` / `PracticeRecommendationKind` értékhez ARB-szöveg mindkét nyelven (a R20-ban hozzáadott 16 kulcs: `practiceInsight*` × 10 + `practiceRecommendation*` × 6; a javító kör #1 az eredetileg különálló `practice_l10n_audit_test.dart`-ot ide olvasztotta, scope-okból); `test/property/practice_engine_property_test.dart` (A4) — öt epic-szintű invariáns (egy target/observation max egyszer, score ∈ [0,1] ∨ NotApplicable, free practice nincs overall accuracy, terminal state tiszta, playing ≤ active ≤ wall). A §3 rendszerszintű rés (önálló Practice V2 session-út drótozatlan) nyíltan dokumentálva a §5 DoD-táblában minden érintett cellánál.

- **Practice V2 tartalom (E02-R04, ADR 0070):** `lib/features/practice/data/`
  `BuiltinPracticeCatalog` — tíz beépített gyakorlat (négy/nyolcad strum-minták,
  folk pattern, G↔D és Em↔C akkordváltás, C-G-Am-F progresszió, 3/4 keringő,
  szinkópált upstroke-ok, rhythm-only, free-practice sablon) stabil
  `builtin.<slug>.v1` ID-kkel, unmodifiable `events`/`const skillTags`
  listákkal; `domain/repository/practice_catalog_repository.dart` szinkron
  szerződés; `application/practice_catalog_controller.dart` két Riverpod
  providerrel. Hívó UI még nincs, ARB-fordítás az első UI-hívóval jön.
- **Practice V2 legacy adapterek (E02-R05, ADR 0071):**
  `lib/features/practice/data/adapters/` — `practiceDefinitionFromLesson`
  (+`easy:`), `…FromSong`, `…FromAnalyze`, `…FromDailyChallenge`: tiszta,
  óra-mentes függvények `AppResult<PracticeDefinition>`-nel (sosem dobnak,
  hibakód `practice.content_unsupported`). Minden adaptált tartalom
  `strumPattern` + befagyasztott `legacyLearnParity` (kivétel: az eseménymentes
  Analyze-import → `freePractice`). `legacyPracticeChordLabel` a legacy
  akkordcímkéket a detektor tényleges 24-elemű maj/min szótárára redukálja
  (`Em7`→`Em`, `Bb`→`A#`, `G/B`→`G`, értelmezhetetlen → strum-only) —
  veszteséges, de nem parity-rontó (ADR 0071 §2).
  `PracticeDefinition.displayTitle` a user-tartalom nevének (61 stabil
  validációs kód). Songs feature-barrel: `lib/features/songs/public.dart`.
  A legacy API (`Lesson`, `Song.toLesson()`, `Lessons.fromAnalyze`,
  `LessonScorer`) érintetlen; hívó UI nincs.
- **Practice V2 időréteg (E02-R06, ADR 0072):**
  `lib/features/practice/domain/model/beat_time_converter.dart` — a domain
  **egyetlen** beat↔idő konverziója (egész µs, egyszeri kerekítés, fail-fast) ·
  `compiled_practice_target.dart` (4 immutable, value-equal modell) ·
  `domain/service/practice_target_compiler.dart` — determinisztikus
  session-timeline count-innal, egész ütemű pass-hosszal, loop-rebase-szel,
  ütemhatárokkal, expected-chord szegmensekkel és scoring applicabilityvel.
  **ADR 0072 §1.1 az egész epic időmodellje:** minden abszolút pillanat a
  nullponttól vett tickszám egyetlen konverziója, minden időtartam két pillanat
  különbsége — így a kompozíció pontos ÉS minden pillanat bitre egyezik a legacy
  képlettel. Parity a szállított korpuszon: **0 µs**. Hívó UI nincs.
- **Practice V2 observation gateway (E02-R08, ADR 0074):** a Live detektor és a
  Practice domain közötti híd. `application/practice_observation_gateway.dart`
  (SDD §13.1 interfész + `PracticeObservationConfig`: 0.55 / 0.60 / 180 ms /
  500 ms) · **`application/practice_observation_activation.dart` — a
  `practiceCaptureActiveByStatus` `const` tábla mind a 11 státuszra**, ez a
  „hallgat-e a mikrofon" EGYETLEN igazságforrása (`countIn` + `running` → be,
  minden más → ki; a `paused → false` a chunk 014 pause-résének szerkezeti
  lezárása a V2 úton), a kulcshalmaz-egyezés gépi őr alatt ·
  `data/live_practice_observation_gateway.dart` — `strumSeq`-dedup, engine-óra
  de-jitter a legacy **szigorú `<`** predikátumával (a kalibrált input latency
  a matcheré marad, ADR 0074 §3), **fajtánként külön** monoton padló, saját sűrű
  `sequence` (§12.5 baseline), change-point + stabilitási chord-mintavétel,
  engedély-elsőség, idempotens start/stop/dispose, hibaleképezés. Fake gateway a
  `test/support/` alatt az R09/R10 számára. Hívó és provider nincs, flagek OFF →
  production viselkedés bitre azonos.
- **Practice V2 event matcher (E02-R09, ADR 0075):**
  `domain/service/practice_event_matcher.dart` — pure, determinisztikus,
  **kurzoralapú** párosító: eldönti, melyik `StrumObservation` melyik
  `CompiledTargetEvent`-hez tartozik, és mikor zárul egy cél kimaradásként.
  Pontozás-mentes (`TimingGrade`/score/combo a Kör 10-é), **megfigyelést nem
  tárol** (`O(célesemény)` memória), az opcionális célt külön feloldással zárja.
  A legacy `LessonScorer` szemantikája (P1–P9) megőrizve: jogosultság `<=`,
  zárás **szigorú `<`**, holtversenynél a **korábbi**, a rossz irány is
  **elfogyasztja** a célt, az extra pengetés **állapotot nem változtat**.
  **A paritás értelmezési tartománya kimondva (ADR 0075 §2b):** a legacy
  kerekítetlen `double`-lel dönt, a compiled target egész µs-mal, ezért a két
  időalap ≤ **0,5 µs**-ban eltér (mérve **0,489795919508 µs** mind a 348
  szállított eseményen) — a **µs-kvantált alap az igazság**, és a levezetett
  védősávon kívül (`≥ 1 µs` a határoktól, `≥ 2 µs` argmin-különbség) a paritás
  **bitre egzakt**, tűrés nélkül. A sávon belüli két divergencia-cella
  (`first-strums[0]`, `anthem-drive[5,6]`) **kipinnelt, őrzött viselkedés**.
  Hívó, provider és flag nincs → production viselkedés bitre azonos.
- **Kétmotoros implementer-készlet (ADR 0069):** `tools/mm-round.sh` +
  `tools/mm-watch.sh` (5 perces korai riasztás) + `tools/mm-trace.py`
  (munkastílus-elemzés) — a MiniMax M3 ugyanazt a kör-jelzés-szerződést
  használja, mint a Codex. Besorolás és a kötelező brief-elemek: AGENTS.md §15.6.

- **Practice V2 pontozás (E02-R10, ADR 0076):** `lib/features/practice/domain/service/`
  — `PracticeTimingScorer` (grade + eseménypont + `meanAbsoluteOffset`/előjeles
  `timingBias`), `PracticeDirectionScorer` (explicit megfigyelés-bemenet,
  fail-fast hiányzó leképezésre), `PracticeChordScorer` (inkluzív
  `[−120 ms, +420 ms]` ablak, `correct`/`wrong`/`noDetection`/`insufficientData`/
  `notApplicable`), `PracticeScoreAggregator` (overall csak az **elérhető**
  dimenziókra, completion + kettős pass-kapu, legacy combo/pont). Minden pontszám
  belül **egész ezrelék**, kifelé `perMille / 1000` — lebegőpontos akkumuláció
  tilos. `PracticeMetricReasonCode` stabil indokkód-készlet; `ChordOutcome`
  ötértékű. **Legacy paritás 51 forgatókönyvön egzakt** (17 lecke × 3 latency,
  nulla kizárt esemény). Hívó nincs → production viselkedés változatlan.

- **Practice V2 result + coaching + history (E02-R18, ADR 0084):** mode-specifikus
  **result képernyő** (`presentation/screens/practice_result_screen.dart` +
  `score_breakdown`/`timing_bias_chart`): csak az **alkalmazható** dimenziók
  látszanak (`MetricNotApplicable` → a blokk nincs a fában; `MetricInsufficientData`
  → lokalizált „nincs elég adat", **nem** 0%); Free Practice külön layout (nincs
  overall/pass-fail/combo). **`PracticeCoach`** pure service
  (`domain/service/practice_coach.dart`): mérésből választott, **bizonyíték-küszöbös**
  insight-kódok (`practice_insight.dart`), determinisztikus prioritás (SDD §17.3),
  legalább egy pozitív insight befejezett sessionre. **Practice History V2**
  (`data/local_practice_history_repository.dart` + `practice_history_serializer.dart`
  + `practice_history_recorder.dart` + `..._mapper.dart`,
  `domain/model/practice_history_entry.dart` + `practice_metric_snapshot.dart`): új
  kulcs `ss.practice.history_v2` (`StorageKeys.all`-ban), verziózott dokumentum,
  karantén a sérült bájtoknak, jövőbeli `schemaVersion` kihagyva, cap
  `maxSessions=200`, a per-attempt **detail-window** csak a legújabb **N=20**
  sessionre, **idempotens** mentés a `sessionId`-re. **A mentési hiba nem néma:** a
  repository közvetlenül a `KeyValueStore`-ral ír (propagálja a `StorageException`-t)
  → `AppResult.failure` → a controller `ShowRecoverableError`-t emittál; a session
  sikeres marad. A V1 `ss.progress.practice_log` **bájtra érintetlen** (egyesítés =
  R19). A live recorder-wiring valós session-metaadatig (mode/source/definition)
  **R19-ig halasztva** (placeholder-metaadatnál `Noop`, hogy ne keletkezzen
  betölthetetlen — write-then-drop — rekord). Flag: `practiceDetailedHistoryEnabled`
  (non-prod ON) → részletes attempt-adat.

## 3. Known blockers / risks

- ~~**Rendszerszintű rés (E02-R20, mérve): a standalone Practice V2 session nem
  indítható éles buildben.**~~ **JAVÍTVA (E02-R21, PR #55, `6e5cec7`).** A
  `practiceSessionHostProvider`/`practicePrepareSinkProvider` production
  drótozása (A1-A5, ADR 0111) elkészült és merge-elve — a Hub→Setup→Session
  presentation→controller kötés él. Részletek:
  [`docs/sdd/epic-02-completion-report.md`](docs/sdd/epic-02-completion-report.md)
  §3/§5 (a §3 leírás a régi állapotot rögzíti, evidenciaként megmarad).
- **§16.3/§16.4 készülékes menet PENDING** — az Epic-1 zárás végső elfogadási
  kapuja a user valódi-gitáros APK-tesztje; eredménye a completion reportba kerül.
- **Epic-2 valódi eszközös teszt PENDING** — a Practice Engine device-mátrix
  ([`docs/manual-testing/practice-engine-device-matrix.md`](docs/manual-testing/practice-engine-device-matrix.md))
  kész, a user tölti ki — a standalone Practice V2 út (E02-R21 óta) és a
  Learn-migrációs út egyaránt elérhető éles buildben.
- **Login-backend nincs hosztolva** (a :8019-es uvicorn lokális); auth-hiányok:
  nincs jelszó-reset / e-mail-verifikáció / refresh token (14 napos JWT),
  mid-session token-lejárat interceptor szándékosan halasztva.
- **Coverage-küszöb nincs:** `config` 79,66%, `foundation` 76,19% a Ch2 §14.8
  90%-os célja alatt (kritikus modulok együtt 88,07%) — küszöbösítés későbbi kör.
- **User-inputra vár:** Contents:write token (release-publikálás) ·
  Workflows:R+W PAT · Hermes-kutatás továbbítása.
- iOS build Mac nélkül nem lehetséges.
- Nyitott follow-up lista tételesen: completion report §2.

## 4. Current branch

`main` @ [PR #151](https://github.com/wolfcasaba/strumsight/pull/151), squash
`104e685` (E04-R18). A tisztán Dart/dokumentum-diffhez a CI-terv `full-gate.yml`-t
írt elő (nincs natív út): full-gate [31056115529](https://github.com/wolfcasaba/strumsight/actions/runs/31056115529)
+ router-ci [31056108608](https://github.com/wolfcasaba/strumsight/actions/runs/31056108608)
**success** az exact merge-SHA `a6165c5`-en; a post-merge gate `main`-en zöld, a
review **APPROVED** (javító kör #1: box-timeout salvage + 2 teszt-fix).
(Történeti product-merge referenciák: PR #148 / `1e9b2db`, E04-R17; PR #147 / `df25806`, E04-R16; PR #145 / `1fe91d2`,
E04-R15; PR #140 / `c5b14e5`, E04-R12; PR #137 / `479550f`, E04-R11; PR #129 / `f3d69ef`,
E04-R06; PR #128 / `55d640d`, E04-R05; PR #127 / `0d7ab1b`, E04-R04.)

> **L48 clone-pitfall recurred on a fresh `auto`-router worktree
> (mérve 2026-08-02, E03-R06):** a brand-new worktree's first
> `BASELINE_GATE` run BLOCKED on 625 `AppLocalizations` analyze errors
> (gitignored `lib/l10n/app_localizations*.dart` missing from the fresh
> `git worktree add`). Fix: `flutter pub get && flutter gen-l10n` in the
> worktree, then `python3 tools/model-router.py reset --task-id <ID>`
> (sanctioned, zero-cost) — same recipe as L48, now confirmed systemic
> across `auto`-router worktrees, not a one-off. Also measured in the
> same pre-flight (NOT this session's to fix — a closed round's
> artifact): the currently-`main` E03-R05 brief's `ai-router` TOML
> `allowed_paths` incorrectly includes the ADR 0114 path, which is why
> Router CI (`router-ci.yml`) is red on `main` right now — left for a
> future self-heal round. Details: `docs/LESSONS.md` L59.

> **Two router infra dead ends closed/documented on the E03-R05 branch
> before that round's own work started:** the branch had already been
> through two H6 self-heal cycles (PR #61/#62/#63, `docs/LESSONS.md`
> L54–L56 — async router dispatch, gate-guard scope, and finally a PATH
> git-guard shim closing M3's illegal self-commit at the shell layer).
> That session's pre-flight found the salvageable, scope-clean M3 diff
> sitting uncommitted in an abandoned worktree and reconciled it (L50
> pattern: `git reset --soft` + rebase + independent gate re-run +
> orchestrator commit) instead of re-running the round from scratch.

> **Router `resume` false-`BLOCKED` from a premature orchestrator commit
> (mérve 2026-08-02, E03-R03):** teljes leírás `docs/LESSONS.md` L51-ben —
> röviden: NE commitold a diffet/review-t a `resume` hívás előtt (audit +
> review UNCOMMITTED, vagy külön klón); findings-fájl `.ai/review-findings-
> <slug>.md` néven; csak a TELJES ciklus lezárása után, egyetlen lépésben
> commitolj.

> **`BLOCKED`→`READY_FOR_REVIEW` recovery (mérve 2026-08-02, E03-R02):** ha
> `m3_attempts >= 1` és a self-heal már bizonyította a diff scope-tisztaságát,
> a `model-router.py reset --task-id` + friss `run` a JELENLEGI worktree
> tartalmát kapja új baseline manifestként — ha a diff még a worktree-ben
> van, azonnal újra `BLOCKED`-ba fut ("baseline has untracked files"); ha
> pristine-re tisztítod előbb, egy felesleges, ismételt M3-attempt-et fizetsz
> a már kész munkáért. A helyes út: `git reset --soft <pre-flight commit>` a
> worktree-ben (M3 saját commitját visszabontja uncommitted diffre),
> `git rebase origin/main` a healed baseline-ra, scope-audit a brief
> `allowed_paths` ellen, majd az orchestrátor saját authorship-szel
> commitolja — a router task state-hez nem kell nyúlni. Részletek:
> `docs/LESSONS.md` L50.

> **Router baseline-precheck clone pitfall (mérve 2026-08-02, E03-R01):** egy
> vadonatúj izolált munkapéldány első `ai-router-round.sh run` hívása a lenti
> klón-csapdába fut, de a router SAJÁT `BASELINE_GATE` precheckjében, `BLOCKED`
> státusszal és **`m3_attempts=0`**. A javítás: `flutter pub get && flutter
> gen-l10n` a klónban, majd `python3 tools/model-router.py reset --task-id
> <ID>` (sanctioned, zéró-fogyasztású reset — NEM a tiltott kézi
> state-törlés). Részletek: `docs/LESSONS.md` L48.

> ⚠ **A squash-commit üzenete tévesen a régi, „HALT H3" PR-címet viszi**
> (`0bdee7e`): a `gh pr edit` a merge előtt a Projects-classic GraphQL
> deprecation miatt némán elhasalt, a cím csak utólag, REST-en át (`gh api -X
> PATCH .../pulls/43`) lett javítva. A kör állapota **APPROVED**. Tanulság:
> `gh pr edit` után **ellenőrizd** a címet, mielőtt mergelsz.

> **Klón-/friss-munkafa csapda (mérve 2026-08-01):** a generált
> `lib/l10n/app_localizations*.dart` **gitignore-olt**, ezért egy friss klónban
> — és egy régóta nem regenerált munkafában is — az `analyze` több száz
> `undefined_getter` hibával pirosat ad. Ez klón-artefaktum, nem kör-hiba:
> `flutter gen-l10n` után a gate zöld. Reviewer-oldalon ez a **legelső** lépés.

> **CI-szabály (ADR 0086):** a `build-apk.yml` csak `workflow_dispatch`-re fut;
> merge előtt kötelező az `origin/main` mozgás-ellenőrzés, és a dispatch után a
> run **`headSha`-ját össze kell vetni a lokális HEAD-del** (L21 — az R11-ben
> egy néma `&&`-lánc-bukás miatt először rossz SHA-ra ment a dispatch).

## 5. Last completed round

**E04-R18 — Tutor Home, Chat UI & streaming UX** (PR
[#151](https://github.com/wolfcasaba/strumsight/pull/151), squash `104e685`,
**nincs új ADR** — presentation-only, ADR 0131+0134 hatálya; implementer
**MiniMax M3**; orchestrátor/reviewer **Claude Opus 4.8**).

**Elkészült:** az AI-tutor első teljes, accessibility-kompatibilis Flutter
felülete az `aiTutorEnabled` flag mögött, **fake gatewayre** kötve (valódi cloud
= R19). Tutor Home (`tutor_home_screen.dart`) + virtualizált Chat
(`tutor_chat_screen.dart`), content-blockonkénti `tutor_message_bubble.dart`
(unknown/raw blokk biztonságos, monospaced, nem futtatható HTML),
`tutor_composer.dart` (input + draft-megőrzés), `tutor_banners.dart`
(offline≠consent≠rate≠error, distinct semantics label), `tutor_providers.dart`
(Riverpod wiring a fake gatewayjel + orchestrátor/knowledge/context — csak
`ai_tutor/` importok, nincs remote/cloud). Route a flag mögött
`lib/app/routing/app_router.dart`-ban (typed `AppRoutes.tutorHome/tutorChat`);
flag OFF ⇒ route hiányzik ⇒ Live fallback (R18-R1..R4 mindkét cellát méri).
20 widget-teszt fake gatewayjel (empty/send/stream/cancel/retry/banner/unknown/
large-text/semantics/hu-en/scroll-anchoring).
**Pre-flight §0.0:** nincs új ADR (mérve); base-korrekció — a brief rossz
`lib/app/router/app_route.dart` útja `routing/`-ra javítva + `app_router.dart`
felvéve az `allowed_paths`-ba (a flag-gating cellák enélkül nem teljesíthetők).
Review: [`docs/reviews/e04-r18-tutor-home-chat-ui-review.md`](docs/reviews/e04-r18-tutor-home-chat-ui-review.md)
— **APPROVED javító kör #1 után**: az első futás a box lassúsága miatt a 3600s
abszolút időkorlátot elérte a gate teszt-lépésében (`status=timeout`,
`scope_audit=ok`) commit előtt → az orchestrátor a scope-tiszta munkát megmentette,
a két valódi teszt-bukást (R18-A4 látható Stop; R18-A13 új-buborék rebuild) a
MiniMax egy javító körben zöldre vitte. CI exact-SHA `a6165c5`: full-gate +
router-ci **success**; post-merge gate `main`-en zöld.

---

**E04-R17 — Conversation repository, summary & inspectable memory** (PR
[#148](https://github.com/wolfcasaba/strumsight/pull/148), squash `1e9b2db`,
**nincs új ADR** — ADR [0134](docs/adr/0134-ai-tutor-memory-policy.md) hatálya;
implementer **Codex** `gpt-5.6-terra`; orchestrátor/reviewer **Claude Opus 4.8**).

**Elkészült:** lokális, verziózott tutor beszélgetéstárolás + megtekinthető
memória. `TutorConversationRepository`/`TutorMemoryRepository` contract +
`TutorMemoryFact` modell; `LocalTutorConversationRepository` (verziózott
document-envelope, dokumentum-előbb-index sorrend → index-újraépítés a
dokumentumokból, lapozás, message-provenance summary, **rekord-szintű
korrupt-karantén**, őrzött top-level decode → karantén+reset); a
`LocalTutorMemoryRepository` (candidate-dedup normalizált fingerprinttel,
sensitivity-filter [password/secret/token/email/telefon — pont- és
perjel-szeparátorral is], inspect/edit/delete, retention `purgeExpired`,
redaktált export, **delete-all AI data** a teljes `StorageKeys.tutorAiData` +
minden karantén-kulcs felett). Silent-no-op tilalom: minden tár-írási hiba →
`AppResult.failure(StorageFailure)` (nem néma). `StorageKeys`: három additív
`ss.tutor.*` kulcs + `tutorAiData` delete-all lista.
**Pre-flight §0.0:** nincs új ADR (mérve), `public.dart` kivéve az
`allowed_paths`-ból (üres-boundary invariáns védelme).
Review: [`docs/reviews/e04-r17-conversation-repository-and-memory-review.md`](docs/reviews/e04-r17-conversation-repository-and-memory-review.md)
— **APPROVED javító kör #1 (`6830e63`) után**: a security-reviewer 2 MAJOR-t
talált (M1 telefon-filter pont-formátum bypass; M2 őrizetlen top-level
`jsonDecode` → tartós brick + content a cause-ban), mindkettő ZÁRVA
hibát-pirosra-fogó regressziós teszttel; falszifikációs próba (delete-all
mutáció → 2 cella RED) igazolta a guardokat. CI exact-SHA `41cafd5`:
full-gate + router-ci **success**; post-merge gate `main`-en zöld.

---

**E04-R16 — Tutor orchestration state machine & output validator** (PR
[#147](https://github.com/wolfcasaba/strumsight/pull/147), squash `df25806`,
ADR [0174](docs/adr/0174-ai-tutor-orchestration-state-machine.md); implementer
**Codex** `gpt-5.6-terra`). Ld. a fejléc-összefoglalót és az RTM-et.

---

**E04-R15 — Backend + Flutter streaming transport** (PR
[#145](https://github.com/wolfcasaba/strumsight/pull/145), squash `1fe91d2`,
ADR [0142](docs/adr/0142-ai-tutor-streaming-transport-protocol.md); implementer
**qwen38-max** / Terra, ADR 0140 override; orchestrátor/reviewer **Claude Opus 4.8**).

**Elkészült:** sorrendhelyes, megszakítható, újrapróbálható tutor streaming a
backend (`backend/app/tutor/stream.py`, SSE) és a Flutter kliens
(`TutorStreamDto` frame-parser + `RemoteTutorModelGateway`) között. Monoton
event-sequence; started/delta/usage/tool-call/complete/failure frame;
gap/out-of-order → **kontrollált** `transport_sequence_gap`/`malformed` failure
(nem néma átugrás); duplicate-frame idempotens; retry nem duplikál
user-message-et (backend stateless, ADR 0142 D9); disconnect → **nincs árva
provider-request** (`finally: turn_task.cancel()`, mutáció-öléssel bizonyítva);
body + frame size-limit (alatt/rajta/fölött mátrix); provider-semleges
failure-message (nincs secret/prompt-leak); auth-védett `/tutor/stream`.
Review: [`docs/reviews/e04-r15-streaming-transport-review.md`](docs/reviews/e04-r15-streaming-transport-review.md)
— kód **APPROVED**, MAJOR-1 (ruff-format) + MINOR (log-forging kontrollkarakter)
javító körökben zárva. **H3-blokkoló** (build-apk secret-scan az R14
`test_tutor_proxy.py` tilos-zóna fixture-jén) a self-heal #143 (`7b3b5b9`)
után feloldva; a branch a gyógyított `main`-re rebase-elve. CI: `full-gate.yml`
+ `router-ci.yml` exact-SHA `a7377ed` **success**.

**E04-R13 — TutorModelGateway és scripted fake** (PR
[#141](https://github.com/wolfcasaba/strumsight/pull/141), squash `b9d2950`,
**nincs új ADR** — ADR [0131](docs/adr/0131-ai-tutor-provider-boundary.md)
provider-boundary hatálya, orchestrátor a pre-flightban dokumentált nem-döntést).
Implementer: **qwen-plus** (`qwen/qwen3.7-plus`, codex-harness, ADR 0140 első
éles kör-futása); orchestrátor/reviewer: **Claude Opus 4.8**.

**Elkészült:** providerfüggetlen streaming modellkapu teljes contract-tesztkészlettel,
valódi cloud nélkül. `TutorModelGateway` (`abstract interface class`:
`start(TutorModelRequest)→AppResult<Stream<TutorModelEvent>>`, `cancel()`,
`health()`) — **nincs Flutter UI / provider-SDK típus** (ADR 0131). `sealed
TutorModelEvent`: delta / tool-call / done / error, duplicate-terminal guard
(csak az első jut ki). Scripted `FakeTutorModelGateway` injektált `FakeClock`-kal:
delay/delta/tool/error, **determinisztikus** cancel, late-event drop; a
`withTimeouts` teszt-helper first-event/inactivity/total timeout mátrixa
below/**at**/above bontásban. `LocalTutorModelGatewayStub` capability-unavailable
(`'tutor.model_gateway.unavailable'`). **Pre-flight §0.0 (main @ `5d082dc`):**
`public.dart` **kivéve** az engedélyezett listából — az `ai_tutor_boundary_test`
üres-boundary invariánsa R16+-ig él (HANDOFF §6), a gateway intra-feature
importtal érhető el. Review **APPROVED** (0 BLOCKER/MAJOR/MINOR, 3 NOTE);
a provider-boundary/no-secret határt eldobható mutáció igazolta pirosra
(hardcoded secret → `secrets` lépés; provider-SDK import → `analyze`). **3 javító
kör** (qwen kétszer jelzés nélkül `unknown`-ra esett token-kimerülés miatt, de
commitolt; a hiányokat az orchestrátor mérte ki: F1 unused-import, F2 at-threshold
mátrix, F3 uncommitted production fájlok, F4 `FakeClock`(szinkron)↔`StreamController`
(aszinkron) sequencing). CI exact-SHA `2fe4b60`: build-apk
[31012190270](https://github.com/wolfcasaba/strumsight/actions/runs/31012190270)
+ router-ci `success`; merge-SHA `b9d2950` router-ci `success`; post-merge gate zöld
(format/analyze/test 69/architecture/secrets/l10n).

<details><summary>E04-R12 — Prompt templates, output schema & injection boundary (PR #140, ADR 0141) — snapshot</summary>

**E04-R12 — Prompt templatek, output schema és injection boundary** (PR
[#140](https://github.com/wolfcasaba/strumsight/pull/140), squash `c5b14e5`,
**új ADR [0141](docs/adr/0141-ai-tutor-prompt-output-schema-injection-boundary.md)** —
bővíti a 0131/0132/0137/0139-et, orchestrátor írta a pre-flightban). Implementer:
**Codex (Terra, örökölt kézi override)**; orchestrátor/reviewer: **Claude Opus 4.8**.

**Elkészült:** verziózott, determinisztikus tutor-prompt-építés kemény
trusted/untrusted határral. `TutorPromptBuilder` **csak redaktált**
`TutorContextSnapshot`-ot fogad (nyers audio/token/secret sosem); rögzített
layer-sorrend (`PRODUCT_POLICY`→`SAFETY_POLICY`→`TUTOR_PEDAGOGY_POLICY`→
`TOOL_CONTRACT_SUMMARY`→`STRUCTURED_USER_CONTEXT`→`TRUSTED_KNOWLEDGE`→
`UNTRUSTED_*`×3→`REQUIRED_OUTPUT_SCHEMA`). Trusted (system-`en` + `TutorSourceRef`
citációk) és untrusted (user/import) fizikailag külön, delimiterrel; az untrusted
`<`/`>` escape-elve, `PromptTemplate` elutasít `<<<`/`>>>`-t → **delimiter-forgery
zárva** (mutáció-próba: az escape eltávolítása RED-re vált). Tool-schema injection a
registry-birtokolt allowlisttel (`TutorToolRegistry.schemasForTurn(policy)` — a
builder nem vezet be sajátot). Strukturált output-schema v1, **nincs chain-of-thought**.
Intentenkénti asset-template (`assets/tutor_prompts/*.json`, 6 `ContextPurpose`),
bit-stabil snapshot + adversarial injection fixture. **Pre-flight §0.0 (main @
`c1c57db`):** ADR 0141 kiosztva (0140→0141 átszámozva, GOV-04 ütközés); mérési
szabály #2 — az allowlist a registryé, nem a builderé. Review **APPROVED 1 javító
kör után**: BLOCKER-1 — a `public.dart` export törte a merge-elt
`ai_tutor_boundary_test` nulla-directive invariánsát, amit a **teljes CI-suite**
fogott meg (a kör `gate_tests` csak `prompts/`-ot mért, L120); feloldás
scope-szűkítéssel (export R13+-ra halasztva, boundary-teszt érintetlen — H2 elkerülve).
CI: build-apk [31001924809](https://github.com/wolfcasaba/strumsight/actions/runs/31001924809)
+ router-ci `success` exact head `89a56fe`, merge-SHA router-ci `c5b14e5` success;
post-merge gate zöld.

</details>

<details><summary>E04-R11 — Action proposal, validation & confirmation service (PR #137, ADR 0139) — snapshot</summary>

**E04-R11 — Action proposal, validation & confirmation service** (PR
[#137](https://github.com/wolfcasaba/strumsight/pull/137), squash `479550f`,
**új ADR [0139](docs/adr/0139-ai-tutor-action-proposal-confirmation.md)** —
mechanizmus-döntések, implementálja az ADR 0133-at, orchestrátor írta a
pre-flightban). Implementer: **Codex (Terra, örökölt kézi override)**;
orchestrátor/reviewer: **Claude Opus 4.8**.

**Elkészült:** kétlépcsős, felhasználó által megerősített action-rendszer —
**automatikus write/launch soha**. Providerfüggetlen sealed `TutorAction`
hierarchia immutable metadatával (source, expiry [UTC], typed `TutorActionCapability`,
`clientActionId`, opaque `TutorActionRevisionToken`); typed profile-update /
plan-save / session-launch action `preview`-vel; explicit `TutorUnknownActionProposal`
és `TutorRawRouteActionProposal` — **egyik sem `TutorAction`**, így strukturálisan
sem érhet el executort. Pure `TutorActionValidator` (expiry inkluzív, capability,
song-revision, source-session), amit a `confirm` **confirm-időben újrafuttat**
(stale-recheck). `ActionConfirmationService`: csak `pendingConfirmation`-ből
`execute`, reject után nem, **idempotens `clientActionId`-vel** (in-flight future
dedup + completed-set); memóriás `FakeTutorActionExecutor`, nincs production
nav/write. Route-katalógus mérve: `AppRoutes` **String-katalógus, nincs
route-enum**; a domain **nem** importál `lib/app/routing/*`-ot. **Pre-flight §0.0
(main @ `fa76d20`):** D1 — új ADR 0139 (0138 volt a legmagasabb); D2 —
`public.dart` eltávolítva az engedélyezett-listáról (nulla-export boundary
invariáns, nincs hívó; R12/R16/R19 fogyasztja); erőforrás-tulajdonlás mérve
(`rg .acquire(` → csak `mic_capture.dart`, az action-réteg lease-mentes). Review
**APPROVED** (0 BLOCKER/MAJOR/MINOR, 1 NOTE) — expiry alatt/rajta/fölötte mátrix
tesztelve, a raw-route guard **valódi-sértés mutáció-próbával** RED-re váltva
(izolált `/tmp` klón), sequential-reconfirm idempotencia próbával igazolva. CI:
build-apk [30996409067](https://github.com/wolfcasaba/strumsight/actions/runs/30996409067)
+ router-ci `success` exact head `66fadfc`, merge-SHA router-ci `479550f` success;
post-merge gate zöld.
</details>

<details><summary>E04-R10 — Tutor Tool contract & read-only registry (PR #136, ADR 0137) — snapshot</summary>

**E04-R10 — Tutor Tool contract & read-only registry** (PR
[#136](https://github.com/wolfcasaba/strumsight/pull/136), squash `2f7fffc`,
**új ADR [0137](docs/adr/0137-ai-tutor-readonly-tool-contract.md)** —
read-only tutor tool contract & registry, orchestrátor írta a pre-flightban).
Implementer: **Codex (Terra, örökölt kézi override)**; orchestrátor/reviewer:
**Claude Opus 4.8**.

**Elkészült:** typed `TutorTool` contract (permission + providerfüggetlen input-schema),
verziózott **fail-closed** `TutorToolRegistry` (unknown/nem-engedélyezett tool →
normalizált `ValidationFailure`, turn-specifikus allowlist), immutable
request/turn-policy + provenance/timeout/size-report result (méretlimit fölött
**jelent, nem csonkol**), két kezdeti local tool (`getContextField` read-local,
`summarizeContext` compute-local), behelyettesíthető `FakeTutorToolRegistry`.
Kizárólag **read-only + lokális compute** — nincs arbitrary file/network/code tool
(ADR 0137, komplementer az ADR 0133 write/launch-megerősítéssel). **Pre-flight
§0.0 (main @ `acc84d9`):** ADR 0137 szabad (0136 volt a legmagasabb); D2 —
`public.dart` eltávolítva az engedélyezett-listáról (nulla-export boundary
invariáns, nincs hívó; R11/R12/R16/R19 fogyasztja); D3 — `lib/core/foundation/`
scope-on kívül, tool-exception a **meglévő** `ValidationFailure`/`UnknownFailure`
kódokra képződik; D4 — nincs erőforrás-lease (`rg .acquire(` 0 találat). Review
**APPROVED** (0 BLOCKER/MAJOR/MINOR, 1 NOTE) — a security-allowlist guard
**valódi-sértés próbával** igazolva (extra tool a shipped `toolsFor`-ba → 3 teszt
RED → visszaállítva). CI: build-apk + router-ci `success` exact head `80a7b7b`;
post-merge gate zöld.
</details>

<details><summary>E04-R07 — Offline knowledge index & retrieval (PR #130, ADR 0136) — snapshot</summary>

**E04-R07 — Offline knowledge index & retrieval** (PR
[#130](https://github.com/wolfcasaba/strumsight/pull/130), squash `8182204`,
**új ADR [0136](docs/adr/0136-tutor-knowledge-retrieval.md)** —
deterministic offline tutor knowledge retrieval, orchestrátor írta a
pre-flightban). Implementer: **Codex (Terra, örökölt kézi override)**;
orchestrátor/reviewer: **Claude Opus 4.8**.

**Elkészült:** determinisztikus, **offline** tudásbázis-keresés forrásjelöléssel
az R06 approved-only, hash-lezárt knowledge pack fölött. `KnowledgeIndex`
(approved-only, kanonikusan rendezett, hash-verifikált entryk); `KnowledgeRetriever`
lexical ranking (`title`×2 + chunk-`content`×1 + preferred-skill boost), **inkluzív
min-score** (`>= minScore`), **stable tie-break** `(score↓, sourceId↑, chunkIndex↑)`
shuffle-invariáns, duplicate-chunk collapse, max-result cap, `KnowledgeRetrievalBackend`
embedding-seam nyitva; `AssetKnowledgeRepository` fail-loud **nem-omlasztó** fallback
(üres index + stabil hibakód + `logger.error`, manifest+chunk hash-verifikáció);
`TutorSourceRef` provenance-kimenet — a query **soha nem trusted content**.
`build_tutor_knowledge_index.dart` determinisztikus build; latency baseline
(`docs/baseline/epic-04-knowledge-retrieval.md`). **Pre-flight §0.0 (main @
`e79a0eb`):** ADR 0136 szabad (0135 volt a legmagasabb); `KnowledgeDocument`-ben
**nincs** `topic`/`keywords`/`heading` → **`topic ≡ skill`**; **engedélyezett-lista
szűkítve** — `public.dart` eltávolítva (nulla-export boundary invariáns, nincs hívó;
R12/R16 fogyasztja), helyette ADR 0136. Review **APPROVED** (0 BLOCKER/MAJOR/MINOR,
1 NOTE) — min-score inkluzivitás **valódi-sértés próbával** (`<` → `<=` → RED).
CI run 30975365023 success exact head `2b4bb19`; post-merge gate zöld. Full
narrative: [`docs/handoff-archive.md`](docs/handoff-archive.md).

</details>

<details><summary>E04-R06 — Curated tutor knowledge schema & first content pack (PR #129, ADR 0135) — snapshot</summary>

Felhasználói célú, review-zott, verziózott tudásbázis a fejlesztői `docs/rag`
DSP-anyagtól **szigorúan elkülönítve** (ADR 0135 §1, AGENTS.md §9). `KnowledgeDocument`/
`KnowledgeChunk` immutable schema (SHA-256 contentHash, fail-loud); `KnowledgeCodec`
determinisztikus kanonikus JSON codec + chunker; `build_tutor_knowledge_manifest.dart`
**approved-only** manifest + négy külön hibakód. Első **tíz CC0-1.0** dokumentum
(`assets/tutor_knowledge/{en,hu}/`) öt témában. Review APPROVED (valódi-sértés próba:
`!= rejected` → RED). Full narrative: [`docs/handoff-archive.md`](docs/handoff-archive.md).

</details>

<details><summary>Korábbi körök: E04-R05 (context adapters), E04-R04 (skill taxonomy/reducer) — snapshot</summary>

**E04-R05** (PR #128, squash `55d640d`, nincs új ADR): provider-free, redakciós,
provenance-olt tutor context aggregáció immutable `TutorContextSnapshot`-ba (hat
public-barrel adapter, deny-by-default purpose-allowlist, budget). Review
APPROVED (1 MAJOR → fix: rg-shell→Dart fájlolvasás, L110).

**E04-R04** (PR #127, squash `0d7ab1b`, nincs új ADR): provider-független skill
graph + készségbizonyíték-modell, pure determinisztikus reducer. Review APPROVED,
coverage 98,68%. `public.dart` üres.

<details><summary>Korábbi kör: E04-R03 — Student/guitar profile, goals & consent (superseded snapshot)</summary>

**E04-R03 — Student/guitar profile, goals & granular consent** (PR
[#126](https://github.com/wolfcasaba/strumsight/pull/126), squash `06ae3f7`,
nincs új ADR — az R01 0132/0134 realizálása). `StudentProfile` (per-mező
`ProfileField<T>` provenance + explicit>inferred `merge`), `GuitarProfile`,
`LearningGoal`, **`TutorConsent` három független tengely** (ADR 0132 §3);
`TutorProfileCodec` verziózott, bit-stabil round-trip. Review APPROVED,
coverage 90,6%. Full narrative: [`docs/handoff-archive.md`](docs/handoff-archive.md).

</details>

<details><summary>Korábbi kör: E04-R01 — AI Tutor baseline & ADR-ek (superseded snapshot)</summary>

**E04-R01 — AI Tutor baseline, ADR-ek és feature flagek** (PR
[#124](https://github.com/wolfcasaba/strumsight/pull/124), squash `814388a`,
ADR 0131/0132/0133/0134). Epic 4 kickoff funkcionális változtatás nélkül, flag
mögött (`aiTutorEnabled`/`aiTutorCloudEnabled` default OFF); üres `public.dart`
boundary; négy kötött ADR; egy javító kör (MAJOR M1: hashCode-bővítés törte az
`app_config_test` 6-mezős hashCode-ját → fix: value semantics `==`-on).
Full narrative: [`docs/handoff-archive.md`](docs/handoff-archive.md).

</details>

<details><summary>Korábbi kör: E03-R19 (superseded snapshot)</summary>

**E03-R19 — Practice compiler és chord/rhythm trainer orchestration** (PR
[#120](https://github.com/wolfcasaba/strumsight/pull/120), squash `e8dd74e`,
[ADR 0127](docs/adr/0127-song-practice-compiler-and-practice-engine-orchestration-boundary.md)).
Implementer: **Codex (gpt-5.6-terra)**; orchestrátor/reviewer: **Claude Opus 4.8**.

**Elkészült:** `SongPracticeCompiler` (`application/trainer/`, tiszta függvény):
`SongDocument` track+range → determinisztikus `PracticeDefinition`, a range
startja local beat 0-ra, minden `PracticeEvent`-hez `SongEventReference`.
Reference-tempo normalizált idővonal: a tempo/meter-váltó range a start tempóra
normalizál, minden event a `SongTimeMap` szerinti VALÓS onset-idejére kerül
(`µs·bpm·480/µsPerMin` tick) — a Practice pontozás idő-alapú, így az onset-idők
végig hűek. Hat track-profil publikus `PracticeEvent` + `ScoringProfile.weights`
encodinggal (rhythm-only = `StrumDirection.down` placeholder + rhythm-súlyú
profil). `SongTrainerController` (A9-tiszta: az injektált publikus
`PracticeSessionController`-t + `SongTransport`-ot vezényli, sosem éri el direkt
az AudioSessionCoordinatort/StrumEngine-t): count-in, backing+scoring,
pause/resume, seek→új attempt, mic-denied, background; idempotens finalize
(`_operationId`/`_finalizedOperationId`). Playback-only mód nem konstruál Practice
sessiont → **mic provider call count 0** (strukturálisan + teszttel). `SongResultMapper`:
`PracticeSessionResult` → `SongTrainerResult`, measure/section aggregáció, fail-closed
hiányzó referenciára. Négy implementer-STOP mind dokumentált §0.0-revízióval
feloldva (R1 additív public export, R4 fájl-elhelyezés, R5 tempo-normalizálás,
R6 encoding-recept) — nem halt. Full narrative: [`docs/handoff-archive.md`](docs/handoff-archive.md).

</details>

### Előző kör (referencia): E03-R17 — Song Overview, track/range választás és Trainer Setup (PR
[#118](https://github.com/wolfcasaba/strumsight/pull/118), squash `168114a`,
[ADR 0125](docs/adr/0125-song-trainer-setup-configuration-boundary.md)).
Implementer: **Codex**; orchestrátor/reviewer: **Claude Opus 4.8**.

**Elkészült:** Song Overview + Trainer Setup képernyők. `SongTrainerSetupController`
(route-scoped, read-only): a `songRepositoryProvider`-ből tölti a `SongDocument`-et,
tiszta `const SongValidator()`+`const SongCapabilityResolver()` láncon számol
capabilityt (nincs új provider), és egyetlen immutable `TrainerConfig`-ot ad ki.
Capability-driven mode gating: chord (`report.chord.scoring`), rhythm
(strukturális: ChordTrack/StrumTrack/NoteTrack + `canTrain`), pitch
(`pitch.scoring && isMonophonic`); unsupported mode disabled + indokolt.
`TrainerRange` full/section/measure(inclusive UI→exclusive domain)/bookmark,
dalhatáron validálva. Speed 50–150%, count-in/metronome/loop, tuning/capo
reminder, missing-asset entry, rejtett resume-CTA (R21 producer). A setup a
`SongDocument`-et sose mutálja. Flag-gated (`songTrainerV2Enabled` OFF).
Egy implementer-STOP (`36059ad`) §0.0 R2 revízióval feloldva (a capability nem
provider-injektált). Full narrative: [`docs/handoff-archive.md`](docs/handoff-archive.md).

### Korábbi kör (referencia): E03-R13 — Guitar Pro feasibility és stratégiai döntés (PR
[#103](https://github.com/wolfcasaba/strumsight/pull/103), squash `83535e5`,
[ADR 0122](docs/adr/0122-guitar-pro-import-strategy.md)). Implementer: **auto
router**; independent reviewer: **Codex/Terra**.

**Elkészült:** a stratégia C: a Guitar Pro forrásokat az appon kívül, a user
által választott eszközzel MusicXML/MXL/MIDI-vé kell konvertálni, majd a már
auditált import útvonalon beolvasni. A külön Dart feasibility spike
reprodukálható GP3/GP5/GPX probe-ot, fixture-provenanciát és exact output
snapshotot tartalmaz; nem kerül production parser, dependency, registry vagy
félkész támogatási állítás a termékbe. A review egy CI-beli nested-tool import
feloldási MAJOR-t talált; az `F1` javítás relatív library importtal zárult.

Zöld gate: `tools/round-gate.sh test/features/song_trainer/data/importers`
(format/analyze/45 teszt/architecture zöld, merge előtt és után is) + CI
[30839878617](https://github.com/wolfcasaba/strumsight/actions/runs/30839878617)
zöld az exact `ead6f03` branch-headen. Full narrative:
[`docs/handoff-archive.md`](docs/handoff-archive.md) § E03-R13.

### Previous completed round

**E03-R07 — Fájlrendszeres Song repository és asset store** (PR
[#66](https://github.com/wolfcasaba/strumsight/pull/66), squash `b8b7e4e`,
[ADR 0090](docs/adr/0090-song-storage-files-and-assets.md) — elfogadva
E03-R01-ben, ez a kör csak implementálta, nem kellett új ADR-szám).
Implementer: **auto MiniMax-first router**. Orchestrátor: **Claude Sonnet 5**.

**Elkészült:** `SongRepository`/`SongAssetRepository`, `FileSongRepository`,
`FileSongAssetRepository`, `AtomicFileWriter`, `SongRepositoryRecovery`,
`InMemorySongRepository`, `song_trainer_providers.dart` (lásd §2
részletesen).

**Pre-flight:** ADR 0090 már elfogadott volt és szó szerint fedte a kör
minden döntését (nincs új ADR); `path_provider`/`clock` csak tranzitívan
feloldott csomag, ugyanaz a precedens mint az E03-R06 `crypto`-ja; a
`song_trainer/domain/` purityt egy önálló teszt-scanner őrzi, nem a
`tool/check_architecture.dart` — részletek `docs/handoff-archive.md`
§ E03-R07.

**Folyamat:** M3 első próbája két, a §4 listán kívüli teszt-fájlt hozott
létre — az orchestrátor mechanikusan (fájllista-bővítés nélkül)
áthelyezte a teszteseteket a már engedélyezettekbe. Egy `BLOCKED` állapotú
`auto`-router-task `resume`-mal való feloldásához a router SAJÁT
kódjával kellett frissre állítani a perzisztált baseline-manifestet
(`docs/LESSONS.md` L60) — plain `reset`+`run` a stale manifest miatt
azonnal újra BLOCKED-ba futott volna.

**Három független review pass + két javító kör:** pass 1 → 1 BLOCKER +
6 MAJOR (hiányzó mentés-előtti validáció, asset-integritás/atomicitás
hiányok, rossz staging könyvtár, delete-then-rename atomicitás-sértés,
nem streamelt hash); javító kör #1 (M3) mind zárta; pass 2 egy ÚJ
BLOCKER-t talált a saját streamelt-hash javításban (`writeFromSync`
length/end-index csere — `docs/LESSONS.md` L60); javító kör #2
**orchestrátor-írt** (M3 kerete + Terra napi automatikus kerete egyaránt
mérve kimerült — AGENTS.md motor-oldal-nem-elérhető kivétele) egyetlen
sort + egy multi-chunk regressziós tesztet javított; pass 3 **APPROVED**.

Zöld kapu: `tools/round-gate.sh test/features/song_trainer/data/local`
(67/67, format/analyze/architecture mind zöld) + CI
[30750669625](https://github.com/wolfcasaba/strumsight/actions/runs/30750669625)
zöld a merge-elt `headSha`-n (`652fdf6`), független post-merge
gate-ellenőrzés `main`-en (`b8b7e4e`) szintén zöld. Full narrative:
[`docs/handoff-archive.md`](docs/handoff-archive.md) § E03-R07. Review:
[`docs/reviews/e03-r07-song-repository-asset-store-review.md`](docs/reviews/e03-r07-song-repository-asset-store-review.md).

**Előző körök:** E03-R06 (legacy Song/Setlist migrációs adapter, PR
[#65](https://github.com/wolfcasaba/strumsight/pull/65), `d20c402`,
`docs/LESSONS.md` L59) · E03-R05 (validator/normalizer/capability resolver,
PR [#64](https://github.com/wolfcasaba/strumsight/pull/64), `5226127`,
`docs/LESSONS.md` L54–L58) · E03-R04 (track/event domain modell +
monophonic elemzés, PR [#60](https://github.com/wolfcasaba/strumsight/pull/60),
`5c01149`, `docs/LESSONS.md` L52/L53) · E03-R03 (songstruktúra +
determinisztikus időmodell, PR
[#59](https://github.com/wolfcasaba/strumsight/pull/59), `47ad6da`,
`docs/LESSONS.md` L51) · E03-R02 (SongDocument V2 azonosítók/metaadatok,
PR [#58](https://github.com/wolfcasaba/strumsight/pull/58), `a5b0b55`,
`docs/LESSONS.md` L50) — mind teljes narratívája:
[`docs/handoff-archive.md`](docs/handoff-archive.md).

## 6. Exact next task

0. **A következő Epic 4 kör** — a `docs/execution/pipeline-queue.tsv` következő
   `pending` sora; a pipeline (ADR 0087) automatikusan indítja új sessionben —
   **ez a session nem kezdi el**. A `public.dart` **üres-boundary invariáns**
   (`ai_tutor_boundary_test.dart`) tovább él, amíg a hívó (R16/R19) nem érkezik
   meg — az R12 prompt- és R13 gateway-osztályok a feature-en belül közvetlen
   importtal érhetők el, a publikus export a hívó UI-kör (R18/R19) érkezéséig
   halasztva. **A queue következő `pending` sora: E04-R20 — Practice/Analyze
   integráció (a pipeline indítja új sessionben).**
   **~~E04-R19 — Evidence, source & action card UI~~ — KÉSZ** (PR #152, `f0f74fb`,
   nincs új ADR — ADR 0132+0133 hatálya; implementer MiniMax M3; első futás stalled →
   folytató dispatch salvage; ld. fejléc + §5).
   **~~E04-R18 — Tutor Home, Chat UI & streaming UX~~ — KÉSZ** (PR #151, `104e685`,
   nincs új ADR — ADR 0131+0134 hatálya; implementer MiniMax M3; box-timeout salvage
   + 2 teszt-fix javító kör #1-ben; ld. fejléc + §5).
   **~~E04-R17 — Conversation repository, summary & inspectable memory~~ — KÉSZ** (PR #148, `1e9b2db`,
   nincs új ADR — ADR 0134 hatálya; implementer Codex; 2 MAJOR zárva javító kör #1-ben; ld. fejléc + §5).
   **~~E04-R16 — Tutor orchestration state machine & output validator~~ — KÉSZ** (PR #147, `df25806`,
   ADR 0174; implementer Codex; ld. fejléc + §5).
   **~~E04-R15 — Backend + Flutter streaming transport~~ — KÉSZ** (PR #145, `1fe91d2`,
   ADR 0142; implementer qwen38-max; H3 self-heal #143 után; ld. a fejléc-összefoglalót és §5).
   **~~E04-R14 — Backend tutor proxy, provider registry & usage guard~~ — KÉSZ** (PR #142, `c1c0a77`,
   nincs új ADR — ADR 0131 hatálya; implementer qwen-coder-plus; ld. §5 archívum).
   **~~E04-R13 — TutorModelGateway & scripted fake~~ — KÉSZ** (PR #141, `b9d2950`,
   nincs új ADR — ADR 0131 hatálya; implementer qwen-plus; ld. a fejléc-összefoglalót és §5).
   **~~E04-R12 — Prompt templatek, output schema & injection boundary~~ — KÉSZ** (PR #140, `c5b14e5`,
   ADR 0141, ld. a fejléc-összefoglalót és §5).
   **~~E04-R11 — Action proposal & confirmation~~ — KÉSZ** (PR #137, `479550f`,
   ADR 0139, ld. §5 snapshot).
   **~~E04-R10 — Tutor Tool contract & read-only registry~~ — KÉSZ** (PR #136, `2f7fffc`,
   ADR 0137, ld. §5 snapshot).
   **~~E04-R08 — Deterministic debrief coaching~~ — KÉSZ** (a queue sora, ld. archívum).
   **~~E04-R07 — Offline knowledge index & retrieval~~ — KÉSZ** (PR #130, `8182204`,
   ADR 0136, ld. a fejléc-összefoglalót és §5).
   **~~E04-R06 — Knowledge schema & content pack~~ — KÉSZ** (PR #129, `f3d69ef`,
   ADR 0135).
   **~~E04-R05 — Context adapters & snapshot~~ — KÉSZ** (PR #128, `55d640d`).
   **~~E04-R04 — Skill taxonomy & evidence reducer~~ — KÉSZ** (PR #127, `0d7ab1b`).
   **~~E04-R03 — Student/guitar profile, goals & consent~~ — KÉSZ** (PR #126,
   `06ae3f7`).
1. **~~E03-R22 lezárási lánc~~ — KÉSZ** (PR #123, `3ae368a`, Epic 3 zárva).
1. **Historical pipeline snapshot (superseded): ~~E03-R01~~, ~~E03-R02~~, ~~E03-R03~~, ~~E03-R04~~, ~~E03-R05 —
   Validator, normalizer, capabilities~~, ~~E03-R06 — Legacy Song/Setlist
   migrációs adapter~~ és ~~E03-R07 — Fájlrendszeres Song repository és
   asset store~~ — KÉSZ, ld. §5.** Következő:
   **E03-R08 — Legacy adatok tartós V2 migrációja**
   ([docs/rounds/e03-r08-persistent-v2-migration.md](docs/rounds/e03-r08-persistent-v2-migration.md)).
   A `docs/execution/pipeline-queue.tsv` E03-R08 sora `pending` — a driver
   automatikusan folytatja (mid-epic round, nincs emberi kapu, ADR 0087 §7).
1. **User:** §16.3 audio-regresszió + §16.4 teljesítmény-megfigyelések a friss
   APK-val; eredmény vissza → completion report frissítése. Az APK a PR #37
   CI-runjából tölthető
   ([30673821431](https://github.com/wolfcasaba/strumsight/actions/runs/30673821431)).
2. **~~E02-R20 — Epic 2 lezárás (a11y/l10n/perf audit, DoD-tábla)~~ — KÉSZ**
   (PR #44, `4616aed`, 2026-08-01, implementer **MiniMax M3**, orchestrátor
   **Claude Sonnet 5**, egy javító kör → **APPROVED**). **Epic 2 technikailag
   lezárva.**
   - **~~A rendszerszintű drótozási rés (§3)~~ — KÉSZ (E02-R21, ld. §5).**
   - **A `migratedLearnEnabled` rollout-döntés** — mindenhol OFF, a
     bekapcsolás feltételei (mérföldkövek, monitorozás, visszaállítási
     útvonal) az R19 paritása alapján még **user-döntésre várnak**
     (R20 nem hozott ebben döntést, csak dokumentált).
   (E02-R19 progress/streak/daily-goal + Learn V2-migráció — KÉSZ: PR #43,
   `0bdee7e`.)
3. **A pipeline (ADR 0087, GOV-02) E02-R14…R19-et és E02-R21-et vitte
   (utóbbit a self-heal round 10/H4 zárta le); E02-R20-at és E03-R01-et
   SZÁNDÉKOSAN ember indította** (ADR 0087 §7 — epic-kickoff és epic-zárás
   emberi döntési pont); E03-R02-t és E03-R03-at a user már `pending`-re
   állította, a driver ezeken a körökön keresztül automatikusan folytatta
   (self-heal L49/L50, majd L51 közbeiktatásával) — a
   ([`docs/execution/pipeline-queue.tsv`](docs/execution/pipeline-queue.tsv))
   E03-R01/R02/R03/R04/R05 sora `done`, E03-R06 sora a fájlban még
   `pending` (a driver saját könyvelése frissíti `done`-ra a következő
   firing-en — ez a session nem nyúl a queue-fájlhoz), E03-R07…R21
   `pending` — a driver körönként automatikusan halad, amíg HALT nem éri.

   > **Megállási szerződés (ADR 0087 §2):** az orchestrátor-session önállóan
   > javíthatja a kör SAJÁT, még nem merge-elt briefjét/ADR-jét (§0.0
   > revízióval); H1–H8 esetén (merged ADR, lezárt kör viselkedése, tilos zóna,
   > túlélő BLOCKER/MAJOR, 2× piros CI, `blocked`, gate nem zöldíthető,
   > rebase-konfliktus) a kör HALT-tal megáll.
   >
   > **ÖNJAVÍTÁS (ADR 0112, GOV-03, 2026-08-01 — user-döntés):** a HALT már NEM
   > a lánc vége. A driver a következő firingen friss **önjavító sessiont**
   > indít (`docs/execution/pipeline-selfheal-prompt.md`), amely az
   > infrastruktúrát is javíthatja (`tools/**`, merge-elt ADR jelölt
   > módosítás-blokkal, brief, sor-fájl), kötelező **regressziós teszttel**, a
   > változatlan zöld kapun át merge-elve — majd feloldja a láncot. Korlátok:
   > körönként+halt-kódonként max **3** kísérlet (`PIPELINE_SELFHEAL_MAX`), és
   > a **mércét nem gyengítheti**: ha a teszt-fájlok száma csökken vagy a
   > `round-gate.sh` / `.github/workflows/` változik, a driver `H-GATEGUARD`
   > halttal EMBER elé viszi. Kikapcsolás: `PIPELINE_SELFHEAL=0`.
   > Állapot: `tools/pipeline-status.sh` (önjavítás-blokk + kísérletszámláló).
   >
   > **REVIEW-MOTOR FALLBACK (ADR 0115, 2026-08-02 — user-döntés):** ha a
   > **Claude-kvóta** kimerül, a lánc nem áll meg: ugyanazt a kör- vagy
   > önjavító promptot a **Terra** (`codex exec`, `CODEX_HOME=~/.codex-terra`,
   > `gpt-5.6-terra`) viszi tovább, a
   > `docs/execution/pipeline-codex-orchestrator-preamble.md` motor-előszóval.
   > A váltás kiváltója KIZÁRÓLAG a mért kvóta-minta a session-naplóban —
   > minden más néma halál marad halt. A zárlat 5 óra
   > (`.pipeline/claude-blocked-until`), visszaállítás:
   > `tools/pipeline-status.sh --unblock-claude`; kikapcsolás:
   > `PIPELINE_FALLBACK_ENGINE=none`. **Az implementer-routing (ADR 0088:
   > M3 → Terra) ettől FÜGGETLEN és változatlan** — ez csak arról szól, ki
   > vezényel és ki review-z.
   >
   > **E03-R05 H6 önjavító kör (2026-08-02) — KÉSZ, `outcome=fixed`:** a
   > `router_result` egyetlen szinkron `ai-router-round.sh run` hívása a
   > Bash-eszköz 600s-es kemény plafonjánál tovább tartó MiniMax-hívásoknál
   > (`model_timeout_seconds=7200`) jelzés nélküli SIGTERM-mel halt meg —
   > docs/LESSONS.md L42 pontos ismétlődése, most az `engine=auto` úton.
   > Javítás: `engine=auto` is a már szentesített leválaszt-és-előtérben-várj
   > mintát követi (`setsid ... & ; tools/wait-for-router.sh`); az örökölt
   > `wait-for-round.sh` a router `progress`/`blocked` jelzéseit nem ismeri
   > fel terminálisnak (mérve, regressziós teszttel dokumentálva), ezért egy
   > ÚJ, dedikált poller kellett. `tools/ai-router-round.sh` és a Python
   > router (`tools/ai_router/**`) VÁLTOZATLAN — a szükséges state-alapú
   > állapotlekérdezés már létezett. PR #61, `3b4707f`, `router-ci` zöld.
   > Részletek: docs/LESSONS.md L54.
   >
   > **E03-R05 H-GATEGUARD önjavító kör (2026-08-02) — KÉSZ, `outcome=fixed`:**
   > a H6 heal (PR #61) UTÁN a driver `H-GATEGUARD`-dal állt le, holott a PR
   > #61 saját diffje a mércét NEM érintette — a heal ~07:50–08:08 közötti
   > futása KÖZBEN egy tőle FÜGGETLEN, jogos commit (`8715773`, ADR 0115)
   > módosította a `router-ci.yml`-t, és a régi őrszem a teljes main
   > előtte/utána állapotát hasonlította össze, nem a heal SAJÁT diffjét.
   > Javítás: `heal_pr_number`/`heal_pr_gate_violation` a determinisztikus
   > `heal/{ROUND}-{HALT_CODE}-{ATTEMPT}` branch-névhez tartozó, merge-elt PR
   > SAJÁT diffjét nézi (immunis a konkurens, független commitokra); nincs
   > megtalálható PR esetén óvatosságból a régi teljes-fingerprint marad
   > fallback. Regressziós tesztek a VALÓDI PR #61/`3b4707f` (negatív eset) és
   > a VALÓDI, `round-gate.sh`-t módosító `6d61e23` (pozitív eset) adatain.
   > Részletek: docs/LESSONS.md L55.
   >
   > **E03-R05 H6 önjavító kör #2 (2026-08-02) — KÉSZ, `outcome=fixed`:** a
   > H-GATEGUARD heal (PR #62) UTÁN a friss `auto` M3-hívás ÚJRA commitolt
   > (`d0546f0`, worktree `ss-router-e03-r05-2`) a prompt "Do not commit,
   > push..." tiltása ellenére — `security.py` helyesen hard-BLOCKolt, de a
   > `HALTED` saját gyökérok-elmélete ("a tiltás sosincs kimondva") mérve
   > téves volt (a `router.py:353-364` prompt élén ott áll). Ez ugyanaz a
   > tünet, mint L49 (E03-R02) — ott a self-heal SZÁNDÉKOSAN elvetett egy
   > `security.py`-lazítást mércegyengítésként. Javítás most: egy ÚJ,
   > korábbi rétegen ülő kontroll, nem az elvetett lazítás újramérlegelése —
   > `tools/ai_router/git-guard/git` PATH-shim, amit `execution.py`
   > `run_codex()` minden M3/Terra hívás elé tesz, és ami `git commit`/
   > `git push`-t a shell-rétegen utasít el (minden más git-alparancs
   > változatlanul átmegy); `security.py` audit_scope-ja és hard-blockja
   > ÉRINTETLEN. Regressziós tesztek (fix előtt RED, utána GREEN):
   > `tools/tests/test_execution.py::test_git_guard_blocks_commit_and_push_but_passes_through_other_subcommands`,
   > `::test_run_codex_blocks_a_model_commit_at_the_shell_layer` (a `d0546f0`
   > mintát reprodukálja egy hamis "codex" folyamattal). Részletek:
   > docs/LESSONS.md L56.
   >
   > **E03-R08 H6 önjavító kör (2026-08-02) — KÉSZ, `outcome=fixed`:** az
   > auto-router M3 1. próbálkozása `changed_paths=0` mellett terminális
   > `STOPPED`-ot adott vissza; `classification.py`'s catch-all-ja futott,
   > mert egyik ismert minta (quota/429/timeout/network/credential/env) sem
   > talált — a `HALTED` fájl innen csak ezt az egy szót tudta jelenteni,
   > mert `execution.py`'s `run_codex()` a MiniMax CLI nyers `stdout`-ját
   > sorról sorra JSON-ra próbálta parse-olni, és minden NEM-JSON sort
   > (pont ahol egy szöveges self-halt üzenet állna) némán eldobott — a
   > `CodexResult`-nak nem is volt `stdout` mezője. Class A gyökérok (a
   > router SAJÁT diagnosztikai csatornája hiányos, nem a MiniMax-hívás
   > tartalma). Javítás: `CodexResult.stdout` mező (az `events`/
   > `agent_messages` MELLETT) + `router.py`'s új `_record_provider_call()`
   > (az `_record_gate()` mintája) minden M3-/Terra-hívás után a task-state
   > `provider_calls`-listájába teszi a nyers (20000 karakterre vágott)
   > `stdout`/`stderr`-t, a `FailureClass`-szal együtt. Regressziós tesztek
   > (RED a fix előtt, GREEN utána):
   > `test_execution.py::test_run_codex_preserves_raw_stdout_for_non_jsonl_output`,
   > `test_router.py::test_provider_call_history_persists_raw_stdout_for_stopped_diagnosis`.
   > A `tools/tests -q` egy MÁSIK, ehhez a halthoz nem tartozó sub-teszttel
   > (`test_epic3_brief_metadata.py`, E03-R05 brief TOML-drift) továbbra is
   > pirosít — ez az [[L59]]-ben már dokumentált, önálló felhatalmazású
   > önjavító kört vár, SZÁNDÉKOSAN érintetlen ebben a körben (§2 hatóköre
   > csak a MEGÁLLT — E03-R08 — kör briefjére terjed ki). PR #67, `3725f09`.
   > Részletek: `docs/LESSONS.md` L61.
   >
   > **E03-R08 H6 önjavító kör, 2. előfordulás (2026-08-02) — KÉSZ,
   > `outcome=fixed`:** a fenti javítás után a H6 más gyökérokkal két
   > egymást követő 5 perces cikluson (15:19, 15:29 UTC) belül ismét
   > lecsapott: a brief `migration`-fragmenst érint, ezért a kötelező Terra
   > high-risk review (ADR 0088 §2) szükséges, de a napi automatikus
   > Terra-budget (`.ai/router.toml` `max_automatic_terra_calls_per_utc_day
   > = 3`) MÉRVE (`terra-ledger.json`, `daily_count=3`) kimerült — ez csak
   > `2026-08-03T00:00:00Z`-kor nyílik meg újra. C osztályú (külső,
   > naptár-kapuzott) akadály, de a driver 5 percenkénti retry-ciklusa
   > ~20-30 percen belül elhasználta volna mind a 3 önjavítási kísérletet
   > egy olyan haltra, ami emberi döntést nem is igényelt. Javítás:
   > `tools/round-pipeline.sh` kör-specifikus, időkorlátos "hold" — egy
   > Terra napi-budget-kimerülésre visszavezetett `retry` után a driver
   > `terra-budget-hold` fájlt ír (`round`, `hold_until=UTC éjfél`), és
   > minden firing a zár után, halt-kezelés/kör-indítás ELŐTT ellenőrzi:
   > ha a soron lévő kör megegyezik, session és önjavítási-kísérlet
   > fogyasztása NÉLKÜL lép ki. Új, tisztán olvasó
   > `StateStore.daily_terra_count()` (state.py) + `terra-status`
   > alparancs (model-router.py, JSON + nemnulla exit kimerülésnél) — a
   > driver ugyanazt a forrást kérdezi, amit `reserve_terra` a döntéséhez
   > használ, nincs duplikált szabály. Regressziós tesztek (RED a fix
   > előtt, GREEN utána): `test_state_store.py::
   > test_daily_terra_count_matches_the_active_status_rule_reserve_terra_enforces`,
   > `test_router_cli.py::
   > test_terra_status_exits_nonzero_and_reports_the_utc_midnight_reset_once_exhausted`,
   > `test_pipeline_integration.py::
   > test_terra_budget_hold_blocks_a_firing_without_spending_a_selfheal_attempt`.
   > A `tools/tests -q` ezen a javításon átfutva is UGYANAZZAL a [[L59]]-ben
   > dokumentált E03-R05 brief-TOML sub-teszttel pirosít — mérve azonosan a
   > módosítás nélküli `main`-en is, ezen kör hatóköre kívül esik rajta.
   > Részletek: `docs/LESSONS.md` L62.
   >
   > **E03-R08 H6 önjavító kör, 3. előfordulás (2026-08-02) — KÉSZ,
   > `outcome=fixed`:** a fenti L62-hold BEVEZETVE volt (PR #68/#69), a
   > driver mégis NÉGYSZER futott ugyanabba a Terra-budget falba egy nap
   > alatt (14:26, 15:19–15:29, 16:05, 16:15 UTC) — `find .pipeline
   > -iname '*hold*'` a 4. haltkor is ÜRES találatot adott. Gyökérok:
   > `terra_hold_if_exhausted()`-ben `status_json=$(terra_status_json) ||
   > return 0` — de a `terra-status` a DOKUMENTÁLT viselkedése szerint
   > pontosan akkor tér vissza NEMNULLA exit-tel, amikor kimerült; a `||`
   > ezt is lekérdezési hibaként kezelte, a függvény visszatért, mielőtt
   > egyszer is megírta volna a hold-fájlt. A meglévő
   > `test_terra_budget_hold_blocks_a_firing_without_spending_a_selfheal_attempt`
   > csak az OLVASÓ függvényt (`terra_hold_active_for`) tesztelte, kézzel
   > megírt hold-fájllal — az ÍRÓ ág sosem futott le teszt alatt. Javítás:
   > az `|| return 0` törölve, a meglévő `[ -n "$status_json" ] || return
   > 0` marad a valódi lekérdezési hiba (üres kimenet) védelmére. Új
   > `--terra-hold-if-exhausted` teszthorog (a `--terra-hold-active`
   > mintájára) + `test_pipeline_integration.py::
   > test_terra_hold_if_exhausted_writes_the_hold_file_when_terra_status_reports_exhausted`
   > (PATH-stub `python3`, ami a `terra-status` mért exhausted/exit-1
   > viselkedését szimulálja) — RED a régi sorral, GREEN az újjal. A
   > `tools/tests -q` ezen a javításon átfutva is UGYANAZZAL a [[L59]]-ben
   > dokumentált E03-R05 brief-TOML sub-teszttel pirosít, mérve azonosan a
   > módosítás nélküli `main`-en is; `router-ci.yml` (push-only, nem
   > GitHub-required check) ezért erre a heal branch-re is pirosat
   > mutatott, PR #70 a #68/#69 mintáját követve a CodeRabbit-checkkel
   > merge-elődött. Részletek: `docs/LESSONS.md` L63.
   >
   > **E03-R08 H6 önjavító kör, 4. előfordulás (2026-08-02) — KÉSZ,
   > `outcome=fixed`:** az L63-fix (PR #70, 16:27) UTÁN is jött egy 6.
   > azonos H6 halt (16:38 UTC) — a hold-fájl megint hiányzott. Gyökérok:
   > a hold-írás (`terra_hold_if_exhausted`) KIZÁRÓLAG `attempt_selfheal()`
   > `retry`-ágából íródott ki, sosem a driver `halted)` ágából (a HALT
   > ELSŐ, session előtti észlelése). A 3. előfordulás heal-köre
   > (16:20–16:30) maga egy MÁSIK gyökérokra javított (a hold-író saját
   > hibája) — `outcome=fixed`, nem `retry` —, ezért a `retry`-ág EBBEN a
   > ciklusban sem futott le, a hold-fájl a fix után is üres maradt.
   > Javítás: új `handle_round_halt()` (`tools/round-pipeline.sh`) a
   > `halt_file` írása MELLÉ meghívja `terra_hold_if_exhausted()`-et is —
   > a HALT ELSŐ észlelésekor, MIELŐTT bármilyen self-heal elindulna,
   > FÜGGETLENÜL a self-heal későbbi `outcome`-jától. Az
   > `attempt_selfheal()` retry-ágának hívása változatlanul marad
   > (idempotens második réteg). Új `--handle-round-halt` teszthorog +
   > `test_pipeline_integration.py::
   > test_first_halt_detection_writes_the_terra_hold_without_waiting_for_a_selfheal_retry`
   > — RED a hook nélkül (a hívás a case-ágból kiesve a teljes
   > driver-folyamatba zuhan), GREEN a hookkal. A `tools/tests -q` ezen a
   > javításon átfutva is UGYANAZZAL a [[L59]]-ben dokumentált E03-R05
   > brief-TOML sub-teszttel pirosít, mérve azonosan a módosítás nélküli
   > `main`-en is; `router-ci.yml` ezért erre a heal branch-re is pirosat
   > mutatott ugyanazzal az EGY sub-teszttel, a #68/#69/#70 mintáját
   > követve a CodeRabbit-checkkel merge-elődött. Részletek:
   > `docs/LESSONS.md` L64.
   >
   > **A napi Terra-korlát eltávolítása (PR #72, `53b9637`, L65):**
   > user-döntésre `max_automatic_terra_calls_per_utc_day = 0` mostantól
   > korlátlant jelent — a `daily_count=3/3` fal maga szűnt meg, nem csak a
   > driver retry-viselkedése rá. A taskonkénti 1 Terra-hívásos korlát és a
   > magas kockázatú review kötelezettsége változatlan.
   >
   > **E03-R08 H6 önjavító kör, 7. előfordulás (2026-08-02 18:45 UTC) — KÉSZ,
   > `outcome=fixed`:** a napi korlát megszűnése (fent) után az első
   > cron-firing helyesen törölte az elavult `terra-budget-hold` fájlt, de a
   > MELLETTE élő `.pipeline/HALTED` (a MÉG korlátozott policy alatt,
   > `halted_at=16:58:03Z`-kor kiírva) érintetlen maradt — a driver 2.
   > szakasza ettől függetlenül egy ÚJABB, valódi önjavító sessiont indított
   > egy már megszűnt okra (ez a session). **1. javító kör (PR #73):**
   > `terra_clear_stale_halt_for()` a hold-törléssel EGYÜTT, csak akkor
   > futva, ha még LÉTEZIK hold-fájl. **MÉRT hiányosság:** élesben a
   > hold-fájl a HALT előtti firingen már törlődött, tehát PR #73 hívási
   > pontja SOHA nem futott le a valódi incidensen — csak a driver
   > `outcome=fixed` standard könyvelése (a `halt_file` archiválása)
   > oldotta fel EZT a konkrét haltot, nem az új függvény. **2. javító kör
   > (PR #74, ugyanebben a sessionben):** `terra_clear_stale_halt_for()`
   > mostantól ÖNÁLLÓAN kérdezi le a Terra-policy-t, és a driver főágában a
   > hold-fájl létezésétől FÜGGETLENÜL, feltétel nélkül fut — a KÖVETKEZŐ
   > hasonló esetben már ez fog reagálni, nem egy újabb heal-session. Új
   > `--terra-clear-stale-halt` teszthorog + 3 regressziós teszt (RED PR #73
   > állapota ellen, GREEN PR #74 után); `tools/tests -q` 151/151 zöld.
   > **Biztonsági incidens a saját tesztelés közben:** a tesztek első
   > verziója egy ismeretlen CLI-flaget hívott a pre-fix scripten, ami a
   > TELJES driver-folyamatba esett és egy VALÓDI tmux+claude
   > önjavító sessiont indított — azonnal észlelve és leállítva, állapot-
   > károsodás nélkül; javítva az attempt-budget-határ biztonsági minta
   > minden ilyen teszthez való hozzáadásával. Részletek: `docs/LESSONS.md`
   > L66.
4. **Kötelező pre-flight minden körhöz** (az R10 és R11 mért tanulságai):
   minden briefben hivatkozott szimbólumot grep-elj ki; minden előírt
   cél-státuszra mérd meg, melyik INPUT produkálja (L20); minden
   erőforrás-előírásnál mérd ki a tényleges hívási láncot (L19).
   **A javító kör küszöbe EGY** (user-döntés 2026-08-01, `8e719f1` — a korábbi
   HÁROM-ról szigorítva); a második javító kört a **Codex** viszi, H4 halt
   csak utána. **UI-kör esetén a review-nak kötelező eleme a több-belépéses
   és a kombinált-státusz próba** — az R13 három MAJOR-ja mind ilyen volt
   (L22). **Zöld gate mellett is mérj konkrét hívási láncot a DoD-/
   zárójelentés-jellegű állításokra** — az R20 review 6 hamis "teljesül"
   sort talált egy egyébként teljesen zöld gate mellett (L31).
5. **Az E02-R08 nyitva maradt follow-upja:** a chord-confidence felvitele a
   `LiveFrame`-be — az Analyze úton is közös, ezért külön kör; addig a Live
   adapter `confidence: 1.0` = „nem mért".

## 7. Required verification (before any "done")

A lokális mérce **egyetlen futtatható artefaktum** (GOV-01) — a parancssorban
reprodukált lista a csővezeték miatt nem bizonyíték (`docs/LESSONS.md` L09):

```bash
tools/round-gate.sh test/<a kör területe> [további teszt-útvonal ...]
```

A script a `format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket **külön processzként** futtatja (ezért nem OOM-ol), és az első piros
lépésnél a helyes kilépési kóddal megáll. Normatív forrás: `AGENTS.md` §12.
Backend-érintésnél kiegészítő lépés (NEM a gate része):
`cd backend && .venv/bin/python -m pytest`.

- Full suite + property gate + APK: `gh workflow run build-apk.yml --ref <branch>`.
- **Never chain `analyze && test`.** ONE win32 major across the tree
  (`flutter_secure_storage` pinned to v10). Riverpod 3.3.2: `AsyncValue.value`
  (nullable), NOT `.valueOrNull`.
- DSP param change ⇒ `docs/rag/chunks/` update in the SAME commit; new DSP
  behaviour ⇒ randomized property in `test/property/` (`PROPERTY_SEED`).
- Backend writes are easy to lose silently — a failed push must NOT mark state
  synced; verify persistence + offline path.
- Backend dev loop: `cd backend && python3 -m venv .venv &&
  .venv/bin/pip install -r requirements.txt`, then
  `.venv/bin/uvicorn app.main:app --reload` (emulator → host: `10.0.2.2`).
  Deploy-szabály: uvicorn-restart előtt `pip install -r requirements.txt`
  (a `main.py` futásidőben importál `alembic`-ot).
- **HORIZON ritual minden kör-commit után:**
  ```bash
  git notes add -m "round=<n> verdict=pass|fail tests=<n> lesson=<slug>"
  git push origin 'refs/notes/*'
  ```

## 8. Historical archive

A teljes kör-történeti napló (pre-SDD r1–r217 + E01-R01…R15 részletes
összefoglalók, git-notes tükör): [`docs/handoff-archive.md`](docs/handoff-archive.md).
Epic-1 evidencia-gyűjtemény: [`docs/sdd/epic-01-completion-report.md`](docs/sdd/epic-01-completion-report.md).

---

## How to update this file

After **every** round: (1) header date + round; (2) §1/§2 if release state or
capabilities changed; (3) §3 blockers +/-; (4) §4–§6 branch / last round / next
task; (5) move the finished round's detailed story to
`docs/handoff-archive.md` (append, never delete). Keep this file a ~120-line
operational snapshot — history lives in the archive, detail in git.
