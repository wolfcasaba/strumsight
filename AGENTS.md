# AGENTS.md — StrumSight

Ez a fájl minden fejlesztői ágensre, Codex-munkamenetre és emberi közreműködőre kötelező a repository teljes fájára.

## 1. Projekt

A StrumSight egy Flutter alapú, Android-first, offline-first gitártanulási alkalmazás. A mikrofonból érkező DSP/ML feldolgozás alapértelmezetten helyben fut. A FastAPI backend opcionális fiók-, szinkron-, cloud AI- és közösségi funkciókat szolgál ki; az alap gitárfunkciók nem függhetnek tőle.

## 2. Dokumentációs elsőbbség

Ütközés esetén:

1. aktuális, explicit felhasználói utasítás;
2. aktuálisan kijelölt SDD-kör;
3. érintett SDD-fejezet;
4. `docs/sdd/01-architecture-engineering-principles.md` és ez a fájl;
5. elfogadott ADR;
6. aktuális `HANDOFF.md`;
7. README, `CLAUDE.md` és történeti dokumentum.

Elavult dokumentumot nem szabad csendben követni. Dokumentáld az eltérést.

## 3. Kötelező olvasás minden kör előtt

- ez a fájl;
- `docs/sdd/00-index.md`;
- Chapter 1;
- a kijelölt fejezet közös szabályai és pontos köre;
- `HANDOFF.md` aktuális összefoglalója;
- érintett production kód és tesztek;
- releváns ADR és environment dokumentáció.

## 4. Scope szabály

- Egy munkamenetben egy kijelölt Codex-kör.
- Ne kezdd el a következő kört.
- Amit a terv új sessionre ír elő, azt MINDIG új sessionben indítsd: a kör
  lezárása (merge + végrehajtási jelentés) után a session megáll. Kivétel
  csak aktuális, explicit user-utasítás (elsőbbségi lista 1. pont) — user
  szabály 2026-07-29, [ADR 0052](docs/adr/0052-ci-apk-automerge-session-per-round.md).
- Ne végezz „mellékesen” teljes repo refaktort.
- Talált, de scope-on kívüli hibát dokumentálj follow-up issue-ként.
- Minden változtatás legyen önállóan review-zható és visszaállítható.

## 5. Nem tárgyalható termékhatárok

- Nyers audio alapértelmezetten nem hagyhatja el az eszközt.
- Kijelentkezett, diagnostics-off állapotban nincs rejtett hálózati kérés.
- Mikrofont egyszerre egy owner birtokolhat.
- Gyenge confidence nem jelenhet meg biztos állításként.
- Kamera és AI nem találgathat exact string/fret vagy technikai hibát mérési bizonyíték nélkül.
- Cloud és community funkció nem ronthatja az offline alapélményt.
- Secret, token, jelszó, signing key, nyers audio vagy kamera-frame nem kerülhet logba vagy commitba.

## 6. Architektúra

- Feature-first, fokozatos Clean Architecture.
- Domain nem függ Fluttertől, Riverpodtól, Dio-tól vagy storage plugintól.
- Core nem importál feature-t.
- Más feature csak `public.dart` contracton vagy közös core modellen keresztül érhető el.
- UI nem beszél közvetlenül adatbázissal, Dio-val, SharedPreferences-szel vagy platform pluginnal.
- Dependency injection explicit Riverpod provider override-dal.
- Composition over inheritance.

## 7. Flutter szabályok

- Riverpod 3 kézzel írt provider; codegen csak külön ADR után.
- Immutable state.
- Minden felhasználói szöveg ARB lokalizáció.
- `BuildContext` nem kerül domain/data rétegbe.
- Widgetben nincs üzleti logika, JSON-serializáció vagy közvetlen pluginhívás.
- A lifecycle-erőforrások (`StreamSubscription`, isolate, mic, camera, wakelock, timer) minden útvonalon felszabadulnak.
- A reduced-motion és accessibility beállítások tiszteletben tartandók.

