# E02-R05 review — Legacy adapterek (Lesson / Song / Analyze / Daily Challenge)

- **Kör:** E02-R05, brief: [`docs/rounds/e02-r05-legacy-adapters.md`](../rounds/e02-r05-legacy-adapters.md)
- **ADR:** [0071](../adr/0071-legacy-practice-adapters.md)
- **Implementer motor:** MiniMax M3 (`engine=minimax-m3`, ADR 0069)
- **Reviewer:** Claude (read-only; production fájlt a review során nem szerkesztettem)
- **Verdikt (1. kör):** **CHANGES REQUESTED** — 0 BLOCKER · 0 MAJOR · 3 MINOR · 1 NOTE
- **Verdikt (javító kör után):** lásd §6

## 1. Scope-audit

`git status --short` a munkapéldányban: **17 érintett fájl, pontosan a brief §4
engedélyezett listája** — 12 új (6 lib adapter/kulcs + `songs/public.dart` + 5
teszt), 5 módosított (`practice_definition.dart`, `practice_validation.dart`,
`app_failure.dart`, `practice_definition_test.dart`,
`practice_validation_test.dart`). Tilos zónába nyúlás: **nincs**. A legacy kód
(`learn/`, `songs/model/`, `analyze/`, `streak/`) bitre érintetlen, ARB-fájl nem
változott.

## 2. Független gate-újrafuttatás (nem a bemásolt kimenet)

Izolált klónban (`/tmp/ss-review-e02r05`), saját `flutter pub get` után:

| Gate | Eredmény |
|---|---|
| `dart format --set-exit-if-changed lib test` | exit 0 |
| `flutter analyze lib/ test/` | exit 0, 0 issue |
| `flutter test test/features/practice/` | **242/242 zöld** |
| `flutter test test/core/foundation/ test/core/architecture_dependency_test.dart` | 22/22 zöld |
| `dart run tool/check_architecture.dart` | `Architecture dependencies OK (12 allowlisted deviation(s))` — az allowlist **nem bővült** |

## 3. Tartalmi ellenőrzés (nem bemondásra)

Az R04 tanulsága szerint a szövegesen előírt tartalmat **mérni** kell. Amit
tételesen ellenőriztem a forráson és eldobható próbateszttel:

- **Lesson-parity:** a teszt mind a 17 leckét (16 curriculum + `firstWin`)
  végigméri, esemény-szinten, EGZAKT `toLegacyBeats() == beat` egyenlőséggel,
  iránnyal és akkorddal; az Easy-variáns a `lesson.simplified` ellen. ✔
- **Akkord-redukció:** a normalizáló utófeltétele (`isCanonicalPracticeChordLabel`)
  a teljes szállított leckekészleten mérve; a `twoFingerFrame` → `Em`/`C`, a
  `bluesShuffle` → `A`/`D` tételesen kipinnelve. Az E02-R03 review NOTE-3
  ezzel **lezárva**. ✔
- **Song-adapter `toLesson()` nélkül:** forrás-scan teszt méri, hogy a fájl a
  `toLesson` szöveget sem tartalmazza; a parity a teszt oldalán hívott
  `song.toLesson()`-nal szemben mér. ✔
- **Immutabilitás:** a `skillTags` mind `static const List<String>`, az `events`
  `List.unmodifiable` — az R04 MAJOR-1 hibaosztály (mutálható lista `const`-nak
  hazudva) itt nem ismétlődik. A doc-comment nem állít nem bizonyított `const`-ot. ✔
- **Determinizmus/pure:** egyik adapterben sincs `DateTime.now(`, `Random(`,
  `Stopwatch(`, IO; a napi kihívás napját a hívó adja. ✔
- **Hibaút:** minden adapter `AppResult`-tal tér vissza, `returnsNormally`
  tesztekkel bizonyítva, hogy a hibaágak nem dobnak. ✔

## 4. Leletek

### MINOR-1 — az Analyze-idővonal fölöslegesen egy ütemmel hosszabb lesz (`analyze_practice_adapter.dart:105`)

```dart
if (lastIssuedTick >= totalBeatsTicks - 1) {
  totalBeatsTicks += bpb * BeatPosition.ticksPerBeat;
}
```

A ciklus után a `lastIssuedTick >= totalBeatsTicks` eset már nem fordulhat elő
(a cikluson belüli növelés kizárja), a `- 1` viszont azt is elkapja, amikor az
utolsó esemény **szabályosan** a határ alatti utolsó ticken van.

**Mérve (eldobható próbateszt, 120 BPM, 4/4, két pengetés):** az utolsó esemény
tickje 1919 (a `totalBeats` 1920-as kizárólagos határa alatt, tehát érvényes) →
az adapter mégis 8 negyedre nyújtja az idővonalat, míg a legacy
`Lessons.fromAnalyze` 4-et ad. Egy hibátlan klipből néma módon kétszer olyan
hosszú gyakorlat lesz.

**Kért javítás:** a post-loop blokk feltétele `>= totalBeatsTicks` legyen (vagy
a blokk elhagyása), és egy teszt pinnelje ki, hogy a tick 1919-es eset
`totalBeats == 4` marad.

