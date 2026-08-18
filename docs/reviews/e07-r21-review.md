# E07-R21 — Review

Brief: `docs/rounds/e07-r21-plan-preview-and-explanation.md`
Diff: `e7a6a239..fbe9f7a2`
Reviewer: Codex/Terra correctness review + independent security-reviewer
Dátum: 2026-08-18
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

Az első review F1 BLOCKER-jét a MiniMax javító kör a controller → screen →
sheet priority-átadásával és hiányzó priority esetére fail-closed
uncertainty-jelzéssel zárta. A javított tipet friss, távoli GitHub-klónban a
correctness gate újramérte; a dedikált security re-review is PASS.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Kilépés nem aktivál/ment | ✅ | `plan_preview_screen_test.dart`, A1; `PlanPreviewScreen` nem aktivál dispose/pop alatt |
| A2 | Szerkesztés után revalidál | ✅ | A2 + regression truth-table célteszt |
| A3 | `error` blokkol | ✅ | A3 + manuális szerkesztéses cella |
| A4 | warning explicit áttekintést kér | ✅ | A4 célteszt |
| A5 | Reason code ARB-ből jön | ✅ | `plan_reason_sheet_test.dart`, en + hu A5 |
| A6 | Bizonytalanság kimondott | ✅ | whole-screen F1 regresszió + missing-priority fail-closed cella |
| A7 | Offline működik | ✅ | A7 widget-tesztek; diffben nincs hálózati/IO hívás |
| A8 | Aktiválás csak confirmra | ✅ | A8 célteszt; `confirmConfirmed()` az egyetlen activation-hívó |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e07-r21-remote.97t0XV --brief docs/rounds/e07-r21-plan-preview-and-explanation.md --base e7a6a2391b832e8e42afe0ff71e2b36eaa824ec2`

Eredmény: **OK**, 11 implementer-változás, 0 listán kívüli útvonal. Ez a
review-jelentés a review-artefaktum állandó mentességével kerül a branchre.

## Megállapítások

### F1 — BLOCKER — A tényleges preview-útvonal elrejti a gyenge confidence-et

- **Fájl:** `lib/features/practice_generator/presentation/screens/plan_preview_screen.dart:123-125`; `lib/features/practice_generator/presentation/widgets/plan_reason_sheet.dart:27-30, 119-136`
- **Probléma:** a screen `priority` nélkül nyitja a `PlanReasonSheet`-et. A
  sheet `null` priority-t magabiztosként kezel, ezért egy
  `evidence.tempo-accuracy` oknál a biztos hangvételű ARB-állítás megjelenik,
  miközben a hozzá tartozó `SkillPriority.uncertainty >= 0.5` lenne.
- **Hatás:** a felhasználó gyenge mérési evidence-et biztos állításként lát;
  ez sérti az `AGENTS.md` §5 confidence-határát és a brief A6/§5.4 kritériumát.
- **Kötelező javítás:** a valódi screen-útvonal kapja meg és adja át a
  blokknak megfelelő priority/confidence adatot, vagy a sheet fail-closed,
  bizonytalanságot jelző szöveget használjon, ha a priority hiányzik.
- **Ellenőrzés:** egész-screen widget regressziós teszt: `uncertainty >= 0.5`
  + `evidence.tempo-accuracy` blokkról megnyitott reason sheet tartalmazza a
  `plan-preview-reason-uncertain` elemet; a meglévő közvetlen sheet-teszt
  önmagában nem elég.
- **Státusz:** FIXED (`2ec8e7e7`, tesztek: `f132a237`, dokumentált valódi-sértés próba: `9cc1c321`)

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrizve |
|---|---|
| format | ✅ — 1617 fájl, 0 változás |
| analyze | ✅ — `No issues found` |
| célzott tesztek | ✅ — 10 preview + 6 reason-sheet teszt zöld |
| architecture / secrets / l10n | ✅ — mind zöld az izolált klónon |
| CI (teljes suite + property + APK) | függőben — a review-artefaktum commitja után exact-SHA dispatch következik |

## Merge-döntés

Az F1 lezárt, a correctness review APPROVED. Merge csak az exact-SHA CI teljes
suite + property + APK, valamint Router CI zöld eredménye után engedett.
