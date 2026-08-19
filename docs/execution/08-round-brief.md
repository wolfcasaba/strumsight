# Kör-brief (Round Brief) — sablon és szabály

A **kör-brief** a Claude tervezői kimenete és a Codex implementációs szerződése
([ADR 0055](../adr/0055-agent-role-protocol.md), `AGENTS.md` §15).

**Hely:** `docs/rounds/eXX-rYY-<slug>.md`
**Commitolva a kör indítása ELŐTT.** Ha nincs brief, a kör nem Ready
(`03-definition-of-ready.md`).

A legfontosabb szekció az **engedélyezett fájlok** listája: ez teszi a
scope-tágulást objektíven ellenőrizhetővé a review-ban (`git diff --stat` a
listával összevetve), a korábbi, sessionnel elszálló prompt-megállapodás
helyett.

---

## Sablon

```markdown
# EXX-RYY — <cím>

Státusz: PLANNING | IN PROGRESS | IN REVIEW | DONE
SDD: docs/sdd/<fejezet>.md §<szakasz>
Branch: codex/eXX-rYY-<slug>
Brief szerzője: Claude · Implementáció: Codex

## 1. Cél

Egy bekezdés: mi a kör kimenete, és miért most.

## 2. Jelenlegi állapot

A ténylegesen elolvasott kód alapján — ne a dokumentációból feltételezve.
Fájlnevek és a mai viselkedés.

## 3. Scope

**Benne:**
- ...

**Kívül (ebben a körben TILOS):**
- ...

## 4. Engedélyezett fájlok

Csak az alábbi útvonalak módosíthatók. Bármi más → MEGÁLLÁS és jelentés.

| Útvonal | Miért |
|---|---|
| `lib/...` | ... |
| `test/...` | ... |

**Tilos zóna** (a másik ágens területe vagy scope-on kívül): `...`

Közös fájlba (pl. `lib/core/foundation/app_failure.dart`) csak a kör saját
szekciójába szabad írni.

> **ÚJ fájl létrehozása is scope-sértés, ha nincs a listán — akkor is, ha
> „csak teszt".** Ha a körhöz új fájl kell, a helyes lépés a `stopped` jelzés
> és listabővítés kérése, nem a néma létrehozás.
> *Mért eset:* E02-R07 javító kör, 456 soros új tesztfájl az explicit tiltás
> ellenére ([`docs/reviews/e02-r07-review.md`](../reviews/e02-r07-review.md) §7.3).

> **KÖTELEZŐ pre-flight a listára ([ADR 0321](../adr/0321-gateguard-round-hold-not-chain-halt.md)):**
> ```bash
> tools/gateguard-scan.py --brief docs/rounds/<ez-a-brief>.md   # 0 = indítható
> ```
> Ha a lista védett fájlt tartalmaz (`tools/round-gate.sh`, `tool/ci/*`,
> `.github/workflows/*`, `tools/ai_router/*`, `schemas/*`, `.claude/hooks/*`),
> a kört **autonóm session nem tudja végrehajtani** — sem markerrel, sem
> újrapróbálással ([`LESSONS.md` L322–L324](../LESSONS.md)). Ilyenkor vagy ki
> kell venni a védett fájlt a kör hatóköréből, vagy emberi gate-lépést kell
> terveznie; a driver az ilyen kört a dispatch előtt `hold`-ra teszi.
> *Mért eset:* E99-R17, három halt ugyanazzal a gyökérokkal, ~5 óra lánc-leállás.

## 5. Kötött architekturális döntések

Amit a kör NEM tervezhet újra. Új ADR nélkül nem térhet el tőle.
Előre kiosztott ADR-szám: `00NN`.

### 5.1 Nyitott döntések — előre rögzített feloldással ([ADR 0138](../adr/0138-factory-hardening-scope-guard-and-independence.md))

A brief ne REJTSE el a bizonytalanságot, de ne is állítsa meg vele a láncot.
Minden olyan kérdéshez, amiről tudod, hogy az implementer bele fog ütközni,
adj **előre rögzített feloldási politikát** — így a kör nem `stopped`-dal kér
döntést, hanem a dokumentált default szerint megy tovább.

A mért indok: az E02-R11 **kétszer** állt meg valós, blokkoló ellentmondáson
(ADR 0087 „Kontextus"), és mindkét feloldás ítélet volt, nem szabályalkalmazás.
Amit előre el tudsz dönteni, azt előre döntsd el.

```yaml
open_decisions:
  - id: OD-01
    question: A validátor ismeretlen mezőre dobjon, vagy némán hagyja el?
    blocking: true
    resolution_policy: use_default     # use_default | stop_and_ask
    default: fail-closed — ismeretlen mező ValidationFailure
```

- `resolution_policy: use_default` → az implementer a `default` szerint jár el,
  és a §10 handoffban rögzíti, hogy élt vele.
- `resolution_policy: stop_and_ask` → ez tudatosan halt-pont; csak akkor
  válaszd, ha a rossz döntés több körön át beépülne.
- **Blocking döntés `resolution_policy` nélkül nem mehet ki a briefben.**

## 6. Acceptance criteria

- [ ] Mérhető, ellenőrizhető állítások — nem „jól működik".

Három kötelező elem, mind mért hibából
([`docs/LESSONS.md`](../LESSONS.md) L09, L10, L01):

1. **Az invariánsnál mondd ki a NEM elfogadható gyengítést is**, ne csak az
   elfogadhatót — különben az implementer jóhiszeműen, kódkommentben
   megindokolva fellazítja a mércét, hogy a kód átmenjen rajta.
   *Példa:* „minden elfogadott lépésre az `(előző, új)` **pár** szerepeljen a
   táblában; **a tranzitív lezárt NEM elfogadható mérce**."
2. **Ha a mérés technikai akadályba ütközik, add meg az ESZKÖZT is** hozzá —
   különben a mérce lazítása marad az egyetlen kiút.
   *Példa:* ha egy tick több átmenetet láncolhat, a brief írja elő a bejárt
   statusok visszaadását (`statusPath`), és arra mérjen.
3. **Paraméteres szerződéshez MÁTRIXOT írj elő, ne egy esetet.** A fixture
   default-ja csendesen kiválaszthat egy olyan pontot, ahol a hibás és a helyes
   implementáció megkülönböztethetetlen.
   *Példa:* „`countInBars ∈ {0,1,2,4}` × `Meter ∈ {4/4, 3/4}`" — E02-R07-ben a
   `countInBars: 1` default miatt 11 zöld teszt mellett élt a hiba.
4. **A küszöb-mátrix a SZÁRMAZTATOTT mennyiségre szóljon, ne a bemenetekre**, és
   a táblázat oszlopként tartalmazza a származtatott értéket is. Küszöbnél
   **három** cella kell: szigorúan alatta, **pontosan rajta**, szigorúan fölötte
   — a „rajta" cella az egyetlen, ami a `<` és a `<=` közti különbséget méri.
   **Számold ki a cellákat (`python3 -c`), ne fejben.**
   *Példa:* E02-R08-ban a lag-mátrix a `(engineTimeSec, latestStrumTime)` párokat
   sorolta fel, és a „határ fölötti" cellának szánt `(1.0, 0.5001)` valójában
   `lag = 0.4999` — a mátrixban egyetlen a határ fölötti eset sem volt.
   ([`docs/LESSONS.md`](../LESSONS.md) L13.)

> **Ha az implementer `stopped`-dal ellentmondást jelez a kötött döntés és az
> acceptance között, a helyes válasz dokumentált brief-revízió** (a brief §0.0
> szekciója: mit mért, melyik feloldás nyert és miért), **nem** a kötött döntés
> csendes enyhítése és **nem** a fájllista tágítása.

## 7. Kötelező ellenőrzések

**Egyetlen parancs — a gate futtatható artefaktum, nem prompt-szöveg:**

```bash
tools/round-gate.sh test/<érintett terület> [további teszt-útvonal ...]
```

A script a lépéseket (`format` → `analyze` → `test …` → `architecture`) külön
processzként, egymás után futtatja, csonkítatlan kimenettel, és az első piros
lépésnél megáll a helyes kilépési kóddal.

> **Miért script:** az E02-R07-ben az implementer motor **háromszor** futtatta a
> gate-et `| tail -N`-nel, pedig a brief ÉS a javító prompt is szó szerint
> tiltotta. A csővezeték elrejti a kilépési kódot, így a „minden gate zöld"
> jelentés bizonyíthatatlan. A tiltás szövegben nem tartott — artefaktumban igen.

A teljes suite + randomizált property gate a CI-ban
([ADR 0053](../adr/0053-ci-full-test-suite.md)) — azt az **orchestrátor** indítja;
az implementer `gh`-t nem hív. Hogy melyik workflow a kapu (`build-apk.yml`, vagy
az azonos mérce-láncú, Android-build nélküli `full-gate.yml`), azt nem a brief és
nem az orchestrátor ítéli meg, hanem
[`tools/round-ci-plan.py`](../../tools/round-ci-plan.py)
([ADR 0171](../adr/0171-pipeline-throughput-program.md) §3) — a brief dolga csak
annyi, hogy a `native_gate` mezője IGAZAT mondjon.

### 6.1 Mérce-mátrix — a brief KÖTELEZŐ szakasza (ADR 0171 §4, ADR 0175)

Minden briefben álljon egy `### 6.1 Mérce-mátrix` szakasz, amely
acceptance-pontonként megmondja, **melyik hibás implementáció melyik cellát
váltja PIROSRA**. Elfogadott alakok (a `tools/brief-lint.py` mindkettőt ismeri):

```markdown
### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A backpressure a legrégebbi frame-et adja át | backpressure-teszt |
```

vagy guard-tesztnél: **valódi-sértés próba** — `<az őr ideiglenes rontása>` →
a teszt **PIROS** → visszaállítás (a §10-ben dokumentálva).

Docs-only körnél a falszifikáció a **reviewer eldobható próbája**: melyik
mondat/oszlop törlése teszi az adott acceptance-cellát bizonyíthatatlanná.

### 7.1 Falszifikációs cella minden acceptance-ponthoz (ADR 0171 §4)

Minden acceptance-ponthoz írd oda, **melyik hibás implementációt fogja pirosra**,
és **melyik őr** méri (konkrét unit-cella vagy property-teszt). Numerikus
küszöbnél kötelező az **alatta / rajta / fölötte** cellahármas, a cellákat
`python3 -c`-vel kiszámolva — nem idealizált rácsból.

Miért: a mért javító körök nagy része nem kódhiba, hanem brief-hiba (hiányzó
falszifikáció, küszöb fölötti cella nélküli mátrix, nem létező `gate_test`).
A brief lintje ezt gépileg is méri:

```bash
tools/brief-lint.py --brief docs/rounds/<brief>.md --level strict
```

A `base` szintű leletek (`B*`) **CI-kapuk** a még nyitott körökre; a `strict`
leletek (`S*`) a kör pre-flightjának teendői.

## 8. Implementációs sorrend

1. ...

## 9. Kockázatok

- ...

## 10. Implementation handoff — a Codex tölti ki

- Fájlonkénti összefoglaló.
- Futtatott parancsok + TÉNYLEGES kimenet (ne állíts sikert, ami nem futott).
- Eltérések a tervtől és okuk.
- Nem futtatott ellenőrzések és okuk.
- Follow-up issue-k.

> **A handoff minden viselkedési állításához add meg a tesztet, ami bizonyítja.**
> A „bizonyított állítás" szabály nem csak a doc-commentre vonatkozik: az
> E02-R07 handoffja azt írta, hogy „a timeout erősebb", miközben a kód az
> ellenkezőjét csinálta, és a review mérte meg. Állítás teszt nélkül = bemondás.

## 11. Review — a Claude tölti ki

Link: `docs/reviews/eXX-rYY-review.md`
```

---
