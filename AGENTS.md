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
- **Explicit staging.** A fájlokat tételesen kell stage-elni; `git add .` és
  `git add -A` tilos — kétágenses munkában behúzza a másik ágens vagy a
  working tree ismeretlen változtatásait.
- **Destruktív parancsok tilalma külön user-engedély nélkül:** `git reset --hard`,
  `git checkout -- .`, `git restore .`, `git clean -fd`, `git stash drop/clear`,
  `git branch -D` idegen branchre. Ezek némán megsemmisítik a másik ágens
  még nem commitolt munkáját, és a git-szintű veszteség nem visszaállítható a
  sandboxból. Ha a working tree zavaros, állj meg és jelentsd.

## 14. HANDOFF frissítés

A kör végén a `HANDOFF.md` tartalmazza:

- aktuális branch és commit;
- utolsó befejezett chapter/kör;
- mi működik;
- futtatott tesztek és eredmények;
- ismert blocker/kockázat;
- pontos következő kör;
- nem commitolt vagy külső függőség.

## 15. Ágensszerepek (Claude + Codex + MiniMax M3)

**Alapértelmezett modell — váltóbot** ([ADR 0055](docs/adr/0055-agent-role-protocol.md),
user-döntés 2026-07-29). Egy körön egyszerre EGY ágens ír; a munka átadásra
kerül, nem párhuzamosan zajlik:

```
Claude tervez → Codex implementál → Claude review-z → Codex javít → Claude merge-el
```

### 15.1 Claude — tervező és reviewer

- Elolvassa az SDD-t (§3) és megírja a **kör-briefet**
  (`docs/execution/08-round-brief.md` sablon): cél, scope, scope-on kívüli
  rész, **engedélyezett fájlok tételes listája**, acceptance criteria,
  kötelező gate-parancsok, kockázatok, implementációs sorrend.
- A brief a kör indítása ELŐTT commitolva van — az „engedélyezett fájlok"
  lista így a review-nál objektíven ellenőrizhető, nem a sessionnel elszálló
  prompt-megállapodás.
- A Codex-diff átvétele után **független review-jelentést** ír
  (`docs/execution/09-review-report.md` sablon → `docs/reviews/eXX-rYY-review.md`),
  BLOCKER / MAJOR / MINOR / NOTE osztályozással.
- **Review közben Claude nem ír production kódot.** A review kimenete
  jelentés. Kivétel: aktuális explicit user-utasítás, vagy ha a Codex-oldal
  nem elérhető — ezt a jelentésben rögzíteni kell.
- **A kör levezénylése is Claude-oldal** (user-szabály, 2026-07-29):
  CI-dispatch, a futás figyelése és a build-evidencia begyűjtése; PR-nyitás és
  a squash-merge az [ADR 0052](docs/adr/0052-ci-apk-automerge-session-per-round.md)
  zöld-kapus szabálya szerint (§13); `HANDOFF.md`, RTM, ADR-hivatkozások és a
  végrehajtási jelentés.
- **A gate-eket függetlenül újra kell futtatni** a merge-elt `main`-en. Az „X
  kész és zöld" állítást nem fogadjuk el bemondásra (az E01-R10-ben az
  architecture guard mind a négy szabályát valódi, kézzel bevitt sértéssel
  próbáltuk ki).

### 15.2 Codex — implementáló

- Csak a briefben **engedélyezett fájlokat** módosítja. Ha a kör
  elvégezhetetlennek tűnik a listán belül, MEGÁLL és jelent — nem tágítja a
  scope-ot magától.
- Implementál + tesztet ír, futtatja a formázást, analyzert és a célzott
  teszteket (§12, külön parancsokként).
- Kitölti a brief „Implementation handoff" szekcióját: fájlonkénti
  összefoglaló, futtatott parancsok TÉNYLEGES kimenettel, eltérések, nem
  futtatott ellenőrzések és okuk.
