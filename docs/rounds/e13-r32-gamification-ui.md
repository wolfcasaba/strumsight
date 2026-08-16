# E13-R32 — Gamification Hub, Quest, Achievement és Reward UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 0f7afd9a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 32
- **Kör-azonosító:** `E13-R32`
- **Branch:** `<motor>/e13-r32-gamification-ui`
- **Előfeltétel:** `E13-R31` merge-elve (fejlődési felületek)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0290`](../adr/0290-compassionate-streaks-and-idempotent-claims.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES
> gamifikációs főkönyv (ledger) use case-ét — a §5.2 kimondja, hogy a felület
> nem számít jutalmat. Ha az idempotens beváltás use case hiányzik, `blocked`
> jelzéssel állj meg. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/gamification/ui/claim_idempotency_test.dart",
  "test/features/gamification/ui/streak_states_test.dart",
  "test/features/gamification/ui/compassionate_copy_test.dart",
  "test/features/gamification/ui/reduced_motion_test.dart",
  "test/fixtures/gamification/ui/",
  "docs/rounds/e13-r32-gamification-ui.md",
]
gate_tests = [
  "test/features/gamification/ui/claim_idempotency_test.dart",
  "test/features/gamification/ui/streak_states_test.dart",
  "test/features/gamification/ui/compassionate_copy_test.dart",
  "test/features/gamification/ui/reduced_motion_test.dart",
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

Az UI-51–UI-52 **együttérző**, idempotens jutalmazási felülete
(SDD Ch13 Kör 32).

## 2. Jelenlegi állapot — mért tények

- Az R22 ADR 0283 §4 kimondta: a jutalom a főkönyvből jön, nem UI-számításból.
  Ez a kör ugyanazt a szabályt viszi végig a gamifikációs felületen.
- Az R06 ADR-je szerint a csökkentett mozgás **csökkent, nem kikapcsolt**
  visszajelzés — az ünneplésre is.
- A széria (streak) a legkönnyebben büntetővé váló mechanizmus.

## 3. Scope

**Benne van:** a gamifikációs hub szint, XP, széria, küldetés és jutalom-összegzés
elrendezése · a részletes Küldetések / Eredmények / Bejövő fülek · pihenőnap,
türelmi idő, széria vége, offline főkönyv, függő beváltás és integritás-vizsgálat
állapotok · a beváltás **idempotens use case-hez** kötve · csökkentett mozgású
ünneplés és animáció nélküli alternatíva · együttérző microcopy és lokalizáció.

**NINCS benne (tilos):** a jutalom UI-oldali **számítása** · a főkönyv vagy a
küldetés-logika módosítása · fizetős széria-megőrzés bevezetése · más
képernyők · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/` | a hub és a fülek |
| `lib/l10n/app_{en,hu}.arb` | az együttérző microcopy |
| `test/features/gamification/ui/*_test.dart` (4) | a §6 cellái |
| `docs/rounds/e13-r32-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a `gamification/` KIVÉTELÉVEL ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0290)

### 5.1 NINCS büntető széria-nyelv

A megszakadt széria tény, nem kudarc. A szöveg nem hibáztat, nem kelt bűntudatot
és nem sürget — a pihenőnap és a türelmi idő normális állapot.

**NEM elfogadható gyengítés:** „Elvesztetted a 30 napos szériádat!" felkiáltó
jellel. Ez a mechanizmus szorongást termel, nem gyakorlást.

### 5.2 A beváltás IDEMPOTENS, és a felület NEM számít jutalmat

A UI a főkönyv use case-ét hívja. Offline állapotban a beváltás sorba kerül, és
a hálózat visszatérésekor **nem duplikál** (ADR 0283 §4).

**NEM elfogadható gyengítés:** optimista jóváírás a felületen, a főkönyv
megerősítése nélkül. A projekt már mérte ezt a hibaosztályt: a `try/catch`-be
fojtott írás néma eltérést hagy a felület és az adat között.

### 5.3 A jutalom FORRÁSA auditálható

A felhasználó megnézheti, mit miért kapott.

### 5.4 NINCS fizetős megőrzés (pay-to-preserve)

A szériát nem lehet pénzért visszavásárolni. Az a szorongásra épülő monetizáció.

### 5.5 Az eredmény FELTÉTELE érthető

Minden eredményhez világos, teljesíthető feltétel tartozik — nem rejtett
kritérium.

### 5.6 Az ünneplésnek van csökkentett mozgású alternatívája

Az ADR (E13-R06) szabálya: a visszajelzés megmarad, csak más modalitásban.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Nincs büntető vagy bűntudatkeltő széria-szöveg (en + hu) | `compassionate_copy_test.dart` |
| A2 | A beváltás idempotens — offline sorból sem duplikál | `claim_idempotency_test.dart` |
| A3 | A felület nem számít jutalmat (use case-t hív) | `grep` a diffben |
| A4 | A jutalom forrása auditálható | `claim_idempotency_test.dart` |
| A5 | Pihenőnap / türelmi idő / széria vége külön, nem büntető állapot | `streak_states_test.dart` |
| A6 | Nincs fizetős széria-megőrzés | `compassionate_copy_test.dart` |
| A7 | Az eredmény feltétele megjelenik és érthető | ugyanott |
| A8 | Csökkentett mozgás mellett az ünneplés visszajelzése megmarad | `reduced_motion_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| „Elvesztetted a szériádat!" | **A1** |
| Optimista jóváírás a főkönyv megerősítése előtt | **A2** |
| A jutalom a képernyőn számolva | **A3** |
| A pihenőnap a széria végeként | A5 |
| Fizetős visszaállítás felajánlva | **A6** |
| Csökkentett mozgás → az ünneplés eltűnik | **A8** |

**A beváltás három kötelező cellája** (a küszöb: hányszor íródik jóvá):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | a beváltás megszakad | **0** jóváírás |
| rajta (a küszöbön) | egyszeri beváltás | **pontosan 1** jóváírás |
| a küszöb fölött | offline beváltás + újrapróbálkozás online | **pontosan 1** jóváírás |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** írd jóvá a jutalmat
optimista módon a főkönyv megerősítése előtt → az **A2** cellának PIROSNAK kell
lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/ui/claim_idempotency_test.dart test/features/gamification/ui/streak_states_test.dart test/features/gamification/ui/compassionate_copy_test.dart test/features/gamification/ui/reduced_motion_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. A hub elrendezése (szint, XP, széria, küldetés, jutalom-összegzés).
2. A beváltás use case-hez kötve + a három idempotencia-cella.
3. A széria-állapotok: pihenőnap, türelmi idő, vége — nem büntető nyelven.
4. Az együttérző microcopy en + hu, a fizetős megőrzés kizárásával.
5. Az eredmények feltételeinek megjelenítése és a jutalom-forrás auditja.
6. Csökkentett mozgású ünneplés-alternatíva.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az optimista jóváírás.** Gyorsabbnak hat, és néma eltérést hagy a felület
  meg a főkönyv között (A2).
- **A büntető széria-nyelv.** Rövid távon növeli a visszatérést, hosszú távon
  szorongást termel — és a terméket elhagyják miatta (A1).
- **A fizetős visszaállítás.** Bevételi ötletnek látszik, és a szorongásra
  épít (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
