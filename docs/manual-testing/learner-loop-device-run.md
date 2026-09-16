# Tanulói hurok — valós készülékes menet (kitöltendő)

- **Build:** a `claude/sdd-plans-quality-clarity-5ydqyy` ág legutóbbi ZÖLD
  `build-apk.yml` futásának artefaktuma (`strumsight-1.0.0-1-<sha>-development.apk`,
  a run „Artifacts" szekciójából). Az első ilyen: run 34968350914 (`a2b08a6`,
  1–3. kör); a 4–5. kör utáni build a HANDOFF-ban van linkelve.
- **Környezet:** `STRUMSIGHT_ENV=development` → adaptív shell (Ma · Gyakorló hub
  · Dalkönyvtár · Profil), Practice V2, Song Trainer V2, Practice Generator **BE**;
  AI Tutor, Vision, Analysis V2, Community **KI**.
- **Kitölti:** a user · **Elemzi:** Claude
- **Miért ez a lap:** a programnak 400+ köre van és EGYETLEN dokumentált valós
  gitáros menete sincs (`docs/sdd/program-completion-report.md` §5). Ez a lap a
  hiányzó bemenet: a Chapter 14 R20+ (modell-tanítás) csak a 8. szakasz számaira
  tervezhető, a tanulói-hurok körök (1–5) pedig az 1–7. szakaszon mérődnek.

## Hogyan töltsd ki

Minden sor `Eredmény` mezőjébe **pontosan egy** szó: `pass` · `részleges` ·
`fail` · `crash` · `kihagyva`. A `Megjegyzés` mezőbe a **szám és a konkrétum**
a legértékesebb („4-ből 1 akkordot ismert fel", „G-t Em-nek látta", „~2 mp").
Ha nem tudod: `?`. **Visszaküldés:** az egész kitöltött tábla a beszélgetésbe.

---

## 1. Alap

| # | Teszteset | Elvárás | Eredmény | Megjegyzés |
|---|---|---|---|---|
| 1.1 | Első indítás | Onboarding jön be, nincs crash | | |
| 1.2 | Négy fül (Ma → Gyakorló hub → Dalkönyvtár → Profil) | Mind megnyílik; a 4. fül címkéje **„Profil"** (nem „Tutor profil") | | |

## 2. Onboarding — az első győzelem (1. kör)

| # | Teszteset | Elvárás | Eredmény | Megjegyzés |
|---|---|---|---|---|
| 2.1 | „Próbáld ki az első győzelmed" → mikrofon engedélyezése | A Stage **„Hallgatlak…"** állapotban vár, NEM ír azonnal „nem hallottuk tisztán"-t | | ez volt a régi hiba |
| 2.2 | Maradj csendben 5 mp | Továbbra is hallgat, nem bukik | | |
| 2.3 | Pengess egy tiszta Em-et | Siker → „Tovább"; vagy gyenge → „Próbáld újra" — de csak PENGETÉS után | | |
| 2.4 | Tovább → mini-lecke | A pontozott Em-lecke jön, majd a Ma-hub | | |

## 3. Gyakorló hub (1–2. kör)

| # | Teszteset | Elvárás | Eredmény | Megjegyzés |
|---|---|---|---|---|
| 3.1 | „Neked ajánlott" kártya | Megnevezi a gyakorlatot ÉS egy mondatban indokolja („Az első gyakorlásod…") | | |
| 3.2 | „Vezetett tanfolyam" kártya | Megnyílik a 17 leckés lista | | |
| 3.3 | „Böngészés cél szerint" | Csoportok (Bemelegítés / Akkordok / Ritmus) alatt KONKRÉT gyakorlat-csempék; nincs „Gyakorlat nem elérhető" hiba egyik érintésre sem | | ez volt az 5 zsákutca |
| 3.4 | Gyors eszközök: Song Trainer | Megnyílik a tréner könyvtára | | |

## 4. Gyakorlás → eredmény → „mi legyen most" (2–3. kör)

