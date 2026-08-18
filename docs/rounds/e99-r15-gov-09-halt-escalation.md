# E99-R15 (GOV-09) — Halt-eszkaláció: motorváltás az utolsó önjavító kísérletnél és ismétlődő riasztás

- **Státusz:** READY FOR IMPLEMENTATION (brief 2026-08-18, `main @ 52324cb3`)
- **Típus:** **governance-kör** — a lánc SAJÁT vezérlése
- **Kör-azonosító:** `E99-R15`. Emberi neve **GOV-09**.
- **Előfeltétel:** `E99-R14` merge-elve (ugyanaz a fájl, `tools/round-pipeline.sh`)
- **Brief szerzője:** Claude (Opus 5, orchesztrátor) · **ADR:** [`0307`](../adr/0307-pipeline-throughput-program-v2.md) **§2** — az ADR MÁR MEGÍRVA, a `docs/adr/` TILOS zóna.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "tools/round-pipeline.sh",
  "tools/tests/test_selfheal_escalation.py",
  "docs/execution/pipeline-selfheal-prompt.md",
  "docs/rounds/e99-r15-gov-09-halt-escalation.md",
]
gate_tests = [
  "test/tooling/architecture_allowlist_guard_test.dart",
]
native_gate = false
```

> **Kockázat = high, indoklás:** a diff a lánc saját vezérlésébe (self-heal ág,
> riasztás) nyúl; egy hibás feltétel némán megállíthatja vagy végtelen
> ismétlésbe hajthatja a láncot. A `gate_tests` cella fa-egészség őr; a kör
> tényleges mércéje a `pytest tools/tests` + Router CI (§7).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **STOP-protokoll:** listán kívüli fájl →
`stopped` + brief-revízió kérése; az `allowed_paths` tágítása TILOS.

## 1. Cél — a mért 42 órás állás

2026-08-16 13:06-kor indult az `E07-R16`. 14:15-kor `H-NOSIGNAL`-lal halt (az
elakadás-őr helyesen mérte, hogy a session-napló 20 perce nem változott). Ezután
**három** önjavító kísérlet futott — mindhárom UGYANAZZAL a motorral —, és
mindhárom ugyanúgy, jelzés nélkül halt el (14:40, 15:05, 15:30). 15:35-kor „az
önjavítás KIMERÜLT (3/3)", a lánc megállt, és **2026-08-18 08:20-ig állt**:
**42 óra**, nulla munkával.

Mért kontextus: 2026-08-01 óta **115,7 óra** halt-állás 93 epizódban; a
self-heal 91 epizódot magától megoldott. A két valaha mért KIMERÜLÉS (E03-R09,
E07-R16) **mindkettő `H-NOSIGNAL`** volt — vagyis pontosan az a hibaosztály,
ahol a variáció nélküli ismétlés semmit nem változtat.

A riasztás egyszer ment ki (`round-pipeline.sh`, „önjavítás kimerült"), és nem
ismétlődött — éjszaka ez egyenlő a csenddel.

## 2. Jelenlegi állapot — mérve a kódban

- `selfheal_max=${PIPELINE_SELFHEAL_MAX:-3}`; a `heal_attempts` a (kör,
  halt-kód) párra számol kísérletet.
- Az önjavító session MINDIG a kör saját motorjával indul — a kísérlet
  sorszáma nem befolyásol semmit.
- Kimerüléskor egyetlen `notify … high` megy, majd a lánc minden firingen csak
  annyit naplóz, hogy „a lánc továbbra is áll — feloldás:
  tools/pipeline-status.sh --resume".
- A `H-GATEGUARD` ág (az önjavítás a gate-hez nyúlt) emberi döntést kér.

## 3. Feladatok

### D1 — Az utolsó kísérlet MÁS motorral fut

- Új függvény: `heal_engine_for_attempt <kör> <halt-kód> <kísérlet> <kör-motor>`.
- Szabály: az 1. és 2. kísérlet a kör saját motorjával megy (mai viselkedés);
  az **utolsó** (`selfheal_max`-adik) kísérlet a motor-nyilvántartásból
  (`docs/execution/engine-registry.tsv`) választ **determinisztikusan** másikat:
  a nyilvántartás sorrendjében az első olyan, elérhető motor, ami (a) nem a kör
  motorja, (b) nem ugyanaz a `model` érték (a `codex` és a `terra` sor mérve
  UGYANAZ a modell — a kettő cseréje nem variáció), (c) `harness`-e támogatott.
- A választás naplózva: `ÖNJAVÍTÓ MOTORVÁLTÁS: <kör> <régi> → <új> (utolsó kísérlet)`,
  és ntfy-jal jelezve.
- Ha nincs alkalmas másik motor, a mai viselkedés marad (ugyanaz a motor),
  naplózott indoklással — **fail-open a mai állapotra, nem néma kihagyás**.

### D2 — A kimerült állapot nem néma

- `PIPELINE_HALT_REMINDER_MIN` (alap **60** perc): amíg a `.pipeline/HALTED`
  létezik ÉS az önjavítás kimerült, a driver ennyi percenként ismételt,
  `high` prioritású ntfy-t küld. Az utolsó riasztás időbélyege a `$state_dir`-ben
  él, hogy az 5 perces cron ne spammeljen.
- `PIPELINE_HALT_REMINDER_MAX_H` (alap **24** óra): ennyi idő után az ismétlés
  leáll (a napló ettől még minden firingen ír).
- A riasztás törzse tartalmazza a kört, a halt-kódot és a
  `tools/pipeline-status.sh --resume` parancsot.

### D3 — A self-heal prompt tudjon a motorváltásról

`docs/execution/pipeline-selfheal-prompt.md`: az utolsó kísérlet promptja
mondja ki, hogy MÁS motor futtatja, és hogy az előző két kísérlet naplója
(`.pipeline/heal-*.log`) bemenet, nem megismételendő munka.

## 4. Mérce-mátrix

`PIPELINE_HALT_REMINDER_MIN = 60` és a kísérlet-küszöb hármas cellái
(`tools/tests/test_selfheal_escalation.py`):

| eset | bemenet | elvárt viselkedés |
|---|---|---|
| küszöb **alatt** | az utolsó riasztás 59 perce ment ki | NINCS új ntfy |
| küszöb **rajta** | pontosan 60 perce | pontosan EGY új ntfy |
| küszöb **fölött** | 25 óra telt el a halt óta (`MAX_H` fölött) | nincs több ntfy, a napló továbbra is ír |
| kísérlet 1 | `heal_attempts = 0` | a kör saját motorja |
| kísérlet 2 | `heal_attempts = 1` | a kör saját motorja |
| kísérlet 3 (utolsó) | `heal_attempts = 2` | MÁS motor, más `model` értékkel |

**Falszifikációs cella (kötelező):** a D1 motorváltás kiszedése (az utolsó
kísérlet is a kör motorjával induljon) → a „kísérlet 3" eset **PIROS** →
visszaállítás után zöld. Második falszifikáció: a D2 időbélyeg-ellenőrzés
kiszedése → a „küszöb alatt" eset **PIROS** (spam).

## 5. Tilos zóna — amit ez a kör NEM tesz

- **Nincs automatikus resume.** A kimerült halt feloldása változatlanul emberi
  döntés; a kör csak hangosabbá teszi az állapotot.
- A `H-GATEGUARD` ág változatlan.
- A `selfheal_max` alapértéke NEM nő (3 marad): a cél a variáció, nem a több
  próbálkozás.
- A gate, a review-protokoll és a merge-kapu érintetlen.
- Fájlok: `docs/adr/**`, `.ai/router.toml`, `.pipeline/**`, Dart források — tilos.

## 6. Definition of Done

1. D1–D3 kész; a mai viselkedés minden nem érintett ágon bitre azonos.
2. `tools/tests/test_selfheal_escalation.py` lefedi a §4 mind a hat celláját.
3. `python3 -m pytest tools/tests -q` zöld.
4. `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart` zöld.
5. Kör-jelzés `done`.

## 7. Gate

```bash
tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart
python3 -m pytest tools/tests -q
```

A gate-lépések külön processzben futnak; a csonkítatlan kimenet a bizonyíték.
A teljes suite + property gate a CI-ban fut (ADR 0053).
