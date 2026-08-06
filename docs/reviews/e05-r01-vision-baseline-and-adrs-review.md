# Review — E05-R01 Vision baseline, capability audit és alapozó ADR-ek

- **Verdikt:** **APPROVED** (0 OPEN BLOCKER/MAJOR/MINOR; 1 NOTE)
- **Reviewer:** Claude (orchestrátor, független read-only review, ADR 0055)
- **Branch:** `codex/e05-r01-vision-baseline-and-adrs` @ `7a9d9e0`
- **Base:** `origin/main` @ `19c02eb`
- **Implementer:** DeepSeek v4 Pro (`deepseek/deepseek-v4-pro`, Kilo-profil,
  `codex-round.sh`) — a hat ADR-t az orchestrátor írta a pre-flightban (§0.0),
  az implementer a baseline + két sablon dokumentumot.

## Módszer

- Scope-audit `19c02eb..7a9d9e0` ellen (`tools/scope-audit.py`): **OK**, 10
  változott útvonal, 0 generált/ignorált, 0 listán kívüli.
- Diff-tartalom acceptance-cellánként (brief §6) ellenőrizve.
- §6.1 falszifikációs próbák gondolatban végigfuttatva (lásd lent).
- Gate/CI: `full-gate.yml` exact-SHA `7a9d9e0` + `router-ci.yml` — a merge-kapu
  a zöld CI-t igényli (exact-SHA, ADR 0086 §2).

## Diff (10 fájl, mind az `allowed_paths`-on belül)

- 6 ADR: `docs/adr/0178…0183-*.md` (orchestrátor, pre-flight)
- `docs/baseline/epic-05-vision-start.md` (implementer)
- `docs/manual-testing/vision-device-matrix.md` (implementer)
- `docs/manual-testing/vision-performance-benchmark.md` (implementer)
- `docs/rounds/e05-r01-vision-baseline-and-adrs.md` (§0.0 revízió + §10 handoff)

## Acceptance-ellenőrzés (brief §6)

| Kritérium | Eredmény |
|---|---|
| §6.1 baseline: minden állítás mellett parancs+kimenet | **PASS** — §1.1–1.x nyers `rg`/`ls` parancsok + kimenet (pl. `rg -n "camera" pubspec.yaml` → nincs találat, exit 1) |
| §6.2 hat ADR: Kontextus/Döntés/Következmények/Elutasított-alternatívák + „NEM elfogadható" | **PASS** — mind a 6 ADR 4/4 szekció + 1× „NEM elfogadható" (mérve grep-pel) |
| §6.3 metrika-lista kétoszlopos (production vs experimental), `requiredCapability` + observability | **PASS** — baseline §4.1 (12 production sor) + §4.2 (5 experimental sor), oszlopok: Metrika / `requiredCapability` / Minimum observability előfeltétel |
| §6.4 device-mátrix: eszköz, Android, kamera, mért érték helye, státusz (PENDING/PASS/FAIL), felelős | **PASS** — §2.1 fejléc mind tartalmazza; PENDING sorok |
| §6.5 `git diff --stat` nem érint `lib/`/`test/`/`android/`/`ios/`/`pubspec.yaml` | **PASS** — scope-audit 0 listán kívüli; a round diff csak `docs/` |

## §6.1 falszifikációs próbák (reviewer eldobható próbái — nem commitolva)

| Próba | Mért őr | Eredmény |
|---|---|---|
| ADR-ből törölt „NEM elfogadható" | reviewer szemrevételezés (§6.2) | az őr létezik: mind a 6 ADR-ben jelen van; törlés esetén a cella bizonyítatlan → elutasítás |
| baseline állítás mellől törölt forrás-parancs | reviewer szemrevételezés (§6.1) | minden állítás alatt van parancs+kimenet; törlés esetén mérhetetlen → elutasítás |
| `lib/`/`test/` fájl a diffben | gépi `scope-audit.py` (ADR 0138) | a scope-audit VIOLATION-t adna → `stopped`; jelen diffen OK |
| `requiredCapability` oszlop kivétele | reviewer szemrevételezés (§6.3) | a kétoszlopos lista jelen van; kivétel esetén a §6 3. cella piros |

## Leletek

- **NOTE-1 (nem blokkoló):** a baseline fejléce a „Forrásbaseline: `main` @
  `41a0b29`"-et jelöli, míg az aktuális `origin/main` `19c02eb` (PR #161, Sonnet-5
  orchestrátor-váltás). A #161 diffje kizárólag `tools/round-pipeline.sh`-t és
  egy pipeline-tesztet érint — **egyetlen baseline-mérés sem függ tőle**
  (pubspec, manifest, `lib/features/`, iOS plist változatlan), ezért a mért
  állítások érvényesek. Kozmetikai eltérés; a `41a0b29` az Epic 4 zárócommitja,
  amiből a bázis logikailag ered. Nem igényel javító kört.

## Döntés

0 OPEN BLOCKER/MAJOR/MINOR. **APPROVED** — merge a zöld exact-SHA CI
(`full-gate.yml` + `router-ci.yml` a `7a9d9e0` merge-SHA-n) után.
