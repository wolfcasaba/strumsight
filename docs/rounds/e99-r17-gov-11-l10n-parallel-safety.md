# E99-R17 (GOV-11) — Az ARB-ütközés feloldása: feature-szintű l10n-fragmentumok és generált aggregátum

- **Státusz:** HOLD — `H-GATEGUARD` (pre-flight folytatás 2026-08-19, `main @ dc6b4583`)
- **Típus:** **governance-kör** — a párhuzamos körök első fizikai blokkjának feloldása
- **Kör-azonosító:** `E99-R17`. Emberi neve **GOV-11**.
- **Előfeltétel:** `E99-R16` merge-elve
- **Brief szerzője:** Claude (Opus 5, orchesztrátor); pre-flight: Codex (Terra) · **ADR:** [`0307`](../adr/0307-pipeline-throughput-program-v2.md) **§4**

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

## 0.0 Pre-flight revízió (2026-08-19)

### Folytatási mérés (2026-08-19, `origin/main @ dc6b4583`)

- A megőrzött kör-branch D1 commitja (`eb915931`) előtt a `main` nyolc
  committal előrelépett. A branch a `630f8615` merge commitban konfliktusmentesen
  tartalmazza az aktuális `origin/main`-t, és a freshness-bizonyíték pusholva
  van; régi szerződéshez nem indult javító-dispatch.
- A foglaló most `0324`-et adott, de új ADR továbbra sem készül: az elfogadott
  ADR 0307 §4 már normatívan rögzíti ezt a döntést, `docs/adr/**` pedig tiltott
  zóna. A foglalás nem jogosít fel új ADR létrehozására.
- Kötelező RAG-mérés: `node tools/knowledge-rag.mjs --top 5 "E99-R17 ARB l10n
  feature fragments generated aggregate check_l10n_parity tool/ci"` és
  `node tools/knowledge-rag.mjs --corpus lessons --top 5 "protected gate file
  H-GATEGUARD l10n parity generated ARB fragments"`. Az index `55b2bf16`-on
  nyolc committal elavult, ezért ez nem újraindexelési hatáskör; a találatok
  továbbra is a generált l10n előkészítésére (`lessons/L89`, `lessons/L111`) és
  a gate elkülönített futtatására (`lessons/L130`) mutatnak. A jelen kör
  közvetlen, frissebb precedense `lessons/L323`: a marker önmagában nem nyitja
  fel az implementer-őrt.
- A tényleges út most is `tools/round-gate.sh:243` →
  `tool/ci/check_l10n_parity.dart`; a `tool/ci/*` a gyári mérce védett
  globja. A `.claude/gate-edit-authorized` marker jelen van, de a D1 utáni
  branch-történetben nincs emberi commit a D2 célfájlra. Ezért D2 nem
  dispatch-elhető: a következő helyes lépés a user személyes szerkesztése és
  pushja erre a branchre, vagy a kör holdon hagyása. A scope-lista nem bővül,
  és a mérce nem változik.

- A `main @ 67d459f1` tényleges ARB-mérése eltér az előre írt briefétől:
  `app_en.arb` 1 988 sor / 1 354 üzenetkulcs, `app_hu.arb` 1 911 sor /
  1 354 üzenetkulcs; mindkettőben pontosan 14 `tuner*` kulcs van. A
  `lib/l10n/base/` és `lib/l10n/features/` még nem létezik. A cél és a pilot
  ezért változatlan, de a régi 1 333-as szám nem használható bizonyítékként.
- A `pipeline-queue.tsv` 77 nem-`done` sort tartalmaz. A valódi brieffájlok
  átvizsgálása szerint `app_en.arb` 37, `app_hu.arb` 36 nyitott briefben
  szerepel; ez megerősíti a mechanikus ütközést, de nem állít hamis, azonos
  darabszámot a két fájlra.
- A tényleges út ellenőrzése: `check_l10n_parity.dart` ma közvetlenül a két
  aggregátumot olvassa; `round-gate.sh` ennek `main()`-ját hívja a meglévő
  `l10n` lépésben. A D2 ezért ezt az egy gate-útvonalat bővíti, nem vezet be
  új gate-lépést.
- Az ADR-foglaló `0322`-t adott ki az E99-R17-nek, de **nem készül új ADR**:
  az elfogadott ADR 0307 §4 szó szerint rögzíti ezt a szegmentálás- és
  generált-aggregátum döntést, a brief pedig `docs/adr/**`-t tilt. Az E99-R16
  pre-flight R1 ugyanezt a „`nincs`” pipeline-szöveget már méréssel oldotta
  fel. A foglalás ezért szándékosan felhasználatlan; fájl létrehozása itt H3
  lenne.
- **Visszakeresett előzmény:** a RAG-index a méréskor 4 committal elavult volt,
  de a releváns előzményeket visszaadta: `lessons/L111` és `lessons/L222`
  szerint a friss klónban a `prepare-flutter-generated.sh` kötelező; a
  `lessons/L177` szerint a wrapper `scope_audit` mezője kézi ellenőrzést is
  igényel. Az ADR 0307 §4 a szegmentált, generált aggregátum mintájának
  normatív forrása. Más releváns l10n-fragmentum előzményt a lekérdezés nem
  talált.

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

A `docs/execution/pipeline-queue.tsv` **77 nem-`done`** briefjéből a
`lib/l10n/app_en.arb` **37**-ben, az `lib/l10n/app_hu.arb` **36**-ban szerepel az
`allowed_paths` listán. A `tools/round-slots.py` ezért bármely két ilyen kört
ütközőnek lát — **nem azért, mert ugyanazt a logikát írják, hanem mert
mindkettő hozzáfűz egy kulcsot ugyanahhoz a fájlhoz.**

Mérve: 2026-08-04 óta 120 kör futott, ebből **1** párhuzamos pár; a második slot
291 alkalommal maradt üresen. A §4 lever ezt a mechanikus blokkot oldja fel — a
mérce (l10n-paritás) gyengítése nélkül.

## 2. Jelenlegi állapot — mérve

- `lib/l10n/app_en.arb`: 1 988 sor, **1 354** kulcs (a `@`-metaadatokon
  kívül); `app_hu.arb`: 1 911 sor, ugyanennyi kulcs. Mindkettő kézzel
  szerkesztett, egyetlen fájl.
- `tool/ci/check_l10n_parity.dart` gate-lépés: minden sablonkulcshoz van
  nem üres, azonos helyőrzőjű fordítás.
- `tools/round-slots.py`: `SERIALIZED_PATHS` (HANDOFF, RTM, LESSONS, sor-fájl)
  nem számít ütközésnek — az ARB igen; `GENERATED_PATHS` ma még nincs.
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
  szándékos: a mechanizmus bizonyítása a cél, nem az 1 354 kulcs mozgatása.
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
