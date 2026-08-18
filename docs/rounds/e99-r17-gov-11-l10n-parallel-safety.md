# E99-R17 (GOV-11) — Az ARB-ütközés feloldása: feature-szintű l10n-fragmentumok és generált aggregátum

- **Státusz:** READY FOR IMPLEMENTATION (brief 2026-08-18, `main @ 52324cb3`)
- **Típus:** **governance-kör** — a párhuzamos körök első fizikai blokkjának feloldása
- **Kör-azonosító:** `E99-R17`. Emberi neve **GOV-11**.
- **Előfeltétel:** `E99-R16` merge-elve
- **Brief szerzője:** Claude (Opus 5, orchesztrátor) · **ADR:** [`0307`](../adr/0307-pipeline-throughput-program-v2.md) **§4**

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "tool/gen_l10n_segments.dart",
  "tool/ci/check_l10n_parity.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/features/tuner_en.arb",
  "lib/l10n/features/tuner_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "tools/round-slots.py",
  "tools/tests/test_round_slots_generated_paths.py",
  "test/tooling/gen_l10n_segments_test.dart",
  "test/tooling/check_l10n_parity_test.dart",
  "docs/rounds/e99-r17-gov-11-l10n-parallel-safety.md",
]
gate_tests = [
  "test/tooling/gen_l10n_segments_test.dart",
  "test/tooling/check_l10n_parity_test.dart",
]
native_gate = false
```

> **Kockázat = high, indoklás:** a diff MINDEN felhasználói szöveg forrását
> érinti (`lib/l10n/**`); egy kulcsvesztés az egész appban néma
> szöveghiányként jelenne meg. Ezért a mérce a kulcshalmaz **halmazszintű
> egyezése**, nem szemrevételezés.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **STOP-protokoll:** listán kívüli fájl →
`stopped` + brief-revízió; az `allowed_paths` tágítása TILOS.

## 1. Cél — mit mértünk

A `docs/execution/pipeline-queue.tsv` **75 nyitott** briefjéből a
`lib/l10n/app_en.arb` és `lib/l10n/app_hu.arb` **36**-ban szerepel az
`allowed_paths` listán. A `tools/round-slots.py` ezért bármely két ilyen kört
ütközőnek lát — **nem azért, mert ugyanazt a logikát írják, hanem mert
mindkettő hozzáfűz egy kulcsot ugyanahhoz a fájlhoz.**

Mérve: 2026-08-04 óta 120 kör futott, ebből **1** párhuzamos pár; a második slot
291 alkalommal maradt üresen. A §4 lever ezt a mechanikus blokkot oldja fel — a
mérce (l10n-paritás) gyengítése nélkül.

## 2. Jelenlegi állapot — mérve

- `lib/l10n/app_en.arb`: 1946 sor, **1333** kulcs (a `@`-metaadatokon kívül);
  `app_hu.arb` a párja. Mindkettő kézzel szerkesztett, egyetlen fájl.
- `tool/ci/check_l10n_parity.dart` gate-lépés: minden sablonkulcshoz van
  nem üres, azonos helyőrzőjű fordítás.
- `tools/round-slots.py`: `SERIALIZED_PATHS` (HANDOFF, RTM, LESSONS, sor-fájl)
  nem számít ütközésnek — az ARB igen.
- A `tuner` feature 14 kulccsal a legkisebb, önmagában zárt kulcscsoport → pilot.

## 3. Feladatok

### D1 — `tool/gen_l10n_segments.dart` (generátor + ellenőrző mód)

- Bemenet: `lib/l10n/base/app_<locale>.arb` (a még nem migrált maradék) és
  `lib/l10n/features/<feature>_<locale>.arb` fragmentumok.
- Kimenet: `lib/l10n/app_<locale>.arb` — **determinisztikus**, kulcs szerint
  rendezett unió, a `@@locale` és a `@kulcs` metaadatok megtartásával.
- `--check` mód: a lemezen lévő aggregátum megegyezik-e a generálttal
  (frissesség-ellenőrzés), kilépési kód 1, ha nem.
- **Ütköző kulcs** (ugyanaz a kulcs két fragmentumban) → hiba, nem néma
  felülírás.

### D2 — A gate méri a frissességet (`tool/ci/check_l10n_parity.dart`)

A meglévő `l10n` gate-lépés **kiegészül** a `--check` hívással, hogy ne
kelljen új gate-lépés (a `round-gate.sh` és a CI composite lépéslistája így
változatlan marad, az ADR 0171 paritás-őre nem sérül).

### D3 — Pilot migráció: `tuner`

- A `tuner*` prefixű kulcsok (mérve **14** kulcs) átkerülnek a
  `lib/l10n/features/tuner_{en,hu}.arb` fájlokba, minden más a
  `lib/l10n/base/app_{en,hu}.arb`-ba.
- **Acceptance:** a regenerált `lib/l10n/app_{en,hu}.arb` kulcs→érték leképezése
  **halmazszinten azonos** a migráció előttivel (a kulcsok SORRENDJE változhat,
  a tartalom nem). A teszt ezt JSON-összehasonlítással méri, nem diff-fel.

### D4 — `tools/round-slots.py`: a generált aggregátum nem ütközés

- Új `GENERATED_PATHS` halmaz (`lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb`):
  ezek — a `SERIALIZED_PATHS`-hoz hasonlóan — nem számítanak fájl-ütközésnek,
  mert tartalmuk **újragenerálható**, és a merge-zár sorosítja őket.
- A fragmentumok (`lib/l10n/features/*.arb`) TELJES ÉRTÉKŰ ütközési felület
  maradnak: két kör ugyanarra a feature-fragmentumra továbbra sem futhat.

## 4. Mérce-mátrix

| eset | bemenet | elvárt |
|---|---|---|
| kulcshalmaz **azonos** | migráció előtti vs. regenerált aggregátum | a teszt ZÖLD |
| kulcs **hiányzik** (egy fragmentum-kulcs kimarad az unióból) | mesterséges fixtúra | `check_l10n_parity` **PIROS** |
| kulcs **duplikált** (ugyanaz a kulcs két fragmentumban) | mesterséges fixtúra | a generátor hibával áll meg, kilépési kód ≠ 0 |
| aggregátum **elavult** (kézi szerkesztés a generált fájlban) | mesterséges fixtúra | `--check` **PIROS** |
| `round-slots.py` ütközés | két brief, mindkettő `lib/l10n/app_en.arb` | NINCS ütközés (generált) |
| `round-slots.py` ütközés | két brief, mindkettő `lib/l10n/features/tuner_en.arb` | ÜTKÖZÉS (fragmentum) |

**Falszifikációs cella (kötelező):** a D2 `--check` hívás kiszedése a gate
l10n-lépéséből → az „aggregátum elavult" eset **PIROS** helyett zöld lenne,
ezért a `test/tooling/check_l10n_parity_test.dart` erre írt esete **PIROS** →
visszaállítás után zöld. Második falszifikáció: a D4 `GENERATED_PATHS`
kiszedése → a „NINCS ütközés" eset **PIROS**.

## 5. Tilos zóna

- `docs/adr/**`, `.ai/router.toml`, `docs/execution/pipeline-queue.tsv`,
  `.pipeline/**`, `tools/round-pipeline.sh`.
- **A `tuner`-en kívüli kulcscsoportok migrációja TILOS ebben a körben** — a
  többi feature lustán, a rá következő körök során vándorol át. A pilot mérete
  szándékos: a mechanizmus bizonyítása a cél, nem az 1333 kulcs mozgatása.
- A `flutter gen-l10n` konfigurációja (`l10n.yaml`, ha van) változatlan: az
  aggregátum útvonala és neve nem változik, tehát a generált
  `AppLocalizations` érintetlen.

## 6. Definition of Done

1. D1–D4 kész; a `tuner` kulcsok fragmentumban élnek, az aggregátum generált.
2. A §4 mind a hat cellája tesztelt (`test/tooling/gen_l10n_segments_test.dart`,
   `test/tooling/check_l10n_parity_test.dart`,
   `tools/tests/test_round_slots_generated_paths.py`).
3. `tools/round-gate.sh test/tooling/gen_l10n_segments_test.dart test/tooling/check_l10n_parity_test.dart` zöld
   (a gate `l10n` lépése a frissességet is méri).
4. `python3 -m pytest tools/tests -q` zöld.
5. Kör-jelzés `done`.

## 7. Gate

```bash
tools/round-gate.sh test/tooling/gen_l10n_segments_test.dart test/tooling/check_l10n_parity_test.dart
python3 -m pytest tools/tests -q
```

A teljes suite (minden ARB-fogyasztó widget-teszttel) + property gate a CI-ban
fut (ADR 0053) — a kulcsvesztés ott is fennakadna.
