# E02-R17 review — Speed Builder, loop és adaptív retry

- **Kör:** E02-R17 · branch `codex/e02-r17-speed-builder` @ `65bf6ad`
- **Implementer:** MiniMax M3
- **Reviewer:** Claude (orchestrátor), read-only, izolált `/tmp/review-e02r17` klón
- **Dátum:** 2026-08-01
- **Verdikt:** **APPROVED** — nincs BLOCKER/MAJOR/MINOR nyitott lelet.

## 1. Jelzés + handoff

`.codex-round-status`: `status=done`, `head=65bf6ad`, `dirty_files=0`,
gate zöld, 813 teszt. A brief §10 kitöltve a gate teljes kimenetével és az
A1–A11 bizonyítékokkal. A jelzést nem bemondásra fogadtam el — a gate-et
magam futtattam újra.

## 2. Gate-újrafuttatás (független, izolált klón)

```
tools/round-gate.sh test/features/practice/ test/property/speed_builder_property_test.dart test/core/l10n_parity_test.dart
```

- format · analyze · test (809 practice + property + l10n parity) · architecture
  → **MINDEN GATE ZÖLD**, `GATE_EXIT=0`.
- A klón `65bf6ad`-ról készült (nem a stale primary-ref) — origin ground truth
  ellenőrizve (`git ls-remote` = 65bf6ad).

## 3. Scope-audit (brief §4 engedélyezett lista ellen)

`git diff --name-only caca3a9..HEAD` → 16 fájl, **mind a listán belül**.
Tiltott zóna érintés: **0 sor** (`application/`, `data/`, `features/learn/`,
`.github/`, `docs/sdd/`, `HANDOFF.md`). Egyetlen jól formált commit (`65bf6ad`).
A `docs/rounds/...md` csak a §0.0 (orchestrátor) + §10 (implementer) szekciót
érinti.

## 4. Acceptance criteria — tételes bizonyíték

| AC | Státusz | Bizonyíték |
|---|---|---|
| A1 validációs mátrix | ✅ | `speed_builder_policy_test.dart` — minden határ három cellája, stabil kódok, minden hiba visszaadva |
| A2 két pass → step-up + streak-null | ✅ | `speed_builder_engine_test.dart` A2: `successStreak` 1→0 a lépés után (`engine.dart:59`) |
| A3 fail-streak step-down + alsó/felső korlát | ✅ | A3 + A3/A4 teszt; `clamp(start,target)` mindkét irány (`engine.dart:54,62`) |
| A4 target completion | ✅ | A3/A4 teszt: targeten `required` pass → `completed`, egy pass a targeten → **nem** completed |
| A5 max attempt + user-finish | ✅ | A5 tesztek: `same(closed)` idempotencia dobás nélkül; `finish()` megőrzi a történetet |
| A6 legmagasabb stabil BPM | ✅ | **öt cellás** mátrix (80/90/null/80/90); a „legmagasabb BPM egy passzal" csapda pirosra fogva |
| A7 adaptív prioritás + determinizmus | ✅ | `adaptive_practice_policy_test.dart`; rendezett lista (nem `Map`), `attemptActive→null` |
| A8 progress-blokk | ✅ | `speed_builder_progress_test.dart`; „Highest stable BPM: 0 BPM" `findsNothing` (nincs 0-BPM antipattern) |
| A9 javaslat sosem hat magától | ✅ | banner: elfogadás=1, elutasítás=0, render=0; **valódi-sértés próbával igazolva** (lásd §5) |
| A10 property gate | ✅ | `test/property/speed_builder_property_test.dart` zöld a gate-ben |
| A11 domain-tisztaság + scope | ✅ | `domain_purity_test` + architecture zöld; scope §3 tiszta |

## 5. Próbatesztek (eldobható, valódi-sértés)

**A9 auto-apply próba** — a `AdaptiveSuggestionBanner.build`-be beszúrtam egy
`onAccept(suggestion)` hívást (a pontosan tiltott „auto-apply"), majd
lefuttattam az A9 tesztet:

```
A9 — rendering and dismissing never apply a suggestion  [FAILED]
A9 — accepting emits exactly one command                [FAILED]
```

Mindkét A9 teszt pirosra váltott → a guard valóban fogja a viselkedést. A
próbát visszavontam (`git checkout --`, `grep PROBE` = 0, klón tiszta).

**Step-up ≠ plain pass** — az engine-teszt külön esettel bizonyítja
(`step-up pass uses metrics rather than plain passed outcome`): `outcome=passed`
+ completion 0.90/overall 0.75 → **nem** lép; `outcome=failed` + 0.95/0.85 +
`MetricNotApplicable` rhythm → **lép**. A kör legfontosabb hamis-állítás
kockázata (ADR 0083 §3 / brief §0.0) mérten kizárva. A `rhythm` „ha
alkalmazható" mérten a `MetricNotApplicable`-lel dől el (`engine.dart:27-31`),
az inclusive `≥` határ 0.95/0.85/0.80-on tesztelt (a 0.79 rhythm eset piros).

## 6. Architektúra + termékhatárok

- A policy/engine **pure**: nincs óra, random, IO, Riverpod (AGENTS.md §6
  domain-függetlenség). A `0.95/0.85/0.80` **egy** helyen (`SpeedBuilderEngine`
  static const), nem szétszórva, nem a `ScoringProfile`-ból.
- A widgetek **injektált** állapottal renderelnek; a screen csak a két widgetet
  csatolja be (import + két widget), a controller bekötése nem történt meg
  (helyesen E02-R18-ra hagyva).
- ARB-paritás: 27 új kulcs mindkét nyelven (`app_en.arb` / `app_hu.arb`), a
  l10n-parity gate zöld.

## 7. NOTE-ok (nem blokkol)

- **N1** — `DefaultAdaptivePracticePolicy` a „3 egymást követő step-up pass"
  küszöböt (`positiveReinforcement` vs `nextDifficulty`) hardkódolt `3`-mal
  kezeli, nem a policy-ból. A SDD §18.2 ezt nem paraméterezi, így elfogadható;
  ha a jövőben konfigurálható kell, egy follow-up körben a policy mezőjévé
  emelhető.

## Verdikt

**APPROVED.** A zöld kapu független ellenőrzéssel igazolt, a scope tiszta, a
kör kritikus hamis-állítás kockázatai (stabil-BPM definíció, step-up≠plain
pass, auto-apply) mérten kizárva. Merge a CI zöld után, mozdulatlan
`origin/main` mellett.
