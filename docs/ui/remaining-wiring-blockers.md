# A maradék bekötési akadályok — mérve 2026-09-05

Elérhetetlen képernyők: **23 → 6** (`dart run tool/check_screen_reachability.dart`).

Ez a dokumentum a HÁTRALÉVŐ hatot írja le. Mindegyik közös vonása: **nem
route hiányzik alóluk.** Mindegyik mögött egy megnevezett, hiányzó darab
áll, és mindegyik hiány egy TERMÉK-döntést kíván, nem bekötést. Ezért nem
kaptak route-ot: egy útvonal ma mind a hat esetben olyan képernyőt
szállítana, ami működőnek látszik, de nem az.

---

## 1–4. Gyakorlástervező (4 képernyő)

`plan_preview_screen.dart`, `plan_privacy_screen.dart`,
`plan_change_review_screen.dart`, `weekly_plan_screen.dart`

**Az akadály:** a `exerciseCandidateResolverProvider` és a
`generationPlanInputBuilderProvider` élesben `UnimplementedError`-t dob
(`practice_generator_providers.dart`). Mindkettő az EXERCISE-KATALÓGUSRA
vár.

**Miért nem lehet egyszerűen feltölteni.** A katalógus-adapterek
(`practice_engine_catalog_adapter.dart`,
`legacy_lesson_candidate_adapter.dart`) minden jelöltnél NÉGY, a hívótól
származó mezőt követelnek, és a hiányzót nem pótolják alapértékkel, hanem
**kizárják a jelöltet** egy figyelmeztetéssel. Ez szándékos őr — a kód
kifejezetten megtagadja a kitalált adatot.

A négy mezőből három levezethető a gyakorlat saját definíciójából
(`offlineAvailable`: a beépített gyakorlatok a csomagban vannak;
`contentRevision`: a `schemaVersion`-ből; `skillTargets`: a `skillTags`-ből
jön). A negyedik nem:

**`ExerciseLoadProfile` — hat pedagógiai dimenzió** (kognitív, fogó kéz,
pengető kéz, ismétlés, újdonság, koncentráció), gyakorlatonként, három
szinten. A fában SEHOL nincs ilyen adat. Ez tartalom: azt határozza meg,
mit ajánl az app gyakorlásra. Kitalálni annyi lenne, mint kitalált
számokból valódi gyakorlási javaslatokat adni.

**Egy további, önálló hiba ugyanitt:** az adapter üres `prerequisites`
listát is elutasít. Egy kezdő gyakorlatnak viszont IGAZ állítása, hogy
nincs előfeltétele — ezt a modell ma nem tudja kifejezni. A „nincs
előfeltétel" ábrázolása külön döntés.

**Amit a döntés igényel:** a 10 beépített gyakorlat terhelési profilja és
előfeltételei, plusz a „nincs előfeltétel" ábrázolása.

---

## 5. Dalcsomag-munkamenet

`song_trainer/presentation/screens/setlist_session_screen.dart`

**Az akadály:** a `SetlistItemRunner` egy typedef
(`Future<SetlistItemResult> Function(SongSetlistItem)`), és a fában NINCS
éles implementációja — csak a tesztek adnak ilyet.

Egy futtató megírása két ponton dönt:

1. **A dal elindítása** a `songTrainerSession` útvonalon megy, ami
   `SongTrainerControllerInputs`-t vár `extra`-ként — azt a beállító
   képernyő állítja elő. A futtatónak tehát egy TÖBBLÉPÉSES navigációt
   kellene levezényelnie és megvárnia.
2. **Mit jelent a „kész".** A `SetlistItemResultStatus` ismer `failed`
   állapotot, de **nincs hozzá gyártó függvény** — a modell ki tudja
   fejezni, de semmi nem tudja előállítani. Egy félbehagyott dal ma csak
   `completed`-ként rögzíthető, ami hamis állítás lenne.

**Amit a döntés igényel:** mi számít befejezett tételnek, és kell-e
`failed` gyártó.

---

## 6. Tutor gyakorlásterv-előnézet

`ai_tutor/presentation/screens/practice_plan_preview_screen.dart`

**Az akadály:** a képernyő `draft` + `validationContext` párt kér. A
`PracticePlanCompiler` elő tudja állítani mindkettőt, de **nincs
providere**, és a `PracticePlanCompilationContext` hat bemenetet kér
(dalok, gyakorlási célok, kerülendő lista, hangolás, képességek,
elérhető skill-azonosítók) — ezek összeállítása maga a hiányzó kompozíció.

**Amit a döntés igényel:** honnan jönnek a gyakorlási célok és a kerülendő
lista.

---

## A mérce vakfoltja

A `check_screen_reachability` **96 képernyőt mér, a fában viszont 99 van.**
A háromból kettő ártalmatlan (`LaunchScreen`, `RecoveryScreen` — utóbbi
route-olt), a harmadik viszont valódi árva:

**`SetlistListScreenV2`** — a fában SEMMI nem hivatkozza, és a mérce nem
látja. A detektor osztálynév-mintája nem fogja a `V2` utótagot.

Ez azt jelenti, hogy az `Unreachable: 0` cél ma egy HIÁNYOS populáción
mérne. A mérce kiterjesztése előfeltétele annak, hogy a nulla valóban
nullát jelentsen.

**Külön termék-kérdés:** két párhuzamos dalcsomag-rendszer él egymás
mellett — a route-olt `features/songs/SetlistListScreen` és a nem
route-olt `features/song_trainer/SetlistListScreenV2` a `SongSetlist` V2
modellel. A V2 lista bekötése azt a kérdést veti fel, melyik a
„a" dalcsomag-képernyő; ez nem bekötés, hanem döntés.
