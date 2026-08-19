# ADR 0321 — A `H-GATEGUARD` a KÖRT tartja vissza, nem a LÁNCOT

- **Státusz:** elfogadva (2026-08-19)
- **Kontextus:** ADR 0112 (önjavító lánc, „egyetlen emberi határ"), ADR 0138
  (mérce-őr hook), ADR 0309 (implementer-oldali gépi őrök), ADR 0087 (kör-sor)
- **Döntéshozó:** user-kérés 2026-08-19 („állítsd be úgy, hogy automatikusan
  tudjunk jól fejleszteni"), mérés alapján

## Kontextus — a MÉRT hibaosztály

Az `E99-R17` (GOV-11) kör három egymást követő halttal állította meg az egész
láncot (2026-08-19 05:31, 09:56, 10:38 UTC). A halt oka mindháromszor ugyanaz:

- a brief `allowed_paths` listáján ott állt a `tool/ci/check_l10n_parity.dart`,
- ezt a fájlt a `.claude/hooks/protect_factory_files.py` `PROTECTED_GLOBS`
  listája védi (`tool/ci/*`), és a MiniMax-oldali implementer-sessiont a
  `tools/hooks/implementer_guard.py` (ADR 0309) is blokkolja,
- a `.claude/gate-edit-authorized` marker **strukturálisan nem old fel**: az
  implementer-őr nem ismeri, a Claude-oldali sessiont pedig a harness saját
  auto-mode osztályozója is blokkolja (`docs/LESSONS.md` L322–L323).

Két, egymástól független baj rakódott egymásra:

1. **Tervezési hiba a briefben.** A kör dispatch ELŐTT eldőlt: olyan fájlt írt
   volna elő, amit egy autonóm session nem tud megírni. Ez az a hibaosztály,
   amit „az engedélyezett-fájllista a tervezőt is köti" tanulság tilt — csak
   eddig a teszt-fát néztük brief-íráskor, a védett listát nem.
2. **A halt hatóköre.** A `.pipeline/HALTED` jelzés GLOBÁLIS
   (`tools/round-pipeline.sh` §2), ezért egyetlen gate-érintő kör a sor MIND a
   37 nyitott körét megállította — köztük a tőle teljesen független E07/E08
   termék-munkát. Mérve: a lánc 05:31 és 10:40 között ~5 órán át nulla kört
   vitt előre, miközben 32 kör futásra kész volt.

A sorban ma **5 ilyen kör** van (gépi mérés, `tools/gateguard-scan.py --all`):
`E99-R17` (`tool/ci`), `E99-R20`, `E99-R21` (`tools/round-gate.sh` +
workflow), `E99-R22`, `E08-R29` (workflow).

## Döntés

**A mérce nem változik.** Az ADR 0112 emberi határa érintetlen: gate-érintő kör
autonóm sessionben nem fut le, és a védett fájlt továbbra is csak ember írhatja.
Ami változik, az kizárólag a halt **hatóköre**:

1. **Kör-szintű hold.** Ha a kör-session `H-GATEGUARD`-ot jelez, a driver a
   kör sorát `pending` → `hold`-ra írja (saját commit + push), archiválja a
   halt-fájlt (`.pipeline/gateguard-hold-<kör>-<bélyeg>.txt`), főkönyvet vezet
   (`.pipeline/gateguard-holds.tsv`), riaszt — és a lánc a következő pending
   körrel MEGY TOVÁBB.
2. **Az őrszem haltja LÁNC-szintű marad.** Ha a haltot az önjavítás fölötti
   őrszem írta (`attempt_selfheal`), a halt-fájl `gateguard_origin=selfheal`
   mezőt kap: ott a mércét gyengítő commit MÁR a main-en állhat, tehát a
   következő kör mércéje is romlott — az egész lánc áll. A megkülönböztetés
   gépi mező, nem szövegértelmezés.
3. **Pre-flight a dispatch előtt.** A driver a kiválasztott kör briefjét a
   `tools/gateguard-scan.py`-vel méri, ami a védett listát **magából az őrből
   importálja** (nincs második igazság-forrás). Ütközésnél a kör azonnal
   `hold`-ra kerül — implementer-futás és halt nélkül.
4. **Láthatóság.** A `tools/pipeline-status.sh` külön szakaszban sorolja fel
   az emberi gate-döntésre váró köröket és az utolsó öt automatikus holdot.

Kapcsolók (alap: bekapcsolva): `PIPELINE_GATEGUARD_AUTOHOLD=0`,
`PIPELINE_GATEGUARD_PREFLIGHT=0`.

## Következmények

- **Jó:** egyetlen emberi döntésre váró kör nem fagyasztja be a termék-láncot.
  A mai állapotban 32 kör szabadul fel 5 helyett.
- **Jó:** a gate-érintő körök egy helyen, géppel felsorolhatók
  (`tools/gateguard-scan.py --all`), így egy közös alkalommal, kötegben
  oldhatók fel — nem egyesével, halt-onként.
- **Ár:** a `hold` státusz emberi beavatkozás nélkül soha nem oldódik fel. Ez
  szándékos: a `hold` LÁTHATÓ (státusz + főkönyv + ntfy), szemben a csendes
  átugrással. A kör nem vész el, csak várakozik.
- **Ár:** egy gate-érintő kör felfedezése továbbra is egy firinget elvesz (a
  pre-flight után a driver kilép, a következő firing viszi a soron következő
  kört) — 5 perc, szemben a korábbi több órás lánc-megállással.

## A brief-írás szabálya (kötelező)

Kör-brief `allowed_paths` írásakor a teszt-fa mellett a **védett listát is** meg
kell nézni:

```bash
tools/gateguard-scan.py --brief docs/rounds/<új-brief>.md   # 0 = indítható
```

Ütközés esetén a brief nem indítható autonóm körként: vagy ki kell venni a
védett fájlt a kör hatóköréből, vagy a körnek emberi gate-lépést kell terveznie.

## Mérce

`tools/tests/test_gateguard_autohold.py` — a kör-szintű hold, az őrszem-halt
változatlan lánc-megállása, a kikapcsolhatóság, a nem-`pending` sor
érintetlensége, a hamis pozitívok hiánya és a sor jelenlegi állapota
(minden ütköző kör `hold`-on).
