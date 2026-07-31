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

## 5. Kötött architekturális döntések

Amit a kör NEM tervezhet újra. Új ADR nélkül nem térhet el tőle.
Előre kiosztott ADR-szám: `00NN`.

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

A teljes suite + randomizált property gate + APK a CI-ban
([ADR 0053](../adr/0053-ci-full-test-suite.md)) — azt az **orchestrátor** indítja
(`gh workflow run build-apk.yml --ref <kör-branch>`); az implementer `gh`-t nem hív.

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