- A review után minden BLOCKER és MAJOR megállapítást javít; MINOR-t csak ha
  nem növeli érdemben a diffet. Kapcsolódó, de scope-on kívüli refaktort nem
  végez.
- Nem tervezi újra a jóváhagyott architektúrát külön ADR nélkül.
- **KÖTELEZŐ KÖR-JELZÉS** (user-szabály 2026-07-29). A Codex minden futást
  jelzéssel zár, a kimenetel MINDEGY:

  ```bash
  tools/codex-signal.sh done    "R11 implementálva, minden célzott teszt zöld"
  tools/codex-signal.sh stopped "a brief §5.8 ütközik az onboarding first-win úttal"
  tools/codex-signal.sh blocked "flutter analyze 3 javítási kísérlet után is piros"
  tools/codex-signal.sh progress "route katalógus kész, jönnek a tesztek"   # opcionális mérföldkő
  ```

  **Problémánál a jelzés az ELSŐ lépés, nem az utolsó.** Amint megállási pontot
  (§15.2 lista) vagy blokkolót azonosítasz: előbb `stopped`/`blocked` jelzés a
  rövid okkal, és csak UTÁNA a részletes jelentés/auditok. Az indoklás mérve:
  az E01-R11 első futásán a megállás helyes volt, de a jelzés csak három
  megerősítő audit után jött — az orchestrátor addig vakon várt. A cél, hogy
  a hívó **másodpercekben** értesüljön, ne a futás végén.
  A `progress` nem zárja le a kört; a `done`/`stopped`/`blocked` igen.

### 15.3 Indítás

A Codexet **soha ne közvetlen `codex exec`-kel** indítsd (és főleg ne
`nohup … &`-vel, mert akkor csak pollozni tudsz). A burkoló garantálja, hogy a
futás véget ér és nyomot hagy:

```bash
# 1) a kör — háttér-taskként, hogy a harness a kilépéskor értesítsen
tools/codex-round.sh /home/ubuntu/ss-codex-<kör> <prompt>.md /tmp/codex-<kör>.log

# 2) korai riasztás ugyanarra a körre, MÁSODIK háttér-taskként
tools/codex-watch.sh /home/ubuntu/ss-codex-<kör> /tmp/codex-<kör>.log
```

(A bwrap-sandbox ezen a boxon AppArmor miatt nem tud user namespace-t nyitni,
ezért a burkoló `-s danger-full-access`-t ad — az izolációt a külön
munkapéldány adja, nem a sandbox.)

