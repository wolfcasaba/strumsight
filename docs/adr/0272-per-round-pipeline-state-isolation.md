# ADR 0272 — Párhuzamos körök: a kör-állapot kör-kulcsolt

**Státusz:** elfogadva (2026-08-15, user-döntés: „csináld meg, hogy fusson
párhuzamosan"). A `PIPELINE_SLOTS>1` működésének feltétele.
Épít: [ADR 0171](0171-pipeline-throughput-program.md) §1 (párhuzamos slotok,
diszjunktság-ellenőrzés), [ADR 0087](0087-autonomous-round-pipeline.md).

## Kontextus — az első párhuzamos firing egy kört némán késznek hazudott

2026-08-15-én a `PIPELINE_SLOTS=2` első éles firingje után az `E14-R01` a
sorban **`done`** lett, miközben **semmi nem épült meg belőle**: nulla
recognition flag, nincs `docs/eval/recognition-release-guard.md`, és **nincs
PR** hozzá (a merge-eltek mind Epic 7-esek voltak).

Az áruló jel: az `E14-R01` merge-értesítése **szó szerint az `E07-R04`
összefoglalója** volt.

**Mért gyökér-ok.** A kör-állapot egyetlen GLOBÁLIS fájlban élt:

```bash
status_file="$state_dir/round-status"
```

A driver ezt törli dispatch előtt, a session ide írja az `outcome`-ot, és a
driver innen olvassa. Két párhuzamos driver ugyanazt a fájlt használta.

**Fontos, amit a hiba NEM érintett:** a slot-választás végig helyes volt — a
`tools/round-slots.py check` mérve diszjunktot adott a két körre. Az ADR 0171
§1 diszjunktság-garanciája működött; a hiba a kör-**állapot** megosztásában
volt.

## Döntés

### 1. A kör-állapotfájl kör-kulcsolt

`$state_dir/round-status-<kör>`, egyetlen feloldó függvényből
(`round_status_file_for`). Két slot nem láthatja egymás eredményét.

### 2. Egy helyen dől el az útvonal

A driver, a teszthorog és a `tools/pipeline-status.sh --mark-halt` **ugyanazt
a függvényt** használja. Ha a két oldal elcsúszna, a router halt-átadása némán
elveszne, és a driver a valódi halt helyett `H-NOSIGNAL`-t adna.

### 3. A viselkedés futtatható artefaktummal mérhető

`tools/round-pipeline.sh --status-file-for <kör>` — a teszt a tényleges
feloldást méri, nem a forrásszöveget (`docs/LESSONS.md` L09).

### 4. A legacy `round-status` megmarad, kettős írással

Több eszköz és teszt olvassa „az utolsó kör állapota" jelentéssel. A
`--mark-halt` mindkét helyre ír: a kör-kulcsolt fájlba (a driver ezt olvassa)
és a legacybe (kompatibilitás).

### 5. A javítás a MÉRT hibára szorítkozik

A `router_status_file` **nem** lett kör-kulcsolt. Mérve annak több fogyasztója
van (`ai-router-round.sh` a fájl *dirname*-jéből vezeti le az
állapotkönyvtárat; `pipeline-status.sh` külön definiálja), és nem az volt a
mért hiba. Az első, tágabb javítási kísérletet két meglévő teszt
(`test_router_h4_handoff`) fogta meg — helyesen.

## Következmények

- A `PIPELINE_SLOTS=2` biztonságosan használható; a box RAM-fedezete mérve
  elbírja (`--effective-slots 2` → 2).
- A néma hamis-lezárás hibaosztályát teszt őrzi
  (`tools/tests/test_per_round_status_isolation.py`).
- Minden további megosztott, nem kulcsolt pipeline-állapot gyanús: a
  párhuzamosítás első számú buktatója nem a munkamegosztás, hanem a közös
  állapot.

## Mérce

`tools/tests/test_per_round_status_isolation.py` öt cellája, benne a
valódi-sértés próbával: a globális fájlra visszaállítva a tesztnek pirosnak
kell lennie. Merge előtt mérve: 447 passed, 446 subtests.
