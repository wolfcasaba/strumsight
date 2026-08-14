# ADR 0236 — Analysis technique-proxy safety and naming

- **Státusz:** Elfogadva (E06-R18 pre-flight, 2026-08-12)
- **Kör:** E06-R18 — Technique proxy kísérleti modul
- **Kapcsolódó:** SDD Ch7 §4.3, §18.1–18.5; ADR 0220, ADR 0229

## Kontextus

Egy audiofelvételből a váltás körüli időbeli és jel-alapú jelenségek
mérhetők, de a kéztartás, ujjhasználat, konkrét húr zörgése vagy egészségi
állapot nem. Az E06-R11 chord evidence-e lehet `derived`; ilyenkor nincs
top-k vagy no-chord valószínűség, ezért confidence collapse sem becsülhető
őszintén.

## Döntés

1. Az öt kísérleti proxy kizárólag azt nevezi meg, amit mér: váltási
   folyamatosság, confidence-collapse időtartam, nem várt extra
   hangindítások, kitartás-stabilitás és hangindítás-instabilitás. Tilos a
   `Technique score`, `Cleanliness`, `Skill`, vagy testrészre, ujjazatra,
   kéztartásra, hangszerhibára és egészségre utaló név vagy szöveg.
2. A biztonsági teszt minden analysis-eredetű ARB-kulcsot és
   metrikamegnevezést tiltott minták ellenőrzésével őriz. A minta szűkítése
   nem megengedett, bővítése igen.
3. A számítás csak akkor indulhat el, ha `analysisTechniqueProxiesEnabled`
   és a hívó Lab-módot jelez. A két bemenet bármelyikének hiányában a
   számító callback nem futhat.
4. E06-R18 csak önálló `TechniqueProxyReport`-ot épít; nem módosítja az
   `AnalysisDocument`-et, annak `metrics` listáját, codecét vagy a pipeline-t.
   A report nem perzisztálódik és nem jelenik meg normál UX-ben.
5. A négy confidence-feltétel mind szükséges: ismert target, nem clippelt
   input, nem backing-track-domináns jel és legalább négy azonos váltáspár.
   `derived` chord evidence esetén a collapse-proxy `unavailable` marad
   `modelUnavailable` okkal.
6. Minden proxy Lab-only marad, amíg az eval-mátrixban rögzített, valós
   jelenségre vonatkozó értékelése nincs lezárva.

## Következmények

**E06-R30 (2026-08-13):** a döntés változatlan; a Lab+flag kettős gate és az EVAL-22–26 nyitott marad.

- A V1 shipping út és a V2 document-szerződés változatlan marad.
- Egy későbbi, külön kör dönthet a Lab-panel vagy a diagnosztikai export
  bekötéséről; az nem emelheti a proxykat a normál UX-be eval nélkül.
