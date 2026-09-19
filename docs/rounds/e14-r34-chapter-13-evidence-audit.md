# E14-R34 — Chapter 13 repositoryba emelése: bizonyíték-audit

- **Kör:** E14-R34 · **Csomag:** PKG-C · **ADR:** nincs (a kör
  **DONE-ELSEWHERE**; új döntés nem született, tehát ADR-számot sem foglal)
- **Státusz:** **DONE-ELSEWHERE** ✅ + egy egysoros link-javítás kérése
- **Ág:** `claude/laptop-apk-debug-prompt-kys4oa`
- **Környezet:** nincs Dart/Flutter SDK — ez a kör kizárólag dokumentum-audit,
  kód nem változik.

## 1. Cél

Megállapítani, hogy a Ch14 Kör 34 („Chapter 13 a repositoryban, SDD-indexbe
és traceability mátrixba kötve") követelménye **teljesült-e**, és ha igen,
akkor a bizonyíték-tábla ellenőrzött formában rögzüljön — nem állításként,
hanem a fán mérhető fájlokra és sorokra mutatva.

## 2. Mért állapot

### 2.1 Bizonyíték-tábla (mind ellenőrizve a fán, 2026-09-09)

| Követelmény-elem | Bizonyíték a fán | Ellenőrizve |
|---|---|---|
| Chapter 13 specifikáció | `docs/sdd/13-chapter-13-ui-ux-design-system.md` | ✅ létezik |
| Foundations | `lib/core/design_system/foundations/` — `ss_breakpoints`, `ss_colors`, `ss_elevation`, `ss_motion`, `ss_radius`, `ss_semantics`, `ss_spacing`, `ss_typography` | ✅ 8 fájl |
| Témák | `lib/core/design_system/themes/` — `ss_dark_theme`, `ss_light_theme`, `ss_high_contrast_theme`, `ss_theme_extensions` | ✅ 4 fájl |
| Motion | `lib/core/design_system/motion/` — `ss_beat_pulse`, `ss_motion_scope`, `ss_transitions` | ✅ 3 fájl |
| Ikonok | `lib/core/design_system/icons/` — `ss_guitar_glyphs`, `ss_icon`, `ss_icons` | ✅ 3 fájl |
| Akadálymentesség | `lib/core/design_system/accessibility/` — `ss_live_region`, `ss_tap_target` | ✅ 2 fájl |
| Komponensek | `lib/core/design_system/components/` — actions, ai, analytics, cards, feedback, inputs, music, overlays, surfaces | ✅ 9 alkönyvtár |
| Layoutok | `lib/core/design_system/layouts/` — `ss_adaptive_scaffold`, `ss_stage_scaffold` | ✅ 2 fájl |
| Dokumentáció-felület | `lib/core/design_system/documentation/component_catalog_screen.dart` | ✅ |
| Barrel-szerződés | `lib/core/design_system/public.dart` (a `check_architecture.dart` kikényszeríti: a design systembe CSAK ezen át vezet import) | ✅ |
| Kör-briefek | `docs/rounds/e13-r02…r07`, `e13-r14-accessibility-toolkit.md`, `e13-r36-visual-regression-and-closure.md` | ✅ |
| Téma-goldenek + variant-mátrix | `test/ui/goldens/e13_r36_variant_matrix_test.dart`, `e15_r13_full_variant_matrix_test.dart`, `e15_r01_theme_adoption_test.dart` + a `goldens/` PNG-k | ✅ |
| Kontraszt-szerződés | `test/core/design_system/themes/contrast_test.dart` + `tool/ui_contrast_check.dart` | ✅ |
| Lezárási riport | `docs/ui/chapter-13-completion-report.md` | ✅ |
| SDD-index bekötés | `docs/sdd/00-index.md:27` — Ch13, 36 kör, „queue-szinten lezárva (36/36 done)" | ✅ |
| Traceability mátrix | `docs/execution/06-requirements-traceability-matrix.md` — E13-R02…E13-R36 minden sora `Done` | ✅ |

### 2.2 Az EGYETLEN hiba

`docs/execution/06-requirements-traceability-matrix.md` **349. sor** (az
`E13-R02` sor) egy **nem létező fájlra** hivatkozik:

```
[`13-ui-ux-design-system.md`](../sdd/13-ui-ux-design-system.md)
```

A valódi név `13-chapter-13-ui-ux-design-system.md` — ugyanezen a lapon a
350. sortól (E13-R03-tól) MINDEN további sor már a helyes nevet használja,
tehát ez egy elmaradt átnevezés egyetlen sorban. A fán nincs más előfordulása
(`grep -rn "13-ui-ux-design-system.md" docs/` → csak ez az egy sor, plusz a
befejezési terv, ami magát a hibát idézi).

## 3. Scope

**Benne:** a fenti bizonyíték-tábla ellenőrzése és rögzítése.

**Kívül:** a javítás elvégzése. A `docs/execution/06-requirements-traceability-matrix.md`
az Epic-14 csomagfelosztás szerint **PKG-D kizárólagos tulajdona**
(`epic-14-completion-plan.md` §4), ezért PKG-C nem szerkeszti — a pontos
patch a §10-ben.

## 4. Érintett fájlok

**Új:** ez a brief.
**Módosított:** egy sem (a javítást PKG-D landolja).

## 5. Döntések

Nincs új döntés → **nincs ADR**. A kör tartalma bizonyíték-ellenőrzés.

## 6. Acceptance

| # | Kritérium | Státusz |
|---|---|---|
| C1 | Chapter 13 a repositoryban, teljes design-system fával | **DONE-ELSEWHERE** — §2.1 tábla, minden sor a fán ellenőrizve |
| C2 | SDD-index bekötés | **DONE-ELSEWHERE** — `docs/sdd/00-index.md:27` |
| C3 | Traceability mátrix E13 sorai | **DONE-ELSEWHERE** — `06-requirements-traceability-matrix.md:349–…`, mind `Done` |
| C4 | A mátrix minden hivatkozása élő fájlra mutat | **NOT-DONE (más tulajdonos)** — a 349. sor dead linkje; patch §10, tulajdonos PKG-D |
| C5 | Vizuális regresszió-fedezet | **DONE-ELSEWHERE** — téma-goldenek + variant-mátrix; a 360 px hézagot az [E14-R39](e14-r39-adaptive-accessibility-outdoor-audit.md) zárja |

## 7. Verifikáció

Dokumentum-audit; `grep` és fájllista-ellenőrzés, kód nem változott, tehát
nincs futtatandó cella. A §2.1 tábla minden sora a fán ellenőrzött útvonal.

## 8. Kockázatok

Nincs kódkockázat. Egyetlen nyitott pont a §10 patch landolása.

## 9. Nem-célok

Nem nyitja újra a Chapter 13 köreit, nem ír goldent, nem módosít design
tokent. **Nem** billenti át az `adaptiveShellEnabled` zászlót sem — az az
R35 nyitott pontja és **emberi GA-döntés**, nem kódfeladat.

## 10. Handoff — kért patch PKG-D-nek (C4)

Fájl: `docs/execution/06-requirements-traceability-matrix.md`, **349. sor**
(az `E13-R02` sor). Egyetlen csere a soron belül:

```diff
-| E13-R02 | Chapter 13, Kör 2 — Design System Foundation és compatibility layer | [`13-ui-ux-design-system.md`](../sdd/13-ui-ux-design-system.md), [ADR 0273](../adr/0273-design-system-token-source-of-truth.md) |
+| E13-R02 | Chapter 13, Kör 2 — Design System Foundation és compatibility layer | [`13-chapter-13-ui-ux-design-system.md`](../sdd/13-chapter-13-ui-ux-design-system.md), [ADR 0273](../adr/0273-design-system-token-source-of-truth.md) |
```

Ekvivalens, kisebb kockázatú alak (a sor többi része érintetlen marad):

```
a linkszöveg  `13-ui-ux-design-system.md`      → `13-chapter-13-ui-ux-design-system.md`
a cél útvonal ../sdd/13-ui-ux-design-system.md → ../sdd/13-chapter-13-ui-ux-design-system.md
```

Ellenőrzés a landolás után:

```bash
grep -rn "sdd/13-ui-ux-design-system.md" docs/   # csak a completion-plan idézete maradhat
```
