# E14-R13 — Live UI truthfulness hotfix

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ 88e08e65`)
- **Típus:** Chapter 14, Kör 13 (truthfulness hotfix blokk)
- **Kör-azonosító:** `E14-R13`
- **Branch:** `<motor>/e14-r13-live-ui-truthfulness-hotfix`
- **Előfeltétel:** `E14-R11` (külön confidence, uncertainty-állapotok) és
  `E14-R12` (stabilizátor) merge-elve. **Enélkül a képernyőnek nincs mit
  igazul megmutatnia** — a kör nem indítható.
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0365` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a
> `lib/features/live/screens/live_screen.dart`-ot és a `widgets/` tíz fájlját —
> a Chapter 13 sáv (`E13-R08/R09/R18`) közben átrendezheti a scaffoldot. Ha az
> `E13-R18` (Live stage UI) MÁR merge-elt, ez a kör az ő szerkezetére épül, és
> a §4 listát a pre-flight igazítja. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/live/screens/live_screen.dart",
  "lib/features/live/widgets/live_status_bar.dart",
  "lib/features/live/widgets/chord_timeline.dart",
  "lib/features/live/widgets/uncertainty_reason_banner.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/live/live_screen_truthfulness_test.dart",
  "test/features/live/uncertainty_reason_banner_test.dart",
  "docs/rounds/e14-r13-live-ui-truthfulness-hotfix.md",
]
gate_tests = [
  "test/features/live/live_screen_truthfulness_test.dart",
  "test/features/live/uncertainty_reason_banner_test.dart",
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

A Live képernyő **egy dolgot mondjon, azt viszont igazul**: egyetlen stabil
akkord-kártya, egyetlen legutóbbi pengetés-esemény, felül a jel- és
modellállapot, alul a `Indítás/Szünet/Befejezés` CTA. A history lenyitható
panelbe kerül, a folyamatos hero-animáció és a shimmer alapértelmezetten ki.
Bizonytalanságnál a képernyő **megmondja az okot** (túl halk, zajos,
bizonytalan irány, ismeretlen akkord).

### 1.1 Visszakeresett előzmény (ADR 0312)

- **Chapter 14 §4.1–4.2:** a mai Live UI technikai feature-listát mutat, és a
  filmstrip felerősíti a felismerési hibát.
- **E13 sáv:** a design-rendszer és a képernyők a Chapter 13-ban épülnek — ez a
  kör NEM redesign, hanem a truthfulness-hotfix a meglévő szerkezeten.

## 2. Jelenlegi állapot — mért tények

- `lib/features/live/screens/live_screen.dart` — egyetlen képernyő, tíz widget
  (`beat_counter`, `input_level_meter`, `chord_timeline`, `live_status_bar`,
  `confidence_pill`, `live_lab_panel`, `chord_timeline_card`, `chord_display`,
  `strum_arrow`) egyidejű tartalommal.
- `chord_timeline.dart` + `chord_timeline_card.dart` — a history ma fő tartalom.
- `uncertainty_reason_banner.dart` — **nem létezik**; ez a kör hozza létre.

## 3. Scope

**Benne:** tartalmi hierarchia (egy fő üzenet), history lenyitható panelbe,
állapotsáv felül, CTA alul, ok-szöveg bizonytalanságnál, akadálymentesség
(200% textscale, semantics), widget- és golden-tesztek.

**Nincs benne:** design-token csere (Chapter 13), új navigáció, DSP, modell,
a stabilizátor vagy a confidence-logika módosítása (R11/R12 zárta).

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/live/screens/live_screen.dart` | a hierarchia |
| `lib/features/live/widgets/live_status_bar.dart` | jel- és modellállapot felül |
| `lib/features/live/widgets/chord_timeline.dart` | lenyitható panel |
| `lib/features/live/widgets/uncertainty_reason_banner.dart` | az ok-szöveg (új) |
| `lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb` | a négy ok-szöveg |
| `test/features/live/live_screen_truthfulness_test.dart` | egy-fő-üzenet, textscale |
| `test/features/live/uncertainty_reason_banner_test.dart` | ok-mátrix |
| `docs/rounds/e14-r13-live-ui-truthfulness-hotfix.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten a **generált** l10n
(`lib/l10n/app_localizations*.dart`), `lib/features/live/engine/**`,
`lib/features/live/providers/**`, `lib/core/theme/**`, `assets/**`, `ml/**`,
`docs/adr/**`, `.github/workflows/**`, `tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0365)

### 5.1 Egy fő üzenet

A képernyőn egyszerre egyetlen elsődleges állítás lehet. **NEM elfogadható**:
„a kártya és a filmstrip is fő tartalom, csak kisebb betűvel".

### 5.2 A history másodlagos

Alapértelmezetten összecsukott panel; a nyitás felhasználói döntés, és nem
változtatja meg a fő kártya tartalmát.

### 5.3 Nyugalom alapértelmezetten

Folyamatos hero-animáció és shimmer alapértelmezetten KI. A `reduce motion`
rendszerbeállítást tiszteletben kell tartani.

### 5.4 A bizonytalanság okot kap

`uncertain`/`rejected`/`lowSignal` esetén a banner konkrét okot ír ki a négy
kategóriából. **NEM elfogadható**: általános „nem sikerült" szöveg.

### 5.5 A képernyő nem hoz felismerési döntést

A UI csak megjelenít; küszöb, stabilizálás, abstention a R10–R12 rétegé.

## 6. Acceptance criteria

1. A widget-teszt szerint egyszerre **pontosan egy** elsődleges szemantikai
   üzenet van a fában (a semantics-fa mérve, nem a pixel).
2. A textscale-küszöb hármas cellája (a támogatott felső határ **200%**,
   **inkluzív**): a küszöb **alatt** (150%) nincs overflow, pontosan **rajta**
   (200%) nincs overflow (a határ ide tartozik), a küszöb **fölött** (250%) a
   kör NEM vállal garanciát — ott a teszt csak azt méri, hogy a képernyő nem
   dob kivételt. A cella a `RenderFlex overflow` hibára esik el.
3. A history panel alapértelmezetten összecsukott; kinyitás után a fő kártya
   szövege változatlan.
4. A négy ok-szöveg mindkét nyelven létezik, és a banner a döntési okhoz a
   HOZZÁ tartozót mutatja (négyelemű mátrix).
5. `reduce motion` esetén nincs futó animáció (a teszt a `Ticker`-ek számát
   méri).
6. A CTA három állapota (`Indítás` / `Szünet` / `Befejezés`) a session
   állapotából következik, és nem jelenik meg kettő egyszerre.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A filmstrip fő tartalom marad | 1. pont semantics-cellája |
| Fix magasságú kártya | 2. pont textscale-cellája |
| A panel nyitása átírja a fő kártyát | 3. pont |
| Egyetlen általános hibaszöveg | 4. pont ok-mátrixa |
| A shimmer `reduce motion` alatt is fut | 5. pont Ticker-cellája |
| A CTA két gombot mutat egyszerre | 6. pont |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live
```

Külön processzben futó `format` → `analyze` → célzott tesztek → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). Az ARB után a generált l10n a
gate dolga — kézzel szerkeszteni TILOS (E08-R12/H6). CI-dispatch/PR/merge
Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: a history panel `initiallyExpanded: true`-ra állításával
a 3. pont **PIROS**, visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. Semantics-teszt a MAI állapotra (ez a kiindulási mérés, PIROS).
2. Hierarchia átrendezése, history panelbe.
3. Ok-banner + ARB-kulcsok, majd a gate generálja az l10n-t.
4. Textscale és reduce-motion cellák.

## 9. Kockázatok

- **Ütközés a Chapter 13 sávval:** ha az `E13-R18` közben landol, a §4 lista
  elavulhat — a pre-flight KÖTELEZŐ, ütközésnél `stopped`.
- **Golden-instabilitás:** ha a golden-teszt platformfüggő, inkább semantics-
  és widget-tesztet írj; a golden nem lehet a kör egyetlen bizonyítéka.
- **Generált l10n scope-csapda:** csak az ARB írható.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
