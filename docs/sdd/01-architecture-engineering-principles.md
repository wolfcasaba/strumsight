# StrumSight Software Design Document

## Chapter 1 — Architecture & Engineering Principles

**Dokumentumverzió:** 1.1  
**Státusz:** kötelező architekturális alapdokumentum  
**Repository:** `wolfcasaba/strumsight`  
**Utolsó frissítés:** 2026-07-28

---

# 1. Cél és hatókör

Ez a fejezet a StrumSight teljes fejlesztésének kötelező mérnöki szabályrendszere. A Chapter 2–12 minden követelménye erre az alapra épül. A szabályok a Flutter kliensre, a FastAPI backend-re, a DSP/ML eszközláncra, a GitHub CI-re és a dokumentációra egyaránt érvényesek.

A cél nem pusztán működő funkciók készítése, hanem olyan rendszer létrehozása, amely:

- hosszú távon olvasható és karbantartható;
- offline alapfunkcióit hálózat nélkül is biztosítja;
- a nyers gitárhangot alapértelmezetten az eszközön tartja;
- kis, ellenőrizhető fejlesztési körökben bővíthető;
- mérhető bizonyíték nélkül nem állít pontosságot vagy teljesítményt;
- gyenge és középkategóriás Android készüléken is kontrolláltan működik;
- hibák esetén biztonságosan és visszaállíthatóan viselkedik.

---

# 2. Termékvízió

A StrumSight egy Android-first, offline-first gitártanulási platform. A megkülönböztető képessége, hogy nemcsak azt elemzi, **mit** játszik a felhasználó, hanem — az elérhető bizonyítékok határain belül — azt is, **hogyan** játszik.

A rendszer fő képességei:

- valós idejű akkord- és pengetésirány-felismerés;
- tuner, metronóm és gyakorlási motor;
- dalgyakorlás és szakaszismétlés;
- audioelemzés és fejlődéskövetés;
- bizonyítékalapú AI gitártanár;
- opcionális kamerás technikai visszajelzés;
- helyi, internet nélküli AI;
- opcionális fiók- és közösségi réteg.

Az AI nem helyettesíti a mérési rendszert. A modell strukturált, verziózott evidenciából dolgozik, és bizonytalanságát jeleznie kell.

---

# 3. Kötelező mérnöki alapelvek

## 3.1 Readability first

A kódot elsősorban emberek és későbbi fejlesztői ágensek olvassák. Az optimalizálás csak mérés után történhet. Egy rövid, jól elnevezett, tesztelhető megoldás előnyt élvez egy bonyolult, implicit megoldással szemben.

## 3.2 Small verified increments

Egy Codex-kör egy önálló, review-zható változtatás. Tilos több egymástól független kört egyetlen nagy refaktorba összevonni. Minden kör után futnak a körhöz előírt ellenőrzések, frissül a `HANDOFF.md`, és elkészül a végrehajtási jelentés.

## 3.3 Offline first

A következő képességeknek fiók és hálózat nélkül is működniük kell:

- Live;
- Tuner;
- Practice;
- Song Trainer helyi tartalommal;
- Analyze helyi fájllal vagy felvétellel;
- lokális progress és library;
- alapvető AI fallback vagy helyi AI, amikor a device tier támogatja.

Kijelentkezett és diagnosztika-kikapcsolt állapotban az alkalmazás nem indíthat rejtett hálózati kérést.

## 3.4 Privacy by default

- Nyers mikrofonhang alapértelmezetten nem hagyja el az eszközt.
- Kamera-frame alapértelmezetten nem kerül feltöltésre.
- Diagnosztikai feltöltés csak explicit, visszavonható beleegyezéssel történhet.
- Token, jelszó, diagnosztikai kulcs és nyers audio nem kerülhet logba.
- A felhasználói adatok exportálhatók és törölhetők legyenek, amikor cloud funkció készül.

## 3.5 Evidence before claims

A pontosság, latency, memóriahasználat, CPU, akkumulátorhasználat és modellminőség kizárólag reprodukálható mérés alapján dokumentálható. Szintetikus teszt önmagában nem bizonyít valós gitárteljesítményt.

## 3.6 Graceful degradation

