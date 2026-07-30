# E02-R04 javító kör — a review három MAJOR leletének zárása

Te vagy ennek a javító körnek az IMPLEMENTERE (ADR 0055). A review jelentés:
`docs/reviews/e02-r04-review.md`. Az eredeti brief: `docs/rounds/e02-r04-practice-catalog.md`.

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

```bash
tools/codex-signal.sh done    "<egy sor>"   # kész, minden gate zöld
tools/codex-signal.sh stopped "<egy sor>"   # ütközés, nincs mit implementálni
tools/codex-signal.sh blocked "<egy sor>"   # a gate 3 javítási kísérlet után is piros
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne commitolj, ne pusholj.

## 0.1 Munkamódszer-szabályok (ADR 0069 — az előző kör megfigyeléseiből)

1. **Ez a lista a terved.** NE készíts külön task-listát; fázisonként legfeljebb
   egy állapotfrissítés.
2. **Köztes gyors ellenőrzést szűkíthetsz** (egy tesztfájl, egy alfa) — a §4 ZÁRÓ
   gate-sort viszont pontosan úgy kell lefuttatni, ahogy ott áll.
3. **A záró gate-parancsokat csővezeték és `tail` nélkül futtasd**, teljes
   kimenettel — a jelentésbe a teljes kimenet kerül, nem csonkolt részlet.
4. **Ne állíts a kódról olyat a doc-commentben, amit nem ellenőriztél.** Ha
   „const"-ot vagy „immutable"-t írsz, előbb bizonyítsd tesztben.

## 1. MAJOR-1 — a katalógus `events` és `skillTags` listái mutábilisak

`PracticeDefinition` szerződése (`practice_definition.dart:16-17`, ADR 0068):
*„[events] and [skillTags] must be immutable; pass const lists or unmodifiable
lists."* Jelenleg mindkettő növelhető lista — bizonyítva:
`events mutable: true, skillTags mutable: true`.

**Feladat:** minden katalógus-bejegyzésnél
- `skillTags:` → `const [...]`,
- a free-practice `events:` → `const []`,
- a comprehension- és helper-alapú eseménylisták → `List.unmodifiable(...)`.

**Új teszt (kötelező, valódi-sértés próbával):** a katalógus MINDEN definíciójára
próbáljon `events.add(...)` és `skillTags.add(...)` — mindkettőnek
`UnsupportedError`-t kell dobnia. A tesztet előbb a JELENLEGI (hibás) kódon
futtasd le és mutasd meg, hogy PIROS, csak utána javíts (RED → GREEN).

## 2. MAJOR-2 — valótlan doc-comment a `const`-ságról

`builtin_practice_catalog.dart:23-26` azt állítja, minden elem `const
PracticeDefinition` build-time. Ez nem igaz. A MAJOR-1 rendezése után írd át a
kommentet arra, ami tényleg igaz (build-time felépített `final` adat +
unmodifiable listák), vagy tedd valóban `const`-tá, amit lehet.

## 3. MAJOR-3 — az akkordváltás ütemenként helyett ütésenként vált

A brief §5.4 tábla 4. és 5. sora **ütemenkénti** váltást ír elő: négy ütés `G`,
majd négy ütés `D` (ill. `Em` / `C`). A jelenlegi `_alternatingChordEvents`
minden ütésen vált (`index.isEven`).

**Feladat:** ütem-szintű váltás (`(index ~/ 4).isEven`), a helper és a
doc-comment nevét/szövegét is igazítva.

**Új teszt (kötelező):** `builtin.gToDChanges.v1` és `builtin.emToCChanges.v1`
első nyolc eseményének akkord-szekvenciája tételesen kipinnelve
(`G,G,G,G,D,D,D,D`, ill. `Em,Em,Em,Em,C,C,C,C`), és az esemény-szám marad 32.

## 4. MINOR-1 (fogadd el vagy indokold meg az elutasítást)

`static final _definitions = _builtinPracticeDefinitions;` fölösleges
indirekció, és az `all()` minden híváson új unmodifiable burkolót allokál.
Egyetlen, egyszer felépített unmodifiable lista elég.

## 5. Engedélyezett fájlok

| Fájl | Miért |
|---|---|
| `lib/features/practice/data/builtin_practice_catalog.dart` | MAJOR-1/2/3 + MINOR-1 |
| `test/features/practice/data/builtin_practice_catalog_test.dart` | az új immutability- és akkord-szekvencia tesztek |

**Tilos zóna:** minden más. Ha a javításhoz ezen kívülre kellene nyúlni:
MEGÁLLÁS, `stopped` jelzés, jelentés.

## 6. Záró gate — PONTOSAN így, külön hívásokként, `tail` és csővezeték nélkül

```bash
~/flutter/bin/dart format --set-exit-if-changed lib test
~/flutter/bin/flutter analyze lib/ test/
~/flutter/bin/flutter test test/features/practice/
~/flutter/bin/flutter test test/core/architecture_dependency_test.dart
```

`&&` láncolás tilos; `analyze` és `test` soha nem egy hívásban.

## 7. Jelentés

Fájlonkénti módosítás · a MAJOR-1 RED → GREEN evidenciája (a piros futás
kimenetével) · a négy záró gate teljes kimenete · eltérések és follow-up.
