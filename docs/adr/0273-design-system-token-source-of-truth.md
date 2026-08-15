# ADR 0273 — Egy token-forrás: az új design system olvas, nem másol

**Státusz:** elfogadva (2026-08-15). A Chapter 13 (UI/UX Design System) nyitó
architekturális döntése.
Forrás: [`docs/sdd/13-chapter-13-ui-ux-design-system.md`](../sdd/13-chapter-13-ui-ux-design-system.md)
§9–§10 és Kör 2.

## Kontextus

A repository felülete ma működik: dark-first Material 3 téma, `AppColors`,
`AppPalette`, `AppTheme`, réz brand accent, és **51 képernyő**, amely ezekre
épül. A Chapter 13 ezt fejleszti tokenizált design-rendszerré — 36 körön át.

A migráció alatt **két rendszer él egymás mellett**. A kézenfekvő megoldás az,
hogy az új tokenek megkapják a hex-értékek másolatát, és a régi rendszer
érintetlen marad. Ez működik — pontosan addig, amíg valaki meg nem változtat
egy színt.

## Döntés

### 1. Egyetlen belépő: `design_system/public.dart`

A design system kizárólag ezen át importálható; belső fájl importja kívülről
tilos, és ezt architektúra-guard kényszeríti ki.

### 2. A színforrás NEM duplikálódik — az adapter olvas

Az új szemantikai tokenek a meglévő `AppColors`/`AppPalette` értékeit
**olvassák**, nem másolják.

*A tiltás:* a hex-értékek átmásolása „amíg a migráció tart". Onnantól minden
színjavítást két helyen kellene elvégezni, és az első elmaradt páros
javításnál a két rendszer csendben elcsúszik — a felhasználó pedig
képernyőnként más árnyalatot lát.

### 3. A design system nem importál feature-t

Sem `lib/features/**`, sem üzleti logika. Enélkül a rendszer nem
újrahasznosítható, és körkörös függés keletkezik.

### 4. A kanonikus forrás szakaszonként dokumentált

A `docs/ui/migration-status.md` mondja meg, melyik token melyik migrációs
szakaszban a mérvadó. A Chapter 13 harminchat köre erre hivatkozik; enélkül
minden kör találgatna.

### 5. A régi theme a migráció alatt működik

A `lib/core/theme/` nem törlődik és nem íródik át. A felelősség fokozatosan
kerül át — nem egyetlen nagy újraírással, ami az 51 képernyőt kockáztatná.

## Következmények

- A migráció bármely pontján leállítható úgy, hogy az app működik.
- Egy színjavítás egy helyen történik, a migráció végéig.
- A Component Catalog fejlesztői eszköz marad (flag mögött), nem production
  felület.
- A későbbi körök (Kör 3-tól) a szemantikai színeket, tipográfiát és
  komponenseket erre az alapra építik.

## Mérce

Az `E13-R02` §6.1 mérce-mátrixa, benne a token-forrás három kötelező
cellájával (a régi a kanonikus → az új onnan olvas / átmenet → a
`migration-status.md` kimondja / az új a kanonikus → későbbi kör) és a
valódi-sértés próbával: egy színértéket a hivatkozás helyett átmásolva, majd a
forrást megváltoztatva az **A4** cellának pirosnak kell lennie.
