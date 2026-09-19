# A maradék bekötési akadályok — mérve 2026-09-05

Elérhetetlen képernyők: **23 → 2** (`dart run tool/check_screen_reachability.dart`).

> **Frissítés — R10, 2026-09-07:** az itt leírt kettőből az egyik
> (`SetlistSessionScreen`, és vele a `SetlistListScreenV2`) bekötve — l. az
> 1. szakaszt. A fenti szám a 2026-09-05-i mérés, nem újraszámolva.

---

## A LEGFONTOSABB LELET: a mérce nem azt méri, amit a felhasználó tapasztal

A `check_screen_reachability` egy REGISZTRÁLT `GoRoute`-ot elérhetőnek
számol — akkor is, ha a szállított felületről semmi nem navigál oda.

**Mért tény: a 87 útvonal-konstansból 39-re SEMMI nem hivatkozik** a
router-fájlokon kívül. Ezek úgy szerepelnek „elérhetőként", hogy a
felhasználó csak mély-linkkel jutna el hozzájuk.

Ez pontosan az a hibaosztály, ami miatt a fejlesztés „késznek látszik, de
nem használható": a kör lezárja a route-ot, a mérce zöld, és senki nem
kérdezi meg, hogy a felületről el lehet-e oda jutni.

Ez a saját munkámban is előfordult: a 13 community route megszületett, de a
Profil hubról nem vezetett hozzájuk semmi. Javítva (`profile-hub-community-entry`),
és a `community_routing_test.dart` E6 cellája őrzi.

**Ami még belépési pont nélkül áll az ÚJ folyamatokból:**
`/analysis/capture`, `/practice/generator/weekly`, `/practice/generator/privacy`.
A route-jaik és a mögöttes adatréteg élnek; a felületről vezető gomb hiányzik.

**Javasolt mérce-bővítés:** a `check_screen_reachability` mellé egy cella,
ami az útvonal-konstansok BEJÖVŐ hivatkozásait számolja. Enélkül az
`Unreachable: 0` cél teljesíthető úgy is, hogy a felhasználó semmit nem lát
belőle.

### A mérce populációja is hiányos

96 képernyőt mér, a fában **99** van. A háromból kettő ártalmatlan
(`LaunchScreen`, `RecoveryScreen`), a harmadik valódi árva volt:
**`SetlistListScreenV2`** — semmi nem hivatkozta, és a detektor
osztálynév-mintája nem fogta a `V2` utótagot.

**Frissítés 2026-09-06/07:** mindkét fele megoldva. A populáció-szűrő
`_screen(_v\d+)?.dart`-ra bővült (96 → 97) és a detektor osztálynév-mintája
felismeri a `V2` utótagot, R10 (2026-09-07) pedig regisztrálta a
`/setlists/v2` útvonalat — a képernyő azóta MÉRTEN elérhető.

---

## A két hátralévő képernyő (2026-09-05-i állapot)

### 1. Dalcsomag-munkamenet — MEGOLDVA (R10, 2026-09-07)

`song_trainer/presentation/screens/setlist_session_screen.dart`

**Az akadály VOLT:** a `SetlistItemRunner` typedefnek nem volt éles
implementációja. Egy futtató a dal-tréner munkamenetét indítaná el —
csakhogy arra az útvonalra sem navigált semmi a fában, és
`SongTrainerControllerInputs`-ot vár `extra`-ként, amit a beállító
folyamat állít elő. A dalcsomag-futtató tehát egy olyan folyamatra épült
volna, ami maga sem volt bekötve.

**Ami R10-ben elkészült:** a beállító folyamat R3 óta bekötött
(`song_trainer_launch.dart`), erre épül az új
`SetlistSessionCoordinator`
(`song_trainer/application/setlist/setlist_session_launch.dart`): egy
dalcsomag-tételből + a tétel felülbírálataiból érvényesített
`TrainerConfig`-ot, abból `SongTrainerControllerInputs`-ot állít elő. Az
éles `SetlistItemRunner`
(`song_trainer/presentation/screens/setlist_session_route.dart`) ezt
tolja a dal-tréner munkamenet-útvonalára, és MEGVÁRJA a visszatérést —
ettől halad a dalcsomag tételről tételre. Az előkészíthetetlen tétel
`skipped` lesz a MEGNEVEZETT okkal (`missingSong` / `unsupportedTrack` /
`invalidConfig`), nem tűnik el némán.

**Ami nyitva maradt:** a Performance mód. A szállított appban minden
dal-munkamenet a PONTOZOTT tréner; egy lejátszás-csak felület nincs, ezért
a route Practice módban fut, a performance-futtató pedig hangos
`StateError` marad.

**Ami MEGVAN (2026-09-05, felhasználói döntés):** a félbehagyott tétel
ábrázolása. Új `SetlistItemResultStatus.partial` + `SetlistItemResult.partial`
gyártó: az addigi eredmény számít, és az `activeDuration` mutatja, meddig
jutott a tanuló. A `completed` hamis állítás lenne (mintha végigjátszotta
volna), a `failed` szintén (nem bukott el, abbahagyta).

### 2. Tutor gyakorlásterv-előnézet

`ai_tutor/presentation/screens/practice_plan_preview_screen.dart`

**Az akadály:** a képernyő `PracticePlanDraft` + `PracticePlanValidationContext`
párt kér. A `PracticePlanCompiler` elő tudná állítani, de **a teljes tutor
tervezési útvonal hivatkozatlan**: sem a fordítót, sem a
`PracticePlanDraft.deterministicTemplate`-et nem hívja semmi a `lib/`-ben.
A `PracticePlanCompilationContext` hat bemenete közül a
`practiceTargets`-nek (`PracticePlanTargetInput`) egyáltalán nincs
előállítója.

---

## Amit ez a sáv lezárt

| | |
|---|---|
| Community: 13 képernyő + belépési pont | ✅ |
| First-Win állomás az onboarding folyamatban | ✅ |
| Hangelemzés felvételi folyamat (3 képernyő) | ✅ |
| Gyakorlástervező (4 képernyő) | ✅ |

A hangelemzésnél az `AnalyzeAudioUseCase` üres mintákat adott tovább —
bekötve csendet elemzett volna. A tervezőnél két provider dobott élesben;
a katalógus tervezői metaadata (`builtin_catalog_metadata.dart`) hiányzott,
és azt a kód szándékos őre nem engedte kitalálni.
