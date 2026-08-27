# E13-R32 review — Gamification Hub, Quest, Achievement és Reward UI

- **Reviewer:** Claude (orchestrátor, read-only review — ADR 0055 / `sdd-round-review`)
- **Dátum:** 2026-08-27
- **Kör-branch:** `sonnet-impl/e13-r32-gamification-ui`
- **Review-lt commit:** `54db96be` (pre-flight bázis: `481bf9bd`)
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Brief:** [`docs/rounds/e13-r32-gamification-ui.md`](../rounds/e13-r32-gamification-ui.md)
- **ADR:** [`0290`](../adr/0290-compassionate-streaks-and-idempotent-claims.md) — MÁR
  merge-elve (`5b32bd8e`); a kör ADR-t nem írt (§0.0.B/B2)

## VÉGSŐ DÖNTÉS: **APPROVED** — 0 BLOCKER / 0 MAJOR / 1 MINOR (a review során javítva) / 2 NOTE

---

## 1. Hogyan mértem

A review **read-only** volt: a kör kódját nem szerkesztettem. A mérés egy
független, izolált klónban futott (`/tmp/ss-review-e13-r32`, a kör commitjáról,
`tools/prepare-flutter-generated.sh` után), és minden állítás mögött ott a
tényleges parancs-kimenet.

### 1.1 Gépi scope-audit — **ok**

Az implementer-burkoló saját auditja (`.codex-round-status`):

```
scope_audit=ok
scope_audit_base=481bf9bd4f777a875960aee1c49f61cf3ff261bf
scope_audit_changed=33
```

Kézzel újramérve:

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e13-r32 \
    --brief docs/rounds/e13-r32-gamification-ui.md --base 481bf9bd