A rendszernek képességszint alapján kell alkalmazkodnia:

- gyenge eszközön kisebb modell, ritkább vision inference vagy kikapcsolt extra effekt;
- túlmelegedéskor kontrollált visszavétel;
- memóriahiánynál biztonságos megszakítás;
- alacsony confidence esetén „nem tudom biztosan”, nem hamis visszajelzés.

## 3.7 Composition over inheritance

Interfészek, kis komponensek és explicit dependency injection előnyben. Service locator, rejtett globális mutable state és mély öröklési hierarchia nem használható.

---

# 4. Célarchitektúra

```text
lib/
├── app/                       # bootstrap, config, routing, shell
├── core/                      # feature-agnosztikus infrastruktúra és domain
│   ├── foundation/
│   ├── logging/
│   ├── storage/
│   ├── network/
│   ├── platform/
│   ├── audio/
│   ├── music/
│   ├── theme/
│   ├── i18n/
│   └── widgets/
├── features/
│   └── <feature>/
│       ├── domain/
│       ├── application/
│       ├── data/
│       ├── presentation/
│       └── public.dart
├── l10n/
└── main.dart
```

A migráció fokozatos. A működő kódot tilos egyetlen nagy lépésben átszervezni.

---

# 5. Függőségi szabályok

## 5.1 Rétegek

```text
Presentation ──▶ Application ──▶ Domain
      │                │             ▲
      └────────────────┴──▶ Data ────┘
```

- `domain` nem függ Fluttertől, Riverpodtól, Dio-tól, storage plugintól vagy platform API-tól;
- `application` use case-eket, orchestrációt és állapotátmeneteket tartalmaz;
- `data` repository implementációt, serializációt, API- és storage adaptert tartalmaz;
- `presentation` UI-t, controllert és lokalizált hibamegjelenítést tartalmaz;
- a `core` nem importálhat feature-t;
- más feature belső könyvtára nem importálható; csak `public.dart` vagy közös core contract használható.

## 5.2 Tiltott függőségek

- Widget → Dio vagy adatbázis;
- Domain → Flutter;
- Core → Feature;
- Feature A → Feature B `data/`, `providers/`, `screens/` vagy `engine/` belső fájlja;
- UI → SharedPreferences vagy secure storage plugin;
- AI prompt → közvetlen, validálatlan adatbázisírás.

---

# 6. Flutter és Riverpod szabályok

- Riverpod 3 kézzel írt provider, codegen nélkül, amíg külön ADR nem dönt másként.
- State immutable.
- Üzleti logika use case-ben vagy domain service-ben, nem widgetben.
- `BuildContext` nem kerül domain vagy data rétegbe.
- A provider inicializálás nem írhatja felül a közben módosított frissebb állapotot.
- A mikrofont birtokló provider lifecycle-ja explicit és tesztelt.
- Minden felhasználói szöveg ARB lokalizációból érkezik.
- Szín önmagában nem hordozhat jelentést.
- Animáció nem ronthatja az audio pipeline-t és tiszteletben tartja a reduced-motion beállítást.

---

# 7. Audio, DSP és ML szabályok

- A DSP a UI isolate-on kívül fut, amikor a mérés ezt indokolja.
- Paraméterváltoztatás csak fixture-, property- és valós audio mérés mellett merge-elhető.
- Modell bináris cseréje model card, checksum, exportverzió és parity teszt nélkül tilos.
- Nyers PCM fölösleges másolása kerülendő.
- Audio frame-enként nagy objektumallokáció nem engedélyezett.
- A végső elfogadás része valódi Android készülék és valódi gitár.
- Ismeretlen vagy gyenge confidence nem alakítható mesterségesen biztos eredménnyé.

---

# 8. Backend szabályok

- FastAPI route vékony; üzleti logika service/use case rétegben.
- Production schema csak verziózott migrációból készülhet.
- Production secret nélküli indulás fail-closed.
- Jelszó, JWT és adatbázis URL nem kerül logba.
- Minden írási API idempotency- vagy replay-stratégiát dokumentál.
- Community és cloud AI szerveroldali authorizationt használ; kliensoldali elrejtés nem jogosultságkezelés.
- Liveness és readiness külön endpoint.
- Lab/diagnostics route production környezetben alapértelmezetten nincs regisztrálva.