| # | Teszteset | Elvárás | Eredmény | Megjegyzés |
|---|---|---|---|---|
| 4.1 | Ajánlott gyakorlás → Setup → Start → játék ≥ 2 perc | A session fut, pontoz | | |
| 4.2 | Eredmény: **„Következő: …"** gomb | Egy MÁSIK gyakorlatot nevez meg indokkal; „Gyakorolj újra" másodlagos | | melyiket ajánlotta? |
| 4.3 | Eredmény: **Jutalom** kártya | „+N XP" VALÓDI számmal (nem „még nincs rögzített jutalom") | | N = ? |
| 4.4 | Ugyanaz 30 mp-es sessionnel | NINCS jutalom-kártya (1 perc alatt nem jár) | | őszinte kapu |
| 4.5 | Gyenge session (sok kihagyott cél) | „Következő" = UGYANAZ a gyakorlat, „még egy kör" indokkal | | |
| 4.6 | Vissza a hubra | Az ajánlott kártya MÁR az új ajánlást mutatja (restart nélkül) | | |

## 5. Ma-hub és Profil a session UTÁN (4. kör)

| # | Teszteset | Elvárás | Eredmény | Megjegyzés |
|---|---|---|---|---|
| 5.1 | Ma-hub: napi perc | A gyakorlás percei beszámítanak | | |
| 5.2 | Ma-hub / Profil: streak | A mai gyakorlás után **1** (első nap) | | |
| 5.3 | Profil: „sessions" szám | Tartalmazza a V2 gyakorlást | | |
| 5.4 | Ma-hub: nincs „Vizuális gyakorlás" kártya; Profil: nincs „Közösség" szekció | Nem jelennek meg (flag KI) | | |

## 6. Élő (szabad felismerés) — összegzés (1. kör)

| # | Teszteset | Elvárás | Eredmény | Megjegyzés |
|---|---|---|---|---|
| 6.1 | Élő → pengess ~10-et → Befejezés | Összegző dialógus: pengetésszám, akkordszám, idő, tipp + „Tanfolyam megnyitása" | | a számok stimmelnek? |
| 6.2 | Élő → 0 pengetés → Befejezés | Nincs dialógus, egyből a Ma-hub | | |

## 7. Dalkönyvtár fül (5. kör)

| # | Teszteset | Elvárás | Eredmény | Megjegyzés |
|---|---|---|---|---|
| 7.1 | Dalkönyvtár fül | A Song Trainer könyvtár nyílik (nem a régi „Dalaim") | | |
| 7.2 | App-bar „Dalaim" ikon | A régi builder-lista elérhető | | |
| 7.3 | Új dal → editor → mentés → lejátszás | Végigmegy crash nélkül | | |

## 8. A központi kérdés — felismerés (Chapter 14 bemenete)

Ez a program leggyengébb bizonyítéka (valós-audio alapvonal: 67 % akkord,
81 % irány). **Ezek a számok döntik el a Chapter 14 R20+ tervet.**

| # | Teszteset | Elvárás | Eredmény | Megjegyzés |
|---|---|---|---|---|
| 8.1 | Élő: G tisztán, ~5 mp | G | | mit írt ki? |
| 8.2 | Élő: C | C | | |
| 8.3 | Élő: D | D | | |
| 8.4 | Élő: Em | Em | | |
| 8.5 | Élő: Am | Am | | |
| 8.6 | Élő: F | F | | |
| 8.7 | G–C–D–G lassan (10 váltás) | Követi | | hány váltásból hányat? |
| 8.8 | **Pengetés-irány**: 20 le/fel váltakozva | A nyilak követik | | hány jó a 20-ból? |
| 8.9 | „Miért nem sikerült" sáv | Ha téveszt, ÉRTHETŐ okot ír (nem szakszót) | | mit írt? |
| 8.10 | Késleltetés érzete | „Azonnali" | | kb. hány mp? |
| 8.11 | Gitár típusa, húr, pengető/ujj, helyiség | | | szabad szöveg |

## 9. Szabad szöveg — ez a legértékesebb

**Mi zavart a legjobban?**

>

**Mi működött váratlanul jól?**

>

**Melyik ponton nem tudtad, mit kellene csinálnod?**

>

**Használnád gyakorláshoz a mai állapotában? Miért / miért nem?**

>

**Készülék és Android-verzió:**

>
