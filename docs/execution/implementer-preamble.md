# Implementer-preambulum — MÉRT hibaminták tiltása (ADR 0173)

> Ezt a szöveget a `tools/codex-round.sh` fűzi MINDEN Codex-harness kör
> feladata elé. Nem stílus-tanács: minden pontja egy megtörtént, naplóból
> visszakereshető kör-bukás.

## 1. A forduló a JELZÉSSEL ér véget, nem a bejelentéssel

Tilos a fordulót azzal zárni, hogy elmondod, mi lesz a következő lépés
(„Now the action confirmation service…", „First Flutter compile is slow —
waiting for the run to finish"). Ha van még hátra munka, **csináld meg**;
ha nincs, **jelezz**. A bejelentés nem munka.

Mérve: E04-R13, E04-R14 és az E04-R16 mindkét kísérlete pontosan így ért véget
— félkész fákkal, jelzés nélkül. Ez körönként egy teljes újraindítás ára volt.

**A Bash-eszköz saját `run_in_background: true` kapcsolója UGYANEZ a hiba,
csak eszköz-szinten.** Ez a session EGYETLEN fordulóban fut (`claude -p`): ha
a kötelező gate-parancsot (`round-gate.sh`, `pytest`) háttérbe küldöd, és a
válaszod azzal zárod, hogy majd jelentkezel / megvárod, amíg befejeződik —
nincs „majd". A folyamat a forduló végén (`end_turn`) kilép, és ezzel a
háttér-feladatot IS megöli, mielőtt bármi eredmény visszajutna hozzád; az a
`task_notification`, amit erre normál, interaktív munkamenetben kapnál, ebben
az egy-fordulós harnessben SOSEM érkezik meg. Kötelező gate-parancsot ezért
MINDIG előtérben (a `run_in_background` paraméter NÉLKÜL) futtass, és a
válaszát blokkolva várd meg, mielőtt a fordulót lezárod. Ugyanez az elv más
hívó eszköz kontextusában már bizonyítva: `docs/LESSONS.md` L183.

Mérve: E99-R08 — két egymást követő `sonnet-impl` javító kör (session
3f71b1fb-ee86-4206-b9a6-6f802768f679, majd a második, folytató futás
665d8491-3352-416f-9ac8-f420c4936468) a kötelező `python3 -m pytest
tools/tests -q` gate-et küldte háttérbe, majd „I'll report back once it
completes" bejelentéssel zárt jelzés és commit nélkül. Mindkettő exit 0-val
`status=unknown`-ba halt, és a lánc emiatt H6 halt-ot jelzett (ADR 0087 §2).

## 2. Commitolj lépésenként, ne a végén egyszer

Minden elkészült fájl után:

```bash
git add -A && git commit -m "<kör>: <mit>"
```

Miért: a token-keret bármikor elfogyhat (E04-R13: két futás halt így), és a
nem commitolt munka ilyenkor elvész. A commitolt munka a folytatás alapja.
**Új fájlt is `git add`-elj** — a review egyszer már öt untracked
production-fájlt talált (E04-R13/F3).

## 3. A záró sorrend kötött

1. a kör gate-je (artefaktum, csonkítás nélkül — `| tail`, `| head`, `&&` tilos);
2. **backend-et is érintő kör**: `backend/.venv/bin/python -m ruff format app tests`
   (az ellenőrzés `--check`-kel a gate-ben van; a formázást neked kell lefuttatni);
3. `git add -A && git commit`;
4. `tools/codex-signal.sh done|stopped|blocked "<egy soros összegzés>"`.

Mérve: E04-R15 MAJOR-1 — a `ruff check` zöld volt, a `ruff format --check`
piros, és ez CI-piros + egy teljes javító kör lett.

## 4. Ne térj el a feladattól

Nincs csomagtelepítés (`pip install`, `apt`, `npm i`), nincs eszközkeresés,
nincs „inkább előbb felderítem az egész repót". A brief §0.0 szakasza a mért
aláírásokat MÁR tartalmazza — abból dolgozz. Ami nincs a kör engedélyezett
fájllistáján, ahhoz nem nyúlsz: ütközésnél `stopped` jelzés és megállás.

Mérve: a qwen3.8-max füst-tesztje egy pytest-telepítéssel kezdett, mielőtt
bármit írt volna.

## 5. Ha elakadsz, azt is jelezni kell

Valódi akadálynál (hiányzó előfeltétel, ellentmondó brief, nem feloldható
függőség) a helyes befejezés `stopped` vagy `blocked` **egy soros, konkrét
összegzéssel** — nem a néma kilépés. A néma kilépést a burkoló automatikus
folytatással próbálja megmenteni, de az a te köröd idejéből megy el.
