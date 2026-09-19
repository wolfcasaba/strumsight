# E14-R24 — Strum release-kapu fokozatok és kontrollált rollout

- **Státusz:** LESZÁLLÍTVA (mechanizmus) / **PARTIAL** (a Beta számok mérése hiányzik)
- **ADR:** [`0537`](../adr/0537-gate-stages-and-clamped-rollout.md)
- **Csomag:** PKG-B · **Készült:** 2026-09-09
- **Doksi:** [`docs/eval/release-gate-stages.md`](../eval/release-gate-stages.md)

## 1. Cél

A release-kapu tudjon **fokozatokat** (Alpha/Beta) és **sávokat**
(strum/chord/shared), a Ch14 §7.3 Beta célok legyenek verziózottan a fán
**letiltva**, és egy rollout-zászló **soha ne léphesse túl** azt, amit a kapu
engedélyez.

## 2. Mért kiindulóállapot

- 10 Alpha küszöb a `recognition_release_gate.json`-ban; a §7.3/§7.5 Beta
  célok sehol.
- PKG-D már leszállította a `RecognitionRolloutStage` létrát
  (`off → shadow → alpha → beta → ga`, ADR 0542) és a két `FeatureFlags`
  mezőt, de **semmi nem köti a fokozatot a kapu verdiktjéhez**.
- A legacy baseline megbukik az Alpha kapun (chord 0,671 · onset F1 0,674).

## 3. Scope

BENNE: `stage`/`band`/`enabled` opcionális mezők a küszöb-soron; a verdikt
csak az engedélyezett sorokra épül; determinisztikus rendezés duplikált
metrika-út mellett; a §7.3 Beta sorok letiltva; rollout-létra + clamp;
riport-renderelés (`INFO (above/below target)`).

KÍVÜL: az Alpha sorok értéke (változatlan); a feature-flag registry (PKG-D);
a `tool/recognition_report.dart` CLI (tiltott zóna — a séma additív, így a
CLI változtatás nélkül tovább működik).

## 4. Fájlok

Módosított:
- `lib/features/live/domain/evaluation/recognition_release_gate.dart`
- `lib/features/live/data/evaluation/recognition_report_renderer.dart`
- `evaluation/recognition/recognition_release_gate.json`
- `test/features/live/evaluation/recognition_release_gate_test.dart`

Új:
- `lib/features/live/domain/evaluation/rollout_licence.dart`
- `test/features/live/evaluation/rollout_licence_test.dart`
- `docs/eval/release-gate-stages.md`

## 5. Frissített meglévő teszt-cella (kimondva)

`recognition_release_gate_test.dart` „carries exactly the Ch14 §7.2/§7.4
Alpha values” cellája eddig a fájl **teljes** metrika-út listáját pinnelte.
Mostantól a **`stage: alpha`** sorokra szűr (ez a 10 sor, változatlan
értékekkel), és külön ellenőrzi, hogy mind engedélyezett. A Beta sorokat a
`rollout_licence_test.dart` pinneli. A cella nem gyengült: több
állítást tesz, mint korábban.

## 6. Acceptance

| # | Kritérium | Állapot |
|---|---|---|
| 1 | Hiányzó metrika = FAIL (nem „nincs adat = PASS”) | **PINNED-BY-TEST** (meglévő + rollout-teszt) |
| 2 | Az Alpha sorok értéke és élessége változatlan | **PINNED-BY-TEST** |
| 3 | Letiltott sor nem buktat, de nem is engedélyez | **PINNED-BY-TEST** |
| 4 | Duplikált metrika-út determinisztikusan rendeződik | **PINNED-BY-TEST** |
| 5 | A rollout-fokozat nem lépheti túl a kaput; csak csökkenthet | **PINNED-BY-TEST** |
| 6 | Ismeretlen fokozatnév → `off` | **PINNED-BY-TEST** |
| 7 | A szállított fájllal `beta` elérhetetlen | **PINNED-BY-TEST** |
| 7b | A `LicensedRolloutStage` névtükör egyezik PKG-D létrájával | **PINNED-BY-TEST** |
| 8 | Ismeretlen `stage`/`band` = tipizált hiba | **PINNED-BY-TEST** |
| 9 | Bármely Beta küszöb tényleges teljesülése | **NEEDS-MEASUREMENT** |
| 10 | Rollback-gyakorlat, subgroup-regresszió hiánya | **NEEDS-MEASUREMENT** (ember + eszköz) |

## 7. Verifikáció

Lokális gate nem futtatható; a mérce a `full-gate.yml`. A megírt cellák
felsorolva a §6-ban; sikeres futás nincs állítva.

## 10. Handoff

- **PKG-D:** a két mező (`strumModelRolloutStage`, `chordModelRolloutStage`)
  és a `RecognitionRolloutStage` létra már a fán van, alapértéke `off` —
  ez a kör ehhez igazodott, nem kér változtatást. Az evaluation réteg
  névtükröt tart (`LicensedRolloutStage`), teszttel pinnelve; import egyik
  irányban sincs.
- **PKG-E/PKG-F:** a rollout-fokozatot mindig a `clampRolloutStage(...)`
  kimenetéből olvassa (a flag `.name`-jét átadva), sosem közvetlenül a
  zászlóból. A `shadow` fokozatot a pontossági kapu nem engedélyezi és nem
  is tiltja — azt a shadow-főkapcsoló őrzi (ADR 0542 D2).
