# ADR 0133 — AI Tutor tool-confirmation

- **Státusz:** Elfogadva (E04-R01 pre-flight, 2026-08-04)
- **Kör:** E04-R01 — AI Tutor baseline, ADR-ek és feature flagek
- **Implementer motor:** Codex (`gpt-5.6-terra`, örökölt kézi override, `codex-round.sh`)
- **Epic:** [Chapter 5 — Epic 4: AI Guitar Teacher](../sdd/05-epic-04-ai-guitar-teacher.md)
- **Kontext-ADR-ek:** [0131](0131-ai-tutor-provider-boundary.md)

## Kontextus

A tutor negyedik feladata az **Act**: megfelelő StrumSight gyakorlat, dalrész
vagy eszköz megnyitása (SDD Ch5 §42). Az SDD kimondja, hogy állapotot módosító
vagy sessiont indító action csak **előnézet és felhasználói megerősítés** után
hajtható végre (Ch5 §493, §225, §2213). Ha az AI önállóan, megerősítés nélkül
indíthatna műveletet, egy tévesztett vagy manipulált model-válasz mellékhatást
okozhatna a felhasználó tudta nélkül.

## Döntés

1. Minden **write/launch** típusú tutor action (gyakorlat indítása, dalrész
   megnyitása, beállítás módosítása, eszköz indítása) **kétlépcsős**:
   először **előnézet** (mit fog tenni), majd **explicit felhasználói
   megerősítés**; csak ezután fut le (R11).
2. Tisztán olvasó/magyarázó válasz (Explain, Debrief) nem igényel action-
   megerősítést, mert nem módosít állapotot és nem indít sessiont.
3. A megerősítési lépés nem kerülhető meg AI-oldali „auto-confirm" jelzéssel;
   a megerősítés a felhasználó explicit UI-interakciója.

## Következmények

- Az action-proposal + preview + confirm gépezet a R11 körben épül; ez a kör
  csak a döntést rögzíti — greenfield boundary, még nincs action-kód.
- A későbbi action-tesztek bizonyítják, hogy megerősítés nélkül nincs
  állapotváltozás.
- Ez a döntés nem lazítható azért, hogy egy teszt zöld legyen.
