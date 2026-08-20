# ADR 0372 — Gate-edit policy: a briefben ELŐRE nevesített mércemódosítás felhatalmazása

- **Státusz:** elfogadva (2026-08-20, user-döntés 2026-08-19: *„legyen ÁLLÓ felhatalmazás, hogy a mércét érintő körökhöz SOHA többé ne kelljen emberi kéz"*)
- **Kontextus-ADR-ek:** [`0112`](0112-self-healing-pipeline.md) (önjavítás, §3 emberi határ), [`0138`](0138-factory-hardening-scope-guard-and-independence.md) (`H-GATEGUARD`), [`0309`](0309-implementer-machine-guards.md) (hook-réteg, §4.1 ismert rés)

## 1. Probléma

A mércét (`tools/round-gate.sh`, `tool/ci/*`, `.github/workflows/*`, a router
biztonsági rétege, maga az őr) az nem javíthatja, akit mér — ez az ADR 0112 §3
egyetlen emberi határa, és jó okkal áll fenn: enélkül egy kör a saját mércéjét
gyengítve válna „zölddé".

A gyakorlatban viszont **legitim** körök is a mércét bővítik: új gate-lépés, új
CI-útvonalszűrő, új őrteszt. Ezek ma mind megállnak:

- a dispatch ELŐTTI pre-flight (`tools/gateguard-scan.py`,
  `round-pipeline.sh` §4.1) a sorban `hold`-ra teszi a kört;
- a futásidejű hook (`.claude/hooks/protect_factory_files.py`) blokkolja az írást.

Mérve 2026-08-20: **két kör** (`E99-R21`, `E08-R29`) áll emiatt hold-ban, és az
`E99-R17` ugyanezért igényelt kézi user-commitot.

A meglévő két escape **hatókör nélküli**: a `STRUMSIGHT_GATE_EDIT_OK=1` env és a
`.claude/gate-edit-authorized` marker jelenléte MINDEN védett útvonalat felold
MINDEN ott futó sessionnek. Az env ráadásul futó sessionben nem is állítható be
(L117), a marker pedig gitignore-olt, tehát friss munkapéldányba sosem kerül be
(L323 utólagos mérése).

## 2. Döntés

A felhatalmazás nem kapcsoló, hanem **előre papírra tett szándék**. A védett
útvonal írása akkor és csak akkor engedett, ha **mind a három** teljesül:

1. létezik a **KÖVETETT** `.claude/gate-edit-policy` fájl (a user álló döntése;
   a törlése a visszavonás — az őr azonnal fail-closed lesz);
2. implementer-körben vagyunk (`STRUMSIGHT_ROUND_BRIEF` be van állítva);
3. a cél a kör briefjének `allowed_paths` listáján **PONTOS egyezéssel**
   szerepel — a briefet **immutábilis forrásból** (a kör bázis-commitjából)
   olvassuk, nem a munkafából.

A pre-flight ugyanezt a kulcsot használja: **pontos fájl-egyezés** nem ütközés,
**szülő-könyvtár vagy glob** találat továbbra is fel nem oldható ütközés.

## 3. Amit ez a döntés NEM enged meg

- **ad-hoc**, a briefben nem nevesített mércemódosítást (ez a lényegi különbség
  a régi, hatókör nélküli markerhez képest);
- **titok-útvonalat** (`SECRET_GLOBS`) — arra semmilyen felhatalmazás nem érvényes;
- **prefix/könyvtár-illesztést** pontos egyezés helyett (egy `tool/` bejegyzés
  nem oldhatja fel az egész `tool/ci/*`-ot);
- a **munkafából** olvasott brief alapján adott engedélyt — mérve **226 / 254**
  brief listázza saját magát az `allowed_paths`-án, és a `docs/rounds/**` nincs
  védve, tehát a munkafa-olvasás önfelhatalmazást tenne lehetővé.

## 4. Változatlan védőháló

`tools/scope-audit.py` · független review (risk=high esetén kötelező
`security-reviewer`) · `tools/round-gate.sh` + Full Gate + Router CI a kör ágán ·
zöld kapus squash-merge. A felhatalmazás azt mondja meg, **mit szabad
megpróbálni**, nem azt, hogy **mi mehet be**.

## 5. Következmény

A `hold`-ban álló körök (`E99-R21`, `E08-R29`) a policy bevezetése után pusztán
a sor-státusz `pending`-re állításával elindulnak. Az egyszeri bootstrapre
(magának az őrnek az első módosítására) még kell egy emberi aktus — ezt a kör
briefje (`E99-R23` §0.2) írja le, és a DoD gépi bizonyítékot kér a
bootstrap-marker törléséről.