## 8. Backend szabályok

- Route vékony, service/use case tesztelhető.
- Production schema migrációból készül; rejtett `create_all` nem elfogadható.
- Production insecure defaulttal nem indul.
- Authorization szerveroldali.
- Írási művelethez idempotency/replay stratégia.
- Lab route productionban alapértelmezetten nincs regisztrálva.
- API változtatás OpenAPI- és migrációs hatását dokumentálni kell.

## 9. DSP és ML szabályok

- Ne módosíts DSP-konstanst, feature extractiont, decoder paramétert vagy modell binárist, ha a kijelölt kör nem kéri.
- Változás esetén kötelező fixture, property, parity és valós audio mérés.
- Modell assethez checksum, model card, exportverzió és licence-adat tartozik.
- Training nem fut normál fejlesztési körben, hacsak a fejezet külön nem írja elő.
- A shipping eredmény az appban futó implementáció mérése, nem csak Python notebook eredmény.

## 10. Kódminőség

Tilos:

- üres `catch`;
- indokolatlan `dynamic`;
- production `print`;
- magic string/number központi definíció nélkül;
- globális mutable state;
- service locator;
- `TODO` vagy `FIXME` issue-hivatkozás nélkül;
- teszt kikapcsolása pusztán azért, hogy zöld legyen a CI.

Kötelező:

- null safety;
- beszédes név;
- kis felelősségi kör;
- explicit hiba- és cancellation kezelés;
- determinisztikus clock/ID/storage/network fake;
- publikus contract dokumentálása.

## 11. Munkafolyamat

1. Ellenőrizd: `git status --short`.
2. Rögzítsd a baseline-t.
3. Olvasd el a releváns teszteket.
4. Hibajavításnál először reprodukáló teszt.
5. Implementálj a legkisebb szükséges változtatással.
6. Formázd a módosított fájlokat.
7. Futtasd a célzott teszteket.
8. Futtasd a kör kötelező teljes gate-jeit.
9. Review-zd a diffet secret, scope és architektúra szempontból.
10. Frissítsd traceabilityt és HANDOFF-ot.
11. Készíts végrehajtási jelentést.
12. Állj meg.

## 12. Kötelező ellenőrzések

A konkrét kör felülírhatja vagy bővítheti, de alapértelmezetten:

