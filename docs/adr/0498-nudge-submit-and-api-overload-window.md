# ADR 0498 — Az ébresztő KÜLÖN Enterrel küld be, és az API-túlterhelés saját, rövid ablakot kap

- **Státusz:** elfogadva (2026-09-03)
- **Kontextus:** ADR 0087 (halt-protokoll), ADR 0112 (önjavító lánc),
  ADR 0495 (áteresztő-csomag), HEAL E13-R14 (elakadás-ébresztő bevezetése)
- **Döntéshozó:** user-jelzés + mérés (2026-09-03 13:31–13:50)

## Kontextus — mit mértünk

A user egy `API Error: 529 Overloaded` üzenetet kapott, és rákérdezett, indul-e
újra a lánc. A mérés két, egymástól független defektet talált.

**(1) A 529 CSENDBEN lezárja a turnt.** Mindkét futó kör sessionje
(`E15-R12`, `E16-R02`) ugyanabban a percben esett el:

```
●API Error: 529 Overloaded. This is a server-side issue, usually temporary…
✻ Cooked for 1h 22m 21s
❯                                        ← ÜRES prompt, a session tétlen
```

Az `E15-R12` **1 óra 22 percnyi** turn-munkát vesztett el, és a folyamat ÉLT,
csak nem dolgozott. A driver néma-ablaka 20 perc, tehát a lánc körönként
legalább ennyit áll egy külső kimaradás után — miközben a jel (`529`) a napló
végén betű szerint ott van.

**(2) Az ébresztő nem küldött be semmit.** A driver „kill előtt ébressz"
mechanizmusa (HEAL E13-R14) ezt az alakot használta:

```bash
tmux send-keys -t "$tmux_session" "$STALL_NUDGE_TEXT" Enter
```

MÉRVE, `tmux capture-pane`-nel: a szöveg **benn maradt a beviteli dobozban**,
négy sorra tördelve, a session tovább állt üresen. Ok: a `claude` TUI a gyorsan
érkező, hosszú szöveget BEILLESZTÉSNEK kezeli, és ilyenkor a közvetlenül utána
érkező Enter ÚJ SORT ír, nem küld be. Egy KÜLÖN, egy másodperccel később
küldött Enter azonnal beküldte — mindkét session azonnal folytatta a munkát
(`esc to interrupt`, a napló újra frissül).

Vagyis az a mechanizmus, ami a session megölése ELŐTT egy olcsó ébresztést
adna, megbízhatatlan volt: a szöveg bement, a beküldés nem.

## Döntés

**D1 — Az ébresztő a szöveget és az Entert KÉT hívásban küldi.**
`send_nudge_to_pane()`: `send-keys -- "<szöveg>"`, majd
`PIPELINE_ORCH_NUDGE_SUBMIT_DELAY` (alap: 1 s) szünet, majd `send-keys Enter`.
A `--` a szöveget argumentumként zárja, hogy a kötőjellel kezdődő prompt se
váljon kapcsolóvá.

**D2 — Az API-túlterhelés saját, RÖVID ablakot kap.** Ha a session-napló
utolsó `PIPELINE_ORCH_OVERLOAD_TAIL_BYTES` (alap: 4000) bájtja illeszkedik az
`API Error: 529|529 Overloaded` mintára, az ébresztés küszöbe
`PIPELINE_ORCH_OVERLOAD_SECONDS` (alap: 120 s) a 20 perc helyett, és az
ébresztés-keret `PIPELINE_ORCH_OVERLOAD_NUDGES` (alap: 12), mert egy külső
kimaradás ismétlődhet. A terminális ág (`break`) VÁLTOZATLAN: a keret
kimerülése után a session továbbra is leáll.

**D3 — Az ébresztő előbb elbocsátja a promptot blokkoló visszajelzés-kérdést.**
MÉRVE 2026-09-03 14:04 (`E15-R12`): a 529 után a CLI a beviteli doboz fölé egy
kérdést tett ki (*„How is Claude doing this session? … 0: Dismiss"*), ami
elnyelte a beküldést — az ébresztő bement, a kör mégis tétlen maradt. A
`dismiss_feedback_prompt_if_present()` a folytatás-prompt ELŐTT fut, és csak
akkor tesz bármit, ha a minta tényleg ott van a panelen. A napló-ablak
(`OVERLOAD_TAIL_BYTES`) 4000-ről 8000 bájtra nőtt, mert a kérdés kitolhatja a
529-sort a látótérből.

**Amit ez NEM tesz:** nem minősíti a 529-et halt-nak, és nem indít önjavítást.
Egy külső kimaradáson az önjavító körnek nincs mit javítania a repóban — ez
ugyanaz az elv, mint a `github_actions_degraded` ágé.

## Mérce

| döntés | őrteszt |
| --- | --- |
| D1 | `tools/tests/test_nudge_submit_and_overload.py::NudgeSubmitTest` — a szöveg és az Enter KÉT külön `send-keys` hívás (a javítás előtti alakkal PIROS) |
| D2 | `…::ApiOverloadWindowTest` — a MÉRT 529-sor illeszkedik, a küszöb rövidebb, a keret nagyobb |
| D3 | `…::FeedbackPromptTest` — a kérdés elbocsátása MEGELŐZI a folytatás-promptot, és kérdés nélkül néma |

## Következmények

- Egy 529 után a lánc ~2 perccel folytat, nem ~20-cal.
- Az ébresztő mostantól ténylegesen ébreszt; a „kill előtt ébressz" fok
  (HEAL E13-R14) a mai naptól működik is, nem csak létezik.
