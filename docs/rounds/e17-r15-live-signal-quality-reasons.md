# E17-R15 — Live jel-minőségi ok szétválasztása (ADR 0535)

**Motor:** 3 párhuzamos Claude Opus agent (A: domain+motor, B: l10n+banner, C: ellenőrzés+dokumentáció). **Kiindulás:** `main @ 1ae9e55`. **Branch:** `claude/laptop-apk-debug-prompt-kys4oa`.

## 1. Cél

A Live képernyő bannerje a MOTOR hat jel-minőségi diagnózisát hat KÜLÖN,
helyes irányú tanáccsal mutassa, ne egyetlen „move closer to the mic"
üzenettel — ami túl hangos/clipping jelnél ront.

## 2. Jelenlegi állapot — mért tények

- `LiveSignalQualityAnalyzer._classify` → 6 nem-`good` állapot (ADR 0507).
- `LivePipeline.debugDeriveChordDecision` (`live_pipeline.dart:325–349`) →
  minden nem-`good`/`unknown` állapot = `RecognitionRejectReason.signalQuality`.
- `UncertaintyReasonBanner.textFor` → `signalQuality` = `l10n.liveRejectSignalQuality`
  = „Signal too weak to tell — move closer to the mic" / „Túl gyenge a jel — menj közelebb a mikrofonhoz".
- Ezen a boxon NINCS Flutter/Dart SDK — a bizonyíték a CI (`build-apk.yml`, ADR 0053).

## 3. Scope

**Benne van:** enum bővítés (D1) · motor-leképezés (D2) · 6 új l10n kulcs
base-szegmens + aggregátum (D3) · banner ágak · tesztek (piros→zöld) ·
`docs/rag/chunks/live-signal-quality.md` leképezés-szakasz · HANDOFF/queue.

**NINCS benne:** küszöb-hangolás · `live_screen.dart` logika · új UI-elem ·
onboarding szövegek · Lab/diagnostics · tools/**, tool/ci/**, .github/**,
schemas/**, .claude/**.

## 4. Engedélyezett fájlok

- `lib/features/live/domain/recognition/recognition_decision.dart`
- `lib/features/live/engine/dsp/live_pipeline.dart`
- `lib/features/live/widgets/uncertainty_reason_banner.dart`
- `lib/l10n/base/app_en.arb`, `lib/l10n/base/app_hu.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb`
- `test/features/live/**` (csak a `signalQuality`-t érintő cellák + új cellák)
- `docs/rag/chunks/live-signal-quality.md`, `docs/adr/0535-*.md`, ez a brief, `HANDOFF.md`, `docs/execution/pipeline-queue.tsv`, `docs/LESSONS.md`

## 5. Kötött döntések

Lásd ADR 0535 D1–D5. Tagnevek és l10n kulcsnevek KÖTÖTTEK (D1, D3).

## 6. Acceptance criteria

- A1 `RecognitionRejectReason.values` = 11 tag, `signalQuality` nincs köztük; JSON round-trip mind a 11-re.
- A2 `debugDeriveChordDecision` a 6 állapotra 6 KÜLÖNBÖZŐ okot ad; `good`/`unknown` soha nem ad `signal*` okot; jel-minőség továbbra is megelőzi a `noChord`-ot.
- A3 A banner mind a 11 okra nem üres, páronként különböző szöveget ad EN és HU nyelven (meglévő teszt bővül).
- A4 Tartalmi őr: `signalTooLoud`/`signalClipping` szövege nem tartalmaz „closer"/„közelebb"; `signalTooQuiet` nem tartalmaz „back"/„further"/„távolabb".
- A5 `lib/l10n/app_*.arb` aggregátum = a `tool/gen_l10n_segments.dart` által generált tartalom (CI `--check` zöld; lokálisan python-szimulációval ellenőrizve).
- A6 `dart format`, `flutter analyze`, `flutter test test/features/live` zöld a CI-ban.

### 6.1 Falszifikációs próba (agent C)

Cseréld vissza a `signalTooLoud` EN szövegét „move closer"-re → A4 cellának pirosnak kell lennie (kódolvasással igazolva, mert nincs lokális SDK).

## 7. Kötelező ellenőrzések

CI: `build-apk.yml` dispatch a branch-en (analyze + teljes suite + property gate + APK). Lokális: python l10n-sorrend szimuláció, `git diff` scope-audit a §4 lista ellen.

## 8. Implementációs sorrend

A és B párhuzamosan (a nevek kötöttek, nincs függés) → C: scope-audit, l10n-ellenőrzés, docs, git-notes.

## 9. Kockázatok

- Aggregátum kézi frissítése eltérhet a generátor sorrendjétől → C ellenőrzi python-nal, CI `--check` a végső őr.
- A banner tesztje a generált `AppLocalizations`-re épül — lokálisan nem futtatható.
- A `signalQuality` névérték eltűnése (D4) — mérve: nincs perzisztált fogyasztó.

## 10. Implementation handoff — az agentek töltik ki