**Lokálisan** (a fejlesztői boxon):

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze lib/ test/ tool/
flutter test test/<a kör által érintett terület>
```

**A CI-ban** (kötelező, a kör-branchre dispatchelve — user szabály 2026-07-29,
[ADR 0053](docs/adr/0053-ci-full-test-suite.md)): a **teljes `flutter test`**,
a **property gate** (friss seeddel) és a release APK. A boxon a teljes suite
~15 perc, a CI-ban ~4–5 — ezért a teljes regresszió bizonyítéka a CI-run linkje,
nem lokális kimenet. A merge feltétele változatlan: minden gate zöld, a CI-ban
futó teljes suite is.

A parancsokat külön futtasd; ne láncold őket `&&` használatával a korlátozott fejlesztői környezetben.

**APK-build MINDIG CI-vel** (user szabály 2026-07-29, ADR 0052): a fejlesztői
boxon nincs Android SDK — `flutter build apk`-t ne futtass és ne is próbálj
lokálisan; a build-evidencia a kör-branchre dispatchelt workflow:

```bash
gh workflow run build-apk.yml --ref <kör-branch>
```

A futás linkje a PR kötelező build-evidenciája.

Backend változtatásnál:

```bash
cd backend
python -m pytest -q
```

ML változtatásnál a fejezetben megadott célzott pytest/parity/evaluation parancsok kötelezők.

## 13. Git szabályok

- Alapértelmezett branch: `main`.
- Közvetlen main push nem megengedett a védett workflow-ban.
- Branch: `codex/eXX-rYY-rovid-leiras`.
- **Zöld-kapus auto-merge** (user szabály 2026-07-29, ADR 0052): ha a kör
  MINDEN kötelező gate-je zöld (format, analyze, teljes test, property, a
  fejezet kör-tesztjei ÉS a branchre dispatchelt CI-build success), a PR-t
  külön jóváhagyás nélkül squash-merge-eld. Bármely gate hiánya/pirossága →
  a merge tilos marad.
- Egy commit egy logikai egység.
- Conventional Commit előtag.
- Ne módosíts vagy törölj más munkáját.
- Ne használj force push-t külön engedély nélkül.
- Ne commitolj generált buildet, secretet, lokális adatbázist vagy nagy datasetet.

## 14. HANDOFF frissítés

A kör végén a `HANDOFF.md` tartalmazza:

- aktuális branch és commit;
- utolsó befejezett chapter/kör;
- mi működik;
- futtatott tesztek és eredmények;
- ismert blocker/kockázat;
- pontos következő kör;
- nem commitolt vagy külső függőség.

## 15. Párhuzamos fejlesztés (Claude + Codex)

Két agent EGYSZERRE két külön kört vihet (bevált 2026-07-29: Codex = E01-R08,
Claude = E01-R09). Kötelező feltételek — ha bármelyik nem teljesül, a köröket
sorban kell vinni:

1. **Külön munkapéldány.** Minden agent SAJÁT klónban dolgozik
   (`/home/ubuntu/ss-<agent>-<kör>`), soha nem a közös working tree-ben, és
   saját branchen (`codex/epic-01-round-NN-<slug>`). A sandbox-izoláció NEM
   véd a git-szintű felülírás ellen.
2. **Fájlszinten diszjunkt körök.** Csak olyan két kör futhat együtt, amelyek
   forrásfájljai nem fedik egymást (pl. hálózati réteg vs. audio lifecycle).
   Ha ez kétséges, nincs párhuzamosítás.
3. **Területkiosztás a promptban.** A prompt sorolja fel tételesen: mihez NYÚLHAT
   az agent, és mi a másik agent területe (oda TILOS írni — ha kellene, meg kell
   állni és jelenteni).
4. **Előre kiosztott ADR-számok** (pl. 0055 = korábbi kör, 0056 = későbbi), hogy
   ne ütközzön a sorszám.
5. **A `HANDOFF.md`-t csak EGY agent írja.** A másik hozzá sem nyúl; a merge-ök
   után egyetlen `docs(handoff)` commit rögzíti mindkét kört.
6. **Közös fájl csak saját szekcióban.** Megosztott enumba/konstansfájlba
   (pl. `lib/core/foundation/app_failure.dart`) mindenki csak a saját köréhez
   tartozó szekcióba ír.
7. **Merge-sorrend:** az alacsonyabb sorszámú kör megy be előbb; a másik utána
   rebase-el `main`-re és ÚJRA lefuttatja a CI-t a merge előtt. A merge-bar
   változatlan: minden gate zöld (§12), különben nincs merge.

Codex indítása headless módban (a bwrap-sandbox ezen a boxon AppArmor miatt nem
tud user namespace-t nyitni, ezért `-s danger-full-access`):

```bash
codex exec -C /home/ubuntu/ss-codex-<kör> -s danger-full-access "$(cat <prompt>.md)"
```

A prompt tartalmazza a kötelező olvasnivalót (§3), a kör pontos scope-ját, a
területkiosztást, a gate-parancsokat KÜLÖN hívásokként, a CI-dispatchet és a
megállási pontokat.

## 16. Végrehajtási jelentés

A válaszban add meg:

1. összefoglaló;
2. módosított fájlok;
3. teljesített acceptance criteria;
4. futtatott parancsok és tényleges eredmények;
5. nem futtatott ellenőrzések és ok;
6. kockázatok vagy follow-up issue-k;
7. pontos következő SDD-kör.

Ne állítsd, hogy teszt sikeres, ha nem futott le.
