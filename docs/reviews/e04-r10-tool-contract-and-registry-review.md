# E04-R10 review — Tutor Tool contract és read-only registry

- **Kör:** E04-R10 · **Branch:** `codex/e04-r10-tool-contract-and-registry`
- **Implementer commit:** `375d58b` (feat(ai-tutor-tools): add safe read-only tool registry)
- **Pre-flight base:** `8251180` (ADR 0137 + brief §0.0)
- **Reviewer:** Claude (Opus 4.8), független read-only review izolált `/tmp/review-e04-r10` klónban
- **Verdikt:** ✅ **APPROVED** — 0 OPEN BLOCKER, 0 OPEN MAJOR

## 1. Scope-audit

`git diff --stat 8251180..375d58b` → 9 megváltozott path, **mind az `allowed_paths` listán**
(6 lib + 2 test + a brief §10 handoff). Gépi audit:
`python3 tools/scope-audit.py --base 8251180` → `Legacy scope audit OK (0 generated/ignored)`.
Tilos zóna érintetlen; `public.dart` (D2) **nem** módosult; `lib/core/foundation/` (D3) érintetlen.

## 2. Gate — független újrafuttatás (izolált klón)

`tools/round-gate.sh test/features/ai_tutor/domain test/features/ai_tutor/application`
külön processzekkel, `prepare-flutter-generated.sh` után:

| lépés | eredmény |
|---|---|
| format | zöld |
| analyze | zöld |
| test `.../domain` | zöld |
| test `.../application` | zöld |
| architecture | zöld |
| secrets | zöld (1602 fájl, 0 találat) |
| l10n | zöld (en→hu 720 üzenet) |

## 3. Acceptance criteria — tételes bizonyíték

| Kritérium | Bizonyíték (teszt) |
|---|---|
| Registry-version | `registry_test` „exposes its version…" |
| unknown-tool fail-closed | `registry_test` „fails closed for an unknown tool" → `ValidationFailure`/`validation.invalid_input` |
| turn-allowlist szűkítés | „rejects a registered tool omitted from the turn allowlist" |
| permission-mismatch (tool nem fut) | „rejects a turn permission mismatch without executing the tool" (`invoked == false`) |
| invalid-input reject | `registry_test` + `read_only_tools_test` „explicitly rejects invalid read-only tool input" |
| oversized (alatta/rajta/fölötte) | „reports output size below, at, and above its limit without truncation" — `excessBytes == 1`, `payload == payload` (nincs néma csonkolás, ADR 0137 §5) |
| tool-timeout | „reports a timeout as a typed result with provenance" |
| provenance minden outputon | completed + timedOut result hordozza; `read_only_tools_test` ellenőrzi a source-ot |
| no-secret-output | „returns redacted context output…" — `apiKey`/`accessToken` nem szivárog, `displayName` megmarad (ContextRedactor, R05) |
| tool-exception → AppFailure | invalid → `ValidationFailure`, váratlan throw → `UnknownFailure` |
| fake registry orchestration | „fake registry records orchestration requests…" (rögzíti a requesteket, `isA<TutorToolRegistry>`) |
| security-allowlist (network-tool RED) | „security allowlist rejects a disposable network tool" → registry-konstruktor `throwsArgumentError` |

## 4. Real-violation próba (eldobható, visszaállítva)

A security-guard **valódi sértéssel** igazolva: a shipped `ReadOnlyTutorTools.toolsFor()`
listájába beszúrtam egy plusz toolt (disposable mutáció) → az application suite
**pirosra váltott** (3 bukó teszt, köztük a „security allowlist…" a
`registryFor` konstruktor-guardján keresztül), majd visszaállítva, `git status` tiszta.
A guard tehát **bizonyítottan bit** — a registry `_tools.keys.length != approvedToolNames.length`
ellenőrzése fail-closed a nem-jóváhagyott tool-hozzáadásra.

## 5. Architektúra / termékhatár

- Domain (`domain/tools/*`) nem függ application/presentation rétegtől; a registry a
  Core `AppResult`/`AppFailure` contractra képez (Epic 1), új `FailureCode` nélkül (D3 tartva).
- `public.dart` barrel érintetlen — a boundary nulla-export invariáns (D2) sértetlen; a
  fogyasztók (R11/R12/R16/R19) később kötik be. A tesztek közvetlen path-importot használnak.
- Read-only/compute permission-modell; nincs file/network/code tool. Immutable modellek
  (`UnmodifiableMapView`/`unmodifiable` freeze mély struktúrán is).

## 6. Leletek

| # | Súlyosság | Fájl:sor | Leírás | Állapot |
|---|---|---|---|---|
| N1 | NOTE | `docs/rounds/e04-r10-*.md` §4 táblázat | A prózai §4 táblázat még listázza a `public.dart | előző körökből | additív export` sort, amit a §0.0 **D2** revízió és a gépi `allowed_paths` már eltávolított — belső dok-inkonzisztencia, nem kód-hiba; a D2 szöveg felülírja, az implementer helyesen NEM nyúlt a barrelhez. | OPEN (nem blokkol) |

Nincs BLOCKER/MAJOR/MINOR. **Merge-re jóváhagyva** exact-SHA zöld CI (build-apk + router-ci) mellett.
