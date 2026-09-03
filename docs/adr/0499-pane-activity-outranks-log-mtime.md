# ADR 0499 — A panel élő állapota ELŐBBRE való a napló mtime-jánál

- **Státusz:** elfogadva (2026-09-03)
- **Kontextus:** ADR 0498 (ébresztő-beküldés és 529-ablak), HEAL E13-R14
  (elakadás-ébresztő), ADR 0087 (halt-protokoll)
- **Döntéshozó:** mérés (2026-09-03 14:51–15:13), a saját ADR 0498 D2 regressziója

## Kontextus — a saját javításunk lőtt bele a dolgozó körökbe

Az ADR 0498 D2 a felismert API-túlterhelésre rövid (120 mp) ébresztési ablakot
adott. A mérés szerint ez **hamis riasztást** termel, és a hamis riasztás ára
súlyosabb, mint az eredeti probléma:

```
14:51:42  ELAKADÁS-ÉBRESZTŐ (3/12): a(z) E15-R12 panelje 2 perce néma…
14:57:13  ELAKADÁS-ÉBRESZTŐ (4/12): …
15:02:45  ELAKADÁS-ÉBRESZTŐ (5/12): …
```

Ugyanebben az ablakban a panel ezt mutatta:

```
  ⎿  Running… (5m 54s · timeout 10m)
✢ Baking… (10m 32s · ↓ 4.6k tokens)
  ⏵⏵ bypass permissions on … · esc to interrupt
```

Vagyis a kör **dolgozott**. Két, egymást erősítő ok:

1. **A napló mtime-ja befagy egy hosszú forduló alatt.** A `pipe-pane` a panel
   KÉPÉT írja; amíg egy parancs fut, a kép nem változik, tehát nincs új bájt.
   A „néma napló" nem jelent tétlen sessiont.
2. **A 529-minta megragad a napló végében.** A felismerés a napló utolsó
   8000 bájtját nézi — abban a helyreállás után is ott marad a korábbi hiba,
   így a rövid ablak VÉGLEG bekapcsolva marad a session hátralévő életére.

A következmény kétféle kár: a dolgozó fordulóba küldött folytatás-prompt egy
fölösleges user-turnt fűz a körhöz, a keret kimerülése után pedig a driver
**megölte volna a dolgozó kört** (`break` → `H-NOSIGNAL` → önjavítás).

## Döntés

**D1 — A nudge/kill döntés előtt a driver megkérdezi a PANELT.**
`pane_is_working()`: a `tmux capture-pane` kimenetében ott van-e a
`PANE_ACTIVITY_PATTERN` (alap: `esc to interrupt`) — ez a CLI saját,
megszakítást kínáló állapotjelzője, tehát pontosan akkor látszik, amikor egy
forduló fut. Ha igen, a pillanat **aktivitásnak** számít (`last_activity_at`),
és az elakadás-referencia ezzel is előre tolódik. Sem ébresztés, sem ölés.

A napló mtime-ja megmarad **másodlagos** jelnek: ha a panel nem elérhető
(nem interaktív harness, halott pane), a régi viselkedés él változatlanul.

**Amit ez NEM változtat:** a 120 mp-es ablak, a 12-es keret és a terminális
`break` ág marad. A hamis riasztás forrása nem a küszöb volt, hanem az, hogy
rossz dolgot mértünk.

## Mérce

`tools/tests/test_nudge_submit_and_overload.py::PaneActivityGuardTest` — a MÉRT
dolgozó panel (`Baking… (10m 32s)` + `esc to interrupt`) aktívnak számít, a
529 utáni üres panel nem, és a forrás-szintű cella rögzíti, hogy a próba
MEGELŐZI a küszöb-döntést. A javítás előtti fán 2 cella PIROS.

## Következmények

- A hosszú, több tíz perces fordulók (nagy gate-futás, sok fájl) többé nem
  minősülnek elakadásnak.
- A 2026-09-03-i tanulság általánosan: **egy „elakadt-e" kérdésre a
  legközvetlenebb élő jelet kell megkérdezni, nem a legkényelmesebbet.** A
  napló mtime-ja azért volt csábító, mert olcsó — és azért volt rossz, mert
  nem arról szól, amit tudni akartunk.
