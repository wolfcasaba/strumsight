# Review — E04-R01 (AI Tutor baseline, ADR-ek és feature flagek)

- **Kör:** E04-R01 — AI Tutor baseline, ADR-ek és feature flagek
- **Branch:** `codex/e04-r01-ai-tutor-baseline-and-boundaries`
- **Implementer commit:** `295081c` (motor: Codex / `codex-round.sh`)
- **Pre-flight commit:** `184e503` (ADR 0131–0134 + brief §0.0, orchestrátor)
- **Reviewer:** Claude (Opus 4.8), független read-only review
- **Dátum:** 2026-08-04
- **Verdikt:** **CHANGES REQUESTED → (fix 1 után) APPROVED** — ld. §9 fix-kör.

> **Frissítés (fix 1, 2026-08-04):** a lokális targeted gate zöld volt, de a
> full-suite CI (run `30957776795`) EGY tesztet pirosra váltott
> (`app_config_test.dart` hashCode-assert). MAJOR lelet rögzítve (§7/§9),
> javító kör lefuttatva. A lenti §2–§6 az EREDETI (295081c) mérés; a fix-kör
> zárása a §9-ben.

## 1. Jelzés + handoff

`.codex-round-status`: `status=done`, `head=295081c`, `dirty_files=1`. A
`dirty_files=1` kivizsgálva (L21): a gitignore-olt `.codex-round-status` signal
fájl (`.gitignore:66`); a **követett** working tree tiszta (`git status
--porcelain` üres), a commit pontosan a 6 engedélyezett fájlt tartalmazza. A
brief §10 handoff kitöltve (módosított fájlok, RED→GREEN + elvetett mutációk,
futtatott gate).

## 2. Gate-újrafuttatás (izolált `/tmp/review-e04-r01` klón, exact-SHA 295081c)

```
tools/prepare-flutter-generated.sh        → exit 0
tools/round-gate.sh test/features/ai_tutor test/app/feature_flags_test.dart \
    test/app/offline_network_guard_test.dart → MINDEN GATE ZÖLD
```

| Lépés | Eredmény |
|---|---|
| format | ZÖLD (865 fájl, 0 changed) |
| analyze | ZÖLD (`No issues found`, 11.9s) |
| test `test/features/ai_tutor` | ZÖLD (1 teszt) |
| test `test/app/feature_flags_test.dart` | ZÖLD (3 teszt) |
| test `test/app/offline_network_guard_test.dart` | ZÖLD (2 teszt) — offline 0-request út érintetlen |
| architecture | ZÖLD (12 allowlisted deviation) |

## 3. Scope-audit (`git diff --stat main...branch`)

10 fájl: a 4 ADR (0131–0134) + a brief a **pre-flight** (orchestrátor)
commitból; a 6 implementációs fájl pontosan a brief §4 `allowed_paths` listáján:
`lib/app/config/feature_flags.dart`, `lib/features/ai_tutor/public.dart`,
`docs/baseline/epic-04-ai-tutor-start.md`,
`test/features/ai_tutor/ai_tutor_boundary_test.dart`,
`test/app/feature_flags_test.dart`, `docs/rounds/…`. **Listán kívüli fájl:
nincs.** A tilos zóna (`app_config_test.dart`, `offline_network_guard_test.dart`,
más feature belső, `docs/rag`) érintetlen.

## 4. Acceptance criteria — tételes bizonyíték

1. **Mindkét flag additív, default OFF, mindkét default bizonyítva** — ✓
   `feature_flags_test.dart`: `const constructor defaults both flags to off`
   + `forEnvironment leaves both flags off in every environment`
   (`AppEnvironment.values` mind). PROBE 1 (lentebb) igazolja, hogy a default
   valóban őrzött.
2. **Flag OFF ⇒ nincs új route és nincs hálózati kérés** — ✓
   `offline_network_guard_test.dart` változatlanul zöld; `usesNetwork`
   érintetlen (`accountEnabled || diagnosticsEnabled`); a boundary semmit sem
   exportál, ami route-ot regisztrálna (üres `public.dart`).
3. **Boundary-import tiltás, „egy import" gyengítés nélkül** — ✓
   `ai_tutor_boundary_test.dart` az import/export direktívák **nulla**
   előfordulását követeli (regex `(?:import|export)\s+['"]…['"]`), nem „legfeljebb
   egyet". PROBE 2 igazolja.
4. **Teljes suite zöld (CI)** — orchestrátor exact-SHA dispatch: `build-apk.yml`
   run `30957533368`, headSha `295081c` = lokális HEAD (ld. §6).
5. **Baseline-dokumentum: forrásonkénti osztályozás + coaching fixture-snapshot**
   — ✓ minden adatforrás jelölve (Mért tény / Számított aggregátum / UI-only);
   `practice_coach_bias_late_v1` fixture-snapshot rögzítve. **Content-fidelity
   mérve:** a snapshot `output.code: practice.insight.bias_late` megegyezik a
   production konstanssal (`practice_insight.dart:20`
   `biasLate = 'practice.insight.bias_late'`), a bemenet (lateShare 0.8, 20
   paired event) megegyezik a valódi `biasLate` teszt-fixture-rel
   (`practice_coach_test.dart:38,53,56`). „Nyers audio nem része a tutor
   contextnek" kimondva (§Adatvédelmi határ); rollout + rollback terv rögzítve.