---

# 9. Hiba- és eredménymodell

A várható hibák strukturált failure-ként jutnak az application/presentation rétegbe. Nyers `DioException`, platform exception vagy storage exception nem kerülhet a UI-ba.

Kötelező kategóriák:

- `NetworkFailure`;
- `AuthenticationFailure`;
- `PermissionFailure`;
- `StorageFailure`;
- `AudioFailure`;
- `MlFailure`;
- `ValidationFailure`;
- `ConfigurationFailure`;
- `CancelledFailure`;
- `UnknownFailure`.

A felhasználói szöveg lokalizált failure code alapján készül.

---

# 10. Tesztelési stratégia

Minden kör a kockázatához igazodó tesztet ad hozzá.

Kötelező rétegek:

- unit teszt domain és application logikára;
- repository/adapter teszt data rétegre;
- widget teszt kritikus UI állapotokra;
- integration teszt lifecycle, routing, storage és hálózati határokra;
- property teszt DSP, timeline, reducer és idempotency invariánsokra;
- fixture parity teszt Flutter–Python és modell-export határokra;
- valódi készülékes manuális gate mikrofon, kamera, thermal és release esetén.

A `flutter analyze` és `flutter test` külön parancsként fut, mert a jelenlegi fejlesztői környezetben a láncolás memóriahibát okozhat.

---

# 11. Biztonság és secret-kezelés

- Secret nem commitolható.
- `.env`, signing key, diagnosztikai token és production API credential GitHub secret vagy lokális, gitignored fájl.
- A debug signing production release-re nem használható.
- Dependency és modell licence dokumentált.
- Prompt injection, tool calling és AI action külön trust boundary.
- Felhasználói által generált tartalom moderációja és report útvonala kötelező a Community release előtt.

---

# 12. Dokumentációs hierarchia

Ütközés esetén a következő sorrend érvényes:

1. a felhasználó aktuális, explicit utasítása;
2. az aktuálisan kijelölt SDD-kör;
3. az érintett SDD-fejezet;
4. ez a Chapter 1 és a gyökér `AGENTS.md`;
5. elfogadott ADR-ek;
6. `HANDOFF.md` aktuális állapot;
7. README és örökölt `CLAUDE.md`.

Az elavult dokumentációt nem szabad csendben követni. Az eltérést dokumentálni és rendezni kell.

---

# 13. Kódolási standardok

- null-safe, erősen típusos kód;
- beszédes elnevezés;
- magic number és magic string központi konstans nélkül nem használható;
- üres `catch` és indokolatlan `dynamic` tiltott;
- production kódban `print` helyett strukturált logger;
- publikus contract dokumentált;
- TODO/FIXME csak issue-hivatkozással és nem blokkoló állapotban;
- egy függvény egy jól körülhatárolt felelősség;
- determinisztikus teszt fake clockkal, fake ID generatorral és fake storage/network adapterrel.

---

# 14. Definition of Done alapja

Egy kör csak akkor kész, ha:

1. a scope teljesült, a scope-on kívüli munka nem került bele;
2. a kód formázott és az analyzer zöld;
3. az érintett és teljes regressziós tesztek a kör előírása szerint zöldek;
4. nincs ismert adatvesztés, secret leak vagy resource leak;
5. a teljesítmény nem romlott indokolatlanul;
6. a dokumentáció, traceability és HANDOFF frissült;
7. a commit/PR egyértelműen visszaállítható;
8. a Codex tényszerű végrehajtási jelentést adott.

A részletes ellenőrzőlista: `docs/execution/04-definition-of-done.md`.

---

# 15. Migrációs elv

A StrumSight már működő, tesztelt kódbázis. Ezért:

- nincs „rewrite from scratch”;
- először contract és teszt, majd adapter, végül fogyasztók migrációja;
- kompatibilitási re-export átmenetileg megengedett;
- allowlist csak csökkenhet;
- minden migráció visszaállítható;
- a DSP és ML output parity külön gate.

E dokumentum elfogadása után a végrehajtás a **Chapter 2 — Epic 1, Kör 1** feladattal indul.
