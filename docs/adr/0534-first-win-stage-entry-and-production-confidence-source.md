# ADR 0534 — A First-Win állomás belépési pontja és produkciós konfidencia-forrása

**Státusz:** elfogadva (2026-09-05, E17-R01 — Chapter 17 „Teljes bekötés", Kör 1)

**Kör:** `E17-R01` · **Brief:** [`docs/rounds/e17-r01-onboarding-first-win-stage-wiring.md`](../rounds/e17-r01-onboarding-first-win-stage-wiring.md)

Kapcsolódik: [ADR 0281](0281-permission-primer-and-honest-first-win.md) (engedély-primer és
igazmondó „első siker"), [ADR 0508](0508-shell-entry-location-and-recommended-practice-handoff.md) (a shell belépési
helye — egy forrás), [ADR 0111](0111-practice-production-wiring.md) §2 (kereszt-feature
bekötés a `live/public.dart` felületén), [ADR 0112](0112-self-healing-pipeline.md) §2
(a kör önjavító revíziója).

## Kontextus

A `FirstWinStageScreen` (`lib/features/onboarding/screens/first_win_stage_screen.dart`) a
fában él, de a szállított kompozícióból **nem érhető el**: a
`tool/check_screen_reachability.dart` `reachable: false`-t mér rá, és a fán kívüli
hivatkozásai kizárólag teszt- és golden-fájlok
(`test/features/onboarding/first_win_test.dart:156`,
`test/ui/goldens/e13_r16_screens_golden_test.dart:132`).

A bekötés első kísérlete `H3`-mal állt meg a pre-flightján, mert a mérés egy második,
súlyosabb hiányt talált: a képernyő adatforrása **létezik**, de a szállított tartalma fake.
Az E17-R01 önjavító köre ezt függetlenül újramérte (`main @ 0b2feb43`), ez a session pedig
megismételte a mérést a jelen `main @ 5fbb4937`-en — az eredmény változatlan:

```
$ sed -n '20,23p' lib/features/onboarding/first_win_providers.dart
final onboardingFirstWinEngineFactoryProvider =
    Provider<OnboardingFirstWinEngine Function()>(
      (_) => FakeOnboardingFirstWinEngine.new,
    );

$ grep -rn "\.emit(" lib/features/onboarding/ --include=*.dart
(üres)

$ grep -rn "onboardingFirstWinEngineFactoryProvider.overrideWith" lib/
(üres)
```

A `FakeOnboardingFirstWinEngine.start()` egyetlen boolt állít
(`first_win_engine.dart:32`), az `emit()` pedig teszt/preview hook
(`first_win_engine.dart:45-49`). A puszta bekötés tehát egy VÉGIG az
`onboardFirstWinListening` ágon álló képernyőt (`first_win_stage_screen.dart:41-52`)
tett volna a **ma is működő** first-win út elé
(`onboarding_screen.dart:126-151` → scored `LearnScreen(lesson: Lessons.firstWin)`),
miközben az elérhetőséget és a „valós providert olvas" állítást mérő cellák zöldek
maradtak volna. Ez az [L606](../LESSONS.md#l606) hibaosztálya (*az üres forrás és a zöld
kapu megkülönböztethetetlen*), rokon az [L498](../LESSONS.md#l498) „gyártott mérésével".

## Döntés

### D1 — A belépés az onboarding folyamat lépése, nem új top-level route

A First-Win állomás az onboarding folyamatból nyílik, és **nem** kap saját `/first-win`
route-ot. Két belépési pont ugyanahhoz az állapothoz megsértené az
[ADR 0508](0508-shell-entry-location-and-recommended-practice-handoff.md) D1 egy-forrás szabályát, és a
folyamat checkpointja (`OnboardingStep`, `onboarding_provider.dart:59`) mellé egy
második, nem perzisztált állapotgépet tenne.

Következmény: az `OnboardingStep` enum **változatlan** — az ordinálisa a lemezen
perzisztált checkpoint (pinneli `test/features/onboarding/onboarding_resume_test.dart`),
tehát új enum-érték nem születhet. Az állomás a `PermissionPrimerScreen` mért
mintáját követi: a folyamaton belül renderelt/pusholt képernyő, nem útvonal.

### D2 — A kimenet az `entryLocationFor(...)` EGYETLEN forrásán megy

Az `onContinue` és az `onSkip` egyaránt az
`entryLocationFor(appConfig.flags.adaptiveShellEnabled)`
(`lib/app/routing/adaptive_shell_routes.dart:28`) eredményére navigál — pontosan úgy,
ahogy az `onboarding_screen.dart:108` és `:132` már ma is. **Literál útvonal egyik ágban
sem szerepelhet**; ez az E16-R06 által a gerincről eltávolított hibaosztály.

### D3 — A produkciós konfidencia a MEGLÉVŐ live motorból jön, nem új mikrofon-tulajdonosból

A `onboardingFirstWinEngineFactoryProvider` szállított default gyára ettől a körtől
**produkciós** `OnboardingFirstWinEngine`-t ad, amely a `strumEngineProvider`
(`lib/features/live/providers/live_providers.dart:12-16`) frame-folyamából, a
`LiveFrame.confidence` mezőből (`live_frame.dart:83`) állítja elő a kísérletenkénti
konfidenciát. A `FakeOnboardingFirstWinEngine` **teszt-infrastruktúra marad**:
override-ból él, `emit()`-tel vezérelve.

A hozzáférés a kereszt-feature publikus felületén megy (`lib/features/live/public.dart:41`
exportálja a `providers/live_providers.dart`-ot); a mért precedens ugyanerre a
`lib/features/practice/data/practice_observation_gateway_provider.dart:31`.

**Miért NEM új `AudioOwner.onboarding`.** A lease-szerződés
(`lib/core/audio/lifecycle/audio_session_lease.dart:5-11`, öt variáns) bővítése a kör
mérete fölött van, és nem is szükséges: a mikrofont a `createMicCapture(ref,
AudioOwner.live)` hívás szerzi meg a `strumEngineProvider`-ben
(`mic_capture.dart:82` → `coordinator.acquire(...)`), és az állomás alatt az onboarding az
egyetlen fogyasztó — a rá következő mini-lecke (`LearnScreen`) pedig UGYANEZT a
providert olvassa (`learn_screen.dart:125`). Egy tulajdonos, egy lease, nulla arbitrációs
kockázat. Ha a mérés mégis külön tulajdonost kívánna, az a kör BLOKKOLÓ lelete
(`stopped` jelzés), nem csendes scope-tágítás.

**Életciklus.** A motor a `liveFrameProvider` precedensét követi
(`live_providers.dart:19-24`): `start()` a mountra, `stop()` a `ref.onDispose`-ra, a
`stop()` idempotens. Mivel a `strumEngineProvider` NEM `autoDispose` — az engine-példány
osztott —, az állomás elhagyása után a rá következő mini-leckének továbbra is kapnia kell
frame-et: a „holt motor" állapot a kör BLOKKOLÓ hibája (a brief A9 cellája méri).

### D4 — A siker-szemantika érinthetetlen, a FORRÁS átkötése viszont a kör célja

A `kFirstWinConfidenceThreshold` (0.60) értéke és az `isFirstWinSuccess(confidence)`
**inkluzív** predikátuma (`first_win_providers.dart:10-14`) VÁLTOZATLAN — ez az
[ADR 0281](0281-permission-primer-and-honest-first-win.md) §2 őszinteség-szerződése:
a feltétel nélküli siker-képernyő tiltva marad. A gyár mögötti **motor** cseréje ettől
független: az a forrás-hiány javítása, nem a küszöb hangolása. A két dolog
összemosása volt a halt gyökéroka.

### D5 — A forrás hibája kimondva jelenik meg, sosem néma „Listening…"

A konfidencia-stream hibája — megtagadott mikrofon-engedély (az engedély-primer
`onSkipped` ága a **szállított** út: `onboarding_screen.dart:181-184`), foglalt mikrofon,
motor-hiba — az `AsyncValue` hibaágán kimondva jelenik meg a Stage-en (a MEGLÉVŐ
`micPermissionBody` / `micPermissionAction` kulcsokból), és a folyamat továbbvitele
(„Not now") mindig elérhető marad. Új l10n kulcs ebben a körben nem születik: a generált
ARB-aggregátum és a forrás-szegmens együtt-mozgatása külön kör tárgya
([L646](../LESSONS.md#l646)).

Ez ugyanannak az őszinteség-szerződésnek a folytatása, amit az ADR 0281 §2 a gyenge
jelre már kimond: a bizonytalanságot a felhasználó megtanulja értelmezni ahelyett, hogy
egy néma képernyő elé ülne.

## Következmények

**Pozitív.** A `FirstWinStageScreen` a szállított kompozíció része lesz, VALÓS
konfidenciával — az elérhetőségi mérés (`check_screen_reachability`) és a tartalmi
igazság (A8) együtt mozdul. Az onboarding a meglévő audio-lease-en marad, tehát a
bekötés nem nyit új arbitrációs felületet.

**Negatív / ár.** Az onboarding és a Live ugyanazon az engine-példányon osztozik: a
`stop()` sorrendje mérendő (A9), és a hiba-ág egy plusz állapotot ad a Stage-nek (D5).
Az onboarding befejezési aránya az ADR 0281 által már vállalt módon romolhat — az
állomás a MŰKÖDŐ first-win út **elé** kerül, nem helyette.

**Amit ez a döntés TILT.** Külön `/first-win` route-ot; új `OnboardingStep` enum-értéket;
literál navigációs útvonalat az `onContinue`/`onSkip` ágban; a
`kFirstWinConfidenceThreshold` / `isFirstWinSuccess` szemantikájának módosítását; új
`AudioOwner` variánst vagy bármely `lib/core/audio/**` módosítást; a szállított
kompozícióban fake motort adó default gyárat; a forrás-hiba beolvasztását a
„Listening…" állapotba.
