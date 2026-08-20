# E14-R17 — Referencia-modell reprodukció és licenc-audit

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ 6371aa3`)
- **Típus:** Chapter 14, Kör 17 (strum recovery blokk) — **kutatási kör**
- **Kör-azonosító:** `E14-R17`
- **Branch:** `<motor>/e14-r17-reference-model-repro-and-licence-audit`
- **Előfeltétel:** `E14-R08` (grouped harness, hogy a StrumSight-korpuszon is
  mérhető legyen) merge-elve.
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0369` — **a Claude írja meg (go/no-go), a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd, hogy a research
> környezet elérhető-e ezen a boxon (`ml/README.md` + a TF-venv útvonala). Ha
> nincs, a kör jelzése `blocked` — sikeres verifikációt állítani tilos
> (Chapter 14 §9/9). Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "ml/reference/README.md",
  "ml/reference/run_reference_eval.py",
  "ml/reference/reference_manifest.json",
  "test/tooling/reference_model_licence_guard_test.dart",
  "docs/eval/reference-model-audit.md",
  "docs/rounds/e14-r17-reference-model-repro-and-licence-audit.md",
]
gate_tests = [
  "test/tooling/reference_model_licence_guard_test.dart",
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
**Hiányzó research-környezet vagy letölthetetlen checkpoint → `blocked`**, nem
„részleges siker".

## 1. Cél

A publikált joint referencia-modell **reprodukálható** legyen egyetlen
paranccsal, és a **licenc-audit** (kód, checkpoint, dataset KÜLÖN) döntse el,
kerülhet-e bármilyen artefaktum a termékbe. A hivatalos eredményt és a
StrumSight saját mérését a report **soha nem keveri**.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **Chapter 14 §5.1:** a joint onset+direction+chord modell a legerősebb
  kutatási irány — de előbb reprodukálni kell, nem átvenni.
- **AGENTS.md §5 / ADR 0138 titok-scan:** külső artefaktum nem kerülhet a
  repóba audit nélkül; ez a kör ezt gépi őrré teszi.

## 2. Jelenlegi állapot — mért tények

- `ml/` — saját tanító oldal (`honest_eval.py`, `klangio.py`, `model_card.json`,
  `export_dart_weights.py`); **nincs** külső referencia-modell futtatókörnyezet.
- `assets/` — a szállított súlyok helye; ma nincs külső, harmadik féltől
  származó checkpoint.
- Nincs olyan gépi őr, amely megakadályozná egy nem auditált külső artefaktum
  bekerülését.

## 3. Scope

**Benne:** pinelt reprodukciós script + README (külön környezet), a hivatalos
fixture és a StrumSight held-out mérése KÜLÖN táblában, licenc-audit
(kód/checkpoint/dataset), gépi licenc-őr, doksi.

**Nincs benne:** bármilyen külső súly bemásolása a repóba/`assets/`-be,
production-bekötés, `lib/**` módosítás, DSP/ML konstans.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `ml/reference/README.md` | környezet, pinelt commit, futtatás |
| `ml/reference/run_reference_eval.py` | egyparancsos reprodukció |
| `ml/reference/reference_manifest.json` | forrás, commit-hash, licencek, checksum |
| `test/tooling/reference_model_licence_guard_test.dart` | gépi őr: nincs auditálatlan artefaktum |
| `docs/eval/reference-model-audit.md` | a két mérés KÜLÖN + go/no-go javaslat |
| `docs/rounds/e14-r17-reference-model-repro-and-licence-audit.md` | §10 handoff |

**Tilos zóna:** minden más — **kiemelten** `assets/**` (semmilyen külső súly),
`lib/**`, `ml/` a `reference/` alkönyvtáron kívül, `docs/adr/**`,
`docs/rag/chunks/**`, `.github/workflows/**`, `tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0369)

### 5.1 Licenc-blokkolónál nincs másolás

Ha a kód, a checkpoint VAGY a dataset licence tiltja a termékfelhasználást,
semmilyen artefaktum nem kerül a repóba, és a kör eredménye **no-go**.
**NEM elfogadható**: „csak kísérletnek betesszük".

### 5.2 A három licenc külön ítélet

A kód, a súly és az adat licence KÜLÖN mezőt kap a manifestben; egyetlen
„MIT-nek tűnik" összefoglaló nem elég.

### 5.3 A két mérés nem keveredik

A hivatalos fixture eredménye és a StrumSight held-out eredménye külön
táblában, külön korpusz-hash-sel szerepel.

### 5.4 A reprodukció egy paranccsal fut

`python3 ml/reference/run_reference_eval.py --manifest …` — kézi lépéssor nem
elfogadható reprodukcióként.

### 5.5 Gépi őr, nem ígéret

A licenc-őr teszt a repó fáján ellenőrzi, hogy nincs olyan referencia-eredetű
artefaktum, amelyhez ne tartozna `approved` audit-bejegyzés.

## 6. Acceptance criteria

1. A reprodukciós script egyetlen paranccsal fut, és a manifestben rögzített
   pinelt commit-hash-t használja.
2. A manifest mindhárom licenc-mezőt tartalmazza; bármelyik hiánya → típusos
   hiba.
3. A report két külön táblát ad (hivatalos fixture vs StrumSight held-out),
   mindkettőnél korpusz-hash-sel.
4. A licenc-őr teszt PIROS, ha egy referencia-eredetű fájl audit-bejegyzés
   nélkül jelenik meg a fán (a teszt ideiglenes fixture-fájllal méri).
5. `blocked` jelzés, ha a research-környezet vagy a checkpoint nem elérhető —
   a report ilyenkor „nem mért", nem becsült értékeket tartalmaz.
6. A go/no-go javaslat a reportban a mért latency- és memória-értékre is
   hivatkozik.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egyetlen összevont licenc-mező | 2. pont |
| A két mérés egy táblában | 3. pont |
| Az őr csak `assets/`-et néz, más útvonalat nem | 4. pont fixture-cellája |
| Hiányzó környezetnél becsült szám | 5. pont |
| Kézi lépéssor reprodukcióként | 1. pont |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling
```

Külön processzben futó `format` → `analyze` → célzott teszt → `architecture`
(AGENTS.md §12). A Python oldal külön, önálló parancsként:

```bash
python3 -m pytest ml -q
```

`&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: egy ideiglenes, audit nélküli referencia-fájl
elhelyezésével a 4. pont **PIROS**, a fájl törlésével **ZÖLD**.

## 8. Implementációs sorrend

1. Manifest-séma (három licenc, commit-hash, checksum).
2. Licenc-őr teszt (RED-del kezdve).
3. Reprodukciós script + README.
4. Mérés és report — ha a környezet hiányzik: `blocked`.

## 9. Kockázatok

- **Környezet-hiány:** valószínű ezen a boxon; a `blocked` út a helyes, nem a
  becslés.
- **Licenc-tévedés:** ha bármelyik licenc nem egyértelmű, a döntés
  **no-go** — a kétség nem engedély.
- **Scope-csúszás a bekötés felé:** tilos zóna: `lib/**`, `assets/**`.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
