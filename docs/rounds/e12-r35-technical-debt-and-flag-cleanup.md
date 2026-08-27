# E12-R35 — Technikaiadósság- és flag cleanup

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 35
- **Kör-azonosító:** `E12-R35`
- **Branch:** `<motor>/e12-r35-technical-debt-and-flag-cleanup`
- **Előfeltétel:** `E12-R34` merge-elve (a GA utáni stabilizáció lezárult)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör auditot és backlogot szállít; a takarítás szabályait az ADR 0446 (flag) és a Kör 28 contract freeze rögzíti.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "technical debt deprecation allowlist expired flag cleanup"` → **[ADR 0395](../adr/0395-community-baseline-feature-flags-and-threat-model-scope.md)** („a visszavonás feltétele" szakasz: a flag-lezárás DEDIKÁLT GOV-kör dolga, nem egy építő-köré) és **[ADR 0065](../adr/0065-practice-engine-v2-parallel-rollout.md)**. A takarítás tehát AUDITÁL és backlogot ír; a tényleges hardcode-lezárás külön kör.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg a `tool/check_architecture.dart` allowlist MÉRETÉT (a megíráskor a fájl 786 sor) és a `test/tooling/architecture_allowlist_guard_test.dart` mai állítását. Az „allowlist nem nő" invariáns ehhez a MÉRT bázisvonalhoz szól.

## 0.0 Miért nem töröl kódot ez a kör

A repó mért szabálya (ADR 0395): egy kompatibilitási réteg vagy flag lezárása önálló, dokumentált kör, mert a támogatott régi kliensek még használhatják. Ez a kör tehát MÉR és TERVEZ: mit lehet eltávolítani, mi a feltétele, ki a felelőse. Kódot csak akkor töröl, ha a MÉRÉS bizonyítja, hogy nulla hívóhely és nulla támogatott kliens érinti — és akkor is a §4 listán belül.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/release/technical-debt.md",
  "tool/check_deprecations.dart",
  "test/tooling/deprecation_audit_test.dart",
  "docs/rounds/e12-r35-technical-debt-and-flag-cleanup.md",
]
gate_tests = [
  "test/tooling/deprecation_audit_test.dart",
  "test/tooling/architecture_allowlist_guard_test.dart",
  "test/tooling/feature_flag_audit_test.dart",
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

**STOP-protokoll:** ha az audit olyan eltávolítható réteget talál, aminek a törlése a §4 listán kívüli fájlt érintene, a kimenet a `stopped` jelzés és a backlog-tétel — a törlés külön kör.

## 1. Cél

Mért adósság-leltár: mi ideiglenes, kinek a felelőssége, mi az eltávolítás feltétele — és a GA utáni core legyen tisztább, ne törékenyebb.

## 2. Jelenlegi állapot — mért tények

- `tool/check_architecture.dart` (786 sor) allowlist-alapú; a `test/tooling/architecture_allowlist_guard_test.dart` az őre.
- `tool/check_feature_flags.dart` (Kör 5) a lejárt flageket fogja; a katalógus a `lib/core/feature_flags/`-ban él.
- `tool/check_deprecations.dart` **nem létezik**.
- A `lib/features/` fa MA `library` ÉS `library_v2`, illetve `progress` ÉS `progress_v2` párokat is tartalmaz — mért, párhuzamos rétegek, amelyek tipikus adósság-jelöltek.
- A `docs/release/technical-debt.md` **nincs**.

## 3. Scope

**Benne van:** `tool/check_deprecations.dart` (a `@Deprecated` jelölések, TODO/FIXME-k és a párhuzamos `*_v2` rétegek MÉRÉSE: hívóhely-szám, utolsó módosítás, van-e eltávolítási feltétel) · `test/tooling/deprecation_audit_test.dart` (az audit-eszköz cellái + az „allowlist NEM nő" invariáns a MÉRT bázisvonalhoz) · `docs/release/technical-debt.md` (tételenként: mi, miért van még, ki a felelőse, mi az eltávolítás feltétele, melyik körben).

**NINCS benne (tilos):**

- Kompatibilitási kód törlése, amíg támogatott kliens használhatja.
- Flag hardcode-lezárása (ADR 0395: külön GOV-kör).
- `lib/**` módosítás (kivéve, ha a MÉRÉS nulla hívóhelyet bizonyít — de az is csak a §4 listán belül, ami MA nem tartalmaz `lib/` útvonalat, tehát a gyakorlatban `stopped`).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/release/technical-debt.md` | ÚJ — az adósság-leltár és backlog |
| `tool/check_deprecations.dart` | ÚJ — a mérő-eszköz |
| `test/tooling/deprecation_audit_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/**` · `backend/**` · `tool/check_architecture.dart` · `tool/check_feature_flags.dart` · `.github/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések

Nincs ADR. Három kötelező szabály:

### 5.1 Az allowlist NEM nő

A `check_architecture.dart` allowlistje a MÉRT bázisvonalhoz képest nem bővülhet. **NEM elfogadható gyengítés:** „ideiglenes" bejegyzés hozzáadása a kör kényelméért.

### 5.2 Minden ideiglenes elemhez FELELŐS és FELTÉTEL tartozik

**NEM elfogadható gyengítés:** „később eltávolítjuk" határidő és feltétel nélkül.

### 5.3 Támogatott régi kliens által használt kód NEM törölhető

**NEM elfogadható gyengítés:** a „valószínűleg senki nem használja" indoklás mérés nélkül.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az audit felsorolja MINDEN `@Deprecated` elem hívóhely-számát | `deprecation_audit_test.dart` |
| A2 | A lejárt flagek listája megegyezik a Kör 5 `check_feature_flags.dart` kimenetével (nincs második igazság) | `deprecation_audit_test.dart` |
| A3 | Az allowlist mérete nem nőtt a MÉRT bázisvonalhoz képest | `architecture_allowlist_guard_test.dart` a §7 gate-ben |
| A4 | Minden adósság-tétel hordoz felelőst és eltávolítási feltételt | `deprecation_audit_test.dart` |
| A5 | A támogatott régi kliens contract füst-cellája zöld (nem töröltünk el használatban lévő utat) | `deprecation_audit_test.dart` |
| A6 | A kör egyetlen `lib/` fájlt sem módosít | `git diff --stat` |

**Küszöb-cellahármas az allowlist méretére** (a MÉRT bázisvonal `N` bejegyzés; a határ INKLUZÍV): a küszöb **alatt** (`N-1`, azaz csökkent) → ZÖLD (és a csökkenés a leltárban indokolt); **pontosan rajta** (`N`) → ZÖLD; a küszöb **fölött** (`N+1`) → PIROS.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az audit saját flag-listát épít a Kör 5 eszköze helyett | A2 |
| Az allowlist egy „ideiglenes" bejegyzéssel bővül | a küszöb-cellahármas „fölött" cellája |
| Egy adósság-tétel felelős nélkül kerül a listára | A4 |
| A kör kódot töröl a `lib/`-ből | A6 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** adj egy bejegyzést az architektúra-allowlisthez ideiglenesen, futtasd a §7 gate-et → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/deprecation_audit_test.dart test/tooling/architecture_allowlist_guard_test.dart test/tooling/feature_flag_audit_test.dart
```

Az audit-eszköz közvetlen futtatása (kimenet a §10-be):

```bash
dart run tool/check_deprecations.dart
```

## 8. Implementációs sorrend

1. `tool/check_deprecations.dart` — a mérés.
2. `test/tooling/deprecation_audit_test.dart` — a küszöb-cellahármassal.
3. `docs/release/technical-debt.md` — a MÉRT leltár, felelősökkel és feltételekkel.
4. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Korai törlés.** Egy még használt kompatibilitási út eltávolítása adatvesztést vagy hibát okoz (§5.3).
- **Allowlist-hízás.** A legcsendesebb minőségromlás (A3).
- **Kettős flag-igazság.** Saját lista a Kör 5 eszköze mellett (A2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
