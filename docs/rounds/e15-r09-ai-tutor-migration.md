# E15-R09 — AI Tutor képernyők migrálása

- **Státusz:** PREPARED (előre megírva 2026-08-28, kód olvasva: `main @ 4cb32eb0`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 9
- **Kör-azonosító:** `E15-R09`
- **Branch:** `<motor>/e15-r09-ai-tutor-migration`
- **Előfeltétel:** `E15-R03` merge-elve (a visszavonási terv dönti el, mit KELL migrálni)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — migrációs kör, kötött ÚJ architekturális döntés nélkül (a hivatkozott szerződéseket korábbi ADR-ek rögzítik).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "ai tutor chat home privacy profile UI"` → **[ADR 0132](../adr/0132-ai-tutor-privacy-and-consent.md)** (Tutor privacy & consent) és **[ADR 0213](../adr/0213-ai-tutor-production-wiring-and-sse-transport.md)** (production-drótozás, SSE transport) — a migráció sem a consent-kapukat, sem a stream-kezelést nem írhatja át.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd be a `docs/ui/retirement-plan.md` (E15-R03) sorait erre a batch-re, és mérd újra, mely képernyők legacyk MÉG:
> ```bash
> for f in lib/features/ai_tutor/presentation/screens/tutor_home_screen.dart lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart lib/features/ai_tutor/presentation/screens/tutor_profile_screen.dart lib/features/ai_tutor/presentation/screens/tutor_data_screen.dart lib/features/ai_tutor/presentation/screens/tutor_privacy_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
> ```
> A megíráskor mind a **5** felsorolt képernyő legacy volt. Ami időközben migrálódott, azt a §3 scope-ból ki kell venni.

## 0.0 A kör határa: MEGJELENÉS, nem viselkedés

A migráció a képernyők VIZUÁLIS rétegét cseréli design-rendszer-komponensekre. A képernyő TÍPUSA, route-ja, publikus API-ja és üzleti viselkedése VÁLTOZATLAN — a típus-pinnelő tesztek (§4) ezért maradnak zöldek, és a jogosultság pontosan ennyi: **cella törlése, `skip`-je vagy gyengítése TILOS**. Az `E15-R01` óta az app témája hordozza a tokeneket, tehát ÚJ `*ThemeScope` burkoló NEM vezethető be; a meglévő burkoló eltávolítható, ha a képernyő már az app témájából old fel.

Az `E15-R02` óta a Coach destination látszik a shellben, tehát a Tutor öt képernyője a fő navigációból elérhető — legacy megjelenéssel és a hálózati hibaállapotok mai, nyers formájában.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/presentation/screens/tutor_home_screen.dart",
  "lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart",
  "lib/features/ai_tutor/presentation/screens/tutor_profile_screen.dart",
  "lib/features/ai_tutor/presentation/screens/tutor_data_screen.dart",
  "lib/features/ai_tutor/presentation/screens/tutor_privacy_screen.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/features/ai_tutor/presentation/tutor_chat_screen_test.dart",
  "test/features/ai_tutor/presentation/tutor_data_screen_test.dart",
  "test/features/ai_tutor/presentation/tutor_privacy_screen_test.dart",
  "test/features/ai_tutor/presentation/tutor_profile_screen_test.dart",
  "test/features/tutor/ai_mode_visibility_test.dart",
  "test/features/tutor/streaming_announcement_test.dart",
  "test/ui/goldens/e13_r29_screens_golden_test.dart",
  "docs/ui/migration-status.md",
  "docs/rounds/e15-r09-ai-tutor-migration.md",
]
gate_tests = [
  "test/ui/ui_inventory_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/features/ai_tutor/presentation/tutor_chat_screen_test.dart",
  "test/features/ai_tutor/presentation/tutor_data_screen_test.dart",
  "test/features/ai_tutor/presentation/tutor_privacy_screen_test.dart",
  "test/features/ai_tutor/presentation/tutor_profile_screen_test.dart",
  "test/features/tutor/ai_mode_visibility_test.dart",
  "test/features/tutor/streaming_announcement_test.dart",
  "test/ui/goldens/e13_r29_screens_golden_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a diff felhasználói felületet ír át azon az úton, amit a felhasználó a leggyakrabban jár; egy elveszett állapot- vagy hibajelzés némán rontaná az élményt. A `flutter-reviewer` és a `flutter-devil-advocate` futtatása a review-ban KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a migrációhoz egy `application/`, `domain/` vagy `data/` réteg módosítása kellene, a kimenet a `stopped` jelzés — a viselkedés-változás nem ennek a körnek a hatásköre ([L478](../LESSONS.md#l478)).

## 1. Cél

A batch 5 képernyője a design-rendszer komponenseit és tokenjeit használja, változatlan viselkedés mellett — hogy a felület egységes legyen, és a 200%-os szövegskála, a képernyőolvasó és a két locale mindenhol működjön.

## 2. Jelenlegi állapot — mért tények

- A batch képernyői (MÉRVE `grep -L design_system`): `tutor_home_screen.dart`, `tutor_chat_screen.dart`, `tutor_profile_screen.dart`, `tutor_data_screen.dart`, `tutor_privacy_screen.dart`.
- Egyik sem importálja a `core/design_system`-et; a stílusuk közvetlen `Theme.of(context)` / `AppColors` / `AppPalette` hivatkozásokból jön.
- Az `E15-R01` óta az app futásidejű témája a design-rendszer témája, tehát a komponensek burkoló NÉLKÜL is feloldják a tokeneket.
- Az `E15-R02` óta az adaptív shell az alapértelmezett belépő, tehát ezek a képernyők a fő navigációból elérhetők.
- A `test/ui/ui_inventory_test.dart` EGZAKT képernyőszámot állít — a kör nem hoz létre és nem töröl képernyőt, tehát a szám VÁLTOZATLAN.

## 3. Scope

**Benne van:** a felsorolt 5 képernyő vizuális migrálása (`SsCard`, `SsButton`, `SsListTile`, `SsEmptyState`, `SsErrorState`, `SsMetricTile` és társaik; `SsSpacing`/`SsTypography` tokenek) · a meglévő `*ThemeScope` burkoló eltávolítása, ahol az `E15-R01` óta felesleges · a `migration-status.md` frissítése a MÉRT új aránnyal.

Batch-specifikus kikötések:

- a chat-képernyő stream-kezelése (SSE, részleges válasz, megszakítás) VISELKEDÉSBEN változatlan; a buborékok és az állapotjelzők kerülnek komponensekre
- a hibaállapot (nincs backend) `SsErrorState` komponenst kap — ez a MÉRT állapot ma nyers szöveg
- a privacy- és adat-képernyő consent-kapcsolói és szövegei érintetlenek (ADR 0132)

**NINCS benne (tilos):**

- `application/`, `domain/`, `data/`, `providers/` réteg módosítása (viselkedés-változás).
- Új képernyő létrehozása vagy meglévő törlése.
- Új `*ThemeScope` burkoló bevezetése.
- ARB-kulcs törlése vagy szöveg-jelentés megváltoztatása (új kulcs FELVEHETŐ, ha a komponens ezt igényli — mindkét locale-ra, egyszerre).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/ai_tutor/presentation/screens/tutor_home_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/ai_tutor/presentation/screens/tutor_profile_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/ai_tutor/presentation/screens/tutor_data_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/ai_tutor/presentation/screens/tutor_privacy_screen.dart` | migráció design-rendszer komponensekre |
| `test/app/navigation/adaptive_scaffold_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/app/offline_network_guard_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/ai_tutor/presentation/tutor_chat_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/ai_tutor/presentation/tutor_data_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/ai_tutor/presentation/tutor_privacy_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/ai_tutor/presentation/tutor_profile_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/tutor/ai_mode_visibility_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/tutor/streaming_announcement_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r29_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `docs/ui/migration-status.md` | a MÉRT arány frissítése |

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
| A1 | Mind a 5 képernyő importálja a `core/design_system`-et, és a mérés szerint migráltnak számít | a §7 mérő-parancs kimenete a §10-ben |
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
tools/round-gate.sh test/ui/ui_inventory_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/offline_network_guard_test.dart test/features/ai_tutor/presentation/tutor_chat_screen_test.dart test/features/ai_tutor/presentation/tutor_data_screen_test.dart test/features/ai_tutor/presentation/tutor_privacy_screen_test.dart test/features/ai_tutor/presentation/tutor_profile_screen_test.dart test/features/tutor/ai_mode_visibility_test.dart test/features/tutor/streaming_announcement_test.dart test/ui/goldens/e13_r29_screens_golden_test.dart
```

A migrációs mérés (a kimenet a §10-be, batch-enként MIGRATED/legacy sorokkal):

```bash
for f in lib/features/ai_tutor/presentation/screens/tutor_home_screen.dart lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart lib/features/ai_tutor/presentation/screens/tutor_profile_screen.dart lib/features/ai_tutor/presentation/screens/tutor_data_screen.dart lib/features/ai_tutor/presentation/screens/tutor_privacy_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
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