### MINOR-2 — a tick-ütközés feloldása eltér a brief §5.5/8-tól, és nincs deklarálva

A brief előírása: az ütköző, előre-tolt esemény **eldobandó**, ha elérné a
`totalBeats` határt. Az implementáció ehelyett **egy ütemmel megnöveli az
idővonalat** (`analyze_practice_adapter.dart:88–92`).

A viselkedés önmagában **jobb** a briefben előírtnál (egyetlen detektált
pengetés sem vész el — próbateszttel mérve négy, 0,2 ms-re lévő pengetés a
0/1/2/3 ticken jelenik meg, hiánytalanul), ezért **elfogadom**, de:

1. a jelentés §10.5-e nem deklarálta eltérésként (a brief-eltérés jelentése
   kötelező), és
2. egyetlen teszt sem pinneli ki a növelő ágat — a §6.8-as teszt csak az
   ütközést méri, a határeset-növelést nem.

**Kért javítás:** teszt a növelő ágra (utolsó pengetés a rácshatárra kerekedve),
és a §10.5 kiegészítése. Az ADR 0071 §6-ot a tervezői oldal igazítja a
tényleges (jobb) döntéshez.

### MINOR-3 — a t0-normalizálás nincs elkötelezett teszttel lefedve

A brief §6.7 kifejezetten kérte („az első esemény tickje 0"), de mind a négy
Analyze-fixture 0,0 s-nál kezdődik, így a `timeSec - t0` kivonás nem
megkülönböztethető a nullától. Próbateszttel ellenőriztem, hogy a viselkedés
helyes (1,7 s-nál kezdődő klip → 0/480/960 tick), de ezt **a kör tesztjének**
kell rögzítenie, nem a reviewernek.

**Kért javítás:** egy nem-nulla `t0`-jú Analyze-teszt.

### NOTE-1 — halott értékadás (`analyze_practice_adapter.dart:91`)

`bars = totalBeatsTicks ~/ (bpb * BeatPosition.ticksPerBeat);` — a `bars`
változót ezután semmi nem olvassa. Az analyzer nem jelzi, de a következő
olvasót félrevezeti; a MINOR-1 javításakor érdemes törölni.

## 5. Amit kifejezetten NEM kifogásolok

- A `displayTitle` bevezetése a `PracticeDefinition`-ön pontosan a brief §5.2
  szerinti (opcionális mező, `==`/`hashCode`, blank-validáció, 61. stabil kód),
  és a Kör 4 katalógusa változatlanul zöld.
- A normalizáló teszt saját, független oracle-t (`_normalize`) használ a
  `legacyPracticeChordLabel` helyett — ez erősebb mérés, nem gyengébb.
- A `songs/public.dart` minimális (csak a `Song` modell) — helyes, a barrel
  akkorára nőjön, amekkorára tényleg kell.

## 6. Javító kör — **APPROVED**

Fix-brief: [`docs/rounds/e02-r05-fix.md`](../rounds/e02-r05-fix.md) (két fájlra
szűkített scope: az Analyze-adapter + a tesztje).

| Lelet | Megoldás |
|---|---|
| MINOR-1 | A post-loop blokk **törölve** (nem `>= totalBeatsTicks`-re javítva): a cikluson belüli növelés után a `lastIssuedTick < totalBeatsTicks` invariáns mindig áll, tehát a blokk halott kód volt. Az implementer RED evidenciát adott (`Expected: <1920> Actual: <3840>`). |
| MINOR-2 | Új teszt a növelő ágra (utolsó pengetés a rácshatárra kerekedve → 2 esemény marad, `totalBeats` 3840, `validate()` üres); az eltérés a jelentésben deklarálva. |
| MINOR-3 | Új teszt nem-nulla `t0`-val (1,7 s-nál kezdődő klip → 0/480/960/1919 tick), ami egyben a MINOR-1 határesetét is kipinneli. |
| NOTE-1 | A halott `bars` értékadás törölve. |

**Független újramérés a javítás után** (izolált klón, ugyanaz az eldobható
próbateszt-készlet, majd törölve):

- t0-normalizálás: 1,7 s-nál kezdődő klip → `0/480/960` tick, `totalBeats 4.0`,
  a legacy `Lessons.fromAnalyze` értékével egyezik. ✔
- **A MINOR-1 esete javult:** tick 1919 → `totalBeats 4.0` (a javítás előtt
  8.0), a legacy-vel egyezően. ✔
- A növelő ág változatlan (tick 1920 → `totalBeats 8.0`) — szándékos,
  ADR-ben rögzített, most már teszttel pinnelve. ✔
- Négy, 0,2 ms-re lévő pengetés továbbra is hiánytalanul kijön (`0/1/2/3` tick). ✔

Záró gate-ek (reviewer által, izolált klónban újrafuttatva, a próbateszt
törlése után): `format` 0 changed · `analyze` 0 issue · `flutter test
test/features/practice/ test/core/foundation/ test/core/architecture_dependency_test.dart`
**266/266 zöld** · `check_architecture` tiszta, az allowlist nem bővült.

**Verdikt: APPROVED** — a kör merge-elhető, ha a CI-oldali teljes suite +
randomizált property gate + APK is zöld (ADR 0053).
