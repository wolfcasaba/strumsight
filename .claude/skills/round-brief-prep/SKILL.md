---
name: round-brief-prep
description: SDD kör-briefek (docs/rounds/) elkészítése a Claude-tervez → Codex-implementál protokollhoz (ADR 0055) — egyetlen kör briefje VAGY több jövőbeli kör előre-elkészítése (batch), amíg a Codex az aktuális körön dolgozik. Használd, amikor a user kör-brief írását, "készítsd elő a következő köröket / terveket R-ig" jellegű batch-előkészítést kér, vagy egy előre megírt brief indítás előtti pre-flight frissítését kell elvégezni.
---

# Kör-brief előkészítés (StrumSight SDD)

A kör-brief a Claude tervezői kimenete és a Codex implementációs szerződése
(ADR 0055, AGENTS.md §15). Sablon: `docs/execution/08-round-brief.md`.
Stílus-horgony: mindig a legutóbbi kész brief a `docs/rounds/`-ban (jelenleg
`e01-r11-routing-and-app-shell.md`) — annak mélységét és szigorát kell hozni.

## Bemenetek (MINDIG olvasd el, ebben a sorrendben)

1. `docs/sdd/<fejezet>.md` — a kör SDD-definíciója (Cél / Feladatok / Kötelező
   tesztek / Elfogadási feltételek / Javasolt commit).
2. A sablon: `docs/execution/08-round-brief.md` + `docs/rounds/README.md`.
3. **A TÉNYLEGES kód**, amit a kör érint — soha ne a dokumentációból feltételezz.
   A „Jelenlegi állapot" szekció minden állítása mért tény legyen, fájlnévvel
   (és ahol értelmes, sorszámmal). Grep-eld végig: hívóhelyek száma, meglévő
   tesztek léte/hiánya, guard-tesztek, env-defaultok.
4. `docs/adr/` — a következő szabad ADR-szám. **Figyelem:** a már megírt (de még
   nem futott) briefekben előre kiosztott számokat is számold bele — a kiosztás
   folytonos a briefek KÖZÖTT is.
5. `HANDOFF.md` releváns sorai + a korábbi körök tanulságai (mit tilt az
   AGENTS.md §9 DSP-tilalom, ADR 0052/0053 gate-szabályok, user-szabályok).

## A brief kötelező elemei (a sablonon túl ezek a minőségi léc)

- **Jelenlegi állapot = mért tények.** Mit csinál MA a kód, mi hiányzik, mi van
  már kész a kör feladataiból (a „már kész, nem e kör dolga" jelölés fontos —
  megakadályozza a duplamunkát és a scope-tágulást).
- **Engedélyezett fájlok tételes táblája** útvonal+indok párokkal, plusz explicit
  **tilos zóna**. Ez a review objektív mércéje (`git diff --stat` vs lista).
- **Kötött architekturális döntések** előre kiosztott ADR-számmal. Az ADR-t
  Claude írja — a briefbe írd bele, hogy a Codex ne hozzon létre `docs/adr/` fájlt.
- **Mérhető acceptance criteria** — „jól működik" tilos; minden pipához teszt,
  parancs-kimenet vagy futás-link tartozzon. Guard-jellegű tesztnél kötelező a
  **valódi-sértés próba** (ideiglenes rontás → piros → visszaállítás, §10-ben
  dokumentálva).
- **Kötelező ellenőrzések külön parancsokként** (AGENTS.md §12 — `&&` láncolás
  tilos, analyze és test soha nem egy hívásban). CI-dispatch / PR / merge mindig
  Claude-oldal — a Codex ne hívjon `gh`-t.
- **Kockázatok**: konkrétak (melyik refaktor mit tör el, melyik teszt-környezeti
  csapda ismert), ne általánosságok.
- Üres **§10 Implementation handoff** (Codex tölti) és **§11 Review-link**.

## Batch-mód: több kör előre-elkészítése

Amikor a Codex az aktuális körön dolgozik és a user a következő körök terveit
kéri előre:

1. Olvasd ki az SDD-ből az ÖSSZES célkör definícióját egyben, és térképezd fel a
   **körök közti függőségeket** (pl. backend-CI kör függ a migrációs körtől).
   Írd bele minden briefbe az „Előfeltétel: RXX merge-ölve" sort, ahol van.
2. A „Jelenlegi állapot"-ot a MOSTANI kódról írd, és a brief fejlécébe rögzítsd:
   `Státusz: PREPARED (előre megírva <dátum>, kód olvasva: main @ <sha>)`.
3. Minden PREPARED briefbe tegyél **⚠ Pre-flight** blokkot a fejléc alá: mit
   kell indítás előtt újraolvasni/frissíteni (az időközben merge-ölt körök
   drift-je), majd Státusz → PLANNING és commit a kör-branchre.
4. ADR-számokat sorban oszd ki a batch összes briefjére (egy kör = egy szám;
   záró/regressziós kör tipikusan nem kap).
5. **NE commitold** az előre készített briefeket a futó Codex-kör branchére —
   a fájlok a working tree-ben várnak; minden brief a SAJÁT kör-branchén lesz
   commitolva a kör indításakor (ADR 0055: „commitolva a kör indítása ELŐTT").

## Indítási pre-flight (amikor egy PREPARED brief élesedik)

1. Friss `main`-en olvasd újra a kör által érintett fájlokat; javítsd a
   „Jelenlegi állapot" és az engedélyezett-fájllista driftjét (az előző körök
   átrendezhették a terepet).
2. Ellenőrizd az előfeltétel-körök merge-státuszát és az ADR-szám ütközését.
3. Státusz → PLANNING, dátum/sha frissítés, brief commit a kör-branchre, majd
   a Codex indítása headless (`-s danger-full-access`, lásd a memória
   parallel-codex-round-protocol bejegyzését).
4. Új session-szabály: egy session = egy kör (ADR 0052) — az indítás mindig új
   sessionben történik.

## Csapdák (korábbi körökből)

- A brief a MAI viselkedést védő teszteket nem engedheti átírni a zöldért —
  írd bele: elbukó meglévő teszt = megállás és jelentés.
- Közös fájloknál (config, main, workflow) jelezd, melyik korábbi/párhuzamos kör
  területe mi — a „csak importsor-igazítás megengedett" típusú finomhatárokat
  írd ki expliciten.
- A merge-gate workflow (`build-apk.yml`) módosítása különösen kockázatos kör:
  az elfogadás bizonyítéka mindig a kör-branchre dispatchelt zöld futás az ÚJ
  gate-ekkel + egy bizonyított piros út.
- DSP/ML paraméter, modell-bináris: AGENTS.md §9 tiltja — minden briefben
  szerepeljen a tilos zónában, ha a kör a közelében jár.
