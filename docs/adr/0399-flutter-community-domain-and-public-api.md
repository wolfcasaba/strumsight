# ADR 0399 — Flutter Community domain: framework-mentes típusfa, önálló teszt-csoportos guard, egyetlen `public.dart` belépő

**Státusz:** elfogadva (E09-R05 pre-flight, 2026-08-22)

## Kontextus

Epic 9 (Community Platform) Kör 2–4 kizárólag backend munka volt
(baseline/threat-model, modul-határ + első migráció, public identity/handle
policy, profil privacy/audience policy). A Flutter oldalon
`lib/features/community/` a Kör 4 `domain/policies/community_audience.dart`
kivételével nem létezik. Kör 5 az első Flutter-oldali Community kör: a
framework-független domain-fát (entitások, value objectek, repository-
interfészek) és a feature stabil belépőjét (`public.dart`) hozza létre — Kör
6-tól épül rá a Dio-alapú `data/` réteg és az UI.

A projekt 21+ meglévő feature-je ugyanezt a mintát követi: `domain/` tiszta
Dart, egyetlen `public.dart` barrel a feature-határ, és a keresztfunkciós
domain-tisztaság mérése `test/core/architecture_dependency_test.dart` önálló
teszt-csoportjaival történik ott, ahol `tool/check_architecture.dart`
`_isSharedDomain()` hardcode-olt listája (jelenleg `lib/core/music/`,
`lib/core/audio/codec/`, `lib/features/practice/domain/`) nem tartalmazza az
új feature-gyökeret — ez a Community esetében is így van, ugyanaz a mért
hiányosság, mint E08-R02-ben (Gamification).

## Döntés

### 1. A domain TISZTA Dart — `final` mezők + `const` konstruktor, NEM `package:flutter/foundation.dart`

Az immutabilitást `final` mezők és `const` konstruktor adja. A `@immutable`
annotáció (akár Flutteres, akár `package:meta`-s) NEM kerül be — a
Gamification domain (E08-R02) sem használja, és a hozzáadott érték
(statikus lint-figyelmeztetés egy mutálható mezőre) nem éri meg a Flutter-
függőség kockázatát egy ilyen korai, tesztekkel egyébként lefedett
rétegben. `package:meta` bevonása (ADR 0057 precedens a shared music
domainben) ITT nem indokolt, mert az ottani domain jóval nagyobb,
egyéni fejlesztésre nyitottabb felület — a Community domain-fa ezzel
szemben egyetlen kör alatt, egyszerre születik, egységes review mellett.

### 2. Domain-purity guard: önálló teszt-csoport, NEM a checker bővítése

`tool/check_architecture.dart` `_isSharedDomain()` listája NEM bővül —
`test/core/architecture_dependency_test.dart` kap egy önálló
`'community domain stays framework-free (E09-R05)'` csoportot, az E07-R02
(`practice_generator`) / E08-R02 (`gamification`) bevált mintáját követve:
a `lib/features/community/domain/` fát rekurzívan bejárva tiltott import-
URI-kra és hívás-mintákra (`package:flutter/`, `package:flutter_riverpod/`,
`package:riverpod/`, `package:shared_preferences/`,
`package:flutter_secure_storage/`, `package:sqflite/`, `dart:ui`,
`DateTime.now(`, `Random(`) vizsgálva. A keresztfunkciós cross-feature-
import szabály (más feature nem importálhatja a Communityt, és fordítva)
generikusan fut minden `lib/features/*` fára — ehhez nem kell külön
bejegyzés.

### 3. `public.dart`: kézzel írt barrel, NEM a generált-barrel pilot regisztráció

A `tool/gen_public_barrel.dart` + `docs/adr/0339` regisztrált-barrel
mechanizmusa jelenleg EGYETLEN pilot bejegyzést tartalmaz
(`lib/features/practice_generator/public.dart`) — ADR 0339 kifejezetten
kimondja, hogy "új feature csak a saját migrációs körében" kerülhet a
registrybe, és "a nem regisztrált feature gyökér `public.dart` továbbra is
teljes ütközési felület". A Community `public.dart` tehát ugyanúgy kézzel
írt, hagyományos barrel, mint a másik 20 meglévő feature-é (gamification,
streak, auth, settings, …) — a generált-barrel migráció egy KÉSŐBBI,
önálló kör tárgya lenne, nem ennek a körnek.

