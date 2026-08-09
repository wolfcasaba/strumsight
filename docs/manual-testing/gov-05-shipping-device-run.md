# GOV-05 shipping — valós készülékes menet (kitöltendő)

- **Build:** `strumsight-1.0.0-1-f1dacb7-development.apk`
  ([letöltés](https://github.com/wolfcasaba/strumsight/releases/download/gov-05-shipping/strumsight-gov05.apk))
- **Forrás:** `main @ f1dacb70`, CI run 31330144176, minden kapu zöld
- **Környezet:** `STRUMSIGHT_ENV=development` → Practice V2, Song Trainer V2 és
  a migrált Learn **BE**; AI Tutor és mind a 11 vision flag **KI**
- **Kitölti:** a user · **Elemzi:** Claude

> ⚠ **Az automatikus diagnosztika-feltöltés ebben a buildben NEM működik.**
> A `DiagnosticsUploader` a `/diagnostics` végpontra POST-ol az
> `apiBaseUrl`-en, az alapérték viszont `http://10.0.2.2:8000` (emulátor-loopback),
> és a backend nincs hosztolva. Ezért a rögzítés **kézi** — ez a lap az adat.
> Ha automatikus gyűjtést szeretnél, az egy külön build (`STRUMSIGHT_API_URL`
> a hosztolt backendre) + a backend kitétele; szólj, és előkészítem.

## Hogyan töltsd ki

Minden sor `Eredmény` mezőjébe **pontosan egy** szó a következőkből:

| Érték | Mit jelent |
|---|---|
| `pass` | működik, ahogy az „Elvárás" írja |
| `részleges` | elindul / megjelenik, de valami eltér — írd a megjegyzésbe, mi |
| `fail` | nem működik, hibás eredmény, vagy nem elérhető |
| `crash` | az app összeomlik vagy befagy |
| `kihagyva` | nem próbáltad |

A `Megjegyzés` mezőbe szabad szöveg — **a szám és a konkrétum a legértékesebb**
(„4-ből 1 akkordot ismert fel", „~2 mp késés", „G-t Em-nek látta").

Ha a sor számot kér, írd oda a számot. Ha nem tudod, `?`.

**Visszaküldés:** másold be az egész kitöltött táblát a beszélgetésbe. Nem kell
formázni, elemzem.

---

## 1. Alap — indul-e egyáltalán

| # | Teszteset | Elvárás | Eredmény | Megjegyzés |
|---|---|---|---|---|
| 1.1 | App indítása | Elindul crash nélkül, a Live fül jön be | | |
| 1.2 | Mikrofon-engedély | Kéri, és megadás után működik | | |
| 1.3 | Öt fül végigkattintása (Live → Analyze → Learn → Library → Settings) | Mind megnyílik, nincs összeomlás | | |

## 2. ÚJ: a két belépési kártya a Learn fülön

Ez a GOV-05a terméke — eddig **semmi nem vezetett** ezekhez a képernyőkhöz.

| # | Teszteset | Elvárás | Eredmény | Megjegyzés |
|---|---|---|---|---|
| 2.1 | Learn fül megnyitása | A lista **tetején** két kártya: „Gyakorló hub" és „Song Trainer" | | |
| 2.2 | „Gyakorló hub" megnyomása | Megnyílik a Practice Hub | | |
| 2.3 | „Song Trainer" megnyomása | Megnyílik a Song Trainer könyvtár | | |
| 2.4 | Zsúfoltság | A két kártya nem nyomja ki a Learn tartalmát kellemetlenül | | |

## 3. Practice V2 — a teljes menet

| # | Teszteset | Elvárás | Eredmény | Megjegyzés |
|---|---|---|---|---|
| 3.1 | Hub → egy gyakorlat kiválasztása | Megnyílik a Setup képernyő | | |
| 3.2 | Setup → Start | Elindul a session, van visszaszámlálás | | |
| 3.3 | Játék gitárral ~30 mp | A pontozás reagál a játékodra | | |
| 3.4 | Session befejezése | Megjelenik az eredmény-képernyő | | |
| 3.5 | **Mennyire volt igazságos a pontszám?** | (szám 1–5, 5 = pontos) | | hány pont, és miért |

## 4. Song Trainer V2 — eddig senki nem használta

| # | Teszteset | Elvárás | Eredmény | Megjegyzés |
|---|---|---|---|---|
| 4.1 | A könyvtár megnyitása | Megnyílik, crash nélkül (üres lista rendben van) | | |
| 4.2 | Új dal létrehozása | Az editor megnyílik és menthető | | |
| 4.3 | Import belépési pont | Elérhető; hiba esetén érthető üzenetet ad | | |
| 4.4 | Egy dal végigjátszása, ha sikerült létrehozni | Elindul, követhető | | |

## 5. Learn a V2 motoron — a migráció láthatatlan kell legyen

A GOV-05c lecserélte a Learn motorját. **Ha bármi megváltozott a felületen,
az regresszió, nem funkció.**

| # | Teszteset | Elvárás | Eredmény | Megjegyzés |
|---|---|---|---|---|
| 5.1 | Egy lecke végigjátszása | Ugyanúgy néz ki és viselkedik, mint korábban | | ha ismerted a régit: mi más? |
| 5.2 | Csillagok / pontszám a lecke végén | Megjelenik, hihető értékkel | | |
| 5.3 | Streak / napi cél frissül | A gyakorlás beszámít | | |
| 5.4 | Szünet és folytatás | A mikrofon nem „ragad be", folytatható | | |

## 6. A központi kérdés — felismeri-e, amit játszol

Ez a termék lényege, és **erre van a leggyengébb bizonyítékunk**: a szintetikus
tesztek zöldek, a valós-audio mérés 67% akkord-pontosságot adott.

| # | Teszteset | Elvárás | Eredmény | Megjegyzés |
|---|---|---|---|---|
| 6.1 | Live: játssz **G**-t tisztán, ~5 mp | G-t ír ki | | mit írt ki? |
| 6.2 | Live: játssz **C**-t | C | | |
| 6.3 | Live: játssz **D**-t | D | | |
| 6.4 | Live: játssz **Em**-et | Em | | |
| 6.5 | Live: játssz **Am**-et | Am | | |
| 6.6 | G–C–D–G váltás lassan | Követi a váltásokat | | hány váltásból hányat? |
| 6.7 | **Pengetés-irány** (le/fel váltogatva) | A nyilak követik az irányt | | kb. hány %-ban jó? |
| 6.8 | **Tempó** kijelzés metronóm mellett (pl. 80 BPM) | Közel a beállított értékhez | | mit mutatott? |
| 6.9 | Késleltetés érzete | A visszajelzés „azonnali" | | kb. hány mp? |

## 7. Szabad szöveg — ez a legértékesebb

**Mi zavart a legjobban?**

>

**Mi működött váratlanul jól?**

>

**Használnád-e gyakorláshoz a mai állapotában? Miért / miért nem?**

>

**Készülék és Android-verzió:**

>