**Három védelmi vonal, hogy soha ne várjunk vakon** (user-szabály 2026-07-29:
„ne várjunk rá fél napot"):

| Vonal | Ki adja | Mikor szól |
|---|---|---|
| Kör-jelzés | a Codex (`codex-signal.sh`, §15.2) | `done` / `stopped` / `blocked` — problémánál AZONNAL |
| Elakadás-őr | `codex-round.sh` + `codex-watch.sh` | ha a log `CODEX_STALL_MINUTES` (alap: 12) percig nem nő → kilövi és jelenti |
| Időkorlát | `codex-round.sh` | `CODEX_ROUND_TIMEOUT` (alap: 3600s) után kilövi és jelenti |

A jelzés a munkapéldány `.codex-round-status` fájlja (gitignore-olt,
`KEY=VALUE` sorok: `status`, `summary`, `branch`, `head`, `dirty_files`,
`signalled_at`). Az orchestrátor értesüléskor **először ezt olvassa el**, és
csak utána a logot. Ha `status=unknown`, a Codex jelzés nélkül halt meg —
a log az egyetlen bizonyíték, a jelentését ne fogadd el bemondásra.

A prompt tartalmazza a kötelező olvasnivalót (§3), a kör-brief elérési útját,
az engedélyezett fájlok listáját, a gate-parancsokat KÜLÖN hívásokként, a
CI-dispatchet, a megállási pontokat és a **kör-jelzés kötelezettségét** (§15.2).

### 15.4 Párhuzamos kétkörös futás — OPT-IN KIVÉTEL

Két agent EGYSZERRE két külön kört is vihet (bevált 2026-07-29: Codex = E01-R08,
Claude = E01-R09), de ez az ADR 0055 óta **nem alapértelmezés, csak explicit
user-döntésre** indítható — cserébe a kör elveszti a független reviewert.
Kötelező feltételek — ha bármelyik nem teljesül, a köröket sorban kell vinni:

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
8. **Pótolt review.** Mivel párhuzamos módban nincs szabad reviewer, a merge
   előtt kötelező a kézi diff-audit (§11/9) + a hiányzó független review
   rögzítése a PR-ben.

### 15.5 Egy kör két félre osztva

Nemcsak két KÜLÖN kör futhat párhuzamosan: egy kör is szétvágható két
fájlszinten diszjunkt félre (bevált 2026-07-29, E01-R10 — A = zenei domain +
feature public API, B = WAV codec + architecture guard). A §15.4 nyolc
feltétele változatlanul kötelező, plusz:

9. **A függő fél megy másodikként.** Ha a B-rész eredménye függ az A-résztől
   (pl. az architecture guard allowlistje csak az A-rész import-migrációja
   után végleges), a B-rész az A merge-e UTÁN rebase-el `main`-re,
   ÚJRAGENERÁLJA a származtatott tartalmat, és csak azután futtat CI-t.

### 15.6 Két implementer motor — melyik kört ki viszi

Az implementer szerepet 2026-07-30 óta két motor tölti be
([ADR 0069](docs/adr/0069-two-engine-implementer-pool.md)). A lánc, a
brief-szerződés, a kör-jelzés (§15.2) és a gate-ek változatlanok — csak az
dől el körönként, melyik motor implementál:

| Kör jellege | Motor | Indítás |
|---|---|---|
| Jól specifikált domain/model/teszt kör, adapter, katalógus, i18n, mechanikus refaktor, migráció, boilerplate-tömeg | **MiniMax M3** | `tools/mm-round.sh <munkapéldány> <prompt>.md /tmp/mm-<kör>.log` + MÁSODIK háttér-taskként `tools/mm-watch.sh <munkapéldány> /tmp/mm-<kör>.log` |
| DSP-hangolás, baseline-érzékeny scorer/matcher, teljesítmény-kritikus út, felderítő vagy kétértelmű feladat | **Codex** | `tools/codex-round.sh …` (§15.3) |
| Bizonytalan besorolás | **Codex** | a drágább motor a biztonságos alapértelmezés |

A szűkös erőforrás a Codex heti kvótája, nem a MiniMax tokenje: volumen- és
ismétlődő munkából inkább többet adunk M3-nak, semmint hogy Codex-kvótát
égessünk.

**MiniMax-körnél a briefbe KÖTELEZŐ** (mért hibák ellenszere, ADR 0069):

1. a gate-parancsok szó szerint — „run each as a SEPARATE command, EXACTLY as
   written" + „narrowing any gate command to only the touched files is a round
   failure" (mérten hajlamos a gate-et a nyúlt fájlokra szűkíteni);
2. explicit STOP-klauzula — „If any requirement conflicts with the allowed-files
   list or with an existing test, STOP, send the `stopped` signal, and report."
   (enélkül némán megkerüli a zárolt fájlt, és feature-ként jelenti);
3. a kör-jelzés kötelezettsége (§15.2) szó szerint a prompt elején.

**Review-oldalon:** a gate-et a reviewer maga futtatja újra (a bemásolt kimenet
nem evidencia), `git diff --stat` scope-audit az engedélyezett listával
összevetve, és a PR törzse rögzíti, melyik motor implementálta a kört. A
git-notes bufferbe is bekerül: `engine=minimax-m3` vagy `engine=codex`.

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
