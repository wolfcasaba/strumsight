# ADR 0053 — A teljes tesztsuite a CI-ban fut, lokálisan csak a kör célzott tesztjei

**Státusz:** elfogadva (explicit user-utasítás, 2026-07-29).
Kiegészíti az [ADR 0052](0052-ci-apk-automerge-session-per-round.md) CI-szabályait;
folyamat-ADR (0050+ sáv).

## Döntés

A kötelező Flutter-gate futtatása kettéválik:

| Gate | Hol fut | Mikor |
|---|---|---|
| `dart format --set-exit-if-changed lib test` | lokálisan | minden körben |
| `flutter analyze lib/ test/` | lokálisan | minden körben |
| a kör által **érintett** teszt-könyvtárak (`flutter test test/<terület>`) | lokálisan | minden körben |
| **teljes `flutter test`** | **CI** (`build-apk.yml`) | minden kör-branchen |
| **property gate** (randomizált seed) | **CI** | minden kör-branchen |
| `flutter build apk --release` | **CI** | minden kör-branchen (ADR 0052) |

A CI-futás a kör-branchre dispatchelve:

```bash
gh workflow run build-apk.yml --ref <kör-branch>
```

A `build-apk.yml` egyetlen futása MINDEGYIK CI-oldali gate-et lefuttatja
(`flutter analyze` → `flutter test` → property gate friss seeddel → release
APK), tehát a PR-hez egyetlen run-link a teljes bizonyíték.

**A merge feltétele változatlan** (ADR 0052 2. pont): minden gate zöld,
beleértve a CI-ban futó teljes suite-ot. A szabály tehát nem gyengíti a
kaput, csak áthelyezi, hogy hol fut.

## Kontextus

A fejlesztői box (Oracle ARM, egy gyors mag, szoftveres renderelés) a teljes
`flutter test`-et **~15 perc** alatt futtatja le (mért: r207 14:38, r211 ~15
perc), miközben a CI x86-on ugyanez ~4–5 perc, és ott ráadásul a property gate
+ az APK-build is elkészül. A körönként kétszer-háromszor lefuttatott teljes
suite a session idejének a nagyobbik részét vitte el, miközben a kör tényleges
regressziós kockázata az érintett könyvtárakban mérhető.

A user 2026-07-29-én (az E01-R04 kör közben, egy 15 perces lokális suite-futás
láttán) elrendelte, hogy ezt mindig így csináljuk.

## Következmények

- Az AGENTS.md §12 és a `docs/execution/04-definition-of-done.md`
  „Teljes kötelező Flutter gate zöld" pontja ennek megfelelően pontosít:
  a teljes suite bizonyítéka a CI-run linkje, nem lokális kimenet.
- **Kockázat:** egy regresszió, amit a kör nem érintett könyvtárban okoz,
  csak a CI-ban derül ki (percekkel később). Enyhítés: az „érintett könyvtár"
  meghatározása bőkezű legyen — ha a diff `lib/core/`-t érint, az arra épülő
  feature-tesztek is érintettek.
- **Nem enyhítés:** piros CI-suite → a kör NEM Done, a merge tilos. Az
  „elmegy CI-ba, majd kiderül" attitűd nem elfogadható a kör-specifikus
  tesztekre — azokat lokálisan is zöldre kell hozni.
- A HORIZON-szabály változatlan: a szintetikus/CI-zöld soha nem „kész"; a
  végső elfogadási kapu a user valós-gitáros APK-tesztje.
