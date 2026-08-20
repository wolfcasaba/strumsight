# E14-R11 — Chord uncertainty, no-chord és külön confidence a UI-ban

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ 88e08e65`)
- **Típus:** Chapter 14, Kör 11 (truthfulness hotfix blokk)
- **Kör-azonosító:** `E14-R11`
- **Branch:** `<motor>/e14-r11-chord-uncertainty-and-separate-confidence`
- **Előfeltétel:** `E14-R04` merge-elve (RecognitionFrame V2). Az `E14-R10`-től
  független, de ha az előbb landol, a §2-t a pre-flight frissíti.
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0363` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a
> `lib/features/live/engine/dsp/live_pipeline.dart` `chordConfidence` getterét
> (a 251–261. sorok környéke) és a `lib/features/live/widgets/confidence_pill.dart`-t.
> A §2 ezekre mutat. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/live/model/live_frame.dart",
  "lib/features/live/engine/dsp/live_pipeline.dart",
  "lib/features/live/widgets/confidence_pill.dart",
  "lib/features/live/widgets/chord_display.dart",
  "lib/features/live/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/live/chord_uncertainty_test.dart",
  "test/features/live/confidence_pill_test.dart",
  "docs/rounds/e14-r11-chord-uncertainty-and-separate-confidence.md",
]
gate_tests = [
  "test/features/live/chord_uncertainty_test.dart",
  "test/features/live/confidence_pill_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A chord- és a strum-confidence **soha ne keveredjen**, és bizonytalan/ismeretlen
akkordnál a UI ne mutasson akkordnevet. A százalék helyett szöveges állapot
(„Biztos / Ellenőrzés / Nem biztos") jelenjen meg — kalibrálatlan valószínűséget
tilos százalékként mutatni (Chapter 14 §9/6).

### 1.1 Visszakeresett előzmény (ADR 0312)

- **Chapter 14 §4.3 (mért audit):** a `LiveFrame` egyetlen confidence-t visz, és
  az a strumé — a UI-ban mégis akkord-bizonyosságnak látszik. Ez a kör zárja.
- **E14-R01 release guard:** kalibrálatlan szám nem mutatható bizonyosságként.

## 2. Jelenlegi állapot — mért tények

- `lib/features/live/engine/dsp/live_pipeline.dart:253` — `double get
  chordConfidence => _lastChord?.confidence ?? 0;` — a getter LÉTEZIK, de a
  frame nem viszi tovább.
- `lib/features/live/model/live_frame.dart` — `confidence` = a STRUM confidence-e.
- `lib/features/live/widgets/confidence_pill.dart` — a pill ma ezt az egyetlen
  értéket mutatja.
- A `noChord` / `unknownChord` / `lowSignal` megkülönböztetés **nincs** a
  frame-ben.

## 3. Scope

**Benne:** külön chord- és strum-confidence (raw, EMA, kalibrált) a frame-ben,
`noChord`/`unknownChord`/`lowSignal` állapotok, a pill szöveges állapotra
váltása, a chord-név elrejtése bizonytalan döntésnél, l10n kulcsok.

**Nincs benne:** DSP-küszöb hangolása, layout-redesign (R13), stabilizátor
(R12), a generált l10n fájlok kézi szerkesztése.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/live/model/live_frame.dart` | külön confidence-mezők + állapotok |
| `lib/features/live/engine/dsp/live_pipeline.dart` | a meglévő getter továbbadása |
| `lib/features/live/widgets/confidence_pill.dart` | szöveges állapot |
| `lib/features/live/widgets/chord_display.dart` | bizonytalanságnál nincs név |
| `lib/features/live/public.dart` | additív export |
| `lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb` | a három állapot szövege |
| `test/features/live/chord_uncertainty_test.dart` | állapot-mátrix |
| `test/features/live/confidence_pill_test.dart` | a pill szemantikája |
| `docs/rounds/e14-r11-chord-uncertainty-and-separate-confidence.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten a **generált** l10n kimenet
(`lib/l10n/app_localizations*.dart`), `lib/features/live/screens/**`,
`lib/features/live/engine/ml/**`, `assets/**`, `ml/**`, `docs/adr/**`,
`docs/rag/chunks/**`, `.github/workflows/**`, `tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0363)

### 5.1 Két külön mező, nem egy „confidence"

A frame-ben `chordConfidence` és `strumConfidence` külön mező. **NEM
elfogadható**: egy mező + „a hívó tudja, melyikről van szó" komment.

### 5.2 Kalibrálatlan érték nem százalék

A UI alapértelmezetten szöveges állapotot mutat. A nyers százalék csak
diagnosztikai (Lab) felületen jelenhet meg, ott is „kalibrálatlan" jelöléssel.

### 5.3 Bizonytalan döntésnél nincs akkordnév

`uncertain` vagy `rejected` esetén a `chord_display` nem ír ki labelt; a
helyére a semleges állapot kerül. **NEM elfogadható**: halványított akkordnév.

### 5.4 A három ok-állapot megkülönböztetett

`noChord` (nincs akkord), `unknownChord` (van, de nem ismerjük fel) és
`lowSignal` (a jel nem elég) külön állapot, külön szöveggel.

### 5.5 Additív szerződés

A meglévő `LiveFrame`-hívók a régi mezőkkel tovább fordulnak (deprecation
komment igen, törlés nem).

## 6. Acceptance criteria

1. Beszéd/zaj fixture-ön a frame `lowSignal`-t ad, és a display nem mutat
   akkordnevet.
2. A chord- és strum-confidence külön mérhető: a teszt eltérő értékeket ad a
   kettőnek, és mindkettő a saját forrásából származik.
3. A pill szemantikája a három szöveges állapotot adja (a teszt a semantics
   labelt olvassa, nem a pixelt).
4. `noChord` / `unknownChord` / `lowSignal` külön szöveget kap mindkét
   nyelven; hiányzó kulcs → a teszt piros.
5. A régi `LiveFrame` hívók fordulnak (kompatibilitási cella).
6. A `lowSignal` állapotot kiváltó jel-küszöb hármas cellája (a határ
   **inkluzív**, az érték az `E14-R05` `SignalQualitySnapshot`-jából jön):
   a küszöb **alatt** → `lowSignal` (nincs akkordnév), pontosan **rajta** →
   `lowSignal` (a határ ide tartozik), a küszöb **fölött** → a normál
   chord-döntés fut.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A frame a strum-confidence-t adja vissza chordként | 2. pont |
| `uncertain` mellett halványítva kiírja a labelt | 1. és 3. pont |
| A három ok-állapot egyetlen „unknown"-ba olvad | 4. pont |
| A pill százalékot mutat | 3. pont semantics-cellája |
| A régi mező törlése | 5. pont fordítási cellája |
| A jel-küszöb exkluzív határral | 6. pont „pontosan rajta" cellája |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live
```

Külön processzben futó `format` → `analyze` → célzott tesztek → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). Az ARB-módosítás után a
generált l10n frissítése a gate dolga — kézzel szerkeszteni TILOS (mért eset:
E08-R12/H6). CI-dispatch/PR/merge Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: a `chordConfidence` ideiglenes visszacserélésével a
strum-értékre a 2. pont **PIROS**, visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. Frame-mezők + állapotok, teszttel.
2. Pipeline-bekötés (a meglévő getter).
3. ARB-kulcsok, majd a gate generálja az l10n-t.
4. Pill és display.

## 9. Kockázatok

- **Generált l10n scope-csapda:** a kör csak az ARB-t írja (E08-R12/H6 lecke).
- **Hívó-drift:** 19 `LiveFrame`-hívó van a fában; a kompatibilitási cella
  védje őket.
- **Túl korai UI-átszabás:** a layout az R13 dolga; itt csak a tartalom változik.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
