# Codex Start Here — StrumSight

## Első munkamenet

A Codexnek ezt a sorrendet add:

1. Olvasd el a gyökér `AGENTS.md` fájlt.
2. Olvasd el a `docs/sdd/00-index.md` fájlt.
3. Olvasd el a `docs/sdd/01-architecture-engineering-principles.md` fájlt.
4. Olvasd el a `docs/sdd/02-epic-01-core-platform.md` fájlból kizárólag a Kör 1 részt és a fejezet közös szabályait.
5. Olvasd el a jelenlegi `HANDOFF.md`, `README.md`, `CLAUDE.md`, `pubspec.yaml` és CI workflow-k releváns részeit.
6. Vizsgáld meg a working tree állapotát.
7. Kizárólag a Kör 1-et hajtsd végre.
8. Futtasd a körben előírt ellenőrzéseket külön parancsokként.
9. Frissítsd a `HANDOFF.md` fájlt.
10. Adj tényszerű végrehajtási jelentést, majd állj meg.

## Másolható első prompt

```text
A wolfcasaba/strumsight repositoryban dolgozol.

Olvasd el sorrendben:
1. AGENTS.md
2. docs/sdd/00-index.md
3. docs/sdd/01-architecture-engineering-principles.md
4. docs/sdd/02-epic-01-core-platform.md
5. HANDOFF.md és a releváns jelenlegi kódot/teszteket

Hajtsd végre kizárólag:
Chapter 2 — Epic 1, Kör 1 — Repository baseline és Codex szabályrendszer.

Ne kezdd el a Kör 2-t. Ne módosíts DSP-paramétert vagy ML-súlyt. A meglévő működést őrizd meg. A teszteket külön parancsokként futtasd. Frissítsd a HANDOFF.md fájlt, majd jelentsd:
- módosított fájlok;
- megvalósított követelmények;
- futtatott parancsok és eredmények;
- nem futtatható ellenőrzések;
- kockázatok és következő pontos kör.
```

## Párhuzamos kör egy másik agenttel (bevált felállás, 2026-07-29)

A Codex és a Claude egyszerre vihet két KÜLÖN kört. A szabályok teljes listája:
[`AGENTS.md` §15](AGENTS.md). Röviden:

- **Saját klón, saját branch.** A Codex `/home/ubuntu/ss-codex-<kör>` klónban
  dolgozik (nem a közös working tree-ben), branch:
  `codex/epic-01-round-NN-<slug>`.
- **Indítás headless módban** (a bwrap sandbox ezen a gépen AppArmor miatt nem
  indul, ezért teljes hozzáférésű mód, dedikált klónban):

  ```bash
  codex exec -C /home/ubuntu/ss-codex-<kör> -s danger-full-access "$(cat <prompt>.md)"
  ```

- **A prompt mindig sorolja fel:** a kör pontos scope-ját, a saját fájlterületet,
  a másik agent TILTOTT területét, az előre kiosztott ADR-sorszámot, a gate-eket
  külön parancsokként, a CI-dispatchet és a megállási pontokat.
- **A `HANDOFF.md`-hez a Codex ilyenkor NEM nyúl** — a merge-ök után a másik
  agent rögzíti mindkét kört egyetlen `docs(handoff)` committal.
- **Merge-sorrend:** az alacsonyabb sorszámú kör előbb; utána a másik rebase-el
  `main`-re és újra lefuttatja a CI-t.
- **Csak fájlszinten diszjunkt körök** futhatnak együtt; kétség esetén sorban.

## Kötelező megállási pontok

A Codex álljon meg és jelentse a problémát, ha:

- a working tree-ben ismeretlen, nem hozzá tartozó változtatás van;
- a kijelölt körhöz szükséges fájl vagy contract hiányzik;
- secretet talál commitolt fájlban;
- a kért módosítás adatvesztést vagy irreverzibilis migrációt okozna;
- a teszt baseline már a módosítás előtt piros;
- a feladat DSP/ML outputot változtatna, de nincs előírt mérési gate;
- a kör túlnő egy review-zható PR-on.

Ilyenkor ne találgasson és ne kezdjen másik kört.
