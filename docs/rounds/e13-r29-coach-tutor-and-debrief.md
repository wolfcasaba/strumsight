# E13-R29 — Coach Home, Tutor és Debrief UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ c732ec75`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 29
- **Kör-azonosító:** `E13-R29`
- **Branch:** `<motor>/e13-r29-coach-tutor-and-debrief`
- **Előfeltétel:** `E13-R28` merge-elve (egységes könyvtár)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0287`](../adr/0287-no-automatic-tool-execution-in-the-tutor.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES tanár-réteg
> tool-interfészét és a streaming API-t — a §5.1 kimondja, hogy egyetlen
> tool-akció sem futhat megerősítés nélkül, és ezt a mért interfészen kell
> kikényszeríteni. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/coach/",
  "lib/features/tutor/",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/tutor/ai_mode_visibility_test.dart",
  "test/features/tutor/streaming_announcement_test.dart",
  "test/features/tutor/tool_confirmation_test.dart",
  "test/features/tutor/prompt_injection_ui_test.dart",
  "docs/rounds/e13-r29-coach-tutor-and-debrief.md",
]
gate_tests = [
  "test/features/tutor/ai_mode_visibility_test.dart",
  "test/features/tutor/streaming_announcement_test.dart",
  "test/features/tutor/tool_confirmation_test.dart",
  "test/features/tutor/prompt_injection_ui_test.dart",
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

Az UI-42–UI-44 **provenance-tudatos** AI-coaching felülete: streaming,
bizonyíték és tool-megerősítés (SDD Ch13 Kör 29).

## 2. Jelenlegi állapot — mért tények

- Az R12 ADR 0278 kimondta: az AI-eredet látható. Az R13 ADR 0279 kimondta: a
  tool-megerősítés megmutatja az érintett adatot és a módot.
- Az R14 ADR 0280 élő régió költségvetése itt a streaming üzenetre vonatkozik.
- A tanár-réteg **eszközöket** hívhat, amelyek adatot módosítanak vagy
  publikálnak.

## 3. Scope

**Benne van:** a Coach kezdőképernyő helyi / felhő / tartalék és hiányzó modell
állapotai · a beszélgetés streaming üzenete, szerkesztője, beszélgetés-listája és
**bizonyíték-panelje** · a debrief / terv-előnézet megfigyelés–ok–akció és
terv-diff szerkezete · **minden tool-akció** az `SsToolConfirmationSheet`-en át ·
streaming megszakítás, hálózatvesztés, helyi tartalék és tool-eredmény
állapotok · prompt/tool-injekció **felületi fixture**, ami igazolja, hogy nincs
automatikus végrehajtás.

**NINCS benne (tilos):** a tanár-réteg vagy a tool-végrehajtó logikájának
módosítása · a beszélgetés-tartalom analitikába küldése · más képernyők ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/coach/` | a Coach kezdőképernyő és debrief |
| `lib/features/tutor/` | a beszélgetés-felület |
| `lib/l10n/app_{en,hu}.arb` | a coaching-szövegek |
| `test/features/tutor/*_test.dart` (4) | a §6 cellái |
| `docs/rounds/e13-r29-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a két érintett KIVÉTELÉVEL ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0287)

### 5.1 EGYETLEN tool-akció sem fut automatikusan

Publikáló, destruktív és rögzítést indító akció **soha** nem indul a modell
javaslatára közvetlenül — mindig az `SsToolConfirmationSheet` megerősítése után.
A modell bemenete részben nem megbízható (importált dal, közösségi tartalom),
ezért a felület az utolsó védvonal.

**NEM elfogadható gyengítés:** „az olvasó jellegű eszközök futhatnak
megerősítés nélkül" — kivéve, ha a lista **explicit**, zárt és a tervben
rögzített. Nyitott kategória-alapú mentesítés tilos.

### 5.2 Az AI-mód MINDIG látható

Helyi, felhő vagy tartalék — az ADR 0278 §1 kikényszerítése a beszélgetésben,
üzenet szinten is.

### 5.3 A streaming NEM spammelheti a képernyőolvasót

Az ADR 0280 §2 költségvetése: a részleges tokenek nem hangzanak el
folyamatosan; a bejelentés összevont.

### 5.4 A terv-módosítás EXPLICIT, diff-fel

A gyakorlási terv változása előbb **különbségként** látszik, és a felhasználó
fogadja el vagy utasítja el.

### 5.5 A beszélgetés tartalma NEM kerül analitikába

Sem esemény-paraméterként, sem hibajelentésben. Ez adatvédelmi határ.

### 5.6 A hiányzó bizonyíték KIMONDOTT

Ha egy állítás mögött nincs mérési bizonyíték, a felület ezt jelzi — nem
tünteti fel megalapozottként (az ADR 0283 elve a coachingra).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az AI-mód (helyi/felhő/tartalék) mindig látható | `ai_mode_visibility_test.dart` |
| A2 | Egyetlen tool-akció sem fut megerősítés nélkül | `tool_confirmation_test.dart` |
| A3 | A tool-megerősítés visszahívása pontosan egyszer fut | ugyanott |
| A4 | Nem megbízható tartalomból érkező tool-javaslat sem fut automatikusan | `prompt_injection_ui_test.dart` |
| A5 | A streaming bejelentés összevont, nem token-szintű | `streaming_announcement_test.dart` |
| A6 | A terv-módosítás diff-fel, elfogadás/elutasítás mellett jelenik meg | `tool_confirmation_test.dart` |
| A7 | A beszélgetés tartalma nem kerül analitikába | `grep` a diffben |
| A8 | A hiányzó bizonyíték kimondott, nem elhallgatott | `ai_mode_visibility_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| „Olvasó" tool megerősítés nélkül fut | **A2** |
| Az importált dalban elrejtett utasítás akciót indít | **A4** |
| A megerősítés visszahívása kétszer fut | **A3** |
| Token-szintű felolvasás streaming közben | **A5** |
| A terv némán módosul | **A6** |
| Az üzenet szövege esemény-paraméterként naplózva | **A7** |