Legacy scope audit OK (481bf9bd4f77..54db96beb0c2, 33 changed path(s), 0 generated/ignored)
```

Nulla listán kívüli fájl. A tilos zóna (`docs/adr/**`, `lib/core/design_system/**`,
`tools/**`, `.github/**`, a `gamification/`-on kívüli `lib/features/**`)
érintetlen.

### 1.2 Célzott kapu izolált klónban — **MINDEN GATE ZÖLD**, exit 0

15 lépés, mind zöld, csonkítatlan kimenettel: `format` (2124 fájl, 0 változott),
`analyze` (0 lelet), 10 célteszt (`+9`, `+11`, `+5`, `+8`, `+1`, `+22`, `+44`,
`+1`, `+2`, `+1` — mind „All tests passed!"), `architecture` (12 allowlisted
deviation, változatlan), `secrets` (0 találat), `l10n` (paritás OK).

### 1.3 Golden (A9) — MINDKÉT architektúrán megmérve

```
$ tools/golden-x86.sh check test/ui/goldens/e13_r32_screens_golden_test.dart
00:53 +10: All tests passed!            → exit 0   (x86_64 = a CI architektúrája)

$ ~/flutter/bin/flutter test test/ui/goldens/e13_r32_screens_golden_test.dart
00:03 +5 -5: Some tests failed.         → 5 piros  (aarch64 = ez a box)
```

A 10 PNG (5 képernyő × {compact, compact_scale2}) commitolva van a
`test/ui/goldens/goldens/` alatt. Az aarch64-piros az [ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md) §2–§3 /
[L493](../LESSONS.md#l493) mért, architektúra-függő jelensége — **nem** a kör
hibája; lásd MINOR-1.

### 1.4 Falszifikációs próbák — eldobható sértések az izolált klónban

A §6.1 mérce-mátrix három legfontosabb hibás implementációját külön-külön
BEÍRTAM a klónba, megmértem, majd visszaállítottam (`git checkout --`,
ellenőrizve: nincs maradék diff).

| Beírt sértés | Elvárt piros cella | MÉRT eredmény |
|---|---|---|
| `streakV2BrokenTitle = "You lost your 30-day streak!"` | **A1** | ✅ PIROS: `streakV2BrokenTitle contains "!"` + `contains \blost\b` |
| `plannedRest` → a `broken` feliratot rendereli | **A5** | ✅ PIROS: „plannedRest renders streakV2PlannedRestTitle — distinct from BOTH grace and broken titles" |
| `reduceMotion` → az ünneplés `SizedBox.shrink()`-re tűnik | **A8** | ✅ PIROS: „reduceMotion=true zeroes AnimatedSize duration but drops no event" |

Mind a három a **feliratot és az adatforrást** méri, nem a widget típusát
([L403](../LESSONS.md#l403)). A `compassionate_copy_test.dart` ráadásul hordoz
egy kimondott **nem-üresség** cellát is („the scan is not vacuous"), tehát a
zöldje nem az üres halmazon nyert.

### 1.5 A pre-flight kötött állításai — mind betartva

| §0.0.B pont | Ellenőrzés | Eredmény |
|---|---|---|
| B4 — a felület SOHA nem ír főkönyvet | `grep -rn "appendIfAbsent" lib/features/gamification/presentation/` | **0 találat** (és a kör saját A3-cellája ugyanezt gépiesíti) |
| B8 — DS import CSAK a barrelen át | `grep -rn "core/design_system" lib/features/gamification/` | 6 találat, **mind** `design_system/public.dart` |
| B5 — nincs új „claim" gomb | `PendingRewardsCard.onRetry` a hívó `ActivityEventIngestor.drain()`-jére köt | ✅ a `RewardInboxItem` claim-mentes modellje érintetlen |
| B6 — A5 a `StreakEvaluationReason`-ra épül | `streak_states_test.dart` a `grace`/`plannedRest`/`broken` értékekre állít, `gap = 0/1/2` | ✅ |
| B9 — `ui_inventory` és `app_router_test` bázisvonal | `git diff` a két fájlon | **érintetlen**; `hasLength(94)` és mind a 6 pinnelt screen-TÍPUS változatlanul zöld |
| R2 — az 5 meglévő teszt nem gyengülhet | `git diff 481bf9bd..HEAD -- test/features/gamification/presentation/` | **üres diff** — egyik cella sem lett törölve, `skip`-elve vagy lazítva |

### 1.6 Valódi-sértés próba (a §6 KÖTELEZŐ eleme) — hitelesítve

Az implementer a `local_activity_outbox_repository.dart`-ba írt egy optimista,
főkönyv-megerősítés ELŐTTI jóváírást; a mért kimenet az **A2** cella pirosa
volt, majd visszaállította. Ellenőriztem: `git diff 481bf9bd..HEAD -- lib/features/gamification/data/`
→ **üres**, a próba nem hagyott maradékot.

---

## 2. Leletek

### MINOR-1 — a brief §7 gate-sora ARM-en mérhetetlen golden-cellát írt elő *(a review során JAVÍTVA)*

**Mit mértem.** A brief §7 sora (és a `gate_tests` tömb) tartalmazta a
`test/ui/goldens/e13_r32_screens_golden_test.dart` útvonalat. Ez az útvonal ezen
a boxon (aarch64) **5/10 cellán determinisztikusan piros**, miközben a merge-kapu
architektúráján (x86_64) **10/10 zöld** — a mérés az 1.3 szakaszban. A
`round-gate.sh` szekvenciális, tehát a literális sor futtatása a golden-lépésnél
MEGÁLLT volna, mielőtt az `architecture` / `secrets` / `l10n` lépések lefutnak.

**Az implementer helyesen járt el:** a golden-útvonal nélkül futtatta a kaput, a
golden-bizonyítékot pedig a `tools/golden-x86.sh record` + `check` párossal adta,
és a §10-ben mérve dokumentálta. Ez pontosan az [ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)
előírása — nem eltérés a mércétől, hanem a mérce helyes gépre tétele.

**A hiba az enyém, a pre-flightban:** a §7 sort az E13-R31 briefjéből örököltem,
ahol az adott képernyők történetesen nem drifteltek. Ez a kör megmérte, hogy a
drift **képernyő-függő**, tehát az útvonal listán hagyása nem konzervatív, hanem
hibás — és a `tools/round-land.sh --gate-test` úton fals pirosat is okozhatna.

**Javítás (ADR 0087 §2 — a kör saját, még nem merge-elt briefje az én
hatásköröm):** a golden-útvonal kikerült a `gate_tests` tömbből és a §7
`round-gate.sh` sorából, a `§0.0.C` szakasz pedig a fenti két mérést
táblázatosan rögzíti. **A mérce nem lazult:** a 10 golden-cellát továbbra is
KETTŐ méri — a kötelező `tools/golden-x86.sh check` és az exact-SHA
`full-gate.yml` teljes suite-ja, mindkettő x86_64-en, változatlan nulla
toleranciájú komparátorral. Egy cella sincs törölve vagy `skip`-elve.

### NOTE-1 — az A7 bizonyíték-oszlopa rossz fájlra mutatott; a kritérium mégis mérve van

A brief §6 A7 sora („Az eredmény feltétele megjelenik és érthető") a
`compassionate_copy_test.dart`-ot jelölte meg bizonyítékként, de az a fájl nem
tartalmaz A7-cellát. A kritériumot valójában egy **merge-elt, futó** őr méri:

```
test/features/gamification/presentation/achievements_screen_test.dart:209
  expect(find.text('Measured progress: 3 of 5.'), findsOneWidget);
```

Ez a teszt a kör `allowed_paths`-án van, **módosítás nélkül** maradt, és a CI
teljes suite-jában fut. A7 tehát teljesül; a lelet a brief bizonyíték-oszlopának
pontatlansága, nem hiányzó mérce. Nem javítottam a brief §6 tábláját, mert az
állítás így is igaz — a §10 handoff pedig kimondottan megnevezi a tényleges őrt.

### NOTE-2 — három widget szándékosan kimaradt a DS-migrációból, mérve és indokolva

`_InboxIndicator` (Hub), `_StreakMetricCard` és `_InboxEntryTile` a korábbi
alakján maradt: az első egyedi accent-színt használ, amit az `SsSurface` nem
paraméterez, a második egy meglévő `find.byType(Card)` asszerciót visel a
`streak_detail_screen_test.dart`-ban. A §10 ezt kimondja. **Szűkítés, nem
csendes kihagyás** — és a `test/core/architecture_dependency_test.dart` zöldje
igazolja, hogy a MEGTÖRTÉNT migráció szabályos.

---

## 3. Amit a kör hozott (mért összegzés)

- **33 fájl**, +2661 / −747 sor.
- A 7 gamifikációs képernyő design-system migrációja a `GamificationThemeScope`
  + `SsSurface` mentén, kizárólag a `public.dart` barrelen át — a fa korábban
  **nulla** DS-importtal élt (§0.0.B/B8).
- Új `PendingRewardsCard`: a függő/karanténos főkönyvi sorok caller-fed
  felülete, `onRetry` → `ActivityEventIngestor.drain()`. **Sosem** ír főkönyvet
  és sosem mutat jóváírt egyenleget a drain előtt.
- `reduceMotion` szál a `StreakStatusCard` / `StreakDetailScreen` /
  `RewardSummarySheet` widgeteken, VAGY-kapcsolva a
  `MediaQuery.disableAnimationsOf`-fal (ADR 0393 §5.1 bekötése).
- 6 új l10n-kulcs a `gamification_{en,hu}.arb` **forrás**-fragmentumba, en+hu
  paritással; az aggregátum regenerálva.
- 4 új gate-teszt (33 cella) + a 10 golden-felvétel.
- **Két, a felvétel közben MÉRT elrendezési hiba javítva** `textScaler 2.0`
  mellett: egy 1577px-es `RenderFlex overflow` az új kártyán, és egy 41px-es
  vízszintes túlcsordulás a **kör előtti** `_InboxEntryTile` XP-feliratán. Ez
  pontosan az A9 létjogosultsága: a golden nem regressziót fogott, hanem egy
  meglévő, addig láthatatlan hibát.

## 4. CI-evidencia

| Workflow | Run | SHA | Eredmény |
|---|---|---|---|
| Router CI | [33063508535](https://github.com/wolfcasaba/strumsight/actions/runs/33063508535) | `54db96be` | ✅ success |
| Full Gate (no APK) | [33063492002](https://github.com/wolfcasaba/strumsight/actions/runs/33063492002) | `54db96be` | lásd a PR-t / a merge-kori újramérést |

A `round-ci-plan.py` verdiktje: `dispatch = ["full-gate.yml"]`, `apk_required =
false` (`native_gate = false`, a diff nem érint natív/release útvonalat),
`router_ci_expected = true` (`docs/rounds/**`). A merge-kapu **exact-SHA**: a
záró SHA-n mindkét futásnak zöldnek kell lennie.
