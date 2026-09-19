# ADR 0537 — Kapu-fokozatok (Alpha/Beta), sáv-hozzárendelés és a kapuhoz vágott rollout

**Státusz:** elfogadva (2026-09-09) · **Kör:** E14-R24 · **Kiterjeszti:** ADR 0511 (fail-closed release gate) · **Párja:** ADR 0541 (chord-sorok)

## Kontextus (mért)

- `evaluation/recognition/recognition_release_gate.json` 10 küszöböt hordoz
  (`thresholdsVersion: ch14-alpha-v1`), pontosan a Ch14 §7.2/§7.4 Alpha
  minimumokat. A §7.3/§7.5 **Beta célok sehol nincsenek a fán.**
- A kapu fail-closed: hiányzó metrika = FAIL (ADR 0511 D1), az irány a
  metrika saját `higherIsBetter`-éből jön (D2), a határ az elfogadó oldalé
  (D3).
- **Rollout-létra van, kapu-kötés nincs**: PKG-D leszállította a
  `RecognitionRolloutStage` létrát (`lib/app/config/recognition_rollout_stage.dart`,
  ADR 0542: `off → shadow → alpha → beta → ga`) és a két `FeatureFlags`
  mezőt (`strumModelRolloutStage`, `chordModelRolloutStage`, alapérték `off`),
  de **semmi nem köti a fokozatot a kapu verdiktjéhez** — egy forrásmódosítás
  ma `beta`-ra állíthatná a sávot piros kapu mellett is.
- A legacy DSP baseline (chord 0,671 · onset F1 0,674 · direction 0,807) a
  kapun **megbukik** — ez a helyes viselkedés, nem hiba.

## Döntés

### D1 — Három OPCIONÁLIS mező a küszöb-soron, visszafelé kompatibilis alapokkal

`stage` (`alpha` \| `beta`, alap `alpha`), `band` (`strum` \| `chord` \|
`shared`, alap `shared`), `enabled` (alap `true`). Az alapértékek miatt egy
korábbi kapu-fájl jelentése **bitre azonos** marad, és a `schemaVersion`
`"1"` maradhat: a séma bővült, nem változott. Ismeretlen `stage`/`band`
érték **tipizált hiba**, nem alapértelmezésre esés.

### D2 — Az Alpha sorok VÁLTOZATLANOK

Ez a kör egyetlen élő küszöböt sem mozdított: a 10 Alpha sor értéke, iránya
és élessége azonos a korábbival, csak megkapta a `stage`/`band` címkéjét. A
kapu mai verdiktje (FAIL a legacy baseline-on) nem változott.

### D3 — A letiltott sor INFORMATÍV: nem buktat, de nem is engedélyez

Egy `enabled: false` sor kiértékelődik és megjelenik a riportban, de nem
folyik bele a `passed`-be. Ugyanakkor **nem is teljesít semmit**: az a
fokozat, amelynek a sorai le vannak tiltva, elérhetetlen marad (D5). Ez az
aszimmetria teszi lehetővé, hogy a Beta célok láthatók és verziózottak
legyenek anélkül, hogy blokkolnák a mai munkát vagy teljesítettnek
látszanának. A riport ezért `INFO (above target)` / `INFO (below target)`
státusszal rendereli őket — sosem sima `FAIL`-lel, ami blokkoló hibának
látszana.

### D4 — Determinisztikus sorrend duplikált metrika-út mellett is

Ugyanaz a `metricPath` most két fokozaton is szerepelhet. A `List.sort` nem
stabil, ezért a rendezés `metricPath → stage → band → enabled → threshold`
teljes rendezéssé bővült; a findings sorrendje továbbra is a forrás-JSON
sorrendjétől független.

### D5 — A rollout-fokozat a kapu által ENGEDÉLYEZETT maximumra vágódik

`rollout_licence.dart::clampRolloutStage(band:, stageName:, verdict:)`. Egy
fokozat akkor engedélyezett, ha minden őt őrző sor (adott `band` + `shared`)
**engedélyezve van ÉS átment**. A clamp a kért fokozatot erre vágja, **csak
csökkenthet**, és megnevezi a korlátozó `metricPath`-okat. Ismeretlen
fokozatnév ⇒ `off` (`unrecognisedStageName`), sosem a legközelebbi ismert
fokozat. Egy fokozat, amelyhez **egyetlen sor sincs**, szintén nem
engedélyezett (`noGateRowForStage`) — az üres követelmény nem teljesített
követelmény.

A `shadow` fokozatot **a pontosság nem engedélyezi és nem is tiltja**: sosem
felhasználó-látható (ADR 0542: `isUserVisible == false`), ezért a
shadow-főkapcsoló őrzi, nem a metrika. Ebből következik, hogy egy piros kapu
egy `alpha` kérést `shadow`-ra vág — kitettség-csökkenés, nem növekedés.

### D6 — A létra PKG-D-é; az evaluation réteg NÉVTÜKRÖT tart, teszttel pinnelve

A `RecognitionRolloutStage` enum, a két `FeatureFlags` mező és a
`docs/release/ch14-recognition-rollout.md` rekord PKG-D tulajdona. Az
evaluation réteg **nem importálja** (app- és Flutter-független marad):
`LicensedRolloutStage` név szerint tükrözi (`off`, `shadow`, `alpha`, `beta`,
`ga`), a `recognitionRolloutFlagNames` pedig csak a két mezőnevet idézi. A
tükröt gépi teszt pinneli: azonos érték-lista azonos sorrendben, és a
`requiredGateStageFor` leképezés meg kell egyezzen a PKG-D-oldali
`isUserVisible` / `requiresBetaThresholds` szemantikával. Így egyetlen ladder
van, két helyen leírva, de nem sodródhatnak szét némán.

### D7 — `ga` a kapu felől = `beta`

Mérésben nincs különbség a kettő között; a különbség emberi (R40 field study,
rollback-gyakorlat, support-készültség). Ezt a kiértékelő **nem ábrázolja** —
egy hamis „automatikus GA-engedély” rosszabb lenne, mint a hiánya.

## Ami MÉRVE van és ami NINCS

**Mérve:** a fail-closed viselkedés (hiányzó metrika, bukó sor, letiltott
sor), a clamp iránya (csak csökkent), a band-szűrés (strum bukás nem fogja a
chordot, shared bukás igen), a determinisztikus rendezés, a PKG-D-létra
névtükre, és hogy a szállított fájllal `beta` **nem érhető el**.

**NINCS mérve:** minden Beta küszöb tényleges értéke; a rollback-gyakorlat; a
subgroup-regresszió hiánya. A Beta sorok engedélyezése a §7.1 korpusz és egy
zöld Alpha után jöhet, külön körben.
