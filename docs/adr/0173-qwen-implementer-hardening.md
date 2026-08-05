# ADR 0173 — A Qwen implementer mért gyengeségeinek gépi ellenszerei

**Státusz:** elfogadva (2026-08-05, user-döntés: „vizsgáld meg a Qwen fejlesztését
az előzmények alapján … hozzuk ki belőle a legjobbat"; a gate bővítését a user
külön, kifejezetten engedélyezte — H-GATEGUARD).

Kiegészíti az [ADR 0069](0069-two-engine-implementer-pool.md) (két motor),
[ADR 0138](0138-factory-hardening-scope-guard-and-independence.md) (scope-őr,
jelzési szerződés) és [ADR 0140](0140-switchable-implementer-engine-profiles.md)
(motor-profilok) döntéseit.

## Kontextus — mit csinált eddig a Qwen, és hol bukott

A Qwen-család 2026-08-04 óta az implementer (`~/.codex-kilo` profil,
Codex-harness). Az azóta lezárt/futó körök naplóiból:

| Kör | Motor | Kimenet | Mért hiba |
|---|---|---|---|
| E04-R13 | qwen-plus | APPROVED, 0 BLOCKER/MAJOR a review-ban | **kétszer** jelzés nélkül halt (token-kimerülés); a review 5 **untracked** production fájlt talált (F3), és hiányzó „rajta"-küszöb cellákat (F2) |
| E04-R14 | qwen-plus → qwen-coder-plus | önjavító körrel zárult | az implementer **bejelentette** a hátralévő fixture-javításokat, de nem hajtotta végre; motorváltás kellett |
| E04-R15 | qwen38-max | APPROVED, **2 javító kör** | MAJOR-1: `ruff check` zöld, **`ruff format --check` piros** → Backend CI piros |
| E04-R16 | qwen38-max | 2 kísérlet | mindkettő úgy ért véget, hogy a modell a következő lépést **bejelentette** („Now the action confirmation service…"), majd a harness kilépett |

Három visszatérő minta, egyik sem képességbeli:

1. **„Bejelent és kilép".** A modell záró üzenetet küld tool-hívás helyett; a
   `codex exec` erre kilép. A munka félkész, jelzés nincs, és eddig ez egy
   teljes kör-újraindítás volt (az E04-R16 orchestrátora ezért már kézzel írt a
   promptba figyelmeztetést — kézi kompenzáció, nem mechanizmus).
2. **Gondolkodás nélkül futott.** A futó session fejlécében mérve:
   `reasoning effort: none`. Egy $2/$6 per 1M tokenes modellt gondolkodási
   szint nélkül használtunk, mert a Kilo-profil nem adta át a paramétert.
3. **A backend-mérce csak a CI-ban futott.** A lokális gate Dart-only volt,
   ezért a Python-oldali formázás/teszt hibák a merge-kapunál derültek ki —
   körönként egy javító kör árán.

## Döntés

### §1 Automatikus folytatás ugyanabban a session-ben

`tools/codex-round.sh`: ha a forduló **magától** ért véget terminális jelzés
nélkül, a burkoló a Codex fejlécéből kiolvasott `session id`-vel
`codex exec resume <id>` hívással folytatja, imperatív prompttal („ne tervezz,
ne jelents be — írd meg, commitold, futtasd a gate-et, jelezz").

* legfeljebb `CODEX_MAX_CONTINUATIONS` (alap **2**) folytatás;
* a kör **globális** határideje nem nyílik újra (a folytatás a maradékból megy);
* **kilövés után nincs folytatás** (elakadás/időtúllépés esetén a tény a
  kilövés — a folytatás elfedné);
* ha a folytatás nem termel kimenetet, azonnal megáll;
* a jelzésfájl `continuations=` és `session_id=` mezőt kap: a reviewer LÁTJA,
  hány szakadás volt — egy két folytatással elért `done` nem ugyanaz a
  bizonyíték, mint egy egy fordulóban lezárt kör.

MÉRT alap: a `codex exec resume` megőrzi a kontextust (füst-teszt 2026-08-05:
a folytatás ismerte az előző forduló fájljait), tehát ez **továbbvitel**, nem
újrakezdés.

### §2 Implementer-preambulum artefaktumként

`docs/execution/implementer-preamble.md` — a burkoló MINDEN Codex-harness
forduló feladata elé fűzi. Öt pontja mind megtörtént bukásra hivatkozik:
a forduló csak jelzéssel ér véget; commitolj lépésenként (`git add` az új
fájlokra is); kötött záró sorrend (gate → `ruff format` → commit → jelzés);
ne kalandozz (nincs csomagtelepítés, nincs listán kívüli fájl); elakadásnál is
jelezni kell. A tiltás így nem körönként újraírt prompt-szöveg, hanem
verziózott, review-zható artefaktum.

### §3 Gondolkodási szint motoronként

Az `engine-registry.tsv` új `reasoning` oszlopa (13.), amit a burkoló
`-c model_reasoning_effort=<érték>`-ként ad át. `-` = ne adjunk át semmit
(a provider defaultja marad, ez a visszakapcsolás útja).

Mérve: `qwen38-max` + `medium` → a provider elfogadja, a füst-teszt sikeresen
szerkesztett. A többi motor `-` marad, amíg nincs saját mérésünk — a
nyilvántartásba csak MÉRT érték kerül.

### §4 Backend sáv a lokális gate-ben

`tools/round-gate.sh`: ha a kör hozzáért a `backend/`-hez, a gate lefuttatja a
Backend CI három lépését is — `ruff format --check`, `ruff check`, `pytest`.
Nincs kikapcsoló: az a mérce gyengítése lenne. Hiányzó venv esetén
`environment_failure` (fail-closed) a `backend/README.md` receptjével — a
mérhetetlen mérce nem lehet zöld. A munkapéldányokban a fő repó venv-je is
elfogadott (`ROUND_GATE_BACKEND_PYTHON`), mert az interpreter csak a
függőségeket adja; a mért fájlok a munkapéldányból jönnek.

> Ez a gate BŐVÍTÉSE. A H-GATEGUARD őr blokkolta a szerkesztést, és a user
> kifejezetten engedélyezte (marker: `.claude/gate-edit-authorized`). Szigorítás,
> nem lazítás: egyetlen meglévő lépés sem tűnt el.

### §5 Az ADR-foglaló lássa a futó körök ágait is

`tools/round-slots.py reserve-adr` mostantól a `git log --all` alapján a
**bármely ágon** létrehozott ADR-számokat is foglaltnak veszi. MÉRT rés: az
E04-R16 a saját ágán már lefoglalta a 0172-t, de a `main`-en az még nem
létezett — a lemez-alapú foglaló ugyanazt a számot adta volna ki másodszor is
(a 0139-es duplikátum hibaosztálya, egy fázissal korábban).

## Miért nem gyengül ettől semmi

`tools/tests/test_qwen_implementer_hardening.py` (13 teszt) + a bővített
`test_engine_profile.py` és `test_pipeline_throughput.py`:

| Kockázat | Őr |
|---|---|
| a folytatás elfedne egy valódi elakadást | teszt: kilövés (`timeout`) után SOHA nincs resume |
| a folytatás korlátlanná válik | teszt: `continuations=2`-nél megáll, és a jelzés jelenti |
| a folytatás új session-t nyitna (kontextusvesztés) | teszt: a `resume` a naplóból olvasott session-id-vel megy |
| a preambulum elveszik | teszt: minden forduló promptjában ott van; a tartalma mért kör-azonosítókra hivatkozik |
| a reasoning tetszőleges stringgé válik | teszt: csak `-|minimal|low|medium|high` |
| a backend sáv némán kimarad | teszt: hiányzó venv → `environment_failure`, nem „skip" |
| a backend sáv Dart-only körre is költene | teszt: nem hívja a Python-t |

## Következmények

* A `done` jelzés mostantól kontextusfüggő: `continuations=0` és
  `continuations=2` nem ugyanaz a bizonyíték — a review-nak nézni kell.
* Az orchestrátornak nem kell körönként kézzel figyelmeztetnie a „bejelent és
  kilép" mintára; ha mégis teszi, az duplikáció, nem hiba.
* A backendet érintő körök lokális gate-je hosszabb lett (pytest), cserébe a
  javító kör + CI-kör ára megspórolható.
* Visszakapcsolás: `CODEX_MAX_CONTINUATIONS=0`, `CODEX_NO_PREAMBLE=1`,
  `reasoning` oszlop `-`-ra állítása.

## Következő mérés (nyitott)

A `reasoning = medium` hatását a következő 3 körön mérjük össze a korábbi
adatokkal (`tools/round-metrics.py` kör-idő + a review javító-kör száma). Ha a
`medium` nem hoz mérhető javulást, `-`-ra állítjuk; ha igen, a `qwen-plus` és
`qwen-max` sorokat is meg kell mérni.
