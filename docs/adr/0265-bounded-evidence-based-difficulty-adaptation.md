# ADR 0265 — A nehézség korlátosan, bizonyíték alapján változik

**Státusz:** elfogadva (2026-08-15). Az Epic 7 adaptációs döntése.
Forrás: [`docs/sdd/08-epic-07-ai-practice-generator.md`](../sdd/08-epic-07-ai-practice-generator.md) Ch8 Kör 16.
Épít: [ADR 0260](0260-skill-evidence-privacy-and-deduplication.md) (discomfort
külön jel), [ADR 0261](0261-skill-estimate-bounded-influence-and-unknown-state.md)
(korlátos hatás), [ADR 0264](0264-explainable-priority-and-versioned-policy.md).

## Kontextus

Az adaptáció dönti el, mikor nehezítünk vagy könnyítünk. Az evidence zajos:
egy jó nap nem tudás, egy rossz nap nem hanyatlás. A tétje nagy — a túl gyors
nehezítés elveszi a sikerélményt, a túl lassú unalmassá teszi a gyakorlást, a
fájdalom melletti nehezítés pedig árt.

## Döntés

### 1. A korlátok centralizáltak

Minden határ — maximális lépés, tempó-clamp, cooldown, minimum evidence — egy
helyen, a policyban. Szétszórt konstansok mellett a rendszer viselkedése
kiszámíthatatlan, és a hangolás visszamérhetetlen.

### 2. Egyetlen adaptáció legfeljebb EGY fokot lép

Több lépcsős ugrás tilos, akkor is, ha az evidence „nagyon jó". Ez az
ADR 0261 §1 (korlátos hatás) folytatása: zajos mérésre nem építünk nagy
lépést.

### 3. A discomfort és a biztonság blokkolja az emelést

Ha a tanuló kényelmetlenséget jelzett, **nincs** nehezítés — a teljesítménytől
függetlenül, és a cél-fókuszt is felülírva (ADR 0264 §3).

*Miért ez a legkárosabb lehetséges hiba:* „jól ment, emeljünk" — miközben fáj.
A rendszer ilyenkor pont a sérülés felé tolja a tanulót, jó szándékkal.

### 4. Egy rossz session nem okoz regressziót

Az egyszeri gyenge eredmény zaj. A visszalépéshez **ismételt** küzdelem kell.

### 5. A „túl nehéz" felhasználói jelzés azonnal hat

Ez a kivétel a 4. pont alól, és ez a biztonsági szelep: aki azt mondja, hogy
nehéz, annak azonnal könnyítünk — nem várjuk meg az evidence-küszöböt.

### 6. Minden döntés evidence-hivatkozást hordoz

Az `AdaptationDecision` megnevezi, mi alapján döntött. Enélkül a változás
magyarázhatatlan (ADR 0255).

## Következmények

- A nehézség lassabban, de megbízhatóbban követi a valós tudást.
- A fájdalom mindig felülír — a rendszer soha nem „bátorít" sérülés felé.
- A hangolás mérhető: a policy egy helyen van, verziózva (ADR 0264 §6).

## Mérce

Az `E07-R16` §6.1 mérce-mátrixa, benne az evidence-mennyiség három kötelező
cellájával (a minimum alatt → nincs emelés / **pontosan a minimumon** → emelés,
a küszöb inkluzív / jóval fölötte → emelés, de **csak egy** fokkal) és a
valódi-sértés próbával: két fok ugrást engedve az **A1** cellának pirosnak
kell lennie.
