---
name: improve-reflective-loop
description: Self-Reflection Loop skill — a modell minden válasz után értékeli és javítja saját teljesítményét. Csökkenti a hallucinationt, javítja a pontosságot. Két verzió: light (gyors) és deep (stage-3 komplex).
trigger_keywords: ["反思", "reflexion", "self-review", "önmagát értékeli", "reflection loop"]
category: self-improvement
tags: [prompt-engineering, reasoning, quality, self-correction]
version: "1.0"
created: "2026-04-21"
validated: false
---

# Self-Reflection Loop Skill

## GYAKORLATIAN

Ez a skill azt mondja meg a modellnek, hogy minden válasz után értékelje saját magát, és szükség esetén javítson rajta. A Reflection prompting (PySquad, 2026) és a Reflexion/ExpeL minták (Nick Lawson, 2026) ötvözete.

## TRIGGER

Akkor alkalmazd, amikor:
- Komplex feladatot oldasz meg (nem trivális, 3+ lépéses)
- Fontos, hogy pontos legyen az eredmény (user-facing output)
- DEBUG módban vagy hibakeresésnél
- Első próbálkozás lehet, hogy nem tökéletes

NE alkalmazd: rövid trivia, egyszerű faktózás, idempotent műveletek.

## LIGHT VERZIÓ (1 mondat, minden válaszhoz)

```
Válaszod végén, egyetlen mondatban: MINŐSÍTES: [sikeres/hibás/részhelyes]. HA hibás: MIÉRT. HA részhelyes: MI HIÁNYZIK.
```

Ez automatikusan a response után kerül, nem kell külön promptba tenni.

## DEEP VERZIÓ (stage-3 komplex feladatokhoz)

Használd EHHEZ a prompt zárlathoz:

```
=== REFLECTION PHASE ===
Válaszod után válaszolj pontosan erre:
1. MIT CSINÁLTAM JÓL: (max 2 pont)
2. MI VOLT HIBÁS VAGY HIÁNYOS: (max 2 pont)
3. KONKRÉT JAVÍTÁS: (1 mondatban, ha szükséges)
4. KÖVETKEZŐ LÉPÉS: (1 mondatban, ha a feladat nem kész)
=== END REFLECTION ===
```

Ez a struktúra a Reflexion paperből származik (Shinn et al., 2023) + ExpeL (2024) ötvözete.

## MIÉRT MŰKÖDIK

- **Csökkenti a hallucinationt**: a modell explicit módon ellenőrzi, hogy mit nem tud biztosan
- **Javítja a Chain-of-Thought-ot**: nem csak gondolkodik, hanem utólag értékel is
- **Explicit tudás**: nem csak output, hanem metakogníció arról, amit tud
- **User trust**: a user látja, hogy a bot gondolkodik és nem csak válaszol

## RECIPEWISER ALKALMAZÁS

Amikor RecipeWiser usereknek segítesz:
- Recipe módosítás után: "Ez a változtatás mit rontott el az eredeti ízprofilból?"
- Új recept generálás után: "Ez a recept realistic-e a szezonális alapanyagok tekintetében?"
- User hiba esetén: "A felhasználó valóban ezt akarta — hogyan ellenőriztem volna korábban?"

## VALIDÁCIÓ (dry-run)

Teszteld:
1. Kérdezd meg: "Magyarázd el a fotoszintézist" → reflection: "Részben sikeres — hiányzik a fényreakció részletessége"
2. Kérdezd meg: "Írj egy olasz risotto receptet" → reflection: "Sikeres — de nem ellenőriztem a rizs típusát"
3. DEBUG: "Miért hibázott a user recipe import?" → reflection: "A schema nem egyezett, de előre nem kérdeztem meg a forrásformátumot"

Ha a reflection nem talál hibát ott, ahol kellene → finomítsd a trigger feltételeket.
