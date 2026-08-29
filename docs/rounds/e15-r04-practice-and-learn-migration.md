# E15-R04 — Practice és Learn képernyők migrálása

- **Státusz:** READY (előre megírva 2026-08-28 `main @ 4cb32eb0`-n; pre-flight
  revízió — §0.0/R1–R9 — MÉRVE `main @ ccc71460`-en, 2026-08-29)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 4
- **Kör-azonosító:** `E15-R04`
- **Branch:** `<motor>/e15-r04-practice-and-learn-migration`
- **Előfeltétel:** `E15-R03` merge-elve (a visszavonási terv dönti el, mit KELL migrálni)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — migrációs kör, kötött ÚJ architekturális döntés nélkül (a hivatkozott szerződéseket korábbi ADR-ek rögzítik).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "practice hub result history speed builder UI migration design system"` → a `halts/round-status-E13-R22` (Practice results és Speed Builder UI) és a `halts/round-status-E13-R32` merge-elt körei — a Ch13 EZEKRE a képernyőkre MÁR épített design-rendszer-komponenseket, csak a legacy képernyők nem használják őket.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd be a `docs/ui/retirement-plan.md` (E15-R03) sorait erre a batch-re, és mérd újra, mely képernyők legacyk MÉG:
> ```bash
> for f in lib/features/practice/presentation/screens/practice_hub_screen.dart lib/features/practice/presentation/screens/practice_result_screen.dart lib/features/practice/presentation/screens/practice_history_screen.dart lib/features/practice/presentation/screens/speed_builder_screen.dart lib/features/learn/screens/learn_screen.dart lib/features/learn/screens/lesson_list_screen.dart lib/features/learn/screens/lesson_score_preview_screen.dart lib/features/learn/screens/latency_calibration_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
> ```
> A megíráskor mind a **8** felsorolt képernyő legacy volt. Ami időközben migrálódott, azt a §3 scope-ból ki kell venni.

## 0.0 A kör határa: MEGJELENÉS, nem viselkedés

A migráció a képernyők VIZUÁLIS rétegét cseréli design-rendszer-komponensekre. A képernyő TÍPUSA, route-ja, publikus API-ja és üzleti viselkedése VÁLTOZATLAN — a típus-pinnelő tesztek (§4) ezért maradnak zöldek, és a jogosultság pontosan ennyi: **cella törlése, `skip`-je vagy gyengítése TILOS**. Az `E15-R01` óta az app témája hordozza a tokeneket, tehát ÚJ `*ThemeScope` burkoló NEM vezethető be; a meglévő burkoló eltávolítható, ha a képernyő már az app témájából old fel.

Ez a leggyakrabban látott felület: a gyakorlás belépője, eredménye és a Learn-út. A `practice_hub` a shell `Practice` destinationjének egyik célja, tehát a felhasználó szinte minden munkamenetben látja.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice/presentation/screens/practice_hub_screen.dart",
  "lib/features/practice/presentation/screens/practice_result_screen.dart",
  "lib/features/practice/presentation/screens/practice_history_screen.dart",
  "lib/features/practice/presentation/screens/speed_builder_screen.dart",
  "lib/features/learn/screens/learn_screen.dart",
  "lib/features/learn/screens/lesson_list_screen.dart",
  "lib/features/learn/screens/lesson_score_preview_screen.dart",
  "lib/features/learn/screens/latency_calibration_screen.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/chords/chord_library_test.dart",
  "test/features/learn/continue_card_test.dart",
  "test/features/learn/expected_chord_hint_test.dart",
  "test/features/learn/latency_calibration_screen_test.dart",
  "test/features/learn/learn_rollback_test.dart",
  "test/features/learn/learn_screen_test.dart",
  "test/features/learn/learning_path_test.dart",
  "test/features/learn/lesson_list_screen_test.dart",
  "test/features/learn/lesson_offline_test.dart",
  "test/features/learn/lesson_score_card_test.dart",
  "test/features/learn/live_scoring_jitter_test.dart",
  "test/features/learn/next_lesson_cta_test.dart",
  "test/features/learn/review_r100_fixes_test.dart",
  "test/features/learn/setlist_expected_hint_test.dart",
  "test/features/learn/visual_offset_test.dart",
  "test/features/learn/waltz_count_in_test.dart",
  "test/features/practice/history_corrupt_record_test.dart",
  "test/features/practice/presentation/practice_a11y_audit_test.dart",
  "test/features/practice/presentation/practice_hub_screen_test.dart",
  "test/features/practice/presentation/practice_result_screen_test.dart",
  "test/features/practice/presentation/practice_routing_test.dart",
  "test/features/practice/result_confidence_test.dart",
  "test/features/practice/reward_idempotency_test.dart",
  "test/features/practice/speed_ladder_test.dart",
  "test/features/songs/setlist_flow_test.dart",
  "test/ui/goldens/e13_r20_screens_golden_test.dart",
  "test/ui/goldens/e13_r22_screens_golden_test.dart",
  # §0.0/R4 — a batch NÉGY képernyőjének VAN goldenje; a migráció ezeket a
  # pixeleket megváltoztatja, és a §7 már elő is írja az újrafelvételt, de a
  # KIMENETI fájlok hiányoztak a listáról. Tételesen (nem könyvtárként):
  "test/ui/goldens/goldens/e13_r20_learning_path_compact.png",
  "test/ui/goldens/goldens/e13_r20_learning_path_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r22_practice_result_compact.png",
  "test/ui/goldens/goldens/e13_r22_practice_result_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r22_practice_history_compact.png",
  "test/ui/goldens/goldens/e13_r22_practice_history_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r22_speed_builder_compact.png",
  "test/ui/goldens/goldens/e13_r22_speed_builder_compact_scale2.png",
  # §0.0/R5 — a §3/§5.3 megengedi az ÚJ ARB-kulcsot (mindkét locale-ra) és
  # tiltja a beégetett szöveget, de egyetlen ARB-útvonal sem volt a listán.
  # Az aggregátum GENERÁLT (ADR 0307 §4), a scope-audit viszont NEM ismer
  # generált-kivételt (mérve), ezért mind a négy fájl a listán van.
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "docs/ui/migration-status.md",
  "docs/rounds/e15-r04-practice-and-learn-migration.md",
]
gate_tests = [
  "test/ui/ui_inventory_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/chords/chord_library_test.dart",
  "test/features/learn/continue_card_test.dart",
  "test/features/learn/expected_chord_hint_test.dart",
  "test/features/learn/latency_calibration_screen_test.dart",
  "test/features/learn/learn_rollback_test.dart",
  "test/features/learn/learn_screen_test.dart",
  "test/features/learn/learning_path_test.dart",
  "test/features/learn/lesson_list_screen_test.dart",
  "test/features/learn/lesson_offline_test.dart",
  "test/features/learn/lesson_score_card_test.dart",
  "test/features/learn/live_scoring_jitter_test.dart",
  "test/features/learn/next_lesson_cta_test.dart",
  "test/features/learn/review_r100_fixes_test.dart",
  "test/features/learn/setlist_expected_hint_test.dart",
  "test/features/learn/visual_offset_test.dart",
  "test/features/learn/waltz_count_in_test.dart",
  "test/features/practice/history_corrupt_record_test.dart",
  "test/features/practice/presentation/practice_a11y_audit_test.dart",
  "test/features/practice/presentation/practice_hub_screen_test.dart",
  "test/features/practice/presentation/practice_result_screen_test.dart",
  "test/features/practice/presentation/practice_routing_test.dart",
  "test/features/practice/result_confidence_test.dart",
  "test/features/practice/reward_idempotency_test.dart",
  "test/features/practice/speed_ladder_test.dart",
  "test/features/songs/setlist_flow_test.dart",
  # §0.0/R6 — az A6 bizonyítéka eddig nem futott a kapuban (futtatni kell,
  # SZERKESZTENI tilos — nincsenek az allowed_paths-on):
  "test/l10n/hardcoded_string_guard_test.dart",
  "test/l10n/arb_parity_test.dart",
  # §0.0/R3 — a két golden-teszt-fájl NEM a lokális ARM-kapuban fut (ADR 0426):
  # `main @ ccc71460`-en, kör-változtatás NÉLKÜL az `e13_r20_screens_golden_test.dart`
  # 3/6 cellája piros (L516 raszter-drift). A golden-sáv mércéje:
  #   tools/golden-x86.sh check test/ui/goldens/e13_r20_screens_golden_test.dart \
  #                             test/ui/goldens/e13_r22_screens_golden_test.dart
]
native_gate = false
```