### 4. `domain/value_objects/audience.dart` ≠ `domain/policies/community_audience.dart` — nem duplikáció, hanem réteg-elválasztás

Mért tény: `lib/features/community/domain/policies/community_audience.dart`
(Kör 4, ADR 0398 §7) MÁR LÉTEZIK, és MÁR definiálja a `ProfileVisibility` /
`CommunityAudience` wire-enumokat (3 érték: `public`/`followers`/`private`,
`wireValue` byte-azonos a backend `(str, Enum)` párjával). Ez a fájl NINCS
ezen a körön az `allowed_paths`-on — a Kör 5 nem módosíthatja.

A SDD Ch10 §9.1 egy korábbi, 4-értékű `CommunityAudience` vázlatot mutat
(`onlyMe, followers, club, public`) — ez a vázlat ADR 0398-cal FELÜLÍRÓDOTT:
a club-domain (és vele a `club` audience-érték) Kör 24-re halasztva
(`is_club_member` a `RelationshipContext`-ben ma `False`-default,
fenntartott mező). A Kör 5 NEM állítja vissza a 4-értékű alakot.

`domain/value_objects/audience.dart` ezért **nem definiálhat új
`CommunityAudience`-t vagy `ProfileVisibility`-t, és nem árnyékolhatja a
Kör 4 típusait** — a wire-enumok egyetlen forrása változatlanul
`policies/community_audience.dart` (import megengedett, a fájl OLVASÁSA nem
`allowed_paths`-sértés, csak a szerkesztése az). A value object feladata: (a)
a Kör 4 enumok tartalmi ISMÉTLÉSE nélkül biztosítani egy kontrollált,
sosem dobó dekódolást ismeretlen wire-stringre (A3 — a Kör 4 fájl saját
doc-kommentje szerint a JSON-kötés "egy jövőbeli körben" landol, ez a
felelősség itt, a value-object rétegben landol, nem a policy fájlban), és
(b) a Kör 5-től induló entitások (poszt/komment audience mezője) számára
stabil, a `public.dart`-on át exportálható típusfelületet adni.

## Alternatívák

- **`@immutable` `package:meta`-ból** — elvetve: nincs meglévő precedens a
  hasonló méretű feature-domainekben (gamification, practice_generator),
  extra függőség kockázat nélküli haszon nélkül.
- **`tool/check_architecture.dart` bővítése az új gyökérrel** — elvetve: a
  brief-lint (S8 ellenőrzés) és a Kör 5 mérés is a bevált önálló
  teszt-csoportos mintát erősíti meg (E07-R02/E08-R02), a checker bővítése
  külön, szélesebb hatókörű döntés lenne, ami ezen a körön kívül esik.
- **`value_objects/audience.dart` a `CommunityAudience` teljes
  újradefiniálása** — elvetve: két versengő, ugyanazt a wire-teret lefedő
  típus review-kockázat (melyiket kell importálni?) és a Kör 4 típussal
  való bájt-egyezés bizonyítását megkettőzné.

## Következmények

Kör 6-tól a `data/` réteg (Dio) ezekre a típusokra épít; a `value_objects/
audience.dart` dekódoló segédfüggvénye ott kap élő hívót. A `public.dart`
kézzel-írt marad, amíg egy külön kör a Communityt is felveszi a generált-
barrel registrybe (ADR 0339 útja). A domain-purity guard önálló
teszt-csoportja a jövőbeli Kör 6+ application/presentation rétegek saját,
réteg-specifikus csoportjainak mintája (lásd E08-R08 gamification
application/presentation guard).

## Hivatkozások

- ADR 0057 (shared music domain, `public.dart` konvenció)
- ADR 0339 (generált `public.dart` barrel registry — pilot: `practice_generator`)
- ADR 0397 (public identity/handle policy — Kör 3)
- ADR 0398 (profil privacy, audience policy — Kör 4, `policies/community_audience.dart` forrása)
- `docs/sdd/10-epic-09-community-platform.md` §7.1, §9.1
- `test/core/architecture_dependency_test.dart` E07-R02/E08-R02 minták
