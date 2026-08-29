# Resource coexistence: priority, suspension, memory pressure

- **Kör:** E12-R15
- **ADR:** [`0476`](../adr/0476-resource-coexistence-priority-and-suspension-contract.md)
- **Kód:** `lib/core/resources/{resource_priority,resource_consumer,resource_arbiter}.dart`
- **Ez a kör NEM vezet be új kizárólagos-erőforrás mechanizmust** — a
  meglévő `AudioSessionCoordinator` ([ADR 0056](../adr/0056-exclusive-microphone-session.md))
  és `CameraSessionCoordinator` ([ADR 0184](../adr/0184-vision-camera-capture-stack.md))
  szerződését dokumentálja és teszteli a fölé tett prioritási réteg, nem
  helyettesíti.

## Mit old meg ez a réteg, és mit nem

A két meglévő koordinátor egy-egy **kizárólagos** erőforrást (mikrofon,
kamera) véd: két egyidejű kérő közül az egyik BUSY hibát kap. Amire eddig
NEM volt szerződés: mi történik, amikor **különböző** erőforrások fogyasztói
versengenek a gép véges kapacitásáért — élő hang + kamerás visszajelzés +
háttérben futó AI egyszerre. Ez a réteg ezt a második kérdést válaszolja meg:
**sorrendet** (ki előzzön kit) és **felfüggesztést** (hogyan adjon át helyet
egy alacsonyabb prioritású fogyasztó anélkül, hogy elveszítené a munkáját).

A két koordinátor viselkedése **változatlan**: a kizárólagos erőforrás
BUSY-ja továbbra is a koordinátoré, és ezt a réteg nem írja felül.

## A prioritási rend (`ResourcePriority`, D1)

Magastól alacsonyig, deklarációs sorrendben:

1. `liveAudio` — élő tanulási hang (a felhasználó éppen játszik)
2. `cameraFeedback` — kamera-alapú visszajelzés
3. `backgroundAi` — háttérben futó helyi AI

`ResourcePriority.outranks(other)` mondja meg, hogy `this` szigorúan
magasabb prioritású-e, mint `other` — csak ez a viszony jogosít fel
felfüggesztésre, sosem a fordítottja. Egyenlő prioritás nem előz: két
fogyasztó lehet egyenlő szinten, ilyenkor egyik sem függeszti fel a másikat.

## A fogyasztói szerződés (`ResourceConsumer`, D3/D6)

Négy művelet: `acquire`, `release`, `pauseForHigherPriority`, `resume`, és
két állapot-getter: `isActive`, `isSuspended`. Szándékosan absztrakt — sem az
audio, sem a kamera, sem egy jövőbeli helyi-AI típus NEM jelenik meg ebben a
fájlban vagy az arbiterben. Egy konkrét fogyasztó maga dönti el, mit jelent
számára a felfüggesztés; az arbiter csak ezt a négy metódust hívja.

`pauseForHigherPriority` **megőrző** művelet: a fogyasztó utána
`resume`-mal folytatható, és tudja magáról, hogy fel van függesztve
(`isSuspended`). Ez NEM `cancel` — egy fogyasztó, amelyik a felfüggesztést
`cancel`-lel valósítja meg, sérti a szerződést (`resource_arbiter_test.dart`
A5 méri).

Ebben a körben a helyi AI **egyetlen konkrét megvalósítással sem
rendelkezik** — az Epic 10 (`hold`-on álló sáv) dolga. A tesztek fake
fogyasztókkal (`_FakeConsumer`) és valódi koordinátorra épülő adapterekkel
(`_AudioBackedConsumer`, `_CameraBackedConsumer`) mérnek.

## Az arbiter (`ResourceArbiter`, D2/D4/D5/D7)

### `request(consumer)` — mit dönt el

| Feltétel | Döntés |
|---|---|
| Egy aktív, nem felfüggesztett fogyasztó UGYANAZON a prioritási szinten már fut | `ResourceDenied(equalPriorityActive)` — semmi nem függesztődik fel |
| Egyébként | Minden aktív, nem felfüggesztett, `consumer`-nél szigorúan alacsonyabb prioritású fogyasztó `pauseForHigherPriority()`-t kap, majd `consumer.acquire()` fut. `ResourceGranted(suspended: [...])` |

**Amit sosem tesz meg:** nem hívja egyik koordinátor `revokeActive()`-ját,
és nem hívja egy másik fogyasztó `release()`-ét azért, hogy egy magasabb
prioritásút kiszolgáljon (D2). A kizárólagos erőforrás BUSY-ja emiatt
továbbra is a koordinátoré marad — a második kérő a koordinátor saját
`audio.session_busy` / `camera.session_busy` hibáját kapja, sosem az
arbiter felülbírálását (`resource_arbiter_test.dart` A2, valódi
`AudioSessionCoordinator`-on mérve).

Különböző prioritási szintek **egyszerre aktívak lehetnek** — ez maga a
"coexistence": élő hang + kamera + háttér-AI normál esetben együtt fut. A
felfüggesztés csak akkor lép közbe, ha egy magasabb prioritású fogyasztó
**kér** (arbiter `request` hívás), vagy memória-nyomás van.

### `onMemoryPressure()` — a jelzés forrása MÉG nincs bekötve (D4, §0.0 R2)

Szinkron belépési pont, amit **jelenleg semmi nem hív** a fán: nincs
`WidgetsBindingObserver.didHaveMemoryPressure` bekötés, és platform-csatorna
érintése ebben a körben tilos volt (mérve: `grep -rni
'memorypressure|didHaveMemoryPressure|lowMemory|low_memory' lib/ test/` → 0
találat). A bekötés (app/lifecycle observer réteg) egy KÉSŐBBI kör dolga.

Egy hívás a **legalacsonyabb** prioritású, aktív, nem felfüggesztett
fogyasztót függeszti fel. Ismételt hívás alatt (elhúzódó nyomás) mindig a
következő legalacsonyabbat éri — a legmagasabb prioritású aktív fogyasztó
így garantáltan utoljára kerül sorra (`resource_arbiter_test.dart` A4).

### Architektúra (D7)

`lib/core/resources/**` csak a `ResourceConsumer` szerződésen keresztül
ismeri a fogyasztókat — nem importál sem `lib/core/audio/**`-t, sem
`lib/core/camera/**`-t, sem (a `coreMustNotImportFeatures` gépi kapu miatt)
`lib/features/**`-et. A tesztek importálják közvetlenül a valódi
koordinátorokat, hogy a valódi lease-állapoton mérjenek — az arbiter maga
sosem.

## Amit ez a kör NEM köt be

- Egyetlen production hívó sincs: `lib/core/audio/mic_capture.dart`,
  `lib/features/vision/application/vision_session_controller.dart` és
  `vision_setup_controller.dart` továbbra is közvetlenül a saját
  koordinátorukat hívják. A bekötés külön kör dolga.
- A `didHaveMemoryPressure` platform-jelzés bekötése, a termál-létra
  (ADR 0196) és a battery saver összekapcsolása az arbiterrel.
- A helyi AI valódi futtatója (Epic 10 Kör 12,
  `e10-r12-local-ai-resource-coordinator.md`).