**Kockázat = high, indoklás:** a diff felhasználói felületet ír át azon az úton, amit a felhasználó a leggyakrabban jár; egy elveszett állapot- vagy hibajelzés némán rontaná az élményt. A `flutter-reviewer` és a `flutter-devil-advocate` futtatása a review-ban KÖTELEZŐ.

### 0.0 Pre-flight revízió — MÉRVE `main @ ccc71460` (2026-08-29, orchestrátor)

A brief 2026-08-28-án, `main @ 4cb32eb0`-n íródott. A `brief-lint --strict`
nem talált leletet; az alábbi kilenc pont a KÓDBÓL és a FUTTATÁSBÓL mért
javítás. A kör hatóköre (8 képernyő, megjelenés-csak) VÁLTOZATLAN.

**R1 — a batch mind a 8 képernyője MÉG legacy.** A §7 mérő-parancs kimenete
`main @ ccc71460`-en mind a 8 sorra `legacy` — egyetlen képernyő sem esik ki a
§3 scope-ból.

**R2 — a `retirement-plan.md` gazda-kör oszlopa és a queue eltér; a DÖNTÉS
oszlop egyezik.** A terv (E15-R03) mind a 8 képernyőre `migrate` döntést ad —
ez a kötelező tartalom, és egyezik. A „gazda-kör" oszlopa viszont `E15-R07`
(learn) / `E15-R08` (practice), miközben a queue előre megírt briefjei ott MÁS
feature-t visznek (`e15-r07-practice-generator-migration`,
`e15-r08-gamification-migration`) — a terv oszlopát követve ez a 8 képernyő
SOHA nem migrálódna. Kötelező: a queue + ez a brief; a terv gazda-kör oszlopa
javaslat (ADR 0471: „retirement is a proposal, not an execution"). Kettős
migráció nincs. A `retirement-plan.md` NINCS az `allowed_paths`-on → nem
szerkesztjük; a korrekció egy sora a `docs/ui/migration-status.md`-be megy (A7).

**R3 — BASE-lelet: a golden-sáv ezen a boxon NEM mérhető, a §7 kapu-sora
zöldíthetetlen volt.** Mérve, kör-változtatás NÉLKÜL, `main @ ccc71460`:

```
flutter test test/ui/goldens/e13_r20_screens_golden_test.dart
  → 00:03 +3 -3: Some tests failed.
    chord detail — compact / chord detail — compact_scale2 / learning path — compact
flutter test test/ui/goldens/e13_r22_screens_golden_test.dart
  → 00:02 +6: All tests passed!
```

Ez a L516 ARM↔x86 raszter-drift, pontosan az a hibaosztály, amit az ADR 0426
kivett a lokális kapuból (az r22 lokális zöldje esetleges, nem szerződés). A
két golden-teszt-fájl ezért KIKERÜLT a `gate_tests`-ből és a §7
`round-gate.sh` sorából; a golden-sáv a `tools/golden-x86.sh check|record`
alatt fut. **A mérce nem lazul:** ugyanaz a nulla toleranciájú
`LocalFileComparator`, ugyanaz a golden-készlet, a CI architektúráján. A
harness elérhetősége MÉRVE ezen a boxon: `docker 29.4.0`,
`docker run --platform linux/amd64 alpine uname -m` → `x86_64`, a
`strumsight-golden-x86:3.44.2` image gyorsítótárazva.

**R4 — a batch 4 képernyőjének VAN goldenje, a PNG-k nem voltak a listán.**
`LessonListScreen` → `e13_r20_learning_path_{compact,compact_scale2}.png`;
`PracticeResultScreen` / `PracticeHistoryScreen` / `SpeedBuilderScreen` → 6
`e13_r22_*` PNG. A §7 már előírta az újrafelvételt, de a kimeneti fájlok
hiányoztak az `allowed_paths`-ról — belső ellentmondás a kör SAJÁT
artefaktumában, tételes (nem könyvtár-szintű) felvétellel feloldva. A másik
négy képernyőnek (`practice_hub`, `learn`, `lesson_score_preview`,
`latency_calibration`) nincs goldenje — mérve: `grep -rl` a nyolc
képernyő-osztályra a `test/ui/goldens/` fában csak ezt a két teszt-fájlt adja.

**R5 — az ARB-út zsákutca volt.** A §3 megengedi az új kulcsot (mindkét
locale-ra), a §5.3 tiltja a beégetett szöveget — de egyetlen ARB-útvonal sem
volt az `allowed_paths`-on, tehát egy szükséges új kulcs csak
scope-sértéssel vagy `stopped`-dal lett volna felvehető. Felvéve a
`lib/l10n/base/app_{en,hu}.arb` FORRÁS és a `lib/l10n/app_{en,hu}.arb`
GENERÁLT aggregátum (ADR 0307 §4; a `tools/scope-audit.py`-ban MÉRVE nincs
generált-kivétel). Új kulcs = base mindkét locale-on + `dart run
tool/gen_l10n_segments.dart` újragenerálás, egy lépésben.

**R6 — az A6 bizonyítéka nem futott.** Az A6 a
`test/l10n/hardcoded_string_guard_test.dart`-ra hivatkozik, de az nem volt a
kapu-sorban → az A6 mérés nélkül maradt. Felvéve a `gate_tests`-be az
`arb_parity_test.dart`-tal együtt; szerkeszteni tilos (nincsenek az
`allowed_paths`-on — E13-R22 precedens).

**R7 — L536 eljárási őr.** A `test/ui/goldens/failures/**` NEM KÖVETETT,
generált bukás-artefaktum, amit a gépi scope-audit a diffnek számol (E15-R02:
60 PNG → hamis `VIOLATION`). Kötelező: `rm -rf test/ui/goldens/failures` a
`done` jelzés ELŐTT, és tételes `git add` — `git add -A` tilos.

**R8 — nincs ÚJ ADR, és ez mért döntés.** A kör nem hoz új architekturális
döntést; a kötő szerződések már merge-eltek: ADR 0466 (az app témája a
design-rendszer témája), ADR 0467 (adaptív shell), ADR 0471 (az elérhetőség
MÉRT), ADR 0273 (egy token-forrás), ADR 0426 (golden-raszter a merge-kapu
architektúráján). A `docs/adr/**` marad a tilos zónában.

**R9 — visszakeresés (ADR 0312, szűkítve ELŐSZÖR).**
`lessons,halts,adr`: [L536](../LESSONS.md#l536) (a golden-`failures/` hamis
scope-sértése), [L516](../LESSONS.md#l516) (ARM↔x86 drift),
[ADR 0426](../adr/0426-golden-rasterization-on-the-merge-gate-architecture.md),
[ADR 0471](../adr/0471-screen-reachability-is-measured-not-assumed.md),
[ADR 0273](../adr/0273-design-system-token-source-of-truth.md); a golden
újrafelvételes migrációs precedens: `halts/round-status-E13-R25`, `E13-R26`.
Teljes korpusz: nem hozott a fentieken túli releváns előzményt.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a migrációhoz egy `application/`, `domain/` vagy `data/` réteg módosítása kellene, a kimenet a `stopped` jelzés — a viselkedés-változás nem ennek a körnek a hatásköre ([L478](../LESSONS.md#l478)).

## 1. Cél

A batch 8 képernyője a design-rendszer komponenseit és tokenjeit használja, változatlan viselkedés mellett — hogy a felület egységes legyen, és a 200%-os szövegskála, a képernyőolvasó és a két locale mindenhol működjön.

## 2. Jelenlegi állapot — mért tények

- A batch képernyői (MÉRVE `grep -L design_system`): `practice_hub_screen.dart`, `practice_result_screen.dart`, `practice_history_screen.dart`, `speed_builder_screen.dart`, `learn_screen.dart`, `lesson_list_screen.dart`, `lesson_score_preview_screen.dart`, `latency_calibration_screen.dart`.
- Egyik sem importálja a `core/design_system`-et; a stílusuk közvetlen `Theme.of(context)` / `AppColors` / `AppPalette` hivatkozásokból jön.
- Az `E15-R01` óta az app futásidejű témája a design-rendszer témája, tehát a komponensek burkoló NÉLKÜL is feloldják a tokeneket.
- Az `E15-R02` óta az adaptív shell az alapértelmezett belépő, tehát ezek a képernyők a fő navigációból elérhetők.
- A `test/ui/ui_inventory_test.dart` EGZAKT képernyőszámot állít — a kör nem hoz létre és nem töröl képernyőt, tehát a szám VÁLTOZATLAN.

## 3. Scope

**Benne van:** a felsorolt 8 képernyő vizuális migrálása (`SsCard`, `SsButton`, `SsListTile`, `SsEmptyState`, `SsErrorState`, `SsMetricTile` és társaik; `SsSpacing`/`SsTypography` tokenek) · a meglévő `*ThemeScope` burkoló eltávolítása, ahol az `E15-R01` óta felesleges · a `migration-status.md` frissítése a MÉRT új aránnyal.

Batch-specifikus kikötések:

- a `practice_result_screen` pontszám- és visszajelzés-blokkjai `SsCard`/`SsMetricTile` komponensekre kerülnek, a MÉRT értékek és a kerekítés változatlanul
- a `speed_builder_screen` lépcső-vezérlője megtartja a jelenlegi BPM-lépéseket — a DSP/időzítés-paraméterekhez NEM nyúlunk (AGENTS.md §9)
- a `latency_calibration_screen` mérési folyamata (a kalibrációs számok és a küszöbök) érintetlen marad

**NINCS benne (tilos):**

- `application/`, `domain/`, `data/`, `providers/` réteg módosítása (viselkedés-változás).
- Új képernyő létrehozása vagy meglévő törlése.
- Új `*ThemeScope` burkoló bevezetése.
- ARB-kulcs törlése vagy szöveg-jelentés megváltoztatása (új kulcs FELVEHETŐ, ha a komponens ezt igényli — mindkét locale-ra, egyszerre).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/practice/presentation/screens/practice_hub_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/practice/presentation/screens/practice_result_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/practice/presentation/screens/practice_history_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/practice/presentation/screens/speed_builder_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/learn/screens/learn_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/learn/screens/lesson_list_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/learn/screens/lesson_score_preview_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/learn/screens/latency_calibration_screen.dart` | migráció design-rendszer komponensekre |
| `test/app/navigation/adaptive_scaffold_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/app/navigation/legacy_route_redirect_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/app/offline_network_guard_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/core/screen_size_guard_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/chords/chord_library_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/continue_card_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/expected_chord_hint_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/latency_calibration_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/learn_rollback_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/learn_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/learning_path_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/lesson_list_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/lesson_offline_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/lesson_score_card_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/live_scoring_jitter_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/next_lesson_cta_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/review_r100_fixes_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/setlist_expected_hint_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/visual_offset_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/waltz_count_in_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/practice/history_corrupt_record_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/practice/presentation/practice_a11y_audit_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/practice/presentation/practice_hub_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/practice/presentation/practice_result_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/practice/presentation/practice_routing_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/practice/result_confidence_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/practice/reward_idempotency_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/practice/speed_ladder_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/setlist_flow_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r20_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r22_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/goldens/e13_r20_learning_path_compact{,_scale2}.png` | §0.0/R4 — a `LessonListScreen` goldenjei, x86-on ÚJRAFELVÉVE |
| `test/ui/goldens/goldens/e13_r22_practice_result_compact{,_scale2}.png` | §0.0/R4 — x86-on ÚJRAFELVÉVE |
| `test/ui/goldens/goldens/e13_r22_practice_history_compact{,_scale2}.png` | §0.0/R4 — x86-on ÚJRAFELVÉVE |
| `test/ui/goldens/goldens/e13_r22_speed_builder_compact{,_scale2}.png` | §0.0/R4 — x86-on ÚJRAFELVÉVE |
| `lib/l10n/base/app_en.arb`, `lib/l10n/base/app_hu.arb` | §0.0/R5 — ÚJ kulcs forrása, csak ha a komponens megköveteli |
| `lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb` | §0.0/R5 — generált aggregátum (`tool/gen_l10n_segments.dart`) |
| `docs/ui/migration-status.md` | a MÉRT arány frissítése + a §0.0/R2 gazda-kör korrekció egy sora |

**Tilos zóna:** a batch feature-einek `application/`, `domain/`, `data/`, `providers/` könyvtárai · minden más `lib/features/**` képernyő · `lib/app/**` · `lib/core/design_system/**` (a komponenseket HASZNÁLJUK, nem módosítjuk) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

Nincs ÚJ ADR. Három kötelező szabály:

### 5.1 A viselkedés bitre azonos marad

Ugyanaz az adat, ugyanaz a sorrend, ugyanazok az állapotok (üres, betöltés, hiba). **NEM elfogadható gyengítés:** „egyszerűsítettük a hibaállapotot" — az információvesztés, nem migráció.

### 5.2 Minden állapotnak van design-rendszer-megfelelője

Üres lista → `SsEmptyState`, hiba → `SsErrorState`, betöltés → a design-rendszer betöltés-komponense. **NEM elfogadható gyengítés:** nyers `CircularProgressIndicator` vagy csupasz `Text('Hiba')` meghagyása.

### 5.3 A szöveg lokalizált marad

Beégetett felhasználói szöveg nem kerülhet a migrált kódba; új szöveg egyszerre `en` ÉS `hu` ARB-kulcsot kap. **NEM elfogadható gyengítés:** angol placeholder „amíg lefordítjuk".

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Mind a 8 képernyő importálja a `core/design_system`-et, és a mérés szerint migráltnak számít | a §7 mérő-parancs kimenete a §10-ben |
| A2 | Minden migrált képernyő üres/betöltés/hiba állapota design-rendszer-komponens | a batch célzott widget-tesztjei |
| A3 | A képernyők `textScaler 2.0` mellett, `en` ÉS `hu` locale-on túlcsordulás nélkül renderelnek | a batch variáns-cellái |
| A4 | A típus-pinnelő tesztek VÁLTOZATLANUL zöldek, egyetlen cellájuk sem törölt/`skip`-elt | a §7 gate + `git diff` a teszt-fájlokon |
| A5 | A `ui_inventory_test.dart` egzakt száma VÁLTOZATLAN | a §7 gate |
| A6 | Nincs beégetett felhasználói szöveg a migrált kódban | `test/l10n/hardcoded_string_guard_test.dart` |
| A7 | A `migration-status.md` a MÉRT új arányt írja (a mérés parancsával) | a dokumentum |

**Küszöb-cellahármas a szövegskálára** (a kötelező határ `2.0`, INKLUZÍV): a küszöb **alatt** (`1.5`) → nincs túlcsordulás; **pontosan rajta** (`2.0`) → nincs túlcsordulás, EZ az A3 feltétele; a küszöb **fölött** (`2.5`) → nem követelmény, és a `2.0` teljesítése nem hivatkozhat rá.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A képernyő megkapja a komponenseket, de a hibaállapot nyers `Text` marad | A2 |
| A migráció csak `en` locale-on lett kipróbálva, a hosszabb `hu` szöveg túlcsordul | A3 |
| A migráció közben egy típus-pinnelő teszt cellája `skip`-re kerül a zöldért | A4 |
| Egy szöveg beégetve kerül a kódba | A6 |
| A képernyő importálja a design-rendszert, de a stílus továbbra is `AppColors`-ból jön | A1 (a mérés a MIGRÁLT/legacy besorolást is ellenőrzi a kód alapján) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** cserélj vissza EGY migrált képernyőn egy `SsErrorState`-et nyers `Text`-re, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/ui/ui_inventory_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/offline_network_guard_test.dart test/core/screen_size_guard_test.dart test/features/chords/chord_library_test.dart test/features/learn/continue_card_test.dart test/features/learn/expected_chord_hint_test.dart test/features/learn/latency_calibration_screen_test.dart test/features/learn/learn_rollback_test.dart test/features/learn/learn_screen_test.dart test/features/learn/learning_path_test.dart test/features/learn/lesson_list_screen_test.dart test/features/learn/lesson_offline_test.dart test/features/learn/lesson_score_card_test.dart test/features/learn/live_scoring_jitter_test.dart test/features/learn/next_lesson_cta_test.dart test/features/learn/review_r100_fixes_test.dart test/features/learn/setlist_expected_hint_test.dart test/features/learn/visual_offset_test.dart test/features/learn/waltz_count_in_test.dart test/features/practice/history_corrupt_record_test.dart test/features/practice/presentation/practice_a11y_audit_test.dart test/features/practice/presentation/practice_hub_screen_test.dart test/features/practice/presentation/practice_result_screen_test.dart test/features/practice/presentation/practice_routing_test.dart test/features/practice/result_confidence_test.dart test/features/practice/reward_idempotency_test.dart test/features/practice/speed_ladder_test.dart test/features/songs/setlist_flow_test.dart test/l10n/hardcoded_string_guard_test.dart test/l10n/arb_parity_test.dart
```

**A golden-sáv NEM ebben a parancsban van** (§0.0/R3, ADR 0426) — a merge-kapu
architektúráján mérjük, a migráció UTÁN újrafelvétellel, majd ellenőrzéssel:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r20_screens_golden_test.dart test/ui/goldens/e13_r22_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r20_screens_golden_test.dart test/ui/goldens/e13_r22_screens_golden_test.dart
```

Az újrafelvétel UTÁN `git status --short test/ui/goldens/goldens/` — kizárólag a
§0.0/R4 nyolc PNG-je változhat. Ha bármelyik `e13_r20_chord_*` PNG is változik,
az NEM a batch képernyője: állítsd vissza (`git checkout -- <png>`) és jelentsd.
A `done` jelzés ELŐTT: `rm -rf test/ui/goldens/failures` (L536).

A migrációs mérés (a kimenet a §10-be, batch-enként MIGRATED/legacy sorokkal):

```bash
for f in lib/features/practice/presentation/screens/practice_hub_screen.dart lib/features/practice/presentation/screens/practice_result_screen.dart lib/features/practice/presentation/screens/practice_history_screen.dart lib/features/practice/presentation/screens/speed_builder_screen.dart lib/features/learn/screens/learn_screen.dart lib/features/learn/screens/lesson_list_screen.dart lib/features/learn/screens/lesson_score_preview_screen.dart lib/features/learn/screens/latency_calibration_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
```

Ha a batch képernyőjének VAN golden PNG-je, az újrafelvétel KIZÁRÓLAG a merge-kapu architektúráján (ADR 0426):

```bash
tools/golden-x86.sh record <a batch érintett golden-teszt fájljai>
```

## 8. Implementációs sorrend

1. A `retirement-plan.md` beolvasása → a tényleges képernyő-lista.
2. Képernyőnként: komponens-csere → állapotok (üres/betöltés/hiba) → tokenek → `*ThemeScope` eltávolítása.
3. A batch célzott widget-tesztjei (állapotok + `textScale 2.0` + `en`/`hu`).
4. A mérés futtatása, `migration-status.md` frissítése.
5. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Néma információvesztés.** A migráció közben elveszett állapot vagy mező a leggyakoribb hiba (A2).
- **Locale-vak elrendezés.** A magyar szövegek hosszabbak; az `en`-re szabott elrendezés túlcsordul (A3).
- **Scope-csúszás a viselkedés felé.** Egy „apró" providers-módosítás a kör mérhetőségét rontja (STOP-eset).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
