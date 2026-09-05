# E17-R04 — Az AI Tutor gyakorlóterv-előnézet bekötése

- **Státusz:** PREPARED (előre megírva 2026-09-05, kód olvasva: `main @ b17e08ef`) — **`hold`: A kör az `aiTutorEnabled` kapu MÖGÉ köt be, ami `forEnvironment`-ben minden környezetben `false`**
- **Típus:** Chapter 17 (Teljes bekötés), Kör 4
- **Kör-azonosító:** `E17-R04`
- **Branch:** `<motor>/e17-r04-tutor-practice-plan-preview-wiring`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0523` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset (mérve: nyolc egymást követő körön át a queue ADR-oszlopa elavult volt).
- **Fejezet-terv:** [`docs/plans/chapter-17-full-wiring.md`](../plans/chapter-17-full-wiring.md)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "az ai tutor gyakorlóterv-előnézet bekötése"` — a kör pre-flightjának KÖTELEZŐ lefuttatnia és a találatokat a §2-be beépítenie; a brief előre megírt állapotában a §2 a `main @ b17e08ef` mérésein áll.

## 0.0 MIÉRT `hold`

A kör az `aiTutorEnabled` kapu MÖGÉ köt be, ami `forEnvironment`-ben minden környezetben `false`. **Mi oldja fel:** az `E17-R01` mintájának lezárása; a kapu alapértéke NEM ennek a körnek a tárgya.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/ai_tutor/presentation/providers/tutor_providers.dart",
  "lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart",
  "lib/features/ai_tutor/public.dart",
  "test/features/ai_tutor/practice_plan_preview_wiring_test.dart",
  "docs/rounds/e17-r04-tutor-practice-plan-preview-wiring.md",
  "test/features/ai_tutor/presentation/tutor_chat_screen_test.dart",
  "test/features/tutor/ai_mode_visibility_test.dart",
  "test/features/tutor/streaming_announcement_test.dart",
  "test/ui/goldens/e13_r29_screens_golden_test.dart",
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
  "test/app/navigation/",
]
native_gate = false
gate_tests = [
  "test/features/ai_tutor/",
  "test/features/tutor/",
  "test/features/practice/",
  "test/features/ai_tutor/presentation/tutor_chat_screen_test.dart",
  "test/features/tutor/ai_mode_visibility_test.dart",
  "test/features/tutor/streaming_announcement_test.dart",
  "test/ui/goldens/e13_r29_screens_golden_test.dart",
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
  "test/app/navigation/",
]
```

## 0. Kör-jelzés és STOP-protokoll

Scope-ütközés esetén a kimenet a brief-REVÍZIÓ, nem a scope önkényes tágítása: állítsd meg a kört (`stopped`), és írd le, melyik §-t kell módosítani.

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

## 1. Cél

A `PracticePlanPreviewScreen` a szállított kompozícióból elérhető: a Tutor által javasolt gyakorlóterv-tervezet megnyitható, szerkeszthető és indítható.

## 2. Jelenlegi állapot — mért tények (`main @ b17e08ef`)

- A `PracticePlanPreviewScreen` `reachable: false`; az AI Tutor öt társ-képernyője MÁR routolt, mind az `aiTutorEnabled` kapu alatt.
- A képernyő injektált `PracticePlanDraft`-ot és `PracticePlanValidationContext`-et vár, alapértelmezett `PracticePlanValidator`-ral.
- Az `ai_tutor` feature-ben `3` db `UnimplementedError` override-seam van (`tutor_providers.dart:387,397`, `tutor_privacy_providers.dart:319`) — a kör pre-flightjának MÉRNIE kell, hogy a terv-tervezet útja ezek KÖZÜL melyiken megy át.

## 3. Scope

**Benne van:** Az előnézet belépési pontja a Tutor-csevegésből (a terv-javaslat elfogadásakor) · a tervezet-előállító kompozíciós provider · a `onSave` / `onStart` visszahívások valós Practice-indításhoz kötése.

**NINCS benne (tilos):**

- Az `aiTutorEnabled` alapértékének megváltoztatása.
- A `PracticePlanValidator` szabályainak módosítása.
- Új tutor-képesség vagy felhő-hívás (`aiTutorCloudEnabled` marad KI).

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

**A pin-őrök jogosultsága (S10/S11, mérve: E13-R16/F9 full-gate 32867296946, E13-R17/H3 `test/app/navigation/` +33 → +30 −3):** a fenti listán szereplő, a briefen KÍVÜL élő pin-tesztek azért kerültek az `allowed_paths`-ba ÉS a `gate_tests`-be, mert a bekötés a route által renderelt képernyő TÍPUSÁT mozdíthatja el. A jogosultság PONTOSAN ennyi: a lecserélt képernyő típusának átírása a pinnelő cellában. **Cella törlése, `skip`-je vagy gyengítése TILOS** — ha egy cella a típus-átíráson túl válik pirossá, az a kör BLOKKOLÓ lelete, nem a cella hibája.


## 5. Kötött architekturális döntések (ADR 0523)

### 5.1 Az `onStart` a MEGLÉVŐ Practice-indító útvonalat hívja, nem épít másodikat

A `PracticeSetupScreen`/`PracticeSessionScreen` route-jai élnek. Egy tutor-specifikus indító út két igazságforrást adna ugyanarra a session-indításra.

### 5.2 A felhő-hívás KI marad: a tervezet-előállítás a helyi, determinisztikus úton megy

Az `aiTutorCloudEnabled` minden környezetben `false`, és ez a kör nem rollout-döntés. A bekötésnek a helyi úton kell mérhetőnek lennie.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A `PracticePlanPreviewScreen` `reachable: true` és `flagGated: true` (`aiTutorEnabled`) | `dart run tool/check_screen_reachability.dart --format json` |
| A2 | A Tutor-csevegésből elfogadott terv-javaslat megnyitja az előnézetet VALÓS tervezettel | widget-teszt valós `ProviderContainer`-rel |
| A3 | Az `onStart` a meglévő Practice-indító útvonalra megy — a diff nem visz második indítót | `git diff` + navigációs teszt |
| A4 | A tervezet-előállítás felhő-hívás NÉLKÜL fut (`aiTutorCloudEnabled=false`) | teszt, ami hálózati hívásra bukik |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** Vezess be egy tutor-specifikus Practice-indító útvonalat, futtasd a gate-et → az A3 cellának PIROSNAK kell lennie → állítsd vissza.

Minden fenti acceptance-cella MÉRT állítás: a §7 gate-parancsa futtatja őket, és a falszifikációs próba bizonyítja, hogy a cellák tényleg pirosra váltanak a hibás implementáción.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/ test/features/tutor/ test/features/practice/ test/features/ai_tutor/presentation/tutor_chat_screen_test.dart test/features/tutor/ai_mode_visibility_test.dart test/features/tutor/streaming_announcement_test.dart test/ui/goldens/e13_r29_screens_golden_test.dart test/ui/goldens/e15_r13_full_variant_matrix_test.dart test/app/navigation/
```

A gate a `format` → `analyze` → `test <minden útvonal külön>` → `architecture` lépéseket KÜLÖN processzként futtatja (a box mért OOM-csapdája miatt a `flutter analyze && flutter test` lánc tilos).

## 8. Implementációs sorrend

1. A §2 mért tényeinek ÚJRAMÉRÉSE a kör indulásakor (a brief alapja elmozdulhatott).
2. A §5 döntéseinek rögzítése az ADR-ben.
3. Az implementáció a §4 engedélyezett fájljain belül.
4. A §6 acceptance-cellák tesztjei.
5. A §6.1 valódi-sértés próba lefuttatása és a §10-be dokumentálása.
6. A §7 gate futtatása csonkítatlan kimenettel.

## 9. Kockázatok

- **A második indító út.** Divergáló session-indítás a Tutorból vs. a Practice-ből (5.1).
- **A néma felhő-hívás.** A tervezet-előállítás hálózatra csúszása megsérti az offline-first szerződést (5.2, A4).
- **A hiányzó seam.** A három `UnimplementedError` egyike a tervezet útjába eshet — a pre-flightnak MÉRNIE kell (§2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
