# E13-R14 — Accessibility foundation audit és semantics toolkit

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 6adea220`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 14
- **Kör-azonosító:** `E13-R14`
- **Branch:** `<motor>/e13-r14-accessibility-toolkit`
- **Előfeltétel:** `E13-R13` merge-elve (overlay-rendszer)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0280`](../adr/0280-accessibility-contract-and-live-region-budget.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R01
> `docs/ui/baseline/accessibility-findings.md` prioritásos leletlistáját — a §3
> „scope képernyők" halmaza abból jön, nem találgatásból. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/design_system/foundations/ss_semantics.dart",
  "lib/core/design_system/accessibility/ss_live_region.dart",
  "lib/core/design_system/accessibility/ss_tap_target.dart",
  "lib/core/design_system/public.dart",
  "test/accessibility/semantics_contract_test.dart",
  "test/accessibility/tap_target_test.dart",
  "test/accessibility/screen_reader_copy_test.dart",
  "docs/ui/accessibility.md",
  "docs/rounds/e13-r14-accessibility-toolkit.md",
]
gate_tests = [
  "test/accessibility/semantics_contract_test.dart",
  "test/accessibility/tap_target_test.dart",
  "test/accessibility/screen_reader_copy_test.dart",
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

A design system accessibility-**szerződésének** automatizálása és a
legkritikusabb leletek javítása (SDD Ch13 Kör 14).

## 2. Jelenlegi állapot — mért tények

- Az R03–R13 minden komponens-körében szerepelt semantics-szabály; ez a kör
  **gépi szerződéssé** teszi őket egy helyen.
- Az R01 prioritásos leletlistája megnevezi a legsúlyosabb baseline-hibákat.
- A Live felismerés **másodpercenként sokszor** frissül — a naiv élő régió
  ettől folyamatosan beszélne.

## 3. Scope

**Benne van:** semantics helper és audit utility (heading, élő régió, mérőszám,
akkord, strum, beat, tuner, diagram-összegzés) · minimális érintési cél
ellenőrzése a kritikus komponensekre · **élő régió költségvetés** (mikor és
milyen sűrűn beszélhet a felület) · képernyőolvasó-szöveg fixture angolul és
magyarul · a kézi TalkBack/VoiceOver ellenőrzőlista dokumentálása.

**NINCS benne (tilos):** `lib/features/**` képernyők átírása (a migrációs
körök dolga; a leletek javítása ott történik) · a DSP vagy a felismerési
frekvencia módosítása (AGENTS.md §9) · `lib/core/theme/**` · `docs/adr/**`,
`tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `foundations/ss_semantics.dart` | a szerződés kibővítése |
| `accessibility/ss_live_region.dart` | **ÚJ** — élő régió + költségvetés |
| `accessibility/ss_tap_target.dart` | **ÚJ** — érintési cél ellenőrzés |
| `public.dart` | az export bővítése |
| `test/accessibility/*_test.dart` (3) | a §6 cellái |
| `docs/ui/accessibility.md` | **ÚJ** — szerződés + kézi ellenőrzőlista |
| `docs/rounds/e13-r14-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` · `lib/core/theme/**` · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0280)

### 5.1 Az élő régió NEM spammelheti a képernyőolvasót

A felismerés gyors frissülése nem fordítható át folyamatos beszédre. Az élő
régiónak **költségvetése** van: csak érdemi változásnál szólal meg, és van
minimális szünet két bejelentés között.

**NEM elfogadható gyengítés:** minden felismerési kereten kimondott akkordnév.
Az felolvasóval használhatatlanná teszi a Stage Mode-ot.

### 5.2 Az automatizált teszt NEM helyettesíti a valós próbát

A `docs/ui/accessibility.md` kimondja, hogy a TalkBack/VoiceOver ellenőrzőlista
kézi lépés marad. A gépi cella szükséges, de nem elégséges.

### 5.3 A tuner cents-eltérése és a strum-irány FELOLVASHATÓ

Nem elég vizuálisan jelezni. A hangoló és a strum-visszajelzés szöveges
formában is elérhető.

### 5.4 Nincs csak színnel közölt siker / hiba / confidence

Az R03 §5.3 és az R12 §5.2 gépi kikényszerítése egy helyen.

### 5.5 A kritikus akciók címkézettek

Minden interaktív elem semantics labelje kötelező a szerződésben.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az élő régió betartja a bejelentés-költségvetést | `semantics_contract_test.dart` |
| A2 | A tuner cents és a strum-irány felolvasható szövegként | `screen_reader_copy_test.dart` |
| A3 | Nincs csak színnel közölt siker/hiba/confidence | `semantics_contract_test.dart` |
| A4 | Minden kritikus akció címkézett | ugyanott |
| A5 | A kritikus komponensek érintési célja ≥ 48 dp | `tap_target_test.dart` |
| A6 | A képernyőolvasó-szöveg angolul ÉS magyarul is létezik | `screen_reader_copy_test.dart` |
| A7 | A kézi TalkBack/VoiceOver ellenőrzőlista dokumentált | `docs/ui/accessibility.md` |
| A8 | Csökkentett mozgás mellett a visszajelzés megmarad | `semantics_contract_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Minden kereten bejelentett akkordnév | **A1** |
| A tuner eltérése csak vizuális | **A2** |
| A confidence csak színes pötty | A3 |
| Címke nélküli ikonos akció | A4 |
| 44 dp-s érintési cél | A5 |
| Csak angol felolvasó-szöveg | A6 |
| A dokumentum a gépi tesztet elégségesnek mondja | A7 |

**Az élő régió három kötelező cellája** (a küszöb: két bejelentés közti
minimális szünet, **1000 ms**):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 400 ms-onként érkező változás | **egy** bejelentés, a többi összevonva |
| rajta (a küszöbön) | pontosan **1000 ms** eltéréssel érkező változás | **bejelentve** (a határ inkluzív) |
| a küszöb fölött | 2500 ms-onként érkező változás | minden változás bejelentve |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a
költségvetés-ellenőrzést az élő régióból → az **A1** cellának PIROSNAK kell
lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/accessibility/semantics_contract_test.dart test/accessibility/tap_target_test.dart test/accessibility/screen_reader_copy_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_semantics.dart` — a szerződés (heading, mérőszám, akkord, strum, beat,
   tuner, diagram).
2. `ss_live_region.dart` — költségvetés + a három cella.
3. `ss_tap_target.dart` + a 48 dp cella.
4. Felolvasó-szöveg fixture en + hu.
5. `docs/ui/accessibility.md` — szerződés és **kézi** ellenőrzőlista.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A beszédes élő régió.** A „minden változást jelentsünk be" szabály
  jóindulatú, és pont a fő használati módot teszi felolvasóval elviselhetetlenné
  (A1).
- **A gépi zöld mint bizonyíték.** A semantics teszt nem hallja, amit a
  TalkBack mond — a dokumentumnak ezt ki kell mondania (A7).
- **A scope-tágulás.** A leletlista javításra hív a feature-ökben; az a
  migrációs körök dolga.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
