# ADR 0287 — A tanár egyetlen eszközt sem futtat automatikusan

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R29` (Chapter 13, Kör 29)
- **Kapcsolódó:** [`0279`](0279-consequence-first-confirmations.md),
  [`0278`](0278-ai-provenance-is-visible.md),
  [`0280`](0280-accessibility-contract-and-live-region-budget.md)

## Kontextus

Az AI-tanár eszközöket hívhat: gyakorlási tervet módosít, tartalmat publikál,
modellt tölt le, felvételt indít. A modell bemenete **részben nem megbízható** —
importált dal szövege, közösségi tartalom, felhasználói jegyzet mind
tartalmazhat elrejtett utasítást (prompt injection).

Ha bármelyik eszköz automatikusan futhat, az injektált utasítás közvetlenül
hatást ér el a felhasználó adatain. A felület ilyenkor az utolsó védvonal.

Csábító kivételt tenni az „olvasó jellegű" eszközökre: azok „nem csinálnak
semmit". Csakhogy az olvasás is kiszivárogtathat (mit olvasott be és hova
került), és a kategória határa menet közben elmosódik — új eszközök szivárognak
be az „ártalmatlan" halmazba.

## Döntés

1. **Egyetlen tool-akció sem fut automatikusan.** Minden végrehajtást a
   felhasználó erősít meg az `SsToolConfirmationSheet`-en, ami megmutatja az
   érintett adatot és a módot (ADR 0279 §2).
2. Mentesítés **csak explicit, zárt, a tervben rögzített listával** adható —
   nyitott kategória-alapú kivétel („olvasó eszközök") tilos.
3. A megerősítés visszahívása **pontosan egyszer** fut; az ismételt modell-kérés
   **új megerősítést** igényel — nincs „emlékezz rá".
4. **Az AI-mód mindig látható** (helyi / felhő / tartalék), üzenet szinten is.
5. **A streaming nem spammelheti a képernyőolvasót**: a bejelentés összevont,
   nem token-szintű (ADR 0280 §2).
6. **A terv-módosítás explicit**, különbségként jelenik meg, elfogadás vagy
   elutasítás mellett.
7. **A beszélgetés tartalma nem kerül analitikába** — sem esemény-paraméterként,
   sem hibajelentésben.
8. **A hiányzó bizonyíték kimondott**: bizonyíték nélküli állítás nem jelenik
   meg megalapozottként (az ADR 0283 elve a coachingra).

## Következmények

**Pozitív.** Az injektált utasítás legfeljebb javaslatig jut, végrehajtásig nem.
A felhasználó minden adatmódosításról tud. A beszélgetés magánjellegű marad.

**Negatív / ár.** Több koppintás a folyamatokban, és a tanár nem tud „magától
elintézni" dolgokat. Ez a biztonság ára, és tudatosan vállaljuk.

**Amit ez a döntés TILT.** A kategória-alapú mentesítést; a megerősítés
megjegyzését későbbi hívásokra; a token-szintű felolvasást; a beszélgetés
naplózását analitikába.
