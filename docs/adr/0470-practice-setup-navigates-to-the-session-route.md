# ADR 0470 — A Practice Setup Start-ja a session útvonalra navigál (a nyitva maradt E02-R12 halasztás lezárása)

- **Státusz:** elfogadva
- **Dátum:** 2026-08-29
- **Kör:** önjavító kör (ADR 0112), `E12-R11` / **H2** feloldása
- **Kapcsolódó:** [`0078`](0078-practice-feature-surface-and-routing.md),
  [`0079`](0079-practice-session-ui-shell.md),
  [`0111`](0111-practice-production-wiring.md),
  [`0087`](0087-autonomous-round-pipeline.md),
  [`0112`](0112-self-healing-round.md),
  [`0472`](0472-e2e-flow-harness-runs-in-the-flutter-test-host.md) (az E12-R11 ágán)

## Kontextus

Az E12-R11 (end-to-end folyam-harness) review-ja **H2**-vel állította meg a
láncot: a „first practice" vertical slice a szállított appban nem volt
végigjárható, ezért az implementer a hiányzó lánc-lépést a **tesztben** pótolta
(`test/support/e2e_harness.dart:281` — `router.go(AppRoutes.practiceSession)`,
plusz két `container.read(practiceSessionHostProvider)` a Start-tap köré). Ez az
[L273](../LESSONS.md#l273) hibaosztálya. A halt által feltett normatív kérdés:
**termékhiba-e a hiányzó Setup → Session navigáció, vagy szándékosan nem-kész
felület?**

A kérdést nem vélemény, hanem a repó saját története dönti el. A mért lánc:

1. **A halasztás szándékos volt — 2026 tavaszán.** Az E02-R12 §5/5. kötött
   döntése kimondta: *„a Setup **nem** navigál a session-képernyőre (az még nem
   létezik) … A Start után a képernyő marad, lokalizált visszajelzéssel."* A
   `practice_setup_screen.dart` fejléce ugyanezt rögzítette:
   *„A »command sent« snackbar after a valid Start, no navigation (**Kör 13
   brings the session route**)."* A halasztásnak tehát **volt** címzettje.

2. **A címzett kör nem nyúlhatott a fájlhoz.** Az E02-R13 megépítette a
   `/practice/session` route-ot és a `PracticeSessionScreen`-t, de a
   `practice_setup_screen.dart` az **engedélyezett-fájllistáján kívül**, sőt a
   §3 tilos zónájában volt (a round-doc 135. sora; a záró mérés szerint a
   fájlon *„0 sor"* változott). A halasztást tehát nem tudta lezárni.

3. **A production-drótozó kör sem.** Az E02-R21 §1 célja szó szerint az volt,
   hogy *„a Hub → Setup → Session úton egy valódi felhasználó **valóban le
   tudjon futtatni** egy önálló Practice V2 sessiont"* — de a §4
   engedélyezett-fájllistáján a `practice_setup_screen.dart` **nem szerepelt**.
   A négy provider bekötése landolt; a felhasználói út utolsó lépése nem.

4. **A mai állapot (mérve, `main @ 8bdcfff9`):**

   ```
   grep -rn "AppRoutes.practiceSession" lib/
     lib/app/routing/app_route.dart:24             (a konstans)
     lib/app/routing/app_router.dart:342           (a route-regisztráció)
     lib/app/routing/adaptive_shell_routes.dart:41 (stage-route predikátum)
   ```

   **Nulla hívó.** A `PracticeSessionScreen` a termék saját felületéről
   elérhetetlen volt.

Másodlagos, ugyanide tartozó rés: az aktiválási lánc
(`practiceActiveSessionInputsProvider` → `practiceSessionControllerProvider`)
**auto-dispose**, és az egyetlen nem-auto-dispose megfigyelője a
`practiceSessionHostProvider` (`practice_effect_listener.dart:99`) — az viszont
csak akkor létesíti a `watch` linkjeit, amikor ténylegesen újraépül. Sem a
prepare sink, sem a Start-kezelő nem olvasta, ezért a sink által épp
létrehozott controller **megfigyelő nélkül** maradt, és a session-képernyő
`initState`-je előtt lebomlott. A `practice_session_providers.dart:233` saját
kommentje már a helyes szerződést írta le (*„the host provider keeps the
controller alive while the screen watches it"*) — a hiányzó fél a *„while"*
volt.

## Döntés

**D1 — Ez termékhiba, nem szándékosan nem-kész felület.** A halasztás
2026-ban szándékos volt, de a címzett köre (E02-R13) fájl-szinten ki volt zárva
a lezárásából, és utána egyetlen kör allowlistjére sem került fel. Egy lejárt,
címzett nélkül maradt halasztás **defekt** — az E02-R21 saját, ki nem mondott
céljával szemben mérve is az.

**D2 — A Setup Start-ja navigál.** Érvényes konfiguráció mellett a Start
lefuttatja a `PreparePractice` parancsot a bekötött prepare sinken, majd
`context.go(AppRoutes.practiceSession)`-nel átadja a felhasználót a session
útvonalnak. A korábbi „command sent" SnackBar **megszűnik**: a navigáció maga a
visszajelzés, és a gyökér `ScaffoldMessenger`-en megjelenő SnackBar túlélné a
route-váltást, ráülve a session vezérlőire. Az ARB-kulcs
(`practiceSetupStarted`) a helyén marad — kulcs-törlés nem ennek a javításnak a
dolga.

**D3 — Az élettartam-szerződés a hívó oldalán, kimondva.** A Start-kezelő a
`start()` **előtt** és közvetlenül **utána** — szinkron, bármelyik frame előtt —
olvassa a `practiceSessionHostProvider`-t. Az első olvasás felépíti a hostot,
hogy az inputs-notifiernek legyen figyelője, amikor a sink aktiválja; a második
átviszi a hostot a már nem-null inputokon, hogy a sink által épített
controllerre is `watch` linket létesítsen, mielőtt egy event-loop forduló
megfigyeletlenül eldobná. Ez **nem** ceremónia, hanem az auto-dispose lánc
szerződése, és a kódban kommenttel, a fán regressziós cellával rögzített.

**D4 — A mérce a valódi provider-gráfon fut.** A regressziós cellák
(`test/features/practice/presentation/practice_setup_navigation_test.dart`) a
VALÓDI routert és a VALÓDI practice-gráfot hajtják; csak a platform-peremek
(`strumEngineProvider`, audio, auth, preferences) fake-ek — ugyanaz a szabály,
amit az E02-R21 A5 cellája is követ. R1 az útvonalat méri, R2 az élettartamot
(a host nem `null`, és a képernyő a valódi `PracticeControls`-t rendereli, nem
a „session unavailable" üres állapotot).

## Következmények

- A „first practice" vertical slice a szállított (nem-produkciós) appban
  **végigjárható**: Hub → Setup → Start → Session.
- Az E12-R11 újrafuttatható. A harness `:275`/`:277`/`:281` áthidalásai
  **feleslegessé váltak** — eltávolításuk a kör saját dolga, nem ezé az ADR-é;
  a kör A1 cellája („a folyam a VALÓDI app-fán megy") ezután teljesíthető.
- A production flag **nem mozdul**: a `practiceEngineV2Enabled` továbbra is
  `nonProd`, tehát a változás a lab/dev buildet érinti. A production rollout
  változatlanul a valódi eszközös teszt utáni külön kör (user-döntés
  2026-08-01).
- Nyitva marad, és NEM ennek a javításnak a dolga: az E12-R11 review N3
  lelete — a `PracticeSessionResultHistoryMapper` valódi fali órát bélyegez a
  `createdAt` mezőre, ezért egy determinizmus-snapshot ezt kihagyni kényszerül.
  Ez önálló kör tárgya.

## Alternatívák, amiket elvetettünk

- **A kör briefjének szűkítése** (a „first practice" folyam újradefiniálása
  arra, amit a termék ma tud). Ez zöldre vitte volna a láncot, miközben egy
  valódi termékhibát dokumentáció-szintre süllyeszt — a mérce gyengítése
  minden lényegi értelemben.
- **A harness-áthidalás elfogadása.** Pontosan az L273 hibaosztálya: a cella
  „teljes láncnak" nevezi magát, miközben a hiányzó lépést maga adja be.
- **Az élettartam javítása a prepare sinkben** (`ref.listen` az application
  rétegben). Réteg-tisztasági szempontból csábító, de a keep-alive
  visszavonásának nincs természetes helye a sinken, és így session-szivárgást
  telepítene. A hívó oldali, két olvasásos szerződés a szűkebb változat.