## 5. Próbatesztek (eldobható mutációk, izolált klón, visszaállítva)

A reviewer-előírás szerint legalább egy központi invariánst eldobható mutációval
pirosra kell váltani. **Mindkettőt** mértem:

- **PROBE 1 — flag-default invariáns:** `this.aiTutorEnabled = false` →
  `= true`. `flutter test test/app/feature_flags_test.dart` → **`+1 -2` PIROS**
  (`const constructor defaults…` és `value semantics…` bukott). Visszaállítva.
- **PROBE 2 — boundary-import invariáns:** a `public.dart`-hoz hozzáadva
  `import '…/features/practice/domain/model/practice_insight.dart';`.
  `flutter test test/features/ai_tutor/ai_tutor_boundary_test.dart` →
  **`+0 -1` PIROS** (`public boundary has no imports or exports…` bukott).
  Visszaállítva. Klón utána tiszta.

Mindkét mérés a bemásolt zöld outputtól függetlenül igazolja, hogy az
invariánsok valódi mutációt fognak.

## 6. Architektúra + termékhatárok (AGENTS.md §5–§6)

- `public.dart` contract: üres, nem húz be idegen belső réteget (PROBE 2). ✓
- `usesNetwork` / URL-validáció változatlan → nincs új hálózati/mic/secret út
  flag OFF mellett (ADR 0132 / brief §0.0/5, cloud wiring R14-re halasztott). ✓
- ADR 0131–0134: provider-boundary, privacy/consent, tool-confirmation,
  memory-policy — a döntések rögzítve, ez a kör csak greenfield boundaryt hoz. ✓
- Doc-comment fegyelem: a flag-doc csak a tesztelt „default OFF" állítást teszi. ✓

## 7. Súlyossági tábla

| Osztály | Lelet |
|---|---|
| BLOCKER | — |
| MAJOR | **M1 (fix 1-ben javítva):** `feature_flags.dart` `hashCode`-ja a két új mezővel bővült → minden `FeatureFlags` hashCode megváltozott → a **tilos zónás** `app_config_test.dart:263-266` (pontos 6-mezős `Object.hash`) PIROS lett a full-suite CI-ban (run `30957776795`). Az `app_config_test` nem módosítható (tilos zóna), a lista bővítése H3 volna. Fix: a `hashCode` marad 6-mezős; a két új mező csak `==` + `toString` része; a `feature_flags_test` ehhez igazodik. Ld. §9. |
| MINOR | — |
| NOTE | (1) A `feature_flags_test` hashCode-assertje a belső `Object.hash`-sorrendtől függ (implementációs részlet), de helyesen bizonyítja az új mezők részvételét — nem kell javítani. (2) A meglévő `hashCode` szándékosan kihagyja a `songTrainerV2Enabled`-et (pre-existing, tilos zóna) — külön follow-up körre hagyva, nem e kör regressziója. |

## 8. Merge-döntés (fix 1 előtt)

A lokális/izolált gate zöld, DE a full-suite CI (run `30957776795`, exact-SHA
`2e8fb0f`) PIROS → **merge tilos**, javító kör indul (§9).

## 9. Fix-kör 1 (2026-08-04)

- **Bemenet:** `codex-fix-e04-r01.md` findings (M1), motor: Codex (ugyanaz).
- **Brief-revízió:** §0.0/3 REVÍZIÓ dokumentálva (mért gyökérok + korrigált
  utasítás: a `hashCode` NEM bővül).
- **Javítás:** `feature_flags.dart` hashCode visszaáll 6-mezősre; `==`/`toString`
  a két új mezővel marad; `feature_flags_test.dart` az új-flag hashCode-assertjeit
  value-semantics (`==`) bizonyítékra cseréli.
- **Zárás (mérve):** fix commit `9380498`. `hashCode` visszaáll a 6-mezős
  eredetire; `==`/`toString` a két új mezővel marad; a `feature_flags_test`
  a hashCode-részvétel helyett value-semantics (`==` + equal-copy hashCode)
  bizonyítékra vált. Izolált `/tmp/review-e04-r01-fix` klón (exact-SHA `9380498`):
  `round-gate.sh` **MINDEN ZÖLD**; a tilos zónás `flutter test
  test/app/app_config_test.dart` → **18/18 zöld** (a korábban piros
  `new constructor fields…` teszt is). Full-suite CI: `build-apk.yml` run
  **[30958928669](https://github.com/wolfcasaba/strumsight/actions/runs/30958928669)**
  = **success**, headSha `9380498` (exact tip). **M1 lezárva.**
- **Verdikt: APPROVED.** Merge: PR **#124**, squash `814388a`, `origin/main`
  a dispatch óta változatlan (`8d70232`); a post-merge gate a merged `main`-en
  függetlenül **zöld**.