**A tool-akció három kötelező cellája** (a küszöb: a megerősítés megtörtént-e):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | a felhasználó megszakítja a megerősítést | **0** végrehajtás |
| rajta (a küszöbön) | egyszeri megerősítés | **pontosan 1** végrehajtás |
| a küszöb fölött | a modell ismételten kéri ugyanazt | **újabb megerősítés** kell — nincs „emlékezz rá" |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedd, hogy egy
olvasó jellegű tool megerősítés nélkül fusson → az **A2** cellának PIROSNAK
kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/tutor/ai_mode_visibility_test.dart test/features/tutor/streaming_announcement_test.dart test/features/tutor/tool_confirmation_test.dart test/features/tutor/prompt_injection_ui_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

> **Review-megjegyzés:** ez a kör `risk = "high"` és AI-tool-végrehajtást érint,
> ezért a review-ban a `security-reviewer` ügynök futtatása kötelező.

## 8. Implementációs sorrend

1. A Coach kezdőképernyő állapotai + az AI-mód látható jelölése.
2. A beszélgetés-felület streaming üzenettel és összevont bejelentéssel.
3. Minden tool-akció az `SsToolConfirmationSheet` mögé + a három cella.
4. A prompt/tool-injekció fixture — automatikus végrehajtás NÉLKÜL.
5. A bizonyíték-panel és a hiányzó bizonyíték kimondása.
6. A debrief megfigyelés–ok–akció szerkezete és a terv-diff.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az „ártalmatlan" olvasó tool.** A kategória-alapú mentesítés csúszós lejtő:
  az injekció pont ezen az úton jut be (A2/A4).
- **A token-szintű felolvasás.** Jóindulatú „azonnali visszajelzés", ami
  felolvasóval elviselhetetlen (A5).
- **A beszélgetés naplózása.** Hibakeresés közben kézenfekvő, és a
  legérzékenyebb szöveges adatot viszi ki (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
